#!/usr/bin/env bash
# SessionStart hook — orients every session. stdout becomes session context.
# Additive only; never blocks. Fail-open on any error.
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

echo "[harness] branch=${BRANCH} | dirty_files=${DIRTY} | newest_spec=${SPEC:-none} | plan=${PLAN:-none} | tests=${TESTS}${DRIFT}"
exit 0
