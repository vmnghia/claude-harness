---
description: Bug-fix flow as a team — diagnosis (a settled /research investigation, picked up or run), the owner's decisions, a bug spec, a spec review and a red run on the unfixed tree, then the /feature-flow team fixes it and proves it green on the same steps; ends ready for human apply
argument-hint: <FRONT-XXXX> [--run-research] [--fix-ticket=FRONT-YYYY] [--spec=<spec path>] [--auto] [--no-test] [--max-iter=N] [--max-gate-iter=N] [--effort=quick|standard|thorough|exhaustive] [--width=<agent>:<n>,…] [--dry=K] [--max-agents=N] [--resume [<run-document>]]
---

Contract: Read [`.claude/guides/ai-workflow.md`](../guides/ai-workflow.md) first and execute its
**§ Bug mode** exactly, then its **§ Procedure** from step 3, under its § Team protocol. This
file selects where each phase runs and how arguments and the owner's answers get in; the steps,
the blocks, the bounds, the decision rules and the exits live in the guide. The diagnosis is
[`.claude/commands/research.md`](./research.md) (`commands/research.md`), executed in this
session. The gate is [`.claude/guides/adversarial-review.md`](../guides/adversarial-review.md)
§ Procedure, run with this session as its orchestrator.

You are the **lead** and the **switchboard**, exactly as in
[`feature-flow.md`](./feature-flow.md): you decide what the spec settles, convene the team for
what it does not, bring the rest to the owner, and forward every peer block verbatim to the
peer named in its `to:`, **by agent id** from the roster. You judge nothing you forward. You
write the run document; nobody else does.

## Input

Raw arguments: `$ARGUMENTS`. Parse out:

- A positional **bug ticket** matching `^FRONT-\d+$`: the ticket the investigation is filed
  under. Required unless `--spec` or `--resume`. Free text is refused: picking up an
  investigation keys on the ticket.
- `--run-research` → run a research run even when a settled investigation exists (a delta run).
  Without it, research runs only when no settled investigation is found.
- `--fix-ticket=FRONT-YYYY` → the ticket the spec is written for. Default: the bug ticket.
- `--spec=<spec path>` → the spec and its sibling `-plan.md` already exist; enter at Team up
  (guide § Bug mode B4, which checks the pair and its repro scenario).
- `--auto` → as in `/feature-flow` for planning and councils. It never assumes the owner's
  decisions about a bug: the guide ends `NEEDS_OWNER` or `NOT_REPRODUCED` where the owner would
  have been asked. Research's Framing still asks.
- `--no-test` → no Tester, so no red and no green run. Typing it is the owner's waiver of the
  repro: record it as a decision when the run document is created (guide § Bug mode,
  `--no-test`), and warn.
- `--max-iter=N`, `--max-gate-iter=N` → as in `/feature-flow`: positive integers, else warn and
  use the default. `--max-iter` is the fix phase's cap only.
- Thoroughness flags (`--effort`, `--width`, `--dry`, `--max-agents`) → parse and validate per
  [`guides/thoroughness.md`](../guides/thoroughness.md) § Input, resolve the knobs once and
  write them into the run document's `knobs:`. Two exceptions (guide § Bug mode, Knobs): a
  research run started here gets research's own `max_iter`, and `--max-agents` is
  one ceiling per phase, so a run can dispatch up to twice the number typed. Say so once when
  the flag is given.
- `--resume [<run-document>]` → go to **Resume**.

Missing bug ticket without `--spec` or `--resume` → stop with the final block,
`status: NEEDS_CLARIFICATION`,
`summary: "Missing bug ticket. Usage: /fix-bug <FRONT-XXXX> [--run-research] [--fix-ticket=FRONT-YYYY] [--spec=<spec path>] [...]"`.

## Where each phase runs

- **Run document:** created and written by you, first, with `mode: bug` and `step: diagnosis`
  (with `--spec`, as the guide's § Bug mode B4 says); before creating it, `git check-ignore -q .claude/runs/`
  (trailing slash) and warn once when it fails.
- **Diagnosis:** the pick-up scan (`kind: incident`, settled, for the bug ticket) in this
  session. A research run: execute `commands/research.md` § New run **inline in this session**
  (its Framing, its lead dispatch, its critique), never as one subagent.
- **Decisions:** `AskUserQuestion`, one batch, the research's recommendation first.
- **Planning:** inline in this session without `--auto`; with `--auto`, `Agent` with
  `subagent_type: "planner"`. Either way the capsule carries the guide's `diagnosis:` item.
- **Team up:** as `/feature-flow`, in **one message**, with Coder on standby too. Load
  `SendMessage` once with ToolSearch `select:SendMessage`.
- **Spec review and red:** two `SendMessage` resumes in one message, Reviewer and Tester, with
  the briefs the guide names. Do not resume Coder until both are back and the spec is final.
- **Branch gate:** `git rev-parse --abbrev-ref HEAD` in this session, after the red run and
  before Coder's first resume; on a shared branch ask the owner to branch or proceed. Never
  create the branch yourself. Always, even with `--auto`.
- **Every later step** (coding, testing, reviewing, the switchboard, decisions with a
  **cost line** before every council round, owner pauses, the gate with its hunters at
  `knobs.width.adversarial-reviewer` and its dry-check rounds, the report) runs where
  [`feature-flow.md`](./feature-flow.md) § Where each phase runs puts it.

## Resume

`--resume [<run-document>]`: read the state block of the given file, else the newest
`.claude/runs/*.md` that has one, and follow the guide's § Resume: the state block's `mode`
decides the path, and a `feature` run document resumes as `/feature-flow` would. In its roster
every id is dead with the old session, a research lead's id included: at `step: diagnosis` the
guide's § Bug mode B1 says what a dead lead leaves you (never a fresh lead for an existing
run).

## Final status block

Always end with exactly one block, the guide's lead block:

```yaml
---
agent: lead
status: READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED | BLOCKED | NEEDS_CLARIFICATION | NEEDS_OWNER | STALLED | NO_BUILD_NEEDED | NOT_REPRODUCED
spec: <path or "n/a">
test_iter: <n>
review_iter: <n>
gate_iter: <n>
run_document: <path or "n/a">
investigations: [<folder>, …]
repro: REPRODUCED | waived (D<n>) | pending
summary: <one line>
---
```

## What you do NOT do

- Everything [`feature-flow.md`](./feature-flow.md) § What you do NOT do lists: no commits,
  pushes or branch creation, no source edits by you, no judging of what you forward, never one
  collapsed dispatch for the team-up, never a re-dispatch of a live peer.
- Never write `findings.md` after research's Framing has created it: the owner's decisions go
  into the run document and the spec.
- Never start a fresh research lead for an existing run.
- Never resume Coder before the spec review and the red run are both back, and never let a fix
  go ahead on a failed red run without the owner's recorded decision.
- Never skip the branch gate; in bug mode it moves to after the red run, and `--auto` skips
  owner pauses only.
