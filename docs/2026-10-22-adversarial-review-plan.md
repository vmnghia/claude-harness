# Adversarial review: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a `/adversarial-review` command that sends two hunters at a diff, makes them debate
every finding to a resolved state with a judge ladder behind them, fixes what survives through
Coder, and repeats with fresh hunters until the diff is clean or a bound is hit.

**Architecture:**
- One guide, `core/guides/adversarial-review.md`, holds everything shared: the attack playbook,
  finding discipline, debate rules, every message and status-block shape, the case-file state
  block, and the round-and-loop **procedure** the command executes.
- Two agent files: `adversarial-reviewer` (the hunter, dispatched twice per round) and
  `review-judge` (fresh per stalemate). Both read-only on the repo; both may run throwaway
  scripts in the session scratchpad.
- `coder` gains a findings-only mode with no spec.
- The command runs in the main session: it resolves the diff, dispatches, relays, synthesises,
  writes the case file, and asks the owner. It never judges a finding's content.
- `harness-check.sh` gains section `5f` that pins the contract between these files.

**Tech stack:** Claude Code agent files, slash commands, `Agent` + `SendMessage` + `AskUserQuestion`
in the main session, bash for `harness-check.sh`, Node ≥18 for the verification fixture.

**Spec:** [2026-10-22-adversarial-review-design.md](./2026-10-22-adversarial-review-design.md).

## Global Constraints

- **Severity scale:** `blocker | major | minor | nit`, as `guides/ai-workflow.md`.
- **Ladder scope:** debate past one cross-examination, the judge, and the fix dispatch apply to
  `blocker` and `major` only. `minor`/`nit` end `AGREED`, `WITHDRAWN` or `CONTESTED` after one
  cross-examination.
- **End states per finding:** `AGREED | WITHDRAWN | REFUTED | ESCALATED | STALEMATE | CONTESTED`.
- **Exhaustion:** a side is exhausted on a finding after the other side has rated two of its
  consecutive turns `peer_added_evidence: no`. Safety cap: 8 turns per finding per side.
- **Judge ladder:** one judge per stalemated finding; one refutation turn per hunter; one judge
  reply; then `STALEMATE`. Both hunters already agreeing "outside the repo" skips the judge.
- **Loop bounds:** `review_iter` starts at 0, +1 per Coder dispatch, default cap 3
  (`--max-iter=N`). Circuit breaker: *fix did not take* (same AGREED blocker/major set two rounds
  running), *Coder could not act* (`BLOCKED`, or `IMPLEMENTED` with empty `changed_files`, or every
  finding in `not_applicable`), *fix churn* (two rounds running, every AGREED finding is in a file
  the previous round's Coder `changed_files` lists).
- **"Same finding"** (breaker test, applied by the orchestrator): same `file`, `|Δline| ≤ 5`, and
  at least 60 % of the words of `issue` shared after lowercasing and collapsing whitespace.
- **Coder rejections:** every `not_applicable` entry goes up the judge ladder in the same round
  (judge rules between Coder's reason and the hunters' position, one refutation turn per hunter,
  one judge reply, then the owner). Never left to the breaker.
- **Capsules carry the scratchpad path:** the orchestrator copies the session scratchpad path
  from its Environment line into every hunter and judge capsule.
- **Orchestrator statuses:** `APPROVED | NEEDS_OWNER | REVIEWED | REVIEW_LIMIT_REACHED | STALLED |
  BLOCKED | NO_DIFF`.
- **Diff base:** as `reviewer.md` § Procedure step 1, verbatim behaviour.
- **Tool boundaries:** hunters and judge list exactly `Read, Grep, Glob, Bash`; never `Edit`,
  `Write`, `NotebookEdit`, `Agent`. Bash whitelist: `git status|diff|log|show|merge-base|rev-parse|
  branch --show-current`, plus `node <scratchpad path>/…` and `python3 -I <scratchpad path>/…`
  on files they write there with a heredoc. Scripts may read the repo and must not write to it,
  build it, run its tests, start a server or use the network.
- **Models:** hunters and judge `claude-opus-5-5`.
- **Case file:** `.claude/runs/YYYY-MM-DD-adversarial-<slug>.md`; the orchestrator is its only
  writer; the YAML state block is the first fenced block in the file.
- **No agent commits, pushes or creates branches.** Work on branch `feat/adversarial-review`; the
  owner commits; `bash scripts/leak-check.sh` stays clean.
- **Every harness-check assertion added here lives in one new section,**
  `== 5f. Adversarial review (2026-10-22) ==`, inserted after §5e and before §6.

## Review Focus

1. **A hunter that writes a scratchpad script must not be able to write into the repo.** Pinned
   by Task 1 step 1 (no write tools in frontmatter) and by the whitelist text; Task 6's live run
   confirms `git status` shows only Coder's edits.
2. **A judge `OUTSIDE_REPO` ruling with no question** would leave the owner nothing to answer.
   Pinned by Task 2 step 1 (the token `question:` must appear in the judge's status block).
3. **Coder in findings-only mode with no spec must not read the newest spec.** Pinned by Task 3
   step 1 (`coder.md` contains the no-fallback sentence) and Task 6 (the fixture has a planted
   unrelated spec; Coder's reply must not mention it).
4. **`--resume` on a case file whose tree hash no longer matches** must say so and restart the
   round, never trust stale finding states. Pinned by Task 4 step 1 (the command text names the
   tree-hash check) and Task 6's resume drill.
5. **Two hunters with the same `name`** must be addressed by agent id, never by name, or a
   SendMessage goes to the wrong one. Pinned by Task 4 step 1 (the procedure records both ids
   in the state block and sends by id).

---

### Task 1: the guide and the hunter

**Files:**
- Create: `core/guides/adversarial-review.md`
- Rewrite: `core/agents/adversarial-reviewer.md` (the untracked stub; keep the owner's `name`,
  `description` and opening sentence, replace everything from `## Review Process` down)
- Modify: `core/scripts/harness-check.sh` (new §5f, created here, extended by tasks 2–5)

**Interfaces:**
- **Produces** the guide's sections, in this order and with these exact headings:
  `## Playbook`, `## Finding discipline`, `## Debate rules`, `## Message shapes`,
  `## Procedure`, `## Case file`, `## Tool boundaries`.
- **Produces** the finding shape every later task consumes:

  ```yaml
  - id: A1                      # hunter letter + own sequence; the state block prefixes the round: r1-A1
    severity: blocker | major | minor | nit
    file: src/x.ts
    line: 42
    issue: <one line>
    trigger: <input and state that fire it>
    consequence: <what breaks, for whom>
    suggestion: <one line>
    provenance: read | inferred | executed
    evidence: <file:line refs, or scratchpad script path + output excerpt>
  ```
- **Produces** the hunter's three status blocks (`agent: adversarial-reviewer`,
  `role: hunter-A | hunter-B`):
  - `phase: hunt`, `status: FINDINGS | CLEAN`, `payload: {findings: [...], summary}`
  - `phase: cross-examine`, `status: RULINGS`, `payload: {rulings: [{id, ruling: VALID |
    FALSE_POSITIVE | UNCLEAR, severity, evidence, reason}], added: [findings]}`
  - `phase: turn`, `status: TURN`, `payload: {turns: [{id, response: CONCEDE | MAINTAIN |
    CLARIFY | ACCEPT | CHALLENGE, new_evidence, peer_added_evidence: yes | no, severity,
    outside_repo: <question or omitted>}]}`. `CONCEDE`/`MAINTAIN`/`CLARIFY` are the asserter's
    responses; `ACCEPT`/`CHALLENGE` the challenger's. `new_evidence` is required and may be
    `none` only with `CONCEDE` or `ACCEPT`.
- **Produces** `## Procedure` with the numbered round (hunt → cross-examine → turns until
  resolved → judge ladder → synthesis → owner pause) and the loop (fix dispatch → fresh round →
  exit and breaker), the ladder scope, and the "same finding" rule, all per the design and Global
  Constraints. The command (Task 4) executes this section; it holds no procedure of its own.
- **Produces** `## Case file` with the state block:

  ```yaml
  state:
    review_iter: 0
    base: <resolved sha>
    tree: <sha256 of `git diff <base>` output>
    hunters: {A: <agent id>, B: <agent id>}
    findings:
      - {id: r1-A1, severity: major, state: AGREED, file: …, line: …, issue: …}
    owner_questions:
      - {id: r1-B2, question: …}
  ```
  and the per-round headings `## Round N`, `### Hunt A`, `### Hunt B`, `### Exchange k`,
  `### Judge <id>`, `### Synthesis`, `### Coder`.
- **Produces** `## Playbook`: one subsection per bucket of the design's evidence table, each a
  list of "for every X, check Y" lines; and the two starting angles, `inside-out` and
  `outside-in`, as named lists of which buckets to start with.
- **Produces** `## Finding discipline`: the pre-report gate (four questions), proof required for
  blocker/major, "zero findings is a valid result", and the false-positive list, ported from the
  stub's text (keep the items, drop the TypeScript examples and the React/Node checklists).

- [ ] **Step 1: Write the failing checks.** Add §5f to `harness-check.sh` with, for now:
  - `core/guides/adversarial-review.md` exists and contains each of the seven `## ` headings above
    (one `ok`/`fail` per heading)
  - the guide contains each token: `AGREED`, `WITHDRAWN`, `REFUTED`, `ESCALATED`, `STALEMATE`,
    `CONTESTED`, `peer_added_evidence`, `new_evidence`, `NO_DIFF`, `review_iter`, `tree:`
  - `agents/adversarial-reviewer.md`: `tools:` line is exactly `tools: Read, Grep, Glob, Bash`;
    `model: claude-opus-5-5`; contains `rules/project/guides-index.md`; contains
    `Read` + `guides/adversarial-review.md` on one line; contains `hunter-A` and `hunter-B`;
    does not contain `## Review Checklist` (the stub's section)
- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh | grep -E 'FAIL|5f'`. Expected: every
  §5f line FAILs. (After step 3 alone, §5e would also FAIL "guide has no consumer"; step 4 is
  what gives it one, so run the check only after both.)
- [ ] **Step 3: Write the guide** per Interfaces. `## Debate rules` holds the evidence gate, burden
  of proof, exhaustion, the ladder scope and the six end states. `## Tool boundaries` holds the
  script rules from Global Constraints. `## Message shapes` holds the three hunter blocks, the
  judge block (Task 2's Interfaces, written here so the guide is complete), the Coder
  findings-only block (Task 3's), and the orchestrator block (Task 4's).
- [ ] **Step 4: Rewrite the hunter.** Frontmatter: keep `name`, `description`; `tools: Read, Grep,
  Glob, Bash`; `model: claude-opus-5-5`. Body: the owner's opening sentence; the project-guides
  line every agent carries (copy from `reviewer.md`); `Read guides/adversarial-review.md` and
  `rules/research-discipline.md` before starting; **Input** (the capsule: base ref, changed
  files, context text, `project.md` § Stack and § Code layout, scratchpad path, its role letter
  and starting angle); **Procedure** (hunt per the Playbook starting from its angle, then answer
  each later message per § Message shapes); **What you do NOT do** (edits, builds, tests,
  servers, network, spawning, reading the other hunter's work except what the orchestrator
  sends); **Output** (end every reply with exactly one status block for the phase asked).
- [ ] **Step 5: Run the check again.** Expected: §5f PASS, §5e "guide … has a consumer" PASS,
  `ALL GREEN`.
- [ ] **Step 6: Commit (owner):** paths `core/guides/adversarial-review.md
  core/agents/adversarial-reviewer.md core/scripts/harness-check.sh`, message
  `feat(review): adversarial-review guide and hunter agent`.

### Task 2: the judge

**Files:**
- Create: `core/agents/review-judge.md`
- Modify: `core/scripts/harness-check.sh` (§5f)

**Interfaces:**
- **Consumes:** the finding shape and `## Debate rules` from Task 1.
- **Produces** the judge status block (already written into the guide by Task 1 step 3):

  ```yaml
  ---
  agent: review-judge
  status: UPHELD | REFUTED | OUTSIDE_REPO
  finding: <id>
  payload:
    severity: blocker | major | minor | nit
    evidence: <file:line refs or script path + output>
    trigger: <UPHELD only>
    refutation: <REFUTED only: the guard, caller or type that stops the trigger>
    question: <OUTSIDE_REPO only: the one question the owner must answer>
    summary: <one line>
  ---
  ```
- **Produces** the judge's input contract: the diff, one finding, both hunters' final turns on
  it, every script output either side produced, the scratchpad path. Nothing else.

- [ ] **Step 1: Write the failing checks** in §5f: `agents/review-judge.md` exists; `tools:` exactly
  `Read, Grep, Glob, Bash`; `model: claude-opus-5-5`; contains `rules/project/guides-index.md`;
  `Read` + `guides/adversarial-review.md` on one line; contains `UPHELD`, `REFUTED`,
  `OUTSIDE_REPO`, `question:`; and a loop over `adversarial-reviewer review-judge` asserting
  none lists `Edit`, `Write`, `NotebookEdit` or `Agent` (use `has_tool`).
- [ ] **Step 2: Run** the check. Expected: the new §5f lines FAIL.
- [ ] **Step 3: Write the judge.** `name: review-judge`; description: "Rules on one disputed
  finding from an adversarial review after re-reading the code, with both hunters' final
  positions. Read-only on source. Dispatched by /adversarial-review only." Body: role, the
  project-guides line, the two Reads, **Input**, **Procedure** (re-read every cited line and its
  callers before ruling; a ruling without `evidence` is not a ruling; prefer a script when the
  claim is about runtime behaviour; `OUTSIDE_REPO` requires `question`), **What you do NOT do**,
  **Output**.
- [ ] **Step 4: Run the check.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** `core/agents/review-judge.md core/scripts/harness-check.sh`,
  `feat(review): review-judge agent`.

### Task 3: Coder findings-only mode

**Files:**
- Modify: `core/agents/coder.md` (§ Input, § Procedure step 1 and step 4, § Output)
- Modify: `core/commands/coder.md`
- Modify: `core/scripts/harness-check.sh` (§5f)

**Interfaces:**
- **Consumes:** the finding shape from Task 1.
- **Produces** a third input: a `findings[]` payload labelled `FIX FROM ADVERSARIAL REVIEW` with a
  `case_file` path and **no spec**. In this mode Coder: never looks under `.claude/specs/`;
  reads the case file's state block for context only; scopes edits to the findings; routes them
  through `superpowers:receiving-code-review`; builds and tests as today.
- **Produces** the status block additions: `spec: n/a` in this mode, and
  `not_applicable: [{id, reason}]` in `payload` (empty list when none).
- **Produces** `/coder --fix-from-adversarial-review [case-file]`: dispatches Coder with the
  `AGREED` blocker/major findings read from the case file's state block (newest
  `.claude/runs/*-adversarial-*.md` when no path is given).

- [ ] **Step 1: Write the failing checks** in §5f: `coder.md` contains
  `FIX FROM ADVERSARIAL REVIEW`, `not_applicable`, and the sentence
  `never fall back to the newest spec`; `commands/coder.md` contains
  `--fix-from-adversarial-review`; `ai-workflow.md` is **not** required to change (the §5
  `pair` lines stay as they are).
- [ ] **Step 2: Run** the check. Expected: 4 FAILs in §5f.
- [ ] **Step 3: Edit `coder.md`.** § Input: add the third bullet and, after the fallback
  sentence, "In findings-only mode (`FIX FROM ADVERSARIAL REVIEW`), never fall back to the
  newest spec: there is none, and the newest one is unrelated." § Procedure step 1: "or, in
  findings-only mode, the case file's state block". Step 4: the `findings[]` bullet also covers
  this label. § Output: `spec: n/a` in this mode; `not_applicable[]` added to the payload list
  with its two fields.
- [ ] **Step 4: Edit `commands/coder.md`:** add the flag to `argument-hint` and one sentence on
  what it dispatches.
- [ ] **Step 5: Run the check.** Expected: `ALL GREEN`.
- [ ] **Step 6: Commit (owner):** `core/agents/coder.md core/commands/coder.md
  core/scripts/harness-check.sh`, `feat(coder): findings-only fix mode for adversarial review`.

### Task 4: the command

**Files:**
- Create: `core/commands/adversarial-review.md`
- Modify: `core/scripts/harness-check.sh` (§5f)

**Interfaces:**
- **Consumes:** `guides/adversarial-review.md` § Procedure, § Case file, § Message shapes (Task
  1); the judge (Task 2); Coder findings-only mode (Task 3).
- **Produces** the orchestrator's final block:

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
- **Produces** the argument grammar
  `[--base=<ref>] [--max-iter=N] [--no-fix] [--auto] [--resume [<case-file>]] [context…]`.

- [ ] **Step 1: Write the failing checks** in §5f: `commands/adversarial-review.md` exists;
  contains `subagent_type: "adversarial-reviewer"`, `subagent_type: "review-judge"`,
  `subagent_type: "coder"`; contains `Read` + `guides/adversarial-review.md` on one line;
  contains `--resume`, `--no-fix`, `--auto`, `--max-iter`, `NO_DIFF`, `STALLED`, `NEEDS_OWNER`;
  contains `SendMessage`, `ToolSearch`, and `by id` (the same-name rule); contains `tree` and
  `restart` (the stale-state rule); contains `AskUserQuestion`; does **not** contain a line
  starting `1. **Hunt` (the procedure lives in the guide, not here).
- [ ] **Step 2: Run** the check. Expected: the new §5f lines FAIL.
- [ ] **Step 3: Write the command.** Frontmatter `description` and `argument-hint` from the
  grammar. Body, in this order:
  - **Contract line:** read the guide; this file selects where things run and holds no
    procedure (mirror `commands/research.md`'s opening).
  - **Input parsing:** each flag; `context…` is everything else, verbatim, passed into both
    capsules; invalid `--max-iter` warns and uses 3.
  - **Branch gate:** as `/feature-flow` Step 0, run only when `--no-fix` is off.
  - **Diff:** the base rule by reference to `reviewer.md` § Procedure 1; empty diff → the final
    block with `NO_DIFF`, nothing written.
  - **New run:** create the case file (date and slug as `/research` does, `-2` suffix on
    collision); write the initial state block; then execute the guide's § Procedure, with these
    locus notes: hunters via `Agent` in **one message** so they run in parallel; later phases via
    `SendMessage` **by agent id** recorded in the state block (load the schema with ToolSearch
    `select:SendMessage` first); the judge via `Agent`; Coder via `Agent` with the
    `FIX FROM ADVERSARIAL REVIEW` payload and the case-file path; ESCALATED questions via
    `AskUserQuestion` unless `--auto`; after every phase, append that phase's blocks to the case
    file verbatim and rewrite the state block at each round boundary.
  - **Resume:** read the state block (newest `*-adversarial-*.md` when no path); recompute
    `tree`; if it differs, say so and restart the current round on the new tree; otherwise
    restart the current round with fresh hunters from the recorded `review_iter` and finding
    states (earlier rounds' states are kept).
  - **Report:** the human-readable recap from the design (verdict, rounds, fixed items with
    Coder notes, ESCALATED questions, STALEMATE chains, minors/nits/contested, the staging test
    plan written by the orchestrator from AGREED and ESCALATED findings, the owner's next
    step), then the final block.
  - **What you do NOT do:** no source edits, no commits, no judging of finding content, never
    collapse the two hunter dispatches into one, never pass round N's findings to round N+1's
    hunters.
- [ ] **Step 4: Run the check.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** `core/commands/adversarial-review.md core/scripts/harness-check.sh`,
  `feat(review): /adversarial-review command`.

### Task 5: bookkeeping

**Files:**
- Modify: `core/CLAUDE.md:58-69` (Guides table, Agents and commands table)
- Modify: `core/guides/ai-workflow.md:8-31` (§ Roles and entry points)
- Modify: `core/agents/reviewer.md:45` (step 3)
- Modify: `core/scripts/harness-check.sh` (§5f)

**Interfaces:**
- **Produces** a Guides row: `adversarial-review.md | /adversarial-review, adversarial-reviewer,
  review-judge, coder (findings-only mode) | running /adversarial-review or dispatching a hunter
  or the judge directly`.
- **Produces** an Agents row: `Adversarial review | adversarial-reviewer, review-judge |
  /adversarial-review` (Coder stays in the Feature workflow row).
- **Produces** in `ai-workflow.md`, after the research-team sentence: one sentence that
  `/adversarial-review` has its own contract in `guides/adversarial-review.md` and reuses Coder in
  findings-only mode.
- **Produces** in `reviewer.md` step 3, after the `code-review.md` sentence: "Also Read
  `.claude/guides/adversarial-review.md` § Finding discipline before writing findings."

- [ ] **Step 1: Write the failing checks** in §5f: `CLAUDE.md` contains `adversarial-review.md`
  and `review-judge`; `ai-workflow.md` contains `adversarial-review.md`; `reviewer.md` contains
  `Read` + `guides/adversarial-review.md` on one line.
- [ ] **Step 2: Run** the check. Expected: 4 FAILs.
- [ ] **Step 3: Make the four edits** per Interfaces.
- [ ] **Step 4: Run the full check.** Expected: `ALL GREEN`, including §4 (no dead links) and §5e
  (the guide's consumers now include `CLAUDE.md`, the command, three agents).
- [ ] **Step 5: Commit (owner):** `core/CLAUDE.md core/guides/ai-workflow.md
  core/agents/reviewer.md core/scripts/harness-check.sh`,
  `docs(harness): index adversarial review in CLAUDE.md, ai-workflow and reviewer`.

### Task 6: live verification

**Files:**
- Create: `<scratchpad>/adversarial-fixture/` (throwaway; never committed)
- Modify: `docs/2026-10-22-adversarial-review-design.md` (append `## Verified` with the results)

**Interfaces:**
- **Consumes:** everything above, installed into the fixture with `bash install.sh
  <fixture>/.claude` from this branch.
- **Produces** the fixture: a Node project with `package.json` (`"build": "node --check
  src/heartbeat.js src/retry.js src/manifest.js src/api.js"`, no test script), one committed
  base commit holding `src/api.js` with a caller that wraps `parseBody` in `try/catch`, and
  **uncommitted** additions:
  - `src/heartbeat.js`: `setInterval(tick, Number(process.env.HEARTBEAT_MS))` with no bounds
    (expected `AGREED`, blocker: ≥ 2^31 ms becomes 1 ms; no minimum)
  - `src/retry.js`: `const now = Date.now(); await send(batch); … nextAt = now + backoff` on
    failure (expected `AGREED`, major)
  - `src/manifest.js`: `if (Object.keys(ids).length === 0) return previous;` on a parsed manifest
    that also carries `updated` (expected `AGREED`, major)
  - `src/api.js`: a new `parseBody(body) { return JSON.parse(body) }` whose only caller is the
    committed try/catch (expected `WITHDRAWN` or `REFUTED`, the guard cited)
  - `.claude/specs/2026-01-01-unrelated-spec.md`: a planted spec about a feature that does not
    exist (Coder must not mention it)
  - `.claude/project.md` with Stack `node`, Build as above, Tests `none`, `shared_branches`
    default.

- [ ] **Step 1: Build the fixture** per Interfaces; `git init`, commit the base, leave the rest
  uncommitted; install the harness from this branch.
- [ ] **Step 2: Run the review** from the fixture directory in a fresh process:
  `claude -p --model claude-opus-5-5 --allowedTools "Agent,SendMessage,ToolSearch,Read,Grep,Glob,Bash,Write,Edit,AskUserQuestion" "/adversarial-review --auto fixture smoke test"`.
  Expected, read from the case file and the final block: three findings `AGREED` at the expected
  files; the `parseBody` finding `WITHDRAWN` or `REFUTED` with the try/catch cited; at least one
  finding carries `provenance: executed` with a scratchpad script; Coder's block has
  `spec: n/a`, `changed_files` covering the three files, and no mention of the planted spec;
  round 2 ends `APPROVED`; `git status` in the fixture shows only Coder's edits plus the
  original uncommitted files.
- [ ] **Step 3: Resume drill.** Reset the fixture to the uncommitted state (`git restore` the
  three files is not enough: re-create them), edit the case file's state block so `tree` is
  wrong, run `/adversarial-review --resume` the same way. Expected: the reply says the tree
  changed and restarts round 1.
- [ ] **Step 4: Stalemate drill**, from this session, no fixture: dispatch `review-judge` with the
  `retry.js` finding and two hand-written final turns (one `MAINTAIN` with the timestamp
  argument, one `CHALLENGE` claiming the SDK retries internally). Expected: `UPHELD` with
  `evidence` naming the line, or `OUTSIDE_REPO` with a `question` about the SDK's retry policy.
  Either is a pass; a ruling with neither is a fail.
- [ ] **Step 5: Record.** Append `## Verified` to the design doc: date, the fixture layout, each
  expectation above with pass/fail, the round count, and the token cost of step 2 from the
  `claude -p` summary.
- [ ] **Step 6: Commit (owner):** `docs/2026-10-22-adversarial-review-design.md`,
  `docs(review): record adversarial-review verification run`.
