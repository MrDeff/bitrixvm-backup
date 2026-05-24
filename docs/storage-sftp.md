# SFTP Storage

Use an SFTP restic repository when backups should be written to a remote SSH server.

## Environment File

Example `/etc/bitrix-backup/sites/example-com.env`:

```bash
RESTIC_PASSWORD=change-this-long-random-secret
```

The runner uses the `repo` value from `/etc/bitrix-backup/sites.yml`, for example:

```yaml
repo: sftp:backup@example-backup-host:/srv/restic/example-com
env_file: /etc/bitrix-backup/sites/example-com.env
```

Configure SSH keys for root or the service account running the backup, and verify non-interactive access:

```bash
ssh backup@example-backup-host
```

## Initialize Repository

Initialize the repository once before the first backup:

```bash
set -a
. /etc/bitrix-backup/sites/example-com.env
set +a
restic -r sftp:backup@example-backup-host:/srv/restic/example-com init
```

The backup runner can initialize an empty repository when repository initialization is enabled in the site configuration. Operators may still prefer running `restic init` manually so credentials and remote paths are validated before the first scheduled backup.
