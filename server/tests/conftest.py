import os
from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from bartab.config import Settings
from bartab.domain.clock import FixedClock
from bartab.main import create_app
from bartab.persistence.db import Base, make_engine

DEVICE_KEYS = ["k" * 32, "l" * 32]


@pytest.fixture
def settings(tmp_path, monkeypatch):
    # independent of ambient BARTAB_* variables and of any .env file
    for name in [n for n in os.environ if n.startswith("BARTAB_")]:
        monkeypatch.delenv(name)
    return Settings(
        _env_file=None,
        public_url="http://localhost:8000",
        db_path=tmp_path / "bartab.db",
        data_dir=tmp_path,
        device_keys=DEVICE_KEYS,
        initial_admin_pin="1234",
    )


@pytest.fixture
def clock():
    return FixedClock(datetime(2026, 11, 2, 18, 0, tzinfo=UTC))


@pytest.fixture
def app(settings, clock):
    engine = make_engine(settings.db_path)
    Base.metadata.create_all(engine)
    engine.dispose()
    return create_app(settings, clock, start_scheduler=False)


@pytest.fixture
def client(app):
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def device_headers():
    return {"Authorization": f"Bearer {DEVICE_KEYS[0]}"}


@pytest.fixture
def device_b_headers():
    return {"Authorization": f"Bearer {DEVICE_KEYS[1]}"}


@pytest.fixture
def db_session(tmp_path):
    engine = make_engine(tmp_path / "test.db")
    Base.metadata.create_all(engine)
    session = Session(engine)
    try:
        yield session
    finally:
        session.close()
        engine.dispose()
