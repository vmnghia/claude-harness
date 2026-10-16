---
title: Research team workflow contract (/research, research-workflow.md)
created: 2026-10-14
status: draft — awaiting the owner's review
---

## Context

The research team exists as seven agent stubs in `.claude/agents/` (2026-10-14): research-lead,
searcher, web-reader, designer, writer, incident-investigator, repro-driver. Their prerequisites
are in place: `rules/research-discipline.md`, `templates/findings-template.md`, the
`production-issue-triage` skill fixes, and the investigation folder `.claude/investigations/`.

What is missing is the contract between them: who dispatches whom, what each one returns, how a
run moves through human-run captures, and a lint that keeps agent files and contract in step.
`rules/ai-workflow.md` plays this role for the four feature-flow agents; nothing plays it for
research. Every stub's procedure (next work item, "#1") has to end with this contract's status
block, so the contract comes first.

## Goal

One rule file, `rules/research-workflow.md`, that defines the research team's flow, status
blocks, dispatch and iteration policy, and tool boundaries; a `/research` command that runs it;
and a harness-check section that fails when an agent drifts from it.

## Non-goals

- Writing the agents' procedures (work item #1).
- The designer's canvas medium and tools.
- Testing what happens to a teammate report that arrives after its dispatcher ended its turn
  (deferred by the owner; see Open).
- Changing the feature-flow contract beyond a one-line pointer.

## Constraints

- `ai-workflow.md`: commands select the execution locus, agent files hold the procedure. Same
  YAML status-block frame. Context capsule for every subagent dispatch.
- `research-discipline.md` applies to every agent (provenance labels, positive controls, stop
  triggers, assumptions ledger).
- `multi-session.md`: dev-server ports and the chrome-devtools profile are shared; the
  measurement lock file is respected.
- `autonomy.md` / `mcp-roster.md`: no writes to Jira, GitLab, Confluence, Slack or Sentry.
- Model policy (2026-10-14): Opus for lead, investigator, designer, writer; Haiku 5.5 for
  searcher (locate only); Sonnet for web-reader and repro-driver.
- `.claude/` is untracked: nothing here is committed.

## Decisions (2026-10-14)

| Question | Decision |
|---|---|
| Who dispatches the team | research-lead dispatches its teammates; the investigator dispatches repro-driver; nobody else dispatches |
| How /research runs the lead | Frame inline in the main session (can ask the owner), then dispatch research-lead as a subagent to run the team and write up |
| Where the contract lives | New `rules/research-workflow.md`; `ai-workflow.md` gets a one-line pointer |
| Late-report behaviour | Not tested now; recorded under Open |

## A. Flow and roles

```
/research <question | FRONT-XXXX> [--max-iter=N]
 ├─ 1. Frame (inline, main session; may ask the owner)
 │     procedure: research-lead.md § "Framing"
 │     → .claude/investigations/YYYY-MM-DD-<slug>/findings.md
 │       (frontmatter, question, dispatch plan: which teammate gathers what, and what result
 │        would confirm or kill each hypothesis)
 ├─ 2. Agent(research-lead) with the framing + a context capsule
 │     procedure: research-lead.md § "Running the team"
 │       searcher · web-reader · incident-investigator   in parallel when independent
 │       designer → writer                                in sequence (copy fills canvas slots)
 │       incident-investigator → repro-driver             the only nested dispatch
 │     the lead merges every report into findings.md and writes Answer + Next
 ├─ 3. Main session shows the owner the lead's status block + Answer + Next
 └─ 4. The owner decides whether to run /planner on Next
```

**Single writer.** Only research-lead writes `findings.md` and `run-log.md`. The investigator
writes `capture.md` and `evidence-*.md`; every other agent returns its results in its status
block only. (The designer's canvas files are decided with its medium.)

**Human-run captures.** Kibana, Grafana and API captures only the owner can run, and a subagent
cannot wait for them. The agent that needs one writes `capture.md` and returns
`AWAITING_CAPTURE` with its path; the lead propagates it. `/research` shows the owner the sheet;
after they paste results into `results.txt` and says so, `/research` **resumes the same lead** via
SendMessage (it continues from its transcript, counters intact). It never starts a fresh lead for
an existing run.

## B. Status blocks

Same frame as `ai-workflow.md`:

```yaml
---
agent: <name>
status: <enum>
iteration: <n>
findings: .claude/investigations/<folder>/findings.md
payload:
  stop_trigger: null            # or which research-discipline.md §6 trigger fired
  assumptions: []               # each with its label
  <agent-specific fields>
---
```

| Agent | Status | Payload (core fields) |
|---|---|---|
| research-lead | `ANSWERED` / `PARTIAL` / `AWAITING_CAPTURE` / `STOPPED` | `findings_path`, `answer` (one line), `next` (build / no-build + summary), `open[]`, `capture_path`, `dispatches[]` (agent, status, iteration) |
| incident-investigator | `DIAGNOSED` / `PARTIAL` / `AWAITING_CAPTURE` / `STOPPED` | `root_cause` (+ label), `fix_proposal`, `repro` (`REPRODUCED` / `NOT_REPRODUCED` / `BLOCKED` / `not_run`), `evidence_files[]`, `capture_path`, `findings[]` (claim, label, evidence) |
| repro-driver | `REPRODUCED` / `NOT_REPRODUCED` / `BLOCKED` | `steps_run[]`, `positive_control` (required for `NOT_REPRODUCED`), `evidence[]`, `console[]`, `network[]` |
| searcher | `FOUND` / `NOT_FOUND` / `BLOCKED` | `hits[]` (`path:line`, one-line snippet), `searches[]` (pattern, scope), `positive_control` (required for `NOT_FOUND`) |
| web-reader | `GATHERED` / `NOT_FOUND` / `BLOCKED` | `sources[]` (url, version or date, read_at, quote, claim supported), `unreachable[]` |
| designer | `CANVAS_READY` / `NEEDS_INPUT` / `BLOCKED` | `canvases[]` (location, viewport, state), `slots[]` (named copy slots), `needs[]` |
| writer | `COPY_READY` / `NEEDS_INPUT` / `BLOCKED` | `copy[]` (slot, text, `alternatives[]`, char_count, language), `needs[]` |

- `STOPPED` = a stop trigger fired (the evidence base is suspect). `BLOCKED` = a tool or access
  problem. They call for different responses.
- No agent emits `NEEDS_CLARIFICATION`: none can ask the owner. The lead turns a teammate's
  `NEEDS_INPUT` into a re-dispatch with context, or into `PARTIAL` plus an Open entry.

## C. Dispatch, iteration, routing

1. **Async waiting.** An `Agent` call returns at once; the report arrives later as a hand-back
   (measured 2026-10-14). A dispatcher must not end its turn while a teammate it dispatched is
   outstanding, and never reads a teammate's transcript file (the harness warns it overflows
   context; a mid-run transcript holds hypotheses, not findings; it bypasses the status block).
2. **Iteration caps.** One counter per teammate, starting at 0, +1 per re-dispatch, never reset
   (including across a resume). Default cap 3 dispatches per teammate per run;
   `/research --max-iter=N` overrides. At the cap the lead records the gap under Open and goes
   `PARTIAL`. Capture rounds are uncapped: each is gated by the owner.
3. **Routing.**

   | Teammate result | Lead's action |
   |---|---|
   | `FOUND` · `GATHERED` · `REPRODUCED` · `DIAGNOSED` · `CANVAS_READY` · `COPY_READY` | merge into findings.md with labels; continue |
   | `NOT_FOUND` / `NOT_REPRODUCED` with a positive control | record under "Not shown / ruled out"; continue |
   | `NOT_FOUND` / `NOT_REPRODUCED` without one | invalid: re-dispatch asking for the control (counts as an iteration) |
   | `NEEDS_INPUT` | re-dispatch with the missing context, or Open + `PARTIAL` |
   | `BLOCKED` | Open, naming who can unblock; continue other branches |
   | `STOPPED` | don't re-send the brief; re-check provenance; the lead's own third hypothesis stops the lead |
   | investigator `AWAITING_CAPTURE` | lead returns `AWAITING_CAPTURE` with `capture_path` |

4. **Resume** after a capture: see A, "Human-run captures".
5. **Shared resources.** searcher and web-reader may run in parallel. At most one repro-driver
   at a time (dev-server ports, the single chrome-devtools profile); the investigator checks
   `.claude/runs/MEASUREMENT-IN-PROGRESS.md` before dispatching it.
6. **Run log.** Every status block is appended to `run-log.md` in the investigation folder as it
   arrives. `findings.md`'s Log section records changes to the findings only.
7. **End of run.** `/research` shows the owner the lead's final status block, Answer and Next.

## D. Tool boundaries and lint

| Agent | Read/Grep/Glob | Write/Edit | Bash | Agent | Other |
|---|:-:|:-:|:-:|:-:|---|
| research-lead | ✅ | ✅ findings.md, run-log.md | read-only git | ✅ team only | — |
| incident-investigator | ✅ | ✅ capture.md, evidence-*.md | read-only | ✅ repro-driver only | Sentry 5 direct reads + gated gateway |
| repro-driver | ✅ | — | `yarn dev`, `ss`, `ps` | — | chrome-devtools |
| searcher | ✅ | — | — | — | — |
| web-reader | — | — | — | — | WebFetch, WebSearch |
| designer | ✅ | decided with its medium | — | — | decided with its medium |
| writer | ✅ | — | — | — | — |

Only the tool list is mechanical. Which agent types may be dispatched, and which paths may be
written, are prose rules.

**harness-check.sh §5b:**

1. Status tokens appear in both `research-workflow.md` and the agent file (`AWAITING_CAPTURE` /
   research-lead, `DIAGNOSED` / investigator, `REPRODUCED` / repro-driver, `FOUND` / searcher,
   `GATHERED` / web-reader, `CANVAS_READY` / designer, `COPY_READY` / writer). An agent still
   carrying the STUB banner prints `SKIP (stub)`.
2. `positive_control` appears in `searcher.md` and `repro-driver.md` (same stub skip).
3. Tool boundaries, from each `tools:` frontmatter line, stubs included: only research-lead and
   incident-investigator have `Agent`, `Write` or `Edit`; searcher, writer and web-reader have
   no `Bash`.
4. Model pins match the roster in Constraints.
5. `ai-workflow.md` contains the pointer to `research-workflow.md`.

## Deliverables

1. `rules/research-workflow.md` — sections A–D as the rule text.
2. `commands/research.md` — thin wrapper: run research-lead.md § "Framing" inline, then dispatch
   research-lead; handles resume after a capture.
3. `agents/research-lead.md` — frontmatter gains `Write, Edit, Bash, Agent`; section headings
   "Framing" and "Running the team" (bodies come with #1); STUB banner stays.
4. `rules/ai-workflow.md` — one-line pointer to `research-workflow.md`.
5. `.claude/CLAUDE.md` — index entry.
6. `scripts/harness-check.sh` — §5b.

## Verification

- `bash .claude/scripts/harness-check.sh` exits 0, with §5b printing `SKIP (stub)` for the
  status-token checks and PASS for tool boundaries, model pins and the pointer.
- Negative check: §5b reads agents from `${HC_AGENTS_DIR:-$ROOT/.claude/agents}`. Copy the agents
  folder to the scratchpad, give the copy's `searcher.md` a `Bash` tool and change one model pin,
  run with `HC_AGENTS_DIR` pointing at the copy, and confirm both checks fail. The real files are
  never touched. (A lint that has never failed has not been shown to work —
  research-discipline.md §3.)
- `/research` cannot be exercised end to end until the procedures exist (#1).

## Open

- **Late reports.** What happens to a teammate report that arrives after its dispatcher ended its
  turn: resumes the dispatcher, goes to the main session, or is lost. Test: a lead dispatches a
  ~60 s child, then ends its turn. If it resumes the lead, rule C1 may relax to "don't *report*
  until all teammates are back". Deferred 2026-10-14.
- **Designer medium**, and with it the designer's tools and canvas output.

## References

- `.claude/rules/ai-workflow.md`, `research-discipline.md`, `multi-session.md`
- `.claude/templates/findings-template.md`, `kibana-query-sheet.md`
- `.claude/agents/*.md` (seven research stubs)
- Nested-dispatch probe, 2026-10-14 (this session): async hand-back to the dispatcher
