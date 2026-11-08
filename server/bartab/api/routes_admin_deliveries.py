from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from bartab.api.deps import get_clock, get_session, require_admin
from bartab.api.schemas import (
    DeliveriesResponse,
    DeliveryBatchRequest,
    DeliveryOut,
    ErrorResponse,
)
from bartab.domain.clock import Clock
from bartab.persistence import deliveries
from bartab.persistence.models import StockEntry
from bartab.persistence.repos import CancelOutcome

router = APIRouter()


def _utc(value: datetime) -> datetime:
    # SQLite returns naive datetimes; stored values are UTC
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value


def _to_out(entry: StockEntry) -> DeliveryOut:
    return DeliveryOut(
        id=entry.id,
        drink_id=entry.drink_id,
        quantity=entry.quantity,
        created_at=_utc(entry.created_at),
        cancelled_at=None if entry.cancelled_at is None else _utc(entry.cancelled_at),
    )


@router.post(
    "/admin/deliveries",
    name="createDeliveries",
    status_code=201,
    response_model=DeliveriesResponse,
    responses={
        401: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
    },
)
def create_deliveries(
    body: DeliveryBatchRequest,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> DeliveriesResponse:
    items = [(str(item.id), item.drink_id, item.quantity) for item in body.deliveries]
    try:
        entries = deliveries.add_deliveries(session, clock, items)
    except deliveries.DeliveryConflict:
        raise HTTPException(status_code=409, detail="delivery_conflict") from None
    except deliveries.UnknownDrink:
        raise HTTPException(status_code=422, detail="unknown_reference") from None
    except deliveries.InvalidQuantity:
        raise HTTPException(status_code=422, detail="invalid_quantity") from None
    return DeliveriesResponse(deliveries=[_to_out(entry) for entry in entries])


@router.get(
    "/admin/deliveries",
    name="listDeliveries",
    response_model=DeliveriesResponse,
    responses={401: {"model": ErrorResponse}},
)
def list_deliveries(
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> DeliveriesResponse:
    rows = deliveries.open_period_deliveries(session)
    return DeliveriesResponse(deliveries=[_to_out(row) for row in rows])


@router.post(
    "/admin/deliveries/{delivery_id}/cancel",
    name="cancelDelivery",
    response_model=DeliveryOut,
    responses={
        401: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
)
def cancel_admin_delivery(
    delivery_id: str,
    device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> DeliveryOut:
    outcome, entry = deliveries.cancel_delivery(session, delivery_id, device_id, clock)
    if outcome is CancelOutcome.NOT_FOUND:
        raise HTTPException(status_code=404, detail="not_found")
    if outcome is CancelOutcome.PERIOD_CLOSED:
        raise HTTPException(status_code=409, detail="period_closed")
    if outcome is CancelOutcome.ALREADY_CANCELLED:
        raise HTTPException(status_code=409, detail="already_cancelled")
    assert entry is not None
    return _to_out(entry)
