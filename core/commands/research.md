---
description: Research team — frame a question with the owner inline, then the research-lead subagent runs the team and writes findings.md
argument-hint: "<question | FRONT-XXXX> [--max-iter=N] [--effort=quick|standard|thorough|exhaustive] [--width=<agent>:<n>,…] [--dry=K] [--max-agents=N] [--no-critique] | --resume <investigation-folder> | --critique <investigation-folder>"
---

Contract: [`.claude/guides/research-workflow.md`](../guides/research-workflow.md). This command
only selects where each phase runs; the procedure lives in
[`.claude/agents/research-lead.md`](../agents/research-lead.md), and the critique's in
`guides/research-workflow.md § Critique`.

## Input

Raw arguments: `$ARGUMENTS`.

- Empty → stop. Reply only: `Usage: /research <question | FRONT-XXXX> [--max-iter=N] [--effort=quick|standard|thorough|exhaustive] [--width=<agent>:<n>,…] [--dry=K] [--max-agents=N] [--no-critique] | --resume <investigation-folder> | --critique <investigation-folder>`. Create nothing.
- Then, if `.claude/agents/research-lead.md` still contains the line starting `> **STUB (`,
  stop. Reply only: `research-lead is still a stub (procedure not written, work item #1); /research can't run yet.` Create nothing.
- `--max-iter=N` → N must be a positive integer; otherwise warn
  `--max-iter ignored, using 3` and use 3. Default 3 (the preset does not drive it:
  `guides/thoroughness.md § Presets`). The resolved value is `knobs.max_iter`.
- Thoroughness flags (`--effort`, `--width`, `--dry`, `--max-agents`) → parse and validate per
  [`guides/thoroughness.md`](../guides/thoroughness.md) § Input. Resolve the knobs once, pass
  `knobs:` and `max_agents` in the lead's capsule (New run step 3), and record them in
  `lead.txt`, so `--resume` reuses them. The lead counts against the top-level `max_agents`
  passed here, not `knobs.max_agents`.
- `--no-critique` → skip the critique (`guides/research-workflow.md § Critique`, "When it
  runs"). `--effort=quick` implies it, and so does a resolved `knobs.width.research-critic` of 0.
  Otherwise the critique runs by default.
- `--resume <folder>` → go to **Resume**.
- `--critique <folder>` → the critique alone on an existing run, whatever its status
  (`guides/research-workflow.md § Critique`, "Standalone"). It takes the thoroughness flags.
  Stop, creating nothing, with `no findings.md` when `<folder>/findings.md` is missing, and with
  `stopped` when its frontmatter `status` is `stopped`. It never edits `findings.md`. Go to
  **Standalone critique**.

## New run

1. **Folder.** `.claude/investigations/YYYY-MM-DD-<slug>/` (date from session context; slug from
   the Jira key or the question, kebab-case, ≤ 5 words). If that folder exists, append `-2`,
   `-3`, … — never write into an existing run's folder.
2. **Frame.** Execute research-lead.md § "Framing" **inline in this session**. It creates
   `findings.md` from the template (frontmatter, question, dispatch plan).
3. **Dispatch.** Agent tool, `subagent_type: "research-lead"`, with: the folder path, the
   framing, `--max-iter`, `knobs:` and `max_agents` (the ceiling minus the critique's reserve:
   `/research` reserves the critique's share of `max_agents`, `guides/thoroughness.md § Agent
   ceiling`), `critique: on | off` (`on` by default; `off` with
   `--no-critique`, `--effort=quick`, or when `knobs.width.research-critic` would be 0; the lead
   defers the Confluence draft when `on`), and a context capsule (`guides/ai-workflow.md`
   template). Then write `lead.txt` in the folder:
   `lead_agent_id: <id from the Agent result>`, followed by the resolved `knobs:` and
   `max_agents:` lines for that agent id (Resume reuses them, never re-resolves). This is the
   main session's only file in the folder; `run-log.md` belongs to the lead.
4. **Wait.** Do not end this turn while the lead is outstanding. Never read its transcript file.
   If the lead's task notification says `failed` on infrastructure (session limit / HTTP 429,
   API or network error), tell the owner what failed. Then say: "once it resets, run
   `/research --resume <folder>` (or say "resume" here)".
5. **Critique.** Unless `critique: off`: run `guides/research-workflow.md § Critique` with this
   session as orchestrator, once the lead has returned `ANSWERED` or `PARTIAL`. On
   `AWAITING_HUMAN` the critique waits for the resume that ends in `ANSWERED` / `PARTIAL`;
   `STOPPED` skips it. Critics by
   `Agent` with `subagent_type: "research-critic"`, all of a round in one message
   (`knobs.width.research-critic`, letters from `A`); the judge by `Agent` with
   `subagent_type: "research-judge"`, one per disputed finding; the lead by `SendMessage` (load
   its schema with ToolSearch `select:SendMessage` first) to the id in `lead.txt`.
   Write `<folder>/critique.md` (the contract's case file; this session writes it, no agent
   does). A failed send → the no-lead path (`rebuttal: unavailable`).
6. **Report.** Show the owner the lead's last status block, the one returned after "critique
   settled" (or, with `rebuttal: unavailable`, its first return), then `findings.md`'s Answer
   and Next, then the critique table and each `disputed` line (`disputed <id>: <question> —
   critic: … — lead: …`) on its own line, how the critique ended (the contract's § Closing
   the run, step 9), and the Confluence draft line. With `rebuttal: unavailable`, add one line
   saying the author never answered. If `confluence_draft` is set, show its URL and say: "a
   draft, not published; review it in Confluence and publish it yourself".
   On `AWAITING_HUMAN`, show the `action` (and the `capture_path`, if set) and say: "do that,
   then run `/research --resume <folder>`".

## Resume

1. Read `lead_agent_id` and the `knobs:` / `max_agents:` lines from `<folder>/lead.txt`; reuse
   them, never re-resolve. If the folder, `lead.txt` or `lead_agent_id` is missing, stop and
   say which one is missing.
2. Read `<folder>/critique.md`'s state block, if the file exists (the contract's "Start,
   restart, resume"). Its outcome selects what follows:
   - **(a) `settled: true`:** never start or restart a critique. Go to step 3 for the lead's
     message, then **New run** step 4 (Wait) and step 6 (Report).
   - **(b) `settled: false`:** no message to the lead yet. The critique restarts its current
     round with fresh critics (**New run** step 5, from the state block); the lead is messaged
     only when that round reaches the rebuttal, or at "critique settled".
   - **(c) no `critique.md`:** go to step 3, then **New run** step 4. When the lead returns
     `ANSWERED` / `PARTIAL` after the resume, **New run** step 5 runs for the first time
     (`critique: on`).
   So the lead gets step 3's message in (a) and (c), and in (b) the critique's own messages.
3. SendMessage to that id. (SendMessage is a deferred tool: load its schema with ToolSearch
   `select:SendMessage` first.) Pick the message by how the lead stopped:
   - Last status block `AWAITING_HUMAN`: "done: <the action from that block>; continue."
   - Failed on infrastructure, with no status block (guides/research-workflow.md, "Infrastructure
     failures"): "You and your teammates were cut off by <error> at <time>, not by anything in
     the brief. Resume each failed teammate via SendMessage (not a dispatch), have the
     investigator resume its own driver, re-check preconditions, and continue."
   A bare "resume" from the owner in the session that ran the lead means this step for that run's
   folder.
4. If the send fails (the session that ran the lead has ended), **stop** and tell the owner that the
   lead can't be resumed from this session. Do **not** start a fresh lead for an existing run.
   Offer the owner the two ways forward: abandon the run, or start a **new run** in a `-2` folder
   whose framing is seeded from the old run's `findings.md` and `results.txt`. In (b) a failed
   send is the critique's no-lead path (`rebuttal: unavailable`), not a stop.

## Standalone critique

`--critique <folder>` (`guides/research-workflow.md § Critique`, "Standalone"): resolve the
knobs as for a new run, `dispatched` starts at 0, and run the critique with this session as
orchestrator and the owner as the author (`rebuttal: unavailable`, no lead). Dispatch as in
**New run** step 5. Write `<folder>/critique.md` (`critique-2.md` on collision); never edit
`findings.md`. Report the critique table and each `disputed` line.
