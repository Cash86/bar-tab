from pathlib import Path

from bartab.cli import build_openapi_json

COMMITTED = Path(__file__).resolve().parents[2] / "api" / "openapi.json"


def test_committed_openapi_matches_app():
    assert COMMITTED.exists(), "api/openapi.json missing; run server/tool/export_openapi.py"
    assert build_openapi_json() == COMMITTED.read_text(
        encoding="utf-8"
    ), "api/openapi.json is out of date; run server/tool/export_openapi.py"
