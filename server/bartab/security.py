import hashlib
import hmac
import math
import threading
from datetime import datetime, timedelta

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from itsdangerous import BadSignature, TimestampSigner
from sqlalchemy.orm import Session

from bartab.config import Settings
from bartab.domain.clock import Clock
from bartab.persistence.repos import get_setting, set_setting

ADMIN_PIN_HASH_KEY = "admin_pin_hash"
ADMIN_TOKEN_MAX_AGE = 900

_hasher = PasswordHasher()


def hash_pin(pin: str) -> str:
    return _hasher.hash(pin)


def verify_pin(pin: str, hashed: str) -> bool:
    try:
        return _hasher.verify(hashed, pin)
    except (VerificationError, InvalidHashError):
        return False


def seed_admin_pin(session: Session, settings: Settings) -> None:
    """Stores the initial PIN hash when none exists; never overwrites."""
    if settings.initial_admin_pin and get_setting(session, ADMIN_PIN_HASH_KEY) is None:
        set_setting(session, ADMIN_PIN_HASH_KEY, hash_pin(settings.initial_admin_pin))


def device_id_for_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()[:8]


def match_device_key(candidate: str, device_keys: list[str]) -> str | None:
    """Returns the device id of the matching key, comparing every key in constant time."""
    matched: str | None = None
    for key in device_keys:
        if hmac.compare_digest(candidate.encode(), key.encode()):
            matched = device_id_for_key(key)
    return matched


class LockedOut(Exception):
    def __init__(self, retry_after: int) -> None:
        super().__init__("locked")
        self.retry_after = retry_after


class PinLockout:
    def __init__(self, clock: Clock, max_failures: int = 5, lock_seconds: int = 60) -> None:
        self._clock = clock
        self._max_failures = max_failures
        self._lock = timedelta(seconds=lock_seconds)
        self._failures: dict[str, int] = {}
        self._locked_until: dict[str, datetime] = {}
        self._mutex = threading.Lock()

    def begin_attempt(self, device_id: str) -> None:
        """Atomically reserves one attempt; call before the slow PIN verification.

        Raises LockedOut when the device is locked. The reservation counts as a failure
        until reset() is called on success, so parallel requests cannot exceed the limit.
        """
        with self._mutex:
            until = self._locked_until.get(device_id)
            if until is not None:
                remaining = (until - self._clock.now()).total_seconds()
                if remaining > 0:
                    raise LockedOut(math.ceil(remaining))
                self._failures.pop(device_id, None)
                del self._locked_until[device_id]
            count = self._failures.get(device_id, 0) + 1
            self._failures[device_id] = count
            if count >= self._max_failures:
                self._locked_until[device_id] = self._clock.now() + self._lock

    def reset(self, device_id: str) -> None:
        with self._mutex:
            self._failures.pop(device_id, None)
            self._locked_until.pop(device_id, None)


class ClockSigner(TimestampSigner):
    """TimestampSigner whose time source is the injected clock."""

    clock: Clock

    def get_timestamp(self) -> int:
        return int(self.clock.now().timestamp())


def _signer(secret_key: str, clock: Clock) -> ClockSigner:
    signer = ClockSigner(secret_key)
    signer.clock = clock
    return signer


def issue_admin_token(secret_key: str, clock: Clock, device_id: str) -> str:
    return _signer(secret_key, clock).sign(device_id).decode()


def verify_admin_token(secret_key: str, clock: Clock, token: str, device_id: str) -> bool:
    try:
        value = _signer(secret_key, clock).unsign(token, max_age=ADMIN_TOKEN_MAX_AGE)
    except BadSignature:
        return False
    return hmac.compare_digest(value, device_id.encode())
