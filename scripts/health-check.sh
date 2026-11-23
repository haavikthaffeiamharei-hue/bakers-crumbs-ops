#!/usr/bin/env bash
# Automation 2 - scheduled health check (runs every 15 minutes from cron).
# Checks the three things Baker's Crumbs needs to answer a customer:
#   1. the website answers over HTTPS          (https://<host>/health)
#   2. the Gemini model exists for our API key  (models.get - free, does not use the answer quota)
#   3. the bakery documents are present in S3
# Publishes BakersCrumbs/HealthCheckOK (1 = healthy, 0 = broken) to CloudWatch, where an alarm emails
# bakers-crumbs-alerts, and writes one JSON line to /var/log/bakers-crumbs/automation.log.
# Check 2 would have caught incident 1 (model retired for new keys -> 404) before a customer did.
set -uo pipefail

REGION=us-east-1
BUCKET=bakers-crumbs-tmth
KEY_PARAM=/bakers-crumbs/gemini-api-key
ENV_FILE=/opt/librechat/.env
LOG=/var/log/bakers-crumbs/automation.log
mkdir -p /var/log/bakers-crumbs

envval() { grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-; }
SITE=$(envval DOMAIN_CLIENT)
MODEL=$(envval BAKERS_CRUMBS_MODEL)
RELEASE=$(envval BAKERS_CRUMBS_RELEASE)

site_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$SITE/health" || echo 000)

KEY=$(aws ssm get-parameter --name "$KEY_PARAM" --with-decryption --query Parameter.Value --output text --region "$REGION" 2>/dev/null || true)
model_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "x-goog-api-key: $KEY" \
  "https://generativelanguage.googleapis.com/v1beta/models/$MODEL" || echo 000)
unset KEY

docs=$(aws s3 ls "s3://$BUCKET/content/" --region "$REGION" 2>/dev/null | grep -c '\.md$' || true)

ok=1; problems=""
[ "$site_code" = "200" ] || { ok=0; problems="$problems site=$site_code"; }
[ "$model_code" = "200" ] || { ok=0; problems="$problems model=$model_code"; }
[ "${docs:-0}" -ge 1 ] || { ok=0; problems="$problems documents=0"; }
status=$([ $ok -eq 1 ] && echo ok || echo fail)

aws cloudwatch put-metric-data --region "$REGION" --namespace BakersCrumbs \
  --metric-name HealthCheckOK --value "$ok" --unit Count || true

printf '{"time":"%s","automation":"health-check","status":"%s","site_http":"%s","model":"%s","model_http":"%s","documents":%s,"release":"%s","problems":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$status" "$site_code" "$MODEL" "$model_code" "${docs:-0}" "$RELEASE" "${problems# }" | tee -a "$LOG"
