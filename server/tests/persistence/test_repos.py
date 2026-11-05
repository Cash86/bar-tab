from datetime import timedelta

from bartab.persistence import repos
from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier


def _seed(session, clock):
    now = clock.now()
    session.add_all(
        [
            PriceTier(id="t1", name="Member", sort_order=1, created_at=now, updated_at=now),
            PriceTier(id="t2", name="Guest", sort_order=2, created_at=now, updated_at=now),
            DrinkGroup(
                id="g1", name="Beer", sort_order=1, color="#aabbcc", created_at=now, updated_at=now
            ),
        ]
    )
    session.flush()
    for pid, name in (("pa", "Alice"), ("pb", "Bob")):
        session.add(Person(id=pid, name=name, price_tier_id="t1", created_at=now, updated_at=now))
    for did, name, order in (("d1", "Zeta", 1), ("d2", "Alpha", 1), ("d3", "First", 0)):
        session.add(
            Drink(
                id=did,
                name=name,
                group_id="g1",
                crate_size=20,
                sort_order=order,
                created_at=now,
                updated_at=now,
            )
        )
    session.flush()
    session.add_all(
        [
            DrinkPrice(drink_id="d1", price_tier_id="t1", price_cents=60),
            DrinkPrice(drink_id="d1", price_tier_id="t2", price_cents=80),
        ]
    )
    session.flush()


def _book(session, clock, person="pa", drink="d1", qty=1, price=60, booked_at=None, bid=None):
    return repos.add_booking(
        session,
        id=bid or f"b-{person}-{qty}-{price}",
        person_id=person,
        drink_id=drink,
        quantity=qty,
        unit_price_cents=price,
        booked_at=booked_at or clock.now(),
        device_id="dev",
        clock=clock,
    )


def test_ensure_open_period_creates_once(db_session, clock):
    first = repos.ensure_open_period(db_session, clock)
    second = repos.ensure_open_period(db_session, clock)
    assert first.id == second.id
    assert first.started_at == clock.now()
    assert first.closed_at is None


def test_add_booking_assigns_open_period_and_not_late(db_session, clock):
    _seed(db_session, clock)
    period = repos.ensure_open_period(db_session, clock)
    clock.advance(timedelta(minutes=5))
    booking = _book(db_session, clock, booked_at=clock.now())
    assert booking.period_id == period.id
    assert booking.is_late is False
    assert booking.received_at == clock.now()
    assert repos.get_booking(db_session, booking.id) is booking
    assert repos.get_booking(db_session, "missing") is None


def test_add_booking_before_period_start_is_late(db_session, clock):
    _seed(db_session, clock)
    repos.ensure_open_period(db_session, clock)
    booking = _book(db_session, clock, booked_at=clock.now() - timedelta(minutes=1))
    assert booking.is_late is True


def test_add_booking_creates_period_when_none_open(db_session, clock):
    _seed(db_session, clock)
    booking = _book(db_session, clock)
    assert booking.period_id == repos.ensure_open_period(db_session, clock).id


def test_tabs_for_open_period_sums_and_excludes_closed(db_session, clock):
    _seed(db_session, clock)
    old = repos.ensure_open_period(db_session, clock)
    _book(db_session, clock, person="pb", qty=1, price=500, bid="old")
    old.closed_at = clock.now()
    db_session.flush()
    new = repos.ensure_open_period(db_session, clock)
    assert new.id != old.id
    _book(db_session, clock, qty=2, price=60, bid="b1")
    _book(db_session, clock, qty=1, price=130, bid="b2")
    assert repos.tabs_for_open_period(db_session) == {"pa": 250}


def test_get_catalog_orders_and_prices(db_session, clock):
    _seed(db_session, clock)
    catalog = repos.get_catalog(db_session)
    assert [d.name for d in catalog.drinks] == ["First", "Alpha", "Zeta"]
    zeta = catalog.drinks[2]
    assert zeta.prices == {"t1": 60, "t2": 80}
    assert catalog.drinks[0].prices == {}
    assert [t.name for t in catalog.price_tiers] == ["Member", "Guest"]
    assert [p.name for p in catalog.persons] == ["Alice", "Bob"]
    assert [g.name for g in catalog.groups] == ["Beer"]


def test_settings_roundtrip(db_session):
    assert repos.get_setting(db_session, "k") is None
    repos.set_setting(db_session, "k", "v1")
    repos.set_setting(db_session, "k", "v2")
    assert repos.get_setting(db_session, "k") == "v2"


def test_persons_with_equal_names_are_ordered_by_id(db_session, clock):
    now = clock.now()
    stamps = {"created_at": now, "updated_at": now}
    db_session.add(PriceTier(id="t", name="T", sort_order=1, **stamps))
    db_session.flush()
    for pid in ["pz", "pb", "pm", "pa"]:
        db_session.add(Person(id=pid, name="Same", price_tier_id="t", **stamps))
    db_session.flush()
    first = repos.get_catalog(db_session)
    assert [p.id for p in first.persons] == ["pa", "pb", "pm", "pz"]
    assert repos.get_catalog(db_session) == first


def test_cancel_marks_booking_with_time_and_device(db_session, clock):
    _seed(db_session, clock)
    booking = _book(db_session, clock, bid="b1")
    clock.advance(timedelta(minutes=3))
    outcome, cancelled = repos.cancel_booking(db_session, "b1", "admin-dev", clock)
    assert outcome == repos.CancelOutcome.CANCELLED
    assert cancelled is booking
    assert booking.cancelled_at == clock.now()
    assert booking.cancelled_by_device_id == "admin-dev"
    assert booking.updated_at == clock.now()


def test_cancel_unknown_booking_is_not_found(db_session, clock):
    outcome, booking = repos.cancel_booking(db_session, "missing", "dev", clock)
    assert outcome == repos.CancelOutcome.NOT_FOUND
    assert booking is None


def test_cancel_twice_is_already_cancelled(db_session, clock):
    _seed(db_session, clock)
    booking = _book(db_session, clock, bid="b1")
    repos.cancel_booking(db_session, "b1", "dev-1", clock)
    first = booking.cancelled_at
    clock.advance(timedelta(minutes=1))
    outcome, again = repos.cancel_booking(db_session, "b1", "dev-2", clock)
    assert outcome == repos.CancelOutcome.ALREADY_CANCELLED
    assert again is booking
    assert booking.cancelled_at == first
    assert booking.cancelled_by_device_id == "dev-1"


def test_cancel_in_closed_period_is_rejected(db_session, clock):
    _seed(db_session, clock)
    period = repos.ensure_open_period(db_session, clock)
    booking = _book(db_session, clock, bid="b1")
    period.closed_at = clock.now()
    db_session.flush()
    repos.ensure_open_period(db_session, clock)
    outcome, found = repos.cancel_booking(db_session, "b1", "dev", clock)
    assert outcome == repos.CancelOutcome.PERIOD_CLOSED
    assert found is booking
    assert booking.cancelled_at is None


def test_open_period_bookings_newest_first_and_filtered(db_session, clock):
    _seed(db_session, clock)
    old = repos.ensure_open_period(db_session, clock)
    t0 = clock.now()
    _book(db_session, clock, person="pb", bid="old", booked_at=t0)
    old.closed_at = clock.now()
    db_session.flush()
    repos.ensure_open_period(db_session, clock)
    _book(db_session, clock, person="pa", bid="b1", booked_at=t0 + timedelta(minutes=1))
    _book(db_session, clock, person="pb", bid="b2", booked_at=t0 + timedelta(minutes=3))
    _book(db_session, clock, person="pa", bid="b3", booked_at=t0 + timedelta(minutes=2))
    repos.cancel_booking(db_session, "b3", "dev", clock)
    assert [b.id for b in repos.open_period_bookings(db_session)] == ["b2", "b3", "b1"]
    assert [b.id for b in repos.open_period_bookings(db_session, "pa")] == ["b3", "b1"]


def test_tabs_exclude_cancelled_bookings(db_session, clock):
    _seed(db_session, clock)
    _book(db_session, clock, qty=2, price=60, bid="b1")
    _book(db_session, clock, qty=1, price=130, bid="b2")
    repos.cancel_booking(db_session, "b2", "dev", clock)
    assert repos.tabs_for_open_period(db_session) == {"pa": 120}


def test_rankings_exclude_cancelled_bookings(db_session, clock):
    _seed(db_session, clock)
    _book(db_session, clock, qty=1, price=60, bid="b1")
    _book(db_session, clock, qty=2, price=60, bid="b2")
    repos.cancel_booking(db_session, "b2", "dev", clock)
    rankings = repos.drink_rankings(db_session)
    assert rankings.overall == {"d1": 1}
    assert rankings.persons == {"pa": {"d1": 1}}
