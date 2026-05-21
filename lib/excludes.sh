#!/usr/bin/env bash
set -euo pipefail

build_exclude_file() {
  local use_defaults="$1"
  local global_file="$2"
  local output_file="$3"
  shift 3

  local output_dir
  output_dir="$(dirname "$output_file")"
  mkdir -p "$output_dir"

  local raw_file filtered_file
  raw_file="$(mktemp "$output_dir/excludes.raw.XXXXXX")"
  filtered_file="$(mktemp "$output_dir/excludes.filtered.XXXXXX")"
  trap 'rm -f "$raw_file" "$filtered_file"' RETURN

  if [[ "$use_defaults" == "true" ]]; then
    cat "$ROOT_DIR/config/excludes.default" >>"$raw_file"
  fi

  if [[ -n "$global_file" && -r "$global_file" ]]; then
    cat "$global_file" >>"$raw_file"
  fi

  local pattern
  for pattern in "$@"; do
    [[ -n "$pattern" ]] || continue
    printf '%s\n' "$pattern" >>"$raw_file"
  done

  awk 'NF && $0 !~ /^[[:space:]]*#/ && !seen[$0]++ { print }' "$raw_file" >"$filtered_file"
  mv "$filtered_file" "$output_file"
}
