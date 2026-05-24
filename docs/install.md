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
```

The installer does not create real secret files. After it finishes, review `/etc/bitrix-backup/sites.yml` and create the root-only environment files under `/etc/bitrix-backup/sites/`.

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

Create one environment file per repository. The file must be readable only by root and include at least `RESTIC_PASSWORD`:

```bash
install -m 600 /dev/null /etc/bitrix-backup/sites/example-com.env
cat >/etc/bitrix-backup/sites/example-com.env <<'ENV'
RESTIC_PASSWORD=change-this-long-random-secret
ENV
chmod 600 /etc/bitrix-backup/sites/example-com.env
```

Add any storage-specific variables required by the selected backend. See `docs/storage-sftp.md` and `docs/storage-s3.md`.

## Install And Enable systemd Timer

Copy the units and enable the timer:

```bash
cp /opt/bitrix-backup/systemd/bitrix-backup.service /etc/systemd/system/
cp /opt/bitrix-backup/systemd/bitrix-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bitrix-backup.timer
```

Run a manual backup after installation:

```bash
systemctl start bitrix-backup.service
systemctl status bitrix-backup.service
```

Check scheduled runs with:

```bash
systemctl list-timers bitrix-backup.timer
journalctl -u bitrix-backup.service
```
