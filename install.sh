#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install.sh --repo-prefix <restic-prefix> [options]

Options:
  --repo-prefix <prefix>       Required restic repository prefix.
  --install-dir <path>         Install directory. Default: /opt/bitrix-backup
  --config-dir <path>          Config directory. Default: /etc/bitrix-backup
  --systemd-dir <path>         systemd unit directory. Default: /etc/systemd/system
  --root <path>                Bitrix sites root. Default: /home/bitrix
  --branch <name>              GitHub branch to download. Default: main
  --source-dir <path>          Copy files from a local checkout instead of GitHub.
  --dry-run                    Print planned commands without changing the system.
  --no-systemd-enable          Install units but do not enable/start the timer.
  --no-generate-restic-passwords
                               Do not create per-site RESTIC_PASSWORD env files.
  --skip-package-install       Do not run dnf install.
  --skip-os-check              Do not require CentOS/RHEL-like /etc/os-release.
  -h, --help                   Show this help.
USAGE
}

repo_prefix=""
install_dir="/opt/bitrix-backup"
config_dir="/etc/bitrix-backup"
systemd_dir="/etc/systemd/system"
bitrix_root="/home/bitrix"
branch="main"
source_dir=""
dry_run=false
enable_systemd=true
generate_restic_passwords=true
install_packages=true
check_os=true
github_repo="MrDeff/bitrixvm-backup"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-prefix)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --repo-prefix requires a value\n' >&2; usage; exit 2; }
      repo_prefix="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --install-dir requires a path\n' >&2; usage; exit 2; }
      install_dir="$2"
      shift 2
      ;;
    --config-dir)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --config-dir requires a path\n' >&2; usage; exit 2; }
      config_dir="$2"
      shift 2
      ;;
    --root)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --root requires a path\n' >&2; usage; exit 2; }
      bitrix_root="$2"
      shift 2
      ;;
    --systemd-dir)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --systemd-dir requires a path\n' >&2; usage; exit 2; }
      systemd_dir="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --branch requires a value\n' >&2; usage; exit 2; }
      branch="$2"
      shift 2
      ;;
    --source-dir)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { printf 'ERROR: --source-dir requires a path\n' >&2; usage; exit 2; }
      source_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --no-systemd-enable)
      enable_systemd=false
      shift
      ;;
    --no-generate-restic-passwords)
      generate_restic_passwords=false
      shift
      ;;
    --skip-package-install)
      install_packages=false
      shift
      ;;
    --skip-os-check)
      check_os=false
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$repo_prefix" ]]; then
  printf 'ERROR: --repo-prefix is required\n' >&2
  usage
  exit 2
fi

run() {
  if [[ "$dry_run" == "true" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

need_root() {
  if [[ "$dry_run" == "true" ]]; then
    return 0
  fi
  if [[ "${BITRIX_BACKUP_INSTALL_ALLOW_NON_ROOT:-}" == "1" ]]; then
    return 0
  fi
  if [[ "$(id -u)" != "0" ]]; then
    printf 'ERROR: installer must run as root\n' >&2
    exit 1
  fi
}

check_supported_os() {
  if [[ "$check_os" != "true" || "$dry_run" == "true" ]]; then
    return 0
  fi
  if [[ ! -r /etc/os-release ]]; then
    printf 'ERROR: cannot read /etc/os-release; use --skip-os-check to override\n' >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}:${ID_LIKE:-}" in
    centos:*|rhel:*|rocky:*|almalinux:*|*:rhel*|*:fedora*)
      ;;
    *)
      printf 'ERROR: unsupported OS %s; use --skip-os-check to override\n' "${PRETTY_NAME:-unknown}" >&2
      exit 1
      ;;
  esac
}

copy_from_source_dir() {
  local src="$1"
  run mkdir -p "$install_dir"
  run rsync -a --delete \
    --exclude .git \
    --exclude .test-work \
    --exclude 'config/sites.yml' \
    --exclude '*.env' \
    "$src/" "$install_dir/"
}

download_from_github() {
  local tmp_dir archive_url
  archive_url="https://github.com/$github_repo/archive/refs/heads/$branch.tar.gz"
  if [[ "$dry_run" == "true" ]]; then
    run mkdir -p "$install_dir"
    run curl -fsSL "$archive_url" -o /tmp/bitrix-backup.tar.gz
    run tar -xzf /tmp/bitrix-backup.tar.gz --strip-components=1 -C "$install_dir"
    return 0
  fi
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  mkdir -p "$install_dir"
  curl -fsSL "$archive_url" -o "$tmp_dir/source.tar.gz"
  tar -xzf "$tmp_dir/source.tar.gz" --strip-components=1 -C "$install_dir"
  rm -rf "$tmp_dir"
  trap - EXIT
}

rewrite_generated_config_paths() {
  local config_path="$1"

  if [[ "$config_dir" == "/etc/bitrix-backup" ]]; then
    return 0
  fi
  if [[ "$dry_run" == "true" ]]; then
    run python3 - "$config_path" "$config_dir"
    return 0
  fi
  python3 - "$config_path" "$config_dir" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
config_dir = sys.argv[2].rstrip("/")
text = path.read_text(encoding="utf-8")
text = text.replace("/etc/bitrix-backup", config_dir)
path.write_text(text, encoding="utf-8")
PY
}

generate_restic_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48
  else
    head -c 48 /dev/urandom | base64
  fi
}

shell_single_quote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

create_restic_env_files() {
  local config_path="$1"
  local site_codes code env_file password quoted_password created_count=0

  if [[ "$generate_restic_passwords" != "true" ]]; then
    return 0
  fi
  if [[ "$dry_run" == "true" ]]; then
    printf '+ create missing per-site RESTIC_PASSWORD env files from %s\n' "$config_path"
    return 0
  fi

  site_codes="$(python3 "$install_dir/lib/config-query.py" "$config_path" enabled-site-codes)"
  while IFS= read -r code; do
    [[ -n "$code" ]] || continue
    env_file="$(python3 "$install_dir/lib/config-query.py" "$config_path" site-field "$code" env_file)"
    [[ -n "$env_file" ]] || continue
    if [[ -f "$env_file" ]]; then
      printf 'INFO: %s already exists; leaving it unchanged\n' "$env_file"
      continue
    fi
    mkdir -p "$(dirname "$env_file")"
    password="$(generate_restic_password)"
    quoted_password="$(shell_single_quote "$password")"
    (umask 077 && printf "RESTIC_PASSWORD='%s'\n" "$quoted_password" >"$env_file")
    chmod 600 "$env_file"
    created_count=$((created_count + 1))
    printf 'INFO: created RESTIC_PASSWORD env file for site %s: %s\n' "$code" "$env_file"
  done <<<"$site_codes"

  if [[ "$created_count" -gt 0 ]]; then
    printf 'INFO: generated %s RESTIC_PASSWORD env file(s); save these secrets securely\n' "$created_count"
  fi
}

need_root
check_supported_os

if [[ "$install_packages" == "true" ]]; then
  run dnf install -y restic mysql python3 python3-pyyaml php-cli curl rsync tar gzip
fi

if [[ -n "$source_dir" ]]; then
  copy_from_source_dir "$source_dir"
else
  download_from_github
fi

run chmod +x "$install_dir"/bin/bitrix-backup-*
run mkdir -p "$config_dir/sites"

if [[ ! -f "$config_dir/excludes.local" || "$dry_run" == "true" ]]; then
  run cp "$install_dir/config/excludes.default" "$config_dir/excludes.local"
else
  printf 'INFO: %s already exists; leaving it unchanged\n' "$config_dir/excludes.local"
fi

if [[ ! -f "$config_dir/sites.yml" || "$dry_run" == "true" ]]; then
  run "$install_dir/bin/bitrix-backup-discover" \
    --root "$bitrix_root" \
    --repo-prefix "$repo_prefix" \
    --output "$config_dir/sites.yml"
  rewrite_generated_config_paths "$config_dir/sites.yml"
else
  printf 'INFO: %s already exists; leaving it unchanged\n' "$config_dir/sites.yml"
fi

create_restic_env_files "$config_dir/sites.yml"

run mkdir -p "$systemd_dir"
run cp "$install_dir/systemd/bitrix-backup.service" "$systemd_dir/"
run cp "$install_dir/systemd/bitrix-backup.timer" "$systemd_dir/"

if [[ "$dry_run" == "true" || -x "$(command -v systemctl 2>/dev/null || true)" ]]; then
  run systemctl daemon-reload
elif [[ "$enable_systemd" == "true" ]]; then
  printf 'ERROR: systemctl is required to enable the timer; use --no-systemd-enable to skip\n' >&2
  exit 1
else
  printf 'INFO: systemctl not found; skipping daemon-reload\n'
fi

if [[ "$enable_systemd" == "true" ]]; then
  run systemctl enable --now bitrix-backup.timer
fi

cat <<EOF

BitrixVM backup installer finished.

Next steps:
1. Review $config_dir/sites.yml
2. Review generated root-only env files under $config_dir/sites/ and save their RESTIC_PASSWORD values securely
3. Run: $install_dir/bin/bitrix-backup-verify --config $config_dir/sites.yml
4. Run: $install_dir/bin/bitrix-backup-run --config $config_dir/sites.yml
EOF
