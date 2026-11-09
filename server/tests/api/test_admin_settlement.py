from datetime import UTC, datetime

import pytest
from sqlalchemy import select

from bartab.domain.clock import FixedClock
from bartab.mail import SmtpMailer
from bartab.persistence import settlement as st
from bartab.persistence.models import Period, SettlementRecord
from tests.api.settlement_seed import COUNTS, book, counts_body, seed
from tests.fakes import FakeMailer

API = "/api/v1/admin"


@pytest.fixture
def clock():
    # 23:30 UTC is already the next day in Europe/Berlin
    return FixedClock(datetime(2026, 11, 2, 23, 30, tzinfo=UTC))


@pytest.fixture
def mailer(app):
    fake = FakeMailer()
    app.state.mailer = fake
    return fake


@pytest.fixture
def admin(client, device_headers):
    response = client.post(f"{API}/session", json={"pin": "1234"}, headers=device_headers)
    return {**device_headers, "X-Admin-Token": response.json()["token"]}


@pytest.fixture
def seeded(app, client):
    seed(app)


def recipients(client, admin, *addresses):
    r = client.put(
        f"{API}/settings/recipients", headers=admin, json={"recipients": list(addresses)}
    )
    assert r.status_code == 204, r.text


def review(client, admin, counts=COUNTS):
    return client.post(
        f"{API}/settlement/review", headers=admin, json={"counts": counts_body(counts)}
    )


def close(client, admin, token, counts=COUNTS):
    return client.post(
        f"{API}/settlement/close",
        headers=admin,
        json={"token": token, "counts": counts_body(counts)},
    )


def review_and_close(client, admin, counts=COUNTS):
    return close(client, admin, review(client, admin, counts).json()["token"], counts)


def periods(app):
    with app.state.session_factory() as session:
        return session.scalars(select(Period).order_by(Period.started_at, Period.closed_at)).all()


def record(app):
    with app.state.session_factory() as session:
        return session.scalars(select(SettlementRecord)).one()


def test_stock_lists_inactive_drink_with_stock(client, admin, seeded):
    response = client.get(f"{API}/stock", headers=admin)
    assert response.status_code == 200
    assert response.json() == {
        "opening_count_allowed": True,
        "drinks": [
            {
                "drink_id": "d3",
                "name": "Old",
                "group_id": "g1",
                "group_name": "Beer",
                "crate_size": 24,
                "expected": 4,
            },
            {
                "drink_id": "d1",
                "name": "Lager",
                "group_id": "g1",
                "group_name": "Beer",
                "crate_size": 20,
                "expected": 8,
            },
            {
                "drink_id": "d2",
                "name": "Cola",
                "group_id": "g2",
                "group_name": "Soft",
                "crate_size": 12,
                "expected": -1,
            },
        ],
    }


def test_review_totals(client, app, admin, seeded):
    response = review(client, admin)
    assert response.status_code == 200
    body = response.json()
    with app.state.session_factory() as session:
        assert body["token"] == st.review_token(st.review(session, app.state.clock, COUNTS))
    del body["token"]
    line = {"opening": 0}
    assert body == {
        "valuation_tier_name": "Member",
        "drinks": [
            {
                **line,
                "drink_id": "d3",
                "name": "Old",
                "group_id": "g1",
                "delivered": 4,
                "booked": 0,
                "expected": 4,
                "counted": 4,
                "shrinkage": 0,
                "value_cents": 0,
                "has_price": False,
            },
            {
                **line,
                "drink_id": "d1",
                "name": "Lager",
                "group_id": "g1",
                "delivered": 10,
                "booked": 2,
                "expected": 8,
                "counted": 7,
                "shrinkage": 1,
                "value_cents": 60,
                "has_price": True,
            },
            {
                **line,
                "drink_id": "d2",
                "name": "Cola",
                "group_id": "g2",
                "delivered": 0,
                "booked": 1,
                "expected": -1,
                "counted": 0,
                "shrinkage": -1,
                "value_cents": -100,
                "has_price": True,
            },
        ],
        "groups": [
            {
                **line,
                "group_id": "g1",
                "name": "Beer",
                "delivered": 14,
                "booked": 2,
                "expected": 12,
                "counted": 11,
                "shrinkage": 1,
                "value_cents": 60,
                "has_price": False,
            },
            {
                **line,
                "group_id": "g2",
                "name": "Soft",
                "delivered": 0,
                "booked": 1,
                "expected": -1,
                "counted": 0,
                "shrinkage": -1,
                "value_cents": -100,
                "has_price": True,
            },
        ],
        "persons_total_cents": 120,
        "hidden_total_cents": 100,
        "grand_total_cents": 220,
        "shrinkage_total_cents": -40,
    }
    assert len(periods(app)) == 1


@pytest.mark.parametrize(
    ("counts", "detail"),
    [
        ({"d1": 7, "d2": 0}, "missing_count"),
        ({**COUNTS, "nope": 1}, "unknown_reference"),
        ({**COUNTS, "d1": -1}, "invalid_quantity"),
        ({**COUNTS, "d1": 100000}, "invalid_quantity"),
    ],
)
def test_review_rejects_bad_counts(client, admin, seeded, counts, detail):
    response = review(client, admin, counts)
    assert (response.status_code, response.json()) == (422, {"detail": detail})


def test_review_accepts_the_quantity_bounds(client, admin, seeded):
    assert review(client, admin, {**COUNTS, "d1": 0}).status_code == 200
    assert review(client, admin, {**COUNTS, "d1": 99999}).status_code == 200


def test_review_rejects_a_drink_counted_twice(client, admin, seeded):
    counts = counts_body(COUNTS) + [{"drink_id": "d1", "quantity": 1}]
    response = client.post(f"{API}/settlement/review", headers=admin, json={"counts": counts})
    assert (response.status_code, response.json()) == (422, {"detail": "invalid_quantity"})


def test_close_sends_pdf_to_all_recipients(client, app, admin, seeded, mailer):
    recipients(client, admin, "a@example.org", "b@example.org")
    response = review_and_close(client, admin)
    assert response.status_code == 201
    closed = [p for p in periods(app) if p.closed_at is not None]
    assert len(closed) == 1
    assert response.json() == {
        "period_id": closed[0].id,
        "closed_at": "2026-11-02T23:30:00Z",
        "mail_status": "sent",
    }
    [mail] = mailer.sent
    assert mail["to"] == ["a@example.org", "b@example.org"]
    assert mail["subject"].startswith("bar-tab: Abrechnung")
    assert "Gesamt: 2,20 €" in mail["body"]
    filename, pdf = mail["attachment"]
    assert filename == "abrechnung-2026-11-03.pdf"  # local date of the period end
    assert pdf.startswith(b"%PDF")
    row = record(app)
    assert (row.mail_status, row.mail_error, row.mailed_at) == (
        "sent",
        None,
        datetime(2026, 11, 2, 23, 30, tzinfo=UTC),
    )


def test_close_with_failing_mail_still_closes(client, app, admin, seeded, mailer):
    recipients(client, admin, "a@example.org")
    mailer.fail = True
    response = review_and_close(client, admin)
    assert response.status_code == 201
    assert response.json()["mail_status"] == "failed"
    assert [p.closed_at is not None for p in periods(app)].count(True) == 1
    row = record(app)
    assert row.mail_status == "failed"
    assert row.mail_error == "fake mail failure"
    assert row.mailed_at is None


def test_failing_render_is_a_failed_mail(client, app, admin, seeded, mailer, monkeypatch):
    def broken(_s, _tz):
        raise RuntimeError("boom")

    monkeypatch.setattr("bartab.api.routes_admin_settlement.render_settlement_pdf", broken)
    recipients(client, admin, "a@example.org")
    response = review_and_close(client, admin)
    assert (response.status_code, response.json()["mail_status"]) == (201, "failed")
    assert [p.closed_at is not None for p in periods(app)].count(True) == 1
    assert record(app).mail_error == "render failed: RuntimeError"
    response = client.post(f"{API}/settlement/resend", headers=admin)
    assert (response.status_code, response.json()) == (200, {"mail_status": "failed"})
    assert mailer.sent == []


def test_mail_is_sent_after_the_close_is_committed(client, app, admin, seeded):
    seen = []

    class ReadingMailer(FakeMailer):
        def send(self, to, subject, body, attachment=None):
            # blocks for the busy timeout and fails if the close still held the write lock
            with app.state.session_factory() as session:
                seen.append(session.scalars(select(SettlementRecord.mail_status)).all())
                session.rollback()
            super().send(to, subject, body, attachment)

    app.state.mailer = ReadingMailer()
    recipients(client, admin, "a@example.org")
    assert review_and_close(client, admin).status_code == 201
    assert seen == [["pending"]]
    assert record(app).mail_status == "sent"


def test_close_replay_returns_200_and_sends_no_second_mail(client, app, admin, seeded, mailer):
    recipients(client, admin, "a@example.org")
    token = review(client, admin).json()["token"]
    first = close(client, admin, token)
    second = close(client, admin, token)
    assert (first.status_code, second.status_code) == (201, 200)
    assert second.json() == first.json()
    assert len(mailer.sent) == 1
    assert len(periods(app)) == 2


def test_close_with_stale_token_is_409(client, app, admin, seeded, mailer):
    recipients(client, admin, "a@example.org")
    token = review(client, admin).json()["token"]
    with app.state.session_factory() as session:
        book(session, app.state.clock, "b9", qty=1)
        session.commit()
    response = close(client, admin, token)
    assert (response.status_code, response.json()) == (409, {"detail": "stale_review"})
    assert len(periods(app)) == 1
    assert mailer.sent == []


def test_close_rejects_invalid_quantity(client, admin, seeded, mailer):
    response = close(client, admin, "token", {**COUNTS, "d1": -1})
    assert (response.status_code, response.json()) == (422, {"detail": "invalid_quantity"})


def test_close_without_recipients_is_skipped(client, app, admin, seeded, mailer):
    response = review_and_close(client, admin)
    assert response.status_code == 201
    assert response.json()["mail_status"] == "skipped"
    assert mailer.sent == []
    assert record(app).mail_status == "skipped"


def test_close_without_smtp_is_skipped(client, app, admin, seeded, settings):
    app.state.mailer = SmtpMailer(settings)  # no BARTAB_SMTP_HOST in the test settings
    recipients(client, admin, "a@example.org")
    response = review_and_close(client, admin)
    assert response.json()["mail_status"] == "skipped"
    assert record(app).mail_status == "skipped"


def test_opening_count_then_409_after_a_close(client, app, admin, seeded, mailer):
    url = f"{API}/opening-count"
    response = client.post(url, headers=admin, json={"counts": counts_body(COUNTS)})
    assert response.status_code == 204
    assert client.get(f"{API}/stock", headers=admin).json()["drinks"][1]["expected"] == 15
    counts = {"d1": 15, "d2": 0, "d3": 8}  # opening count + deliveries - bookings
    assert review_and_close(client, admin, counts).status_code == 201
    assert client.get(f"{API}/stock", headers=admin).json()["opening_count_allowed"] is False
    response = client.post(url, headers=admin, json={"counts": counts_body(counts)})
    assert (response.status_code, response.json()) == (409, {"detail": "already_settled"})


@pytest.mark.parametrize(
    ("counts", "detail"),
    [
        ({"d1": 7}, "missing_count"),
        ({**COUNTS, "nope": 1}, "unknown_reference"),
        ({**COUNTS, "d2": 100000}, "invalid_quantity"),
    ],
)
def test_opening_count_rejects_bad_counts(client, admin, seeded, counts, detail):
    response = client.post(
        f"{API}/opening-count", headers=admin, json={"counts": counts_body(counts)}
    )
    assert (response.status_code, response.json()) == (422, {"detail": detail})


def test_resend_after_a_failure_sets_sent(client, app, admin, seeded, mailer):
    recipients(client, admin, "a@example.org")
    mailer.fail = True
    review_and_close(client, admin)
    mailer.fail = False
    recipients(client, admin, "a@example.org", "c@example.org")
    response = client.post(f"{API}/settlement/resend", headers=admin)
    assert (response.status_code, response.json()) == (200, {"mail_status": "sent"})
    [mail] = mailer.sent
    assert mail["to"] == ["a@example.org", "c@example.org"]
    assert mail["attachment"][0] == "abrechnung-2026-11-03.pdf"
    row = record(app)
    assert (row.mail_status, row.mail_error) == ("sent", None)


def test_resend_failure_records_the_error(client, app, admin, seeded, mailer):
    recipients(client, admin, "a@example.org")
    review_and_close(client, admin)
    mailer.fail = True
    response = client.post(f"{API}/settlement/resend", headers=admin)
    assert response.json() == {"mail_status": "failed"}
    assert record(app).mail_error == "fake mail failure"


def test_resend_without_settlement_is_404(client, admin, seeded, mailer):
    response = client.post(f"{API}/settlement/resend", headers=admin)
    assert (response.status_code, response.json()) == (404, {"detail": "no_settlement"})


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/stock"),
        ("post", "/settlement/review"),
        ("post", "/settlement/close"),
        ("post", "/opening-count"),
        ("post", "/settlement/resend"),
        ("get", "/settings"),
        ("put", "/settings/recipients"),
        ("put", "/settings/valuation-tier"),
    ],
)
def test_every_route_needs_an_admin_session(client, device_headers, method, path):
    response = client.request(method, API + path, headers=device_headers, json={})
    assert (response.status_code, response.json()) == (401, {"detail": "admin_session_required"})
