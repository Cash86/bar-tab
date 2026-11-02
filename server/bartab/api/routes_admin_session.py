from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from bartab.api.deps import (
    get_clock,
    get_lockout,
    get_session,
    get_settings,
    require_admin,
    require_device,
)
from bartab.api.schemas import AdminSessionRequest, AdminSessionResponse
from bartab.config import Settings
from bartab.domain.clock import Clock
from bartab.persistence.repos import get_setting
from bartab.security import (
    ADMIN_PIN_HASH_KEY,
    ADMIN_TOKEN_MAX_AGE,
    LockedOut,
    PinLockout,
    issue_admin_token,
    verify_pin,
)

router = APIRouter()


@router.post("/admin/session", response_model=AdminSessionResponse)
def open_admin_session(
    body: AdminSessionRequest,
    device_id: str = Depends(require_device),
    settings: Settings = Depends(get_settings),
    clock: Clock = Depends(get_clock),
    lockout: PinLockout = Depends(get_lockout),
    session: Session = Depends(get_session),
) -> AdminSessionResponse | JSONResponse:
    try:
        lockout.check(device_id)
    except LockedOut as locked:
        return JSONResponse(
            status_code=429, content={"detail": "locked", "retry_after": locked.retry_after}
        )
    pin_hash = get_setting(session, ADMIN_PIN_HASH_KEY)
    if pin_hash is None or not verify_pin(body.pin, pin_hash):
        lockout.record_failure(device_id)
        raise HTTPException(status_code=401, detail="wrong_pin")
    lockout.reset(device_id)
    token = issue_admin_token(settings.secret_key, clock, device_id)
    return AdminSessionResponse(token=token, expires_in=ADMIN_TOKEN_MAX_AGE)


@router.get("/admin/ping", status_code=204, dependencies=[Depends(require_admin)])
def admin_ping() -> Response:
    return Response(status_code=204)
