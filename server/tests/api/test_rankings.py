from datetime import UTC, datetime

import pytest

from bartab.persistence.models import Booking, Drink, DrinkGroup, Period, Person, PriceTier

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)
CLOSED_AT = datetime(2026, 11, 2, 13, 0, tzinfo=UTC)
URL = "/api/v1/rankings"


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
                Person(id="p-2", name="Ben", price_tier_id="tier-a", **stamps),
                Drink(
                    id="d-1", name="Lager", group_id="g-1", crate_size=20, sort_order=1, **stamps
                ),
                Drink(id="d-2", name="Pils", group_id="g-1", crate_size=20, sort_order=2, **stamps),
            ]
        )
        session.commit()


def book(client, headers, n, person_id, drink_id, quantity=1):
    body = {
        "id": f"00000000-0000-4000-8000-{n:012d}",
        "person_id": person_id,
        "drink_id": drink_id,
        "quantity": quantity,
        "unit_price_cents": 150,
        "booked_at": "2026-11-02T18:00:00+00:00",
    }
    response = client.post("/api/v1/bookings", headers=headers, json={"bookings": [body]})
    assert response.json()["results"][0]["status"] == "accepted"


def test_requires_device_key(client, seeded):
    assert client.get(URL).status_code == 401


def test_empty_history_returns_empty_maps(client, device_headers, seeded):
    response = client.get(URL, headers=device_headers)
    assert response.status_code == 200
    assert response.json() == {"overall": {}, "persons": {}}


def test_counts_bookings_not_units(client, device_headers, seeded):
    book(client, device_headers, 1, "p-1", "d-1", quantity=24)
    for n in (2, 3, 4):
        book(client, device_headers, n, "p-1", "d-2")
    body = client.get(URL, headers=device_headers).json()
    assert body["persons"]["p-1"] == {"d-1": 1, "d-2": 3}
    assert body["overall"] == {"d-1": 1, "d-2": 3}


def test_overall_sums_all_persons(client, device_headers, seeded):
    book(client, device_headers, 1, "p-1", "d-1")
    book(client, device_headers, 2, "p-1", "d-1")
    book(client, device_headers, 3, "p-2", "d-1")
    book(client, device_headers, 4, "p-2", "d-2")
    body = client.get(URL, headers=device_headers).json()
    assert body["overall"] == {"d-1": 3, "d-2": 1}
    assert body["persons"]["p-2"] == {"d-1": 1, "d-2": 1}


def test_counts_closed_periods(app, client, device_headers, seeded):
    with app.state.session_factory() as session:
        stamps = {"created_at": NOW, "updated_at": NOW}
        session.add(Period(id="old", started_at=NOW, closed_at=CLOSED_AT, **stamps))
        session.flush()
        session.add(
            Booking(
                id="00000000-0000-4000-8000-0000000000aa",
                period_id="old",
                person_id="p-1",
                drink_id="d-2",
                quantity=1,
                unit_price_cents=150,
                booked_at=NOW,
                received_at=NOW,
                device_id="dev-x",
                is_late=False,
                **stamps,
            )
        )
        session.commit()
    book(client, device_headers, 1, "p-1", "d-2")
    body = client.get(URL, headers=device_headers).json()
    assert body["persons"]["p-1"]["d-2"] == 2
