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

permissive_file="$WORK_DIR/permissive.cnf"
printf 'old\n' >"$permissive_file"
chmod 644 "$permissive_file"
write_mysql_defaults_file "$permissive_file" "local host" "bitrix_user" 'sec"ret\value'
mode="$(stat -f '%Lp' "$permissive_file" 2>/dev/null || stat -c '%a' "$permissive_file")"
[[ "$mode" == "600" ]] || fail "$permissive_file mode is $mode, expected 600"
assert_contains 'host="local host"' "$permissive_file"
assert_contains 'password="sec\"ret\\value"' "$permissive_file"

if write_mysql_defaults_file "$WORK_DIR/bad.cnf" "localhost" "bitrix_user" $'bad\nvalue' >/dev/null 2>&1; then
  fail "mysql defaults accepted a newline in password"
fi

fake_bin="$WORK_DIR/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/mysqldump" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'dump for %s\n' "${@: -1}"
SH
chmod +x "$fake_bin/mysqldump"

PATH="$fake_bin:$PATH" dump_mysql_database "$defaults_file" "settings_db" "$WORK_DIR/db.sql"
assert_contains "dump for settings_db" "$WORK_DIR/db.sql"
mode="$(stat -f '%Lp' "$WORK_DIR/db.sql" 2>/dev/null || stat -c '%a' "$WORK_DIR/db.sql")"
[[ "$mode" == "600" ]] || fail "$WORK_DIR/db.sql mode is $mode, expected 600"

printf 'ok - mysql\n'
