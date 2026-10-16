# Delegating lookups to the Haiku agents

Set 2026-10-16: usage limits fill faster, so the main session (Opus) hands
**lookups** to the two Haiku 5.5 research agents instead of doing them itself. They locate and
quote; the main session still interprets. Their procedures are unchanged from `/research`
([research-workflow.md](./research-workflow.md)), and `research-discipline.md` still applies.

## When to dispatch

| Task | Agent | Do it yourself instead when… |
|---|---|---|
| Repo sweep: where is X defined / used / configured, every call site, every name variant | `searcher` | you already know the file, or it's one `Grep` you'd read the result of anyway |
| Web / docs lookup: what do the docs say, is X supported in version Y, what does the changelog say | `web-reader` | never for anything you will cite; a quick sanity check you won't quote can stay inline |

- Independent lookups go out **in parallel** (one message, several `Agent` calls).
- Write a real brief: the target or claim, the scope, known names, and which claim is
  load-bearing (`web-reader` then looks for two sources). See research-discipline.md §8.
- **`web-reader` can't read files:** paste `project.md` § Stack into its brief, or every source
  comes back `version_match: unknown`.
- Don't dispatch a lookup whose answer you need before you can write the next brief; do
  that one inline.
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

## Gotchas

- **Agent files load at session start.** An edit to `.claude/agents/*.md` (including its
  hooks) doesn't reach a running session's dispatches. Test agent or hook changes with a fresh
  `claude -p`, as harness-check's notes describe. Measured 2026-10-16.
- The hook needs network and `node_modules/js-yaml` (a transitive dependency, 3.14.1 on
  2026-10-16). harness-check §5c covers both offline except the network.
