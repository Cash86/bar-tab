from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from bartab.persistence.db import Base, make_engine

SERVER_DIR = Path(__file__).resolve().parents[2]
ENTITY_TABLES = {
    "price_tiers",
    "persons",
    "drink_groups",
    "drinks",
    "drink_prices",
    "periods",
    "stock_entries",
    "bookings",
    "app_settings",
    "settlements",
}
NOW = datetime(2026, 1, 1, tzinfo=UTC).isoformat()


@pytest.fixture
def db_path(tmp_path: Path) -> Path:
    path = tmp_path / "migrated.db"
    config = Config(str(SERVER_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{path}")
    command.upgrade(config, "head")
    return path


def test_upgrade_head_creates_all_tables(db_path: Path) -> None:
    engine = create_engine(f"sqlite:///{db_path}")
    tables = set(inspect(engine).get_table_names()) - {"alembic_version"}
    assert tables == ENTITY_TABLES


# SQLite cannot reflect the expression-based partial index, so alembic skips it with a warning;
# test_second_open_period_is_rejected covers that index's behaviour.
@pytest.mark.filterwarnings("ignore:Skipped unsupported reflection of expression-based index")
@pytest.mark.filterwarnings("ignore:autogenerate skipping metadata-specified expression-based")
def test_models_match_migration(db_path: Path) -> None:
    engine = create_engine(f"sqlite:///{db_path}")
    with engine.connect() as connection:
        context = MigrationContext.configure(connection, opts={"compare_type": True})
        assert compare_metadata(context, Base.metadata) == []


def _insert_period(connection, period_id: str, closed_at: str | None) -> None:
    connection.execute(
        text(
            "INSERT INTO periods (id, started_at, closed_at, created_at, updated_at) "
            "VALUES (:id, :now, :closed, :now, :now)"
        ),
        {"id": period_id, "now": NOW, "closed": closed_at},
    )


def test_second_open_period_is_rejected(db_path: Path) -> None:
    engine = make_engine(db_path)
    with engine.begin() as connection:
        _insert_period(connection, "p1", None)
        _insert_period(connection, "p2", NOW)  # closed periods are unrestricted
    with pytest.raises(IntegrityError), engine.begin() as connection:
        _insert_period(connection, "p3", None)


def test_negative_price_is_rejected(db_path: Path) -> None:
    engine = make_engine(db_path)
    with engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO price_tiers (id, name, sort_order, created_at, updated_at) "
                "VALUES ('t1', 'Standard', 0, :now, :now)"
            ),
            {"now": NOW},
        )
        connection.execute(
            text(
                "INSERT INTO drink_groups (id, name, sort_order, color, created_at, updated_at) "
                "VALUES ('g1', 'Beer', 0, '#aabbcc', :now, :now)"
            ),
            {"now": NOW},
        )
        connection.execute(
            text(
                "INSERT INTO drinks (id, name, group_id, crate_size, sort_order, is_hidden, "
                "is_active, created_at, updated_at) "
                "VALUES ('d1', 'Pils', 'g1', 20, 0, 0, 1, :now, :now)"
            ),
            {"now": NOW},
        )
    with pytest.raises(IntegrityError), engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO drink_prices (drink_id, price_tier_id, price_cents) "
                "VALUES ('d1', 't1', -1)"
            )
        )


@pytest.mark.filterwarnings("ignore:Skipped unsupported reflection of expression-based index")
def test_downgrade_removes_storno_columns(db_path: Path) -> None:
    config = Config(str(SERVER_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{db_path}")
    command.downgrade(config, "0001")
    engine = create_engine(f"sqlite:///{db_path}")
    columns = {column["name"] for column in inspect(engine).get_columns("bookings")}
    assert "cancelled_at" not in columns
    assert "cancelled_by_device_id" not in columns


def test_upgrade_adds_stock_entry_storno_columns(db_path: Path) -> None:
    engine = create_engine(f"sqlite:///{db_path}")
    columns = {column["name"]: column for column in inspect(engine).get_columns("stock_entries")}
    assert columns["cancelled_at"]["nullable"]
    assert columns["cancelled_by_device_id"]["nullable"]


@pytest.mark.filterwarnings("ignore:Skipped unsupported reflection of expression-based index")
def test_downgrade_removes_stock_entry_storno_columns(db_path: Path) -> None:
    config = Config(str(SERVER_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{db_path}")
    command.downgrade(config, "0002")
    engine = create_engine(f"sqlite:///{db_path}")
    columns = {column["name"] for column in inspect(engine).get_columns("stock_entries")}
    assert "cancelled_at" not in columns
    assert "cancelled_by_device_id" not in columns


def test_settlement_mail_status_is_checked(db_path: Path) -> None:
    engine = make_engine(db_path)
    with engine.begin() as connection:
        _insert_period(connection, "p1", NOW)
    insert = text(
        "INSERT INTO settlements (id, period_id, token, figures_json, mail_status, created_at, "
        "updated_at) VALUES (:id, 'p1', :id, '{}', :status, :now, :now)"
    )
    with pytest.raises(IntegrityError), engine.begin() as connection:
        connection.execute(insert, {"id": "s0", "status": "lost", "now": NOW})
    with engine.begin() as connection:
        connection.execute(insert, {"id": "s1", "status": "pending", "now": NOW})
    with pytest.raises(IntegrityError), engine.begin() as connection:  # one per period
        connection.execute(insert, {"id": "s2", "status": "pending", "now": NOW})


@pytest.mark.filterwarnings("ignore:Skipped unsupported reflection of expression-based index")
def test_downgrade_removes_settlements(db_path: Path) -> None:
    config = Config(str(SERVER_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{db_path}")
    command.downgrade(config, "0003")
    engine = create_engine(f"sqlite:///{db_path}")
    assert "settlements" not in inspect(engine).get_table_names()


def test_upgrade_adds_drink_is_keg_defaulting_to_false(db_path: Path) -> None:
    columns = {
        c["name"]: c for c in inspect(create_engine(f"sqlite:///{db_path}")).get_columns("drinks")
    }
    assert not columns["is_keg"]["nullable"]


def test_existing_drinks_become_non_kegs(tmp_path: Path) -> None:
    path = tmp_path / "old.db"
    config = Config(str(SERVER_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{path}")
    command.upgrade(config, "0004")
    engine = create_engine(f"sqlite:///{path}")
    with engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO drink_groups (id, name, sort_order, color, created_at, updated_at) "
                f"VALUES ('g1', 'G', 0, '#112233', '{NOW}', '{NOW}')"
            )
        )
        connection.execute(
            text(
                "INSERT INTO drinks (id, name, group_id, crate_size, sort_order, is_hidden, "
                "is_active, created_at, updated_at) "
                f"VALUES ('d1', 'D', 'g1', 20, 0, 0, 1, '{NOW}', '{NOW}')"
            )
        )
    command.upgrade(config, "head")
    with engine.begin() as connection:
        assert connection.execute(text("SELECT is_keg FROM drinks")).scalar_one() == 0


@pytest.mark.filterwarnings("ignore:Skipped unsupported reflection of expression-based index")
def test_downgrade_removes_drink_is_keg(db_path: Path) -> None:
    config = Config(str(SERVER_DIR / "alembic.ini"))
    config.set_main_option("sqlalchemy.url", f"sqlite:///{db_path}")
    command.downgrade(config, "0004")
    columns = {
        c["name"] for c in inspect(create_engine(f"sqlite:///{db_path}")).get_columns("drinks")
    }
    assert "is_keg" not in columns
