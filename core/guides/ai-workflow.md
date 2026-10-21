# AI workflow — shared contract for Planner / Coder / Tester / Reviewer

Single source of truth for the cross-agent contract: how each agent reports
its result, how the orchestrator routes between them, and what agents are
not allowed to do. Design history (2026-07-07 rearchitecture) predates the public harness repo.

## Roles and entry points

Four agents; Planner is **dual-entry**, the other three are subagents only.

The seven-agent **research team** (`/research`) has its own contract:
[research-workflow.md](./research-workflow.md).

- `/planner <requirement | FRONT-XXXX>` — executes `.claude/agents/planner.md`
  **inline in the main session** (interactive mode: AskUserQuestion allowed,
  session memory available).
- `Agent(planner)` — the same file dispatched as a subagent (autonomous
  mode: no user dialogue; assumptions recorded as `ASSUMED:` entries in the
  spec's Open Questions). The dispatcher MUST include a **context capsule**
  in the prompt — relevant session-memory facts (QA slugs, branch state,
  version-forcing tricks) — because subagents start cold.
- `/coder`, `/tester`, `/reviewer` — slim wrappers dispatching the matching
  subagent in `.claude/agents/<role>.md`.
- `/feature-flow <requirement | FRONT-XXXX> [--auto] [--no-test] [--max-iter=N]`
  — the full sequence. Interactive runs plan inline; `--auto` dispatches the
  planner subagent with a context capsule.

Never duplicate an agent's procedure in a command file — commands select the
execution locus; agent files hold the procedure.

### Context capsule template

Every planner-subagent dispatch includes these items (the capsule is the
subagent's only memory — its quality bounds the spec's quality):

- the requirement / Jira key, verbatim
- current branch + dirty-file summary (from the session-context hook line)
- test-runner presence (the session hook's `tests=` value)
- QA access facts: store slug(s), version-forcing steps, test cookies
- one-line constraints from related tickets / the program the ticket
  belongs to
- known gotchas that affect Test Scenarios (SSR version precedence,
  restart wait, cookie resets)

Omit what is genuinely unknown — never invent capsule facts.

## Spec + plan pair

Planner emits two files with the same date+slug stem under `.claude/specs/`:

- `YYYY-MM-DD-<topic>-spec.md` — from `.claude/templates/spec-template.md`.
- `YYYY-MM-DD-<topic>-plan.md` — via `superpowers:writing-plans`.

Callers pass BOTH paths to every dispatch. "Newest `*-spec.md` by filename
date + its sibling `-plan.md`" is fallback discovery only.

## Status block contract

Every agent ends its reply with a YAML-style status block:

```yaml
---
agent: planner | coder | tester | reviewer | orchestrator
status: <enum-per-agent>
iteration: <n>                    # test_iter or review_iter, per caller
spec: .claude/specs/YYYY-MM-DD-<topic>-spec.md
payload:
  <agent-specific fields>
---
```

### Per-agent enum and payload

| Agent    | Status                               | Payload (core fields) |
| -------- | ------------------------------------ | --------------------- |
| Planner  | `SPEC_READY` / `NEEDS_CLARIFICATION` | `spec_path`, `plan_path`, `summary`, `is_bug_spec`, `open_questions[]` |
| Coder    | `IMPLEMENTED` / `BLOCKED`            | `changed_files[]` (each: `path`, `note`), `notes`, `build_result`, `test_result: pass\|fail\|n/a`, `blockers[]` |
| Tester   | `PASS` / `BUGS_FOUND`                | `scenarios_run[]`, `failures[]` (each: scenario, expected, actual, evidence path, console) |
| Reviewer | `APPROVED` / `CHANGES_REQUESTED`     | `findings[]` (each: severity, file, line, issue, suggestion), `summary` |

`severity` values: `blocker | major | minor | nit`. Reviewer emits
`CHANGES_REQUESTED` iff ≥1 finding is `blocker` or `major`; otherwise
`APPROVED` (`minor`/`nit` may still appear informationally).

`NEEDS_CLARIFICATION`: in interactive mode Planner asks the user instead of
emitting it; the status survives only for autonomous-mode hard blockers
(Jira unreachable, self-contradictory requirement, unknown affected
surface).

## Unit tests — conditional policy

The flow keys on whether the project has a test runner: `project.md` § Commands
"Tests" (and the session hook's `tests=present|absent`, from `test_runner_marker`).
If it has one:

- **Coder** runs the project's test command before reporting; failures mean the work is
  not done (`test_result` in payload).
- **Reviewer** maps the spec's `Unit Test Notes` to actual cases; uncovered
  changed logic is a finding (severity by impact).
- **Tester** stays browser-only either way.

If absent: Coder reports `test_result: n/a`; Reviewer may note untested
logic informationally, never as a blocker.

## Iteration policy

- Two independent counters: `test_iter` and `review_iter`. Both start at
  **0**, increment on each re-dispatch of Coder, and **never reset**.
- Default cap per loop: **3**. Overridable via `/feature-flow --max-iter=N`.
- At the cap the orchestrator stops with `BUG_LIMIT_REACHED` or
  `REVIEW_LIMIT_REACHED` and hands back to the human.

Routing:

- Tester `BUGS_FOUND` → re-dispatch Coder with `failures[]`, `test_iter++`,
  then re-run Tester.
- Reviewer `CHANGES_REQUESTED` → re-dispatch Coder with `findings[]`,
  `review_iter++`, then re-run Tester, then Reviewer.
- Planner `NEEDS_CLARIFICATION` (autonomous only) → stop, surface questions.
- Coder `BLOCKED` → stop, surface blockers.

## Branch policy

No agent creates branches, commits, or pushes ([autonomy.md](../rules/autonomy.md)).
Orchestrator branch gate: if the current branch matches `master`, `main`,
`stable`, `develop`, or `release/*`, warn and ask whether to create a
feature branch (named per [git.md](../rules/git.md)) or proceed. Shown even with
`--auto`.

## Mechanical enforcement (hooks)

The prose rules are backed by two hooks registered in `.claude/settings.json`:

- `.claude/hooks/git-guard.sh` (PreToolUse on Bash) — denies pushes from/to
  shared branches, plain `--force`, commits on shared branches, and
  `--no-verify`, for every agent and session. **A git-guard denial is
  policy, not an error — never retry or work around it.**
- `.claude/hooks/session-context.sh` (SessionStart) — emits current branch,
  newest spec+plan pair, test-runner presence, and dirty-file count so agents
  don't re-probe.

## Tool boundaries

Enforced by subagent frontmatter; inline planner uses main-session tools.

| Agent              | Read | Edit/Write  | Bash                        | chrome-devtools | Atlassian | AskUserQuestion |
| ------------------ | :--: | :---------: | :-------------------------: | :-------------: | :-------: | :-------------: |
| Planner (inline)   | ✅   | specs only  | —                           | —               | ✅        | ✅              |
| Planner (subagent) | ✅   | specs only  | —                           | —               | ✅        | —               |
| Coder              | ✅   | ✅          | project build/test/codegen + read-only git + `ss -ltnp` (no dev server) | — | —  | —               |
| Tester             | ✅   | —           | project dev server + `ss -ltnp`; stops only the server it started | ✅              | —         | —               |
| Reviewer           | ✅   | —           | read-only git only          | —               | —         | —               |

## Verification rule (inherited)

Tester drives Chrome DevTools MCP per [verification.md](../rules/verification.md):
scenario URL from the spec (nothing hardcoded), cookies via
`evaluate_script`, reload `ignoreCache: true`, pristine SSR via in-page
`fetch(location.href, {cache:'no-store'})` — never shell `curl`. Respect the
dev-server restart wait (`project.md` § Dev server). Type-check passing
≠ verified.

## Bug-fix rule (inherited)

For bug specs, Coder follows [bug-fixes.md](../rules/bug-fixes.md): reproduce
locally first, implement, re-verify against the same repro. Tester mimics
the real user flow — no `router.push` shortcuts.

## Run log

`/feature-flow` keeps a per-run evidence trail at
`.claude/runs/YYYY-MM-DD-<slug>.md` (gitignored): every agent status block,
appended as it arrives. Debug iteration loops there instead of
reconstructing them from conversation history.

## What ends the flow

The orchestrator's final reply always carries a single status block:

```yaml
---
agent: orchestrator
status: READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED | BLOCKED | NEEDS_CLARIFICATION
spec: <path>
test_iter: <n>
review_iter: <n>
summary: <one-line summary>
---
```

`READY_FOR_HUMAN_APPLY` means Coder IMPLEMENTED (+ `test_result: pass` when
a test runner present), Tester PASS, Reviewer APPROVED. The human runs `git add` /
`git commit` / `git push` — agents never do.
