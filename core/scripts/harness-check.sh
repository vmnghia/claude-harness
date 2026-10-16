#!/usr/bin/env bash
# Harness self-check — run after any change to the harness.
# Hook integrity + deny/allow matrices (in sandboxed temp repos, so results don't depend on your
# branch or your project.md), config validity, doc drift and dead links, and the contract linters
# between agent files and rules/ai-workflow.md + rules/research-workflow.md.
# Runs from an installed harness (<repo>/.claude/scripts/) or from the harness repo (core/scripts/).
# Exit 0 = all green; exit 1 = at least one FAIL (each is printed).

set -u
H="$(cd "$(dirname "$0")/.." && pwd)"                      # the harness dir: <repo>/.claude or core/
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$H/.." && pwd)}"           # the project root (specs, .mcp.json)
GUARD="$H/hooks/git-guard.sh"
CTX="$H/hooks/session-context.sh"
FAILS=0

ok()   { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

echo "== 1. Hook integrity =="
check "git-guard.sh exists+executable" test -x "$GUARD"
check "session-context.sh exists+executable" test -x "$CTX"
check "git-guard.sh bash syntax" bash -n "$GUARD"
check "session-context.sh bash syntax" bash -n "$CTX"

echo "== 2. git-guard matrix (sandboxed) =="
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.email hc@local
git -C "$SANDBOX" config user.name harness-check

guard() { # guard <expected-exit> <branch-context-label> <command-string>
  local expect="$1" label="$2" cmd="$3" got
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" \
    | (cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$SANDBOX" "$GUARD") >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expect" ]; then
    ok "[$label] '$cmd' → exit $got"
  else
    fail "[$label] '$cmd' → exit $got (expected $expect)"
  fi
}

git -C "$SANDBOX" switch -qc feature/hc-test
guard 0 feature "ls -la"
guard 0 feature "git status"
guard 0 feature "git commit -m x"
guard 0 feature "git push origin feature/hc-test"
guard 0 feature "git push --force-with-lease origin feature/hc-test"
guard 2 feature "git push --force origin feature/hc-test"
guard 2 feature "git push -f origin feature/hc-test"
guard 2 feature "cd /tmp && git push -f origin foo"
guard 2 feature "git commit --no-verify -m x"
guard 2 feature "git push --no-verify origin feature/hc-test"
guard 2 feature "git push origin stable"
guard 2 feature "git push origin HEAD:release/0.0.1"
guard 2 feature "git push origin develop"
guard 2 feature "git push origin staging"

git -C "$SANDBOX" switch -qc master
guard 2 shared "git commit -m x"
guard 2 shared "git push origin some-feature"

git -C "$SANDBOX" commit -q --allow-empty -m seed
git -C "$SANDBOX" checkout -q --detach
guard 2 detached "git push origin stable"     # target rule still applies
guard 0 detached "git commit -m x"            # on-branch rules fail-open

# malformed / empty input must fail-open (allow)
printf 'not-json' | "$GUARD" >/dev/null 2>&1 && ok "malformed JSON → allow" || fail "malformed JSON → allow"
printf '' | "$GUARD" >/dev/null 2>&1 && ok "empty input → allow" || fail "empty input → allow"

# Shared branches from project.md (`shared_branches`, globs) replace the default list.
mkdir -p "$SANDBOX/.claude"
printf '# P\n\n```json harness\n{"shared_branches": ["trunk", "rel-*"]}\n```\n' > "$SANDBOX/.claude/project.md"
git -C "$SANDBOX" switch -qc feature/cfg
guard 2 config "git push origin rel-9"
guard 0 config "git push origin main"
git -C "$SANDBOX" switch -qc trunk
guard 2 config-shared "git commit -m x"
printf '```json harness\n{bad json\n```\n' > "$SANDBOX/.claude/project.md"
git -C "$SANDBOX" switch -qc main
guard 2 config-broken "git commit -m x"    # unparseable project.md → default list (main is shared)
check "hooks/lib/project-config.js exists" test -f "$H/hooks/lib/project-config.js"

echo "== 2c. sentry-read-gate matrix =="
SGATE="$H/hooks/sentry-read-gate.sh"
check "sentry-read-gate.sh exists+executable" test -x "$SGATE"
check "sentry-read-gate.sh bash syntax" bash -n "$SGATE"
sgate() { # sgate <expected-exit> <catalog tool name>
  local expect="$1" name="$2" got
  printf '{"tool_name":"mcp__sentry__execute_sentry_tool","tool_input":{"name":"%s","arguments":{}}}' "$name" \
    | "$SGATE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expect" ]; then ok "[sentry] '$name' → exit $got"; else fail "[sentry] '$name' → exit $got (expected $expect)"; fi
}
sgate 0 get_issue_tag_values
sgate 0 get_issue_breadcrumbs
sgate 2 update_project
sgate 2 delete_alert_rule
sgate 2 create_dsn
sgate 2 get_issue_tag_values_x   # exact match only, no prefix match
# fail-closed, unlike git-guard: an unidentifiable operation is denied
printf 'not-json' | "$SGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[sentry] malformed JSON → deny" || fail "[sentry] malformed JSON → deny"
printf '' | "$SGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[sentry] empty input → deny" || fail "[sentry] empty input → deny"
printf '{"tool_input":{}}' | "$SGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[sentry] missing name → deny" || fail "[sentry] missing name → deny"
check "sentry-read-gate registered in settings" grep -q "sentry-read-gate.sh" "$H/settings.json"

echo "== 2d. confluence-draft-gate matrix =="
CGATE="$H/hooks/confluence-draft-gate.sh"
check "confluence-draft-gate.sh exists+executable" test -x "$CGATE"
check "confluence-draft-gate.sh bash syntax" bash -n "$CGATE"
cgate() { # cgate <expected-exit> <label> <tool short name> <tool_input JSON>
  local expect="$1" label="$2" got
  printf '{"tool_name":"mcp__plugin_atlassian_atlassian__%s","tool_input":%s}' "$3" "$4" \
    | "$CGATE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$expect" ]; then ok "[confluence] $label → exit $got"; else fail "[confluence] $label → exit $got (expected $expect)"; fi
}
cgate 0 "create page draft"            createConfluenceContent '{"contentType":"page","draft":true,"title":"t","parent":{}}'
cgate 0 "create blogpost draft"        createConfluenceContent '{"contentType":"blogpost","draft":true,"title":"t","parent":{}}'
cgate 2 "create page draft:false"      createConfluenceContent '{"contentType":"page","draft":false,"title":"t","parent":{}}'
cgate 2 "create page, draft missing"   createConfluenceContent '{"contentType":"page","title":"t","parent":{}}'
cgate 2 "create page draft:\"true\""   createConfluenceContent '{"contentType":"page","draft":"true","title":"t","parent":{}}'
cgate 2 "create whiteboard draft"      createConfluenceContent '{"contentType":"whiteboard","draft":true,"title":"t","parent":{}}'
cgate 0 "update draft"                 updateConfluenceContent '{"contentId":"1","draft":true,"body":{}}'
cgate 2 "update published"             updateConfluenceContent '{"contentId":"1","body":{}}'
cgate 2 "update draft + ownerId"       updateConfluenceContent '{"contentId":"1","draft":true,"ownerId":"x"}'
cgate 2 "other write tool"             executeWrite '{"name":"createConfluencePage","draft":true}'
printf 'not-json' | "$CGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[confluence] malformed JSON → deny" || fail "[confluence] malformed JSON → deny"
printf '' | "$CGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[confluence] empty input → deny" || fail "[confluence] empty input → deny"

echo "== 3. Config validity =="
check ".claude/settings.json parses" node -e "JSON.parse(require('fs').readFileSync('$H/settings.json','utf8'))"
if [ -f "$ROOT/.mcp.json" ]; then
  check ".mcp.json parses" node -e "JSON.parse(require('fs').readFileSync('$ROOT/.mcp.json','utf8'))"
else echo "  SKIP  no .mcp.json"; fi
if [ -f "$H/project.md" ]; then
  check "project.md has a parseable json harness block" node -e "
    const m=require('fs').readFileSync('$H/project.md','utf8').match(/\\x60\\x60\\x60json harness\\s*\\n([\\s\\S]*?)\\n\\x60\\x60\\x60/);
    if(!m) process.exit(1); JSON.parse(m[1]);"
  n=$(grep -c 'TODO' "$H/project.md"); [ "$n" -gt 0 ] && echo "  NOTE  project.md still has $n TODO line(s): agents treat those facts as unavailable"
else echo "  SKIP  no project.md (harness repo, or not installed yet)"; fi
check "git-guard registered in settings" grep -q "git-guard.sh" "$H/settings.json"
check "session-context registered in settings" grep -q "session-context.sh" "$H/settings.json"

echo "== 4. Doc drift greps =="
LIVE="$H/agents/ $H/commands/ $H/rules/"
if grep -rq "claude_ai_Atlassian_Rovo" $LIVE; then
  fail "dead Rovo tool names in live prompt files"
else
  ok "no dead Rovo tool names in agents/commands/rules"
fi
# Relative links in harness markdown must resolve (project.md may be absent in the harness repo).
DEAD=$(cd "$H" && find . -name '*.md' -not -path './investigations/*' -not -path './specs/*' -not -path './runs/*' | while read -r f; do
  d=$(dirname "$f"); grep -o -E '\]\((\.{1,2}/[^)#]+)' "$f" | sed 's/](//' | while read -r l; do
    case "$l" in */project.md) continue;; esac; [ -e "$d/$l" ] || echo "$f -> $l"; done; done)
[ -z "$DEAD" ] && ok "no dead relative links in harness markdown" || { fail "dead relative links:"; echo "$DEAD" | sed 's/^/         /'; }
echo "== 5. Contract linter (agent files ↔ ai-workflow.md) =="
WF="$H/rules/ai-workflow.md"
pair() { # pair <token> <agent-file-basename>
  local tok="$1" agent="$H/agents/$2"
  if grep -q "$tok" "$WF" && grep -q "$tok" "$agent"; then
    ok "'$tok' in ai-workflow.md + $2"
  else
    fail "'$tok' missing from ai-workflow.md or $2"
  fi
}
pair "spec_path" planner.md
pair "plan_path" planner.md
pair "SPEC_READY" planner.md
pair "NEEDS_CLARIFICATION" planner.md
pair "test_result" coder.md
pair "build_result" coder.md
pair "changed_files" coder.md
pair "IMPLEMENTED" coder.md
pair "BLOCKED" coder.md
pair "scenarios_run" tester.md
pair "BUGS_FOUND" tester.md
pair "findings" reviewer.md
pair "APPROVED" reviewer.md
pair "CHANGES_REQUESTED" reviewer.md
pair "blocker | major | minor | nit" reviewer.md
if grep -q "lint_result" "$WF" "$H/agents/coder.md"; then
  fail "retired field 'lint_result' still referenced"
else
  ok "retired field 'lint_result' fully gone"
fi
# Staleness sweep, 2026-10-16: each line guards a defect found in the feature agents that day.
AGD="$H/agents"
for pin in coder:claude-opus-5-5 reviewer:claude-opus-5-5; do   # the owner 2026-10-16: opus+ for code and review
  a="${pin%%:*}"; m="${pin#*:}"
  [ "$(sed -n 's/^model: //p' "$AGD/$a.md" | head -1)" = "$m" ] && ok "$a model $m" || fail "$a model is not $m"
done
# Tool names the MCPs no longer expose (an unknown name silently drops the tool from the agent).
for stale in take_memory_snapshot getConfluencePage searchConfluenceUsingCql atlassian__fetch TodoWrite; do
  if grep -l "^tools:.*$stale" "$AGD"/*.md >/dev/null 2>&1; then
    fail "stale tool name '$stale' in: $(grep -l "^tools:.*$stale" "$AGD"/*.md | xargs -n1 basename | tr '\n' ' ')"
  else ok "no agent lists stale tool '$stale'"; fi
done
grep -q "4-agent" "$AGD"/*.md && fail "an agent still says '4-agent' (harness has two teams)" || ok "no agent says '4-agent'"
grep -q 'leave it running' "$AGD/tester.md" && fail "tester still leaves yarn dev running (collides with Coder's build)" || ok "tester stops the server it started"

echo "== 5b. Research contract linter (agent files ↔ research-workflow.md) =="
RW="$H/rules/research-workflow.md"
AG="${HC_AGENTS_DIR:-$H/agents}"
check "rules/research-workflow.md exists" test -f "$RW"
check "ai-workflow.md points to research-workflow.md" grep -q "research-workflow.md" "$WF"

is_stub()  { grep -q '^> \*\*STUB (' "$1"; }
tools_of() { sed -n 's/^tools: //p' "$1" | head -1; }
model_of() { sed -n 's/^model: //p' "$1" | head -1; }
has_tool() { tools_of "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qx "$2"; }

BROKEN=""
RESEARCH_AGENTS="research-lead incident-investigator repro-driver searcher web-reader designer writer"
for a in $RESEARCH_AGENTS; do
  f="$AG/$a.md"
  if [ ! -f "$f" ]; then fail "$a.md missing"; continue; fi
  if [ -z "$(tools_of "$f")" ]; then fail "$a.md has no single-line 'tools:' frontmatter"; BROKEN="$BROKEN $a"; fi
  case "$(tools_of "$f")" in *'*'*) fail "$a.md tool list contains '*' (wildcard — boundaries unenforceable)"; BROKEN="$BROKEN $a";; esac
done
# usable <agent>: file exists and its tool list could be read — otherwise its boundary checks
# would print PASS for tools it may well have, so they're skipped (it already FAILed above)
usable() { case " $BROKEN " in *" $1 "*) return 1;; esac; [ -f "$AG/$1.md" ]; }
check "commands/research.md exists" test -f "$H/commands/research.md"
for h in "## Framing" "## Running the team"; do   # sections /research dereferences by name
  check "research-lead.md has '$h'" grep -qxF "$h" "$AG/research-lead.md"
done

rtok() { # rtok <token> <agent> — contract token must appear in both files; stubs skip
  local f="$AG/$2.md"
  [ -f "$f" ] || return 0   # missing file already failed above
  if is_stub "$f"; then echo "  SKIP  (stub) '$1' in $2.md"; return 0; fi
  # -w: '_' is a word character, so NOT_REPRODUCED does not satisfy REPRODUCED
  if grep -qw "$1" "$RW" && grep -qw "$1" "$f"; then ok "'$1' in research-workflow.md + $2.md"
  else fail "'$1' missing from research-workflow.md or $2.md"; fi
}
rtok "AWAITING_HUMAN" research-lead
rtok "AWAITING_HUMAN" repro-driver
rtok "AWAITING_HUMAN" incident-investigator
rtok "AWAITING_HUMAN" designer
rtok "DIAGNOSED" incident-investigator
rtok "REPRODUCED" repro-driver
rtok "FOUND" searcher
rtok "GATHERED" web-reader
rtok "CANVAS_READY" designer
rtok "COPY_READY" writer
rtok "positive_control" searcher
rtok "positive_control" repro-driver

for a in research-lead incident-investigator; do
  for t in Agent Write Edit; do
    usable "$a" && { has_tool "$AG/$a.md" "$t" && ok "$a has $t" || fail "$a lacks $t"; }
  done
done
for a in repro-driver searcher web-reader writer; do
  for t in Agent Write Edit; do
    usable "$a" && { has_tool "$AG/$a.md" "$t" && fail "$a must not have $t" || ok "$a has no $t"; }
  done
done
usable designer && { has_tool "$AG/designer.md" Agent && fail "designer must not have Agent" || ok "designer has no Agent"; }
# The lead spot-checks web-reader quotes itself (2026-10-15).
usable research-lead && { has_tool "$AG/research-lead.md" WebFetch && ok "research-lead has WebFetch" || fail "research-lead lacks WebFetch"; }
# The lead searches via searcher or pinned `git grep`, never its own Grep/Glob (2026-10-16).
for t in Grep Glob; do
  usable research-lead && { has_tool "$AG/research-lead.md" "$t" && fail "research-lead must not have $t (search via searcher)" || ok "research-lead has no $t"; }
done
# Confluence drafts: research-lead only, gated by its own frontmatter hook (2026-10-15).
AT=mcp__plugin_atlassian_atlassian__
for a in research-lead incident-investigator repro-driver searcher web-reader designer writer; do
  usable "$a" || continue
  for t in executeWrite executeDestructive; do
    has_tool "$AG/$a.md" "$AT$t" && fail "$a must not have $t (gateway to every Atlassian write)" || ok "$a has no $t"
  done
  [ "$a" = research-lead ] && continue
  for t in createConfluenceContent updateConfluenceContent; do
    has_tool "$AG/$a.md" "$AT$t" && fail "$a must not have $t (Confluence drafts are research-lead's)" || ok "$a has no $t"
  done
done
if usable research-lead && { has_tool "$AG/research-lead.md" "${AT}createConfluenceContent" || has_tool "$AG/research-lead.md" "${AT}updateConfluenceContent"; }; then
  # the gate must sit in the lead's own frontmatter (between the first two --- lines)
  awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$AG/research-lead.md" | grep -q 'confluence-draft-gate.sh' \
    && ok "research-lead frontmatter registers confluence-draft-gate" \
    || fail "research-lead has Confluence write tools but its frontmatter doesn't register confluence-draft-gate.sh"
fi
for a in searcher writer web-reader designer; do
  usable "$a" && { has_tool "$AG/$a.md" Bash && fail "$a must not have Bash" || ok "$a has no Bash"; }
done

for pin in research-lead:claude-opus-5-5 incident-investigator:claude-opus-5-5 designer:claude-opus-5-5 \
           writer:claude-opus-5-5 searcher:claude-haiku-5-5 web-reader:claude-haiku-5-5 repro-driver:claude-sonnet-5-5; do
  a="${pin%%:*}"; m="${pin#*:}"
  [ -f "$AG/$a.md" ] && { [ "$(model_of "$AG/$a.md")" = "$m" ] && ok "$a model $m" || fail "$a model is '$(model_of "$AG/$a.md")', expected $m"; }
done

echo "== 5c. Quote verification + standalone delegation (2026-10-16) =="
# Offline: pages are data: URLs (Node's fetch reads them), so no network and no flakiness.
# What this can't prove: that the hook FIRES. Agent files load at session start, so test that
# with a fresh process, e.g. `claude -p --model claude-haiku-5-5 --allowedTools Agent,WebFetch
# "dispatch web-reader with <brief>"`, then look for the agent id in .claude/runs/quote-verify.log.
VQ="$H/scripts/verify-quote.sh"
QG="$H/hooks/quote-verify-gate.sh"
for f in "$VQ" "$QG"; do
  check "$(basename "$f") exists+executable" test -x "$f"
  check "$(basename "$f") bash syntax" bash -n "$f"
done
check "vendored js-yaml loads (hook parses the status block)" node -e "require('$H/vendor/js-yaml.min.js').load('a: 1')"
PAGE='<html><body><h1>Version support</h1><p>The <code>getFoo</code> function can only be exported from a <strong>page</strong>. It runs on the server and never in the browser, which is why secrets are safe there.</p><table><tr><td>v10.x</td><td>Current</td><td>2026-02-06</td></tr><tr><td>v9.x</td><td>EOL</td><td>2024-04-05</td></tr></table><p>Padding text so the page clears the two hundred character floor for a JS-rendered shell.</p></body></html>'
DURL="data:text/html;charset=utf-8,$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$PAGE")"
vq() { # vq <expected-exit> <label> <quote>
  local got; "$VQ" "$DURL" "$3" >/dev/null 2>&1; got=$?
  [ "$got" -eq "$1" ] && ok "verify-quote: $2 → exit $got" || fail "verify-quote: $2 → exit $got, expected $1"
}
vq 0 "exact prose"                 'It runs on the server and never in the browser'
vq 0 "markdown code+bold"          'The `getFoo` function can only be exported from a **page**.'
vq 0 "markdown table row"          'v10.x | Current | 2026-02-06'
vq 1 "one word changed"            'It runs on the server and never in the client'
vq 1 "paraphrase"                  'getFoo may only be exported by pages'
vq 1 "case changed"                'it runs on the server and never in the browser'
vq 1 "table cell changed"          'v10.x | Current | 2026-02-07'
"$VQ" "data:text/html,<p>tiny</p>" "tiny" >/dev/null 2>&1; [ $? -eq 2 ] && ok "verify-quote: under-200-char page → UNCHECKABLE" || fail "verify-quote: tiny page not UNCHECKABLE"
"$VQ" onlyone >/dev/null 2>&1; [ $? -eq 64 ] && ok "verify-quote: usage → 64" || fail "verify-quote: usage exit"

QT=$(mktemp -d)
qg() { # qg <expected-exit> <label> <agent-id> <last_assistant_message>
  local got
  node -e 'process.stdout.write(JSON.stringify({agent_id:process.argv[1],hook_event_name:"SubagentStop",last_assistant_message:process.argv[2]}))' "$3" "$4" \
    | TMPDIR="$QT" QV_LOG="$QT/log" CLAUDE_PROJECT_DIR="$ROOT" "$QG" >/dev/null 2>&1
  got=$?
  [ "$got" -eq "$1" ] && ok "quote-gate: $2 → exit $got" || fail "quote-gate: $2 → exit $got, expected $1"
}
sb() { printf -- '---\nagent: web-reader\nstatus: GATHERED\npayload:\n  sources:\n    - url: "%s"\n      quote: "%s"\n  unverified: []\n---\n' "$DURL" "$1"; }
qg 0 "verbatim quote allows stop"       q1 "$(sb 'It runs on the server and never in the browser')"
qg 2 "paraphrase blocks"                q2 "$(sb 'getFoo may only be exported by pages')"
qg 2 "missing status block blocks"      q3 "Found it, see above."
qg 0 "empty sources[] allows stop"      q4 "$(printf -- '---\nagent: web-reader\nstatus: NOT_FOUND\npayload:\n  sources: []\n---\n')"
qg 2 "!!js/function tag is rejected"    q5 "$(printf -- "---\nagent: web-reader\npayload:\n  sources:\n    - url: !!js/function 'function(){require(\"fs\").writeFileSync(\"%s/pwned\",\"x\")}'\n      quote: x\n---\n" "$QT")"
[ -e "$QT/pwned" ] && fail "quote-gate: !!js/function EXECUTED (yaml.load not safe)" || ok "quote-gate: no code ran from !!js/function"
for i in 1 2 3; do qg 2 "cap: block $i/3" q6 "$(sb 'getFoo may only be exported by pages')"; done
qg 0 "cap: 4th stop escapes"            q6 "$(sb 'getFoo may only be exported by pages')"
grep -q "q6 ESCAPE" "$QT/log" 2>/dev/null && ok "quote-gate: escape is logged" || fail "quote-gate: escape not logged"
rm -rf "$QT"

awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$AG/web-reader.md" | grep -q 'quote-verify-gate.sh' \
  && ok "web-reader frontmatter registers quote-verify-gate" \
  || fail "web-reader frontmatter doesn't register quote-verify-gate.sh"
check "rules/delegation.md exists" test -f "$H/rules/delegation.md"
check "delegation.md indexed in .claude/CLAUDE.md" grep -q "rules/delegation.md" "$H/CLAUDE.md"
for a in searcher web-reader; do
  check "$a.md description names standalone dispatch (delegation.md)" \
    sh -c "sed -n 's/^description: //p' '$AG/$a.md' | grep -q 'delegation.md'"
done
check "research-workflow.md documents standalone use" grep -q "Standalone use" "$RW"

echo "== 6. Spec/plan pair naming =="
PAIR_OK=true
for plan in "$H"/specs/*-plan.md; do
  [ -e "$plan" ] || continue
  spec="${plan%-plan.md}-spec.md"
  design="${plan%-plan.md}-design.md"
  if [ ! -f "$spec" ] && [ ! -f "$design" ]; then
    fail "orphan plan without sibling spec/design: $(basename "$plan")"
    PAIR_OK=false
  fi
done
$PAIR_OK && ok "every -plan.md has a sibling -spec.md or -design.md"

echo "== 7. research-discipline readers =="
check "rules/research-discipline.md exists" test -f "$H/rules/research-discipline.md"
for a in research-lead searcher web-reader designer writer incident-investigator repro-driver reviewer; do
  check "$a.md references research-discipline.md" grep -q "rules/research-discipline.md" "$AG/$a.md"
done

echo "== 8. findings template core =="
FT="$H/templates/findings-template.md"
check "templates/findings-template.md exists" test -f "$FT"
for h in "Answer" "Assumptions ledger" "Findings" "Not shown / ruled out" "Decisions" "Open" "Next" "Sources & files"; do
  check "core heading '## $h'" grep -qxF "## $h" "$FT"
done
check "frontmatter has status:" grep -q "^status:" "$FT"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "harness-check: ALL GREEN"
  exit 0
else
  echo "harness-check: $FAILS FAILURE(S)"
  exit 1
fi
