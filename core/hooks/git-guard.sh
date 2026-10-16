
#!/usr/bin/env bash
# PreToolUse(Bash) hook — mechanical git guardrails per .claude/rules/git.md.
# Shared branches come from .claude/project.md (`shared_branches`, globs allowed), else the default list.
# Exit 0 = allow (default). Exit 2 = deny; stderr is shown to the agent.
# Fail-open by design: unparseable input or missing node → allow. The normal
# permission system still sits underneath this hook.

INPUT=$(cat)

COMMAND=$(printf '%s' "$INPUT" | node -e '
  var d = "";
  process.stdin.on("data", function (c) { d += c; });
  process.stdin.on("end", function () {
    try {
      var j = JSON.parse(d);
      process.stdout.write((j.tool_input && j.tool_input.command) || "");
    } catch (e) { /* fail-open: emit nothing */ }
  });
' 2>/dev/null)

[ -z "$COMMAND" ] && exit 0
case "$COMMAND" in *git*) ;; *) exit 0 ;; esac

# BRANCH is empty on detached HEAD: on-branch rules (1a, 3) then fail-open,
# but target-based rules (1b, 2, 4) still apply. Documented + covered by
# .claude/scripts/harness-check.sh.
BRANCH=$(git branch --show-current 2>/dev/null)
CFG="$(dirname "$0")/lib/project-config.js"
SHARED=$(node "$CFG" shared_branches --regex anchored 2>/dev/null)
SHARED_TOKEN=$(node "$CFG" shared_branches --regex token 2>/dev/null)
: "${SHARED:=^(main|master|develop|staging|stable|production|release/.+)$}"
: "${SHARED_TOKEN:=(main|master|develop|staging|stable|production|release/[^[:space:]]+)}"

deny() {
  echo "git-guard: DENIED — $1 (policy: .claude/rules/git.md; this is policy, not an error — do not retry)" >&2
  exit 2
}

IS_PUSH=false
IS_COMMIT=false
echo "$COMMAND" | grep -qE '(^|[;&|][[:space:]]*)git[[:space:]]+push' && IS_PUSH=true
echo "$COMMAND" | grep -qE '(^|[;&|][[:space:]]*)git[[:space:]]+commit' && IS_COMMIT=true

# 4. --no-verify on any git commit/push
if { $IS_PUSH || $IS_COMMIT; } && echo "$COMMAND" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  deny "--no-verify bypasses hooks"
fi

if $IS_PUSH; then
  # 1a. push while ON a shared branch
  if [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE "$SHARED"; then
    deny "push while on shared branch '$BRANCH'"
  fi
  # 1b. push TARGETING a shared branch (arg or refspec; loose match by design)
  if echo "$COMMAND" | grep -qE "(^|[[:space:]:])${SHARED_TOKEN}([[:space:]]|\$)"; then
    deny "push targets a shared branch"
  fi
  # 2. plain --force / -f without --force-with-lease
  if echo "$COMMAND" | grep -qE '(^|[[:space:]])(--force|-f)([[:space:]]|$)' \
     && ! echo "$COMMAND" | grep -q -- '--force-with-lease'; then
    deny "plain --force push — use --force-with-lease"
  fi
fi

# 3. commit while ON a shared branch
if $IS_COMMIT && [ -n "$BRANCH" ] && echo "$BRANCH" | grep -qE "$SHARED"; then
  deny "commit on shared branch '$BRANCH'"
fi

exit 0
