# Portability design: claude-code-harness

Status: **APPROVED** 2026-10-16 (installer for v1, MIT, provenance = dates only, no
attribution). **IMPLEMENTED** 2026-10-16: phases 1–4 done; `leak-check` clean, `harness-check`
green from the repo and from a fresh test install; install / `--update` / `--doctor` exercised
end to end (merge into an existing settings.json, refusal on conflicts, an edited file kept with
`.harness-new`). Date: 2026-10-16.

Deviations from the design below, found while building:

- `web-reader` has no Read tool, so it can't open `project.md`: callers paste § Stack into its
  brief (delegation.md, research-lead step 2).
- `incident-investigator` no longer depends on the storefront triage skill; its evidence spine
  is inline and conditional on `project.md` § External systems, with a generic
  `templates/capture-sheet.md`.
- `harness-check` runs from both layouts (`H` = harness dir, `ROOT` = project root) and pins
  `CLAUDE_PROJECT_DIR` in its git-guard sandbox, so a real `project.md` can't skew the
  default-list tests.
Source: copied from the `.claude/` of the private repo it was built in, on 2026-10-16 (that copy
stays live; the two are not linked).

## Intent

Make the Claude Code harness built in that source repo (feature flow
Planner→Coder→Tester→Reviewer, the research team, the safety hooks, research discipline)
adoptable by any repo. It will be published on GitHub, so the core must carry no internal
infrastructure, no company names and no personal data.

## Goals / non-goals / anti-goals

- **Goal:** a repo adopts the harness by installing the core and writing one project file.
  Nothing in the core names a stack, host, branch, person or ticket system.
- **Goal:** the core's own checks (`harness-check.sh`) pass in a fresh repo with only the
  project file filled in.
- **Non-goal:** migrating the source repo or its sibling onto it now. Copy only.
- **Non-goal:** generic versions of the storefront-only parts (perf toolkit, Kibana/Kong
  playbooks, measure-gate). They stay in the source repo.
- **Anti-goal:** a config system so abstract that agents can't be read top to bottom. The
  project file is plain markdown + a small JSON block, nothing more.
- **Anti-goal:** an internal hostname, IP, cluster id or name reaching a commit.

## Decisions taken so far (owner, 2026-10-16)

- Local repo now, pushed to GitHub only when fixing is done.
- The source repo keeps its own copy; both exist until a later switch-over.
- No specific next adopter: parameterize the obvious values generically.

## Proposed design

### 1. Distribution: install-by-copy (v1), not a plugin

Two options:

| | Plugin (`.claude-plugin/`) | Installer copies core into `<repo>/.claude/` |
|---|---|---|
| Discovery | Claude Code loads agents/commands/hooks/skills from the plugin | Claude Code's native `.claude/` discovery |
| Rules (`../rules/x.md` links in agents) | break: agent bodies don't expand `${CLAUDE_PLUGIN_ROOT}` *(inferred, to verify)* | keep working unchanged |
| Updates | reinstall the plugin | `install.sh --update` with a manifest + three-way diff |
| Drift | none | possible; `doctor` reports it |

**Recommendation:** installer for v1. Every relative link keeps working, and the drift risk is
handled by a manifest of core file hashes (`.claude/.harness-manifest`): an update overwrites
only files the project hasn't edited, and reports the rest. Revisit a plugin once rule
resolution inside plugins is verified.

### 2. Layout

```
core/                      → installed to <repo>/.claude/
  agents/ commands/ hooks/ rules/ templates/ skills/ scripts/
  CLAUDE.md                  harness entry point (index of rules)
  settings.json              hook registrations
project-template/
  project.md               → <repo>/.claude/project.md  (the only file a project must write)
install.sh                 install / --update / doctor
scripts/leak-check.sh      pre-commit gate for THIS repo (see 6)
vendor/js-yaml.min.js      MIT, for quote-verify-gate (see 5)
docs/
```

### 3. The project file

`<repo>/.claude/project.md`: prose sections agents read by name, plus one fenced
`json harness` block hooks read mechanically.

- **Owner:** who approves (replaces 144 mentions of a named person with "the owner").
- **Commands:** build / dev / test / lint / codegen, with "don't run unprompted" flags.
- **Dev server:** URL(s), ports, cert bypass if any, readiness probe.
- **Branches:** shared-branch regex (git-guard), promotion flow, naming.
- **Stack pins:** the web-reader's version/docs table moves here.
- **Tickets & docs:** issue tracker key, wiki, where reports go.
- **External systems:** which of Sentry / session replay / log search exist (agents skip
  absent ones).
- **Review checklist additions:** repo-specific reviewer items.

### 4. What moves where

| Tier | Files | Fate |
|---|---|---|
| Core, rename only | research-discipline, ai-workflow, research-workflow, delegation, multi-session, bug-fixes, working-style, autonomy, code-review (CodeRabbit part), plugin-skills, agent-skills; templates findings/spec; hooks git-guard, sentry-read-gate, confluence-draft-gate, quote-verify-gate, session-context; scripts verify-quote, prune-session, harness-check | stay in `core/`, de-personalised |
| Core, parameterized | all 11 agents, git.md, verification.md, code-conventions.md | values move to `project.md` |
| Storefront only | toolchain, performance, external-systems, mcp-roster, perf-testing; templates kibana-query-sheet, confluence-rnd-page; skill production-issue-triage; hook measure-gate | **removed** from this repo (still live in the source repo) |

Incident history in the core (e.g. "the 2026-09-15 outage") is kept as anonymised lessons:
the lesson stays, hosts/tickets/names go.

### 5. Hook dependencies

- `quote-verify-gate.sh` loads `vendor/js-yaml.min.js` (v4, MIT) instead of the project's
  `node_modules`. Needs only `node` ≥18 on PATH.
- `git-guard.sh` reads the shared-branch regex from `project.md`'s JSON block, defaulting to
  `^(main|master|develop|staging|stable|release/.+)$`.
- `measure-gate.sh` is removed (storefront-only, and its default path is `/home/<user>/…`).

### 6. Leak gate

`scripts/leak-check.sh` fails the commit (wired as a git pre-commit hook in this repo) on:
generic patterns (IPv4 except 127.0.0.1/0.0.0.0, emails, token shapes, `/home/<user>`), plus
a **denylist kept outside the repo** (`~/.config/claude-code-harness/denylist`), so the
company's domains are never written into the public repo just to forbid them.

### 7. harness-check

Split into core checks (contracts, hook matrices, tool boundaries, leak patterns) that pass in
any repo, and an optional `project/checks.sh` the project supplies.

## Left to the builder

- Exact JSON keys of the `json harness` block.
- Wording of de-personalised decision provenance ("(owner, 2026-10-16)").
- README and LICENSE (MIT assumed; owner to confirm).

## Resolved (2026-10-16)

1. v1 distribution: **installer** copying into `<repo>/.claude/`.
2. License: **MIT**.
3. Decision provenance: **keep dates, drop all attribution**: "(<name>, 2026-10-14)" →
   "(2026-10-14)". Approvals in the rules name the role ("the owner"), never a person.
