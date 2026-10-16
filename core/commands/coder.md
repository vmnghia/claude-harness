---
description: Run the Coder subagent to implement the latest spec, or to fix per Tester/Reviewer payload
argument-hint: [spec-path] [--fix-from-tester | --fix-from-reviewer]
---

Dispatch the `coder` subagent (defined at `.claude/agents/coder.md`) via the
`Agent` tool with `subagent_type: "coder"` and pass `$ARGUMENTS` verbatim as
the input. If `$ARGUMENTS` is empty, instruct the subagent to locate the newest
`*-spec.md` under `.claude/specs/` by filename date, read its sibling
`-plan.md`, and implement against them. Forward the subagent's full reply, including
its trailing YAML status block, back to me unchanged.
