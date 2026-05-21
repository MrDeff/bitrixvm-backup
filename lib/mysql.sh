#!/usr/bin/env bash
set -euo pipefail

mysql_reject_control_newlines() {
  local value="$1"
  case "$value" in
    *$'\n'*|*$'\r'*)
      printf 'MySQL option values must not contain CR or LF\n' >&2
      return 1
      ;;
  esac
}

mysql_option_value() {
  local value="$1"
  mysql_reject_control_newlines "$value" || return 1

  if [[ "$value" =~ ^[A-Za-z0-9._:/@%+-]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"\n' "$value"
}

write_mysql_defaults_file() {
  local output="$1"
  local host="$2"
  local user="$3"
  local password="$4"
  local output_dir tmp_file host_value user_value password_value

  output_dir="$(dirname "$output")"
  mkdir -p "$output_dir"
  tmp_file="$(mktemp "$output_dir/mysql.defaults.XXXXXX")"

  if ! host_value="$(mysql_option_value "$host")"; then
    rm -f "$tmp_file"
    return 1
  fi
  if ! user_value="$(mysql_option_value "$user")"; then
    rm -f "$tmp_file"
    return 1
  fi
  if ! password_value="$(mysql_option_value "$password")"; then
    rm -f "$tmp_file"
    return 1
  fi

  if (
    umask 077
    {
      printf '[client]\n'
      printf 'host=%s\n' "$host_value"
      printf 'user=%s\n' "$user_value"
      printf 'password=%s\n' "$password_value"
    } >"$tmp_file"
  ); then
    chmod 600 "$tmp_file"
    mv "$tmp_file" "$output"
  else
    local status=$?
    rm -f "$tmp_file"
    return "$status"
  fi
}

dump_mysql_database() {
  local defaults_file="$1"
  local database="$2"
  local output="$3"
  local output_dir tmp_file

  output_dir="$(dirname "$output")"
  mkdir -p "$output_dir"
  tmp_file="$(mktemp "$output_dir/mysql.dump.XXXXXX")"

  if (
    umask 077
    mysqldump \
      --defaults-extra-file="$defaults_file" \
      --single-transaction \
      --quick \
      --routines \
      --triggers \
      --events \
      "$database" >"$tmp_file"
  ); then
    chmod 600 "$tmp_file"
    mv "$tmp_file" "$output"
  else
    local status=$?
    rm -f "$tmp_file"
    return "$status"
  fi
}
