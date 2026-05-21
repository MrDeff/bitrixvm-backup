# BitrixVM Incremental Backup Design

## Context

Target platform:

- BitrixVM / BitrixEnv 9 on CentOS Stream 9 or compatible EL9 distribution.
- Typical BitrixVM stack: NGINX, Apache, PHP 8.2, Percona Server 8.0, firewalld, and `/root/menu.sh` administration.
- All backed up sites are 1C-Bitrix sites.

The built-in 1C-Bitrix backup mechanism is intentionally out of scope. The backup system must not call `bitrix/modules/main/tools/backup.php` and must not rely on `/bitrix/backup` as storage.

## Goals

- Back up 10-20 Bitrix sites on one VM.
- Keep each site's backup isolated in its own external restic repository.
- Back up files and database separately.
- Run database backup daily.
- Run file backup daily as an incremental restic backup.
- Store durable backup data only in external SFTP or S3 storage.
- Keep retention equivalent to: 1 day, 2 days, 3 days, 1 week, and 1 month.
- Notify a webhook after each site is processed.
- Avoid duplicating database passwords into project config.
- Provide safe restore tooling that restores into a staging location by default.

## Non-Goals

- No use of the built-in 1C-Bitrix backup script.
- No local long-term backup archive storage.
- No first-version automated overwrite of production site files or production databases during restore.
- No custom backup format when restic already provides incremental snapshots, encryption, locking, retention, and SFTP/S3 backends.

## Recommended Approach

Use `restic` as the backup engine.

Each site has an independent restic repository:

- SFTP example: `sftp:user@example-backup-host:/backups/bitrix/sites/example.com`
- S3 example: `s3:s3.amazonaws.com/bitrix-backups/example.com`

Inside a site repository, files and database are separate snapshots tagged by kind:

- `kind:files`
- `kind:db`

This favors site isolation over cross-site deduplication. A single site can be restored, rotated, moved, or deleted without touching other sites.

## Project Layout

```text
bin/
  bitrix-backup-discover
  bitrix-backup-run
  bitrix-backup-verify
  bitrix-backup-restore
config/
  sites.example.yml
  excludes.default
  excludes.local.example
lib/
  config.sh
  db-config.sh
  excludes.sh
  logging.sh
  mysql.sh
  restic.sh
  webhook.sh
systemd/
  bitrix-backup.service
  bitrix-backup.timer
docs/
  install.md
  restore.md
  storage-sftp.md
  storage-s3.md
```

## Site Discovery

`bin/bitrix-backup-discover` scans standard BitrixVM locations:

- `/home/bitrix/www`
- `/home/bitrix/ext_www/*`

For each detected site, it looks for standard 1C-Bitrix database config files:

- `bitrix/.settings.php`
- `bitrix/php_interface/dbconn.php`

The discovery command generates a draft `config/sites.yml`. Operators review and edit the file before enabling backups.

## Site Configuration

`sites.yml` is explicit operational inventory, not a secret store.

Example:

```yaml
defaults:
  retention:
    keep_daily: 3
    keep_weekly: 1
    keep_monthly: 1
  default_excludes: true
  global_exclude_file: /etc/bitrix-backup/excludes.local
  webhook_env_file: /etc/bitrix-backup/webhook.env

sites:
  - code: example-com
    enabled: true
    path: /home/bitrix/ext_www/example.com
    repo: sftp:backup@example-backup-host:/backups/bitrix/example-com
    env_file: /etc/bitrix-backup/sites/example-com.env
    db_config:
      auto_detect: true
    excludes:
      - /upload/import
      - "*.log"
```

The per-site `env_file` may contain:

- `RESTIC_PASSWORD`
- SFTP settings required by the environment
- S3 credentials, when not supplied through an instance role or system profile
- restic tuning variables

It must not contain the Bitrix database password unless an emergency override is added in a future version.

## Database Credentials

Database credentials are read from the site's own 1C-Bitrix config immediately before dumping the database.

Supported sources:

- `bitrix/.settings.php`
- `bitrix/php_interface/dbconn.php`

`sites.yml` may specify a non-standard config path, but it must not store database passwords.

The runner extracts:

- database host
- database name
- database user
- database password

Secrets are not written to logs, webhook payloads, restic tags, or generated config.

## Default File Exclusions

The project ships `config/excludes.default` based on the standard BitrixVM exclusion list from `/opt/webdir/bin/ex.txt` and documented Bitrix backup recommendations.

Default exclusions:

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

Operators can extend exclusions in two places:

- global local file, for example `/etc/bitrix-backup/excludes.local`
- per-site `excludes` entries in `sites.yml`

The runner builds a temporary restic exclude file per site by combining:

1. default exclusions, unless `default_excludes: false`
2. global local exclusions, if configured
3. per-site exclusions from `sites.yml`

Patterns are passed to restic with `--exclude-file`. Rules beginning with `/` are interpreted relative to the site root by running restic from the site directory or by normalizing patterns for the selected backup root.

## Backup Flow

`bin/bitrix-backup-run` is the daily entry point.

For each enabled site:

1. Acquire a per-site lock.
2. Load site config and env file.
3. Validate that restic can reach or initialize the site repository.
4. Read database credentials from the Bitrix site config.
5. Create a temporary database dump under `/var/tmp/bitrix-backup`.
6. Back up the database dump to restic with `kind:db`.
7. Delete the temporary database dump.
8. Build the effective exclude file.
9. Back up site files to restic with `kind:files`.
10. Apply retention separately for `kind:db` and `kind:files`.
11. Run `restic forget --prune` for the selected tags.
12. Send the per-site webhook result.
13. Release the lock.

The database dump is local only while the current site is being processed. Cleanup runs on both success and failure.

## Retention

Retention is applied per site repository and per snapshot kind:

```text
restic forget --tag kind:db --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune
restic forget --tag kind:files --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune
```

This preserves:

- the last 3 daily restore points
- 1 weekly restore point
- 1 monthly restore point

The exact snapshot selected by restic for weekly and monthly retention follows restic's retention semantics.

## Webhook

A webhook is called once per site after that site finishes processing.

Request:

- method: `POST`
- content type: `application/json`
- optional bearer token from webhook env file

Payload:

```json
{
  "site": "example-com",
  "host": "bitrix-vm-01",
  "status": "success",
  "started_at": "2026-05-21T02:00:00+07:00",
  "finished_at": "2026-05-21T02:03:17+07:00",
  "duration_seconds": 197,
  "files_snapshot_id": "abc123",
  "db_snapshot_id": "def456",
  "error": null
}
```

Failure payloads use `"status": "failed"` and set `error` to a sanitized message.

Webhook behavior:

- 3 attempts per site.
- Short delay between attempts.
- Webhook delivery failure is logged.
- Webhook delivery failure does not change a successful backup into a failed backup.

## Scheduling

Use a systemd timer:

- `systemd/bitrix-backup.service`
- `systemd/bitrix-backup.timer`

Default schedule: once per day during the low-traffic night window.

The service runs the single runner, and the runner processes enabled sites sequentially. Sequential processing reduces load on MySQL, disk IO, and remote storage for 10-20 sites.

## Verification

`bin/bitrix-backup-verify` checks:

- required binaries: `restic`, `mysql`, `mysqldump`, `curl`, YAML parser used by the implementation
- readability of `sites.yml`
- existence and permissions of env files
- ability to read Bitrix database config files
- external restic repository access for each enabled site
- presence of recent `kind:db` and `kind:files` snapshots

It must not print secrets.

## Restore

`bin/bitrix-backup-restore` restores into staging locations by default.

Default restore output:

```text
/restore/<site>/<snapshot-or-date>/files
/restore/<site>/<snapshot-or-date>/db.sql
```

The restore tool can select snapshots by:

- site code
- snapshot id
- date expression supported by restic
- kind: `files`, `db`, or both

The first version does not overwrite production files and does not import SQL directly into production MySQL.

## Security

- Secret env files must be owned by root or the backup operator and have mode `600`.
- Logs must not include database passwords, restic passwords, S3 secrets, SFTP secrets, or webhook tokens.
- Webhook error fields must be sanitized.
- Temporary dumps and temporary exclude files are removed after use.
- Restic encryption is always enabled through repository passwords.

## Testing Strategy

- Static checks with `shellcheck`.
- Unit-style shell tests for:
  - Bitrix config parsing from fixture `.settings.php`
  - Bitrix config parsing from fixture `dbconn.php`
  - exclude file merging
  - retention command generation
  - webhook payload generation
- Integration test with a local restic repository:
  - create fixture site files
  - create fixture SQL dump
  - run backup
  - verify separate `kind:files` and `kind:db` snapshots
  - run restore into staging directory

## References

- 1C-Bitrix installation environment documentation: https://docs.1c-bitrix.ru/pages/get-started/install-env.html
- BitrixVM course page mentioning `/opt/webdir/bin/ex.txt` default exclusions: https://dev.1c-bitrix.ru/learning/course/?COURSE_ID=37&TYPE=Y
- BitrixFramework backup documentation: https://docs.1c-bitrix.ru/pages/advanced/backup.html
- 1C-Bitrix backup user help with cache and backup directory exclusion examples: https://dev.1c-bitrix.ru/user_help/settings/utilities/dump/dump.php
- Bitrix24 self-hosted installation page with BitrixVM 9 stack summary: https://www.bitrix24.eu/self-hosted/installation.php
