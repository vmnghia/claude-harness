# Adversarial review: two hunters, a debate, a judge

Status: approved by the owner, 2026-10-22.

## Intent

`/reviewer` checks a diff against a spec, the rules and a checklist. The owner's lead reviews
the same diffs on GitLab and keeps finding things that pass that check: a failed load that
overwrites good state, an interval that overflows into a 1 ms loop, a backoff computed from the
wrong timestamp, a component that is also mounted on a page nobody thought about. None of those
are checklist items. They come from simulating the change under adverse conditions and chasing
each break to its blast radius.

This design adds a second kind of review to the harness: **two hunters** try to break the diff
independently, **debate** each other's findings until every one is agreed, withdrawn, refuted
or reduced to a question only the owner can answer, and a **fix loop** sends Coder in on what
survived, then fresh hunters again. The spec is not an input. Most of the diffs that got
reviewed on GitLab never had one, and the owner's specs never reach anyone else.

The council-style restructuring of `/feature-flow` that the owner also wants is a **separate
project**, brainstormed after this one. This command is built so it can later slot in as that
flow's review stage.

## Evidence (GitLab, 2026-10-08 to 2026-10-20, read 2026-10-22)

Lead comments on the owner's MRs in two projects: the storefront app ("default": !711, !717, !722,
!723) and its publishing worker ("worker": !42, !48, !52). Every substantive finding falls in one
of these buckets.
The hunter playbook (§ Playbook) is this table.

| Bucket | Example the previous review missed | MR |
|---|---|---|
| Error path turns destructive | Failed cursor load still marked the cursor dirty, so the saver overwrote the good S3 cursor with the live baseline. A 403 from a missing `ListBucket` took the same path | worker !48 [1], [7] |
| Limits, units and zero of config values | Interval above 2^31-1 ms makes Node fire every 1 ms. No minimum, so `MEMORY_HEARTBEAT_MS=60` logs 1.4 M lines/day. Heartbeat `0` silently disabled the separate GC probe | worker !42 |
| Time and ordering | Backoff from tick start, not failure time, so the first step never happened. Oldest-first sort plus early stop after one failed wave starved every healthy id behind it. The fix for that created a new loop through the fan-out path, caught on re-review | worker !48 [2], [4], [11] |
| Guard conflates error with legitimate state | The empty-manifest guard also blocked a real delete-all, and persisted the stale ids | worker !48 [5] |
| Consumers and surroundings outside the diff | `ProductImages` is also mounted on the thank-you page, so PDP events leaked to upsell. `$NODE_OPTIONS` now appends, so an out-of-repo `common-config` could change the heap limit. A CI revert took effect on the very release it shipped in | default !711, worker !42, default !722 |
| Claims the code does not keep | A comment said the function prevents starvation and it did the opposite. A GC pause estimate assumed a 1 GB heap while the MR investigated multi-GB heaps. Dev tests at 3 s polling never exercised prd's 30 s idle-socket condition | worker !48, !42, !52 |
| Unbounded repeated I/O | Stores watcher marked the cursor dirty every tick, so a multi-MB PUT every 30 s | worker !48 [6] |
| Scope | The countdown fix touched a shared hook with no behaviour change; the lead asked for the diff to shrink | default !717 |

The lead's finding shape, which the hunters copy: severity marker, **file and line**, the
**trigger** (input and state), the **consequence**, a **suggestion**; a summary comment with a
**staging test plan**; and on the next revision a per-finding re-check (✅ or a new finding).

## Decisions (owner, 2026-10-22)

- **Two hunters, one agent file.** `agents/adversarial-reviewer.md`, dispatched twice per round,
  fresh, parallel, no shared context.
- **No spec.** Input is a diff plus optional free-text context (a ticket key, a sentence).
- **Hunt, then debate.** Each hunter cross-examines the other's findings, re-reading the code,
  then both answer the critique. The debate continues **until every disputed finding is
  resolved**; a turn count never ends it.
- **Stalemate ladder.** Hunters may run throwaway code in the session scratchpad to prove a
  claim. A finding neither side can settle goes to a **fresh judge** that re-reads the code
  with both final positions. The hunters then try to refute the judge. Only what survives all
  of that is raised to the owner.
- **Fix loop.** AGREED blocker/major findings go to Coder; then two fresh hunters review the
  result. Bounded by an iteration cap and a circuit breaker.
- **Nothing unresolved is auto-fixed.** ESCALATED and STALEMATE items go to the owner with both
  positions.
- **The full ladder is for blocker and major only** (owner, after the builder check). Minor and
  nit findings get the hunt and one cross-examination; a minor or nit one hunter maintains and
  the other rejects is reported as `CONTESTED` and debated no further.
- **Council refactor of `/feature-flow` is out of scope** here.

## Builder's calls (veto-able)

### Topology

- **The command orchestrates.** `commands/adversarial-review.md` runs in the main session. It
  dispatches, relays, synthesises and writes the case file. Neither hunter spawns the other: a
  participant who also judges anchors (the ECC council skill's own warning). Neither hunter nor
  the judge lists `Agent` in its tools.
- **The procedure lives in the guide, not the command.** The round and loop state machine is
  `guides/adversarial-review.md` § Procedure; the command Reads it and executes it, the way
  `/feature-flow` reads `ai-workflow.md`. A later council-style orchestrator can reuse the same
  section without the command.
- **Within a round the two hunters persist.** Phases after the hunt reach each hunter through
  `SendMessage`, so a hunter answers critique of *its own* findings with its own context intact.
  **Between rounds they are replaced.** Fresh hunters after a fix see the new tree without
  anchoring on the previous round's findings (Santa method: fresh reviewers catch fix
  regressions).
- **Opposite starting angles.** Both hunters get the whole playbook, but Hunter A starts
  **inside-out** (failure paths, limits, timing and state inside the changed code) and Hunter B
  starts **outside-in** (callers and consumers, out-of-repo config, deploy and branch effects,
  claims versus code). Both must cover the full playbook before reporting. Same model, so
  diversity is partial; the design says so rather than pretending otherwise.
- **The judge is its own agent file**, `agents/review-judge.md`: same tool boundary as a hunter,
  a prompt about ruling, not hunting. It receives the diff, one finding, and the two final
  positions. It never sees the orchestrator's context or the debate transcript.
- **Models.** Hunters and judge: `claude-opus-5-5`, like the other feature agents. The stub's
  `model: opus` alias is replaced with the explicit id.

### Inputs and diff base

- `/adversarial-review [--base=<ref>] [--max-iter=N] [--no-fix] [--auto] [--resume] [context…]`.
- Diff base exactly as `reviewer.md` § Procedure 1: explicit `--base`, else merge-base against
  `origin/stable`, else `origin/master`, else `master`; `git diff $BASE` plus `git status` for
  uncommitted work. Empty diff: stop with `NO_DIFF`.
- **Context capsule** to each hunter: the base ref, the changed-file list, the free-text
  context, `project.md` § Stack and § Code layout, and the session scratchpad path. Never the
  conversation, never the other hunter's output.

### The round

```
hunt ──► cross-examine ──► debate until resolved ──► [judge ladder] ──► synthesis
  A,B      A on B, B on A     per open finding            per stalemate    orchestrator
```

1. **Hunt.** Both hunters, parallel. Each returns findings with ids (`A1…`, `B1…`), each
   finding in the lead's shape: severity (`blocker | major | minor | nit`), file:line, trigger,
   consequence, suggestion, and a provenance label per
   [`research-discipline.md`](../core/rules/research-discipline.md) § 1 (read, inferred,
   executed). A clean hunt is a valid hunt: zero findings, no padding.
2. **Cross-examination.** Each hunter receives the other's findings and rules on each after
   **re-reading the cited code**: `VALID` (optionally with a severity change and why), `FALSE
   POSITIVE` with the evidence that the trigger cannot fire (the guard, the caller, the type), or
   `UNCLEAR` with the exact thing it could not determine. It may add findings the other missed;
   those enter the next exchange as new findings.
3. **Debate until resolved.** The orchestrator relays rulings to the asserting hunter, which
   answers per finding: `CONCEDE`, `MAINTAIN` with new evidence, or `CLARIFY` (new trigger or
   re-graded severity). Each exchange carries only still-open findings.
   - **Scope.** Steps 3 and 4 run for blocker and major findings only. A minor or nit that is
     `VALID` after cross-examination is `AGREED`; one that is `FALSE POSITIVE` and conceded is
     `WITHDRAWN`; anything else is `CONTESTED` and reported as such.
   - **Evidence gate.** A reply on a finding must add new code evidence, a concrete trigger with
     input and state, a script result, or a concession, in a required `new_evidence:` field.
     The **opposing hunter**, in its next ruling, marks a reply that only rephrases as
     `NO_NEW_EVIDENCE`. A side is **exhausted** on a finding after two such rulings in a row. The
     orchestrator only checks the field is present and relays; it never judges content. A finding
     closes when one side concedes or both are exhausted.
   - **Burden of proof** sits with the asserter. No surviving trigger means `WITHDRAWN`.
   - **Proof by execution.** Either side may write a throwaway script under the scratchpad to
     prove a claim (runtime semantics, arithmetic, a regex, a copied pure function). Rules in
     § Tool boundaries. The script and its output go into the reply as evidence.
   - **Safety cap**: 8 exchanges per finding. It should never be the normal exit; the case file
     records when it is.
4. **Judge ladder**, per finding still open after both sides are exhausted:
   - If both hunters already agree the answer lives outside the repo, the finding goes straight
     to `ESCALATED` with their agreed question; no judge.
   - Dispatch a fresh `review-judge` with the diff, the finding, both final positions and both
     sides' script results. Its ruling has the shape of a finding (evidence, trigger or
     refutation, severity) and one of `UPHELD | REFUTED | OUTSIDE_REPO`.
   - Both hunters receive the ruling and get **one** exchange to refute it with new evidence.
     No refutation: resolved per the ruling. A refutation: the judge replies once. A refutation
     that still stands after that is a `STALEMATE`.
   - `OUTSIDE_REPO` means the answer lives in prod config, an IAM policy, a broker version,
     product intent: the judge writes the question and the finding becomes `ESCALATED`.
5. **Synthesis** (orchestrator, no agent). Every finding ends in exactly one state:

   | State | Meaning | Goes to |
   |---|---|---|
   | `AGREED` | both affirm; severity is the stricter unless the re-grade was accepted | Coder if blocker/major |
   | `WITHDRAWN` | asserter conceded | case file only |
   | `REFUTED` | challenger's evidence accepted, or judge refuted and nobody overturned it | case file only |
   | `ESCALATED` | reduced to a named question outside the repo | owner |
   | `STALEMATE` | ladder exhausted | owner, with the whole chain |
   | `CONTESTED` | minor or nit the hunters did not settle in one cross-examination | report only |

   Then the **owner pause**: if there are ESCALATED questions and `--auto` is off, ask them now
   with `AskUserQuestion`, because an answer can turn an item into `AGREED` (fixed this round)
   or `WITHDRAWN`. With `--auto`, they are reported at the end instead.

### The loop

- **Round counter** `review_iter` starts at 0, increments on each Coder dispatch, never resets.
  Default cap 3, `--max-iter=N` overrides.
- **Fix dispatch.** When any `AGREED` finding is blocker or major and `--no-fix` is off, dispatch
  Coder in its new **findings-only mode** (below), payload = the AGREED findings, labelled
  "FIX FROM ADVERSARIAL REVIEW". Coder builds and runs the project's tests as it does today.
  **Tester is not run**: there is no spec to drive scenarios, and the fresh hunters are the
  regression check.
- **Coder rejects a finding.** `receiving-code-review` lets Coder prove a finding not
  applicable. Such a rejection is a new position, not a silent drop: the finding and Coder's
  reasoning go up the judge ladder (judge rules between Coder and the hunters, one refutation
  exchange with the hunters, then the owner). Coder reports rejected findings in its status
  block as `not_applicable[]` with the reason, so the orchestrator can route them.
- **Then round N+1** with two new hunters on the new tree. The previous round's findings are
  **not** passed to them; the case file keeps them for the circuit breaker.
- **Exit.** `APPROVED` when a round ends with no AGREED blocker/major and nothing unresolved at
  blocker/major. `NEEDS_OWNER` when the only remaining blocker/major items are ESCALATED or
  STALEMATE. `REVIEW_LIMIT_REACHED` at the cap. `STALLED` on the circuit breaker. `BLOCKED` when
  Coder is blocked. `REVIEWED` when `--no-fix` and findings remain.
- **Circuit breaker**, checked after each round's synthesis, before the fix dispatch:
  - *Fix did not take*: round N's AGREED blocker/major set equals round N-1's after normalising
    file, line (±5) and issue text.
  - *Coder could not act*: Coder returned `BLOCKED`, or `IMPLEMENTED` with no changed files, or
    marked every finding not applicable through `receiving-code-review`.
  - *Fix churn*: two rounds running, every AGREED finding sits in code the previous fix touched.
  On a trip: `STALLED`, naming the condition and the repeated findings.

### Case file and report

- `.claude/runs/YYYY-MM-DD-adversarial-<slug>.md`, gitignored like the feature-flow run log.
  The orchestrator is its **only writer**. Per round: both hunt blocks, every exchange, judge
  rulings, the synthesis table, the Coder block. Per finding, the full chain.
- **State block and resume.** The case file opens with a machine-readable YAML block, rewritten
  at every round boundary: `review_iter`, base ref, tree hash after the last fix, every
  finding's id, severity and end state, and the open owner questions. `--resume` reads the
  newest case file (or a given path) and restarts the **current round with fresh hunters** from
  that state. Mid-debate state is not preserved: a compaction or crash mid-round costs that
  round's debate, never earlier rounds. `/coder --fix-from-adversarial-review` reads its
  findings from the same block, so the manual path after `--no-fix` works in a new session.
- The final report, in the owner's terminal: verdict and round count; AGREED items fixed, with
  Coder's notes; ESCALATED questions; STALEMATE items with both positions and the judge's view;
  minors and nits; and a **staging test plan** derived from the findings, the way the lead ends
  every review. Then the one-line next step: the owner commits.

### Coder: findings-only mode

A third input mode in `agents/coder.md`: a `findings[]` payload **with no spec**. Coder scopes
edits strictly to the findings, still routes them through `superpowers:receiving-code-review`,
reads the same rule files, builds and tests the same way, and reports `spec: n/a`. **It must not
fall back to the newest spec** under `.claude/specs/` in this mode. `commands/coder.md` gains
`--fix-from-adversarial-review` for the manual path.

### Tool boundaries

| Agent | Read | Edit/Write | Bash |
|---|---|---|---|
| adversarial-reviewer | ✅ | — | read-only git (as `reviewer`) + **scratchpad scripts** |
| review-judge | ✅ | — | same |

Scratchpad scripts: written under the session scratchpad only; `node`/`python3` on that file;
may read the repo; **never** write to it, build it, run its tests, start a server, or touch the
network; may import a project module only if that module is side-effect free on import,
otherwise copy the function. The lock gate still applies to anything heavy. The agents stay
`Edit`/`Write`-free in frontmatter; the script is written through Bash heredoc, which is why the
whitelist, not the tool list, carries this rule. `harness-check` gets a check that neither agent
file lists `Edit`, `Write` or `NotebookEdit`.

### Playbook: `guides/adversarial-review.md` (class 2)

Consumers: `adversarial-reviewer`, `review-judge`, `/adversarial-review`. The guide holds:

- **Attack angles** (the evidence table, generalised): for every external call, what happens on
  failure, timeout, partial result, 403-versus-404; for every config value, its range, unit,
  zero and interaction with its neighbours; for every timestamp, when it is taken; for every
  sort-plus-early-exit, who starves; for every guard, which legitimate state it also blocks; for
  every changed symbol, every consumer and mount point; for every comment, docs line and MR
  claim, whether the code keeps it; for every test cited, whether its conditions match prod;
  for every CI or infra change, which branch and release it lands in first; scope beyond the
  stated change.
- **Finding discipline**, salvaged from the ECC `code-reviewer` body: the pre-report gate (exact
  line, concrete trigger, surrounding context read, defensible severity), proof required for
  blocker/major, "zero findings is a valid result", and the false-positive list (error handling
  the caller owns, validated-upstream input, well-known constants, exhaustive switches, detached
  fire-and-forget, non-crypto `Math.random`, and the rest). The ECC React/Node checklists and the
  "AI-generated code addendum" are **dropped**: `reviewer.md` already carries a project-aware
  checklist, and the addendum is about model cost, not code.
- **Debate rules**: the evidence gate and who enforces it, burden of proof, the six end states,
  the severity scope of the ladder, the script rules.
- **Procedure**: the round and the loop (§ The round, § The loop above), as the section the
  command executes.
- **Message shapes** between orchestrator and agents (hunt block, ruling block, reply block,
  judge block), all YAML status blocks in the harness style.

`reviewer.md` gets one added line pointing at § Finding discipline. `tester.md` is untouched.

### Status blocks

Harness style (`guides/ai-workflow.md` § Status block contract), one per agent reply:

- `adversarial-reviewer`: `status: FINDINGS | CLEAN` for a hunt; `status: RULINGS` for a
  cross-examination; `status: REPLIES` for a debate turn; payload = findings or per-finding
  entries keyed by id, each reply carrying `new_evidence:`.
- `coder` in findings-only mode: the existing block plus `not_applicable[]` (finding id, reason).
- `review-judge`: `status: UPHELD | REFUTED | OUTSIDE_REPO`, payload = the ruling in finding
  shape, plus `question` when outside the repo.
- Orchestrator (final): `status: APPROVED | NEEDS_OWNER | REVIEWED | REVIEW_LIMIT_REACHED |
  STALLED | BLOCKED | NO_DIFF`, `review_iter`, `case_file`, `summary`.

The contract lives in the new guide, with a one-line pointer from `guides/ai-workflow.md`.

### Harness bookkeeping

- `CLAUDE.md`: add the two agents and the command to the Agents and commands table, the guide to
  the Guides table.
- `harness-check.sh`: the new agents point at `rules/project/guides-index.md`; single-line
  `tools:` without `*`; no write tools and no `Agent`; the guide has consumers; `coder.md`
  mentions the findings-only mode, `not_applicable`, and the no-fallback rule;
  `commands/adversarial-review.md` exists, names both agent files and Reads the guide's
  § Procedure.
- `docs/`: this design and its plan.

### Verification plan (how the builder proves it works)

- `bash core/scripts/harness-check.sh` green.
- A scratch repo with three planted defects from the evidence table (an unbounded `setInterval`
  from env, a backoff timestamped before the slow call, a guard that swallows a legitimate empty
  result) and one decoy that looks like a bug but is guarded one frame up. Run
  `/adversarial-review` in a fresh `claude -p`. Pass: the three are `AGREED`, the decoy ends
  `WITHDRAWN` or `REFUTED` with the guard cited, at least one finding was settled by a scratchpad
  script, and the case file shows the chain. Then `--no-fix` off: Coder fixes, round 2 is
  `APPROVED`.
- A stalemate drill: feed the judge a synthetic pair of positions and confirm the hunters'
  refutation exchange and the `STALEMATE` path reach the owner with the chain intact.

## Non-goals

- Model diversity (a Codex or Gemini second opinion). The ECC santa-loop's external reviewer is
  noted as a later option; this design keeps one model family and says so in the report.
- Posting findings to GitLab. The MCP can do it later; this command reports to the terminal.
- Replacing `/reviewer` inside `/feature-flow`. That is the council project.
- CodeRabbit interaction. Separate channel, as for `reviewer`.

## Verified (2026-10-22)

Fixture: a throwaway Node project in the session scratchpad, one base commit holding
`src/api.js` with a `try/catch` caller, then uncommitted: `src/heartbeat.js` (unbounded
`setInterval` from `HEARTBEAT_MS`), `src/retry.js` (backoff from a timestamp taken before the
`await`), `src/manifest.js` (empty-map guard that also blocks a real delete-all), a `parseBody`
decoy guarded one frame up, a planted unrelated spec under `.claude/specs/`, and a filled
`project.md` (Node 20, `npm run build` = `node --check`, no tests). Harness installed from this
branch with `install.sh`; runs in fresh `claude -p --model claude-opus-5-5` sessions.

| Expectation | Result |
|---|---|
| Three planted defects `AGREED` and fixed | **Pass.** Retry and heartbeat in round 1, the manifest guard in round 2 (round 1 had graded it minor; round 2's fresh hunters re-raised it as major). |
| Decoy `WITHDRAWN`/`REFUTED` with the guard cited | **Partial.** Nobody flagged the guarded exception. The hunters instead agreed a real contract change (pre-parsed or missing bodies now get a 400) and Coder changed `api.js`. No dispute arose in the whole run, so no judge was needed. |
| At least one finding with `provenance: executed` | **Pass.** 34 findings cite scratchpad probes. |
| Coder `spec: n/a`, `changed_files` over the three files, no mention of the planted spec | **Pass.** Two Coder passes, `not_applicable: []`, the planted spec never appears in the case file. |
| Round 2 ends `APPROVED` | **Deviation, by design.** Three rounds, `NEEDS_OWNER`: two majors were `ESCALATED` as questions the fixture cannot answer (is the retry called from a non-awaiting timer; what fills `req.body`). The design routes those to the owner rather than approving past them. |
| `git status` shows only Coder's edits plus the planted files | **Pass.** |
| Resume drill | **Pass.** With `tree` overwritten, `--resume --no-fix --auto` reported the tree change, restarted the current round (3) with fresh hunters, kept `review_iter` 2 and the earlier rounds' states, re-probed all five fixes clean. |
| Stalemate drill | **Pass.** A fresh judge (Opus, the judge prompt and the guide) ruled `UPHELD` major on the retry finding, corrected the finding's off-by-one line numbers, rejected the challenger's out-of-repo SDK claim, and settled it with an executed script (send ≥ backoff → next call sent with no backoff). |

| Second resume drill, on the final guide text after the review fix pass | **Pass.** With the recorded tree matching, `--resume --no-fix --auto` said the source tree had not changed, restarted the current round anyway with fresh hunters, merged 8 findings to 5 through `same_as`, kept `review_iter` 2 and the earlier states, excluded the never-read paths and earlier scratchpad folders, and ended `NEEDS_OWNER` on the one unanswered question. |

Cost: smoke run $11.47 over about 23 minutes; resume drills $3.33 and $3.15.

Harness defects the live runs surfaced, all fixed on this branch. Found by the smoke run and
fixed before the resume drill: the tree hash must cover untracked files; hunters and the judge
must never grep `.remember/`, `.claude/runs/`, `.claude/investigations/`, `.claude/specs/` (the
Remember plugin's store leaked round 1's findings to a round 3 hunter); `VALID` at the asserter's
severity is `AGREED` at once. Found by the resume drill and fixed after the resume drill: the
tree hash never covers `.claude/` (an untracked harness made every case-file write look like a
tree change, which also means that drill's "tree changed" verdict was trivially true); unanswered
escalations carry over across rounds; each round's agents get their own scratchpad subfolder.
Found by the final whole-branch review and fixed after it: the judge ladder ends on the
challenger's second `CHALLENGE` with no content check; a finding stalemates only when both sides
are exhausted; duplicate findings merge via `same_as`; a reply carries one block per phase
asked; Coder rejections the judge refutes are not a stall; prose is bounded and only blocks are
relayed. After the review, the deferred minors were also closed: Coder may run a scratchpad probe
script to check its own fix; the Coder message carries `review_iter`; the hunt capsule allows a
missing `project.md`; resume runs the branch gate when fixes are on and marks an abandoned
attempt's findings `SUPERSEDED`; the command warns when `.claude/runs/` is not gitignored;
`git check-ignore` and `git ls-files` are on the read-only list; hunters use only the guide's
field names.

## Left to the builder

- Exact prompt wording for hunter, judge and each phase message; the ids and YAML shapes.
- The normalisation used by the circuit breaker's "same finding" test.
- The exact YAML shape of the case file's state block.
- How the command passes the scratchpad path (the session's scratchpad is known to the main
  session; subagents need it in the capsule).
- The scratch-repo fixture for the verification plan.
- Whether the staging test plan is written by the orchestrator from the findings or requested
  from one hunter as a last message. Either is acceptable; the orchestrator is cheaper.
