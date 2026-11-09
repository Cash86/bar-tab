from datetime import UTC, datetime, timedelta

import pytest

from bartab.domain.clock import FixedClock
from bartab.persistence.db import Base, make_engine, make_session_factory
from bartab.persistence.models import PriceTier
from bartab.persistence.repos import ensure_open_period, get_setting
from bartab.persistence.settlement import (
    MONTHLY_REPORT_LAST_ATTEMPT_AT,
    MONTHLY_REPORT_SENT_MONTH,
    set_recipients,
)
from bartab.scheduler import run_monthly_report_once
from tests.fakes import FakeMailer

# 08:00 Europe/Berlin (CET) on 2026-11-01
DUE = datetime(2026, 11, 1, 7, 0, tzinfo=UTC)


@pytest.fixture
def session_factory(tmp_path):
    engine = make_engine(tmp_path / "sched.db")
    Base.metadata.create_all(engine)
    factory = make_session_factory(engine)
    yield factory
    engine.dispose()


@pytest.fixture
def mailer():
    return FakeMailer()


def prepare(session_factory, started: datetime, recipients=("a@example.org",)):
    with session_factory() as session:
        ensure_open_period(session, FixedClock(started))
        session.add(
            PriceTier(
                id="tier-a", name="Standard", sort_order=0, created_at=started, updated_at=started
            )
        )
        set_recipients(session, list(recipients))
        session.commit()


def read(session_factory, key):
    with session_factory() as session:
        return get_setting(session, key)


def test_sends_once_at_the_scheduled_local_time(session_factory, settings, mailer):
    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    early = FixedClock(DUE - timedelta(minutes=1))
    assert run_monthly_report_once(session_factory, settings, early, mailer) is False
    assert mailer.sent == []
    assert read(session_factory, MONTHLY_REPORT_LAST_ATTEMPT_AT) is None

    clock = FixedClock(DUE)
    assert run_monthly_report_once(session_factory, settings, clock, mailer) is True
    assert len(mailer.sent) == 1
    assert mailer.sent[0]["to"] == ["a@example.org"]
    assert mailer.sent[0]["subject"] == "bar-tab: Zwischenstand November 2026"
    assert read(session_factory, MONTHLY_REPORT_SENT_MONTH) == "2026-11"

    clock.advance(timedelta(hours=3))
    assert run_monthly_report_once(session_factory, settings, clock, mailer) is False
    assert len(mailer.sent) == 1


def test_restart_after_send_does_not_resend(session_factory, settings, mailer):
    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    assert run_monthly_report_once(session_factory, settings, FixedClock(DUE), mailer)
    later = FixedClock(DUE + timedelta(days=2))
    assert run_monthly_report_once(session_factory, settings, later, FakeMailer()) is False
    assert len(mailer.sent) == 1


def test_missed_time_sends_later_same_month(session_factory, settings, mailer):
    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    clock = FixedClock(datetime(2026, 11, 14, 12, 0, tzinfo=UTC))
    assert run_monthly_report_once(session_factory, settings, clock, mailer) is True
    assert read(session_factory, MONTHLY_REPORT_SENT_MONTH) == "2026-11"


def test_failure_retries_after_an_hour(session_factory, settings):
    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    failing = FakeMailer(fail=True)
    clock = FixedClock(DUE)
    assert run_monthly_report_once(session_factory, settings, clock, failing) is False
    assert read(session_factory, MONTHLY_REPORT_SENT_MONTH) is None
    assert read(session_factory, MONTHLY_REPORT_LAST_ATTEMPT_AT) == DUE.isoformat()

    clock.advance(timedelta(minutes=59))
    working = FakeMailer()
    assert run_monthly_report_once(session_factory, settings, clock, working) is False
    assert working.sent == []

    clock.advance(timedelta(minutes=1))
    assert run_monthly_report_once(session_factory, settings, clock, working) is True
    assert len(working.sent) == 1
    assert read(session_factory, MONTHLY_REPORT_SENT_MONTH) == "2026-11"


def test_mail_includes_overdue_line(session_factory, settings, mailer):
    prepare(session_factory, datetime(2026, 9, 1, tzinfo=UTC))
    assert run_monthly_report_once(session_factory, settings, FixedClock(DUE), mailer)
    assert "Inventur überfällig seit 31 Tagen" in mailer.sent[0]["body"]


def test_no_overdue_line_when_inventory_is_recent(session_factory, settings, mailer):
    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    assert run_monthly_report_once(session_factory, settings, FixedClock(DUE), mailer)
    assert "überfällig" not in mailer.sent[0]["body"]


def test_no_recipients_records_attempt_only(session_factory, settings, mailer):
    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC), recipients=())
    assert run_monthly_report_once(session_factory, settings, FixedClock(DUE), mailer) is False
    assert mailer.sent == []
    assert read(session_factory, MONTHLY_REPORT_LAST_ATTEMPT_AT) == DUE.isoformat()
    assert read(session_factory, MONTHLY_REPORT_SENT_MONTH) is None


def test_unconfigured_smtp_records_attempt_only(session_factory, settings):
    from bartab.mail import MailNotConfigured

    class Unconfigured:
        def send(self, *args, **kwargs):
            raise MailNotConfigured("no smtp")

    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    clock = FixedClock(DUE)
    assert run_monthly_report_once(session_factory, settings, clock, Unconfigured()) is False
    assert read(session_factory, MONTHLY_REPORT_LAST_ATTEMPT_AT) == DUE.isoformat()
    assert read(session_factory, MONTHLY_REPORT_SENT_MONTH) is None


def test_attempt_is_committed_before_sending(session_factory, settings):
    seen = []

    class Spy:
        def send(self, to, subject, body, attachment=None):
            seen.append(read(session_factory, MONTHLY_REPORT_LAST_ATTEMPT_AT))

    prepare(session_factory, datetime(2026, 10, 20, tzinfo=UTC))
    run_monthly_report_once(session_factory, settings, FixedClock(DUE), Spy())
    assert seen == [DUE.isoformat()]


def test_app_runs_the_loop_only_when_asked(settings, clock):
    from fastapi.testclient import TestClient

    from bartab.main import create_app

    engine = make_engine(settings.db_path)
    Base.metadata.create_all(engine)
    engine.dispose()
    with TestClient(create_app(settings, clock, FakeMailer())):
        pass  # starts and cancels the loop cleanly
