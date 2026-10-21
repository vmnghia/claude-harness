# claude-code-harness

A drop-in harness for [Claude Code](https://claude.com/claude-code): two agent teams, the rules
they work by, and hooks that enforce the parts that matter. Built and used day to day on a
production web app, then made project-agnostic.

- **Feature workflow:** Planner → Coder → Tester → Reviewer, run step by step (`/planner`,
  `/coder`, `/tester`, `/reviewer`) or end to end (`/feature-flow`), with fix loops and iteration
  caps. Agents never commit, push or create branches.
- **Research team:** `/research` frames a question with you, then a lead dispatches a searcher,
  a web reader, an incident investigator (with a browser repro driver), a designer and a writer,
  and writes a findings file where every claim carries its provenance.
- **Cheap lookups:** the main session hands broad repo sweeps and docs lookups to two Haiku
  agents (`searcher`, `web-reader`) instead of spending its own budget.
- **Research discipline:** label every claim (measured / read / inferred / assumed), pin every
  source's version, run a positive control before reporting "not found", stop at the third
  hypothesis.

## What's enforced, not just asked

| Hook | Stops |
|---|---|
| `git-guard.sh` | commits on and pushes to shared branches, plain `--force`, `--no-verify` |
| `quote-verify-gate.sh` | `web-reader` citing a quote that isn't a verbatim substring of the raw page (fabricated, garbled or paraphrased) |
| `sentry-read-gate.sh` | any Sentry MCP catalog operation that isn't read-only |
| `confluence-draft-gate.sh` | the research lead writing anything to Confluence but an unpublished draft |
| `lock-gate.sh` | while a measurement lock exists, it **asks** before another session runs a heavy command (builds, servers, installs, Lighthouse); the lock's owner and its own agents pass, so no idle session needs waking with a message |

`core/scripts/harness-check.sh` re-proves all of it: deny/allow matrices for each hook (with
positive controls), contract linters between agent files and the workflow rules, tool-boundary
checks, and dead links.

## Requirements

- Claude Code, `git`, `bash`, `node` ≥18, `sha256sum`.
- Plugins the agents invoke: `superpowers` (brainstorming, plans, code-review reception) and
  `chrome-devtools-mcp` (Tester, repro driver, designer).
- Optional, used when your project has them: `atlassian` (Jira/Confluence), a Sentry MCP, a
  session-replay MCP. Mark each one yes/no in `project.md`; agents skip what you don't have.

## Install

```bash
git clone <this repo> ~/claude-code-harness
bash ~/claude-code-harness/install.sh /path/to/your-repo
```

This copies `core/` into `your-repo/.claude/` (refusing to overwrite any file it didn't put there),
merges the hook registrations into an existing `.claude/settings.json`, and seeds
`.claude/project.md`.

Then **fill in `.claude/project.md`**: owner, stack, commands, dev server, branches, code
layout, external systems, review checklist additions. It's the only file a project writes; the
harness never hardcodes those facts. A `TODO` left there reads as "not available": agents skip
that step and say so.

Check the install:

```bash
bash .claude/scripts/harness-check.sh      # expect: harness-check: ALL GREEN
```

Agent files load when a Claude Code session starts: start a new session after installing.

## Update and drift

```bash
bash ~/claude-code-harness/install.sh --update /path/to/your-repo
bash ~/claude-code-harness/install.sh --doctor /path/to/your-repo
```

`.claude/.harness-manifest` records the hash of every installed file. `--update` replaces only
files you haven't edited; an edited file is kept and the new version lands next to it as
`<file>.harness-new` for you to merge. A file that left core is **retired** to `.claude/.harness-retired/<version>/` when unedited
(an edited one is kept, with a warning), so a moved rule stops loading. `--doctor` lists edited, missing and outdated files and
runs harness-check.

## Layout

```
core/                 installed to <repo>/.claude/
  CLAUDE.md           entry point: index of rules, agents, hooks
  agents/ commands/   the two teams and their slash commands
  rules/              conventions. Claude Code loads every rule into every session and subagent,
                      so each declares a class: `load: always`, or `paths:` (loads once a
                      matching file is touched)
  guides/             task-specific contracts (research, feature workflow, review), Read only by
                      the agents and commands that need them
  hooks/              enforcement + session context; hooks/lib/project-config.js reads project.md
  templates/          spec, findings, capture sheet
  scripts/            harness-check, verify-quote, prune-session
  skills/             bundled skills
  vendor/             js-yaml 4.1.0 (MIT), for the quote gate
project-template/     project.md, seeded on install
install.sh            install / --update / --doctor
scripts/leak-check.sh this repo's pre-commit gate (see Contributing)
docs/                 design history
```

## Contributing

This repo is public; the projects it came from are not. `scripts/leak-check.sh` runs as a
pre-commit hook (`git config core.hooksPath .githooks`) and blocks IPs, emails, token shapes,
home-directory paths, and every pattern in a **private denylist kept outside the repo**
(`~/.config/claude-code-harness/denylist`, one regex per line). Put your organisation's names
and domains there, so the repo never has to spell out what it forbids.

Run `bash core/scripts/harness-check.sh` after any change to `core/`, and test a changed agent
or hook in a fresh `claude -p` session: a running session keeps the agent files it started with.

## License

MIT, see [LICENSE](./LICENSE). `core/vendor/js-yaml.min.js` is MIT, see
[core/vendor/js-yaml.LICENSE](./core/vendor/js-yaml.LICENSE).
