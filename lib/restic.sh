#!/usr/bin/env bash
set -euo pipefail

restic_base() {
  local repo="$1"
  shift

  restic -r "$repo" "$@"
}

restic_init_if_needed() {
  local repo="$1"

  if ! restic_base "$repo" snapshots >/dev/null 2>&1; then
    restic_base "$repo" init
  fi
}

restic_backup_path() {
  local repo="$1"
  local path="$2"
  local host="$3"
  local tag="$4"
  shift 4

  restic_base "$repo" backup "$path" --host "$host" --tag "$tag" "$@"
}

restic_forget_command() {
  local tag="$1"
  local keep_daily="$2"
  local keep_weekly="$3"
  local keep_monthly="$4"

  printf 'forget --tag %s --group-by tags --keep-daily %s --keep-weekly %s --keep-monthly %s --prune\n' \
    "$tag" "$keep_daily" "$keep_weekly" "$keep_monthly"
}

restic_apply_retention() {
  local repo="$1"
  local tag="$2"
  local keep_daily="$3"
  local keep_weekly="$4"
  local keep_monthly="$5"

  restic_base "$repo" forget \
    --tag "$tag" \
    --group-by tags \
    --keep-daily "$keep_daily" \
    --keep-weekly "$keep_weekly" \
    --keep-monthly "$keep_monthly" \
    --prune
}

restic_latest_snapshot_id() {
  local repo="$1"
  local tag="$2"

  restic_base "$repo" snapshots --json --tag "$tag" \
    | python3 -c 'import json, sys
data = json.load(sys.stdin)
if not isinstance(data, list) or not data:
    sys.exit(1)
snapshot = max(data, key=lambda item: item.get("time", ""))
snapshot_id = snapshot.get("id") or snapshot.get("short_id")
if not snapshot_id:
    sys.exit(1)
print(snapshot_id)
'
}
