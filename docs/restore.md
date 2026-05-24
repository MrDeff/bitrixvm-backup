# Restore Guide

Restores are staged for operator review. `bitrix-backup-restore` never writes directly back to production web roots or production database paths.

## Restore Command

Restore a site's files and database into a staging directory:

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore \
  --snapshot latest
```

The restore command creates a restore-specific directory:

```text
/restore/example-com/<restore-id>/files
/restore/example-com/<restore-id>/db/db.sql
```

When `--snapshot latest` is used, `<restore-id>` is a UTC timestamp such as `20260524T031500Z`. When a snapshot ID is provided, unsafe path characters are replaced before creating the staging directory.

To restore an exact file/database pair reported by a webhook, pass each snapshot ID explicitly:

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore \
  --files-snapshot files-snapshot-id \
  --db-snapshot db-snapshot-id
```

When file and DB snapshot IDs differ, `<restore-id>` is built from both sanitized IDs.

## Restore Files

Review staged files under `/restore/<site>/<restore-id>/files`. Copy only the files you intend to recover back to the production site path after validating ownership, permissions, and application state.

## Restore Database

Review the staged dump at `/restore/<site>/<restore-id>/db/db.sql`. Import it manually into a temporary or production database only after confirming the target database, credentials, and maintenance window.

Example manual import:

```bash
mysql --defaults-extra-file=/path/to/mysql.cnf target_database \
  < /restore/example-com/<restore-id>/db/db.sql
```

The restore tool deliberately stops at staging. The final copy or import step is an operator decision.
