from fastapi import FastAPI

from bartab.api import routes_health
from bartab.config import Settings
from bartab.domain.clock import Clock


def create_app(settings: Settings, clock: Clock) -> FastAPI:
    app = FastAPI(title="bar-tab")
    app.state.settings = settings
    app.state.clock = clock
    app.include_router(routes_health.router, prefix="/api/v1")
    return app
