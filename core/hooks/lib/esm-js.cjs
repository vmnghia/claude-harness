#!/usr/bin/env node
// esm-js.cjs <claude-dir>: the .js files under .claude/ that break, or will break, because Node
// would load them as ES modules (2026-11-05: a "type": "module" host turned the harness's own
// CommonJS .js files into ES modules, require() threw, and git-guard/lock-gate silently fell back
// to defaults). Used by harness-check (§5j), install.sh and session-context.sh, so the rule lives here.
//
// Prints one line each, nothing when all is well:
//   type module      the .claude dir itself resolves to "type": "module" (a reminder: new .js there is ESM)
//   harness <path>   a harness-owned bare .js (in .harness-manifest; every file when there is none, as in core/)
//   esm <path>       a project-owned .js whose nearest package.json says "type": "module"
// A project-owned .js under a CommonJS host is the project's business and is not reported.
// Skips runs/, investigations/, .harness-retired/, node_modules/, .git/ (output and retired copies).
const fs = require("fs"), path = require("path");
const dir = path.resolve(process.argv[2] || ".claude");
const SKIP = new Set(["runs", "investigations", ".harness-retired", "node_modules", ".git"]);

let owned = null;   // null = no manifest: everything is harness-owned
try {
  owned = new Set(fs.readFileSync(path.join(dir, ".harness-manifest"), "utf8").split("\n")
    .filter((l) => l && !/^(#|version |source )/.test(l)).map((l) => l.replace(/^\S+\s+/, "")));
} catch (e) { /* no manifest */ }

const typeCache = new Map();
function typeOf(d) {   // Node's rule: the nearest package.json's "type", else commonjs
  if (typeCache.has(d)) return typeCache.get(d);
  let t;
  const pj = path.join(d, "package.json");
  if (fs.existsSync(pj)) { try { t = JSON.parse(fs.readFileSync(pj, "utf8")).type === "module" ? "module" : "commonjs"; } catch (e) { t = "commonjs"; } }
  else { const up = path.dirname(d); t = up === d ? "commonjs" : typeOf(up); }
  typeCache.set(d, t);
  return t;
}

const out = [];
if (typeOf(dir) === "module") out.push("type module");
(function walk(d) {
  let ents; try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (e) { return; }
  for (const e of ents) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (!SKIP.has(e.name)) walk(p); continue; }
    if (!e.isFile() || !e.name.endsWith(".js")) continue;
    const rel = path.relative(dir, p).split(path.sep).join("/");
    if (!owned || owned.has(rel)) out.push("harness " + rel);
    else if (typeOf(d) === "module") out.push("esm " + rel);
  }
})(dir);
if (out.length) process.stdout.write(out.join("\n") + "\n");
