# Research workflow — shared contract for the research team

Single source of truth for how the research team runs: who dispatches whom, what each agent
returns, and how a run moves through human-run captures. Counterpart of
[ai-workflow.md](./ai-workflow.md), which covers the feature flow; this file reuses its
status-block frame and context capsule. Design and decisions: `docs/2026-10-14-research-workflow-design.md`
in the harness repo.

Every agent here also follows [research-discipline.md](./research-discipline.md) and writes
into an investigation folder shaped by
[templates/findings-template.md](../templates/findings-template.md).

Agents: `research-lead`, `incident-investigator`, `repro-driver`, `searcher`, `web-reader`,
`designer`, `writer`. Entry point: `/research`.

**Standalone use (2026-10-16).** `searcher` and `web-reader` may also be dispatched
directly by the main session for a single lookup, outside any run: no investigation folder
(`findings: null`), no cap, and the main session applies this file's routing table itself.
The when-to and the citation rules are in [delegation.md](./delegation.md).

## Flow and roles

```
/research <question | FRONT-XXXX> [--max-iter=N] | --resume <investigation-folder>
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

**Single writer.** Only research-lead writes `findings.md` and `run-log.md`. One exception: the
main session writes `lead.txt` (the lead's agent id, used to resume it). The investigator
writes `capture.md` and `evidence-*.md`; every other agent returns its results in its status
block only. (The designer's canvas files are decided with its medium.) Framing creates
`findings.md` in the main session; after that the lead changes it with `Edit` only, because a
subagent's whole-file `Write` to it is refused (measured 2026-10-15).

**Design medium.** A design task's medium is chosen at framing and approved with the owner's "go"
(a Decisions row): `canvas` (default: HTML files in `design/`) or `artifact` (a whole landing
page or dashboard someone will click through). A designer that finds the medium wrong mid-run
returns `NEEDS_INPUT` (`artifact medium: <why>`) before drawing. The lead may **deny** on its
own; to accept, it returns `AWAITING_HUMAN` (`approve artifact medium for <X>: <reason>`).
Only the owner approves publishing; no agent authorises another's outward action.

**Confluence write-up (2026-10-15).** Only when the framing has a Decisions row naming
the target (`Confluence: new draft under <parent URL>` or `draft update of <page URL>`).
- At write-up, research-lead writes the page as a Confluence **draft**. Its frontmatter hook
  `confluence-draft-gate.sh` denies any create or update without `draft: true`. It runs only
  while the lead runs; measured with a probe agent on 2026-10-15, where it fired inside the
  subagent and not in the parent session.
- The page follows the target folder's convention: a template named in `project.md` § Tickets
  and docs, else two sibling pages the lead matches (research-lead.md step 8.3).
- **Labels need the owner.** `updateConfluenceContent` has no labels field, and adding labels is an
  `executeWrite` operation that no agent has. The lead lists the labels to add in Open.
- `/research` shows the owner the draft link, and **they publish**. No other agent has a Confluence
  write tool, and none has `executeWrite`/`executeDestructive`.
- This is the one exception to draft-in-chat (`autonomy.md`).

**Waiting for the owner (`AWAITING_HUMAN`).** A subagent can't wait for a person. When a run needs
something only the owner can do, the agent that needs it returns `AWAITING_HUMAN` with an `action`:
a human-run capture ("paste results into `<folder>/results.txt`", with `capture_path`), or a block
they can clear ("start the dev server", "close the other window holding the chrome-devtools
profile", "wait until <session>'s measurement lock is gone"). A block nobody can clear in place
(an irreversible action on prod, prod-only data) stays `BLOCKED` and goes to Open; it doesn't
pause the run.

- **Propagation.** repro-driver → incident-investigator → research-lead → `/research`. Each agent
  first finishes every branch that doesn't depend on the action, then returns `AWAITING_HUMAN`
  with the `action` (and `capture_path`) it received.
- **Resume the same agent.** Every dispatcher records its teammates' agent ids (the lead in
  `run-log.md`, the investigator in its payload's `repro_agent_id`). After the owner does the action
  and runs `/research --resume <folder>`, each level sends "done: <action>" to **the same agent**
  that paused, via SendMessage. A resumed agent re-checks its preconditions before continuing:
  state from before the pause (a browser tab, a server, cookies) is not trusted.
- **When a fresh dispatch replaces a resume.** Only when resuming would be wrong: SendMessage to
  the old agent fails, the task itself changed (e.g. a new repro brief), or the old agent's last
  report was a permanent `BLOCKED`. A fresh dispatch counts toward the cap; a resume does not.
- **The lead itself** is resumed by `/research`, never replaced. If it can't be resumed (the
  session that ran it has ended), that run ends: the owner either abandons it or starts a **new run**
  in a `-2` folder whose framing is seeded from the old run's `findings.md` and `results.txt`. A
  new run is not a resumed lead: its counters start at 0 and its findings cite the old folder as
  a source.

**Infrastructure failures (session limit / HTTP 429, API or network errors).** The harness
reports the cut-off agents as `failed`, with no status block (all six agents of the first run,
2026-10-14). That is not a finding, not `BLOCKED` and not `STOPPED`; nothing about the brief
changed.

- Once the limit resets, the owner runs `/research --resume <folder>`, or says "resume" in the
  session that ran it.
- `/research` resumes the lead. The lead resumes each failed teammate via SendMessage, the
  investigator resumes its own driver, and each one re-checks its preconditions first. The
  first run's investigator caught a staging redeploy this way.
- Resumes after a failure are not dispatches and don't count toward the cap. The lead records
  the gap under "Pause / resume" in `run-log.md`.
- If a send fails, the same rule applies as for `AWAITING_HUMAN`: a fresh, counted dispatch
  for a teammate, a new `-2` run for the lead.

## Status blocks

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
| research-lead | `ANSWERED` / `PARTIAL` / `AWAITING_HUMAN` / `STOPPED` | `findings_path`, `answer` (one line), `next` (build / no-build + summary), `open[]`, `action`, `capture_path`, `dispatches[]` (agent, status, iteration), `confluence_draft` (url, content_id, version; unpublished) |
| incident-investigator | `DIAGNOSED` / `PARTIAL` / `AWAITING_HUMAN` / `STOPPED` | `root_cause` (+ label), `fix_proposal`, `repro` (`REPRODUCED` / `NOT_REPRODUCED` / `BLOCKED` / `not_run`), `repro_agent_id`, `evidence_files[]`, `action`, `capture_path`, `findings[]` (claim, label, evidence), `open[]` (incl. LogRocket session URLs for the owner to open) |
| repro-driver | `REPRODUCED` / `NOT_REPRODUCED` / `AWAITING_HUMAN` / `BLOCKED` | `steps_run[]`, `attempts` (e.g. `2/3`), `positive_control` (required for `NOT_REPRODUCED`), `action`, `block_reason`, `evidence[]`, `console[]`, `network[]` |
| searcher | `FOUND` / `NOT_FOUND` / `BLOCKED` | `hits[]` (`path:line`, one-line snippet), `searches[]` (pattern, scope), `positive_control` (required for `NOT_FOUND`) |
| web-reader | `GATHERED` / `NOT_FOUND` / `BLOCKED` | `sources[]` (url, version or date, read_at, quote, claim supported; each quote hook-verified), `unverified[]` (same + `verdict`; never citable), `unreachable[]` |
| designer | `CANVAS_READY` / `NEEDS_INPUT` / `AWAITING_HUMAN` / `BLOCKED` | `canvases[]` (location, viewport, state, png), `slots[]` (named copy slots), `measured_styles`, `needs[]` (incl. `artifact medium: <why>`), `action` |
| writer | `COPY_READY` / `NEEDS_INPUT` / `BLOCKED` | `copy[]` (slot, text, `alternatives[]`, char_count, language), `needs[]` |

- `STOPPED` = a stop trigger fired (the evidence base is suspect). `BLOCKED` = a tool or access
  problem. They call for different responses.
- No agent emits `NEEDS_CLARIFICATION`: none can ask the owner. The lead turns a teammate's
  `NEEDS_INPUT` into a re-dispatch with context, or into `PARTIAL` plus an Open entry.

## Dispatch, iteration, routing

1. **Async waiting.** An `Agent` call returns at once; the report arrives later as a hand-back
   (measured 2026-10-14). A dispatcher must not end its turn while a teammate it dispatched is
   outstanding, and never reads a teammate's transcript file (the harness warns it overflows
   context; a mid-run transcript holds hypotheses, not findings; it bypasses the status block).
2. **Iteration caps.** One counter per teammate (2026-10-15), starting at 0, +1 per
   dispatch, never reset (including across a resume). Parallel briefs to the same teammate each
   count: two searchers fanned out are dispatches 1 and 2 of the searcher's cap. Plan fan-out
   against `--max-iter`. Default cap 3 dispatches per teammate per run;
   `/research --max-iter=N` overrides. At the cap the lead records the gap under Open and goes
   `PARTIAL`. `AWAITING_HUMAN` rounds are uncapped (each is gated by the owner), and a resume is
   not a dispatch.
3. **Routing.**

   | Teammate result | Lead's action |
   |---|---|
   | `FOUND` · `GATHERED` · `REPRODUCED` · `DIAGNOSED` · `CANVAS_READY` · `COPY_READY` | merge into findings.md with labels; continue |
   | `NOT_FOUND` / `NOT_REPRODUCED` with a positive control | record under "Not shown / ruled out"; continue |
   | `NOT_FOUND` / `NOT_REPRODUCED` without one | invalid: re-dispatch asking for the control (counts as an iteration) |
   | `NEEDS_INPUT` | re-dispatch with the missing context, or Open + `PARTIAL` |
   | `BLOCKED` (permanent) | Open, naming who can unblock; continue other branches |
   | `STOPPED` | don't re-send the brief; re-check provenance; the lead's own third hypothesis stops the lead |
   | `AWAITING_HUMAN` | finish independent branches, then the lead returns `AWAITING_HUMAN` with the `action` (+ `capture_path`) |
   | web-reader `unverified[]` entries, or an `ESCAPE` line for its agent id in `.claude/runs/quote-verify.log` | not a status and not a re-dispatch: those quotes are uncitable. Spot-check the load-bearing ones (step 5) or list them under Open |

   The web-reader's Stop hook (`quote-verify-gate.sh`, its own frontmatter) re-fetches every
   `sources[]` URL raw and blocks the agent until each quote is a verbatim substring or has been
   moved to `unverified[]`. It always converges, so a hook block never surfaces as a status.

4. **Resume**: see "Flow and roles" → "Waiting for the owner" and "Infrastructure failures".
5. **Shared resources.** searcher and web-reader may run in parallel. designer and
   repro-driver both use the single chrome-devtools profile: never at the same time. At most one repro-driver
   at a time (dev-server ports, the single chrome-devtools profile); the investigator checks
   `.claude/runs/MEASUREMENT-IN-PROGRESS.md` before dispatching it.
6. **Run log.** Every status block is appended to `run-log.md` in the investigation folder as it
   arrives. `findings.md`'s Log section records changes to the findings only.
7. **End of run.** `/research` shows the owner the lead's final status block, Answer and Next.

## Tool boundaries and lint

| Agent | Read/Grep/Glob | Write/Edit | Bash | Agent | Other |
|---|:-:|:-:|:-:|:-:|---|
| research-lead | Read only (no Grep/Glob: search = `git grep` at a pinned SHA, else `searcher`) | ✅ findings.md (`Edit` only), run-log.md | read-only git | ✅ team only | SendMessage (resume a paused or failed teammate), WebFetch (spot-check cited URLs), Confluence reads + **draft-only** create/update (frontmatter hook `confluence-draft-gate.sh`) |
| incident-investigator | ✅ | ✅ capture.md, evidence-*.md | read-only | ✅ repro-driver only | error-tracker reads (Sentry: 5 direct + gated gateway), session-replay reads, issue-tracker reads, SendMessage (resume its driver) |
| repro-driver | ✅ | — | `ss`, `ps` only (never starts a server) | — | chrome-devtools |
| searcher | ✅ | — | — | — | — |
| web-reader | — | — | — | — | WebFetch, WebSearch; Stop hook `quote-verify-gate.sh` in its frontmatter |
| designer | ✅ | ✅ `design/` only | — | — | chrome-devtools subset; `Artifact` only with the owner's approval |
| writer | ✅ | — | — | — | — |

Model pins (2026-10-14; the lint compares each agent's `model:` line to this table):

| Agent | Model |
|---|---|
| research-lead, incident-investigator, designer, writer | `claude-opus-5-5` |
| searcher, web-reader | `claude-haiku-5-5` (locate / quote only; the lead interprets) |
| repro-driver | `claude-sonnet-5-5` |

Only the tool list is mechanical. Which agent types may be dispatched, and which paths may be
written, are prose rules.

**harness-check.sh §5b:**

1. Status tokens appear in both `research-workflow.md` and the agent file (`AWAITING_HUMAN` /
   research-lead, `DIAGNOSED` / investigator, `REPRODUCED` / repro-driver, `FOUND` / searcher,
   `GATHERED` / web-reader, `CANVAS_READY` / designer, `COPY_READY` / writer). An agent still
   carrying the STUB banner prints `SKIP (stub)`.
2. `positive_control` appears in `searcher.md` and `repro-driver.md` (same stub skip).
3. Tool boundaries, from each `tools:` frontmatter line, stubs included: only research-lead and
   incident-investigator have `Agent`; only they and designer have `Write` or `Edit`; searcher,
   writer, web-reader and designer have no `Bash`; research-lead has `WebFetch` and no
   `Grep`/`Glob` (it searches via `searcher` or pinned `git grep`). A `*` wildcard
   in any tool list fails. No agent has Atlassian `executeWrite`/`executeDestructive`; only
   research-lead has the Confluence create/update tools, and then its frontmatter must register
   `confluence-draft-gate.sh` (whose allow/deny matrix is §2d).
4. Model pins match the table above.
5. `ai-workflow.md` contains the pointer to `research-workflow.md`.

**§5c** (2026-10-16): `verify-quote.sh` and `quote-verify-gate.sh` offline matrices (`data:` URLs:
verbatim, markdown table/bold, one-word change, paraphrase, case, `!!js/function`, the 3-block
escape and its log line); web-reader's frontmatter registers the gate; `delegation.md` exists
and is indexed; both agents' descriptions name standalone dispatch.

## Open

- **Late reports** (deferred 2026-10-14): what happens to a teammate report that
  arrives after its dispatcher ended its turn is untested. Until it is, the rule in
  "Dispatch, iteration, routing" item 1 stands as written.
- **research-lead ran without `Grep` and stepped outside its Bash scope** (recorded 2026-10-16).
  **Decided (2026-10-16): option 2.** The lead has no Grep/Glob. It searches only with
  `git grep`/`git ls-files` at a pinned SHA, sends everything else to `searcher` in batched
  briefs, and treats a missing tool as a §6 stop. Linted by harness-check §5b. Why the tool was
  missing at runtime is still unknown; the history follows.
  - In a 2026-10-16 run (its `run-log.md`), the lead
    reported "the Grep tool is not available in this session". It then ran read-only `grep`/`sed`
    via Bash over `node_modules/next`, outside its "read-only git" Bash scope above, and said so
    itself. *(read: the run log)*
  - This isn't a definition gap. `research-lead.md`'s `tools:` line lists `Grep` *(read)*. The
    tool was absent at runtime.
  - In the same run, the searcher reported using Grep *(read: run log)*. On 2026-10-16, a
    main session's own tool list had no `Grep` or `Glob` tool *(measured, in another session)*.
    So availability seems to differ by session or agent. Why is not known *(inferred)*.
  - The rule the lead broke is real either way: a boundary that the toolset can't support, met by
    exceeding the boundary rather than stopping. The options considered were:
    - widen the lead's Bash scope to read-only `grep`/`sed`;
    - have it dispatch `searcher` for any search (**chosen**);
    - treat a missing tool as `BLOCKED` (§6: stop and report).
  - harness-check reads `tools:` lines only, so it can't see runtime availability. It now lints
    that the lead's line has no Grep/Glob.
