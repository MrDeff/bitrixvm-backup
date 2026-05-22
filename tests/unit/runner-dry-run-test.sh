#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/runner"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/site/bitrix"
cp "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix/.settings.php" "$WORK_DIR/site/bitrix/.settings.php"

cat >"$WORK_DIR/site.env" <<'EOF'
RESTIC_PASSWORD=test-password
EOF

cat >"$WORK_DIR/sites.yml" <<YAML
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/restic-repo
    env_file: $WORK_DIR/site.env
    excludes:
      - /upload/import
YAML

output="$(BITRIX_BACKUP_TMP="$WORK_DIR/tmp" "$ROOT_DIR/bin/bitrix-backup-run" --config "$WORK_DIR/sites.yml" --dry-run)"

printf '%s\n' "$output" | grep 'DRY-RUN site=example-com step=db-backup' >/dev/null || fail "missing db dry-run"
printf '%s\n' "$output" | grep 'DRY-RUN site=example-com step=files-backup' >/dev/null || fail "missing files dry-run"
printf '%s\n' "$output" | grep 'DRY-RUN site=example-com step=retention kind:db' >/dev/null || fail "missing db retention dry-run"

printf 'ok - runner dry-run\n'
