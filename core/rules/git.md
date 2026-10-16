# Git: commits, branches, pushing

The project's own branch flow, naming pattern and commit style are in
[`project.md`](../project.md) § Branches and promotion; where it differs from the defaults below,
it wins.

## Commits

Default: [Conventional Commits](https://www.conventionalcommits.org/):
`<type>[optional scope]: <description>`. Description lowercase, imperative, no trailing period
(proper nouns and filenames keep their case). Body/footer optional, after a blank line. Breaking
changes: `!` after type/scope, or a `BREAKING CHANGE:` footer.

- **Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- **Scope:** prefer one when it's specific.
  - The **ticket key** when the change belongs to a ticket: `feat(ABC-123): add countdown end event`.
  - A **sub-task** scopes to its **parent** and puts its own key at the end:
    `fix(ABC-120): guard autocomplete against missing input [ABC-123]`.
  - A **topic scope** for tooling changes with no ticket: `chore(claude): add quote gate`. Never a
    vague scope like `(misc)`.

## Branches

`<type>/<slug>`, with the commit types above.

- With a ticket: `<type>/ABC-123-short-summary`. Without: `<type>/short-summary`.
- Lowercase kebab-case summary, at most ~5 words; detail belongs in the PR/MR description.
- One ticket per branch. A branch that grows to span tickets gets split.
- Prefer `git switch` / `git restore` over `git checkout` in commands and snippets.
- **Create a feature branch without tracking its base** when the base is a shared branch:
  `git switch -c <branch> --no-track origin/<base>`, then `git push -u origin <branch>`. A tracked
  base makes a bare `git push` target the shared branch. Confirm with `git branch -vv` before any
  push.

## Pushing

- **Never push on your own.** Every push needs the owner's explicit approval, and an approval
  covers one push, not the session or another branch.
- **Never push to a shared branch** (`project.md` `shared_branches`), not even with casual
  approval. Never force-push one; if it seems needed, surface the situation and let the owner
  drive the recovery. `hooks/git-guard.sh` enforces this.
- Merges into shared branches happen through the forge (PR/MR), not from an agent.

### Diverged branches

Before proposing `--force-with-lease` on a branch that diverged from its remote, diagnose:

1. **`git reflog show <branch>`**: rebase/amend/reset entries show a local rewrite. Local-only;
   absent from fresh clones.
2. **`git range-diff <remote>...<local>`**, commit by commit:
   - `=` identical patch on a different parent (a rebase)
   - `!` near-identical (context shifted)
   - `>` only on the local side
   - `<` only on the remote side: **would be lost** by a force-push

Decision: many `=`, zero `<` → `git push --force-with-lease origin <branch>` is safe. Any `<` →
stop and ask the owner. Unclear → stop and ask. Always `--force-with-lease`, never `--force`: it
aborts if the remote moved since your last fetch.

## Deploy-time traps

A project's CI may have hazards that no git rule can see (e.g. two environments sharing one image
tag, so a staging build silently replaces production's). Record any such trap in `project.md`
§ Branches and promotion, with the check to run before a deploy, rollback or redeploy.
