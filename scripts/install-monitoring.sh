#!/usr/bin/env bash
# One-time setup of monitoring on the Baker's Crumbs EC2 server. Run as root.
#  - installs and starts the Amazon CloudWatch agent (memory and disk metrics, request log shipping)
#  - schedules the request logger every minute (cron)
#  - adds log rotation for /var/log/bakers-crumbs so logs cannot fill the disk
set -euo pipefail
REPO_DIR=/opt/bakers-crumbs-ops
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [install-monitoring] $*"; }

if ! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl >/dev/null 2>&1; then
  log "Installing the CloudWatch agent"
  curl -sSfo /tmp/amazon-cloudwatch-agent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
fi

mkdir -p /var/log/bakers-crumbs /var/lib/bakers-crumbs
touch /var/log/bakers-crumbs/requests.log /var/log/bakers-crumbs/automation.log

log "Configuring and starting the CloudWatch agent"
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c "file:$REPO_DIR/monitoring/cloudwatch-agent.json"

log "Scheduling the request logger every minute"
chmod +x "$REPO_DIR"/scripts/*.sh
cat > /etc/cron.d/bakers-crumbs-request-logger <<EOF
# Baker's Crumbs request logger - writes one JSON line per answer for CloudWatch
* * * * * root $REPO_DIR/scripts/request-logger.sh >> /var/log/bakers-crumbs/request-logger.err 2>&1
EOF
chmod 644 /etc/cron.d/bakers-crumbs-request-logger

log "Adding log rotation for /var/log/bakers-crumbs"
cat > /etc/logrotate.d/bakers-crumbs <<'EOF'
/var/log/bakers-crumbs/*.log /var/log/bakers-crumbs/*.err {
    daily
    rotate 7
    maxsize 50M
    compress
    missingok
    notifempty
    copytruncate
}
EOF

log "Done. Agent status:"
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
