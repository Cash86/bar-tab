from dataclasses import dataclass
from datetime import datetime
from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from bartab.domain.clock import Clock
from bartab.persistence.models import (
    AppSetting,
    Booking,
    Drink,
    DrinkGroup,
    DrinkPrice,
    Period,
    Person,
    PriceTier,
)


@dataclass(frozen=True)
class PriceTierItem:
    id: str
    name: str
    sort_order: int


@dataclass(frozen=True)
class PersonItem:
    id: str
    name: str
    price_tier_id: str
    is_hidden: bool
    is_collective: bool
    is_active: bool


@dataclass(frozen=True)
class GroupItem:
    id: str
    name: str
    sort_order: int
    color: str


@dataclass(frozen=True)
class DrinkItem:
    id: str
    name: str
    group_id: str
    crate_size: int
    sort_order: int
    is_hidden: bool
    is_active: bool
    prices: dict[str, int]  # price_tier_id -> cents


@dataclass(frozen=True)
class Catalog:
    price_tiers: list[PriceTierItem]
    persons: list[PersonItem]
    groups: list[GroupItem]
    drinks: list[DrinkItem]


def _open_period(session: Session) -> Period | None:
    return session.scalars(select(Period).where(Period.closed_at.is_(None))).first()


def ensure_open_period(session: Session, clock: Clock) -> Period:
    period = _open_period(session)
    if period is None:
        now = clock.now()
        period = Period(id=str(uuid4()), started_at=now, created_at=now, updated_at=now)
        session.add(period)
        session.flush()
    return period


def get_catalog(session: Session) -> Catalog:
    tiers = session.scalars(
        select(PriceTier).order_by(PriceTier.sort_order, PriceTier.name, PriceTier.id)
    )
    persons = session.scalars(select(Person).order_by(Person.name, Person.id))
    groups = session.scalars(
        select(DrinkGroup).order_by(DrinkGroup.sort_order, DrinkGroup.name, DrinkGroup.id)
    )
    drinks = session.scalars(select(Drink).order_by(Drink.sort_order, Drink.name, Drink.id))
    prices: dict[str, dict[str, int]] = {}
    for price in session.scalars(select(DrinkPrice)):
        prices.setdefault(price.drink_id, {})[price.price_tier_id] = price.price_cents
    return Catalog(
        price_tiers=[PriceTierItem(t.id, t.name, t.sort_order) for t in tiers],
        persons=[
            PersonItem(p.id, p.name, p.price_tier_id, p.is_hidden, p.is_collective, p.is_active)
            for p in persons
        ],
        groups=[GroupItem(g.id, g.name, g.sort_order, g.color) for g in groups],
        drinks=[
            DrinkItem(
                d.id,
                d.name,
                d.group_id,
                d.crate_size,
                d.sort_order,
                d.is_hidden,
                d.is_active,
                prices.get(d.id, {}),
            )
            for d in drinks
        ],
    )


def get_booking(session: Session, booking_id: str) -> Booking | None:
    return session.get(Booking, booking_id)


def add_booking(
    session: Session,
    *,
    id: str,
    person_id: str,
    drink_id: str,
    quantity: int,
    unit_price_cents: int,
    booked_at: datetime,
    device_id: str,
    clock: Clock,
) -> Booking:
    period = ensure_open_period(session, clock)
    now = clock.now()
    booking = Booking(
        id=id,
        period_id=period.id,
        person_id=person_id,
        drink_id=drink_id,
        quantity=quantity,
        unit_price_cents=unit_price_cents,
        booked_at=booked_at,
        received_at=now,
        device_id=device_id,
        is_late=booked_at < period.started_at,
        created_at=now,
        updated_at=now,
    )
    session.add(booking)
    session.flush()
    return booking


def tabs_for_open_period(session: Session) -> dict[str, int]:
    rows = session.execute(
        select(Booking.person_id, func.sum(Booking.quantity * Booking.unit_price_cents))
        .join(Period, Period.id == Booking.period_id)
        .where(Period.closed_at.is_(None))
        .group_by(Booking.person_id)
    )
    return {person_id: int(total) for person_id, total in rows}


def get_setting(session: Session, key: str) -> str | None:
    setting = session.get(AppSetting, key)
    return setting.value if setting else None


def set_setting(session: Session, key: str, value: str) -> None:
    setting = session.get(AppSetting, key)
    if setting is None:
        session.add(AppSetting(key=key, value=value))
    else:
        setting.value = value
    session.flush()
