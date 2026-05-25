# BitrixVM Backup

Incremental backup tooling for CentOS Stream 9 / BitrixVM 9 hosts running 1C-Bitrix sites.

The project backs up each site into its own restic repository. Database and file snapshots are stored separately, credentials are read from the site's Bitrix configuration, and durable backup data is written to external SFTP or S3-compatible storage.

The built-in 1C-Bitrix backup mechanism is intentionally not used.

## What It Does

- Discovers Bitrix sites under BitrixVM-style paths.
- Reads database credentials from `bitrix/.settings.php` or `bitrix/php_interface/dbconn.php`.
- Creates separate restic snapshots for `kind:db` and `kind:files`.
- Applies retention independently to DB and file snapshots: 3 daily, 1 weekly, 1 monthly by default.
- Uses default Bitrix cache/temp exclusions, plus global and per-site custom exclusions.
- Sends a per-site webhook after each backup attempt.
- Restores files and database dumps into a staging directory for operator review.

## Repository Layout

```text
bin/       CLI entrypoints for discover, run, verify, and restore
lib/       shared shell, Python, and PHP helpers
config/    example site config and default exclude lists
docs/      installation, storage, and restore guides
systemd/   service and timer units
tests/     unit and optional integration tests
```

## Quick Start

Install with one command as root:

```bash
curl -fsSL https://raw.githubusercontent.com/MrDeff/bitrixvm-backup/main/install.sh | bash -s -- \
  --repo-prefix sftp:backup@example-backup-host:/srv/restic
```

Preview planned actions without changing the system:

```bash
curl -fsSL https://raw.githubusercontent.com/MrDeff/bitrixvm-backup/main/install.sh | bash -s -- \
  --repo-prefix sftp:backup@example-backup-host:/srv/restic \
  --dry-run
```

The installer installs dependencies, downloads this repository to `/opt/bitrix-backup`, creates `/etc/bitrix-backup/sites`, writes `/etc/bitrix-backup/excludes.local` from the default exclude list when missing, creates `/etc/bitrix-backup/storage.env` for shared storage credentials, discovers Bitrix sites, creates missing per-site env files with generated `RESTIC_PASSWORD` values, installs systemd units, and enables the timer unless `--no-systemd-enable` is passed.

After installation, review `/etc/bitrix-backup/sites.yml`, fill `/etc/bitrix-backup/storage.env` with shared `AWS_*` values if needed, and save the generated `/etc/bitrix-backup/sites/*.env` secrets securely. Existing env files are never overwritten. Use `--no-generate-restic-passwords` when you want to create env files manually.

## Manual Install

Install dependencies on the BitrixVM host:

```bash
dnf install -y restic mysql python3 python3-pyyaml php-cli curl rsync
```

Copy the repository to `/opt/bitrix-backup`:

```bash
mkdir -p /opt/bitrix-backup
rsync -a --delete ./ /opt/bitrix-backup/
chmod +x /opt/bitrix-backup/bin/bitrix-backup-*
```

Generate an initial config:

```bash
mkdir -p /etc/bitrix-backup/sites
/opt/bitrix-backup/bin/bitrix-backup-discover \
  --repo-prefix sftp:backup@example-backup-host:/srv/restic \
  --output /etc/bitrix-backup/sites.yml
```

When installing manually, create one root-only environment file per site repository:

```bash
install -m 600 /dev/null /etc/bitrix-backup/sites/example-com.env
cat >/etc/bitrix-backup/sites/example-com.env <<'ENV'
RESTIC_PASSWORD=change-this-long-random-secret
ENV
chmod 600 /etc/bitrix-backup/sites/example-com.env
```

Review `/etc/bitrix-backup/sites.yml`, initialize repositories if desired, and run:

```bash
/opt/bitrix-backup/bin/bitrix-backup-verify --config /etc/bitrix-backup/sites.yml
/opt/bitrix-backup/bin/bitrix-backup-run --config /etc/bitrix-backup/sites.yml
```

For scheduled operation, install the systemd units from `systemd/`.

## Storage

SFTP repositories use restic URLs such as:

```yaml
repo: sftp:backup@example-backup-host:/srv/restic/example-com
env_file: /etc/bitrix-backup/sites/example-com.env
```

S3 repositories use restic URLs such as:

```yaml
defaults:
  global_env_file: /etc/bitrix-backup/storage.env

sites:
  - code: example-com
    repo: s3:s3.amazonaws.com/bitrix-backups/example-com
    env_file: /etc/bitrix-backup/sites/example-com.env
```

See:

- `docs/storage-sftp.md`
- `docs/storage-s3.md`

## Restore

Restores are staged and never written directly back into production site roots or databases:

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore \
  --snapshot latest
```

To restore an exact pair reported by webhook, pass both snapshot IDs:

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore \
  --files-snapshot files-snapshot-id \
  --db-snapshot db-snapshot-id
```

See `docs/restore.md`.

`docs/restore.md` also includes examples for unpacking backups on a different server with either `bitrix-backup-restore` or plain `restic`.

## Documentation

- `docs/install.md` - installation, systemd timer, and cron setup
- `docs/storage-sftp.md` - SFTP storage setup
- `docs/storage-s3.md` - S3-compatible storage setup
- `docs/restore.md` - staging restore workflow
- `config/sites.example.yml` - configuration example
- `config/excludes.default` - default Bitrix exclusions
- `install.sh` - one-command installer

## Development

Run the unit suite:

```bash
bash tests/run.sh
```

Run optional integration tests:

```bash
RUN_INTEGRATION=1 bash tests/run.sh
```

The restic integration test is skipped when `restic` is not installed.
