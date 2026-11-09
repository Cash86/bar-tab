import json
from datetime import timedelta

import pytest
from sqlalchemy import select

from bartab.persistence import deliveries, repos
from bartab.persistence import settlement as st
from bartab.persistence.models import (
    Drink,
    DrinkGroup,
    DrinkPrice,
    Period,
    Person,
    PriceTier,
    SettlementRecord,
    StockEntry,
)


@pytest.fixture
def s(db_session, clock):
    now = clock.now()
    stamps = {"created_at": now, "updated_at": now}
    db_session.add_all(
        [
            PriceTier(id="t1", name="Member", sort_order=1, **stamps),
            PriceTier(id="t2", name="Guest", sort_order=2, **stamps),
            # group sort order decides the drink order before the drink sort order
            DrinkGroup(id="g2", name="Soft", sort_order=2, color="#112233", **stamps),
            DrinkGroup(id="g1", name="Beer", sort_order=1, color="#445566", **stamps),
        ]
    )
    db_session.flush()
    db_session.add_all(
        [
            Person(id="pa", name="Alice", price_tier_id="t1", **stamps),
            Person(id="ph", name="Keg", price_tier_id="t1", is_hidden=True, **stamps),
            Person(id="px", name="Gone", price_tier_id="t2", is_active=False, **stamps),
            Drink(id="d2", name="Cola", group_id="g2", crate_size=12, sort_order=0, **stamps),
            Drink(id="d1", name="Lager", group_id="g1", crate_size=20, sort_order=5, **stamps),
            Drink(
                id="d3",
                name="Old",
                group_id="g1",
                crate_size=20,
                sort_order=1,
                is_active=False,
                **stamps,
            ),
        ]
    )
    db_session.flush()
    db_session.add_all(
        [
            DrinkPrice(drink_id="d1", price_tier_id="t1", price_cents=60),
            DrinkPrice(drink_id="d1", price_tier_id="t2", price_cents=150),
            DrinkPrice(drink_id="d2", price_tier_id="t1", price_cents=100),
        ]
    )
    db_session.flush()
    repos.ensure_open_period(db_session, clock)
    db_session.commit()
    return db_session


def _book(session, clock, bid, person="pa", drink="d1", qty=1, price=60, booked_at=None):
    return repos.add_booking(
        session,
        id=bid,
        person_id=person,
        drink_id=drink,
        quantity=qty,
        unit_price_cents=price,
        booked_at=booked_at or clock.now(),
        device_id="dev",
        clock=clock,
    )


def _deliver(session, clock, eid, drink="d1", qty=10):
    deliveries.add_deliveries(session, clock, [(eid, drink, qty)])


def _open(session):
    return session.scalars(select(Period).where(Period.closed_at.is_(None))).one()


def _entries(session, period_id, kind):
    return {
        e.drink_id: e.quantity
        for e in session.scalars(
            select(StockEntry).where(
                StockEntry.period_id == period_id,
                StockEntry.kind == kind,
                StockEntry.cancelled_at.is_(None),
            )
        )
    }


def _review_and_close(s, clock, counts):
    reviewed = st.review(s, clock, counts)
    return st.close(s, clock, st.review_token(reviewed), counts)


def test_review_requires_every_drink_counted(s, clock):
    _deliver(s, clock, "e1", qty=10)
    _book(s, clock, "b1", qty=2)
    with pytest.raises(st.MissingCount):
        st.review(s, clock, {"d1": 7})
    with pytest.raises(st.UnknownDrink):
        st.review(s, clock, {"d1": 7, "d2": 0, "nope": 1})
    # an inactive drink without stock is not counted, so a count for it is not expected either
    with pytest.raises(st.UnknownDrink):
        st.review(s, clock, {"d1": 7, "d2": 0, "d3": 0})
    result = st.review(s, clock, {"d1": 7, "d2": 0})
    assert [d.drink_id for d in result.drinks] == ["d1", "d2"]
    lager = result.drinks[0]
    assert (lager.expected, lager.counted, lager.shrinkage, lager.value_cents) == (8, 7, 1, 60)
    assert result.valuation_tier_name == "Member"
    assert result.grand_total_cents == 120
    assert s.scalars(select(StockEntry).where(StockEntry.kind == "count")).all() == []


def test_review_uses_the_chosen_valuation_tier(s, clock):
    _deliver(s, clock, "e1", qty=10)
    st.set_valuation_tier_id(s, "t2")
    result = st.review(s, clock, {"d1": 9, "d2": 0})
    assert result.valuation_tier_name == "Guest"
    assert result.drinks[0].value_cents == 150
    assert result.drinks[1].has_price is False


def test_review_lists_inactive_drink_with_stock_and_hidden_and_inactive_persons(s, clock):
    _deliver(s, clock, "e1", drink="d3", qty=4)
    _book(s, clock, "b1", person="ph", qty=1)
    _book(s, clock, "b2", person="px", qty=1, price=150)
    with pytest.raises(st.MissingCount):
        st.review(s, clock, {"d1": 0, "d2": 0})
    result = st.review(s, clock, {"d1": 0, "d2": 0, "d3": 4})
    assert [d.drink_id for d in result.drinks] == ["d3", "d1", "d2"]
    assert [p.person_id for p in result.hidden] == ["ph"]
    assert [p.person_id for p in result.persons] == ["px"]


def test_stock_overview_lists_expected_stock(s, clock):
    _deliver(s, clock, "e1", qty=10)
    _deliver(s, clock, "e2", drink="d3", qty=3)
    _book(s, clock, "b1", qty=2)
    allowed, drinks = st.stock_overview(s)
    assert allowed is True
    assert [(d.id, d.group_name, expected) for d, expected in drinks] == [
        ("d3", "Beer", 3),
        ("d1", "Beer", 8),
        ("d2", "Soft", 0),
    ]
    _review_and_close(s, clock, {"d1": 8, "d2": 0, "d3": 3})
    allowed, _ = st.stock_overview(s)
    assert allowed is False


def test_close_stores_counts_and_opens_next_period_with_counts_as_opening(s, clock):
    _deliver(s, clock, "e1", qty=10)
    _book(s, clock, "b1", qty=2)
    old = _open(s)
    counts = {"d1": 7, "d2": 0}
    reviewed = st.review(s, clock, counts)
    clock.advance(timedelta(minutes=3))  # confirming takes a while
    row, created = st.close(s, clock, st.review_token(reviewed), counts)
    assert created is True
    assert old.closed_at == clock.now()
    assert _entries(s, old.id, "count") == counts
    new = _open(s)
    assert new.id != old.id
    assert new.started_at == clock.now()
    assert _entries(s, new.id, "opening") == counts
    assert row.period_id == old.id
    assert row.token == st.review_token(reviewed)
    assert row.mail_status == "pending"
    assert row.mail_error is None and row.mailed_at is None
    assert row.created_at == clock.now()
    assert json.loads(row.figures_json)["version"] == 1
    snapshot = st.snapshot_of(row)
    assert snapshot.ended_at == clock.now()
    assert snapshot.drinks[0].shrinkage == 1
    assert snapshot.grand_total_cents == 120
    assert st.last_settlement(s).id == row.id


def test_close_with_stale_token_is_409(s, clock):
    _deliver(s, clock, "e1", qty=10)
    counts = {"d1": 10, "d2": 0}
    token = st.review_token(st.review(s, clock, counts))
    _book(s, clock, "b1", qty=1)  # another tablet syncs meanwhile
    with pytest.raises(st.StaleReview):
        st.close(s, clock, token, counts)
    assert s.scalars(select(Period).where(Period.closed_at.is_not(None))).all() == []
    assert s.scalars(select(StockEntry).where(StockEntry.kind == "count")).all() == []
    assert s.scalars(select(SettlementRecord)).all() == []

    token = st.review_token(st.review(s, clock, counts))
    s.get(DrinkPrice, ("d1", "t1")).price_cents = 70  # a price change also makes it stale
    s.flush()
    with pytest.raises(st.StaleReview):
        st.close(s, clock, token, counts)

    token = st.review_token(st.review(s, clock, counts))
    with pytest.raises(st.StaleReview):  # different counts than reviewed
        st.close(s, clock, token, {"d1": 9, "d2": 0})


def test_close_retry_with_same_token_is_idempotent(s, clock):
    _deliver(s, clock, "e1", qty=10)
    counts = {"d1": 10, "d2": 0}
    token = st.review_token(st.review(s, clock, counts))
    first, created = st.close(s, clock, token, counts)
    s.commit()
    clock.advance(timedelta(seconds=30))
    again, created_again = st.close(s, clock, token, counts)
    assert (created, created_again) == (True, False)
    assert again.id == first.id
    assert len(s.scalars(select(Period)).all()) == 2
    assert len(s.scalars(select(SettlementRecord)).all()) == 1
    assert len(s.scalars(select(StockEntry).where(StockEntry.kind == "count")).all()) == 2


def test_snapshot_unchanged_after_price_change(s, clock):
    _deliver(s, clock, "e1", qty=10)
    _book(s, clock, "b1", qty=2)
    row, _ = _review_and_close(s, clock, {"d1": 7, "d2": 0})
    before = row.figures_json
    s.get(DrinkPrice, ("d1", "t1")).price_cents = 999
    s.get(PriceTier, "t1").name = "Renamed"
    st.set_valuation_tier_id(s, "t2")
    s.commit()
    s.expire_all()
    row = st.last_settlement(s)
    assert row.figures_json == before
    snapshot = st.snapshot_of(row)
    assert snapshot.valuation_tier_name == "Member"
    assert snapshot.drinks[0].value_cents == 60


def test_late_booking_after_close_lands_in_new_period_marked_late(s, clock):
    _deliver(s, clock, "e1", qty=10)
    old = _open(s)
    clock.advance(timedelta(hours=1))
    _review_and_close(s, clock, {"d1": 10, "d2": 0})
    booked_before_close = clock.now() - timedelta(minutes=5)
    clock.advance(timedelta(minutes=1))
    booking = _book(s, clock, "late", booked_at=booked_before_close)
    assert booking.period_id != old.id
    assert booking.period_id == _open(s).id
    assert booking.is_late is True


def test_opening_count_replaces_previous_and_is_refused_after_a_settlement(s, clock):
    period = _open(s)
    st.record_opening_count(s, clock, {"d1": 5, "d2": 2})
    clock.advance(timedelta(days=1))
    st.record_opening_count(s, clock, {"d1": 6, "d2": 0})
    assert _entries(s, period.id, "opening") == {"d1": 6, "d2": 0}
    cancelled = s.scalars(
        select(StockEntry).where(StockEntry.kind == "opening", StockEntry.cancelled_at.is_not(None))
    ).all()
    assert len(cancelled) == 2
    assert all(e.cancelled_at == clock.now() for e in cancelled)
    allowed, drinks = st.stock_overview(s)
    assert [(d.id, expected) for d, expected in drinks] == [("d1", 6), ("d2", 0)]

    with pytest.raises(st.MissingCount):
        st.record_opening_count(s, clock, {"d1": 1})
    with pytest.raises(st.UnknownDrink):
        st.record_opening_count(s, clock, {"d1": 1, "d2": 0, "nope": 1})

    _review_and_close(s, clock, {"d1": 6, "d2": 0})
    with pytest.raises(st.AlreadySettled):
        st.record_opening_count(s, clock, {"d1": 1, "d2": 1})
    assert _entries(s, _open(s).id, "opening") == {"d1": 6, "d2": 0}


def test_last_inventory_at_rules(s, clock):
    start = _open(s).started_at
    # no opening count: start of the open period
    clock.advance(timedelta(days=2))
    assert st.last_inventory_at(s) == start
    # opening count: its time, the latest one wins
    st.record_opening_count(s, clock, {"d1": 1, "d2": 1})
    clock.advance(timedelta(days=1))
    st.record_opening_count(s, clock, {"d1": 2, "d2": 1})
    assert st.last_inventory_at(s) == clock.now()
    # after a settlement: start of the open period
    clock.advance(timedelta(days=3))
    _review_and_close(s, clock, {"d1": 2, "d2": 1})
    closed_at = clock.now()
    clock.advance(timedelta(days=1))
    assert st.last_inventory_at(s) == closed_at == _open(s).started_at


def test_recipients_and_valuation_tier_round_trip(s):
    assert st.get_recipients(s) == []
    assert st.get_valuation_tier_id(s) is None
    st.set_recipients(s, ["a@example.org", "b@example.org"])
    st.set_valuation_tier_id(s, "t2")
    s.commit()
    assert st.get_recipients(s) == ["a@example.org", "b@example.org"]
    assert st.get_valuation_tier_id(s) == "t2"
    st.set_recipients(s, [])
    assert st.get_recipients(s) == []


def test_set_mail_status(s, clock):
    _deliver(s, clock, "e1", qty=10)
    row, _ = _review_and_close(s, clock, {"d1": 10, "d2": 0})
    clock.advance(timedelta(minutes=1))
    st.set_mail_status(s, row.id, "failed", "connection refused", clock)
    assert (row.mail_status, row.mail_error, row.mailed_at) == (
        "failed",
        "connection refused",
        None,
    )
    assert row.updated_at == clock.now()
    clock.advance(timedelta(minutes=1))
    st.set_mail_status(s, row.id, "sent", None, clock)
    assert (row.mail_status, row.mail_error, row.mailed_at) == ("sent", None, clock.now())


def test_last_settlement_is_the_latest(s, clock):
    assert st.last_settlement(s) is None
    first, _ = _review_and_close(s, clock, {"d1": 0, "d2": 0})
    clock.advance(timedelta(days=30))
    _deliver(s, clock, "e1", qty=5)
    second, _ = _review_and_close(s, clock, {"d1": 5, "d2": 0})
    assert first.id != second.id
    assert st.last_settlement(s).id == second.id


def test_close_with_changed_count_list_is_stale(s, clock):
    counts = {"d1": 0, "d2": 0}
    token = st.review_token(st.review(s, clock, counts))
    _deliver(s, clock, "e1", drink="d3", qty=2)  # inactive drink gets stock: must be counted now
    with pytest.raises(st.StaleReview):
        st.close(s, clock, token, counts)
    assert s.scalars(select(Period).where(Period.closed_at.is_not(None))).all() == []

    counts = {"d1": 0, "d2": 0, "d3": 2}
    token = st.review_token(st.review(s, clock, counts))
    deliveries.cancel_delivery(s, "e1", "dev", clock)  # inactive without stock: not listed now
    with pytest.raises(st.StaleReview):
        st.close(s, clock, token, counts)
    assert s.scalars(select(Period).where(Period.closed_at.is_not(None))).all() == []
    assert s.scalars(select(SettlementRecord)).all() == []


def test_review_does_not_create_a_period(db_session, clock):
    with pytest.raises(LookupError):
        st.review(db_session, clock, {})
    assert db_session.scalars(select(Period)).all() == []


def test_last_settlement_follows_the_closing_time(s, clock):
    first, _ = _review_and_close(s, clock, {"d1": 0, "d2": 0})
    clock.advance(timedelta(days=30))
    second, _ = _review_and_close(s, clock, {"d1": 0, "d2": 0})
    first.created_at = clock.now() + timedelta(days=1)  # row timestamps do not decide
    s.flush()
    assert st.last_settlement(s).id == second.id
