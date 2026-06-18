# Install BitrixVM Incremental Backups

These steps target CentOS Stream 9 / BitrixVM 9 hosts and install the runner under `/opt/bitrix-backup`.

## One-command Install

Run the installer as root and provide the restic repository prefix that should be used during site discovery:

```bash
curl -fsSL https://raw.githubusercontent.com/MrDeff/bitrixvm-backup/main/install.sh | bash -s -- \
  --repo-prefix sftp:backup@example-backup-host:/srv/restic
```

Useful installer options:

```text
--repo-prefix <prefix>       Required restic repository prefix.
--install-dir <path>         Install directory. Default: /opt/bitrix-backup
--config-dir <path>          Config directory. Default: /etc/bitrix-backup
--root <path>                Bitrix sites root. Default: /home/bitrix
--dry-run                    Print planned commands without changing the system.
--no-systemd-enable          Install units but do not enable/start the timer.
--no-generate-restic-passwords
                             Do not create per-site RESTIC_PASSWORD env files.
```

The installer creates `/etc/bitrix-backup/excludes.local` from the default exclude list when the file does not exist. It also creates `/etc/bitrix-backup/storage.env` for shared storage credentials, creates missing per-site env files from `sites.yml`, writes generated `RESTIC_PASSWORD` values, and sets env file modes to `600`. Existing env files are left unchanged. After it finishes, review `/etc/bitrix-backup/sites.yml`, fill shared storage credentials if needed, adjust excludes if needed, and save the generated secrets securely.

## Manual Install

## Install Packages

Install the runtime dependencies:

```bash
dnf install -y restic mysql python3 python3-pyyaml php-cli curl rsync
```

## Copy Application Files

Copy this repository to `/opt/bitrix-backup` and keep the executable bits on the scripts in `bin/`:

```bash
mkdir -p /opt/bitrix-backup
rsync -a --delete ./ /opt/bitrix-backup/
chmod +x /opt/bitrix-backup/bin/bitrix-backup-*
```

Create the configuration directory:

```bash
mkdir -p /etc/bitrix-backup/sites
```

## Generate Site Configuration

Run discovery to create an initial site configuration:

```bash
/opt/bitrix-backup/bin/bitrix-backup-discover \
  --repo-prefix sftp:backup@example-backup-host:/srv/restic \
  --output /etc/bitrix-backup/sites.yml
```

Review `/etc/bitrix-backup/sites.yml` before enabling scheduled backups. Confirm each site path, repository URL, environment file path, and enabled flag.

## Create Environment Files

For manual installation, create a shared storage env file when storage credentials are common to all sites:

```bash
install -m 600 /dev/null /etc/bitrix-backup/storage.env
cat >/etc/bitrix-backup/storage.env <<'ENV'
# Optional shared S3 credentials:
# AWS_ACCESS_KEY_ID=''
# AWS_SECRET_ACCESS_KEY=''
# AWS_DEFAULT_REGION='us-east-1'
ENV
chmod 600 /etc/bitrix-backup/storage.env
```

Then create one environment file per repository. The file must be readable only by root and include at least `RESTIC_PASSWORD`:

```bash
install -m 600 /dev/null /etc/bitrix-backup/sites/example-com.env
cat >/etc/bitrix-backup/sites/example-com.env <<'ENV'
RESTIC_PASSWORD=change-this-long-random-secret
ENV
chmod 600 /etc/bitrix-backup/sites/example-com.env
```

Add any storage-specific variables required by the selected backend. See `docs/storage-sftp.md` and `docs/storage-s3.md`.

## Install And Enable systemd Timer

The recommended recurring job is the systemd timer from `systemd/bitrix-backup.timer`. By default it runs once per day at `03:15` with up to 20 minutes of randomized delay. `Persistent=true` means systemd will run a missed backup after boot if the VM was powered off at the scheduled time.

Copy the units and enable the timer:

```bash
cp /opt/bitrix-backup/systemd/bitrix-backup.service /etc/systemd/system/
cp /opt/bitrix-backup/systemd/bitrix-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bitrix-backup.timer
```

Run a manual backup after installation to verify credentials and repositories before waiting for the schedule:

```bash
systemctl start bitrix-backup.service
systemctl status bitrix-backup.service
```

Check that the timer is enabled and see the next scheduled run:

```bash
systemctl list-timers bitrix-backup.timer
journalctl -u bitrix-backup.timer
journalctl -u bitrix-backup.service
```

Check only the latest backup service logs:

```bash
journalctl -u bitrix-backup.service -n 200 --no-pager
```

## Change The Schedule

Use a systemd drop-in override instead of editing `/etc/systemd/system/bitrix-backup.timer` directly. This keeps local scheduling changes separate from files copied from the repository.

Example: run daily at `01:30`:

```bash
systemctl edit bitrix-backup.timer
```

Add:

```ini
[Timer]
OnCalendar=
OnCalendar=*-*-* 01:30:00
RandomizedDelaySec=20m
Persistent=true
```

Apply and inspect the timer:

```bash
systemctl daemon-reload
systemctl restart bitrix-backup.timer
systemctl list-timers bitrix-backup.timer
systemctl cat bitrix-backup.timer
```

## Disable Scheduled Backups

Temporarily stop scheduled runs:

```bash
systemctl disable --now bitrix-backup.timer
```

Manual backups still work while the timer is disabled:

```bash
systemctl start bitrix-backup.service
```

## Cron Alternative

Use cron only when systemd timers are not available. Keep systemd disabled to avoid duplicate runs.

Example root cron entry for daily backups at `03:15`:

```cron
15 3 * * * /opt/bitrix-backup/bin/bitrix-backup-run --config /etc/bitrix-backup/sites.yml >>/var/log/bitrix-backup.log 2>&1
```

When using cron, rotate `/var/log/bitrix-backup.log` with the host's normal log rotation policy.

## Retention Check

The runner applies retention after every successful site backup:

```bash
restic forget --tag kind:db --group-by tags --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune
restic forget --tag kind:files --group-by tags --keep-daily 3 --keep-weekly 1 --keep-monthly 1 --prune
```

`--group-by tags` is important because database dumps are created in temporary directories before upload. Grouping by tags keeps all `kind:db` snapshots in one retention group and all `kind:files` snapshots in another.

To inspect what remains in a repository:

```bash
set -a
. /etc/bitrix-backup/storage.env
. /etc/bitrix-backup/sites/example-com.env
set +a

restic -r s3:s3.amazonaws.com/bitrix-backups/example-com snapshots --tag kind:db
restic -r s3:s3.amazonaws.com/bitrix-backups/example-com snapshots --tag kind:files
```
