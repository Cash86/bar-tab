from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from bartab.api import routes_admin_session, routes_bookings, routes_catalog, routes_health
from bartab.config import Settings
from bartab.domain.clock import Clock, SystemClock
from bartab.persistence.db import make_engine, make_session_factory
from bartab.persistence.repos import ensure_open_period
from bartab.security import PinLockout, seed_admin_pin


def create_app(settings: Settings, clock: Clock) -> FastAPI:
    engine = make_engine(settings.db_path)
    session_factory = make_session_factory(engine)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        with session_factory() as session:
            seed_admin_pin(session, settings)
            ensure_open_period(session, clock)
            session.commit()
        yield
        engine.dispose()

    app = FastAPI(title="bar-tab", lifespan=lifespan)
    app.state.settings = settings
    app.state.clock = clock
    app.state.engine = engine
    app.state.session_factory = session_factory
    app.state.lockout = PinLockout(clock)
    app.include_router(routes_health.router, prefix="/api/v1")
    app.include_router(routes_admin_session.router, prefix="/api/v1")
    app.include_router(routes_catalog.router, prefix="/api/v1")
    app.include_router(routes_bookings.router, prefix="/api/v1")
    return app


def app_from_env() -> FastAPI:
    """Uvicorn factory: settings come from BARTAB_* environment variables."""
    return create_app(Settings(), SystemClock())
