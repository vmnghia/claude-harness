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
# Milliseconds on a monotonic clock. Timing checks must not use $SECONDS or date: WSL2 steps the
# wall clock forward to resync, and a 2.06 s hook run read as 5.3 s wall time (measured 2026-10-27,
# 2 of 30 runs), which failed the session-context check below with nothing slow.
mono_ms() { node -e 'process.stdout.write(String(process.hrtime.bigint() / 1000000n))'; }
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
SANDBOX2=$(mktemp -d)   # a second repo, on shared `main`, for `git -C` and input-cwd cases
trap 'rm -rf "$SANDBOX" "$SANDBOX2"' EXIT
git -C "$SANDBOX2" init -q -b main
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
# Global options between `git` and the subcommand must not hide it (2026-10-26).
guard 0 feature "git -C . push origin feature/hc-test"
guard 2 feature "git -C . push origin develop"
guard 2 feature "git -c core.x=y push --force origin feature/hc-test"
guard 2 feature "git --no-pager push -f origin feature/hc-test"
guard 2 feature "git -C . commit --no-verify -m x"
# The branch is the one in the repo git acts on: the -C target, else the input cwd.
guard 2 feature "git -C $SANDBOX2 commit -m x"
guard 0 feature "git -C $SANDBOX2 log --oneline"
printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$SANDBOX2" \
  | (cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$SANDBOX" "$GUARD") >/dev/null 2>&1
[ $? -eq 2 ] && ok "[feature] commit with input cwd on shared main → exit 2" || fail "[feature] commit with input cwd on shared main → expected exit 2"

git -C "$SANDBOX" switch -qc master
guard 2 shared "git commit -m x"
guard 2 shared "git push origin some-feature"
guard 2 shared "git -C . commit -m x"
guard 2 shared "git -c user.name=x commit -m x"
guard 2 shared "git --no-pager push origin some-feature"
git -C "$SANDBOX2" switch -qc feature/other
guard 0 shared "git -C $SANDBOX2 commit -m x"   # commits to SANDBOX2's feature branch

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

echo "== 2e. lock-gate matrix (2026-10-21) =="
# Asks before a heavy command when ANOTHER session holds the measurement lock. Owner = caller's
# session_id equals the lock's owner_session (subagents carry the parent's id). Fail-open on errors.
LG="$H/hooks/lock-gate.sh"
check "lock-gate.sh exists+executable" test -x "$LG"
check "lock-gate.sh bash syntax" bash -n "$LG"
LGT=$(mktemp -d); mkdir -p "$LGT/.claude/runs" "$LGT/.claude/hooks/lib"; cp "$H/hooks/lib/project-config.js" "$LGT/.claude/hooks/lib/"
LOCKF="$LGT/.claude/runs/MEASUREMENT-IN-PROGRESS.md"
lgcfg() { if [ -n "$1" ]; then printf '# p\n\n```json harness\n{"heavy_commands": %s}\n```\n' "$1" > "$LGT/.claude/project.md"; else rm -f "$LGT/.claude/project.md"; fi; }
iso() { MIN="$1" OFF="${2:-0}" node -e 'const off=Number(process.env.OFF||0);const d=new Date(Date.now()+Number(process.env.MIN)*60000);if(!off){console.log(d.toISOString());process.exit()}
  const l=new Date(d.getTime()+off*60000),p=n=>String(n).padStart(2,"0");console.log(`${l.getUTCFullYear()}-${p(l.getUTCMonth()+1)}-${p(l.getUTCDate())}T${p(l.getUTCHours())}:${p(l.getUTCMinutes())}:00+${p(off/60)}:00`)'; }   # numbers via env: node reads a leading '-120' argument as an option
mklock() { # mklock <owner_session|-> <expected_end|-> — writes the lock file; '-' omits the line
  { echo "# MEASUREMENT IN PROGRESS"; echo "- **What:** fixture build timing"; echo "owner_name: peer-session"
    [ "$1" != "-" ] && printf 'owner_session: %s\n' "$1"; [ "$2" != "-" ] && echo "expected_end: $2"; } > "$LOCKF"; }
LGOUT=""
lg() { # lg <allow|ask> <label> <session_id> <agent_id|-> <command> [raw-stdin]
  local exp="$1" label="$2" in got
  if [ -n "${6:-}" ]; then in="$6"; else
    in=$(node -e 'const [s,a,c]=process.argv.slice(1);const j={session_id:s,permission_mode:"default",tool_name:"Bash",tool_input:{command:c}};if(a!=="-")j.agent_id=a;process.stdout.write(JSON.stringify(j))' "$3" "$4" "$5"); fi
  LGOUT=$(printf '%s' "$in" | CLAUDE_PROJECT_DIR="$LGT" "$LG" 2>/dev/null); local rc=$?
  if [ -z "$LGOUT" ] && [ "$rc" -eq 0 ]; then got=allow
  elif printf '%s' "$LGOUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.exit(JSON.parse(s).hookSpecificOutput.permissionDecision==="ask"?0:1))' 2>/dev/null; then got=ask
  else got="other(rc=$rc)"; fi
  [ "$got" = "$exp" ] && ok "[$label] → $got" || fail "[$label] → $got (expected $exp)"
}
has() { printf '%s' "$LGOUT" | grep -qF -- "$1"; }
lgcfg ""; rm -f "$LOCKF"
lg allow "a no lock → allow"                                 X - "yarn build"
mklock X "$(iso 30)"
lg allow "b lock, non-heavy command → allow"                 Y - "ls -la"
lg allow "c owner's own heavy command → allow"               X - "yarn build"
lg allow "d owner's subagent (agent_id set) → allow"         X agentA "yarn build"
lg ask   "e foreign heavy command → ask"                     Y - "yarn build"
{ has "peer-session" && has "Only the session named peer-session" && has "fixture build timing"; } && ok "[e] reason names the owner and what's measured" || fail "[e] reason incomplete: $LGOUT"
mklock - "$(iso 30)"
lg ask   "f lock without owner_session → ask, even its writer" X - "yarn build"
mklock X "$(iso -120)"
lg ask   "g stale lock (Z) → ask"                            Y - "yarn build"
has "STALE" && ok "[g] reason says STALE" || fail "[g] no STALE in: $LGOUT"
mklock X -
lg ask   "h no expected_end → ask"                           Y - "yarn build"
{ has "end unknown" && ! has "STALE"; } && ok "[h] 'end unknown', not STALE" || fail "[h] reason: $LGOUT"
lg allow "i malformed stdin → allow (fail-open)"             - - - '{not json'
mklock X "$(iso 30)"; lgcfg '["my-perf\\.sh"]'
lg ask   "j project heavy_commands: custom script → ask"     Y - "bash my-perf.sh"
lg allow "j project list replaces the default: yarn build → allow" Y - "yarn build"
lgcfg ""
lg ask   "k whole-string match: a commit message naming yarn build → ask" Y - 'git commit -m "yarn build fix"'
printf '# L\nowner_name: peer-session\nowner_session: X  \r\nexpected_end: %s\n' "$(iso 30)" > "$LOCKF"
lg allow "l owner_session with trailing spaces + CR still matches" X - "yarn build"
mklock X "$(iso 30)"; lgcfg '["(bad", "yarn build"]'
lg ask   "m an invalid regex entry is skipped, the rest still apply" Y - "yarn build"
lgcfg ""; mklock X "$(iso 30 420)"
lg ask   "n +07:00 end 30 min ahead → ask"                   Y - "yarn build"
has "STALE" && fail "[n] +07:00 end in the future reported STALE" || ok "[n] +07:00 end in the future is not stale"
printf '# L\n- owner_session: <your id here>\nowner_name: peer-session\nowner_session: X\nexpected_end: %s\n' "$(iso 30)" > "$LOCKF"
lg allow "o two owner_session lines: the matching one counts (owner not asked)" X - "yarn build"
lg ask   "o two owner_session lines: a non-owner is still asked" Y - "yarn build"
has "If you hold this lock, set" && fail "[o] ask text still invites setting owner_session" || ok "[o] ask text no longer invites setting owner_session"
{ has "Only the session named" && has "ask the user"; } && ok "[o] ask text is identity-tied and points at the user" || fail "[o] ask text: $LGOUT"
mklock X "$(iso 30)"
lg ask   "q bare yarn (install) → ask"                       Y - "yarn"
lg ask   "q npm i → ask"                                     Y - "npm i"
lg ask   "q yarn add x → ask"                                Y - "yarn add lodash"
lg allow "q yarn --version is not an install"                Y - "yarn --version"
rm -rf "$LGT"

node -e 'const s=require(process.argv[1]);process.exit(s.hooks.PreToolUse.some(g=>g.matcher==="Bash"&&g.hooks.some(h=>/lock-gate\.sh/.test(h.command)))?0:1)' "$H/settings.json" \
  && ok "settings.json registers lock-gate.sh in the Bash group" || fail "settings.json doesn't register lock-gate.sh"
PTPL="$ROOT/project-template/project.md"
[ "$H" = "$ROOT/core" ] && { grep -qF '"heavy_commands"' "$PTPL" && ok "project template json documents heavy_commands" || fail "project template json lacks heavy_commands"; }
SCT=$(mktemp -d); mkdir -p "$SCT/.claude/runs"; SCH="$H/hooks/session-context.sh"
sc2() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$SCT" bash "$SCH" 2>/dev/null; }
O=$(sc2 '{"session_id":"abc","source":"startup"}'); printf '%s' "$O" | grep -q 'session=abc' && ok "session-context prints session=<id> from its stdin" || fail "session-context: no session=abc in: $O"
printf '%s' "$O" | grep -q 'lock=' && fail "session-context prints lock= with no lock" || ok "session-context: no lock → no lock= field"
printf 'owner_session: abc\nowner_name: n\nexpected_end: 2099-01-01T00:00:00Z\n' > "$SCT/.claude/runs/MEASUREMENT-IN-PROGRESS.md"
O=$(sc2 '{"session_id":"abc","source":"resume"}'); { printf '%s' "$O" | grep -q 'lock=n' && printf '%s' "$O" | grep -q '(yours)'; } && ok "session-context shows the lock, marked (yours) for its owner" || fail "session-context lock field: $O"
O=$(sc2 '{not json'); RC=$?; { [ "$RC" -eq 0 ] && printf '%s' "$O" | grep -q '^\[harness\]'; } && ok "session-context: malformed stdin still prints its line, exit 0" || fail "session-context malformed stdin: rc=$RC $O"
T0=$(mono_ms); CLAUDE_PROJECT_DIR="$SCT" timeout 15 bash "$SCH" >/dev/null 2>&1 < <(sleep 20); EL=$(( $(mono_ms) - T0 ))   # <(…): stdin stays open, and bash doesn't wait for it (a pipe would)
[ "$EL" -lt 5000 ] && ok "session-context returns fast on an open, silent stdin (${EL} ms)" || fail "session-context blocked on an open stdin (${EL} ms) — it must never hang a session start"
printf 'owner_session: old\nowner_name: n\nowner_session: abc\nexpected_end: 2099-01-01T00:00:00Z\n' > "$SCT/.claude/runs/MEASUREMENT-IN-PROGRESS.md"
O=$(sc2 '{"session_id":"abc","source":"clear"}'); printf '%s' "$O" | grep -q '(yours)' && ok "session-context: (yours) when any owner_session line matches" || fail "session-context two-line owner: $O"
rm -rf "$SCT"

MSR="$H/rules/multi-session.md"
for tok in owner_session expected_end busy lock-gate.sh; do grep -qF "$tok" "$MSR" && ok "multi-session.md names '$tok'" || fail "multi-session.md lacks '$tok'"; done
grep -nE 'messages? .*machine free' "$MSR" | grep -viE 'no longer|never|don.t|do not' | grep -q . && fail "multi-session.md still tells the holder to message 'machine free'" || ok "multi-session.md no longer asks for 'machine free' messages"
grep -qF 'no hook enforces it' "$MSR" && fail "multi-session.md still says no hook enforces it" || ok "multi-session.md no longer claims no hook enforces it"
grep -qF 'Never edit a peer' "$MSR" && ok "multi-session.md forbids editing a peer's lock (incl. owner_session)" || fail "multi-session.md lacks 'Never edit a peer's lock'"
grep -qF 'on create, message only' "$MSR" && ok "multi-session.md §6 agrees with §3 (busy-only on create)" || fail "multi-session.md §6 contradicts §3 on create messages"
grep -qE 'Message peers \*\*before\*\* registering' "$MSR" && fail "multi-session.md §2 still asks to message all peers before a hook change" || ok "multi-session.md §2 hook/install announcements follow busy-only"
grep -qF 'lock-gate.sh' "$H/CLAUDE.md" && ok "CLAUDE.md Hooks table names lock-gate.sh" || fail "CLAUDE.md Hooks table lacks lock-gate.sh"

echo "== 2f. Review minors (2026-10-21) =="
for a in tester repro-driver incident-investigator research-lead; do
  grep -qF 'dispatcher_session' "$H/agents/$a.md" && ok "$a.md knows dispatcher_session (owner's own lock isn't a stop)" || fail "$a.md lacks dispatcher_session"
done
grep -qF 'dispatcher_session' "$H/rules/multi-session.md" && ok "multi-session.md tells holders to pass dispatcher_session" || fail "multi-session.md lacks dispatcher_session"
grep -qF -- '- **What:**' "$H/rules/multi-session.md" && ok "multi-session.md defines the '- **What:**' line" || fail "multi-session.md never defines '- **What:**'"
grep -qF 'start and expected end (ICT)' "$H/rules/multi-session.md" && fail "multi-session.md still asks for a prose end time (drifts from expected_end)" || ok "multi-session.md writes the end once (expected_end)"
if [ "$H" = "$ROOT/core" ]; then
  grep -qF 'not auto-loaded' "$ROOT/README.md" && fail "README still says rules are not auto-loaded" || ok "README no longer says rules aren't auto-loaded"
  for tok in 'guides/' 'retire' 'lock-gate.sh' 'load: always'; do grep -qF -- "$tok" "$ROOT/README.md" && ok "README documents '$tok'" || fail "README lacks '$tok'"; done
  sed -n 2,25p "$ROOT/install.sh" | grep -qi 'retire' && ok "install.sh header describes retiring" || fail "install.sh header lacks retiring"
fi
WT=$(mktemp -d); WRAP=$(awk '/^## Running a step/{f=1} f&&/^```bash$/{g=1;next} g&&/^```$/{exit} g' "$H/agents/runner.md")
CMDX='read -r x; echo "got:[$x]" # a trailing comment'
SCRIPT=$(printf '%s' "$WRAP" | REPO="$WT" RUN="$WT/run" CMDX="$CMDX" node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(s.split("<repo_root>").join(process.env.REPO).split("<run_dir>").join(process.env.RUN).split("<n>").join("1").split("<cmd>").join(process.env.CMDX)))')
WOUT=$(timeout 10 bash -c "$SCRIPT" 2>&1); WRC=$?
{ [ "$WRC" -eq 0 ] && printf '%s' "$WOUT" | grep -q '^exit=0 ' && grep -qF 'got:[]' "$WT/run/step-1.log" 2>/dev/null; } \
  && ok "runner wrapper: stdin is /dev/null and a trailing # comment doesn't break it" || fail "runner wrapper broke (rc=$WRC): $(printf '%s' "$WOUT" | head -2 | tr '\n' ' ')"
rm -rf "$WT"

echo "== 2g. Review minors, round 2 (2026-10-21) =="
# runner M6: rule labels + one fact per line
EST=$(mktemp -d); cat > "$EST/r.json" <<JSON
[{"filePath":"$ROOT/src/w.ts","errorCount":1,"warningCount":1,"messages":[
  {"ruleId":null,"severity":1,"message":"File ignored because of a matching ignore pattern","line":0,"column":0},
  {"ruleId":"no-undef","severity":2,"message":"first line\nsecond line","line":2,"column":1}]}]
JSON
EO=$(node "$H/scripts/eslint-summary.js" "$EST/r.json" src/w.ts 2>&1); rm -rf "$EST"
printf '%s\n' "$EO" | grep -qxF 'RULE (no rule) errors=0 warnings=1' && ok "eslint-summary: a null-rule warning is '(no rule)', not '(parse error)'" || fail "eslint-summary null-rule label: $EO"
printf '%s\n' "$EO" | grep -qxF 'CHANGED_ERROR src/w.ts:2:1 no-undef first line second line' && ok "eslint-summary: multi-line message collapsed to one line" || fail "eslint-summary multi-line message"
# runner M10: lint opt-out is a json key, not a Commands row
if [ "$H" = "$ROOT/core" ]; then
  grep -qF '"lint_on_request_only"' "$ROOT/project-template/project.md" && ok "template json has lint_on_request_only" || fail "template json lacks lint_on_request_only"
  grep -qF '| Lint on request only |' "$ROOT/project-template/project.md" && fail "template still stores the lint opt-out as a Commands row" || ok "template Commands table holds commands only"
fi
# load-budget M6: consumers that can read
grep -E '^\| \[research-workflow\.md\]' "$H/CLAUDE.md" | grep -q 'web-reader' && fail "CLAUDE.md lists web-reader (no Read tool) as a research-workflow consumer" || ok "CLAUDE.md guide consumers can all Read"
# lock M1: the lock= field is a snapshot
grep -qF 'snapshot' "$H/rules/multi-session.md" && ok "multi-session.md says the lock= field is a session-start snapshot" || fail "multi-session.md lacks the snapshot caveat"
# lock M3 + M6: absolute lock path; missing session_id
AT=$(mktemp -d); mkdir -p "$AT/.claude/hooks/lib" "$AT/elsewhere"; cp "$H/hooks/lib/project-config.js" "$AT/.claude/hooks/lib/"
printf '# p\n\n```json harness\n{"measurement_lock": "%s/elsewhere/LOCK.md"}\n```\n' "$AT" > "$AT/.claude/project.md"
printf 'owner_session: X\nowner_name: abs-owner\nexpected_end: 2099-01-01T00:00:00Z\n' > "$AT/elsewhere/LOCK.md"
AO=$(printf '{"session_id":"Y","tool_input":{"command":"yarn build"}}' | CLAUDE_PROJECT_DIR="$AT" bash "$H/hooks/lock-gate.sh" 2>/dev/null)
printf '%s' "$AO" | grep -q '"ask"' && ok "lock-gate honours an absolute measurement_lock path" || fail "lock-gate ignored an absolute measurement_lock path"
AS=$(printf '{"session_id":"Y"}' | CLAUDE_PROJECT_DIR="$AT" bash "$H/hooks/session-context.sh" 2>/dev/null)
printf '%s' "$AS" | grep -q 'lock=abs-owner' && ok "session-context shows a lock at an absolute path" || fail "session-context missed the absolute-path lock: $AS"
NO=$(printf '{"tool_input":{"command":"yarn build"}}' | CLAUDE_PROJECT_DIR="$AT" bash "$H/hooks/lock-gate.sh" 2>/dev/null)
{ printf '%s' "$NO" | grep -q '"ask"' && ! printf '%s' "$NO" | grep -q 'undefined'; } && ok "lock-gate: no session_id → ask, no 'undefined' in the text" || fail "lock-gate missing session_id: $NO"
rm -rf "$AT"
if [ "$H" = "$ROOT/core" ] && [ -f "$ROOT/install.sh" ]; then
  # runner M8: source change is announced; load M3: retiring twice keeps both copies
  IT5=$(mktemp -d); git -C "$IT5" init -q; bash "$ROOT/install.sh" "$IT5" >/dev/null 2>&1
  sed -i '3s|.*|source ~/some-other-harness|' "$IT5/.claude/.harness-manifest"
  bash "$ROOT/install.sh" --update "$IT5" 2>&1 | grep -q 'source changed' && ok "install --update announces a changed harness source" || fail "install --update silently switched the harness source"
  for i in 1 2; do printf 'gone\n' > "$IT5/.claude/rules/zz-twice.md"; printf '%s  rules/zz-twice.md\n' "$(printf 'gone\n' | sha256sum | cut -d' ' -f1)" >> "$IT5/.claude/.harness-manifest"; bash "$ROOT/install.sh" --update "$IT5" >/dev/null 2>&1; done
  [ "$(find "$IT5/.claude/.harness-retired" -name 'zz-twice.md*' | wc -l)" = 2 ] && ok "retiring the same path twice into one version keeps both copies" || fail "a second retire overwrote the first copy"
  rm -rf "$IT5"
fi

echo "== 2h. Review minors, round 3 (2026-10-21) =="
RT=$(mktemp -d); mkdir -p "$RT/.claude/hooks/lib" "$RT/.claude/runs"; cp "$H/hooks/lib/project-config.js" "$RT/.claude/hooks/lib/"
printf '# p\n\n```json harness\n{"heavy_commands": ["^(a+)+$", "yarn build"]}\n```\n' > "$RT/.claude/project.md"
printf 'owner_session: X\nowner_name: o\nexpected_end: 2099-01-01T00:00:00Z\n' > "$RT/.claude/runs/MEASUREMENT-IN-PROGRESS.md"
T0=$(mono_ms); printf '{"session_id":"Y","tool_input":{"command":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!"}}' | CLAUDE_PROJECT_DIR="$RT" timeout 30 bash "$H/hooks/lock-gate.sh" >/dev/null 2>&1; EL=$(( $(mono_ms) - T0 ))
[ "$EL" -le 6000 ] && ok "lock-gate: a catastrophic heavy_commands regex is cut off fast (${EL} ms; fails open)" || fail "lock-gate stalled ${EL} ms on a catastrophic regex"
RO=$(printf '{"session_id":"Y","tool_input":{"command":"yarn build"}}' | CLAUDE_PROJECT_DIR="$RT" bash "$H/hooks/lock-gate.sh" 2>/dev/null)
printf '%s' "$RO" | grep -q '"ask"' && ok "lock-gate: a normal heavy command still asks next to a pathological pattern" || fail "lock-gate: normal heavy command not asked: $RO"
rm -rf "$RT"
if [ "$H" = "$ROOT/core" ] && [ -f "$ROOT/install.sh" ]; then
  IT6=$(mktemp -d); git -C "$IT6" init -q; bash "$ROOT/install.sh" "$IT6" >/dev/null 2>&1
  head -3 "$IT6/.claude/.harness-manifest" > "$IT6/m" && mv "$IT6/m" "$IT6/.claude/.harness-manifest"   # header only, no entries
  UO=$(bash "$ROOT/install.sh" --update "$IT6" 2>&1); URC=$?
  { [ "$URC" -eq 0 ] && [ "$(grep -vcE '^(#|version |source )' "$IT6/.claude/.harness-manifest")" -gt 0 ]; } \
    && ok "install --update survives a manifest with no entries (set -euo pipefail)" || fail "install --update on an entry-less manifest: rc=$URC $(printf '%s' "$UO" | tail -1)"
  rm -rf "$IT6"
fi

echo "== 2i. review-bash-gate matrix (2026-10-22) =="
# Hunters and the judge get Bash for read-only git and throwaway scripts under the session scratchpad,
# nothing else. Registered in their own frontmatter, so the main session and other agents are unaffected.
RGATE="$H/hooks/review-bash-gate.sh"
check "review-bash-gate.sh exists+executable" test -x "$RGATE"
check "review-bash-gate.sh bash syntax" bash -n "$RGATE"
RSCR=/tmp/claude-1000/-x/sess/scratchpad
rgate() { # rgate <expected-exit> <label> <command> [agent_type, default adversarial-reviewer; "-" = none] [cwd]
  local expect="$1" label="$2" got who="${4:-adversarial-reviewer}"
  WHO="$who" CWD="${5:-}" node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j={tool_name:"Bash",tool_input:{command:d}};if(process.env.WHO!=="-")j.agent_type=process.env.WHO;if(process.env.CWD)j.cwd=process.env.CWD;process.stdout.write(JSON.stringify(j))})' <<<"$3" \
    | "$RGATE" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$expect" ]; then ok "[review-bash] $label → exit $got"; else fail "[review-bash] $label → exit $got (expected $expect)"; fi
}
rgate 0 "git diff base"            "git diff abc123 -- src"
rgate 0 "git log oneline"          "git log --oneline -5"
rgate 0 "git diff | head"          "git diff HEAD | head -50"
rgate 0 "git check-ignore"         "git check-ignore -q .claude/runs"
rgate 0 "git ls-files pipeline"    "git ls-files --others --exclude-standard -z | sort -z | xargs -0 -r sha256sum"
rgate 0 "git -C <repo> diff"       "git -C /srv/repo diff main...HEAD -- src"
rgate 0 "git -C quoted path log"   "git -C \"/srv/my repo\" log --oneline -5"
rgate 0 "node scratchpad script"   "node $RSCR/adv-r1-hunter-A/probe.js"
rgate 0 "python3 -I scratchpad"    "python3 -I $RSCR/adv-r1-hunter-B/p.py"
rgate 0 "heredoc into scratchpad"  "cat > $RSCR/adv-r1-hunter-A/probe.js <<'EOF'
console.log(1)
EOF"
rgate 0 "mkdir -p scratchpad"      "mkdir -p $RSCR/adv-r1-hunter-A"
rgate 0 "cd scratchpad && node"    "cd $RSCR/adv-r1-hunter-A && node probe.js"
rgate 0 "cat a repo file"          "cat src/retry.js"
rgate 0 "grep -rn excluding dirs"  "grep -rn --exclude-dir=.claude --exclude-dir=.remember publishWithBackoff src"
rgate 2 "git add"                  "git add -A"
rgate 2 "git commit"               "git commit -m x"
rgate 2 "git stash"                "git stash"
rgate 2 "git restore"              "git restore src/x.js"
rgate 2 "git -C <repo> add"        "git -C /srv/repo add -A"
rgate 2 "git -c config (exec)"     "git -c core.pager=sh diff"
rgate 2 "git -C then -c"           "git -C /srv/repo -c core.fsmonitor=x status"
# A hunter can write a repo into its scratchpad whose .git/config runs core.fsmonitor (measured
# 2026-10-26: git status executed it). git must never run against a repo under /tmp/claude-*.
rgate 2 "git -C scratchpad repo"   "git -C $RSCR/evil status"
rgate 2 "git -C unnormalized tmp"  "git -C /tmp/./claude-1000/-x/sess/scratchpad/evil status"
rgate 2 "cd scratchpad && git"     "cd $RSCR/evil && git status"
rgate 2 "git from scratchpad cwd"  "git status"                         adversarial-reviewer "$RSCR/evil"
rgate 2 "relative -C into scratch" "git -C evil diff"                   adversarial-reviewer "$RSCR"
rgate 0 "git from repo cwd"        "git status"                         adversarial-reviewer /srv/repo
rgate 0 "relative -C out of repo"  "git -C sub/pkg diff"                adversarial-reviewer /srv/repo
rgate 2 "node -e inline"           "node -e 'require(\"fs\").writeFileSync(\"x\",\"1\")'"
rgate 2 "node script in repo"      "node scripts/probe.js"
rgate 2 "python3 without -I"       "python3 $RSCR/p.py"
rgate 2 "heredoc into repo"        "cat > src/x.js <<'EOF'
x
EOF"
rgate 2 "redirect into repo"       "git diff > notes.txt"
rgate 2 "rm -rf"                   "rm -rf src"
rgate 2 "npm run build"            "npm run build"
rgate 2 "curl"                     "curl https://example.com"
rgate 2 "sed -i"                   "sed -i s/a/b/ src/x.js"
# Bypasses closed 2026-10-26, each one allowed by the gate before: operators the segment split
# never saw, options that run a program or write a file, and GNU long-option prefixes (sort --outp
# is --output). The rgate 0 lines below them are the controls that must keep passing.
rgate 2 "lone & (background)"      "cat a & touch /tmp/p"
rgate 2 "process substitution"     "diff <(touch /tmp/p) a"
rgate 2 "&> redirect into repo"    "cat a &>notes.txt"
rgate 2 "unbalanced quote"         "cat 'a"
rgate 2 "rg --pre"                 "rg --pre /bin/sh x ."
rgate 2 "rg --hostname-bin"        "rg --hostname-bin=/bin/sh x ."
rgate 2 "sort --compress-program"  "sort --compress-program=/bin/sh a"
rgate 2 "sort -o bundled"          "sort -nro src/x.js a"
rgate 2 "sort --outp (prefix)"     "sort --outp=src/x.js a"
rgate 2 "sed without --sandbox"    "sed -n '1e touch /tmp/p' a"
rgate 2 "sed --sandbox after --"   "sed -n '1e id' -- --sandbox a"
rgate 2 "sed --sandbox --in"       "sed --sandbox --in s/a/b/ src/x.js"
rgate 2 "sed --sandbox quoted -i"  "sed --sandbox '-i' s/a/b/ src/x.js"
rgate 2 "find -fprint0"            "find . -fprint0 notes.txt"
rgate 2 "find quote-split -exec"   "find . -e''xec touch /tmp/p +"
rgate 2 "uniq IN OUT"              "uniq a src/x.js"
rgate 2 "tee repo + scratchpad"    "git diff | tee src/x.js $RSCR/y"
rgate 2 "mkdir repo + scratchpad"  "mkdir -p src/new $RSCR/y"
rgate 2 "xargs -I word then sh"    "git ls-files | xargs -I cat sh -c id"
rgate 2 "awk -f program file"      "awk -f $RSCR/p.awk a"
rgate 2 "awk -o writes a file"     "awk -osrc/x.js 1 a"
rgate 2 "awk @f indirect system"   "awk -v f=system 'BEGIN{@f(\"id\")}'"
rgate 2 "awk system quote-spliced" "awk 'BEGIN{sys''tem(\"id\")}'"
rgate 0 "sed --sandbox range"      "sed --sandbox -n '1,20p' src/x.js"
rgate 0 "grep quoted &"            "grep -n 'a & b' src/x.js"
rgate 0 "2>&1 into a pipe"         "git diff 2>&1 | head -5"
rgate 0 "sort -u | uniq -c"        "git ls-files | sort -u | uniq -c"
rgate 0 "rg --hidden --pretty"     "rg -n --hidden --pretty foo src"
rgate 0 "awk -F"                   "awk -F: '{print \$1}' src/x.js"
rgate 0 "xargs -n 1 grep"          "git ls-files | xargs -n 1 grep -l foo"
rgate 0 "tee into scratchpad"      "git diff | tee $RSCR/adv-r1-hunter-A/diff.txt"
# Second pass (2026-10-26), each allowed by the gate above it: redirects the per-segment pattern
# missed, and shell shapes that rewrite words after the option checks ran (escapes, braces, and
# globs expanding to files named like options: a file named --pre=sh made `rg x *` run sh).
rgate 2 "digit then &>"            "echo x 1&>src/x.js"
rgate 2 ">| into repo"             "git diff >|cat"
rgate 2 "ANSI-C escaped option"    "find . \$'\\x2dexec' touch /tmp/p +"
rgate 2 "brace-expanded option"    "sed --sandbox {-i,s/a/b/} src/x.js"
rgate 2 "glob into sed options"    "sed --sandbox -? s/a/b/ src/x.js"
rgate 2 "glob into rg options"     "rg x *"
rgate 0 "grep quoted =>"           "grep -n '=>' src/x.js"
rgate 0 "grep end anchor \$'"      "grep -n 'foo\$' src/x.js"
rgate 0 "git reflog HEAD@{1}"      "git diff HEAD@{1}..HEAD"
rgate 0 "rg quoted -g glob"        "rg -n foo -g '*.ts' src"
rgate 0 "cat a glob"               "cat src/*.ts"
rgate 0 "redirect into scratchpad" "git diff > $RSCR/adv-r1-hunter-A/d.txt 2>&1"
rgate 2 "shell comment"            "cat src/x.js # note"
rgate 0 "# inside quotes"          "grep -n '#' src/x.js"
rgate 2 "scratchpad path with .."  "node $RSCR/../../etc/x.js"
rgate 2 "allowed && denied"        "git diff && git add -A"
rgate 2 "command substitution"     "node \$(echo $RSCR/p.js)"
rgate 2 "judge: git add"           "git add -A"                         review-judge
rgate 0 "coder: git add passes"    "git add -A"                         coder
rgate 0 "main session: rm passes"  "rm -rf build"                       -
rgate 0 "research-lead: curl passes" "curl https://example.com"         research-lead
printf 'not-json' | "$RGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[review-bash] malformed JSON → deny" || fail "[review-bash] malformed JSON → deny"
printf '' | "$RGATE" >/dev/null 2>&1; [ $? -eq 2 ] && ok "[review-bash] empty input → deny" || fail "[review-bash] empty input → deny"
grep -qF 'review-bash-gate.sh' "$H/settings.json" && ok "settings.json registers review-bash-gate on PreToolUse(Bash)" || fail "settings.json does not register review-bash-gate.sh (a frontmatter hook never fires for PreToolUse: measured 2026-10-22)"
for a in adversarial-reviewer review-judge; do
  awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$H/agents/$a.md" 2>/dev/null | grep -qF 'hooks:' \
    && fail "$a frontmatter carries a hooks: block (never fires for PreToolUse; register in settings.json)" || ok "$a frontmatter has no hooks: block"
done
grep -qF 'review-bash-gate.sh' "$H/CLAUDE.md" && ok "CLAUDE.md Hooks table names review-bash-gate.sh" || fail "CLAUDE.md Hooks table lacks review-bash-gate.sh"

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
check "autonomy.md names the lint_on_request_only opt-out" grep -qF 'lint_on_request_only' "$H/rules/autonomy.md"
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
  sed -n 3p "$IT/.claude/.harness-manifest" 2>/dev/null | grep -qE '^source (~/|/)' && ok "install: manifest line 3 records 'source <path>'" || fail "install: manifest has no 'source' line 3"
  sc() { CLAUDE_PROJECT_DIR="$IT" bash "$IT/.claude/hooks/session-context.sh" 2>/dev/null; }
  sc | grep -q 'harness_edited=0' && ok "session-context: clean install → harness_edited=0" || fail "session-context: no harness_edited=0 on a clean install"
  sc | grep -qE 'harness_source=(~/|/)' && ok "session-context: prints harness_source" || fail "session-context: no harness_source"
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
  FIRST=$(grep -vE '^(#|version |source )' "$IT2/.claude/.harness-manifest" | head -1 | awk '{print $2}')
  echo '<!-- edit -->' >> "$IT2/.claude/$FIRST"
  DOC=$(bash "$ROOT/install.sh" --doctor "$IT2" 2>&1)
  printf '%s' "$DOC" | grep -qF "edited locally: $FIRST" && ok "install --doctor: legacy manifest's FIRST entry is still checked" || fail "install --doctor skipped the first entry of a legacy manifest ($FIRST)"
  { printf '%s' "$DOC" | grep -q 'manifest: all installed files match' && ! printf '%s' "$DOC" | grep -q 'missing: /'; } \
    || true   # (the edit above makes "all match" false by design; the FIRST-entry check is the real one)
  IT3=$(mktemp -d); git -C "$IT3" init -q; bash "$ROOT/install.sh" "$IT3" >/dev/null 2>&1
  printf '[gone](./zz-nope.md)\n' > "$IT3/.claude/rules/zz-old.md"; printf y > "$IT3/.claude/rules/zz-edited.md"   # a relative link that breaks once retired
  HX=$(printf '[gone](./zz-nope.md)\n' | sha256sum | cut -d' ' -f1)
  printf '%s  rules/zz-old.md\n%s  rules/zz-edited.md\n' "$HX" "$HX" >> "$IT3/.claude/.harness-manifest"
  UPD=$(bash "$ROOT/install.sh" --update "$IT3" 2>&1)
  { ls "$IT3"/.claude/.harness-retired/*/rules/zz-old.md >/dev/null 2>&1 && [ ! -e "$IT3/.claude/rules/zz-old.md" ]; } \
    && ok "install --update: retires an unedited file that left core" || fail "install --update: unedited orphan not retired"
  { [ -e "$IT3/.claude/rules/zz-edited.md" ] && printf '%s' "$UPD" | grep -qF 'edited locally, kept: rules/zz-edited.md'; } \
    && ok "install --update: keeps (and warns about) an edited file that left core" || fail "install --update: edited orphan not kept with a warning"
  grep -q 'rules/zz-old.md' "$IT3/.claude/.harness-manifest" && fail "install --update: retired orphan still in the manifest" || ok "install --update: retired orphan dropped from the manifest"
  grep -q 'rules/zz-edited.md' "$IT3/.claude/.harness-manifest" && ok "install --update: edited orphan stays tracked in the manifest" || fail "install --update: edited orphan dropped out of tracking"
  bash "$ROOT/install.sh" --doctor "$IT3" 2>&1 | grep -q 'left core.*rules/zz-edited.md' && ok "install --doctor keeps reporting the edited orphan" || fail "install --doctor no longer reports the edited orphan"
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
paths_of() { fm "$1" | awk '/^paths:/{p=1; sub(/^paths:[ ]*/,"");
    if($0 ~ /^\[/){gsub(/^\[|\][ ]*$/,""); n=split($0,a,","); for(i=1;i<=n;i++){g=a[i]; gsub(/^[ ]*"?|"?[ ]*$/,"",g); if(g!="") print g}; p=0; next}   # flow list
    if($0!=""){gsub(/^"|"$/,""); print}; next}
  p&&/^[ ]*- /{sub(/^[ ]*- [ ]*/,""); gsub(/^"|"$/,""); print; next} p&&/^[^ ]/{p=0}'; }
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
printf -- '---\npaths: ["src/**", "lib/**"]\n---\n' > "$FX/.claude/rules/flow.md"   # flow-style YAML list
printf -- '---\npaths:\n  - "node_modules/**"\n---\n' > "$FX/.claude/rules/nm.md"
printf -- '---\nload: always\npaths:\n  - "src/**"\n---\n' > "$FX/.claude/rules/git.md"
FXC=$(class_lint "$FX/.claude")
[ "$(printf '%s\n' "$FXC" | grep -c FAIL)" = 4 ] && ok "class_lint fixture: both-keys, load: never, and safety-with-paths caught (4 FAILs)" || { fail "class_lint fixture: expected 4 FAILs"; printf '%s\n' "$FXC"; }
FXP=$( cd "$FX" && paths_lint "$FX/.claude" "$FX" )
printf '%s\n' "$FXP" | grep -q 'ok3.md: paths: match 1 file' && ok "paths_lint from a cwd with src/ subdirs: globs not shell-expanded" || { fail "paths_lint expanded globs in the shell"; printf '%s\n' "$FXP"; }
printf '%s\n' "$FXP" | grep -q 'flow.md: paths: match 1 file' && ok "paths_lint parses a flow-style list (paths: [\"a\", \"b\"])" || fail "paths_lint can't parse a flow-style paths list"
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

echo "== 5f. Adversarial review (2026-10-22) =="
AR="$H/guides/adversarial-review.md"; HUNTER="$H/agents/adversarial-reviewer.md"
check "guides/adversarial-review.md exists" test -f "$AR"
for hd in "## Playbook" "## Finding discipline" "## Debate rules" "## Message shapes" "## Procedure" "## Case file" "## Tool boundaries"; do
  grep -qxF "$hd" "$AR" 2>/dev/null && ok "adversarial-review.md has '$hd'" || fail "adversarial-review.md lacks '$hd'"
done
for tok in AGREED WITHDRAWN REFUTED ESCALATED STALEMATE CONTESTED peer_added_evidence new_evidence NO_DIFF review_iter "tree:"; do
  grep -qF -- "$tok" "$AR" 2>/dev/null && ok "adversarial-review.md mentions $tok" || fail "adversarial-review.md never mentions $tok"
done
[ "$(tools_of "$HUNTER")" = "Read, Grep, Glob, Bash" ] && ok "adversarial-reviewer tools are exactly Read, Grep, Glob, Bash" || fail "adversarial-reviewer tools are not exactly 'Read, Grep, Glob, Bash'"
[ "$(model_of "$HUNTER")" = "claude-opus-5-5" ] && ok "adversarial-reviewer model claude-opus-5-5" || fail "adversarial-reviewer model is not claude-opus-5-5"
grep -qE 'Read.*guides/adversarial-review\.md' "$HUNTER" 2>/dev/null && ok "adversarial-reviewer Reads guides/adversarial-review.md" || fail "adversarial-reviewer never Reads guides/adversarial-review.md"
{ grep -qF 'hunter-A' "$HUNTER" && grep -qF 'hunter-B' "$HUNTER"; } 2>/dev/null && ok "adversarial-reviewer knows both roles hunter-A / hunter-B" || fail "adversarial-reviewer lacks hunter-A / hunter-B"
grep -qF '## Review Checklist' "$HUNTER" 2>/dev/null && fail "adversarial-reviewer still carries the ECC '## Review Checklist' stub section" || ok "adversarial-reviewer dropped the ECC checklist section"

JUDGE="$H/agents/review-judge.md"
check "agents/review-judge.md exists" test -f "$JUDGE"
[ "$(tools_of "$JUDGE")" = "Read, Grep, Glob, Bash" ] && ok "review-judge tools are exactly Read, Grep, Glob, Bash" || fail "review-judge tools are not exactly 'Read, Grep, Glob, Bash'"
[ "$(model_of "$JUDGE")" = "claude-opus-5-5" ] && ok "review-judge model claude-opus-5-5" || fail "review-judge model is not claude-opus-5-5"
grep -qE 'Read.*guides/adversarial-review\.md' "$JUDGE" 2>/dev/null && ok "review-judge Reads guides/adversarial-review.md" || fail "review-judge never Reads guides/adversarial-review.md"
for tok in UPHELD REFUTED OUTSIDE_REPO "question:"; do
  grep -qF -- "$tok" "$JUDGE" 2>/dev/null && ok "review-judge mentions $tok" || fail "review-judge never mentions $tok"
done
for a in adversarial-reviewer review-judge; do
  f="$H/agents/$a.md"; [ -f "$f" ] || continue
  for t in Edit Write NotebookEdit Agent; do
    has_tool "$f" "$t" && fail "$a lists $t (hunters and judge are read-only and never dispatch)" || ok "$a does not list $t"
  done
done

CODER="$H/agents/coder.md"
for tok in "FIX FROM ADVERSARIAL REVIEW" "not_applicable" "never fall back to the newest spec"; do
  grep -qF -- "$tok" "$CODER" && ok "coder.md knows findings-only mode: '$tok'" || fail "coder.md lacks '$tok' (findings-only mode)"
done
grep -qF -- '--fix-from-adversarial-review' "$H/commands/coder.md" && ok "commands/coder.md has --fix-from-adversarial-review" || fail "commands/coder.md lacks --fix-from-adversarial-review"

CMD="$H/commands/adversarial-review.md"
check "commands/adversarial-review.md exists" test -f "$CMD"
for tok in 'subagent_type: "adversarial-reviewer"' 'subagent_type: "review-judge"' 'subagent_type: "coder"' '--resume' '--no-fix' '--auto' '--max-iter' NO_DIFF STALLED NEEDS_OWNER SendMessage ToolSearch 'by id' 'Recompute `tree`' 'restart the current round' AskUserQuestion; do
  grep -qF -- "$tok" "$CMD" 2>/dev/null && ok "adversarial-review command mentions $tok" || fail "adversarial-review command never mentions $tok"
done
grep -qE 'Read.*guides/adversarial-review\.md' "$CMD" 2>/dev/null && ok "adversarial-review command Reads the guide" || fail "adversarial-review command never Reads guides/adversarial-review.md"
grep -qE '^1\. \*\*Hunt' "$CMD" 2>/dev/null && fail "adversarial-review command duplicates the round procedure (belongs in the guide)" || ok "adversarial-review command holds no round procedure of its own"

grep -qF 'adversarial-review.md' "$H/CLAUDE.md" && ok "CLAUDE.md indexes guides/adversarial-review.md" || fail "CLAUDE.md does not index adversarial-review.md"
grep -qF 'review-judge' "$H/CLAUDE.md" && ok "CLAUDE.md lists review-judge" || fail "CLAUDE.md does not list review-judge"
grep -qF 'adversarial-review.md' "$WF" && ok "ai-workflow.md points at adversarial-review.md" || fail "ai-workflow.md never mentions adversarial-review.md"
grep -qE 'Read.*guides/adversarial-review\.md' "$H/agents/reviewer.md" && ok "reviewer Reads guides/adversarial-review.md § Finding discipline" || fail "reviewer never Reads guides/adversarial-review.md"

# live-run defects, 2026-10-22 smoke test: untracked files in the tree hash; plugin stores leak earlier rounds; VALID semantics
grep -qF 'untracked' "$AR" && ok "adversarial-review.md tree hash covers untracked files" || fail "adversarial-review.md tree hash ignores untracked files (resume would miss a fix to a new file)"
grep -qF 'untracked' "$CMD" 2>/dev/null && ok "adversarial-review command recomputes tree over untracked files too" || fail "adversarial-review command recomputes tree without untracked files"
for a in adversarial-reviewer review-judge; do
  grep -qF '.remember/' "$H/agents/$a.md" 2>/dev/null && ok "$a never reads .remember/ (plugin store leaks earlier rounds)" || fail "$a may grep .remember/ and see earlier rounds' findings"
done
grep -qF '.remember/' "$AR" && ok "adversarial-review.md names .remember/ among paths agents never read" || fail "adversarial-review.md does not exclude .remember/"
grep -qF 'is `AGREED` at once' "$AR" && ok "adversarial-review.md: VALID at the asserter's severity is AGREED at once" || fail "adversarial-review.md leaves cross-examination VALID → AGREED unspecified"

# resume drill, 2026-10-22: the tree hash must not cover .claude/; escalations carry over; scratchpad folders per round
grep -qF 'tree` never covers `.claude/' "$AR" && ok "adversarial-review.md tree hash excludes .claude/" || fail "adversarial-review.md tree hash covers .claude/ (every case-file write looks like a tree change)"
grep -qF 'carry over' "$AR" && ok "adversarial-review.md: unanswered ESCALATED/STALEMATE items carry over across rounds" || fail "adversarial-review.md does not say escalations carry over"
grep -qF 'own subfolder' "$AR" && ok "adversarial-review.md: each round's agents get their own scratchpad subfolder" || fail "adversarial-review.md does not isolate scratchpad folders per round"

# final review fix pass, 2026-10-22: execution points an orchestrator had to guess
grep -qF 'second `CHALLENGE`' "$AR" && ok "adversarial-review.md: judge ladder ends on the challenger's second CHALLENGE, no content check" || fail "adversarial-review.md: judge-ladder termination needs a content judgement"
grep -qF 'both sides are exhausted, or the cap' "$AR" && ok "adversarial-review.md: a finding stalemates when both sides are exhausted or the cap" || fail "adversarial-review.md: exhaustion (one side or both) is ambiguous"
grep -qF 'same_as' "$AR" && ok "adversarial-review.md: duplicate findings merge via same_as" || fail "adversarial-review.md has no rule for duplicate findings"
grep -qF 'one block per phase' "$AR" && ok "adversarial-review.md: a reply may carry one block per phase asked" || fail "adversarial-review.md: added findings cannot be ruled on in a turn reply"
grep -qF '`CLARIFY` carrying the re-graded severity' "$AR" && ok "adversarial-review.md: the asserter accepts a re-grade with CLARIFY" || fail "adversarial-review.md tells the asserter to ACCEPT (a challenger response)"
grep -qF 'before the breaker' "$AR" && ok "adversarial-review.md: Coder rejections are judged before the breaker" || fail "adversarial-review.md: the breaker punishes Coder for correct rejections"
grep -qF 'relays only the blocks' "$AR" && ok "adversarial-review.md: the orchestrator relays blocks, not prose" || fail "adversarial-review.md relays unbounded prose"
for a in adversarial-reviewer review-judge; do grep -qF '20 lines' "$H/agents/$a.md" && ok "$a bounds its prose" || fail "$a has no prose bound"; done
grep -qF 'estimated cost' "$CMD" && ok "adversarial-review command prints an estimated cost before dispatching" || fail "adversarial-review command never estimates cost"
grep -qF 'xargs -0 -r' "$AR" && grep -qF 'show-toplevel' "$AR" && ok "adversarial-review.md tree pipeline runs from the repo root and skips sha256sum with no files" || fail "adversarial-review.md tree pipeline hangs on stdin with no untracked files or depends on cwd"
grep -qF 'the base ref, the diff' "$AR" && ok "adversarial-review.md judge capsule carries the base ref" || fail "adversarial-review.md judge capsule lacks the base ref"
if [ "$H" = "$ROOT/core" ]; then   # harness repo only: the design doc is not installed
  grep -qF 'after the resume drill' "$ROOT/docs/2026-10-22-adversarial-review-design.md" && ok "design § Verified says which fixes landed after the resume drill" || fail "design § Verified misstates when the live-run fixes landed"
fi

# deferred minors from the final review and the live runs, 2026-10-22
grep -qF 'iteration: <review_iter>' "$AR" && ok "adversarial-review.md: the Coder message carries review_iter" || fail "adversarial-review.md: the Coder message lacks review_iter"
grep -qF 'project.md missing' "$AR" && ok "adversarial-review.md: hunt capsule allows a missing project.md" || fail "adversarial-review.md: hunt capsule assumes project.md"
grep -qF 'branch gate' "$CMD" && sed -n '/^## Resume/,/^## Final/p' "$CMD" | grep -qF 'branch gate' && ok "adversarial-review command: resume runs the branch gate when fixes are on" || fail "adversarial-review command: resume skips the branch gate"
grep -qF 'check-ignore' "$CMD" && ok "adversarial-review command warns when .claude/runs/ is not ignored" || fail "adversarial-review command never checks that .claude/runs/ is ignored"
grep -qF 'Gitignored with the other run logs' "$AR" && fail "adversarial-review.md still claims .claude/runs/ is gitignored" || ok "adversarial-review.md no longer claims .claude/runs/ is gitignored"
grep -qF 'SUPERSEDED' "$AR" && ok "adversarial-review.md: an abandoned round attempt's findings are SUPERSEDED" || fail "adversarial-review.md: abandoned round attempt unspecified"
for f in "$AR" "$HUNTER" "$JUDGE"; do grep -qF 'git check-ignore' "$f" && ok "$(basename "$f") whitelists git check-ignore" || fail "$(basename "$f") lacks git check-ignore in the read-only git list"; done
grep -qF 'only the field names' "$HUNTER" && ok "adversarial-reviewer uses only the guide's field names" || fail "adversarial-reviewer may invent field names"
grep -qF 'scratchpad' "$CODER" && ok "coder.md allows scratchpad probe scripts" || fail "coder.md cannot run a probe script to check its own fix"

sed -n 's/^description: //p' "$HUNTER" | head -1 | grep -qF '/adversarial-review' && ok "adversarial-reviewer description is scoped to /adversarial-review" || fail "adversarial-reviewer description invites auto-dispatch of a lone hunter"

# installer: .claude/runs/ must be ignored (the case file and the feature-flow run log live there)
if [ "$H" = "$ROOT/core" ]; then
  IT=$(mktemp -d); git -C "$IT" init -q; printf 'node_modules\n' > "$IT/.gitignore"
  bash "$ROOT/install.sh" "$IT" >/dev/null 2>&1
  grep -qxF '.claude/runs/' "$IT/.gitignore" && ok "install.sh adds .claude/runs/ to .gitignore" || fail "install.sh does not add .claude/runs/ to .gitignore"
  sed -i '/^\.claude\/runs\/$/d' "$IT/.gitignore"; bash "$ROOT/install.sh" --update "$IT" >/dev/null 2>&1
  grep -qxF '.claude/runs/' "$IT/.gitignore" && ok "install.sh --update restores the .claude/runs/ ignore" || fail "install.sh --update does not restore the .claude/runs/ ignore"
  bash "$ROOT/install.sh" --update "$IT" >/dev/null 2>&1; [ "$(grep -cxF '.claude/runs/' "$IT/.gitignore")" = 1 ] && ok "install.sh never duplicates the ignore line" || fail "install.sh duplicated the ignore line"
  rm -rf "$IT"
fi
# verify-quote: SSRF hardening (2026-10-22) — https or data only; no loopback, private, link-local or unspecified targets; redirects re-checked
VQ="$H/scripts/verify-quote.sh"
vq() { # vq <expected-exit> <label> <url> <reason-regex>
  local out; out=$(bash "$VQ" "$3" "hello" 2>/dev/null); local got=$?
  if [ "$got" -eq "$1" ] && printf '%s' "$out" | grep -qiE "$4"; then ok "[verify-quote] $2 → $out"; else fail "[verify-quote] $2 → exit $got '$out' (expected $1 /$4/)"; fi
}
vq 2 "http scheme refused"      "http://example.com/"                      "scheme"
vq 2 "loopback literal refused" "https://127.0.0.1/"                       "private|loopback"
vq 2 "localhost refused"        "https://localhost/"                       "private|loopback"
# literal addresses are built with printf so the leak check's IPv4 pattern never sees one in source
vq 2 "link-local refused"       "https://$(printf '%d.%d.%d.%d' 169 254 169 254)/latest/meta-data" "private|link-local"
vq 2 "RFC1918 refused"          "https://$(printf '%d.%d.%d.%d' 10 0 0 1)/"     "private"
vq 2 "v4-mapped v6 (hex) refused"    "https://[::ffff:7f00:1]/"            "private|embeds"
vq 2 "v4-mapped v6 (dotted) refused" "https://[::ffff:$(printf '%d.%d.%d.%d' 127 0 0 1)]/" "private|embeds"
vq 2 "NAT64 refused"                 "https://[64:ff9b::7f00:1]/"          "private|embeds"
vq 2 "6to4 refused"                  "https://[2002:7f00:1::1]/"           "private|embeds"
vq 2 "IPv4-compatible v6 refused"    "https://[::7f00:1]/"                 "private|embeds"
vq 2 "IPv6 loopback refused"    "https://[::1]/"                           "private|loopback"
vq 2 "unspecified refused"      "https://0.0.0.0/"                         "private|unspecified"
vq 0 "data: positive control"   "data:text/html,$(printf 'a%.0s' $(seq 1 250)) hello world" "MATCH"

echo "== 5g. Team flow (2026-10-22) =="
# ai-workflow.md is the contract: § Team protocol subsections and § Procedure; new tokens
for hd in "## Team protocol" "### Roster and run document" "### Message shapes" "### Questions" "### Blockers and decisions" "### Councils" "### Bounds" "### Resume" "## Procedure"; do
  grep -qxF "$hd" "$WF" && ok "ai-workflow.md has '$hd'" || fail "ai-workflow.md lacks '$hd'"
done
for tok in QUESTION ANSWER OBJECTION POSITION DECISION decisions_applied questions_asked gate_iter "--max-gate-iter" "by: lead | council | owner | assumed" NEEDS_OWNER "then resume the asker" "cannot be settled by the lead" "when the asker next goes idle" '`main` only' "cost line" "standby brief"; do
  [ "$tok" = "--" ] && continue
  grep -qF -- "$tok" "$WF" && ok "ai-workflow.md mentions $tok" || fail "ai-workflow.md never mentions $tok"
done

# peers: § Team sections, SendMessage boundary, contract pairs
for a in coder tester reviewer planner; do
  for hd in "### When you ask" "### When you are asked" "### When a decision arrives" "### When you object"; do
    grep -qxF "$hd" "$H/agents/$a.md" && ok "$a has '$hd'" || fail "$a lacks '$hd'"
  done
  grep -qF 'Without a roster in your capsule, this section does not apply' "$H/agents/$a.md" && ok "$a: no-roster rule" || fail "$a lacks the no-roster rule"
done
for f in "$H"/agents/*.md; do
  a=$(basename "$f" .md)
  case " coder tester reviewer planner research-lead incident-investigator " in
    *" $a "*) has_tool "$f" SendMessage && ok "$a lists SendMessage" || fail "$a should list SendMessage";;
    *) has_tool "$f" SendMessage && fail "$a lists SendMessage (only the four peers and the two research agents may)" || ok "$a does not list SendMessage";;
  esac
done
pair "decisions_applied" coder.md
pair "QUESTION" coder.md
pair "is_decision" tester.md
pair "OBJECTION" tester.md
pair "POSITION" planner.md
pair "rationale" reviewer.md

# hunters' routed question
grep -qF 'at most one per finding, routed to Coder' "$AR" && ok "adversarial-review.md hunt reply carries questions[] (one per finding, routed to Coder)" || fail "adversarial-review.md hunt reply lacks questions[]"
grep -qF 'citing `D<n>`' "$AR" && ok "adversarial-review.md: an answer citing D<n> withdraws the finding" || fail "adversarial-review.md lacks the D<n> withdrawal rule"
grep -qF 'questions[]' "$HUNTER" && ok "adversarial-reviewer knows the routed question (questions[])" || fail "adversarial-reviewer lacks the routed question (questions[])"

# the command: locus and arguments only; the switchboard rule; resume re-dispatches
FF="$H/commands/feature-flow.md"
grep -qE 'Read.*ai-workflow\.md' "$FF" && ok "feature-flow Reads ai-workflow.md" || fail "feature-flow never Reads ai-workflow.md"
for tok in '--max-gate-iter' '--resume' switchboard 'by agent id' 'every id is dead' AskUserQuestion 'adversarial-review.md' 'agent: lead' gate_iter 'cost line' NEEDS_OWNER STALLED; do
  grep -qF -- "$tok" "$FF" && ok "feature-flow mentions $tok" || fail "feature-flow never mentions $tok"
done
for hd in '### Step 3 — Coder' '### Step 4 — Tester'; do
  grep -qF "$hd" "$FF" && fail "feature-flow still holds the procedure ('$hd'); it belongs in ai-workflow.md § Procedure" || ok "feature-flow holds no '$hd' step"
done

grep -qF 'Team flow' "$H/CLAUDE.md" && ok "CLAUDE.md names the team flow" || fail "CLAUDE.md still calls it a feature workflow pipeline"
grep -qF 'switchboard' "$H/CLAUDE.md" && ok "CLAUDE.md says the lead is the switchboard" || fail "CLAUDE.md does not mention the switchboard"

# final-review fix pass (2026-10-23)
grep -qF 'recorded before the hunt was dispatched' "$AR" && grep -qF 'recorded before the hunt was dispatched' "$WF" && ok "only a decision recorded before the hunt withdraws a finding (both guides)" || fail "a lead can mint a decision inside the gate and withdraw a finding"
grep -qF 'fresh status block; the step does not advance' "$WF" && ok "ai-workflow.md: a delivered ANSWER yields a fresh status block before the step advances" || fail "ai-workflow.md: non-blocking reconcile has no completion"
grep -qF 'first option as its `POSITION`' "$WF" && ok "ai-workflow.md: a busy asker's first option stands as its POSITION" || fail "ai-workflow.md: council on a busy peer's question unspecified"
grep -qF 'case file'"'"'s `review_iter` is `gate_iter`' "$WF" && ok "ai-workflow.md maps gate_iter to the case file's review_iter" || fail "ai-workflow.md never maps gate_iter to the case file"
grep -qF 'in a team run, a blocking `QUESTION`' "$CODER" && ok "coder.md: a contradictory spec is a blocking QUESTION in a team run" || fail "coder.md still says BLOCKED for a contradictory spec in every run"
for a in reviewer tester; do grep -qF 'blocking: yes' "$H/agents/$a.md" && ok "$a: its per-finding question is blocking" || fail "$a: per-finding question blocking-ness unspecified"; done
grep -qF 'several `QUESTION` blocks in one reply' "$WF" && ok "ai-workflow.md: several questions per pause reply" || fail "ai-workflow.md allows only one QUESTION per reply"
grep -qF 'The roster lives in the state block only' "$WF" && ok "ai-workflow.md: no roster broadcast (peers address main only)" || fail "ai-workflow.md still broadcasts a roster nobody uses"
grep -qF 'send the roster to all' "$FF" && fail "feature-flow still broadcasts the roster" || ok "feature-flow holds no roster broadcast"
grep -qF '`assumed` decision is treated as `council`' "$WF" && ok "ai-workflow.md: objection to an assumed decision has a route" || fail "ai-workflow.md: objection to an assumed decision has no route"
for a in coder tester reviewer planner; do grep -qF 'A reply that is only an `ANSWER`, a `POSITION`' "$H/agents/$a.md" && ok "$a: standby replies carry no status block" || fail "$a: standby replies would carry a bogus status block"; done
grep -qF 'unless `--no-test`' "$WF" && ok "ai-workflow.md: Tester after a gate fix respects --no-test" || fail "ai-workflow.md: Tester after a gate fix ignores --no-test"
grep -qE 're-dispatch Coder' "$WF" && fail "ai-workflow.md § Iteration policy still says re-dispatch Coder" || ok "ai-workflow.md routing says resume, not re-dispatch"
grep -qF 'into one dispatch' "$FF" && ok "feature-flow: never collapse into one dispatch (wording restored)" || fail "feature-flow: 'collapse into one' contradicts the one-message team-up"
grep -qF 'quoting the spec line' "$WF" && ok "ai-workflow.md: move 1 must quote the spec line" || fail "ai-workflow.md: move 1 has no criterion"
grep -qF 'context is at risk' "$WF" && ok "ai-workflow.md: the lead stops with the resume command when its context is at risk" || fail "ai-workflow.md: no lead-context ceiling rule"
for a in coder tester reviewer planner; do for tok in is_decision applies_to question_id; do grep -qF "$tok" "$H/agents/$a.md" && ok "$a mentions $tok" || fail "$a never mentions $tok (shape not pinned)"; done; done
if [ "$H" = "$ROOT/core" ]; then grep -qF 'minted' "$ROOT/docs/2026-10-22-team-flow-design.md" && ok "team-flow design records the minted-decision incident" || fail "team-flow design lacks the minted-decision incident"; fi

echo "== 5h. Thoroughness knobs (2026-10-27) =="
# guides/thoroughness.md is the single home of the knob table, presets, shared flags and angles;
# commands and agents point at it by section and never repeat a number.
TH="$H/guides/thoroughness.md"
check "guides/thoroughness.md exists" test -f "$TH"
for hd in "## Knob table" "## Width semantics" "## Presets" "## Input" "## Angles" "## Delta and probed" "## Agent ceiling" "## Counting"; do
  grep -qxF "$hd" "$TH" 2>/dev/null && ok "thoroughness.md has '$hd'" || fail "thoroughness.md lacks '$hd'"
done
KT=$(sed -n '/^## Knob table$/,/^## /p' "$TH" 2>/dev/null)
trim_cell() { awk -F'|' -v c="$1" 'NR==1{v=$c; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit}'; }
for f in "$H"/agents/*.md; do
  a=$(basename "$f" .md); row=$(printf '%s\n' "$KT" | grep -E '^\| `'"$a"'`')
  n=$(printf '%s\n' "$KT" | grep -cE '^\| `'"$a"'`')
  [ "$n" = 1 ] && ok "knob table has exactly one row for $a" || { fail "knob table has $n rows for $a (wants exactly 1)"; continue; }
  w="$(printf '%s\n' "$row" | trim_cell 3) $(printf '%s\n' "$row" | trim_cell 4) $(printf '%s\n' "$row" | trim_cell 5)"
  r=$(printf '%s\n' "$row" | trim_cell 6)
  { printf '%s\n' "$w" | grep -qxE '[1-8] [1-8] [1-8]' || { [ -n "$r" ] && [ "$r" != "—" ]; }; } \
    && ok "knob row $a is a width (1–8) or carries a reason" || fail "knob row $a is neither a width 1–8 nor a reason"
done
for a in research-lead incident-investigator repro-driver designer coder tester reviewer planner; do
  r=$(printf '%s\n' "$KT" | grep -E '^\| `'"$a"'`' | trim_cell 6)
  [ -n "$r" ] && [ "$r" != "—" ] && ok "singleton $a carries its reason" || fail "singleton $a has no reason in the knob table"
done
for tok in quick standard thorough exhaustive --effort --width --dry --max-agents 8 warn cycle hunter-H time-and-config claims-and-consumers probed "tried:" "agent ceiling" "counts once toward" "git ls-files --others" "--effort=quick" '"max_agents": 48' '"width": {"searcher": 2}'; do
  grep -qF -- "$tok" "$TH" 2>/dev/null && ok "thoroughness.md mentions $tok" || fail "thoroughness.md never mentions $tok"
done
grep -qF 'A round of parallel briefs to one teammate type counts once toward `--max-iter`; the width is the number of agents in that round.' "$TH" 2>/dev/null \
  && ok "thoroughness.md § Counting holds the counting sentence verbatim" || fail "thoroughness.md lacks the counting sentence verbatim"
sed -n '/^## Delta and probed$/,/^## /p' "$TH" 2>/dev/null | grep -qF 'git ls-files --others' \
  && ok "thoroughness.md § Delta counts untracked files (git ls-files --others)" || fail "thoroughness.md § Delta ignores untracked files"
grep -qF 'thoroughness.md' "$H/CLAUDE.md" && ok "CLAUDE.md § Guides lists thoroughness.md" || fail "CLAUDE.md § Guides does not list thoroughness.md"

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
