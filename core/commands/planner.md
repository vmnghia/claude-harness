---
description: Plan a requirement or FRONT-XXXX ticket into a spec+plan pair — interactive, runs in this session
argument-hint: <requirement text | FRONT-XXXX>
---

Read `.claude/agents/planner.md` and execute that procedure **inline in
this session** — do NOT dispatch a subagent. This is the interactive entry
point: the agent file's "interactive mode" applies (AskUserQuestion
available, session memory in context). Pass `$ARGUMENTS` verbatim as the
input. End with the planner status block.

To plan in the background instead (autonomous mode), dispatch the `planner`
subagent via the Agent tool with a context capsule — see
`.claude/rules/ai-workflow.md`.
