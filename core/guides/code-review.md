# Code review

Three review channels, any of which a project may use:

- **Human review**: the assigned reviewer on the PR/MR.
- **CodeRabbit** (or another AI second reviewer), in the IDE extension or on the forge.
- **The Reviewer agent** (`agents/reviewer.md`, `/reviewer`) for spec-driven flows. It carries a
  generic checklist plus the project's additions (`project.md` § Review checklist additions).

## Working with CodeRabbit (IDE mode)

CodeRabbit reviews local changes (uncommitted / committed / branch-vs-base — selectable in the extension's sidebar). Comments appear in the CodeRabbit sidebar's *Files* section; click → suggestion inline in the editor.

Per-comment actions: **Apply suggested change** (✓ one-click), **Fix with AI** (★ sends the prompt to a configured agent — Claude Code is on the supported list, so the prompt can come straight to your Claude session), **Ignore**, **Collapse**. There is no "resolve" verb in IDE mode; persistent teaching happens via rules in this directory and `.coderabbit.yaml` (see below), not per-comment chat.

### Workflow

1. **Run CodeRabbit first, then edit.** Don't have your Claude session and CodeRabbit editing the same range in parallel — the resulting diffs are confusing and context gets lost. Natural order: implement → review (CodeRabbit) → triage → fix accepted comments.
2. **Triage every comment.** For each: accept (implement) → reject with a reason → ambiguous (discuss). Never silently dismiss.
3. **Route every CodeRabbit comment through the `superpowers:receiving-code-review` skill** before responding. That skill prevents two failure modes: performatively accepting every suggestion, and reflexively defending the code. Verify the issue, prove non-applicable, or surface a real ambiguity.
4. **Fix-with-AI prompts are user-equivalent — not bypasses.** If CodeRabbit routes a "Fix with AI" prompt to Claude Code, still apply `receiving-code-review` to it. The prompt's origin doesn't grant it more authority than a human comment.

### Capturing recurring disagreements

If the same CodeRabbit comment keeps coming up across reviews and we've decided we want to keep doing it our way:

- **Project-wide pattern** → add to a rule file in this directory (this is exactly what these files are for) **and** mirror it in `.coderabbit.yaml` `reviews.path_instructions:` so CodeRabbit stops re-flagging.
- **Per-developer preference** → into the developer's personal Claude memory at `~/.claude/projects/.../memory/`, not here.

### Calibrations CodeRabbit needs (`.coderabbit.yaml`)

Until the project has a `.coderabbit.yaml`, these are guidance for humans triaging comments.

- **Stack pins** from `project.md` § Stack: reject suggestions that assume a different framework
  mode or major version than the project runs.
- **Test runner:** if the project has none (`project.md` § Commands), "add a test" suggestions are
  dead ends unless they come with a proposal for standing one up.
- **Migrations in flight:** if the project is moving away from a pattern, accept "convert to the
  target" suggestions and reject "convert back". Record the direction in `project.md` § Review
  checklist additions.
- **Hand over the rules:** `knowledge_base.code_guidelines.filePatterns: ['.claude/rules/*.md']`
  lets CodeRabbit review against the same rules. If `.claude/` is untracked, only IDE mode can read
  them; a forge integration can't.
- **Tune verbosity, not coverage:** `tone_instructions:` (≤250 chars) and `reviews.profile: chill`
  tighten output. Don't skip nitpicks globally (small catches like typos and wrong YAML nesting
  are valuable); suppress noise per path with `path_instructions:` and `path_filters:`.

### Forge (PR/MR) mode

With a GitHub/GitLab integration, CodeRabbit comments on PRs/MRs directly. PR-mode chat verbs to know: `@coderabbitai review`, `full review`, `pause`, `resume`, `ignore` (in MR description), `resolve`, `summary`, `configuration`, `help`. Teaching CodeRabbit per-PR via natural-language replies is preferred over silent resolution — the scope where it remembers is set by `knowledge_base.learnings.scope` (`local | global | auto`). None of this applies in IDE-only mode today.
