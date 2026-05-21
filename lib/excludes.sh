#!/usr/bin/env bash
set -euo pipefail

build_exclude_file() {
  local use_defaults="$1"
  local global_file="$2"
  local output_file="$3"
  shift 3

  : >"$output_file"

  if [[ "$use_defaults" == "true" ]]; then
    cat "$ROOT_DIR/config/excludes.default" >>"$output_file"
  fi

  if [[ -n "$global_file" && -r "$global_file" ]]; then
    cat "$global_file" >>"$output_file"
  fi

  local pattern
  for pattern in "$@"; do
    [[ -n "$pattern" ]] || continue
    printf '%s\n' "$pattern" >>"$output_file"
  done

  awk 'NF && $0 !~ /^#/ && !seen[$0]++ { print }' "$output_file" >"$output_file.tmp"
  mv "$output_file.tmp" "$output_file"
}
