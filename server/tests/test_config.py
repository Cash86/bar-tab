import pytest
from pydantic import ValidationError

from bartab.config import Settings


def _base_env(monkeypatch, tmp_path, **overrides):
    env = {
        "BARTAB_PUBLIC_URL": "http://localhost:8000",
        "BARTAB_DB_PATH": str(tmp_path / "db.sqlite"),
        "BARTAB_DATA_DIR": str(tmp_path),
        "BARTAB_SECRET_KEY": "s" * 32,
        "BARTAB_DEVICE_KEYS": "a" * 32,
    }
    env.update(overrides)
    for key, value in env.items():
        monkeypatch.setenv(key, value)


def test_device_keys_are_split_from_comma_separated_env(monkeypatch, tmp_path):
    _base_env(monkeypatch, tmp_path, BARTAB_DEVICE_KEYS="a" * 32 + "," + "b" * 32)
    assert Settings().device_keys == ["a" * 32, "b" * 32]


def test_defaults(monkeypatch, tmp_path):
    _base_env(monkeypatch, tmp_path)
    s = Settings()
    assert s.tz == "Europe/Berlin"
    assert s.monthly_report_day == 1
    assert s.monthly_report_time == "08:00"
    assert s.initial_admin_pin is None


def test_short_device_key_is_rejected(monkeypatch, tmp_path):
    _base_env(monkeypatch, tmp_path, BARTAB_DEVICE_KEYS="short")
    with pytest.raises(ValidationError):
        Settings()


def test_short_secret_key_is_rejected(monkeypatch, tmp_path):
    _base_env(monkeypatch, tmp_path, BARTAB_SECRET_KEY="short")
    with pytest.raises(ValidationError):
        Settings()


@pytest.mark.parametrize("pin", ["123", "123456789", "12ab"])
def test_invalid_admin_pin_is_rejected(monkeypatch, tmp_path, pin):
    _base_env(monkeypatch, tmp_path, BARTAB_INITIAL_ADMIN_PIN=pin)
    with pytest.raises(ValidationError):
        Settings()


def test_dotenv_file_comma_separated_device_keys(monkeypatch, tmp_path):
    for key in list(__import__("os").environ):
        if key.startswith("BARTAB_"):
            monkeypatch.delenv(key)
    env_file = tmp_path / ".env"
    env_file.write_text(
        "BARTAB_PUBLIC_URL=http://localhost:8000\n"
        f"BARTAB_DB_PATH={tmp_path}/db.sqlite\n"
        f"BARTAB_DATA_DIR={tmp_path}\n"
        f"BARTAB_SECRET_KEY={'s' * 32}\n"
        f"BARTAB_DEVICE_KEYS={'a' * 32},{'b' * 32}\n"
    )
    assert Settings(_env_file=env_file).device_keys == ["a" * 32, "b" * 32]


def test_env_example_placeholders_fail_validation(monkeypatch):
    from pathlib import Path

    for key in list(__import__("os").environ):
        if key.startswith("BARTAB_"):
            monkeypatch.delenv(key)
    example = Path(__file__).resolve().parents[2] / ".env.example"
    with pytest.raises(ValidationError) as exc:
        Settings(_env_file=example)
    failed = {err["loc"][0] for err in exc.value.errors()}
    assert {"secret_key", "device_keys", "initial_admin_pin"} <= failed


def test_env_example_with_valid_keys_loads(monkeypatch, tmp_path):
    """Guards the previous test: only the placeholders make .env.example fail."""
    from pathlib import Path

    for key in list(__import__("os").environ):
        if key.startswith("BARTAB_"):
            monkeypatch.delenv(key)
    example = Path(__file__).resolve().parents[2] / ".env.example"
    text = example.read_text().replace("<generate>", "x" * 32)
    text = text.replace("<choose 4-8 digits>", "4821")
    env_file = tmp_path / ".env"
    env_file.write_text(text)
    assert Settings(_env_file=env_file).device_keys == ["x" * 32]


@pytest.fixture
def ambient_env(monkeypatch, tmp_path_factory):
    env_dir = tmp_path_factory.mktemp("envdir")
    (env_dir / ".env").write_text("BARTAB_SMTP_HOST=leak.example\n")
    monkeypatch.setenv("BARTAB_TZ", "Mars/Base")
    monkeypatch.chdir(env_dir)


def test_settings_fixture_ignores_ambient_env_and_dotenv(ambient_env, settings):
    assert settings.tz == "Europe/Berlin"
    assert settings.smtp_host is None


@pytest.mark.parametrize("day", ["0", "29"])
def test_monthly_report_day_out_of_range_is_rejected(monkeypatch, tmp_path, day):
    _base_env(monkeypatch, tmp_path, BARTAB_MONTHLY_REPORT_DAY=day)
    with pytest.raises(ValidationError):
        Settings()


def test_monthly_report_day_28_is_accepted(monkeypatch, tmp_path):
    _base_env(monkeypatch, tmp_path, BARTAB_MONTHLY_REPORT_DAY="28")
    assert Settings().monthly_report_day == 28


@pytest.mark.parametrize("value", ["24:00", "8:00", "ab", "12:60"])
def test_monthly_report_time_invalid_is_rejected(monkeypatch, tmp_path, value):
    _base_env(monkeypatch, tmp_path, BARTAB_MONTHLY_REPORT_TIME=value)
    with pytest.raises(ValidationError):
        Settings()


def test_monthly_report_time_valid_is_accepted(monkeypatch, tmp_path):
    _base_env(monkeypatch, tmp_path, BARTAB_MONTHLY_REPORT_TIME="23:59")
    assert Settings().monthly_report_time == "23:59"
