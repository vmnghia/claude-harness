# Autonomy boundaries

Default ask-first. Trust will expand as work proves out.

## OK without asking
- Read-only investigation (reading files, grepping, browsing tickets/docs).
- Edits to obviously-non-sensitive files.
- Running build/format/codegen.

## Ask first
- Creating branches, pushing, opening or merging PRs.
- Deleting files.
- Touching auth, payments, data integrity, prod, or shared infrastructure.
- Any action whose blast radius isn't obvious.
- **Any write through an MCP to a forge, issue tracker, wiki or chat** (e.g. GitLab/GitHub, Jira, Confluence, Slack): draft it in chat, hand it to the owner for a
  review pass, and post only on their explicit instruction. Covers GitLab comments / reviews / MR edits / merges /
  branches / commits / work items; Jira issues, comments, edits, transitions, links, worklogs; Confluence pages
  and comments (create, update, delete, restore); Slack messages, scheduled messages, canvases, reactions and
  Slack-side drafts. Reads stay free. An instruction covers the write it names, not later ones.
  CI/CD tools (pipelines, jobs, artifacts) are off limits even for reads unless `project.md` says otherwise; if
  asked to use them, confirm first.
  **One exception (2026-10-15):** `research-lead` may create or update Confluence **drafts**
  (unpublished), and only to the target its run's framing names in a Decisions row. Its own frontmatter hook
  (`confluence-draft-gate.sh`) denies anything else. The draft in Confluence takes the place of the chat
  draft, and the owner publishes it themselves. See [research-workflow.md](./research-workflow.md).

Sensitivity overrides category — if a "default-OK" action lands near a high-risk surface, ask anyway.

## Don't do unprompted
- **Don't run the project's lint command** as a post-task verification step. The owner runs lint themselves (commit hooks, IDE, or their own pass). Lint runs can be slow and surface pre-existing noise unrelated to your change. The build and a type-check are still fair game for confirming an edit compiles — different concern.

## Mechanical guardrails (hooks)

`.claude/hooks/git-guard.sh` denies dangerous git operations (pushes
from/to shared branches, plain `--force`, commits on shared branches,
`--no-verify`) at the tool layer. A git-guard denial is **policy, not an
error** — do not retry, rephrase, or work around it; surface it and let
the owner decide. Its push check matches shared-branch names **anywhere in the command
string** ("loose match by design"), so keep a push alone in its own command: on
2026-10-02 a push of a feature branch was denied because a ledger `echo` in the same
command contained the word `stable`. The no-auto-lint rule above applies to subagents too (Coder
runs the build, and tests when the project has a runner — not lint).
