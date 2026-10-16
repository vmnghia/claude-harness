# Agent skills

Notes for working with the open agent-skills ecosystem (`npx skills …`, [skills.sh](https://skills.sh/)) in this repo.

## Running the CLI

The `skills` CLI needs Node ≥18:

```bash
npx -p skills@latest -- skills find <query>
```

## Installing skills

```bash
npx -p skills@latest -- skills add <owner/repo> \
  --skill <skill-name> --agent claude-code --copy -y
```

- `--copy` writes a real file under `.claude/skills/` instead of a symlink into a `.agents/`
  store, so the skill survives if that store is cleaned.
- If `.claude/` is untracked in this project, an installed skill is per-developer: it never
  reaches teammates through git ([working-style.md](./working-style.md#file-layout)).
- An install can drop a `skills-lock.json` at the repo root, which may be tracked. Committing it
  is a team-visible change: coordinate first, don't let it ride along in a feature PR.

## Invoking `find-skills` on capability questions

When the user asks "can you do X" / "do you support X" / "how do I do X" / "is there a skill for X" / "find a skill for X" — invoke `find-skills` **before** answering from training data.

Sequence: invoke `find-skills` → if a relevant skill exists, present it; if not, fall back to a general-knowledge answer with an explicit "no installed skill for this" note. Don't double up — if a skill is already obviously applicable (e.g. chrome-devtools for browser verification, frontend-design for UI building), just use it directly. `find-skills` is for *discovery*, not duplication.

For meta questions like "what skills do I have?" — still invoke `find-skills`; it answers authoritatively.

## When recommending skills

The point of a recommendation is to filter signal from noise. Generic top-results dumps aren't useful. When asked to find skills:

1. **Run several targeted searches in parallel** over the project's distinct domains, not a single broad query.
2. **Cross-check results against skills already loaded in the session** before recommending. Don't suggest duplicates of skills that are already available.
3. **Call out project-specific fit caveats** against `project.md` § Stack: a skill written for a different framework mode, major version, hosting platform or test setup may not apply (e.g. App-Router skills in a Pages-Router project). Say which caveat rules a skill out.
4. **Present as a structured comparison** — group by "already installed / worth installing / probably skip" with install counts and one-line fit justification. Reputable sources (`vercel-labs`, `anthropics`, `getsentry`, `addyosmani`) carry more weight than unknown authors with low install counts.
