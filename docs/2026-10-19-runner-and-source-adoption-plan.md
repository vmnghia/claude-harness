# Runner agent + source-repo adoption: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ship the `runner` agent in core, then move the source repo onto an installed core, so
that this repo becomes the only place harness changes are made.

**Architecture:**
- **Phase 1** adds to `core/` on a branch: the runner, `eslint-summary.js`, a project-checks hook
  in `harness-check`, and drift reporting.
- **Phase 2** builds the source repo's `project.md`, `rules/project/` and `project/checks.sh` in a
  staging tree **outside** that repo.
- **Phase 3** swaps the source repo's hand-edited `.claude/` for `install.sh` output plus the
  staged files, with a backup and rollback.
- **Phase 5** (load budget) is a separate plan, written after task 12's measurements.

**Tech stack:** bash, Node ≥18 (`node:fs`, `node:path` only), Claude Code agents/rules/hooks,
`claude -p` for fresh-session tests.

**Spec:** [2026-10-19-runner-and-source-adoption-design.md](./2026-10-19-runner-and-source-adoption-design.md).
Read it first, including its "Builder-check resolutions".

## Global Constraints

- **Leak gate:** `bash scripts/leak-check.sh` exits 0 before anything in this repo is called ready.
  No person's name, home path, internal host or ticket key in any file here.
- **Commits and pushes in this repo are the owner's.** Every "Commit" step below hands the owner
  the exact `git add <paths>` / `git commit` lines. Never `git add -A`.
- **Work on branch `feat/runner-agent`:** git-guard denies commits on `main`.
- **Runner model pin:** `model: claude-haiku-5-5`. Its tools are exactly `Bash, Read, Grep, Glob`:
  no `Write`, `Edit`, `Agent` or `NotebookEdit`.
- **Lint is report-only.** No step anywhere runs `--fix`, `--write`, or a command flagged
  "writes files".
- **The source repo's `.claude/` is untracked.** No tracked file in the source repo changes in this
  plan (no package.json script, no root `CLAUDE.md` edit).
- **Staging lives outside the source repo:** `$HOME/harness-adoption/staging/.claude/`. Anything
  placed under the live `.claude/rules/` loads into every new session at once (measured
  2026-10-19).
- **The switch-over (task 12) runs under the source repo's measurement lock file**, with a
  notice to peer sessions before and "machine free" after.
- **git-guard false positive:** git-guard matches commit/push words anywhere in a Bash command.
  Write files that quote git commands with the Write tool, not a shell heredoc, when the checkout
  is on a shared branch.
- **Verification commands:**
  - `bash core/scripts/harness-check.sh` (this repo) prints `harness-check: ALL GREEN`
  - `bash scripts/leak-check.sh` prints `leak-check: clean`

## Review Focus

1. **Staged files leaking into live sessions.** A staged `rules/project/*.md` placed in the source
   repo before task 12 would load into every new session, duplicating content. Pinned by task 8's
   check that the staging path is outside the repo.
2. **Hook registrations after the install.** `settings.json` must end with each hook (git-guard,
   measure-gate, sentry-read-gate, session-context) registered **exactly once**. Pinned by task
   12's count check.
3. **A runner brief whose `run_dir` is relative, outside `repo_root`, or lacks `repo_root`** must
   come back `BLOCKED` with no folder created. Pinned by task 7's Brief C.
4. **A "writes files" command in a variant spelling** (extra spaces, trailing args:
   `yarn  lint src/`) must still be refused. The runner matches on the command's first two
   whitespace-separated words against the flagged list. Pinned by task 7's Brief B.
5. **`session-context.sh` in a repo with no manifest, or with a deleted installed file**, must still
   print its line and exit 0 (fail-open), just without drift fields. Pinned by task 6's tests.

---

## Phase 1: core (this repo, branch `feat/runner-agent`)

### Task 1: project.md template: "writes files" flag and lint recipe

**Files:**
- Modify: `project-template/project.md` (§ Commands)
- Test: `core/scripts/harness-check.sh` (new section `== 5d. Runner ==`, created here and extended
  by tasks 2–4)

**Interfaces:**
- **Produces:** § Commands gains a fourth column, `Writes files`, holding `yes` or `no`.
  - A `yes` row's command is what the runner refuses (task 3).
  - The Lint row's notes hold the report-only recipe: `<lint> -f json -o <run_dir>/eslint.json`,
    then `node .claude/scripts/eslint-summary.js <run_dir>/eslint.json <changed paths…>`.
  - A new optional row, `Lint on request only | yes/no`, lets an adopter turn off unprompted runner
    lint (default `no`).

- [ ] **Step 1: Write the failing check.** In the new §5d, assert:
  - `project-template/project.md` contains a table header line matching `| Purpose | Command | Notes | Writes files |`
  - it contains the literal `eslint-summary.js`
- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh | grep -E 'FAIL|5d'`. Expected: 2 FAIL lines in §5d.
- [ ] **Step 3: Edit the template:**
  - add the column (`no` on every existing row)
  - put the recipe in the Lint row's notes
  - add the `Lint on request only` row
- [ ] **Step 4: Run the check again.** Expected: §5d PASS, `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** paths `project-template/project.md core/scripts/harness-check.sh`,
  message `feat(template): writes-files flag and report-only lint recipe`.

### Task 2: `eslint-summary.js` (optional ESLint helper)

**Files:**
- Create: `core/scripts/eslint-summary.js`, ported from the source repo's tested version unchanged,
  except that its JSDoc names no project
- Test: `core/scripts/harness-check.sh` §5d

**Interfaces:**
- **CLI:** `node eslint-summary.js <eslint.json> [changed-path ...]`. Exit 0 when a summary is
  printed, 64 on bad usage, 65 on an unreadable report.
- **Output lines, one fact per line, in this order:**
  - `TOTAL errors=<n> warnings=<n> files=<n> files_with_errors=<n> fatal=<n>`
  - up to 10 `RULE <id> errors=<n> warnings=<n>`, then `RULE_MORE <n>`
  - up to 30 `ERROR_FILE <path> errors=<n>`, then `ERROR_FILE_MORE <n>`
  - for each changed file: `CHANGED <path> errors=<n> warnings=<n>`, followed by its
    `CHANGED_ERROR <path>:<line>:<col> <rule> <message>` lines
  - `CHANGED_NOT_LINTED <arg>` for each argument that matched no linted file
- **Paths:** repo-relative, using `ROOT = path.resolve(__dirname, '../..')`. That resolves to the
  repo root both in this repo (`core/scripts/`) and when installed (`.claude/scripts/`).
- **`matchesChanged(relPath, arg)`:** exact path, or a directory prefix on a `/` boundary.
  - `./x`, absolute paths and trailing slashes normalise to the same form.
  - The repo root itself, or anything outside the repo, never matches.

- [ ] **Step 1: Write the failing checks.** Port the source repo's §5d fixture block verbatim: two
  synthetic files, changed args `src/a.ts src/nope.ts`.
  - Expect these lines:
    - `TOTAL errors=3 warnings=1 files=2 files_with_errors=2 fatal=1`
    - `RULE no-unused-vars errors=2 warnings=0`
    - `RULE (parse error) errors=1 warnings=0`
    - `ERROR_FILE src/b.ts errors=2`
    - `CHANGED src/a.ts errors=1 warnings=1`
    - `CHANGED_ERROR src/a.ts:3:5 no-unused-vars x unused`
    - `CHANGED_NOT_LINTED src/nope.ts`
  - Also expect no `CHANGED src/b.ts`, no warning among the `CHANGED_ERROR` lines, exit 64 on no
    arguments, and exit 65 on `{not json`.
  - Add the five `matchesChanged` edge cases as a `node -e` check:
    - `./src/a.ts` → true
    - `src/c/` matching `src/c/x.ts` → true
    - `src/a` vs `src/ab.ts` → false
    - `.` → false
    - `../other/src/a.ts` → false
- [ ] **Step 2: Run harness-check.** Expected: §5d FAILs, because the script is missing.
- [ ] **Step 3: Create the script** (`chmod +x`).
- [ ] **Step 4: Run harness-check.** Expected: `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** message `feat(scripts): eslint-summary.js for report-only lint`.

### Task 3: `core/agents/runner.md`

**Files:**
- Create: `core/agents/runner.md`, based on the source repo's tested `agents/runner.md`
  (2026-10-19, after its wrapper and no-Grep fixes)
- Test: `core/scripts/harness-check.sh` §5d

**Interfaces:**
- **Frontmatter:** `name: runner`, `model: claude-haiku-5-5`, `tools: Bash, Read, Grep, Glob`. The
  description names `delegation.md`.
- **Brief fields:**
  - `repo_root` (absolute, **required**)
  - `run_dir` (absolute, must start with `<repo_root>/.claude/runs/runner/`)
  - `steps[] {n, cmd, allowed_exit=[0], timeout_s=120 (max 600), report?}`
  - `checks[] {name, step, pattern, expect}`
  - `approval?`
  - `continue_on_error=false`
- **Wrapper (fixed text),** with `cd '<repo_root>'` replacing the source repo's hardcoded path:
  ```bash
  mkdir -p '<run_dir>' && cd '<repo_root>' && { s=$EPOCHREALTIME; ( <cmd> ) > '<run_dir>/step-<n>.log' 2>&1; rc=$?; echo "exit=$rc duration_s=$(awk -v a="$s" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.2f", b-a}') lines=$(wc -l < '<run_dir>/step-<n>.log')"; [ "$rc" -eq 0 ] || tail -n 20 '<run_dir>/step-<n>.log'; }
  ```
- **Pre-flight (before any step runs):**
  - Read `<repo_root>/.claude/project.md` § Commands and collect every `Writes files = yes`
    command.
  - A step is refused if its first two whitespace-separated words equal a flagged command's first
    two words, or if it contains `--fix` or `--write`.
  - Plus the generic list: `git add -A`, `git add .`, `git commit -a`, `git stash` without paths,
    `git clean`, `git reset --hard`, `rm -rf` outside `run_dir` and the build output folder named
    in `project.md`, and `git push` without a matching `approval`.
  - No `project.md`, or no § Commands: the generic list only, and say so in `block_reason` notes.
- **Status block:** as in the source version, plus `repo_root:`. Status is `DONE | FAILED | BLOCKED`.
  Check verdicts are `pass | fail | unchecked`.
- **Provenance:** decisions are dated, not attributed ("(2026-10-19)").

- [ ] **Step 1: Write the failing checks** in §5d:
  - the file exists, and its model is `claude-haiku-5-5`
  - it has Bash and Read
  - it has no Write, Edit, Agent or NotebookEdit, and no `*`
  - it contains each of: `verbatim`, `--fix`, `repo_root`, `Writes files`, `approval`,
    `Never count`, `EPOCHREALTIME`, `Never depend on it`
  - its description contains `delegation.md`
- [ ] **Step 2: Run harness-check.** Expected: §5d FAILs, because the file is missing.
- [ ] **Step 3: Write `core/agents/runner.md`.**
- [ ] **Step 4: Run harness-check and leak-check.** Expected: `ALL GREEN`, and `clean`.
- [ ] **Step 5: Commit (owner):** message `feat(agents): runner, a verbatim command runner on haiku`.

### Task 4: core rules: delegation, autonomy, CLAUDE.md

**Files:**
- Modify: `core/rules/delegation.md`, `core/rules/autonomy.md`, `core/CLAUDE.md`
- Test: `core/scripts/harness-check.sh` §5d

**Interfaces:**
- **`delegation.md`:**
  - **title:** "Delegating lookups and commands to the Haiku agents"
  - **table:** a `| … | \`runner\` | … |` row, with the same wording as the source repo
  - **"Judgement goes in the brief, or the job isn't the runner's"** bullet
  - **`## Runner briefs` section:** brief shape incl. `repo_root`; the lint recipe pointing at
    `project.md` § Commands; reading results back; big-log checks as their own
    `grep -m1 -E` step
  - **gotchas:**
    - rules auto-load recursively into sessions and subagents
    - `paths:` frontmatter defers loading
    - a new agent file is picked up mid-session, an edit is not
    - Grep can be absent at runtime
    - `$CLAUDE_PROJECT_DIR` is unset in Bash
    - fixed dispatch cost (~87k tokens in a repo whose rules total ~45k)
- **`autonomy.md`:** the lint line becomes "don't run lint inline". Exception: report-only lint
  through the runner may run unprompted, unless `project.md` sets `Lint on request only: yes`.
- **`CLAUDE.md`:**
  - replace "They are **not** auto-loaded…" with: every `rules/**/*.md` loads at session start and
    into every subagent; a rule with `paths:` frontmatter loads when a matching file is touched
  - add: project-owned rules go in `rules/project/`, which the installer never touches
  - index the runner in the delegation line and in the agents table

- [ ] **Step 1: Write the failing checks** in §5d:
  - delegation.md contains ``| `runner` |`` and `## Runner briefs`
  - autonomy.md contains `through the \`runner\` agent` and `Lint on request only`
  - CLAUDE.md contains `rules/project/` and `paths:`
  - CLAUDE.md does **not** contain `not** auto-loaded`
- [ ] **Step 2: Run harness-check.** Expected: 7 FAILs in §5d.
- [ ] **Step 3: Edit the three files.**
- [ ] **Step 4: Run harness-check and leak-check.** Expected: `ALL GREEN`, and `clean`.
- [ ] **Step 5: Commit (owner):** message `docs(rules): runner delegation, report-only lint, rules auto-load`.

### Task 5: harness-check runs a project's own checks

**Files:**
- Modify: `core/scripts/harness-check.sh` (new final section `== 9. Project checks ==`, before
  the summary)
- Test: same file (self-test in a temp dir)

**Interfaces:**
- **Location:** `$H/project/checks.sh` (= `<repo>/.claude/project/checks.sh` when installed).
- **Contract:**
  - if absent: print `  SKIP  no project/checks.sh`
  - if present: run it with `bash`, with `ROOT` and `H` exported, and indent its stdout
  - its own `FAIL` lines count toward `FAILS`
  - a non-zero exit with no `FAIL` line adds one `FAIL  project/checks.sh exited <n>`
- **Function:** `run_project_checks <script-path>`, which sets `FAILS`.

- [ ] **Step 1: Write the failing self-test.** Create two temp scripts. One echoes
  `  PASS  x` and exits 0; the other echoes `  FAIL  y` and exits 1. Call `run_project_checks` on
  each in a subshell and capture the `FAILS` delta: expected 0 and 1.
- [ ] **Step 2: Run it.** Expected: FAIL (function undefined).
- [ ] **Step 3: Implement `run_project_checks`** and the §9 call.
- [ ] **Step 4: Run harness-check.** Expected: `SKIP  no project/checks.sh` in this repo, and
  `ALL GREEN`.
- [ ] **Step 5: Commit (owner):** message `feat(harness-check): run a project's own checks.sh`.

### Task 6: drift visibility: manifest source line and session-context drift count

**Files:**
- Modify: `install.sh` (`write_manifest`; `--doctor` prints the source line)
- Modify: `core/hooks/session-context.sh`
- Modify: `core/rules/working-style.md` (where harness files live)
- Test: `core/scripts/harness-check.sh` (§5d)

**Interfaces:**
- **The manifest's line 3 becomes `source <absolute path of this repo>`.**
  - `--update` rewrites it.
  - Readers that skip header lines must now skip 3: the `awk 'NR>2'` calls become `NR>3`, and a
    pre-existing 2-line header must still parse. Detect it by whether line 3 starts with `source `.
- **`session-context.sh` appends to its `[harness]` line:**
  - ` | harness_edited=<n> | harness_source=<path>`, when `.claude/.harness-manifest` exists
  - `<n>` = installed files whose sha256 differs from the manifest
  - **missing manifest:** the fields are omitted
  - **missing installed file:** it doesn't count as edited, and no error
  - **always exits 0**
- **`working-style.md`:** harness edits are made in the source named by the manifest's `source`
  line, then applied with `install.sh --update`. Editing an installed file is drift, and the
  session line shows it.

- [ ] **Step 1: Write the failing checks.** In a `mktemp -d` git repo:
  1. Run `bash install.sh <tmp>`. Assert line 3 of `<tmp>/.claude/.harness-manifest` matches
     `^source /`.
  2. Run `CLAUDE_PROJECT_DIR=<tmp> bash <tmp>/.claude/hooks/session-context.sh`. Assert it
     contains `harness_edited=0`.
  3. Append a line to `<tmp>/.claude/rules/git.md` and rerun. Assert `harness_edited=1`.
  4. `rm` the manifest and rerun. Assert exit 0 and no `harness_edited`.
  5. With the manifest restored, delete an installed file and rerun. Assert exit 0.
  6. Run `install.sh --doctor <tmp>` against a hand-made 2-line-header manifest. Assert no parse
     error.
- [ ] **Step 2: Run them.** Expected: FAILs.
- [ ] **Step 3: Implement** the `install.sh` and `session-context.sh` changes. Edit `working-style.md`.
- [ ] **Step 4: Run harness-check and leak-check.** Expected: `ALL GREEN`, and `clean`.
- [ ] **Step 5: Commit (owner):** message `feat(install): record harness source; session line reports drift`.

### Task 7: phase 1 acceptance in a fresh session

**Files:** none (verification only). Results go to `$HOME/harness-adoption/phase1-acceptance.md`.

- [ ] **Step 1: Install into a scratch repo.**
  1. `mktemp -d` a fresh git repo.
  2. `bash install.sh <tmp>`.
  3. Fill its `project.md` § Commands with one flagged row: `Lint | yarn lint | … | yes`.
  4. Run its `harness-check`. Expected: `ALL GREEN`.
- [ ] **Step 2: Run three refusal briefs**, each via
  `cd <tmp> && claude -p --model claude-haiku-5-5 --allowedTools=Agent "Dispatch the runner agent with this brief: …; reply with its status block only"`.
  1. **Brief A:**
     - steps `git status --porcelain`, `yarn lint`, then an unapproved push to `main`
     - expected: `status: BLOCKED`, every step `not_run` or `refused`, and no `<run_dir>` on disk
  2. **Brief B:**
     - steps `git status --porcelain`, `yarn  lint src/` (double space, trailing arg)
     - expected: `BLOCKED`, and no `<run_dir>`
  3. **Brief C:**
     - `run_dir` = `/tmp/elsewhere`, valid steps
     - expected: `BLOCKED` with `malformed brief`, and `/tmp/elsewhere` not created
- [ ] **Step 3: Record** each status block and the on-disk checks in `phase1-acceptance.md`.
  Any mismatch reopens task 3.

## Phase 2: prepare the source repo (staging only; the live `.claude/` stays untouched)

### Task 8: staging tree and the source repo's `project.md`

**Files:**
- Create: `$HOME/harness-adoption/staging/.claude/project.md`, from `project-template/project.md`

**Interfaces:**
- **Values come from the source repo's live `.claude/CLAUDE.md`, root `CLAUDE.md` and
  `rules/git.md`:**
  - owner
  - stack pins (framework, React, Node, package manager, TypeScript)
  - commands: build, dev, tests = `none`, codegen
  - lint row:
    - `npx eslint . -f json -o <run_dir>/eslint.json`, `Writes files: no`
    - the project's auto-fix lint and format scripts listed separately with `Writes files: yes`
  - dev server URL, ports, and certificate bypass
  - shared branches and promotion flow
  - ticket key and wiki
  - external systems: error tracker = yes, session replay = yes, log search = yes
  - review checklist additions (the repo's numbered performance gates)
  - QA fixtures
- **JSON block:**
  - `shared_branches` copied from the live git-guard
  - `measurement_lock`: `.claude/runs/MEASUREMENT-IN-PROGRESS.md`

- [ ] **Step 1: Write the staging-location check** into `$HOME/harness-adoption/check-staging.sh`:
  - `realpath` of the staging dir does not start with `realpath` of the source repo
  - `project.md` has no `TODO` left
- [ ] **Step 2: Fill in `project.md`.**
- [ ] **Step 3: Run `check-staging.sh`.** Expected: exit 0.

### Task 9: residue triage

**Files:**
- Create: `$HOME/harness-adoption/triage/<group>.md`, one per group:
  - `agents`
  - `rules`
  - `entry` (CLAUDE.md, commands, templates)
  - `infra` (hooks, scripts, settings)

**Interfaces:**
- **Input per file:** `diff core/<f> <source>/.claude/<f>`, over the 33 installed-core files that
  differ.
- **Output: one table row per hunk:**
  `| file | hunk (live line range) | class | destination | note |`
  - `class` is one of `fact`, `knowledge`, `generic`, `personal`
  - `destination` is a `project.md` § name, a `rules/project/<file>.md`, `core:<file>`, or `drop`
- **Dispatch:** one Sonnet general-purpose agent per group, read-only. The main session reviews
  every `generic` and every `drop` row before accepting.

- [ ] **Step 1: Dispatch** the four agents with the input/output contract above. Each brief
  includes the design doc's four-way classification verbatim.
- [ ] **Step 2: Review the tables.** A `drop` that loses a measured fact or a dated decision becomes
  `knowledge`.
- [ ] **Step 3: Coverage check.** Every differing file appears in some table with ≥1 row (a script
  counts the files with rows against the 33).

### Task 10: build `rules/project/` and `project/checks.sh` in staging

**Files:**
- Create: `$HOME/harness-adoption/staging/.claude/rules/project/*.md`:
  - `overview.md`, from the storefront part of the live `.claude/CLAUDE.md`
  - one file per `knowledge` destination
  - the six storefront-only rules, moved in: toolchain, performance, external-systems,
    mcp-roster, perf-testing, and the triage stub
- Create: `$HOME/harness-adoption/staging/.claude/project/checks.sh`:
  - the live harness-check's measure-gate matrix (§2b)
  - the storefront doc-drift greps
  - the `eslint-summary` real-repo smoke (optional)
- **Staged unchanged, at their current paths:** the measure-gate hook, the perf scripts, the
  storefront templates, and the triage skill.

**Interfaces:**
- **Links:** relative links between moved files are rewritten for their new depth
  (`../rules/x.md` → `../x.md`, etc.).
- **No core file may link to any `rules/project/` file.**

- [ ] **Step 1: Write the link check** into `check-staging.sh`: every relative `](…)` link in the
  staging tree resolves against the union of staging and `core/`. Expected now: FAIL (files absent).
- [ ] **Step 2: Build the files** from task 9's tables.
- [ ] **Step 3: Run `check-staging.sh`.** Expected: exit 0.
- [ ] **Step 4: Run the staged `project/checks.sh`** against a scratch install (task 7's repo with the
  staged files copied in). Expected: all PASS.

### Task 11: upstream `generic` hunks, then re-run acceptance

**Files:** whatever `core:<file>` rows task 9 produced.

- [ ] **Step 1: Apply each accepted `generic` hunk** to the core file, de-personalised.
- [ ] **Step 2: Run harness-check and leak-check.** Expected: `ALL GREEN`, and `clean`.
- [ ] **Step 3: Re-run task 7** in full. Expected: the same results.
- [ ] **Step 4: Owner commits, merges `feat/runner-agent` into `main`, and decides whether to push.**
  Task 12 installs exactly that `main` commit.

## Phase 3: switch-over (source repo)

### Task 12: swap, verify, measure

**Files:** the source repo's `.claude/` (untracked); `$HOME/harness-adoption/switchover.md` (log).

- [ ] **Step 1: Lock and notify.** Write the lock file per the source repo's multi-session rule, and
  message peer sessions: hooks are changing; don't start sessions until "machine free".
- [ ] **Step 2: Measure before.**
  `claude -p --output-format json "reply OK"` in the source repo. Record
  `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` as **startup_tokens_before**.
- [ ] **Step 3: Back up:**
  `cp -a <source>/.claude $HOME/harness-adoption/backup-<UTC timestamp>`, plus a
  `tar czf` of the same. Verify with `diff -rq` (no output).
- [ ] **Step 4: Move the core-path files aside:** every path `install.sh`'s `core_files` lists that
  exists in the live `.claude/` moves to `$HOME/harness-adoption/moved-aside/`, keeping its
  structure.
- [ ] **Step 5: Install and add the project files:**
  1. `bash <harness>/install.sh <source>`. Expected: no conflicts, `installed <n> files`.
  2. Copy the staging tree over `<source>/.claude/`.
  3. Remove the six moved storefront rules from the live `rules/`, since they're now in `rules/project/`.
- [ ] **Step 6: Verify:**
  - `install.sh --doctor`: `manifest: all installed files match`, and no `edited locally`
  - `harness-check`: `ALL GREEN` (its §9 runs `project/checks.sh`)
  - the `settings.json` hook count: each of the four hook commands appears exactly once
    (`node -e` count)
- [ ] **Step 7: Measure after:** the same command as step 2 gives **startup_tokens_after**. Record
  the delta in `switchover.md`. A change over ±10% is a finding to raise with the owner before
  step 8, not a pass.
- [ ] **Step 8: Fresh-session acceptance** in the source repo:
  - task 7's Brief A
  - a real-lint brief per `project.md`'s recipe, which must return `DONE`, with the `TOTAL` line
    copied and equal to an independent recount of `eslint.json`
- [ ] **Step 9: Release the lock**, and message "machine free".
- [ ] **Rollback (only if steps 5–8 fail):**
  1. `rm -rf <source>/.claude`
  2. `cp -a $HOME/harness-adoption/backup-<ts> <source>/.claude`
  3. Re-run the live harness-check.
  4. Release the lock.

### Task 13: record the new arrangement

**Files:**
- The owner's memory notes for the source repo (outside both repos): the harness-repo note, and the
  rules-auto-load note
- The source repo's `rules/project/overview.md` (pointer to the harness source)

- [ ] **Step 1: Update the harness-repo memory note.** Since 2026-10-19 this repo is the source of
  truth, and the source repo runs an installed core. That replaces "copy only, keep both".
- [ ] **Step 2: Check a fresh session's `[harness]` line** in the source repo. It must show
  `harness_edited=0` and the `harness_source=` path.

## Not in this plan

- **Phase 5 (load budget):** a separate design and plan, written from task 12's
  `startup_tokens_before/after`.
  - Candidates: research-workflow, external-systems, performance, mcp-roster, toolchain,
    code-review, agent-skills, perf-testing (~18k tokens in the source repo).
