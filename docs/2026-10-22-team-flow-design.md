# Team flow: a lead and peers instead of a pipeline

Status: approved by the owner, 2026-10-22.

## Intent

`/feature-flow` today is a pipeline. The orchestrator dispatches Planner, Coder, Tester and
Reviewer one after another, each fresh, each reporting a status block when done, and routes on
the block. Nothing travels sideways. Coder discovers an ambiguity, guesses, and reports it as a
note at the end. Tester files the consequence as a bug. Reviewer flags the same thing as drift.
Three agents spend a round each on one unanswered question, and the owner reads about it last.

The owner's words: very little communication between agents, a top-down hierarchy instead of a
team of peers. The agents should work with each other to get the best result: Coder raises a
blocker the moment it hits one; the lead decides, possibly with the team, and passes the verdict
to everyone it affects; Tester reasons about whether a bug is a bug or a decision Coder made.

This design rebuilds `/feature-flow` as a **lead and a team of persistent peers**. The lead is
the main session, as now. The peers are the same four roles, dispatched once per run and reached
by message after that, able to ask each other questions directly, convened by the lead for
decisions, and all reading one run document where every decision is recorded. The adversarial
review from `docs/2026-10-22-adversarial-review-design.md` becomes the gate before the owner.

## Measured facts (2026-10-22, this session, Claude Code 2.1.308)

| Fact | Evidence |
|---|---|
| A parent's `SendMessage` to an idle subagent resumes it at once; the subagent's reply to `main` arrives in the parent's conversation as a message | probe: B resumed within seconds of the parent's send, answered, and its answer was delivered |
| A subagent's `SendMessage` to a **sibling** subagent's id is accepted by the tool ("Resuming agent …") but the sibling is never resumed | probe: A's send succeeded; B's transcript did not grow and no turn fired in 9 minutes; the same message from the parent resumed B at once |
| Subagents have no `ListAgents`; they can address only ids they were given | probe: ToolSearch found no such tool for A |
| The tool's own text: a subagent's send goes out under its parent's address and any reply lands in the parent's conversation | SendMessage description |

So peers cannot talk to each other directly in this runtime. The lead carries every message.

## Decisions (owner, 2026-10-22)

- **Peers, not a pipeline.** Agents communicate proactively during the work, not only in their
  final block.
- **The lead decides what the spec settles.** Anything the spec does not settle goes to the
  owner. Before going to the owner, the lead may discuss the question with the team rather than
  decide alone.
- **Hybrid communication.** Free-form for **questions**: one agent asks another directly and gets
  an answer, bounded to a question and one follow-up. Council-shaped rounds for **decisions**:
  the lead puts a question to everyone at once, each gives a position, the lead rules; a second
  round only on real conflict. Never an open-ended thread.
- **Both review stages.** Reviewer stays a team member during the work (spec, rules, stack pins,
  conventions). The adversarial review (two hunters, judge, fix loop) is the gate before the
  owner.
- **Under `--auto`, council then assume.** When nobody can ask the owner, the lead convenes the
  team; if the positions converge it records the decision with `by: assumed`, continues, and
  lists every assumption in the recap; if they conflict it stops with `NEEDS_OWNER` at the step
  boundary. A run that assumed something can still end `READY_FOR_HUMAN_APPLY`, as Planner's
  `ASSUMED:` entries do today.
- **Resumable from the state block.** `--resume [<run-document>]` re-dispatches the peers fresh
  with the decisions in their capsules and restarts the current step; the gate restarts its
  round as its own guide says. A dead session costs at most the current step.
- **Tester may question a bug.** Before filing a failure, Tester checks the recorded decisions and
  may ask Coder whether the behaviour was a choice. A failure that is a recorded decision Tester
  disagrees with becomes an objection to the lead, not a bug.

## Builder's calls (veto-able)

### Shape of the team

- **The lead is the main session**, running `/feature-flow`. It is the only agent that can ask
  the owner, and the only writer of decisions. Mechanically it is also the **switchboard**: a
  peer's question is addressed to a peer but travels through the lead, which forwards it
  verbatim and forwards the answer back verbatim, without judging either (the adversarial
  orchestrator's relay rule). The runtime leaves no other path (§ Measured facts). The lead
  judges only when it decides.
- **Persistent peers.** Planner (when run as a subagent), Coder, Tester and Reviewer are
  dispatched **once** per run and resumed by `SendMessage` for every later step. Coder keeps
  its reasons; Tester keeps what it already drove; Reviewer keeps what it already read. The only
  fresh dispatches are the adversarial hunters and judge, which stay fresh per round on purpose
  (their guide § Debate rules).
- **Raising a blocker.** A subagent cannot pause and wait, so "raise it immediately" means: the
  moment Coder (or any peer) cannot proceed without a decision, it **stops** and ends its reply
  with a `QUESTION` block instead of guessing or finishing wrong. The lead answers and resumes it
  with the decision. This replaces today's `BLOCKED`-at-the-end for anything the lead can settle;
  `BLOCKED` stays for what nobody can (a missing system, a denied command).
- **No new agents.** The council voices are the existing roles: Planner speaks for intent, Tester
  for what breaks, Reviewer for conventions and the stack, Coder for cost and feasibility. The
  lead never speaks as a voice: in interactive runs a Planner subagent is dispatched on standby
  so intent is not the lead's own voice (the anchoring the adversarial design warns about).
- **Tool boundary change.** Coder, Tester and Reviewer gain `SendMessage`, addressed to `main`
  only: every `QUESTION`, `ANSWER` and `OBJECTION` names its real addressee in `to:` and is sent
  to the lead, which delivers it. A non-blocking question costs the asker nothing: it continues,
  and the lead resumes it later with the `ANSWER`. They never message the owner, other sessions,
  or agents outside the run. Everything else in `guides/ai-workflow.md` § Tool boundaries stays.

### The run document

`.claude/runs/YYYY-MM-DD-<slug>.md`, today's run log, becomes the team's shared record and is
gitignored (the installer now adds `.claude/runs/`). The lead is its only writer. Its first
fenced block is a state block:

```yaml
state:
  step: planning | coding | testing | reviewing | gate | done
  test_iter: 0
  review_iter: 0
  roster: {lead: <session name>, planner: <agent id or inline>, coder: <id>, tester: <id>, reviewer: <id>}
  decisions:
    - {id: D1, by: lead | council | owner, question: <one line>, decision: <one line>, applies_to: [coder, tester, reviewer]}
  open_questions: []
```

Then, appended verbatim as they happen: every status block, every question and answer, every
council round, every decision. A peer joining or resuming reads the decisions first. The lead
sends the roster to each peer when it is complete, and again when an id changes.

### Message shapes

All blocks YAML in `---` fences, last thing in a reply; one block per phase a message asked
for (the adversarial-review convention). New blocks, beside the existing status blocks:

- **`QUESTION`** (any peer → a peer or the lead): `to`, `about` (file:line or spec section),
  `question` (one line), `options` (what the asker would do under each answer, at most three),
  `blocking: yes | no`. A blocking question ends the asker's turn; a non-blocking one is asked
  in passing and the asker continues on its stated default.
- **`ANSWER`** (the asked peer → the asker, lead copied): `question_id`, `answer`, `evidence`
  (file:line or a decision id), `is_decision: yes | no` ("I chose this on purpose" versus "it just
  happened"). One follow-up `QUESTION` is allowed on the same id; after that the asker either
  accepts or raises an `OBJECTION`.
- **`OBJECTION`** (any peer → the lead): `decision_id` or `answer_id`, `why`, `evidence`,
  `would_break` (one line). It is never silent disagreement in a note.
- **`POSITION`** (each peer → the lead, in a council round): `question_id`, `position` (one line),
  `reasons` (three bullets at most), `risk` (the biggest risk in its own recommendation).
- **`DECISION`** (the lead → every peer in `applies_to`): the decision entry from the state
  block, verbatim, plus `supersedes` when it changes an earlier one. A peer that receives one
  acknowledges it in its next block's `decisions_applied: [D1, …]` and acts on it.

Existing status blocks gain two optional fields: `decisions_applied` and `questions_asked`
(ids), so the lead can see what each peer has seen.

### Bounds, so a team does not become a chat

- A **question** is one `QUESTION` and at most one follow-up on the same id. The answer must
  cite evidence or a decision id. No third message: accept, or object to the lead.
- A **council round** is one `POSITION` per peer. The lead rules after one round unless two
  positions contradict on a fact (not a preference); then exactly one more round, on that fact
  only. Then the lead rules or goes to the owner.
- The **evidence gate** from the adversarial review applies to follow-ups and second rounds: a
  message that adds no new evidence is that peer being done.
- **Cost line.** Before each council round the lead prints who is being convened and why. Each
  position is a wake of an Opus context; the lead convenes only when the spec does not settle it.
- **Owner questions** are batched: the lead collects everything that needs the owner at a step
  boundary and asks once, with the team's positions attached, unless a peer is blocked on it
  now.

### The flow, step by step

0. **Branch gate**, as today.
1. **Planning**, as today (inline without `--auto`; a subagent with a capsule under `--auto`).
   The spec is the baseline every decision is checked against.
2. **Team up.** The lead creates the run document, dispatches Coder with the spec and plan,
   and dispatches Tester, Reviewer and, when planning ran inline, a **Planner subagent with the
   spec as its capsule** (so intent has its own voice in a council and the lead, who rules, is
   not also a voice), each with a **standby brief**: the spec, the roster so far,
   and "read the run document when the lead calls you; until then answer peers' questions".
   The roster goes to everyone once the ids are known.
3. **Coding.** Coder implements. On an ambiguity the spec does not settle it stops with a
   blocking `QUESTION` to the lead. The lead: settles it from the spec and records `D<n>` by
   `lead`; or convenes a council round and records by `council`; or asks the owner and records
   by `owner`. Then it sends the `DECISION` to every peer in `applies_to` and resumes Coder.
   Non-blocking questions to Tester ("would you drive this with a cookie or a flag?") or Reviewer
   ("is this import allowed here?") are addressed to that peer, carried by the lead, and do not
   stop Coder: the answer resumes Coder when it arrives.
4. **Testing.** The lead resumes Tester with "the tree is ready". Before each failure Tester
   checks `decisions` and may ask Coder one question about the behaviour. `is_decision: yes`
   with a decision id → not a failure. `is_decision: yes` with no decision id → Tester asks the
   lead to record it or overrule it (an `OBJECTION` if Tester thinks it is wrong). Otherwise a
   failure as today. `BUGS_FOUND` → the lead resumes Coder with the failures; `test_iter++`;
   Tester is resumed, not re-dispatched, so it re-drives only what failed plus a smoke of the
   rest.
5. **Reviewing.** The lead resumes Reviewer. Reviewer may ask Coder the rationale behind a
   change before writing a finding, one question per would-be finding. A convention finding
   that Coder justifies with a decision id is not a finding. `CHANGES_REQUESTED` → Coder resumed
   with the findings, `review_iter++`, then Tester, then Reviewer, as today's loop.
6. **Gate.** `/adversarial-review`'s procedure runs with the lead as its orchestrator: fresh
   hunters, the debate, the judge, Coder resumed in findings-only mode but with the spec and the
   decisions available, fresh hunters again. One addition: a hunter may route **one** question
   per finding to Coder **through the lead** before cross-examination ends (hunters have no
   `SendMessage`); an answer with a decision id makes the finding `WITHDRAWN` unless the hunter
   objects to the decision itself, which goes to the lead as an `OBJECTION`.
7. **Finish.** Recap as today, plus the decisions list with who made each, the open owner
   questions, and the adversarial case file path.

### Resume

`--resume [<run-document>]`: read the state block of the given file, else the newest run document.
Every roster id is dead with the old session, so re-dispatch Planner (subagent), Coder, Tester
and Reviewer fresh, each with the spec, the plan, the full `decisions` list and the standby
brief; write the new roster; restart the current `step` (a step restarts from its beginning: a
half-done coding step is re-run against the tree as it is, with Coder told what the previous
Coder reported). `test_iter`, `review_iter` and `gate_iter` are kept. The gate resumes per
`guides/adversarial-review.md` § Resume. An `OBJECTION` or `QUESTION` that was open when the
session died is re-raised by the re-dispatched peer if it still applies.

### Counters, exits and statuses

`test_iter` and `review_iter` as today, default cap 3. The gate has its own counter, `gate_iter`,
default cap 2 (`--max-gate-iter=N`), so a Reviewer loop that used its cap still leaves the gate
able to fix. After every gate fix Tester is resumed (a fix can break a Test Scenario; the spec
exists here, unlike in the standalone command) and then fresh hunters; Reviewer is not re-run
after gate fixes, since the hunters and Tester cover it. Exits: `READY_FOR_HUMAN_APPLY`, `BUG_LIMIT_REACHED`, `REVIEW_LIMIT_REACHED`,
`BLOCKED`, `NEEDS_CLARIFICATION`, plus `NEEDS_OWNER` (an `--auto` run whose council did not
converge on an owner-only question, batched at a boundary) and `STALLED` (the gate's circuit
breaker). `by:` on a decision is `lead | council | owner | assumed`.

### What changes in files

- `commands/feature-flow.md`: the step machine above; it reads the procedure from the guide and
  holds only locus and argument parsing (the research and adversarial-review commands' pattern).
  Arguments gain `--max-gate-iter=N` and `--resume [<run-document>]`.
- `guides/ai-workflow.md`: the shared contract gains § Team protocol (roster, run document,
  message shapes, bounds, the blocker flow, the question flow) and the persistent-peer rule.
  Status blocks gain the two optional fields. The adversarial-review guide is referenced, not
  duplicated.
- `agents/coder.md`, `agents/tester.md`, `agents/reviewer.md`: `SendMessage` in `tools:`; a
  § Team section each (when to ask, whom, the blocks, what a `DECISION` obliges); Coder's
  `BLOCKED` narrowed to the unanswerable; Tester's bug-or-decision step; Reviewer's
  rationale question. `agents/planner.md`: the subagent mode answers `POSITION` messages for
  intent.
- `agents/adversarial-reviewer.md`, `guides/adversarial-review.md`: the one routed question per
  finding, and `WITHDRAWN` on a decision id.
- `scripts/harness-check.sh`: §5 contract linter extended with the new tokens; a new section
  that pins the message shapes across guide, agents and command; the `SendMessage` boundary
  (only coder, tester, reviewer, research-lead, incident-investigator may list it).
- `CLAUDE.md`: the Feature workflow row says "team flow"; the Guides table row for
  `ai-workflow.md` names the new consumers.

### Verification plan

A scratch repo with a small spec that is **deliberately silent** on one choice the
implementation must make (an empty-state copy, a sort order), a planted convention violation
the spec invites, and one defect from the adversarial playbook. Run `/feature-flow` in a fresh
`claude -p`, first with `--auto`, then interactively. Pass: Coder stops with a blocking
`QUESTION` on the silent choice and does not guess; the lead records a decision (`ASSUMED` under
`--auto`, the owner's under interactive) and Coder resumes without re-dispatch; Tester drives the
behaviour and files no bug on it, with the decision id in its block; Reviewer asks Coder about
the convention and files the finding anyway when Coder has no decision to cite; the gate finds
the planted defect; the recap lists every decision with who made it. Cost recorded.

## The tension worth naming

This adds a message protocol (five block types, a roster, a decisions log) on top of a flow that
worked with four status blocks. That is more machinery than most runs will use: a clean spec
produces zero questions and zero council rounds, and the protocol then costs only the standby
dispatches of Tester and Reviewer. The alternative, re-dispatching fresh agents with ever
larger capsules, is what produces the fragmentation the owner described. The protocol is the
price of memory and lateral talk; the bounds are what keep it from becoming the cost centre.
If the first real runs show questions are rare, the standby dispatch can become lazy (dispatch
Tester and Reviewer at their step, with the decisions in the capsule) without changing the
shapes.

## Non-goals

- Free-form decisions: decisions are council rounds ruled by the lead, never emergent from a
  thread.
- New council agents (Architect, Skeptic, Pragmatist, Critic): the existing roles are the voices.
- Replacing Reviewer with the hunters, or the reverse.
- Model diversity.
- Peers messaging the owner or other sessions.

## Verified (2026-10-22, fixture; fresh `claude -p --model claude-opus-5-5` sessions)

Fixture: a Node HTTP server (health endpoint, a `loadItems()` helper whose doc comment promises
`label` while the data files use `title` and `name`, a CSV export that reads `label`, a logging
rule that bans console writes outside `src/log.js`), the harness installed from this branch,
`project.md` filled, dev server on port 3456. Requirement: an items page listing name and
price via `loadItems()`, logging every request, rendering an empty catalogue.

| Expectation | Result |
|---|---|
| One-message team-up; four persistent ids in the roster; one Coder id for the whole run | **Pass** (runs 1, 2). In run 2 the same Coder answered the gate's questions it had been dispatched with at team-up. |
| Coder stops with a blocking `QUESTION` instead of guessing | **Not exercised by a live Coder.** Under `--auto` the Planner subagent's spec resolved every planted ambiguity with `ASSUMED` entries, so Coder had nothing to ask. Run 1 showed `BLOCKED` used correctly for the unanswerable: a foreign dev server on the port. |
| Council round, `DECISION` with `by: assumed` | **Not completed.** In the drill the lead settled the crafted open question from the spec (its move one) and checked the question's premise against the repo first; later it did convene a council of three voices on Coder's non-blocking question about the 500 body, and the run was cut before the positions returned. An autonomous Planner's spec rarely leaves the gap a council needs; interactive runs with thinner specs will. |
| `DECISION` sent to `applies_to` before the asker is resumed; peers cite it | **Pass** (drill). All three peers' blocks carried `decisions_applied: [D1]`. |
| Tester drives the browser from a headless session and files no bug on a decided behaviour | **Pass** (drill: Tester's block cited `decisions_applied: [D1]`); run 2 had no decision before testing, so it only shows the browser path: five scenarios with screenshots, no failures. |
| Reviewer asks Coder for a rationale before a convention finding | **Not triggered**: Coder followed the logging rule, so there was no convention finding to question. |
| The gate runs inside the flow; hunters' routed questions reach Coder; a decision-cited answer withdraws | **Routing passed, the withdrawal rule failed** (run 2): three `ANSWER` blocks with `is_decision: yes` and no decision id reached the orchestrator, which then **minted** two decisions after the answers and withdrew three findings under them. The drill's lead, on the same text, withdrew nothing. The rule is now explicit: only a decision recorded before the hunt dispatch withdraws, and the lead records none between a hunt and its synthesis. In the drill the gate agreed one major and resumed Coder (`gate_iter` 1). |
| Tester re-runs after a gate fix | **Not observed**: the drill was cut off by the account's usage limit right after the gate fix. |
| `--resume` after a dead session re-dispatches fresh peers and restarts the step with counters kept | **Pass** (drill, and once more in a forked session before a collision): four new ids, the old ones recorded as dead, the coding step restarted on the tree as it was. |
| Non-blocking `QUESTION` while busy; answer delivery | **Raised, delivery unmeasured**: Coder sent a non-blocking question about the 500 body text and continued; the run was cut before the answer's delivery could be observed. The guide keeps the "deliver when the asker next goes idle" rule. |
| `READY_FOR_HUMAN_APPLY` with assumptions listed | **Pass** (run 2): Planner's six `ASSUMED` entries and the two decisions listed for the owner. |

Costs: run 1 $4.08 (blocked on the port), run 2 $7.51, drill $7.54 (cut off).

Incidents worth knowing: the minted-decision withdrawal above, the most instructive thing the
live runs produced. And: on a Claude Code restart the daemon forked a background copy of the
orchestrating session, which continued the plan on its own, moved the fixture to another port
and resumed run 1; the two sessions collided until the owner killed the fork. Its ledger lines
were kept as evidence. A `claude -p` launched with `setsid` detaches from its launcher, so wait
on the pid, not the launcher.

## Left to the builder

- Exact wording of every block and of the standby brief; the roster message.
- How the lead addresses itself in `to:` (its `ListAgents` name) and how peers learn it.
- Whether Tester's standby dispatch starts the dev server early or waits for "tree is ready".
- The scratch-repo fixture for the verification plan.
