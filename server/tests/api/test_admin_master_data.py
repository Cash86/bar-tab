from datetime import UTC, datetime

import pytest

from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)
BASE = "/api/v1/admin"
STAMPS = {"created_at": NOW, "updated_at": NOW}


@pytest.fixture
def seeded(app):
    with app.state.session_factory() as session:
        session.add_all(
            [
                PriceTier(id="tier-a", name="Standard", sort_order=0, **STAMPS),
                PriceTier(id="tier-b", name="Member", sort_order=1, **STAMPS),
                DrinkGroup(id="g-1", name="Beer", sort_order=0, color="#112233", **STAMPS),
                DrinkGroup(id="g-2", name="Soft", sort_order=1, color="#445566", **STAMPS),
            ]
        )
        session.flush()
        session.add_all(
            [
                Person(id="p-1", name="Anna", price_tier_id="tier-a", **STAMPS),
                Drink(
                    id="d-1", name="Lager", group_id="g-1", crate_size=20, sort_order=0, **STAMPS
                ),
                Drink(id="d-2", name="Pils", group_id="g-1", crate_size=20, sort_order=1, **STAMPS),
            ]
        )
        session.flush()
        for drink_id in ("d-1", "d-2"):
            for tier_id in ("tier-a", "tier-b"):
                session.add(DrinkPrice(drink_id=drink_id, price_tier_id=tier_id, price_cents=250))
        session.commit()


@pytest.fixture
def admin(client, device_headers):
    response = client.post(f"{BASE}/session", json={"pin": "1234"}, headers=device_headers)
    return {**device_headers, "X-Admin-Token": response.json()["token"]}


def person_body(**over):
    return {
        "name": "Ben",
        "price_tier_id": "tier-a",
        "is_hidden": False,
        "is_collective": False,
        **over,
    }


def drink_body(**over):
    return {
        "name": "Cola",
        "group_id": "g-1",
        "crate_size": 12,
        "is_hidden": False,
        "prices": {"tier-a": 200, "tier-b": 150},
        **over,
    }


def test_create_person(client, admin, seeded):
    response = client.post(f"{BASE}/persons", json=person_body(), headers=admin)
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Ben"
    assert body["is_active"] is True
    assert body["price_tier_id"] == "tier-a"


def test_update_person(client, admin, seeded):
    body = person_body(name="Anne", price_tier_id="tier-b", is_active=False)
    response = client.put(f"{BASE}/persons/p-1", json=body, headers=admin)
    assert response.status_code == 200
    assert response.json() == {
        "id": "p-1",
        "name": "Anne",
        "price_tier_id": "tier-b",
        "is_hidden": False,
        "is_collective": False,
        "is_active": False,
    }


def test_update_unknown_person_is_404(client, admin, seeded):
    body = person_body(is_active=True)
    response = client.put(f"{BASE}/persons/nope", json=body, headers=admin)
    assert response.status_code == 404
    assert response.json()["detail"] == "not_found"


def test_create_drink(client, admin, seeded):
    response = client.post(f"{BASE}/drinks", json=drink_body(), headers=admin)
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Cola"
    assert body["prices"] == {"tier-a": 200, "tier-b": 150}
    assert body["sort_order"] == 2


def test_update_drink(client, admin, seeded):
    body = drink_body(name="Lager 0.5", group_id="g-2", is_active=False)
    response = client.put(f"{BASE}/drinks/d-1", json=body, headers=admin)
    assert response.status_code == 200
    out = response.json()
    assert out["id"] == "d-1"
    assert out["name"] == "Lager 0.5"
    assert out["group_id"] == "g-2"
    assert out["is_active"] is False
    assert out["prices"] == {"tier-a": 200, "tier-b": 150}


def test_create_group(client, admin, seeded):
    body = {"name": "Wine", "color": "#AABBCC"}
    response = client.post(f"{BASE}/groups", json=body, headers=admin)
    assert response.status_code == 201
    assert response.json()["color"] == "#AABBCC"
    assert response.json()["sort_order"] == 2


def test_update_group(client, admin, seeded):
    body = {"name": "Lager", "color": "#000000"}
    response = client.put(f"{BASE}/groups/g-1", json=body, headers=admin)
    assert response.status_code == 200
    assert response.json()["name"] == "Lager"


def test_delete_group(client, admin, seeded):
    response = client.delete(f"{BASE}/groups/g-2", headers=admin)
    assert response.status_code == 204


def test_delete_group_in_use_is_409(client, admin, seeded):
    response = client.delete(f"{BASE}/groups/g-1", headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "group_in_use"


def test_create_price_tier(client, admin, seeded):
    response = client.post(f"{BASE}/price-tiers", json={"name": "Guest"}, headers=admin)
    assert response.status_code == 201
    assert response.json()["name"] == "Guest"
    assert response.json()["sort_order"] == 2


def test_update_price_tier(client, admin, seeded):
    response = client.put(f"{BASE}/price-tiers/tier-b", json={"name": "Club"}, headers=admin)
    assert response.status_code == 200
    assert response.json()["name"] == "Club"


def test_delete_price_tier(client, admin, seeded):
    response = client.delete(f"{BASE}/price-tiers/tier-b", headers=admin)
    assert response.status_code == 204


def test_delete_price_tier_in_use_is_409(client, admin, seeded):
    response = client.delete(f"{BASE}/price-tiers/tier-a", headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "tier_in_use"


def test_reorder_groups(client, admin, seeded):
    response = client.put(f"{BASE}/order/groups", json={"ids": ["g-2", "g-1"]}, headers=admin)
    assert response.status_code == 204
    groups = client.get("/api/v1/catalog", headers=admin).json()["groups"]
    assert [g["id"] for g in groups] == ["g-2", "g-1"]


def test_reorder_price_tiers(client, admin, seeded):
    body = {"ids": ["tier-b", "tier-a"]}
    response = client.put(f"{BASE}/order/price-tiers", json=body, headers=admin)
    assert response.status_code == 204
    tiers = client.get("/api/v1/catalog", headers=admin).json()["price_tiers"]
    assert [t["id"] for t in tiers] == ["tier-b", "tier-a"]


def test_reorder_drinks(client, admin, seeded):
    response = client.put(f"{BASE}/order/drinks/g-1", json={"ids": ["d-2", "d-1"]}, headers=admin)
    assert response.status_code == 204
    drinks = client.get("/api/v1/catalog", headers=admin).json()["drinks"]
    assert [d["id"] for d in drinks] == ["d-2", "d-1"]


def test_reorder_mismatch_is_409(client, admin, seeded):
    response = client.put(f"{BASE}/order/groups", json={"ids": ["g-1"]}, headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "order_mismatch"


def test_reorder_drinks_unknown_group_is_404(client, admin, seeded):
    response = client.put(f"{BASE}/order/drinks/nope", json={"ids": []}, headers=admin)
    assert response.status_code == 404
    assert response.json()["detail"] == "not_found"


ROUTES = [
    ("post", "/persons", person_body()),
    ("put", "/persons/p-1", person_body(is_active=True)),
    ("post", "/drinks", drink_body()),
    ("put", "/drinks/d-1", drink_body(is_active=True)),
    ("post", "/groups", {"name": "X", "color": "#000000"}),
    ("put", "/groups/g-1", {"name": "X", "color": "#000000"}),
    ("delete", "/groups/g-1", None),
    ("post", "/price-tiers", {"name": "X"}),
    ("put", "/price-tiers/tier-a", {"name": "X"}),
    ("delete", "/price-tiers/tier-a", None),
    ("put", "/order/groups", {"ids": []}),
    ("put", "/order/price-tiers", {"ids": []}),
    ("put", "/order/drinks/g-1", {"ids": []}),
]


@pytest.mark.parametrize(("method", "path", "body"), ROUTES)
def test_master_data_requires_admin(client, device_headers, seeded, method, path, body):
    response = client.request(method, BASE + path, json=body, headers=device_headers)
    assert response.status_code == 401
    assert response.json()["detail"] == "admin_session_required"


def test_duplicate_name_is_409_name_taken(client, admin, seeded):
    response = client.post(f"{BASE}/persons", json=person_body(name=" anna "), headers=admin)
    assert response.status_code == 409
    assert response.json()["detail"] == "name_taken"


def test_overlong_drink_name_is_422_invalid_name(client, admin, seeded):
    response = client.post(f"{BASE}/drinks", json=drink_body(name="x" * 25), headers=admin)
    assert response.status_code == 422
    assert response.json()["detail"] == "invalid_name"


def test_unknown_reference_is_422(client, admin, seeded):
    body = person_body(price_tier_id="nope")
    response = client.post(f"{BASE}/persons", json=body, headers=admin)
    assert response.status_code == 422
    assert response.json()["detail"] == "unknown_reference"


def test_catalog_etag_changes_after_edit(client, admin, seeded):
    before = client.get("/api/v1/catalog", headers=admin).headers["ETag"]
    body = person_body(name="Anne", is_active=True)
    assert client.put(f"{BASE}/persons/p-1", json=body, headers=admin).status_code == 200
    after = client.get("/api/v1/catalog", headers=admin).headers["ETag"]
    assert before != after


def test_drink_with_stale_prices_is_422_prices_incomplete(client, admin, seeded):
    body = drink_body(prices={"tier-a": 200})
    response = client.post(f"{BASE}/drinks", json=body, headers=admin)
    assert response.status_code == 422
    assert response.json()["detail"] == "prices_incomplete"


def test_bad_colour_is_422(client, admin, seeded):
    body = {"name": "Wine", "color": "red"}
    response = client.post(f"{BASE}/groups", json=body, headers=admin)
    assert response.status_code == 422


def test_crate_size_zero_is_422(client, admin, seeded):
    response = client.post(f"{BASE}/drinks", json=drink_body(crate_size=0), headers=admin)
    assert response.status_code == 422
