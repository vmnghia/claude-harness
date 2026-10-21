---
load: always
---
# Plugin skills — when to use what

Stance on Claude Code plugin skills that are installed but not obvious whether to invoke. Use these defaults; situational skills not listed here are fine to invoke when they clearly fit.

## superpowers:*

The `superpowers:*` plugin ships ~15 skills. The harness will nudge me to invoke them frequently; treat the nudging as a default I can override.

### Mandatory
- **`superpowers:brainstorming`** — invoke before any non-trivial feature, refactor, or behavior change. Explore intent, constraints, and design **before** writing code. Talking through approach first beats discovering after the fact that the diff went the wrong way.

### Conditional
- **`superpowers:test-driven-development`** — applicable **only when
  the project has a test runner** (`project.md` § Commands; the session hook's `tests=`).
  Without one, treat TDD as N/A ([verification.md](./verification.md)): don't force the loop,
  and don't propose it as the plan.

### Already covered elsewhere — don't double up
- **`superpowers:verification-before-completion`** → use [verification.md](./verification.md) (chrome-devtools MCP for UI, browser repro for bug fixes). That file is canonical.
- **`superpowers:receiving-code-review`** → required by [guides/code-review.md](../guides/code-review.md) for every CodeRabbit comment.

### Situational (no rule needed)
Invoke when the task obviously fits; no project-level mandate:
`systematic-debugging`, `executing-plans`, `subagent-driven-development`, `writing-plans`, `dispatching-parallel-agents`, `using-git-worktrees`, `requesting-code-review`, `finishing-a-development-branch`, `writing-skills`.

## claude-md-management:*

For maintaining CLAUDE.md and the rule files in this directory.
- **`claude-md-management:claude-md-improver`** — invoke when auditing CLAUDE.md health, after structural changes to commands / architecture, or when adding new rule files. Scans, evaluates quality, applies targeted updates.
- **`claude-md-management:revise-claude-md`** — invoke at session-end to capture learnings back into CLAUDE.md (new commands, new conventions). Not for transient session state — that belongs in personal memory at `~/.claude/projects/.../memory/`.

## feature-dev:feature-dev

Guided feature development workflow: codebase exploration → architecture proposal → implementation plan. Invoke for non-trivial features that need design before code. Pairs naturally with `superpowers:brainstorming` (brainstorm intent → feature-dev plans the implementation).

Skip for small fixes or single-file edits — the overhead isn't worth it.
