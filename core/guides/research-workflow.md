# Research workflow — shared contract for the research team

Single source of truth for how the research team runs: who dispatches whom, what each agent
returns, and how a run moves through human-run captures. Counterpart of
[ai-workflow.md](./ai-workflow.md), which covers the feature flow; this file reuses its
status-block frame and context capsule. Design and decisions: `docs/2026-10-14-research-workflow-design.md`
in the harness repo.

Every agent here also follows [research-discipline.md](../rules/research-discipline.md) and writes
into an investigation folder shaped by
[templates/findings-template.md](../templates/findings-template.md).

Agents: `research-lead`, `incident-investigator`, `repro-driver`, `searcher`, `web-reader`,
`designer`, `writer`, and for the critique `research-critic`, `research-judge`. Entry point:
`/research`.

**Standalone use (2026-10-16).** `searcher` and `web-reader` may also be dispatched
directly by the main session for a single lookup, outside any run: no investigation folder
(`findings: null`), no cap, and the main session applies this file's routing table itself.
The when-to and the citation rules are in [delegation.md](../rules/delegation.md).

## Flow and roles

```
/research <question | FRONT-XXXX> [--max-iter=N] [--no-critique] [thoroughness flags]
          | --resume <folder> | --critique <folder>
 ├─ 1. Frame (inline, main session; may ask the owner)
 │     procedure: research-lead.md § "Framing"
 │     → .claude/investigations/YYYY-MM-DD-<slug>/findings.md
 │       (frontmatter, question, dispatch plan: which teammate gathers what, and what result
 │        would confirm or kill each hypothesis)
 ├─ 2. Agent(research-lead) with the framing + a context capsule
 │     procedure: research-lead.md § "Running the team"
 │       searcher · web-reader at `knobs.width`, partitioned · incident-investigator
 │                                                        in parallel when independent
 │       designer → writer                                in sequence (copy fills canvas slots)
 │       incident-investigator → repro-driver             the only nested dispatch
 │     the lead merges every report into findings.md, drafts Answer + Next and returns
 │     (gather and draft); it finishes the write-up only after the critique
 ├─ 3. Critique (main session as orchestrator; § Critique; skipped by --no-critique,
 │     --effort=quick, or a lead status of STOPPED)
 │       research-critic × knobs.width.research-critic   in one message, then N-way
 │                                                        cross-examination
 │       rebuttal → re-check (critic ↔ lead, SendMessage to the lead's id)
 │       research-judge per stalemated blocker/major → synthesis into critique.md
 │       dry loop at K; then "critique settled" → the lead finishes (## Critique, Answer,
 │       Next, the Confluence draft) and returns its final block
 ├─ 4. Main session shows the owner the lead's status block + Answer + Next + the critique table
 └─ 5. The owner decides whether to run /planner on Next
```

**Single writer.** Only research-lead writes `findings.md` and `run-log.md`. Two exceptions,
both in the main session: `lead.txt` (the lead's agent id, used to resume it), and
`critique.md`, the critique's case file and the **second main-session file** in the folder
(§ Critique, Case file). Critics and judges return blocks; the lead applies them. The investigator
writes `capture.md` and `evidence-*.md`; every other agent returns its results in its status
block only. (The designer's canvas files are decided with its medium.) Framing creates
`findings.md` in the main session; after that the lead changes it with `Edit` only, because a
subagent's whole-file `Write` to it is refused (measured 2026-10-15).

**Design medium.** A design task's medium is chosen at framing and approved with the owner's "go"
(a Decisions row): `canvas` (default: HTML files in `design/`) or `artifact` (a whole landing
page or dashboard someone will click through). A designer that finds the medium wrong mid-run
returns `NEEDS_INPUT` (`artifact medium: <why>`) before drawing. The lead may **deny** on its
own; to accept, it returns `AWAITING_HUMAN` (`approve artifact medium for <X>: <reason>`).
Only the owner approves publishing; no agent authorises another's outward action.

**Confluence write-up (2026-10-15).** Only when the framing has a Decisions row naming
the target (`Confluence: new draft under <parent URL>` or `draft update of <page URL>`).
- At write-up, research-lead writes the page as a Confluence **draft**. Its frontmatter hook
  `confluence-draft-gate.sh` denies any create or update without `draft: true`. It runs only
  while the lead runs; measured with a probe agent on 2026-10-15, where it fired inside the
  subagent and not in the parent session.
- The page follows the target folder's convention: a template named in `project.md` § Tickets
  and docs, else two sibling pages the lead matches (research-lead.md step 10.3).
- **Labels need the owner.** `updateConfluenceContent` has no labels field, and adding labels is an
  `executeWrite` operation that no agent has. The lead lists the labels to add in Open.
- `/research` shows the owner the draft link, and **they publish**. No other agent has a Confluence
  write tool, and none has `executeWrite`/`executeDestructive`.
- This is the one exception to draft-in-chat (`autonomy.md`).

**Waiting for the owner (`AWAITING_HUMAN`).** A subagent can't wait for a person. When a run needs
something only the owner can do, the agent that needs it returns `AWAITING_HUMAN` with an `action`:
a human-run capture ("paste results into `<folder>/results.txt`", with `capture_path`), or a block
they can clear ("start the dev server", "close the other window holding the chrome-devtools
profile", "wait until <session>'s measurement lock is gone"). A block nobody can clear in place
(an irreversible action on prod, prod-only data) stays `BLOCKED` and goes to Open; it doesn't
pause the run.

- **Propagation.** repro-driver → incident-investigator → research-lead → `/research`. Each agent
  first finishes every branch that doesn't depend on the action, then returns `AWAITING_HUMAN`
  with the `action` (and `capture_path`) it received.
- **Resume the same agent.** Every dispatcher records its teammates' agent ids (the lead in
  `run-log.md`, the investigator in its payload's `repro_agent_id`). After the owner does the action
  and runs `/research --resume <folder>`, each level sends "done: <action>" to **the same agent**
  that paused, via SendMessage. A resumed agent re-checks its preconditions before continuing:
  state from before the pause (a browser tab, a server, cookies) is not trusted.
- **When a fresh dispatch replaces a resume.** Only when resuming would be wrong: SendMessage to
  the old agent fails, the task itself changed (e.g. a new repro brief), or the old agent's last
  report was a permanent `BLOCKED`. A fresh dispatch counts toward the cap; a resume does not.
- **The lead itself** is resumed by `/research`, never replaced. If it can't be resumed (the
  session that ran it has ended), that run ends: the owner either abandons it or starts a **new run**
  in a `-2` folder whose framing is seeded from the old run's `findings.md` and `results.txt`. A
  new run is not a resumed lead: its counters start at 0 and its findings cite the old folder as
  a source.

**Infrastructure failures (session limit / HTTP 429, API or network errors).** The harness
reports the cut-off agents as `failed`, with no status block (all six agents of the first run,
2026-10-14). That is not a finding, not `BLOCKED` and not `STOPPED`; nothing about the brief
changed.

- Once the limit resets, the owner runs `/research --resume <folder>`, or says "resume" in the
  session that ran it.
- `/research` resumes the lead. The lead resumes each failed teammate via SendMessage, the
  investigator resumes its own driver, and each one re-checks its preconditions first. The
  first run's investigator caught a staging redeploy this way.
- Resumes after a failure are not dispatches and don't count toward the cap. The lead records
  the gap under "Pause / resume" in `run-log.md`.
- If a send fails, the same rule applies as for `AWAITING_HUMAN`: a fresh, counted dispatch
  for a teammate, a new `-2` run for the lead.

## Status blocks

Same frame as `ai-workflow.md`:

```yaml
---
agent: <name>
status: <enum>
iteration: <n>
findings: .claude/investigations/<folder>/findings.md
payload:
  stop_trigger: null            # or which research-discipline.md §6 trigger fired
  assumptions: []               # each with its label
  <agent-specific fields>
---
```

| Agent | Status | Payload (core fields) |
|---|---|---|
| research-lead | `ANSWERED` / `PARTIAL` / `AWAITING_HUMAN` / `STOPPED`; `REBUTTAL` (phase block answering the critique) | `findings_path`, `answer` (one line), `next` (build / no-build + summary), `open[]`, `action`, `capture_path`, `dispatches[]` (agent, status, round), `confluence_draft` (url, content_id, version; unpublished), `critique` (rounds, findings, fixed, agreed, withdrawn, refuted, disputed; final block after the critique) |
| incident-investigator | `DIAGNOSED` / `PARTIAL` / `AWAITING_HUMAN` / `STOPPED` | `root_cause` (+ label), `fix_proposal`, `repro` (`REPRODUCED` / `NOT_REPRODUCED` / `BLOCKED` / `not_run`), `repro_agent_id`, `evidence_files[]`, `action`, `capture_path`, `findings[]` (claim, label, evidence), `open[]` (incl. LogRocket session URLs for the owner to open) |
| repro-driver | `REPRODUCED` / `NOT_REPRODUCED` / `AWAITING_HUMAN` / `BLOCKED` | `steps_run[]`, `attempts` (e.g. `2/3`), `positive_control` (required for `NOT_REPRODUCED`), `action`, `block_reason`, `evidence[]`, `console[]`, `network[]` |
| searcher | `FOUND` / `NOT_FOUND` / `BLOCKED` | `hits[]` (`path:line`, one-line snippet), `searches[]` (pattern, scope), `positive_control` (required for `NOT_FOUND`) |
| web-reader | `GATHERED` / `NOT_FOUND` / `BLOCKED` | `sources[]` (url, version or date, read_at, quote, claim supported; each quote hook-verified), `unverified[]` (same + `verdict`; never citable), `unreachable[]` |
| designer | `CANVAS_READY` / `NEEDS_INPUT` / `AWAITING_HUMAN` / `BLOCKED` | `canvases[]` (location, viewport, state, png), `slots[]` (named copy slots), `measured_styles`, `needs[]` (incl. `artifact medium: <why>`), `action` |
| writer | `COPY_READY` / `NEEDS_INPUT` / `BLOCKED` | `copy[]` (slot, text, `alternatives[]`, char_count, language), `needs[]` |
| research-critic | `FINDINGS` / `CLEAN` (hunt), `RULINGS` (cross-examination), `TURN` (re-check and turns) | `findings[]` (critique-finding shape), `rulings[]`, `added[]`, `turns[]`, `summary` |
| research-judge | `UPHELD` / `REFUTED` / `OUTSIDE_RUN` | `finding`, `severity`, `evidence`, `trigger`, `refutation`, `question` (required with `OUTSIDE_RUN`), `summary` |

- `STOPPED` = a stop trigger fired (the evidence base is suspect). `BLOCKED` = a tool or access
  problem. They call for different responses.
- `research-critic`, `research-judge` and the lead's `REBUTTAL` reply in the adversarial frame,
  not the one above: shapes in `adversarial-review.md` § Critique variants.
- No agent emits `NEEDS_CLARIFICATION`: none can ask the owner. The lead turns a teammate's
  `NEEDS_INPUT` into a re-dispatch with context, or into `PARTIAL` plus an Open entry.

## Dispatch, iteration, routing

1. **Async waiting.** An `Agent` call returns at once; the report arrives later as a hand-back
   (measured 2026-10-14). A dispatcher must not end its turn while a teammate it dispatched is
   outstanding, and never reads a teammate's transcript file (the harness warns it overflows
   context; a mid-run transcript holds hypotheses, not findings; it bypasses the status block).
2. **Rounds and the agent ceiling.** One counter per teammate (2026-10-15), starting at 0, +1
   per **round**, never reset (including across a resume). A round is one dispatch message to
   one teammate type, whatever its width. A round of parallel briefs to one teammate type
   counts once toward `--max-iter`; the width is the number of agents in that round.
   Parallel briefs within a round are partitioned per
   [`guides/thoroughness.md § Width semantics`](thoroughness.md), never duplicated. Plan
   rounds against `--max-iter`: default 3 rounds per teammate per run; `/research --max-iter=N`
   overrides (it is `knobs.max_iter`). At the cap the lead records the gap under Open, naming
   the cap, and goes `PARTIAL`.
   `max_agents` is a second ceiling, on dispatches: every fresh agent counts, a resume is free.
   A round that does not fit is not started: the lead records the gap under Open, naming the
   ceiling, and goes `PARTIAL` (`guides/thoroughness.md § Agent ceiling`). `AWAITING_HUMAN`
   pause/resume cycles are uncapped (each is gated by the owner), and a resume is not a
   dispatch.
3. **Routing.**

   | Teammate result | Lead's action |
   |---|---|
   | `FOUND` · `GATHERED` · `REPRODUCED` · `DIAGNOSED` · `CANVAS_READY` · `COPY_READY` | merge into findings.md with labels; continue |
   | `NOT_FOUND` / `NOT_REPRODUCED` with a positive control | record under "Not shown / ruled out"; continue |
   | `NOT_FOUND` / `NOT_REPRODUCED` without one | invalid: re-dispatch asking for the control (counts as a round) |
   | `NEEDS_INPUT` | re-dispatch with the missing context, or Open + `PARTIAL` |
   | `BLOCKED` (permanent) | Open, naming who can unblock; continue other branches |
   | `STOPPED` | don't re-send the brief; re-check provenance; the lead's own third hypothesis stops the lead |
   | `AWAITING_HUMAN` | finish independent branches, then the lead returns `AWAITING_HUMAN` with the `action` (+ `capture_path`) |
   | web-reader `unverified[]` entries, or an `ESCAPE` line for its agent id in `.claude/runs/quote-verify.log` | not a status and not a re-dispatch: those quotes are uncitable. Spot-check the load-bearing ones (step 5) or list them under Open |

   The web-reader's Stop hook (`quote-verify-gate.sh`, its own frontmatter) re-fetches every
   `sources[]` URL raw and blocks the agent until each quote is a verbatim substring or has been
   moved to `unverified[]`. It always converges, so a hook block never surfaces as a status.

4. **Resume**: see "Flow and roles" → "Waiting for the owner" and "Infrastructure failures".
5. **Shared resources.** searcher and web-reader may run in parallel. designer and
   repro-driver both use the single chrome-devtools profile: never at the same time. At most one repro-driver
   at a time (dev-server ports, the single chrome-devtools profile); the investigator checks
   `.claude/runs/MEASUREMENT-IN-PROGRESS.md` before dispatching it.
6. **Run log.** Every status block is appended to `run-log.md` in the investigation folder as it
   arrives. `findings.md`'s Log section records changes to the findings only.
7. **End of run.** `/research` shows the owner the lead's final status block, Answer and Next,
   and the critique table (§ Critique step 9).

## Critique

Peer review of `findings.md` before the owner acts on it. Fresh **critics**
(`research-critic`) try to break the run's claims; the **lead**, resumed, answers as the author
and stays the only writer of `findings.md`; a fresh **judge** (`research-judge`) rules on what
the two argue to a standstill; the owner settles the rest. The main session is the
orchestrator and runs this section; `/research` only selects where each phase runs. Every
message and block named here has its shape in
[`adversarial-review.md` § Critique variants](adversarial-review.md#critique-variants). The
debate machinery is `adversarial-review.md` § Debate rules (N-way cross-examination, burden of
proof, evidence gate, exhaustion, the 8-turn cap, ladder scope, the judge ladder), applied with
the differences this section names.

**When it runs.** After the lead's first return with `ANSWERED` or `PARTIAL`, before its
write-up is final: the lead's run splits into *gather and draft* (first return) and *finish*
(on step 8's message). Skipped by `--no-critique`, by `--effort=quick` (the research critique row of
`thoroughness.md § Presets`), and by a lead status of `STOPPED` (nothing to review). On
`AWAITING_HUMAN` the critique waits for the resume that ends in `ANSWERED` / `PARTIAL`. It
starts only when the run has no `critique.md`; `--resume` never starts or restarts a settled
one (§ Closing the run, "Start, restart, resume").

**Knobs and the ceiling.** Critic width is `knobs.width.research-critic` and `K` is
`knobs.dry`, resolved once by `/research` (`thoroughness.md § Input`); critics and judges get
numbers, never the guide. Before the lead is dispatched, `/research` subtracts the critique's
reserve (0 with the critique off; `guides/thoroughness.md § Agent ceiling`, "One ceiling,
three dispatchers") from `max_agents`. The lead's capsule carries the remainder as its
`max_agents`. After the lead returns, the critique's `dispatched`
starts at the dispatches the lead counted against its share (its `dispatches[]`); every critic
and every judge adds 1, and so does every `redispatch` in a `REBUTTAL` block, which also counts
toward the lead's share and that teammate's round cap. A dispatch fits when
`dispatched + n ≤ max_agents` (`n` is the whole critic width for a round, 1 for a judge), so
the first round always fits. A judge that does not fit leaves its finding `STALEMATE` with
`reason: agent ceiling`; a further round that does not fit is not started, and the report says
the loop was **cut at the agent ceiling**.

**Roles, angles, ids.** Critics are `critic-A` … `critic-H` in dispatch order. The `n`-th
critic takes the `n`-th of `evidence-first`, `argument-first`, `scope-and-decisions`, cycling
above three by `thoroughness.md § Angles`; a further round rotates them by that section's
dry-check rule. The orderings themselves live in `agents/research-critic.md`. Finding ids are the
critic's letter plus its own sequence (`A1`, `B2`); the case file prefixes the round (`r1-A1`).

### The round

1. **Hunt.** Dispatch the round's critics in **one message**, each with the critique capsule.
   Record every agent id in the state block (`critics:`) and append every hunt reply. A critic
   gathers no new evidence (no `searcher`, no new web search), and its reply has no
   `questions[]`: the author answers in the rebuttal, not before.
2. **Cross-examination.** Send each critic the cross-examination message with the other
   critics' findings; append every reply. Tally each finding by § Debate rules, N-way
   cross-examination (`adversarial-review.md` § A round step 2 for a re-graded severity).
   `minor` / `nit` resolve here by § A round step 3 (`AGREED`, `WITHDRAWN`, `CONTESTED`) and
   never go up the ladder. A `blocker` / `major` with a majority `VALID` is `AGREED`; every
   other `blocker` / `major` is **open**. With a lead, no turns run between critics: an open
   finding is debated with the lead (step 4); without one, § Closing the run, "If the lead
   cannot be resumed". Rulings with `same_as` merge at synthesis (step 6).
3. **Rebuttal.** One `SendMessage` to the lead's id (`lead.txt`): the critique message, with
   every `AGREED` finding and every open `blocker` / `major` in critique-finding shape, each
   with the cross-examination rulings on it verbatim, plus the `CONTESTED` ones for
   information. The lead replies with a `REBUTTAL` block (§ Rebuttal); the orchestrator checks
   that the fields each `response` requires exist, appends the block and relays it; it never
   judges content. If the `SendMessage` fails, § Closing the run, "If the lead cannot be
   resumed", applies from here. When the critique message would carry no `AGREED`, open or
   `CONTESTED` finding (a `CONTESTED` one is sent: the lead may `FIX` it), steps 3–5 are
   skipped and the synthesis records `rebuttal: not needed`.
4. **Re-check and turns.** Each asserting critic gets the re-check message: the lead's
   responses on its own findings and the current `findings.md`. A finding's two sides are its
   critic and the lead. The lead takes the designated challenger's seat (the author disputes
   the finding), so turns are **critic ↔ lead**; the other critics take no turns on it, and the
   burden of proof stays with the critic. The critic answers each response in a `TURN` block:
   - `FIX` → `ACCEPT` when the edit closes the finding (→ `FIXED`), or `CHALLENGE` naming the
     line of `findings.md` that still fails (→ the lead's next turn).
   - `MAINTAIN` → `ACCEPT` (→ `WITHDRAWN`) or `CHALLENGE` with new evidence (→ the lead's
     next turn).
   - `OUTSIDE_RUN` → `ACCEPT` carrying `outside_run: <question>` (both sides say it →
     `ESCALATED` with the critic's `outside_run` question, no judge), or `CHALLENGE` with new
     evidence (→ the lead's next turn).

   The lead's next turn is the turn message to the lead and its reply another `REBUTTAL` block
   for the still-open ids; a `FIX` is applied before that reply too. The evidence gate,
   `peer_added_evidence`, exhaustion and the 8-turn cap per side are § Debate rules'; the lead
   rates the critic's turns from its second turn on. A finding is stalemated when both sides
   are exhausted or the cap is hit. Turns are for `blocker` / `major` only: on a `minor` /
   `nit` or a `CONTESTED` finding only a `FIX` is re-checked, once (`ACCEPT` → `FIXED`;
   anything else leaves the cross-examination state, the lead's response recorded).

   Findings a critic `added` in cross-examination are ruled on by every other critic in its
   re-check message (the cross-examination message reused for them, as `adversarial-review.md`
   § A round step 2 does; a critic with no re-check pending gets a cross-examination message),
   tallied the same way, and go to the lead in its next turn message, or in a critique message
   of their own when no turn is pending.
5. **Judge.** For every stalemated `blocker` / `major`, a fresh `research-judge` with the judge
   capsule (several in one message when there are several). It rules `UPHELD | REFUTED |
   OUTSIDE_RUN` (`question` required with `OUTSIDE_RUN`). Then the judge-ruling message, one
   turn for the side the ruling went against: on `OUTSIDE_RUN` both sides; on `UPHELD` the
   lead, with the critic receiving the ruling for information only (no reply expected); on
   `REFUTED` the critic, with the lead receiving it for information only:

   | Ruling | The critic accepts with | The lead accepts with | A challenge is |
   |---|---|---|---|
   | `UPHELD` | — (ruled for it) | `FIX` | the lead's `MAINTAIN` / `OUTSIDE_RUN` |
   | `REFUTED` | `ACCEPT` | — (ruled for it) | the critic's `CHALLENGE` |
   | `OUTSIDE_RUN` | `ACCEPT` | `OUTSIDE_RUN`, or `FIX` (concedes) | `CHALLENGE` / `MAINTAIN` |

   Every challenge carries new evidence. No challenge → resolved per the ruling: `UPHELD` →
   the lead's `FIX`, re-checked once by the critic (`ACCEPT` → `FIXED`, `CHALLENGE` →
   `STALEMATE`); `REFUTED` → `REFUTED`. A `FIX` on an `OUTSIDE_RUN` ruling is re-checked once
   like an `UPHELD` `FIX` (`ACCEPT` → `FIXED`); only an unfixed, unchallenged `OUTSIDE_RUN`
   becomes `ESCALATED`, with the judge's question.
   A challenge → one judge reply (`SendMessage` to the judge's id), then the challenging side
   gets it and one more turn: accepting resolves per the ruling; a second challenge is
   `STALEMATE`, no content check. An upheld finding the lead rejects twice therefore ends
   `STALEMATE`, recorded and reported to the owner.
6. **Synthesis.** Merge duplicates (a `same_as` ruling, or § Dry loop's sameness rule within the
   round) under the lowest id at the stricter severity, recording `dup:`. Append the round's
   synthesis table to `critique.md` (every finding, its end state, its severity, the chain of
   message references) and rewrite the state block. End states:

   | State | Meaning |
   |---|---|
   | `FIXED` | the lead's edit was accepted by the finding's critic |
   | `AGREED` | valid; `minor` / `nit` (left as a note), or any severity when there is no author to fix it (listed for the owner) |
   | `WITHDRAWN` | the critic conceded, or accepted the other side's evidence |
   | `REFUTED` | the judge refuted it and nobody overturned that |
   | `ESCALATED` | reduced to one question outside the run (the judge's, else the critic's `outside_run`) |
   | `STALEMATE` | the ladder ran out, or `reason: agent ceiling` |
   | `CONTESTED` | `minor` / `nit` not settled in cross-examination |

   `ESCALATED` and `STALEMATE` are **`disputed`**: each gets a `disputed:` entry with its
   question (the judge's `question` when a judge ruled, else the critic's `outside_run`
   question, else "which side holds on <id>?" with both final positions attached).
7. **Next round or close.** § Dry loop decides whether a further round runs; when none does,
   § Closing the run.

### Rebuttal

The lead's `REBUTTAL` block carries one entry per `AGREED` or open finding the message
carried (an entry for a `CONTESTED` one is optional):

- **`FIX`** is applied **before** the lead replies: the edit is in `findings.md`, in place per
  the template's supersede rule, with a Log line, so the critics re-check the file, not a
  promise. `edit` says what changed in one line; `new_evidence: none`. A `FIX` that needs new
  evidence may re-dispatch a teammate (`redispatch`) within that teammate's round cap and the
  lead's share of `max_agents`, and the rebuttal waits for its report. A `FIX` whose evidence
  is out of reach (a cap or the share exhausted) moves the claim to Open, naming the gap, and
  says so in `edit`: a claim is never dropped silently.
- **`MAINTAIN`** is the lead's turn in the debate: `new_evidence` is required and is never
  `none` (a pin, a marker, a quote check, a script and its output).
- **`OUTSIDE_RUN`** is `outside_repo` renamed: the answer is something no artefact of the run
  holds (a capture nobody ran, prod state, product intent). `question` is required: the one
  thing only the owner can settle.

Nothing but a `FIX` edits `findings.md`, and only the lead makes it; the orchestrator never
edits it.

### Dry loop

`K` is `knobs.dry`; the rules are `thoroughness.md § Dry rounds`, with the critique's own
sameness rule.

- `K = 0`: exactly one round; the report says "one round, `K = 0`", never "ended dry".
- **Duplicate.** Two critique findings are the same when they share `target` and either the
  same `kind` or 60 % of `claim` words shared (lowercased, whitespace collapsed), so quoting a
  different sentence of the same Finding does not read as new. There is no line component:
  targets are section references.
- **New finding**: not a duplicate of any earlier round's finding, at any severity, and it
  survives its cross-examination (any end state but `WITHDRAWN` or `REFUTED`).
- **Dry round.** Any round with no new finding is dry, round 1 included, and increments
  `dry_streak`; a round with a new finding resets it to 0.
- **Further rounds.** With `K > 0`, after any non-dry round, or after a dry round while
  `dry_streak < K`, a further round runs: a whole round (steps 1–6, rebuttal included) with
  **fresh** critics on the current `findings.md`, angles rotated; earlier rounds' findings are
  never sent to them (the case file keeps them for the sameness rule). `dry_rounds` counts
  further rounds and is incremented when one is dispatched, before its hunt.
- **End.** After each round's synthesis: `dry_streak` reaching `K` → the critique ended dry;
  otherwise `dry_rounds` reaching its hard cap of `2K` further rounds → it ends, and the report
  says the loop was **cut at its cap**, not dry; otherwise a further round (subject to the
  ceiling). The critique therefore runs at most `1 + 2K` rounds. The reserve
  (`guides/thoroughness.md § Agent ceiling`) covers the shortest path to a dry end whether
  round 1 is dry or not; rounds past it run on what the lead left of the ceiling and are cut
  at the agent ceiling when they do not fit.

### Closing the run

8. **"Critique settled"** goes to the lead (`SendMessage`) with the final table and the
   `disputed:` entries, after the orchestrator writes `settled: true` in the state block. The
   lead:
   - writes **`## Critique`** in `findings.md`: the template's checked-claim table, one row per
     finding (`Claim (quoted) | Verdict | Severity | Evidence`, verdict = its end state), or
     `no findings` when no round raised one, plus one line naming `critique.md`;
   - adds a `disputed` Open row per `ESCALATED` / `STALEMATE` finding, in one fixed shape the
     resume and the report find it by:
     `disputed <id>: <question> — critic: <one line> — lead: <one line>`;
   - rewrites Answer and Next if any `FIXED` finding touched them (confidence line included),
     bumps `updated`, adds a Log line;
   - then, and only then, writes the Confluence draft, so a draft never carries a superseded
     claim;
   - returns its final status block with `critique: {rounds, findings, fixed, agreed,
     withdrawn, refuted, disputed}`.

   **Status at close.** With the critique on, the lead's first return writes the frontmatter
   status as `open` whatever the token it returns; `settled` is written only at the finish. At
   the finish the status is re-derived as in the lead's step 7 against the edited file:
   a load-bearing claim moved to Open makes it `PARTIAL`. A `disputed` `blocker` or `major` is
   a claim the Answer or Next may turn on that only the owner can settle: the lead returns
   `AWAITING_HUMAN` with `action: "answer the disputed questions in Open (<ids>)"` and
   frontmatter `status: open`, never `settled` (framing cites `settled` runs instead of
   re-investigating, and `/planner` takes Next from them). The owner answers in chat;
   `/research --resume` sends "done: <answers>" to the lead, which records them as Decisions
   rows, closes or supersedes the findings, and finishes: `ANSWERED` → `settled`, or
   `PARTIAL` → `open` if a question stays open. A `disputed` `minor` / `nit` does not change
   the status; its row remains. A critique with no findings does not change it either.
9. **Report.** `/research` shows the lead's final block, Answer, Next, the critique table and
   every `disputed` question on its own line, then the Confluence draft line, and says whether
   the loop ended dry, was cut at its cap, was cut at the agent ceiling, or ran one round
   (`K = 0`).

**Start, restart, resume.** A critique starts only when no `critique.md` exists for the run
(§ Standalone writes a new file of its own). `--resume` on a run whose `critique.md` says
`settled: true` never starts or restarts a critique: the "done: <answers>" resume after a
disputed close only finishes the lead. With `settled: false` it restarts the current round
with fresh critics (§ Case file, Resume).

**If the lead cannot be resumed** (the session that ran it ended, `SendMessage` fails):
`critique.md` records `rebuttal: unavailable` and no `findings.md` edit happens. From then on
the critique runs without an author, as `adversarial-review.md` § A round steps 4–5 among the
critics: an open `blocker` / `major` (majority `FALSE_POSITIVE`, or no majority) goes through
turns between its critic and its **designated challenger**, the lowest-letter critic that
ruled `FALSE_POSITIVE`, else `UNCLEAR` (turn message and turn reply, § Debate rules), then a
stalemated one goes up the judge ladder (judge capsule; the judge-ruling message to both
critics). Nothing can be fixed: an `AGREED` finding of any severity stays `AGREED`, an
`UPHELD` one resolves to `AGREED`, a `REFUTED` one to `REFUTED`, and a judge `OUTSIDE_RUN`
(→ `ESCALATED`) or a `STALEMATE` becomes a `disputed` question for the owner. At the end the
orchestrator writes `settled: true`. The report shows the critique table, every `AGREED`
`blocker` / `major` and every `disputed` question beside the untouched Answer, with one line
saying the author never answered; the owner reads both. No fresh lead is started for an
existing run (§ Flow and roles, "The lead itself").

### Case file

`<investigation folder>/critique.md`, written by the main session only: the
**second main-session file** in the folder, next to `lead.txt` (§ Flow and roles, "Single
writer").
Critics and judges get its path for reference and never read it. The first fenced block is the
state block, rewritten at every round boundary:

```yaml
state:
  critique_round: <N>                     # the current round
  dry_rounds: 0                           # further rounds dispatched (cap 2K)
  dry_streak: 0                           # consecutive dry rounds, round 1 included
  settled: false                          # true at "critique settled" (no lead: at the end)
  dispatched: <n>                         # the run's dispatches so far (§ Critique, ceiling)
  knobs: {…}                              # as resolved by /research, never re-resolved
  rebuttal: lead | unavailable | not needed
  critics: {A: <agent id>, B: <agent id>} # the current round's
  findings:
    - {id: r1-A1, dup: r1-B2, severity: major, target: "#3", state: FIXED, issue: <one line>}
    - {id: r1-B1, severity: blocker, target: Answer, state: STALEMATE, issue: <one line>}
  disputed:
    - {id: r1-B1, question: <one line>}
```

Then, per round, verbatim appends under `## Round N`: `### Hunt A|B|C` (one per critic),
`### Cross-examination`, `### Rebuttal`, `### Re-check` (every later turn too),
`### Judge <id>` (capsule summary, ruling, both turns, the reply), `### Synthesis` (the
table, then the loop's decision). Every block is appended as its author wrote it.

**Resume.** A critique starts only when the run has no `critique.md`. With `settled: true` it
is never started or restarted again; with `settled: false` it restarts its current round with
fresh critics from the state block; mid-round debate state is never restored (as
`adversarial-review.md` § Resume).
The abandoned attempt's critics stay counted in `dispatched`; its findings stay in the state
block with `state: SUPERSEDED`, and the restart's ids take the next letter suffix (`r2b-A1`).

### Standalone

`/research --critique <investigation-folder>` is the no-lead path as a kept entry point: the
critique alone on an existing folder, whatever its status, with the owner as the author. It is
how a past run, or a report another team or model wrote, gets checked
(`research-discipline.md` § 5: reports from other teams are claim sets), and the only way a
critique starts on a run whose lead is gone. It takes the same knobs, `dispatched` starts at 0,
and it writes `critique.md` in that folder (`critique-2.md` on collision) with
`rebuttal: unavailable`. It **never edits** `findings.md`. The report is the critique table and
the `disputed` questions; what to change in the file is the owner's. `--resume` on a finished
run never starts a critique; it resumes the lead, as today.

## Tool boundaries and lint

| Agent | Read/Grep/Glob | Write/Edit | Bash | Agent | Other |
|---|:-:|:-:|:-:|:-:|---|
| research-lead | Read only (no Grep/Glob: search = `git grep` at a pinned SHA, else `searcher`) | ✅ findings.md (`Edit` only), run-log.md | read-only git | ✅ team only | SendMessage (resume a paused or failed teammate), WebFetch (spot-check cited URLs), Confluence reads + **draft-only** create/update (frontmatter hook `confluence-draft-gate.sh`) |
| incident-investigator | ✅ | ✅ capture.md, evidence-*.md | read-only | ✅ repro-driver only | error-tracker reads (Sentry: 5 direct + gated gateway), session-replay reads, issue-tracker reads, SendMessage (resume its driver) |
| repro-driver | ✅ | — | `ss`, `ps` only (never starts a server) | — | chrome-devtools |
| searcher | ✅ | — | — | — | — |
| web-reader | — | — | — | — | WebFetch, WebSearch; Stop hook `quote-verify-gate.sh` in its frontmatter |
| designer | ✅ | ✅ `design/` only | — | — | chrome-devtools subset; `Artifact` only with the owner's approval |
| writer | ✅ | — | — | — | — |
| research-critic | Read only (no Grep/Glob) | — | read-only git, scratchpad scripts, `verify-quote.sh` (gated by `review-bash-gate.sh`) | — | WebFetch (re-read a cited URL); no SendMessage |
| research-judge | Read only (no Grep/Glob) | — | read-only git, scratchpad scripts, `verify-quote.sh` (gated by `review-bash-gate.sh`) | — | WebFetch (re-read a cited URL); no SendMessage |

Model pins (2026-10-14; the lint compares each agent's `model:` line to this table):

| Agent | Model |
|---|---|
| research-lead, incident-investigator, designer, writer, research-critic, research-judge | `claude-opus-5-5` |
| searcher, web-reader | `claude-haiku-5-5` (locate / quote only; the lead interprets) |
| repro-driver | `claude-sonnet-5-5` |

Only the tool list is mechanical. Which agent types may be dispatched, and which paths may be
written, are prose rules.

**harness-check.sh §5b:**

1. Status tokens appear in both `research-workflow.md` and the agent file (`AWAITING_HUMAN` /
   research-lead, `DIAGNOSED` / investigator, `REPRODUCED` / repro-driver, `FOUND` / searcher,
   `GATHERED` / web-reader, `CANVAS_READY` / designer, `COPY_READY` / writer, `FINDINGS` /
   research-critic, `UPHELD` / research-judge). An agent still carrying the STUB banner prints
   `SKIP (stub)`.
2. `positive_control` appears in `searcher.md` and `repro-driver.md` (same stub skip).
3. Tool boundaries, from each `tools:` frontmatter line, stubs included: only research-lead and
   incident-investigator have `Agent`; only they and designer have `Write` or `Edit`; searcher,
   writer, web-reader and designer have no `Bash`; research-lead has `WebFetch` and no
   `Grep`/`Glob` (it searches via `searcher` or pinned `git grep`); research-critic and
   research-judge have `Bash` and `WebFetch` and no `Agent`, `Write`, `Edit`, `Grep`, `Glob` or
   `SendMessage` (their Bash is gated, so they are not in the no-`Bash` list; §5i pins their
   exact tool line). A `*` wildcard in any tool list fails. No agent has Atlassian
   `executeWrite`/`executeDestructive`; only research-lead has the Confluence create/update
   tools, and then its frontmatter must register `confluence-draft-gate.sh` (whose allow/deny
   matrix is §2d).
4. Model pins match the table above, the critique's critic and judge included.
5. `ai-workflow.md` contains the pointer to `research-workflow.md`.

**§5c** (2026-10-16): `verify-quote.sh` and `quote-verify-gate.sh` offline matrices (`data:` URLs:
verbatim, markdown table/bold, one-word change, paraphrase, case, `!!js/function`, the 3-block
escape and its log line); web-reader's frontmatter registers the gate; `delegation.md` exists
and is indexed; both agents' descriptions name standalone dispatch.

## Open

- **Late reports** (deferred 2026-10-14): what happens to a teammate report that
  arrives after its dispatcher ended its turn is untested. Until it is, the rule in
  "Dispatch, iteration, routing" item 1 stands as written.
- **research-lead ran without `Grep` and stepped outside its Bash scope** (recorded 2026-10-16).
  **Decided (2026-10-16): option 2.** The lead has no Grep/Glob. It searches only with
  `git grep`/`git ls-files` at a pinned SHA, sends everything else to `searcher` in batched
  briefs, and treats a missing tool as a §6 stop. Linted by harness-check §5b. Why the tool was
  missing at runtime is still unknown; the history follows.
  - In a 2026-10-16 run (its `run-log.md`), the lead
    reported "the Grep tool is not available in this session". It then ran read-only `grep`/`sed`
    via Bash over `node_modules/next`, outside its "read-only git" Bash scope above, and said so
    itself. *(read: the run log)*
  - This isn't a definition gap. `research-lead.md`'s `tools:` line lists `Grep` *(read)*. The
    tool was absent at runtime.
  - In the same run, the searcher reported using Grep *(read: run log)*. On 2026-10-16, a
    main session's own tool list had no `Grep` or `Glob` tool *(measured, in another session)*.
    So availability seems to differ by session or agent. Why is not known *(inferred)*.
  - The rule the lead broke is real either way: a boundary that the toolset can't support, met by
    exceeding the boundary rather than stopping. The options considered were:
    - widen the lead's Bash scope to read-only `grep`/`sed`;
    - have it dispatch `searcher` for any search (**chosen**);
    - treat a missing tool as `BLOCKED` (§6: stop and report).
  - harness-check reads `tools:` lines only, so it can't see runtime availability. It now lints
    that the lead's line has no Grep/Glob.
