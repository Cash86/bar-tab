from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from bartab.api.deps import get_clock, get_session, require_admin
from bartab.api.schemas import AdminBookingOut, AdminBookingsResponse, ErrorResponse
from bartab.domain.clock import Clock
from bartab.persistence.models import Booking
from bartab.persistence.repos import CancelOutcome, cancel_booking, open_period_bookings

router = APIRouter()


def _utc(value: datetime) -> datetime:
    # SQLite returns naive datetimes; stored values are UTC
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value


def _to_out(booking: Booking) -> AdminBookingOut:
    return AdminBookingOut(
        id=booking.id,
        person_id=booking.person_id,
        drink_id=booking.drink_id,
        quantity=booking.quantity,
        unit_price_cents=booking.unit_price_cents,
        booked_at=_utc(booking.booked_at),
        is_late=booking.is_late,
        cancelled_at=None if booking.cancelled_at is None else _utc(booking.cancelled_at),
    )


@router.get(
    "/admin/bookings",
    name="listAdminBookings",
    response_model=AdminBookingsResponse,
    responses={401: {"model": ErrorResponse}},
)
def list_admin_bookings(
    person_id: str | None = None,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> AdminBookingsResponse:
    rows = open_period_bookings(session, person_id)
    return AdminBookingsResponse(bookings=[_to_out(row) for row in rows])


@router.post(
    "/admin/bookings/{booking_id}/cancel",
    name="cancelBooking",
    response_model=AdminBookingOut,
    responses={
        401: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
    },
)
def cancel_admin_booking(
    booking_id: str,
    device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> AdminBookingOut:
    outcome, booking = cancel_booking(session, booking_id, device_id, clock)
    if outcome is CancelOutcome.NOT_FOUND:
        raise HTTPException(status_code=404, detail="booking_not_found")
    if outcome is CancelOutcome.PERIOD_CLOSED:
        raise HTTPException(status_code=409, detail="period_closed")
    if outcome is CancelOutcome.ALREADY_CANCELLED:
        raise HTTPException(status_code=409, detail="already_cancelled")
    assert booking is not None
    return _to_out(booking)
