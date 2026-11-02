"""Writes the OpenAPI contract to <repo>/api/openapi.json."""

import sys
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

from bartab.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(["export-openapi", str(SERVER_DIR.parent / "api" / "openapi.json")]))
