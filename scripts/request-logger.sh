#!/usr/bin/env bash
# Request logger for Baker's Crumbs (runs every minute from cron).
# Reads new assistant answers from LibreChat's MongoDB and writes one JSON line per answer to
# /var/log/bakers-crumbs/requests.log: the question asked, how long the answer took, whether it
# succeeded (no error and not empty), and which release answered. The CloudWatch agent ships the
# file to the /bakers-crumbs/requests log group, where metric filters turn it into metrics.
#
# duration_ms is approximate: answer saved time minus question saved time.
set -euo pipefail

STATE_DIR=/var/lib/bakers-crumbs
OUT_DIR=/var/log/bakers-crumbs
STATE_FILE=$STATE_DIR/request-logger.since
OUT=$OUT_DIR/requests.log
mkdir -p "$STATE_DIR" "$OUT_DIR"

SINCE=$(cat "$STATE_FILE" 2>/dev/null || date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%S.000Z)
RELEASE=$(grep -E '^BAKERS_CRUMBS_RELEASE=' /opt/librechat/.env | cut -d= -f2 || echo unknown)

read -r -d '' JS <<'EOF' || true
const since = new Date('__SINCE__');
const release = '__RELEASE__';
// leave answers younger than 20 s alone: they may still be streaming
const until = new Date(Date.now() - 20000);
let latest = since;
const textOf = (m) => {
  if (!m) return '';
  let t = typeof m.text === 'string' ? m.text : '';
  if (!t && Array.isArray(m.content)) {
    t = m.content
      .filter((c) => c && c.type === 'text')
      .map((c) => (typeof c.text === 'string' ? c.text : (c.text && c.text.value) || ''))
      .join(' ');
  }
  return t;
};
db.messages
  .find({ isCreatedByUser: false, createdAt: { $gt: since, $lte: until } })
  .sort({ createdAt: 1 })
  .forEach((r) => {
    const q = r.parentMessageId ? db.messages.findOne({ messageId: r.parentMessageId }) : null;
    const answer = textOf(r);
    const error = !!r.error;
    const empty = !error && answer.trim().length === 0;
    print(JSON.stringify({
      event: 'answer',
      time: r.createdAt.toISOString(),
      conversationId: r.conversationId,
      question: q ? textOf(q).slice(0, 300) : null,
      answer_chars: answer.length,
      duration_ms: q ? (new Date(r.createdAt) - new Date(q.createdAt)) : null,
      success: !error && !empty,
      error: error,
      empty: empty,
      model: r.model || null,
      release: release,
    }));
    if (r.createdAt > latest) latest = r.createdAt;
  });
print('#SINCE ' + latest.toISOString());
EOF
JS=${JS//__SINCE__/$SINCE}
JS=${JS//__RELEASE__/$RELEASE}

RESULT=$(docker exec chat-mongodb mongosh --quiet "mongodb://localhost:27017/LibreChat" --eval "$JS")
echo "$RESULT" | grep '^{' >> "$OUT" || true
NEW_SINCE=$(echo "$RESULT" | sed -n 's/^#SINCE //p' | tail -1)
if [ -n "$NEW_SINCE" ]; then
  echo "$NEW_SINCE" > "$STATE_FILE"
fi
