from bartab.domain.clock import SystemClock
from bartab.main import app_from_env


def test_app_from_env_builds_app_from_environment(monkeypatch, tmp_path):
    monkeypatch.setenv("BARTAB_PUBLIC_URL", "http://localhost:8000")
    monkeypatch.setenv("BARTAB_DB_PATH", str(tmp_path / "bartab.db"))
    monkeypatch.setenv("BARTAB_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("BARTAB_DEVICE_KEYS", "k" * 32)

    app = app_from_env()

    assert app.state.settings.db_path == tmp_path / "bartab.db"
    assert app.state.settings.device_keys == ["k" * 32]
    assert isinstance(app.state.clock, SystemClock)
