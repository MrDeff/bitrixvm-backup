#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/restore"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/bin" "$WORK_DIR/site"

cat >"$WORK_DIR/site.env" <<EOF
RESTIC_PASSWORD=test-password
AWS_ACCESS_KEY_ID=site-key
target=/tmp/evil-target
site=evil-site
repo=/tmp/evil-repo
snapshot=evil-snapshot
kind=files
EOF
chmod 600 "$WORK_DIR/site.env"

cat >"$WORK_DIR/global.env" <<EOF
AWS_ACCESS_KEY_ID=global-restore-key
AWS_DEFAULT_REGION=us-east-1
EOF
chmod 600 "$WORK_DIR/global.env"

cat >"$WORK_DIR/sites.yml" <<YAML
defaults:
  global_env_file: $WORK_DIR/global.env
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: $WORK_DIR/repo
    env_file: $WORK_DIR/site.env
YAML

cat >"$WORK_DIR/bin/restic" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${AWS_DEFAULT_REGION:-}" == "us-east-1" ]] || exit 23
[[ "${AWS_ACCESS_KEY_ID:-}" == "site-key" ]] || exit 24
printf '%s\n' "$*" >>"$RESTORE_TEST_LOG"
case "$*" in
  *" restore files-snapshot --tag kind:files --target "*)
    mkdir -p "${*: -1}"
    printf 'restored file\n' >"${*: -1}/index.php"
    ;;
  *" snapshots --json --tag kind:db"*)
    printf '[{"id":"db-snapshot","time":"2026-05-21T00:00:00Z"}]\n'
    ;;
  *" ls --json db-snapshot"*)
    printf '%s\n' '{"type":"file","path":"/var/tmp/bitrix-backup/example/db.sql"}'
    ;;
  *" dump db-snapshot /var/tmp/bitrix-backup/example/db.sql"*)
    printf 'CREATE TABLE example(id int);\n'
    ;;
  *" ls --json explicit-db-snapshot"*)
    printf '%s\n' '{"type":"file","path":"/var/tmp/bitrix-backup/explicit/db.sql"}'
    ;;
  *" dump explicit-db-snapshot /var/tmp/bitrix-backup/explicit/db.sql"*)
    printf 'CREATE TABLE explicit_example(id int);\n'
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$WORK_DIR/bin/restic"

RESTORE_TEST_LOG="$WORK_DIR/restic.log" PATH="$WORK_DIR/bin:$PATH" "$ROOT_DIR/bin/bitrix-backup-restore" \
  --config "$WORK_DIR/sites.yml" \
  --site example-com \
  --kind db \
  --target "$WORK_DIR/out" \
  --snapshot latest

restore_root="$(find "$WORK_DIR/out/example-com" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$restore_root" ]] || fail "missing restore staging directory"
assert_contains "CREATE TABLE example" "$restore_root/db/db.sql"

if [[ -e /tmp/evil-target ]]; then
  fail "env file overrode restore target"
fi
if grep -F "/tmp/evil-repo" "$WORK_DIR/restic.log" >/dev/null; then
  fail "env file overrode restore repo"
fi

RESTORE_TEST_LOG="$WORK_DIR/restic-explicit.log" PATH="$WORK_DIR/bin:$PATH" "$ROOT_DIR/bin/bitrix-backup-restore" \
  --config "$WORK_DIR/sites.yml" \
  --site example-com \
  --kind both \
  --target "$WORK_DIR/out-explicit" \
  --files-snapshot files-snapshot \
  --db-snapshot explicit-db-snapshot

explicit_restore_root="$(find "$WORK_DIR/out-explicit/example-com" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$explicit_restore_root" ]] || fail "missing explicit restore staging directory"
assert_contains "restored file" "$explicit_restore_root/files/index.php"
assert_contains "CREATE TABLE explicit_example" "$explicit_restore_root/db/db.sql"
assert_contains "restore files-snapshot --tag kind:files" "$WORK_DIR/restic-explicit.log"
assert_contains "dump explicit-db-snapshot /var/tmp/bitrix-backup/explicit/db.sql" "$WORK_DIR/restic-explicit.log"

printf 'ok - restore\n'
