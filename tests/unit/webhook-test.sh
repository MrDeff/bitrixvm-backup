#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/webhook.sh"

assert_json_contains() {
  local needle="$1"
  local json="$2"

  [[ "$json" == *"$needle"* ]] || fail "JSON does not contain $needle"
}

assert_json_not_contains() {
  local needle="$1"
  local json="$2"

  [[ "$json" != *"$needle"* ]] || fail "JSON unexpectedly contains $needle"
}

payload="$(webhook_payload "example-com" "vm01" "success" "2026-05-21T02:00:00+07:00" "2026-05-21T02:01:00+07:00" "60" "files123" "db123" "")"
assert_json_contains '"site": "example-com"' "$payload"
assert_json_contains '"status": "success"' "$payload"
assert_json_contains '"files_snapshot_id": "files123"' "$payload"
assert_json_contains '"error": null' "$payload"

failed_payload="$(webhook_payload "example-com" "vm01" "failed" "2026-05-21T02:00:00+07:00" "2026-05-21T02:01:00+07:00" "60" "" "" "password=secret failed")"
assert_json_not_contains "password=" "$failed_payload"
assert_json_contains '"error": "REDACTED failed"' "$failed_payload"

printf 'ok - webhook\n'
