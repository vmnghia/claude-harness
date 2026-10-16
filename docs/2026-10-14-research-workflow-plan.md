# Research Workflow Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the seven-agent research team a written contract (`rules/research-workflow.md`), an entry point (`/research`), and a harness-check section that fails when an agent drifts from it.

**Architecture:** The contract is a rule file mirroring `rules/ai-workflow.md`'s shape. `/research` is a thin command wrapper that runs research-lead's "Framing" section inline, then dispatches research-lead as a subagent. The lint is a new §5b in `scripts/harness-check.sh`, written first so every later task turns one of its checks green.

**Tech Stack:** Markdown rule/agent/command files under `.claude/`; bash + grep/sed in `harness-check.sh`. No Node, no Jest.

**Spec:** `.claude/specs/2026-10-14-research-workflow-design.md` (approved 2026-10-14). Read it alongside this plan; Task 2 copies its sections A–D.

## Global Constraints

- Everything is under `.claude/`, which is untracked (`*.claude` in `.gitignore`): **no `git add`, no commits.** The "commit" step of each task is replaced by a harness-check run.
- Don't run `yarn lint`, `yarn build` or `yarn dev` (autonomy.md; a peer session may be serving from the main tree).
- Commands hold no procedure: "commands select the execution locus; agent files hold the procedure" (`ai-workflow.md`).
- Model pins, verbatim: research-lead `claude-opus-5-5`, incident-investigator `claude-opus-5-5`, designer `claude-opus-5-5`, writer `claude-opus-5-5`, searcher `claude-haiku-5-5`, web-reader `claude-sonnet-5-5`, repro-driver `claude-sonnet-5-5`.
- Every STUB banner stays. research-lead stays "do not dispatch" until its procedure is written (work item #1).
- `bash .claude/scripts/harness-check.sh` must end `ALL GREEN` (exit 0) after every task from Task 2 on.

## Review Focus

1. **Resume after the session that ran the lead has ended.** The lead's agent id no longer resolves, so SendMessage fails. Expected: `/research` stops and tells the owner, and does **not** silently start a fresh lead (that would re-derive everything and reset counters). Pinned in Task 5.
2. **A second `/research` run on the same day with the same slug.** Expected: a new folder with a `-2` suffix, never writing into the existing run's `findings.md`. Pinned in Task 5.
3. **A missing agent file, or one whose `tools:` line can't be parsed.** Expected: the lint **fails**. The trap: an absent tool list makes every "must not have X" check pass. Pinned in Task 1.
4. **`/research` with no arguments.** Expected: stop with a usage line, create nothing. Pinned in Task 5.
5. **`--max-iter` that isn't a positive integer.** Expected: warn and use the default 3. Pinned in Task 5.

---

### Task 1: harness-check §5b — research contract linter

**Files:**
- Modify: `.claude/scripts/harness-check.sh`: insert a new section between the end of section 5 (the line `  ok "retired field 'lint_result' fully gone"` and its closing `fi`) and `echo "== 6. Spec/plan pair naming =="`.

**Interfaces:**
- Consumes: `$ROOT`, `$WF` (= `$ROOT/.claude/rules/ai-workflow.md`, defined in section 5), `ok`, `fail`, `check` (top of the script).
- Produces: env override `HC_AGENTS_DIR` (default `$ROOT/.claude/agents`), used by Task 6.

- [ ] **Step 1: Run the check to record the baseline**

Run: `bash .claude/scripts/harness-check.sh | tail -1`
Expected: `harness-check: ALL GREEN`

- [ ] **Step 2: Insert §5b**

```bash
echo "== 5b. Research contract linter (agent files ↔ research-workflow.md) =="
RW="$ROOT/.claude/rules/research-workflow.md"
AG="${HC_AGENTS_DIR:-$ROOT/.claude/agents}"
check "rules/research-workflow.md exists" test -f "$RW"
check "ai-workflow.md points to research-workflow.md" grep -q "research-workflow.md" "$WF"

is_stub()  { grep -q '^> \*\*STUB (' "$1"; }
tools_of() { sed -n 's/^tools: //p' "$1" | head -1; }
model_of() { sed -n 's/^model: //p' "$1" | head -1; }
has_tool() { tools_of "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -qx "$2"; }

RESEARCH_AGENTS="research-lead incident-investigator repro-driver searcher web-reader designer writer"
for a in $RESEARCH_AGENTS; do
  f="$AG/$a.md"
  if [ ! -f "$f" ]; then fail "$a.md missing"; continue; fi
  if [ -z "$(tools_of "$f")" ]; then fail "$a.md has no single-line 'tools:' frontmatter"; fi
done

rtok() { # rtok <token> <agent> — contract token must appear in both files; stubs skip
  local f="$AG/$2.md"
  [ -f "$f" ] || return 0   # missing file already failed above
  if is_stub "$f"; then echo "  SKIP  (stub) '$1' in $2.md"; return 0; fi
  if grep -q "$1" "$RW" && grep -q "$1" "$f"; then ok "'$1' in research-workflow.md + $2.md"
  else fail "'$1' missing from research-workflow.md or $2.md"; fi
}
rtok "AWAITING_CAPTURE" research-lead
rtok "DIAGNOSED" incident-investigator
rtok "REPRODUCED" repro-driver
rtok "FOUND" searcher
rtok "GATHERED" web-reader
rtok "CANVAS_READY" designer
rtok "COPY_READY" writer
rtok "positive_control" searcher
rtok "positive_control" repro-driver

for a in research-lead incident-investigator; do
  for t in Agent Write Edit; do
    [ -f "$AG/$a.md" ] && { has_tool "$AG/$a.md" "$t" && ok "$a has $t" || fail "$a lacks $t"; }
  done
done
for a in repro-driver searcher web-reader designer writer; do
  for t in Agent Write Edit; do
    [ -f "$AG/$a.md" ] && { has_tool "$AG/$a.md" "$t" && fail "$a must not have $t" || ok "$a has no $t"; }
  done
done
for a in searcher writer web-reader; do
  [ -f "$AG/$a.md" ] && { has_tool "$AG/$a.md" Bash && fail "$a must not have Bash" || ok "$a has no Bash"; }
done

for pin in research-lead:claude-opus-5-5 incident-investigator:claude-opus-5-5 designer:claude-opus-5-5 \
           writer:claude-opus-5-5 searcher:claude-haiku-5-5 web-reader:claude-sonnet-5-5 repro-driver:claude-sonnet-5-5; do
  a="${pin%%:*}"; m="${pin#*:}"
  [ -f "$AG/$a.md" ] && { [ "$(model_of "$AG/$a.md")" = "$m" ] && ok "$a model $m" || fail "$a model is '$(model_of "$AG/$a.md")', expected $m"; }
done
```

- [ ] **Step 3: Run it and confirm the expected failures**

Run: `bash .claude/scripts/harness-check.sh | grep -E 'FAIL|SKIP|5b'`
Expected, exactly these FAIL lines (later tasks clear them):
- `FAIL  rules/research-workflow.md exists` (Task 2)
- `FAIL  ai-workflow.md points to research-workflow.md` (Task 3)
- `FAIL  research-lead lacks Agent`, `… lacks Write`, `… lacks Edit` (Task 4)

plus 9 `SKIP  (stub)` lines. Every other §5b line is PASS.

- [ ] **Step 4: Pin Review Focus #3 (missing file / unparseable tools fail, not pass)**

```bash
NEG="$CLAUDE_SCRATCH/agents-rf3"   # use the session scratchpad
rm -rf "$NEG" && cp -r .claude/agents "$NEG"
rm "$NEG/writer.md"
sed -i 's/^tools: .*/tools:/' "$NEG/searcher.md"
HC_AGENTS_DIR="$NEG" bash .claude/scripts/harness-check.sh | grep -E 'writer.md missing|searcher.md has no single-line'
rm -rf "$NEG"
```
Expected: both lines print as `FAIL`. (`$CLAUDE_SCRATCH` = this session's scratchpad directory; substitute the literal path.)

---

### Task 2: `rules/research-workflow.md`

**Files:**
- Create: `.claude/rules/research-workflow.md`

**Interfaces:**
- Consumes: spec sections A, B, C, D.
- Produces: the status tokens Task 1's `rtok` greps for (`AWAITING_CAPTURE`, `DIAGNOSED`, `REPRODUCED`, `FOUND`, `GATHERED`, `CANVAS_READY`, `COPY_READY`, `positive_control`), all present in spec section B.

- [ ] **Step 1: Write the file header**

```markdown
# Research workflow — shared contract for the research team

Single source of truth for how the research team runs: who dispatches whom, what each agent
returns, and how a run moves through human-run captures. Counterpart of
[ai-workflow.md](./ai-workflow.md), which covers the feature flow; this file reuses its
status-block frame and context capsule. Design and decisions:
[2026-10-14 research-workflow design](../specs/2026-10-14-research-workflow-design.md).

Every agent here also follows [research-discipline.md](./research-discipline.md) and writes
into an investigation folder shaped by
[templates/findings-template.md](../templates/findings-template.md).

Agents: `research-lead`, `incident-investigator`, `repro-driver`, `searcher`, `web-reader`,
`designer`, `writer`. Entry point: `/research`.
```

- [ ] **Step 2: Append the spec's sections A–D verbatim**

Copy from `.claude/specs/2026-10-14-research-workflow-design.md`, unchanged and in order, the four sections from `## A. Flow and roles` through the end of `## D. Tool boundaries and lint` (stop before `## Deliverables`). Rename the headings to drop the letter prefixes:
`## A. Flow and roles` → `## Flow and roles`, `## B. Status blocks` → `## Status blocks`, `## C. Dispatch, iteration, routing` → `## Dispatch, iteration, routing`, `## D. Tool boundaries and lint` → `## Tool boundaries and lint`.

- [ ] **Step 3: Append the open item**

```markdown
## Open

- **Late reports** (deferred 2026-10-14): what happens to a teammate report that
  arrives after its dispatcher ended its turn is untested. Until it is, the rule in
  "Dispatch, iteration, routing" item 1 stands as written.
```

- [ ] **Step 4: Verify**

Run: `bash .claude/scripts/harness-check.sh | grep -E 'FAIL'`
Expected: `rules/research-workflow.md exists` no longer listed; the pointer and three research-lead lines remain.

Run: `grep -c -E 'AWAITING_CAPTURE|DIAGNOSED|CANVAS_READY|COPY_READY|positive_control' .claude/rules/research-workflow.md`
Expected: a number ≥ 5.

---

### Task 3: pointer in `ai-workflow.md` + index entry

**Files:**
- Modify: `.claude/rules/ai-workflow.md`: after the line `Four agents; Planner is **dual-entry**, the other three are subagents only.`
- Modify: `.claude/CLAUDE.md`: after the line beginning `- [ai-workflow.md](./rules/ai-workflow.md)`

**Interfaces:**
- Consumes: `rules/research-workflow.md` (Task 2).
- Produces: the pointer Task 1's check greps for.

- [ ] **Step 1: Add the pointer to `ai-workflow.md`**

Insert after the "Four agents" line:

```markdown

The seven-agent **research team** (`/research`) has its own contract:
[research-workflow.md](./research-workflow.md).
```

- [ ] **Step 2: Add the index entry to `.claude/CLAUDE.md`**

Insert after the `ai-workflow.md` bullet:

```markdown
- [research-workflow.md](./rules/research-workflow.md) — research team contract: `/research` frames inline then dispatches `research-lead`, which alone dispatches its teammates (investigator → `repro-driver` is the one nested dispatch); status blocks per agent, `AWAITING_CAPTURE` + resume for human-run captures, iteration caps, tool boundaries; linted by harness-check §5b
```

- [ ] **Step 3: Verify**

Run: `bash .claude/scripts/harness-check.sh | grep -E 'FAIL'`
Expected: only the three `research-lead lacks …` lines remain.

---

### Task 4: research-lead frontmatter and section skeleton

**Files:**
- Modify: `.claude/agents/research-lead.md`: the `tools:` line, and the body after `## Role`.

**Interfaces:**
- Consumes: the tool table in `research-workflow.md`.
- Produces: the section names `## Framing` and `## Running the team`, which Task 5's command references.

- [ ] **Step 1: Replace the tools line**

`tools: Read, Grep, Glob` → `tools: Read, Grep, Glob, Write, Edit, Bash, Agent`

- [ ] **Step 2: Update the banner's first sentence**

`> **STUB (2026-10-14).** Role and model are decided; procedure, tool list and` → `> **STUB (2026-10-14).** Role, model, tools and contract are decided; procedure and`
and on the next line `> output contract are not.` → `> output are not.` (keep the rest of the banner).

- [ ] **Step 3: Add the boundaries and the two section headings**

Insert after the `## Role` bullets, before `## To fill`:

```markdown
## Boundaries

- Contract: [research-workflow.md](../rules/research-workflow.md). You are the only dispatcher
  of the team (except incident-investigator → repro-driver) and the only writer of
  `findings.md` and `run-log.md`.
- `Write`/`Edit`: only `findings.md` and `run-log.md` in this run's investigation folder.
- `Bash`: read-only git (`git log`, `git show`, `git rev-list`) for research-discipline.md §2
  and §5. Nothing else.
- `Agent`: only the six research teammates.

## Framing

Runs **inline in the main session** via `/research` (may ask the owner). Procedure: to be written
(work item #1).

## Running the team

Runs as a **subagent** dispatched by `/research` with the framing and a context capsule.
Procedure: to be written (work item #1).
```

- [ ] **Step 4: Verify**

Run: `bash .claude/scripts/harness-check.sh | tail -1`
Expected: `harness-check: ALL GREEN`

---

### Task 5: `/research` command

**Files:**
- Create: `.claude/commands/research.md`

**Interfaces:**
- Consumes: `agents/research-lead.md` sections `## Framing` and `## Running the team` (Task 4); `rules/research-workflow.md` (Task 2); `templates/findings-template.md`.
- Produces: the `/research` slash command (available from the next session start).

- [ ] **Step 1: Write the command**

```markdown
---
description: Research team — frame a question with the owner inline, then the research-lead subagent runs the team and writes findings.md
argument-hint: <question | FRONT-XXXX> [--max-iter=N] | --resume <investigation-folder>
---

Contract: [`.claude/rules/research-workflow.md`](../rules/research-workflow.md). This command
only selects where each phase runs; the procedure lives in
[`.claude/agents/research-lead.md`](../agents/research-lead.md).

## Input

Raw arguments: `$ARGUMENTS`.

- First, if `.claude/agents/research-lead.md` still contains the line starting `> **STUB (`,
  stop. Reply only: `research-lead is still a stub (procedure not written, work item #1); /research can't run yet.` Create nothing.
- Empty → stop. Reply only: `Usage: /research <question | FRONT-XXXX> [--max-iter=N] | --resume <investigation-folder>`. Create nothing.
- `--max-iter=N` → N must be a positive integer; otherwise warn `--max-iter ignored, using 3` and use 3. Default 3.
- `--resume <folder>` → go to **Resume**.

## New run

1. **Folder.** `.claude/investigations/YYYY-MM-DD-<slug>/` (date from session context; slug from
   the Jira key or the question, kebab-case, ≤ 5 words). If that folder exists, append `-2`,
   `-3`, … — never write into an existing run's folder.
2. **Frame.** Execute research-lead.md § "Framing" **inline in this session**. It creates
   `findings.md` from the template (frontmatter, question, dispatch plan).
3. **Dispatch.** Agent tool, `subagent_type: "research-lead"`, with: the folder path, the
   framing, `--max-iter`, and a context capsule (`ai-workflow.md` template). Then create
   `run-log.md` in the folder whose first line is `lead_agent_id: <id from the Agent result>`.
4. **Wait.** Do not end this turn while the lead is outstanding. Never read its transcript file.
5. **Report.** Show the owner the lead's final status block, then `findings.md`'s Answer and Next.
   On `AWAITING_CAPTURE`, also show the `capture_path` and say: "paste results into
   `results.txt`, then run `/research --resume <folder>`".

## Resume

1. Read `lead_agent_id` from `<folder>/run-log.md`.
2. SendMessage to that id: "Captures pasted into results.txt; continue."
3. If the send fails (the session that ran the lead has ended), **stop** and tell the owner that the
   lead can't be resumed from this session. Do **not** start a fresh lead for an existing run;
   the owner decides what happens next.
4. Otherwise continue from **New run** step 4.
```

- [ ] **Step 2: Pin Review Focus #1, #2, #4, #5 (the command states each behaviour)**

Run:
```bash
f=.claude/commands/research.md
grep -q 'Do \*\*not\*\* start a fresh lead' $f && grep -q 'append `-2`' $f \
 && grep -q '^- Empty → stop' $f && grep -q 'using 3' $f && grep -q 'research-lead is still a stub' $f && echo RF-OK
```
Expected: `RF-OK`

- [ ] **Step 3: Verify**

Run: `bash .claude/scripts/harness-check.sh | tail -1`
Expected: `harness-check: ALL GREEN`

---

### Task 6: negative check of §5b

**Files:** none modified (scratchpad copy only).

**Interfaces:**
- Consumes: `HC_AGENTS_DIR` (Task 1).

- [ ] **Step 1: Break a copy and run the lint against it**

```bash
NEG="$CLAUDE_SCRATCH/agents-neg"   # substitute the session scratchpad path
rm -rf "$NEG" && cp -r .claude/agents "$NEG"
sed -i 's/^tools: Read, Grep, Glob$/tools: Read, Grep, Glob, Bash/' "$NEG/searcher.md"
sed -i 's/^model: claude-sonnet-5-5$/model: claude-opus-5-5/' "$NEG/web-reader.md"
HC_AGENTS_DIR="$NEG" bash .claude/scripts/harness-check.sh | grep -E 'FAIL'
```
Expected, both:
- `FAIL  searcher must not have Bash`
- `FAIL  web-reader model is 'claude-opus-5-5', expected claude-sonnet-5-5`

- [ ] **Step 2: Clean up and confirm the real tree is untouched**

```bash
rm -rf "$NEG"
bash .claude/scripts/harness-check.sh | tail -1
```
Expected: `harness-check: ALL GREEN`
