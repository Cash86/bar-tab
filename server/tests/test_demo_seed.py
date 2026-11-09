import pytest
from sqlalchemy import func, select

from bartab import cli
from bartab.demo_data import seed_demo
from bartab.persistence.models import (
    Drink,
    DrinkGroup,
    DrinkPrice,
    Period,
    Person,
    PriceTier,
)


def _count(session, model):
    return session.scalar(select(func.count()).select_from(model))


def test_seed_creates_demo_data_and_open_period(db_session, clock):
    assert seed_demo(db_session, clock) is True
    db_session.commit()

    tiers = db_session.scalars(select(PriceTier.name)).all()
    assert sorted(tiers) == ["Gäste", "Mitglieder"]
    groups = {g.name: g.color for g in db_session.scalars(select(DrinkGroup))}
    assert groups == {
        "Bier": "#E3A33A",
        "Alkoholfrei": "#9CC46A",
        "Limo": "#C79BF0",
        "Wasser": "#72B8DE",
    }
    drinks = db_session.scalars(select(Drink)).all()
    assert 9 <= len(drinks) <= 11
    assert {d.crate_size for d in drinks} >= {20, 24, 12, 1}
    hidden = [d for d in drinks if d.is_hidden]
    assert len(hidden) == 1 and hidden[0].crate_size == 1
    assert _count(db_session, DrinkPrice) == len(drinks) * 2

    persons = db_session.scalars(select(Person)).all()
    assert 11 <= len(persons) <= 13
    assert [p.name for p in persons if p.is_collective] == ["Stammtisch"]
    assert [p.name for p in persons if p.is_hidden] == ["Veranstaltung"]
    assert any(ch in p.name for p in persons for ch in "äöüÄÖÜß")

    periods = db_session.scalars(select(Period)).all()
    assert len(periods) == 1 and periods[0].closed_at is None


def test_seed_refuses_non_empty_db(db_session, clock):
    assert seed_demo(db_session, clock) is True
    db_session.commit()
    before = (
        _count(db_session, Person),
        _count(db_session, Drink),
        _count(db_session, PriceTier),
        _count(db_session, DrinkGroup),
        _count(db_session, DrinkPrice),
    )

    assert seed_demo(db_session, clock) is False
    db_session.commit()

    after = (
        _count(db_session, Person),
        _count(db_session, Drink),
        _count(db_session, PriceTier),
        _count(db_session, DrinkGroup),
        _count(db_session, DrinkPrice),
    )
    assert after == before


def test_cli_seed_demo_exit_codes(settings, monkeypatch, capsys):
    from bartab.persistence.db import Base, make_engine

    engine = make_engine(settings.db_path)
    Base.metadata.create_all(engine)
    engine.dispose()
    for name, value in {
        "BARTAB_PUBLIC_URL": settings.public_url,
        "BARTAB_DB_PATH": str(settings.db_path),
        "BARTAB_DATA_DIR": str(settings.data_dir),
        "BARTAB_SECRET_KEY": settings.secret_key,
        "BARTAB_DEVICE_KEYS": ",".join(settings.device_keys),
    }.items():
        monkeypatch.setenv(name, value)

    assert cli.main(["seed-demo"]) == 0
    assert cli.main(["seed-demo"]) == 1
    assert "not empty" in capsys.readouterr().err


def test_cli_requires_subcommand():
    with pytest.raises(SystemExit):
        cli.main([])


def _cli_env(settings, monkeypatch):
    from bartab.persistence.db import Base, make_engine

    engine = make_engine(settings.db_path)
    Base.metadata.create_all(engine)
    engine.dispose()
    for name, value in {
        "BARTAB_PUBLIC_URL": settings.public_url,
        "BARTAB_DB_PATH": str(settings.db_path),
        "BARTAB_DATA_DIR": str(settings.data_dir),
        "BARTAB_SECRET_KEY": settings.secret_key,
        "BARTAB_DEVICE_KEYS": ",".join(settings.device_keys),
    }.items():
        monkeypatch.setenv(name, value)


def _legacy_files(tmp_path):
    import json

    from tests.domain.test_legacy import DRINKS, USERS, mapping_data

    users = tmp_path / "user.csv"
    drinks = tmp_path / "drink.csv"
    mapping = tmp_path / "mapping.json"
    users.write_bytes(USERS.encode("cp1252"))
    drinks.write_bytes(DRINKS.encode("cp1252"))
    mapping.write_text(json.dumps(mapping_data()), encoding="utf-8")
    return ["--users", str(users), "--drinks", str(drinks), "--mapping", str(mapping)]


def _db_counts(settings):
    from bartab.persistence.db import make_engine, make_session_factory

    engine = make_engine(settings.db_path)
    try:
        with make_session_factory(engine)() as session:
            return _count(session, Person), _count(session, Drink)
    finally:
        engine.dispose()


def test_cli_import_legacy_dry_run_writes_nothing(settings, monkeypatch, capsys, tmp_path):
    _cli_env(settings, monkeypatch)
    args = _legacy_files(tmp_path)
    assert cli.main(["import-legacy", *args, "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "Aktive: 2 persons" in out
    assert "Bier: 2 drinks" in out
    assert "Kasse Eins" in out
    assert "Geist Eins" in out
    assert "hidden drinks: Altes Zeug" in out
    assert "kegs: Fass Alpha" in out
    assert "placeholder price" in out
    assert "drink 'fass_a' renamed to 'Fass Alpha'" in out
    assert "database emptiness not checked" in out
    assert _db_counts(settings) == (0, 0)


def test_cli_import_legacy_writes_once(settings, monkeypatch, capsys, tmp_path):
    _cli_env(settings, monkeypatch)
    args = _legacy_files(tmp_path)
    assert cli.main(["import-legacy", *args]) == 0
    assert _db_counts(settings) == (4, 6)
    capsys.readouterr()
    assert cli.main(["import-legacy", *args]) == 1
    assert "not empty" in capsys.readouterr().err
    assert _db_counts(settings) == (4, 6)


def test_cli_import_legacy_error_exit_code(settings, monkeypatch, capsys, tmp_path):
    _cli_env(settings, monkeypatch)
    args = _legacy_files(tmp_path)
    (tmp_path / "user.csv").write_bytes(b"Name,Rolle\nKim,Chef\n")
    assert cli.main(["import-legacy", *args]) == 1
    assert "Chef" in capsys.readouterr().err
    assert _db_counts(settings) == (0, 0)


def test_cli_import_legacy_bad_mapping_json(settings, monkeypatch, capsys, tmp_path):
    _cli_env(settings, monkeypatch)
    args = _legacy_files(tmp_path)
    (tmp_path / "mapping.json").write_text("{nope", encoding="utf-8")
    assert cli.main(["import-legacy", *args]) == 1
    assert "mapping" in capsys.readouterr().err
