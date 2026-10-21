#!/usr/bin/env bash
# Harness self-check — run after any change to the harness.
# Hook integrity + deny/allow matrices (in sandboxed temp repos, so results don't depend on your
# branch or your project.md), config validity, doc drift and dead links, and the contract linters
# between agent files and guides/ai-workflow.md + guides/research-workflow.md.
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
DEAD=$(cd "$H" && find . -name '*.md' -not -path './investigations/*' -not -path './specs/*' -not -path './runs/*' -not -path './.harness-retired/*' | while read -r f; do
  d=$(dirname "$f"); grep -o -E '\]\((\.{1,2}/[^)#]+)' "$f" | sed 's/](//' | while read -r l; do
    case "$l" in */project.md) continue;; esac; [ -e "$d/$l" ] || echo "$f -> $l"; done; done)
[ -z "$DEAD" ] && ok "no dead relative links in harness markdown" || { fail "dead relative links:"; echo "$DEAD" | sed 's/^/         /'; }
echo "== 5. Contract linter (agent files ↔ ai-workflow.md) =="
WF="$H/guides/ai-workflow.md"
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
RW="$H/guides/research-workflow.md"
AG="${HC_AGENTS_DIR:-$H/agents}"
check "guides/research-workflow.md exists" test -f "$RW"
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

echo "== 5d. Runner: verbatim command runner (2026-10-19) =="
# What this can't prove: that runner REFUSES at runtime. Agent files load at session start, so test
# refusals with a fresh `claude -p` dispatch (delegation.md, "Runner briefs").
PT="$ROOT/project-template/project.md"   # exists in the harness source repo only, not once installed
if [ "$H" = "$ROOT/core" ] && [ -f "$PT" ]; then
  check "project template: Commands has a 'Writes files' column" grep -qF '| Purpose | Command | Notes | Writes files |' "$PT"
  check "project template: lint recipe names eslint-summary.js" grep -qF 'eslint-summary.js' "$PT"
else
  echo "  SKIP  project template checks (not the harness source repo)"
fi

RN="$AG/runner.md"
if [ -f "$RN" ]; then
  ok "agents/runner.md exists"
  [ "$(model_of "$RN")" = "claude-haiku-5-5" ] && ok "runner model claude-haiku-5-5" || fail "runner model is not claude-haiku-5-5"
  for t in Bash Read; do has_tool "$RN" "$t" && ok "runner has $t" || fail "runner lacks $t"; done   # Grep may be listed, but is absent at runtime (2026-10-19)
  for t in Write Edit Agent NotebookEdit; do has_tool "$RN" "$t" && fail "runner has $t (it must not edit files or dispatch)" || ok "runner has no $t"; done
  case "$(tools_of "$RN")" in *'*'*) fail "runner tool list contains '*'";; *) ok "runner tool list has no wildcard";; esac
  for tok in "verbatim" "--fix" "repo_root" "Writes files" "approval" "Never count" 'EPOCHREALTIME' 'Never depend on it' \
             'simple command' 'VAR=value' 'yarn run X' 'as many words as' '`..` segment' "can't be read" "cd '<repo_root>' && mkdir -p"; do
    grep -qF -- "$tok" "$RN" && ok "runner.md states '$tok'" || fail "runner.md lost '$tok'"
  done
  check "runner description names delegation.md" sh -c "sed -n 's/^description: //p' '$RN' | grep -q 'delegation.md'"
else
  fail "agents/runner.md missing"
fi
check "delegation.md has the runner row" grep -qF '| `runner` |' "$H/rules/delegation.md"
grep -qF 'A failed check comes back `FAILED`' "$H/rules/delegation.md" && fail "delegation.md says a failed check returns FAILED (runner returns DONE + fail verdict)" || ok "delegation.md doesn't contradict runner check semantics"
check "delegation.md: DONE doesn't mean the checks passed" grep -qF "doesn't mean the checks passed" "$H/rules/delegation.md"
check "delegation.md lint recipe includes untracked files" grep -qF 'git ls-files --others --exclude-standard' "$H/rules/delegation.md"
check "delegation.md has '## Runner briefs'" grep -qxF '## Runner briefs' "$H/rules/delegation.md"
check "autonomy.md scopes lint to the runner" grep -qF 'through the `runner` agent' "$H/rules/autonomy.md"
check "autonomy.md names the 'Lint on request only' opt-out" grep -qF 'Lint on request only' "$H/rules/autonomy.md"
check "CLAUDE.md documents rules/project/" grep -qF 'rules/project/' "$H/CLAUDE.md"
check "CLAUDE.md documents paths: frontmatter" grep -qF 'paths:' "$H/CLAUDE.md"
grep -qF 'not** auto-loaded' "$H/CLAUDE.md" && fail "CLAUDE.md still claims rules are not auto-loaded (measured false 2026-10-19)" || ok "CLAUDE.md no longer claims rules aren't auto-loaded"
ES="$H/scripts/eslint-summary.js"   # optional helper for ESLint projects (2026-10-19)
check "eslint-summary.js exists+executable" test -x "$ES"
check "eslint-summary.js syntax" node --check "$ES"
ET=$(mktemp -d)
cat > "$ET/r.json" <<JSON
[{"filePath":"$ROOT/src/a.ts","errorCount":1,"warningCount":1,"messages":[
   {"ruleId":"no-unused-vars","severity":2,"message":"x unused","line":3,"column":5},
   {"ruleId":"semi","severity":1,"message":"Missing semicolon","line":4,"column":1}]},
 {"filePath":"$ROOT/src/b.ts","errorCount":2,"warningCount":0,"messages":[
   {"ruleId":"no-unused-vars","severity":2,"message":"y unused","line":7,"column":2},
   {"ruleId":null,"severity":2,"fatal":true,"message":"Parsing error","line":1,"column":1}]}]
JSON
EOUT=$(node "$ES" "$ET/r.json" src/a.ts src/nope.ts 2>&1); ERC=$?
es() { printf '%s\n' "$EOUT" | grep -qxF -- "$2" && ok "eslint-summary: $1" || fail "eslint-summary: $1 (wanted: $2)"; }
[ "$ERC" -eq 0 ] && ok "eslint-summary: exit 0 on a report with errors" || fail "eslint-summary: exit $ERC on fixture"
es "totals"                   "TOTAL errors=3 warnings=1 files=2 files_with_errors=2 fatal=1"
es "top rule first"           "RULE no-unused-vars errors=2 warnings=0"
es "parse errors named"       "RULE (parse error) errors=1 warnings=0"
es "error files by count"     "ERROR_FILE src/b.ts errors=2"
es "changed file counted"     "CHANGED src/a.ts errors=1 warnings=1"
es "changed error located"    "CHANGED_ERROR src/a.ts:3:5 no-unused-vars x unused"
es "unlinted changed path"    "CHANGED_NOT_LINTED src/nope.ts"
printf '%s\n' "$EOUT" | grep -q "^CHANGED src/b.ts" && fail "eslint-summary: unchanged b.ts reported as CHANGED" || ok "eslint-summary: unchanged file not CHANGED"
printf '%s\n' "$EOUT" | grep -q "^CHANGED_ERROR.*semi" && fail "eslint-summary: a warning listed as CHANGED_ERROR" || ok "eslint-summary: warnings stay out of CHANGED_ERROR"
node "$ES" >/dev/null 2>&1; [ $? -eq 64 ] && ok "eslint-summary: usage → 64" || fail "eslint-summary: usage exit"
echo '{not json' > "$ET/bad.json"; node "$ES" "$ET/bad.json" >/dev/null 2>&1; [ $? -eq 65 ] && ok "eslint-summary: bad report → 65" || fail "eslint-summary: bad-report exit"
MC=$(sed -n '/^function matchesChanged/,/^}/p' "$ES" 2>/dev/null)
if [ -n "$MC" ] && node -e '
  const path=require("path"); const ROOT=process.argv[1]; '"$MC"'
  const t=[["src/a.ts","./src/a.ts",true],["src/c/x.ts","src/c/",true],["src/ab.ts","src/a",false],["src/a.ts",".",false],["src/a.ts","../other/src/a.ts",false]];
  process.exit(t.every(([r,a,e])=>matchesChanged(r,a)===e)?0:1)' "$ROOT" 2>/dev/null
then ok "eslint-summary: matchesChanged edge cases (./, dir/, boundary, root, outside)"
else fail "eslint-summary: matchesChanged edge cases"; fi
node -e 'const fs=require("fs"),[f,root]=process.argv.slice(1);fs.writeFileSync(f,JSON.stringify([{filePath:root+"/src/c.ts",errorCount:25,warningCount:0,messages:Array.from({length:25},(_,i)=>({ruleId:"r",severity:2,message:"m"+i,line:i+1,column:1}))}]))' "$ET/cap.json" "$ROOT"
COUT=$(node "$ES" "$ET/cap.json" src/c.ts $(for i in $(seq 1 25); do printf 'x%s.md ' "$i"; done) 2>&1)
[ "$(printf '%s\n' "$COUT" | grep -c '^CHANGED_ERROR src/c.ts')" = 20 ] && ok "eslint-summary: CHANGED_ERROR capped at 20 per file" || fail "eslint-summary: CHANGED_ERROR not capped at 20"
printf '%s\n' "$COUT" | grep -qxF 'CHANGED_ERROR_MORE src/c.ts 5' && ok "eslint-summary: CHANGED_ERROR_MORE line" || fail "eslint-summary: no CHANGED_ERROR_MORE src/c.ts 5"
[ "$(printf '%s\n' "$COUT" | grep -c '^CHANGED_NOT_LINTED ')" = 20 ] && printf '%s\n' "$COUT" | grep -qxF 'CHANGED_NOT_LINTED_MORE 5' && ok "eslint-summary: CHANGED_NOT_LINTED capped at 20 + _MORE" || fail "eslint-summary: CHANGED_NOT_LINTED not capped"
rm -rf "$ET"

if [ "$H" = "$ROOT/core" ] && [ -f "$ROOT/install.sh" ]; then   # the harness source repo only: never an adopter's own install.sh (2026-10-19)
  IT=$(mktemp -d); git -C "$IT" init -q
  bash "$ROOT/install.sh" "$IT" >/dev/null 2>&1
  sed -n 3p "$IT/.claude/.harness-manifest" 2>/dev/null | grep -q '^source /' && ok "install: manifest line 3 records 'source <path>'" || fail "install: manifest has no 'source' line 3"
  sc() { CLAUDE_PROJECT_DIR="$IT" bash "$IT/.claude/hooks/session-context.sh" 2>/dev/null; }
  sc | grep -q 'harness_edited=0' && ok "session-context: clean install → harness_edited=0" || fail "session-context: no harness_edited=0 on a clean install"
  sc | grep -q 'harness_source=/' && ok "session-context: prints harness_source" || fail "session-context: no harness_source"
  echo '<!-- local edit -->' >> "$IT/.claude/rules/git.md"
  sc | grep -q 'harness_edited=1' && ok "session-context: one edited file → harness_edited=1" || fail "session-context: edit not counted"
  mv "$IT/.claude/.harness-manifest" "$IT/m.bak"; OUT=$(sc); RC=$?
  { [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^\[harness\]' && ! printf '%s' "$OUT" | grep -q 'harness_edited'; } \
    && ok "session-context: no manifest → line printed, no drift fields, exit 0" || fail "session-context: no-manifest case"
  mv "$IT/m.bak" "$IT/.claude/.harness-manifest"; rm -f "$IT/.claude/rules/bug-fixes.md"; OUT=$(sc); RC=$?
  { [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'harness_edited=1'; } \
    && ok "session-context: deleted installed file → exit 0, not counted as edited" || fail "session-context: deleted-file case"
  IT2=$(mktemp -d); git -C "$IT2" init -q; bash "$ROOT/install.sh" "$IT2" >/dev/null 2>&1
  grep -v '^source ' "$IT2/.claude/.harness-manifest" > "$IT2/m" && mv "$IT2/m" "$IT2/.claude/.harness-manifest"   # legacy 2-line header
  DOC=$(bash "$ROOT/install.sh" --doctor "$IT2" 2>&1)
  { printf '%s' "$DOC" | grep -q 'manifest: all installed files match' && ! printf '%s' "$DOC" | grep -q 'missing: /'; } \
    && ok "install --doctor: legacy 2-line manifest parses" || fail "install --doctor: legacy manifest misparsed"
  IT3=$(mktemp -d); git -C "$IT3" init -q; bash "$ROOT/install.sh" "$IT3" >/dev/null 2>&1
  printf '[gone](./zz-nope.md)\n' > "$IT3/.claude/rules/zz-old.md"; printf y > "$IT3/.claude/rules/zz-edited.md"   # a relative link that breaks once retired
  HX=$(printf '[gone](./zz-nope.md)\n' | sha256sum | cut -d' ' -f1)
  printf '%s  rules/zz-old.md\n%s  rules/zz-edited.md\n' "$HX" "$HX" >> "$IT3/.claude/.harness-manifest"
  UPD=$(bash "$ROOT/install.sh" --update "$IT3" 2>&1)
  { ls "$IT3"/.claude/.harness-retired/*/rules/zz-old.md >/dev/null 2>&1 && [ ! -e "$IT3/.claude/rules/zz-old.md" ]; } \
    && ok "install --update: retires an unedited file that left core" || fail "install --update: unedited orphan not retired"
  { [ -e "$IT3/.claude/rules/zz-edited.md" ] && printf '%s' "$UPD" | grep -qF 'edited locally, kept: rules/zz-edited.md'; } \
    && ok "install --update: keeps (and warns about) an edited file that left core" || fail "install --update: edited orphan not kept with a warning"
  grep -q 'rules/zz-' "$IT3/.claude/.harness-manifest" && fail "install --update: orphans still in the manifest" || ok "install --update: orphans dropped from the manifest"
  (cd "$IT3" && CLAUDE_PROJECT_DIR="$IT3" bash "$IT3/.claude/scripts/harness-check.sh" 2>&1) | grep -q '\.harness-retired/' \
    && fail "installed harness-check scans .harness-retired/ (retired files' links are broken by design)" \
    || ok "installed harness-check ignores .harness-retired/"
  rm -rf "$IT3"
  printf '#!/bin/sh\ntouch "$(dirname "$0")/ADOPTER_INSTALL_RAN"\n' > "$IT/install.sh"
  (cd "$IT" && CLAUDE_PROJECT_DIR="$IT" bash "$IT/.claude/scripts/harness-check.sh" >/dev/null 2>&1)
  [ -e "$IT/ADOPTER_INSTALL_RAN" ] && fail "installed harness-check ran the adopter's own install.sh" || ok "installed harness-check never runs an adopter's install.sh"
  rm -rf "$IT" "$IT2"
fi

echo "== 5e. Loading classes: always / guides / paths (2026-10-21) =="
# Every rule loads in every session and subagent unless it says otherwise (measured 2026-10-19), so
# each rule declares its class: `load: always` (class 1) or `paths:` (class 3); class 2 lives in guides/.
fm() { awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$1" 2>/dev/null; }
fm_has() { fm "$1" | grep -q "^$2:"; }
paths_of() { fm "$1" | awk '/^paths:/{p=1; sub(/^paths:[ ]*/,""); if($0!=""){gsub(/^"|"$/,""); print}; next} p&&/^[ ]*- /{sub(/^[ ]*- [ ]*/,""); gsub(/^"|"$/,""); print; next} p&&/^[^ ]/{p=0}'; }
guide_consumers() { local b; b=$(basename "$1"); grep -l -F "$b" $(ls "$H"/agents/*.md "$H"/commands/*.md "$H"/skills/*/SKILL.md "$H/CLAUDE.md" "$H/rules/project/guides-index.md" 2>/dev/null) 2>/dev/null | grep -vxF "$1"; }
glob_matches() { # glob_matches <root> <glob>... — prints the number of files under <root> matching any glob (ignores node_modules/.next/.git/.claude)
  node -e '
    const fs=require("fs"),path=require("path"),[root,...globs]=process.argv.slice(1);
    const rx=g=>new RegExp("^"+g.replace(/[.+^$()|[\]\\]/g,"\\$&").replace(/\{([^}]*)\}/g,(_,a)=>"("+a.split(",").join("|")+")")
      .replace(/\*\*\//g,"\u0001").replace(/\*\*/g,"\u0002").replace(/\*/g,"[^/]*").replace(/\?/g,"[^/]")
      .replace(/\u0001/g,"(?:.*/)?").replace(/\u0002/g,".*")+"$");
    const res=globs.map(rx), skip=new Set(["node_modules",".next",".git",".claude"]); let n=0;
    (function walk(d,rel){ let es=[]; try{es=fs.readdirSync(d,{withFileTypes:true})}catch{return}
      for(const e of es){ if(skip.has(e.name)) continue; const r=rel?rel+"/"+e.name:e.name;
        if(e.isDirectory()) walk(path.join(d,e.name),r); else if(res.some(x=>x.test(r))) n++; } })(root,"");
    console.log(n)' "$@"
}
class_lint() { # class_lint <H>: prints a FAIL line per rule whose loading class is wrong
  local h="$1" f l p
  for f in $(find "$h/rules" -name '*.md' 2>/dev/null | sort); do
    l=$(fm "$f" | grep '^load:' | head -1); p=0; fm_has "$f" paths && p=1
    if [ -n "$l" ] && [ "$p" = 1 ]; then echo "  FAIL  ${f#$h/}: has both load: and paths: (paths: wins, so it would not always load)"
    elif [ -n "$l" ] && [ "$l" != "load: always" ]; then echo "  FAIL  ${f#$h/}: '$l' is not a class (only 'load: always')"
    elif [ -z "$l" ] && [ "$p" = 0 ]; then echo "  FAIL  ${f#$h/}: no class marker (load: always | paths:)"; fi
  done
  for f in rules/autonomy.md rules/git.md rules/multi-session.md rules/project/git-release-flow.md; do
    [ -f "$h/$f" ] || continue
    { fm "$h/$f" | grep -qx 'load: always' && ! fm_has "$h/$f" paths; } || echo "  FAIL  safety rule $f must be exactly 'load: always' with no paths: (it would stop loading in plain sessions)"
  done
}
stale_lint() { # stale_lint <H>: prints a FAIL line per reference to a guide by a path other than guides/ (links or prose)
  local h="$1" names
  names=$(find "$h/guides" -name '*.md' -exec basename {} .md \; 2>/dev/null | sort -u | paste -sd'|')
  [ -n "$names" ] || return 0
  grep -rnE "\b($names)\.md" "$h/agents" "$h/commands" "$h/templates" "$h/rules" "$h/skills" "$h/CLAUDE.md" "$h/project.md" 2>/dev/null \
    | grep -v 'guides/' | grep -vE '^[^:]+:[0-9]+:### From ' | sed "s|^$h/|  FAIL  stale guide path: |" | cut -c1-170
}
paths_lint() { # paths_lint <H> <root>: OK/FAIL per path-scoped rule; globs are passed as an array, never shell-expanded
  local h="$1" root="$2" f n GLA
  for f in $(find "$h/rules" -name '*.md' 2>/dev/null | sort); do
    fm_has "$f" paths || continue
    mapfile -t GLA < <(paths_of "$f")
    [ "${#GLA[@]}" -gt 0 ] || { echo "  FAIL  ${f#$h/}: paths: has no globs"; continue; }
    n=$(glob_matches "$root" "${GLA[@]}")
    [ "$n" -gt 0 ] && echo "  PASS  ${f#$h/}: paths: match $n file(s)" || echo "  FAIL  ${f#$h/}: paths: match no file"
  done
}
for f in rules/autonomy.md rules/git.md rules/multi-session.md; do [ -f "$H/$f" ] || fail "safety rule $f missing"; done
CL=$(class_lint "$H"); [ -z "$CL" ] && ok "every rule has exactly one valid class; safety rules are load: always only" || { FAILS=$((FAILS + $(printf '%s\n' "$CL" | grep -c FAIL))); printf '%s\n' "$CL"; }
ST=$(stale_lint "$H"); [ -z "$ST" ] && ok "no reference to any guide by a non-guides/ path (links or prose)" || { FAILS=$((FAILS + $(printf '%s\n' "$ST" | grep -c FAIL))); printf '%s\n' "$ST"; }
for g in $(find "$H/guides" -name '*.md' 2>/dev/null | sort); do
  [ -n "$(guide_consumers "$g")" ] && ok "guide ${g#$H/} has a consumer" || fail "guide ${g#$H/} has no consumer (nothing would ever load it)"
done
for g in $(find "$H/guides/project" -name '*.md' 2>/dev/null | sort); do
  grep -qF "$(basename "$g")" "$H/rules/project/guides-index.md" 2>/dev/null && ok "project guide $(basename "$g") is in guides-index.md" || fail "project guide $(basename "$g") missing from rules/project/guides-index.md"
done
for a in "$H"/agents/*.md; do
  grep -qF 'rules/project/guides-index.md' "$a" && ok "$(basename "$a") is told to read the project guide index" || fail "$(basename "$a") never points at rules/project/guides-index.md"
done
grep -qF 'rules/**/*.md' "$H/agents/reviewer.md" && ok "reviewer reads rules/** recursively (path-scoped and project rules too)" || fail "reviewer globs rules/ non-recursively (misses rules/project/)"
grep -qE 'Read.*guides/code-review\.md' "$H/agents/reviewer.md" && ok "reviewer Reads guides/code-review.md" || fail "reviewer only mentions guides/code-review.md, never Reads it"
# fixtures: the real lint functions, run against a fake tree, from a cwd where shell globbing would bite
FX=$(mktemp -d); mkdir -p "$FX/.claude/rules" "$FX/src/sub" "$FX/node_modules"; echo x > "$FX/src/sub/x.ts"; echo x > "$FX/node_modules/y.js"
printf -- '---\nload: always\npaths:\n  - "src/**"\n---\n' > "$FX/.claude/rules/both.md"
printf -- '---\nload: never\n---\n' > "$FX/.claude/rules/never.md"
printf -- '---\npaths:\n  - "src/**"\n---\n' > "$FX/.claude/rules/ok3.md"
printf -- '---\npaths:\n  - "node_modules/**"\n---\n' > "$FX/.claude/rules/nm.md"
printf -- '---\nload: always\npaths:\n  - "src/**"\n---\n' > "$FX/.claude/rules/git.md"
FXC=$(class_lint "$FX/.claude")
[ "$(printf '%s\n' "$FXC" | grep -c FAIL)" = 4 ] && ok "class_lint fixture: both-keys, load: never, and safety-with-paths caught (4 FAILs)" || { fail "class_lint fixture: expected 4 FAILs"; printf '%s\n' "$FXC"; }
FXP=$( cd "$FX" && paths_lint "$FX/.claude" "$FX" )
printf '%s\n' "$FXP" | grep -q 'ok3.md: paths: match 1 file' && ok "paths_lint from a cwd with src/ subdirs: globs not shell-expanded" || { fail "paths_lint expanded globs in the shell"; printf '%s\n' "$FXP"; }
printf '%s\n' "$FXP" | grep -q 'nm.md: paths: match no file' && ok "paths_lint: a node_modules-only glob fails" || fail "paths_lint counted node_modules"
mkdir -p "$FX/.claude/guides/project" "$FX/.claude/templates"; echo x > "$FX/.claude/guides/project/ext-sys.md"
echo 'see .claude/rules/ext-sys.md' > "$FX/.claude/templates/t.md"; echo '### From `rules/ext-sys.md` (provenance)' > "$FX/.claude/rules/prov.md"
FXS=$(stale_lint "$FX/.claude")
{ printf '%s\n' "$FXS" | grep -q 'templates/t.md' && ! printf '%s\n' "$FXS" | grep -q 'prov.md'; } && ok "stale_lint fixture: project guide name caught in a template; provenance header exempt" || { fail "stale_lint fixture"; printf '%s\n' "$FXS"; }
rm -rf "$FX"
GT=$(mktemp -d); mkdir -p "$GT/src"; echo x > "$GT/src/a.ts"
[ "$(glob_matches "$GT" '**/*.{ts,py}')" = 1 ] && ok "paths: match lint: brace glob positive control" || fail "paths: match lint brace glob broken"
rm -rf "$GT"
if [ "$H" != "$ROOT/core" ]; then   # installed projects only: globs must match real files
  PL=$(paths_lint "$H" "$ROOT"); printf '%s\n' "$PL"; FAILS=$((FAILS + $(printf '%s\n' "$PL" | grep -c FAIL)))
fi

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

echo "== 9. Project checks (.claude/project/checks.sh, 2026-10-19) =="
run_project_checks() { # run_project_checks <script>: a project's own checks; each FAIL line it prints counts
  local out rc n
  out=$(ROOT="$ROOT" H="$H" bash "$1" 2>&1); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'
  n=$(printf '%s\n' "$out" | grep -c '^ *FAIL ')
  FAILS=$((FAILS + n))
  if [ "$rc" -ne 0 ] && [ "$n" -eq 0 ]; then fail "project/checks.sh exited $rc"; fi
}
PCT=$(mktemp -d)
printf 'echo "  PASS  x"; exit 0\n' > "$PCT/ok.sh"
printf 'echo "  FAIL  y"; exit 1\n' > "$PCT/bad.sh"
printf 'exit 3\n' > "$PCT/silent.sh"
pc_delta() { ( FAILS=0; run_project_checks "$1" >/dev/null 2>&1; echo "$FAILS" ); }
[ "$(pc_delta "$PCT/ok.sh")" = 0 ]     && ok "run_project_checks: passing script adds 0 FAILs"      || fail "run_project_checks: passing script"
[ "$(pc_delta "$PCT/bad.sh")" = 1 ]    && ok "run_project_checks: its FAIL line counts"             || fail "run_project_checks: FAIL line not counted"
[ "$(pc_delta "$PCT/silent.sh")" = 1 ] && ok "run_project_checks: silent non-zero exit counts once" || fail "run_project_checks: silent non-zero exit"
rm -rf "$PCT"
if [ -f "$H/project/checks.sh" ]; then run_project_checks "$H/project/checks.sh"
else echo "  SKIP  no project/checks.sh"; fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "harness-check: ALL GREEN"
  exit 0
else
  echo "harness-check: $FAILS FAILURE(S)"
  exit 1
fi
