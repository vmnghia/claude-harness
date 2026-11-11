# `/fix-bug`: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** one command, `/fix-bug <FRONT-XXXX>`, that carries a bug from its ticket through
diagnosis (`/research`, picked up or run), the owner's decisions, a bug spec, a spec review, a
red run on the unfixed tree, the fix, and a green run on the same steps, ending
`READY_FOR_HUMAN_APPLY`.

**Architecture:**
- The **procedure** lives in `core/guides/ai-workflow.md` as a new `## Bug mode` section: six
  steps that run before § Procedure's step 3, plus the branch gate moved to after Red. From
  coding on, the run is § Procedure steps 3 to 7 unchanged. A feature run reads no bug step.
- `core/commands/fix-bug.md` is thin, modelled on `feature-flow.md`: input parsing, where each
  phase runs, resume, the final block, what the lead does not do. It holds no procedure.
- The run document's state block carries `mode: bug`, so `--resume` follows the mode whichever
  command was typed.
- Four agents learn one brief each: Planner the `diagnosis:` capsule, Reviewer "SPEC REVIEW",
  Tester "RED CHECK", Coder standby until Red is done.
- `harness-check.sh` gains § 5k, red first per task.

**Tech Stack:** Claude Code agent files, slash commands and guides (Markdown + YAML
frontmatter); bash for `harness-check.sh`.

**Spec:** [2026-11-11-fix-bug-design.md](./2026-11-11-fix-bug-design.md) (approved
2026-11-11). Executors read it first; this plan does not repeat its reasoning.

## Global Constraints

- **Branch:** work on `feat/fix-bug`, created by the owner or on the owner's go. Never commit
  on `main`. Never push. Use `git switch` / `git restore`, never `git checkout`.
- **Commits:** conventional subjects as in `git log` (`feat(harness): …`, `docs(harness): …`).
  The message ends with the `Co-Authored-By:` line only, no session link.
- **Test command:** `bash core/scripts/harness-check.sh` from the repo root. It takes about a
  minute; give it a 300 s timeout. Baseline on 2026-11-11: `harness-check: ALL GREEN`. To see
  one section's result: `bash core/scripts/harness-check.sh 2>/dev/null | sed -n '/== 5k/,/== 6/p'`.
- **No procedure in a command file.** `commands/fix-bug.md` must not contain a heading that
  starts `### Step`, nor the words `RED CHECK` or `SPEC REVIEW` as anything but a pointer.
- **Exact tokens** (they are grepped; spell them exactly):
  - command: `/fix-bug`; flags `--run-research`, `--fix-ticket=`, `--spec=`, plus every flag
    `feature-flow.md`'s `argument-hint` has.
  - state block: `mode: feature | bug`, `bug_ticket`, `fix_ticket`, `investigations:`,
    `repro: pending | REPRODUCED | waived (D<n>)`.
  - step enum, in order: `diagnosis | decisions | planning | spec-review | red | coding |
    testing | reviewing | gate | done`.
  - capsule key: `diagnosis:` with `investigations`, `next`, `decisions`, `bug_ticket`,
    `fix_ticket`.
  - briefs (the first words of the resume message): `SPEC REVIEW`, `RED CHECK`,
    `FIX FROM SPEC REVIEW`.
  - Reviewer statuses: `SPEC_APPROVED`, `SPEC_CHANGES_REQUESTED`.
  - Tester statuses for RED CHECK: `REPRODUCED`, `NOT_REPRODUCED`; per-scenario results
    `reproduced | not_reproduced | not_executable`.
  - spec scenario lines: `repro: yes`, `expected (unfixed)`, `expected (fixed)`.
  - final statuses added to the lead block: `NO_BUILD_NEEDED`, `NOT_REPRODUCED`.
  - evidence directory: `.claude/runs/<run-slug>-evidence/`.
- **Pick-up rule:** `ticket:` equals the bug ticket, `kind: incident`, `status: settled`,
  `superseded_by` followed, newest folder first.
- **`--no-test` is the owner's waiver:** a `DECISION` `by: owner` at the start of the run and
  `repro: waived (D<n>)`; never `not_run`.
- **`--max-agents` is one ceiling per phase;** a research run started by `/fix-bug` gets
  research's own `max_iter` (3), never the team flow's.
- **Existing cases must stay green.** In particular `feature-flow.md` must keep the strings
  `--resume`, `every id is dead` and `Read … ai-workflow.md`; `ai-workflow.md` must keep the
  heading list at `harness-check.sh:1273` and the sentences § 5g and § 5h grep.
- **`/feature-flow` behaviour does not change.** Only its § Resume text changes.
- **Style:** match the neighbouring text: 100-column wrap, no em dashes in new prose, dated
  notes as `(2026-11-11)` where a rule records a decision.

## Review Focus

Conditions the design implies that a token grep cannot prove. Each is pinned by a case in the
task named.

1. **An old run document with no `mode:` line is resumed.** Expected: it is a feature run and
   resumes as today. (Task 1: the guide says "absent means `feature`" inside § Resume.)
2. **`--no-test` in bug mode.** Expected: a recorded owner decision and `repro: waived`, never
   a silent skip. (Task 1: `## Bug mode` contains the waiver sentence; Task 4: the command's
   `--no-test` bullet names it.)
3. **`REPRODUCED` satisfied by `NOT_REPRODUCED` in a grep.** Expected: the linter uses word
   matching, as `rtok` does. (Task 3: `btok` uses `grep -qw`.)
4. **The investigation is `open`, or its lead is dead in a new session.** Expected: the owner
   is asked; no fresh lead is started for an existing run. (Task 1: `## Bug mode` names
   research.md § Resume step 4 and the four choices.)
5. **A second failed red check after a widening.** Expected: the owner's choices are proceed
   or stop; no second widening. (Task 1: "One widening per run".)

---

### Task 1: The guide: `## Bug mode`, the state block, resume

**Files:**
- Modify: `core/guides/ai-workflow.md` (§ Roles and entry points `:28-30`, § Per-agent enum
  table `:77-82`, § Roster and run document state block `:159-170`, § Resume `:331-339`, new
  `## Bug mode` between § Procedure and § Mechanical enforcement, § Bug-fix rule `:425-429`,
  § What ends the flow `:446`)
- Test: `core/scripts/harness-check.sh` (new § 5k, inserted immediately before the line
  `echo "== 6. Spec/plan pair naming =="`)

**Interfaces:**
- Produces: every token under Global Constraints › Exact tokens, defined in the guide. Later
  tasks make agents and the command match them.
- Produces in `harness-check.sh`: `BM` (the text of `## Bug mode`, newlines folded to spaces)
  and `btok <token> <agent-basename>` (token must appear, as a word, in both `ai-workflow.md`
  and the agent file).

- [ ] **Step 1: Write the failing cases.** Insert § 5k:

```bash
echo "== 5k. Bug mode: /fix-bug (2026-11-11) =="
WF="$H/guides/ai-workflow.md"
BM=$(sed -n '/^## Bug mode/,/^## Mechanical enforcement/p' "$WF" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')
[ -n "$BM" ] && ok "ai-workflow.md has ## Bug mode" || fail "ai-workflow.md lacks ## Bug mode"
btok() { # btok <token> <agent-basename>: word match in the guide and the agent file
  if grep -qw -- "$1" "$WF" && grep -qw -- "$1" "$H/agents/$2"; then ok "'$1' in ai-workflow.md + $2"
  else fail "'$1' missing from ai-workflow.md or $2"; fi
}
grep -qF 'step: diagnosis | decisions | planning | spec-review | red | coding | testing | reviewing | gate | done' "$WF" \
  && ok "state block: step enum carries the bug steps in order" || fail "state block: step enum lacks the bug steps"
for tok in 'mode: feature | bug' 'bug_ticket' 'fix_ticket' 'investigations:' 'repro: pending | REPRODUCED | waived (D<n>)'; do
  grep -qF -- "$tok" "$WF" && ok "state block carries $tok" || fail "state block lacks $tok"
done
for tok in 'kind: incident' 'status: settled' 'superseded_by' 'research.md § New run' 'research.md § Resume' \
           'NO_BUILD_NEEDED' 'AskUserQuestion' 'findings.md` is not touched' 'diagnosis:' \
           'SPEC REVIEW' 'FIX FROM SPEC REVIEW' 'One pass' 'RED CHECK' 'not_executable' \
           '.claude/runs/<run-slug>-evidence/' 'One widening per run' 'Never proceed silently' \
           'is the owner'"'"'s waiver' 'one ceiling per phase' 'expected (fixed)' 'no fresh lead'; do
  printf '%s' "$BM" | grep -qF -- "$tok" && ok "## Bug mode: $tok" || fail "## Bug mode lacks: $tok"
done
printf '%s' "$BM" | grep -qE 'branch gate.*after Red|after Red.*branch gate' && ok "## Bug mode: the branch gate runs after Red" || fail "## Bug mode: branch gate position unspecified"
sed -n '/^### Resume/,/^## Procedure/p' "$WF" | tr '\n' ' ' | grep -qF 'absent means `feature`' \
  && ok "§ Resume: a run document without mode is a feature run" || fail "§ Resume: no rule for a run document without mode"
sed -n '/^## Procedure/,/^## Bug mode/p' "$WF" | grep -qE 'RED CHECK|SPEC REVIEW' \
  && fail "§ Procedure carries a bug step (a feature run must read none)" || ok "§ Procedure carries no bug step"
grep -qE 'status: READY_FOR_HUMAN_APPLY.*NO_BUILD_NEEDED.*NOT_REPRODUCED' "$WF" \
  && ok "lead block lists NO_BUILD_NEEDED and NOT_REPRODUCED" || fail "lead block lacks the bug-mode final statuses"
grep -qF '/fix-bug' "$WF" && ok "ai-workflow.md names /fix-bug as an entry point" || fail "ai-workflow.md never names /fix-bug"
```

- [ ] **Step 2: Run it and see the section fail.**
  Run: `bash core/scripts/harness-check.sh 2>/dev/null | sed -n '/== 5k/,/== 6/p'`
  Expected: every § 5k line is `FAIL` except "§ Procedure carries no bug step".

- [ ] **Step 3: Write `## Bug mode`** in `core/guides/ai-workflow.md`, between § Procedure and
  § Mechanical enforcement. Its content is the design's § Builder's calls, subsections
  "1. Diagnosis" to "7. Fix" plus "Command line"'s two knob exceptions, rewritten as numbered
  procedure steps in the voice of § Procedure (imperative, one bold step name each, statuses in
  backticks). Required structure:
  - an opening paragraph: bug mode is entered by `/fix-bug`; it replaces § Procedure steps 0 to
    2 and then hands to step 3; `--spec` enters at Team up;
  - steps `B1. Diagnosis`, `B2. Decisions`, `B3. Planning`, `B4. Team up`,
    `B5. Spec review`, `B6. Red`, then `Branch gate` (one sentence saying it runs after Red
    and why), then `B7. Fix` naming the two message additions and the recap additions;
  - B5 and B6 are sent in one message;
  - the `diagnosis:` capsule as a fenced YAML block, copied from the design;
  - every outcome in the design's bullets, each with its status or its owner question.
  Use the exact strings the Step 1 cases grep.

- [ ] **Step 4: Update the rest of the guide.**
  - § Roles and entry points: add a `/fix-bug <FRONT-XXXX> […]` bullet after `/feature-flow`,
    one sentence, pointing at `## Bug mode`.
  - § Per-agent enum table: Reviewer row gains `SPEC_APPROVED` / `SPEC_CHANGES_REQUESTED`
    (bug mode's spec review); Tester row gains `REPRODUCED` / `NOT_REPRODUCED` (bug mode's red
    check) and `repro_results[]` (each: scenario, `reproduced | not_reproduced |
    not_executable`, evidence path).
  - State block: replace the `step:` line with the enum from Global Constraints and add the
    five new keys after `gate_iter`, each with a short `#` comment; `mode` says
    "absent means `feature`".
  - § Resume: first sentence becomes "`/feature-flow --resume` and `/fix-bug --resume` are the
    same: the state block's `mode` decides the path (absent means `feature`)". Add: at
    `step: diagnosis` follow `## Bug mode` B1's resume rules; `spec-review` and `red` restart
    from their beginning; in bug mode the branch gate is re-run only from `coding` on.
  - § Bug-fix rule: replace the body with two sentences: `/fix-bug` runs `bug-fixes.md` as
    `## Bug mode`; in a `/feature-flow` run on a bug spec, Coder still follows `bug-fixes.md`.
  - § What ends the flow: add the two statuses to the `status:` line and one sentence each
    below it; add `investigations:` and `repro:` to the block as bug-mode-only lines.

- [ ] **Step 5: Run the whole script.**
  Run: `bash core/scripts/harness-check.sh 2>/dev/null | grep -c '  FAIL  '`
  Expected: `0`. (Section 5k's `btok` is defined but not yet called; that is Task 2 and 3.)

- [ ] **Step 6: Commit.**
  `git add core/guides/ai-workflow.md core/scripts/harness-check.sh`
  `git commit -m "feat(harness): bug mode in the team-flow guide (diagnosis, decisions, spec review, red)"`

---

### Task 2: Planner and the spec template

**Files:**
- Modify: `core/agents/planner.md` (frontmatter `tools:` `:4`; § Procedure step 1 `:38-45`;
  § Team first paragraph `:79-85`; § What you do NOT do `:122-127`)
- Modify: `core/templates/spec-template.md` (§ Repro Steps `:25-29`, § Test Scenarios `:43-52`)
- Test: `core/scripts/harness-check.sh` § 5k

**Interfaces:**
- Consumes: `btok`, the capsule shape and the tokens from Task 1.
- Produces: a spec whose bug scenarios carry `repro: yes`, `expected (unfixed)`,
  `expected (fixed)`; Tester (Task 3) reads exactly those three lines.

- [ ] **Step 1: Write the failing cases.** Append to § 5k:

```bash
PL="$H/agents/planner.md"; ST="$H/templates/spec-template.md"
btok 'diagnosis' planner.md
for tok in 'FIX FROM SPEC REVIEW' 'repro: yes' 'expected (unfixed)' 'expected (fixed)' 'waived (D<n>)' 'revis'; do
  grep -qF -- "$tok" "$PL" && ok "planner.md: $tok" || fail "planner.md lacks: $tok"
done
has_tool "$PL" Edit && ok "planner has Edit (spec fixes after the spec review)" || fail "planner lacks Edit"
for t in Bash Agent; do has_tool "$PL" "$t" && fail "planner must not have $t" || ok "planner has no $t"; done
grep -qF 'Do not run Bash' "$PL" && ok "planner.md still forbids Bash" || fail "planner.md lost the Bash boundary"
for tok in 'repro: yes' 'expected (unfixed)' 'expected (fixed)'; do
  grep -qF -- "$tok" "$ST" && ok "spec-template.md: $tok" || fail "spec-template.md lacks: $tok"
done
```

- [ ] **Step 2: Run § 5k; the new lines fail** (same command as Task 1 Step 2).

- [ ] **Step 3: Edit `planner.md`.**
  - `tools:` add `Edit` after `Write`.
  - Step 1 gains a third input type, placed first: "**A `diagnosis:` capsule item**
    (`guides/ai-workflow.md` § Bug mode B3)": this is a bug spec whatever the issue type; the
    four rules from the design's § 3 Planning (Context, Repro Steps incl. the `assumed` and
    `waived (D<n>)` cases, Test Scenarios with the three lines, decisions as dated rows) and
    "do not re-ask what the diagnosis or a decision settles".
  - A short paragraph after step 7: **revising an existing pair**. When the brief names an
    existing spec path and says to revise (after a widening, or `FIX FROM SPEC REVIEW`), edit
    the pair in place with `Edit`; never write a second pair.
  - § Team: standby "writes nothing" gains its one exception: resumed with
    `FIX FROM SPEC REVIEW` and Reviewer's `findings[]`, it edits the spec and plan and replies
    with `SPEC_READY`.
  - § What you do NOT do: "Do not run Bash, Edit, or any code-changing tool" becomes "Do not
    run Bash or any code-changing tool; `Edit` is for the spec+plan pair only".

- [ ] **Step 4: Edit `spec-template.md`.** In § Repro Steps' comment add: when the owner waived
  the repro write `waived (D<n>)`; steps the investigation attempted but did not reproduce are
  labelled `assumed`. In § Test Scenarios add three bullets marked "bug specs only":
  `repro: yes` on each scenario that reproduces the bug, `expected (unfixed)` (the symptom) and
  `expected (fixed)`.

- [ ] **Step 5: Run the whole script; expect 0 FAIL.**

- [ ] **Step 6: Commit.**
  `git commit -m "feat(harness): planner writes a bug spec from a diagnosis; red/green scenario lines"`

---

### Task 3: Reviewer, Tester and Coder

**Files:**
- Modify: `core/agents/reviewer.md` (§ Input `:22-26`, § Team `:112-…`, § Output `:169-…`)
- Modify: `core/agents/tester.md` (§ Procedure step 3.8 `:77-78` and step 4 `:79-81`, § Team
  `:84-…`, § Output block `:157-174`)
- Modify: `core/agents/coder.md` (§ Procedure step 2 `:48-49`, § Team)
- Test: `core/scripts/harness-check.sh` § 5k

**Interfaces:**
- Consumes: the brief names, statuses and scenario lines from Tasks 1 and 2.
- Produces: Reviewer's and Tester's status blocks as `## Bug mode` B5 and B6 route them.

- [ ] **Step 1: Write the failing cases.** Append to § 5k:

```bash
btok 'SPEC_APPROVED' reviewer.md
btok 'SPEC_CHANGES_REQUESTED' reviewer.md
btok 'REPRODUCED' tester.md
btok 'NOT_REPRODUCED' tester.md
btok 'not_executable' tester.md
grep -qF 'SPEC REVIEW' "$H/agents/reviewer.md" && ok "reviewer.md knows the SPEC REVIEW brief" || fail "reviewer.md lacks the SPEC REVIEW brief"
TS="$H/agents/tester.md"
for tok in 'RED CHECK' 'repro: yes' 'expected (unfixed)' 'expected (fixed)' 'positive_control' '.claude/runs/<run-slug>-evidence/'; do
  grep -qF -- "$tok" "$TS" && ok "tester.md: $tok" || fail "tester.md lacks: $tok"
done
grep -qF '/tmp/tester-' "$TS" && fail "tester.md still writes evidence to /tmp" || ok "tester.md writes no evidence to /tmp"
grep -qE 'On failure, capture evidence' "$TS" && fail "tester.md captures evidence on failure only" || ok "tester.md captures evidence on success too"
CODER="$H/agents/coder.md"
grep -qF 'repro:' "$CODER" && grep -qiF 'does not reproduce again' "$CODER" && ok "coder.md: the lead's repro state is the confirmation in bug mode" || fail "coder.md: bug-mode repro confirmation unspecified"
grep -qiF 'standby' "$CODER" && grep -qF 'the spec is final' "$CODER" && ok "coder.md: standby until the spec is final (bug mode)" || fail "coder.md: no bug-mode standby"
```

- [ ] **Step 2: Run § 5k; the new lines fail.**

- [ ] **Step 3: Edit `reviewer.md`.** § Team gains a subsection `### Spec review (bug mode)`:
  resumed with `SPEC REVIEW` before any diff exists, it reads the spec and plan against the
  code as it stands and reports where they cannot work, contradict the code, or contradict the
  diagnosis (the investigation folders are in the spec's References); findings use the usual
  shape with `file`/`line` pointing into the spec or plan; status `SPEC_APPROVED`, or
  `SPEC_CHANGES_REQUESTED` iff at least one `blocker` or `major`; one pass, it is not asked to
  re-review; it keeps what it read for the code review. § Output's `status:` line lists the
  two new values with "(spec review only)".

- [ ] **Step 4: Edit `tester.md`.**
  - Step 3.8: capture evidence for every scenario, pass or fail. In a team run write it under
    `.claude/runs/<run-slug>-evidence/` (the brief gives the run slug); outside a team run the slug
    is the spec's filename stem. Remove the `/tmp/tester-…` paths, in the Output
    block too.
  - § Team gains `### Red check (bug mode)`: resumed with `RED CHECK`, drive only the
    `repro: yes` scenarios on the tree as it is, compare against `expected (unfixed)`, follow
    `bug-fixes.md` § Mimic the real user flow; report `repro_results[]` (scenario, result,
    evidence); `REPRODUCED` iff every one is `reproduced`; `NOT_REPRODUCED` otherwise, with a
    `positive_control` (`research-discipline.md` § 3); `not_executable` names the step that
    could not be done. No `test_iter` moves.
  - Step 4 Decide: in bug mode a `PASS` needs each `repro: yes` scenario to meet
    `expected (fixed)` on the same steps, and the block lists red and green evidence paths side
    by side; with `repro: waived` it says the red half is missing.
  - § Output: `status:` adds the two values with "(red check only)"; add `repro_results:`.

- [ ] **Step 5: Edit `coder.md`.** Step 2's last sentence: for bug specs read `bug-fixes.md`;
  in a `/fix-bug` run the lead's first resume carries `repro: <state>`, which is the
  confirmation, and Coder does not reproduce again; outside one, confirm the spec's Repro Steps
  before editing as today. § Team: in bug mode Coder is dispatched on standby and starts
  nothing until resumed with "the spec is final; repro: …; decisions so far: D…".

- [ ] **Step 6: Run the whole script; expect 0 FAIL.**

- [ ] **Step 7: Commit.**
  `git commit -m "feat(harness): reviewer spec review, tester red check, coder standby for bug mode"`

---

### Task 4: The command, and `/feature-flow --resume`

**Files:**
- Create: `core/commands/fix-bug.md`
- Modify: `core/commands/feature-flow.md` (§ Resume `:77-84` only)
- Test: `core/scripts/harness-check.sh` § 5k, and the § 5h loops at `:1471` and `:1477`

**Interfaces:**
- Consumes: `## Bug mode` (Task 1) by section name; `commands/research.md` § New run and
  § Resume by section name.
- Produces: the `/fix-bug` entry point.

- [ ] **Step 1: Write the failing cases.** In § 5h change `for c in adversarial-review
  feature-flow research; do` to include `fix-bug`, and `for c in adversarial-review
  feature-flow; do` to include `fix-bug`. Append to § 5k:

```bash
FB="$H/commands/fix-bug.md"; FF="$H/commands/feature-flow.md"
check "commands/fix-bug.md exists" test -f "$FB"
grep -qE 'Read.*ai-workflow\.md' "$FB" 2>/dev/null && ok "fix-bug Reads ai-workflow.md" || fail "fix-bug never Reads ai-workflow.md"
for tok in 'Bug mode' '--run-research' '--fix-ticket=' '--spec=' '--resume' '--no-test' '--max-gate-iter' \
           'commands/research.md' 'kind: incident' 'mode: bug' 'switchboard' 'by agent id' 'every id is dead' \
           'AskUserQuestion' 'agent: lead' 'NO_BUILD_NEEDED' 'NOT_REPRODUCED' 'NEEDS_OWNER' 'cost line' \
           'one ceiling per phase' 'waiver'; do
  grep -qF -- "$tok" "$FB" 2>/dev/null && ok "fix-bug mentions $tok" || fail "fix-bug never mentions $tok"
done
grep -qE '^### Step' "$FB" 2>/dev/null && fail "fix-bug holds procedure steps; they belong in ai-workflow.md § Bug mode" || ok "fix-bug holds no procedure step"
hint=$(grep -m1 '^argument-hint:' "$FB" 2>/dev/null)
for f in $(grep -m1 '^argument-hint:' "$FF" | grep -oE -- '--[a-z-]+'); do
  printf '%s' "$hint" | grep -qF -- "$f" && ok "fix-bug argument-hint carries $f" || fail "fix-bug argument-hint lacks $f"
done
sed -n '/^## Resume/,/^## /p' "$FF" | tr '\n' ' ' | grep -qF 'mode' && ok "feature-flow § Resume follows the run document's mode" || fail "feature-flow § Resume ignores mode"
grep -qF 'Never skip the branch gate' "$FB" 2>/dev/null && ok "fix-bug keeps the branch gate (after Red)" || fail "fix-bug drops the branch gate"
```

- [ ] **Step 2: Run § 5k and § 5h; the new lines fail.**

- [ ] **Step 3: Write `core/commands/fix-bug.md`.** Same skeleton and headings as
  `feature-flow.md`: frontmatter (`description`, `argument-hint` with the design's command
  line), the Contract paragraph ("Read `guides/ai-workflow.md` first and execute its
  **§ Bug mode**, then **§ Procedure** from step 3, under its § Team protocol"), the lead and
  switchboard paragraph (by reference to the same rule, not a second wording of it),
  `## Input`, `## Where each phase runs`, `## Resume`, `## Final status block`,
  `## What you do NOT do`.
  - `## Input`: the positional must match `^FRONT-\d+$` unless `--spec` or `--resume`;
    otherwise `NEEDS_CLARIFICATION` with the usage line. `--run-research`, `--fix-ticket=`
    (default: the bug ticket), `--spec=` (sibling `-plan.md` must exist; at least one
    `repro: yes` scenario unless `--no-test`). `--no-test`: the owner's waiver, recorded as a
    decision. Thoroughness flags per `guides/thoroughness.md` § Input, with the two exceptions
    (`--max-agents` is one ceiling per phase, so up to twice the number typed; research gets
    its own `max_iter`). The caps as in `feature-flow.md`.
  - `## Where each phase runs`, one bullet per phase: run document (created first, with
    `mode: bug` and `step: diagnosis`, after the `git check-ignore -q .claude/runs/` check);
    diagnosis (the scan in this session; a research run by executing `commands/research.md`
    § New run inline here); decisions (`AskUserQuestion`); planning (as `feature-flow.md`,
    plus the `diagnosis:` capsule item); team up (one message, all on standby, Coder
    included); spec review and red (two `SendMessage` resumes in one message); branch gate
    (after Red, always); then "every later step" by pointing at `feature-flow.md`
    § Where each phase runs for coding, switchboard, decisions, owner pause, gate and report.
  - `## Resume`: points at the guide's § Resume; `mode` decides.
  - `## Final status block`: the lead block with the two extra statuses and the
    `investigations:` and `repro:` lines.
  - `## What you do NOT do`: `feature-flow.md`'s list, plus: never write `findings.md` after
    Framing; never start a fresh research lead for an existing run; never resume Coder before
    the spec review and Red are both back; never skip the branch gate.

- [ ] **Step 4: Edit `feature-flow.md` § Resume.** Keep its first sentence's file discovery
  and the strings `--resume` and `every id is dead`. Add: "the state block's `mode` decides the
  path: `bug` follows `guides/ai-workflow.md` § Bug mode's resume rules and § Resume, absent or
  `feature` is the path below". Nothing else in the file changes.

- [ ] **Step 5: Run the whole script; expect 0 FAIL.**

- [ ] **Step 6: Commit.**
  `git commit -m "feat(harness): /fix-bug command; /feature-flow --resume follows the run document's mode"`

---

### Task 5: Listings and the rule

**Files:**
- Modify: `core/guides/thoroughness.md` (`:14` Consumers, `:162` Flags sentence, and one new
  paragraph in § Agent ceiling)
- Modify: `core/CLAUDE.md` (`:59` guides table row, `:62` thoroughness row, `:69` Team flow row)
- Modify: `README.md` (`:7-9` Feature workflow bullet)
- Modify: `core/rules/bug-fixes.md` (after the § Workflow list)
- Modify: `docs/2026-11-11-fix-bug-design.md` (Status line)
- Test: `core/scripts/harness-check.sh` § 5k

- [ ] **Step 1: Write the failing cases.** Append to § 5k:

```bash
TH="$H/guides/thoroughness.md"
grep -qF '/fix-bug' "$TH" && ok "thoroughness.md lists /fix-bug as a consumer" || fail "thoroughness.md never names /fix-bug"
sed -n '/Agent ceiling/,/^## /p' "$TH" | tr '\n' ' ' | grep -qF 'one ceiling per phase' && ok "thoroughness.md § Agent ceiling: /fix-bug counts per phase" || fail "thoroughness.md § Agent ceiling: /fix-bug ceiling unspecified"
[ "$(grep -c '/fix-bug' "$H/CLAUDE.md")" -ge 2 ] && ok "CLAUDE.md lists /fix-bug (guides table and teams table)" || fail "CLAUDE.md does not list /fix-bug twice"
grep -qF '/fix-bug' "$H/rules/bug-fixes.md" && ok "bug-fixes.md names /fix-bug" || fail "bug-fixes.md never names /fix-bug"
if [ "$H" = "$ROOT/core" ]; then
  grep -qF '/fix-bug' "$ROOT/README.md" && ok "README names /fix-bug" || fail "README never names /fix-bug"
  grep -qE '^Status: .*implemented on ' "$ROOT/docs/2026-11-11-fix-bug-design.md" && ok "fix-bug design Status says implemented" || fail "fix-bug design Status not updated"
fi
```

- [ ] **Step 2: Run § 5k; the new lines fail.**

- [ ] **Step 3: Make the edits.**
  - `thoroughness.md`: add `/fix-bug` to the Consumers line and the Flags sentence; in
    § Agent ceiling one paragraph: in `/fix-bug` the ceiling is one ceiling per phase (the
    research run and the gate each count from zero), and the research run's `max_iter` is
    research's own.
  - `core/CLAUDE.md`: `/fix-bug` in the `ai-workflow.md` row, the `thoroughness.md` row and the
    Team flow row's entry points. `bug-fixes.md` is `load: always`: check § 5e stays green
    after its edit and keep the addition to one line.
  - `README.md`: one clause in the Feature workflow bullet: `/fix-bug` for a bug, from
    diagnosis to a fix proven against its repro.
  - `bug-fixes.md`: one line after the Workflow list: "`/fix-bug <ticket>` runs this workflow
    as a team (`guides/ai-workflow.md` § Bug mode)."
  - Design doc Status: "approved by the owner 2026-11-11; implemented on `feat/fix-bug`
    (acceptance rows 2 to 4 open)".

- [ ] **Step 4: Run the whole script.**
  Run: `bash core/scripts/harness-check.sh 2>/dev/null | tail -1`
  Expected: `harness-check: ALL GREEN`.
  Then `bash scripts/leak-check.sh` and expect its clean result.

- [ ] **Step 5: Commit.**
  `git commit -m "docs(harness): list /fix-bug in the indexes, the thoroughness guide and bug-fixes.md"`

---

### Task 6: Acceptance smokes (owner's go required for each step)

No source changes. Nothing here runs without the owner saying so: it installs into another
repo and drives a browser.

- [ ] **Step 1:** On the owner's go, `install.sh --update` into the reference project and run
  that repo's `.claude/scripts/harness-check.sh`; expect ALL GREEN.
- [ ] **Step 2 (design acceptance 3):** in the reference project, `/fix-bug FRONT-AAAA
  --fix-ticket=FRONT-BBBB`. Expected: both `2026-10-28-front-aaaa` and
  `2026-11-04-front-aaaa` are named as the diagnosis, no research starts, and the decision
  pause lists nothing the investigations' Decisions tables settle. Stop it at the pause.
- [ ] **Step 3 (design acceptance 2):** mark the repro scenario in
  the reference fix ticket's spec with the three lines, then
  `/fix-bug --spec=<that path>`. Expected: Team up on standby, spec review and red check in
  one message, a `REPRODUCED` or `NOT_REPRODUCED` block with evidence under
  `.claude/runs/…-evidence/`, and `git status` showing no source file changed before the
  branch gate.
- [ ] **Step 4 (design acceptance 5):** `/feature-flow --resume` on a run document written
  before this change. Expected: it resumes as a feature run.
- [ ] **Step 5:** Add a `## Verified` section to the design with what each smoke showed, dated,
  and leave acceptance row 4 (a full run from a ticket with no investigation) open in the
  Status line until a suitable bug comes. Commit:
  `git commit -m "docs(harness): /fix-bug smoke results"`
