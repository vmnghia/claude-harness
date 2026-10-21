# Runner agent + making this repo the harness's official source

Status: approved by the owner, 2026-10-19. Supersedes two points of
[2026-10-16-portability-design.md](./2026-10-16-portability-design.md): its non-goal
"migrating the source repo … copy only", and its claim that rules are not auto-loaded.

## Intent

1. **This repo becomes the official harness source.** Harness changes are made in `core/` and
   reach a project only through `install.sh --update`. The source repo (the web storefront the
   harness was extracted from) stops keeping its own hand-edited copy and adopts the core like any
   other project.
2. **A cheap command runner joins the core.** Usage limits fill faster than they used to, so the
   main session hands long or repetitive command output (lint, builds, log sweeps, multi-step git)
   to a Haiku agent and reads back a summary. The agent was built and smoke-tested in the source
   repo on 2026-10-19. It has to move here before the source repo can adopt the core.

## Measured facts this design rests on (2026-10-19)

| Fact | How measured |
|---|---|
| Every `.claude/rules/**/*.md` auto-loads at session start, **recursively**, into the main session **and every subagent** | sentinel words in a scratch repo, `claude -p` + one dispatched subagent |
| A rule with `paths:` frontmatter loads only after a matching file is touched | same probe: absent at start, present after `Read src/a.ts` |
| In the source repo that eager load is ~37k tokens of rules + ~8.5k of CLAUDE.md, paid per session and per dispatch | byte count ÷ 4 (estimate) |
| A runner dispatch costs ~87k–102k subagent tokens before any command output | two smoke-test dispatches |
| `Grep` (and `Glob`) can be listed in an agent's tools yet be absent at runtime ("No such tool available") | runner smoke test; same as a 2026-10-16 report for research-lead |
| `$CLAUDE_PROJECT_DIR` is **unset** inside Bash tool commands (it is set for hooks) | `echo` in a Bash call |
| A **newly created** agent file was dispatchable mid-session, seconds after it was written. A mid-session edit to an existing agent was not picked up (2026-10-16) | tool list announcement; earlier measurement |
| bash `time ( cmd ) > log 2>&1` sends the timing into the log file, not the command result | runner smoke test (`step-1.log` held only the timing) |

## Decisions (owner, 2026-10-19)

- **Runner contract:** Haiku 5.5 may run **any** command, writes included, **provided the
  dispatcher hands it the command verbatim**. It never composes, retries or fixes one.
- **Lint is report-only.** No `--fix`, and no project lint script that auto-fixes. The runner
  refuses both. Lint may run through the runner without being asked, because its output never
  reaches the main context. The main session still never runs lint inline.
- **`eslint-summary.js` ships in core as an optional helper** for ESLint projects. This
  deliberately bends the 2026-10-16 goal "nothing in the core names a stack": the owner uses
  ESLint in almost every project. Its fixture tests live in core `harness-check`.
- **Project rules live in `.claude/rules/project/`.** The installer never writes there, and Claude
  Code discovers the folder on its own, so no index is needed.
- **Order:** migrate first, behaviour-preserving. Then, as a separately measured change, reduce
  the eager load (phase 5).
- Harness changes reach the source repo only via `install.sh --update`. Editing an installed core
  file in place is drift.

## Goals / non-goals / anti-goals

- **Goal:** the source repo runs on an installed core, plus `project.md`, plus
  `rules/project/`, plus its own extras. `install.sh --doctor` reports no local edits, and core and
  project checks are green.
- **Goal:** no storefront knowledge is lost in the move. Every hunk the core stripped out lands
  somewhere the source repo's agents still load.
- **Non-goal:** generic versions of storefront-only tooling (perf toolkit, log-search playbooks,
  the measure gate). They stay project-local, as in 2026-10-16.
- **Anti-goal:** an internal name, host, path or ticket key reaching a commit here
  (`scripts/leak-check.sh` + the private denylist).
- **Anti-goal:** a switch-over that also changes what loads. A regression after it must have only
  one possible cause.

## Phases

### 1. Core additions (this repo, on a branch: git-guard denies commits on `main`)
- **`core/agents/runner.md`**, de-personalised from the source repo's tested version:
  - the wrapper starts at `cd "$(git rev-parse --show-toplevel)"`, not a hardcoded path
  - run folders go under `.claude/runs/runner/`
  - the refusal list is generic (`--fix`, `--write`, `git add -A`, `git commit -a`, `git clean`,
    `git reset --hard`, an unapproved `git push`), plus any command `project.md` marks as writing
    files
- **`core/scripts/eslint-summary.js`** (optional helper), plus its fixtures in `harness-check`.
- **Core rule updates:**
  - `delegation.md`: the runner row, the "judgement goes in the brief" rule, the lint recipe
  - `autonomy.md`: lint only through the runner, report-only
  - `CLAUDE.md`: index entry; correct the "not auto-loaded" sentence; the `rules/project/` convention
- **`harness-check`:**
  - runner checks: model pin, no Write/Edit/Agent, required tokens
  - call `.claude/project/checks.sh` when it exists (the 2026-10-16 design's §7, never built)
- **`project.md` template:**
  - `## Commands` gains a "writes files" flag
  - a lint recipe slot
- **Gotchas:** the measured facts above, anonymised.
- **Acceptance:** `leak-check` exit 0, `harness-check` all green, and a fresh `claude -p` runs the
  two runner smoke briefs (refusal must return `BLOCKED` with nothing run; a real lint must return
  `DONE` with copied summary lines).

### 2. Prepare the source repo (no switch yet, still running on its live copy)
- **Write its `.claude/project.md`:** owner, stack pins, commands, dev server, branches and
  promotion, tickets and docs, external systems, review checklist additions, QA fixtures.
- **Residue triage.** For each of the ~33 installed-core files whose live version differs from
  `core/`, classify every diff hunk as one of:
  - **project fact** → `project.md`
  - **project knowledge** → a file in `rules/project/`
  - **generic improvement the core lacks** → back to phase 1
  - **personalisation only** → drop
  This needs judgement: Sonnet agents per file group return hunk classifications, and the main
  session reviews them. The live copy stays untouched until phase 3.
- **`.claude/project/checks.sh`:** the measure-gate matrix, storefront doc-drift greps.
- **Already project-local, stays put:** storefront-only rules, templates, the measure-gate hook,
  the perf scripts, and the triage skill.

### 3. Switch-over (machine lock + peer-session notice: hooks change for every session)
1. Back up the whole `.claude/` outside the repo. `specs/`, `runs/`, `investigations/`,
   `reports/` and `settings.local.json` are not core paths, so the installer never touches them.
2. Move the core-path files aside, run `install.sh`, put the phase 2 files in place.
3. `install.sh --doctor`: no local edits. Core and project checks: green.
4. In a fresh session: both runner smoke briefs, and a git-guard deny.
5. **Rollback:** restore the backup.

### 4. Make "official source" stick
- A core rule: harness edits go to this repo, then `install.sh --update`.
- `session-context.sh` reports "N harness files edited locally" from the manifest at every
  session start, so drift is seen rather than remembered.

### 5. Load budget (after phase 3, measured on its own)
- Make rarely-needed rules on-demand: `paths:` frontmatter where a file glob fits (code-tied
  rules); move out of `rules/` and index from `CLAUDE.md` where it doesn't (investigation
  playbooks, research-only contracts).
- In the source repo the candidates total ~18k of the ~45k-token eager load.
- **Before and after:** the same runner smoke brief's dispatch tokens, and a fresh session's
  start-up context.

## Constraints

- **Commits and pushes in this repo are the owner's.** The leak gate runs pre-commit (and is
  re-run by hand before anything is shown as ready).
- **The source repo's `.claude/` is untracked**, so its switch-over needs no MR, but nothing in
  git backs it up either. Hence the explicit backup.
- **Other Claude sessions may be running in the source repo.** Changes to hooks and settings, and
  the switch-over itself, follow its multi-session rule: lock file, notice, "machine free".

## Builder-check resolutions (2026-10-19)

A fresh builder read this doc and raised nine gaps. Each one is settled below. **(Answered)** means
the owner already decided it in the design conversation. **(Builder's call)** is a decision made
when the doc was written, open to the owner's veto.

1. **Where the source repo's `.claude/CLAUDE.md` content and its storefront-only rules go**
   (Builder's call).
   - **Storefront-only rules** (toolchain, performance, external systems, MCP roster, perf
     testing, the triage stub) **move into `rules/project/`** along with the residue. That gives one
     place for everything project-owned, and no future core file can collide with them.
   - **The storefront part of `.claude/CLAUDE.md`** (repo identity, commands, architecture) becomes
     `rules/project/overview.md`.
   - Relative links between moved files are rewritten. Core files never link to project files.
   - **What "doesn't change what loads" means:** `project.md` is **not** auto-loaded. A fact moved
     *only* into `project.md` would stop loading eagerly. So project facts that agents look up by
     name live in `project.md`. The storefront knowledge the main session needs at all times lives
     in `rules/project/`, which still loads eagerly.
   - **Measured at the switch-over:** a fresh session's start-up context tokens, before and after.
     A large change is a phase 3 finding, not a phase 5 change.
2. **Where the phase 1 smoke briefs run** (Builder's call).
   - **Refusal brief:** in a scratch git repo with the core installed by `install.sh`. That also
     tests the installer. The brief is `git status --porcelain`, then an auto-fixing lint, then an
     unapproved `git push`. Pass means `BLOCKED`, all steps `not_run`, and no run folder created.
   - **Real-lint brief:** it needs an ESLint project, so it runs in the source repo as phase 3's
     acceptance. Phase 1 covers `eslint-summary.js` with offline fixtures only.
3. **The report-only lint command** (Answered).
   - The recipe in the source repo's `project.md` is `npx eslint . -f json -o <run_dir>/eslint.json`,
     then `eslint-summary.js`. No new package.json script, so there is no tracked change.
   - Project scripts that auto-fix (the source repo's `yarn lint`, `yarn format`) are listed under
     `project.md` § Commands with the "writes files" flag, and the runner refuses whatever is
     listed there.
4. **Enforcing `--fix` refusal by hook** (Builder's call): **prose only** for now. Commits
   legitimately run auto-fixing lint through lint-staged, so a hook would need exemptions. Revisit if
   an agent is ever seen running a fix.
5. **Lint without being asked** (Answered):
   - The owner's decision: lint through the runner may run unprompted, because its output never
     reaches the main context.
   - Core `autonomy.md` ships that default.
   - `project.md` § Commands can mark lint "on request only" for an adopter who wants the old
     behaviour.
6. **Who runs phase 3** (Builder's call): the main session in the source repo, with the owner's go
   at each phase gate. The plan carries the exact commands (backup, move, install, doctor, checks),
   not just a checklist.
7. **Is the core frozen after phase 1?** (Builder's call): no.
   - Phase 2's "generic improvement" hunks are added to the same core branch.
   - Phase 1's acceptance is re-run at the end of phase 2.
   - The owner commits and merges only after that, so phase 3 installs one final core version.
8. **How the runner knows the repo root and the "writes files" list** (Builder's call):
   - The brief carries `repo_root` (absolute).
   - The runner rejects a `run_dir` not under `<repo_root>/.claude/runs/runner/`.
   - Before running anything, it Reads `<repo_root>/.claude/project.md` § Commands for commands
     flagged "writes files", and refuses those too.
   - `repo_root` joins the required brief fields and `harness-check`'s token list.
9. **Runner checks and the source location** (Builder's call).
   - The runner's model pin is checked in its own `harness-check` section, as in the source repo
     today. The research-team model table is not touched.
   - `install.sh` records `source <path>` in the target's manifest. The manifest sits in the
     adopter's repo, never here, so no path reaches this repo.
   - The phase 4 rule stays path-free ("edit the harness source named in `.claude/.harness-manifest`,
     then `install.sh --update`"), and `session-context.sh` prints that source line.

## Left to the builder

- Exact `project.md` keys for the "writes files" flag and the lint recipe.
- Exact name and shape of `project/checks.sh`'s contract with `harness-check` (exit code, output
  lines).
- How to batch the residue triage across agents.
