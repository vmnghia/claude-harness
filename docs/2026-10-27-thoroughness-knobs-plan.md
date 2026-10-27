# Thoroughness knobs: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** four run-time knobs for the harness's teams, width per agent type with singletons,
loop-until-dry, N-way cross-examination and effort presets with an agent ceiling, built on the
`Agent` tool so that a run with no flag behaves exactly as today.

**Architecture:**
- One new class-2 guide, `core/guides/thoroughness.md`, is the single home of the knob table,
  the presets, the shared flag block and its precedence, the angle list, the width semantics,
  the delta/`probed[]` rule and the ceiling semantics. Commands and agents point at it; nothing
  repeats a number.
- `guides/adversarial-review.md` gains the N-way tally, the designated challenger, dry-check
  rounds, the delta in the hunt capsule and `probed[]` in the hunt reply. The research files
  gain rounds-not-dispatches counting, partitioned width and `max_agents`.
- Resolution happens once in the main session; subagents receive numbers in their capsule.
- `harness-check.sh` gains **§5h**, written red-first for every task: the lints are this
  plan's tests, since every deliverable is prose that an orchestrator or agent executes.

**Tech Stack:** Claude Code agent files, slash commands and guides (Markdown with YAML
frontmatter); bash for `harness-check.sh`; Node ≥18 for `hooks/lib/project-config.js`.

**Spec:** [2026-10-27-thoroughness-knobs-design.md](./2026-10-27-thoroughness-knobs-design.md).
The research critique ([2026-10-27-research-critique-design.md](./2026-10-27-research-critique-design.md))
is planned separately and starts after this plan lands; where this plan touches something the
critique will change again, the task says so.

## Global Constraints

- **Standard = today.** No flag and no `project.md` key ⇒ 2 hunters, gatherer width 1, `K = 0`,
  `--max-iter` 3 (`--max-gate-iter` 2), `--max-agents` 24. Every existing lint stays green.
- **Presets:** `quick` 2 / 1 / 0 / 1 (gate 1) / 12; `standard` 2 / 1 / 0 / 3 (gate 2) / 24;
  `thorough` 3 / 2 / 1 / 5 (gate 3) / 48; `exhaustive` 5 / 3 / 3 / 8 (gate 5) / 64, in the
  order hunters-or-critics, gatherer width, `K`,
  adversarial cap, `--max-agents`. The critique row (`off`/`on`/`on`) is written in the table now
  and consumed by the critique plan.
- **Hard ceiling 8** on every non-singleton width; `--width` on a singleton warns, names the
  reason, and is ignored. Hunter letters `A`–`H`; four angles, cycling above four.
- **Flags**, shared by `/adversarial-review`, `/feature-flow`, `/research`:
  `--effort=quick|standard|thorough|exhaustive`, `--width=<agent>:<n>[,…]`, `--dry=K`, `--max-agents=N`.
  Precedence by layer (flag > `project.md` > guide), then by specificity (single value >
  preset). Invalid values warn and fall back, in the style of `--max-iter`.
- **Counting:** a round of parallel briefs to one teammate type counts once toward `--max-iter`
  (the sentence appears verbatim in both guides); `--max-agents` counts dispatches, resumes are
  free; reaching it mid-round finishes the round with resumes and leaves an undispatchable
  judge's finding `STALEMATE` with `reason: agent ceiling`; no new status token.
- **Dry rounds:** a new finding is non-duplicate (same `file`, lines within 5, 60 % of `issue`
  words) **and** survives cross-examination; dry-check rounds are hard-capped at `2K`; they
  never increment `review_iter`; `--no-fix` keeps them.
- **Delta:** after a fix the next hunt capsule carries Coder's `changed_files` and the hunks
  that differ from the previous round's diff, untracked files included; a delta file with no
  finding needs a `probed[]` entry `{file, buckets, tried}`; `CLEAN` with a delta needs one per
  delta file.
- No `*` in any `tools:` line. Agent files load at session start: test agent changes in a fresh
  `claude -p`. Commit only on the owner's go (`rules/git.md`); never push.

## Review Focus

1. `--width=adversarial-reviewer:9` → clamped to 8 with one warning line, the run continues
   (Task 1 lint: the guide's § Input says `8` and `warn`).
2. `--width=research-lead:2` → ignored with the table's reason, width stays 1 (Task 1 lint:
   the singleton sentence names the reason column).
3. `--effort=quick` with `project.md` `"max_agents": 48` → 12, and a `project.md`
   `"width": {"searcher": 2}` beats its own `"preset"` (Task 1 lint: both worked examples are
   in § Input verbatim).
4. A dry-check round that finds one never-seen nit every time → ends after `2K` rounds with
   "cut at its cap" in the recap, never `REVIEW_LIMIT_REACHED` (Task 2 lint: `2K` and
   `cut at its cap` in the guide).
5. Coder's fix adds a **new, untracked** file → it is in the delta (Task 2 lint: the delta
   paragraph names `git ls-files --others`), so `probed[]` is required for it.

---

### Task 1: the thoroughness guide and §5h

**Files:**
- Create: `core/guides/thoroughness.md`
- Modify: `core/CLAUDE.md` (§ Guides table), `core/scripts/harness-check.sh` (new §5h after §5g)

**Interfaces:**
- **Produces** the guide's section names every later task points at: `## Knob table`,
  `## Width semantics`, `## Presets`, `## Input` (the shared flag block and precedence),
  `## Angles`, `## Delta and probed`, `## Agent ceiling`, `## Counting`.
- **Produces** the resolved-knobs shape every capsule and state block carries:
  ```yaml
  knobs: {effort: standard, width: {adversarial-reviewer: 2, searcher: 1, web-reader: 1, writer: 1, research-critic: 2}, dry: 0, max_iter: 3, max_agents: 24}
  ```
- **Produces** the `probed[]` entry shape: `{file: <path>, buckets: [<playbook bucket names>], tried: <one line>}`.
- **Produces** the `§5h` header line `echo "== 5h. Thoroughness knobs (2026-10-27) =="` and
  `TH="$H/guides/thoroughness.md"`, which Tasks 2–5 append to.

- [ ] **Step 1: Write the failing checks.** Append §5h after §5g's last line (before the summary
  block at the end of the script): `check "guides/thoroughness.md exists"`; a `grep -qxF`
  loop over the eight `## ` headings above; a loop over `"$H"/agents/*.md` asserting each
  basename (minus `.md`) appears in a table row of `## Knob table` as `` `<name>` `` (use
  `grep -qE '^\| `'"$a"'`'`); a loop over `research-lead incident-investigator repro-driver
  designer coder tester reviewer planner` asserting that agent's row has a non-empty fourth
  cell (`awk -F'|'` on the matched row, `$5` trimmed non-empty); tokens in the guide:
  `quick`, `standard`, `thorough`, `exhaustive`, `--effort`, `--width`, `--dry`, `--max-agents`, `8`,
  `warn`, `cycle`, `hunter-H`, `time-and-config`, `claims-and-consumers`, `probed`,
  `tried:`, `agent ceiling`, `counts once toward`, `git ls-files --others`, `--effort=quick`,
  `"max_agents": 48`, `"width": {"searcher": 2}` (on one line); and
  `grep -qF 'thoroughness.md' "$H/CLAUDE.md"`.
- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh`. Expected: every new §5h line FAIL;
  §5e also fails with "guide guides/thoroughness.md has no consumer" once the file exists.
- [ ] **Step 3: Write the guide.** Top paragraph: what the four knobs are, who reads this
  (`/adversarial-review`, `/feature-flow`, `/research`, `research-lead`), the design doc
  reference, "resolution happens once in the main session; a subagent receives numbers".
  Then, in this order, the spec's text made normative:
  - `## Knob table`: the spec's table with four columns (Agent, `standard`, `thorough`,
    Singleton and why), every file in `core/agents/` as a row, the ceiling-8 paragraph.
  - `## Width semantics`: hunters/critics = same brief, different angles; gatherers =
    partitioned briefs, never duplicates, the 50-hit searcher cap as the partition size.
  - `## Counting`: the one sentence, verbatim: "A round of parallel briefs to one teammate
    type counts once toward `--max-iter`; the width is the number of agents in that round."
  - `## Presets`: the spec's preset table including the critique row and the two adversarial
    cap rows; the sentence that presets drive the adversarial cap only.
  - `## Agent ceiling`: what counts, what is free, the mid-round rule with the literal
    `reason: agent ceiling`, the 48 anchor.
  - `## Input`: the four flags with their syntax, the `project.md` `"thoroughness"` object
    with every key optional, the precedence paragraph with both worked examples from the
    spec, each JSON fragment on one line (`"max_agents": 48`, `"width": {"searcher": 2}`), the
    clamping/warning sentences ("above 8 … warn and use 8"; "a `--width` on a
    singleton warns with the reason from the table and is ignored"), the `knobs:` shape
    above, and "each command's § Input points here instead of repeating this".
  - `## Angles`: the four orderings (`inside-out`, `outside-in` as in `adversarial-review.md`
    § Starting angles; `time-and-config`: Time and ordering → Config values → Unbounded repeated
    work → then the rest; `claims-and-consumers`: Claims the code does not keep → Consumers and
    surroundings → Guards → then the rest), roles `hunter-A` … `hunter-H`, "above four the
    angles cycle".
  - `## Delta and probed`: the delta definition (Coder's `changed_files` plus hunks differing
    from the previous round's diff, computed over `git diff <base>` **and**
    `git ls-files --others --exclude-standard` as the tree hash is), hunters cover every bucket
    on the delta first, the `probed[]` entry as YAML
    (`- {file: <path>, buckets: [<bucket names>], tried: <one line>}`), the send-back rule ("name what you probed in
    <file>", once), `CLEAN` with a delta.
  - `## Dry rounds`: the definition of a new finding, `K`, the `2K` cap, "cut at its cap".
- [ ] **Step 4: Index it.** Add the row to `core/CLAUDE.md` § Guides:
  `| [thoroughness.md](./guides/thoroughness.md) | /adversarial-review, /feature-flow, /research, research-lead | parsing --effort / --width / --dry / --max-agents, or sizing a dispatch |`.
- [ ] **Step 5: Run the check.** Expected: §5h green except the lines Tasks 2–5 own (none yet
  written), §5e green (the guide now has consumers through `CLAUDE.md`).
- [ ] **Step 6: Commit (owner's go):** `core/guides/thoroughness.md core/CLAUDE.md
  core/scripts/harness-check.sh`, `feat(harness): thoroughness guide with knob table, presets and shared flags`.

### Task 2: adversarial review: angles, N-way tally, delta, dry-check rounds

**Files:**
- Modify: `core/guides/adversarial-review.md` (§ Starting angles ~100; § Debate rules;
  § Message shapes: hunt capsule ~259, hunt reply ~269, cross-examination message ~294;
  § Procedure: A round steps 1–2 ~404, The loop step 2 ~450 and step 5 ~466; § Report ~470;
  § Case file state block ~504)
- Modify: `core/agents/adversarial-reviewer.md` (§ Input, step 2, step 6, § Output)
- Modify: `core/scripts/harness-check.sh` (§5h)

**Interfaces:**
- **Consumes** from Task 1: the angle names, the `probed[]` shape, the `knobs:` shape, the
  dry-round definitions, by section reference (`guides/thoroughness.md § Angles` etc.).
- **Produces** the hunt reply with `probed: []` beside `findings`, the state block keys
  `knobs:` and `dry_rounds:`, the hunt capsule's `delta:` item, and the message texts:
  cross-examination "Here are the other hunters' findings, grouped by hunter: …", the send-back
  "Name what you probed in <file>".

- [ ] **Step 1: Write the failing checks** in §5h. Guide tokens: `time-and-config`,
  `claims-and-consumers`, `hunter-H`, `probed`, `delta`, `git ls-files --others` (in the delta
  paragraph: `sed -n '/^## Delta/,/^## /p'` of the thoroughness guide is Task 1's; here assert
  the hunt capsule paragraph of `adversarial-review.md` mentions `delta`), `designated
  challenger`, `no majority`, `dry-check round`, `dry_rounds`, `knobs:`, `2K`, `cut at its cap`,
  `survives its cross-examination`, `reason: agent ceiling`, `counts once toward`,
  `git ls-files --others` (in § The loop step 5). Hunter
  tokens: `time-and-config`, `claims-and-consumers`, `hunter-H`, `probed`, `cycle`. Negative:
  `grep -qF 'Dispatch two `adversarial-reviewer`' "$AR"` must now fail (the fixed "two").
- [ ] **Step 2: Run the check.** Expected: the new lines FAIL.
- [ ] **Step 3: Edit the guide.**
  - § Starting angles: replace the two bullets with a pointer to `thoroughness.md § Angles`
    plus the four names and the cycling sentence; keep the two existing orderings' text.
  - § Debate rules: a new bullet **N-way cross-examination** (every hunter rules on the `N−1`
    others; majority `VALID` → `AGREED`; `same_as` counts as `VALID`; majority
    `FALSE_POSITIVE` → turns or the asserter's one turn; **no majority** → turns as if
    challenged; turns are between the asserter and the **designated challenger** = lowest
    letter among `FALSE_POSITIVE` rulers, else among `UNCLEAR`; the other rulings are attached
    verbatim to the first turn message as evidence; the judge gets those two positions).
  - § Message shapes: hunt capsule gains "the resolved `knobs:`" and "`delta:` (round ≥ 2
    after a fix): Coder's `changed_files` and the differing hunks, or `none`"; hunt reply gains
    `probed: []            # one entry per delta file with no finding: {file, buckets, tried}`;
    cross-examination message becomes "Here are the other hunters' findings, grouped by
    hunter: …"; a new **Probe send-back message** "Name what you probed in <file>" with the
    reply being a hunt reply carrying only `probed`.
  - § Procedure, A round step 1: "Dispatch `knobs.width.adversarial-reviewer` hunters in one
    message, letters from `A`, angles from `thoroughness.md § Angles`"; after the hunt, the
    send-back check; step 2 the N-way rule by reference to Debate rules.
  - § The loop, step 2: before `APPROVED`, the dry-check round: "With `K > 0`, a round whose
    exit would be `APPROVED` starts a dry-check round: fresh hunters, same tree, the first
    hunter's angle rotated to the one no hunter of the previous round had; a new finding (not a
    duplicate of any earlier round's, and one that **survives its cross-examination**) resets
    the dry counter, a new `blocker`/`major` re-enters the fix loop; `K` consecutive dry rounds,
    or `dry_rounds` reaching its hard cap `2K`, → `APPROVED`; dry-check rounds never increment
    `review_iter`; `--no-fix` keeps them." Step 5: the delta computation (keep the previous
    round's `git diff <base>` under the round's scratchpad subfolder, diff the two, add new
    untracked files from `git ls-files --others --exclude-standard`).
  - § Report: "how many dry-check rounds ran and whether the loop ended dry or was **cut at its
    cap**"; the cost line reads "round N of ≤ M, W hunters, about $X".
  - § Case file: `knobs: {…}` and `dry_rounds: 0` lines in the state block;
    `hunters: {A: …, B: …, …}`.
  - The ceiling sentence from `thoroughness.md § Agent ceiling`, by reference, in § The loop:
    reaching `max_agents` mid-round finishes with resumes and marks an undispatchable judge's
    finding `STALEMATE` with `reason: agent ceiling`.
  - The counting sentence (Task 1 § Counting), verbatim, under § Procedure.
- [ ] **Step 4: Edit the hunter.** § Input: "your role (`hunter-A` … `hunter-H`) and angle,
  one of the four in `thoroughness.md § Angles`; angles cycle above four"; the `delta`
  item; step 2 "when the capsule carries a delta, every bucket on the delta first, then the
  rest"; a new step after 5: "For every delta file where you report nothing, add a `probed[]`
  entry: the buckets you tried and the trigger that did not fire. A null without a probe is
  sent back once." § Output: `probed` is in the hunt reply; role enum `hunter-A | … |
  hunter-H`.
- [ ] **Step 5: Run the check.** Expected: §5f still green (its `hunter-A`/`hunter-B` and
  "is `AGREED` at once" tokens survive), §5h Task-2 lines green.
- [ ] **Step 6: Commit (owner's go):** the two files and the check,
  `feat(review): N-way cross-examination, delta probes and dry-check rounds`.

### Task 3: the commands: shared flags, width in the dispatch, feature-flow's gate cap

**Files:**
- Modify: `core/commands/adversarial-review.md` (frontmatter `argument-hint`; § Input; "Before
  each round" cost line; "Hunters" bullet; "Fresh hunters" bullet; § What you do NOT do last
  bullet)
- Modify: `core/commands/feature-flow.md` (frontmatter `argument-hint`; § Input lines 28–29;
  "Gate" bullet)
- Modify: `core/guides/ai-workflow.md` (§ Bounds: one sentence)
- Modify: `core/scripts/harness-check.sh` (§5h)

**Interfaces:**
- **Consumes** Task 1 § Input and § Presets by reference; Task 2's dispatch wording.
- **Produces** the resolution sentence every command carries: "Resolve the knobs once per
  `guides/thoroughness.md § Input` (flags, then `project.md` `thoroughness`, then the preset)
  and write them into the case file's `knobs:`."

- [ ] **Step 1: Write the failing checks** in §5h: for each of
  `commands/adversarial-review.md commands/feature-flow.md commands/research.md`, if its
  `argument-hint` mentions `--max-iter` or `--max-gate-iter` then it also mentions `--effort`
  (the research half of this lands in Task 4; write the loop now and let that one line fail
  until then); `adversarial-review.md` and `feature-flow.md` mention `guides/thoroughness.md`,
  `--width`, `knobs:`, `dry-check`; `adversarial-review.md` says `--no-fix` keeps dry-check
  rounds (token `keeps dry-check`); `feature-flow.md` § Input says the preset sets
  `--max-gate-iter` (token `preset` on the `--max-gate-iter` line: `grep -E
  '^- `--max-gate-iter=N`.*preset'`); negative: `grep -qF 'two `Agent` dispatches'
  "$CMD"` fails.
- [ ] **Step 2: Run the check.** Expected: the new lines FAIL (the research line too).
- [ ] **Step 3: Edit `commands/adversarial-review.md`.** `argument-hint` gains
  `[--effort=quick|standard|thorough|exhaustive] [--width=<agent>:<n>,…] [--dry=K] [--max-agents=N]`.
  § Input: one bullet "Thoroughness flags → `guides/thoroughness.md § Input`; resolve once,
  record `knobs:` in the case file; `--max-iter` defaults to the preset's adversarial cap when
  absent"; `--no-fix` bullet gains "keeps dry-check rounds". Cost line: "round N of ≤ M, W
  hunters, about $X". Hunters bullet: "`knobs.width.adversarial-reviewer` dispatches in one
  message, letters from `A`, each with its angle". Fresh hunters bullet: "the same width". Last
  "NOT do" bullet: "Never collapse the hunter dispatches into one".
- [ ] **Step 4: Edit `commands/feature-flow.md`.** `argument-hint` gains the same four flags.
  § Input: `--max-gate-iter=N` line becomes "cap on `gate_iter` (default: the preset's
  adversarial cap, 2 at `standard`)"; a bullet for the thoroughness flags by reference, with
  "`--max-iter` (Tester/Reviewer) is not touched by the preset". Gate bullet: "hunters at
  `knobs.width.adversarial-reviewer`, dry-check rounds per the guide".
- [ ] **Step 5: Edit `ai-workflow.md` § Bounds.** Add the counting sentence from Task 1
  § Counting as its own bullet, with "(team-flow widths are 1; see
  `guides/thoroughness.md`)".
- [ ] **Step 6: Run the check.** Expected: all Task-3 lines green except the research
  argument-hint line; §5f, §5g green.
- [ ] **Step 7: Commit (owner's go):** the four files,
  `feat(review): shared thoroughness flags in /adversarial-review and /feature-flow`.

### Task 4: research: rounds count once, partitioned width, `max_agents`

**Files:**
- Modify: `core/guides/research-workflow.md` (§ Dispatch, iteration, routing item 2 ~147;
  § Status blocks research-lead row; § Flow and roles step 2 line)
- Modify: `core/agents/research-lead.md` (§ Running the team steps 1–2; § Output
  `dispatches` comment)
- Modify: `core/commands/research.md` (frontmatter `argument-hint`; § Input; New run step 3)
- Modify: `core/scripts/harness-check.sh` (§5h; §5b stays untouched)

**Interfaces:**
- **Consumes** Task 1 § Input, § Width semantics, § Counting, § Agent ceiling.
- **Produces** the lead's capsule items `knobs:` (the shape from Task 1) and the run-log header
  line `max_agents: <n>`; the lead's counting rule: every fresh team dispatch, including each
  `repro_agent_id` the investigator reports, +1; a resume +0. **Hand-off to the critique plan:**
  `/research` passes the **whole** ceiling as `max_agents` here; the critique plan changes it
  to "ceiling minus the critique's reserve".

- [ ] **Step 1: Write the failing checks** in §5h: `research-workflow.md` contains the counting
  sentence (`counts once toward`) and no longer `dispatches 1 and 2 of the searcher's cap`;
  `research-lead.md` mentions `max_agents`, `partition`, `repro_agent_id` in the counting
  paragraph (`sed -n '/^1\. \*\*Set up/,/^2\. /p'` contains `repro_agent_id`), `knobs`;
  `commands/research.md` `argument-hint` mentions `--effort` (closes Task 3's loop) and § Input
  mentions `guides/thoroughness.md`.
- [ ] **Step 2: Run the check.** Expected: the new lines FAIL.
- [ ] **Step 3: Edit `research-workflow.md`.** Item 2 becomes: one counter per teammate, +1 per
  **round** (a round = one dispatch message to one teammate type, whatever its width), never
  reset; the counting sentence verbatim; "parallel briefs within a round are partitioned per
  `guides/thoroughness.md § Width semantics`, never duplicated"; `--max-iter` default 3 rounds;
  the `max_agents` ceiling (dispatches, resumes free, at the ceiling `PARTIAL` with an Open row
  naming it). § Status blocks: `dispatches[]` entries carry `round` in place of `iteration`.
  § Flow and roles step 2:
  "searcher · web-reader at `knobs.width`, partitioned".
- [ ] **Step 4: Edit `research-lead.md`.** Step 1: the counters count rounds; `max_agents` from
  the capsule into the run-log header; the dispatch count includes every `repro_agent_id` the
  investigator reports (fresh ones only); the run-log header gains `knobs:` and
  `max_agents:`. Step 2: a new bullet "**Width.** With
  `knobs.width.searcher` (or `web-reader`, `writer`) above 1, partition the round's targets
  across that many briefs, each under the 50-hit cap, in one message; the round counts once;
  never send the same brief twice." § Output: `dispatches: []  # each: { agent, agent_id,
  status, round }`.
- [ ] **Step 5: Edit `commands/research.md`.** `argument-hint` gains the four flags and the
  usage line in § Input matches it; a bullet "Thoroughness flags → `guides/thoroughness.md
  § Input`; resolve once; pass `knobs:` and `max_agents` in the lead's capsule (New run step 3)
  and record them in `lead.txt` under the agent id, so `--resume` reuses them"; `--max-iter`
  default from the preset.
- [ ] **Step 6: Run the check.** Expected: §5h fully green, §5b green (status tokens, tool
  boundaries and model pins are untouched), `ALL GREEN` apart from Task 5's lines if written
  first.
- [ ] **Step 7: Commit (owner's go):** the four files,
  `feat(research): rounds count once; partitioned width; max_agents in the lead's capsule`.

### Task 5: `project.md` key and the config-parse check

**Files:**
- Modify: `project-template/project.md` (`json harness` block and its key list)
- Modify: `core/scripts/harness-check.sh` (§5h; fixture-based)

**Interfaces:**
- **Consumes** `hooks/lib/project-config.js <key>` as is: dotted keys resolve into nested
  objects, a missing key prints nothing. No code change to it.
- **Produces** the documented key: `"thoroughness": {"preset": "standard", "width": {"searcher": 2}, "dry_rounds": 0, "max_agents": 24}`, every sub-key optional.

- [ ] **Step 1: Write the failing checks** in §5h: `grep -qF '"thoroughness"'
  "$ROOT/project-template/project.md"` (harness repo only, guard with
  `[ "$H" = "$ROOT/core" ]` as §5f does); a fixture: `FX=$(mktemp -d)`, write
  `$FX/.claude/project.md` with a `json harness` block containing
  `"thoroughness": {"preset": "thorough", "width": {"searcher": 2}}`, then
  `CLAUDE_PROJECT_DIR=$FX node "$H/hooks/lib/project-config.js" thoroughness.width.searcher`
  prints `2`, `… thoroughness.preset` prints `thorough`, `… thoroughness.max_agents` prints
  nothing; `rm -rf "$FX"`.
- [ ] **Step 2: Run the check.** Expected: the template line FAILs; the three fixture lines
  already PASS (the parser needs no change; this pins it).
- [ ] **Step 3: Edit the template.** Add `"thoroughness": null` to the block and a key
  description in the list: "`thoroughness`: optional sizes for the teams, see
  `guides/thoroughness.md § Input`: `{"preset": …, "width": {…}, "dry_rounds": …, "max_agents":
  …}`; any key may be absent; `null` = the guide's `standard`."
- [ ] **Step 4: Run the check.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner's go):** `project-template/project.md
  core/scripts/harness-check.sh`, `feat(harness): project.md thoroughness key`.

### Task 6: verification

**Files:**
- Modify: `docs/2026-10-27-thoroughness-knobs-design.md` (new `## Verified (2026-10-27)` section)
- Run in: a fresh `claude -p` against an installed project (`install.sh --update`), never this
  session (agent files load at session start).

- [ ] **Step 1: Regression, no flags.** `/adversarial-review --no-fix` on the fixture diff the
  2026-10-22 design was verified with (the design's § Verified names it). Expected: two
  hunters, the case file's state block carries `knobs:` with `standard` values and
  `dry_rounds: 0`, plus the new keys `knobs`, `dry_rounds`, `dry_streak`, `dispatched`,
  `round_kind`, `round`; every pre-existing key as before, final block `REVIEWED` or `APPROVED`
  as before. Record the state block in § Verified.
- [ ] **Step 1b: Fresh-session resume.** Start `/adversarial-review --effort=thorough --no-fix`
  on the fixture, stop it after round 1's synthesis, `--resume` it in a fresh `claude -p`: the
  restarted round's capsule carries the recorded `knobs` width and a `delta:` recomputed from
  `r<N-1>`/`r<N>`.
- [ ] **Step 2: Delta and probes.** A fixture diff with a planted defect inside a hunk that a
  "fix" adds (e.g. a time window that counts from the first failure with no minimum count),
  run with fixes on and `--max-iter=1`. Expected: round 2's capsule carries `delta:`, every
  hunt reply has `probed[]` for each delta file it reports nothing on, or the orchestrator
  sends the probe send-back once. Record whether the planted defect was found.
- [ ] **Step 3: Dry-check rounds and width.** `--effort=thorough --no-fix` on the same fixture.
  Expected: three hunters `A`–`C` with three different angles, N-way rulings in every
  cross-examination reply, at least one dry-check round, and the recap stating "dry" or "cut
  at its cap" with `dry_rounds`.
- [ ] **Step 4: Acceptance smoke (owner's go, real spend).** The spec § Verification plan's
  thorough run at the tree the gate once approved, in a worktree (`superpowers:using-git-worktrees`).
  Record whether the idle-time defect surfaced, by which hunter or round, and the cost. A miss
  is written down as a miss.
- [ ] **Step 5: Research width.** `/research --effort=thorough` on a small codebase question in
  the installed project, `--max-iter=1`. Expected: the lead partitions one searcher round into
  two briefs in one message, `run-log.md` records `max_agents` and the round once, the lead's
  `dispatches[]` carry `round` in place of `iteration`.
- [ ] **Step 6: Write § Verified** in the design: one subsection per step with the measured
  result and any fix it forced (each fix goes back through §5h: red line first).
- [ ] **Step 7: Commit (owner's go):** `docs/2026-10-27-thoroughness-knobs-design.md` and any
  fixes, `docs(harness): thoroughness knobs verified`.
