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
assert_equals "forget --tag kind:db --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune" "$cmd"

printf 'ok - restic\n'
