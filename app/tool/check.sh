#!/usr/bin/env bash
# Full app check: deps, codegen, l10n, analyze, format, tests.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

dirs=()
for d in lib test test_e2e; do
  [ -d "$d" ] && dirs+=("$d")
done

flutter pub get
dart run build_runner build
flutter gen-l10n
flutter analyze
dart format --set-exit-if-changed "${dirs[@]}"
flutter test
