from datetime import UTC, datetime, timedelta

from bartab.domain.clock import FixedClock, SystemClock


def test_fixed_clock_advances():
    clock = FixedClock(datetime(2026, 11, 2, 18, 0, tzinfo=UTC))
    clock.advance(timedelta(minutes=5))
    assert clock.now() == datetime(2026, 11, 2, 18, 5, tzinfo=UTC)


def test_system_clock_is_utc_aware():
    assert SystemClock().now().utcoffset() == timedelta(0)
