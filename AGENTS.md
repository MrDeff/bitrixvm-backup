# Agent Notes

This file is for coding agents and future maintainers working in this repository.

## Project Purpose

This project provides backup scripts for CentOS Stream 9 / BitrixVM 9 hosts with multiple 1C-Bitrix sites. It uses restic for incremental backups and stores durable backup data only in external repositories such as SFTP or S3-compatible storage.

The built-in 1C-Bitrix backup mechanism must not be used.

## Hard Requirements

- Do not call or depend on `bitrix/modules/main/tools/backup.php`.
- Do not use `/bitrix/backup` as durable backup storage.
- Do not commit real `/etc/bitrix-backup/sites.yml`, `.env` files, restic passwords, S3 keys, SSH keys, database passwords, or generated dumps.
- Keep DB and file snapshots separate: `kind:db` and `kind:files`.
- Keep site handling per-site; one failing site must not leak state into the next site.
- Keep durable backups off the VM. Temporary local files must be short-lived and cleaned up.
- Restore commands must stage output for operator review, not overwrite production paths.

## Important Files

```text
bin/bitrix-backup-discover  discovers Bitrix sites and writes initial YAML
bin/bitrix-backup-run       performs DB backup, file backup, retention, webhook
bin/bitrix-backup-verify    validates config, env files, Bitrix DB config, optional restic access
bin/bitrix-backup-restore   restores files and DB dumps into staging
install.sh                  one-command installer for BitrixVM hosts

lib/config-query.py         YAML parser and config merger
lib/db-config-reader.php    reads Bitrix DB credentials
lib/excludes.sh             merges default/global/per-site excludes
lib/mysql.sh                writes private mysql defaults and dumps DBs
lib/restic.sh               restic wrapper helpers
lib/webhook.sh              webhook payload and delivery

config/excludes.default     default Bitrix cache/temp exclusions
config/sites.example.yml    example operator config
tests/run.sh                test suite entrypoint
```

## Development Workflow

Before editing, inspect the existing pattern in the relevant `bin/`, `lib/`, and `tests/unit/` files. The project intentionally uses small shell helpers with focused tests.

Run tests after changes:

```bash
bash tests/run.sh
```

Run optional integration tests when `restic` is available:

```bash
RUN_INTEGRATION=1 bash tests/run.sh
```

If `shellcheck` is available, run it across scripts:

```bash
shellcheck bin/* lib/*.sh tests/*.sh tests/unit/*.sh tests/integration/*.sh
```

## Editing Guidance

- Prefer explicit error handling in shell. Avoid hidden failures inside `if ! command; then` unless the called function logs enough context.
- Preserve `set -euo pipefail` scripts and quote variables.
- When passing the 10th or later shell argument, use braces such as `${10}`.
- Keep temporary files under `BITRIX_BACKUP_TMP` or `/var/tmp/bitrix-backup`.
- Clean temporary work directories on normal exit and interruption.
- Keep env sourcing isolated per site so secrets and webhook variables do not leak between sites.
- Use `config-query.py` for YAML access instead of parsing YAML in shell.
- Keep docs and docs tests in sync when changing CLI flags, paths, or operator workflow.
- Keep `install.sh`, `docs/install.md`, `README.md`, and `tests/unit/install-test.sh` in sync when changing installation behavior.

## Security Notes

Environment files are expected to be root-only with mode `600`. They may contain `RESTIC_PASSWORD`, SFTP/SSH-related environment, S3 credentials, or webhook credentials.

`install.sh` creates missing per-site env files with generated `RESTIC_PASSWORD` values unless `--no-generate-restic-passwords` is passed. It must never print generated passwords to stdout or overwrite existing env files.

Shared credentials belong in `global_env_file`, typically `/etc/bitrix-backup/storage.env`. Code must source `global_env_file` before the per-site `env_file`, so site-specific values can override shared values.

Database credentials are read from Bitrix config and written only to temporary mysql defaults files during backup. DB dumps are backed up first, then removed before file backup so dumps are not included in file snapshots.

Webhook errors are sanitized before payload generation. Do not add raw secret-bearing command output to webhook payloads.

## Restore Notes

`bitrix-backup-restore` supports:

- `--snapshot latest` for convenience.
- `--files-snapshot` and `--db-snapshot` for restoring an exact pair reported by webhook.

Restore output belongs under a staging target such as `/restore/<site>/<restore-id>/`. Operators decide whether and how to copy files or import DB dumps into production.
