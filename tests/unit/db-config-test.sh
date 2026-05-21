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

bad_site="$ROOT_DIR/.test-work/db-config/bad-settings"
mkdir -p "$bad_site/bitrix"
cat >"$bad_site/bitrix/.settings.php" <<'PHP'
<?php
return [
    'connections' => [
        'value' => [
            'default' => [
                'host' => 'localhost',
                'database' => ['bad'],
                'login' => 'settings_user',
                'password' => 'settings_pass',
            ],
        ],
    ],
];
PHP

if php "$ROOT_DIR/lib/db-config-reader.php" "$bad_site" >/dev/null 2>&1; then
  fail "malformed settings config was accepted"
fi

printf 'ok - db config\n'
