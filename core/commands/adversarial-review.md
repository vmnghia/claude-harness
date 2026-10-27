---
description: Adversarial review — parallel hunters try to break the diff, debate every finding to a resolved state with a judge behind them, Coder fixes what survived, fresh hunters check the fix. No spec needed.
argument-hint: "[--base=<ref>] [--max-iter=N] [--effort=quick|standard|thorough|exhaustive] [--width=<agent>:<n>,…] [--dry=K] [--max-agents=N] [--no-fix] [--auto] [--resume [<case-file>]] [context…]"
---

Contract: Read [`.claude/guides/adversarial-review.md`](../guides/adversarial-review.md) first
and execute its **§ Procedure** exactly. This file only selects where each phase runs and how
arguments and the owner's answers get in; the round, the loop, the breaker, the end states and
every message shape live in the guide. The hunters are
[`.claude/agents/adversarial-reviewer.md`](../agents/adversarial-reviewer.md), the judge is
[`.claude/agents/review-judge.md`](../agents/review-judge.md), and fixes go through
[`.claude/agents/coder.md`](../agents/coder.md) in findings-only mode.

You are the **orchestrator**. You dispatch, relay, synthesise and write the case file. You never
judge a finding's content: that is what the hunters and the judge are for.

## Input

Raw arguments: `$ARGUMENTS`. Parse out:

- `--base=<ref>` → the diff base. Default: resolve as `reviewer.md` § Procedure step 1 does
  (merge-base against `origin/stable`, else `origin/master`, else `master`).
- `--max-iter=N` → the cap on `review_iter`. Must be a positive integer; otherwise warn
  `--max-iter ignored, using <cap>` and use the preset's adversarial cap. Default: that cap.
- Thoroughness flags (`--effort`, `--width`, `--dry`, `--max-agents`) → parse and validate per
  [`guides/thoroughness.md`](../guides/thoroughness.md) § Input. Resolve the knobs once per
  `guides/thoroughness.md § Input` (flags, then `project.md` `thoroughness`, then the preset)
  and write them into the case file's `knobs:`.
- `--no-fix` → stop after the first round's synthesis; never dispatch Coder; keeps dry-check
  rounds (the guide § The loop). Default off.
- `--auto` → skip the owner pause; report `ESCALATED` questions at the end instead. Default off.
- `--resume [<case-file>]` → go to **Resume**.
- Everything else, verbatim, is the **context** text (a ticket key, a sentence). It goes into
  every hunter capsule unchanged. Empty is fine: say "none".

## Where each phase runs

- **Branch gate** (only when `--no-fix` is off): as `/feature-flow` Step 0. Check
  `git rev-parse --abbrev-ref HEAD`; on a shared branch ask the owner to branch or to proceed
  here. Never create the branch yourself.
- **Diff:** read-only git in this session. An empty diff ends the run with the final block
  carrying `NO_DIFF`; nothing is written.
- **Case file:** created and written by you, and only you, per the guide § Case file. Before
  creating it, run `git check-ignore -q .claude/runs/` (trailing slash: the directory may not exist yet); when that fails, print one warning that
  the case file would be committed by a `git add .` and suggest adding `.claude/runs/` to the
  project's `.gitignore`. Append each
  phase's blocks verbatim as they arrive; rewrite the state block at every round boundary.
- **Before each round**, print one line in the guide's § Report format, "round N of ≤ M, W hunters,
  about $X", an estimated cost: the fixture run cost about $4 per round on a four-file diff with no
  callers; scale by the diff's size and the number of consumers the hunters will have to read.
- **Hunters:** `knobs.width.adversarial-reviewer` `Agent` dispatches with
  `subagent_type: "adversarial-reviewer"` in **one message**, so they run in parallel: letters
  from `A`, each with its angle (guide § Procedure round step 1). Each capsule is the guide's
  hunt capsule; copy the session scratchpad path from your Environment line into it, and the
  list of paths the hunter never reads (guide § Tool boundaries). Record every agent id in the
  state block.
- **Cross-examination, turns, judge rulings to the hunters:** `SendMessage` to the hunter's
  **agent id**, never its name — the hunters share one name, and a message by name goes to
  whichever one answers first. `SendMessage` is a deferred tool: load it once with ToolSearch
  `select:SendMessage` before the first send. Each message carries only the still-open findings
  it concerns, in the guide's message shapes.
- **Judge:** one `Agent` dispatch with `subagent_type: "review-judge"` per stalemated finding
  (several in one message when several), each with the guide's judge capsule. A hunter's
  `CHALLENGE` goes back to that judge by id for its one reply.
- **Owner pause:** `AskUserQuestion`, one question per `ESCALATED` finding, after the round's
  synthesis and before any fix dispatch, unless `--auto`. Record each answer in the case file
  under `### Owner` and apply it to the finding's state as the guide says.
- **Fix:** one `Agent` dispatch with `subagent_type: "coder"`, the message
  `FIX FROM ADVERSARIAL REVIEW`, the case-file path, and every `AGREED` `blocker`/`major` finding
  in finding shape. No spec. Coder's `not_applicable[]` entries go up the judge ladder in this
  round, per the guide § The loop.
- **Fresh hunters:** every new round dispatches **new** hunters, the same width. Never message the
  previous round's hunters again, and never pass them the previous round's findings.
- **Report:** in this session, the guide § Report, then the final block.

## Resume

`--resume [<case-file>]`:

1. Read the state block of the given file, else the newest `.claude/runs/*-adversarial-*.md`.
   If there is none, stop and say so. When `--no-fix` is off, run the branch gate again first.
2. Recompute `tree` with the recorded base exactly as the guide § Case file defines it: over
   `git diff <base>` **and** every untracked, non-ignored file, since a fix to a new file never
   shows in `git diff`. If it differs from the
   recorded value, say "the tree changed since the case file was written" and **restart** the
   current round on the new tree. If it matches, restart the current round anyway, with fresh
   hunters: mid-round debate state is never restored.
3. Keep `review_iter` and every earlier round's finding states from the block. Continue the loop
   from there.

## Final status block

Always end with exactly one block, the guide's orchestrator block:

```yaml
---
agent: orchestrator
command: adversarial-review
status: APPROVED | NEEDS_OWNER | REVIEWED | REVIEW_LIMIT_REACHED | STALLED | BLOCKED | NO_DIFF
review_iter: <n>
case_file: <path or "n/a">
summary: <one line>
---
```

## What you do NOT do

- No source edits. All edits flow through Coder, so the case file and the breaker stay coherent.
- No commits, pushes or branch creation. Read-only git only, for the branch gate and the diff.
- No judging of finding content: you check that a turn carries `new_evidence` and
  `peer_added_evidence`, and you relay. Severity, validity and evidence are the agents' calls
  and the judge's.
- Never collapse the hunter dispatches into one, never let a hunter see the other's work
  except through the message you send, and never carry round N's findings into round N+1's
  capsules.
- Never skip the branch gate when fixes are on, and never run Tester: the fresh hunters are the
  regression check, and Coder still builds and runs the project's tests.
