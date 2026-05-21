#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_file_executable() {
  local path="$1"
  [[ -x "$path" ]] || fail "$path is not executable"
}

assert_contains() {
  local needle="$1"
  local path="$2"
  grep -F -- "$needle" "$path" >/dev/null || fail "$path does not contain $needle"
}
