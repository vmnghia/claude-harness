#!/usr/bin/env bash
# PreToolUse(mcp__sentry__execute_sentry_tool) hook — read-only gate for the
# Sentry MCP catalog gateway. The gateway takes the operation as an argument,
# so it reaches destructive writes (update_project, delete_alert_rule,
# create_dsn…) that no frontmatter tool allowlist can see. Decided by the owner
# 2026-10-14 for the incident-investigator agent; applies to every session.
# Exit 0 = allow. Exit 2 = deny; stderr is shown to the agent.

INPUT=$(cat)

# Catalog names whose readOnlyHint was true in search_sentry_tools on 2026-10-14.
# Add a name only after re-checking its annotation the same way.
ALLOW='get_issue_tag_values get_issue_breadcrumbs search_issue_events get_issue_details get_issue_activity get_issue_user_reports get_span_details find_teams find_dsns'

deny() {
  echo "sentry-read-gate: DENIED — $1 (policy: .claude/agents/incident-investigator.md; this is policy, not an error — do not retry)" >&2
  exit 2
}

NAME=$(printf '%s' "$INPUT" | node -e '
  var d = "";
  process.stdin.on("data", function (c) { d += c; });
  process.stdin.on("end", function () {
    try {
      var j = JSON.parse(d);
      process.stdout.write((j.tool_input && j.tool_input.name) || "");
    } catch (e) { /* emit nothing */ }
  });
' 2>/dev/null)

# Fail closed, unlike git-guard: if the operation can't be identified, it may
# be a destructive one, and Sentry is shared by the whole team.
if [ -z "$NAME" ]; then
  deny "could not read the catalog tool name (malformed input, missing name, or node unavailable)"
fi

for n in $ALLOW; do
  [ "$NAME" = "$n" ] && exit 0
done
deny "'$NAME' is not on the Sentry read allowlist"
