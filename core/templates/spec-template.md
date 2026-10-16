---
ticket: FRONT-XXXX            # optional — delete this line if no ticket
title: <one line>
created: YYYY-MM-DD
status: draft
---

<!-- Canonical spec template. Planner copies this file and fills every
     section. Sections marked "delete if N/A" may be removed; all others
     are mandatory. Filename: YYYY-MM-DD-<topic-kebab>-spec.md -->

## Context
Why this change exists, who/what is affected, evidence (Jira link, log, repro).

## Goal
One sentence on the expected outcome.

## Non-goals
What is explicitly NOT in scope.

## Constraints
Stack pins (from `project.md` § Stack), relevant rules
from `.claude/rules/*`, and risk boundaries (payment, analytics, SEO paths).

## Repro Steps
<!-- Bug specs only — delete for features. Per .claude/rules/bug-fixes.md:
     reproduce BEFORE fixing. -->
Numbered steps that reliably reproduce the defect locally: env
(prod/staging/local), browser, device emulation, cookie state, build mode.

## Implementation Plan
Ordered steps. Each step:
- intent (why)
- files touched
- per-step verification (build? scenario? test case?)

## Unit Test Notes
<!-- Consumed by Coder and Reviewer when the project has a test runner
     (project.md § Commands). -->
Which changed logic deserves test cases; expected behaviors per case.
Write exactly `n/a — no test runner` when the project has none.

## Test Scenarios
<!-- Consumed by Tester. Each scenario must be executable without reading
     anything else in this spec. -->
For each scenario:
- name
- preconditions (cookies, store/slug, version forcing, paygate state)
- URL (full, including port — Tester probes this host, nothing hardcoded)
- steps (chrome-devtools MCP actions: navigate_page, evaluate_script, click…)
- expected DOM / console / network outcome
- evidence to capture (screenshot path, console lines)

## Open Questions
Anything unresolved that blocks the flow. Autonomous planning mode records
assumptions here as `ASSUMED: <what> — flag if wrong`.

## References
Jira, Confluence, Figma, file paths.
