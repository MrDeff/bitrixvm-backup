#!/usr/bin/env bash
set -euo pipefail

log_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  printf '%s INFO %s\n' "$(log_ts)" "$*" >&2
}

log_warn() {
  printf '%s WARN %s\n' "$(log_ts)" "$*" >&2
}

log_error() {
  printf '%s ERROR %s\n' "$(log_ts)" "$*" >&2
}
