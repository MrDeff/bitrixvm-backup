#!/usr/bin/env bash
set -euo pipefail

sanitize_error() {
  local error="$1"

  printf '%s' "$error" | python3 -c 'import re, sys
text = sys.stdin.read()
patterns = [
    (r"(?i)(authorization:\s*bearer\s+)\S+", r"\1REDACTED"),
    (r"(?i)\b([A-Z0-9_]*(PASSWORD|SECRET|TOKEN|ACCESS_KEY|SECRET_KEY)[A-Z0-9_]*\s*=\s*)([\"\047]?)[^\s\"\047]+", r"\1\3REDACTED"),
    (r"(?i)([\"\047]?(password|secret|token|access_key|secret_key)[\"\047]?\s*:\s*)([\"\047]?)[^,\"\047\s}]+", r"\1\3REDACTED"),
]
for pattern, replacement in patterns:
    text = re.sub(pattern, replacement, text)
print(text, end="")
'
}

webhook_payload() {
  local site="$1"
  local host="$2"
  local status="$3"
  local started_at="$4"
  local finished_at="$5"
  local duration_seconds="$6"
  local files_snapshot_id="$7"
  local db_snapshot_id="$8"
  local error="$9"

  local sanitized_error
  if [[ ! "$duration_seconds" =~ ^[0-9]+$ ]]; then
    duration_seconds=0
  fi
  sanitized_error="$(sanitize_error "$error")"

  python3 - "$site" "$host" "$status" "$started_at" "$finished_at" "$duration_seconds" "$files_snapshot_id" "$db_snapshot_id" "$sanitized_error" <<'PY'
import json
import sys

_, site, host, status, started_at, finished_at, duration_seconds, files_snapshot_id, db_snapshot_id, error = sys.argv

payload = {
    "db_snapshot_id": db_snapshot_id or None,
    "duration_seconds": int(duration_seconds),
    "error": error or None,
    "files_snapshot_id": files_snapshot_id or None,
    "finished_at": finished_at,
    "host": host,
    "site": site,
    "started_at": started_at,
    "status": status,
}

print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
}

send_webhook() {
  local url="$1"
  local token="$2"
  local payload="$3"

  if [[ -z "$url" ]]; then
    return 0
  fi

  local curl_args=(-fsS --connect-timeout 5 --max-time 20 --retry 2 --retry-delay 1 --retry-connrefused -X POST -H "Content-Type: application/json" --data-binary "$payload")

  if [[ -n "$token" ]]; then
    curl_args+=(-H "Authorization: Bearer $token")
  fi

  curl "${curl_args[@]}" "$url"
}
