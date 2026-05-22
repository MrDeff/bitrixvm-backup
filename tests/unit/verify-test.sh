#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/verify"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/site/bitrix" "$WORK_DIR/repo"
cp "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix/.settings.php" "$WORK_DIR/site/bitrix/.settings.php"

cat >"$WORK_DIR/site.env" <<'EOF'
RESTIC_PASSWORD=test-password
EOF
chmod 600 "$WORK_DIR/site.env"

cat >"$WORK_DIR/sites.yml" <<YAML
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/repo
    env_file: $WORK_DIR/site.env
YAML

output="$("$ROOT_DIR/bin/bitrix-backup-verify" --config "$WORK_DIR/sites.yml" --offline)"

printf '%s\n' "$output" | grep 'OK config readable' >/dev/null || fail "missing config readable check"
printf '%s\n' "$output" | grep 'OK site example-com db config readable' >/dev/null || fail "missing db config readable check"
printf '%s\n' "$output" | grep 'OK site example-com env file mode' >/dev/null || fail "missing env file mode check"

printf 'ok - verify\n'
