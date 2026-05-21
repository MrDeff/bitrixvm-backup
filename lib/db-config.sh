#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

db_config_json() {
  local site_root="$1"
  php "$ROOT_DIR/lib/db-config-reader.php" "$site_root"
}

db_config_field() {
  local site_root="$1"
  local field="$2"
  db_config_json "$site_root" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$field"
}
