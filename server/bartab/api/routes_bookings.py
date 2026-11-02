from datetime import UTC, datetime

from fastapi import APIRouter, Depends
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from bartab.api.deps import get_clock, get_session, require_device
from bartab.api.schemas import BookingBatchRequest, BookingBatchResponse, BookingIn, BookingResult
from bartab.domain.clock import Clock
from bartab.persistence.models import Booking, Drink, Person
from bartab.persistence.repos import add_booking, get_booking

router = APIRouter()

MIN_QUANTITY = 1
MAX_QUANTITY = 999


def _validation_error(item: BookingIn, session: Session) -> str | None:
    if not MIN_QUANTITY <= item.quantity <= MAX_QUANTITY:
        return "invalid_quantity"
    if item.unit_price_cents < 0:
        return "invalid_price"
    if item.booked_at.tzinfo is None or item.booked_at.utcoffset() is None:
        return "invalid_booked_at"
    if session.get(Person, item.person_id) is None:
        return "unknown_person"
    if session.get(Drink, item.drink_id) is None:
        return "unknown_drink"
    return None


def _same_content(stored: Booking, item: BookingIn, booked_at: datetime | None) -> bool:
    return (
        stored.person_id == item.person_id
        and stored.drink_id == item.drink_id
        and stored.quantity == item.quantity
        and stored.unit_price_cents == item.unit_price_cents
        and stored.booked_at == booked_at
    )


def _classify_existing(
    stored: Booking, item: BookingIn, booked_at: datetime | None
) -> BookingResult:
    status = "duplicate" if _same_content(stored, item, booked_at) else "conflict"
    return BookingResult(id=str(item.id), status=status)


def _process(item: BookingIn, session: Session, device_id: str, clock: Clock) -> BookingResult:
    booking_id = str(item.id)
    # An existing id is always duplicate/conflict, whatever the new payload looks like,
    # so a client never mistakes a stored booking for a rejected one.
    naive = item.booked_at.tzinfo is None or item.booked_at.utcoffset() is None
    booked_at = None if naive else item.booked_at.astimezone(UTC)
    stored = get_booking(session, booking_id)
    if stored is not None:
        return _classify_existing(stored, item, booked_at)
    reason = _validation_error(item, session)
    if reason is not None:
        return BookingResult(id=booking_id, status="rejected", reason=reason)
    assert booked_at is not None
    try:
        # SAVEPOINT: a failing insert rolls back only this item.
        with session.begin_nested():
            add_booking(
                session,
                id=booking_id,
                person_id=item.person_id,
                drink_id=item.drink_id,
                quantity=item.quantity,
                unit_price_cents=item.unit_price_cents,
                booked_at=booked_at,
                device_id=device_id,
                clock=clock,
            )
    except IntegrityError:
        # A concurrent request inserted the same id first; classify by what is stored.
        session.expire_all()
        stored = get_booking(session, booking_id)
        if stored is None:
            raise
        return _classify_existing(stored, item, booked_at)
    return BookingResult(id=booking_id, status="accepted")


@router.post("/bookings", response_model=BookingBatchResponse)
def post_bookings(
    body: BookingBatchRequest,
    device_id: str = Depends(require_device),
    session: Session = Depends(get_session),
    clock: Clock = Depends(get_clock),
) -> BookingBatchResponse:
    results = []
    for item in body.bookings:
        results.append(_process(item, session, device_id, clock))
    return BookingBatchResponse(results=results)
