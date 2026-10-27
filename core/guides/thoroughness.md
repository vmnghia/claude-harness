# Thoroughness — knob table, presets and the shared flags

How wide and how deep a run goes, chosen per run. Four knobs:

- **Width**: how many agents of one type run concurrently in one round or one brief, with
  singletons that never widen (§ Knob table, § Width semantics).
- **Dry rounds** (`K`): loop-until-dry. `K` consecutive rounds that add no new finding end a
  loop early (§ Dry rounds).
- **N-way cross-examination**: what width means for hunters and critics. Each of `N` agents
  rules on the findings of the other `N−1` (`adversarial-review.md` § Debate rules).
- **Effort presets** set every knob at once, under an **agent ceiling** (`--max-agents`) on the
  dispatches of one run (§ Presets, § Agent ceiling).

Consumers: `/adversarial-review`, `/feature-flow`, `/research`, `research-lead`,
`adversarial-reviewer` and `research-critic` (§ Angles only). Design:
`docs/2026-10-27-thoroughness-knobs-design.md` in the harness repo.

**Resolution happens once in the main session; a subagent receives numbers.** The command
resolves the knobs (§ Input), writes them into the case file's state block or the run-log
header, and passes them in every capsule. A subagent never reads this guide or `project.md` to
size itself; a hunter or critic reads § Angles for its bucket order. It counts against the
numbers in its capsule.

**`standard` is today's size.** A run with no flag and no `project.md` key behaves exactly as it
did before this guide: two hunters per round, one gatherer per brief, `K = 0`.

## Knob table

Widths are **concurrent dispatches of one agent type in one round or one brief**. `quick` uses
the `standard` widths. A row with a reason in the last column never widens.

| Agent | `standard` | `thorough` | `exhaustive` | Singleton, why |
|---|---|---|---|---|
| `adversarial-reviewer` (hunters per round) | 2 | 3 | 5 | — |
| `research-critic` (critics per critique round) | 2 | 3 | 5 | — |
| `searcher` (per brief round) | 1 | 2 | 3 | — |
| `web-reader` (per brief round) | 1 | 2 | 3 | — |
| `writer` (per brief round) | 1 | 2 | 3 | — |
| `review-judge` | one per dispute | one per dispute | one per dispute | fresh per finding by design; disputes may run in parallel |
| `research-judge` | one per dispute | one per dispute | one per dispute | fresh per finding by design; disputes may run in parallel |
| `research-lead` | 1 | 1 | 1 | single writer of `findings.md` and `run-log.md` |
| `incident-investigator` | 1 | 1 | 1 | writes `capture.md` / `evidence-*.md`; owns the single repro-driver |
| `repro-driver` | 1 | 1 | 1 | one chrome-devtools profile (parked: a second driver needs profile partitioning and a lock) |
| `designer` | 1 | 1 | 1 | one chrome-devtools profile; `design/` |
| `coder` | 1 | 1 | 1 | persistent team-flow peer (parked: N coders need disjoint file ownership and a merge step) |
| `tester` | 1 | 1 | 1 | persistent team-flow peer (parked) |
| `reviewer` | 1 | 1 | 1 | persistent team-flow peer (parked) |
| `planner` | 1 | 1 | 1 | persistent team-flow peer (parked) |
| `runner` | n/a | n/a | n/a | delegation, not a team role |

**Hard ceiling: 8.** No width exceeds 8, whatever a flag or `project.md` says. At eight a hunter
already cross-examines seven peers; beyond it the dispatcher merges more reports than it can
read against each other. (The Workflow tool's own concurrency cap is `min(16, CPUs − 2)`.)
Hunter letters run `A`–`H` for the same reason: eight is the most there can be.

**Floors.** A hunter or critic width is at least 2: cross-examination needs a peer. A gatherer
width is at least 1.

**Singletons.** A `--width` (or `project.md` `"width"` key) on a row with a reason warns with
that reason and is ignored.

## Width semantics

Width means one of two things, depending on the kind of agent:

- **Hunters and critics: same brief, different angles.** All `N` agents get the same capsule
  and each covers everything; they differ only in what they look at first (§ Angles). Width
  `N` gives every finding `N−1` rulings in cross-examination.
- **Gatherers (`searcher`, `web-reader`, `writer`): partitioned briefs.** The dispatcher splits
  the target set (paths, source list, copy slots) and sends each part to one agent, all parts
  of a round in one message. The same brief is never sent twice: a duplicate dispatch doubles
  the merge and finds nothing new. A searcher brief is sized to its 50-hit cap, and that is the
  partition size: a target set that fits in fewer parts than the width uses fewer agents, and
  parts beyond the width wait for the next round. Width is a maximum for gatherers, never a
  quota.

## Counting

A round of parallel briefs to one teammate type counts once toward `--max-iter`; the width is the number of agents in that round.

- In `/adversarial-review` a round's hunters are one `review_iter`, as they always were.
- In `/research` two searchers fanned out in one message are one round of the searcher's cap,
  not two. `run-log.md` still records every dispatch with its agent id.
- In the team flow widths are 1, so nothing changes in practice.
- Every agent in a round is one dispatch toward `--max-agents` (§ Agent ceiling): iteration
  counts rounds, the ceiling counts agents.

## Presets

| | `quick` | `standard` | `thorough` | `exhaustive` |
|---|---|---|---|---|
| hunters / critics per round | 2 | 2 | 3 | 5 |
| gatherer width (searcher, web-reader, writer) | 1 | 1 | 2 | 3 |
| `K` (dry rounds) | 0 | 0 | 1 | 3 |
| adversarial cap: `--max-iter` in `/adversarial-review` | 1 | 3 | 5 | 8 |
| adversarial cap: `--max-gate-iter` in `/feature-flow` | 1 | 2 | 3 | 5 |
| research critique | off | on | on | on |
| `--max-agents` default | 12 | 24 | 48 | 64 |

`exhaustive` (owner, 2026-10-27) is for a deep run on a very complex topic where spend is not the
constraint.

The preset drives the **adversarial** cap only, wherever it lives: `review_iter` in
`/adversarial-review`, `gate_iter` in `/feature-flow`. `/feature-flow`'s own `--max-iter` (the
Tester/Reviewer loop) and `/research`'s `--max-iter` keep their own defaults; the team protocol is
not a knob. The research critique row is consumed by the research critique.

## Agent ceiling

`max_agents` is the ceiling on dispatches in one run. It is an agent count, not a token budget:
the `Agent` tool exposes no per-agent token figure to the dispatcher, and a count is the one
thing every orchestrator and the lead already track in their run logs. A count is a loose proxy
(one hunter on a wide diff costs ten times a searcher), so the ceiling is a brake, not a budget.

- **Counts:** every fresh `Agent` dispatch of the run: hunters, critics, judges, gatherers,
  teammates. A fresh dispatch that replaces a failed resume counts.
- **Free:** a resume through `SendMessage`.
- **Fits:** a dispatch of `n` agents fits when `dispatched + n ≤ max_agents`, where
  `dispatched` is the run's count so far. For a round of hunters or critics `n` is the whole
  width; for gatherers it is the parts the round will actually dispatch (gatherer width is a
  maximum, § Width semantics); a judge or a teammate is 1. A round that does not fit is not
  started: nothing is dispatched partially.
- **Mid-round:** the orchestrator finishes the round with what resumes allow (a `SendMessage` is
  free). A judge it can no longer dispatch leaves its finding `STALEMATE` with
  `reason: agent ceiling`. Then the exit check runs. It never stops with findings in mid-debate.
- **The recap says so:** a run ended by the ceiling reads "cut at the agent ceiling".

**Status at the ceiling: the last exit check decides.** There is no new status token. In
`/adversarial-review` and the `/feature-flow` gate, the last exit check's result stands
(`APPROVED`, `NEEDS_OWNER`, `REVIEWED`), except where it calls for another round that does not
fit:

- the next round would verify a fix (the exit check found an `AGREED` `blocker`/`major`,
  including one left by a round the ceiling stopped mid-way) → `REVIEW_LIMIT_REACHED`. The
  orchestrator does not dispatch a fix it cannot verify: Coder goes out only when Coder and the
  next round both fit;
- the next round would be a dry-check round (the exit check was clean) → `APPROVED`, and the
  recap says the **dry loop was cut at the agent ceiling**, as it does at the `2K` cap.

A round that does not fit is not started; the lead records the gap under Open, naming the
ceiling, and goes `PARTIAL`, exactly as it does at a teammate's cap.

The 48 of `thorough` is the session's own Workflow guideline ("keep workflows under 50 agents").
At `exhaustive` the arithmetic runs the other way: `K = 3` allows 6 dry-check rounds, so a
worst-case adversarial run is 15 rounds × 5 hunters, and the 64 ceiling, not `K`, ends it.

**One ceiling, three dispatchers (`/research`).** Before the lead is dispatched, `/research`
reserves the critique's share: `critic width × (K + 1)` critic dispatches plus `critic width`
judges. The remainder is the lead's `max_agents`, written in its capsule and the run-log header.
The lead counts every team dispatch against it, including the investigator's fresh repro-driver
dispatches (one per `repro_agent_id` it reports; a resume is not one). After the lead returns,
`/research` reads `dispatches[]`, and the critique counts against what is left of the whole
ceiling, so an under-spent lead leaves more room, never less. At `exhaustive`, 64 leaves the lead
39 after the critique's reserve (5 critics × 4 rounds + 5 judges). Until the research critique
lands, `/research` passes the whole ceiling to the lead; the reserve below is the critique plan's
to subtract.

## Input

Each command's § Input points here instead of repeating this.

**Flags**, shared by `/adversarial-review`, `/feature-flow` and `/research`:

- `--effort=quick|standard|thorough|exhaustive`: the preset.
- `--width=<agent>:<n>[,<agent>:<n>…]`: the width of one or more agent types, named as in
  § Knob table (`--width=searcher:2,web-reader:2`).
- `--dry=K`: dry rounds, a non-negative integer.
- `--max-agents=N`: the agent ceiling, a positive integer.

The adversarial cap flags (`--max-iter` in `/adversarial-review`, `--max-gate-iter` in
`/feature-flow`) stay in each command's § Input; they are single values in the sense below.

**`project.md`.** The `json harness` block takes an optional `"thoroughness"` object:

```json
"thoroughness": {"preset": "standard", "width": {"searcher": 2}, "dry_rounds": 0, "max_agents": 24}
```

Every key is optional; an absent key means the next layer decides. The main session reads the
block the way `hooks/lib/project-config.js` does.

**Precedence: by layer, then by specificity.** A run flag beats `project.md`, which beats this
guide. Within one layer a single value (`--width`, `--dry`, `--max-agents`, the adversarial cap
flag; a `project.md` key) beats that layer's preset (`--effort`; `project.md` `"preset"`). For
each knob, the first of these that is set wins:

1. a single-value flag;
2. `--effort`;
3. a `project.md` `"thoroughness"` key;
4. `project.md` `"preset"`;
5. this guide's `standard`.

So `--effort=quick` on the command line beats a `project.md` `"max_agents": 48` (the run gets 12),
and a `project.md` `"width": {"searcher": 2}` beats its own `"preset"`.

**Invalid values warn and fall back**, in the style of `--max-iter`: the warning names the flag
and the value used, and resolution continues with the next layer.

- An unknown `--effort` value: warn `--effort=<value> ignored, using <preset>` and use the
  next layer's preset.
- A width above 8: warn `--width=<agent>:<n> above 8, using 8` and use 8.
- A width below its floor, a non-integer, or an agent not in § Knob table: warn and ignore that
  pair.
- A `--width` on a singleton warns with the reason from the table and is ignored:
  `--width=<agent>:<n> ignored: <reason>`.
- A `--dry` that is not a non-negative integer, or a `--max-agents` that is not a positive
  integer: warn `--<flag> ignored, using <value>` and use the next layer's value.

The same rules apply to `project.md` values, with the warning naming the key.

**The resolved knobs** go into the case file's state block and `run-log.md`'s header, so a resume
uses the same sizes and never re-resolves. Shape (all non-singleton widths, always present):

```yaml
knobs: {effort: standard, width: {adversarial-reviewer: 2, searcher: 1, web-reader: 1, writer: 1, research-critic: 2}, dry: 0, max_iter: 3, max_agents: 24}
```

`effort` is the preset resolution started from; `dry` is `K`, the setting (§ Dry rounds tells
it apart from the state block's `dry_rounds` count); `max_iter` is the cap of the
command's own loop: `review_iter` in `/adversarial-review`, `gate_iter` in `/feature-flow`, the
per-teammate round cap in `/research`.

## Angles

A hunter works through every playbook bucket (`adversarial-review.md` § Playbook); its angle
only sets the order it starts in. Four angles:

| Angle | Bucket order |
|---|---|
| `inside-out` | Error paths → Config values → Time and ordering → Guards → Unbounded repeated work → then Consumers, Claims, Scope |
| `outside-in` | Consumers and surroundings → Claims the code does not keep → Scope → Unbounded repeated work → then Error paths, Config values, Time and ordering, Guards |
| `time-and-config` | Time and ordering → Config values → Unbounded repeated work → then the rest |
| `claims-and-consumers` | Claims the code does not keep → Consumers and surroundings → Guards → then the rest |

Roles run `hunter-A` … `hunter-H`, lettered in dispatch order. In a round the `n`-th hunter takes
the `n`-th angle in the table's order: `hunter-A` `inside-out`, `hunter-B` `outside-in`,
`hunter-C` `time-and-config`, `hunter-D` `claims-and-consumers`. Above four the angles cycle:
`hunter-E` starts `inside-out` again, and so on to `hunter-H`.

**Rotation in a dry-check round.** The first hunter starts at the angle after the last one the
previous round used, and the rest follow in table order, cycling. Below width 4 the first hunter
therefore starts from an angle no hunter of the previous round had (2 hunters: `hunter-A`
`time-and-config`, `hunter-B` `claims-and-consumers`).

`research-critic` angles belong to the research critique; they cycle by the same rule.

## Delta and probed

Fix-introduced code is a fresh diff, at every width. Code a fix added has never been hunted.

**The delta.** After a fix, the next round's hunt capsule carries `delta:`: Coder's
`changed_files` plus the hunks that differ between the previous round's tree and this one. The
orchestrator keeps, under `.claude/runs/<case-file stem>/r<N>/` (`adversarial-review.md` § The
loop step 5), the previous round's `git diff <base>` and, for every
path from `git ls-files --others --exclude-standard`, the path and its `sha256sum`: the inputs
of the tree hash (`adversarial-review.md` § Case file), kept per file instead of hashed
together. The delta is:

- Coder's `changed_files`;
- every file whose hunks differ between the previous round's `git diff <base>` and this one;
- every untracked file that is new since the previous round or whose `sha256sum` changed, as a
  whole-file delta. An edit to an existing untracked file reaches the delta this way, without
  relying on Coder's self-reported `changed_files`.

A round that follows no fix (the first round, a dry-check round) carries `delta: none`.

**Hunters cover every playbook bucket on the delta first**, then the rest of the diff.

**`probed[]`.** The hunt reply carries one entry per delta file where the hunter reports no
finding, naming the buckets tried and the trigger that did not fire:

```yaml
probed:
  - {file: <path>, buckets: [<playbook bucket names>], tried: <one line>}
```

- A hunt reply with a delta and no `probed[]` entry for a delta file it has no finding on is
  incomplete. The orchestrator sends it back once, before cross-examination: "Name what you
  probed in <file>." A reply still missing entries after the send-back goes on to
  cross-examination, and its missing delta files count as uncovered by that hunter.
- A `CLEAN` hunt reply in a round with a delta requires a `probed[]` entry for every delta
  file. A `CLEAN` reply still missing entries after the send-back does not count as `CLEAN` for
  the exit check: it is recorded as `CLEAN (unprobed: <files>)` and treated as a hunt that found
  nothing on the rest of the diff, with the delta files unprobed by it. The recap lists every
  uncovered delta file.
- **A round with an uncovered delta file cannot exit `APPROVED`.** A delta file is uncovered
  when no hunter of the round has a finding on it or a `probed[]` entry for it. The
  orchestrator dispatches one more dry-check round whose capsule names the uncovered files as
  its delta; that round does not count toward `2K` and never increments `review_iter`. A file
  still uncovered after it ends the review `NEEDS_OWNER` with one question per file:
  "nobody probed <file> after the fix; review it by hand". No new status token.

This is `research-discipline.md` § 3 applied to a review: a null needs proof the probe ran.

## Dry rounds

`K` is the number of consecutive **dry rounds** that end a loop early. A round is dry when it
adds no **new finding**.

Three names, two things: `--dry`, `project.md` `"dry_rounds"` and `knobs.dry` are `K`, the
setting; the state block's `dry_rounds` is the count of dry-check rounds dispatched so far
(incremented at dispatch; a `round_kind: probe` round is not one).

A **new finding** is one that is not a duplicate of any earlier round's finding, at **any**
severity, by the breaker's sameness rule (same `file`, lines within 5, 60 % of `issue` words
shared), **and** that survives its cross-examination: any end state but `WITHDRAWN` or
`REFUTED`. A finding that died in cross-examination was never added. There is no severity floor:
a floor at `major` would have called dry the round that missed a defect graded low.

**In `/adversarial-review` and the `/feature-flow` gate:**

- With `K > 0`, a round whose exit would be `APPROVED` starts a **dry-check round** instead:
  fresh hunters, same tree, angles rotated (§ Angles).
- A new finding resets the dry counter; a new `blocker`/`major` re-enters the fix loop as usual.
- `K` consecutive dry rounds → `APPROVED`.
- Dry-check rounds never increment `review_iter` (nothing was fixed). They have their own count,
  `dry_rounds`, in the state block, with a **hard cap of `2K` per run**: fresh hunters on an
  unchanged tree can keep producing never-seen nits. At the cap the review ends `APPROVED`, and
  the recap says the dry loop was **cut at its cap**, not dry.
- The total number of rounds is bounded by `(max_iter + 1) + 2K`.
- `--no-fix` never dispatches Coder but keeps dry-check rounds: catching what a "clean" verdict
  missed must not depend on fixing anything.

**In `/research`** the dry loop is the critique's loop: a critique round that raises no new
finding is dry. Gathering does not loop on `K`: the lead's hypotheses, not a counter, decide when
gathering is done.
