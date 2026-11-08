from datetime import UTC, datetime, timedelta

import pytest

from bartab.persistence.models import Drink, DrinkGroup, Period, PriceTier, StockEntry
from bartab.persistence.repos import ensure_open_period
from bartab.security import device_id_for_key
from tests.conftest import DEVICE_KEYS

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)
URL = "/api/v1/admin/deliveries"


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
        session.add(
            Drink(id="d-1", name="Lager", group_id="g-1", crate_size=20, sort_order=1, **stamps)
        )
        session.commit()


@pytest.fixture
def admin(client, device_headers):
    response = client.post("/api/v1/admin/session", json={"pin": "1234"}, headers=device_headers)
    return {**device_headers, "X-Admin-Token": response.json()["token"]}


def uid(n):
    return f"00000000-0000-4000-8000-{n:012d}"


def item(n, quantity=43, drink_id="d-1"):
    return {"id": uid(n), "drink_id": drink_id, "quantity": quantity}


def post(client, admin, *items):
    return client.post(URL, headers=admin, json={"deliveries": list(items)})


def cancel_url(n):
    return f"{URL}/{uid(n)}/cancel"


def stored(app):
    with app.state.session_factory() as session:
        return session.query(StockEntry).filter_by(kind="delivery").count()


def close_period(app):
    with app.state.session_factory() as session:
        for period in session.query(Period).all():
            period.closed_at = NOW
        session.flush()
        ensure_open_period(session, app.state.clock)
        session.commit()


def test_delivery_of_43_units_lands_in_open_period(client, app, admin, seeded):
    # 2 crates of 20 plus 3 single bottles, sent as one quantity
    response = post(client, admin, item(1, 43))
    assert response.status_code == 201
    [row] = response.json()["deliveries"]
    assert row == {
        "id": uid(1),
        "drink_id": "d-1",
        "quantity": 43,
        "created_at": "2026-11-02T18:00:00Z",
        "cancelled_at": None,
    }
    with app.state.session_factory() as session:
        entry = session.get(StockEntry, uid(1))
        period = session.get(Period, entry.period_id)
        assert (entry.kind, entry.quantity, period.closed_at) == ("delivery", 43, None)


def test_retried_delivery_batch_is_not_doubled(client, app, admin, seeded):
    first = post(client, admin, item(1), item(2, 5))
    second = post(client, admin, item(1), item(2, 5))
    assert (first.status_code, second.status_code) == (201, 201)
    assert second.json() == first.json()
    assert stored(app) == 2


def test_mixed_new_and_existing_stores_only_new(client, app, admin, seeded):
    post(client, admin, item(1))
    response = post(client, admin, item(1), item(2, 7))
    assert response.status_code == 201
    assert [r["id"] for r in response.json()["deliveries"]] == [uid(1), uid(2)]
    assert stored(app) == 2


def test_same_id_different_quantity_is_conflict(client, app, admin, seeded):
    post(client, admin, item(1, 10))
    response = post(client, admin, item(2, 3), item(1, 11))
    assert response.status_code == 409
    assert response.json()["detail"] == "delivery_conflict"
    assert stored(app) == 1


def test_unknown_drink_rejects_whole_batch(client, app, admin, seeded):
    response = post(client, admin, item(1), item(2, drink_id="nope"))
    assert response.status_code == 422
    assert response.json()["detail"] == "unknown_reference"
    assert stored(app) == 0


@pytest.mark.parametrize("quantity", [0, -1, 100_000])
def test_quantity_outside_range_rejects_whole_batch(client, app, admin, seeded, quantity):
    response = post(client, admin, item(1), item(2, quantity))
    assert response.status_code == 422
    assert response.json()["detail"] == "invalid_quantity"
    assert stored(app) == 0


def test_quantity_limits_are_accepted(client, admin, seeded):
    assert post(client, admin, item(1, 1), item(2, 99_999)).status_code == 201


def test_list_shows_only_open_period_deliveries_newest_first(client, app, admin, seeded):
    post(client, admin, item(1))
    with app.state.session_factory() as session:
        session.add(
            StockEntry(
                id=uid(9),
                period_id=session.query(Period).one().id,
                drink_id="d-1",
                kind="opening",
                quantity=5,
                created_at=NOW,
                updated_at=NOW,
            )
        )
        session.commit()
    close_period(app)
    app.state.clock.advance(timedelta(minutes=1))
    post(client, admin, item(2, 4))
    app.state.clock.advance(timedelta(minutes=1))
    post(client, admin, item(3, 6))
    rows = client.get(URL, headers=admin).json()["deliveries"]
    assert [r["id"] for r in rows] == [uid(3), uid(2)]


def test_cancel_delivery_records_device_and_time(client, app, admin, seeded):
    post(client, admin, item(1))
    app.state.clock.advance(timedelta(minutes=1))
    response = client.post(cancel_url(1), headers=admin)
    assert response.status_code == 200
    assert response.json()["cancelled_at"] == "2026-11-02T18:01:00Z"
    with app.state.session_factory() as session:
        row = session.get(StockEntry, uid(1))
        assert row.cancelled_by_device_id == device_id_for_key(DEVICE_KEYS[0])
    listed = client.get(URL, headers=admin).json()["deliveries"]
    assert listed[0]["cancelled_at"] == "2026-11-02T18:01:00Z"


def test_cancel_twice_is_409_already_cancelled(client, admin, seeded):
    post(client, admin, item(1))
    client.post(cancel_url(1), headers=admin)
    response = client.post(cancel_url(1), headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "already_cancelled"


def test_cancel_in_closed_period_is_409(client, app, admin, seeded):
    post(client, admin, item(1))
    close_period(app)
    response = client.post(cancel_url(1), headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "period_closed"


def test_cancel_unknown_or_non_delivery_is_404(client, app, admin, seeded):
    with app.state.session_factory() as session:
        session.add(
            StockEntry(
                id=uid(9),
                period_id=ensure_open_period(session, app.state.clock).id,
                drink_id="d-1",
                kind="count",
                quantity=5,
                created_at=NOW,
                updated_at=NOW,
            )
        )
        session.commit()
    for n in (8, 9):
        response = client.post(cancel_url(n), headers=admin)
        assert response.status_code == 404
        assert response.json()["detail"] == "not_found"


def test_deliveries_require_admin(client, device_headers, seeded):
    body = {"deliveries": [item(1)]}
    for response in (
        client.get(URL, headers=device_headers),
        client.post(URL, headers=device_headers, json=body),
        client.post(cancel_url(1), headers=device_headers),
    ):
        assert response.status_code == 401
        assert response.json()["detail"] == "admin_session_required"
