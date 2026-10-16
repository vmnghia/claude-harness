#!/usr/bin/env bash
# PreToolUse(createConfluenceContent|updateConfluenceContent) hook — drafts-only gate
# for research-lead. Registered in .claude/agents/research-lead.md's own frontmatter,
# so it runs only while that subagent runs; the main session and peers are unaffected.
# Decided 2026-10-15: the lead may create/update Confluence DRAFTS when the
# run's framing names the target; the owner reviews and publishes. Everything else denied.
# Exit 0 = allow. Exit 2 = deny; stderr is shown to the agent.

INPUT=$(cat)

deny() {
  echo "confluence-draft-gate: DENIED — $1. Confluence writes from research-lead are drafts only; the owner publishes (policy: .claude/agents/research-lead.md; this is policy, not an error — do not retry)" >&2
  exit 2
}

# Prints "allow" or a deny reason. Anything unreadable falls through to a deny below.
VERDICT=$(printf '%s' "$INPUT" | node -e '
  var d = "";
  process.stdin.on("data", function (c) { d += c; });
  process.stdin.on("end", function () {
    var j;
    try { j = JSON.parse(d); } catch (e) { return; }
    var tool = String(j.tool_name || "");
    var i = j.tool_input || {};
    var out;
    if (/__createConfluenceContent$/.test(tool)) {
      if (i.draft !== true) out = "create without draft: true";
      else if (i.contentType !== "page" && i.contentType !== "blogpost")
        out = "contentType \"" + i.contentType + "\" has no draft state (page or blogpost only)";
      else out = "allow";
    } else if (/__updateConfluenceContent$/.test(tool)) {
      if (i.draft !== true) out = "update of the published version (draft: true required)";
      else if (i.ownerId !== undefined) out = "ownership transfer";
      else out = "allow";
    } else {
      out = "tool \"" + tool + "\" is not a Confluence draft write";
    }
    process.stdout.write(out);
  });
' 2>/dev/null)

# Fail closed: if the call can't be read, it may be a publish.
[ -z "$VERDICT" ] && deny "could not read the tool call (malformed input or node unavailable)"
[ "$VERDICT" = "allow" ] && exit 0
deny "$VERDICT"
