# Install BitrixVM Incremental Backups

These steps target CentOS Stream 9 / BitrixVM 9 hosts and install the runner under `/opt/bitrix-backup`.

## Install Packages

Install the runtime dependencies:

```bash
dnf install -y restic mysql python3 python3-pyyaml php-cli curl
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
mkdir -p /etc/bitrix-backup
```

## Generate Site Configuration

Run discovery to create an initial site configuration:

```bash
/opt/bitrix-backup/bin/bitrix-backup-discover \
  --output /etc/bitrix-backup/sites.yml
```

Review `/etc/bitrix-backup/sites.yml` before enabling scheduled backups. Confirm each site path, repository URL, environment file path, and enabled flag.

## Create Environment Files

Create one environment file per repository. The file must be readable only by root and include at least `RESTIC_PASSWORD`:

```bash
install -m 600 /dev/null /etc/bitrix-backup/example-com.env
cat >/etc/bitrix-backup/example-com.env <<'ENV'
RESTIC_PASSWORD=change-this-long-random-secret
ENV
chmod 600 /etc/bitrix-backup/example-com.env
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
