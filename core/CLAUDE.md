# CLAUDE.md — harness entry point

This file is the entry point of the Claude Code harness installed under `.claude/`. It indexes
the rules, agents and hooks. **Project facts are not here:** read
[`project.md`](./project.md) first. It holds the stack, commands, dev server, branch flow,
external systems and owner. Anything this harness says about "the project's build command",
"the dev server" or "the owner" means what `project.md` says.

If `project.md` is missing or still has `TODO` values, say so instead of guessing them, and
skip the steps that need them.

## Contents

- [Rules](#rules)
- [Agents and commands](#agents-and-commands)
- [Hooks](#hooks)
- [Maintaining the harness](#maintaining-the-harness)

## Rules

Detailed rules live under [rules/](./rules/). They are **not** auto-loaded: read the relevant file
before the matching action.

- [working-style.md](./rules/working-style.md) — diffs, reviews, decision capture, where harness files live
- [code-conventions.md](./rules/code-conventions.md) — read before writing a component or helper: icons as components, JSDoc on exported helpers, generic helpers in generic files
- [autonomy.md](./rules/autonomy.md) — what's OK without asking, what to ask the owner first (pushes, branches, any write to a shared system)
- [git.md](./rules/git.md) — commit messages, branch names, pushing, diverged branches; the promotion flow is in `project.md`
- [delegation.md](./rules/delegation.md) — **the main session hands lookups to Haiku**: broad repo sweeps → `searcher`, web/docs lookups → `web-reader`; cite only hook-verified `sources[]`
- [research-discipline.md](./rules/research-discipline.md) — provenance label on every claim, pin every source's version, positive control before any null, stop triggers, assumptions ledger
- [research-workflow.md](./rules/research-workflow.md) — the research team's contract (`/research`)
- [ai-workflow.md](./rules/ai-workflow.md) — the feature workflow's contract: Planner → Coder → Tester → Reviewer, `/feature-flow`
- [bug-fixes.md](./rules/bug-fixes.md) — reproduce locally before fixing
- [verification.md](./rules/verification.md) — real-browser verification, fixtures that can break, device emulation, measurement pitfalls; type-check ≠ verified
- [multi-session.md](./rules/multi-session.md) — two or more Claude sessions on one machine: shared resources, the measurement lock, owning your processes
- [code-review.md](./rules/code-review.md) — working with an AI second reviewer (CodeRabbit) and `superpowers:receiving-code-review`
- [plugin-skills.md](./rules/plugin-skills.md) — when to use which plugin skill
- [agent-skills.md](./rules/agent-skills.md) — finding and recommending skills from the agent-skills ecosystem

When adding a convention, prefer extending an existing rule file. Add a new file only when the
topic doesn't fit, then index it here.

## Agents and commands

| Team | Agents (`agents/`) | Entry points (`commands/`) |
|---|---|---|
| Feature workflow | planner, coder, tester, reviewer | `/planner`, `/coder`, `/tester`, `/reviewer`, `/feature-flow` |
| Research team | research-lead, searcher, web-reader, incident-investigator, repro-driver, designer, writer | `/research` |

`searcher` and `web-reader` may also be dispatched directly by the main session
([delegation.md](./rules/delegation.md)). No agent commits, pushes or creates branches.

**Prerequisites** (plugins the agents invoke): `superpowers` (brainstorming, writing-plans,
receiving-code-review), `chrome-devtools-mcp` (Tester, repro-driver, designer). Optional:
`atlassian` (Planner reads Jira/Confluence; research-lead writes Confluence drafts), a Sentry
MCP (incident-investigator). An agent whose system is marked `no` in `project.md` skips it.

## Hooks

Registered in [settings.json](./settings.json) unless noted. A denial is **policy, not an error**:
don't retry, rephrase or work around it.

| Hook | Event | What it does |
|---|---|---|
| `git-guard.sh` | PreToolUse(Bash) | denies commits on and pushes from/to shared branches (`project.md` `shared_branches`), plain `--force`, `--no-verify` |
| `sentry-read-gate.sh` | PreToolUse(Sentry `execute_sentry_tool`) | allows only read-only Sentry catalog operations; fails closed |
| `session-context.sh` | SessionStart | prints branch, dirty files, newest spec+plan, test-runner presence |
| `confluence-draft-gate.sh` | PreToolUse, **in `research-lead.md`'s frontmatter** | research-lead may write Confluence drafts only |
| `quote-verify-gate.sh` | Stop, **in `web-reader.md`'s frontmatter** | every quote web-reader cites must be a verbatim substring of its page |

Hooks read project facts through `hooks/lib/project-config.js` and fall back to defaults when
`project.md` is absent. They need `node` ≥18 on `PATH`. The quote gate parses YAML with the
vendored `vendor/js-yaml.min.js` (v4.1.0, MIT).

**Agent files load at session start.** An edit to `agents/*.md`, its frontmatter hooks included,
reaches only sessions started afterwards. Test agent and hook changes in a fresh `claude -p`.

## Maintaining the harness

- `bash .claude/scripts/harness-check.sh` — self-check: hook integrity and deny/allow matrices,
  contract linters, tool boundaries, quote-verification matrices. Run after any change under
  `.claude/`. Exit 0 = all green.
- `bash .claude/scripts/verify-quote.sh <url> "<quote>"` — is a quote a verbatim substring of
  the page? `MATCH` / `NO MATCH` / `UNCHECKABLE`.
- `python3 .claude/scripts/prune-session.py` — truncate a transcript too large to `--resume`.
- Templates: [spec-template.md](./templates/spec-template.md) (Planner),
  [findings-template.md](./templates/findings-template.md) (research runs, copied to
  `.claude/investigations/YYYY-MM-DD-<slug>/findings.md`).
