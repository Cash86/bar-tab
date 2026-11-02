from datetime import timedelta

from bartab.persistence.repos import get_setting, set_setting
from bartab.security import hash_pin, seed_admin_pin, verify_pin

SESSION = "/api/v1/admin/session"
PING = "/api/v1/admin/ping"


def _login(client, headers, pin="1234"):
    return client.post(SESSION, json={"pin": pin}, headers=headers)


def test_health_needs_no_device_key(client):
    assert client.get("/api/v1/health").status_code == 200


def test_ping_without_device_key_is_401(client):
    r = client.get(PING)
    assert r.status_code == 401
    assert r.json() == {"detail": "invalid_device_key"}


def test_ping_with_unknown_device_key_is_401(client):
    r = client.get(PING, headers={"Authorization": "Bearer " + "z" * 32})
    assert r.status_code == 401
    assert r.json() == {"detail": "invalid_device_key"}


def test_ping_without_admin_token_is_401(client, device_headers):
    r = client.get(PING, headers=device_headers)
    assert r.status_code == 401
    assert r.json() == {"detail": "admin_session_required"}


def test_correct_pin_gives_token_that_opens_ping(client, device_headers):
    r = _login(client, device_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["expires_in"] == 900
    ping = client.get(PING, headers={**device_headers, "X-Admin-Token": body["token"]})
    assert ping.status_code == 204


def test_token_is_bound_to_its_device(client, device_headers, device_b_headers):
    token = _login(client, device_headers).json()["token"]
    r = client.get(PING, headers={**device_b_headers, "X-Admin-Token": token})
    assert r.status_code == 401
    assert r.json() == {"detail": "admin_session_required"}


def test_garbage_token_is_401(client, device_headers):
    r = client.get(PING, headers={**device_headers, "X-Admin-Token": "garbage"})
    assert r.status_code == 401
    assert r.json() == {"detail": "admin_session_required"}


def test_token_expires_after_900_seconds_of_injected_clock(client, clock, device_headers):
    token = _login(client, device_headers).json()["token"]
    headers = {**device_headers, "X-Admin-Token": token}
    clock.advance(timedelta(seconds=899))
    assert client.get(PING, headers=headers).status_code == 204
    clock.advance(timedelta(seconds=2))
    r = client.get(PING, headers=headers)
    assert r.status_code == 401
    assert r.json() == {"detail": "admin_session_required"}


def test_wrong_pin_is_401(client, device_headers):
    r = _login(client, device_headers, "0000")
    assert r.status_code == 401
    assert r.json() == {"detail": "wrong_pin"}


def test_five_wrong_pins_lock_the_device(client, clock, device_headers):
    for _ in range(5):
        assert _login(client, device_headers, "0000").status_code == 401
    r = _login(client, device_headers)
    assert r.status_code == 429
    assert r.json() == {"detail": "locked", "retry_after": 60}
    clock.advance(timedelta(seconds=61))
    assert _login(client, device_headers).status_code == 200


def test_lockout_is_per_device(client, device_headers, device_b_headers):
    for _ in range(5):
        _login(client, device_headers, "0000")
    assert _login(client, device_headers).status_code == 429
    assert _login(client, device_b_headers).status_code == 200


def test_successful_login_resets_failures(client, device_headers):
    for _ in range(4):
        _login(client, device_headers, "0000")
    assert _login(client, device_headers).status_code == 200
    for _ in range(4):
        assert _login(client, device_headers, "0000").status_code == 401


def test_hash_and_verify_pin():
    hashed = hash_pin("1234")
    assert hashed != "1234"
    assert verify_pin("1234", hashed)
    assert not verify_pin("4321", hashed)


def test_seed_admin_pin_does_not_overwrite_existing_hash(db_session, settings):
    set_setting(db_session, "admin_pin_hash", hash_pin("9999"))
    seed_admin_pin(db_session, settings)
    assert verify_pin("9999", get_setting(db_session, "admin_pin_hash"))


def test_seed_admin_pin_seeds_when_unset(db_session, settings):
    seed_admin_pin(db_session, settings)
    assert verify_pin("1234", get_setting(db_session, "admin_pin_hash"))


def test_seed_admin_pin_without_initial_pin_does_nothing(db_session, settings):
    settings.initial_admin_pin = None
    seed_admin_pin(db_session, settings)
    assert get_setting(db_session, "admin_pin_hash") is None


def test_concurrent_attempts_are_capped_before_verify(clock):
    import threading
    from concurrent.futures import ThreadPoolExecutor

    from bartab.security import LockedOut, PinLockout

    lockout = PinLockout(clock)
    barrier = threading.Barrier(20)
    reached_verify = []

    def attempt():
        barrier.wait()
        try:
            lockout.begin_attempt("dev")
        except LockedOut:
            return
        reached_verify.append(1)

    with ThreadPoolExecutor(20) as pool:
        for future in [pool.submit(attempt) for _ in range(20)]:
            future.result()
    assert len(reached_verify) == 5


def test_malformed_pin_is_422(client, device_headers):
    assert _login(client, device_headers, pin="12ab").status_code == 422


def test_malformed_pins_do_not_consume_lockout_attempts(client, device_headers):
    for _ in range(5):
        assert _login(client, device_headers, pin="12ab").status_code == 422
    assert _login(client, device_headers).status_code == 200
