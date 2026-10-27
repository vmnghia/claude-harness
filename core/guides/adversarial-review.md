# Adversarial review — contract for the hunters, the judge and `/adversarial-review`

`N` **hunters** (`N` dispatches of `agents/adversarial-reviewer.md`, `N` being
`knobs.width.adversarial-reviewer`; [`thoroughness.md`](./thoroughness.md) § Knob table) try to
break a diff independently, then debate each other's findings until every one is resolved. A
fresh **judge** (`agents/review-judge.md`) rules on what the hunters cannot settle. The command
(`commands/adversarial-review.md`) orchestrates, relays, synthesises, writes the case file, and
sends what survived to Coder in findings-only mode, then `N` fresh hunters again.

Consumers: `/adversarial-review`, `adversarial-reviewer`, `review-judge`, `coder` (findings-only
mode). Status blocks follow [`ai-workflow.md`](./ai-workflow.md) § Status block contract; the
severity scale is its `blocker | major | minor | nit`. Every claim carries a provenance label
per [`research-discipline.md`](../rules/research-discipline.md) § 1.

**The spec is not an input.** The review is of the diff as it stands, with whatever free-text
context the owner typed. Design: `docs/2026-10-22-adversarial-review-design.md` in the harness
repo, with the GitLab evidence the playbook is built from.

## Playbook

A hunter does not walk a checklist. It simulates the change under adverse conditions and chases
every break to its blast radius. Work through every bucket below. Start with the buckets your
**angle** lists, then finish the rest: every hunter covers everything, they only diverge in what
they look at first.

### Error paths

For every external call in or near the diff (object store, HTTP, DB, queue, file, child process):

- What happens on failure, timeout, a partial result, and on each error class the caller treats
  differently (403 versus 404, `ENOENT` versus `EACCES`, "too large" versus "unreadable")? A
  branch that handles one class and lets the others fall into the generic path is a finding when
  the generic path does something the specific class must not.
- What state is written **after** a failed read? A failed load that still marks something dirty,
  advances a cursor, or swaps in a fallback baseline turns a read error into a destructive write.
- Is the error path exercised by anything (a test, a repro, a log line), or only the happy path?

### Config values, limits and units

For every value read from env, config, args or a configmap:

- Range: what happens at `0`, negative, `NaN`, empty string, and absurdly large? (Node timers
  above 2^31-1 ms overflow and fire every 1 ms.) Is there a minimum and a maximum?
- Unit: can a human mistake seconds for milliseconds? Would `60` be caught?
- Zero semantics: does `0` mean "disabled", and does disabling one setting silently disable a
  neighbour the docs call independent (an early `return` before the neighbour is set up)?
- Precedence: when the same knob is also set outside the repo (`envFrom`, `NODE_OPTIONS`, a CI
  variable), which wins now, and did the diff change that?

### Time and ordering

- For every timestamp: is it taken before or after the slow call it measures? A backoff computed
  from the start of the tick is no backoff when the send itself took longer than the first step.
- For every sort plus early exit, wave, or batch: which items can never reach the front? An item
  that always fails and always sorts first starves everything behind it.
- For every fixed-order loop with a `skip`/`deferred` branch: can the same items be deferred on
  every pass, forever?
- For every retry counter: is it reset when the item succeeds through another path? Is it only
  in memory, and does a restart change the behaviour?
- For every writer: what happens when two instances run at once (a rolling deploy)?

### Guards that conflate error with legitimate state

For every "if empty / missing / zero, keep the previous value" guard: name the legitimate state
it also blocks (a real delete-all, a folder that is genuinely empty now). Is the stale value then
persisted, so the guard outlives the condition?

### Consumers and surroundings outside the diff

- For every changed symbol or component: `grep` every consumer, caller and mount point before
  writing anything. A component also mounted on another page sends that page's events too. Name
  the consumers in the finding.
- For every shared hook, helper or store the diff touches: who else depends on it? A "no
  behaviour change" refactor of shared code is a scope finding.
- Out-of-repo inputs: configmaps, IAM and bucket policies, broker settings, CI variables. A
  permission the change needs is a finding until the code handles its absence or the finding is
  escalated as a question.
- Deploy and branch effects: which branch does a CI change land in first, and does a revert take
  effect on the very release it ships in?

### Claims the code does not keep

- Every comment, docstring, log message, commit message and MR description is a claim. Check each
  one against the code: "prevents starvation", "a few hundred ms", "the two settings are
  independent".
- Every test or measurement cited: do its conditions match production (poll rate, idle time,
  heap size, data volume, flag state)? Name the condition the test never exercised.

### Unbounded repeated work

For anything that runs per tick, poll or request: can a non-settling state make it run every
time (a dirty flag set unconditionally, a stringify-and-PUT of megabytes every interval, a
re-fan-out of a whole family on every pass)?

### Scope

A diff larger than its fix: incidental refactors, renamed things, shared code touched with no
behaviour change. `minor` on its own; `major` when it touches a shared path, with the consumers
named.

### Starting angles

Four angles, defined with their bucket orders in `thoroughness.md § Angles`: `inside-out`,
`outside-in`, `time-and-config`, `claims-and-consumers`. The `n`-th hunter of a round takes the
`n`-th angle; above four the angles cycle (`hunter-E` starts `inside-out` again, up to
`hunter-H`). A dry-check round rotates them by the rule in the same section. The two orderings a
two-hunter round uses:

- **`inside-out`**: Error paths → Config values → Time and ordering → Guards →
  Unbounded repeated work → then Consumers, Claims, Scope.
- **`outside-in`**: Consumers and surroundings → Claims the code does not keep →
  Scope → Unbounded repeated work → then Error paths, Config values, Time and ordering, Guards.

## Finding discipline

### Pre-report gate

Answer all four before writing a finding. A "no" or "unsure" downgrades it or drops it.

1. **Can I cite the exact line?** File and line, not "somewhere in the auth layer".
2. **Can I name the trigger?** Input, state, and the bad outcome. No trigger means you are
   pattern-matching, not reviewing.
3. **Have I read the surrounding context?** Callers, imports, tests. Many apparent issues are
   handled one frame up or narrowed by a type.
4. **Is the severity defensible?** A missing doc comment is never `major`. Severity inflation
   erodes trust faster than a missed finding.

### Proof for `blocker` and `major`

The snippet and line; the trigger scenario; and why the existing guards (types, validation,
framework defaults, a caller's `try/catch`) do not catch it. Any of the three missing: demote to
`minor` or drop.

### Zero findings is a valid result

A clean hunt is a valid hunt. Never manufacture a finding to justify the dispatch. Filler nits,
speculative "consider using X", and hypothetical edge cases with no trigger are the primary
failure mode of model reviewers.

### False positives to skip

Skip these unless you have evidence specific to this codebase:

- **"Consider adding error handling"** on a call whose error path the caller or framework owns
  (error middleware, an error boundary, a top-level `try/catch`, a `.catch` upstream).
- **"Missing input validation"** on an internal function whose callers already validate. Trace
  one caller before flagging.
- **"Magic number"** for well-known constants (`200`, `404`, `1000` ms, `60`, `24`, `1024`,
  index `0`/`-1`) and single-use locals whose name says what they are.
- **"Function too long"** for exhaustive `switch` statements, configuration objects, test
  tables, generated code. Length is not complexity.
- **"Missing doc comment"** on a single-purpose internal helper whose name and signature say
  what it does.
- **"Prefer `const`"** when the variable is reassigned. Read the whole function.
- **"Possible null dereference"** when the preceding line narrows the type or an `if` guard is
  in scope. Trace type flow instead of pattern-matching on `?.`.
- **"N+1 query"** on fixed-cardinality loops (a four-element enum) or paths already batching.
- **"Missing await"** on a deliberately detached call (logging, metrics, a background push).
  Look for the comment or the `void` prefix.
- **"Should use TypeScript / types"** in a JavaScript-only file. Match the project's language.
- **"Hardcoded value"** in fixtures, examples and docs. Tests should have hardcoded expectations.
- **Security theatre**: `Math.random()` outside cryptography (jitter, sampling, animation);
  `eval`/`Function` in a plugin system that is explicitly a code-loading surface.

When tempted, ask: would a senior engineer on this team actually change this in review?

### Severity on the harness scale

- `blocker`: would lose or silently stale production data, leak secrets, break prod, or let a
  shopper be charged a price nobody chose.
- `major`: wrong behaviour under a realistic trigger, starvation, a loop that never settles,
  unbounded resource use, a shared path changed without its consumers checked.
- `minor`: readability, minor convention drift, scope creep that touches nothing shared.
- `nit`: style preference. Informational.

### Provenance

Every finding, ruling and turn carries one label: `read` (the cited lines say it), `inferred`
(reasoned from code you read but did not run; say what is inferred), `executed` (a scratchpad
script; the reply carries its path and an output excerpt). A `blocker` built only on `inferred`
is a `major` until someone reads or runs the missing piece.

## Debate rules

- **Independence in the hunt.** A hunter sees nothing of the other hunters until the orchestrator
  sends it their findings. It never asks for them.
- **Cross-examination re-reads the code.** A ruling cites the lines it rests on. `FALSE_POSITIVE`
  names the guard, the caller or the type that stops the trigger. A ruling with no evidence is
  `UNCLEAR`, never `FALSE_POSITIVE`.
- **N-way cross-examination.** Every hunter rules on every finding of the `N−1` others, so each
  finding gets `N−1` rulings; the orchestrator tallies them, counting enums only. A `same_as`
  ruling counts as `VALID`.
  - **Majority `VALID`** (more than half of the `N−1` rulings) → `AGREED` (§ Procedure, A round,
    step 2 for a re-graded severity).
  - **Majority `FALSE_POSITIVE`** → turns (`blocker`/`major`) or the asserter's one turn
    (`minor`/`nit`).
  - **No majority** (an `UNCLEAR` split, or a tie at even `N−1`) → turns as if challenged for a
    `blocker`/`major`; `CONTESTED` for a `minor`/`nit` (§ Ladder scope).
  - **Turns are two-sided**: between the asserter and the **designated challenger**, the lowest
    hunter letter among those who ruled `FALSE_POSITIVE`, else the lowest among those who ruled
    `UNCLEAR`. The other rulings on the finding are attached verbatim to the first turn message
    as evidence; their authors take no turns on it. Wherever this guide says "the other side",
    "both sides" or "both hunters" about one finding, it means the asserter and its designated
    challenger, and the judge gets those two positions.

  At `N = 2` each finding has one ruling, its author is the designated challenger, and this is
  the two-hunter protocol unchanged.
- **Burden of proof sits with the asserter.** A finding whose trigger does not survive the
  challenge is `WITHDRAWN`. "It could still happen somehow" is not a trigger.
- **Evidence gate.** Every turn on a finding carries `new_evidence:` — new cited lines, a
  concrete trigger with input and state, a script result, or a concession. It may be `none` only
  with `CONCEDE` or `ACCEPT`. Each turn also rates the message it answers:
  `peer_added_evidence: yes | no`. A side is **exhausted** on a finding once the other side has
  rated two of its consecutive turns `no`. An exhausted side gets no further turn messages on
  that finding; the other side continues until it concedes, accepts, or is exhausted too. A
  finding is **stalemated** only when both sides are exhausted, or the cap is hit. The
  orchestrator checks the fields exist and relays; it never judges content.
- **Proof by execution.** Either side may prove a claim about runtime behaviour, arithmetic, a
  regex or a copied pure function with a throwaway script under the session scratchpad
  (§ Tool boundaries). A passing script is `executed` evidence, the strongest kind. Prefer it to
  arguing when the claim can be run.
- **Outside the repo.** When the answer lives in prod config, an IAM policy, a broker version,
  product intent, either side may say so with `outside_repo: <the one question>`. When both
  sides say it, the finding is `ESCALATED` with that question; no judge.
- **Ladder scope.** Everything past one cross-examination (further turns, the judge, the fix
  dispatch) is for `blocker` and `major` only. A `minor`/`nit` that is `VALID` after
  cross-examination is `AGREED`; `FALSE_POSITIVE` and conceded is `WITHDRAWN`; anything else is
  `CONTESTED` and reported as such.
- **Severity reconciliation.** `AGREED` takes the stricter severity unless a re-grade was
  explicitly accepted in a turn.
- **Judge ladder** (per `blocker`/`major` finding with both sides exhausted and no shared
  `outside_repo`): a fresh `review-judge` gets the diff, the finding, both final turns and every
  script output on it, and rules `UPHELD | REFUTED | OUTSIDE_REPO` in finding shape. Both hunters
  get the ruling and **one** turn to refute it with new evidence. No refutation: resolved per
  the ruling (`AGREED` or `REFUTED`; `OUTSIDE_REPO` is `ESCALATED` with the judge's question). A
  `CHALLENGE`: the judge replies once, then the challenging hunter gets one more turn. `ACCEPT`
  resolves per the ruling; a second `CHALLENGE` is `STALEMATE`. Nobody weighs that last
  exchange: the second `CHALLENGE` itself ends the ladder.
- **Duplicates.** Hunters usually find the same defect. In cross-examination a ruling may
  carry `same_as: <own id>`; at synthesis findings that describe one defect (same `file`,
  overlapping lines, same trigger) merge under the lowest id (`A` before `B`, then by number) at
  the stricter severity, the state block records `dup:`, and the Coder payload and the breaker
  use the merged set.
- **Safety cap.** 8 turns per side per finding. Reaching it counts as both sides exhausted; the
  case file records that the cap, not the gate, ended the debate.
- **Tone.** No performative agreement, no reflexive defence. Conceding when the evidence says so
  is what makes your next finding credible.

### End states

| State | Meaning | Goes to |
|---|---|---|
| `AGREED` | both affirm, severity reconciled | Coder when `blocker`/`major` |
| `WITHDRAWN` | the asserter conceded, or Coder's answer cited a recorded decision | case file only |
| `REFUTED` | the challenger's evidence was accepted, or the judge refuted it and nobody overturned that | case file only |
| `ESCALATED` | reduced to one named question outside the repo | the owner |
| `STALEMATE` | ladder exhausted | the owner, with the whole chain |
| `CONTESTED` | `minor`/`nit` not settled in one cross-examination | report only |

## Message shapes

All blocks are YAML inside `---` fences, last thing in the reply. A reply carries
**one block per phase** the message asked for: a message that asks for rulings on added
findings and turns on open ones gets a `RULINGS` block and a `TURN` block. The orchestrator **relays only the blocks**
between agents, never the prose around them; prose goes to the case file. Ids: hunter
letter plus its own sequence (`A1`, `A2`, `B1`). A hunter that adds findings during
cross-examination continues its own sequence. The case file prefixes the round: `r1-A1`.

### Finding

```yaml
- id: A1
  severity: blocker | major | minor | nit
  file: src/x.ts
  line: 42
  issue: <one line>
  trigger: <input and state that fire it>
  consequence: <what breaks, for whom>
  suggestion: <one line>
  provenance: read | inferred | executed
  evidence: <file:line refs, or scratchpad script path + output excerpt>
```

### Hunt capsule (orchestrator → hunter, the dispatch prompt)

Role (`hunter-A` … `hunter-H`) and its angle (`thoroughness.md § Angles`); the resolved `knobs:`
(the state block's line, verbatim); the resolved base ref and the changed-file list; `delta:`
(round ≥ 2 after a fix): Coder's `changed_files` and the differing hunks, or `none`
(§ Procedure, The loop step 5); the owner's context text verbatim (or "none"); `project.md`
§ Stack and § Code layout verbatim (or the line `project.md missing` / `project.md still has
TODOs`, in which case the hunter infers the stack from the files and says so); the session
scratchpad path; the case-file path (for
reference only; the hunter never writes it); the list of paths it never reads (§ Tool
boundaries). Never the conversation, never another hunter's output, never a spec.

### Hunt reply

```yaml
---
agent: adversarial-reviewer
role: hunter-A | hunter-B | … | hunter-H
phase: hunt
status: FINDINGS | CLEAN
payload:
  findings: []            # finding shape; empty with CLEAN
  questions: []           # at most one per finding, routed to Coder through the lead: {finding_id, to: coder, question}
  probed: []            # one entry per delta file with no finding: {file, buckets, tried}
  summary: <one line>
---
```

A hunter's question is the one thing it may ask the author: "was this a choice?" In
`/feature-flow` the orchestrator sends it to Coder by id and appends the `ANSWER` to the
cross-examination capsule. An answer citing `D<n>` withdraws the finding only when that decision
was recorded before the hunt was dispatched, and the `DECISION` block is quoted beside the
`ANSWER` so the hunter can object to it informedly (an `OBJECTION` to the lead, recorded, not
debated). An `is_decision: yes` answer with no decision id is evidence for the cross-examination,
never a withdrawal; the orchestrator records no decision between a hunt's dispatch and that
round's synthesis. In the standalone command there is no
Coder to ask: the questions are reported to the owner in the recap and the finding proceeds.

`probed` follows `thoroughness.md § Delta and probed`: with a delta, every delta file the hunter
has no finding on gets one entry, `{file: <path>, buckets: [<bucket names>], tried: <one line>}`.
With `delta: none` it is `[]`.

### Probe send-back message (orchestrator → hunter)

"Name what you probed in <file>[, <file>…]: the buckets you tried and the trigger that did not
fire." Sent once, before cross-examination, to a hunt reply that lacks a `probed` entry for a
delta file it has no finding on. The reply is a hunt reply carrying only `probed` (its `status`
as in the first hunt reply).

### Cross-examination message (orchestrator → hunter)

"Cross-examine. Here are the other hunters' findings, grouped by hunter: <for each other hunter,
`hunter-<letter>:` and its findings block>. Rule on each after re-reading the cited code; add
anything they missed." One `RULINGS` block answers all of them.

### Cross-examination reply

```yaml
---
agent: adversarial-reviewer
role: hunter-A | hunter-B | … | hunter-H
phase: cross-examine
status: RULINGS
payload:
  rulings:
    - id: B1
      ruling: VALID | FALSE_POSITIVE | UNCLEAR
      severity: <same or re-graded>
      same_as: <own id, when this is the same defect you found>
      evidence: <file:line refs or script>
      reason: <one line>
  added: []               # finding shape, ids continuing this hunter's sequence
---
```

### Turn message (orchestrator → hunter)

"Turn k on <ids>. The other hunter's last message on each: <their rulings or turns, verbatim>.
For each, as asserter reply CONCEDE | MAINTAIN | CLARIFY; as challenger reply ACCEPT |
CHALLENGE. `new_evidence` is required; rate what you answer with `peer_added_evidence`."
"The other hunter" is, per finding, the asserter or its designated challenger (§ Debate rules).
The asserter's first turn message on a finding also carries the other rulings on it: "Other
hunters' rulings on <id>, as evidence: <their rulings, verbatim>."

### Turn reply

```yaml
---
agent: adversarial-reviewer
role: hunter-A | hunter-B | … | hunter-H
phase: turn
status: TURN
payload:
  turns:
    - id: A1
      response: CONCEDE | MAINTAIN | CLARIFY | ACCEPT | CHALLENGE
      new_evidence: <required; "none" only with CONCEDE or ACCEPT>
      peer_added_evidence: yes | no
      severity: <same or re-graded>
      outside_repo: <the one question, only when the answer is outside the repo>
---
```

### Judge capsule (orchestrator → judge, the dispatch prompt)

Everything the judge needs and nothing more: the base ref, the diff (or the path to read it
from); one finding in finding shape; the asserter's and the designated challenger's final turns
on it verbatim; every script path and output either side produced on it; the scratchpad path.
Nothing about the orchestrator's reasoning or the rest of the debate.

### Judge reply

```yaml
---
agent: review-judge
status: UPHELD | REFUTED | OUTSIDE_REPO
finding: <id>
payload:
  severity: blocker | major | minor | nit
  evidence: <file:line refs or script path + output>
  trigger: <UPHELD only: the surviving trigger>
  refutation: <REFUTED only: the guard, caller or type that stops the trigger>
  question: <OUTSIDE_REPO only: the one question the owner must answer>
  summary: <one line>
---
```

### Judge-ruling message (orchestrator → the asserter and the designated challenger)

"The judge ruled on <id>: <judge block verbatim>. One turn: ACCEPT, or CHALLENGE with new
evidence." The reply is a turn reply. Coder's `not_applicable` entries go through the same
message with Coder's reason in place of a hunter's turn.

### Coder, findings-only mode (orchestrator → coder)

"FIX FROM ADVERSARIAL REVIEW. No spec. `iteration: <review_iter>`. Case file: <path>. Findings: <AGREED blocker/major
findings in finding shape>." Coder's reply is its normal block with `spec: n/a` and
`payload.not_applicable: [{id, reason}]` ([`coder.md`](../agents/coder.md)).

### Orchestrator, final

```yaml
---
agent: orchestrator
command: adversarial-review
status: APPROVED | NEEDS_OWNER | REVIEWED | REVIEW_LIMIT_REACHED | STALLED | BLOCKED | NO_DIFF
review_iter: <n>
case_file: <path or "n/a">
summary: <one line>
---
```

## Procedure

The command executes this section. It holds no procedure of its own.

A round of parallel briefs to one teammate type counts once toward `--max-iter`; the width is the number of agents in that round.
Here a round's hunters, whatever the width, are one round toward the cap, and every hunter,
judge and Coder dispatch counts once toward `max_agents` (`thoroughness.md § Counting`).

### Before the first round

1. Parse arguments (the command's § Input). Run the branch gate when fixes are on.
2. Resolve the diff base as [`reviewer.md`](../agents/reviewer.md) § Procedure step 1 does, and
   take `git diff <base>` plus `git status`. Empty: final block `NO_DIFF`, nothing written.
3. Create the case file (§ Case file) with `review_iter: 0`, `dry_rounds: 0`, the resolved
   `knobs:` (`thoroughness.md § Input`) and the `tree` hash. Take round 1's snapshot (§ The
   loop step 5); round 1 carries `delta: none`.

### A round

1. **Hunt.** Dispatch `knobs.width.adversarial-reviewer` hunters in **one message** so they run
   in parallel, letters from `A`, angles from `thoroughness.md § Angles` (rotated in a dry-check
   round), each with the hunt capsule (then, in `/feature-flow`, relay each hunt reply's
   `questions[]` to Coder and append the answers to the cross-examination message). Record
   every agent id in the state block. Append every hunt reply.
   **Probe check** (`thoroughness.md § Delta and probed`), before cross-examination: a hunt
   reply that lacks a `probed` entry for a delta file it has no finding on gets the probe
   send-back message once (§ Message shapes); append its reply. A reply still missing entries
   goes on to cross-examination with those files uncovered by that hunter. A `CLEAN` one is
   recorded `CLEAN (unprobed: <files>)` in the synthesis, does not count as `CLEAN` for the exit
   check, and the recap lists its files.
2. **Cross-examine.** Send each hunter the other hunters' findings, grouped by hunter (by agent
   id). Append every reply. Tally each finding's rulings by § Debate rules, N-way
   cross-examination. A finding a majority rules `VALID`, every such ruling at the asserter's
   own severity, is `AGREED` at once, no turn needed. A majority `VALID` with a re-graded
   severity among its votes goes to the asserter for one turn:
   `CLARIFY` carrying the re-graded severity accepts it (`AGREED` at the new severity);
   `MAINTAIN` with evidence keeps it open like any other finding, its designated challenger the
   lowest letter among the re-graders. Findings a hunter `added` enter the open set like hunt
   findings: every other hunter rules on them with a `RULINGS` block in its next reply, beside
   its `TURN` block when it has one, and they are tallied the same way. Rulings with `same_as`
   are merged at synthesis (§ Debate rules, Duplicates).
3. **Resolve `minor`/`nit`.** Majority `VALID` → `AGREED`; majority `FALSE_POSITIVE` → one turn
   to the asserter; `CONCEDE` → `WITHDRAWN`, otherwise `CONTESTED`; no majority → `CONTESTED`.
   These never go further.
4. **Turns until resolved** on every open `blocker`/`major`: alternate turn messages between the
   asserter and its designated challenger, each carrying only still-open findings. After every
   reply apply the Debate rules: `CONCEDE` → `WITHDRAWN`; `ACCEPT` → `AGREED` (severity
   reconciled); both sides `outside_repo` → `ESCALATED`; both sides are exhausted, or the cap is
   hit → the finding is **stalemated** (an exhausted side simply gets no more turn messages on
   it). Stop when the open set is empty.
5. **Judge ladder** for every stalemated finding, each judge dispatched fresh (several in one
   message when there are several). Then the judge-ruling message to the asserter and the
   designated challenger, one turn. No `CHALLENGE` → resolved per the ruling. A `CHALLENGE` →
   one judge reply via SendMessage to the judge's id; the challenging hunter gets it and one more
   turn: `ACCEPT` → resolved per the ruling; a second `CHALLENGE` → `STALEMATE`, no content
   check.
6. **Synthesis** (orchestrator). Write the round's synthesis table into the case file: every
   finding, its end state, its severity, and the chain of message references. A dry-check
   round's synthesis ends with `dry: yes` or `dry: no (<new ids>)` (§ The loop step 2). Rewrite
   the state block.
7. **Owner pause.** With `ESCALATED` findings and `--auto` off, ask the questions now with
   `AskUserQuestion`, one question per finding. An answer that settles the finding changes its
   state to `AGREED` (fixed this round) or `WITHDRAWN`; record the answer in the case file. With
   `--auto`, the questions are reported at the end instead.

### The loop

1. **Circuit breaker** (after synthesis, before any fix dispatch):
   - *Fix did not take*: this round's `AGREED` `blocker`/`major` set is the same as the previous
     round's. Two findings are the same when they share `file`, their lines differ by at most 5,
     and at least 60 % of the words of `issue` are shared after lowercasing and collapsing
     whitespace.
   - *Coder could not act*: the previous Coder reply was `BLOCKED`, or `IMPLEMENTED` with an
     empty `changed_files`, or a finding the judge had upheld came back in `not_applicable` a
     second time. A rejection the judge refuted is Coder being right, never a stall.
   - *Fix churn*: for two rounds running, every `AGREED` finding sits in a file the previous
     round's Coder `changed_files` lists.
   Tripped → final status `STALLED`, naming the condition and the repeated findings. A round
   with no `AGREED` `blocker`/`major` never trips it.
2. **Exit before fixing.** `ESCALATED` and `STALEMATE` items **carry over** from earlier rounds
   until the owner answers them: a question nobody answered is still open, whatever the current
   round's hunters found. No `AGREED` `blocker`/`major` and nothing `ESCALATED`/`STALEMATE` at
   `blocker`/`major` in any round → `APPROVED`. No `AGREED` `blocker`/`major` but some `ESCALATED`/`STALEMATE`
   at that severity → `NEEDS_OWNER`. `AGREED` `blocker`/`major` with `--no-fix` → `REVIEWED`.
   `review_iter` at the cap → `REVIEW_LIMIT_REACHED`.
   **Dry check** (`thoroughness.md § Dry rounds`). With `K > 0` (`knobs.dry`), a round whose exit
   would be `APPROVED` starts a **dry-check round** instead: fresh hunters, same tree,
   `delta: none`, no Coder, angles rotated (`thoroughness.md § Angles`). A finding is new when it
   is not a duplicate of any earlier round's finding (step 1's sameness rule, at any severity)
   and it **survives its cross-examination** (any end state but `WITHDRAWN` or `REFUTED`). A
   dry-check round with no new finding is dry. A new finding resets the dry counter; a new
   `AGREED` `blocker`/`major` re-enters the fix loop (step 3; `REVIEWED` with `--no-fix`). `K`
   consecutive dry rounds (the trailing `dry: yes` syntheses), or `dry_rounds` reaching its hard
   cap `2K`, → `APPROVED`; at the cap the recap says the dry loop was **cut at its cap**, not
   dry. Dry-check rounds never increment `review_iter`; each one increments `dry_rounds`.
   `--no-fix` keeps them.
3. **Fix dispatch.** `review_iter++`. Dispatch `coder` with the findings-only message carrying
   every `AGREED` `blocker`/`major` finding. Append its block. `BLOCKED` → final `BLOCKED`.
4. **Coder rejections**, evaluated **before the breaker** and before the next round. Every
   `not_applicable` entry goes up the judge ladder now: a fresh judge with Coder's reason as one
   position and the hunters' final position as the other; the judge-ruling message to the
   hunters; the ladder as in step 5 of the round. A refuted finding is `REFUTED` and leaves the
   `AGREED` set. An upheld finding goes back to Coder **in this round** (`review_iter++`); an
   upheld finding Coder rejects a second time trips the breaker. When every rejection was
   refuted and nothing else was sent, the round has no `AGREED` `blocker`/`major` left: go to
   the exit check, not to a new round.
5. **Next round.** Rewrite the state block (`tree` from the new diff). Take this round's
   snapshot and compute the delta (`thoroughness.md § Delta and probed`) against the previous
   round's: every round takes one, a dry-check round included. `D` is `<scratchpad>/adv-r<N>/`
   for the round about to start, `P` the previous round's, `BASE` the state block's `base`:

   ```bash
   cd "$(git rev-parse --show-toplevel)" && mkdir -p "$D"
   git diff "$BASE" -- . ':!.claude' > "$D/diff.patch"
   git diff --name-only "$BASE" -- . ':!.claude' | while IFS= read -r f; do
     printf '%s  %s\n' "$(git diff "$BASE" -- "$f" | sha256sum | cut -c1-64)" "$f"
   done > "$D/tracked.sha256"
   git ls-files --others --exclude-standard -z -- . ':!.claude' | sort -z \
     | xargs -0 -r sha256sum > "$D/untracked.sha256"
   { diff "$P/tracked.sha256" "$D/tracked.sha256" | sed -n 's/^[<>] [0-9a-f]\{64\}  //p'
     diff "$P/untracked.sha256" "$D/untracked.sha256" | sed -n 's/^> [0-9a-f]\{64\}  //p'
   } | sort -u
   ```

   The last command prints the delta paths; run it only when the round follows a fix (round 1
   and a dry-check round carry `delta: none`). The delta files are those paths plus Coder's
   `changed_files`. Its hunks: for a tracked file,
   what `diff` reports between its sections of `$P/diff.patch` and `$D/diff.patch`; an untracked
   file new or changed since the previous round is a whole-file delta (its path). Start a new
   round with `knobs.width.adversarial-reviewer` **fresh** hunters and the delta in their
   capsule. The previous round's findings are never sent to them; the case file keeps them for
   the breaker.

**Agent ceiling** (`thoroughness.md § Agent ceiling`). A dispatch that does not fit `max_agents`
is not started; a round's hunters fit or wait together. Reaching `max_agents` mid-round, finish
the round with resumes (`SendMessage` is free): a judge that can no longer be dispatched leaves
its finding `STALEMATE` with `reason: agent ceiling`; then the exit check runs. Coder goes out
only when Coder and the next round both fit. When the exit check calls for a round that does not
fit, the last exit check decides: a round that would verify a fix → `REVIEW_LIMIT_REACHED`; a
dry-check round → `APPROVED`, and the recap says the dry loop was cut at the agent ceiling.

### Report

The human-readable recap, then the final block: verdict and `review_iter`; `AGREED` items that
were fixed, with Coder's `changed_files` notes; `ESCALATED` questions, one per line;
`STALEMATE` items with both positions and the judge's view; `minor`, `nit` and `CONTESTED` items;
a **staging test plan** the orchestrator writes from the `AGREED` and `ESCALATED` findings (one
line per finding: the trigger to reproduce and what must now happen); the case-file path; and
the next step, which is the owner committing. Never the orchestrator. Also: how many dry-check
rounds ran and whether the loop ended dry or was **cut at its cap** (or cut at the agent
ceiling); every delta file left uncovered (`CLEAN (unprobed: <files>)` and the like); findings
`STALEMATE` with `reason: agent ceiling`.

The per-round cost line the command prints before each round reads "round N of ≤ M, W hunters,
about $X": `M` is the bound on rounds from `thoroughness.md § Dry rounds`, `W` the round's width.

### Resume

`--resume [<case-file>]`: read the state block of the given file, else the newest
`.claude/runs/*-adversarial-*.md`. Recompute `tree`. If it differs, say so and restart the
current round on the new tree. Either way, start the current round again with **fresh** hunters
from the recorded `review_iter`, `dry_rounds` and `knobs` (never re-resolved) and the recorded
states of earlier rounds. Mid-round debate state
is never restored. The abandoned attempt's findings stay in the state block with
`state: SUPERSEDED` and their ids; the restart's ids get the next letter suffix (`r3b-`, `r3c-`),
so nothing in the case file is overwritten. When fixes are on, the branch gate runs again before
any fix dispatch.

## Case file

`.claude/runs/YYYY-MM-DD-adversarial-<slug>.md`, date from the session, slug from the context
text or the branch (kebab-case, at most five words), `-2`, `-3` on collision. It should be gitignored like the other run logs; the installer does not add that line, so the
command warns when `git check-ignore -q .claude/runs/` (trailing slash: the directory may not exist yet) fails. The **orchestrator is the only writer**; agents receive its path for reference
and never touch it.

The first fenced block is the state block, rewritten at every round boundary:

```yaml
state:
  review_iter: 0
  dry_rounds: 0                                 # dry-check rounds run so far (cap 2K)
  knobs: {…}                                    # resolved once (thoroughness.md § Input)
  base: <resolved sha>
  tree: <sha256 over `git diff <base>` followed by every untracked, non-ignored file (see below)>
  hunters: {A: <agent id>, B: <agent id>, …}    # the current round's
  findings:
    - {id: r1-A1, dup: r1-B2, severity: major, state: AGREED, file: src/x.ts, line: 42, issue: <one line>}
    - {id: r2-C1, severity: major, state: STALEMATE, reason: agent ceiling, file: …, issue: …}
  owner_questions:
    - {id: r1-B2, question: <one line>}
```

**`tree`** must see new files, not only edits to tracked ones: a Coder fix to an untracked file
is invisible to `git diff`. Compute it as the sha256 of the concatenation of `git diff <base>`
and, for each path from `git ls-files --others --exclude-standard` in sorted order, the path
and that file's sha256:

```bash
cd "$(git rev-parse --show-toplevel)" && { git diff "$BASE" -- . ':!.claude'; git ls-files --others --exclude-standard -z -- . ':!.claude' | sort -z | xargs -0 -r sha256sum; } | sha256sum
```

`tree` never covers `.claude/`: in a repo where the harness is untracked and not ignored, the
case file itself would otherwise be part of the hash, and every write to it would read as a
tree change (measured 2026-10-22).

Then, per round, verbatim appends under `## Round N` (a dry-check round is a round too):
`### Hunt <letter>` per hunter (`### Hunt A`, `### Hunt B`, …, with its probe send-back reply),
`### Cross-examination <letter> on <the other letters>` per hunter (`### Cross-examination A on
B`, `### Cross-examination B on A` at width 2), `### Exchange k` (both turn
replies), `### Judge <finding id>` (capsule summary, ruling, the hunters' turns, the reply),
`### Synthesis` (the table), `### Owner` (questions and answers), `### Coder` (its block). Every
block is appended as the agent wrote it.

## Tool boundaries

| Agent | Read | Edit/Write | Bash | Agent / SendMessage |
|---|---|---|---|---|
| adversarial-reviewer | ✅ | — | read-only git + scratchpad scripts | — |
| review-judge | ✅ | — | read-only git + scratchpad scripts | — |

**Read-only git:** `git status`, `git diff`, `git log`, `git show`, `git merge-base`,
`git rev-parse`, `git branch --show-current`, `git check-ignore`, `git ls-files`, each
optionally as `git -C <path> …` (never `-c`: a config override can run a pager or fsmonitor).
Nothing state-mutating, and never against a repo under `/tmp/claude-*`: a repo written into the
scratchpad can carry a `.git/config` that executes on `git status` (measured 2026-10-26).

**Enforced, not only asked** (2026-10-22): `hooks/review-bash-gate.sh`, a PreToolUse hook on Bash
in `settings.json` that applies itself only when the call's `agent_type` is `adversarial-reviewer`
or `review-judge`, denies everything outside this list and the script rules below, and fails
closed. (A hook in an agent file's frontmatter never fired for PreToolUse: measured 2026-10-22.) A denial is policy: reformulate within the list, never work
around it. **It is a guardrail against accidental mutation, not a sandbox:** scratchpad scripts
run unscanned with the session's full privileges, so a hunter steered by its input (e.g. prompt
injection in the diff) is not contained. Neither are the main session or Coder, which read the
same diff with full Bash; containment, if ever needed, belongs session-wide (Claude Code's native
sandbox), not in this gate.

**Scratchpad scripts:** a throwaway script written with a Bash heredoc under the session
scratchpad path from the capsule, run with `node <path>` or `python3 -I <path>`. Every agent
gets its **own subfolder** in the capsule (`<scratchpad>/adv-r<N>-<role>/`, the orchestrator
names it) and never reads another agent's: an earlier round's scripts are that round's
findings in another form. It may read
the repo. It must never write to the repo, build it, run its tests, start a server, install
anything, or use the network. A project module may be imported only when importing it has no
side effect; otherwise copy the function into the script. The script path and an output excerpt
go into the reply as `executed` evidence. The lock gate still applies to anything heavy.

**What agents never see:** the orchestrator's conversation, the other hunter's work except what
the orchestrator relays, the case file's contents beyond what the capsule quotes, any spec.

**Paths agents never read or grep**, because they hold earlier rounds' findings, other runs, or
specs: `.claude/runs/`, `.claude/investigations/`, `.claude/specs/`, `.claude/reports/`, and
any plugin store in the repo such as `.remember/` (the Remember plugin writes a summary of the
session there mid-run, and a round 3 hunter's grep matched round 1's findings in it: measured
2026-10-22). Every `grep -r` a hunter or judge runs excludes these directories, and the hunt and
judge capsules repeat the list.
