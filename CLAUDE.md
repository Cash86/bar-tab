# CLAUDE.md - project rules for agents

bar-tab is a monorepo: Flutter tablet app (`app/`) and Python FastAPI server (`server/`).
Design spec: `docs/superpowers/specs/2026-11-02-bar-tab-design.md` (read it before larger work).

## Language

- The repo is English: code, comments, docs, commit messages, identifiers.
- Chat with the maintainer is German.
- UI strings are German first, but live in Flutter l10n `.arb` files; never hard-code them.

## Working rules

- TDD: write the failing test first, see it fail for the right reason, then implement.
- Every acceptance criterion has a test that goes red when the behaviour breaks.
- Never weaken or delete an existing test to get green. Fix the code, or ask.
- Ambiguity: ask, do not invent behaviour. Record decisions in the spec.
- No secrets, real names, club names, addresses or real data in the repo. Demo data is
  invented. `.env`, `legacy/` and `.superpowers/` are git-ignored.
- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`).
  Commits written by Claude end with a blank line and a `Co-Authored-By:` trailer.
- Do not add features, abstractions or config beyond what the current task needs.

## Data rules

- IDs are UUID4 strings; entities have `created_at` / `updated_at` (UTC, timezone-aware).
- Money is integer cents everywhere. Never use floats for money.
- The unit price sent with a booking is final; the server never re-prices.
- No `datetime.now()` / `DateTime.now()` outside the clock wrapper. Take a `Clock`.
- Every schema change ships a migration and a test: Alembic on the server
  (`alembic upgrade head` on a fresh DB), Drift on the app.

## Server (`server/`)

- Layers: `bartab/domain` is pure (no I/O, no framework imports), `bartab/persistence`
  holds SQLAlchemy models and repositories, `bartab/api` holds FastAPI routes.
  Dependencies point inward: api -> persistence -> domain.
- Configuration only via `BARTAB_*` env vars (`bartab/config.py`); update `.env.example`
  whenever a setting is added.
- Run everything with `server/tool/test.sh [pytest args]` (pytest, `ruff check`,
  `ruff format --check` in Docker). Line length 100. Must be clean before commit.

## App (`app/`)

- Layers: `domain/` pure Dart, `data/` implements repositories, `presentation/` uses Riverpod.
- Models with `freezed`, local storage with Drift, mocks with `mocktail`.
- `flutter analyze` and `dart format` must be clean.
- Strings via `.arb` l10n files only (`app/lib/l10n/app_de.arb`).
- Run everything with `app/tool/check.sh` (pub get, build_runner, gen-l10n, analyze, format check,
  tests). Must be clean before commit. Generated files are not committed.
