"""Admin routes for the settlement settings: mail recipients and valuation tier."""

import re

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from bartab.api.deps import get_session, require_admin
from bartab.api.schemas import (
    ErrorResponse,
    RecipientsWrite,
    SettingsResponse,
    SettlementCloseOut,
    ValuationTierWrite,
)
from bartab.persistence import settlement

router = APIRouter()

EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


@router.get(
    "/admin/settings",
    name="getSettings",
    response_model=SettingsResponse,
    responses={401: {"model": ErrorResponse}},
)
def read_settings(
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> SettingsResponse:
    record = settlement.last_settlement(session)
    last = None
    if record is not None:
        last = SettlementCloseOut(
            period_id=record.period_id,
            closed_at=settlement.snapshot_of(record).ended_at,
            mail_status=record.mail_status,
        )
    return SettingsResponse(
        recipients=settlement.get_recipients(session),
        valuation_tier_id=settlement.get_valuation_tier_id(session),
        effective_valuation_tier_id=settlement.effective_valuation_tier_id(session),
        last_settlement=last,
    )


@router.put(
    "/admin/settings/recipients",
    name="setRecipients",
    status_code=204,
    responses={401: {"model": ErrorResponse}, 422: {"model": ErrorResponse}},
)
def set_recipients(
    body: RecipientsWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> Response:
    if not all(EMAIL.match(address) for address in body.recipients):
        raise HTTPException(status_code=422, detail="invalid_email")
    settlement.set_recipients(session, list(dict.fromkeys(body.recipients)))
    return Response(status_code=204)


@router.put(
    "/admin/settings/valuation-tier",
    name="setValuationTier",
    status_code=204,
    responses={401: {"model": ErrorResponse}, 422: {"model": ErrorResponse}},
)
def set_valuation_tier(
    body: ValuationTierWrite,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> Response:
    try:
        settlement.set_valuation_tier_id(session, body.tier_id)
    except settlement.UnknownTier:
        raise HTTPException(status_code=422, detail="unknown_reference") from None
    return Response(status_code=204)
