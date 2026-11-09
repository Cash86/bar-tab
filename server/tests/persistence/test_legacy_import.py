import dataclasses

import pytest
from sqlalchemy import func, select

from bartab.demo_data import seed_demo
from bartab.domain.legacy import ImportPlan, PlannedDrink, PlannedPerson
from bartab.persistence.legacy_import import GROUP_PALETTE, NotEmpty, apply_plan
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier


def make_plan() -> ImportPlan:
    return ImportPlan(
        tiers=["Aktive", "Alte"],
        groups=["Bier", "Limo"],
        persons=[
            PlannedPerson("Kim Beispiel", "Aktive", False, False),
            PlannedPerson("Kasse Eins", "Aktive", False, True),
            PlannedPerson("Geist Eins", "Alte", True, False),
        ],
        drinks=[
            PlannedDrink("Bier Hell", "Bier", 20, False, False, {"Aktive": 120, "Alte": 150}),
            PlannedDrink("Fass Alpha", "Bier", 1, True, True, {"Aktive": 4500, "Alte": 4500}),
            PlannedDrink("Cola", "Limo", 12, False, False, {"Aktive": 55, "Alte": 0}),
        ],
        report=[],
    )


def count(session, model):
    return session.scalar(select(func.count()).select_from(model))


def test_import_creates_everything(db_session, clock):
    apply_plan(db_session, clock, make_plan())
    db_session.commit()

    tiers = db_session.scalars(select(PriceTier).order_by(PriceTier.sort_order)).all()
    assert [t.name for t in tiers] == ["Aktive", "Alte"]
    groups = db_session.scalars(select(DrinkGroup).order_by(DrinkGroup.sort_order)).all()
    assert [(g.name, g.color) for g in groups] == [
        ("Bier", GROUP_PALETTE[0]),
        ("Limo", GROUP_PALETTE[1]),
    ]
    persons = {p.name: p for p in db_session.scalars(select(Person))}
    assert persons["Kasse Eins"].is_collective
    assert persons["Geist Eins"].is_hidden
    assert persons["Geist Eins"].price_tier_id == tiers[1].id
    assert persons["Kim Beispiel"].price_tier_id == tiers[0].id
    assert persons["Kim Beispiel"].created_at == clock.now()

    drinks = db_session.scalars(select(Drink).order_by(Drink.sort_order)).all()
    assert [d.name for d in drinks] == ["Bier Hell", "Fass Alpha", "Cola"]
    assert [d.is_keg for d in drinks] == [False, True, False]
    assert [d.is_hidden for d in drinks] == [False, True, False]
    assert [d.group_id for d in drinks] == [groups[0].id, groups[0].id, groups[1].id]
    prices = {
        (p.drink_id, p.price_tier_id): p.price_cents for p in db_session.scalars(select(DrinkPrice))
    }
    assert prices[(drinks[0].id, tiers[0].id)] == 120
    assert prices[(drinks[0].id, tiers[1].id)] == 150
    assert prices[(drinks[2].id, tiers[1].id)] == 0
    assert len(prices) == 6


def test_refuses_non_empty_database(db_session, clock):
    seed_demo(db_session, clock)
    db_session.commit()
    before = count(db_session, Drink)
    with pytest.raises(NotEmpty):
        apply_plan(db_session, clock, make_plan())
    assert count(db_session, Drink) == before


def _tier(clock):
    return PriceTier(
        id="t1", name="T", sort_order=0, created_at=clock.now(), updated_at=clock.now()
    )


def _group(clock):
    return DrinkGroup(
        id="g1",
        name="G",
        sort_order=0,
        color="#EA1313",
        created_at=clock.now(),
        updated_at=clock.now(),
    )


@pytest.mark.parametrize("kind", ["tier", "group", "person", "drink"])
def test_each_kind_alone_blocks_the_import(db_session, clock, kind):
    now = clock.now()
    # the kind under test must stand alone, without its parent rows
    raw = db_session.get_bind().raw_connection()
    raw.cursor().execute("PRAGMA foreign_keys=OFF")
    raw.close()
    if kind == "tier":
        db_session.add(_tier(clock))
    elif kind == "group":
        db_session.add(_group(clock))
    elif kind == "person":
        db_session.add(
            Person(
                id="p1",
                name="P",
                price_tier_id="t1",
                is_collective=False,
                is_hidden=False,
                created_at=now,
                updated_at=now,
            )
        )
    else:
        db_session.add(
            Drink(
                id="d1",
                name="D",
                group_id="g1",
                crate_size=1,
                sort_order=0,
                created_at=now,
                updated_at=now,
            )
        )
    db_session.commit()
    with pytest.raises(NotEmpty):
        apply_plan(db_session, clock, make_plan())


def test_import_is_all_or_nothing(db_session, clock):
    bad = dataclasses.replace(
        make_plan(),
        drinks=[*make_plan().drinks, PlannedDrink("Kaputt", "Nope", 1, False, False, {})],
    )
    with pytest.raises(KeyError):
        apply_plan(db_session, clock, bad)
    db_session.rollback()
    for model in (PriceTier, DrinkGroup, Person, Drink, DrinkPrice):
        assert count(db_session, model) == 0
