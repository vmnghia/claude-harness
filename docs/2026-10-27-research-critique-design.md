# Research critique: peer review for `/research` findings

Status: draft for the owner, 2026-10-27. Builder check done. **Prerequisite:**
[2026-10-27-thoroughness-knobs-design.md](./2026-10-27-thoroughness-knobs-design.md) (width,
dry rounds, N-way cross-examination, presets, the agent ceiling) is built **first**; this
design's plan starts once `guides/thoroughness.md`, the shared flags and the N-way tally exist,
and it never hardcodes a size those define. Read that design first.

## Intent

A `/research` run ends with the lead merging every teammate's report into `findings.md` and
writing Answer and Next. The lead "spot-checks load-bearing claims" (`research-lead.md` step 5),
but that is the author checking its own work: nobody independent reads the report before the
owner acts on it. In scientific practice a result is not a result until reviewers who did not
produce it have tried to break it. The owner wants that here, as a hardening step rather than
in response to a known bad run.

This design adds **peer review** to `/research`, taken literally: reviewers (fresh
**critics**), an author rebuttal (the **lead**, resumed), an editor's ruling on what they cannot
settle (a fresh **judge**, then the owner). The research discipline is already the rubric;
`findings-template.md` already has the shape for a checked claim; the adversarial-review guide
already has the hunt → cross-examine → debate → judge machinery. The design reuses all three.

## Evidence

- **What a critic can hold the report to** is written down: `research-discipline.md` § 1
  (label every claim), § 2 (pin every source), § 3 (positive control before a null), § 4 (the
  reasoning traps), § 5 (a ticket's root cause is a hypothesis; check the Decisions table and
  the log before calling anything new), § 7 (the ledger).
- **The lead is resumable.** `/research` writes `lead.txt` with the lead's agent id and resumes
  it with `SendMessage` after `AWAITING_HUMAN` and after infrastructure failures
  (`research-workflow.md` § Waiting for the owner). An author rebuttal is the same mechanism
  with a new message.
- **The single-writer rule** (`research-workflow.md` § Flow and roles): only the lead writes
  `findings.md`, by `Edit`; the main session writes only `lead.txt`. Critics therefore return
  blocks and the lead applies them; the orchestrator keeps its own case file.
- **`findings-template.md` § Claims checked** (kind `review`) already defines a checked-claim
  row: claim quoted, verdict `holds / wrong / unverifiable`, severity, evidence. The critique's
  record in `findings.md` is that table.
- **The adversarial-review guide** defines the finding discipline (pre-report gate, proof for
  `blocker`/`major`, "zero findings is a valid result"), the debate rules (evidence gate,
  exhaustion, judge ladder), the end states and the message shapes. The critique keeps them and
  changes only what a finding is about.

## Decisions (owner, 2026-10-27)

- **Fresh critics after the lead returns**, dispatched by `/research` from the main session,
  independent of the lead and of each other until cross-examination. Width from the knobs
  (`standard` 2, `thorough` 3, `exhaustive` 5). Angles: *evidence-first* and *argument-first*
  (a third, *scope-and-decisions*, at width 3; above three the angles cycle).
- **The lead is the author.** It answers the critique, edits `findings.md` itself, and remains
  its only writer.
- **Disputes go to a fresh judge first, then to the owner.** `research-judge` rules on a claim
  the critic and the lead argued to a standstill; what the judge cannot settle from the run's
  evidence reaches the owner as a `disputed` Open row with one question.
- **On by default; `--no-critique` skips it.** The `quick` preset also skips it.
- **Knobs come from the thoroughness design:** critic width, `K` for the critique loop, the
  agent ceiling.

## Builder's calls (veto-able)

### Topology

```
/research … (existing: Frame → Agent(research-lead) → lead returns ANSWERED | PARTIAL)
 ├─ critique (new, main session as orchestrator; skipped by --no-critique, --effort=quick,
 │            or a lead status of STOPPED / AWAITING_HUMAN)
 │   1. Hunt: N research-critic agents in one message, each with the critique capsule
 │   2. Cross-examination: N-way, per the thoroughness design; tally; duplicates merge
 │   3. Rebuttal: SendMessage to the lead (lead.txt) with every AGREED and open finding
 │   4. Re-check: each asserting critic gets the lead's reply on its findings; turns
 │      (critic ↔ lead) for blocker/major, with the evidence gate and exhaustion as in the
 │      adversarial guide
 │   5. Judge: research-judge per stalemated blocker/major; one challenge turn; then disputed
 │   6. Synthesis into critique.md; K-loop (thorough): a further critique round on the revised
 │      findings.md with fresh critics, until a round is dry
 │   7. "Critique settled" to the lead → it finishes the write-up (Answer, Next, § Critique,
 │      the Confluence draft) and returns its final block
 └─ Report: the lead's final block, Answer, Next, and the critique table
```

The critique runs after the lead's **first** return and before its write-up is final: the
lead's run splits into *gather and draft* and *finish*. On `AWAITING_HUMAN`, the critique waits
for the resume that ends in `ANSWERED`/`PARTIAL`. On `STOPPED` there is nothing to review.

### Who the critics are

`agents/research-critic.md`, model `claude-opus-5-5` (this is interpretation, not lookup; the
haiku pins are for `searcher` and `web-reader`). Tools: `Read`, `Bash`, `WebFetch`. No `Write`,
`Edit`, `Agent`, `Grep`, `Glob`, `SendMessage`, no Atlassian tools. It reads
`.claude/rules/research-discipline.md` and `.claude/guides/research-workflow.md`, the critique
section of `guides/adversarial-review.md` (finding discipline, debate rules, message shapes) and
the investigation folder it is given.

**Bash boundary:** `review-bash-gate.sh` gains `research-critic` and `research-judge` to its
`agent_type` list, with one addition to the allowlist for those two types only:
`bash .claude/scripts/verify-quote.sh <url> "<quote>"` (the network is already open to them
through `WebFetch`; the hunters' no-network rule stays for hunters). Everything else is the
hunters' boundary: read-only git, scratchpad scripts, read-only filters.

**What a critic reads and never reads.** It reads the run's folder in full (`findings.md`,
`run-log.md`, `results.txt`, `capture.md`, `evidence-*.md`, `raw/`, `design/`), the repo at the
pinned SHAs the findings cite (`git show <sha>:<path>`), the cited URLs, and the related spec's
Decisions table and `git log` for § 5 checks. It never reads other investigation folders,
`.claude/runs/` (the critique case file included), `.claude/reports/`, or a plugin store, and
says so if a search matches one. It gathers no new evidence: no `searcher`, no new web
searches; a claim it cannot check from what the run cites is `unverifiable`, which is itself a
finding when the claim is load-bearing.

### What a critic checks

The rubric is `research-discipline.md`; the critic works through it as the hunters work
through the playbook: angle order first, then the rest. Every critic covers all seven.

1. **Evidence says what the claim says.** For every numbered Finding and every ledger row, open
   the cited evidence (`path:line@sha`, the `results.txt` marker, the URL and quote, the
   screenshot) and check the claim is actually there. A quote not on the page, a line that
   says something narrower, a marker that holds a different query: finding.
2. **Labels are honest.** `measured` names the instrument and what it measures (§ 2);
   `read` carries a pin; `inferred` and `assumed` are not load-bearing without being named in
   the ledger and the Answer's confidence line.
3. **Nulls have controls.** Every entry under "Not shown / ruled out" has its positive control
   (§ 3); a `NOT_FOUND`/`NOT_REPRODUCED` merged without one is a finding.
4. **Answer follows from Findings; Next follows from Answer.** The Answer's confidence names
   the riskiest ledger row; nothing in Next rests on an `inferred` claim presented as `read`.
5. **Alternatives not ruled out.** An explanation consistent with the same evidence that the run
   did not test (§ 4: a prediction is not an observation; parsimony is not evidence; a matched
   point needs its series). The critic states the alternative and what observation would
   separate it: that is the finding's `trigger`.
6. **Already settled.** A claim the run calls new or open that the spec's Decisions table or
   the git log had settled (§ 5), or a ticket's stated root cause taken as fact.
7. **Scope.** The run answered the framed question, not a neighbour of it; every Open row
   from the framing is either answered, killed with evidence, or still Open with a reason.

**Angles.** `evidence-first`: 1, 2, 3, then 4–7. `argument-first`: 4, 5, then 1–3, 6, 7.
`scope-and-decisions` (width 3): 6, 7, 4, then the rest.

### The critique finding

The adversarial finding shape, with the code-specific fields replaced:

```yaml
- id: A1
  severity: blocker | major | minor | nit
  target: "#3" | "Answer" | "Next" | "ledger: <fact>" | "Not shown: <entry>" | "Open: H2"
  claim: <quoted verbatim from findings.md>
  kind: unsupported | mislabelled | null-without-control | non-sequitur | alternative | settled | scope
  trigger: <what the evidence actually shows, or the alternative and what would separate it>
  consequence: <what changes in Answer or Next if this stands>
  suggestion: <one line>
  provenance: read | inferred | executed
  evidence: <path:line@sha, URL + quote check result, results.txt marker, or script + output>
```

**Severity on the research scale**, mapped onto the harness scale so the ladder-scope rule
(everything past one cross-examination is for `blocker`/`major`) applies unchanged:

- `blocker`: the Answer or Next would change: a load-bearing claim whose evidence does not
  support it, or an untested alternative consistent with all the evidence.
- `major`: a load-bearing claim mislabelled or unpinned, a null without a control, a settled
  item re-raised as open, the framed question not answered.
- `minor`: the same defects on a claim nothing in Answer or Next rests on.
- `nit`: presentation; a label missing on a claim whose evidence is plainly cited.

The finding discipline applies unchanged: cite the exact line of `findings.md` **and** the
evidence you re-opened; name the trigger; a `blocker` built only on `inferred` is a `major`;
zero findings is a valid result, and a critique that manufactures one to justify its dispatch
is the failure mode to avoid. Provenance `executed` here means the critic re-ran a cited
check: `verify-quote.sh` on a quote, a scratchpad script over `results.txt`, `git grep -c` at
the pinned SHA against a count in a table.

### The round

1. **Hunt.** `/research` dispatches `N` critics in one message with the **critique capsule**:
   role and angle, the investigation folder path, the resolved knobs, the framing's question
   verbatim, `project.md` § Stack verbatim (for versioned docs), the session scratchpad path,
   the critique case-file path (reference only), the never-read list. Never the lead's
   transcript, never the other critics' output, never the owner's conversation. The reply is
   the hunt reply shape with `agent: research-critic`, `role: critic-A | critic-B | critic-C`,
   and no `questions[]` (the author answers in the rebuttal, not before).
2. **Cross-examination.** N-way, per the thoroughness design: each critic rules on the others'
   findings after re-opening the cited evidence; tally; `same_as` merges. `minor`/`nit` resolve
   here (`AGREED`, `WITHDRAWN`, `CONTESTED`) and never go further.
3. **Rebuttal.** One `SendMessage` to the lead's id, the **critique message**: every `AGREED`
   finding and every open `blocker`/`major` in finding shape, plus the `CONTESTED` ones for
   information. The lead's reply carries one entry per finding:

   ```yaml
   ---
   agent: research-lead
   phase: rebuttal
   status: REBUTTAL
   payload:
     responses:
       - id: A1
         response: FIX | MAINTAIN | OUTSIDE_RUN
         new_evidence: <required with MAINTAIN; "none" with FIX>
         edit: <FIX only: what changed in findings.md, one line, e.g. "#3 relabelled inferred; ledger row added">
         redispatch: <FIX only, optional: teammate re-dispatched to close the gap; counts toward its cap>
         question: <OUTSIDE_RUN only: the one thing only the owner can settle>
   ---
   ```

   `FIX` is applied **before** the lead replies: the edit is in `findings.md` (in place, per the
   template's supersede rule, with a Log line), so the critics re-check the file, not a promise.
   A `FIX` that needs new evidence may re-dispatch a teammate within its cap; the rebuttal
   waits for that report. `MAINTAIN` is the lead's turn in the debate and must carry
   `new_evidence`. `OUTSIDE_RUN` is `outside_repo` renamed: the answer is a capture nobody ran,
   prod state, product intent.
4. **Re-check and turns.** Each asserting critic receives the lead's responses on its own
   findings and the current `findings.md`. `FIX` → the critic confirms the edit closes the
   finding (`ACCEPT` → `FIXED`) or `CHALLENGE` with the line that still fails. `MAINTAIN` → a
   turn, as challenger: `ACCEPT` → `WITHDRAWN`; `CHALLENGE` with new evidence → the lead's next
   turn. The debate is **critic ↔ lead**, two-sided; the other critics do not take turns on it.
   The evidence gate, `peer_added_evidence`, exhaustion and the 8-turn cap are the adversarial
   guide's. Both sides saying `OUTSIDE_RUN` → `ESCALATED` with the question.
5. **Judge.** For every stalemated `blocker`/`major`: a fresh `research-judge` with the judge
   capsule (the folder path, the one finding, the critic's and the lead's final turns verbatim,
   every script path and output either side produced, the scratchpad path, the never-read
   list). It re-opens the evidence and rules `UPHELD | REFUTED | OUTSIDE_RUN` in the judge
   reply shape (`question` required with `OUTSIDE_RUN`). Both sides get one turn to challenge;
   a `CHALLENGE` gets one judge reply; a second `CHALLENGE` is `STALEMATE`. `UPHELD` goes back
   to the lead as a `FIX` it must apply (an upheld finding the lead rejects again is recorded
   and reported to the owner, as Coder's second rejection trips the breaker). `OUTSIDE_RUN` and
   `STALEMATE` are `disputed`.
6. **Synthesis.** The orchestrator writes the round's table into `critique.md` and rewrites its
   state block. End states per finding: `FIXED` (new: the lead's edit was accepted), `AGREED`
   (valid, `minor`/`nit`, left as a note), `WITHDRAWN`, `REFUTED`, `ESCALATED`, `STALEMATE`,
   `CONTESTED`.
7. **Dry loop** (`K > 0` only), with the thoroughness design's rules. A round is **dry** when
   it adds no new finding: one that is not a duplicate of any earlier round's finding and
   survives its cross-examination (any end state but `WITHDRAWN` or `REFUTED`). Duplicate here:
   same `target` and either the same `kind` or 60 % of `claim` words shared, so quoting a
   different sentence of the same Finding does not read as new. After any **non-dry** round, a
   further round runs with fresh critics on the current `findings.md`; `K` consecutive dry
   rounds end the critique, and so does the **hard cap of `2K` further rounds** (`dry_rounds`
   in the state block), in which case the report says the loop was cut at its cap, not dry.
   The critique therefore runs at most `1 + 2K` rounds; `K = 0` is exactly one.

### Closing the run

8. **"Critique settled"** goes to the lead with the final table. The lead:
   - writes **`## Critique`** in `findings.md`: the template's checked-claim table, one row per
     finding (`Claim (quoted) | Verdict | Severity | Evidence`, verdict = end state), plus one
     line naming the critique case file;
   - adds a `disputed` Open row per `ESCALATED`/`STALEMATE` finding, with the judge's or the
     critic's question and both positions in one line each;
   - rewrites Answer and Next if any `FIXED` finding touched them (confidence line included),
     bumps `updated`, adds a Log line;
   - then, and only then, writes the Confluence draft (step 8 of its procedure moves after the
     critique, so a draft never carries a superseded claim);
   - returns its final status block with a new payload field,
     `critique: {rounds, findings, fixed, agreed, withdrawn, refuted, disputed}`.

   **Status with a `disputed` finding.** A `disputed` `blocker` or `major` is, by the
   severity scale, a claim on which the Answer or Next may turn and which only the owner can
   settle: the lead returns **`AWAITING_HUMAN`** with `action: "answer the disputed questions
   in Open (<ids>)"` and frontmatter `status: open`, never `settled` (Framing step 2 cites
   `settled` runs instead of re-investigating, and `/planner` takes Next from them). The owner
   answers in chat; `/research --resume` sends "done: <answers>" to the lead, which records
   them as Decisions rows, closes or supersedes the findings, and finishes (`ANSWERED` →
   `settled`, or `PARTIAL` → `open` if a question stays open). A `disputed` `minor`/`nit`
   leaves the status as the lead had it; the rows remain. This is the adversarial
   `NEEDS_OWNER` expressed in the research team's existing owner-gated round.
9. **Report.** `/research` shows the lead's final block, Answer, Next, the critique table and
   every `disputed` question on its own line, then the Confluence draft line as today.

**If the lead cannot be resumed** (the session that ran it ended, `SendMessage` fails):
`critique.md` records the round with `rebuttal: unavailable`, no `findings.md` edit happens,
and the report shows the critique table beside the untouched Answer with a line saying the
author never answered. The owner reads both. No fresh lead is started for an existing run
(the existing rule).

**Standalone: `/research --critique <investigation-folder>`.** The same no-lead path as a
kept entry point: the critique stage alone on an existing folder, whatever its status, the
owner as the author. It is how the fixture is run (§ Verification plan), how a past run or a
report another team or model wrote gets checked (`research-discipline.md` § 5: reports from
other teams are claim sets), and the only way a critique starts on a run whose lead is gone.
`--resume` on a finished run never starts a critique; it resumes the lead, as today. `--critique`
takes the same knobs, writes `critique.md` in that folder (`-2` on collision), and never edits
`findings.md`. The report is the critique table and the `disputed` questions; what to change in
the file is the owner's.

### Case file

`<investigation folder>/critique.md`, written by the main session only (the second main-session
file in the folder, next to `lead.txt`; the single-writer rule gains that sentence). Shape as the
adversarial case file: a state block (`critique_round`, `dry_rounds`, `knobs`, `rebuttal: lead | unavailable`, `critics: {A, B, C}`,
`findings: [{id, dup, severity, target, state, issue}]`, `disputed: [{id, question}]`), then
verbatim appends per round: `### Hunt A|B|C`, `### Cross-examination`, `### Rebuttal`,
`### Re-check`, `### Judge <id>`, `### Synthesis`.

### `research-judge`

`agents/research-judge.md`, model `claude-opus-5-5`, tools `Read`, `Bash`, `WebFetch`; the same
"fresh on purpose, owes neither side anything" framing as `review-judge`, with evidence of the
research kind: it re-opens pins, markers, quotes and ledgers rather than callers and types.
Separate file (named trade-off: ~80 lines that echo `review-judge`'s framing, against teaching
one judge two evidence kinds and touching the adversarial lints). `OUTSIDE_RUN` in place of
`OUTSIDE_REPO`. Same never-read list as the critic.

### Knobs

From the thoroughness design: `--effort`, `--width=research-critic:N`, `--dry=K`,
`--max-agents`. `/research` resolves them once and passes numbers. The ceiling is split as
that design says: `/research` reserves the critique's share (`critic width × (K + 1)` critics
plus `critic width` judges) before the lead is dispatched, the lead's capsule carries the
remainder, and the critique counts against whatever the lead left of the whole. The first
critique round is therefore always affordable; a big run never skips its review for lack of
room. A lead re-dispatch during a `FIX` counts toward the lead's share and that teammate's
cap. `--no-critique` is a `/research` flag only; `quick` implies it.

### Harness bookkeeping

- `guides/research-workflow.md`: § Flow and roles gains the critique stage, the second
  main-session file, and the lead's two-phase run; § Status blocks gains `research-critic`
  (`FINDINGS | CLEAN`, then `RULINGS`, `TURN`), `research-judge` (`UPHELD | REFUTED |
  OUTSIDE_RUN`) and the lead's `REBUTTAL` block and `critique` payload field; § Tool boundaries
  gains both rows and both model pins.
- `guides/adversarial-review.md` § Message shapes: a short "Critique variants" subsection
  listing the fields the critique finding, rebuttal and `OUTSIDE_RUN` replace, so the shapes
  have one home. The critic and judge files point there.
- `agents/research-lead.md`: step 7 split into draft (first return) and finish (after
  "critique settled"); step 8 moved after the critique; the rebuttal shape; `## Critique` and
  `disputed` rows; the `critique` payload field.
- `agents/research-critic.md`, `agents/research-judge.md`: new.
- `commands/research.md`: the critique stage between Wait and Report; `--no-critique`;
  `--critique <folder>`; the shared flag block by reference; Resume: a critique in progress restarts its current round
  with fresh critics from `critique.md`'s state block (mid-round debate state is never
  restored, as in the adversarial resume).
- `templates/findings-template.md`: the `## Claims checked` block becomes `## Critique` for
  every kind (the review-kind use is a special case of the same table), with the one-line
  comment updated.
- `hooks/review-bash-gate.sh`: the two agent types; `verify-quote.sh` allowed for them.
- `CLAUDE.md`: the research-team row lists the two new agents; the guides table lists the
  critic and judge as consumers of both guides; the hooks table row for `review-bash-gate.sh`
  names the four agent types.
- `harness-check.sh` §5b extensions: status tokens for the two agents in both files; neither
  has `Write`/`Edit`/`Agent`/`Grep`/`Glob`; both have `WebFetch`; model pins; the gate's
  agent list includes both; `research-lead.md` contains `REBUTTAL` and `critique:`; the
  template has `## Critique`. §2-style matrix rows for the gate: `verify-quote.sh` allowed for
  `research-critic`, denied for `adversarial-reviewer`.

### Verification plan

- `harness-check.sh` green.
- **Fixture:** a past, settled investigation folder in one of the owner's projects (they pick
  one whose findings they know). `/research --critique <folder>` against it
  exercises hunt → cross-examination → synthesis on the command's own path, with the no-lead
  branch (`rebuttal: unavailable`); the rebuttal and re-check are first exercised live. Record
  what the critics raise, and whether every finding cites a line of `findings.md` and a
  re-opened piece of evidence. Expected cost: two opus critics reading one folder and a
  handful of pins, roughly one adversarial round.
- **Live:** the owner's next `/research` run, `standard` preset. The design's Verified section
  records the critique table, the rebuttal responses, and whether Answer or Next changed.
- A fresh `claude -p` for the agent files and the gate change (agent files load at session
  start).

## Non-goals

- Critics gathering new evidence (no `searcher`/`web-reader` dispatch from a critic): a
  peer reviewer checks what was cited and names what is missing; the lead's re-dispatch, within
  its caps, is how new evidence enters.
- Critiquing `STOPPED` runs, standalone `searcher`/`web-reader` lookups, or Confluence pages.
- A second fix loop after the dry loop: at `K = 0` the critique is one round plus the rebuttal.
- Changing the lead's own step-5 spot-check: it stays, and a critic finding that step 5 should
  have caught is reported as such in the `Lessons` table the lead already keeps.

## Left to the builder

- The exact text of the critique message, the "critique settled" message and the critic's
  re-check message, within the shapes above.
- Whether `critique.md`'s sameness rule for the dry loop needs a line-based component (targets
  are section references, not lines).
- The never-read list wording for the critic (the hunters' list minus the run's own folder).
- Which existing investigation folder serves as the fixture.
