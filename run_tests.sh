#!/usr/bin/env bash
# run_tests.sh — T12 one-command GUT runner (per docs/ultron/research/r2-test-framework.md).
#
# Imports the project headless once (idempotent; REQUIRED after any addon/asset
# change — without it GUT errors "Some GUT class_names have not been imported"),
# then runs the full GUT suite from res://tests and propagates GUT's exit code:
# 0 = all tests passed, 1 = any failure.
#
# Collection guard (T12 finding, live-observed): GUT 9.7.1 exits 0 even when it
# collected nothing ("Nothing was run") or silently skipped an unloadable
# test_*.gd ("Ignoring script …"). A parse error or a -gdir typo must not
# green the gate, so the runner fails on those signatures explicitly.
#
# Legacy probes (tests/probe_*.gd) are plain --script SceneTree probes and stay
# runnable separately:
#   "$GODOT" --headless --path . -s res://tests/probe_content.gd   (etc.)
# GUT only discovers scripts with the test_ prefix, so the probes are not
# double-run here.
#
# Override the binary with GODOT=... if not using the Steam install.
set -euo pipefail

GODOT="${GODOT:-$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")"

echo "== import (headless, idempotent) =="
"$GODOT" --headless --path . --import

echo "== GUT suite (res://tests) =="
# -gexit is required or the process won't quit; GUT's exit code (0 pass / 1
# fail) propagates from the suite below.
LOG="$(mktemp "${TMPDIR:-/tmp}/t12_gut.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
set +e
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit -glog=1 2>&1 | tee "$LOG"
GUT_EXIT="${PIPESTATUS[0]}"
set -e

if grep -q "Nothing was run" "$LOG"; then
  echo "run_tests.sh: GUT collected no tests (parse error? wrong -gdir?) — failing the gate" >&2
  exit 1
fi
if grep -q "Ignoring script" "$LOG"; then
  echo "run_tests.sh: GUT skipped an unloadable test script — failing the gate" >&2
  exit 1
fi
exit "$GUT_EXIT"
