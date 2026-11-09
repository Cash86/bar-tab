"""Monthly interim report: decides when it is due, sends it, retries failures hourly."""

import asyncio
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session, sessionmaker

from bartab.config import Settings
from bartab.domain.clock import Clock
from bartab.domain.monthly_report import due_month, overdue_days, should_attempt
from bartab.mail import Mailer, MailError
from bartab.persistence.repos import get_setting, set_setting
from bartab.persistence.settlement import (
    MONTHLY_REPORT_LAST_ATTEMPT_AT,
    MONTHLY_REPORT_SENT_MONTH,
    get_recipients,
    last_inventory_at,
    open_period_preview,
)
from bartab.reports.texts import month_label, monthly_mail

log = logging.getLogger(__name__)

CHECK_INTERVAL_SECONDS = 60


def run_monthly_report_once(
    session_factory: sessionmaker[Session], settings: Settings, clock: Clock, mailer: Mailer
) -> bool:
    """Send the interim report if it is due; return whether a mail was sent."""
    now = clock.now()
    local = now.astimezone(ZoneInfo(settings.tz))
    with session_factory() as session:
        sent_month = get_setting(session, MONTHLY_REPORT_SENT_MONTH)
        raw_attempt = get_setting(session, MONTHLY_REPORT_LAST_ATTEMPT_AT)
    month = due_month(local, settings.monthly_report_day, settings.monthly_report_time, sent_month)
    last_attempt = None if raw_attempt is None else datetime.fromisoformat(raw_attempt)
    if month is None or not should_attempt(now, last_attempt):
        return False

    with session_factory() as session:
        set_setting(session, MONTHLY_REPORT_LAST_ATTEMPT_AT, now.isoformat())
        session.commit()

    with session_factory() as session:
        recipients = get_recipients(session)
        if not recipients:
            return False
        preview = open_period_preview(session, clock)
        overdue = overdue_days(
            local.date(), last_inventory_at(session).astimezone(ZoneInfo(settings.tz)).date()
        )
    subject, body = monthly_mail(preview, overdue, month_label(local))
    try:
        mailer.send(recipients, subject, body)
    except MailError as error:
        log.warning("monthly report mail failed: %s", error)
        return False

    with session_factory() as session:
        set_setting(session, MONTHLY_REPORT_SENT_MONTH, month)
        session.commit()
    return True


async def monthly_report_loop(
    session_factory: sessionmaker[Session], settings: Settings, clock: Clock, mailer: Mailer
) -> None:
    while True:
        try:
            await asyncio.to_thread(
                run_monthly_report_once, session_factory, settings, clock, mailer
            )
        except Exception:
            log.exception("monthly report check failed")
        await asyncio.sleep(CHECK_INTERVAL_SECONDS)
