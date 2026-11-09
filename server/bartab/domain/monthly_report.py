"""Pure scheduling rules for the monthly report mail and the overdue-inventory warning."""

import calendar
from datetime import date, datetime, timedelta

RETRY_INTERVAL = timedelta(hours=1)


def due_month(now_local: datetime, day: int, time_hhmm: str, sent_month: str | None) -> str | None:
    """Return "YYYY-MM" of the current month if its report is due and not yet sent."""
    hour, minute = (int(part) for part in time_hhmm.split(":"))
    scheduled = now_local.replace(day=day, hour=hour, minute=minute, second=0, microsecond=0)
    month = f"{now_local.year:04d}-{now_local.month:02d}"
    if now_local >= scheduled and sent_month != month:
        return month
    return None


def should_attempt(now: datetime, last_attempt_at: datetime | None) -> bool:
    """True if never attempted or at least RETRY_INTERVAL has passed since the last attempt."""
    return last_attempt_at is None or now - last_attempt_at >= RETRY_INTERVAL


def overdue_days(today: date, last_inventory: date) -> int | None:
    """Days past one calendar month after the last inventory, or None while not yet overdue."""
    total = last_inventory.year * 12 + (last_inventory.month - 1) + 1
    year, month = total // 12, total % 12 + 1
    day = min(last_inventory.day, calendar.monthrange(year, month)[1])
    deadline = date(year, month, day)
    if today <= deadline:
        return None
    return (today - deadline).days
