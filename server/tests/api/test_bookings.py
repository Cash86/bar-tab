from datetime import UTC, datetime

import pytest
from sqlalchemy import func, select

from bartab.persistence.models import Booking, Drink, DrinkGroup, Person, PriceTier

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)
URL = "/api/v1/bookings"
B1 = "00000000-0000-4000-8000-000000000001"
B2 = "00000000-0000-4000-8000-000000000002"
B3 = "00000000-0000-4000-8000-000000000003"


@pytest.fixture
def seeded(app):
    with app.state.session_factory() as session:
        stamps = {"created_at": NOW, "updated_at": NOW}
        session.add_all(
            [
                PriceTier(id="tier-a", name="Standard", sort_order=1, **stamps),
                DrinkGroup(id="g-1", name="Beer", sort_order=1, color="#112233", **stamps),
            ]
        )
        session.flush()
        session.add_all(
            [
                Person(id="p-1", name="Anna", price_tier_id="tier-a", **stamps),
                Person(
                    id="p-hidden",
                    name="Hidden",
                    price_tier_id="tier-a",
                    is_hidden=True,
                    is_active=False,
                    **stamps,
                ),
                Drink(
                    id="d-1", name="Lager", group_id="g-1", crate_size=20, sort_order=1, **stamps
                ),
                Drink(
                    id="d-off",
                    name="Old",
                    group_id="g-1",
                    crate_size=20,
                    sort_order=2,
                    is_hidden=True,
                    is_active=False,
                    **stamps,
                ),
            ]
        )
        session.commit()


def item(id=B1, **overrides):
    base = {
        "id": id,
        "person_id": "p-1",
        "drink_id": "d-1",
        "quantity": 1,
        "unit_price_cents": 150,
        "booked_at": "2026-11-02T18:00:00+00:00",
    }
    return {**base, **overrides}


def post(client, headers, *items):
    return client.post(URL, headers=headers, json={"bookings": list(items)})


def statuses(response):
    return [(r["status"], r["reason"]) for r in response.json()["results"]]


def count(app):
    with app.state.session_factory() as session:
        return session.scalar(select(func.count()).select_from(Booking))


def test_requires_device_key(client, seeded):
    assert client.post(URL, json={"bookings": [item()]}).status_code == 401


def test_accepted_booking_is_stored_with_device_and_open_period(
    app, client, device_b_headers, seeded
):
    response = post(client, device_b_headers, item())
    assert response.status_code == 200
    assert response.json() == {"results": [{"id": B1, "status": "accepted", "reason": None}]}
    with app.state.session_factory() as session:
        booking = session.get(Booking, B1)
        assert booking.device_id
        assert booking.person_id == "p-1"
        assert booking.unit_price_cents == 150
        assert booking.is_late is False
        assert booking.period_id


def test_device_id_is_the_callers(app, client, device_headers, device_b_headers, seeded):
    post(client, device_headers, item(B1))
    post(client, device_b_headers, item(B2))
    with app.state.session_factory() as session:
        assert session.get(Booking, B1).device_id != session.get(Booking, B2).device_id


def test_same_batch_twice_is_duplicate_and_stores_nothing_new(app, client, device_headers, seeded):
    batch = [item(B1), item(B2, quantity=3)]
    post(client, device_headers, *batch)
    again = post(client, device_headers, *batch)
    assert statuses(again) == [("duplicate", None), ("duplicate", None)]
    assert count(app) == 2


def test_duplicate_from_other_device_and_equivalent_utc_offset(
    app, client, device_headers, device_b_headers, seeded
):
    post(client, device_headers, item(B1))
    again = post(client, device_b_headers, item(B1, booked_at="2026-11-02T19:00:00+01:00"))
    assert statuses(again) == [("duplicate", None)]
    assert count(app) == 1


def test_same_id_twice_within_one_batch(app, client, device_headers, seeded):
    response = post(client, device_headers, item(B1), item(B1))
    assert statuses(response) == [("accepted", None), ("duplicate", None)]
    assert count(app) == 1


@pytest.mark.parametrize(
    "change",
    [
        {"quantity": 2},
        {"unit_price_cents": 151},
        {"drink_id": "d-off"},
        {"person_id": "p-hidden"},
        {"booked_at": "2026-11-02T18:00:01+00:00"},
    ],
)
def test_same_id_different_field_is_conflict_and_row_unchanged(
    app, client, device_headers, seeded, change
):
    post(client, device_headers, item(B1))
    response = post(client, device_headers, item(B1, **change))
    assert statuses(response) == [("conflict", None)]
    with app.state.session_factory() as session:
        stored = session.get(Booking, B1)
        assert (stored.quantity, stored.unit_price_cents) == (1, 150)
        assert stored.person_id == "p-1"
        assert stored.drink_id == "d-1"
    assert count(app) == 1


def test_bad_item_does_not_drop_good_ones_and_order_is_kept(app, client, device_headers, seeded):
    response = post(client, device_headers, item(B1), item(B2, person_id="nobody"), item(B3))
    assert response.status_code == 200
    assert statuses(response) == [
        ("accepted", None),
        ("rejected", "unknown_person"),
        ("accepted", None),
    ]
    assert [r["id"] for r in response.json()["results"]] == [B1, B2, B3]
    assert count(app) == 2


def test_unknown_drink_is_rejected(client, device_headers, seeded):
    response = post(client, device_headers, item(drink_id="nope"))
    assert statuses(response) == [("rejected", "unknown_drink")]


def test_inactive_hidden_person_and_drink_are_accepted(app, client, device_headers, seeded):
    response = post(client, device_headers, item(person_id="p-hidden", drink_id="d-off"))
    assert statuses(response) == [("accepted", None)]


@pytest.mark.parametrize(
    ("overrides", "expected"),
    [
        ({"quantity": 0}, ("rejected", "invalid_quantity")),
        ({"quantity": -1}, ("rejected", "invalid_quantity")),
        ({"quantity": 1000}, ("rejected", "invalid_quantity")),
        ({"quantity": 999}, ("accepted", None)),
        ({"quantity": 1}, ("accepted", None)),
        ({"unit_price_cents": -1}, ("rejected", "invalid_price")),
        ({"unit_price_cents": 0}, ("accepted", None)),
        ({"booked_at": "2026-11-02T18:00:00"}, ("rejected", "invalid_booked_at")),
    ],
)
def test_item_validation(client, device_headers, seeded, overrides, expected):
    response = post(client, device_headers, item(**overrides))
    assert response.status_code == 200
    assert statuses(response) == [expected]


def test_all_rejected_still_200(app, client, device_headers, seeded):
    response = post(client, device_headers, item(quantity=0))
    assert response.status_code == 200
    assert count(app) == 0


def test_booked_at_before_period_start_is_late(app, client, device_headers, seeded):
    response = post(client, device_headers, item(booked_at="2020-01-01T00:00:00Z"))
    assert statuses(response) == [("accepted", None)]
    with app.state.session_factory() as session:
        assert session.get(Booking, B1).is_late is True


def test_booked_at_is_stored_normalized_to_utc(app, client, device_headers, seeded):
    post(client, device_headers, item(booked_at="2026-11-02T19:00:00+01:00"))
    with app.state.session_factory() as session:
        assert session.get(Booking, B1).booked_at == datetime(2026, 11, 2, 18, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    "payload",
    [
        {"bookings": []},
        {"bookings": [item(f"00000000-0000-4000-8000-{i:012d}") for i in range(201)]},
        {},
        {"bookings": [{"id": "not-a-uuid"}]},
        {"bookings": [item(quantity="many")]},
        {"bookings": [item(booked_at="yesterday")]},
    ],
)
def test_batch_shape_errors_are_422(client, device_headers, seeded, payload):
    assert client.post(URL, headers=device_headers, json=payload).status_code == 422


def test_200_items_are_allowed(app, client, device_headers, seeded):
    items = [item(f"00000000-0000-4000-8000-{i:012d}") for i in range(200)]
    assert post(client, device_headers, *items).status_code == 200
    assert count(app) == 200


@pytest.mark.parametrize(("quantity", "expected"), [(1, "duplicate"), (2, "conflict")])
def test_concurrent_insert_race_is_classified_from_stored_row(
    app, client, device_headers, seeded, monkeypatch, quantity, expected
):
    from bartab.api import routes_bookings

    post(client, device_headers, item(B1))
    real = routes_bookings.get_booking
    calls = iter([None])  # the pre-insert lookup misses, as if the other writer was not yet visible
    monkeypatch.setattr(
        routes_bookings,
        "get_booking",
        lambda session, booking_id: next(calls, "real") and real(session, booking_id),
    )
    response = post(client, device_headers, item(B1, quantity=quantity), item(B2))
    assert statuses(response) == [(expected, None), ("accepted", None)]
    assert count(app) == 2
