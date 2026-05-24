#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/install"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

if "$ROOT_DIR/install.sh" --dry-run >/dev/null 2>&1; then
  fail "installer accepted missing repo prefix"
fi

dry_output="$("$ROOT_DIR/install.sh" \
  --dry-run \
  --source-dir "$ROOT_DIR" \
  --repo-prefix sftp:backup@example:/srv/restic \
  --install-dir "$WORK_DIR/opt" \
  --config-dir "$WORK_DIR/etc" \
  --systemd-dir "$WORK_DIR/systemd" \
  --root "$WORK_DIR/home/bitrix" \
  --no-systemd-enable)"

printf '%s\n' "$dry_output" | grep -F "dnf install -y restic mysql python3 python3-pyyaml php-cli curl rsync tar gzip" >/dev/null || fail "dry-run missing package install"
printf '%s\n' "$dry_output" | grep -F "bitrix-backup-discover" >/dev/null || fail "dry-run missing discovery"
printf '%s\n' "$dry_output" | grep -F -- "--repo-prefix sftp:backup@example:/srv/restic" >/dev/null || fail "dry-run missing repo prefix"
printf '%s\n' "$dry_output" | grep -F "systemctl daemon-reload" >/dev/null || fail "dry-run missing systemd reload"
if printf '%s\n' "$dry_output" | grep -F "systemctl enable --now" >/dev/null; then
  fail "dry-run enabled systemd despite --no-systemd-enable"
fi

mkdir -p "$WORK_DIR/home/bitrix/www/bitrix"
cp "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix/.settings.php" "$WORK_DIR/home/bitrix/www/bitrix/.settings.php"

BITRIX_BACKUP_INSTALL_ALLOW_NON_ROOT=1 "$ROOT_DIR/install.sh" \
  --source-dir "$ROOT_DIR" \
  --repo-prefix sftp:backup@example:/srv/restic \
  --install-dir "$WORK_DIR/opt" \
  --config-dir "$WORK_DIR/etc" \
  --systemd-dir "$WORK_DIR/systemd" \
  --root "$WORK_DIR/home/bitrix" \
  --skip-package-install \
  --skip-os-check \
  --no-systemd-enable >/dev/null

assert_file_executable "$WORK_DIR/opt/bin/bitrix-backup-run"
assert_contains 'repo: "sftp:backup@example:/srv/restic/www"' "$WORK_DIR/etc/sites.yml"
[[ -d "$WORK_DIR/etc/sites" ]] || fail "installer did not create sites config dir"
[[ -f "$WORK_DIR/etc/excludes.local" ]] || fail "installer did not create global excludes file"
assert_contains "/bitrix/cache" "$WORK_DIR/etc/excludes.local"
[[ -f "$WORK_DIR/etc/sites/www.env" ]] || fail "installer did not create site restic env file"
assert_contains "RESTIC_PASSWORD='" "$WORK_DIR/etc/sites/www.env"
env_mode="$(stat -f '%Lp' "$WORK_DIR/etc/sites/www.env" 2>/dev/null || stat -c '%a' "$WORK_DIR/etc/sites/www.env")"
[[ "$env_mode" == "600" ]] || fail "installer created env file with mode $env_mode"
[[ -f "$WORK_DIR/systemd/bitrix-backup.service" ]] || fail "installer did not copy systemd service"

printf 'custom-entry\n' >"$WORK_DIR/etc/excludes.local"
printf "RESTIC_PASSWORD='custom-password'\n" >"$WORK_DIR/etc/sites/www.env"
BITRIX_BACKUP_INSTALL_ALLOW_NON_ROOT=1 "$ROOT_DIR/install.sh" \
  --source-dir "$ROOT_DIR" \
  --repo-prefix sftp:backup@example:/srv/restic \
  --install-dir "$WORK_DIR/opt" \
  --config-dir "$WORK_DIR/etc" \
  --systemd-dir "$WORK_DIR/systemd" \
  --root "$WORK_DIR/home/bitrix" \
  --skip-package-install \
  --skip-os-check \
  --no-systemd-enable >/dev/null
assert_contains "custom-entry" "$WORK_DIR/etc/excludes.local"
assert_contains "custom-password" "$WORK_DIR/etc/sites/www.env"

rm -f "$WORK_DIR/etc/sites/www.env"
BITRIX_BACKUP_INSTALL_ALLOW_NON_ROOT=1 "$ROOT_DIR/install.sh" \
  --source-dir "$ROOT_DIR" \
  --repo-prefix sftp:backup@example:/srv/restic \
  --install-dir "$WORK_DIR/opt" \
  --config-dir "$WORK_DIR/etc" \
  --systemd-dir "$WORK_DIR/systemd" \
  --root "$WORK_DIR/home/bitrix" \
  --skip-package-install \
  --skip-os-check \
  --no-systemd-enable \
  --no-generate-restic-passwords >/dev/null
[[ ! -e "$WORK_DIR/etc/sites/www.env" ]] || fail "installer created env file despite --no-generate-restic-passwords"

printf 'ok - install\n'
