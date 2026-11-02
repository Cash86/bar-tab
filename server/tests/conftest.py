from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from bartab.config import Settings
from bartab.domain.clock import FixedClock
from bartab.main import create_app

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
