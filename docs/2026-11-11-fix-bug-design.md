# `/fix-bug`: the team flow for a bug, from diagnosis to a fix proven against its repro

Status: approved by the owner 2026-11-11 (builder check done); implemented on `feat/fix-bug`
2026-11-11. Acceptance rows 2 to 5 are open: the smokes have not been run.

Read first: [2026-10-22-team-flow-design.md](./2026-10-22-team-flow-design.md) (the lead, the
persistent peers, the run document), [2026-10-14-research-workflow-design.md](./2026-10-14-research-workflow-design.md)
and [2026-10-27-research-critique-design.md](./2026-10-27-research-critique-design.md) (what a
settled investigation is). Paths below are relative to `core/` unless they start with `docs/`.

## Intent

A bug ticket today takes five hand-offs that the owner drives by hand. The reference run is
a bug-fix session in a consuming project (2026-11-04 to 2026-11-10; ticket keys below are placeholders):

1. `/research FRONT-AAAA --effort=thorough`: diagnosis, repro-driver, three critique rounds.
2. The owner asks "what needs me now?" and answers the decisions the research left open.
3. `/planner FRONT-BBBB`: spec and plan from the research's Next plus those decisions.
4. The owner asks for a review of the spec and plan against the code; two must-fix and four
   smaller findings; the owner says "apply".
5. `/feature-flow` for the fix.

Step 5 fits badly. `/feature-flow` starts by planning from a requirement, but the spec and plan
exist and are reviewed. Nothing in it starts from the diagnosis, and no step proves the bug red
on the unfixed tree and green on the same steps afterwards: `bug-fixes.md` reaches it only as
one inherited sentence addressed to Coder (`guides/ai-workflow.md` § Bug-fix rule).

The owner wants one command that carries a bug ticket through all five steps and pauses only
for the decisions that are the owner's.

## Evidence

- **`/research` already is the bug investigation.** `incident-investigator` diagnoses,
  `repro-driver` reproduces, the critique reviews, and `findings.md` ends with `## Next`, which
  "research-lead hands to Planner" (`templates/findings-template.md`), plus `## Repro`,
  `## Decisions`, `## Open` and `## Options`.
- **A settled investigation is identifiable from disk.** `findings.md` frontmatter carries
  `ticket:` and `status: open | settled | stopped | on-hold | superseded` (+ `superseded_by`).
- **The fix can live on another ticket.** FRONT-AAAA was diagnosed; the fix was planned and
  specced as FRONT-BBBB.
- **A ticket can have more than one investigation.** FRONT-AAAA has `2026-10-28-front-aaaa`
  (settled) and the delta run `2026-11-04-front-aaaa`; the planner took Next from both.
- **A closed investigation is not edited for the owner's decisions.** In the reference run the
  decisions were carried into the spec as dated Decisions rows, and `findings.md` was left as it
  was. Only research-lead writes `findings.md` (`guides/research-workflow.md` § Flow and roles).
- **The spec review earned its place.** On 2026-11-10 it found a gate that could never match and
  three Test Scenarios that could not run as written (they click a button that is not clickable
  while loading). The second is a defect only a browser run or a careful read against the code
  finds, and it is found before any coding.
- **Planner already knows bug specs.** `agents/planner.md` step 1 makes a `Bug` issue a bug spec
  with the template's `Repro Steps` section; its status block carries `is_bug_spec`.
- **The run document and `--resume` exist** (`guides/ai-workflow.md` § Roster and run document,
  § Resume) and the lead already stops at a step boundary when its context is at risk
  (§ Procedure, first paragraph). The reference session was compacted once.
- **`bug-fixes.md`** forbids a fix before a local repro, forbids pre-creating a branch before
  the repro is confirmed, and says what to do when a repro cannot be had: widen the net, then
  escalate.

## Decisions (owner, 2026-11-10 and 2026-11-11)

- **A new command, `/fix-bug`,** rather than making the owner chain `/research`, `/planner` and
  `/feature-flow`.
- **No separate `/investigate-bug`.** `/research` is the investigation.
- **Research is part of the command:** `/fix-bug` picks up a settled investigation for the
  ticket when one exists and runs `/research` when none does; `--run-research` forces a run.
- **One planned owner pause,** for the decisions the research left open.
- **The spec carries the root cause and the exact repro steps.**
- **A spec review before any coding.**
- **Red before the fix, green after, on the same steps.** No repro means stop and bring it to
  the owner, never fix anyway.
- **`--no-test` counts as the owner's waiver of the repro** (2026-11-11), recorded as a
  decision, rather than being refused in bug mode.
- **The fix phase is `/feature-flow`'s steps 2 to 7, unchanged.**
- **Built as a thin command plus a bug-mode section in `guides/ai-workflow.md`,** reusing the
  team, the run document and `--resume`. The accepted cost: the guide gets a second entry path
  to keep coherent. A separate guide would have duplicated most of it.

## Goals

- `/fix-bug FRONT-XXXX` takes a bug from ticket to `READY_FOR_HUMAN_APPLY` with the owner
  answering decisions and nothing else.
- The fix is never started on an unreviewed spec or an unproven repro, unless the owner waived
  the repro in a recorded decision.
- A run survives a session ending **from the decisions step onward**. During diagnosis it
  survives only as far as `/research` does today (see § 1): the settled investigation on disk
  is the durable hand-off, not the research lead.

## Non-goals

- `/feature-flow` does not change behaviour. The spec review and the red check are written so
  it could adopt them later; this design does not do that.
- No `--no-research` entry in v1. A bug that needs no investigation is `/planner FRONT-XXXX`
  followed by `/fix-bug --spec=<path>`. (YAGNI call: a third entry path can be added when that
  two-step is felt as friction.)
- No cross-repo work. A backend ask found by the research stays in the investigation's Open and
  with the owner, as it did for another team's backend in the reference run.
- No new research procedure, no change to the critique.
- No commits, pushes or branch creation by any agent, as today.

## Anti-goals

- A fix that goes ahead without a red run and without an owner decision waiving it.
- Re-investigating a settled diagnosis because the command was started again.
- The lead writing `findings.md` after research's inline Framing has created it (Framing in
  the main session is how `/research` works today and stays).
- Procedure text in `commands/fix-bug.md`.
- A lead that judges what it forwards, in either mode.

## Builder's calls (veto-able)

Everything in this section is the designer's choice, not the owner's.

### Command line

```
/fix-bug <FRONT-XXXX> [--run-research] [--fix-ticket=FRONT-YYYY] [--spec=<spec path>]
         [--auto] [--no-test] [--max-iter=N] [--max-gate-iter=N]
         [--effort=…] [--width=…] [--dry=K] [--max-agents=N]
         [--resume [<run-document>]]
```

- The positional is the **bug ticket**: the one the investigation is filed under. A Jira key is
  required unless `--spec` or `--resume` is given; free text is refused with the usage line
  (`NEEDS_CLARIFICATION`), because picking up an investigation keys on the ticket.
- `--fix-ticket`: the ticket the spec is written for. Default: the bug ticket.
- `--spec=<path>`: a spec that already exists (its sibling `-plan.md` must exist too). The run
  starts at **Team up**; diagnosis, decisions and planning are skipped. The spec must be a bug
  spec with at least one scenario marked `repro: yes` (below); otherwise stop with
  `NEEDS_CLARIFICATION` naming what is missing.
- Thoroughness flags resolve once (`guides/thoroughness.md` § Input) and apply to both the
  research run and the gate, with two exceptions, because the two flows read the same names
  differently (`guides/thoroughness.md` § Presets: `max_iter` is the gate cap in the team flow
  and the per-teammate round cap in research):
  - `--max-iter` and the preset's `max_iter` apply to the fix phase only. A research run
    started by `/fix-bug` gets research's own default cap (3), never the team flow's.
  - `--max-agents` is **one ceiling per phase**, as today: the research run counts from zero
    against it and so does the gate. A `/fix-bug` run can therefore dispatch up to twice the
    number typed; the usage line says so. (A shared ceiling would let research starve the gate
    at `quick`.)
  An owner who wants a custom research run starts `/research` by hand, and `/fix-bug` picks
  the result up.
- `--auto` and `--no-test` mean what they mean in `/feature-flow`, with the exceptions named
  under each step.

### Topology

```
/fix-bug FRONT-XXXX
 1. diagnosis    pick up settled investigation(s) │ run /research (frame → lead → critique)
 2. decisions    owner answers what the research left open            ← the planned pause
 3. planning     Planner: bug spec + plan from Next + decisions
 4. team up      Coder, Tester, Reviewer (+ standby Planner), ALL on standby
 5. spec review  Reviewer reads spec + plan against the code   ┐ one message,
 6. red          Tester drives the repro scenarios, unfixed    ┘ in parallel
    branch gate  only now (bug-fixes.md: no branch before the repro is confirmed)
 7. coding → testing (green on the same steps) → reviewing → gate → finish
                 = ai-workflow.md § Procedure steps 3–7, unchanged
```

`--spec` enters at 4. Steps 1 to 6 and the moved branch gate are the whole of bug mode.

### 1. Diagnosis

- **Finding investigations.** Scan `.claude/investigations/*/findings.md` frontmatter for
  `ticket:` equal to the bug ticket and `kind: incident`. Follow `superseded_by`. Keep those
  with `status: settled`, newest folder first. All of them are the diagnosis; where two
  disagree the newest governs. (Checked 2026-11-11: both FRONT-AAAA folders are
  `kind: incident`, `status: settled`.) A settled run of another kind on the same ticket is
  listed for the owner in the decisions step, not treated as the diagnosis.
- **None settled, or `--run-research`:** execute `commands/research.md` § New run for the bug
  ticket in this session (its Framing is inline and asks the owner; its critique runs here),
  with the resolved knobs. When a settled investigation already exists and `--run-research` was
  given, the framing says so and frames a delta run, as on 2026-11-04. The run's folder goes
  into the run document at once, so a resume finds it.
- **An investigation exists with `status: open`.** Open covers every unfinished run: just
  framed, paused on `AWAITING_HUMAN`, mid-critique, ended `PARTIAL`, or live in another
  session. `/fix-bug` does not guess which. It asks the owner: resume it (research.md
  § Resume, which works only from the session that ran its lead), plan from it as it stands,
  run a delta, or stop. Under `--auto`: stop, `NEEDS_OWNER`.
- **Research returns `AWAITING_HUMAN`:** the run pauses the way `/research` does. The final
  block is `NEEDS_OWNER` with the action. **In the same session,** `/fix-bug --resume`
  executes research.md § Resume and carries on. **From a new session** research.md § Resume
  step 4 applies unchanged: the lead cannot be resumed and no fresh lead is started for an
  existing run. `/fix-bug --resume` then offers what that step offers (abandon, or a new `-2`
  run seeded from the old one) plus "plan from it as it stands". This design adds no way to
  revive a research lead.
- **`STOPPED`, or `stopped` / `on-hold` on disk:** stop, `BLOCKED`, quoting `status_reason`.
- **Next says "No build needed":** stop with the new final status `NO_BUILD_NEEDED`, quoting the
  Answer.
- Framing always asks the owner, even with `--auto`: the question being researched is the
  owner's. (Same standing as the branch gate.)

### 2. Decisions

The lead reads the investigation's `## Open`, `## Options` and `## Decisions` and lists what
only the owner can settle and has not: Open rows whose resolver is the owner, an Options table
with no Decisions row choosing, and a `## Repro` that is not `REPRODUCED` (missing,
`NOT_REPRODUCED`, `BLOCKED` or `not_run`). For that last one the choices are: waive the repro
and proceed on the evidence, try Red anyway with the steps the investigation attempted, or
stop (see Red). One
`AskUserQuestion` batch, the research's recommendation first in each. Each answer becomes a
`DECISION` block `by: owner` in the run document's state block. `findings.md` is not touched.

Nothing to decide: no pause. Under `--auto` with something to decide: stop, `NEEDS_OWNER`,
listing the questions. A council may not assume an owner's product decision about a bug fix.

If the lead's context is at risk after a research run in this session, the existing rule
applies here: write the state block and stop with the resume command.

### 3. Planning

Planner as today (inline, or `Agent(planner)` with `--auto`), with one new capsule item:

```yaml
diagnosis:
  investigations: [<folder>, …]     # newest first
  next: <the Next paragraph(s), verbatim>
  decisions: [D1, D2, …]            # by: owner, from step 2
  bug_ticket: FRONT-XXXX
  fix_ticket: FRONT-YYYY
```

`agents/planner.md` gains: a capsule with `diagnosis:` makes this a bug spec whatever the issue
type, and

- **Context** states the root cause in the investigation's words, each claim keeping its label
  and its finding number.
- **Repro Steps** come from `findings.md` § Repro and the repro-driver report it links, not
  from a fresh guess. When the investigation did not reproduce and the owner chose "try Red
  anyway", they are the steps the investigation attempted, labelled `assumed`. When the owner
  waived the repro, the section says `waived (D<n>)` and no scenario is marked `repro: yes`.
- **Test Scenarios** mark the scenario(s) that reproduce the bug with a line `repro: yes` and
  give two expectations: `expected (unfixed)`, the symptom, and `expected (fixed)`. These are
  the red/green scenarios. `templates/spec-template.md` documents both lines for bug specs.
- The owner's decisions become dated rows the way the reference spec carried them.
- It does not re-ask what the diagnosis or a decision settles.

### 4. Team up

As § Procedure step 2, except that **Coder also gets the standby brief** and starts nothing.
Bug mode's Coder is resumed for the first time after Red.

### 5. Spec review (parallel with 6)

Resume Reviewer with "SPEC REVIEW": read the spec and the plan against the code as it stands
and report where they cannot work, contradict the code, or contradict the diagnosis. It emits
its usual block with a new status pair, `SPEC_APPROVED` / `SPEC_CHANGES_REQUESTED`, the same
severities, and `findings[]` whose `file`/`line` point into the spec or the plan.

- `blocker` and `major` findings are fixed in the spec and plan before coding. Under `--auto`
  the standby Planner is resumed with "FIX FROM SPEC REVIEW" and edits the pair, which is the
  one write a standby Planner may make; it needs `Edit` added to its tools (it has only
  `Write`, and a subagent's whole-file `Write` over a main-session file was measured refused,
  `guides/research-workflow.md` § Flow and roles). In every other case the lead applies them:
  it planned inline, or the run entered by `--spec`, or it was resumed.
- A finding whose fix changes an owner decision goes to the owner, not to a council.
- **One pass, no loop, no counter.** The reference review was one pass, and the gate at the end
  still stands behind it. (YAGNI call: a re-review loop is easy to add if one pass proves leaky.)
- Reviewer keeps what it read: the same agent reviews the code in step 7.

### 6. Red (parallel with 5)

Resume Tester with "RED CHECK": drive only the `repro: yes` scenarios on the tree as it is and
report against `expected (unfixed)`. New Tester status pair for this brief: `REPRODUCED` /
`NOT_REPRODUCED`, with the evidence paths; `NOT_REPRODUCED` needs a positive control
(`research-discipline.md` § 3). Steps follow `bug-fixes.md` § Mimic the real user flow.

- The Tester block lists a result per scenario: `reproduced`, `not_reproduced` or
  `not_executable` (with the step that could not be done). `REPRODUCED` needs every
  `repro: yes` scenario reproduced; anything else is `NOT_REPRODUCED`.
- Evidence is captured on success as well as failure and is written under
  `.claude/runs/<run-slug>-evidence/`, not `/tmp`, so the red half outlives the session.
- `REPRODUCED` → record `repro: REPRODUCED` and the evidence paths in the state block.
- A `not_executable` scenario is a spec defect: it joins the spec review's findings, the spec
  is fixed, and Red runs once more. A second `not_executable` is treated as `NOT_REPRODUCED`.
- `NOT_REPRODUCED` → the owner chooses: widen the net, proceed on the evidence, or stop.
  Proceeding is a `DECISION` `by: owner` and `repro: waived (D<n>)`; stopping is the new final
  status `NOT_REPRODUCED`. Under `--auto`: stop, `NOT_REPRODUCED`. Never proceed silently.
- **Widening the net** is a delta `/research` whose question is the repro. When it settles the
  run re-enters at step 2 (decisions, only what is new), then step 3 with Planner **revising
  the existing pair** rather than writing a new one (the lead does it: widening never happens
  under `--auto`), then spec review of the changed parts and Red again, with the same team.
  **One widening per run.** After a second `NOT_REPRODUCED` the owner's choices are proceed or
  stop.
- **The waiver can come earlier.** If the investigation's own Repro is not `REPRODUCED` and the
  owner chose in step 2 to proceed on evidence, Red is skipped and `repro: waived (D<n>)` is
  recorded then.
- **`--no-test` is the owner's waiver** (owner, 2026-11-11). There is no Tester, so no red
  and no green. The lead records a `DECISION` `by: owner` ("`--no-test` typed: repro waived")
  at the start of the run and `repro: waived (D<n>)`, warns once, and the recap says so in its
  first line. Reviewer and the gate's hunters read that decision, so "fixed without a repro"
  is not a finding. This keeps `/fix-bug` usable in a repo with no browser (e.g.
  a worker repo); a non-browser red step, such as a failing unit test written first,
  is not built here.
- A spec fix after Red that changes a `repro: yes` scenario's steps makes Red run again.

Then the **branch gate**, as § Branch policy, always. It sits here because `bug-fixes.md` says
not to prepare a branch before the repro is confirmed and nothing before this point edits
source.

### 7. Fix

§ Procedure steps 3 to 7. Two additions to messages, none to routing:

- Coder's first resume: "the spec is final; repro: <state>; decisions so far: D…". In bug mode
  that `repro:` state **is** the confirmation `agents/coder.md` asks for ("confirm the spec's
  Repro Steps before editing"): Coder has no browser and does not reproduce again.
- Tester's "the tree is ready" names the `repro: yes` scenarios and the red evidence paths; a
  `PASS` needs each of them to meet `expected (fixed)` on the same steps, and the Tester block
  lists the red and green evidence side by side. With `repro: waived` it runs the scenarios as
  usual and says the red half is missing.

The recap (step 7) adds: the investigation folders, the bug and fix tickets, the root cause in
one line, the repro state, and the red and green evidence paths.

### Run document and resume

- The state block gains `mode: feature | bug` (absent means `feature`), `bug_ticket`,
  `fix_ticket`, `investigations: […]`, `repro: pending | REPRODUCED | waived (D<n>)`,
  and the `step` enum gains `diagnosis | decisions | spec-review | red` before `coding`.
- In bug mode the run document is created at the start (`step: diagnosis`), named from the fix
  ticket when given, else the bug ticket.
- `--resume` reads `mode` from the state block and follows it, whichever of the two commands
  was typed. `commands/feature-flow.md` § Resume therefore stops hard-coding the feature path
  and points at the guide's § Resume; in bug mode the branch gate is re-run only from `coding`
  on. At `step: diagnosis` it executes `commands/research.md` § Resume on the recorded
  folder, or re-scans when the folder is settled. Steps `spec-review` and `red` restart from
  their beginning with a fresh team, as every step does today.

### Final block

The guide's lead block, plus `investigations`, `repro`, and two statuses:
`NO_BUILD_NEEDED` and `NOT_REPRODUCED`.

### Files

| File | Change |
|---|---|
| `commands/fix-bug.md` | new; input parsing, where each phase runs, resume, final block, what the lead does not do. No procedure. Modelled on `commands/feature-flow.md` |
| `commands/feature-flow.md` | § Resume points at the guide's § Resume and follows `mode`; nothing else |
| `guides/ai-workflow.md` | new `## Bug mode` section holding steps 1 to 6, the moved branch gate and the message additions; state block, step enum, status tables, § Resume, § Roles and entry points, § Bug-fix rule updated to point at it |
| `agents/planner.md` | the `diagnosis:` capsule rules; the "FIX FROM SPEC REVIEW" exception to standby; `Edit` in tools; revising an existing pair after a widening |
| `agents/reviewer.md` | the "SPEC REVIEW" brief and status pair |
| `agents/tester.md` | the "RED CHECK" brief, status pair and per-scenario results; evidence on success, under `.claude/runs/`; red/green in `PASS` |
| `agents/coder.md` | standby at team-up in bug mode; the first-resume message; the lead's `repro:` state as the repro confirmation |
| `templates/spec-template.md` | `repro: yes`, `expected (unfixed)`, `expected (fixed)` for bug specs |
| `rules/bug-fixes.md` | one line naming `/fix-bug` as the automated form of the workflow |
| `guides/thoroughness.md`, `CLAUDE.md`, `README.md` | the command added wherever `/feature-flow` is listed |
| `scripts/harness-check.sh` | cases in the style of the `feature-flow` block: the command Reads the guide and holds no procedure heading; every new status and step token appears in both the guide and the agent file that emits it; the thoroughness-flag loops include `fix-bug` |

## Changed by the final review (2026-11-11)

The whole-branch review found places where a lead reading § Builder's calls literally would
guess. The guide (`guides/ai-workflow.md` § Bug mode) is the current text; it differs from the
sections above in these points:

- **Diagnosis outcomes are decided by the newest `kind: incident` folder only.** Older `open`,
  `stopped` or `on-hold` folders are ignored, research runs only when there is none settled and
  none open, and an owner "stop" ends `BLOCKED`.
- **A waiver chosen in the decisions step writes `repro: waived` at once,** and stopping there
  ends `NOT_REPRODUCED`.
- **Under `--auto` the standby Planner applies spec-review fixes in every entry;** otherwise the
  lead does. A standby Planner is dispatched in every bug run, `--spec` included.
- **The state block also carries `spec`, `plan`, `widened` and `red_refix`,** so a resumed run
  finds its spec and cannot offer a second widening or a second spec re-fix.
- **With `--spec`, only this run's waiver counts** (`--no-test`); the run document is named
  from the spec's filename stem.
- **The gate's hunters do not read decisions.** A "fixed without a repro" finding is withdrawn
  by Coder's answer citing the waiver decision, as any decision is.
- **Coder is never resumed while `repro: pending`,** and team-up no longer sets `step: coding`.

## Left to the builder

- The exact wording of the briefs and of `## Bug mode`, within the rules above.
- Whether `## Bug mode` is one section or folded into § Procedure as marked sub-steps, as long
  as a feature run reads no bug step and `harness-check` can tell them apart.
- How `commands/fix-bug.md` shares the input-parsing text with `feature-flow.md` (repeat it, or
  point at it).
- The `harness-check` case list beyond the three kinds named above, red first as in earlier work.
- Whether the installer needs a manifest entry for the new command file.

## Acceptance

1. `scripts/harness-check.sh` passes, including the new cases and the load budget.
2. **Smoke, `--spec` entry:** in the reference project, after an `install --update` the owner
   approves, `/fix-bug --spec=<the reference fix ticket's spec>`
   (the spec needs its repro scenario marked first) reaches Red and reports `REPRODUCED` or
   `NOT_REPRODUCED` with evidence before any source file changes.
3. **Smoke, pick-up entry:** `/fix-bug FRONT-AAAA --fix-ticket=FRONT-BBBB` finds both
   investigations (`2026-10-28-front-aaaa`, `2026-11-04-front-aaaa`, both settled) without
   starting research, and its decision pause lists nothing the
   investigation's Decisions table already settles.
4. **Full run** from a ticket with no investigation, at `--effort=quick`, on the next suitable
   bug. Until then this row stays open, and the Status line says so.
5. A `/feature-flow` run document from before this change resumes unchanged.
