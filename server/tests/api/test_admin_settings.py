import pytest

from tests.api.settlement_seed import COUNTS, counts_body, seed
from tests.fakes import FakeMailer

API = "/api/v1/admin"


@pytest.fixture
def admin(client, device_headers):
    response = client.post(f"{API}/session", json={"pin": "1234"}, headers=device_headers)
    return {**device_headers, "X-Admin-Token": response.json()["token"]}


@pytest.fixture
def seeded(app, client):
    seed(app)


def settings_of(client, admin):
    response = client.get(f"{API}/settings", headers=admin)
    assert response.status_code == 200
    return response.json()


def put_recipients(client, admin, recipients):
    return client.put(f"{API}/settings/recipients", headers=admin, json={"recipients": recipients})


def put_tier(client, admin, tier_id):
    return client.put(f"{API}/settings/valuation-tier", headers=admin, json={"tier_id": tier_id})


def test_defaults(client, admin, seeded):
    assert settings_of(client, admin) == {
        "recipients": [],
        "valuation_tier_id": None,
        "effective_valuation_tier_id": "t1",
        "last_settlement": None,
    }


def test_recipients_drop_duplicates_and_keep_order(client, admin, seeded):
    response = put_recipients(client, admin, ["b@example.org", "a@example.org", "b@example.org"])
    assert response.status_code == 204
    assert settings_of(client, admin)["recipients"] == ["b@example.org", "a@example.org"]
    assert put_recipients(client, admin, []).status_code == 204
    assert settings_of(client, admin)["recipients"] == []


@pytest.mark.parametrize(
    "address", ["", "no-at.example.org", "a@b", "a b@example.org", "a@@example.org", "@x.org"]
)
def test_invalid_recipient_is_422_and_nothing_stored(client, admin, seeded, address):
    put_recipients(client, admin, ["ok@example.org"])
    response = put_recipients(client, admin, ["new@example.org", address])
    assert (response.status_code, response.json()) == (422, {"detail": "invalid_email"})
    assert settings_of(client, admin)["recipients"] == ["ok@example.org"]


def test_valuation_tier(client, admin, seeded):
    assert put_tier(client, admin, "t2").status_code == 204
    body = settings_of(client, admin)
    assert (body["valuation_tier_id"], body["effective_valuation_tier_id"]) == ("t2", "t2")
    review = client.post(
        f"{API}/settlement/review", headers=admin, json={"counts": counts_body(COUNTS)}
    )
    assert review.json()["valuation_tier_name"] == "Guest"


def test_unknown_valuation_tier_is_422(client, admin, seeded):
    response = put_tier(client, admin, "nope")
    assert (response.status_code, response.json()) == (422, {"detail": "unknown_reference"})
    assert settings_of(client, admin)["valuation_tier_id"] is None


def test_last_settlement(client, app, admin, seeded):
    app.state.mailer = FakeMailer(fail=True)
    put_recipients(client, admin, ["a@example.org"])
    token = client.post(
        f"{API}/settlement/review", headers=admin, json={"counts": counts_body(COUNTS)}
    ).json()["token"]
    closed = client.post(
        f"{API}/settlement/close",
        headers=admin,
        json={"token": token, "counts": counts_body(COUNTS)},
    ).json()
    assert settings_of(client, admin)["last_settlement"] == closed
    assert closed["mail_status"] == "failed"
