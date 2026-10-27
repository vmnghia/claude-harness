# Research critique: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** peer review for `/research`: fresh critics try to break `findings.md`, the lead answers
as the author, a fresh judge rules on what they cannot settle, the owner settles the rest — on by
default, `--no-critique` to skip, `--critique <folder>` to run alone.

**Architecture:**
- The critique **procedure** lives in `core/guides/research-workflow.md` (new `## Critique`
  section: the round, the rebuttal, the dry loop, closing the run, the case file). The
  **message shapes** it adds live in `core/guides/adversarial-review.md` § Message shapes as a
  "Critique variants" subsection, so every block shape keeps one home. The command selects
  where each phase runs and adds the two flags; it holds no procedure.
- Two new agents, `research-critic` (×width, angles) and `research-judge` (fresh per dispute),
  both read-only on the repo, both under `review-bash-gate.sh` with one extra allowance,
  `verify-quote.sh`.
- The lead's run splits into *gather and draft* (today's steps 1–7, first return) and *finish*
  (after "critique settled": `## Critique`, `disputed` rows, Answer/Next, then the Confluence
  draft). It answers the critique with a `REBUTTAL` block and edits `findings.md` itself.
- The knobs are the thoroughness guide's: critic width, `K`, the ceiling with the critique's
  reserve now subtracted. `harness-check.sh` gains §5i, red-first per task; §5b and §2i extend.

**Tech Stack:** Claude Code agent files, slash commands and guides (Markdown + YAML
frontmatter); bash + node for `review-bash-gate.sh`; bash for `harness-check.sh`.

**Spec:** [2026-10-27-research-critique-design.md](./2026-10-27-research-critique-design.md),
on top of [2026-10-27-thoroughness-knobs-design.md](./2026-10-27-thoroughness-knobs-design.md)
(merged 2026-10-27 as `3d16b9f`; its guide `core/guides/thoroughness.md` is the source of every
number here).

## Global Constraints

- **Critics:** `research-critic`, `model: claude-opus-5-5`, `tools: Read, Bash, WebFetch` —
  no `Write`/`Edit`/`Agent`/`Grep`/`Glob`/`SendMessage`, no Atlassian tools. Width from
  `knobs.width.research-critic` (2 / 3 / 5); angles `evidence-first`, `argument-first`,
  `scope-and-decisions`, cycling above three; roles `critic-A` … `critic-H`.
- **Judge:** `research-judge`, same model and tools; rules `UPHELD | REFUTED | OUTSIDE_RUN`;
  `question` required with `OUTSIDE_RUN`; one challenge turn per side, one judge reply, a second
  `CHALLENGE` is `STALEMATE`.
- **Never-read list** (critic and judge): every investigation folder but the run's own,
  `.claude/runs/` (the critique case file included), `.claude/reports/`, `.remember/`; they
  gather no new evidence (no `searcher`/`web-reader`); an uncheckable load-bearing claim is
  `unverifiable`, a finding.
- **Gate:** `review-bash-gate.sh` applies to `agent_type` `research-critic` and
  `research-judge` with the hunters' allowlist plus exactly one addition for those two types:
  `bash <…>/.claude/scripts/verify-quote.sh <url> "<quote>"`. Hunters stay denied that.
- **Finding shape:** `id, severity, target, claim (verbatim), kind (unsupported | mislabelled |
  null-without-control | non-sequitur | alternative | settled | scope), trigger, consequence,
  suggestion, provenance (read | inferred | executed), evidence`. Severity: `blocker` = Answer
  or Next would change; `major` = load-bearing claim mislabelled/unpinned, null without control,
  settled item re-raised, question not answered; `minor` = the same on a non-load-bearing claim;
  `nit` = presentation. The ladder past one cross-examination is `blocker`/`major` only.
- **Round:** hunt (critics in one message, no `questions[]`) → N-way cross-examination
  (thoroughness design; `minor`/`nit` end here) → rebuttal (one `SendMessage` to the lead; reply
  `REBUTTAL` with per-finding `FIX | MAINTAIN | OUTSIDE_RUN`; `FIX` applied before replying;
  `MAINTAIN` carries `new_evidence`) → re-check (critic ↔ lead turns; evidence gate, exhaustion,
  8-turn cap as the adversarial guide) → judge → synthesis. End states `FIXED | AGREED |
  WITHDRAWN | REFUTED | ESCALATED | STALEMATE | CONTESTED`.
- **Dry loop:** `K = 0` → exactly one round; otherwise a further round after any non-dry round,
  `K` consecutive dry rounds or `2K` further rounds end it (recap says "cut at its cap");
  duplicate = same `target` and (same `kind` or 60 % of `claim` words); at most `1 + 2K` rounds.
- **Closing:** "critique settled" → the lead writes `## Critique` (template table: `Claim
  (quoted) | Verdict | Severity | Evidence`, plus the case-file path), `disputed` Open rows,
  rewrites Answer/Next if a `FIXED` finding touched them, bumps `updated`, Log line, **then** the
  Confluence draft, returns `critique: {rounds, findings, fixed, agreed, withdrawn, refuted,
  disputed}`. A `disputed` `blocker`/`major` → `AWAITING_HUMAN`, `action: "answer the disputed
  questions in Open (<ids>)"`, frontmatter `open`; `--resume` sends "done: <answers>" → Decisions
  rows → `ANSWERED`/`settled` or `PARTIAL`/`open`. `disputed` `minor`/`nit` leave the status.
- **No lead:** `SendMessage` fails → `critique.md` records `rebuttal: unavailable`, no
  `findings.md` edit, report shows the table beside the untouched Answer; never a fresh lead.
- **Standalone:** `/research --critique <folder>`: the no-lead path on an existing folder, any
  status, `critique.md` in that folder (`-2` on collision), never edits `findings.md`; `--resume`
  on a finished run never starts a critique.
- **Case file:** `<folder>/critique.md`, written by the main session only (the second
  main-session file; the single-writer rule says so); state block `critique_round, dry_rounds,
  knobs, rebuttal: lead | unavailable, critics: {A, B, …}, findings: [{id, dup, severity, target,
  state, issue}], disputed: [{id, question}]`; verbatim appends `### Hunt A|B|C`,
  `### Cross-examination`, `### Rebuttal`, `### Re-check`, `### Judge <id>`, `### Synthesis`.
- **Ceiling:** `/research` reserves `critic width × (K + 1) + critic width` before the lead and
  passes the remainder as the lead's `max_agents`; the critique counts against what the lead left
  of the whole; a `FIX` re-dispatch counts toward the lead's share and that teammate's cap; a
  cap-exhausted `FIX` moves the claim to Open, never silently dropped.
- **Skips:** `--no-critique`, `--effort=quick`, lead status `STOPPED`; on `AWAITING_HUMAN` the
  critique waits for the resume that ends in `ANSWERED`/`PARTIAL`.
- No `*` in any `tools:` line; agent files load at session start (test in a fresh `claude -p`);
  lines ≤ 100 chars; nothing project-specific (leak-check); commit on the owner's go only; never
  push.

## Review Focus

1. The lead's session has ended when the critique finishes → `rebuttal: unavailable`, the report
   shows the critique table beside the untouched Answer with one line saying the author never
   answered (Task 1 lint: `rebuttal: unavailable` in § Critique; Task 5 lint: the same in the
   command's Report).
2. `--critique <folder>` on a folder with no `findings.md`, or with `status: stopped` → stops
   with a one-line reason, writes nothing (Task 5 lint: `no findings.md` and `stopped` in the
   command's § Input).
3. Every critic returns `CLEAN` → no manufactured finding, `## Critique` says "no findings", the
   status is unchanged (Task 2 lint: "Zero findings is a valid result" in the critic; Task 4
   lint: `no findings` in the lead's finish step).
4. A `disputed` `blocker` → `AWAITING_HUMAN` with the `action` naming the ids and frontmatter
   `open`, never `settled` (Task 4 lint tokens `answer the disputed questions` and `never
   \`settled\``).
5. A `FIX` that needs a teammate past its cap → the claim moves to Open with the gap named, the
   rebuttal still answers it (Task 4 lint: `cap` inside the rebuttal bullet).

---

### Task 1: the contract — § Critique in research-workflow.md, the shapes, the template

**Files:**
- Modify: `core/guides/research-workflow.md` (§ Flow and roles diagram and the single-writer
  paragraph ~41; § Status blocks table ~128; new `## Critique` before `## Tool boundaries and
  lint` ~187)
- Modify: `core/guides/adversarial-review.md` (§ Message shapes: new `### Critique variants`
  after `### Orchestrator, final` ~428)
- Modify: `core/templates/findings-template.md` (`## Claims checked` ~82 → `## Critique`)
- Modify: `core/scripts/harness-check.sh` (new `== 5i. Research critique (2026-10-27) ==` after
  §5h, before `== 6.`)

**Interfaces:**
- **Produces** `research-workflow.md § Critique` with subsections `### The round`,
  `### Rebuttal`, `### Dry loop`, `### Closing the run`, `### Case file`, `### Standalone`,
  holding the Global Constraints' Round, Dry loop, Closing, No lead, Standalone, Case file and
  Ceiling rules as normative text (every enum and field name as written above).
- **Produces** `adversarial-review.md § Message shapes › ### Critique variants`: the critique
  finding (the fields above, as a YAML block), the **critique capsule** (role/angle, folder
  path, resolved knobs, the framing's question verbatim, `project.md` § Stack verbatim, the
  scratchpad path, the case-file path, the never-read list; never the lead's transcript or the
  other critics' output), the **critique message** (orchestrator → lead), the `REBUTTAL` block
  (`responses: [{id, response: FIX | MAINTAIN | OUTSIDE_RUN, new_evidence, edit, redispatch,
  question}]`), the **re-check message** (orchestrator → critic: the lead's responses on its
  findings and the current `findings.md`; `FIX` → `ACCEPT` = `FIXED` or `CHALLENGE`), the judge
  capsule and reply with `OUTSIDE_RUN`, and the sentence "everything else is the hunter shape
  with `agent: research-critic` and `role: critic-A | … | critic-H`".
- **Produces** status rows in § Status blocks: `research-critic` — `FINDINGS` / `CLEAN`
  (hunt), `RULINGS`, `TURN`; `research-judge` — `UPHELD` / `REFUTED` / `OUTSIDE_RUN`;
  `research-lead` gains `REBUTTAL` (phase block) and the `critique` payload field.
- **Produces** `findings-template.md` `## Critique` with the comment "every kind: the critique's
  checked-claim table, one row per finding, verdict = its end state; a run without findings says
  `no findings`; names the critique case file".
- **Produces** the §5i header and `RW`, `AR`, `FT="$H/templates/findings-template.md"` bound
  for Tasks 2–5.

- [ ] **Step 1: Write the failing checks** in a new §5i: `grep -qxF '## Critique' "$RW"`; the
  six `### ` subsection names inside § Critique (`sed -n '/^## Critique/,/^## Tool/p'`); tokens
  inside it: `FIXED`, `REBUTTAL`, `OUTSIDE_RUN`, `rebuttal: unavailable`, `critique.md`,
  `second main-session file`, `--critique`, `1 + 2K`, `60 %`, `never edits`, `critic width ×
  (K + 1)`; in `$AR`: `### Critique variants`, and inside it `research-critic`, `critic-H`,
  `null-without-control`, `response: FIX | MAINTAIN | OUTSIDE_RUN`, `new_evidence`, `re-check`;
  § Status blocks rows `^| research-critic |` and `^| research-judge |`, and `critique` on the
  `^| research-lead |` row; `grep -qxF '## Critique' "$FT"` and a negative on `## Claims
  checked`; the single-writer paragraph mentions `critique.md`.
- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh 2>&1 | sed -n '/== 5i/,$p'`.
  Expected: every new line FAIL; §8 (findings template core) still green.
- [ ] **Step 3: Write `## Critique`** in `research-workflow.md` from the spec § "The round",
  § "Closing the run", § "Case file", § "Standalone", § "Knobs" as rules: numbered steps 1–9
  with the message names from the shapes; the dry loop with its duplicate rule and bound; the
  case-file state block as a YAML example; the standalone paragraph; the ceiling reserve
  sentence. Update the § Flow and roles diagram (a `critique` stage between the lead's return
  and the report) and the single-writer paragraph (`critique.md` is the **second main-session
  file**, those words). Add the status rows and the lead's `REBUTTAL`/`critique` entries.
- [ ] **Step 4: Write `### Critique variants`** in `adversarial-review.md` (the blocks above,
  each a fenced YAML in the file's style) and the template's `## Critique` block.
- [ ] **Step 5: Run the check.** Expected: §5i Task-1 lines green; §5b, §5f, §5h, §8 green.
- [ ] **Step 6: Commit (owner's go):** the four files,
  `feat(research): critique contract — round, rebuttal, shapes, template`.

### Task 2: the critic and the judge

**Files:**
- Create: `core/agents/research-critic.md`, `core/agents/research-judge.md`
- Modify: `core/guides/research-workflow.md` (§ Tool boundaries and lint: two rows; the model
  pins table; the §5b description items 1, 3, 4)
- Modify: `core/scripts/harness-check.sh` (§5b `RESEARCH_AGENTS` gains both; §5i agent checks)

**Interfaces:**
- **Consumes** Task 1's shapes and § Critique by section reference.
- **Produces** `research-critic.md`: frontmatter `name`, `description` ("Dispatched by /research
  only, N per critique round with a critique capsule; not for direct use"), `tools: Read, Bash,
  WebFetch`, `model: claude-opus-5-5`; body: role ("one of N critics; the author will answer
  you; the other critics will cross-examine you"), the project-guides line
  (`rules/project/guides-index.md`), Reads (`research-discipline.md`, `research-workflow.md`
  § Critique, `adversarial-review.md` § Finding discipline + § Debate rules + § Message shapes,
  `thoroughness.md § Angles` for the cycling rule only — the three critic angle orderings from
  the spec § "What a critic checks" are written in the critic file itself), **Input** (the
  critique capsule), **Procedure** (read the folder
  in full; work the seven checks in angle order — the spec § "What a critic checks" verbatim as
  the rubric; re-open every cited piece of evidence: `git show <sha>:<path>`, the `results.txt`
  marker, `verify-quote.sh` for a quote; `executed` means a re-run check; the pre-report gate;
  "Zero findings is a valid result"; cross-examine when asked; take turns with the lead when
  asked; answer a judge ruling with one turn), **What you do NOT do** (no Write/Edit, no
  dispatch, no new evidence, the never-read list, `20 lines` of prose before the block, `only
  the field names` the shapes define), **Output** (the hunt / rulings / turn blocks with `agent:
  research-critic`, `role: critic-<letter>`).
- **Produces** `research-judge.md`: same frontmatter pattern; the `review-judge` framing ("fresh
  on purpose") with evidence of the research kind; **Input** (the folder path, one finding, the
  critic's and the lead's final turns verbatim, every script path either side produced, the
  scratchpad path, the never-read list); **Procedure** (re-open every pin, marker, quote and
  ledger row both sides cite; re-run what was run; `UPHELD`/`REFUTED`/`OUTSIDE_RUN` with
  `question` required; one challenge reply); the judge block with `agent: research-judge`.

- [ ] **Step 1: Write the failing checks.** In §5b: add `research-critic research-judge` to
  `RESEARCH_AGENTS`; extend the status-token loop (`FINDINGS` / critic, `UPHELD` / judge in both
  the agent file and `$RW`); extend the tool-boundary loop (neither has `Agent`, `Write`, `Edit`,
  `Grep`, `Glob`, `SendMessage`; both have `WebFetch` and `Bash`); model pins
  `claude-opus-5-5` for both. In §5i: `tools_of` is exactly `Read, Bash, WebFetch` for both;
  both Read `guides/research-workflow.md` and `guides/adversarial-review.md` and
  `rules/research-discipline.md`; critic mentions `critic-A`, `critic-H`, `evidence-first`,
  `argument-first`, `scope-and-decisions`, `verify-quote.sh`, `Zero findings is a valid
  result`, `unverifiable`, `.remember/`, `20 lines`, `only the field names`; judge mentions
  `UPHELD`, `REFUTED`, `OUTSIDE_RUN`, `question:`, `.remember/`, `20 lines`; both descriptions
  contain `/research`; $RW tool table has `^| research-critic |` and `^| research-judge |`
  rows and the model-pins table names both.
- [ ] **Step 2: Run the check.** Expected: the new §5b and §5i lines FAIL (`research-critic.md
  missing`, …).
- [ ] **Step 3: Write both agent files** per Interfaces, and the two guide tables plus the §5b
  description items.
- [ ] **Step 4: Run the check.** Expected: ALL GREEN except Tasks 3–5's lines (none yet).
- [ ] **Step 5: Commit (owner's go):** `feat(research): research-critic and research-judge agents`.

### Task 3: the Bash gate

**Files:**
- Modify: `core/hooks/review-bash-gate.sh` (header comment; line ~55 agent-type test; a new
  allow branch inside `verdict()` for `verify-quote.sh`; the deny message)
- Modify: `core/guides/adversarial-review.md` § Tool boundaries (the "applies itself only when
  `agent_type` is …" sentence names four types; one sentence on the critic/judge addition)
- Modify: `core/scripts/harness-check.sh` (§2i matrix rows)

**Interfaces:**
- **Consumes** `rgate <expected-exit> <label> <command> [agent_type] [cwd]` (§2i helper).
- **Produces** the gate rule: for `agent_type` `research-critic` or `research-judge` only, a
  command whose first word is `bash` and whose second word matches
  `^(\./|/[^\s]+/)?\.claude/scripts/verify-quote\.sh$` with no `..`, followed by exactly two
  arguments (the URL and the quote, each a single quoted or unquoted word), is allowed; every
  other rule of the gate is unchanged for all four types. `verdict()` receives `who`.

- [ ] **Step 1: Write the failing checks** in §2i:
  `rgate 0 "critic: verify-quote" 'bash .claude/scripts/verify-quote.sh https://example.com/x "a quote"' research-critic`;
  the same with `research-judge`; `rgate 2 "hunter: verify-quote denied" '…' adversarial-reviewer`;
  `rgate 2 "critic: verify-quote with .."` using `.claude/scripts/../scripts/verify-quote.sh`;
  `rgate 2 "critic: verify-quote three args"`; `rgate 2 "critic: other script" 'bash .claude/scripts/harness-check.sh' research-critic`;
  `rgate 0 "critic: git show pinned" 'git show abc123:src/x.ts' research-critic`;
  `rgate 2 "critic: git add" 'git add -A' research-critic`.
- [ ] **Step 2: Run the check.** Expected: today the gate allows every caller but the two hunter
  types, so the `rgate 0` critic/judge lines PASS vacuously and every `rgate 2` critic/judge line
  (the `..` path, three args, the other script, `git add`) FAILs — those four are the red lines;
  the hunter denial of `verify-quote.sh` already PASSes. The report names which lines were red.
- [ ] **Step 3: Implement.** The agent-type test becomes a set of four; `verdict(cmd, cwd, who)`;
  the new branch is checked before the generic command-word allowlist and only when `who` is a
  critic or judge; the header comment and the deny message name the four types and the one
  addition. Update the guide's § Tool boundaries sentence.
- [ ] **Step 4: Run the check.** Expected: §2i all PASS (the existing matrix unchanged), ALL GREEN.
- [ ] **Step 5: Commit (owner's go):** `feat(hooks): review-bash-gate covers research-critic and research-judge; verify-quote allowed`.

### Task 4: the lead as author

**Files:**
- Modify: `core/agents/research-lead.md` (§ Role; § Running the team step 7 ~186 and step 8
  ~195; new steps for the rebuttal and the finish; § Output)

**Interfaces:**
- **Consumes** Task 1's `REBUTTAL` block, critique message and "critique settled" message.
- **Produces** the lead's two-phase procedure: step 7 becomes "**Draft and return**" (Answer,
  Next, Lessons, frontmatter as today; return `ANSWERED`/`PARTIAL`; the Confluence draft is
  **not** written here when the capsule says `critique: on`); new step 8 "**Rebuttal**" (on the
  critique message: per finding `FIX` — edit `findings.md` in place per the template's
  supersede rule, Log line, optional re-dispatch within caps, a cap-exhausted `FIX` moves the
  claim to Open; `MAINTAIN` with `new_evidence`; `OUTSIDE_RUN` with the one question; reply
  with the `REBUTTAL` block; take turns with the asserting critic as the adversarial guide's
  asserter; accept an `UPHELD` as a `FIX`); new step 9 "**Finish**" (on "critique settled":
  `## Critique` table or `no findings`, `disputed` rows, Answer/Next rewrite, `updated`, Log,
  a `Lessons` row for any finding the lead's own step 5 spot-check should have caught, the
  status rule with `AWAITING_HUMAN` for a `disputed` `blocker`/`major` and `never
  \`settled\``); old step 8 (Confluence) becomes step 10, "only after step 9"; the resume case
  "done: <answers>" → Decisions rows → finish again. § Output gains `critique: {rounds, findings,
  fixed, agreed, withdrawn, refuted, disputed}` and notes the `REBUTTAL` phase block.

- [ ] **Step 1: Write the failing checks** in §5i: the lead file contains, in order
  (`grep -n` and compare line numbers), `Draft and return`, `Rebuttal`, `Finish`, `Confluence
  draft`; tokens `REBUTTAL`, `critique:`, `## Critique`, `no findings`, `disputed`, `answer the
  disputed questions`, `never \`settled\``, `critique settled`, `FIX`, `MAINTAIN`,
  `OUTSIDE_RUN`; `cap` inside the rebuttal step (`sed -n '/\*\*Rebuttal/,/\*\*Finish/p'`);
  `Lessons` inside the finish step; `only after` inside the Confluence step.
- [ ] **Step 2: Run the check.** Expected: the new lines FAIL.
- [ ] **Step 3: Edit the lead** per Interfaces; keep its `tools:` line and frontmatter hook
  unchanged (§5b).
- [ ] **Step 4: Run the check.** Expected: ALL GREEN except Task 5's lines.
- [ ] **Step 5: Commit (owner's go):** `feat(research): the lead answers the critique and finishes after it`.

### Task 5: the command, the reserve, the index

**Files:**
- Modify: `core/commands/research.md` (frontmatter `argument-hint`; § Input; New run step 3
  "(the whole ceiling)" → "minus the critique's reserve"; a new step between Wait and Report:
  "**Critique.** Run `guides/research-workflow.md § Critique` with this session as
  orchestrator: critics by `Agent` with `subagent_type: "research-critic"` in one message, the
  judge by `"research-judge"`, the lead by `SendMessage` to its id; write `critique.md`";
  Report gains the critique table and the `disputed` lines; Resume gains "a critique in
  progress restarts its current round with fresh critics from `critique.md`'s state block")
- Modify: `core/guides/thoroughness.md` (§ Agent ceiling: delete the "Until the research
  critique lands …" clause ~154–155)
- Modify: `core/CLAUDE.md` (research-team row lists both agents; guides table: the
  `adversarial-review.md` and `research-workflow.md` rows' consumers gain both; the
  `review-bash-gate.sh` hooks row names four types)
- Modify: `core/scripts/harness-check.sh` (§5i command/index checks; §5h's negative on
  `passes the whole ceiling` flips)

**Interfaces:**
- **Consumes** everything above.
- **Produces** the flags: `argument-hint` gains `[--no-critique]` and `| --critique
  <investigation-folder>`; § Input bullets: `--no-critique` (also implied by `--effort=quick`);
  `--critique <folder>` → the standalone paragraph by reference, takes the thoroughness flags,
  stops with `no findings.md` when the file is missing and `stopped` when the frontmatter says
  so; the resolution sentence
  "reserve `critic width × (K + 1) + critic width` of `max_agents` for the critique; the lead's
  capsule carries the remainder".

- [ ] **Step 1: Write the failing checks** in §5i: `argument-hint` mentions `--no-critique` and
  `--critique`; § Input mentions `no findings.md`, `stopped`, `--effort=quick`; the command
  mentions `subagent_type: "research-critic"`, `subagent_type: "research-judge"`,
  `critique.md`, `rebuttal: unavailable`, `disputed`, `restarts its current round`; step 3 no
  longer says `the whole ceiling` and does say `reserve`; `$TH` no longer contains `passes the
  whole ceiling` (flip the §5h assertion to a negative); `CLAUDE.md` names `research-critic`
  and `research-judge` on the research-team row and the gate row names four types; the
  command's usage line equals the argument-hint (reuse §5h's comparison).
- [ ] **Step 2: Run the check.** Expected: the new lines FAIL; the flipped §5h line FAILs.
- [ ] **Step 3: Edit the four files** per Interfaces.
- [ ] **Step 4: Run the check.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner's go):** `feat(research): /research runs the critique; --no-critique, --critique <folder>; the ceiling reserve`.

### Task 6: verification

**Files:**
- Modify: `docs/2026-10-27-research-critique-design.md` (new `## Verified (<date>)`)
- Run in: an installed project after `install.sh --update`, in a fresh `claude -p`.

- [ ] **Step 1: Fixture, standalone.** `/research --critique <folder>` on a settled investigation
  the owner picks. Expected: `critique.md` created with the state block, `rebuttal:
  unavailable`, one `### Hunt` per critic, a `### Cross-examination`, a `### Synthesis` table;
  every finding cites a line of `findings.md` and a re-opened piece of evidence; `findings.md`
  byte-identical before and after. Record the table and the cost.
- [ ] **Step 2: Gate in a live agent.** From the same run's transcript, one `verify-quote.sh`
  call by a critic allowed and one denied command (e.g. `git add`) refused with the gate's
  message; record both lines.
- [ ] **Step 3: Live, standard.** The owner's next `/research` at `standard`. Expected: the
  lead's first return without a Confluence draft, two critics, a `REBUTTAL` block, `## Critique`
  in `findings.md`, the final block's `critique:` field, and the draft (if any) written last.
  Record whether Answer or Next changed, and every `disputed` question.
- [ ] **Step 4: Write § Verified** with the measured results; fixes go back through §5i red-first.
- [ ] **Step 5: Commit (owner's go):** `docs(research): critique verified`.
