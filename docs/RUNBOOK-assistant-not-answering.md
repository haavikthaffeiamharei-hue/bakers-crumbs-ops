# RUNBOOK: Baker's Crumbs assistant is not answering (Gemini errors 404 / 429)

Owner: Thaffeia Mharei T. Haavik · Last tested: 23 Nov 2026 · Takes: about 10 minutes · Ask: Thaffeia Haavik

## 1. What this is for
Getting the assistant answering again when the website is up but answers fail because Google Gemini refuses the request (model retired = 404, free quota used up = 429).

## 2. How you know you need it
- An email: **ALARM: "bakers-crumbs-answers-failed"**, **"bakers-crumbs-health-check-failed"** or **"bakers-crumbs-slow-answers"**.
- Or a user sees a red box in the chat: *"The model provider could not complete this request (status 404)"* or *"The provider declined this request for exceeding a rate or spending limit"*.

Command that shows the problem (server terminal, after `sudo -i`):
```bash
tail -n 5 /var/log/bakers-crumbs/requests.log      # look for "success":false
tail -n 3 /var/log/bakers-crumbs/automation.log    # health check: "model_http" should be "200"
```

## 3. What it affects
Every customer: the site loads and they can log in, but no question gets an answer. Saved chats are not affected.

## 4. How to do it
Open a terminal on the server: **EC2 → Instances → bakers-crumbs-server → Connect → Session Manager → Connect**, then `sudo -i`.

**Step 1 — Find out which models work right now** (prints status codes only, never the key):
```bash
K=$(aws ssm get-parameter --name /bakers-crumbs/gemini-api-key --with-decryption --query Parameter.Value --output text --region us-east-1); for m in gemini-3.5-flash-lite gemini-3.5-flash gemini-flash-lite-latest; do R=$(curl -s -w "\n%{http_code}" -H "x-goog-api-key: $K" -H "Content-Type: application/json" -d '{"contents":[{"parts":[{"text":"Say hi"}]}]}' "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent"); echo "$m: $(echo "$R" | tail -1) $(echo "$R" | grep -o '"quotaId": "[^"]*"' | head -1)"; sleep 2; done; unset K
```
→ you should see one line per model. **200** = works, **404** = model not available to this key, **429** = quota used up (`PerDay` resets at midnight US Pacific = 4 PM Philippine time; `PerMinute` clears in a minute).

**Step 2 — Restart on a model that returned 200** (example: `gemini-3.5-flash-lite`):
```bash
GEMINI_MODEL=gemini-3.5-flash-lite bash /opt/bakers-crumbs-ops/scripts/start-bakers-crumbs.sh
```
→ you should see `Building librechat.yaml ... (model gemini-3.5-flash-lite ...)` and `Container LibreChat Started`.

**Step 3 — If the key itself is rejected (403 / "API key not valid")**: create a new key in Google AI Studio, then
**Systems Manager → Parameter Store → /bakers-crumbs/gemini-api-key → Edit → paste the new key into *Value*** (never into the name) → Save, delete the old key in AI Studio, and run Step 2 again.

**Step 4 — Make the change permanent**: edit `GEMINI_MODEL=${GEMINI_MODEL:-...}` in `scripts/start-bakers-crumbs.sh` on GitHub, commit with a message saying why, then on the server:
```bash
git -C /opt/bakers-crumbs-ops pull && bash /opt/bakers-crumbs-ops/scripts/start-bakers-crumbs.sh
```

## 5. How to check it worked
- [ ] the original symptom is gone: a **New Chat** with *"What time do you open on Saturday?"* answers "6:00 AM"
- [ ] `bash /opt/bakers-crumbs-ops/scripts/health-check.sh` prints `"status":"ok"` and `"model_http":"200"`
- [ ] no new alarms for 10 minutes, and an **OK** email arrives for the alarm that fired

## 6. How to undo it
Run Step 2 again with the previous model name (it is in the `release`/`model` fields of `/var/log/bakers-crumbs/requests.log`), or `git -C /opt/bakers-crumbs-ops checkout <previous-commit>` and run the start script.

## 7. Gotchas
- **Always restart with `start-bakers-crumbs.sh`**, never a bare `docker compose up`: the script injects the key from Parameter Store and forces LibreChat to re-read its config. A plain restart once left the old model running.
- **Asking many test questions in a row uses up the free quota.** Space them 20 s apart.
- A model can appear in Google's model list and still return 404 for a new key — always test with a real request (Step 1).
- If `git pull` says *"local changes would be overwritten"*, run `git -C /opt/bakers-crumbs-ops config core.fileMode false` and pull again.
- Session Manager logs you out after idle time — run `sudo -i` again after reconnecting.

## 8. Change history
- 23 Nov 2026 — written after incident 1 (`gemini-2.5-flash` returned 404 for a new key; fixed by moving to `gemini-3.5-flash`) and incident 2 (free-tier 429 after a burst of chats; fixed by moving to `gemini-3.5-flash-lite` and turning off auto-titles). Steps 1, 2 and 5 tested the same day.
