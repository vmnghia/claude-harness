# Team flow: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rebuild `/feature-flow` as a lead and a team of persistent peers that ask each other
questions through the lead, are convened for decisions, read one run document, and end with the
adversarial review as the gate.

**Architecture:**
- `guides/ai-workflow.md` stays the one contract and gains § Team protocol (roster, run
  document, five message shapes, bounds, the blocker and question flows, decisions, resume) and
  § Procedure (the step machine the command executes).
- `commands/feature-flow.md` becomes locus and arguments only, like `/research` and
  `/adversarial-review`.
- Coder, Tester, Reviewer and Planner gain `SendMessage` to `main` and a § Team section each.
- The adversarial hunters get one routed question per finding.
- `harness-check.sh` §5 pins the new tokens and a new §5g pins the shapes across files.
- The lead is the main session and the switchboard: every peer message goes to `main` with a
  `to:` and the lead forwards it verbatim.

**Tech stack:** Claude Code agent files, slash commands, `Agent`, `SendMessage`,
`AskUserQuestion`; bash for `harness-check.sh`; a Node fixture for verification.

**Spec:** [2026-10-22-team-flow-design.md](./2026-10-22-team-flow-design.md), including its
Measured facts and the builder-check resolutions.

## Global Constraints

- **Measured and binding:** peers cannot message each other; a subagent's `SendMessage` goes to
  `main` only; the lead forwards. Subagents have no `ListAgents`; ids come from the roster.
- **Message shapes** (YAML in `---` fences, last in the reply, one block per phase asked):
  - `QUESTION`: `id: Q<n>` (the asker numbers its own, prefixed by role letter: `QC1`, `QT1`,
    `QR1`, `QP1`), `from`, `to` (`coder | tester | reviewer | planner | lead`), `about`
    (file:line or spec section), `question` (one line), `options` (≤ 3, each with what the asker
    would do), `blocking: yes | no`.
  - `ANSWER`: `question_id`, `from`, `answer`, `evidence` (file:line or `D<n>`),
    `is_decision: yes | no`.
  - `OBJECTION`: `id: O<n>`, `from`, `decision_id` or `answer_id`, `why`, `evidence`,
    `would_break`.
  - `POSITION`: `question_id`, `from`, `position`, `reasons` (≤ 3), `risk`.
  - `DECISION`: `id: D<n>`, `by: lead | council | owner | assumed`, `question_id`, `question`,
    `decision`, `applies_to: [...]`, `supersedes: D<m>` (optional).
- **Bounds:** one follow-up per question, then accept or object. A council is one `POSITION`
  per peer; a second round only on a factual contradiction, on that fact only. A message with no
  new evidence is that peer done (the adversarial evidence gate). Cost line before every council
  round. Owner questions batched at a step boundary unless a peer is blocked now.
- **Blocking question = the asker stops** and ends its reply with the `QUESTION` block (no status
  block). The lead answers or decides, sends the `DECISION`/`ANSWER` to everyone in
  `applies_to`/the asker, then resumes the asker by `SendMessage`. Non-blocking: the asker sends
  the `QUESTION` to `main` by `SendMessage` and continues on its stated default; the lead delivers
  the `ANSWER` by `SendMessage` when it has it.
- **Counters:** `test_iter`, `review_iter` (cap 3, `--max-iter`), `gate_iter` (cap 2,
  `--max-gate-iter`). Tester re-runs after every gate fix; Reviewer does not.
- **Statuses (orchestrator):** `READY_FOR_HUMAN_APPLY | BUG_LIMIT_REACHED | REVIEW_LIMIT_REACHED |
  BLOCKED | NEEDS_CLARIFICATION | NEEDS_OWNER | STALLED`. The gate's cap also ends in
  `REVIEW_LIMIT_REACHED` with the summary naming the gate.
- **Run document:** `.claude/runs/YYYY-MM-DD-<slug>.md`, lead the only writer, first fenced block
  the state block (`step`, `test_iter`, `review_iter`, `gate_iter`, `roster`, `decisions[]`,
  `open_questions[]`, `assumptions[]`), then verbatim appends.
- **`--auto`:** owner-only question → council; converged → `by: assumed`, continue, list in recap;
  conflict → `NEEDS_OWNER` at the boundary.
- **`--resume [<run-document>]`:** re-dispatch Planner (subagent), Coder, Tester, Reviewer fresh
  with spec, plan, decisions and the standby brief; new roster; restart the current step;
  counters kept; the gate resumes per its guide.
- **Standalone dispatch** (`/coder`, `/tester`, `/reviewer`, no roster): the agent behaves as
  today; the § Team section applies only when the capsule carries a roster.
- **Tool boundaries:** `SendMessage` may appear in the `tools:` of exactly `coder`, `tester`,
  `reviewer`, `planner`, `research-lead`, `incident-investigator`. Hunters and judge never.
- **No agent commits.** Branch `feat/team-flow`; the owner commits; `leak-check` clean; every new
  check in one section `== 5g. Team flow (2026-10-22) ==` after §5f.

## Review Focus

1. **A `DECISION` must reach Tester and Reviewer before they act on the affected code**, or the
   fragmentation returns. Pinned by Task 1 step 1 (the guide orders "send DECISION to
   applies_to, then resume the asker") and Task 6's run (Tester's block cites the decision id).
2. **An `OBJECTION` to an owner-made decision** cannot be settled by the lead or a council; it
   goes back to the owner, or ends `NEEDS_OWNER` under `--auto`. Pinned by Task 1 step 1 (guide
   text) and a §5g token.
3. **A blocking `QUESTION` with no status block** must not be read by the lead as a finished
   step. Pinned by Task 1 (the guide says a reply ending in `QUESTION` is a pause, counters
   untouched) and Task 4 (the command's step machine branches on it).
4. **A non-blocking `ANSWER` delivered while the asker is busy** must not be lost. Unmeasured:
   Task 6 measures it; the fallback written into the guide is "deliver when the asker next goes
   idle, before any resume for another reason".
5. **`--resume` after a dead session must not reuse dead ids.** Pinned by Task 4 step 1 (the
   command text says every id is re-dispatched) and Task 6's resume drill.

---

### Task 1: the contract — § Team protocol and § Procedure in `ai-workflow.md`

**Files:**
- Modify: `core/guides/ai-workflow.md` (new sections after § Branch policy; edits to § Status
  block contract, § Iteration policy, § Tool boundaries, § Run log, § What ends the flow)
- Modify: `core/scripts/harness-check.sh` (new §5g, created here)

**Interfaces:**
- **Produces** `## Team protocol` with subsections, these exact headings: `### Roster and run
  document`, `### Message shapes`, `### Questions`, `### Blockers and decisions`, `### Councils`,
  `### Bounds`, `### Resume`. Content per Global Constraints and the design.
- **Produces** `## Procedure` with the numbered steps 0–7 from the design § The flow, each step
  naming the dispatch or resume it makes, the blocks it waits for, and the branch on each. Step
  2 names the standby brief verbatim: the spec path, the plan path, the roster so far, "read the
  run document's decisions when the lead calls you; until then answer peers' questions sent to
  you by the lead".
- **Produces** in § Status block contract: `agent: orchestrator` now also `lead`; two optional
  fields on every peer block, `decisions_applied: [D…]` and `questions_asked: [Q…]`; the
  `DECISION` `by:` enum.
- **Produces** in § Iteration policy: `gate_iter`, cap 2, `--max-gate-iter=N`; Tester after gate
  fixes; Reviewer not.
- **Produces** in § Tool boundaries: a `SendMessage` column, ✅ `main only` for Coder, Tester,
  Reviewer, Planner (subagent).
- **Produces** in § What ends the flow: the seven statuses and the recap's decisions list.

- [ ] **Step 1: Write the failing checks.** New §5g in `harness-check.sh` with
  `WF="$H/guides/ai-workflow.md"` already set: each of the seven `### ` headings present; tokens
  `QUESTION`, `ANSWER`, `OBJECTION`, `POSITION`, `DECISION`, `decisions_applied`,
  `questions_asked`, `gate_iter`, `--max-gate-iter`, `by: lead | council | owner | assumed`,
  `NEEDS_OWNER`, `then resume the asker`, `cannot be settled by the lead`, `when the asker next
  goes idle`, `main only`. (The negative check that the command no longer holds the procedure
  belongs to Task 4, where the command changes.)
- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh | grep -E 'FAIL|5g'`. Expected: every
  §5g line FAILs.
- [ ] **Step 3: Write § Team protocol and § Procedure** per Interfaces, and the four section
  edits. Keep § Context capsule template; add to it "the roster, when known".
- [ ] **Step 4: Run the check.** Expected: §5g PASS; §5 `pair` lines still PASS; `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** `core/guides/ai-workflow.md core/scripts/harness-check.sh`,
  `feat(team): team protocol and procedure in ai-workflow.md`.

### Task 2: the peers — Coder, Tester, Reviewer, Planner

**Files:**
- Modify: `core/agents/coder.md` (frontmatter `tools:`; § Input; § Procedure step 4; new § Team;
  § What you do NOT do; § Output)
- Modify: `core/agents/tester.md` (same shape; new bug-or-decision step in § Procedure)
- Modify: `core/agents/reviewer.md` (same shape; rationale question in § Procedure)
- Modify: `core/agents/planner.md` (§ Mode detection: a third mode, standby; `tools:`)
- Modify: `core/scripts/harness-check.sh` (§5g; §5 `pair` lines)

**Interfaces:**
- **Consumes:** the shapes and bounds from Task 1.
- **Produces** in each peer a `## Team` section with these exact subheadings: `### When you ask`,
  `### When you are asked`, `### When a decision arrives`, `### When you object`, and the line
  "Without a roster in your capsule, this section does not apply and you work as before."
- **Produces** `tools:` lines: Coder `Read, Edit, Write, Grep, Glob, Bash, NotebookEdit, Skill,
  SendMessage`; Tester its current list plus `SendMessage`; Reviewer `Read, Grep, Glob, Bash,
  Agent, SendMessage`; Planner its current list plus `SendMessage`.
- **Produces** Coder: a blocking `QUESTION` replaces guessing; `BLOCKED` only for the
  unanswerable (missing system, denied command, destructive need); `decisions_applied` in its
  block; findings-only mode unchanged.
- **Produces** Tester § Procedure, before "report a failure": check `decisions`; one `QUESTION`
  to Coder per suspected decision; `is_decision: yes` + `D<n>` → not a failure, cite it;
  `is_decision: yes` without `D<n>` → `QUESTION` to the lead to record or overrule;
  disagreement → `OBJECTION`.
- **Produces** Reviewer § Procedure: one `QUESTION` to Coder per would-be convention finding;
  a `D<n>` in the answer closes it; spec/stack findings never need the question.
- **Produces** Planner: standby mode = dispatched with the spec and a roster, answers `POSITION`
  requests for intent and `QUESTION`s about the spec, writes nothing.

- [ ] **Step 1: Write the failing checks** in §5g: for each of the four agents, the four `### `
  subheadings and the no-roster sentence; `tools_of` contains `SendMessage` for exactly those
  four plus `research-lead` and `incident-investigator` (loop over `"$H"/agents/*.md`, FAIL on
  any other); `pair "decisions_applied" coder.md`, `pair "QUESTION" coder.md`,
  `pair "is_decision" tester.md`, `pair "OBJECTION" tester.md`, `pair "POSITION" planner.md`,
  `pair "rationale" reviewer.md` added to §5.
- [ ] **Step 2: Run** the check. Expected: the new §5g and §5 lines FAIL.
- [ ] **Step 3: Edit the four agents** per Interfaces. Keep every existing rule; add, do not
  rewrite. Tester keeps `dispatcher_session`.
- [ ] **Step 4: Run the check.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** the four agents + `harness-check.sh`,
  `feat(team): peers ask, answer, object and apply decisions`.

### Task 3: the hunters' routed question

**Files:**
- Modify: `core/guides/adversarial-review.md` (§ Message shapes hunt reply; § Procedure round
  step 1–2; § Debate rules end states)
- Modify: `core/agents/adversarial-reviewer.md` (§ Procedure)
- Modify: `core/scripts/harness-check.sh` (§5g)

**Interfaces:**
- **Produces** in the hunt reply: `payload.questions: [{finding_id, to: coder, question}]`, at most
  one per finding, relayed by the orchestrator to Coder **through the lead** before
  cross-examination; the answers are appended to the capsule for cross-examination.
- **Produces** the rule: an answer citing `D<n>` makes the finding `WITHDRAWN` at
  cross-examination unless the hunter objects to the decision itself, which becomes an
  `OBJECTION` to the lead (recorded, not debated).
- In the standalone `/adversarial-review` there is no Coder to ask: `questions` are reported to
  the owner in the recap and the finding proceeds as today.

- [ ] **Step 1: Write the failing checks** in §5g: guide contains `questions:` in the hunt reply
  and `WITHDRAWN` + `D<n>` in one sentence (token: ``citing `D<n>` ``); hunter contains
  `questions`.
- [ ] **Step 2: Run.** Expected: 3 FAILs.
- [ ] **Step 3: Make the three edits.**
- [ ] **Step 4: Run.** Expected: `ALL GREEN` (including §5f, untouched).
- [ ] **Step 5: Commit (owner):** `feat(review): hunters may route one question per finding to Coder`.

### Task 4: the command

**Files:**
- Rewrite: `core/commands/feature-flow.md`
- Modify: `core/scripts/harness-check.sh` (§5g)

**Interfaces:**
- **Consumes:** § Procedure and § Team protocol (Task 1); the peers (Task 2); the gate
  (`guides/adversarial-review.md` § Procedure).
- **Produces** the argument grammar: `<requirement | FRONT-XXXX> [--auto] [--no-test]
  [--max-iter=N] [--max-gate-iter=N] [--resume [<run-document>]]`.
- **Produces** the command body, in order: contract line (Read `ai-workflow.md`, execute its
  § Procedure, hold no procedure here); § Input; § Where each phase runs (branch gate; planning
  inline vs subagent; the one-message dispatch of Coder, Tester, Reviewer and standby Planner;
  the switchboard rule: a reply ending in `QUESTION` or a `SendMessage` from a peer is
  forwarded verbatim to its `to:` by agent id, never by name; `DECISION` to every `applies_to`
  before resuming the asker; councils as one message to every peer; the owner pause via
  `AskUserQuestion` with positions attached; the gate as `/adversarial-review`'s procedure with
  this session as orchestrator and Coder resumed, not re-dispatched); § Resume (every id is
  dead: re-dispatch all four fresh with decisions; restart `step`); § Report; final block;
  § What you do NOT do.
- **Produces** the final block: `agent: lead`, the seven statuses, `spec`, `test_iter`,
  `review_iter`, `gate_iter`, `run_document`, `summary`.

- [ ] **Step 1: Write the failing checks** in §5g: command contains `Read` + `ai-workflow.md` on
  one line; tokens `--max-gate-iter`, `--resume`, `switchboard`, `by agent id`, `every id is
  dead`, `AskUserQuestion`, `adversarial-review.md`, `agent: lead`, `gate_iter`; does **not**
  contain a line starting `### Step 3 — Coder` or `### Step 4 — Tester` (procedure moved out).
- [ ] **Step 2: Run.** Expected: the token lines FAIL; the two negatives FAIL (the old file has
  those headings).
- [ ] **Step 3: Rewrite the command** per Interfaces.
- [ ] **Step 4: Run.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** `feat(team): /feature-flow as lead and switchboard`.

### Task 5: bookkeeping

**Files:**
- Modify: `core/CLAUDE.md` (Agents and commands table: Feature workflow row → "Team flow";
  Guides table `ai-workflow.md` consumers)
- Modify: `docs/2026-10-22-adversarial-review-design.md` (one line under § Verified: the gate is
  now also reached from `/feature-flow`)
- Modify: `core/scripts/harness-check.sh` (§5g)

- [ ] **Step 1: Write the failing checks:** `CLAUDE.md` contains `Team flow` and `switchboard`.
- [ ] **Step 2: Run.** Expected: 2 FAILs.
- [ ] **Step 3: Edit** the two tables and add the design line.
- [ ] **Step 4: Run the full check.** Expected: `ALL GREEN`, §4 no dead links.
- [ ] **Step 5: Commit (owner):** `docs(harness): index the team flow`.

### Task 6: live verification

**Files:**
- Create: `<scratchpad>/team-fixture/` (throwaway, never committed)
- Modify: `docs/2026-10-22-team-flow-design.md` (append `## Verified`)

**Interfaces:**
- **Produces** the fixture: a Node project with `npm run build` = `node --check`, no tests, a
  filled `project.md`, and a spec under `.claude/specs/` that asks for a small CLI that lists
  items from a JSON file and is **silent on sort order and on the empty-file message**; the
  spec's Test Scenarios include "lists three items" and "empty file prints a message"; the
  project's `rules/project/` carries one convention the spec invites breaking (no `console.log`
  outside `src/cli.js`); a planted defect in an existing helper the feature must call (a
  `JSON.parse` on a possibly-undefined value).
- The harness installed from this branch with `install.sh`.

- [ ] **Step 1: Build the fixture.**
- [ ] **Step 2: Run `--auto`** in a fresh process: `claude -p "/feature-flow --auto <requirement>"
  --model claude-opus-5-5 --output-format json --allowedTools "Agent,SendMessage,ToolSearch,
  Read,Grep,Glob,Bash,Write,Edit,Skill,AskUserQuestion"` from the fixture. Expected, from the
  run document: Coder stops with a blocking `QUESTION` on sort order or the empty message and
  does not guess; a council round with four `POSITION` blocks; a `DECISION` with `by: assumed`
  sent to `applies_to` before Coder is resumed; Coder resumed by message, not re-dispatched (one
  Coder id in the roster for the whole run); Tester's block cites the decision id and files no
  failure on it; Reviewer asks Coder about the `console.log` and files the finding when Coder
  cannot cite a decision; the gate finds the `JSON.parse` defect and Coder fixes it in
  findings-only mode; Tester re-runs after the gate fix; final `READY_FOR_HUMAN_APPLY` with the
  assumptions listed. Record cost.
- [ ] **Step 3: Measure the non-blocking path.** In the same run document, find at least one
  non-blocking `QUESTION` and whether its `ANSWER` reached the asker while busy (its next block
  lists the id in `questions_asked` with an answer applied) or only at its next idle. Write the
  measured behaviour into § Team protocol § Questions (replace the fallback sentence if the
  busy delivery works).
- [ ] **Step 4: Resume drill.** Kill the run mid-coding (a second fixture run with
  `--max-iter=1` interrupted after Coder's first `QUESTION`, or edit the state block to
  `step: coding` with dead ids), run `/feature-flow --resume`. Expected: four new ids in the
  roster, the decisions re-sent in the capsules, coding restarted, counters kept.
- [ ] **Step 5: Record** `## Verified` in the design doc: each expectation with pass/fail, the
  measured busy-delivery fact, costs.
- [ ] **Step 6: Commit (owner):** `docs(team): record the team-flow verification run`.
