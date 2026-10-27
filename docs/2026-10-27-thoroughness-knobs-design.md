# Thoroughness knobs: width, dry rounds, N-way cross-examination, effort presets

Status: draft for the owner, 2026-10-27. Builder check done.

## Intent

Every team in the harness runs at a fixed size: two hunters per round, one searcher or
web-reader per brief, one round of review unless a `blocker`/`major` forces another. The size
is baked into the guides, not chosen per run. The owner wants it to be a setting: wider when a
question is urgent or a diff is risky, narrower when cheap is fine, and with the patterns the
Workflow tool popularised (loop-until-dry, refuter voting, a budget that sizes the fleet)
available inside the harness's own flows, where the agents are persistent and the resume
protocol lives.

This design adds four knobs to the harness, applied to `/adversarial-review`, the `/feature-flow`
gate and `/research` (the research **critique** that consumes them is a separate design,
`2026-10-27-research-critique-design.md`).

## Evidence

- **The gate's one known miss (a two-round adversarial review, case file of 2026-10-25,
  read 2026-10-27).** After the gate approved the diff, a human reviewer raised three points.
  Two were already in the case file, agreed at `minor`/`nit` and left by plan. The third, an
  alert whose time window counted idle time from the first failure (two transient failures an
  hour apart read as an hour-long outage), was missed, and the shape of the miss is the
  lesson: that logic did not exist in round 1. Coder **added** it in response to a round-1
  finding, and round 2's hunt summary called the new episode logic "clean" without naming
  anything it had tried. Fix-introduced code got one pass and an unprobed null. The playbook's
  *Time and ordering* bucket covers exactly that defect.
- **Workflow is absent inside subagents (measured 2026-10-27).** A general-purpose subagent
  dispatched from this session listed its tools: `Agent`, `SendMessage`, `Monitor`, `TaskStop`
  present; `Workflow` neither loaded nor deferred (`ToolSearch select:Workflow` → "No matching
  deferred tools found"). Only the main session can run a workflow, and its agents are one-shot:
  no `SendMessage` resume, no `AWAITING_HUMAN` round-trip. The lead and the investigator can
  only ever fan out through `Agent`.
- **Cost is a live constraint.** Research and team-flow runs have been cut off by the usage
  limit more than once (the 2026-10-19 team-flow run waited for the 12:00 UTC reset; the first
  research run lost all six agents to a 429). Today's sizes must stay the default.
- **The harness already has the pieces.** Parallel dispatch is "N `Agent` calls in one
  message" (`adversarial-review.md` § Procedure, `research-lead.md` step 2). The duplicate rule
  (`same file`, lines within 5, 60 % of `issue` words shared) exists in the circuit breaker. The
  positive-control rule for nulls is `research-discipline.md` § 3. The per-teammate counter is in
  `research-workflow.md` § Dispatch, iteration, routing item 2.

## Decisions (owner, 2026-10-27)

- **Build on the `Agent` tool.** Workflow is named in this document only as a main-session
  option for stateless sweeps, not used.
- **Four knobs:** width per agent type with singletons; loop-until-dry; refuter voting as
  N-way cross-examination; effort presets with an agent-count ceiling.
- **Parked, with the reason recorded:** coder width (N coders need disjoint file ownership and
  a merge step in `ai-workflow.md`, which is a protocol change, not a knob) and multiple
  repro-drivers (one chrome-devtools profile; a second driver needs profile partitioning and a
  lock). Both are a follow-up after the research run.
- **Research critique consumes these knobs** (critics have a width, the critique loop has a dry
  count); its design is separate.

## Builder's calls (veto-able)

### Today's size is the `standard` preset

Nothing changes for a run that passes no flag and whose `project.md` sets nothing. Every default
below reproduces current behaviour; `thorough` and `exhaustive` are where the new sizes live.

### The knob table

One table, in a new class-2 guide `guides/thoroughness.md`, read by `/adversarial-review`,
`/feature-flow`, `/research` and `research-lead`. Widths are **concurrent dispatches of one
agent type in one round or one brief**. Singletons carry their reason.

| Agent | `standard` | `thorough` | `exhaustive` | Singleton, why |
|---|---|---|---|---|
| `adversarial-reviewer` (hunters per round) | 2 | 3 | 5 | — |
| `research-critic` (critics per critique round) | 2 | 3 | 5 | — |
| `searcher` (per brief round) | 1 | 2 | 3 | — |
| `web-reader` (per brief round) | 1 | 2 | 3 | — |
| `writer` | 1 | 2 | 3 | — |
| `review-judge`, `research-judge` | one per dispute; disputes may run in parallel | | | fresh per finding by design |
| `research-lead` | 1 | 1 | 1 | single writer of `findings.md` and `run-log.md` |
| `incident-investigator` | 1 | 1 | 1 | writes `capture.md` / `evidence-*.md`; owns the single repro-driver |
| `repro-driver` | 1 | 1 | 1 | one chrome-devtools profile (parked) |
| `designer` | 1 | 1 | 1 | one chrome-devtools profile; `design/` |
| `coder`, `tester`, `reviewer`, `planner` | 1 | 1 | 1 | persistent team-flow peers (parked) |
| `runner` | n/a | n/a | n/a | delegation, not a team role |

A hard ceiling of **8** applies to every non-singleton width, whatever the flag says: at
eight a hunter already cross-examines seven peers, and beyond it the dispatcher merges more
reports than it can read against each other; the guide says so. (The Workflow tool's own
concurrency cap is `min(16, CPUs − 2)`.) A `--width` on a singleton is refused with the reason
from the table.

**What width means per kind of agent.** Two different things, and the guide says which:

- **Hunters and critics: same brief, different angles.** N agents cover everything; they differ
  in what they look at first. The playbook gains two more angles as bucket orderings:
  `inside-out` and `outside-in` as today, then `time-and-config` (*Time and ordering*, *Config
  values, limits and units*, *Unbounded repeated work* first) and `claims-and-consumers`
  (*Claims the code does not keep*, *Consumers and surroundings outside the diff*, *Guards that
  conflate error with legitimate state* first). Above four, the angles cycle: the fifth hunter
  starts `inside-out` again, and so on. Hunter letters run `A`–`H`.
- **Gatherers (searcher, web-reader, writer): partitioned briefs.** The dispatcher splits the
  target set (paths, source list, copy slots) and sends each part to one agent. The same brief
  is never sent twice: a duplicate dispatch doubles the merge and finds nothing new. The lead's
  existing rule "size a searcher brief to its 50-hit cap" becomes the partition size.

### Iteration counts rounds, width counts agents

Today `research-workflow.md` says "two searchers fanned out are dispatches 1 and 2 of the
searcher's cap", so width eats depth. The change: **a round of parallel briefs to one teammate
type counts once toward `--max-iter`**; the width is the number of agents in that round.
`run-log.md` still records every dispatch with its agent id, so nothing is lost. The same
sentence goes into `adversarial-review.md` (a round's hunters are one `review_iter`, as they
already are) and `ai-workflow.md` (unchanged in practice: team-flow widths are 1).

The agent-count ceiling (below) is the brake on width × depth.

### Loop-until-dry

`K` = the number of consecutive **dry rounds** that end a loop early. A round is **dry** when it
adds no finding that is not a duplicate of a finding from any earlier round, at **any**
severity, by the breaker's sameness rule (same `file`, lines within 5, 60 % of `issue` words).
A severity floor is deliberately absent: the known miss was graded low, and a floor at `major` would
have called that round dry.

- **`/adversarial-review` and the gate.** The loop today ends when a round's exit check finds
  no `AGREED` `blocker`/`major`. With `K > 0`, a round that would exit `APPROVED` instead starts
  a **dry-check round**: fresh hunters, same tree, angles rotated so the first hunter of the
  dry-check round starts from the angle no hunter of the previous round had. A **new finding**
  is one that is not a duplicate (sameness rule) of any earlier round's finding **and survives
  its cross-examination** (any end state but `WITHDRAWN` or `REFUTED`): a finding that died in
  cross-examination was never added. A new finding resets the dry counter; a new
  `blocker`/`major` re-enters the fix loop as usual. `K` consecutive dry rounds → `APPROVED`.
  Dry-check rounds do not increment `review_iter` (nothing was fixed); they have their own
  count, `dry_rounds`, in the state block, with a **hard cap of `2K` per run**: fresh hunters on
  an unchanged tree can keep producing never-seen nits, and without the cap only `--max-agents`
  would stop them. At the cap the review ends `APPROVED`, and the recap says the dry loop was
  cut at its cap, not dry. The total number of rounds is therefore bounded by
  `(max_iter + 1) + 2K`. `--no-fix` never dispatches Coder but **keeps dry-check rounds**:
  catching what a "clean" verdict missed must not depend on fixing anything.
- **Research.** Loop-until-dry is the critique's loop: a critique round that raises no new
  finding is dry (critique design § The loop). Gathering itself does not loop on `K`: the
  lead's hypotheses, not a counter, decide when gathering is done.
- **Default `K = 0` in `standard`** (today's loop), `K = 1` in `thorough`.

### Fix-introduced code is a fresh diff

This is the direct answer to the known miss (§ Evidence), and it applies at every width.

- After a fix, the hunt capsule of the next round carries a **delta**: Coder's `changed_files`
  and the hunks that differ between the previous round's tree and this one (the orchestrator
  keeps the previous `git diff <base>` in the scratchpad and diffs the two). Hunters cover every
  playbook bucket on the delta **before** the rest of the diff.
- The hunt reply gains `probed[]`: one entry per delta file with no finding, naming the buckets
  tried and the trigger that did not fire (`{file, buckets: [...], tried: <one line>}`). A hunt
  reply with a delta and no `probed[]` for a delta file is incomplete: the orchestrator sends
  it back once ("name what you probed in <file>") before cross-examination. This is
  `research-discipline.md` § 3 applied to a review: a null needs proof the probe ran.
- `CLEAN` on a round with a delta requires `probed[]` for every delta file.

### N-way cross-examination

Refuter voting, expressed in the protocol the harness already has, so that `N = 2` is exactly
today and nothing existing changes shape.

- **Cross-examination message.** Each hunter receives the findings of all `N−1` others in one
  message, grouped by hunter letter, and returns one `RULINGS` block covering all of them.
- **Tally.** For each finding, count the `N−1` rulings. Majority `VALID` at the asserter's
  severity → `AGREED`; a `same_as` ruling counts as `VALID` (independent discovery is the
  strongest vote) and merges at synthesis under the lowest id. Majority `FALSE_POSITIVE` →
  the finding goes to turns (for `blocker`/`major`) or to the asserter's one turn (for
  `minor`/`nit`), as today. No majority (`UNCLEAR` splits, or a tie at even `N−1`) → turns,
  as if challenged.
- **Turns are two-sided.** The asserter debates **one designated challenger**: the lowest
  hunter letter among those who ruled `FALSE_POSITIVE` (or `UNCLEAR`, when nobody ruled
  `FALSE_POSITIVE`). The other challengers' rulings are attached verbatim to the first turn
  message as evidence; they take no further turns. Exhaustion, the evidence gate, the safety
  cap and the judge ladder are unchanged: the judge gets the asserter's and the designated
  challenger's final positions.
- **Severity reconciliation** with `N` votes: the stricter severity among `AGREED` votes wins
  unless a re-grade was accepted in a turn, as today.
- The orchestrator still judges nothing: it counts enums and relays.

### Effort presets and the agent ceiling

Four presets set every knob at once; raw flags override single values. `exhaustive` (owner,
2026-10-27) is for a deep run on a very complex topic where spend is not the constraint.

| | `quick` | `standard` | `thorough` | `exhaustive` |
|---|---|---|---|---|
| hunters / critics per round | 2 | 2 | 3 | 5 |
| gatherer width (searcher, web-reader, writer) | 1 | 1 | 2 | 3 |
| `K` (dry rounds) | 0 | 0 | 1 | 3 |
| adversarial cap: `--max-iter` in `/adversarial-review` | 1 | 3 | 5 | 8 |
| adversarial cap: `--max-gate-iter` in `/feature-flow` | 1 | 2 | 3 | 5 |
| research critique | off | on | on | on |
| `--max-agents` default | 12 | 24 | 48 | 64 |

- The preset drives the **adversarial** cap only, wherever it lives: `review_iter` in
  `/adversarial-review`, `gate_iter` in `/feature-flow`. `/feature-flow`'s own `--max-iter`
  (the Tester/Reviewer loop) is untouched: the team protocol is a non-goal here.
- **`--max-agents=N`** is the ceiling on dispatches in one run (hunters, critics, judges,
  gatherers; resumes via `SendMessage` do not count, a fresh dispatch replacing a failed resume
  does). It is an agent count, not a token budget: the `Agent` tool exposes no per-agent token
  figure to the dispatcher, and a count is the one thing every orchestrator and the lead already
  track in their run logs. Named trade-off: a count is a loose proxy (one hunter on a wide diff
  costs ten times a searcher), so the ceiling is a brake, not a budget. Reaching it ends the
  run through the existing limit statuses (`REVIEW_LIMIT_REACHED`; the lead goes `PARTIAL` with
  an Open row naming the ceiling); no new status token. Reached **mid-round**, the orchestrator
  finishes the round with what resumes allow (a `SendMessage` is free), a judge it can no
  longer dispatch leaves its finding `STALEMATE` with `reason: agent ceiling`, and the exit
  check runs; it never stops with findings in mid-debate.
- The 48 anchor is the session's own Workflow guideline ("keep workflows under 50 agents").
  At `exhaustive` the arithmetic runs the other way: `K = 3` allows 6 dry-check rounds, so a
  worst-case adversarial run is 15 rounds × 5 hunters, and the 64 ceiling, not `K`, ends it;
  the recap says so ("cut at the agent ceiling"). For research, 64 leaves the lead roughly 39
  after the critique's reserve (5 critics × 4 rounds + 5 judges).
- `/adversarial-review`'s per-round cost line gains the width: "round 2 of ≤ 4, 3 hunters,
  about $N".

### Flags, `project.md`, resolution

Three layers, resolved **once, in the main session**, and passed to every subagent as numbers
in its capsule. A subagent never reads the knob table or `project.md` for this: the lead's
capsule says `width: {searcher: 2, web-reader: 2, writer: 1}`, `max_agents: 48`, and it counts
against those.

1. Guide defaults: the two tables above.
2. `project.md`'s `json harness` block gains an optional `"thoroughness"` object:
   `{"preset": "standard", "width": {"searcher": 2}, "dry_rounds": 0, "max_agents": 24}`. Any
   key may be absent; `hooks/lib/project-config.js` already parses the block, and the main
   session reads it the same way. Absent = guide default.
3. Per-run flags, shared by `/adversarial-review`, `/feature-flow` and `/research`:
   `--effort=quick|standard|thorough|exhaustive`, `--width=<agent>:<n>[,<agent>:<n>…]`, `--dry=K`,
   `--max-agents=N`. **Precedence by layer, then by specificity:** a run flag beats
   `project.md`, which beats the guide; within one layer a single value (`--width`, `--dry`,
   `--max-agents`, the adversarial cap flag; a `project.md` key) beats that layer's preset
   (`--effort`; `project.md` `preset`). So `--effort=quick` on the command line beats a
   `project.md` `"max_agents": 48` (the run gets 12), and a `project.md` `"width": {"searcher":
   2}` beats its own `"preset"`. An invalid value warns and falls back, in the style of
   `--max-iter`. The flag block is written once, in
   `guides/thoroughness.md` § Input, and each command's § Input points to it rather than
   repeating it.

The resolved knobs are written into the case file's state block (`knobs:`) and into
`run-log.md`'s header, so a resume uses the same sizes.

### Research-specific applications

- The lead's capsule carries the resolved widths; its step 2 partitions searcher and
  web-reader briefs to the width (never duplicates), dispatches them in one message, and counts
  the round once.
- The critique's width and `K` come from the same resolution; see the critique design.
- **One ceiling, three dispatchers.** `/research` reserves the critique's share up front:
  `critic width × (K + 1)` critic dispatches plus `critic width` judges, from the critique
  knobs. The remainder is the lead's `max_agents`, written in its capsule and the run-log
  header. The lead counts every team dispatch against it, including the investigator's fresh
  repro-driver dispatches (one per `repro_agent_id` it reports; a resume is not one). After the
  lead returns, `/research` reads `dispatches[]`, and the critique counts against what is
  left of the whole ceiling, so an under-spent lead leaves more room, never less.

### Harness bookkeeping

- `guides/thoroughness.md` (class 2) with the knob table, the presets, the flag block, the
  angle list, the width semantics, the delta rule and the `probed[]` shape. Consumers listed in
  `CLAUDE.md` § Guides.
- `adversarial-review.md`: § Procedure gains the dry-check round, the delta in the hunt capsule,
  `probed[]` in the hunt reply, the N-way tally and the designated challenger; § Case file's state
  block gains `knobs:` and `dry_rounds:`; § Starting angles lists four.
- `adversarial-reviewer.md`: four angles, cycling above four; `probed[]`; letters `A`–`H`.
- `commands/adversarial-review.md`, `commands/feature-flow.md`, `commands/research.md`: § Input
  points at the shared flag block; the hunter dispatch says "N hunters in one message".
- `research-workflow.md` and `research-lead.md`: rounds-not-dispatches counting; partitioned
  width; `max_agents` in the capsule and the run-log header.
- `project-template/project.md`: the `"thoroughness"` key with its one-line explanation.
- `harness-check.sh`, new section **§5h** (5e–5g exist):
  1. the knob table lists every file in `core/agents/` exactly once, each row a width or a
     singleton with a non-empty reason;
  2. every command whose argument-hint mentions `--max-iter` or `--max-gate-iter` also
     mentions `--effort`;
  3. `research-workflow.md` and `adversarial-review.md` both contain the sentence that a round
     counts once toward `--max-iter`;
  4. `adversarial-reviewer.md` names all four angles and `probed`;
  5. `adversarial-review.md` § Message shapes has `probed` in the hunt reply and `knobs` in the
     state block.

### Verification plan

- `harness-check.sh` green after every file change.
- **Acceptance smoke, not a guarantee:** `/adversarial-review --effort=thorough` (3 hunters,
  `K = 1`) in a worktree of the project where the miss happened, at the tree the gate approved
  (before the human reviewer's fix), with the same base and context as the original run (the
  owner holds the refs, outside this repo). The
  question is whether any hunter or the dry-check round surfaces the idle-time defect in the
  publish-failure window that round 2 called clean. Expected cost: the original run was about $4 per round on a
  four-file diff; this diff is larger, so budget $15–25 for two rounds of three. A miss is
  recorded in the design's Verified section, not hidden; the delta/`probed[]` rule is exercised
  by the same run only if a fix round happens, so a second, cheaper check is a fixture diff with
  one planted defect in a "fix" hunk and `--no-fix` off.
- A `standard` run on the original adversarial-review fixture must produce the same case-file
  shape as before, plus the `knobs:` key: the no-flag path is a regression check.

## Non-goals

- Coder width and multiple repro-drivers (parked; see Decisions).
- Token budgets: not observable from the `Agent` tool.
- Adopting the Workflow tool for any flow: absent in subagents, one-shot agents.
- A hook that enforces width or the ceiling: a hook sees one tool call, not concurrency. Prose
  plus lint, like today's caps.
- Any change to the team-flow protocol (`ai-workflow.md` § Team protocol) beyond the one
  counting sentence.

## Left to the builder

- Exact bucket order for the two new angles, and the rotation rule for dry-check rounds.
- How the orchestrator stores the previous round's diff for the delta (scratchpad path naming).
- The exact grep patterns of §5h.
- Wording of the warnings for invalid flag values and refused singleton widths.
