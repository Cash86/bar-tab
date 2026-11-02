from uuid import uuid4

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from bartab.domain.clock import Clock
from bartab.persistence.models import (
    Drink,
    DrinkGroup,
    DrinkPrice,
    Person,
    PriceTier,
)
from bartab.persistence.repos import ensure_open_period

TIERS = ["Mitglieder", "Gäste"]

GROUPS = [
    ("Bier", "#E3A33A"),
    ("Alkoholfrei", "#9CC46A"),
    ("Limo", "#C79BF0"),
    ("Wasser", "#72B8DE"),
]

# (name, group, crate_size, hidden, member price, guest price) in cents
DRINKS = [
    ("Pils", "Bier", 20, False, 150, 200),
    ("Helles", "Bier", 20, False, 150, 200),
    ("Weizen", "Bier", 20, False, 170, 220),
    ("Radler", "Bier", 20, False, 150, 200),
    ("Alkoholfreies Pils", "Alkoholfrei", 20, False, 150, 200),
    ("Cola", "Limo", 24, False, 120, 160),
    ("Orangenlimo", "Limo", 24, False, 120, 160),
    ("Apfelschorle", "Limo", 12, False, 130, 170),
    ("Mineralwasser", "Wasser", 12, False, 100, 140),
    ("Fassbier 30 l", "Bier", 1, True, 120, 160),
]

# (name, collective, hidden, tier index)
PERSONS = [
    ("Jörg", False, False, 0),
    ("Kalle", False, False, 0),
    ("Uschi", False, False, 0),
    ("Bärbel", False, False, 0),
    ("Heinz", False, False, 0),
    ("Resi", False, False, 0),
    ("Sepp", False, False, 0),
    ("Gerda", False, False, 0),
    ("Fritz", False, False, 1),
    ("Lotte", False, False, 1),
    ("Stammtisch", True, False, 0),
    ("Veranstaltung", False, True, 0),
]


def _is_empty(session: Session) -> bool:
    for model in (Person, Drink, PriceTier, DrinkGroup):
        if session.scalar(select(func.count()).select_from(model)):
            return False
    return True


def seed_demo(session: Session, clock: Clock) -> bool:
    """Fills an empty database with invented demo data; returns False if it was not empty."""
    if not _is_empty(session):
        return False
    now = clock.now()

    tiers = [
        PriceTier(id=str(uuid4()), name=name, sort_order=index, created_at=now, updated_at=now)
        for index, name in enumerate(TIERS)
    ]
    groups = {
        name: DrinkGroup(
            id=str(uuid4()),
            name=name,
            sort_order=index,
            color=color,
            created_at=now,
            updated_at=now,
        )
        for index, (name, color) in enumerate(GROUPS)
    }
    session.add_all([*tiers, *groups.values()])
    session.flush()

    for index, (name, group, crate_size, hidden, member, guest) in enumerate(DRINKS):
        drink = Drink(
            id=str(uuid4()),
            name=name,
            group_id=groups[group].id,
            crate_size=crate_size,
            sort_order=index,
            is_hidden=hidden,
            created_at=now,
            updated_at=now,
        )
        session.add(drink)
        session.flush()
        for tier, price in zip(tiers, (member, guest), strict=True):
            session.add(DrinkPrice(drink_id=drink.id, price_tier_id=tier.id, price_cents=price))

    for name, collective, hidden, tier_index in PERSONS:
        session.add(
            Person(
                id=str(uuid4()),
                name=name,
                price_tier_id=tiers[tier_index].id,
                is_collective=collective,
                is_hidden=hidden,
                created_at=now,
                updated_at=now,
            )
        )

    ensure_open_period(session, clock)
    session.flush()
    return True
