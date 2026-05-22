#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/webhook.sh"

json_field() {
  local payload="$1"
  local field="$2"
  python3 -c 'import json,sys; value=json.loads(sys.argv[1])[sys.argv[2]]; print("__NULL__" if value is None else value)' "$payload" "$field"
}

payload="$(webhook_payload "example-com" "vm01" "success" "2026-05-21T02:00:00+07:00" "2026-05-21T02:01:00+07:00" "60" "files123" "db123" "")"
[[ "$(json_field "$payload" site)" == "example-com" ]] || fail "payload missing site"
[[ "$(json_field "$payload" status)" == "success" ]] || fail "payload missing status"
[[ "$(json_field "$payload" files_snapshot_id)" == "files123" ]] || fail "payload missing files snapshot"
[[ "$(json_field "$payload" error)" == "__NULL__" ]] || fail "payload error should be null"

invalid_duration="$(webhook_payload "example-com" "vm01" "failed" "s" "f" "not-a-number" "" "" "")"
[[ "$(json_field "$invalid_duration" duration_seconds)" == "0" ]] || fail "invalid duration should become 0"

failed_payload="$(webhook_payload "example-com" "vm01" "failed" "s" "f" "1" "" "" "password=secret RESTIC_PASSWORD=\"abc def\" Authorization: Bearer xyz token: value {\"Authorization\": \"Bearer abc123\", \"password\": \"abc def\"}")"
if printf '%s\n' "$failed_payload" | grep -E 'secret|abc|Bearer xyz|token: value|abc123|abc def' >/dev/null; then
  fail "payload leaked secret material"
fi

WORK_DIR="$ROOT_DIR/.test-work/webhook"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/bin"
curl_log="$WORK_DIR/curl.log"
cat >"$WORK_DIR/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$WEBHOOK_TEST_LOG"
case "${WEBHOOK_FAKE_MODE:-success}" in
  success) exit 0 ;;
  transient)
    count_file="${WEBHOOK_TEST_LOG}.count"
    count=0
    [[ -f "$count_file" ]] && count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    [[ "$count" -lt 2 ]] && exit 7
    exit 0
    ;;
  client) exit 22 ;;
  fail) exit 7 ;;
esac
SH
chmod +x "$WORK_DIR/bin/curl"

WEBHOOK_TEST_LOG="$curl_log" PATH="$WORK_DIR/bin:$PATH" send_webhook "" "" "$payload"
[[ ! -f "$curl_log" ]] || fail "empty webhook URL should not call curl"

WEBHOOK_TEST_LOG="$curl_log" PATH="$WORK_DIR/bin:$PATH" send_webhook "https://hook.example" "" "$payload"
assert_contains "https://hook.example" "$curl_log"
if grep -F "Authorization: Bearer" "$curl_log" >/dev/null; then
  fail "authorization header was sent without token"
fi

rm -f "$curl_log" "$curl_log.count"
WEBHOOK_TEST_LOG="$curl_log" PATH="$WORK_DIR/bin:$PATH" WEBHOOK_FAKE_MODE=success send_webhook "https://hook.example" "tok" "$payload"
assert_contains "Authorization: Bearer tok" "$curl_log"

assert_contains "--retry 2" "$curl_log"
assert_contains "--connect-timeout 5" "$curl_log"
assert_contains "--max-time 20" "$curl_log"

rm -f "$curl_log" "$curl_log.count"
if WEBHOOK_TEST_LOG="$curl_log" PATH="$WORK_DIR/bin:$PATH" WEBHOOK_FAKE_MODE=client send_webhook "https://hook.example" "" "$payload"; then
  fail "client error should fail"
fi
[[ "$(wc -l <"$curl_log" | tr -d '[:space:]')" == "1" ]] || fail "client error should not be manually retried"

printf 'ok - webhook\n'
