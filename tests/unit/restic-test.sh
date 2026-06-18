#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/restic.sh"

assert_equals() {
  local expected="$1"
  local actual="$2"
  [[ "$actual" == "$expected" ]] || fail "expected '$expected', got '$actual'"
}

cmd="$(restic_forget_command "kind:db" 3 1 1)"
assert_equals "forget --tag kind:db --group-by tags --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune" "$cmd"

restic_base() {
  [[ "$1" == "repo" ]] || fail "unexpected repo: $1"
  shift
  assert_equals "forget --tag kind:db --group-by tags --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune" "$*"
}

restic_apply_retention "repo" "kind:db" 3 1 1

restic_base() {
  [[ "$1" == "repo" ]] || fail "unexpected repo: $1"
  shift
  [[ "$*" == "snapshots --json --tag kind:db" ]] || fail "unexpected restic args: $*"
  cat <<'JSON'
[
  {"id": "older-full-id", "short_id": "older", "time": "2026-05-20T00:00:00Z"},
  {"id": "newer-full-id", "short_id": "newer", "time": "2026-05-21T00:00:00Z"}
]
JSON
}

latest="$(restic_latest_snapshot_id "repo" "kind:db")"
assert_equals "newer-full-id" "$latest"

printf 'ok - restic\n'
