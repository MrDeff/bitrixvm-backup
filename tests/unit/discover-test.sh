#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/discover"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/home/bitrix/www" "$WORK_DIR/home/bitrix/ext_www/example.com" "$WORK_DIR/home/bitrix/ext_www/site #1"

cp -R "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix" "$WORK_DIR/home/bitrix/www/"
cp -R "$ROOT_DIR/tests/fixtures/bitrix-dbconn-site/bitrix" "$WORK_DIR/home/bitrix/ext_www/example.com/"
cp -R "$ROOT_DIR/tests/fixtures/bitrix-dbconn-site/bitrix" "$WORK_DIR/home/bitrix/ext_www/site #1/"

OUTPUT="$WORK_DIR/sites.yml"
"$ROOT_DIR/bin/bitrix-backup-discover" \
  --root "$WORK_DIR/home/bitrix" \
  --output "$OUTPUT" \
  --repo-prefix sftp:backup@example:/backups

assert_contains "db_config:" "$OUTPUT"
assert_contains "auto_detect: true" "$OUTPUT"

enabled_codes="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" enabled-site-codes)"
printf '%s\n' "$enabled_codes" | grep '^www$' >/dev/null || fail "missing www site"
printf '%s\n' "$enabled_codes" | grep '^example-com$' >/dev/null || fail "missing example-com site"
printf '%s\n' "$enabled_codes" | grep '^site-1$' >/dev/null || fail "missing site-1 site"

www_path="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" site-field www path)"
[[ "$www_path" == "$WORK_DIR/home/bitrix/www" ]] || fail "www path was not generated correctly"

www_repo="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" site-field www repo)"
[[ "$www_repo" == "sftp:backup@example:/backups/www" ]] || fail "www repo was not generated correctly"

example_path="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" site-field example-com path)"
[[ "$example_path" == "$WORK_DIR/home/bitrix/ext_www/example.com" ]] || fail "example-com path was not generated correctly"

example_repo="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" site-field example-com repo)"
[[ "$example_repo" == "sftp:backup@example:/backups/example-com" ]] || fail "example-com repo was not generated correctly"

special_path="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" site-field site-1 path)"
[[ "$special_path" == "$WORK_DIR/home/bitrix/ext_www/site #1" ]] || fail "special path was not YAML-quoted safely"

special_repo="$(python3 "$ROOT_DIR/lib/config-query.py" "$OUTPUT" site-field site-1 repo)"
[[ "$special_repo" == "sftp:backup@example:/backups/site-1" ]] || fail "special repo was not YAML-quoted safely"

if grep -F 'settings_pass' "$OUTPUT" >/dev/null; then
  fail "discovery output leaked settings password"
fi

if grep -F 'dbconn_pass' "$OUTPUT" >/dev/null; then
  fail "discovery output leaked dbconn password"
fi

printf 'ok - discover\n'
