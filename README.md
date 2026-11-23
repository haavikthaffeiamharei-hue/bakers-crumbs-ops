# Baker's Crumbs: operations repository (SAM10 Final Project)

Baker's Crumbs is a question-and-answer assistant for an **invented** neighbourhood bakery. It is a reskin of
[LibreChat](https://github.com/danny-avila/LibreChat), connected to Google Gemini (free tier), deployed and operated
on AWS for the SAM10 (Systems Administration and Maintenance) final project.

This repository holds everything needed to rebuild the deployment: the reskin, the start-up script, the bakery
documents, and (later) the automation scripts. **It contains no keys, passwords or tokens.**

## Credits and licence

| | |
| --- | --- |
| Base system | LibreChat v0.8.9 (commit `4700c44eb`, cloned 23 Nov 2026) |
| Source | https://github.com/danny-avila/LibreChat |
| Author | Danny Avila and the LibreChat contributors |
| Licence | MIT: https://github.com/danny-avila/LibreChat/blob/main/LICENSE |
| AI model | Google Gemini via the Gemini API free tier (Google AI Studio) |
| Bakery content, logo, scripts | Written for this project; the bakery and all its details are invented |

AI-tool use: Claude (Anthropic) was used to explain the brief, suggest commands and help draft these files.
All steps were run and checked by the author in her own AWS account.

## What is in here

```
content/                                 Source copy of the 5 invented bakery documents (live copy is in S3)
librechat/branding/                      Baker's Crumbs logo (SVG) and browser icons (PNG)
librechat/Caddyfile.template             HTTPS front door (Caddy + Let's Encrypt) with security headers
librechat/docker-compose.override.yml    Branding mounts, key injection, Caddy, container logs -> CloudWatch
scripts/build_config.py                  Builds librechat.yaml: name, theme, hidden features, assistant instructions
scripts/start-bakers-crumbs.sh           Pulls content from S3, reads the Gemini key from Parameter Store, starts the app
scripts/request-logger.sh                Every minute: one JSON line per answer (question, duration, success, release)
scripts/install-monitoring.sh            Installs the CloudWatch agent, request-logger cron and log rotation
scripts/backup-mongodb.sh                AUTOMATION 1 - hourly database backup to S3
scripts/health-check.sh                  AUTOMATION 2 - 15-minute health check -> CloudWatch metric HealthCheckOK
scripts/install-automation.sh            Installs both automations as cron jobs
scripts/restore-mongodb.sh               Restores the database from the newest (or a given) S3 backup
scripts/score-answers.sh                 Scores the 6 test questions against the bakery documents (quality number)
monitoring/setup-cloudwatch.sh           Creates log groups, metric filters, alarms and the dashboard
monitoring/dashboard.json                CloudWatch dashboard layout
monitoring/cloudwatch-agent.json         CloudWatch agent config (memory, disk, log files)
docs/RUNBOOK-assistant-not-answering.md  Runbook for Gemini 404/429 failures
```

## How it fits together

1. `start-bakers-crumbs.sh` downloads the bakery documents from `s3://bakers-crumbs-tmth/content/`.
2. `build_config.py` turns them into LibreChat's `librechat.yaml`, including the Baker's Crumbs instructions.
3. The Gemini API key is read from SSM Parameter Store (`/bakers-crumbs/gemini-api-key`, SecureString)
   using the EC2 instance role, passed to Docker as an environment variable, and never written to disk.
4. Docker Compose starts LibreChat, MongoDB and its helper services on one EC2 instance.

## Deploy on a fresh server

Prerequisites: Ubuntu 24.04 EC2 instance with the `bakers-crumbs-ec2-role` instance profile, Docker, Git and the AWS CLI.

```bash
sudo -i
git clone https://github.com/danny-avila/LibreChat.git /opt/librechat
cd /opt/librechat && cp .env.example .env
# generate fresh secrets on the server (never commit them)
sed -i "s|^CREDS_KEY=.*|CREDS_KEY=$(openssl rand -hex 32)|" .env
sed -i "s|^CREDS_IV=.*|CREDS_IV=$(openssl rand -hex 16)|" .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" .env
sed -i "s|^JWT_REFRESH_SECRET=.*|JWT_REFRESH_SECRET=$(openssl rand -hex 32)|" .env
chmod 600 .env

git clone https://github.com/haavikthaffeiamharei-hue/bakers-crumbs-ops.git /opt/bakers-crumbs-ops
bash /opt/bakers-crumbs-ops/scripts/start-bakers-crumbs.sh
```

Always start or restart the app with `start-bakers-crumbs.sh`, not a bare `docker compose up`, so the key is injected.

### Monitoring
1. Create the SNS topic `bakers-crumbs-alerts` and confirm an email subscription.
2. With permission to manage CloudWatch (CloudShell as an admin, or a temporary policy on the instance role
   that is removed straight afterwards), run `bash monitoring/setup-cloudwatch.sh`.
3. On the server: `bash /opt/bakers-crumbs-ops/scripts/install-monitoring.sh`, then run the start script again
   so the containers send their logs to CloudWatch.
4. Create the alarm `bakers-crumbs-health-check-failed` on `BakersCrumbs/HealthCheckOK` (Minimum < 1 over 15 min,
   missing data = breaching) in the console.

### Automations, backup and restore
```bash
bash /opt/bakers-crumbs-ops/scripts/install-automation.sh     # schedules backup (hourly) and health check (15 min)
bash /opt/bakers-crumbs-ops/scripts/backup-mongodb.sh         # run a backup now
bash /opt/bakers-crumbs-ops/scripts/restore-mongodb.sh        # restore the newest backup (stops and restarts the app)
bash /opt/bakers-crumbs-ops/scripts/score-answers.sh          # score the test questions (PASS/FAIL + total)
```
Each automation run writes one JSON line to `/var/log/bakers-crumbs/automation.log`, shipped to the CloudWatch
log group `/bakers-crumbs/automation`. The S3 lifecycle rule `expire-backups-after-7-days` keeps backups for 7 days.
If `git pull` complains about local changes after installing, run `git config core.fileMode false` in the repo.

## Contribution log

Solo project: all work by Thaffeia Mharei T. Haavik.

| Date | Work |
| --- | --- |
| 17 Nov 2026 | Chose base system and domain. Laptop could not run Docker (WSL/DISM errors, full C: drive); AWS Academy sandboxes found to wipe every session. Opened a personal AWS account (Free plan). Root MFA, IAM user with MFA, MFA-protected admin role, $10 budget, CloudTrail, Gemini key in Parameter Store, S3 content bucket with versioning, least-privilege EC2 role. |
| 23 Nov 2026 | Launched EC2 (m7i-flex.large, encrypted 30 GB gp3, no SSH; access via Session Manager). Ran original LibreChat v0.8.9; built and deployed the reskin from this repository. Incident 1: `gemini-2.5-flash` 404 for new keys -> moved model. Elastic IP; CloudFront and CloudShell blocked pending new-account verification -> HTTPS with Caddy + Let's Encrypt. CloudWatch agent, request logger, container logs, 9 alarms, dashboard, SNS email. Incident 2: free-tier 429 detected by alarms -> flash-lite + no auto-titles. Hourly backup and 15-minute health check automations; restore test (database deleted and restored in 12 s). Runbook written. |
