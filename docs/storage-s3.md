# S3 Storage

Use an S3-compatible restic repository for AWS S3 or compatible object storage.

## Environment File

Example `/etc/bitrix-backup/sites/example-com.env`:

```bash
RESTIC_PASSWORD=change-this-long-random-secret
AWS_ACCESS_KEY_ID=AKIAEXAMPLE
AWS_SECRET_ACCESS_KEY=replace-with-secret
AWS_DEFAULT_REGION=us-east-1
```

Keep the file mode at `600` and readable only by root.

## Repository Example

Set the site repository in `/etc/bitrix-backup/sites.yml`:

```yaml
repo: s3:s3.amazonaws.com/bitrix-backups/example-com
env_file: /etc/bitrix-backup/sites/example-com.env
```

For S3-compatible providers, use that provider's endpoint:

```yaml
repo: s3:https://s3.example-storage.local/bitrix-backups/example-com
```

Initialize the repository once before the first backup:

```bash
set -a
. /etc/bitrix-backup/sites/example-com.env
set +a
restic -r s3:s3.amazonaws.com/bitrix-backups/example-com init
```
