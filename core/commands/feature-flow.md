---
description: End-to-end AI feature flow — Planner → Coder → Tester (loop) → Reviewer (loop) → ready for human apply
argument-hint: <requirement | FRONT-XXXX> [--auto] [--no-test] [--max-iter=N]
---

You are the **orchestrator** for the project's AI workflow. Read
[`.claude/rules/ai-workflow.md`](../rules/ai-workflow.md) first — it is the
source of truth for the status-block contract, iteration policy, branch
policy, and the spec+plan pair convention.

## Input

Raw arguments: `$ARGUMENTS`.

Parse out:

- A positional requirement string OR a `FRONT-XXXX` Jira key. Required.
- `--auto` → skip the human-review-spec gate AND run planning as a subagent
  dispatch instead of inline. Default off.
- `--no-test` → skip the Tester step (debug only — warn the user). Default off.
- `--max-iter=N` → override the iteration cap. Default 3 (per loop).

If the positional requirement is missing, stop immediately with a single
orchestrator status block carrying `status: NEEDS_CLARIFICATION` and
`summary: "Missing requirement. Usage: /feature-flow <requirement | FRONT-XXXX>"`.

## State machine

Maintain two counters across the run: `test_iter` and `review_iter`, both
starting at **0**, incrementing on each Coder re-dispatch, never resetting
(policy in `ai-workflow.md`).

**Run log.** Create `.claude/runs/YYYY-MM-DD-<slug>.md` at Step 1
(gitignored). After parsing each agent's status block, append it verbatim
under a `## Step — <agent> (test_iter=N, review_iter=M)` heading. This is
the evidence trail for debugging multi-iteration loops — keep it current
even when a step fails.

### Step 0 — Branch policy gate (always shown, even with `--auto`)

Check the current branch (`git rev-parse --abbrev-ref HEAD`). If it matches
`master`, `main`, `stable`, `develop`, or `release/*`, ask the user to
either (a) create a feature branch named per
[`git.md`](../rules/git.md) — suggest a name derived from the requirement
or Jira key — or (b) proceed here. Do not create the branch yourself. Note:
`.claude/hooks/git-guard.sh` will mechanically deny commits on those
branches anyway.

### Step 1 — Planning (mode-mapped)

- **Without `--auto`**: read `.claude/agents/planner.md` and execute the
  procedure **inline in this session** (interactive mode — you may use
  AskUserQuestion and the session memory already in context).
- **With `--auto`**: dispatch `subagent_type: "planner"` with the
  requirement AND a **context capsule**: relevant facts from session
  memory / this conversation (QA store slugs, version forcing, branch
  state, test-runner presence from the session-context hook line).

Either way, parse the resulting status block:

- `SPEC_READY` → remember `spec_path` and `plan_path`. Continue.
- `NEEDS_CLARIFICATION` → STOP. Final orchestrator block with
  `status: NEEDS_CLARIFICATION`, questions in `summary`.

### Step 2 — Human-review-spec gate

Skipped with `--auto`. Otherwise pause: show `spec_path` + one-line summary
and ask the user to confirm. Decline → STOP with `NEEDS_CLARIFICATION`
carrying their feedback.

### Step 3 — Coder (initial)

Dispatch `subagent_type: "coder"` with `<spec_path>` AND `<plan_path>`, no
fix payload.

- `IMPLEMENTED` → remember `changed_files[]` and `test_result`. Continue.
- `BLOCKED` → STOP. Final block `status: BLOCKED`, blockers in summary.

### Step 4 — Tester loop

If `--no-test`: warn it was skipped, jump to Step 5. Otherwise:

1. Dispatch `subagent_type: "tester"` with `<spec_path>`.
2. Parse status:
   - `PASS` → Step 5.
   - `BUGS_FOUND` →
     - `test_iter < max_iter`: `test_iter++`; dispatch Coder with
       `<spec_path>`, `<plan_path>`, and the `failures[]` payload labeled
       "FIX FROM TESTER"; after `IMPLEMENTED`, loop to 4.1.
     - else STOP: `status: BUG_LIMIT_REACHED`, last `failures[]` in summary.

### Step 5 — Reviewer loop

1. Dispatch `subagent_type: "reviewer"` with `<spec_path>` and
   `<plan_path>` (Reviewer auto-resolves the diff base; pass `--base=<ref>`
   only if the user specified one).
2. Parse status:
   - `APPROVED` → Step 6.
   - `CHANGES_REQUESTED` →
     - `review_iter < max_iter`: `review_iter++`; dispatch Coder with the
       `findings[]` payload labeled "FIX FROM REVIEWER"; after
       `IMPLEMENTED`, re-run Step 4 (fixes can break tests), then loop to 5.1.
     - else STOP: `status: REVIEW_LIMIT_REACHED`, last `findings[]` attached.

### Step 6 — Finish

Print a short human-readable recap: spec+plan paths, the run-log path,
final `changed_files[]`, `test_iter`/`review_iter` used, Tester result (or
"skipped"), `test_result` when the project has a test runner, remaining `minor`/`nit`
findings, and the one-line next step: the human runs `git add` /
`git commit` / `git push` per [`git.md`](../rules/git.md) — never you.

## Final orchestrator status block

Always end with exactly one block:

```yaml
---
agent: orchestrator
status: READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED | BLOCKED | NEEDS_CLARIFICATION
spec: <path or "n/a">
test_iter: <n>
review_iter: <n>
summary: <one-line summary>
---
```

## What you do NOT do

- No commits, pushes, branch creation, or state-mutating git. Read-only git
  for the branch gate only.
- No source edits by you — all edits flow through Coder so counters and
  status blocks stay coherent.
- Never collapse multiple subagent invocations into one dispatch.
- Never skip the branch gate — `--auto` skips the spec-review gate only.
