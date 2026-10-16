---
description: Run the Reviewer subagent to critique the current diff against the spec and project rules
argument-hint: [spec-path] [--base=<ref>]
---

Dispatch the `reviewer` subagent (defined at `.claude/agents/reviewer.md`)
via the `Agent` tool with `subagent_type: "reviewer"` and pass `$ARGUMENTS`
verbatim as the input. If `$ARGUMENTS` is empty, instruct the subagent to
use the newest `*-spec.md` under `.claude/specs/` (by filename date) plus
its sibling `-plan.md`, and to auto-resolve the diff base per its procedure
(merge-base against origin/stable, falling back to master). Forward the
subagent's full reply, including its trailing YAML status block, back to me
unchanged.
