# Lock gate: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a measurement lock that enforces itself through a PreToolUse `ask` gate, so no idle
peer session ever has to be woken by a message.

**Architecture:**
- A new hook, `core/hooks/lock-gate.sh`, reads the PreToolUse JSON and the lock file. It answers
  `ask` for heavy commands from non-owner sessions.
- `session-context.sh` tells every session its own id and shows any active lock.
- The rule text in `multi-session.md` switches from messaging to the gate.
- It is rolled out to the source repo under a lock in the new format, which is the gate's first
  real use.

**Tech stack:** bash, Node ≥18 (for JSON and ISO-date parsing), Claude Code PreToolUse and
SessionStart hooks.

**Spec:** [2026-10-21-lock-gate-design.md](./2026-10-21-lock-gate-design.md), including its
"Builder-check resolutions".

## Global Constraints

- **Hook output for an ask:** stdout
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"<text>"}}`,
  exit 0. Allow = exit 0 with no output.
- **Fail open:** malformed stdin, no lock file, or a node error → allow.
- **Lock path:** `project.md` json `measurement_lock`, default `.claude/runs/MEASUREMENT-IN-PROGRESS.md`,
  relative to `$CLAUDE_PROJECT_DIR`.
- **Lock fields** (machine-read lines anywhere in the file, leading/trailing spaces and `\r`
  trimmed): `owner_session: <id>`, `owner_name: <name>`, `expected_end: <ISO-8601 with offset or Z>`.
- **Owner:** the caller's `session_id` equals `owner_session`. Subagents carry the parent's
  `session_id`, so they're the owner too. No `owner_session` means nobody is the owner.
- **Stale:** `now > expected_end + 1 h`. A missing or unparseable `expected_end` reads "end
  unknown", never stale.
- **Heavy:**
  - `project.md` json `heavy_commands` (an array of regexes, matched against the **whole command
    string**) replaces the default when present.
  - Default:
    `["\\b(yarn|npm|pnpm)( run)? (build|dev|start|install|ci)\\b", "\\bnext (build|dev|start)\\b", "\\blighthouse\\b", "harness-check\\.sh"]`.
  - An invalid regex entry is skipped, with a warning on stderr.
- **The ask reason names:**
  - the owner name
  - what's measured (the lock file's first `- **What:**` line, if any)
  - the expected end, or "end unknown", plus "STALE" when stale
  - the caller's `permission_mode`
  - "if you hold this lock, set `owner_session: <caller id>`"
- **Scope:** Bash only.
- **Repo rules:** `leak-check` stays clean, the owner commits, work happens on branch
  `feat/lock-gate`, and files quoting git commands are written with the Write tool.

## Review Focus

1. **The owner's own commands during its own lock,** including its subagents (`agent_id` set),
   are never asked. Pinned by Task 1 cases c and d.
2. **An `owner_session` line with trailing spaces or CRLF** must still match. Pinned by Task 1
   case l.
3. **An invalid regex in `heavy_commands`** must not crash the hook into a block; the other
   entries still apply. Pinned by Task 1 case m.
4. **`expected_end` with a `+07:00` offset versus `Z`** must give the right stale verdict. Pinned
   by Task 1 cases g and n.
5. **A peer that wakes after the lock is gone** gets no prompt and no stale state. Pinned by
   Task 1 case a, and by Task 4's probe after release.

---

### Task 1: `core/hooks/lock-gate.sh` and its matrix

**Files:**
- Create: `core/hooks/lock-gate.sh` (bash wrapper; the decision logic is in inline `node`)
- Modify: `core/scripts/harness-check.sh` (new section `== 2e. lock-gate matrix ==` after §2d,
  plus the hook-integrity entry in §1)

**Interfaces:**
- **Consumes:** `core/hooks/lib/project-config.js <key>` for `measurement_lock` and
  `heavy_commands`.
- **Produces:** stdin = PreToolUse JSON `{session_id, agent_id?, permission_mode, tool_input:{command}}`.
  Output and exit as in Global Constraints.

- [ ] **Step 1: Write the matrix.**
  - Sandbox: a `mktemp -d` project with `.claude/project.md` (json block configurable) and a lock
    file written per case.
  - `lg <expect: allow|ask> <label> <session_id> <agent_id> <command>`: pipe the JSON to the hook
    with `CLAUDE_PROJECT_DIR` set. `allow` means exit 0 and empty stdout. `ask` means stdout parses
    with `permissionDecision == "ask"`.

  | Case | Setup | Command | Expect |
  |---|---|---|---|
  | a | no lock | `yarn build` | allow |
  | b | lock, owner X | `ls -la` | allow |
  | c | lock, owner X, caller X | `yarn build` | allow |
  | d | lock, owner X, caller X, `agent_id` set | `yarn build` | allow |
  | e | lock, owner X, caller Y | `yarn build` | ask; reason contains the owner name, the end, and `owner_session: Y` |
  | f | lock with no `owner_session`, caller X | `yarn build` | ask |
  | g | `expected_end` = now − 2 h, in `Z` | `yarn build` | ask; reason contains `STALE` |
  | h | no `expected_end` line | `yarn build` | ask; reason contains `end unknown`, not `STALE` |
  | i | stdin `{not json` | — | allow |
  | j | `heavy_commands: ["my-perf\\.sh"]` | `bash my-perf.sh` → ask; `yarn build` → allow (the key replaces the default) | |
  | k | foreign lock | `git commit -m "yarn build fix"` | ask (the documented whole-string trade) |
  | l | `owner_session: X  \r` (trailing spaces + CR), caller X | `yarn build` | allow |
  | m | `heavy_commands: ["(bad", "yarn build"]`, foreign lock | `yarn build` | ask, with no crash |
  | n | `expected_end` = now + 30 min, as `+07:00` local time | `yarn build` | ask; reason has no `STALE` |

- [ ] **Step 2: Run** `bash core/scripts/harness-check.sh`. Expected: §2e FAILs, because the hook
  is missing.
- [ ] **Step 3: Implement** `core/hooks/lock-gate.sh` (`chmod +x`). The bash part reads stdin and
  calls node. Any node error exits 0, so a crash allows.
- [ ] **Step 4: Run the suite.** Expected: `ALL GREEN`. Also run `leak-check`.

### Task 2: registration, template key, session-start line

**Files:**
- Modify: `core/settings.json`: append `"$CLAUDE_PROJECT_DIR"/.claude/hooks/lock-gate.sh` to the
  existing `Bash` PreToolUse group, after git-guard.
- Modify: `project-template/project.md`: add `heavy_commands` to the json block (omitted = default),
  with a bullet explaining it.
- Modify: `core/hooks/session-context.sh`:
  - read stdin JSON for `session_id`; it now receives it
  - append ` | session=<id>`
  - when a lock exists, append ` | lock=<owner_name|unknown> until <expected_end|end unknown>[ STALE][ (yours)]`
- Test: `core/scripts/harness-check.sh`, next to the session-context drift tests

**Interfaces:**
- **Produces:** the `[harness]` line fields `session=` and `lock=`.

- [ ] **Step 1: Write the failing tests:**
  1. `core/settings.json` registers `lock-gate.sh` in the Bash group.
  2. The template json has `heavy_commands`.
  3. The session-context hook, given stdin `{"session_id":"abc","source":"startup"}`, prints
     `session=abc`. With a lock whose `owner_session: abc` and `owner_name: n`, it prints `lock=n`
     and `(yours)`. With no lock, it prints no `lock=`.
  4. With stdin empty or malformed, it still prints its line and exits 0.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the suite.** Expected: `ALL GREEN`; `leak-check` clean.

### Task 3: rule text (`core/rules/multi-session.md`)

**Files:**
- Modify: `core/rules/multi-session.md` §1, §3, §6, §7
- Modify: `core/CLAUDE.md`, the Hooks table row for `lock-gate.sh`
- Test: `core/scripts/harness-check.sh`

**Interfaces:**
- **Produces, rule text:**
  - **§1:** message **only `busy` peers**; never wake an `idle` one for a notice, with the measured
    cold-wake cost cited
  - **§3:**
    - the lock carries `owner_session` (copied from the holder's own `session=` line),
      `owner_name` and `expected_end`
    - `lock-gate.sh` asks non-owners before heavy commands
    - a resumed or cleared session re-checks its `session=` and rewrites `owner_session` if it
      changed
  - **§6 / §7:** no "machine free" messages; release = delete the lock

- [ ] **Step 1: Write the failing token checks.**
  - multi-session.md contains `owner_session`, `busy`, `lock-gate.sh` and `expected_end`.
  - It does **not** contain an instruction to send `machine free`. Test: no line matching
    `messages? .*machine free` outside a "no longer" sentence.
  - CLAUDE.md's Hooks table names `lock-gate.sh`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Edit both files.**
- [ ] **Step 4: Run the suite.** Expected: `ALL GREEN`; `leak-check` clean.

### Task 4: acceptance in a scratch install (fresh sessions)

- [ ] **Step 1:** `bash install.sh --update $HOME/harness-adoption/phase1/scratch`. Expected:
  `lock-gate.sh` is installed, and `settings.json` registers it (1 registration added). The
  scratch `harness-check` is `ALL GREEN`.
- [ ] **Step 2: Foreign lock.** Write a lock with `owner_session: someone-else` and
  `expected_end` = now + 30 min. Run
  `claude -p --model claude-haiku-5-5 --allowedTools=Bash "Run: yarn build --version > ran-marker"`.
  Expected: `ran-marker` absent, and the reply quotes the lock reason.
- [ ] **Step 3: Owner path.**
  - Run `claude -p` asking the session to: read its own `session=` value from the session-start
    context, write it into the lock's `owner_session:` line, then run the same command.
  - Expected: the marker exists. The owner isn't asked, so the id round trip works.
- [ ] **Step 4: Release.** Delete the lock and run the step-2 command again. Expected: the marker
  exists, with no prompt.
- [ ] **Step 5: Owner commits and merges** `feat/lock-gate` into `main`.

### Task 5: rollout to the source repo (under the new lock)

- [ ] **Step 1: Write the lock in the new format.**
  - `owner_session` = this session's id (its transcript file name).
  - `owner_name`, and `expected_end` = now + 45 min.
  - Message only peers that `ListAgents` shows as `busy`, and record who was skipped as idle.
- [ ] **Step 2:** `bash <harness>/install.sh --update <source-repo>`. Expected: `lock-gate.sh`
  installed, 1 hook registration added.
- [ ] **Step 3:** add `heavy_commands` to the source repo's `project.md`:
  - the defaults
  - `lh-run\\.sh`, `build-local\\.sh`, `start-prod\\.sh`, `/arm\\.sh`, `f4073-ab-session`
- [ ] **Step 4:** run `install.sh --doctor` and `harness-check`. Expected: `ALL GREEN`.
- [ ] **Step 5: The gate's first real use.** While the lock is held, run a fresh `claude -p` (a
  different session id) and ask it to run `bash .claude/scripts/perf/lh-run.sh --help`. Expected:
  not run, with the lock reason quoted.
- [ ] **Step 6: Release** by deleting the lock. No "machine free" messages.
- [ ] **Step 7: Manual check by the owner, in two interactive modes:** **default** and **auto**
  (sessions here run in auto mode).
  - During a test lock held by another id, try `yarn build --version` in each mode.
  - Expected: the ask prompt appears in both. An auto-mode classifier must not answer it.
  - Record both results in the design's measured facts. `claude -p` can't show this, because an
    ask can never be answered there (2026-10-21 review, I4).
