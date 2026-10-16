#!/usr/bin/env bash
# Stop hook (arrives as SubagentStop) for web-reader — every quote in sources[] must be a
# verbatim substring of its page. Registered in .claude/agents/web-reader.md's own
# frontmatter, so it runs only while that subagent runs; main sessions and peers are
# unaffected. Decided 2026-10-16: web-reader (Haiku) must not fabricate, garble
# or paraphrase a citable quote, and the check must cost the caller no tokens.
#
# Reads last_assistant_message (the status block), runs .claude/scripts/verify-quote.sh
# on each sources[] entry, and blocks (exit 2, reason on stderr → shown to the agent)
# until every entry is MATCH. A failing quote can always be moved to unverified[] (kept,
# never citable), so the agent can always finish without dropping evidence; that matters
# because it has no shell and WebFetch caches pages for 15 min (observed
# 2026-10-16). unverified[] is not checked.
#
# Safety valve: after MAX_BLOCKS blocks for one agent the hook lets it stop, and logs
# the escape to .claude/runs/quote-verify.log so it is auditable. Every verdict is logged
# there too. Exit 0 = allow stop. Exit 2 = keep working.

INPUT=$(cat)
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
HERE="$(cd "$(dirname "$0")" && pwd)"            # <repo>/.claude/hooks once installed
VERIFY="$HERE/../scripts/verify-quote.sh"
YAML_JS="$HERE/../vendor/js-yaml.min.js"           # vendored js-yaml 4.1.0 (MIT): no project node_modules needed
LOG="${QV_LOG:-$ROOT/.claude/runs/quote-verify.log}"   # QV_LOG: harness-check's sandbox
STATE="${TMPDIR:-/tmp}/quote-verify-gate"
MAX_BLOCKS=3
mkdir -p "$STATE" "$(dirname "$LOG")"

printf '%s' "$INPUT" | ROOT="$ROOT" VERIFY="$VERIFY" YAML_JS="$YAML_JS" LOG="$LOG" STATE="$STATE" MAX="$MAX_BLOCKS" node -e '
  const fs = require("fs"), path = require("path"), { spawnSync } = require("child_process");
  const { VERIFY, YAML_JS, LOG, STATE } = process.env, MAX = +process.env.MAX;
  const log = (line) => { try { fs.appendFileSync(LOG, new Date().toISOString() + " " + line + "\n"); } catch (e) {} };
  let d = ""; process.stdin.on("data", (c) => (d += c)); process.stdin.on("end", () => {
    let j; try { j = JSON.parse(d); } catch (e) { j = {}; }
    const agent = String(j.agent_id || "unknown").replace(/[^\w-]/g, "");
    const countFile = path.join(STATE, agent);
    const blocks = +(fs.existsSync(countFile) ? fs.readFileSync(countFile, "utf8") : 0) || 0;

    const block = (reason) => {
      if (blocks >= MAX) {
        log(agent + " ESCAPE after " + blocks + " blocks: " + reason.split("\n")[0]);
        process.exit(0);
      }
      fs.writeFileSync(countFile, String(blocks + 1));
      log(agent + " BLOCK " + (blocks + 1) + "/" + MAX + ": " + reason.split("\n")[0]);
      process.stderr.write("quote-verify-gate: " + reason + "\n(policy: .claude/agents/web-reader.md § Quotes are checked; this is policy, not an error)\n");
      process.exit(2);
    };

    let yaml;
    try { yaml = require(YAML_JS); }
    catch (e) { return block("hook cannot load " + YAML_JS + "; end your reply now and the caller will see this in the log."); }

    // The status block is the last "---" fenced section naming agent: web-reader.
    const msg = String(j.last_assistant_message || "");
    const parts = msg.replace(/```(yaml)?/g, "").split(/^---\s*$/m);
    const raw = parts.reverse().find((p) => /^\s*agent:\s*web-reader\s*$/m.test(p));
    if (!raw) return block("no status block found. End your reply with exactly one status block (agent: web-reader).");
    // The block carries page-derived text, so parsing must be safe. js-yaml 4 load() is safe and its
    // safeLoad is a stub that THROWS; js-yaml 3 load() runs !!js/function tags. Pick by version.
    const parse = yaml.DEFAULT_FULL_SCHEMA ? yaml.safeLoad : yaml.load;   // DEFAULT_FULL_SCHEMA exists only in v3
    let sb; try { sb = parse(raw); } catch (e) { return block("status block is not valid YAML (" + e.message.split("\n")[0] + "). Fix it and end again."); }

    const sources = (sb && sb.payload && Array.isArray(sb.payload.sources)) ? sb.payload.sources : [];
    const failed = [], seen = new Map();
    sources.forEach((s, i) => {
      const url = s && s.url, quote = s && s.quote;
      if (!url || !quote) { failed.push("sources[" + i + "]: missing url or quote"); return; }
      const key = url + "\u0000" + quote;
      if (!seen.has(key)) {
        const r = spawnSync(VERIFY, [String(url), String(quote)], { encoding: "utf8", timeout: 30000 });
        seen.set(key, (r.stdout || "").trim() || "UNCHECKABLE: verifier gave no output");
      }
      const v = seen.get(key);
      log(agent + " " + v.split(":")[0] + " " + url);
      if (v !== "MATCH") failed.push("sources[" + i + "] " + url + " -> " + v + "\n    quote: " + JSON.stringify(String(quote)).slice(0, 160));
    });

    if (!failed.length) { try { fs.unlinkSync(countFile); } catch (e) {} process.exit(0); }
    block(failed.length + " quote(s) in sources[] are not verbatim substrings of their page:\n  " + failed.join("\n  ") +
      "\nFor each: either copy the page text exactly (re-fetch with a WebFetch prompt asking for the exact sentence, unchanged), " +
      "or move the entry from sources[] to unverified[] with the same fields plus `verdict: <the line above>`. " +
      "Never reword a quote to pass. Then end again with the full status block.");
  });
'
STATUS=$?
# node missing or crashed: a hook bug, not the agent's fault. Blocking would loop forever
# (the block counter lives in node), so let it stop and leave an auditable trace.
if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 2 ]; then
  echo "$(date -u +%FT%TZ) unknown CRASH exit $STATUS; quotes unverified" >> "$LOG"
  exit 0
fi
exit "$STATUS"
