#!/usr/bin/env bash
# PreToolUse(Bash) hook — the Bash boundary for adversarial-reviewer and review-judge.
# Registered in settings.json for every Bash call; it reads the call's `agent_type` and allows
# everything from any other caller (the main session, Coder, the research team). A hook in an
# agent file's own frontmatter never fired for PreToolUse here (measured 2026-10-22, Claude Code
# 2.1.308, fresh `claude -p`), which is why this one is project-wide and self-scoping.
#
# Allowed, and nothing else:
#   - read-only git: status, diff, log, show, merge-base, rev-parse, branch --show-current,
#     check-ignore, ls-files (never --output)
#   - a throwaway script under the session scratchpad: `node <path>` or `python3 -I <path>`,
#     where <path> is /tmp/claude-*/…/scratchpad/… without `..`; `cd` and `mkdir -p` to such a
#     path; a relative script after a `cd` into one
#   - writing such a script: a redirect or a *quoted* heredoc whose target is a scratchpad path
#   - read-only filters: cat, head, tail, wc, grep, rg, sed (never -i), sort, uniq, cut, tr, ls,
#     find (never -delete/-exec/-ok/-fprint), sha256sum, xargs (only onto sha256sum/wc/grep/cat),
#     awk (no `>` or system() in the program), diff, comm, jq, stat, basename, dirname, realpath,
#     pwd, date, echo, printf, true, timeout <allowed command>
# Denied: any other command word, any redirect outside the scratchpad or /dev/null, `$(`,
# backticks, `${`, env assignments, unquoted heredocs, `..` in a scratchpad path, and any
# segment of a compound command that fails the above. Fail closed: unreadable input is denied.
# Exit 0 = allow. Exit 2 = deny; stderr is shown to the agent.

INPUT=$(cat)

deny() {
  echo "review-bash-gate: DENIED — $1. Hunters and the judge may run only read-only git and throwaway scripts under the session scratchpad (policy: .claude/guides/adversarial-review.md § Tool boundaries; this is policy, not an error — do not retry the same command)" >&2
  exit 2
}

VERDICT=$(printf '%s' "$INPUT" | node -e '
  var d = "";
  process.stdin.on("data", function (c) { d += c; });
  process.stdin.on("end", function () {
    var j;
    try { j = JSON.parse(d); } catch (e) { return; }
    if (String(j.tool_name || "") !== "Bash") return process.stdout.write("allow");
    var who = String(j.agent_type || "");
    if (who !== "adversarial-reviewer" && who !== "review-judge") return process.stdout.write("allow");
    var cmd = String((j.tool_input || {}).command || "");
    if (!cmd.trim()) return process.stdout.write("empty command");
    process.stdout.write(verdict(cmd));
  });

  var SCRATCH = /^\/tmp\/claude-[^\/\s]+\/[^\s]*\/scratchpad\/[^\s]*$/;
  function isScratch(p) {
    p = p.replace(/^["\x27]|["\x27]$/g, "");
    return SCRATCH.test(p) && !/(^|\/)\.\.(\/|$)/.test(p) && !/\/\.\.\//.test(p);
  }
  var GIT_RO = /^git\s+(status|diff|log|show|merge-base|rev-parse|branch\s+--show-current|check-ignore|ls-files)(\s|$)/;
  var FILTERS = { cat:1, head:1, tail:1, wc:1, grep:1, rg:1, sed:1, sort:1, uniq:1, cut:1, tr:1, ls:1, find:1,
    sha256sum:1, xargs:1, awk:1, diff:1, comm:1, jq:1, stat:1, basename:1, dirname:1, realpath:1, pwd:1,
    date:1, echo:1, printf:1, "true":1 };
  var XARGS_OK = { sha256sum:1, wc:1, grep:1, cat:1 };

  function verdict(cmd) {
    // 1. Split off a heredoc body: it is script content, scanned for nothing; the delimiter must be quoted.
    var shell = cmd, m = cmd.match(/<<-?\s*(["\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n/);
    if (m) {
      if (!m[1]) return "unquoted heredoc (<<" + m[2] + ") expands shell inside the script; use <<\x27" + m[2] + "\x27";
      var start = m.index + m[0].length, end = cmd.indexOf("\n" + m[2], start - 1);
      shell = cmd.slice(0, m.index + m[0].length - 1) + (end >= 0 ? cmd.slice(end + 1 + m[2].length) : "");
      if (/<</.test(shell.slice(m.index + m[0].length - 1))) return "more than one heredoc";
    }
    // 2. No expansion or substitution anywhere in the shell part.
    if (/\$\(|`|\$\{|\$[A-Za-z_]/.test(shell)) return "command substitution or variable expansion";
    if (/^\s*[A-Za-z_][A-Za-z0-9_]*=/.test(shell)) return "environment assignment";
    // 3. Every segment of a compound command must pass.
    var segs = shell.split(/\n|&&|\|\||;|\|(?!\|)/), cwdScratch = false;
    for (var i = 0; i < segs.length; i++) {
      var s = segs[i].trim(); if (!s) continue;
      var r = checkSegment(s, cwdScratch); if (r !== "allow") return r;
      var cdm = s.match(/^cd\s+(\S+)$/); if (cdm && isScratch(cdm[1])) cwdScratch = true;
    }
    return "allow";
  }

  function checkSegment(s, cwdScratch) {
    // redirects: only into the scratchpad or /dev/null; fd dups are fine
    var re = /(^|[^0-9&])(\d*)>>?\s*(\S+)/g, rm;
    while ((rm = re.exec(s))) {
      var t = rm[3];
      if (/^&\d$/.test(t) || t === "/dev/null") continue;
      if (!isScratch(t)) return "redirect to " + t + " (only the session scratchpad or /dev/null)";
    }
    var w = s.split(/\s+/), cw = w[0];
    if (cw === "timeout") { w = w.slice(1); while (w.length && /^-|^\d/.test(w[0])) w = w.slice(1); return checkSegment(w.join(" "), cwdScratch); }
    if (cw === "git") {
      if (!GIT_RO.test(s)) return "git \x27" + (w[1] || "") + "\x27 is not read-only";
      if (/--output/.test(s)) return "git --output writes a file";
      return "allow";
    }
    if (cw === "node" || cw === "python3") {
      var args = w.slice(1);
      if (cw === "python3") { if (args[0] !== "-I") return "python3 without -I (isolated mode)"; args = args.slice(1); }
      if (!args.length || /^-/.test(args[0])) return cw + " with a flag or inline code instead of a scratchpad script";
      var p = args[0];
      if (isScratch(p)) return "allow";
      if (cwdScratch && !/^\//.test(p) && !/(^|\/)\.\.(\/|$)/.test(p)) return "allow";
      return cw + " script outside the session scratchpad: " + p;
    }
    if (cw === "cd" || cw === "mkdir") {
      var tgt = w[w.length - 1];
      if (cw === "mkdir" && w[1] !== "-p") return "mkdir without -p";
      return isScratch(tgt) ? "allow" : cw + " outside the session scratchpad: " + tgt;
    }
    if (cw === "tee") return isScratch(w[w.length - 1]) ? "allow" : "tee outside the session scratchpad";
    if (!FILTERS[cw]) return "command \x27" + cw + "\x27 is not on the read-only list";
    if (cw === "sed" && /(^|\s)-[a-zA-Z]*i/.test(s)) return "sed -i edits in place";
    if (cw === "find" && /-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b/.test(s)) return "find with a writing or executing action";
    if (cw === "awk" && /[>]|system\s*\(/.test(s.replace(/^awk\s+/, ""))) return "awk program writes or executes";
    if (cw === "xargs") {
      var a = w.slice(1); while (a.length && /^-/.test(a[0])) a = a.slice(1);
      if (!a.length || !XARGS_OK[a[0]]) return "xargs onto \x27" + (a[0] || "") + "\x27 (only sha256sum, wc, grep, cat)";
    }
    return "allow";
  }
' 2>/dev/null)

[ -z "$VERDICT" ] && deny "could not read the tool call (malformed input or node unavailable)"
[ "$VERDICT" = "allow" ] && exit 0
deny "$VERDICT"
