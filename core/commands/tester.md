---
description: Run the Tester subagent to drive the Test Scenarios section of the latest spec in a real browser via Chrome DevTools MCP
argument-hint: [spec-path]
---

Dispatch the `tester` subagent (defined at `.claude/agents/tester.md`) via the
`Agent` tool with `subagent_type: "tester"` and pass `$ARGUMENTS` verbatim as
the input. If `$ARGUMENTS` is empty, instruct the subagent to use the newest
`*-spec.md` under `.claude/specs/` by filename date. Forward the subagent's full reply, including its trailing YAML status
block, back to me unchanged.
