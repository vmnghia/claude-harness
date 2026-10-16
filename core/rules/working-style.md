# Working style

## File layout

- **Whether `.claude/` is tracked is the project's choice** (`project.md` § Branches and
  promotion). Tracked: harness changes are team-visible and go through review. Untracked: every
  developer installs their own copy, and changes never reach teammates unless shared some other
  way.
- **Never `git add -f` an ignored harness.** Untracked content survives every `git switch`;
  tracked content is deleted the moment you switch to a branch that doesn't track it. A file that
  is tracked on one branch and ignored on another disappears on switch, and has done so in
  practice.
- `.claude/CLAUDE.md` is the harness entry point: an index of rules, agents and hooks. Don't bloat
  it with detailed rules; add or extend a file under [`rules/`](.) instead. Project facts go in
  `.claude/project.md`.
- `.mcp.json` lives at the repo root (Claude Code only discovers it there): the one exception to
  "everything Claude-related lives under `.claude/`".
- `.claude/settings.local.json` is per-developer.
- Per-developer Claude memory (`~/.claude/projects/.../memory/`) is never committed. Personal
  preferences go there; anything team-relevant goes under `.claude/rules/`.

## Diffs and reviews
- Explain reasoning alongside changes; keep diffs small and reviewable.
- Cadence: in-session diffs as work progresses, end-of-task summary, PR-per-change preferred when feasible.
- Branch decisions: ask before creating a branch for non-trivial work. Naming follows [git.md](./git.md).

## Capturing decisions
Non-trivial decisions go in the PR description, plus a one-or-two-line pointer in the relevant rule file (or a new file under `.claude/rules/`) if the decision sets a precedent worth remembering.
