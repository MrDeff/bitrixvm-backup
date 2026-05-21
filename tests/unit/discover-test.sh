#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/discover"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/home/bitrix/www" "$WORK_DIR/home/bitrix/ext_www/example.com"

cp -R "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix" "$WORK_DIR/home/bitrix/www/"
cp -R "$ROOT_DIR/tests/fixtures/bitrix-dbconn-site/bitrix" "$WORK_DIR/home/bitrix/ext_www/example.com/"

OUTPUT="$WORK_DIR/sites.yml"
"$ROOT_DIR/bin/bitrix-backup-discover" \
  --root "$WORK_DIR/home/bitrix" \
  --output "$OUTPUT" \
  --repo-prefix sftp:backup@example:/backups

assert_contains "code: www" "$OUTPUT"
assert_contains "path: $WORK_DIR/home/bitrix/www" "$OUTPUT"
assert_contains "repo: sftp:backup@example:/backups/www" "$OUTPUT"
assert_contains "code: example-com" "$OUTPUT"
assert_contains "path: $WORK_DIR/home/bitrix/ext_www/example.com" "$OUTPUT"
assert_contains "repo: sftp:backup@example:/backups/example-com" "$OUTPUT"

if grep -F 'settings_pass' "$OUTPUT" >/dev/null; then
  fail "discovery output leaked settings password"
fi

if grep -F 'dbconn_pass' "$OUTPUT" >/dev/null; then
  fail "discovery output leaked dbconn password"
fi

printf 'ok - discover\n'
