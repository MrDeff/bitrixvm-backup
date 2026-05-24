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

## Restore On Another Server

Install the tooling on the restore server, then create a minimal config and env file for the repository you need to unpack. The restore server does not need the original Bitrix site to be present when you only need staged files and a DB dump.

Example minimal config:

```bash
mkdir -p /etc/bitrix-backup/sites
cat >/etc/bitrix-backup/sites.yml <<'YAML'
sites:
  - code: example-com
    enabled: true
    path: /tmp/not-used-for-restore
    repo: sftp:backup@example-backup-host:/srv/restic/example-com
    env_file: /etc/bitrix-backup/sites/example-com.env
YAML
```

Create the restore credentials file:

```bash
install -m 600 /dev/null /etc/bitrix-backup/sites/example-com.env
cat >/etc/bitrix-backup/sites/example-com.env <<'ENV'
RESTIC_PASSWORD=change-this-long-random-secret
ENV
chmod 600 /etc/bitrix-backup/sites/example-com.env
```

For S3 repositories, include the AWS variables in the same env file:

```bash
AWS_ACCESS_KEY_ID=AKIAEXAMPLE
AWS_SECRET_ACCESS_KEY=replace-with-secret
AWS_DEFAULT_REGION=us-east-1
```

Restore the latest file and DB snapshots into `/restore`:

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore \
  --snapshot latest
```

Restore a specific pair from a webhook:

```bash
/opt/bitrix-backup/bin/bitrix-backup-restore \
  --config /etc/bitrix-backup/sites.yml \
  --site example-com \
  --kind both \
  --target /restore \
  --files-snapshot files-snapshot-id \
  --db-snapshot db-snapshot-id
```

The unpacked data will be staged under:

```text
/restore/example-com/<restore-id>/files
/restore/example-com/<restore-id>/db/db.sql
```

## Restore With Restic Only

If the helper scripts are not installed on the restore server, use restic directly.

For SFTP:

```bash
export RESTIC_PASSWORD='change-this-long-random-secret'
export RESTIC_REPOSITORY='sftp:backup@example-backup-host:/srv/restic/example-com'
```

For S3:

```bash
export RESTIC_PASSWORD='change-this-long-random-secret'
export AWS_ACCESS_KEY_ID='AKIAEXAMPLE'
export AWS_SECRET_ACCESS_KEY='replace-with-secret'
export AWS_DEFAULT_REGION='us-east-1'
export RESTIC_REPOSITORY='s3:s3.amazonaws.com/bitrix-backups/example-com'
```

List available snapshots:

```bash
restic snapshots
restic snapshots --tag kind:files
restic snapshots --tag kind:db
```

Unpack files from the latest file snapshot:

```bash
mkdir -p /restore/example-com/files
restic restore latest \
  --tag kind:files \
  --target /restore/example-com/files
```

Extract the database dump from a DB snapshot:

```bash
mkdir -p /restore/example-com/db
restic snapshots --tag kind:db
db_snapshot='db-snapshot-id'
db_path="$(restic ls "$db_snapshot" | awk '/\/db\.sql$/ { print $NF; exit }')"
restic dump "$db_snapshot" "$db_path" > /restore/example-com/db/db.sql
chmod 600 /restore/example-com/db/db.sql
```

When using an explicit files snapshot ID, replace `latest` in the file restore command with that snapshot ID.
