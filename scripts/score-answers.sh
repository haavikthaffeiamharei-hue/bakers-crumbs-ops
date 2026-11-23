#!/usr/bin/env bash
# Scores the Baker's Crumbs test questions (evidence E-04).
# Reads each test question and the assistant's answer from MongoDB, checks the answer
# against the facts in content/*.md, and prints PASS/FAIL per question plus the total.
#
# Usage (on the server, as root):
#   bash /opt/bakers-crumbs-ops/scripts/score-answers.sh [FROM_UTC] [TO_UTC]
# Default window = the graded test run on 23 Nov 2026, 07:45-07:55 UTC (15:45-15:55 PST).
set -euo pipefail

FROM="${1:-2026-11-23T07:45:00Z}"
TO="${2:-2026-11-23T07:55:00Z}"

JS="
const textOf = (m) => {
  if (!m) return '';
  let t = typeof m.text === 'string' ? m.text : '';
  if (!t && Array.isArray(m.content)) {
    t = m.content.filter((c) => c && c.type === 'text')
      .map((c) => (typeof c.text === 'string' ? c.text : (c.text && c.text.value) || '')).join(' ');
  }
  return t;
};
db.messages.find({ isCreatedByUser: true, createdAt: { \$gte: new Date('$FROM'), \$lt: new Date('$TO') } })
  .sort({ createdAt: 1 }).forEach((q) => {
    const a = db.messages.find({ parentMessageId: q.messageId, isCreatedByUser: false })
      .sort({ createdAt: -1 }).limit(1).toArray()[0];
    print(JSON.stringify({ time: q.createdAt, question: textOf(q), answer: textOf(a), error: a ? !!a.error : true }));
  });
"

docker exec chat-mongodb mongosh --quiet "mongodb://localhost:27017/LibreChat" --eval "$JS" | python3 -c '
import json, re, sys

# Each test: which question it matches, what a correct answer MUST contain, and what it must NOT do.
# The expected facts come from content/01-05 *.md.
TESTS = [
  ("Q1 Saturday opening", r"saturday",   [r"\b6(:00)?\s*a\.?m"],                        [],                          "opens 6:00 AM"),
  ("Q2 Cookie Box price", r"cookie box", [r"450"],                                       [],                          "PHP 450"),
  ("Q3 Delivery and fee", r"deliver",    [r"\b60\b", r"\b90\b", r"500"],                 [],                          "PHP 60 / 90, PHP 500 minimum"),
  ("Q4 Cakes with nuts",  r"nut",        [r"cashew", r"staff|confirm|ask"],              [],                          "mango cake cashew + check with staff"),
  ("Q5 Cancel cake",      r"cancel",     [r"48"],                                         [r"^\W*yes\b"],              "48 h rule, no misleading Yes"),
  ("Q6 Pizza (not in docs)", r"pizza",   [r"not sure|don.t know|don.t have (that|any|this) information|@"], [r"(we )?(don.t|do not) sell pizza"], "say it does not know + contact"),
]

rows = [json.loads(l) for l in sys.stdin if l.strip().startswith("{")]
passed = 0
print("Baker\x27s Crumbs - test question score")
print("-" * 72)
for name, qpat, must, must_not, rule in TESTS:
    hits = [r for r in rows if re.search(qpat, r["question"], re.I) and r["answer"]]
    if not hits:
        print(f"MISSING  {name}: no answered question found in the window"); continue
    r = hits[-1]
    ans = r["answer"].strip()
    missing = [m for m in must if not re.search(m, ans, re.I)]
    bad = [m for m in must_not if re.search(m, ans, re.I)]
    ok = not missing and not bad and not r["error"]
    passed += ok
    why = "" if ok else ("  <- missing: " + ", ".join(missing) if missing else "") + ("  <- not allowed: " + ", ".join(bad) if bad else "")
    status = "PASS" if ok else "FAIL"
    print(f"{status}  {name}  [{rule}]{why}")
    print("      answer: " + re.sub(r"\s+", " ", ans)[:150])
print("-" * 72)
print(f"SCORE: {passed} of {len(TESTS)} correct")
'
