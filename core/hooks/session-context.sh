#!/usr/bin/env bash
# SessionStart hook — orients every session. stdout becomes session context.
# Additive only; never blocks. Fail-open on any error.
IN=""; [ -t 0 ] || IN=$(timeout 2 cat 2>/dev/null)   # SessionStart JSON (session_id, source); bounded: an open, silent stdin must never hang session start
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0

BRANCH=$(git branch --show-current 2>/dev/null || echo "?")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

SPEC=$(ls -t .claude/specs/*-spec.md 2>/dev/null | head -1)
PLAN=""
if [ -n "$SPEC" ]; then
  CANDIDATE="${SPEC%-spec.md}-plan.md"
  [ -f "$CANDIDATE" ] && PLAN="$CANDIDATE"
fi

# Test runner: the project's marker glob (project.md `test_runner_marker`), else common ones.
MARKER=$(node "$(dirname "$0")/lib/project-config.js" test_runner_marker 2>/dev/null)
TESTS="absent"
for m in ${MARKER:-jest.config.* vitest.config.* playwright.config.* pytest.ini pyproject.toml go.mod}; do
  ls $m >/dev/null 2>&1 && { TESTS="present($m)"; break; }
done

# Harness drift: installed files edited in place instead of at the harness source (2026-10-19).
# The manifest is "<sha256>  <path>" lines, sha256sum's own format; a deleted file is not "edited".
DRIFT=""
MAN=.claude/.harness-manifest
if [ -f "$MAN" ]; then
  EDITED=$(cd .claude && grep -vE '^(#|version |source )' .harness-manifest | sha256sum -c --quiet --ignore-missing 2>/dev/null | grep -c ': FAILED$')
  HSRC=$(sed -n 's/^source //p' "$MAN" | head -1)
  DRIFT=" | harness_edited=${EDITED:-0} | harness_source=${HSRC:-unrecorded}"
fi

# This session's id (the lock's owner_session) and any measurement lock (hooks/lock-gate.sh asks
# non-owners before heavy commands while it exists).
SID=$(printf '%s' "$IN" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).session_id||"")}catch{}})' 2>/dev/null)
LOCKF=$(node "$(dirname "$0")/lib/project-config.js" measurement_lock 2>/dev/null); LOCKF="${LOCKF:-.claude/runs/MEASUREMENT-IN-PROGRESS.md}"
LOCKS=""
if [ -f "$LOCKF" ]; then
  LOCKS=$(SID="$SID" node -e 'const l=require("fs").readFileSync(process.argv[1],"utf8");const f=k=>((l.match(new RegExp("^[ \\t>*-]*"+k+":[ \\t]*(.*?)[ \\t\\r]*$","m"))||[])[1]||"").trim();
    const os=[...l.matchAll(/^[ \t>*-]*owner_session:[ \t]*(.*?)[ \t\r]*$/gm)].map(m=>m[1].trim()),n=f("owner_name")||"unknown",e=f("expected_end"),t=Date.parse(e);
    const end=e&&!isNaN(t)?e:"end unknown",stale=e&&!isNaN(t)&&Date.now()>t+3600e3;
    process.stdout.write(" | lock="+n+" until "+end+(stale?" STALE":"")+(process.env.SID&&os.includes(process.env.SID)?" (yours)":""))' "$LOCKF" 2>/dev/null)
fi

echo "[harness] branch=${BRANCH} | dirty_files=${DIRTY} | newest_spec=${SPEC:-none} | plan=${PLAN:-none} | tests=${TESTS}${DRIFT}${SID:+ | session=$SID}${LOCKS}"
exit 0
