# Load budget: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** sort every harness rule into one of three loading classes, so that each session and each
subagent loads only what its task needs, with the classes linted.

**Architecture:**
- **Phase A, core** (this repo, branch `feat/load-budget`):
  - class markers, plus a `harness-check` lint
  - core class-2 rules move to `core/guides/`, and their consumers are re-pointed
  - class-3 core rules get a generic `paths:` glob
  - `install.sh --update` retires files that left core
- **Phase B, source repo:**
  - project rules are re-classed in a staging tree outside the repo: `guides/project/`, a guide
    index, precise `paths:` globs, and the excerpt tidy
  - then one locked `--update` + copy, measured before and after

**Tech stack:** bash, Node ≥18, Claude Code rule frontmatter (`paths:`, plus the custom
`load: always` marker), `claude -p` for fresh-session measurement.

**Spec:** [2026-10-21-load-budget-design.md](./2026-10-21-load-budget-design.md), including its
"Builder-check resolutions".

## Global Constraints

- **Class markers:** class 1 is `load: always` frontmatter. Class 3 is `paths:` frontmatter (a YAML
  list of quoted globs). Class 2 lives under `guides/` (core) or `guides/project/` (project), with
  no auto-load. A `rules/**/*.md` file with neither marker fails `harness-check`.
- **Core class-3 glob:** exactly
  `"**/*.{ts,tsx,js,jsx,mjs,cjs,vue,svelte,py,go,rs,java,kt,rb,php,cs,swift,css,scss,sass,less,html}"`.
- **Safety files must carry `load: always`:** core `autonomy`, `git`, `multi-session`; project
  `git-release-flow`. This is linted by name.
- **Placement is the spec's table, verbatim.** No file changes class in this plan.
- **Retire, never delete:** an unedited file that left core moves to
  `.claude/.harness-retired/<version>/<path>`. An edited one stays, with a warning.
- **The excerpt tidy** removes only verbatim or near-verbatim duplicates of core passages. Safety
  passages always stay.
- **Repo rules carried over:**
  - `leak-check` must be clean; the owner commits; this repo works on a branch
  - files that quote git commands are written with the Write tool while the source checkout is on
    a shared branch
  - the source repo's measurement lock plus peer notice cover the switch, as in the 2026-10-19 plan
- **Success:** the before/after billing startup tokens are recorded. A drop under 15k is raised
  with the owner before closing.

## Review Focus

1. **A link or prose reference still pointing at a moved file's old `rules/<name>.md` path,** in
   core or in project-local files (agents, commands, skills, templates, `project.md`). Pinned by
   Task 2's grep check (prose and links) and Task 6's link check.
2. **An adopter who edited a file that later leaves core:** `--update` must keep the file and warn,
   not retire it. Pinned by Task 3's edited-file case.
3. **A `paths:` glob that matches only ignored folders** (`node_modules`, `.next`): the match lint
   must exclude them, so such a glob fails. Pinned by Task 1's lint and a negative fixture.
4. **A safety rule accidentally given `paths:`, or left unmarked:** it would stop loading in plain
   sessions. Pinned by Task 1's by-name check, and by Task 7's safety probe.
5. **A consumer that names its guide only in prose** ("read research-workflow.md") with the old
   path: the agent would Read a missing file. Pinned by Task 2's grep, which counts prose
   mentions, not just links.

---

## Phase A: core (this repo, branch `feat/load-budget`)

### Task 1: class lint in `harness-check` (§5e)

**Files:**
- Modify: `core/scripts/harness-check.sh` (new section `== 5e. Loading classes ==`, before §6)

**Interfaces:**
- **Produces:**
  - `fm_has <file> <key>`: true if the file's leading `---` frontmatter block has a line starting
    with `<key>:`
  - `paths_of <file>`: prints each glob of its `paths:` list, one per line
  - `guide_consumers <guide>`: prints the files under `agents/`, `commands/`, `skills/`, `CLAUDE.md`
    and `rules/project/guides-index.md` that mention the guide's basename
- **Checks:**
  1. Every `$H/rules/**/*.md` has `load:` **or** `paths:`. Each failure names the file.
  2. `$H/rules/{autonomy,git,multi-session}.md`, and `$H/rules/project/git-release-flow.md` if it
     exists, contain the frontmatter line `load: always`.
  3. Every `$H/guides/**/*.md` has ≥1 consumer (`guide_consumers` non-empty).
  4. Every `$H/guides/project/*.md` is listed in `$H/rules/project/guides-index.md`.
  5. **Installed projects only** (skipped when `$H = $ROOT/core`): every glob of every `paths:`
     rule matches ≥1 file under `$ROOT`. Exclude `node_modules`, `.next`, `.git` and `.claude`.
     Match with `node` (`fs` walk + a minimal glob→regex supporting `**`, `*`, `{a,b}`).

- [ ] **Step 1: Write the checks.** Also add a negative fixture: a temp tree holding one rule
  with `paths: ["node_modules/**"]`, plus `node_modules/x.js`. The match function must report 0
  matches.
- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh`. Expected: FAIL for each of the 14 core
  rules (no marker) and for the 3 safety-name checks. The negative fixture passes (0 matches).
- [ ] **Step 3: Run it against a scratch install** (`$HOME/harness-adoption/phase1/scratch`).
  Expected: the same FAILs, since the core rules are unmarked there too.

(Task 2 turns them green; there is no commit until Task 2.)

### Task 2: re-class core rules and re-point consumers

**Files:**
- Move: `core/rules/{research-workflow,ai-workflow,code-review,agent-skills}.md` →
  `core/guides/`
- Modify (frontmatter `load: always`): `core/rules/{autonomy,git,multi-session,delegation,working-style,research-discipline,plugin-skills,bug-fixes}.md`
- Modify (frontmatter `paths:` + the generic glob): `core/rules/{verification,code-conventions}.md`
- Modify (references):
  - every `core/agents/*.md`, `core/commands/*.md`, `core/templates/*.md`, `core/rules/*.md` that
    names a moved file
  - `core/CLAUDE.md`
  - `core/scripts/harness-check.sh` (`RW=`, `WF=` and any `rules/<moved>.md` path)

**Interfaces:**
- **Produces** the paths `core/guides/research-workflow.md`, `core/guides/ai-workflow.md`,
  `core/guides/code-review.md` and `core/guides/agent-skills.md`.
- **Produces** `core/CLAUDE.md`:
  - a `## Guides (loaded by the task that needs them)` section: one line per guide, with its
    trigger and consumers
  - its `## Rules` intro explains the three classes
  - the verification index line keeps the one-line essentials "type-check ≠ verified; verify in a
    real browser"

- [ ] **Step 1: Write the failing reference check** in §5e:
  - `grep -rnE 'rules/(research-workflow|ai-workflow|code-review|agent-skills)\.md|\b(research-workflow|ai-workflow|code-review|agent-skills)\.md' $H/agents $H/commands $H/templates $H/rules $H/CLAUDE.md $H/skills`
    must print no line that lacks `guides/`
  - every `guides/` mention must resolve
  - Expected now: FAIL, listing the current references.
- [ ] **Step 2: `git mv` the four files.** Add the frontmatter markers. Rewrite every reference,
  in links and in prose, from `rules/<name>.md` to `guides/<name>.md` (relative from each file).
- [ ] **Step 3: Edit `core/CLAUDE.md`:**
  - `## Rules` describes the classes
  - the new `## Guides` section
  - the verification one-liner
- [ ] **Step 4: Run** `bash core/scripts/harness-check.sh` and `bash scripts/leak-check.sh`.
  Expected: `ALL GREEN` and `clean`.
- [ ] **Step 5: Commit (owner):** paths `core/rules core/guides core/agents core/commands core/templates core/CLAUDE.md core/scripts/harness-check.sh`,
  message `feat(rules): three loading classes; task-gated rules move to guides/`.

### Task 3: `install.sh --update` retires files that left core

**Files:**
- Modify: `install.sh` (`update` branch)
- Test: `core/scripts/harness-check.sh` (the source-repo-only block, next to the drift tests)

**Interfaces:**
- **Behaviour:** for each manifest entry whose path is no longer in core:
  - **hash equals the manifest's:** `mkdir -p` and `mv` it to
    `$DEST/.harness-retired/$VERSION/<path>`, print `  retired: <path>`, and drop it from the new
    manifest
  - **else:** print
    `  no longer in core but edited locally, kept: <path> (move or delete it yourself)`, and drop
    it from the new manifest
  - The summary line gains `, <n> retired`.

- [ ] **Step 1: Write the failing test.** In a `mktemp -d` repo:
  1. Install.
  2. Append a fake entry: create `.claude/rules/zz-old.md` with content `x`, and add its sha256 line
     to the manifest.
  3. Create `.claude/rules/zz-edited.md` with content `y`, but give the manifest the hash of `x`.
  4. Run `install.sh --update`.
  5. Assert:
     - `.claude/.harness-retired/*/rules/zz-old.md` exists and `.claude/rules/zz-old.md` doesn't
     - `.claude/rules/zz-edited.md` still exists, and the output says `edited locally, kept: rules/zz-edited.md`
     - neither path remains in the manifest
- [ ] **Step 2: Run it.** Expected: FAIL (today's update only prints "left in place").
- [ ] **Step 3: Implement** in `install.sh`'s `update` branch, replacing the current
  "no longer in core" loop.
- [ ] **Step 4: Run** `harness-check` and `leak-check`. Expected: `ALL GREEN` and `clean`.
- [ ] **Step 5: Commit (owner):** paths `install.sh core/scripts/harness-check.sh`, message
  `feat(install): --update retires unedited files that left core`.

### Task 4: phase A acceptance

- [ ] **Step 1: Update the scratch install** with `bash install.sh --update $HOME/harness-adoption/phase1/scratch`.
  Expected:
  - `retired:` lines for the four moved rules
  - `.claude/guides/` present
  - the scratch `harness-check` `ALL GREEN`
- [ ] **Step 2: Fresh session in scratch,** asking it to quote, without tools, a sentence from
  `research-workflow` (e.g. its "Single writer" rule). Expected: it can't. The guide isn't loaded.
- [ ] **Step 3: Owner merges** `feat/load-budget` into `main`. Phase B installs that commit.

## Phase B: source repo

### Task 5: staging tree for the project re-class

**Files** (all under `$HOME/harness-adoption/staging2/.claude/`, outside the repo):
- **Move from `rules/project/` to `guides/project/`:** `research-storefront.md`,
  `external-systems.md`, `mcp-roster.md`, `agents-storefront.md`, `perf-testing.md`
- **Delete:** `rules/project/production-issue-triage.md`
- **Frontmatter `load: always`:** `rules/project/{git-release-flow,overview,multi-session-storefront,autonomy-storefront}.md`
- **Frontmatter `paths:`:**
  - `performance.md`: `["src/**", "@libs/client/**", "@libs/common/**", "assets/**"]`
  - `verification-storefront.md`: `["src/**", "@server/**", "@libs/**"]`
  - `toolchain.md`: `["package.json", ".nvmrc", ".yarnrc.yml", "tsconfig*.json", "next.config.js", "src/**", "@libs/**", "@server/**"]`
  - `review-storefront.md`: `["src/**", "@libs/**", "@server/**"]`
  - `code-conventions-storefront.md`: `["src/**"]`
- **Create `rules/project/guides-index.md`** (`load: always`), one line per project guide:

  | Guide | Consumers | Read when |
  |---|---|---|
  | research-storefront | `/research`, research-lead, incident-investigator, repro-driver, searcher, web-reader, designer, writer | any research run |
  | external-systems | `production-issue-triage` skill, incident-investigator, research-lead, main session | prod investigation, Kibana / Kong / k8s / Prometheus |
  | mcp-roster | same as external-systems, plus the main session before any MCP write | MCP availability or writes |
  | agents-storefront | searcher, writer | every dispatch of either |
  | perf-testing | main session | before proposing load tests |

- **Rewrite references** to the five moved files:
  - in `project.md`
  - in the project-local `skills/production-issue-triage/SKILL.md`, `templates/*.md` and
    `rules/project/*.md` (copied into staging2 first)

- [ ] **Step 1: Copy the live project files into `staging2`:** `rules/project/`, `project.md`,
  `skills/production-issue-triage/` and `templates/`.
- [ ] **Step 2: Apply the moves, markers, index and reference rewrites above.**
- [ ] **Step 3: Excerpt tidy.**
  - For each `rules/project/*.md` and `guides/project/*.md` excerpt section, drop a paragraph when
    its whitespace-normalised text appears verbatim in any `core/**/*.md` on `main`.
  - Keep any paragraph that names a shared branch, a push, the prd image, or a peer session.
  - Print the bytes removed per file.
- [ ] **Step 4: Extend `$HOME/harness-adoption/check-staging.sh`:**
  - every staged `rules/project/*.md` has a marker
  - every `guides/project/*.md` is in the index
  - no staged file mentions `rules/project/<moved>.md`
  - the existing link check, which also scans the staged skill and templates
  - Expected: `ALL GREEN`.

### Task 6: switch (locked) and measure

**Files:** the source repo's `.claude/`; log `$HOME/harness-adoption/load-budget.md`.

- [ ] **Step 1: Lock + peer notice**, as in the 2026-10-19 Task 12.
- [ ] **Step 2: Measure before:**
  - **billing startup tokens:** `claude -p --model claude-haiku-5-5 --output-format json "Reply with exactly: OK"`
  - the `/context` memory-files total
  - the total usage of one runner refusal brief (phase 1 Brief A, dispatched via `claude -p`)
- [ ] **Step 3: Back up** `.claude/` (`cp -a` + `tar czf`, then verify with `diff -rq --no-dereference`).
- [ ] **Step 4: Update and apply:**
  1. `bash <harness>/install.sh --update <source-repo>`. Expected: 4
     `retired:` lines.
  2. Copy the `staging2` changes in.
  3. Move the five old `rules/project/` copies and the triage stub to
     `$HOME/harness-adoption/moved-aside-2/`.
- [ ] **Step 5: Verify:**
  - `install.sh --doctor`: all installed files match
  - `harness-check`: `ALL GREEN`, including §5e's match lint on the real tree and §9's project
    checks
- [ ] **Step 6: Measure after,** with the same three numbers. Record before, after and delta. If
  the billing startup drop is under 15k, stop and raise it with the owner.
- [ ] **Step 7: Release the lock**, and send "machine free".
- [ ] **Rollback (only if step 5 fails):** restore the backup, re-run `harness-check`, release the
  lock.

### Task 7: behaviour acceptance (fresh sessions, source repo)

- [ ] **Step 1: Safety probe.** A plain session, no tools, quotes the shared-branch rule (core
  `git.md`) and the prd image trap (`git-release-flow`). Expected: both present.
- [ ] **Step 2: Class-3 probe:**
  - **before any read:** a plain session can't quote a known phrase from `performance.md` (its
    "§10.1" hydration gate)
  - **after `Read src/pages/_app.tsx`:** the same session can
- [ ] **Step 3: Consumer probe.** Dispatch `searcher` (fresh `claude -p`) with a one-line lookup.
  Ask it to also report the first heading of each guide its role says to read. Expected: it quotes
  the headings of `guides/research-workflow.md` and `guides/project/agents-storefront.md`.
- [ ] **Step 4: Record** the probes in `load-budget.md`. Update the
  `claude-rules-auto-load-everywhere` and `claude-code-harness-repo` memory notes with the
  measured numbers and the classes.
