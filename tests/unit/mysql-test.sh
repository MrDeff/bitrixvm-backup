#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/mysql.sh"

WORK_DIR="$ROOT_DIR/.test-work/mysql"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

defaults_file="$WORK_DIR/client.cnf"
write_mysql_defaults_file "$defaults_file" "localhost" "bitrix_user" "secret"

assert_contains "[client]" "$defaults_file"
assert_contains "host=localhost" "$defaults_file"
assert_contains "user=bitrix_user" "$defaults_file"
assert_contains "password=secret" "$defaults_file"

mode="$(stat -f '%Lp' "$defaults_file" 2>/dev/null || stat -c '%a' "$defaults_file")"
[[ "$mode" == "600" ]] || fail "$defaults_file mode is $mode, expected 600"

printf 'ok - mysql\n'
