from collections.abc import Iterator

from fastapi import Depends, HTTPException, Request
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from bartab.config import Settings
from bartab.domain.clock import Clock
from bartab.security import PinLockout, match_device_key, verify_admin_token

# auto_error=False: these only declare the schemes and read the credentials;
# every failure is raised below as the documented 401.
device_key_scheme = HTTPBearer(scheme_name="deviceKey", auto_error=False)
admin_token_scheme = APIKeyHeader(name="X-Admin-Token", scheme_name="adminToken", auto_error=False)


def get_session(request: Request) -> Iterator[Session]:
    session = request.app.state.session_factory()
    try:
        yield session
        session.commit()
    except BaseException:
        session.rollback()
        raise
    finally:
        session.close()


def get_clock(request: Request) -> Clock:
    return request.app.state.clock


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_lockout(request: Request) -> PinLockout:
    return request.app.state.lockout


def require_device(
    settings: Settings = Depends(get_settings),
    credentials: HTTPAuthorizationCredentials | None = Depends(device_key_scheme),
) -> str:
    device_id = (
        match_device_key(credentials.credentials, settings.device_keys) if credentials else None
    )
    if device_id is None:
        raise HTTPException(status_code=401, detail="invalid_device_key")
    return device_id


def require_admin(
    settings: Settings = Depends(get_settings),
    clock: Clock = Depends(get_clock),
    device_id: str = Depends(require_device),
    x_admin_token: str | None = Depends(admin_token_scheme),
) -> None:
    if not x_admin_token or not verify_admin_token(
        settings.secret_key, clock, x_admin_token, device_id
    ):
        raise HTTPException(status_code=401, detail="admin_session_required")
