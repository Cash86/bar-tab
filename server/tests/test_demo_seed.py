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
