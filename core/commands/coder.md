---
description: Run the Coder subagent to implement the latest spec, or to fix per Tester/Reviewer payload, or per an adversarial review's case file
argument-hint: [spec-path] [--fix-from-tester | --fix-from-reviewer | --fix-from-adversarial-review [case-file]]
---

Dispatch the `coder` subagent (defined at `.claude/agents/coder.md`) via the
`Agent` tool with `subagent_type: "coder"` and pass `$ARGUMENTS` verbatim as
the input. If `$ARGUMENTS` is empty, instruct the subagent to locate the newest
`*-spec.md` under `.claude/specs/` by filename date, read its sibling
`-plan.md`, and implement against them. Forward the subagent's full reply, including
its trailing YAML status block, back to me unchanged.

With `--fix-from-adversarial-review [case-file]`: read the state block of the given case file
(else the newest `.claude/runs/*-adversarial-*.md`), take every finding whose `state` is
`AGREED` and whose severity is `blocker` or `major`, and dispatch Coder in findings-only mode
with the message `FIX FROM ADVERSARIAL REVIEW`, the case-file path and those findings
(`.claude/guides/adversarial-review.md` § Message shapes). No spec is passed.
