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

if BITRIX_BACKUP_TMP="$WORK_DIR/tmp" "$ROOT_DIR/bin/bitrix-backup-run" --config "$WORK_DIR/missing.yml" --dry-run >/dev/null 2>&1; then
  fail "runner accepted missing config"
fi

fake_bin="$WORK_DIR/bin"
mkdir -p "$fake_bin"
fake_bin="$(cd "$fake_bin" && pwd)"

cat >"$fake_bin/mysqldump" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'dump\n'
SH
chmod +x "$fake_bin/mysqldump"

cat >"$fake_bin/restic" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "$args" == *" snapshots --json --tag kind:db"* ]]; then
  printf '[{"id":"db-id","time":"2026-05-21T00:00:00Z"}]\n'
  exit 0
fi
if [[ "$args" == *" snapshots --json --tag kind:files"* ]]; then
  printf '[{"id":"files-id","time":"2026-05-21T00:00:00Z"}]\n'
  exit 0
fi
if [[ "$args" == *" backup "* && "$args" == *"db.sql"* ]]; then
  exit 9
fi
if [[ "$args" == *" backup ."* ]]; then
  find "$(pwd)" -name db.sql -print -quit | grep . && exit 8
fi
exit 0
SH
chmod +x "$fake_bin/restic"

cat >"$fake_bin/flock" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-n" ]]; then
  exit 0
fi
if [[ "${1:-}" == "-u" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$fake_bin/flock"

cat >"$fake_bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$RUNNER_CURL_LOG"
exit 0
SH
chmod +x "$fake_bin/curl"

cat >"$WORK_DIR/webhook.env" <<'EOF'
WEBHOOK_URL=https://hook.example
EOF

cat >"$WORK_DIR/sites-fail.yml" <<YAML
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
  webhook_env_file: $WORK_DIR/webhook.env
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/restic-repo
    env_file: $WORK_DIR/site.env
    excludes: []
YAML

curl_log="$WORK_DIR/curl.log"
if BITRIX_BACKUP_TMP="$WORK_DIR/tmp" PATH="$fake_bin:$PATH" RUNNER_CURL_LOG="$curl_log" "$ROOT_DIR/bin/bitrix-backup-run" --config "$WORK_DIR/sites-fail.yml" >/dev/null 2>&1; then
  fail "runner succeeded after failed DB restic backup"
fi

assert_contains '"status": "failed"' "$curl_log"
if grep -F '"status": "success"' "$curl_log" >/dev/null; then
  fail "runner sent success webhook after failed backup"
fi

cat >"$fake_bin/restic" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "$args" == *" snapshots --json --tag kind:db"* ]]; then
  printf '[{"id":"db-id","time":"2026-05-21T00:00:00Z"}]\n'
  exit 0
fi
if [[ "$args" == *" snapshots --json --tag kind:files"* ]]; then
  printf '[{"id":"files-id","time":"2026-05-21T00:00:00Z"}]\n'
  exit 0
fi
if [[ "$args" == *" backup ."* ]]; then
  find "$(pwd)" -name db.sql -print -quit | grep . && exit 8
fi
exit 0
SH
chmod +x "$fake_bin/restic"

rm -f "$curl_log"
BITRIX_BACKUP_TMP="$WORK_DIR/tmp" PATH="$fake_bin:$PATH" RUNNER_CURL_LOG="$curl_log" "$ROOT_DIR/bin/bitrix-backup-run" --config "$WORK_DIR/sites-fail.yml" >/dev/null 2>&1 || fail "runner failed when fake restic succeeded"
assert_contains '"status": "success"' "$curl_log"
assert_contains '"db_snapshot_id": "db-id"' "$curl_log"
assert_contains '"files_snapshot_id": "files-id"' "$curl_log"

cat >"$WORK_DIR/webhook-empty.env" <<'EOF'
# intentionally empty
EOF

cat >"$WORK_DIR/site2.env" <<'EOF'
# intentionally empty to verify site env isolation
EOF

cat >"$WORK_DIR/sites-two.yml" <<YAML
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
sites:
  - code: first-site
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/restic-repo-first
    env_file: $WORK_DIR/site.env
    webhook_env_file: $WORK_DIR/webhook.env
    excludes: []
  - code: second-site
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/restic-repo-second
    env_file: $WORK_DIR/site2.env
    webhook_env_file: $WORK_DIR/webhook-empty.env
    excludes: []
YAML

rm -f "$curl_log"
BITRIX_BACKUP_TMP="$WORK_DIR/tmp" PATH="$fake_bin:$PATH" RUNNER_CURL_LOG="$curl_log" "$ROOT_DIR/bin/bitrix-backup-run" --config "$WORK_DIR/sites-two.yml" >/dev/null 2>&1 || fail "runner failed for two-site env isolation check"
[[ "$(wc -l <"$curl_log" | tr -d '[:space:]')" == "1" ]] || fail "empty webhook env reused previous webhook URL"
assert_contains '"site": "first-site"' "$curl_log"
if grep -F '"site": "second-site"' "$curl_log" >/dev/null; then
  fail "second site sent webhook through leaked WEBHOOK_URL"
fi

printf 'ok - runner dry-run\n'
