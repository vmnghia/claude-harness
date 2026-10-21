# Delegating lookups and commands to the Haiku agents

Set 2026-10-16: usage limits fill faster, so the main session (Opus) hands
**lookups** to the two Haiku 5.5 research agents instead of doing them itself. They locate and
quote; the main session still interprets. Extended 2026-10-19 with **`runner`**, also Haiku 5.5:
it runs commands the main session writes out verbatim, so long output (lint, builds, logs) never
enters the main context. The two research agents' procedures are unchanged from `/research`
([research-workflow.md](./research-workflow.md)), and `research-discipline.md` still applies.

## When to dispatch

| Task | Agent | Do it yourself instead when… |
|---|---|---|
| Repo sweep: where is X defined / used / configured, every call site, every name variant | `searcher` | you already know the file, or it's one `Grep` you'd read the result of anyway |
| Web / docs lookup: what do the docs say, is X supported in version Y, what does the changelog say | `web-reader` | never for anything you will cite; a quick sanity check you won't quote can stay inline |
| Commands whose output is long or repetitive: lint, builds, log or process sweeps, measurement loops, multi-step git (a merge plus its checks) | `runner` | it's a one-liner whose raw output you need for your next decision (a `git status`, one `git show`): the brief and the summary would cost as much as the output |

- Independent lookups go out **in parallel** (one message, several `Agent` calls).
- Write a real brief: the target or claim, the scope, known names, and which claim is
  load-bearing (`web-reader` then looks for two sources). See research-discipline.md §8.
- **`web-reader` can't read files:** paste `project.md` § Stack into its brief, or every source
  comes back `version_match: unknown`.
- Don't dispatch a lookup whose answer you need before you can write the next brief; do
  that one inline.
- **Judgement goes in the brief, or the job isn't the runner's.** The runner can't decide that
  a server is "ready", that a run is "contaminated", or that load is "too high". Write those as
  `until … sleep 15` loops with a deadline inside the command, and as `checks[]`. A failed check
  is a `fail` verdict inside a `DONE` status: read every `checks[].verdict`, because `DONE`
  doesn't mean the checks passed. Then re-dispatch. A job that needs on-the-fly judgement goes to a Sonnet
  general-purpose agent instead. Never ask the runner to "figure out" anything.
- Not delegated: `designer`, `writer`, `incident-investigator`, `repro-driver`. They write
  files, drive browsers or reach Sentry/LogRocket, and stay behind `/research`.

## Reading what comes back (you are the router)

Without a lead, the main session applies the lead's routing table itself:

- `searcher` `NOT_FOUND` **without** a `positive_control` is invalid: re-dispatch asking for it.
- `web-reader` `sources[]` are **hook-verified**: `quote-verify-gate.sh` re-fetched each URL raw
  and matched the quote verbatim before the agent could finish. Cite only from `sources[]`.
- `unverified[]` is **never citable**. To use one, run
  `bash .claude/scripts/verify-quote.sh <url> "<quote>"` yourself (prints `MATCH` /
  `NO MATCH` / `UNCHECKABLE: …`), or read the page.
- **The escape hatch.** After 3 blocks the hook lets the agent stop anyway. Before citing a
  `web-reader` result, check: `grep -c '<agentId> ESCAPE' .claude/runs/quote-verify.log`.
  Non-zero means treat its whole `sources[]` as `unverified[]`.
- Labels: `searcher` hits are `read (working tree)`; pin a commit yourself if the claim needs it.

## Runner briefs

The brief shape is in [`agents/runner.md`](../agents/runner.md):
- `repo_root`: required, absolute
- `run_dir`: under `<repo_root>/.claude/runs/runner/YYYY-MM-DD-<slug>/`
- `steps[]`: `{n, cmd, allowed_exit, timeout_s ≤ 600, report}`
- `checks[]`, and an `approval` quote for any push

Split anything longer than 10 minutes into steps.

- **Lint is report-only** (2026-10-19): never `--fix`, never a command `project.md` § Commands
  marks `Writes files: yes`. The runner refuses both. Recipe (also in `project.md` § Commands):
  ```
  1. <lint> -f json -o <run_dir>/eslint.json              allowed_exit: [0, 1]   timeout_s: 600
  2. node .claude/scripts/eslint-summary.js <run_dir>/eslint.json $(git diff --name-only <base>) $(git ls-files --others --exclude-standard)
  ```
  `eslint-summary.js` is an optional helper for ESLint projects. Step 2 prints the following, and
  the runner copies the lines verbatim:
  - `TOTAL …`
  - the top `RULE` lines
  - `ERROR_FILE` lines
  - `CHANGED` / `CHANGED_ERROR` lines for the changed paths
  - `CHANGED_NOT_LINTED` for paths the linter never saw
  `CHANGED_ERROR` lines are the ones to act on. The rest is pre-existing debt. The untracked
  list matters: agents never commit, so a file the Coder created is untracked, and `git diff`
  alone would leave its errors in the "debt" lines.
- **Reading the result:**
  - Numbers are only trustworthy as copies of printed lines. A count with no quoted line is a
    tally the runner made up.
  - On `FAILED`, read its `key_lines` (the wrapper's last 20 lines), and open the step log
    yourself only if they don't explain it.
  - `exit: denied` is a hook decision: policy, not a retry.
  - **A check on a big log** (over 2000 lines, such as a build) comes back `unchecked`, because
    Grep may be absent at runtime. Write that check as a step of its own instead:
    `grep -m1 -E '<pattern>' <run_dir>/step-<n>.log`, with `allowed_exit: [0, 1]` and
    `report: '.'`. Exit 1 means no match.

## Gotchas

- **Agent files load at session start**, mostly. An edit to `.claude/agents/*.md` (including
  its hooks) didn't reach a running session's dispatches (measured 2026-10-16). But a **newly
  created** agent file was dispatchable mid-session, seconds after it was written (2026-10-19).
  To test an edit to an existing agent or hook, use a fresh `claude -p`, as harness-check's notes
  describe.
- **Every `rules/**/*.md` loads into every session and every subagent** (measured 2026-10-19), so
  a rule's size is paid per session and per dispatch.
  - In a repo whose rules and CLAUDE.md total ~45k tokens, a runner dispatch cost ~87k tokens
    before any command ran.
  - Batch steps into one brief rather than dispatching one per command.
- **Tools listed in an agent's frontmatter can be absent at runtime**: Grep and Glob were, on
  2026-10-16 and 2026-10-19. Never build a procedure that only works with them.
- **`$CLAUDE_PROJECT_DIR` is unset inside Bash tool commands**: it is set for hooks only. Pass
  `repo_root` in briefs.
- The hook needs network and `node_modules/js-yaml` (a transitive dependency, 3.14.1 on
  2026-10-16). harness-check §5c covers both offline except the network.
