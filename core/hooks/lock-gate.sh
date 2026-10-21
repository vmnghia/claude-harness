#!/usr/bin/env bash
# lock-gate.sh — PreToolUse(Bash). While a measurement lock exists, ask before a heavy command run
# by any session other than the lock's owner, so a lock protects itself and idle peers never need a
# wake-up message (a message to an idle session costs it a full context re-read; measured 2026-10-21).
#
#   owner   = the caller's session_id equals the lock's `owner_session:` line (a subagent carries its
#             parent's session_id, so the owner's own agents pass). No owner_session → nobody owns it.
#   heavy   = project.md json `heavy_commands` (regexes vs the whole command string), else DEFAULT.
#   stale   = now > `expected_end:` + 1 h; a missing/unparseable end reads "end unknown".
#   decision: `ask` (an interactive user decides; a non-interactive caller can't run it).
# Fail-open: any error, no lock, or malformed input → allow (exit 0, no output). Never exits 2.
IN=$(cat 2>/dev/null) || exit 0
DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CFG="$(dirname "$0")/lib/project-config.js"
LOCK_REL=$(CLAUDE_PROJECT_DIR="$DIR" node "$CFG" measurement_lock 2>/dev/null)
LOCK_REL="${LOCK_REL:-.claude/runs/MEASUREMENT-IN-PROGRESS.md}"
case "$LOCK_REL" in /*) LOCK="$LOCK_REL";; *) LOCK="$DIR/$LOCK_REL";; esac   # an absolute path must not silently disable the gate
[ -f "$LOCK" ] || exit 0
HEAVY=$(CLAUDE_PROJECT_DIR="$DIR" node "$CFG" heavy_commands 2>/dev/null)
# A pathological heavy_commands regex can't be interrupted inside node's one thread, so the whole
# decision is capped at 3 s: a timeout prints nothing, which is an allow (fail-open, but fast).
printf '%s' "$IN" | LOCK="$LOCK" HEAVY="$HEAVY" timeout 3 node -e '
const fs = require("fs");
const DEFAULT = ["\\b(yarn|npm|pnpm)( run)? (build|dev|start|install|ci)\\b", "\\bnext (build|dev|start)\\b",
                 "\\blighthouse\\b", "harness-check\\.sh",
                 "\\b(npm|pnpm) (i|add)\\b", "\\byarn( add\\b|\\s*$|\\s*(&&|;|\\|))"];   // installs: npm i, yarn add, bare yarn
let s = "";
process.stdin.on("data", d => s += d).on("end", () => {
  try {
    const j = JSON.parse(s);
    const cmd = (j.tool_input && j.tool_input.command) || "";
    if (!cmd) return;
    let pats; try { pats = JSON.parse(process.env.HEAVY || "null"); } catch { pats = null; }
    if (!Array.isArray(pats)) pats = DEFAULT;
    const heavy = pats.some(p => {
      try { return new RegExp(p).test(cmd); }
      catch { process.stderr.write("lock-gate: skipped invalid heavy_commands regex: " + p + "\n"); return false; }
    });
    if (!heavy) return;
    const lock = fs.readFileSync(process.env.LOCK, "utf8");
    const field = k => { const m = lock.match(new RegExp("^[ \\t>*-]*" + k + ":[ \\t]*(.*?)[ \\t\\r]*$", "m")); return m ? m[1].trim() : ""; };
    // Owner if ANY owner_session line matches: a session that re-wrote its id after /clear by
    // appending a line must not be locked out by the stale one above it (2026-10-21 review).
    const owners = [...lock.matchAll(/^[ \t>*-]*owner_session:[ \t]*(.*?)[ \t\r]*$/gm)].map(m => m[1].trim()).filter(Boolean);
    if (j.session_id && owners.includes(j.session_id)) return;
    const name = field("owner_name") || "another session";
    const what = ((lock.match(/^- \*\*What:\*\*[ \t]*(.*)$/m) || [])[1] || "").trim();
    const endS = field("expected_end"), t = Date.parse(endS);
    let end = "end unknown", stale = false;
    if (endS && !isNaN(t)) { end = endS; stale = Date.now() > t + 3600e3; }
    const reason = "Measurement lock held by " + name + (what ? " (" + what + ")" : "") + ", until " + end +
      (stale ? " — STALE (over 1 h past its end; ask the user)" : "") +
      ". This command is listed as heavy and could skew the measurement. Permission mode: " + (j.permission_mode || "?") +
      ". Only the session named " + name + " may update owner_session in " + process.env.LOCK +
      " (e.g. after /clear). If that is not you, do not edit the lock and do not rephrase the command to get past this: wait for the lock to go, or ask the user.";   // no apostrophes: this program is inside a single-quoted bash string
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse",
      permissionDecision: "ask", permissionDecisionReason: reason } }));
  } catch (e) { /* fail open */ }
});' 2>/dev/null
exit 0
