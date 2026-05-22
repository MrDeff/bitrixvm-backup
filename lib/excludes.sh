#!/usr/bin/env bash
set -euo pipefail

build_exclude_file() {
  local use_defaults="$1"
  local global_file="$2"
  local output_file="$3"
  shift 3

  local output_dir
  output_dir="$(dirname "$output_file")"
  mkdir -p "$output_dir" || return 1

  local raw_file filtered_file
  raw_file="$(mktemp "$output_dir/excludes.raw.XXXXXX")" || return 1
  filtered_file="$(mktemp "$output_dir/excludes.filtered.XXXXXX")" || {
    rm -f "$raw_file"
    return 1
  }
  local status=0

  if [[ "$use_defaults" == "true" ]]; then
    cat "$ROOT_DIR/config/excludes.default" >>"$raw_file" || status=1
  fi

  if [[ "$status" -eq 0 && -n "$global_file" && -r "$global_file" ]]; then
    cat "$global_file" >>"$raw_file" || status=1
  fi

  local pattern
  if [[ "$status" -eq 0 ]]; then
    for pattern in "$@"; do
      [[ -n "$pattern" ]] || continue
      printf '%s\n' "$pattern" >>"$raw_file" || {
        status=1
        break
      }
    done
  fi

  if [[ "$status" -eq 0 ]]; then
    awk 'NF && $0 !~ /^[[:space:]]*#/ && !seen[$0]++ { print }' "$raw_file" >"$filtered_file" || status=1
  fi
  if [[ "$status" -eq 0 ]]; then
    mv "$filtered_file" "$output_file" || status=1
  fi

  rm -f "$raw_file" "$filtered_file"
  return "$status"
}
