# Baker's Crumbs — operations repository (SAM10 Final Project)

Baker's Crumbs is a question-and-answer assistant for an **invented** neighbourhood bakery. It is a reskin of
[LibreChat](https://github.com/danny-avila/LibreChat), connected to Google Gemini (free tier), deployed and operated
on AWS for the SAM10 — Systems Administration and Maintenance final project.

This repository holds everything needed to rebuild the deployment: the reskin, the start-up script, the bakery
documents, and (later) the automation scripts. **It contains no keys, passwords or tokens.**

## Credits and licence

| | |
| --- | --- |
| Base system | LibreChat v0.8.9 (commit `4700c44eb`, cloned 23 Nov 2026) |
| Source | https://github.com/danny-avila/LibreChat |
| Author | Danny Avila and the LibreChat contributors |
| Licence | MIT — https://github.com/danny-avila/LibreChat/blob/main/LICENSE |
| AI model | Google Gemini via the Gemini API free tier (Google AI Studio) |
| Bakery content, logo, scripts | Written for this project; the bakery and all its details are invented |

AI-tool use: Claude (Anthropic) was used to explain the brief, suggest commands and help draft these files.
All steps were run and checked by the author in her own AWS account.

## What is in here

```
content/                      Source copy of the 5 invented bakery documents (live copy is in S3)
librechat/branding/           Baker's Crumbs logo (SVG) and browser icons (PNG)
librechat/docker-compose.override.yml   Port 80, librechat.yaml mount, branding mounts, key injection
scripts/build_config.py       Builds librechat.yaml: name, theme colours, hidden features, assistant instructions
scripts/start-bakers-crumbs.sh  Pulls content from S3, reads the Gemini key from Parameter Store, starts LibreChat
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

## Contribution log

Solo project — all work by Thaffeia Mharei T. Haavik.

| Date | Work |
| --- | --- |
| 17 Nov 2026 | Chose base system and domain. Laptop could not run Docker (WSL/DISM errors, full C: drive); AWS Academy sandboxes found to wipe every session. Opened a personal AWS account (Free plan). Root MFA, IAM user with MFA, MFA-protected admin role, $10 budget, CloudTrail, Gemini key in Parameter Store, S3 content bucket with versioning, least-privilege EC2 role. |
| 23 Nov 2026 | Launched EC2 (m7i-flex.large, encrypted 30 GB gp3, HTTP-only security group, no SSH; access via Session Manager). Installed Docker, ran original LibreChat v0.8.9, created this repository with the reskin and start-up script. |
