#!/usr/bin/env node
// project-config.js <key> [--regex anchored|token]
// Prints one value from the ```json harness block in <project>/.claude/project.md, so hooks read
// project facts from the one file a project writes. Prints nothing when the file, the block or the
// key is missing: every caller has a default. Never throws (hooks must not crash on a bad file).
//
// --regex turns a branch list like ["main", "release/*"] into a grep -E pattern:
//   anchored → ^(main|release/.+)$             (does this branch name match?)
//   token    → (main|release/[^[:space:]]+)     (does a command line mention one?)
const fs = require("fs"), path = require("path");
const [key, flag, mode] = process.argv.slice(2);
try {
  const dir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const md = fs.readFileSync(path.join(dir, ".claude", "project.md"), "utf8");
  const m = md.match(/```json harness\s*\n([\s\S]*?)\n```/);
  if (!m) process.exit(0);
  let v = JSON.parse(m[1]);
  for (const k of String(key || "").split(".")) v = v == null ? undefined : v[k];
  if (v == null) process.exit(0);
  if (flag === "--regex" && Array.isArray(v)) {
    const esc = (s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
    const star = mode === "token" ? "[^[:space:]]+" : ".+";
    const alt = v.map((b) => esc(String(b)).replace(/\*/g, star)).join("|");
    process.stdout.write(mode === "token" ? "(" + alt + ")" : "^(" + alt + ")$");
  } else {
    process.stdout.write(typeof v === "object" ? JSON.stringify(v) : String(v));
  }
} catch (e) { /* missing file or bad JSON: print nothing, caller uses its default */ }
