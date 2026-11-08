from sqlalchemy import select
from sqlalchemy.orm import Session

from bartab.domain.clock import Clock
from bartab.persistence.models import Drink, Period, StockEntry
from bartab.persistence.repos import CancelOutcome, ensure_open_period

MAX_DELIVERY_UNITS = 99_999


class DeliveryConflict(Exception):
    """The same id was sent with a different drink or quantity."""


class UnknownDrink(Exception):
    pass


class InvalidQuantity(Exception):
    pass


def add_deliveries(
    session: Session, clock: Clock, items: list[tuple[str, str, int]]
) -> list[StockEntry]:
    """Stores deliveries in the open period, all or nothing.

    Items whose id already exists with identical content are returned as they are.
    """
    # validate everything before the first write
    pending: dict[str, tuple[str, int]] = {}
    for entry_id, drink_id, quantity in items:
        if not 1 <= quantity <= MAX_DELIVERY_UNITS:
            raise InvalidQuantity
        if session.get(Drink, drink_id) is None:
            raise UnknownDrink
        existing = session.get(StockEntry, entry_id)
        if existing is not None:
            if (existing.kind, existing.drink_id, existing.quantity) != (
                "delivery",
                drink_id,
                quantity,
            ):
                raise DeliveryConflict
        elif pending.setdefault(entry_id, (drink_id, quantity)) != (drink_id, quantity):
            raise DeliveryConflict

    created: dict[str, StockEntry] = {}
    if pending:
        period = ensure_open_period(session, clock)
        now = clock.now()
        for entry_id, (drink_id, quantity) in pending.items():
            created[entry_id] = StockEntry(
                id=entry_id,
                period_id=period.id,
                drink_id=drink_id,
                kind="delivery",
                quantity=quantity,
                created_at=now,
                updated_at=now,
            )
        session.add_all(created.values())
        session.flush()
    return [created.get(entry_id) or session.get(StockEntry, entry_id) for entry_id, _, _ in items]


def open_period_deliveries(session: Session) -> list[StockEntry]:
    """Deliveries of the open period, cancelled ones included, newest first."""
    query = (
        select(StockEntry)
        .join(Period, Period.id == StockEntry.period_id)
        .where(Period.closed_at.is_(None), StockEntry.kind == "delivery")
        .order_by(StockEntry.created_at.desc(), StockEntry.id.desc())
    )
    return list(session.scalars(query))


def cancel_delivery(
    session: Session, entry_id: str, device_id: str, clock: Clock
) -> tuple[CancelOutcome, StockEntry | None]:
    entry = session.get(StockEntry, entry_id)
    if entry is None or entry.kind != "delivery":
        return CancelOutcome.NOT_FOUND, None
    period = session.get(Period, entry.period_id)
    if period is None or period.closed_at is not None:
        return CancelOutcome.PERIOD_CLOSED, entry
    if entry.cancelled_at is not None:
        return CancelOutcome.ALREADY_CANCELLED, entry
    now = clock.now()
    entry.cancelled_at = now
    entry.cancelled_by_device_id = device_id
    entry.updated_at = now
    session.flush()
    return CancelOutcome.CANCELLED, entry
