from datetime import UTC, datetime

import pytest

from bartab.persistence.models import Booking, Drink, DrinkGroup, Period, Person, PriceTier
from bartab.persistence.repos import ensure_open_period
from bartab.security import device_id_for_key
from tests.conftest import DEVICE_KEYS

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)
LIST_URL = "/api/v1/admin/bookings"


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
            ]
        )
        session.commit()


@pytest.fixture
def admin(client, device_headers):
    response = client.post("/api/v1/admin/session", json={"pin": "1234"}, headers=device_headers)
    return {**device_headers, "X-Admin-Token": response.json()["token"]}


def booking_body(n, person_id="p-1", quantity=2, price=250, booked_at="2026-11-02T18:00:00+00:00"):
    return {
        "id": f"00000000-0000-4000-8000-{n:012d}",
        "person_id": person_id,
        "drink_id": "d-1",
        "quantity": quantity,
        "unit_price_cents": price,
        "booked_at": booked_at,
    }


def book(client, headers, body):
    response = client.post("/api/v1/bookings", headers=headers, json={"bookings": [body]})
    return response.json()["results"][0]["status"]


def cancel_url(n):
    return f"{LIST_URL}/00000000-0000-4000-8000-{n:012d}/cancel"


def test_list_requires_admin_session(client, device_headers, seeded):
    response = client.get(LIST_URL, headers=device_headers)
    assert response.status_code == 401
    assert response.json()["detail"] == "admin_session_required"


def test_list_returns_open_period_newest_first(client, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1, booked_at="2026-11-02T17:00:00+00:00"))
    book(client, device_headers, booking_body(2, "p-2", 1, 300, "2026-11-02T18:00:00+00:00"))
    response = client.get(LIST_URL, headers=admin)
    assert response.status_code == 200
    rows = response.json()["bookings"]
    assert [r["id"][-1] for r in rows] == ["2", "1"]
    assert rows[0] == {
        "id": "00000000-0000-4000-8000-000000000002",
        "person_id": "p-2",
        "drink_id": "d-1",
        "quantity": 1,
        "unit_price_cents": 300,
        "booked_at": "2026-11-02T18:00:00Z",
        "is_late": False,
        "cancelled_at": None,
    }


def test_list_filters_by_person(client, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1))
    book(client, device_headers, booking_body(2, "p-2"))
    rows = client.get(LIST_URL, params={"person_id": "p-2"}, headers=admin).json()["bookings"]
    assert [r["person_id"] for r in rows] == ["p-2"]


def test_cancel_removes_booking_from_tabs(client, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1))
    response = client.post(cancel_url(1), headers=admin)
    assert response.status_code == 200
    assert response.json()["cancelled_at"] == "2026-11-02T18:00:00Z"
    assert "p-1" not in client.get("/api/v1/tabs", headers=device_headers).json()["tabs"]
    rows = client.get(LIST_URL, headers=admin).json()["bookings"]
    assert rows[0]["cancelled_at"] == "2026-11-02T18:00:00Z"


def test_cancel_removes_booking_from_rankings(client, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1))
    client.post(cancel_url(1), headers=admin)
    body = client.get("/api/v1/rankings", headers=device_headers).json()
    assert not body["overall"]
    assert not body["persons"]


def test_cancel_twice_is_409_already_cancelled(client, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1))
    assert client.post(cancel_url(1), headers=admin).status_code == 200
    response = client.post(cancel_url(1), headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "already_cancelled"


def test_cancel_unknown_is_404(client, admin, seeded):
    response = client.post(cancel_url(99), headers=admin)
    assert response.status_code == 404
    assert response.json()["detail"] == "booking_not_found"


def test_cancel_in_closed_period_is_409_period_closed(client, app, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1))
    with app.state.session_factory() as session:
        period = session.get(Period, session.get(Booking, booking_body(1)["id"]).period_id)
        period.closed_at = NOW
        session.flush()
        ensure_open_period(session, app.state.clock)
        session.commit()
    response = client.post(cancel_url(1), headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "period_closed"


def test_cancel_records_the_admin_device(client, app, device_headers, admin, seeded):
    book(client, device_headers, booking_body(1))
    client.post(cancel_url(1), headers=admin)
    with app.state.session_factory() as session:
        row = session.get(Booking, booking_body(1)["id"])
        assert row.cancelled_by_device_id == device_id_for_key(DEVICE_KEYS[0])


def test_reposting_a_cancelled_booking_stays_cancelled(client, device_headers, admin, seeded):
    body = booking_body(1)
    book(client, device_headers, body)
    client.post(cancel_url(1), headers=admin)
    assert book(client, device_headers, body) == "duplicate"
    assert "p-1" not in client.get("/api/v1/tabs", headers=device_headers).json()["tabs"]
