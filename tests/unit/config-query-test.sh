#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/config-query"
mkdir -p "$WORK_DIR"
CONFIG="$WORK_DIR/sites.yml"

cat >"$CONFIG" <<'YAML'
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
sites:
  - code: example-com
    enabled: true
    path: /home/bitrix/ext_www/example.com
    repo: sftp:backup@example:/backups/example-com
    env_file: /etc/bitrix-backup/sites/example-com.env
    excludes:
      - /upload/import
      - "*.log"
  - code: disabled-site
    enabled: false
    path: /home/bitrix/ext_www/disabled.example
    repo: sftp:backup@example:/backups/disabled-site
YAML

enabled_codes="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" enabled-site-codes)"
[[ "$enabled_codes" == "example-com" ]] || fail "enabled-site-codes returned $enabled_codes"

site_json="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" site-json example-com)"
printf '%s\n' "$site_json" | grep '"code": "example-com"' >/dev/null || fail "site-json missing code"
printf '%s\n' "$site_json" | grep '"keep_daily": 3' >/dev/null || fail "site-json missing merged retention"

default_excludes="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" site-field example-com default_excludes)"
[[ "$default_excludes" == "true" ]] || fail "site-field default_excludes returned $default_excludes"

excludes="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" site-excludes example-com)"
printf '%s\n' "$excludes" | grep '^/upload/import$' >/dev/null || fail "missing /upload/import exclude"
printf '%s\n' "$excludes" | grep '^\*.log$' >/dev/null || fail "missing *.log exclude"

if python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" enabled-site-codes extra >/dev/null 2>&1; then
  fail "enabled-site-codes accepted an extra argument"
fi

bad_config="$WORK_DIR/bad.yml"
printf 'sites: [\n' >"$bad_config"
if python3 "$ROOT_DIR/lib/config-query.py" "$bad_config" enabled-site-codes >/dev/null 2>&1; then
  fail "invalid YAML was accepted"
fi

printf 'ok - config query\n'
