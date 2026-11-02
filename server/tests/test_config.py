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
