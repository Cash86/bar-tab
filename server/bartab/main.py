import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI

from bartab.api import (
    routes_admin_bookings,
    routes_admin_deliveries,
    routes_admin_master_data,
    routes_admin_session,
    routes_admin_settings,
    routes_admin_settlement,
    routes_bookings,
    routes_catalog,
    routes_health,
    routes_rankings,
)
from bartab.config import Settings
from bartab.domain.clock import Clock, SystemClock
from bartab.mail import Mailer, SmtpMailer
from bartab.persistence.db import make_engine, make_session_factory
from bartab.persistence.repos import ensure_open_period
from bartab.scheduler import monthly_report_loop
from bartab.security import AdminSessions, PinLockout, seed_admin_pin


def _merge_security(app: FastAPI) -> None:
    """FastAPI lists each security dependency as an alternative; ours are all required."""
    original = app.openapi

    def openapi() -> dict[str, Any]:
        cached = app.openapi_schema is not None
        spec = original()
        if not cached:
            for item in spec["paths"].values():
                for op in item.values():
                    if len(op.get("security", [])) > 1:
                        merged: dict[str, list[str]] = {}
                        for requirement in op["security"]:
                            merged.update(requirement)
                        op["security"] = [merged]
        return spec

    app.openapi = openapi  # type: ignore[method-assign]


def create_app(
    settings: Settings,
    clock: Clock,
    mailer: Mailer | None = None,
    start_scheduler: bool = True,
) -> FastAPI:
    engine = make_engine(settings.db_path)
    session_factory = make_session_factory(engine)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        with session_factory() as session:
            seed_admin_pin(session, settings)
            ensure_open_period(session, clock)
            session.commit()
        task = None
        if start_scheduler:
            task = asyncio.create_task(
                monthly_report_loop(session_factory, settings, clock, app.state.mailer)
            )
        yield
        if task is not None:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        engine.dispose()

    app = FastAPI(
        title="bar-tab", lifespan=lifespan, generate_unique_id_function=lambda route: route.name
    )
    app.state.settings = settings
    app.state.clock = clock
    app.state.mailer = mailer if mailer is not None else SmtpMailer(settings)
    app.state.engine = engine
    app.state.session_factory = session_factory
    app.state.lockout = PinLockout(clock)
    app.state.admin_sessions = AdminSessions(clock)
    app.include_router(routes_health.router, prefix="/api/v1")
    app.include_router(routes_admin_session.router, prefix="/api/v1")
    app.include_router(routes_admin_bookings.router, prefix="/api/v1")
    app.include_router(routes_admin_deliveries.router, prefix="/api/v1")
    app.include_router(routes_admin_master_data.router, prefix="/api/v1")
    app.include_router(routes_admin_settlement.router, prefix="/api/v1")
    app.include_router(routes_admin_settings.router, prefix="/api/v1")
    app.include_router(routes_catalog.router, prefix="/api/v1")
    app.include_router(routes_bookings.router, prefix="/api/v1")
    app.include_router(routes_rankings.router, prefix="/api/v1")
    _merge_security(app)
    return app


def app_from_env() -> FastAPI:
    """Uvicorn factory: settings come from BARTAB_* environment variables."""
    return create_app(Settings(), SystemClock())
