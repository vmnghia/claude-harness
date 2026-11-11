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
- `/fix-bug <FRONT-XXXX> [--run-research] [--fix-ticket=FRONT-YYYY] [--spec=<path>]` — the same
  team for a bug: diagnosis, the owner's decisions, a bug spec, a spec review and a red run
  before the fix (§ Bug mode).

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
| Tester   | `PASS` / `BUGS_FOUND`; `REPRODUCED` / `NOT_REPRODUCED` (bug mode's red check) | `scenarios_run[]`, `failures[]` (each: scenario, expected, actual, evidence path, console); red check: `repro_results[]` (each: scenario, `reproduced \| not_reproduced \| not_executable`, evidence path), `positive_control` |
| Reviewer | `APPROVED` / `CHANGES_REQUESTED`; `SPEC_APPROVED` / `SPEC_CHANGES_REQUESTED` (bug mode's spec review) | `findings[]` (each: severity, file, line, issue, suggestion), `summary` |

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
  mode: feature | bug    # absent means `feature`; `bug` is § Bug mode
  step: diagnosis | decisions | planning | spec-review | red | coding | testing | reviewing | gate | done   # the first two and spec-review, red: bug mode only
  test_iter: 0
  review_iter: 0
  gate_iter: 0
  bug_ticket: FRONT-XXXX          # bug mode only, as the three lines below
  fix_ticket: FRONT-YYYY
  investigations: [<folder>, …]   # newest first
  repro: pending | REPRODUCED | waived (D<n>)
  knobs: {…}   # resolved once per guides/thoroughness.md § Input; never re-resolved
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

`/feature-flow --resume [<run-document>]` and `/fix-bug --resume [<run-document>]` are the same:
the state block's `mode` decides the path (absent means `feature`), whichever command was
typed. In bug mode, `step: diagnosis` follows § Bug mode B1 (re-scan when the recorded folder
is settled, else its `AWAITING_HUMAN` rule); `decisions` and `planning` restart from their
beginning with no team; `spec-review` and `red` restart from B4 with a fresh team; and the
branch gate is re-run only from `coding` on. Every roster id is dead with the old session.
Re-dispatch Planner (subagent), Coder, Tester and Reviewer fresh, each with the spec, the plan,
the full `decisions` list and the standby brief; write the new roster; restart the current
`step` from its beginning (a half-done coding step runs again on the tree as it is, with Coder
told what the previous Coder reported). `test_iter`, `review_iter` and `gate_iter` are kept.
`knobs` is kept, never re-resolved; the gate's case file copies it. A `QUESTION` or `OBJECTION` that was open is re-raised by the
re-dispatched peer if it still applies. The gate resumes per [adversarial-review.md](./adversarial-review.md) § Resume.

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

## Bug mode

`/fix-bug` runs a bug from its ticket to a fix proven against its repro (design:
`docs/2026-11-11-fix-bug-design.md` in the harness repo). It is [bug-fixes.md](../rules/bug-fixes.md)
run by the team. Bug mode **replaces § Procedure steps 0 to 2** with steps B1 to B6 below and
then hands over to § Procedure step 3. `--spec=<path>` enters at B4. Everything in § Team
protocol applies; the run document carries `mode: bug` from its first write, and it is created
at the start of B1 (`step: diagnosis`), named from the fix ticket when one was given, else the
bug ticket.

**Knobs.** The thoroughness flags resolve once and serve both the research run and the gate,
with two exceptions. `--max-iter` and the preset's `max_iter` belong to the fix phase only: a
research run started here gets research's own default cap (3). `--max-agents` is
**one ceiling per phase**: the research run counts from zero against it and so does the gate,
so a run can dispatch up to twice the number typed.

**B1. Diagnosis.** `step: diagnosis`.
- **Pick up.** Read the frontmatter of every `.claude/investigations/*/findings.md`. Keep the
  ones with `ticket:` equal to the bug ticket, `kind: incident` and `status: settled`, following
  `superseded_by`, newest folder first. Together they are the diagnosis; where two disagree the
  newest governs. Record them in `investigations:`. A settled run of another kind on the same
  ticket is not the diagnosis: list it for the owner in B2.
- **None settled, or `--run-research`:** execute `commands/research.md § New run` for the bug
  ticket in this session, with the knobs above. Its Framing asks the owner, always, even with
  `--auto`. When a settled investigation exists, frame a delta run and say so. Write the new
  folder into `investigations:` as soon as it exists.
- **An investigation is `status: open`.** Open covers every unfinished run (just framed, paused,
  mid-critique, ended `PARTIAL`, or live in another session); do not guess which. Ask the owner:
  resume it, plan from it as it stands, run a delta, or stop. Under `--auto`: final `NEEDS_OWNER`.
- **Research returns `AWAITING_HUMAN`:** final `NEEDS_OWNER` with the action. On `--resume` in
  the same session, execute `commands/research.md § Resume` and carry on. From a new session
  that section's step 4 applies unchanged: the lead cannot be resumed and no fresh lead is
  started for an existing run. Offer what it offers (abandon, or a new `-2` run seeded from the
  old one) plus "plan from it as it stands".
- **`STOPPED`, or `stopped` / `on-hold` on disk:** final `BLOCKED`, quoting `status_reason`.
- **Next says "No build needed":** final `NO_BUILD_NEEDED`, quoting the Answer.

**B2. Decisions.** `step: decisions`. Read the investigations' `## Open`, `## Options`,
`## Decisions` and `## Repro`. List what only the owner can settle and has not: Open rows whose
resolver is the owner, an Options table with no Decisions row choosing, and a Repro that is not
`REPRODUCED` (the choices: waive the repro and proceed on the evidence, try Red anyway with the
steps the investigation attempted, or stop). Ask once, with `AskUserQuestion`, the research's
recommendation first in each. Each answer is a `DECISION` block `by: owner` in the state block;
`findings.md` is not touched. Nothing to decide: no pause. Under `--auto` with something to
decide: final `NEEDS_OWNER` listing the questions; a council never assumes an owner's decision
about a bug fix. `--no-test` is the owner's waiver: record a `DECISION` `by: owner`
("`--no-test` typed: repro waived") and `repro: waived (D<n>)` here, warn once, and say so in
the recap's first line.

**B3. Planning.** `step: planning`. As § Procedure step 1, with one more capsule item:

```yaml
diagnosis:
  investigations: [<folder>, …]     # newest first
  next: <the Next paragraph(s), verbatim>
  decisions: [D1, D2, …]            # by: owner, from B2
  bug_ticket: FRONT-XXXX
  fix_ticket: FRONT-YYYY            # defaults to the bug ticket
```

Planner writes a bug spec from it (`agents/planner.md`): the root cause in the investigation's
words, Repro Steps from its `## Repro`, and at least one Test Scenario marked `repro: yes` with
`expected (unfixed)` and `expected (fixed)`, unless the repro was waived.

**B4. Team up.** As § Procedure step 2, except that **Coder also gets the standby brief** and
starts nothing. With `--spec`, check first that the sibling plan exists and that the spec has a
`repro: yes` scenario (or the repro is waived); otherwise final `NEEDS_CLARIFICATION` naming
what is missing.

**B5. Spec review** and **B6. Red** go out in one message.

**B5. Spec review.** `step: spec-review`. Resume Reviewer: "SPEC REVIEW: read the spec and the
plan against the code as it stands". `SPEC_APPROVED` → nothing to do.
`SPEC_CHANGES_REQUESTED` → every `blocker` and `major` is fixed in the spec and plan before
coding. Under `--auto` resume the standby Planner with "FIX FROM SPEC REVIEW" and the
`findings[]`; in every other case (inline planning, `--spec`, a resumed run) the lead applies
them. A finding whose fix changes an owner decision goes to the owner, not to a council.
One pass: no re-review, no counter. Reviewer keeps what it read for step 5.

**B6. Red.** `step: red`. Skipped when `repro: waived`. Resume Tester: "RED CHECK: drive only
the `repro: yes` scenarios on the tree as it is, against `expected (unfixed)`; run slug
<slug>". Its block lists a result per scenario (`reproduced`, `not_reproduced`,
`not_executable`) and evidence under `.claude/runs/<run-slug>-evidence/`.
- `REPRODUCED` → `repro: REPRODUCED` and the evidence paths into the state block.
- A `not_executable` scenario is a spec defect: add it to B5's findings, fix the spec, and run
  Red once more. A second `not_executable` is `NOT_REPRODUCED`. A spec fix from B5 that changes
  a `repro: yes` scenario's steps also makes Red run again.
- `NOT_REPRODUCED` → the owner chooses: widen the net, proceed on the evidence, or stop.
  Proceeding is a `DECISION` `by: owner` and `repro: waived (D<n>)`. Stopping is final
  `NOT_REPRODUCED`. Under `--auto`: final `NOT_REPRODUCED`. Never proceed silently.
- **Widening the net** is a delta research run whose question is the repro (B1's second
  bullet). When it settles, go back to B2 for what is new, then B3 with Planner revising the
  existing pair (the lead does it: widening never happens under `--auto`), then B5 on the
  changed parts and B6 again, with the same team. One widening per run: after a second
  `NOT_REPRODUCED` the owner's choices are proceed or stop.

**Branch gate.** As § Branch policy, always. In bug mode the branch gate runs after Red, not at
the start: [bug-fixes.md](../rules/bug-fixes.md) says not to prepare a branch before the repro
is confirmed, and nothing before this point edits source.

**B7. Fix.** § Procedure steps 3 to 7, with these additions to messages and none to routing:
- Coder's first resume: "the spec is final; repro: <state>; decisions so far: D…". That state
  is the repro confirmation `agents/coder.md` asks for; Coder does not reproduce again.
- Tester's "the tree is ready" names the `repro: yes` scenarios and the red evidence paths. A
  `PASS` needs each of them to meet `expected (fixed)` on the same steps, red and green
  evidence listed side by side. With `repro: waived` Tester says the red half is missing.
- The recap adds the investigation folders, the bug and fix tickets, the root cause in one
  line, the repro state, and the red and green evidence paths.

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

`/fix-bug` runs [bug-fixes.md](../rules/bug-fixes.md) as § Bug mode: Tester proves the bug red
before the fix and green after, on the same steps. In a `/feature-flow` run on a bug spec, Coder
still follows it: reproduce locally first, implement, re-verify against the same repro. Tester
mimics the real user flow in both: no `router.push` shortcuts.

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
status: READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED | BLOCKED | NEEDS_CLARIFICATION | NEEDS_OWNER | STALLED | NO_BUILD_NEEDED | NOT_REPRODUCED
spec: <path>
test_iter: <n>
review_iter: <n>
gate_iter: <n>
run_document: <path>
investigations: [<folder>, …]   # bug mode only
repro: <state>                  # bug mode only
summary: <one-line summary>
---
```

`NO_BUILD_NEEDED` and `NOT_REPRODUCED` are bug mode's: the diagnosis says there is nothing to
build, or the red check failed and the owner (or `--auto`) stopped (§ Bug mode B1, B6).

`NEEDS_OWNER`: an `--auto` run reached a decision only the owner can make and the council did
not converge, or an objection to an owner decision. `STALLED`: the gate's circuit breaker.

`READY_FOR_HUMAN_APPLY` means Coder IMPLEMENTED (+ `test_result: pass` when
a test runner present), Tester PASS, Reviewer APPROVED, and the gate `APPROVED` (or `REVIEWED`
with nothing at blocker/major); assumptions, if any, are listed in the recap. The human runs `git add` /
`git commit` / `git push` — agents never do.
