import smtplib

import pytest

from bartab.config import Settings
from bartab.mail import MailError, MailNotConfigured, SmtpMailer
from bartab.main import create_app
from tests.fakes import FakeMailer


class FakeSMTP:
    instances: list["FakeSMTP"] = []
    fail = False

    def __init__(self, host, port, timeout=None, **kwargs):
        self.kind = type(self).__name__
        self.host, self.port, self.timeout = host, port, timeout
        self.calls: list[str] = []
        self.login_args = None
        self.messages = []
        FakeSMTP.instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def starttls(self, *a, **k):
        self.calls.append("starttls")

    def login(self, user, password):
        self.calls.append("login")
        self.login_args = (user, password)

    def send_message(self, msg):
        if FakeSMTP.fail:
            raise smtplib.SMTPException("boom")
        self.calls.append("send")
        self.messages.append(msg)


class FakeSMTP_SSL(FakeSMTP):
    pass


@pytest.fixture(autouse=True)
def fake_smtplib(monkeypatch):
    FakeSMTP.instances = []
    FakeSMTP.fail = False
    monkeypatch.setattr(smtplib, "SMTP", FakeSMTP)
    monkeypatch.setattr(smtplib, "SMTP_SSL", FakeSMTP_SSL)


def make_settings(tmp_path, **kw) -> Settings:
    base = dict(
        _env_file=None,
        public_url="http://localhost:8000",
        db_path=tmp_path / "b.db",
        data_dir=tmp_path,
        secret_key="s" * 32,
        device_keys=["k" * 32],
        smtp_host="smtp.example.test",
        smtp_from="bar@example.test",
    )
    base.update(kw)
    return Settings(**base)


def test_ssl_on_465(tmp_path):
    s = make_settings(tmp_path, smtp_port=465, smtp_user="u", smtp_password="p")
    SmtpMailer(s).send(["a@example.test"], "Hi", "Body")
    (smtp,) = FakeSMTP.instances
    assert smtp.kind == "FakeSMTP_SSL"
    assert smtp.port == 465
    assert smtp.timeout == 20
    assert "starttls" not in smtp.calls
    assert smtp.login_args == ("u", "p")
    assert smtp.calls[-1] == "send"


def test_starttls_otherwise(tmp_path):
    SmtpMailer(make_settings(tmp_path)).send(["a@example.test"], "Hi", "Body")
    (smtp,) = FakeSMTP.instances
    assert smtp.kind == "FakeSMTP"
    assert smtp.port == 587
    assert smtp.calls == ["starttls", "send"]  # no login without user


def test_message_headers_and_body(tmp_path):
    SmtpMailer(make_settings(tmp_path)).send(
        ["a@example.test", "b@example.test"], "Betreff", "Grüße"
    )
    msg = FakeSMTP.instances[0].messages[0]
    assert msg["From"] == "bar@example.test"
    assert msg["To"] == "a@example.test, b@example.test"
    assert msg["Subject"] == "Betreff"
    assert msg.get_content().strip() == "Grüße"


def test_attachment_is_pdf(tmp_path):
    SmtpMailer(make_settings(tmp_path)).send(
        ["a@example.test"], "S", "B", attachment=("abrechnung.pdf", b"%PDF-1.4 x")
    )
    msg = FakeSMTP.instances[0].messages[0]
    (att,) = list(msg.iter_attachments())
    assert att.get_content_type() == "application/pdf"
    assert att.get_filename() == "abrechnung.pdf"
    assert att.get_content() == b"%PDF-1.4 x"


@pytest.mark.parametrize("missing", ["smtp_host", "smtp_from"])
def test_not_configured_raises(tmp_path, missing):
    s = make_settings(tmp_path, **{missing: None})
    with pytest.raises(MailNotConfigured):
        SmtpMailer(s).send(["a@example.test"], "S", "B")
    assert FakeSMTP.instances == []


def test_smtp_error_becomes_mail_error(tmp_path):
    FakeSMTP.fail = True
    with pytest.raises(MailError):
        SmtpMailer(make_settings(tmp_path)).send(["a@example.test"], "S", "B")


def test_os_error_becomes_mail_error(tmp_path, monkeypatch):
    def refuse(*a, **k):
        raise ConnectionRefusedError("no")

    monkeypatch.setattr(smtplib, "SMTP", refuse)
    with pytest.raises(MailError):
        SmtpMailer(make_settings(tmp_path)).send(["a@example.test"], "S", "B")


def test_create_app_uses_injected_or_default_mailer(tmp_path):
    from bartab.domain.clock import SystemClock

    fake = FakeMailer()
    assert create_app(make_settings(tmp_path), SystemClock(), mailer=fake).state.mailer is fake
    assert isinstance(create_app(make_settings(tmp_path), SystemClock()).state.mailer, SmtpMailer)
