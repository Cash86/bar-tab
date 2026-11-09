from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from bartab.domain.clock import Clock
from bartab.domain.legacy import ImportPlan
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier

# Same colours, in the same order, as the app's group palette (app/lib/domain/master_data.dart).
GROUP_PALETTE = [
    "#EA1313",
    "#B1600E",
    "#7B7B0A",
    "#47840B",
    "#0B890B",
    "#0B894A",
    "#0B8484",
    "#1275D9",
    "#6363F2",
    "#9C47F0",
    "#CD11CD",
    "#E2127A",
]


class NotEmpty(Exception):
    """The database already holds price tiers, groups, persons or drinks."""


def apply_plan(session: Session, clock: Clock, plan: ImportPlan) -> None:
    """Writes the plan into an empty database; the caller commits (or rolls back)."""
    for model in (PriceTier, DrinkGroup, Person, Drink):
        if session.scalar(select(func.count()).select_from(model)):
            raise NotEmpty("database is not empty (price tiers, groups, persons or drinks exist)")
    now = clock.now()

    tiers = {
        name: PriceTier(id=str(uuid4()), name=name, sort_order=i, created_at=now, updated_at=now)
        for i, name in enumerate(plan.tiers)
    }
    groups = {
        name: DrinkGroup(
            id=str(uuid4()),
            name=name,
            sort_order=i,
            color=GROUP_PALETTE[i % len(GROUP_PALETTE)],
            created_at=now,
            updated_at=now,
        )
        for i, name in enumerate(plan.groups)
    }
    session.add_all([*tiers.values(), *groups.values()])
    session.flush()

    for person in plan.persons:
        session.add(
            Person(
                id=str(uuid4()),
                name=person.name,
                price_tier_id=tiers[person.tier].id,
                is_collective=person.is_collective,
                is_hidden=person.is_hidden,
                created_at=now,
                updated_at=now,
            )
        )
    for i, planned in enumerate(plan.drinks):
        drink = Drink(
            id=str(uuid4()),
            name=planned.name,
            group_id=groups[planned.group].id,
            crate_size=planned.crate_size,
            sort_order=i,
            is_hidden=planned.is_hidden,
            is_keg=planned.is_keg,
            created_at=now,
            updated_at=now,
        )
        session.add(drink)
        session.flush()
        for tier_name, cents in planned.prices.items():
            session.add(
                DrinkPrice(drink_id=drink.id, price_tier_id=tiers[tier_name].id, price_cents=cents)
            )
    session.flush()
