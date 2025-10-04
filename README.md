# effective_mobile_script

# Monitor Test

## Description
Monitor process `test`:

- Logs restarts in `/var/log/monitoring.log`.
- Sends request to `https://test.com/monitoring/test/api`.
- Logs errors if monitoring server is unreachable or HTTP code >= 400.
- Uses lock to avoid parallel execution.

## Prerequisites
- User `monitor` must exist.
- User `monitor` must have write access to:
  - `/var/lib/monitor_test`
  - `/var/log/monitoring.log`

Set permissions manually if needed:

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin monitor
sudo mkdir -p /var/lib/monitor_test
sudo chown monitor:monitor /var/lib/monitor_test
sudo chmod 750 /var/lib/monitor_test
sudo touch /var/log/monitoring.log
sudo chown monitor:monitor /var/log/monitoring.log
sudo chmod 640 /var/log/monitoring.log




``` # Notes:

The script itself does not create the monitor user.

Permissions must be set manually as described.


# Installation
sudo cp monitor_test.sh /usr/local/bin/
sudo chmod 750 /usr/local/bin/monitor_test.sh

sudo cp monitor_test.service /etc/systemd/system/
sudo cp monitor_test.timer /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now monitor_test.service
sudo systemctl enable --now monitor_test.timer

# Verification
# Check timer
systemctl list-timers | grep monitor_test

# Check service status
systemctl status monitor_test.service

# Check logs
tail -f /var/log/monitoring.log

# Check last PID file
ls -l /var/lib/monitor_test/last_pid
