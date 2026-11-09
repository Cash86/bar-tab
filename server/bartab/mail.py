import smtplib
from email.message import EmailMessage
from typing import Protocol

from bartab.config import Settings

_TIMEOUT_SECONDS = 20
_DEFAULT_PORT = 587
_SSL_PORT = 465


class MailError(Exception):
    """Sending a mail failed."""


class MailNotConfigured(MailError):
    """SMTP host or sender address is missing."""


class Mailer(Protocol):
    def send(
        self,
        to: list[str],
        subject: str,
        body: str,
        attachment: tuple[str, bytes] | None = None,
    ) -> None: ...


class SmtpMailer:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def send(
        self,
        to: list[str],
        subject: str,
        body: str,
        attachment: tuple[str, bytes] | None = None,
    ) -> None:
        s = self._settings
        if not s.smtp_host or not s.smtp_from:
            raise MailNotConfigured("SMTP host and sender address must be configured")
        message = EmailMessage()
        message["From"] = s.smtp_from
        message["To"] = ", ".join(to)
        message["Subject"] = subject
        message.set_content(body, charset="utf-8")
        if attachment is not None:
            filename, data = attachment
            message.add_attachment(data, maintype="application", subtype="pdf", filename=filename)
        port = s.smtp_port or _DEFAULT_PORT
        try:
            if port == _SSL_PORT:
                with smtplib.SMTP_SSL(s.smtp_host, port, timeout=_TIMEOUT_SECONDS) as smtp:
                    self._deliver(smtp, message)
            else:
                with smtplib.SMTP(s.smtp_host, port, timeout=_TIMEOUT_SECONDS) as smtp:
                    smtp.starttls()
                    self._deliver(smtp, message)
        except (smtplib.SMTPException, OSError) as exc:
            raise MailError(f"sending mail failed: {type(exc).__name__}") from exc

    def _deliver(self, smtp: smtplib.SMTP, message: EmailMessage) -> None:
        s = self._settings
        if s.smtp_user:
            smtp.login(s.smtp_user, s.smtp_password or "")
        smtp.send_message(message)
