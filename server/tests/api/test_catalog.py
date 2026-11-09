from datetime import UTC, datetime

import pytest

from bartab.persistence.models import Drink, DrinkGroup, DrinkPrice, Person, PriceTier

NOW = datetime(2026, 11, 2, 12, 0, tzinfo=UTC)


@pytest.fixture
def seeded(app):
    with app.state.session_factory() as session:
        stamps = {"created_at": NOW, "updated_at": NOW}
        session.add_all(
            [
                PriceTier(id="tier-a", name="Standard", sort_order=1, **stamps),
                PriceTier(id="tier-b", name="Reduced", sort_order=2, **stamps),
                DrinkGroup(id="g-1", name="Beer", sort_order=1, color="#112233", **stamps),
            ]
        )
        session.flush()
        session.add_all(
            [
                Person(id="p-1", name="Rüdiger", price_tier_id="tier-a", **stamps),
                Person(id="p-2", name="Faßbrause", price_tier_id="tier-b", **stamps),
                Drink(
                    id="d-1", name="Lager", group_id="g-1", crate_size=20, sort_order=1, **stamps
                ),
            ]
        )
        session.flush()
        session.add_all(
            [
                DrinkPrice(drink_id="d-1", price_tier_id="tier-a", price_cents=150),
                DrinkPrice(drink_id="d-1", price_tier_id="tier-b", price_cents=120),
            ]
        )
        session.commit()


def test_requires_device_key(client):
    assert client.get("/api/v1/catalog").status_code == 401


def test_returns_seeded_catalog(client, device_headers, seeded):
    response = client.get("/api/v1/catalog", headers=device_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["price_tiers"] == [
        {"id": "tier-a", "name": "Standard", "sort_order": 1},
        {"id": "tier-b", "name": "Reduced", "sort_order": 2},
    ]
    assert body["groups"] == [{"id": "g-1", "name": "Beer", "sort_order": 1, "color": "#112233"}]
    assert body["drinks"] == [
        {
            "id": "d-1",
            "name": "Lager",
            "group_id": "g-1",
            "crate_size": 20,
            "sort_order": 1,
            "is_hidden": False,
            "is_active": True,
            "is_keg": False,
            "prices": {"tier-a": 150, "tier-b": 120},
        }
    ]
    assert {p["name"] for p in body["persons"]} == {"Rüdiger", "Faßbrause"}
    person = next(p for p in body["persons"] if p["id"] == "p-1")
    assert person == {
        "id": "p-1",
        "name": "Rüdiger",
        "price_tier_id": "tier-a",
        "is_hidden": False,
        "is_collective": False,
        "is_active": True,
    }


def test_umlauts_are_sent_as_utf8(client, device_headers, seeded):
    response = client.get("/api/v1/catalog", headers=device_headers)
    assert response.headers["content-type"].startswith("application/json")
    assert "Rüdiger".encode() in response.content
    assert "Faßbrause".encode() in response.content


def test_etag_header_matches_body_and_is_quoted(client, device_headers, seeded):
    response = client.get("/api/v1/catalog", headers=device_headers)
    etag = response.json()["etag"]
    assert len(etag) == 64
    assert response.headers["etag"] == f'"{etag}"'


def test_if_none_match_gives_304_until_catalog_changes(app, client, device_headers, seeded):
    first = client.get("/api/v1/catalog", headers=device_headers)
    etag = first.json()["etag"]
    for value in (f'"{etag}"', etag):
        cached = client.get("/api/v1/catalog", headers={**device_headers, "If-None-Match": value})
        assert cached.status_code == 304
        assert cached.content == b""
        assert cached.headers["etag"] == f'"{etag}"'

    with app.state.session_factory() as session:
        session.get(Drink, "d-1").name = "Pils"
        session.commit()
    changed = client.get(
        "/api/v1/catalog", headers={**device_headers, "If-None-Match": f'"{etag}"'}
    )
    assert changed.status_code == 200
    assert changed.json()["etag"] != etag


def test_catalog_schema_in_openapi(client):
    schema = client.get("/openapi.json").json()
    assert "CatalogResponse" in schema["components"]["schemas"]
