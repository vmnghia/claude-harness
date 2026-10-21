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
- [Guides](#guides)
- [Agents and commands](#agents-and-commands)
- [Hooks](#hooks)
- [Maintaining the harness](#maintaining-the-harness)

## Rules

Claude Code loads every `rules/**/*.md` at session start, recursively, into the main session **and
every subagent** (measured 2026-10-19). That's paid per session and per dispatch, so every rule
declares one of three **loading classes**. `harness-check` §5e fails an unmarked rule.

1. **Always loaded**, frontmatter `load: always`: safety and conduct rules a session might need
   without knowing it. When in doubt, a rule goes here.
2. **Loaded by the task**: lives in [guides/](./guides), which nothing auto-loads. Its consumers
   (commands, agents, skills) Read it explicitly. See [Guides](#guides).
3. **Loaded when code is touched**, frontmatter `paths:` (a list of globs): the platform loads the
   rule once a matching file is read or edited, in that session or subagent (measured 2026-10-21).

**Project-owned rules go in `rules/project/`, and project guides in `guides/project/`.** The
installer writes neither. Project guides are listed in `rules/project/guides-index.md`, which is
class 1, so every agent sees which ones its role reads.

- [working-style.md](./rules/working-style.md) — (1) diffs, reviews, decision capture, where harness files live
- [autonomy.md](./rules/autonomy.md) — (1) what's OK without asking, what to ask the owner first (pushes, branches, any write to a shared system)
- [git.md](./rules/git.md) — (1) commit messages, branch names, pushing, diverged branches; the promotion flow is in `project.md`
- [delegation.md](./rules/delegation.md) — (1) **the main session hands lookups and commands to Haiku**: broad repo sweeps → `searcher`, web/docs lookups → `web-reader`, long or repetitive commands (lint, builds, log sweeps, multi-step git) → `runner`, which runs only verbatim commands and lints report-only; cite only hook-verified `sources[]`
- [research-discipline.md](./rules/research-discipline.md) — (1) provenance label on every claim, pin every source's version, positive control before any null, stop triggers, assumptions ledger
- [multi-session.md](./rules/multi-session.md) — (1) two or more Claude sessions on one machine: shared resources, the measurement lock, owning your processes
- [bug-fixes.md](./rules/bug-fixes.md) — (1) reproduce locally before fixing
- [plugin-skills.md](./rules/plugin-skills.md) — (1) when to use which plugin skill
- [verification.md](./rules/verification.md) — (3, code files) **type-check ≠ verified: verify in a real browser** before claiming done; fixtures that can break, device emulation, measurement pitfalls. Read it before verifying anything, even when no source file is open.
- [code-conventions.md](./rules/code-conventions.md) — (3, code files) icons as components, JSDoc on exported helpers, generic helpers in generic files

When adding a convention, prefer extending an existing rule file. Add a new file only when the
topic doesn't fit, then index it here **with its class**.

## Guides

Loaded by the task that needs them, never auto-loaded. Each one names its consumers, which Read it before starting. The main session
reads it when the trigger applies.

| Guide | Consumers | Main session reads it when… |
|---|---|---|
| [research-workflow.md](./guides/research-workflow.md) | `/research`, research-lead, incident-investigator, repro-driver, searcher, web-reader, designer, writer | running or resuming `/research`, or dispatching a research agent directly |
| [ai-workflow.md](./guides/ai-workflow.md) | `/feature-flow`, `/planner`, planner, coder, tester, reviewer | running the feature workflow or dispatching one of its agents |
| [code-review.md](./guides/code-review.md) | reviewer | triaging review comments (CodeRabbit or human) |
| [agent-skills.md](./guides/agent-skills.md) | — | answering "can you do X / is there a skill for X", or recommending skills |

## Agents and commands

| Team | Agents (`agents/`) | Entry points (`commands/`) |
|---|---|---|
| Feature workflow | planner, coder, tester, reviewer | `/planner`, `/coder`, `/tester`, `/reviewer`, `/feature-flow` |
| Research team | research-lead, searcher, web-reader, incident-investigator, repro-driver, designer, writer | `/research` |
| Delegation | runner | dispatched directly ([delegation.md](./rules/delegation.md)) |

`searcher`, `web-reader` and `runner` may be dispatched directly by the main session
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
