#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

for script in \
  "$ROOT_DIR/bin/bitrix-backup-discover" \
  "$ROOT_DIR/bin/bitrix-backup-run" \
  "$ROOT_DIR/bin/bitrix-backup-verify" \
  "$ROOT_DIR/bin/bitrix-backup-restore" \
  "$ROOT_DIR/install.sh"; do
  assert_file_executable "$script"
  "$script" --help | grep -E 'Usage:|usage:' >/dev/null || fail "$script --help lacks usage"
done

assert_contains "set -euo pipefail" "$ROOT_DIR/lib/common.sh"
assert_contains "log_info" "$ROOT_DIR/lib/logging.sh"

for test_script in "$ROOT_DIR"/tests/unit/*-test.sh; do
  [[ -e "$test_script" ]] || continue
  bash "$test_script"
done

if [[ "${RUN_INTEGRATION:-0}" == "1" ]]; then
  for test_script in "$ROOT_DIR"/tests/integration/*-test.sh; do
    [[ -e "$test_script" ]] || continue
    bash "$test_script"
  done
fi

printf 'ok - smoke tests\n'
