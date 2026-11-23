#!/usr/bin/env bash
# Creates Baker's Crumbs monitoring in CloudWatch: log groups with 30-day retention, metric filters,
# 8 alarms that email the SNS topic, and the dashboard. Safe to run again (it overwrites).
# Run in AWS CloudShell (us-east-1) while switched into the SAM10-Admin role:
#   bash monitoring/setup-cloudwatch.sh
set -euo pipefail
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
NS=BakersCrumbs

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=bakers-crumbs-server Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
TOPIC_ARN=$(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':bakers-crumbs-alerts')].TopicArn | [0]" --output text)
echo "Instance: $INSTANCE_ID"
echo "SNS topic: $TOPIC_ARN"
if [ "$INSTANCE_ID" = "None" ] || [ "$TOPIC_ARN" = "None" ]; then
  echo "ERROR: could not find the running bakers-crumbs-server instance or the bakers-crumbs-alerts topic" >&2
  exit 1
fi

echo "== Log groups (30-day retention) =="
for g in /bakers-crumbs/librechat /bakers-crumbs/mongodb /bakers-crumbs/caddy-access /bakers-crumbs/requests /bakers-crumbs/automation; do
  aws logs create-log-group --log-group-name "$g" 2>/dev/null || true
  aws logs put-retention-policy --log-group-name "$g" --retention-in-days 30
  aws logs tag-log-group --log-group-name "$g" --tags Project=SAM10
  echo "  $g"
done

echo "== Metric filters =="
mf() { # group, filter-name, pattern, metric, value
  aws logs put-metric-filter --log-group-name "$1" --filter-name "$2" --filter-pattern "$3" \
    --metric-transformations "metricName=$4,metricNamespace=$NS,metricValue=$5,defaultValue=0"
  echo "  $4"
}
mf /bakers-crumbs/caddy-access http-requests     '{ $.status > 0 }'    HttpRequests     1
mf /bakers-crumbs/caddy-access http-5xx          '{ $.status >= 500 }' Http5xx          1
aws logs put-metric-filter --log-group-name /bakers-crumbs/caddy-access --filter-name http-response-time \
  --filter-pattern '{ $.status > 0 }' \
  --metric-transformations "metricName=ResponseTimeSeconds,metricNamespace=$NS,metricValue=\$.duration"
echo "  ResponseTimeSeconds"
mf /bakers-crumbs/requests answers-total  '{ $.event = "answer" }'                        AnswersTotal  1
mf /bakers-crumbs/requests answers-failed '{ $.event = "answer" && $.success IS FALSE }'  AnswersFailed 1
mf /bakers-crumbs/requests answers-empty  '{ $.event = "answer" && $.empty IS TRUE }'     EmptyAnswers  1
aws logs put-metric-filter --log-group-name /bakers-crumbs/requests --filter-name answer-duration \
  --filter-pattern '{ $.event = "answer" && $.duration_ms > 0 }' \
  --metric-transformations "metricName=AnswerDurationMs,metricNamespace=$NS,metricValue=\$.duration_ms"
echo "  AnswerDurationMs"

echo "== Alarms =="
alarm() { # name, description, then put-metric-alarm args
  local name=$1 desc=$2; shift 2
  aws cloudwatch put-metric-alarm --alarm-name "$name" --alarm-description "$desc" \
    --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" --tags Key=Project,Value=SAM10 "$@"
  echo "  $name"
}
alarm bakers-crumbs-cpu-high "CPU above 85% for 10 minutes: look for a stuck process or runaway loop." \
  --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average --period 300 --evaluation-periods 2 --threshold 85 --comparison-operator GreaterThanThreshold \
  --treat-missing-data missing
alarm bakers-crumbs-status-check-failed "EC2 status check failed: look at the instance." \
  --namespace AWS/EC2 --metric-name StatusCheckFailed --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Maximum --period 60 --evaluation-periods 1 --threshold 0 --comparison-operator GreaterThanThreshold \
  --treat-missing-data breaching
alarm bakers-crumbs-disk-high "Root disk more than 85% used for an hour: clean up logs or grow the disk." \
  --namespace CWAgent --metric-name disk_used_percent --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Maximum --period 3600 --evaluation-periods 1 --threshold 85 --comparison-operator GreaterThanThreshold \
  --treat-missing-data missing
alarm bakers-crumbs-memory-high "Memory above 90% for 5 minutes: a container may be about to be killed." \
  --namespace CWAgent --metric-name mem_used_percent --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average --period 300 --evaluation-periods 1 --threshold 90 --comparison-operator GreaterThanThreshold \
  --treat-missing-data missing
alarm bakers-crumbs-http-5xx "Any HTTP 5xx from the site in a minute: the app or proxy is failing." \
  --namespace "$NS" --metric-name Http5xx --statistic Sum --period 60 --evaluation-periods 1 \
  --threshold 0 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching
alarm bakers-crumbs-answers-failed "More than 5% of answers failed in 15 minutes: the site is up but the assistant is not working (e.g. model or key problem)." \
  --metrics '[{"Id":"failed","MetricStat":{"Metric":{"Namespace":"BakersCrumbs","MetricName":"AnswersFailed"},"Period":900,"Stat":"Sum"},"ReturnData":false},{"Id":"total","MetricStat":{"Metric":{"Namespace":"BakersCrumbs","MetricName":"AnswersTotal"},"Period":900,"Stat":"Sum"},"ReturnData":false},{"Id":"pct","Expression":"IF(total > 0, 100 * failed / total, 0)","Label":"Failed answers %","ReturnData":true}]' \
  --evaluation-periods 1 --threshold 5 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching
alarm bakers-crumbs-empty-answer "An empty answer in 30 minutes: the bakery documents are probably missing or unreadable." \
  --namespace "$NS" --metric-name EmptyAnswers --statistic Sum --period 1800 --evaluation-periods 1 \
  --threshold 0 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching
alarm bakers-crumbs-slow-answers "Average answer time above 10 s for 5 minutes: the assistant is too slow (Gemini usually answers in 2-6 s)." \
  --namespace "$NS" --metric-name AnswerDurationMs --statistic Average --period 300 --evaluation-periods 1 \
  --threshold 10000 --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching

echo "== Dashboard =="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DASH=$(sed -e "s|__INSTANCE_ID__|$INSTANCE_ID|g" -e "s|__ACCOUNT__|$ACCOUNT_ID|g" "$(dirname "$0")/dashboard.json")
aws cloudwatch put-dashboard --dashboard-name BakersCrumbs --dashboard-body "$DASH" >/dev/null
echo "  BakersCrumbs"
echo "Done."
