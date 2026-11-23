#!/usr/bin/env bash
# Start (or restart) Baker's Crumbs on the EC2 server.
#  1. Pulls the bakery documents from S3 (the AWS integration).
#  2. Builds librechat.yaml (branding, theme, assistant instructions).
#  3. Reads the Gemini API key from SSM Parameter Store at runtime - it is never written to a file.
#  4. Starts LibreChat with Docker Compose.
# Run as root:  bash /opt/bakers-crumbs-ops/scripts/start-bakers-crumbs.sh
set -euo pipefail

REPO_DIR=/opt/bakers-crumbs-ops
LC_DIR=/opt/librechat
REGION=us-east-1
BUCKET=bakers-crumbs-tmth
KEY_PARAM=/bakers-crumbs/gemini-api-key
GEMINI_MODEL=${GEMINI_MODEL:-gemini-3.5-flash}
RELEASE="bakers-crumbs-$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo local)"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [start-bakers-crumbs] $*"; }

log "Syncing bakery documents from s3://$BUCKET/content/"
mkdir -p "$LC_DIR/bakers-content"
aws s3 sync "s3://$BUCKET/content/" "$LC_DIR/bakers-content/" --delete --region "$REGION" --only-show-errors
DOC_COUNT=$(find "$LC_DIR/bakers-content" -name '*.md' | wc -l)
if [ "$DOC_COUNT" -lt 1 ]; then
  log "ERROR: no bakery documents found in S3 - refusing to start an assistant with no content"
  exit 1
fi

log "Building librechat.yaml from $DOC_COUNT documents (model $GEMINI_MODEL, release $RELEASE)"
python3 "$REPO_DIR/scripts/build_config.py" "$LC_DIR/bakers-content" "$GEMINI_MODEL" "$RELEASE" > "$LC_DIR/librechat.yaml.new"
mv "$LC_DIR/librechat.yaml.new" "$LC_DIR/librechat.yaml"

log "Copying branding and compose override"
rm -rf "$LC_DIR/branding"
cp -r "$REPO_DIR/librechat/branding" "$LC_DIR/branding"
cp "$REPO_DIR/librechat/docker-compose.override.yml" "$LC_DIR/docker-compose.override.yml"

log "Applying non-secret settings to .env"
set_env() {
  local key=$1 val=$2
  if grep -qE "^#? ?${key}=" "$LC_DIR/.env"; then
    sed -i -E "s|^#? ?${key}=.*|${key}=${val}|" "$LC_DIR/.env"
  else
    echo "${key}=${val}" >> "$LC_DIR/.env"
  fi
}
set_env APP_TITLE "Baker's Crumbs"
set_env CUSTOM_FOOTER "Baker's Crumbs Helper - an invented bakery for a SAM10 class project. Built on LibreChat (MIT)."
set_env ENDPOINTS "google"
set_env GOOGLE_MODELS "$GEMINI_MODEL"
set_env BAKERS_CRUMBS_RELEASE "$RELEASE"
set_env SCHEDULES_SINGLE_PROCESS "true"
# The real key comes from Parameter Store below; make sure no key is kept in .env
sed -i -E 's|^GOOGLE_KEY=.*|# GOOGLE_KEY is injected at runtime from SSM Parameter Store|' "$LC_DIR/.env"

log "Reading Gemini API key from Parameter Store ($KEY_PARAM)"
GOOGLE_KEY=$(aws ssm get-parameter --name "$KEY_PARAM" --with-decryption --query Parameter.Value --output text --region "$REGION")
export GOOGLE_KEY

log "Starting containers"
cd "$LC_DIR"
docker compose up -d
unset GOOGLE_KEY

log "Baker's Crumbs started (release $RELEASE)"
