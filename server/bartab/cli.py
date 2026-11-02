import argparse
import json
import sys
import tempfile
from pathlib import Path

from bartab.config import Settings
from bartab.demo_data import seed_demo
from bartab.domain.clock import SystemClock
from bartab.main import create_app
from bartab.persistence.db import make_engine, make_session_factory


def build_openapi_json() -> str:
    """Renders the OpenAPI document without a real database or environment."""
    with tempfile.TemporaryDirectory() as tmp:
        settings = Settings(
            public_url="http://localhost:8000",
            db_path=Path(tmp) / "openapi.db",
            data_dir=Path(tmp),
            secret_key="x" * 32,
            device_keys=["d" * 32],
            _env_file=None,  # type: ignore[call-arg]
        )
        app = create_app(settings, SystemClock())
        spec = app.openapi()
        app.state.engine.dispose()
    return json.dumps(spec, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def _seed_demo() -> int:
    settings = Settings()  # type: ignore[call-arg]
    engine = make_engine(settings.db_path)
    try:
        with make_session_factory(engine)() as session:
            if not seed_demo(session, SystemClock()):
                print("database is not empty; demo data not seeded", file=sys.stderr)
                return 1
            session.commit()
    finally:
        engine.dispose()
    print("demo data seeded")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bartab.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("seed-demo", help="fill an empty, migrated database with demo data")
    export = sub.add_parser("export-openapi", help="write the OpenAPI document as JSON")
    export.add_argument("path", type=Path)
    args = parser.parse_args(argv)

    if args.command == "seed-demo":
        return _seed_demo()
    args.path.write_text(build_openapi_json(), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
