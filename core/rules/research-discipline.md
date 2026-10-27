---
load: always
---
# Research discipline

How to gather evidence and state conclusions in an investigation, a research brief or a review.
**Required reading** for the research team (`research-lead`, `searcher`, `web-reader`, `designer`,
`writer`, `incident-investigator`, `repro-driver`, `research-critic`, `research-judge`) and for
`reviewer`. Planner reads it with every
other rule.

> Condensed on 2026-10-14 from the owner's personal memories, which keep the full incident detail:
> `investigation-discipline`, `verify-means-check-the-basis`, `suspect-the-instrument`,
> `stop-triggers-for-delegated-work`, `verify-data-flow-claims-before-dispatching`,
> `verify-ticket-diagnosis`, `nextjs-docs-use-versioned-pages-urls`,
> `pin-confluence-source-revision-in-specs`, `check-decisions-table-before-flagging-open`,
> `user-input-is-authoritative`. Both copies are kept on purpose. If this file and a memory
> disagree, stop and ask the owner; don't pick one.

The common failure: wrong inference feels identical to right inference from the inside, so
confidence is not a usable signal. The 2026-09-15 outage investigation produced six successive,
well-argued root causes, all built on unverified provenance.

## 1. Label every claim

- Tag each claim with its provenance: **measured** (by you, with what), **read** (`path:line` at
  `<sha>`, or a URL with version), **inferred**, or **assumed**. An unlabelled claim reads as
  unverified.
- For a conclusion, name its load-bearing assumption and say what changes if it is wrong.

## 2. Before you assert

- **Read the whole source** before quoting or disputing it. In the outage, the answer to a
  three-day dispute was a figure caption under the disputed table.
- **Pin the version of every source.**
  - Code: what ran, not the working tree. `git rev-list -1 --before="<time>" origin/stable`,
    then `git show <sha>:<path>`.
  - Next.js docs: `https://nextjs.org/docs/15/pages/…`. Unversioned URLs serve 16.x and mix in
    App Router examples.
  - Confluence: the API version number, never the page's hand-edited "Last updated" field.
- **Know what your instrument measures:** sampling interval, aggregation window, units.
  `rate()` at a step finer than the scrape interval fabricates a smooth curve.
- **Grep a data path before describing it.** Code structure is a good prior and a bad fact: six
  briefs in one session described data flow from how the code looked, and each was wrong.
- **Identity before properties.** Confirm what an entity is (pod → owning RS → configmap →
  branch) before attributing anything to it. Don't grep the config that matches your label.
- **Print a raw sample before trusting a classifier.** A regex once truncated
  `reserve-internal` to `reserve`, and every property of that "control" group was wrong.

## 3. Before you report a null

"Not found", "zero occurrences" and "not reproducible" need proof that the probe ran.

- Run a **positive control** on data known to match. A null that tidily confirms the current
  story deserves more scepticism, not less.
- Scripted input changes what is on screen: record the element's viewport position
  (`getBoundingClientRect` vs `innerHeight`) when you read a lazy-loaded state.
- An SDK error surfaced via `console.error` is **not thrown**; a try/catch probe misses it.

## 4. Reasoning traps

- **A prediction is not an observation.** Re-test a mechanism against every verified fact,
  your own included. A claim about a moment needs the subject's own telemetry at that moment.
- **A calibration holds only for the phenomenon it was measured on.**
- **If the verdict flips when you re-read the same data, it was interpretation.**
- **Parsimony is not evidence** against a measured, co-occurring alternative.
- **Apply a document's own caveats to its own headlines**, including yours.
- **Check your new claims as hard as inherited ones.**
- **A matched-point comparison needs the surrounding series.** One matched minute inside 10×
  swings is a coincidence.
- Classify a consumer (work queue vs broadcast) before recommending messaging-topology changes.

## 5. Sources and authority

- **A ticket's stated root cause is a hypothesis.** FRONT tickets have named the wrong one more
  than once. Confirm against the real event, breadcrumbs or console before building its fix.
- **Reports from other teams or other models are claim sets**, not sources of truth, however
  official they look. Check them like your own.
- **Before calling anything "new" or "open"**, grep the spec's Decisions table and read
  `git log --date=format:'%m-%d %H:%M' --pretty=format:'%h %ad %s' -25`. Settled work has been
  re-raised as news. If a decision contradicts the commits, the commits win.

## 6. Stop triggers

Act on these without being asked:

- **A third hypothesis for one observation** → the observation is mismeasured or the source is
  unread. Stop producing; go back to provenance.
- **About to dispute a source** → read it end to end first.
- **About to cite code or config** → pin the commit. **About to cite a metric** → know its
  sampling and aggregation.
- **Your data contradicts the owner's or another team's** → verify your own instrument first.
- **Genuine ambiguity that changes the work** → in the main session, ask. A subagent can't ask:
  **stop and report** the trigger, what you have, and what would resolve it.

## 7. Assumptions ledger

Any long or unsupervised deliverable opens with a ledger: each load-bearing fact and how it was
verified, e.g. `77643bd6 (pinned)` vs `working tree (unverified)`. A 30-second scan should show
where the risk is without reading the work. The shape is the ledger table in
[templates/findings-template.md](../templates/findings-template.md).

## 8. Writing briefs

For `research-lead` and `incident-investigator` when dispatching a teammate:

- State the **goal** alongside the mechanism, so a teammate who finds the mechanism false still
  knows what to do.
- Include a **context capsule** (`guides/ai-workflow.md`): subagents start cold, so pass the facts
  they need, and never invent ones you don't have.
- Grep every path and field you name in the brief (§2).
