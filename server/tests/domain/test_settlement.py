from datetime import UTC, datetime, timedelta

import pytest

from bartab.domain.settlement import (
    BookingIn,
    DrinkIn,
    PersonIn,
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

T0 = datetime(2026, 10, 1, tzinfo=UTC)
T1 = datetime(2026, 11, 1, tzinfo=UTC)

AKTIVE = TierIn("t1", "Aktive", 1, True)
GAESTE = TierIn("t2", "Gaeste", 2, True)

BEER = DrinkIn("d1", "Pils", "g1", "Bier", 20, True)
COLA = DrinkIn("d2", "Cola", "g2", "Softdrinks", 12, True)

ANNA = PersonIn("p1", "Anna", "t1", False, False)
BEN = PersonIn("p2", "Ben", "t2", False, False)
KEG = PersonIn("p3", "Fass", "t1", True, False)

PRICES = {("t1", "d1"): 60, ("t1", "d2"): 100, ("t2", "d1"): 150, ("t2", "d2"): 170}


def booking(person="p1", drink="d1", qty=1, price=150, cancelled=False, late=False):
    cancelled_at = T0 + timedelta(days=2) if cancelled else None
    return BookingIn(person, drink, qty, price, T0 + timedelta(days=1), cancelled_at, late)


def stock(drink="d1", kind="opening", qty=10, cancelled=False):
    return StockIn(drink, kind, qty, T0, T0 + timedelta(days=3) if cancelled else None)


def settle(
    bookings=(),
    stocks=(),
    counts=None,
    persons=(ANNA, BEN, KEG),
    drinks=(BEER, COLA),
    prices=PRICES,
    tier=AKTIVE,
):
    return compute_settlement(
        period_id="per1",
        started_at=T0,
        ended_at=T1,
        persons=list(persons),
        tiers=[AKTIVE, GAESTE],
        drinks=list(drinks),
        bookings=list(bookings),
        stocks=list(stocks),
        prices=prices,
        counts=counts,
        valuation_tier=tier,
    )


def test_amount_is_sum_of_quantity_times_frozen_unit_price():
    s = settle([booking(qty=2, price=150), booking(drink="d2", qty=1, price=170)])
    assert s.persons[0].amount_cents == 470
    assert s.persons[0].quantities_by_group == {"g1": 2, "g2": 1}
    assert s.person_drink == {"p1": {"d1": 2, "d2": 1}}
    assert s.tier_names == {"t1": "Aktive", "t2": "Gaeste"}


def test_cancelled_bookings_and_deliveries_are_excluded():
    cancelled = booking(qty=5, cancelled=True)
    s = settle(
        [booking(qty=1), cancelled],
        [
            stock(qty=10),
            stock(kind="delivery", qty=7),
            stock(kind="delivery", qty=99, cancelled=True),
        ],
    )
    line = next(d for d in s.drinks if d.drink_id == "d1")
    assert (line.opening, line.delivered, line.booked) == (10, 7, 1)
    assert s.persons[0].amount_cents == 150
    assert s.cancelled_bookings == [cancelled]
    assert len(s.deliveries) == 1
    assert s.cancelled_deliveries == [stock(kind="delivery", qty=99, cancelled=True)]


def test_shrinkage_value_uses_valuation_tier_price():
    s = settle(stocks=[stock(qty=20)], counts={"d1": 17, "d2": 0})
    line = next(d for d in s.drinks if d.drink_id == "d1")
    assert (line.expected, line.counted, line.shrinkage, line.value_cents) == (20, 17, 3, 180)
    assert s.shrinkage_total_cents == 180


def test_negative_shrinkage_offsets_total():
    s = settle(
        stocks=[stock("d1", qty=10), stock("d2", qty=10)],
        counts={"d1": 7, "d2": 11},
    )
    assert s.shrinkage_total_cents == 3 * 60 - 100 == 80
    assert s.group_totals["g1"].value_cents == 180
    assert s.group_totals["g2"].shrinkage == -1


def test_drink_without_valuation_price_counts_zero_and_is_flagged():
    s = settle(stocks=[stock(qty=5)], counts={"d1": 1, "d2": 0}, prices={("t1", "d2"): 100})
    line = next(d for d in s.drinks if d.drink_id == "d1")
    assert line.has_price is False
    assert line.value_cents == 0
    assert next(d for d in s.drinks if d.drink_id == "d2").has_price is True


def test_preview_without_counts_has_no_shrinkage():
    s = settle(stocks=[stock(qty=5)], counts=None)
    assert all(d.counted is None and d.shrinkage is None and d.value_cents == 0 for d in s.drinks)
    assert s.shrinkage_total_cents == 0


def test_hidden_persons_are_separate_and_totals_split():
    s = settle([booking("p1", qty=1, price=150), booking("p3", qty=2, price=60)])
    assert [p.person_id for p in s.persons] == ["p1"]
    assert [p.person_id for p in s.hidden] == ["p3"]
    assert (s.persons_total_cents, s.hidden_total_cents, s.grand_total_cents) == (150, 120, 270)


def test_persons_without_bookings_are_not_listed():
    s = settle([booking("p1")])
    assert [p.person_id for p in s.persons] == ["p1"]


def test_deactivated_person_listed_in_tier():
    gone = PersonIn("p9", "Zoe", "t1", False, False)
    s = settle([booking("p9")], persons=[ANNA, gone])
    assert [p.name for p in s.persons] == ["Zoe"]
    assert s.persons[0].tier_id == "t1"


def test_persons_sorted_by_tier_order_then_name():
    abel = PersonIn("p9", "Abel", "t2", False, False)
    s = settle([booking("p2"), booking("p1"), booking("p9")], persons=[BEN, ANNA, abel])
    assert [p.name for p in s.persons] == ["Anna", "Abel", "Ben"]


def test_effective_valuation_tier_falls_back_to_lowest_active_sort_order():
    off = TierIn("t0", "Alt", 0, False)
    tiers = [GAESTE, AKTIVE, off]
    assert effective_valuation_tier(tiers, "t2") == GAESTE
    assert effective_valuation_tier(tiers, "t0") == AKTIVE
    assert effective_valuation_tier(tiers, None) == AKTIVE
    assert effective_valuation_tier(tiers, "missing") == AKTIVE


def test_drinks_to_count_includes_inactive_with_stock_only():
    old = DrinkIn("d3", "Alt", "g1", "Bier", 10, False)
    empty = DrinkIn("d4", "Leer", "g1", "Bier", 10, False)
    stocks = [stock("d3", qty=4), stock("d4", qty=4)]
    bookings = [booking(drink="d4", qty=4)]
    assert drinks_to_count([BEER, old, empty], stocks, bookings) == [BEER, old]


def test_missing_count_for_listed_drink_is_rejected():
    with pytest.raises(ValueError):
        settle(counts={"d1": 0})


def test_token_is_stable():
    args = ([booking()], [stock()], {"d1": 3, "d2": 0})
    assert figures_token(settle(*args)) == figures_token(settle(*args))


def test_token_changes_when_a_booking_or_count_changes():
    base = figures_token(settle([booking()], [stock()], {"d1": 3, "d2": 0}))
    assert figures_token(settle([booking(qty=2)], [stock()], {"d1": 3, "d2": 0})) != base
    assert figures_token(settle([booking()], [stock()], {"d1": 4, "d2": 0})) != base
    assert figures_token(settle([booking(cancelled=True)], [stock()], {"d1": 3, "d2": 0})) != base


def test_snapshot_round_trip():
    s = settle(
        [booking(), booking("p3", cancelled=True), booking("p3")],
        [stock(), stock(kind="delivery", qty=2), stock(kind="delivery", cancelled=True)],
        {"d1": 3, "d2": 0},
    )
    assert settlement_from_json(settlement_to_json(s)) == s


def test_booking_of_unknown_person_is_rejected():
    with pytest.raises(ValueError, match="person"):
        settle([booking("nobody")])


def test_booking_of_unknown_drink_is_rejected():
    with pytest.raises(ValueError, match="drink"):
        settle([booking(drink="nope")])


def test_effective_valuation_tier_without_active_tier_is_rejected():
    with pytest.raises(ValueError, match="active"):
        effective_valuation_tier([TierIn("t0", "Alt", 0, False)], None)


def test_person_with_unknown_tier_is_rejected():
    odd = PersonIn("p8", "Odd", "tx", False, False)
    with pytest.raises(ValueError, match="tier"):
        settle([booking("p8")], persons=[odd])


def test_expected_stock_ignores_cancelled_entries():
    stocks = [
        stock("d1", qty=10),
        stock("d1", kind="delivery", qty=5),
        stock("d1", kind="delivery", qty=7, cancelled=True),
    ]
    bookings = [booking(qty=3), booking(qty=2, cancelled=True)]
    assert expected_stock([BEER, COLA], stocks, bookings) == {"d1": 12, "d2": 0}


def test_names_cover_every_referenced_person_drink_and_group():
    sold_out = DrinkIn("d3", "Bock", "g3", "Saisonal", 20, False)
    unused = DrinkIn("d4", "Leer", "g4", "Alt", 20, False)
    s = settle(
        [booking("p1"), booking("p3", cancelled=True), booking("p1", drink="d3", qty=2)],
        [stock("d3", qty=2)],
        drinks=(BEER, COLA, sold_out, unused),
    )
    assert "d3" not in {d.drink_id for d in s.drinks}
    assert s.person_names == {"p1": "Anna", "p3": "Fass"}
    assert s.drink_names == {"d1": "Pils", "d2": "Cola", "d3": "Bock"}
    assert s.group_names == {"g1": "Bier", "g2": "Softdrinks", "g3": "Saisonal"}


def test_snapshot_without_name_maps_loads_with_empty_maps():
    data = settlement_to_json(settle([booking()], [stock()], {"d1": 3, "d2": 0}))
    for key in ("person_names", "drink_names", "group_names"):
        del data[key]
    s = settlement_from_json(data)
    assert (s.person_names, s.drink_names, s.group_names) == ({}, {}, {})


def test_stock_since_cuts_off_earlier_stock_movements_but_not_billing():
    count_at = T0 + timedelta(days=1, hours=1)  # after booking() at T0 + 1 day
    before = booking(qty=3)
    after = BookingIn("p1", "d1", 2, 150, count_at + timedelta(hours=1), None, False)
    early_delivery = StockIn("d1", "delivery", 7, T0, None)
    opening = StockIn("d1", "opening", 10, count_at, None)
    late_delivery = StockIn("d1", "delivery", 4, count_at + timedelta(hours=2), None)
    bookings = [before, after]
    stocks = [early_delivery, opening, late_delivery]

    assert expected_stock([BEER], stocks, bookings, stock_since=count_at) == {"d1": 10 + 4 - 2}
    s = compute_settlement(
        period_id="per1",
        started_at=T0,
        ended_at=T1,
        persons=[ANNA],
        tiers=[AKTIVE],
        drinks=[BEER],
        bookings=bookings,
        stocks=stocks,
        prices=PRICES,
        counts={"d1": 12},
        valuation_tier=AKTIVE,
        stock_since=count_at,
    )
    line = s.drinks[0]
    assert (line.opening, line.delivered, line.booked, line.expected) == (10, 4, 2, 12)
    assert s.persons[0].amount_cents == 5 * 150
    assert s.person_drink == {"p1": {"d1": 5}}


def test_drinks_to_count_uses_stock_since():
    old = DrinkIn("d3", "Alt", "g1", "Bier", 10, False)
    since = T0 + timedelta(days=5)
    # 4 delivered before the opening count, which found none: nothing left to count
    stocks = [stock("d3", kind="delivery", qty=4)]
    assert drinks_to_count([BEER, old], stocks, [], stock_since=since) == [BEER]
    assert drinks_to_count([BEER, old], stocks, []) == [BEER, old]
