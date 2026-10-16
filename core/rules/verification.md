# Verification

How to verify a change works before claiming it's done. Type-check and build are necessary, not
sufficient: anything that renders in a browser is verified in a real browser. The dev server URL,
test command and fixtures are in [`project.md`](../project.md).

## Browser / runtime: chrome-devtools MCP is the primary tool

For anything that renders (SSR HTML, hydration, console warnings, network, performance, layout),
drive the **chrome-devtools MCP**. Don't claim a UI fix verified from type-check or curl alone.

1. `list_pages` (the MCP can talk to Chrome)
2. `navigate_page(url)` to the affected page
3. Set required cookies/storage via `evaluate_script` (e.g. a returning-visitor scenario)
4. Reload with `navigate_page(type: 'reload', ignoreCache: true)`. A URL navigation with
   `ignoreCache` still serves chunks from cache (measured 2026-09-25). Repeat any `initScript` on
   the reload.
5. Inspect the DOM, then `list_console_messages`, **even when the page looks fine**: a React
   duplicate-key error once named a bug's exact cause and had been firing all along.

### Pristine SSR HTML

`evaluate_script`'s `document` already reflects post-hydration mutations. To see what the server
emitted, re-fetch from inside the page, with the live session's cookies:

```js
const html = await fetch(location.href, { credentials: 'include', cache: 'no-store' }).then(r => r.text())
```

Shell `curl` is fine for health endpoints, raw response headers, or reproducing a request without
a browser; not for SSR-vs-CSR comparisons (different cookies).

### Third-party SDK / analytics verification

Console warnings can outlive a reload and don't prove what an SDK was called with. Intercept the
SDK's call queue with an `initScript` and read that. Use valid-format fake IDs (an invalid ID
triggers the SDK's own warning and masks the real signal), and test on a page that actually loads
the SDK.

### When the MCP can't reach the dev server

- **Timeout, server running:** wait ≥60 s before concluding anything (Chrome is slow to give up
  on an unresolvable host), then check the hosts file.
- **Certificate interstitial** on a self-signed dev cert: type `thisisunsafe` on the error page
  (`type_text`); it navigates through. The bypass is lost when the MCP browser restarts.
- **`ERR_SSL_PROTOCOL_ERROR` on an `http://` URL:** the TLD is HSTS-preloaded (e.g. `.dev`), so
  Chrome forced HTTPS onto a plain-HTTP port. `thisisunsafe` won't help: put a TLS proxy in front.

## Pick fixtures that can break

A rich fixture proves the happy path and nothing else. Render bugs cluster at **degenerate data
shapes**, and a well-stocked fixture is immune to them by construction.

Worked example (2026-09-07): selecting a variant moved the thumbnails but left the main image
stale. It didn't reproduce on galleries of 14 or 19 images. It needed one with **exactly 2**: a
three-slot `[prev, active, next]` strip collapses to `[1, 0, 1]` at length 2, giving duplicate
React keys and undefined reconciliation.

When a bug reproduces for QA but not for you, **suspect your fixture's shape before the report.**
Check boundary counts (0, 1, 2 items; single-option axes) and whether derived indices can collide.
Keep two fixtures, rich and minimal (`project.md` § QA fixtures).

## Emulate the device, not just the viewport

`emulate(viewport: '375x812x3,mobile')` sets metrics only; `navigator.userAgent` stays desktop, so
every UA-conditional branch stays dark. Pass `userAgent` too when **behaviour** is what you check.

Worked example (2026-09-18): an effect gated on an iOS UA threw `forEach is not a function` on
every iOS visit for two years. `getElementsByClassName` returns an `HTMLCollection` (no
`forEach`), and an `as any` cast hid it from `tsc`. A session of viewport-only runs missed it; one
iPhone-UA run found it.

- Do one behavioural pass with an iPhone UA (and Android when a branch exists). Keep it apart
  from layout-shift measurement: `touch` in the viewport string sets `hadRecentInput` and
  suppresses shifts.
- **`as any` on a DOM collection is a smell**: `HTMLCollection` vs `NodeList` is exactly what it
  erases.

## Measuring layout shift and hydration safety

- **A `layout-shift` entry's `sources` are the nodes that MOVED, not the one that resized.**
  Read the suspect element's `getBoundingClientRect()` before and after instead.
- **Take a baseline on the unchanged code with the identical procedure** (page, viewport, scroll
  steps, cohort). A 0.488 regression was invisible until the baseline read 0.028 on the same
  script.
- **Dev-server numbers ≠ deployed numbers.** Quote deployed numbers; use dev only for
  same-session A/B.
- **Hydration-safety probe (React):** an inline script after the app root tags SSR nodes with an
  expando (`el.__ssr = 1`). If React discards and re-creates the server DOM, the tags vanish; this
  works in production builds, where React stays silent. Count commits with an `initScript` stub
  of `__REACT_DEVTOOLS_GLOBAL_HOOK__.onCommitFiberRoot`. Include a **positive control** (a
  deliberate pre-hydration text change → error #418 and 0 surviving tags), or a clean result
  means nothing. Measured on React 19.2: production hydration compares text children, never
  attributes.

## Mobile scroll smoothness: in-page metrics can't see it

iOS scrolls off the page's main thread: the page's frames stayed at p99 18–21 ms through hitches
a person could plainly see. Ground truth is a **screen recording** on the device, measured frame by
frame (content displacement per frame; calibrate so the median speed equals the scripted speed),
with a **time-based scripted scroll** so a stall shows as a jump and runs are comparable. Keep the
recorder's own timing: padding to constant fps duplicates frames and fakes freezes.

## Tests

Whether a test runner exists is in `project.md` § Commands and in the session hook's
`tests=present|absent`. When absent, specs write `n/a — no test runner` in Unit Test Notes, Coder
reports `test_result: n/a`, and nobody proposes "add a test" without saying where the runner
would come from.

## Dev-server restart wait

Some edits make the dev server restart and reload data, so it answers wrongly for a while
(`project.md` § Dev server, "Readiness" and "Restart quirks"). Don't conclude failure inside that
window: poll every 15–20 s. Premature probing has produced false-negative verifications.

## Build and type-check

- The project's **full** build (`project.md` § Commands) is the prod-readiness check; a partial
  step (e.g. only the client bundle) misses server-side errors.
- A type-checker verifies structure, not behaviour. "It compiles" is not "it's fixed".

## Measuring a local production build

Use one when a claim depends on production timing (hydration order, LCP, FCP, TBT), where a dev
server's unminified, compile-on-demand output gives meaningless numbers.

- **Prove the page hydrated before trusting any number.** A misconfigured asset prefix can make
  every chunk 404: SSR content still renders and LCP still fires, so the broken build *looks*
  fine while everything needing hydration silently vanishes. One such comparison made new code
  look correct and old code broken, entirely falsely. Check in-page:
  ```js
  () => ({
    hydrated: /* your framework's "app is live" flag, e.g. typeof window.next !== 'undefined' */ true,
    chunk404s: performance.getEntriesByType('resource')
      .filter(r => /\.js(\?|$)/.test(r.name) && r.responseStatus >= 400).length
  })
  ```
- **Compare builds only within one session.** The identical build measured a TBT median of
  1398 ms in one session and 1031 ms in another; a "−304 ms win" across sessions didn't survive a
  same-session re-run.
- **Split LCP at `responseEnd`:** before it is network, `firstPaint − responseEnd` is page work.
- **The LCP element depends on network speed** (text on a fast link, the hero image throttled).
  Record the element with the number.
- **A local build can't show hydration-timing layout shift**: chunks served from localhost often
  hydrate before first paint. Use a deployed build for that.
- Take ≥3 runs, use medians, check the spread before calling a delta real.
- **Kill servers by the PID listening on your port** (`ss -ltnp`), never `pgrep -f <pattern>`:
  a pattern also matches your own shell. Never build while a dev server writes the same output
  directory.

## Verify object shape after a shape-changing fix

In a loosely typed codebase (`any`, plain-object types) the type-checker won't catch an object
that gains, drops or renames keys. When a fix builds or merges an object whose shape matters
downstream (persisted, put into a store, sent in a request, read elsewhere):

- Capture it **before** (a known-good baseline) and **after**, and diff the key sets, not one
  eyeballed sample.
- Exercise the paths that inject extra keys (e.g. an autocomplete-filled form vs a typed one).
- Read the **authoritative** sink, not a look-alike cache with a similar name.

## Verify before claiming done

- Run the changed scenario in a real browser (or have the owner run it).
- For a bug fix, the same repro that showed the bug must now show the expected behaviour
  ([bug-fixes.md](./bug-fixes.md)).
- If you couldn't reproduce or run it, say so explicitly instead of claiming success.
