#!/usr/bin/env bash
set -euo pipefail

bb_abspath() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    local dir
    dir="$(dirname "$path")"
    local base
    base="$(basename "$path")"
    local abs_dir
    abs_dir="$(cd "$dir" && pwd)" || return 1
    printf '%s/%s\n' "$abs_dir" "$base"
  fi
}

bb_require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    return 1
  }
}
