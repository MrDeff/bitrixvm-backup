#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

if ! command -v restic >/dev/null 2>&1; then
  printf 'skip - restic is not installed\n'
  exit 0
fi

WORK_DIR="$ROOT_DIR/.test-work/integration"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/site" "$WORK_DIR/repo" "$WORK_DIR/work"

cat >"$WORK_DIR/site/index.php" <<'PHP'
<?php echo "example";
PHP

cat >"$WORK_DIR/db.sql" <<'SQL'
CREATE TABLE example (id int);
SQL

cat >"$WORK_DIR/site.env" <<'EOF'
RESTIC_PASSWORD=test-password
EOF
chmod 600 "$WORK_DIR/site.env"

cat >"$WORK_DIR/work/sites.yml" <<YAML
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: $WORK_DIR/repo
    env_file: $WORK_DIR/site.env
YAML

export RESTIC_PASSWORD=test-password
restic -r "$WORK_DIR/repo" init >/dev/null
(cd "$WORK_DIR/site" && restic -r "$WORK_DIR/repo" backup index.php --tag kind:files >/dev/null)
restic -r "$WORK_DIR/repo" backup "$WORK_DIR/db.sql" --tag kind:db >/dev/null
unset RESTIC_PASSWORD

"$ROOT_DIR/bin/bitrix-backup-restore" \
  --config "$WORK_DIR/work/sites.yml" \
  --site example-com \
  --kind both \
  --target "$WORK_DIR/work/restore"

restore_root="$(find "$WORK_DIR/work/restore/example-com" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$restore_root" ]] || fail "missing restore staging directory"
[[ -f "$restore_root/files/index.php" ]] || fail "missing restored file"
[[ -f "$restore_root/db/db.sql" ]] || fail "missing restored DB dump"

printf 'ok - restic local restore\n'
