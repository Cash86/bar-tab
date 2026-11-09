"""Closing a period with a frozen figures snapshot, opening counts and settlement settings."""

import json
from dataclasses import dataclass, replace
from datetime import datetime
from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from bartab.domain.clock import Clock
from bartab.domain.settlement import (
    BookingIn,
    DrinkIn,
    PersonIn,
    Settlement,
    StockIn,
    TierIn,
    compute_settlement,
    drinks_to_count,
    effective_valuation_tier,
    expected_stock,
    figures_token,
    settlement_from_json,
    settlement_to_json,
)
from bartab.persistence.models import (
    Booking,
    Drink,
    DrinkGroup,
    DrinkPrice,
    MailStatus,
    Period,
    Person,
    PriceTier,
    SettlementRecord,
    StockEntry,
)
from bartab.persistence.repos import ensure_open_period, get_setting, set_setting

SNAPSHOT_VERSION = 1

MAIL_RECIPIENTS = "mail_recipients"  # JSON list of addresses
VALUATION_TIER_ID = "valuation_tier_id"
MONTHLY_REPORT_SENT_MONTH = "monthly_report_sent_month"
MONTHLY_REPORT_LAST_ATTEMPT_AT = "monthly_report_last_attempt_at"  # ISO UTC


class StaleReview(Exception):
    """The figures changed since the review the token was issued for."""


class AlreadySettled(Exception):
    """An opening count is only possible before the first settlement."""


class UnknownDrink(Exception):
    """A count for a drink that is not on the list of drinks to count."""


class MissingCount(Exception):
    """A drink on the list of drinks to count has no count."""


class UnknownTier(Exception):
    """The chosen valuation tier does not exist."""


@dataclass(frozen=True)
class _Inputs:
    persons: list[PersonIn]
    tiers: list[TierIn]
    drinks: list[DrinkIn]  # group sort order, then drink sort order
    bookings: list[BookingIn]
    stocks: list[StockIn]
    prices: dict[tuple[str, str], int]  # (tier_id, drink_id) -> cents

    def to_count(self) -> list[DrinkIn]:
        return drinks_to_count(self.drinks, self.stocks, self.bookings)


def _open_period(session: Session) -> Period | None:
    return session.scalars(select(Period).where(Period.closed_at.is_(None))).first()


def _require_open_period(session: Session) -> Period:
    period = _open_period(session)
    if period is None:
        raise LookupError("no open period")
    return period


def _has_closed_period(session: Session) -> bool:
    return session.scalar(select(func.count(Period.id)).where(Period.closed_at.is_not(None))) > 0


def _load(session: Session, period_id: str | None) -> _Inputs:
    """Everything the domain needs, deactivated and hidden master data included."""
    persons = [
        PersonIn(p.id, p.name, p.price_tier_id, p.is_hidden, p.is_collective)
        for p in session.scalars(select(Person).order_by(Person.name, Person.id))
    ]
    tiers = [
        TierIn(t.id, t.name, t.sort_order, True)
        for t in session.scalars(select(PriceTier).order_by(PriceTier.sort_order, PriceTier.id))
    ]
    drinks = [
        DrinkIn(d.id, d.name, g.id, g.name, d.crate_size, d.is_active)
        for d, g in session.execute(
            select(Drink, DrinkGroup)
            .join(DrinkGroup, DrinkGroup.id == Drink.group_id)
            .order_by(
                DrinkGroup.sort_order,
                DrinkGroup.name,
                DrinkGroup.id,
                Drink.sort_order,
                Drink.name,
                Drink.id,
            )
        )
    ]
    prices = {
        (p.price_tier_id, p.drink_id): p.price_cents for p in session.scalars(select(DrinkPrice))
    }
    bookings: list[BookingIn] = []
    stocks: list[StockIn] = []
    if period_id is not None:
        bookings = [
            BookingIn(
                b.person_id,
                b.drink_id,
                b.quantity,
                b.unit_price_cents,
                b.booked_at,
                b.cancelled_at,
                b.is_late,
            )
            for b in session.scalars(
                select(Booking)
                .where(Booking.period_id == period_id)
                .order_by(Booking.booked_at, Booking.id)
            )
        ]
        stocks = [
            StockIn(e.drink_id, e.kind, e.quantity, e.created_at, e.cancelled_at)
            for e in session.scalars(
                select(StockEntry)
                .where(
                    StockEntry.period_id == period_id,
                    StockEntry.kind.in_(("opening", "delivery")),
                )
                .order_by(StockEntry.created_at, StockEntry.id)
            )
        ]
    return _Inputs(persons, tiers, drinks, bookings, stocks, prices)


def _check_counts(to_count: list[DrinkIn], counts: dict[str, int]) -> None:
    listed = {d.id for d in to_count}
    if set(counts) - listed:
        raise UnknownDrink
    if listed - set(counts):
        raise MissingCount


def _compute(
    session: Session, period: Period, counts: dict[str, int], ended_at: datetime
) -> Settlement:
    inputs = _load(session, period.id)
    _check_counts(inputs.to_count(), counts)
    return compute_settlement(
        period_id=period.id,
        started_at=period.started_at,
        ended_at=ended_at,
        persons=inputs.persons,
        tiers=inputs.tiers,
        drinks=inputs.drinks,
        bookings=inputs.bookings,
        stocks=inputs.stocks,
        prices=inputs.prices,
        counts=counts,
        valuation_tier=effective_valuation_tier(inputs.tiers, get_valuation_tier_id(session)),
    )


def review_token(s: Settlement) -> str:
    """Token over the figures of a review.

    The end of the period is the time the figures were computed, so it is left out: a review and
    the close that follows it a few minutes later yield the same token when nothing changed.
    """
    return figures_token(replace(s, ended_at=s.started_at))


def stock_overview(session: Session) -> tuple[bool, list[tuple[DrinkIn, int]]]:
    """Whether an opening count is allowed, and the drinks to count with their expected stock."""
    period = _open_period(session)
    inputs = _load(session, None if period is None else period.id)
    expected = expected_stock(inputs.drinks, inputs.stocks, inputs.bookings)
    drinks = [(d, expected[d.id]) for d in inputs.to_count()]
    return not _has_closed_period(session), drinks


def review(session: Session, clock: Clock, counts: dict[str, int]) -> Settlement:
    """Settlement figures of the open period for the given counts; stores nothing."""
    return _compute(session, _require_open_period(session), counts, clock.now())


def _stock_entries(
    period_id: str, kind: str, counts: dict[str, int], now: datetime
) -> list[StockEntry]:
    return [
        StockEntry(
            id=str(uuid4()),
            period_id=period_id,
            drink_id=drink_id,
            kind=kind,
            quantity=quantity,
            created_at=now,
            updated_at=now,
        )
        for drink_id, quantity in counts.items()
    ]


def close(
    session: Session, clock: Clock, token: str, counts: dict[str, int]
) -> tuple[SettlementRecord, bool]:
    """Closes the open period with the reviewed counts and opens the next one.

    Returns the snapshot row and whether it was created now; a retry with the token of an
    earlier close returns that close's row.
    """
    existing = session.scalars(
        select(SettlementRecord).where(SettlementRecord.token == token)
    ).first()
    if existing is not None:
        return existing, False
    period = ensure_open_period(session, clock)
    now = clock.now()
    try:
        settlement = _compute(session, period, counts, now)
    except (MissingCount, UnknownDrink) as error:
        # the list of drinks to count changed since the review
        raise StaleReview from error
    if review_token(settlement) != token:
        raise StaleReview

    session.add_all(_stock_entries(period.id, "count", counts, now))
    period.closed_at = now
    period.updated_at = now
    session.flush()  # only one period may be open
    following = Period(id=str(uuid4()), started_at=now, created_at=now, updated_at=now)
    session.add(following)
    session.flush()
    session.add_all(_stock_entries(following.id, "opening", counts, now))
    record = SettlementRecord(
        id=str(uuid4()),
        period_id=period.id,
        token=token,
        figures_json=json.dumps(
            {"version": SNAPSHOT_VERSION, "settlement": settlement_to_json(settlement)}
        ),
        mail_status="pending",
        mail_error=None,
        mailed_at=None,
        created_at=now,
        updated_at=now,
    )
    session.add(record)
    session.flush()
    return record, True


def snapshot_of(record: SettlementRecord) -> Settlement:
    data = json.loads(record.figures_json)
    if data.get("version") != SNAPSHOT_VERSION:
        raise ValueError(f"unsupported snapshot version: {data.get('version')}")
    return settlement_from_json(data["settlement"])


def record_opening_count(session: Session, clock: Clock, counts: dict[str, int]) -> None:
    """Stores the counts as the opening stock of the open period, replacing an earlier one."""
    if _has_closed_period(session):
        raise AlreadySettled
    period = ensure_open_period(session, clock)
    _check_counts(_load(session, period.id).to_count(), counts)
    now = clock.now()
    previous = session.scalars(
        select(StockEntry).where(
            StockEntry.period_id == period.id,
            StockEntry.kind == "opening",
            StockEntry.cancelled_at.is_(None),
        )
    )
    for entry in previous:
        entry.cancelled_at = now
        entry.updated_at = now
    session.add_all(_stock_entries(period.id, "opening", counts, now))
    session.flush()


def last_inventory_at(session: Session) -> datetime:
    period = _require_open_period(session)
    if not _has_closed_period(session):
        latest = session.scalar(
            select(func.max(StockEntry.created_at)).where(
                StockEntry.period_id == period.id,
                StockEntry.kind == "opening",
                StockEntry.cancelled_at.is_(None),
            )
        )
        if latest is not None:
            return latest
    return period.started_at


def last_settlement(session: Session) -> SettlementRecord | None:
    return session.scalars(
        select(SettlementRecord)
        .join(Period, Period.id == SettlementRecord.period_id)
        .order_by(Period.closed_at.desc())
    ).first()


def set_mail_status(
    session: Session, row_id: str, status: MailStatus, error: str | None, clock: Clock
) -> None:
    record = session.get(SettlementRecord, row_id)
    if record is None:
        raise LookupError(f"no settlement {row_id}")
    now = clock.now()
    record.mail_status = status
    record.mail_error = error
    if status == "sent":
        record.mailed_at = now
    record.updated_at = now
    session.flush()


def get_recipients(session: Session) -> list[str]:
    value = get_setting(session, MAIL_RECIPIENTS)
    return [] if value is None else json.loads(value)


def set_recipients(session: Session, recipients: list[str]) -> None:
    set_setting(session, MAIL_RECIPIENTS, json.dumps(recipients))


def get_valuation_tier_id(session: Session) -> str | None:
    return get_setting(session, VALUATION_TIER_ID)


def set_valuation_tier_id(session: Session, tier_id: str) -> None:
    if session.get(PriceTier, tier_id) is None:
        raise UnknownTier
    set_setting(session, VALUATION_TIER_ID, tier_id)


def effective_valuation_tier_id(session: Session) -> str:
    """The tier the next settlement is valued with (the chosen one, else the first tier)."""
    tiers = [TierIn(t.id, t.name, t.sort_order, True) for t in session.scalars(select(PriceTier))]
    return effective_valuation_tier(tiers, get_valuation_tier_id(session)).id
