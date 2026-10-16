# Project facts

The one file a project writes to adopt the harness. Installed to `<repo>/.claude/project.md`.
Agents read its sections **by heading**, so keep the headings. Hooks read only the
`json harness` block. Anything left as `TODO` reads as "not available here": agents skip that
step and say so; they never guess a value.

```json harness
{
  "shared_branches": ["main", "master", "develop", "release/*"],
  "test_runner_marker": "",
  "dev_ports": [3000],
  "measurement_lock": ".claude/runs/MEASUREMENT-IN-PROGRESS.md"
}
```

- `shared_branches`: `git-guard.sh` denies commits on, and pushes from or to, these. `*` is a
  glob. Default when absent: main, master, develop, staging, stable, production, release/*.
- `test_runner_marker`: a glob whose presence means "a test runner exists" (e.g.
  `vitest.config.*`). Empty: the session hook tries common markers.
- `dev_ports`: what Coder and Tester check with `ss -ltnp` before building or starting a server.
- `measurement_lock`: path of the multi-session measurement lock (`rules/multi-session.md`).

## Owner

Who approves pushes, MR/PR writes and anything on the "ask first" list (`rules/autonomy.md`).
The rules say "the owner"; this is who that is.

- Owner: TODO

## Stack

Pin every version that changes what the docs say. `web-reader` reads this table to pick
versioned docs URLs, and Reviewer uses it to flag APIs the stack can't run.

| Thing | Version | Where its docs live |
|---|---|---|
| TODO (framework) | | |
| TODO (runtime) | | |
| TODO (language) | | |

Client-side support policy (which browsers / how new an API may be): TODO

## Code layout

Where `rules/code-conventions.md` and the agents look for things.

- Source roots: TODO (e.g. `src/`, `server/`); server-only code: TODO
- Import aliases: TODO (e.g. `@app/*` → `src/*`); relative imports out of a root are banned: yes/no
- Icon folder + its import path: TODO (e.g. `src/components/icons/`, `@app/components/icons`)
- Reference icon to copy: TODO
- Helper folders: TODO (e.g. `src/helpers/`, with an index that re-exports)
- Exemplar spec (the density Planner should match): TODO (a path under `.claude/specs/`, or none)

## Commands

| Purpose | Command | Notes |
|---|---|---|
| Build (Coder's gate) | TODO | the full pipeline, not a partial step |
| Dev server (Tester) | TODO | |
| Tests | TODO or `none` | `none` = Coder reports `test_result: n/a` |
| Lint | TODO | not run unprompted by agents |
| Codegen | none | |

## Dev server

- URL Tester opens: TODO (e.g. `https://localhost:3000`)
- Readiness: TODO (how long a cold start takes; what to poll)
- Certificate: TODO (e.g. self-signed: type `thisisunsafe` on Chrome's interstitial)
- Restart quirks: TODO

## Branches and promotion

- Production branch (what's deployed to prod): TODO (e.g. `main`)
- Is `.claude/` tracked in git here? TODO (yes: harness changes go through review; no: each developer installs their own)
- Branch naming: TODO (e.g. `<type>/<TICKET>-short-summary`)
- Flow: TODO (e.g. feature → main via PR; release branches; who merges)
- Commit style: TODO (e.g. Conventional Commits, ticket key as scope)
- Deploy-time traps: TODO or none (e.g. "staging and prod builds share an image tag: before a prod
  redeploy, check no release branch points at the SHA")

## Tickets and docs

- Issue tracker and key: TODO (e.g. Jira `ABC`, GitHub Issues)
- Wiki / long-form docs: TODO
- Where investigation reports go: TODO

## External systems

Mark each `yes` (and how to reach it) or `no`. Agents skip a `no` system instead of failing on it.

| System | Available | Access / notes |
|---|---|---|
| Error tracking (e.g. Sentry) | TODO | |
| Session replay (e.g. LogRocket) | TODO | |
| Log search (e.g. Kibana) | TODO | |
| Browser automation (chrome-devtools MCP) | TODO | |
| Wiki writes (e.g. Confluence drafts) | TODO | |

## Review checklist additions

Repo-specific items Reviewer checks on top of `agents/reviewer.md`'s generic list, e.g.
framework hazards, styling rules, banned imports.

- TODO

## QA fixtures

Pages or data Tester and repro-driver should use: a rich happy-path fixture and a minimal
boundary one (`rules/verification.md`).

- TODO
