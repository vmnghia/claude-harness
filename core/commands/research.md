---
description: Research team — frame a question with the owner inline, then the research-lead subagent runs the team and writes findings.md
argument-hint: <question | FRONT-XXXX> [--max-iter=N] | --resume <investigation-folder>
---

Contract: [`.claude/guides/research-workflow.md`](../guides/research-workflow.md). This command
only selects where each phase runs; the procedure lives in
[`.claude/agents/research-lead.md`](../agents/research-lead.md).

## Input

Raw arguments: `$ARGUMENTS`.

- Empty → stop. Reply only: `Usage: /research <question | FRONT-XXXX> [--max-iter=N] | --resume <investigation-folder>`. Create nothing.
- Then, if `.claude/agents/research-lead.md` still contains the line starting `> **STUB (`,
  stop. Reply only: `research-lead is still a stub (procedure not written, work item #1); /research can't run yet.` Create nothing.
- `--max-iter=N` → N must be a positive integer; otherwise warn `--max-iter ignored, using 3` and use 3. Default 3.
- `--resume <folder>` → go to **Resume**.

## New run

1. **Folder.** `.claude/investigations/YYYY-MM-DD-<slug>/` (date from session context; slug from
   the Jira key or the question, kebab-case, ≤ 5 words). If that folder exists, append `-2`,
   `-3`, … — never write into an existing run's folder.
2. **Frame.** Execute research-lead.md § "Framing" **inline in this session**. It creates
   `findings.md` from the template (frontmatter, question, dispatch plan).
3. **Dispatch.** Agent tool, `subagent_type: "research-lead"`, with: the folder path, the
   framing, `--max-iter`, and a context capsule (`guides/ai-workflow.md` template). Then write
   `lead.txt` in the folder: `lead_agent_id: <id from the Agent result>`. This is the main
   session's only file in the folder; `run-log.md` belongs to the lead.
4. **Wait.** Do not end this turn while the lead is outstanding. Never read its transcript file.
   If the lead's task notification says `failed` on infrastructure (session limit / HTTP 429,
   API or network error), tell the owner what failed. Then say: "once it resets, run
   `/research --resume <folder>` (or say "resume" here)".
5. **Report.** Show the owner the lead's final status block, then `findings.md`'s Answer and Next.
   If `confluence_draft` is set, show its URL and say: "a draft, not published; review it in
   Confluence and publish it yourself".
   On `AWAITING_HUMAN`, show the `action` (and the `capture_path`, if set) and say: "do that,
   then run `/research --resume <folder>`".

## Resume

1. Read `lead_agent_id` from `<folder>/lead.txt`. If the folder, `lead.txt` or the key is
   missing, stop and say which one is missing.
2. SendMessage to that id. (SendMessage is a deferred tool: load its schema with ToolSearch
   `select:SendMessage` first.) Pick the message by how the lead stopped:
   - Last status block `AWAITING_HUMAN`: "done: <the action from that block>; continue."
   - Failed on infrastructure, with no status block (guides/research-workflow.md, "Infrastructure
     failures"): "You and your teammates were cut off by <error> at <time>, not by anything in
     the brief. Resume each failed teammate via SendMessage (not a dispatch), have the
     investigator resume its own driver, re-check preconditions, and continue."
   A bare "resume" from the owner in the session that ran the lead means this step for that run's
   folder.
3. If the send fails (the session that ran the lead has ended), **stop** and tell the owner that the
   lead can't be resumed from this session. Do **not** start a fresh lead for an existing run.
   Offer the owner the two ways forward: abandon the run, or start a **new run** in a `-2` folder
   whose framing is seeded from the old run's `findings.md` and `results.txt`.
4. Otherwise continue from **New run** step 4.
