#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

assert_contains "ExecStart=/opt/bitrix-backup/bin/bitrix-backup-run" "$ROOT_DIR/systemd/bitrix-backup.service"
assert_contains "OnCalendar=" "$ROOT_DIR/systemd/bitrix-backup.timer"
assert_contains "python3-pyyaml" "$ROOT_DIR/docs/install.md"
assert_contains "restic init" "$ROOT_DIR/docs/storage-sftp.md"
assert_contains "AWS_ACCESS_KEY_ID" "$ROOT_DIR/docs/storage-s3.md"
assert_contains "bitrix-backup-restore" "$ROOT_DIR/docs/restore.md"

printf 'ok - docs\n'
