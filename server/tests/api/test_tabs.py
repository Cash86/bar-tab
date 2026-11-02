from datetime import UTC, datetime

import pytest

from bartab.persistence.models import Drink, DrinkGroup, Person, PriceTier

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)
URL = "/api/v1/tabs"


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
                Person(id="p-3", name="Cleo", price_tier_id="tier-a", **stamps),
                Drink(
                    id="d-1", name="Lager", group_id="g-1", crate_size=20, sort_order=1, **stamps
                ),
            ]
        )
        session.commit()


def book(client, headers, n, person_id, quantity, price):
    body = {
        "id": f"00000000-0000-4000-8000-{n:012d}",
        "person_id": person_id,
        "drink_id": "d-1",
        "quantity": quantity,
        "unit_price_cents": price,
        "booked_at": "2026-11-02T18:00:00+00:00",
    }
    response = client.post("/api/v1/bookings", headers=headers, json={"bookings": [body]})
    assert response.json()["results"][0]["status"] == "accepted"


def test_requires_device_key(client, seeded):
    assert client.get(URL).status_code == 401


def test_empty_period_returns_no_tabs(client, device_headers, seeded):
    response = client.get(URL, headers=device_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["tabs"] == {}
    assert body["period_started_at"] == "2026-11-02T18:00:00Z"


def test_totals_per_person_and_absent_without_bookings(client, device_headers, seeded):
    book(client, device_headers, 1, "p-1", 2, 150)
    book(client, device_headers, 2, "p-1", 1, 200)
    book(client, device_headers, 3, "p-2", 3, 100)
    body = client.get(URL, headers=device_headers).json()
    assert body["tabs"] == {"p-1": 500, "p-2": 300}
    assert "p-3" not in body["tabs"]
    assert body["period_started_at"] == "2026-11-02T18:00:00Z"
