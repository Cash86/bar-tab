import pytest

OPERATION_IDS = {
    "getHealth",
    "openAdminSession",
    "pingAdmin",
    "changeAdminPin",
    "closeAdminSession",
    "getCatalog",
    "postBookings",
    "getTabs",
    "getRankings",
    "listAdminBookings",
    "cancelBooking",
    "createDeliveries",
    "listDeliveries",
    "cancelDelivery",
    "createPerson",
    "updatePerson",
    "createDrink",
    "updateDrink",
    "createGroup",
    "updateGroup",
    "deleteGroup",
    "createPriceTier",
    "updatePriceTier",
    "deletePriceTier",
    "reorderGroups",
    "reorderPriceTiers",
    "reorderDrinks",
    "getStock",
    "reviewSettlement",
    "closeSettlement",
    "recordOpeningCount",
    "resendSettlement",
    "getSettings",
    "setRecipients",
    "setValuationTier",
}


@pytest.fixture
def spec(client):
    return client.get("/openapi.json").json()


def test_security_schemes_are_declared(spec):
    schemes = spec["components"]["securitySchemes"]
    assert schemes["deviceKey"] == {"type": "http", "scheme": "bearer"}
    assert schemes["adminToken"] == {"type": "apiKey", "in": "header", "name": "X-Admin-Token"}


def test_catalog_operation_is_client_ready(spec):
    op = spec["paths"]["/api/v1/catalog"]["get"]
    assert op["operationId"] == "getCatalog"
    assert op["security"] == [{"deviceKey": []}]
    assert "authorization" not in {p["name"].lower() for p in op.get("parameters", [])}


def test_admin_and_health_security(spec):
    paths = spec["paths"]
    assert paths["/api/v1/admin/ping"]["get"]["security"] == [{"deviceKey": [], "adminToken": []}]
    close = paths["/api/v1/admin/session"]["delete"]
    assert close["security"] == [{"deviceKey": [], "adminToken": []}]
    assert "security" not in paths["/api/v1/health"]["get"]
    for path in paths.values():
        for op in path.values():
            names = {p["name"].lower() for p in op.get("parameters", [])}
            assert not names & {"authorization", "x-admin-token"}


def test_admin_session_documents_errors(spec):
    responses = spec["paths"]["/api/v1/admin/session"]["post"]["responses"]
    ref = "#/components/schemas/"
    assert (
        responses["401"]["content"]["application/json"]["schema"]["$ref"] == ref + "ErrorResponse"
    )
    assert (
        responses["429"]["content"]["application/json"]["schema"]["$ref"] == ref + "LockedResponse"
    )


def test_every_device_operation_documents_401(spec):
    for path, item in spec["paths"].items():
        if path.endswith("/health"):
            continue
        assert "401" in item[next(iter(item))]["responses"], path


def test_catalog_documents_304_with_etag(spec):
    r304 = spec["paths"]["/api/v1/catalog"]["get"]["responses"]["304"]
    assert "ETag" in r304["headers"]
    assert "content" not in r304


def test_operation_ids(spec):
    ids = {op["operationId"] for item in spec["paths"].values() for op in item.values()}
    assert ids == OPERATION_IDS


def test_cancel_documents_404_and_409(spec):
    responses = spec["paths"]["/api/v1/admin/bookings/{booking_id}/cancel"]["post"]["responses"]
    ref = "#/components/schemas/ErrorResponse"
    for code in ("401", "404", "409"):
        assert responses[code]["content"]["application/json"]["schema"]["$ref"] == ref
