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
def settings(tmp_path):
    return Settings(
        public_url="http://localhost:8000",
        db_path=tmp_path / "bartab.db",
        data_dir=tmp_path,
        secret_key="s" * 32,
        device_keys=DEVICE_KEYS,
        initial_admin_pin="1234",
    )


@pytest.fixture
def clock():
    return FixedClock(datetime(2026, 11, 2, 18, 0, tzinfo=UTC))


@pytest.fixture
def app(settings, clock):
    return create_app(settings, clock)


@pytest.fixture
def client(app):
    return TestClient(app)


@pytest.fixture
def device_headers():
    return {"Authorization": f"Bearer {DEVICE_KEYS[0]}"}


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
