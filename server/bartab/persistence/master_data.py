"""Admin writes for master data: persons, drinks, drink groups and price tiers."""

from collections.abc import Sequence
from typing import Any
from uuid import uuid4

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from bartab.domain.clock import Clock
from bartab.domain.names import (
    MAX_DRINK,
    MAX_GROUP,
    MAX_PERSON,
    MAX_TIER,
    clean_name,
    name_key,
)
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier

MAX_PRICE_CENTS = 1_000_000


class NotFound(Exception):
    pass


class Conflict(Exception):
    """detail: name_taken, group_in_use, tier_in_use, last_tier or order_mismatch."""

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class Invalid(Exception):
    """detail: invalid_name, unknown_reference or prices_incomplete."""

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


def _get(session: Session, model: type, entity_id: str) -> Any:
    row = session.get(model, entity_id)
    if row is None:
        raise NotFound(entity_id)
    return row


def _ensure_unique(session: Session, model: type, name: str, own_id: str | None) -> None:
    key = name_key(name)
    for row_id, other in session.execute(select(model.id, model.name)):
        if row_id != own_id and name_key(other) == key:
            raise Conflict("name_taken")


def _require_tier(session: Session, tier_id: str) -> None:
    if session.get(PriceTier, tier_id) is None:
        raise Invalid("unknown_reference")


def _require_group(session: Session, group_id: str) -> None:
    if session.get(DrinkGroup, group_id) is None:
        raise Invalid("unknown_reference")


def _next_order(session: Session, model: type, *where: Any) -> int:
    top = session.scalar(select(func.max(model.sort_order)).where(*where))
    return 0 if top is None else top + 1


def _check_prices(session: Session, prices: dict[str, int]) -> None:
    tier_ids = set(session.scalars(select(PriceTier.id)))
    if set(prices) != tier_ids or any(not 0 <= c <= MAX_PRICE_CENTS for c in prices.values()):
        raise Invalid("prices_incomplete")


def _set_prices(session: Session, drink_id: str, prices: dict[str, int]) -> None:
    session.execute(delete(DrinkPrice).where(DrinkPrice.drink_id == drink_id))
    session.add_all(DrinkPrice(drink_id=drink_id, price_tier_id=t, price_cents=c)
                    for t, c in prices.items())  # fmt: skip
    session.flush()


def create_person(
    session: Session,
    clock: Clock,
    *,
    name: str,
    price_tier_id: str,
    is_hidden: bool,
    is_collective: bool,
) -> Person:
    name = clean_name(name, MAX_PERSON)
    _ensure_unique(session, Person, name, None)
    _require_tier(session, price_tier_id)
    now = clock.now()
    person = Person(
        id=str(uuid4()),
        name=name,
        price_tier_id=price_tier_id,
        is_hidden=is_hidden,
        is_collective=is_collective,
        is_active=True,
        created_at=now,
        updated_at=now,
    )
    session.add(person)
    session.flush()
    return person


def update_person(
    session: Session,
    clock: Clock,
    person_id: str,
    *,
    name: str,
    price_tier_id: str,
    is_hidden: bool,
    is_collective: bool,
    is_active: bool,
) -> Person:
    person = _get(session, Person, person_id)
    name = clean_name(name, MAX_PERSON)
    _ensure_unique(session, Person, name, person.id)
    _require_tier(session, price_tier_id)
    person.name = name
    person.price_tier_id = price_tier_id
    person.is_hidden = is_hidden
    person.is_collective = is_collective
    person.is_active = is_active
    person.updated_at = clock.now()
    session.flush()
    return person


def create_drink(
    session: Session,
    clock: Clock,
    *,
    name: str,
    group_id: str,
    crate_size: int,
    is_hidden: bool,
    prices: dict[str, int],
) -> Drink:
    name = clean_name(name, MAX_DRINK)
    _ensure_unique(session, Drink, name, None)
    _require_group(session, group_id)
    _check_prices(session, prices)
    now = clock.now()
    drink = Drink(
        id=str(uuid4()),
        name=name,
        group_id=group_id,
        crate_size=crate_size,
        sort_order=_next_order(session, Drink, Drink.group_id == group_id),
        is_hidden=is_hidden,
        is_active=True,
        created_at=now,
        updated_at=now,
    )
    session.add(drink)
    session.flush()
    _set_prices(session, drink.id, prices)
    return drink


def update_drink(
    session: Session,
    clock: Clock,
    drink_id: str,
    *,
    name: str,
    group_id: str,
    crate_size: int,
    is_hidden: bool,
    is_active: bool,
    prices: dict[str, int],
) -> Drink:
    drink = _get(session, Drink, drink_id)
    name = clean_name(name, MAX_DRINK)
    _ensure_unique(session, Drink, name, drink.id)
    _require_group(session, group_id)
    _check_prices(session, prices)
    if group_id != drink.group_id:
        drink.sort_order = _next_order(session, Drink, Drink.group_id == group_id)
        drink.group_id = group_id
    drink.name = name
    drink.crate_size = crate_size
    drink.is_hidden = is_hidden
    drink.is_active = is_active
    drink.updated_at = clock.now()
    session.flush()
    _set_prices(session, drink.id, prices)
    return drink


def create_group(session: Session, clock: Clock, *, name: str, color: str) -> DrinkGroup:
    name = clean_name(name, MAX_GROUP)
    _ensure_unique(session, DrinkGroup, name, None)
    now = clock.now()
    group = DrinkGroup(
        id=str(uuid4()),
        name=name,
        sort_order=_next_order(session, DrinkGroup),
        color=color,
        created_at=now,
        updated_at=now,
    )
    session.add(group)
    session.flush()
    return group


def update_group(
    session: Session, clock: Clock, group_id: str, *, name: str, color: str
) -> DrinkGroup:
    group = _get(session, DrinkGroup, group_id)
    name = clean_name(name, MAX_GROUP)
    _ensure_unique(session, DrinkGroup, name, group.id)
    group.name = name
    group.color = color
    group.updated_at = clock.now()
    session.flush()
    return group


def delete_group(session: Session, group_id: str) -> None:
    group = _get(session, DrinkGroup, group_id)
    if session.scalar(select(Drink.id).where(Drink.group_id == group_id).limit(1)) is not None:
        raise Conflict("group_in_use")
    session.delete(group)
    session.flush()


def create_tier(session: Session, clock: Clock, *, name: str) -> PriceTier:
    name = clean_name(name, MAX_TIER)
    _ensure_unique(session, PriceTier, name, None)
    first_id = session.scalar(select(PriceTier.id).order_by(PriceTier.sort_order).limit(1))
    now = clock.now()
    tier = PriceTier(
        id=str(uuid4()),
        name=name,
        sort_order=_next_order(session, PriceTier),
        created_at=now,
        updated_at=now,
    )
    session.add(tier)
    session.flush()
    if first_id is not None:
        session.add_all(
            DrinkPrice(drink_id=p.drink_id, price_tier_id=tier.id, price_cents=p.price_cents)
            for p in session.scalars(select(DrinkPrice).where(DrinkPrice.price_tier_id == first_id))
        )
        session.flush()
    return tier


def update_tier(session: Session, clock: Clock, tier_id: str, *, name: str) -> PriceTier:
    tier = _get(session, PriceTier, tier_id)
    name = clean_name(name, MAX_TIER)
    _ensure_unique(session, PriceTier, name, tier.id)
    tier.name = name
    tier.updated_at = clock.now()
    session.flush()
    return tier


def delete_tier(session: Session, tier_id: str) -> None:
    tier = _get(session, PriceTier, tier_id)
    if session.scalar(select(func.count()).select_from(PriceTier)) == 1:
        raise Conflict("last_tier")
    if session.scalar(select(Person.id).where(Person.price_tier_id == tier_id).limit(1)):
        raise Conflict("tier_in_use")
    session.execute(delete(DrinkPrice).where(DrinkPrice.price_tier_id == tier_id))
    session.delete(tier)
    session.flush()


def _reorder(session: Session, clock: Clock, model: type, ids: Sequence[str], *where: Any) -> None:
    rows = {row.id: row for row in session.scalars(select(model).where(*where))}
    if len(ids) != len(rows) or set(ids) != set(rows):
        raise Conflict("order_mismatch")
    now = clock.now()
    for position, row_id in enumerate(ids):
        rows[row_id].sort_order = position
        rows[row_id].updated_at = now
    session.flush()


def reorder_groups(session: Session, clock: Clock, ids: list[str]) -> None:
    _reorder(session, clock, DrinkGroup, ids)


def reorder_tiers(session: Session, clock: Clock, ids: list[str]) -> None:
    _reorder(session, clock, PriceTier, ids)


def reorder_drinks(session: Session, clock: Clock, group_id: str, ids: list[str]) -> None:
    _reorder(session, clock, Drink, ids, Drink.group_id == group_id)
