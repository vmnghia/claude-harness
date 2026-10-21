# Load budget: three loading classes for harness rules

Status: approved by the owner, 2026-10-21. Phase 5 of
[2026-10-19-runner-and-source-adoption-design.md](./2026-10-19-runner-and-source-adoption-design.md).

## Intent

Every session **and every subagent** pays for every `.claude/rules/**/*.md` file before doing
anything (measured 2026-10-19). Usage limits are the reason this harness delegates to cheap agents
at all. A fixed ~80k-token rules load on each dispatch eats most of that saving. This phase makes
each rule load **when it's needed**, without letting an agent miss a rule it needed.

## Measured baseline (source repo, 2026-10-21, after the switch-over)

- Billing startup tokens (`claude -p --output-format json "Reply with exactly: OK"`, Haiku 5.5):
  **144,517**.
- `/context` attribution (estimates; deferred tools excluded from its 120.7k total):

| Category | ~Tokens |
|---|---:|
| Memory files: project rules (`rules/project/`, 15 files) | 46.5k |
| Memory files: core rules (`rules/*.md`, 14 files) | 32.7k |
| Memory files: CLAUDE.md files + auto-memory index | 15.1k |
| Skills listing, SessionStart hook output, agents, system prompt, tools | ~26k |

`/context` attributes the load; the **billing number decides success**. The two differ by ~24k of
scaffolding that `/context` doesn't itemise.

## Decisions (owner, 2026-10-21)

- **In scope:** project rules and core rules.
- **Out of scope:** the Vercel plugin, the auto-memory index, and the team-owned root `CLAUDE.md`.
- **Three loading classes.** Every rule file belongs to exactly one:
  1. **Always loaded:** stays in `rules/`, no frontmatter. These are safety and conduct rules a
     session might need without knowing it.
  2. **Loaded by the task:** moves to `guides/` (core) or `guides/project/` (project).
     - Claude Code does not auto-load `guides/`.
     - Each guide has named **consumers**: commands, agents or skills that Read it explicitly
       before starting. `CLAUDE.md` indexes it with a "read when…" trigger for the main session.
  3. **Loaded when code is touched:** stays in `rules/` with `paths:` frontmatter, so the platform
     loads it once a matching file is read or edited.
- **When in doubt, class 1.** Misplacing a rule in class 1 costs tokens. Misplacing it in class 2
  or 3 costs correctness.
- **Placement** (approved in the design conversation):

| Class | Core rules | Source-repo project rules |
|---|---|---|
| 1 | autonomy, git, multi-session, delegation, working-style, research-discipline, plugin-skills, bug-fixes | git-release-flow, overview, multi-session-storefront, autonomy-storefront |
| 2 | research-workflow, ai-workflow, code-review, agent-skills | research-storefront, external-systems, mcp-roster, agents-storefront, perf-testing |
| 3 | verification, code-conventions | performance, verification-storefront, toolchain, review-storefront, code-conventions-storefront |
| deleted | | production-issue-triage stub (it only points at the skill, which is on-demand already) |

- **The verbatim excerpts get tidied** in this phase (deferred from the switch-over). The
  `rules/project/` excerpt files lose every passage core already states, and keep only what is
  project-specific.

## Goals / non-goals / anti-goals

- **Goal:** billing startup tokens for a plain session in the source repo drop substantially.
  - The estimate: ~79k of rules → ~27k.
  - The number that counts is the measured one, before and after, with the same command.
- **Goal:** a runner dispatch's fixed cost drops by about the same amount.
  - Measure it with the phase 1 refusal brief's usage, before and after.
- **Goal:** each class is mechanically linted, so the classification can't silently rot.
- **Non-goal:** shortening rules for its own sake. Tidying removes duplication; it doesn't
  rewrite.
- **Anti-goal:** an on-demand rule that nothing ever loads: a guide with no consumer, or a
  `paths:` glob that matches no file.
- **Anti-goal:** a safety rule (pushes, shared branches, the prd image trap, peer sessions) that
  stops loading in some session.

## How the classes work

- **Class 2 consumers:**
  - `/research` + research agents read `guides/research-workflow.md`
  - `/feature-flow` + feature agents read `guides/ai-workflow.md`
  - Reviewer + the main session, when triaging review comments, read `guides/code-review.md`
  - The main session, on capability questions, reads `guides/agent-skills.md`
  - In the source repo:
    - the triage skill + incident-investigator + research-lead read external-systems and mcp-roster
    - searcher + writer read agents-storefront
    - the main session, before proposing load tests, reads perf-testing
- **Class 3 globs:**
  - Core can't know a project's source roots, so core rules use a generic any-code glob (e.g.
    common source extensions).
  - Project rules use precise globs (e.g. the source roots `project.md` § Code layout names).
  - **Measured 2026-10-21** (scratch repo, sentinel words, Haiku 5.5):
    - `paths:` accepts a YAML list of globs, brace sets (`"**/*.{ts,tsx,py}"`) and a plain scalar
      (`paths: "lib/**"`)
    - a rule loads in a **subagent** when *that subagent* Reads a matching file
    - a subagent that reads nothing sees no path-scoped rule (control), so deferral holds per
      agent
- **`harness-check` lints:**
  - every `guides/**/*.md` is named by ≥1 consumer, or by a `CLAUDE.md` index line with a trigger
  - every `rules/**/*.md` with `paths:` has globs that match ≥1 file (in an installed project)
  - every rule left in `rules/` without `paths:` is on an explicit class-1 list
- **Installer:** `guides/` is a core directory like `rules/`. `guides/project/`, like
  `rules/project/`, is project-owned and never written by the installer.

## Constraints

- **Core changes are made in this repo on a branch**, with `harness-check` and `leak-check`
  green. The owner commits. They reach the source repo through `install.sh --update`.
- **Project-file moves in the source repo are project-owned:** no manifest drift.
- **The source-repo update runs under its measurement lock,** with a notice to peer sessions. A
  running session keeps the rules it started with.
- **Rules moved out of auto-load still have to be reachable.** Every move updates the links that
  point at the old path (the switch-over showed project-local files linking into moved rules).

## Measurement and acceptance

1. **Before and after, in the source repo:**
   - the billing startup tokens (same command, same model)
   - a runner refusal brief's total usage
   - the `/context` memory-files total
2. **A fresh session in the source repo:**
   - `/research`-style and `/feature-flow`-style dispatches show their guide was Read
     (consumers work)
   - reading a `src/` file loads a class-3 rule (the `paths:` trigger works)
3. **Safety probe:** a fresh plain session (no code touched) can still quote the shared-branch
   rule and the prd-image trap, which shows class 1 is intact.

## Builder-check resolutions (2026-10-21)

A fresh builder raised eight gaps. All are settled here as **builder's calls**, open to the owner's
veto. None needed the owner, because each answer follows from a decision already in this doc.

1. **How core agents find project guides they can't name:** a **project guide index**,
   `rules/project/guides-index.md`.
   - It is class 1 and tiny. One line per project guide: path, consumers (agent, command or
     skill names), and the "read when…" trigger.
   - It auto-loads into every session and subagent, so each agent sees which project guides its
     role must Read. No core file names a project path.
   - Core guides keep their index lines in core `CLAUDE.md`, and core consumers name them directly.
2. **Consumers, decided by where each excerpt came from** (the 2026-10-19 triage tables):
   - `research-storefront`: the same consumers as `research-workflow`, i.e. `/research` and the
     research agents
   - `agents-storefront`: its excerpts came only from `searcher` and `writer`, so those two
   - Recorded in the guide index.
3. **Stale `rules/` copies after a file moves to `guides/`:**
   - `install.sh --update` **retires** files that left core, rather than leaving them in place. A
     retired file whose hash still matches the manifest (nobody edited it) moves to
     `.claude/.harness-retired/<version>/<path>`, which is outside `rules/` and so never loads.
   - An edited one stays put, with a warning.
   - It's a move, not a delete, so it's reversible, and it gets its own `harness-check` test.
4. **The class-1 marker:** `load: always` frontmatter on every class-1 rule, core and project alike.
   - Measured 2026-10-21: a custom frontmatter key doesn't change auto-loading.
   - `harness-check` fails any `rules/**/*.md` that has neither `paths:` nor `load: always`.
   - Unclassified fails rather than defaulting silently. "When in doubt, class 1" is a human
     decision, so a person must write the marker.
5. **`paths:` match lint:**
   - Skipped in the harness source repo (core globs are generic).
   - Run in installed projects against the filesystem (`find`, excluding `node_modules`, `.next`,
     `.git` and `.claude`), so untracked source roots count.
   - Project globs are written by hand per rule. The lint only checks that each glob matches ≥1 file.
6. **Acceptance threshold:** done means the classes are in place, the lints are green, and the
   before/after numbers are recorded. A billing startup drop under **15k tokens** is a finding to
   raise with the owner before closing, not a silent pass.
7. **Class-3 rules that also matter outside code work** (core `verification`): the approved
   placement stands.
   - Its `CLAUDE.md` index line, which is always loaded, keeps the one-line essentials:
     "type-check ≠ verified; verify in a real browser".
   - So a session verifying a deployed build without touching `src/` still sees the rule's core
     and the pointer to the full file. Nothing gets rewritten.
8. **The excerpt tidy:**
   - It removes only passages that are verbatim or near-verbatim duplicates of a core passage.
   - Anything partial or ambiguous stays.
   - Safety passages always stay (shared branches, pushes, the prd image trap, peer sessions).
   - The final report lists bytes removed per file. There's no per-file review gate.

## Left to the builder

- The exact name of the class-1 list (a frontmatter key or a list in `harness-check`).
- The generic code glob for core class-3 rules, once the syntax probe has run.
- How to batch the excerpt tidy.
