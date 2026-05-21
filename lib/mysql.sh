#!/usr/bin/env bash
set -euo pipefail

write_mysql_defaults_file() {
  local output="$1"
  local host="$2"
  local user="$3"
  local password="$4"

  (
    umask 077
    {
      printf '[client]\n'
      printf 'host=%s\n' "$host"
      printf 'user=%s\n' "$user"
      printf 'password=%s\n' "$password"
    } >"$output"
  )
  chmod 600 "$output"
}

dump_mysql_database() {
  local defaults_file="$1"
  local database="$2"
  local output="$3"

  mysqldump \
    --defaults-extra-file="$defaults_file" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    --events \
    "$database" >"$output"
}
