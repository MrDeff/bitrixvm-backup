#!/usr/bin/env bash
set -euo pipefail

config_query() {
  local config_path="$1"
  shift
  python3 "$ROOT_DIR/lib/config-query.py" "$config_path" "$@"
}

config_enabled_site_codes() {
  config_query "$1" enabled-site-codes
}

config_site_json() {
  config_query "$1" site-json "$2"
}

config_site_field() {
  config_query "$1" site-field "$2" "$3"
}

config_site_excludes() {
  config_query "$1" site-excludes "$2"
}
