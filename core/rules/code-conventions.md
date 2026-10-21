---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,vue,svelte,py,go,rs,java,kt,rb,php,cs,swift,css,scss,sass,less,html}"
---
# Code conventions

Source-level conventions the owner enforces in review. Check this file before writing a component
or a helper. Where things live (icon folder, helper folders, import aliases, reference files) is
in [`project.md`](../project.md) § Code layout; the project's own naming and component rules are
in its root `CLAUDE.md` or contributing guide.

## Icons: one component per icon, never inline

Caught twice in review (two chevron icons, 2026-10-06).

- **Never put an `<svg>` inline in a feature component, and never use a text glyph** (`‹`, `›`,
  `×`) as an icon: a glyph takes its shape and centring from the inherited font, which varies by
  platform.
- One file per icon in the project's icon folder, exporting `<Name>Icon`, re-exported from the
  folder's index (alphabetical). Import through the project's alias for that folder.
- Shape (in React/TSX; copy the project's reference icon if it names one):
  - typed `FC<SVGProps<SVGSVGElement>>`;
  - `width="1em" height="1em"` with the exported `viewBox`: font size or the caller's CSS sets
    the size;
  - `fill="currentColor"` (or `stroke`), so colour, hover and `:disabled` come from CSS;
  - `aria-hidden="true" focusable="false"`: the accessible name belongs on the button;
  - `{...props}` spread last;
  - a short comment saying what the icon is for and, if it's mirrored or rotated for another
    direction, how.

## Helper docs: JSDoc, so the comment shows on hover

Set 2026-10-06. A `//` comment above an export is invisible at the call site; `/** … */` shows in
the editor's hover everywhere the helper is used.

- Every exported helper (function, hook, shared constant or type) gets a `/** … */` doc directly
  above it. Lead with what it returns or does, then the non-obvious *why* (spec reference, a
  measured fact, an invariant).
- Keep it short: 1–4 lines. Long derivations, worked examples and probe evidence go in the spec,
  or in a `//` comment inside the body.
- Module-private helpers may keep `//` comments.

## Generic helpers go in a generic file

- Before writing a helper, search the project's helper folders for an existing one.
- A helper that isn't feature-specific (string, number, date…) goes in the matching generic file
  with a generic name: `capitalizeWords` in `string.ts`, not `capitalizeVariantText` in the
  feature's file. Re-export it from the helpers index if the project has one.
- A pure module that must stay runnable under plain `node` (a script, a test without the
  framework) imports a dependency-free file by relative path, not an index that pulls in framework
  modules.
