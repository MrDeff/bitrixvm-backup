#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/restore"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/bin" "$WORK_DIR/site"

cat >"$WORK_DIR/site.env" <<EOF
RESTIC_PASSWORD=test-password
target=/tmp/evil-target
site=evil-site
repo=/tmp/evil-repo
snapshot=evil-snapshot
kind=files
EOF
chmod 600 "$WORK_DIR/site.env"

cat >"$WORK_DIR/sites.yml" <<YAML
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
printf '%s\n' "$*" >>"$RESTORE_TEST_LOG"
case "$*" in
  *" snapshots --json --tag kind:db"*)
    printf '[{"id":"db-snapshot","time":"2026-05-21T00:00:00Z"}]\n'
    ;;
  *" ls --json db-snapshot"*)
    printf '%s\n' '{"type":"file","path":"/var/tmp/bitrix-backup/example/db.sql"}'
    ;;
  *" dump db-snapshot /var/tmp/bitrix-backup/example/db.sql"*)
    printf 'CREATE TABLE example(id int);\n'
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

printf 'ok - restore\n'
