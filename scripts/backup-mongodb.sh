#!/usr/bin/env bash
# Automation 1 - scheduled backup of the Baker's Crumbs database to S3 (runs hourly from cron).
# Dumps LibreChat's MongoDB (users, chats, settings) with mongodump, compresses it, uploads it to
# s3://bakers-crumbs-tmth/backups/mongodb/ (a lifecycle rule deletes backups after 7 days) and writes
# one JSON line to /var/log/bakers-crumbs/automation.log, which the CloudWatch agent ships to CloudWatch.
set -uo pipefail

BUCKET=bakers-crumbs-tmth
REGION=us-east-1
TS=$(date -u +%Y%m%dT%H%M%SZ)
KEY="backups/mongodb/librechat-$TS.archive.gz"
TMP="/var/tmp/librechat-$TS.archive.gz"
LOG=/var/log/bakers-crumbs/automation.log
START=$(date +%s)
mkdir -p /var/log/bakers-crumbs

result() { # status, message
  local secs=$(( $(date +%s) - START ))
  local bytes=0
  [ -f "$TMP" ] && bytes=$(stat -c %s "$TMP")
  printf '{"time":"%s","automation":"backup-mongodb","status":"%s","s3_key":"%s","bytes":%s,"seconds":%s,"message":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "s3://$BUCKET/$KEY" "$bytes" "$secs" "$2" | tee -a "$LOG"
  rm -f "$TMP"
}

if ! docker exec chat-mongodb mongodump --quiet --db LibreChat --archive --gzip > "$TMP"; then
  result fail "mongodump failed"; exit 1
fi
if [ "$(stat -c %s "$TMP")" -lt 100 ]; then
  result fail "dump is suspiciously small"; exit 1
fi
if ! aws s3 cp "$TMP" "s3://$BUCKET/$KEY" --region "$REGION" --only-show-errors; then
  result fail "upload to S3 failed"; exit 1
fi
result ok "backup uploaded"
