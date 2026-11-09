from datetime import UTC, date, datetime, timedelta, timezone

from bartab.domain.monthly_report import due_month, overdue_days, should_attempt

TZ = timezone(timedelta(hours=1))


def _at(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2026, 11, day, hour, minute, tzinfo=TZ)


def test_not_due_before_day_and_time():
    assert due_month(_at(1, 12), 2, "08:00", None) is None
    assert due_month(_at(2, 7, 59), 2, "08:00", None) is None


def test_due_at_time():
    assert due_month(_at(2, 8, 0), 2, "08:00", None) == "2026-11"
    assert due_month(_at(2, 8, 0), 2, "08:00", "2026-10") == "2026-11"


def test_not_due_when_sent_this_month():
    assert due_month(_at(5, 9), 2, "08:00", "2026-11") is None


def test_due_later_in_month_after_missed_time():
    assert due_month(_at(20, 23), 2, "08:00", None) == "2026-11"


def test_retry_after_one_hour_only():
    last = datetime(2026, 11, 2, 8, 0, tzinfo=UTC)
    assert should_attempt(last + timedelta(minutes=59), last) is False
    assert should_attempt(last + timedelta(hours=1), last) is True
    assert should_attempt(last, None) is True


def test_overdue_none_within_one_month():
    assert overdue_days(date(2026, 11, 1), date(2026, 10, 1)) is None


def test_overdue_counts_days_after_one_month():
    assert overdue_days(date(2026, 11, 11), date(2026, 10, 1)) == 10


def test_overdue_month_end_clamp():
    last = date(2026, 1, 31)
    assert overdue_days(date(2026, 2, 28), last) is None
    assert overdue_days(date(2026, 3, 1), last) == 1
