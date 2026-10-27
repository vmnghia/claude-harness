# AI workflow — shared contract for Planner / Coder / Tester / Reviewer

Single source of truth for the cross-agent contract: how each agent reports
its result, how the orchestrator routes between them, and what agents are
not allowed to do. Design history (2026-07-07 rearchitecture) predates the public harness repo.

## Roles and entry points

Four agents; Planner is **dual-entry**, the other three are subagents only.

The seven-agent **research team** (`/research`) has its own contract:
[research-workflow.md](./research-workflow.md). So does **`/adversarial-review`**
([adversarial-review.md](./adversarial-review.md)): the round's hunters
(`knobs.width.adversarial-reviewer`) and a judge, no spec, reusing Coder in findings-only mode.

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
- the roster and the run-document path, when known (§ Team protocol)
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
agent: planner | coder | tester | reviewer | orchestrator | lead
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

Every peer block may also carry `decisions_applied: [D…]` and `questions_asked: [Q…]`
(§ Team protocol). A reply that ends in a blocking `QUESTION` block carries no status block.

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

- Three independent counters: `test_iter`, `review_iter` and `gate_iter`. All start at
  **0**, increment on each fix dispatch to Coder (a resume, in the team flow), and **never reset**.
- Default cap: **3** for `test_iter` and `review_iter` (`/feature-flow --max-iter=N`), **2** for
  `gate_iter` (`--max-gate-iter=N`). After a gate fix Tester re-runs; Reviewer does not.
- At the cap the orchestrator stops with `BUG_LIMIT_REACHED` or
  `REVIEW_LIMIT_REACHED` and hands back to the human.

Routing:

- Tester `BUGS_FOUND` → resume Coder with `failures[]`, `test_iter++`,
  then resume Tester.
- Reviewer `CHANGES_REQUESTED` → resume Coder with `findings[]`,
  `review_iter++`, then resume Tester, then Reviewer.
- Planner `NEEDS_CLARIFICATION` (autonomous only) → stop, surface questions.
- Coder `BLOCKED` → stop, surface blockers.

## Branch policy

No agent creates branches, commits, or pushes ([autonomy.md](../rules/autonomy.md)).
Orchestrator branch gate: if the current branch matches `master`, `main`,
`stable`, `develop`, or `release/*`, warn and ask whether to create a
feature branch (named per [git.md](../rules/git.md)) or proceed. Shown even with
`--auto`.

## Team protocol

`/feature-flow` is a **lead and a team of persistent peers**, not a pipeline (design:
`docs/2026-10-22-team-flow-design.md` in the harness repo). The lead is the main session. The
peers are Planner (as a standby subagent), Coder, Tester and Reviewer, dispatched **once** per
run and reached by `SendMessage` after that, so each keeps its context for the whole run. The
adversarial review ([adversarial-review.md](./adversarial-review.md)) is the gate before the
owner, run by the lead as its orchestrator.

**Measured 2026-10-22 (Claude Code 2.1.308):** a parent's `SendMessage` resumes an idle subagent
at once and the subagent's reply to `main` reaches the parent; a subagent's `SendMessage` to a
sibling is accepted but the sibling is never resumed; subagents have no `ListAgents`. So peers
cannot talk to each other directly. **The lead is the switchboard:** every peer message is
addressed to a peer in `to:` but sent to `main`, and the lead forwards it verbatim, judging
nothing. The lead judges only when it decides.

### Roster and run document

The run document `.claude/runs/YYYY-MM-DD-<slug>.md` is the team's shared record. The lead is
its **only writer**. Its first fenced block is the state block, rewritten at every step
boundary and after every decision:

```yaml
state:
  step: planning | coding | testing | reviewing | gate | done
  test_iter: 0
  review_iter: 0
  gate_iter: 0
  roster: {lead: main, planner: <agent id or inline>, coder: <id>, tester: <id>, reviewer: <id>}
  decisions:
    - {id: D1, by: lead | council | owner | assumed, question_id: QC1, question: <one line>, decision: <one line>, applies_to: [coder, tester, reviewer]}
  open_questions: [{id: QC2, from: coder, to: tester, blocking: no}]
  assumptions: [D3]      # decisions with by: assumed, listed in the recap
```

Then, appended verbatim as they happen: every status block, every `QUESTION`, `ANSWER`,
`OBJECTION`, `POSITION` and `DECISION`, under `## <step>` headings. A peer that is resumed or
re-dispatched reads the decisions first. The roster lives in the state block only: peers address
`main` and name roles in `to:`, so no peer ever needs an id and the lead sends no roster message
(every unneeded message to a standby peer is a wake). The standby brief names the roles on the team.

**Standby brief** (Tester, Reviewer and the standby Planner at dispatch): the spec path, the
plan path, the run-document path, the roles on the team, and: "read the run document's decisions
when the lead calls you; until then answer the questions the lead forwards to you, with an
`ANSWER` block, and nothing else." Coder's capsule is the spec and plan as today, plus the
run-document path and the team's roles.

### Message shapes

YAML blocks in `---` fences, last in the reply, one block per phase a message asked for. Ids:
questions are numbered by the asker with its role letter (`QC1`, `QT1`, `QR1`, `QP1`);
objections `O<n>`; decisions `D<n>` by the lead.

```yaml
---                                   # QUESTION (any peer → a peer or the lead, via main)
block: QUESTION
id: QC1
from: coder
to: tester | reviewer | planner | coder | lead
about: <file:line or spec section>
question: <one line>
options:                              # at most three; what the asker would do under each
  - <answer A → what I would do>
blocking: yes | no                    # yes: the asker has stopped; no: it continues on the first option
---
```

```yaml
---                                   # ANSWER (the asked peer → the asker, via main)
block: ANSWER
question_id: QC1
from: tester
answer: <one line>
evidence: <file:line, or D<n>>
is_decision: yes | no                 # "I chose this on purpose" vs "it just happened"
---
```

```yaml
---                                   # OBJECTION (any peer → the lead)
block: OBJECTION
id: O1
from: tester
decision_id: D2                       # or answer_id: QC1
why: <one line>
evidence: <file:line or scenario>
would_break: <one line>
---
```

```yaml
---                                   # POSITION (each peer → the lead, in a council round)
block: POSITION
question_id: QC1
from: planner | coder | tester | reviewer
position: <one line>
reasons: [<up to three>]
risk: <the biggest risk in this position>
---
```

```yaml
---                                   # DECISION (the lead → every peer in applies_to)
block: DECISION
id: D1
by: lead | council | owner | assumed
question_id: QC1
question: <one line>
decision: <one line>
applies_to: [coder, tester, reviewer]
supersedes: D0                        # optional
---
```

Every peer status block gains two optional fields: `decisions_applied: [D…]` (what it has
acted on) and `questions_asked: [Q…]`. A reply that ends in a `QUESTION` with `blocking: yes`
carries **no status block**: it is a pause, not a finished step, and no counter moves.

### Questions

A question is one `QUESTION` and at most one follow-up on the same id. The answer cites a
file:line or a decision id. After the follow-up the asker accepts, or raises an `OBJECTION` to
the lead. Nothing is argued in a third message. A pause reply may carry several `QUESTION` blocks in one reply
when the asker has several independent questions (Reviewer's would-be findings, Tester's
suspected decisions); the lead gets every answer and resumes the asker **once** with all of them.

- **Blocking** (`blocking: yes`): the asker stops and ends its reply with the block. The lead
  gets the answer (from the peer named in `to:`, or by deciding), sends every `DECISION` to its
  `applies_to` first, **then resume the asker** by `SendMessage` with the `ANSWER` or `DECISION`.
- **Non-blocking** (`blocking: no`): the asker sends the block to `main` by `SendMessage` and
  continues on its first option. The lead forwards it, and delivers the `ANSWER` to the asker by
  `SendMessage`. Delivery to a busy peer is not yet measured; until it is, the rule is that the
  answer is delivered **when the asker next goes idle**, before any resume for another reason,
  and the asker then reconciles what it did with the answer. The asker's reply to a delivered
  `ANSWER` is a fresh status block; the step does not advance until it arrives. When a council is
  convened on a busy peer's non-blocking question, that peer is not woken: its stated
  first option as its `POSITION`.
- **Forwarding is verbatim.** The lead copies the block, adds nothing, and sends it to the `to:`
  peer **by agent id** from the roster. Tester asks Coder "was this a choice?"; Reviewer asks
  Coder for a rationale; Coder asks Tester how it would drive something or Reviewer whether an
  import is allowed; anyone asks Planner what the spec meant.
- **Without a roster** (an agent dispatched by `/coder`, `/tester` or `/reviewer` alone) there is
  nobody to ask: the agent works as it did before the team protocol.

### Blockers and decisions

A peer that cannot proceed without a decision the spec does not make **stops with a blocking
`QUESTION` to the lead** instead of guessing or finishing wrong. `BLOCKED` is kept for what nobody
in the run can answer: a missing external system, a denied command, a destructive need.

The lead has three moves, in this order:

1. **The spec settles it** → `DECISION` with `by: lead`, quoting the spec line that settles it in
   `decision:`. A decision that cannot quote one is not move 1.
2. **It does not** → convene a council (below) → `DECISION` with `by: council`.
3. **Still open, or product intent** → the owner, with the positions attached (`AskUserQuestion`
   in an interactive run) → `DECISION` with `by: owner`. Under `--auto` nobody can answer: a
   council that converged becomes `by: assumed` and the run continues, with the id listed under
   `assumptions` and in the recap; a council that did not converge ends the run at the step
   boundary with `NEEDS_OWNER`.

Every `DECISION` is appended to the state block and sent to every peer in `applies_to`, which
acknowledges it in its next block's `decisions_applied` and acts on it. A `DECISION` delivered to an
idle standby peer needs no reply; it applies when that peer is next resumed. Tester never files a
recorded decision as a bug; Reviewer never flags it as drift. An `OBJECTION` to a `lead` or
`council` decision reopens it for one council round; an `assumed` decision is treated as `council`. An `OBJECTION` to an `owner` decision
**cannot be settled by the lead** or a council: it goes back to the owner, or ends `NEEDS_OWNER`
under `--auto`.

### Councils

A council is the lead putting one question to every peer at once, in one message each, and
each answering with a `POSITION`: Planner speaks for intent, Tester for what breaks, Reviewer
for conventions and the stack, Coder for cost and feasibility. The lead never speaks as a voice;
it rules. In interactive runs, where planning ran inline, a Planner subagent is dispatched on
standby so intent has its own voice.

One round, then the lead rules, unless two positions contradict on a **fact** (not a
preference): then exactly one more round, on that fact only, and the lead rules or goes to the
owner. Before every round the lead prints a **cost line**: who is convened and why, since each
position wakes a context.

### Bounds

- One follow-up per question; one council round, a second only on a factual contradiction.
- The evidence gate from [adversarial-review.md](./adversarial-review.md) § Debate rules applies
  to follow-ups and second rounds: a message with no new evidence is that peer being done.
- Owner questions are batched at a step boundary and asked once, with positions attached, unless
  a peer is blocked on one now.
- The lead relays blocks, never prose; prose stays in the run document.
- A round of parallel briefs to one teammate type counts once toward `--max-iter`; the width is
  the number of agents in that round. (Team-flow widths are 1; see `guides/thoroughness.md`.)

### Resume

`/feature-flow --resume [<run-document>]`: every roster id is dead with the old session.
Re-dispatch Planner (subagent), Coder, Tester and Reviewer fresh, each with the spec, the plan,
the full `decisions` list and the standby brief; write the new roster; restart the current
`step` from its beginning (a half-done coding step runs again on the tree as it is, with Coder
told what the previous Coder reported). `test_iter`, `review_iter` and `gate_iter` are kept. A
`QUESTION` or `OBJECTION` that was open is re-raised by the re-dispatched peer if it still
applies. The gate resumes per [adversarial-review.md](./adversarial-review.md) § Resume.

## Procedure

The command executes this section and holds no procedure of its own. Every hunt, turn, ruling
and team block transits the lead's context. At any step boundary, when the lead's
context is at risk, it writes the state block, says so, and stops with the `--resume` command
rather than discovering it mid-gate.

0. **Branch gate**, as § Branch policy. Always, even with `--auto`.
1. **Planning.** Without `--auto`: Planner's procedure inline. With `--auto`: `Agent(planner)`
   with the context capsule. `SPEC_READY` → `spec_path`, `plan_path`. `NEEDS_CLARIFICATION` →
   stop. Create the run document with `step: planning`.
2. **Team up.** In **one message**: dispatch Coder (spec, plan, run-document path, the team's
   roles), Tester and Reviewer (standby brief), and, when planning ran inline, a Planner subagent
   (standby brief with the spec). Record the ids in the state block. `step: coding`.
3. **Coding.** Wait for Coder. A reply ending in a blocking `QUESTION` → § Blockers and
   decisions, then resume Coder. A `SendMessage` from any peer carrying a `QUESTION` → forward to
   its `to:` by id; its `ANSWER` → back to the asker. `IMPLEMENTED` → `step: testing`. `BLOCKED`
   → final `BLOCKED`.
4. **Testing.** Resume Tester: "the tree is ready; decisions so far: D…". Forward its questions
   to Coder and the answers back. `PASS` → `step: reviewing`. `BUGS_FOUND` → resume Coder with
   `failures[]` ("FIX FROM TESTER"), `test_iter++`, then resume Tester (it re-drives what failed
   plus a smoke of the rest). At the cap → `BUG_LIMIT_REACHED`. `--no-test` skips this step and
   Tester's council voice, with a warning.
5. **Reviewing.** Resume Reviewer. Forward its rationale questions to Coder and the answers back.
   `APPROVED` → `step: gate`. `CHANGES_REQUESTED` → resume Coder with `findings[]` ("FIX FROM
   REVIEWER"), `review_iter++`, then Tester (step 4's loop), then Reviewer. At the cap →
   `REVIEW_LIMIT_REACHED`.
6. **Gate.** Run [adversarial-review.md](./adversarial-review.md) § Procedure with this session as
   orchestrator and the spec and decisions available to Coder: fresh hunters, cross-examination,
   debate, judge, synthesis. A hunter's routed question (its hunt reply's `questions[]`) goes to
   Coder by id and the answer back to the orchestrator before cross-examination. Only a
   `DECISION` recorded before the hunt was dispatched withdraws a finding: the `DECISION` block
   is quoted beside the `ANSWER` in the cross-examination message, so the hunter can object to it
   informedly (an `OBJECTION` to the lead). An `is_decision: yes` answer with no decision id is
   evidence for the cross-examination, never a withdrawal, and **the lead records no decision
   between a hunt's dispatch and that round's synthesis** (measured 2026-10-22: a lead did, and
   withdrew three findings under decisions it had just minted).
   The case file's `review_iter` is `gate_iter`; its cap is `--max-gate-iter`; the Reviewer
   loop's `review_iter` never enters the case file. `AGREED` blocker/major → **resume** Coder in findings-only mode, `gate_iter++`,
   then resume Tester unless `--no-test` (a fix can break a scenario), then fresh hunters. Cap
   (`--max-gate-iter`, default 2) → `REVIEW_LIMIT_REACHED` with the summary naming the gate.
   `ESCALATED`/`STALEMATE` at blocker/major → the owner, or `NEEDS_OWNER` under `--auto`. The
   gate's breaker → `STALLED`.
7. **Finish.** `step: done`. Recap: spec and plan paths, run-document and case-file paths,
   `changed_files[]`, the three counters, every decision with `by:` and who it applied to, the
   assumptions, remaining minors and nits, and the owner's next step (commit). Then the final
   block.

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

| Agent              | Read | Edit/Write  | Bash                        | chrome-devtools | Atlassian | AskUserQuestion | SendMessage |
| ------------------ | :--: | :---------: | :-------------------------: | :-------------: | :-------: | :-------------: | :---------: |
| Planner (inline)   | ✅   | specs only  | —                           | —               | ✅        | ✅              | —           |
| Planner (subagent) | ✅   | specs only  | —                           | —               | ✅        | —               | `main` only |
| Coder              | ✅   | ✅          | project build/test/codegen + read-only git + `ss -ltnp` (no dev server) + scratchpad probe scripts | — | —  | —               | `main` only |
| Tester             | ✅   | —           | project dev server + `ss -ltnp`; stops only the server it started | ✅              | —         | —               | `main` only |
| Reviewer           | ✅   | —           | read-only git only          | —               | —         | —               | `main` only |

`SendMessage` carries only the team blocks (§ Team protocol), always to `main`; the lead
forwards. Hunters and the judge never have it.

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
`.claude/runs/YYYY-MM-DD-<slug>.md` (gitignored; the installer adds the ignore line): the state
block first (§ Team protocol), then every agent status block and every team block, appended as
it arrives. Debug iteration loops there instead of
reconstructing them from conversation history.

## What ends the flow

The orchestrator's final reply always carries a single status block:

```yaml
---
agent: lead
status: READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED | BLOCKED | NEEDS_CLARIFICATION | NEEDS_OWNER | STALLED
spec: <path>
test_iter: <n>
review_iter: <n>
gate_iter: <n>
run_document: <path>
summary: <one-line summary>
---
```

`NEEDS_OWNER`: an `--auto` run reached a decision only the owner can make and the council did
not converge, or an objection to an owner decision. `STALLED`: the gate's circuit breaker.

`READY_FOR_HUMAN_APPLY` means Coder IMPLEMENTED (+ `test_result: pass` when
a test runner present), Tester PASS, Reviewer APPROVED, and the gate `APPROVED` (or `REVIEWED`
with nothing at blocker/major); assumptions, if any, are listed in the recap. The human runs `git add` /
`git commit` / `git push` — agents never do.
