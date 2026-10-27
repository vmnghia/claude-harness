---
ticket: FRONT-XXXX            # optional: delete this line if there is no ticket
kind: incident                # incident | codebase | web | design | copy | review | measurement
status: open                  # open | settled | stopped | on-hold | superseded
status_reason:                # required for stopped / on-hold (what blocked it, or what would reopen it)
superseded_by:                # path, when superseded
question: <the one question this investigation answers>
created: YYYY-MM-DD
updated: YYYY-MM-DD
author: <agent name or session>
---

<!-- Findings template. Copy to .claude/investigations/YYYY-MM-DD-<ticket-or-topic>/findings.md.
     Rules this file applies: .claude/rules/research-discipline.md (read it first).
     - Core sections (no marker) are always kept; write "none" rather than deleting one.
     - Blocks marked "optional" are deleted when they don't apply.
     - Correct findings IN PLACE. Never append an addendum that leaves the body wrong: mark the
       overturned finding `~~claim~~ superseded YYYY-MM-DD by #n: <why>` and add a Log line.
     - This is the working record, for agents and the owner. Jira comments and published reports are
       derived from it (written for a mixed audience: answer first, tight bullets) and listed under Sources & files.
     - Raw data never goes here: it lives in results.txt / raw/ next to this file. -->

## Answer

<!-- At most 5 lines, answer first, or "Not yet answered" plus the best current hypothesis.
     End with confidence, naming the riskiest assumption from the ledger. -->

## Assumptions ledger

<!-- Each load-bearing fact and how it was verified, riskiest first (research-discipline.md §7). -->

| Fact | How verified | Label |
|---|---|---|
| <fact> | <`<sha>` pinned / query R3 / working tree, unverified> | measured / read / inferred / assumed |

## Findings

<!-- Numbered, so other sections can cite #n. One bold claim each, then its evidence:
     `path:line@sha`, `URL@version`, `results.txt ===== Qn =====`, or a screenshot path. -->

1. **<claim>** `[measured]`
   Evidence: <where, pinned>

## Not shown / ruled out

<!-- Hypotheses killed and what killed them. Nulls together with their positive control
     (research-discipline.md §3). What the evidence cannot show. -->

## Decisions

<!-- Date, who, what. Settled items live here; check this before calling anything open. -->

| Date | Who | Decision |
|---|---|---|

## Open

<!-- Each open question: what would resolve it, and who can (the owner, ops, a query, a repro). -->

## Next

<!-- What to build, or "no build needed". research-lead hands this to Planner. -->

## Repro

<!-- optional: delete if N/A. Env, build mode, variant/version forcing, cookies, device/UA, steps,
     result REPRODUCED / NOT_REPRODUCED with its positive control, link to the repro-driver report. -->

## Options

<!-- optional: delete if N/A. Mitigations or design alternatives. -->

| # | Option | Effort | Risk | Fixes root cause? | Recommended |
|---|---|---|---|---|---|

## Method

<!-- optional: delete if N/A. How this run collected or attributed its evidence: sources, clock
     (state UTC vs ICT), attribution rules for raw data, sampling. Descriptive only; advice for
     next time goes under Lessons. -->

## Critique

<!-- every kind: the critique's checked-claim table, one row per finding, verdict = its end state;
     a run without findings says `no findings`; names the critique case file
     (critique.md; guides/research-workflow.md § Critique). -->

| Claim (quoted) | Verdict | Severity | Evidence |
|---|---|---|---|
| <claim> | FIXED / AGREED / WITHDRAWN / REFUTED / ESCALATED / STALEMATE / CONTESTED | blocker / major / minor / nit | <where> |

Case file: <investigation folder>/critique.md

## Lessons for future runs

<!-- optional: delete if N/A. What any future run should do differently: traps hit, tool quirks,
     wasted steps. Each lesson names where it should live; moving it there is an edit the owner
     approves, so agents only propose it here. -->

| # | Lesson | Promote to | Promoted? |
|---|---|---|---|
| 1 | <lesson> | rules/<file>.md / templates/<file>.md / skills/<name> / memory / none | no / yes, YYYY-MM-DD / n/a |

## Sources & files

<!-- Every source read, with its pinned version. Then this folder's map:
     capture.md (human-run query sheet from templates/capture-sheet.md; capture-<system>.md if several), results.txt
     (===== Qn ===== markers), evidence-<topic>.md (deep-dive appendices), raw/ (exports, logs).
     Derived outputs: Jira drafts and published artifacts, with version, location, and which is current. -->

## Log

<!-- Dated, newest last: what changed in this file and why (finding superseded, status changed). -->

- YYYY-MM-DD: created.
