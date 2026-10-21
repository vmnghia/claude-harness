# Lock gate: measurement locks that protect themselves

Status: approved by the owner, 2026-10-21.

## Intent

When one session measures (builds, Lighthouse, local prod A/B), `rules/multi-session.md` has it
write a lock file and **message every peer session**, then message them again with "machine free".
Those messages are expensive:

- A message to an idle peer always starts a turn, and that turn re-reads the peer's whole context.
- Past the 1-hour prompt-cache TTL, that is a cold re-cache.
- A peer's idle time can't be seen from outside, so the sender can't tell a warm peer from a cold one.

This change makes the lock **enforce itself**, so idle peers never need waking.

## Measured facts (2026-10-21; scratch repo and peer transcripts)

| Fact | Evidence |
|---|---|
| A cross-session message to an idle peer triggers a turn that re-reads its context. First notice after long idle: `cache_create` 120,601 / 246,839 / 486,969 tokens | peer transcripts: the first assistant turn after each notice |
| Warm wake-ups (4–44 min idle) still re-read 121k–288k tokens from cache | the same transcripts |
| `ListAgents` shows `idle`/`busy` and "started X ago" (the session's start), never last activity. No peer→transcript mapping is exposed (no open file, no session-id env var) | ListAgents output; `/proc/<pid>/fd` and `environ` |
| PreToolUse and SessionStart hooks receive `session_id`. A **subagent's** tool call carries its parent's `session_id`, plus its own `agent_id` | hook log probe |
| A PreToolUse `permissionDecision: "ask"` prompts the user in an interactive session. In a non-interactive one (`claude -p`) the command doesn't run, even with Bash in `--allowedTools` | `ask` probe: no marker file written |

## Decisions (owner, 2026-10-21)

- **Never message an `idle` peer** for routine lock notices. Only `busy` peers get a message. They
  are mid-work, their cache is warm, and they could collide right now.
- **No "machine free" messages.** Deleting the lock is the release.
- **A new PreToolUse hook on Bash, `lock-gate.sh`,** returns `ask` when all three hold:
  - a lock file exists
  - the command is heavy
  - the caller's `session_id` differs from the lock's owner
- **The ask prompt quotes** the owner, what is being measured, the expected end, and whether the
  lock is stale.
- **The owner's own subagents pass,** because they share its `session_id`.
- **A non-interactive caller is effectively refused,** because `ask` can't be answered there.
- **The session-start line shows each session its own id.** `session-context.sh` prints
  `session=<id>`, so the owner can write it into the lock. It also prints any active lock: owner,
  expected end, stale or not.

## Builder's calls (veto-able)

- **Heavy commands** come from `project.md`'s json block, key `heavy_commands`: a list of regexes
  matched against the command string.
  - The default, when the key is absent, mirrors the old DON'T list: builds, dev/start servers,
    package installs, Lighthouse and harness-check.
  - The project lists its own perf scripts.
- **Lock file format:** the existing prose file, plus three machine-read lines anywhere in it:
  - `owner_session: <session id>`
  - `owner_name: <ListAgents name>`
  - `expected_end: <ISO-8601 with offset>`
  - A lock without `owner_session` is treated as **foreign to everyone**, so even its writer gets
    the ask. That's the safe default for hand-written locks.
- **Stale** means `now > expected_end + 1 h` (the old rule's grace). A stale lock still asks, but
  the prompt says "stale".
- **The lock path** stays `project.md` `measurement_lock`, with default
  `.claude/runs/MEASUREMENT-IN-PROGRESS.md`.

## Goals / non-goals / anti-goals

- **Goal:** a peer that is idle while a lock is taken pays **zero** tokens for it, and still can't
  run a heavy command by accident when it wakes.
- **Goal:** the gate's decision matrix is tested in `harness-check`, as git-guard's is.
- **Non-goal:** detecting peers' idle time. It's unobservable, and this design makes it unnecessary.
- **Anti-goal:** the gate blocking the lock's owner, or its own subagents (the runner, measurement
  agents).
- **Anti-goal:** the gate silently allowing a heavy command in a non-interactive caller during a
  foreign lock.
- **Anti-goal:** a hook crash blocking all Bash. Like git-guard, it fails open (allow) on malformed
  input or a missing lock.

## Rule changes (`core/rules/multi-session.md`)

- **§1:** still run `ListAgents` before shared work, but message only `busy` peers.
- **§3:**
  - the lock carries `owner_session`, `owner_name` and `expected_end`
  - the holder writes its own id from the `session=` line
  - no peer messaging on create or release, except `busy` peers on create
  - the gate replaces "peers read it before heavy work"
- **§6:** drop "machine free"; add "never wake an idle peer for a notice".
- **§7:** release = delete the lock.

## Constraints

- **Core change,** made in this repo on a branch. `harness-check` and `leak-check` stay green, and
  the owner commits. It reaches the source repo via `install.sh --update`, which also merges the
  hook registration into `settings.json`.
- **The source repo's update runs under its own lock,** written in the new format. The gate's first
  real use is its own rollout.

## Builder-check resolutions (2026-10-21)

A fresh builder raised six gaps. Two were settled by measurement; the rest are **builder's calls**,
open to the owner's veto.

1. **Does `ask` hold in every permission mode?** Measured with `claude -p --permission-mode <m>`:
   - the gated command did **not** run in `default`, `acceptEdits`, `auto` or `bypassPermissions`
   - the hook receives `permission_mode`, and the ask text names it
   - the interactive prompt itself can't be driven from `-p`, so acceptance includes **one manual
     check by the owner** in their normal mode
   - No deny fallback is needed.
2. **Is `session_id` stable?**
   - **Measured:** `--resume` keeps the same id, and SessionStart fires with `source: resume` and that
     id.
   - **Unmeasured:** `/clear` and compaction, which can't be driven non-interactively. So owner
     identity is made **recoverable** rather than assumed stable:
     - `session-context.sh` prints `session=<id>` on **every** SessionStart source
     - the gate's ask text includes the caller's current id: "if you hold this lock, set
       `owner_session: <id>`"
3. **The source repo's own heavy scripts are in scope** for the rollout.
   - Its `project.md`, which is project-owned, gains a `heavy_commands` list: the defaults plus
     `lh-run.sh`, `build-local.sh`, `start-prod.sh`, `arm.sh` and `f4073-ab-session*.sh`.
   - `install.sh` never touches `project.md`, so the rollout writes it.
4. **Matching:** regexes run against the **whole command string**.
   - False asks (e.g. a commit message mentioning `yarn build`) cost one prompt, and only during a
     foreign lock.
   - Misses would defeat the gate. That's the same trade git-guard's loose match makes.
5. **Scope: Bash only,** as approved. The MCP `lighthouse_audit` tool and the shared chrome-devtools
   profile are not gated. That's a recorded non-goal and a candidate follow-up.
6. **A missing or unparseable `expected_end`:** the gate asks, with the label "end unknown", and
   never counts the lock as stale.

## Left to the builder

- The exact default `heavy_commands` regexes.
- The ask-prompt wording.
- How `session-context.sh` formats the lock line.
