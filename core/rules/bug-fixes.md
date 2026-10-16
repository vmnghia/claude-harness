# Bug fixes

Bug tickets follow a stricter workflow than feature work because "the fix compiles" and "the fix actually addresses the user-visible symptom" are different things.

## Reproduce locally before fixing

**Do not propose or implement a fix until the bug has been reproduced locally.** A code-level hypothesis from reading the source is not a substitute for seeing the bug.

If you cannot reproduce, the next move is *not* "let's try a fix anyway" — it's to widen the repro net (different build mode, throttling, cookie state, env mirror, device emulation, etc.) until the bug is visible.

When the bug ticket has an attached video/screenshot you can't view, ask the reporter (or the assignee) to describe the exact visible symptom and the conditions: env (prod / preview / local), browser, device, network, cookie state, build mode.

## Workflow

1. **Read the ticket and all attachments.** Note env, conditions, expected vs actual.
2. **Discuss repro strategy before touching code.** Brainstorm angles, propose them as a checklist, agree on one.
3. **Reproduce locally.** Reliably. Record the exact steps.
4. **Then** investigate root cause — see [working-style.md](./working-style.md) and the systematic-debugging skill.
5. **Implement the fix.** Smallest change that addresses the root cause.
6. **Verify against the repro.** The same steps that produced the bug must now produce the expected behavior.

## What this means in practice

- Do not pre-create branches, scaffolding, or "preparation" edits before repro is confirmed — that signals you're about to fix something unverified.
- A bug that only appears in prod needs a prod-equivalent local setup (the project's production build served locally, throttling, real cookies) — not "I'll deploy and check."
- If repro genuinely can't be achieved locally, escalate (ask reporter for a reproducible env, request a screen-share, or get access to the failing env) rather than fixing blindly.

## Mimic the real user flow

When reproducing a bug or verifying a fix via chrome-devtools MCP, drive the UI the way a real user would.

- **Don't** call the router programmatically (e.g. `router.push('/checkout')`) to switch routes.
- **Do** click through the UI by element uids (choose options, press the real buttons).

A programmatic `router.push` skips analytics events, intermediate component mounts, side-effect timing, and any UI-gated state transitions that the real user trips. The bug might depend on those, and even when it doesn't, the resulting "repro" doesn't prove what the user actually experiences.

Reserve `evaluate_script` for *observing* state (counters, console capture, wrap-chain inspection), not for *driving* navigation or form submission. The only acceptable shortcut is setting cookies/storage to put the page in a starting state the user would otherwise reach via login or previous-session flow.
