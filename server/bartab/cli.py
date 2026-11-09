import argparse
import json
import sys
import tempfile
from pathlib import Path

from bartab.config import Settings
from bartab.demo_data import seed_demo
from bartab.domain.clock import SystemClock
from bartab.domain.legacy import (
    ImportPlan,
    LegacyError,
    build_plan,
    decode_legacy,
    parse_mapping,
)
from bartab.main import create_app
from bartab.persistence.db import make_engine, make_session_factory
from bartab.persistence.legacy_import import NotEmpty, apply_plan


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


def _print_plan(plan: ImportPlan) -> None:
    print("tiers:")
    for tier in plan.tiers:
        count = sum(1 for p in plan.persons if p.tier == tier)
        print(f"  {tier}: {count} persons")
    print("groups:")
    for group in plan.groups:
        count = sum(1 for d in plan.drinks if d.group == group)
        print(f"  {group}: {count} drinks")
    print(f"persons: {len(plan.persons)}, drinks: {len(plan.drinks)}")
    print("hidden persons: " + (", ".join(p.name for p in plan.persons if p.is_hidden) or "-"))
    print("collective: " + (", ".join(p.name for p in plan.persons if p.is_collective) or "-"))
    print("hidden drinks: " + (", ".join(d.name for d in plan.drinks if d.is_hidden) or "-"))
    print("kegs: " + (", ".join(d.name for d in plan.drinks if d.is_keg) or "-"))
    if plan.report:
        print("report:")
        for line in plan.report:
            print(f"  {line}")


def _import_legacy(users: Path, drinks: Path, mapping: Path, dry_run: bool) -> int:
    try:
        try:
            mapping_data = json.loads(mapping.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise LegacyError(f"cannot read the mapping file: {exc}") from exc
        try:
            users_text = decode_legacy(users.read_bytes())
            drinks_text = decode_legacy(drinks.read_bytes())
        except OSError as exc:
            raise LegacyError(f"cannot read input file: {exc}") from exc
        plan = build_plan(users_text, drinks_text, parse_mapping(mapping_data))
        _print_plan(plan)
        if dry_run:
            print("dry run: nothing written (database emptiness not checked)")
            return 0
        settings = Settings()  # type: ignore[call-arg]
        engine = make_engine(settings.db_path)
        try:
            with make_session_factory(engine)() as session:
                apply_plan(session, SystemClock(), plan)
                session.commit()
        finally:
            engine.dispose()
    except (LegacyError, NotEmpty) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("legacy data imported")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bartab.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("seed-demo", help="fill an empty, migrated database with demo data")
    export = sub.add_parser("export-openapi", help="write the OpenAPI document as JSON")
    export.add_argument("path", type=Path)
    legacy = sub.add_parser("import-legacy", help="import the legacy CSV files into an empty DB")
    legacy.add_argument("--users", type=Path, required=True)
    legacy.add_argument("--drinks", type=Path, required=True)
    legacy.add_argument("--mapping", type=Path, required=True)
    legacy.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    if args.command == "seed-demo":
        return _seed_demo()
    if args.command == "import-legacy":
        return _import_legacy(args.users, args.drinks, args.mapping, args.dry_run)
    args.path.write_text(build_openapi_json(), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
