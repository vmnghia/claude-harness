---
description: End-to-end AI feature flow as a team — lead (this session) + persistent Planner, Coder, Tester, Reviewer who ask each other questions through the lead, are convened for decisions, then the adversarial-review gate; ends ready for human apply
argument-hint: <requirement | FRONT-XXXX> [--auto] [--no-test] [--max-iter=N] [--max-gate-iter=N] [--effort=quick|standard|thorough|exhaustive] [--width=<agent>:<n>,…] [--dry=K] [--max-agents=N] [--resume [<run-document>]]
---

Contract: Read [`.claude/guides/ai-workflow.md`](../guides/ai-workflow.md) first and execute its
**§ Procedure** exactly, under its § Team protocol. This file selects where each phase runs and
how arguments and the owner's answers get in; the steps, the blocks, the bounds, the decision
rules and the exits live in the guide. The gate is
[`.claude/guides/adversarial-review.md`](../guides/adversarial-review.md) § Procedure, run with
this session as its orchestrator.

You are the **lead**. You decide what the spec settles, convene the team for what it does not,
and bring the rest to the owner. You are also the **switchboard**: peers cannot reach each other
(measured, see the guide), so every `QUESTION`, `ANSWER` and `OBJECTION` a peer sends to `main`
is forwarded by you, verbatim, to the peer named in its `to:`, **by agent id** from the roster,
never by name. You judge nothing you forward. You write the run document; nobody else does.

## Input

Raw arguments: `$ARGUMENTS`. Parse out:

- A positional requirement string OR a `FRONT-XXXX` Jira key. Required unless `--resume`.
- `--auto` → no owner pauses: planning as a subagent dispatch with a context capsule; owner-only
  decisions go to a council and become `by: assumed` when it converges, `NEEDS_OWNER` when it
  does not (guide § Blockers and decisions).
- `--no-test` → no Tester standby, no Tester step, no Tester voice in councils; warn.
- `--max-iter=N` → cap on `test_iter` and `review_iter` (default 3).
- `--max-gate-iter=N` → cap on `gate_iter` (default: the preset's adversarial cap, 2 at
  `standard`; the preset sets it).
- Thoroughness flags (`--effort`, `--width`, `--dry`, `--max-agents`) → parse and validate per
  [`guides/thoroughness.md`](../guides/thoroughness.md) § Input. Resolve the knobs once per
  `guides/thoroughness.md § Input` (flags, then `project.md` `thoroughness`, then the preset)
  and write them into the run document's `knobs:`. `--max-iter` (Tester/Reviewer) is not
  touched by the preset.
- `--resume [<run-document>]` → go to **Resume**.

A positive integer is required for the caps; otherwise warn and use the default. Missing
requirement without `--resume` → stop with the final block, `status: NEEDS_CLARIFICATION`,
`summary: "Missing requirement. Usage: /feature-flow <requirement | FRONT-XXXX> [...]"`.

## Where each phase runs

- **Branch gate:** `git rev-parse --abbrev-ref HEAD` in this session; on a shared branch ask the
  owner to branch or proceed. Never create the branch yourself. Always, even with `--auto`.
- **Planning:** inline in this session without `--auto` (AskUserQuestion allowed); with
  `--auto`, `Agent` with `subagent_type: "planner"` and the context capsule.
- **Run document:** created and written by you, per the guide § Roster and run document; before
  creating it, `git check-ignore -q .claude/runs/` (trailing slash) and warn once when it fails.
- **Team up:** in **one message**, `Agent` dispatches of `subagent_type: "coder"`, `"tester"`,
  `"reviewer"` and, when planning ran inline, `"planner"` on standby, each with its capsule or
  standby brief from the guide. Record every id in the state block. No roster message: peers address `main` and name roles,
  and every message to a standby peer is a wake. Load `SendMessage` once with ToolSearch
  `select:SendMessage` for the resumes.
- **Every later step is a resume**, never a re-dispatch: `SendMessage` to the peer's id with the
  message the guide's § Procedure names ("the tree is ready", "FIX FROM TESTER" + `failures[]`,
  "FIX FROM REVIEWER" + `findings[]`, "FIX FROM ADVERSARIAL REVIEW" + findings). The same Coder
  id serves the whole run.
- **Switchboard:** a peer reply ending in a blocking `QUESTION` is a pause, not a step: no counter
  moves. Forward it to its `to:` by agent id, or answer it yourself when `to: lead`. Forward the
  `ANSWER` back the same way. A non-blocking `QUESTION` arrives as a message while the asker is
  busy: forward it, and deliver the answer when you have it (guide § Questions for the delivery
  rule). Append every block to the run document as it passes through you.
- **Decisions:** `DECISION` blocks are written by you into the state block and sent to every
  peer in `applies_to` **before** you resume the asker. Print a **cost line** before every
  council round: who is convened and why.
- **Owner pause:** `AskUserQuestion`, with the team's positions attached, batched at a step
  boundary unless a peer is blocked now. Not under `--auto`.
- **Gate:** the adversarial guide's procedure with this session as orchestrator: hunters at
  `knobs.width.adversarial-reviewer`, dry-check rounds per the guide, fresh hunters
  by `Agent` with `subagent_type: "adversarial-reviewer"`, the judge by `"review-judge"`, Coder
  **resumed** by id in findings-only mode with the spec and decisions available, Tester resumed
  after each gate fix, `gate_iter` counted here. A hunt reply's `questions[]` go to Coder by id
  and the answers into the cross-examination message.
- **Report:** in this session, the guide § Procedure step 7, then the final block.

## Resume

`--resume [<run-document>]`: read the state block of the given file, else the newest
`.claude/runs/*.md` that has one. In its roster every id is dead with the old session: re-dispatch Planner
(subagent), Coder, Tester and Reviewer fresh, each with the spec, the plan, the full `decisions`
list and the standby brief; write the new roster into the state block; restart the current `step` from
its beginning with the counters kept; the gate resumes per its own guide § Resume. Run the branch
gate again first, since Coder may edit.

## Final status block

Always end with exactly one block, the guide's lead block:

```yaml
---
agent: lead
status: READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED | BLOCKED | NEEDS_CLARIFICATION | NEEDS_OWNER | STALLED
spec: <path or "n/a">
test_iter: <n>
review_iter: <n>
gate_iter: <n>
run_document: <path or "n/a">
summary: <one line>
---
```

## What you do NOT do

- No commits, pushes, branch creation, or state-mutating git. Read-only git for the branch gate
  and the ignore check only.
- No source edits by you: all edits flow through Coder, resumed by id, so the counters, the
  decisions and the run document stay coherent.
- No judging of what you forward: a `QUESTION` or `ANSWER` passes through verbatim. You judge
  when you decide, and every decision is a `DECISION` block in the record.
- Never collapse the team-up dispatches into one dispatch, never re-dispatch a peer whose id is
  alive, never give a peer another peer's id: they address `main` and you forward.
- Never skip the branch gate; `--auto` skips owner pauses only.
