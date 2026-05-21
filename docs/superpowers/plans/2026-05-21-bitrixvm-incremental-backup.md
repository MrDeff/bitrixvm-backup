# BitrixVM Incremental Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build production-ready scripts for daily incremental backups of multiple 1C-Bitrix sites on BitrixVM/CentOS 9, with separate external restic repositories per site, separate file/database snapshots, default Bitrix exclusions, webhook reporting, verification, and staging restore.

**Architecture:** Bash command-line scripts orchestrate restic, mysqldump, curl, and systemd. Small helpers handle structured parsing: Python with PyYAML reads `sites.yml`, and PHP reads native Bitrix database config files without copying DB passwords into backup config. Tests run through a lightweight POSIX shell harness and use fixtures plus a local restic repository for integration coverage.

**Tech Stack:** Bash, PHP CLI, Python 3 + PyYAML, restic, mysqldump, curl, flock, systemd, shellcheck.

---

## File Structure

- Create `bin/bitrix-backup-discover`: scans `/home/bitrix/www` and `/home/bitrix/ext_www/*`, detects Bitrix sites, and writes draft YAML.
- Create `bin/bitrix-backup-run`: daily runner that processes enabled sites sequentially.
- Create `bin/bitrix-backup-verify`: validates dependencies, config, repos, and recent snapshots.
- Create `bin/bitrix-backup-restore`: restores files and/or database dump into staging paths.
- Create `lib/common.sh`: strict mode, path discovery, cleanup helpers.
- Create `lib/logging.sh`: timestamped logs and secret-safe messages.
- Create `lib/config.sh`: shell wrapper around YAML query helper.
- Create `lib/config-query.py`: PyYAML-based query helper for shell scripts.
- Create `lib/db-config.sh`: shell wrapper around Bitrix DB config reader.
- Create `lib/db-config-reader.php`: reads `.settings.php` and `dbconn.php`, emits JSON.
- Create `lib/excludes.sh`: merges default/global/per-site excludes into restic exclude files.
- Create `lib/mysql.sh`: creates temporary mysqldump files.
- Create `lib/restic.sh`: restic init/check/backup/forget/snapshot helpers.
- Create `lib/webhook.sh`: JSON payload and retrying webhook delivery.
- Create `config/sites.example.yml`: documented multi-site example.
- Create `config/excludes.default`: BitrixVM default exclude list.
- Create `config/excludes.local.example`: operator extension example.
- Create `systemd/bitrix-backup.service`: daily service unit.
- Create `systemd/bitrix-backup.timer`: daily timer unit.
- Create `docs/install.md`: installation and dependency guide.
- Create `docs/storage-sftp.md`: SFTP repository setup.
- Create `docs/storage-s3.md`: S3 repository setup.
- Create `docs/restore.md`: safe restore procedures.
- Create `tests/run.sh`: test harness.
- Create `tests/assert.sh`: assertions.
- Create fixture trees under `tests/fixtures/`.
- Create unit tests under `tests/unit/`.
- Create integration test under `tests/integration/`.

---

### Task 1: Bootstrap Project Skeleton and Test Harness

**Files:**
- Create: `bin/bitrix-backup-discover`
- Create: `bin/bitrix-backup-run`
- Create: `bin/bitrix-backup-verify`
- Create: `bin/bitrix-backup-restore`
- Create: `lib/common.sh`
- Create: `lib/logging.sh`
- Create: `tests/assert.sh`
- Create: `tests/run.sh`
- Create: `.gitignore`

- [ ] **Step 1: Write failing executable smoke tests**

Create `tests/assert.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_file_executable() {
  local path="$1"
  [[ -x "$path" ]] || fail "$path is not executable"
}

assert_contains() {
  local needle="$1"
  local path="$2"
  grep -F -- "$needle" "$path" >/dev/null || fail "$path does not contain $needle"
}
```

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

for script in \
  "$ROOT_DIR/bin/bitrix-backup-discover" \
  "$ROOT_DIR/bin/bitrix-backup-run" \
  "$ROOT_DIR/bin/bitrix-backup-verify" \
  "$ROOT_DIR/bin/bitrix-backup-restore"; do
  assert_file_executable "$script"
  "$script" --help | grep -E 'Usage:|usage:' >/dev/null || fail "$script --help lacks usage"
done

assert_contains "set -euo pipefail" "$ROOT_DIR/lib/common.sh"
assert_contains "log_info" "$ROOT_DIR/lib/logging.sh"

printf 'ok - smoke tests\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `bin/bitrix-backup-discover` does not exist or is not executable.

- [ ] **Step 3: Add minimal executable scripts and shared libraries**

Create each `bin/*` script with this pattern, replacing the script name in `usage`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"

usage() {
  cat <<'USAGE'
Usage: bitrix-backup-discover [--help]
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

usage
exit 2
```

Create `lib/common.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

bb_abspath() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    local dir
    dir="$(dirname "$path")"
    local base
    base="$(basename "$path")"
    printf '%s/%s\n' "$(cd "$dir" && pwd)" "$base"
  fi
}

bb_require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    return 1
  }
}
```

Create `lib/logging.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

log_ts() {
  date -Iseconds
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
```

Create `.gitignore`:

```gitignore
/tmp/
/.test-work/
config/sites.yml
*.env
```

Run:

```bash
chmod +x bin/bitrix-backup-discover bin/bitrix-backup-run bin/bitrix-backup-verify bin/bitrix-backup-restore tests/run.sh tests/assert.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
bash tests/run.sh
```

Expected: PASS with `ok - smoke tests`.

- [ ] **Step 5: Run shellcheck**

Run:

```bash
shellcheck bin/* lib/*.sh tests/*.sh
```

Expected: PASS with no output. If `shellcheck` is absent on the development host, record that and run it later on CentOS/CI.

- [ ] **Step 6: Commit**

```bash
git add .gitignore bin lib tests
git commit -m "chore: bootstrap backup scripts"
```

---

### Task 2: Implement YAML Config Querying

**Files:**
- Create: `lib/config-query.py`
- Create: `lib/config.sh`
- Create: `config/sites.example.yml`
- Modify: `tests/run.sh`
- Create: `tests/unit/config-query-test.sh`

- [ ] **Step 1: Write failing config tests**

Create `tests/unit/config-query-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/config-query"
mkdir -p "$WORK_DIR"
CONFIG="$WORK_DIR/sites.yml"

cat >"$CONFIG" <<'YAML'
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
sites:
  - code: example-com
    enabled: true
    path: /home/bitrix/ext_www/example.com
    repo: sftp:backup@example:/backups/example-com
    env_file: /etc/bitrix-backup/sites/example-com.env
    excludes:
      - /upload/import
      - "*.log"
  - code: disabled-site
    enabled: false
    path: /home/bitrix/ext_www/disabled.example
    repo: sftp:backup@example:/backups/disabled-site
YAML

enabled_codes="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" enabled-site-codes)"
[[ "$enabled_codes" == "example-com" ]] || fail "enabled-site-codes returned $enabled_codes"

site_json="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" site-json example-com)"
printf '%s\n' "$site_json" | grep '"code": "example-com"' >/dev/null || fail "site-json missing code"
printf '%s\n' "$site_json" | grep '"keep_daily": 3' >/dev/null || fail "site-json missing merged retention"

excludes="$(python3 "$ROOT_DIR/lib/config-query.py" "$CONFIG" site-excludes example-com)"
printf '%s\n' "$excludes" | grep '^/upload/import$' >/dev/null || fail "missing /upload/import exclude"
printf '%s\n' "$excludes" | grep '^\*.log$' >/dev/null || fail "missing *.log exclude"

printf 'ok - config query\n'
```

Modify `tests/run.sh` to execute all unit tests:

```bash
for test_script in "$ROOT_DIR"/tests/unit/*-test.sh; do
  [[ -e "$test_script" ]] || continue
  bash "$test_script"
done
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `lib/config-query.py` does not exist.

- [ ] **Step 3: Implement PyYAML config helper**

Create `lib/config-query.py`:

```python
#!/usr/bin/env python3
import json
import sys

try:
    import yaml
except ImportError:
    print("PyYAML is required: install python3-pyyaml", file=sys.stderr)
    sys.exit(3)


def load_config(path):
    with open(path, "r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    data.setdefault("defaults", {})
    data.setdefault("sites", [])
    return data


def merged_site(config, code):
    defaults = config.get("defaults", {})
    for site in config.get("sites", []):
        if site.get("code") == code:
            merged = dict(site)
            merged.setdefault("retention", defaults.get("retention", {}))
            merged.setdefault("default_excludes", defaults.get("default_excludes", True))
            if "global_exclude_file" not in merged and "global_exclude_file" in defaults:
                merged["global_exclude_file"] = defaults["global_exclude_file"]
            if "webhook_env_file" not in merged and "webhook_env_file" in defaults:
                merged["webhook_env_file"] = defaults["webhook_env_file"]
            return merged
    raise SystemExit(f"site not found: {code}")


def enabled_site_codes(config):
    return [site["code"] for site in config.get("sites", []) if site.get("enabled", True)]


def main(argv):
    if len(argv) < 3:
        print("Usage: config-query.py <sites.yml> <command> [args...]", file=sys.stderr)
        return 2
    config = load_config(argv[1])
    command = argv[2]
    if command == "enabled-site-codes":
        print("\n".join(enabled_site_codes(config)))
        return 0
    if command == "site-json":
        print(json.dumps(merged_site(config, argv[3]), ensure_ascii=False, sort_keys=True))
        return 0
    if command == "site-field":
        site = merged_site(config, argv[3])
        value = site.get(argv[4], "")
        if isinstance(value, (dict, list)):
            print(json.dumps(value, ensure_ascii=False, sort_keys=True))
        else:
            print(value)
        return 0
    if command == "site-excludes":
        site = merged_site(config, argv[3])
        print("\n".join(site.get("excludes", []) or []))
        return 0
    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

Create `lib/config.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

config_query() {
  local config_path="$1"
  shift
  python3 "$ROOT_DIR/lib/config-query.py" "$config_path" "$@"
}

config_enabled_site_codes() {
  config_query "$1" enabled-site-codes
}

config_site_json() {
  config_query "$1" site-json "$2"
}

config_site_field() {
  config_query "$1" site-field "$2" "$3"
}

config_site_excludes() {
  config_query "$1" site-excludes "$2"
}
```

Create `config/sites.example.yml` using the YAML shown in the design spec.

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
bash tests/run.sh
```

Expected: PASS including `ok - config query`.

- [ ] **Step 5: Run shellcheck**

Run:

```bash
shellcheck lib/config.sh tests/*.sh tests/unit/*.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/config-query.py lib/config.sh config/sites.example.yml tests/run.sh tests/unit/config-query-test.sh
git commit -m "feat: add backup config parsing"
```

---

### Task 3: Implement Bitrix Site Discovery and DB Config Reading

**Files:**
- Create: `lib/db-config-reader.php`
- Create: `lib/db-config.sh`
- Modify: `bin/bitrix-backup-discover`
- Create: `tests/fixtures/bitrix-settings-site/bitrix/.settings.php`
- Create: `tests/fixtures/bitrix-dbconn-site/bitrix/php_interface/dbconn.php`
- Create: `tests/unit/db-config-test.sh`
- Create: `tests/unit/discover-test.sh`

- [ ] **Step 1: Write failing DB config tests**

Create `tests/unit/db-config-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

settings_json="$(php "$ROOT_DIR/lib/db-config-reader.php" "$ROOT_DIR/tests/fixtures/bitrix-settings-site")"
printf '%s\n' "$settings_json" | grep '"database": "settings_db"' >/dev/null || fail "settings database not parsed"
printf '%s\n' "$settings_json" | grep '"login": "settings_user"' >/dev/null || fail "settings login not parsed"
printf '%s\n' "$settings_json" | grep '"password": "settings_pass"' >/dev/null || fail "settings password not parsed"

dbconn_json="$(php "$ROOT_DIR/lib/db-config-reader.php" "$ROOT_DIR/tests/fixtures/bitrix-dbconn-site")"
printf '%s\n' "$dbconn_json" | grep '"database": "dbconn_db"' >/dev/null || fail "dbconn database not parsed"
printf '%s\n' "$dbconn_json" | grep '"login": "dbconn_user"' >/dev/null || fail "dbconn login not parsed"
printf '%s\n' "$dbconn_json" | grep '"password": "dbconn_pass"' >/dev/null || fail "dbconn password not parsed"

printf 'ok - db config\n'
```

Create fixture `.settings.php`:

```php
<?php
return [
    'connections' => [
        'value' => [
            'default' => [
                'className' => '\\Bitrix\\Main\\DB\\MysqliConnection',
                'host' => 'localhost',
                'database' => 'settings_db',
                'login' => 'settings_user',
                'password' => 'settings_pass',
                'options' => 2,
            ],
        ],
    ],
];
```

Create fixture `dbconn.php`:

```php
<?php
$DBHost = 'localhost';
$DBName = 'dbconn_db';
$DBLogin = 'dbconn_user';
$DBPassword = 'dbconn_pass';
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `lib/db-config-reader.php` does not exist.

- [ ] **Step 3: Implement Bitrix DB config reader**

Create `lib/db-config-reader.php`:

```php
<?php
declare(strict_types=1);

if ($argc < 2) {
    fwrite(STDERR, "Usage: db-config-reader.php <site-root>\n");
    exit(2);
}

$siteRoot = rtrim($argv[1], '/');
$settingsPath = $siteRoot . '/bitrix/.settings.php';
$dbconnPath = $siteRoot . '/bitrix/php_interface/dbconn.php';

function emit_config(array $config): void
{
    echo json_encode($config, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
}

if (is_readable($settingsPath)) {
    $settings = include $settingsPath;
    $default = $settings['connections']['value']['default'] ?? null;
    if (is_array($default)) {
        emit_config([
            'host' => (string)($default['host'] ?? 'localhost'),
            'database' => (string)($default['database'] ?? ''),
            'login' => (string)($default['login'] ?? ''),
            'password' => (string)($default['password'] ?? ''),
            'source' => $settingsPath,
        ]);
        exit(0);
    }
}

if (is_readable($dbconnPath)) {
    $DBHost = 'localhost';
    $DBName = '';
    $DBLogin = '';
    $DBPassword = '';
    include $dbconnPath;
    emit_config([
        'host' => (string)$DBHost,
        'database' => (string)$DBName,
        'login' => (string)$DBLogin,
        'password' => (string)$DBPassword,
        'source' => $dbconnPath,
    ]);
    exit(0);
}

fwrite(STDERR, "No readable Bitrix database config found in {$siteRoot}\n");
exit(1);
```

Create `lib/db-config.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

db_config_json() {
  local site_root="$1"
  php "$ROOT_DIR/lib/db-config-reader.php" "$site_root"
}

db_config_field() {
  local site_root="$1"
  local field="$2"
  db_config_json "$site_root" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$field"
}
```

- [ ] **Step 4: Write failing discovery test**

Create `tests/unit/discover-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/discover"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/home/bitrix/www/bitrix" "$WORK_DIR/home/bitrix/ext_www/example.com"
cp -R "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix" "$WORK_DIR/home/bitrix/www/"
cp -R "$ROOT_DIR/tests/fixtures/bitrix-dbconn-site/bitrix" "$WORK_DIR/home/bitrix/ext_www/example.com/"

OUTPUT="$WORK_DIR/sites.yml"
"$ROOT_DIR/bin/bitrix-backup-discover" --root "$WORK_DIR/home/bitrix" --output "$OUTPUT" --repo-prefix "sftp:backup@example:/backups"

assert_contains "code: www" "$OUTPUT"
assert_contains "path: $WORK_DIR/home/bitrix/www" "$OUTPUT"
assert_contains "code: example-com" "$OUTPUT"
assert_contains "repo: sftp:backup@example:/backups/example-com" "$OUTPUT"
if grep -E 'settings_pass|dbconn_pass' "$OUTPUT" >/dev/null; then
  fail "discovery leaked database password"
fi

printf 'ok - discovery\n'
```

- [ ] **Step 5: Implement discovery**

Replace `bin/bitrix-backup-discover` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"

usage() {
  cat <<'USAGE'
Usage: bitrix-backup-discover --output config/sites.yml --repo-prefix <restic-prefix> [--root /home/bitrix]
USAGE
}

root="/home/bitrix"
output=""
repo_prefix=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --root) root="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --repo-prefix) repo_prefix="$2"; shift 2 ;;
    *) log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ -n "$output" ]] || { log_error "--output is required"; exit 2; }
[[ -n "$repo_prefix" ]] || { log_error "--repo-prefix is required"; exit 2; }

site_code() {
  local name="$1"
  printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//'
}

is_bitrix_site() {
  local path="$1"
  [[ -r "$path/bitrix/.settings.php" || -r "$path/bitrix/php_interface/dbconn.php" ]]
}

{
  cat <<YAML
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
  global_exclude_file: /etc/bitrix-backup/excludes.local
  webhook_env_file: /etc/bitrix-backup/webhook.env

sites:
YAML

  candidates=("$root/www")
  if [[ -d "$root/ext_www" ]]; then
    while IFS= read -r -d '' site_dir; do
      candidates+=("$site_dir")
    done < <(find "$root/ext_www" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  fi

  for site_path in "${candidates[@]}"; do
    [[ -d "$site_path" ]] || continue
    is_bitrix_site "$site_path" || continue
    base="$(basename "$site_path")"
    [[ "$base" == "www" ]] && code="www" || code="$(site_code "$base")"
    cat <<YAML
  - code: $code
    enabled: true
    path: $site_path
    repo: $repo_prefix/$code
    env_file: /etc/bitrix-backup/sites/$code.env
    db_config:
      auto_detect: true
    excludes: []
YAML
  done
} >"$output"
```

- [ ] **Step 6: Run tests and shellcheck**

Run:

```bash
bash tests/run.sh
shellcheck bin/bitrix-backup-discover lib/*.sh tests/*.sh tests/unit/*.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add bin/bitrix-backup-discover lib/db-config-reader.php lib/db-config.sh tests/fixtures tests/unit/db-config-test.sh tests/unit/discover-test.sh
git commit -m "feat: discover bitrix sites and database configs"
```

---

### Task 4: Implement Exclude Merging

**Files:**
- Create: `config/excludes.default`
- Create: `config/excludes.local.example`
- Create: `lib/excludes.sh`
- Create: `tests/unit/excludes-test.sh`

- [ ] **Step 1: Write failing exclude merge test**

Create `tests/unit/excludes-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/excludes.sh"

WORK_DIR="$ROOT_DIR/.test-work/excludes"
mkdir -p "$WORK_DIR"
global_file="$WORK_DIR/global.exclude"
output_file="$WORK_DIR/effective.exclude"

cat >"$global_file" <<'EOF'
/upload/import
*.tmp
EOF

build_exclude_file true "$global_file" "$output_file" "/local/cache" "*.log"

assert_contains "/bitrix/cache" "$output_file"
assert_contains "/upload/resize_cache" "$output_file"
assert_contains "/upload/import" "$output_file"
assert_contains "*.tmp" "$output_file"
assert_contains "/local/cache" "$output_file"
assert_contains "*.log" "$output_file"

printf 'ok - excludes\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `lib/excludes.sh` or `build_exclude_file` does not exist.

- [ ] **Step 3: Implement default excludes and merge function**

Create `config/excludes.default`:

```text
/bitrix/cache
/bitrix/managed_cache
/bitrix/stack_cache
/bitrix/local_cache
/bitrix/backup
/bitrix/tmp
/upload/tmp
/upload/resize_cache
```

Create `config/excludes.local.example`:

```text
# One pattern per line. Examples:
# /upload/import
# *.log
# *.tmp
```

Create `lib/excludes.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

build_exclude_file() {
  local use_defaults="$1"
  local global_file="$2"
  local output_file="$3"
  shift 3

  : >"$output_file"

  if [[ "$use_defaults" == "true" ]]; then
    cat "$ROOT_DIR/config/excludes.default" >>"$output_file"
  fi

  if [[ -n "$global_file" && -r "$global_file" ]]; then
    cat "$global_file" >>"$output_file"
  fi

  local pattern
  for pattern in "$@"; do
    [[ -n "$pattern" ]] || continue
    printf '%s\n' "$pattern" >>"$output_file"
  done

  awk 'NF && $0 !~ /^#/ && !seen[$0]++ { print }' "$output_file" >"$output_file.tmp"
  mv "$output_file.tmp" "$output_file"
}
```

- [ ] **Step 4: Run tests and shellcheck**

Run:

```bash
bash tests/run.sh
shellcheck lib/excludes.sh tests/unit/excludes-test.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/excludes.default config/excludes.local.example lib/excludes.sh tests/unit/excludes-test.sh
git commit -m "feat: add bitrix backup exclusions"
```

---

### Task 5: Implement Restic and MySQL Backup Primitives

**Files:**
- Create: `lib/restic.sh`
- Create: `lib/mysql.sh`
- Create: `tests/unit/restic-test.sh`
- Create: `tests/unit/mysql-test.sh`

- [ ] **Step 1: Write failing restic command tests**

Create `tests/unit/restic-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/restic.sh"

cmd="$(restic_forget_command "kind:db" 3 1 1)"
[[ "$cmd" == "forget --tag kind:db --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune" ]] || fail "unexpected forget command: $cmd"

printf 'ok - restic helpers\n'
```

Create `tests/unit/mysql-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/mysql.sh"

defaults_file="$ROOT_DIR/.test-work/mysql/client.cnf"
mkdir -p "$(dirname "$defaults_file")"
write_mysql_defaults_file "$defaults_file" "localhost" "bitrix_user" "secret"

assert_contains "[client]" "$defaults_file"
assert_contains "host=localhost" "$defaults_file"
assert_contains "user=bitrix_user" "$defaults_file"
assert_contains "password=secret" "$defaults_file"

mode="$(stat -f '%Lp' "$defaults_file" 2>/dev/null || stat -c '%a' "$defaults_file")"
[[ "$mode" == "600" ]] || fail "mysql defaults file mode is $mode"

printf 'ok - mysql helpers\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because helper functions are missing.

- [ ] **Step 3: Implement restic helpers**

Create `lib/restic.sh`:

```bash
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
  printf 'forget --tag %s --keep-daily %s --keep-weekly %s --keep-monthly %s --prune\n' \
    "$tag" "$keep_daily" "$keep_weekly" "$keep_monthly"
}

restic_apply_retention() {
  local repo="$1"
  local tag="$2"
  local keep_daily="$3"
  local keep_weekly="$4"
  local keep_monthly="$5"
  restic_base "$repo" forget --tag "$tag" --keep-daily "$keep_daily" --keep-weekly "$keep_weekly" --keep-monthly "$keep_monthly" --prune
}

restic_latest_snapshot_id() {
  local repo="$1"
  local tag="$2"
  restic_base "$repo" snapshots --json --last --tag "$tag" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data[-1]["short_id"] if data else "")'
}
```

Create `lib/mysql.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

write_mysql_defaults_file() {
  local output="$1"
  local host="$2"
  local user="$3"
  local password="$4"
  umask 077
  cat >"$output" <<EOF
[client]
host=$host
user=$user
password=$password
EOF
  chmod 600 "$output"
}

dump_mysql_database() {
  local defaults_file="$1"
  local database="$2"
  local output="$3"
  mysqldump --defaults-extra-file="$defaults_file" --single-transaction --quick --routines --triggers --events "$database" >"$output"
}
```

- [ ] **Step 4: Run tests and shellcheck**

Run:

```bash
bash tests/run.sh
shellcheck lib/restic.sh lib/mysql.sh tests/unit/restic-test.sh tests/unit/mysql-test.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/restic.sh lib/mysql.sh tests/unit/restic-test.sh tests/unit/mysql-test.sh
git commit -m "feat: add restic and mysql helpers"
```

---

### Task 6: Implement Webhook Reporting

**Files:**
- Create: `lib/webhook.sh`
- Create: `tests/unit/webhook-test.sh`

- [ ] **Step 1: Write failing webhook payload test**

Create `tests/unit/webhook-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"
source "$ROOT_DIR/lib/webhook.sh"

payload="$(webhook_payload "example-com" "vm01" "success" "2026-05-21T02:00:00+07:00" "2026-05-21T02:01:00+07:00" "60" "files123" "db123" "")"

printf '%s\n' "$payload" | grep '"site": "example-com"' >/dev/null || fail "payload missing site"
printf '%s\n' "$payload" | grep '"status": "success"' >/dev/null || fail "payload missing status"
printf '%s\n' "$payload" | grep '"files_snapshot_id": "files123"' >/dev/null || fail "payload missing files snapshot"
printf '%s\n' "$payload" | grep '"error": null' >/dev/null || fail "payload missing null error"

failed="$(webhook_payload "example-com" "vm01" "failed" "s" "f" "1" "" "" "password=secret failed")"
printf '%s\n' "$failed" | grep 'password=' >/dev/null && fail "payload leaked password pattern"

printf 'ok - webhook\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `lib/webhook.sh` does not exist.

- [ ] **Step 3: Implement webhook JSON and retry delivery**

Create `lib/webhook.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

sanitize_error() {
  local message="$1"
  printf '%s\n' "$message" | sed -E 's/(password|secret|token|key)=([^ ]+)/\1=REDACTED/Ig'
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

  python3 - "$site" "$host" "$status" "$started_at" "$finished_at" "$duration_seconds" "$files_snapshot_id" "$db_snapshot_id" "$(sanitize_error "$error")" <<'PY'
import json
import sys

site, host, status, started_at, finished_at, duration, files_id, db_id, error = sys.argv[1:]
payload = {
    "site": site,
    "host": host,
    "status": status,
    "started_at": started_at,
    "finished_at": finished_at,
    "duration_seconds": int(duration),
    "files_snapshot_id": files_id or None,
    "db_snapshot_id": db_id or None,
    "error": error or None,
}
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
}

send_webhook() {
  local url="$1"
  local token="$2"
  local payload="$3"
  local attempt
  for attempt in 1 2 3; do
    if [[ -n "$token" ]]; then
      curl -fsS -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $token" --data "$payload" "$url" >/dev/null && return 0
    else
      curl -fsS -X POST -H "Content-Type: application/json" --data "$payload" "$url" >/dev/null && return 0
    fi
    sleep "$attempt"
  done
  return 1
}
```

- [ ] **Step 4: Run tests and shellcheck**

Run:

```bash
bash tests/run.sh
shellcheck lib/webhook.sh tests/unit/webhook-test.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/webhook.sh tests/unit/webhook-test.sh
git commit -m "feat: add per-site webhook reporting"
```

---

### Task 7: Implement Daily Backup Runner

**Files:**
- Modify: `bin/bitrix-backup-run`
- Modify: `lib/config-query.py`
- Create: `tests/unit/runner-dry-run-test.sh`

- [ ] **Step 1: Write failing runner dry-run test**

Create `tests/unit/runner-dry-run-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/runner"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/site/bitrix" "$WORK_DIR/etc/sites"
cp "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix/.settings.php" "$WORK_DIR/site/bitrix/.settings.php"

cat >"$WORK_DIR/site.env" <<'EOF'
RESTIC_PASSWORD=test-password
EOF

cat >"$WORK_DIR/sites.yml" <<YAML
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/restic-repo
    env_file: $WORK_DIR/site.env
    excludes:
      - /upload/import
YAML

output="$("$ROOT_DIR/bin/bitrix-backup-run" --config "$WORK_DIR/sites.yml" --dry-run)"

printf '%s\n' "$output" | grep 'DRY-RUN site=example-com step=db-backup' >/dev/null || fail "missing db dry-run"
printf '%s\n' "$output" | grep 'DRY-RUN site=example-com step=files-backup' >/dev/null || fail "missing files dry-run"
printf '%s\n' "$output" | grep 'DRY-RUN site=example-com step=retention kind:db' >/dev/null || fail "missing db retention dry-run"

printf 'ok - runner dry-run\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `bitrix-backup-run --dry-run` is still absent from the initial usage stub.

- [ ] **Step 3: Add JSON field extraction to config helper**

Extend `lib/config-query.py` with command `site-retention-field`:

```python
    if command == "site-retention-field":
        site = merged_site(config, argv[3])
        print(site.get("retention", {}).get(argv[4], ""))
        return 0
```

Extend `lib/config.sh`:

```bash
config_site_retention_field() {
  config_query "$1" site-retention-field "$2" "$3"
}
```

- [ ] **Step 4: Implement backup runner**

Replace `bin/bitrix-backup-run` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/db-config.sh"
source "$ROOT_DIR/lib/excludes.sh"
source "$ROOT_DIR/lib/mysql.sh"
source "$ROOT_DIR/lib/restic.sh"
source "$ROOT_DIR/lib/webhook.sh"

usage() {
  cat <<'USAGE'
Usage: bitrix-backup-run --config /etc/bitrix-backup/sites.yml [--dry-run]
USAGE
}

config=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --config) config="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ -n "$config" ]] || { log_error "--config is required"; exit 2; }

host_name="$(hostname -f 2>/dev/null || hostname)"
tmp_root="${BITRIX_BACKUP_TMP:-/var/tmp/bitrix-backup}"
mkdir -p "$tmp_root"

run_site() {
  local code="$1"
  local started_at finished_at start_epoch finish_epoch duration
  local site_path repo env_file global_exclude_file use_default_excludes
  local keep_daily keep_weekly keep_monthly
  local work_dir defaults_file dump_file exclude_file
  local files_snapshot_id="" db_snapshot_id="" status="success" error=""

  started_at="$(date -Iseconds)"
  start_epoch="$(date +%s)"

  site_path="$(config_site_field "$config" "$code" path)"
  repo="$(config_site_field "$config" "$code" repo)"
  env_file="$(config_site_field "$config" "$code" env_file)"
  global_exclude_file="$(config_site_field "$config" "$code" global_exclude_file)"
  use_default_excludes="$(config_site_field "$config" "$code" default_excludes)"
  keep_daily="$(config_site_retention_field "$config" "$code" keep_daily)"
  keep_weekly="$(config_site_retention_field "$config" "$code" keep_weekly)"
  keep_monthly="$(config_site_retention_field "$config" "$code" keep_monthly)"

  if [[ "$dry_run" == "true" ]]; then
    printf 'DRY-RUN site=%s step=db-backup repo=%s\n' "$code" "$repo"
    printf 'DRY-RUN site=%s step=files-backup path=%s repo=%s\n' "$code" "$site_path" "$repo"
    printf 'DRY-RUN site=%s step=retention kind:db daily=%s weekly=%s monthly=%s\n' "$code" "$keep_daily" "$keep_weekly" "$keep_monthly"
    printf 'DRY-RUN site=%s step=retention kind:files daily=%s weekly=%s monthly=%s\n' "$code" "$keep_daily" "$keep_weekly" "$keep_monthly"
    return 0
  fi

  work_dir="$(mktemp -d "$tmp_root/$code.XXXXXX")"
  defaults_file="$work_dir/mysql.cnf"
  dump_file="$work_dir/db.sql"
  exclude_file="$work_dir/excludes.txt"

  cleanup_site() {
    rm -rf "$work_dir"
  }
  trap cleanup_site RETURN

  if ! (
    source "$env_file"
    db_json="$(db_config_json "$site_path")"
    db_host="$(printf '%s\n' "$db_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["host"])')"
    db_name="$(printf '%s\n' "$db_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["database"])')"
    db_user="$(printf '%s\n' "$db_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["login"])')"
    db_pass="$(printf '%s\n' "$db_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"

    restic_init_if_needed "$repo"
    write_mysql_defaults_file "$defaults_file" "$db_host" "$db_user" "$db_pass"
    dump_mysql_database "$defaults_file" "$db_name" "$dump_file"
    restic_backup_path "$repo" "$dump_file" "$host_name" "kind:db"
    db_snapshot_id="$(restic_latest_snapshot_id "$repo" "kind:db")"

    mapfile -t site_excludes < <(config_site_excludes "$config" "$code")
    build_exclude_file "$use_default_excludes" "$global_exclude_file" "$exclude_file" "${site_excludes[@]}"
    (cd "$site_path" && restic_backup_path "$repo" "." "$host_name" "kind:files" --exclude-file "$exclude_file")
    files_snapshot_id="$(restic_latest_snapshot_id "$repo" "kind:files")"

    restic_apply_retention "$repo" "kind:db" "$keep_daily" "$keep_weekly" "$keep_monthly"
    restic_apply_retention "$repo" "kind:files" "$keep_daily" "$keep_weekly" "$keep_monthly"
  ); then
    status="failed"
    error="backup failed for site $code"
  fi

  finished_at="$(date -Iseconds)"
  finish_epoch="$(date +%s)"
  duration="$((finish_epoch - start_epoch))"

  webhook_env_file="$(config_site_field "$config" "$code" webhook_env_file)"
  if [[ -n "${webhook_env_file:-}" && -r "$webhook_env_file" ]]; then
    source "$webhook_env_file"
    payload="$(webhook_payload "$code" "$host_name" "$status" "$started_at" "$finished_at" "$duration" "$files_snapshot_id" "$db_snapshot_id" "$error")"
    send_webhook "${WEBHOOK_URL:-}" "${WEBHOOK_TOKEN:-}" "$payload" || log_warn "Webhook delivery failed for $code"
  fi

  [[ "$status" == "success" ]]
}

while IFS= read -r code; do
  [[ -n "$code" ]] || continue
  run_site "$code" || log_error "Site backup failed: $code"
done < <(config_enabled_site_codes "$config")
```

- [ ] **Step 5: Run tests and shellcheck**

Run:

```bash
bash tests/run.sh
shellcheck bin/bitrix-backup-run lib/*.sh tests/unit/runner-dry-run-test.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bin/bitrix-backup-run lib/config-query.py lib/config.sh tests/unit/runner-dry-run-test.sh
git commit -m "feat: implement backup runner"
```

---

### Task 8: Implement Verification Command

**Files:**
- Modify: `bin/bitrix-backup-verify`
- Create: `tests/unit/verify-test.sh`

- [ ] **Step 1: Write failing verify dry-run test**

Create `tests/unit/verify-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/verify"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/site/bitrix"
cp "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix/.settings.php" "$WORK_DIR/site/bitrix/.settings.php"
cat >"$WORK_DIR/site.env" <<'EOF'
RESTIC_PASSWORD=test-password
EOF
chmod 600 "$WORK_DIR/site.env"

cat >"$WORK_DIR/sites.yml" <<YAML
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: local:$WORK_DIR/repo
    env_file: $WORK_DIR/site.env
YAML

output="$("$ROOT_DIR/bin/bitrix-backup-verify" --config "$WORK_DIR/sites.yml" --offline)"
printf '%s\n' "$output" | grep 'OK config readable' >/dev/null || fail "missing config check"
printf '%s\n' "$output" | grep 'OK site example-com db config readable' >/dev/null || fail "missing db config check"
printf '%s\n' "$output" | grep 'OK site example-com env file mode' >/dev/null || fail "missing env mode check"

printf 'ok - verify\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because `--offline` verification is still absent from the initial usage stub.

- [ ] **Step 3: Implement verify command**

Replace `bin/bitrix-backup-verify` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/db-config.sh"
source "$ROOT_DIR/lib/restic.sh"

usage() {
  cat <<'USAGE'
Usage: bitrix-backup-verify --config /etc/bitrix-backup/sites.yml [--offline]
USAGE
}

config=""
offline=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --config) config="$2"; shift 2 ;;
    --offline) offline=true; shift ;;
    *) log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ -r "$config" ]] || { log_error "Config is not readable: $config"; exit 1; }
printf 'OK config readable\n'

for command_name in python3 php curl; do
  bb_require_command "$command_name"
done
if [[ "$offline" != "true" ]]; then
  for command_name in restic mysql mysqldump; do
    bb_require_command "$command_name"
  done
fi

while IFS= read -r code; do
  site_path="$(config_site_field "$config" "$code" path)"
  env_file="$(config_site_field "$config" "$code" env_file)"
  repo="$(config_site_field "$config" "$code" repo)"

  db_config_json "$site_path" >/dev/null
  printf 'OK site %s db config readable\n' "$code"

  [[ -r "$env_file" ]] || { log_error "Env file is not readable for $code"; exit 1; }
  mode="$(stat -f '%Lp' "$env_file" 2>/dev/null || stat -c '%a' "$env_file")"
  [[ "$mode" == "600" ]] || { log_error "Env file mode must be 600 for $code: $mode"; exit 1; }
  printf 'OK site %s env file mode\n' "$code"

  if [[ "$offline" != "true" ]]; then
    source "$env_file"
    restic_base "$repo" snapshots --tag kind:db >/dev/null
    restic_base "$repo" snapshots --tag kind:files >/dev/null
    printf 'OK site %s restic snapshots readable\n' "$code"
  fi
done < <(config_enabled_site_codes "$config")
```

- [ ] **Step 4: Run tests and shellcheck**

Run:

```bash
bash tests/run.sh
shellcheck bin/bitrix-backup-verify
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/bitrix-backup-verify tests/unit/verify-test.sh
git commit -m "feat: add backup verification command"
```

---

### Task 9: Implement Restore Command and Integration Test

**Files:**
- Modify: `bin/bitrix-backup-restore`
- Create: `tests/integration/restic-local-test.sh`
- Modify: `tests/run.sh`

- [ ] **Step 1: Write failing restore integration test**

Create `tests/integration/restic-local-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

command -v restic >/dev/null 2>&1 || {
  printf 'skip - restic is not installed\n'
  exit 0
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

WORK_DIR="$ROOT_DIR/.test-work/integration"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/site/bitrix" "$WORK_DIR/site/upload" "$WORK_DIR/restore"
cp "$ROOT_DIR/tests/fixtures/bitrix-settings-site/bitrix/.settings.php" "$WORK_DIR/site/bitrix/.settings.php"
printf 'hello\n' >"$WORK_DIR/site/index.php"
printf 'cache\n' >"$WORK_DIR/site/bitrix/cache"

cat >"$WORK_DIR/site.env" <<'EOF'
RESTIC_PASSWORD=test-password
EOF
chmod 600 "$WORK_DIR/site.env"

cat >"$WORK_DIR/sites.yml" <<YAML
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
sites:
  - code: example-com
    enabled: true
    path: $WORK_DIR/site
    repo: $WORK_DIR/repo
    env_file: $WORK_DIR/site.env
YAML

RESTIC_PASSWORD=test-password restic -r "$WORK_DIR/repo" init >/dev/null
RESTIC_PASSWORD=test-password restic -r "$WORK_DIR/repo" backup "$WORK_DIR/site/index.php" --tag kind:files >/dev/null
printf 'create table test(id int);\n' >"$WORK_DIR/db.sql"
RESTIC_PASSWORD=test-password restic -r "$WORK_DIR/repo" backup "$WORK_DIR/db.sql" --tag kind:db >/dev/null

"$ROOT_DIR/bin/bitrix-backup-restore" --config "$WORK_DIR/sites.yml" --site example-com --kind both --target "$WORK_DIR/restore"

[[ -f "$WORK_DIR/restore/example-com/files/index.php" ]] || fail "restored file missing"
[[ -f "$WORK_DIR/restore/example-com/db/db.sql" ]] || fail "restored db dump missing"

printf 'ok - restic local integration\n'
```

Modify `tests/run.sh`:

```bash
if [[ "${RUN_INTEGRATION:-0}" == "1" ]]; then
  for test_script in "$ROOT_DIR"/tests/integration/*-test.sh; do
    [[ -e "$test_script" ]] || continue
    bash "$test_script"
  done
fi
```

- [ ] **Step 2: Run integration test to verify it fails**

Run:

```bash
RUN_INTEGRATION=1 bash tests/run.sh
```

Expected: FAIL because restore command still has only the initial usage stub, or SKIP if restic is not installed.

- [ ] **Step 3: Implement restore command**

Replace `bin/bitrix-backup-restore` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/logging.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/restic.sh"

usage() {
  cat <<'USAGE'
Usage: bitrix-backup-restore --config sites.yml --site <code> --kind files|db|both --target /restore [--snapshot latest]
USAGE
}

config=""
site=""
kind="both"
target="/restore"
snapshot="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --config) config="$2"; shift 2 ;;
    --site) site="$2"; shift 2 ;;
    --kind) kind="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    --snapshot) snapshot="$2"; shift 2 ;;
    *) log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ -n "$config" && -n "$site" ]] || { usage; exit 2; }
repo="$(config_site_field "$config" "$site" repo)"
env_file="$(config_site_field "$config" "$site" env_file)"
source "$env_file"

restore_files() {
  local output="$target/$site/files"
  mkdir -p "$output"
  restic_base "$repo" restore "$snapshot" --tag kind:files --target "$output"
}

restore_db() {
  local output="$target/$site/db"
  mkdir -p "$output"
  restic_base "$repo" restore "$snapshot" --tag kind:db --target "$output"
}

case "$kind" in
  files) restore_files ;;
  db) restore_db ;;
  both) restore_files; restore_db ;;
  *) log_error "Invalid kind: $kind"; exit 2 ;;
esac
```

- [ ] **Step 4: Run unit and integration tests**

Run:

```bash
bash tests/run.sh
RUN_INTEGRATION=1 bash tests/run.sh
shellcheck bin/bitrix-backup-restore tests/integration/restic-local-test.sh
```

Expected: unit tests PASS; integration PASS when restic is installed, otherwise SKIP.

- [ ] **Step 5: Commit**

```bash
git add bin/bitrix-backup-restore tests/run.sh tests/integration/restic-local-test.sh
git commit -m "feat: add staging restore command"
```

---

### Task 10: Add systemd Units and Operator Documentation

**Files:**
- Create: `systemd/bitrix-backup.service`
- Create: `systemd/bitrix-backup.timer`
- Create: `docs/install.md`
- Create: `docs/storage-sftp.md`
- Create: `docs/storage-s3.md`
- Create: `docs/restore.md`
- Create: `tests/unit/docs-test.sh`

- [ ] **Step 1: Write failing docs/systemd presence test**

Create `tests/unit/docs-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/assert.sh"

assert_contains "ExecStart=/opt/bitrix-backup/bin/bitrix-backup-run" "$ROOT_DIR/systemd/bitrix-backup.service"
assert_contains "OnCalendar=" "$ROOT_DIR/systemd/bitrix-backup.timer"
assert_contains "python3-pyyaml" "$ROOT_DIR/docs/install.md"
assert_contains "restic init" "$ROOT_DIR/docs/storage-sftp.md"
assert_contains "AWS_ACCESS_KEY_ID" "$ROOT_DIR/docs/storage-s3.md"
assert_contains "bitrix-backup-restore" "$ROOT_DIR/docs/restore.md"

printf 'ok - docs and systemd\n'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run.sh
```

Expected: FAIL because systemd units and docs do not exist.

- [ ] **Step 3: Add systemd units**

Create `systemd/bitrix-backup.service`:

```ini
[Unit]
Description=BitrixVM incremental site backups
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=root
Group=root
WorkingDirectory=/opt/bitrix-backup
ExecStart=/opt/bitrix-backup/bin/bitrix-backup-run --config /etc/bitrix-backup/sites.yml
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
```

Create `systemd/bitrix-backup.timer`:

```ini
[Unit]
Description=Run BitrixVM incremental site backups daily

[Timer]
OnCalendar=*-*-* 03:15:00
Persistent=true
RandomizedDelaySec=20m

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: Add operator docs**

Create `docs/install.md`:

````markdown
# Install

Install dependencies on CentOS Stream 9 / BitrixVM 9:

```bash
dnf install -y restic mysql python3 python3-pyyaml php-cli curl
```

Copy the project to `/opt/bitrix-backup`, create `/etc/bitrix-backup`, and generate initial config:

```bash
/opt/bitrix-backup/bin/bitrix-backup-discover \
  --output /etc/bitrix-backup/sites.yml \
  --repo-prefix sftp:backup@example.org:/backups/bitrix
```

Create one env file per site with mode `600` and at least `RESTIC_PASSWORD`.

Enable systemd timer:

```bash
cp /opt/bitrix-backup/systemd/bitrix-backup.* /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bitrix-backup.timer
```
````

Create `docs/storage-sftp.md`:

````markdown
# SFTP Storage

Example site env file:

```bash
RESTIC_PASSWORD='change-me'
```

Initialize a repository manually if desired:

```bash
RESTIC_PASSWORD='change-me' restic -r sftp:backup@example.org:/backups/bitrix/example-com init
```

The runner also initializes an empty repository when it cannot read snapshots.
````

Create `docs/storage-s3.md`:

````markdown
# S3 Storage

Example site env file:

```bash
RESTIC_PASSWORD='change-me'
AWS_ACCESS_KEY_ID='access-key'
AWS_SECRET_ACCESS_KEY='secret-key'
AWS_DEFAULT_REGION='ru-central1'
```

Example repository:

```text
s3:s3.amazonaws.com/bucket-name/example-com
```
````

Create `docs/restore.md`:

````markdown
# Restore

Restore never writes into production paths by default.

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore
```

Files are restored under `/restore/example-com/files`.
Database snapshots are restored under `/restore/example-com/db`.
Inspect the result and import/copy manually during a controlled maintenance window.
````

- [ ] **Step 5: Run tests**

Run:

```bash
bash tests/run.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add systemd docs tests/unit/docs-test.sh
git commit -m "docs: add installation and restore guide"
```

---

### Task 11: Final Verification and Packaging Review

**Files:**
- Modify as needed based on verification results.

- [ ] **Step 1: Run full unit suite**

Run:

```bash
bash tests/run.sh
```

Expected: PASS for all unit tests.

- [ ] **Step 2: Run integration suite**

Run:

```bash
RUN_INTEGRATION=1 bash tests/run.sh
```

Expected: PASS if restic is installed; SKIP only for integration tests when restic is unavailable.

- [ ] **Step 3: Run shellcheck across all scripts**

Run:

```bash
shellcheck bin/* lib/*.sh tests/*.sh tests/unit/*.sh tests/integration/*.sh
```

Expected: PASS with no warnings.

- [ ] **Step 4: Verify no secrets or generated local config are tracked**

Run:

```bash
git status --short
git ls-files | grep -E '(^|/)(sites.yml|.*\.env)$' && exit 1 || true
```

Expected: `git status --short` has only intended source/doc changes, and no `sites.yml` or `.env` files are tracked.

- [ ] **Step 5: Review spec coverage**

Confirm these requirements have implementation and tests:

```text
separate restic repo per site
daily DB backup path
daily file backup path
DB credentials read from Bitrix config
default BitrixVM exclusions
custom global and per-site exclusions
per-site webhook
retention: 3 daily, 1 weekly, 1 monthly
SFTP/S3 env support
no built-in Bitrix backup.php
restore to staging by default
```

- [ ] **Step 6: Final commit if verification caused changes**

```bash
git add .
git commit -m "chore: finalize bitrix backup scripts"
```
