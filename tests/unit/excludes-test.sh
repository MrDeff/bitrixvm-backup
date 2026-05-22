#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/excludes.sh"

WORK_DIR="$ROOT_DIR/.test-work/excludes"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

global_file="$WORK_DIR/global.exclude"
output_file="$WORK_DIR/merged.exclude"

printf '%s\n' "/upload/import" "  # ignored comment" "*.tmp" >"$global_file"
printf 'sentinel\n' >"$output_file.tmp"

build_exclude_file true "$global_file" "$output_file" "/local/cache" "*.log"

assert_contains "/bitrix/cache" "$output_file"
assert_contains "/upload/resize_cache" "$output_file"
assert_contains "/upload/import" "$output_file"
assert_contains "*.tmp" "$output_file"
assert_contains "/local/cache" "$output_file"
assert_contains "*.log" "$output_file"

if grep -F 'ignored comment' "$output_file" >/dev/null; then
  fail "indented comment was included in excludes"
fi

assert_contains "sentinel" "$output_file.tmp"

bad_root="$WORK_DIR/missing-root"
bad_output="$WORK_DIR/bad.exclude"
if ROOT_DIR="$bad_root" build_exclude_file true "" "$bad_output"; then
  fail "missing default excludes did not fail"
fi
[[ ! -f "$bad_output" ]] || fail "bad exclude output was created after failure"
[[ -z "$(trap -p RETURN)" ]] || fail "build_exclude_file left a RETURN trap installed after failure"

printf 'ok - excludes\n'
