#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

settings_json="$(php "$ROOT_DIR/lib/db-config-reader.php" "$ROOT_DIR/tests/fixtures/bitrix-settings-site")"
printf '%s\n' "$settings_json" | grep '"database":"settings_db"' >/dev/null || fail "settings config missing database"
printf '%s\n' "$settings_json" | grep '"login":"settings_user"' >/dev/null || fail "settings config missing login"
printf '%s\n' "$settings_json" | grep '"password":"settings_pass"' >/dev/null || fail "settings config missing password"

dbconn_json="$(php "$ROOT_DIR/lib/db-config-reader.php" "$ROOT_DIR/tests/fixtures/bitrix-dbconn-site")"
printf '%s\n' "$dbconn_json" | grep '"database":"dbconn_db"' >/dev/null || fail "dbconn config missing database"
printf '%s\n' "$dbconn_json" | grep '"login":"dbconn_user"' >/dev/null || fail "dbconn config missing login"
printf '%s\n' "$dbconn_json" | grep '"password":"dbconn_pass"' >/dev/null || fail "dbconn config missing password"

printf 'ok - db config\n'
