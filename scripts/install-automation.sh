#!/usr/bin/env bash
# Installs the two Baker's Crumbs automations as cron jobs. Run once as root.
#   Automation 1: backup-mongodb.sh  - every hour at :05   -> S3 (kept 7 days by a lifecycle rule)
#   Automation 2: health-check.sh    - every 15 minutes    -> CloudWatch metric HealthCheckOK + alarm
# Both write a timestamped JSON line per run to /var/log/bakers-crumbs/automation.log
# (shipped to the /bakers-crumbs/automation log group), which is the evidence that they ran unattended.
set -euo pipefail
REPO_DIR=/opt/bakers-crumbs-ops

cat > /etc/cron.d/bakers-crumbs-automation <<EOF
# Baker's Crumbs automations (installed by scripts/install-automation.sh)
5 * * * * root bash $REPO_DIR/scripts/backup-mongodb.sh >> /var/log/bakers-crumbs/cron.err 2>&1
*/15 * * * * root bash $REPO_DIR/scripts/health-check.sh >> /var/log/bakers-crumbs/cron.err 2>&1
EOF
chmod 644 /etc/cron.d/bakers-crumbs-automation

# Run the request logger through bash too, so a git pull that resets file permissions cannot break it
cat > /etc/cron.d/bakers-crumbs-request-logger <<EOF
# Baker's Crumbs request logger - writes one JSON line per answer for CloudWatch
* * * * * root bash $REPO_DIR/scripts/request-logger.sh >> /var/log/bakers-crumbs/request-logger.err 2>&1
EOF
chmod 644 /etc/cron.d/bakers-crumbs-request-logger

echo "Installed cron jobs:"
cat /etc/cron.d/bakers-crumbs-automation /etc/cron.d/bakers-crumbs-request-logger
