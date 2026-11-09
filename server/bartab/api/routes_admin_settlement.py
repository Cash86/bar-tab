"""Admin routes for the inventory, the settlement and its mail."""

import logging
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from bartab.api.deps import get_clock, get_session, get_settings, require_admin
from bartab.api.schemas import (
    CloseRequest,
    CountIn,
    CountsRequest,
    DrinkLineOut,
    ErrorResponse,
    GroupLineOut,
    ResendOut,
    SettlementCloseOut,
    SettlementReviewOut,
    StockDrinkOut,
    StockResponse,
)
from bartab.config import Settings
from bartab.domain.clock import Clock
from bartab.domain.settlement import Settlement
from bartab.mail import Mailer, MailError, MailNotConfigured
from bartab.persistence import settlement
from bartab.persistence.models import MailStatus
from bartab.reports.settlement_pdf import render_settlement_pdf
from bartab.reports.texts import settlement_mail

router = APIRouter()
logger = logging.getLogger(__name__)

MAX_COUNT = 99999

COUNT_ERRORS = {401: {"model": ErrorResponse}, 422: {"model": ErrorResponse}}


def get_mailer(request: Request) -> Mailer:
    return request.app.state.mailer


def _counts(items: list[CountIn]) -> dict[str, int]:
    counts = {item.drink_id: item.quantity for item in items}
    if len(counts) != len(items) or any(not 0 <= q <= MAX_COUNT for q in counts.values()):
        raise HTTPException(status_code=422, detail="invalid_quantity")
    return counts


def _send(
    mailer: Mailer, recipients: list[str], s: Settlement, tz: str
) -> tuple[MailStatus, str | None]:
    """Renders and mails the settlement; runs without touching the database."""
    if not recipients:
        return "skipped", None
    filename = f"abrechnung-{s.ended_at.astimezone(ZoneInfo(tz)):%Y-%m-%d}.pdf"
    try:
        subject, body = settlement_mail(s, tz)
        mailer.send(recipients, subject, body, (filename, render_settlement_pdf(s, tz)))
    except MailNotConfigured:
        return "skipped", None
    except MailError as error:
        return "failed", str(error)
    except Exception as error:  # the period is closed already; report instead of a 500
        logger.exception("rendering or sending the settlement failed")
        return "failed", f"render failed: {type(error).__name__}"
    return "sent", None


async def _mail(
    session: Session, clock: Clock, mailer: Mailer, tz: str, record_id: str, s: Settlement
) -> MailStatus:
    """Commits what the session holds, mails outside the write transaction, records the result."""
    recipients = await run_in_threadpool(settlement.get_recipients, session)
    await run_in_threadpool(session.commit)
    status, error = await run_in_threadpool(_send, mailer, recipients, s, tz)
    await run_in_threadpool(settlement.set_mail_status, session, record_id, status, error, clock)
    return status


@router.get(
    "/admin/stock",
    name="getStock",
    response_model=StockResponse,
    responses={401: {"model": ErrorResponse}},
)
def get_stock(
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
) -> StockResponse:
    allowed, drinks = settlement.stock_overview(session)
    return StockResponse(
        opening_count_allowed=allowed,
        drinks=[
            StockDrinkOut(
                drink_id=d.id,
                name=d.name,
                group_id=d.group_id,
                group_name=d.group_name,
                crate_size=d.crate_size,
                expected=expected,
            )
            for d, expected in drinks
        ],
    )


@router.post(
    "/admin/settlement/review",
    name="reviewSettlement",
    response_model=SettlementReviewOut,
    responses=COUNT_ERRORS,
)
def review_settlement(
    body: CountsRequest,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> SettlementReviewOut:
    counts = _counts(body.counts)
    try:
        s = settlement.review(session, clock, counts)
    except settlement.MissingCount:
        raise HTTPException(status_code=422, detail="missing_count") from None
    except settlement.UnknownDrink:
        raise HTTPException(status_code=422, detail="unknown_reference") from None
    return SettlementReviewOut(
        token=settlement.review_token(s),
        valuation_tier_name=s.valuation_tier_name,
        drinks=[DrinkLineOut.model_validate(line, from_attributes=True) for line in s.drinks],
        groups=[
            GroupLineOut.model_validate(line, from_attributes=True)
            for line in s.group_totals.values()
        ],
        persons_total_cents=s.persons_total_cents,
        hidden_total_cents=s.hidden_total_cents,
        grand_total_cents=s.grand_total_cents,
        shrinkage_total_cents=s.shrinkage_total_cents,
    )


@router.post(
    "/admin/settlement/close",
    name="closeSettlement",
    status_code=201,
    response_model=SettlementCloseOut,
    responses={
        200: {"model": SettlementCloseOut, "description": "Replay of an earlier close"},
        401: {"model": ErrorResponse},
        409: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
    },
)
async def close_settlement(
    body: CloseRequest,
    response: Response,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
    settings: Settings = Depends(get_settings),
    mailer: Mailer = Depends(get_mailer),
) -> SettlementCloseOut:
    counts = _counts(body.counts)
    try:
        record, created = await run_in_threadpool(
            settlement.close, session, clock, body.token, counts
        )
    except settlement.StaleReview:
        raise HTTPException(status_code=409, detail="stale_review") from None
    s = settlement.snapshot_of(record)
    if created:
        status = await _mail(session, clock, mailer, settings.tz, record.id, s)
    else:
        response.status_code = 200
        status = record.mail_status
    return SettlementCloseOut(period_id=record.period_id, closed_at=s.ended_at, mail_status=status)


@router.post(
    "/admin/opening-count",
    name="recordOpeningCount",
    status_code=204,
    responses={**COUNT_ERRORS, 409: {"model": ErrorResponse}},
)
def record_opening_count(
    body: CountsRequest,
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> Response:
    counts = _counts(body.counts)
    try:
        settlement.record_opening_count(session, clock, counts)
    except settlement.AlreadySettled:
        raise HTTPException(status_code=409, detail="already_settled") from None
    except settlement.MissingCount:
        raise HTTPException(status_code=422, detail="missing_count") from None
    except settlement.UnknownDrink:
        raise HTTPException(status_code=422, detail="unknown_reference") from None
    return Response(status_code=204)


@router.post(
    "/admin/settlement/resend",
    name="resendSettlement",
    response_model=ResendOut,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def resend_settlement(
    _device_id: str = Depends(require_admin),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
    settings: Settings = Depends(get_settings),
    mailer: Mailer = Depends(get_mailer),
) -> ResendOut:
    record = await run_in_threadpool(settlement.last_settlement, session)
    if record is None:
        raise HTTPException(status_code=404, detail="no_settlement")
    s = settlement.snapshot_of(record)
    status = await _mail(session, clock, mailer, settings.tz, record.id, s)
    return ResendOut(mail_status=status)
