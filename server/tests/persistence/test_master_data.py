from datetime import timedelta

import pytest
from sqlalchemy import select

from bartab.domain.names import InvalidName
from bartab.persistence import master_data as md
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier


@pytest.fixture
def s(db_session):
    return db_session


def _tiers(s, clock):
    a = md.create_tier(s, clock, name="Member")
    b = md.create_tier(s, clock, name="Guest")
    return a, b


def _prices(*tiers, cents=100):
    return {t.id: cents for t in tiers}


def _person(s, clock, tier, name="Anton Beispiel"):
    return md.create_person(
        s, clock, name=name, price_tier_id=tier.id, is_hidden=False, is_collective=False
    )


def _deactivate_person(s, clock, person):
    return md.update_person(
        s,
        clock,
        person.id,
        name=person.name,
        price_tier_id=person.price_tier_id,
        is_hidden=False,
        is_collective=False,
        is_active=False,
    )


def test_create_person_trims_and_stores(s, clock):
    tier, _ = _tiers(s, clock)
    p = md.create_person(
        s,
        clock,
        name="  Anton Beispiel ",
        price_tier_id=tier.id,
        is_hidden=False,
        is_collective=True,
    )
    assert p.name == "Anton Beispiel"
    assert p.is_active is True and p.is_collective is True
    assert p.created_at == clock.now() == p.updated_at
    assert len(p.id) == 36


def test_duplicate_person_name_case_insensitive_is_taken(s, clock):
    tier, _ = _tiers(s, clock)
    first = _person(s, clock, tier)
    _deactivate_person(s, clock, first)
    with pytest.raises(md.Conflict) as e:
        _person(s, clock, tier, "anton beispiel ")
    assert e.value.detail == "name_taken"


def test_blank_person_name_is_invalid_name(s, clock):
    tier, _ = _tiers(s, clock)
    with pytest.raises(InvalidName):
        _person(s, clock, tier, " ")


def test_update_person_keeps_own_name(s, clock):
    tier, other = _tiers(s, clock)
    p = _person(s, clock, tier, "Anton")
    out = md.update_person(
        s,
        clock,
        p.id,
        name="ANTON",
        price_tier_id=other.id,
        is_hidden=True,
        is_collective=False,
        is_active=True,
    )
    assert out.name == "ANTON" and out.price_tier_id == other.id and out.is_hidden


def test_update_unknown_person_is_not_found(s, clock):
    tier, _ = _tiers(s, clock)
    with pytest.raises(md.NotFound):
        md.update_person(
            s,
            clock,
            "nope",
            name="A",
            price_tier_id=tier.id,
            is_hidden=False,
            is_collective=False,
            is_active=True,
        )


def test_person_with_unknown_tier_is_invalid(s, clock):
    with pytest.raises(md.Invalid) as e:
        md.create_person(
            s, clock, name="Anton", price_tier_id="nope", is_hidden=False, is_collective=False
        )
    assert e.value.detail == "unknown_reference"


def _group(s, clock, name="Beer"):
    return md.create_group(s, clock, name=name, color="#aabbcc")


def _drink(s, clock, group, tiers, name):
    return md.create_drink(
        s,
        clock,
        name=name,
        group_id=group.id,
        crate_size=20,
        is_hidden=False,
        prices=_prices(*tiers),
    )


def _update_drink(s, clock, drink, tiers, *, is_active=True, group=None, prices=None):
    return md.update_drink(
        s,
        clock,
        drink.id,
        name=drink.name,
        group_id=group.id if group else drink.group_id,
        crate_size=drink.crate_size,
        is_hidden=False,
        is_active=is_active,
        prices=prices or _prices(*tiers),
    )


def test_create_drink_goes_to_end_of_group(s, clock):
    tiers = _tiers(s, clock)
    g = _group(s, clock)
    d1 = _drink(s, clock, g, tiers, "Pils")
    d2 = _drink(s, clock, g, tiers, "Weizen")
    assert (d1.sort_order, d2.sort_order) == (0, 1)
    prices = s.scalars(select(DrinkPrice).where(DrinkPrice.drink_id == d2.id)).all()
    assert {p.price_tier_id for p in prices} == {t.id for t in tiers}


def test_drink_needs_price_for_every_tier(s, clock):
    t1, t2 = _tiers(s, clock)
    g = _group(s, clock)
    bad_sets = [
        {t1.id: 100},
        {t1.id: 100, t2.id: 100, "x": 100},
        {t1.id: 100, t2.id: -1},
        {t1.id: 100, t2.id: 1_000_001},
    ]
    for bad in bad_sets:
        with pytest.raises(md.Invalid) as e:
            md.create_drink(
                s, clock, name="Pils", group_id=g.id, crate_size=20, is_hidden=False, prices=bad
            )
        assert e.value.detail == "prices_incomplete"


def test_drink_unknown_group_is_invalid(s, clock):
    t1, t2 = _tiers(s, clock)
    with pytest.raises(md.Invalid) as e:
        md.create_drink(
            s,
            clock,
            name="Pils",
            group_id="nope",
            crate_size=20,
            is_hidden=False,
            prices=_prices(t1, t2),
        )
    assert e.value.detail == "unknown_reference"


def test_update_drink_replaces_prices(s, clock):
    t1, t2 = _tiers(s, clock)
    g = _group(s, clock)
    d = _drink(s, clock, g, (t1, t2), "Pils")
    _update_drink(s, clock, d, (t1, t2), prices={t1.id: 150, t2.id: 200})
    rows = s.scalars(select(DrinkPrice).where(DrinkPrice.drink_id == d.id)).all()
    assert {r.price_tier_id: r.price_cents for r in rows} == {t1.id: 150, t2.id: 200}
    assert d.sort_order == 0


def test_moving_drink_to_other_group_appends_it(s, clock):
    tiers = _tiers(s, clock)
    g1, g2 = _group(s, clock), _group(s, clock, "Soft")
    d = _drink(s, clock, g1, tiers, "Pils")
    _drink(s, clock, g2, tiers, "Cola")
    out = _update_drink(s, clock, d, tiers, group=g2)
    assert out.group_id == g2.id and out.sort_order == 1


def test_duplicate_drink_group_and_tier_names_are_taken(s, clock):
    tiers = _tiers(s, clock)
    g = _group(s, clock)
    _drink(s, clock, g, tiers, "Pils")
    with pytest.raises(md.Conflict):
        _drink(s, clock, g, tiers, " pils")
    with pytest.raises(md.Conflict):
        _group(s, clock, "BEER")
    with pytest.raises(md.Conflict):
        md.create_tier(s, clock, name="guest")


def test_new_tier_copies_first_tier_prices(s, clock):
    t1, t2 = _tiers(s, clock)
    g = _group(s, clock)
    d1 = md.create_drink(
        s,
        clock,
        name="A",
        group_id=g.id,
        crate_size=20,
        is_hidden=False,
        prices={t1.id: 111, t2.id: 222},
    )
    d2 = md.create_drink(
        s,
        clock,
        name="B",
        group_id=g.id,
        crate_size=20,
        is_hidden=False,
        prices={t1.id: 333, t2.id: 444},
    )
    _update_drink(s, clock, d2, (t1, t2), is_active=False, prices={t1.id: 333, t2.id: 444})
    t3 = md.create_tier(s, clock, name="Staff")
    assert t3.sort_order == 2
    rows = s.scalars(select(DrinkPrice).where(DrinkPrice.price_tier_id == t3.id)).all()
    assert {r.drink_id: r.price_cents for r in rows} == {d1.id: 111, d2.id: 333}


def test_first_tier_copies_nothing(s, clock):
    t = md.create_tier(s, clock, name="Only")
    assert t.sort_order == 0
    assert s.scalars(select(DrinkPrice)).all() == []


def test_tier_in_use_cannot_be_deleted(s, clock):
    _, t2 = _tiers(s, clock)
    _deactivate_person(s, clock, _person(s, clock, t2))
    with pytest.raises(md.Conflict) as e:
        md.delete_tier(s, t2.id)
    assert e.value.detail == "tier_in_use"


def test_last_tier_cannot_be_deleted(s, clock):
    t = md.create_tier(s, clock, name="Only")
    with pytest.raises(md.Conflict) as e:
        md.delete_tier(s, t.id)
    assert e.value.detail == "last_tier"


def test_delete_tier_removes_its_prices(s, clock):
    t1, t2 = _tiers(s, clock)
    g = _group(s, clock)
    _drink(s, clock, g, (t1, t2), "Pils")
    md.delete_tier(s, t2.id)
    assert s.get(PriceTier, t2.id) is None
    assert s.scalars(select(DrinkPrice).where(DrinkPrice.price_tier_id == t2.id)).all() == []
    assert len(s.scalars(select(DrinkPrice)).all()) == 1


def test_delete_unknown_tier_is_not_found(s, clock):
    with pytest.raises(md.NotFound):
        md.delete_tier(s, "nope")


def test_group_with_deactivated_drink_cannot_be_deleted(s, clock):
    tiers = _tiers(s, clock)
    g = _group(s, clock)
    d = _drink(s, clock, g, tiers, "Pils")
    _update_drink(s, clock, d, tiers, is_active=False)
    with pytest.raises(md.Conflict) as e:
        md.delete_group(s, g.id)
    assert e.value.detail == "group_in_use"


def test_empty_group_is_deleted(s, clock):
    g = _group(s, clock)
    md.delete_group(s, g.id)
    assert s.get(DrinkGroup, g.id) is None


def test_update_group_and_tier_names(s, clock):
    t1, _ = _tiers(s, clock)
    g = _group(s, clock)
    assert md.update_group(s, clock, g.id, name="Bier", color="#112233").color == "#112233"
    assert md.update_tier(s, clock, t1.id, name="Vereinsmitglied").name == "Vereinsmitglied"
    with pytest.raises(md.Conflict):
        md.update_tier(s, clock, t1.id, name="guest")


def test_reorder_rewrites_sort_order(s, clock):
    tiers = _tiers(s, clock)
    g1, g2 = _group(s, clock), _group(s, clock, "Soft")
    d1, d2 = _drink(s, clock, g1, tiers, "A"), _drink(s, clock, g1, tiers, "B")
    md.reorder_groups(s, clock, [g2.id, g1.id])
    md.reorder_tiers(s, clock, [tiers[1].id, tiers[0].id])
    md.reorder_drinks(s, clock, g1.id, [d2.id, d1.id])
    assert (g2.sort_order, g1.sort_order) == (0, 1)
    assert (tiers[1].sort_order, tiers[0].sort_order) == (0, 1)
    assert (d2.sort_order, d1.sort_order) == (0, 1)


def test_reorder_with_missing_or_extra_id_is_order_mismatch(s, clock):
    tiers = _tiers(s, clock)
    g1, g2 = _group(s, clock), _group(s, clock, "Soft")
    d1, d2 = _drink(s, clock, g1, tiers, "A"), _drink(s, clock, g1, tiers, "B")
    other = _drink(s, clock, g2, tiers, "C")
    calls = [
        lambda ids: md.reorder_groups(s, clock, ids),
        lambda ids: md.reorder_tiers(s, clock, ids),
        lambda ids: md.reorder_drinks(s, clock, g1.id, ids),
    ]
    cases = [
        ([g1.id], [g1.id, g2.id, "x"]),
        ([tiers[0].id], [tiers[0].id, tiers[1].id, "x"]),
        ([d1.id], [d1.id, d2.id, other.id]),
    ]
    for call, (missing, extra) in zip(calls, cases, strict=True):
        for ids in (missing, extra):
            with pytest.raises(md.Conflict) as e:
                call(ids)
            assert e.value.detail == "order_mismatch"


def test_every_write_changes_updated_at(s, clock):
    t1, t2 = _tiers(s, clock)
    g = _group(s, clock)
    d = _drink(s, clock, g, (t1, t2), "Pils")
    p = _person(s, clock, t1, "Anton")
    clock.advance(timedelta(minutes=5))
    now = clock.now()
    md.update_person(
        s,
        clock,
        p.id,
        name="Anton",
        price_tier_id=t1.id,
        is_hidden=False,
        is_collective=False,
        is_active=True,
    )
    _update_drink(s, clock, d, (t1, t2))
    md.update_group(s, clock, g.id, name="Beer", color="#aabbcc")
    md.update_tier(s, clock, t1.id, name="Member")
    assert [x.updated_at for x in (p, d, g, t1)] == [now] * 4
    clock.advance(timedelta(minutes=5))
    now = clock.now()
    md.reorder_groups(s, clock, [g.id])
    md.reorder_tiers(s, clock, [t1.id, t2.id])
    md.reorder_drinks(s, clock, g.id, [d.id])
    assert [x.updated_at for x in (g, t1, t2, d)] == [now] * 4
    assert s.get(Person, p.id) and s.get(Drink, d.id)
