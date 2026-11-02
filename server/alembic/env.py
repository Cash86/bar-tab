from logging.config import fileConfig

from sqlalchemy import create_engine

from alembic import context
from bartab.config import Settings
from bartab.persistence import models  # noqa: F401  (registers tables on Base.metadata)
from bartab.persistence.db import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)


def _url() -> str:
    return config.get_main_option("sqlalchemy.url") or f"sqlite:///{Settings().db_path}"


def run_migrations_offline() -> None:
    context.configure(url=_url(), target_metadata=Base.metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    engine = create_engine(_url())
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=Base.metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
