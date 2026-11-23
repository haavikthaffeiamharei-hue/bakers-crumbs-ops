#!/usr/bin/env bash
# Restore the Baker's Crumbs database from a backup in S3.
# Usage (as root):  bash restore-mongodb.sh            -> restores the newest backup
#                   bash restore-mongodb.sh <s3-key>   -> restores a specific backup
# Stops the app, replaces the LibreChat database with the backup (mongorestore --drop),
# starts the app again and prints document counts so you can check the data came back.
set -euo pipefail

BUCKET=bakers-crumbs-tmth
REGION=us-east-1
START=$(date +%s)
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [restore-mongodb] $*"; }

KEY=${1:-$(aws s3 ls "s3://$BUCKET/backups/mongodb/" --region "$REGION" | sort | tail -1 | awk '{print "backups/mongodb/"$4}')}
if [ -z "$KEY" ] || [ "$KEY" = "backups/mongodb/" ]; then
  log "ERROR: no backup found in s3://$BUCKET/backups/mongodb/"; exit 1
fi
TMP=/var/tmp/restore.archive.gz

log "Downloading s3://$BUCKET/$KEY"
aws s3 cp "s3://$BUCKET/$KEY" "$TMP" --region "$REGION" --only-show-errors
log "Downloaded $(stat -c %s "$TMP") bytes"

counts() {
  docker exec chat-mongodb mongosh --quiet mongodb://localhost:27017/LibreChat --eval \
    'print("users=" + db.users.countDocuments() + " conversations=" + db.conversations.countDocuments() + " messages=" + db.messages.countDocuments())'
}
log "Counts before restore: $(counts)"

log "Stopping the app so nobody writes during the restore"
cd /opt/librechat && docker compose stop api

log "Restoring (replacing the LibreChat database)"
docker exec -i chat-mongodb mongorestore --quiet --drop --archive --gzip < "$TMP"
rm -f "$TMP"

log "Counts after restore: $(counts)"

log "Starting the app again (start script re-reads the key from Parameter Store)"
bash /opt/bakers-crumbs-ops/scripts/start-bakers-crumbs.sh > /dev/null

log "Restore finished in $(( $(date +%s) - START )) seconds. Now log in and check your chats are back."
