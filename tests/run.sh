#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

for script in \
  "$ROOT_DIR/bin/bitrix-backup-discover" \
  "$ROOT_DIR/bin/bitrix-backup-run" \
  "$ROOT_DIR/bin/bitrix-backup-verify" \
  "$ROOT_DIR/bin/bitrix-backup-restore"; do
  assert_file_executable "$script"
  "$script" --help | grep -E 'Usage:|usage:' >/dev/null || fail "$script --help lacks usage"
done

assert_contains "set -euo pipefail" "$ROOT_DIR/lib/common.sh"
assert_contains "log_info" "$ROOT_DIR/lib/logging.sh"

printf 'ok - smoke tests\n'
