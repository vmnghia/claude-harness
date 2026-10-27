#!/usr/bin/env bash
# PreToolUse(Bash) hook — the Bash boundary for adversarial-reviewer, review-judge, research-critic
# and research-judge.
# Registered in settings.json for every Bash call; it reads the call's `agent_type` and allows
# everything from any other caller (the main session, Coder, the research team). A hook in an
# agent file's own frontmatter never fired for PreToolUse here (measured 2026-10-22, Claude Code
# 2.1.308, fresh `claude -p`), which is why this one is project-wide and self-scoping.
#
# Allowed, and nothing else:
#   - read-only git: status, diff, log, show, merge-base, rev-parse, branch --show-current,
#     check-ignore, ls-files (never --output); `git -C <path>` before them is fine, `-c` is not.
#     Never against a repo under /tmp/claude- (cwd, `cd` or `-C`): a hunter can write one there
#     whose .git/config runs a command on `git status`
#   - a throwaway script under the session scratchpad: `node <path>` or `python3 -I <path>`,
#     where <path> is /tmp/claude-*/…/scratchpad/… without `..`; `cd` and `mkdir -p` to such a
#     path; a relative script after a `cd` into one
#   - writing such a script: a redirect, `tee` or a *quoted* heredoc whose targets are all
#     scratchpad paths
#   - read-only filters: cat, head, tail, wc, grep, rg (never --pre/--pre-glob/--hostname-bin),
#     sed (only as `sed --sandbox …`, never -i), sort (never -o/--output/--compress-program),
#     uniq (at most one file: a second one is written), cut, tr, ls,
#     find (never -delete/-exec/-execdir/-ok/-okdir/-fprint/-fprint0/-fprintf/-fls), sha256sum,
#     xargs (only -0 -r -t -x and numeric -n/-P/-L/-s, onto sha256sum/wc/grep/cat),
#     awk (options -F/-v only; no `>`, system() or `@` in the program), diff, comm, jq, stat,
#     basename, dirname, realpath, pwd, date, echo, printf, true, timeout <allowed command>
#   Option checks read the words as the program receives them (`'-i'` is `-i`), and a long option
#   is denied when it is a prefix of a denied one: GNU tools expand `sort --outp` to `--output`.
#   Shapes that rewrite words before the program sees them are denied outside quotes: `$'…'` /
#   `$"…"` (escapes: `$'\x2dexec'` is -exec), brace expansion (`{-i,x}` is two words), and a glob
#   in the arguments of sed/sort/rg/find/awk/xargs/uniq (a file named `--pre=sh` turned
#   `rg x *` into running sh on every file: measured 2026-10-26).
#   - research-critic and research-judge only, two more (everything else here binds all four types):
#     `git grep` (the read-only git rules apply; `-O`/`--open-files-in-pager` runs a program, so it
#     is denied) and `bash .claude/scripts/verify-quote.sh <url> '<quote>'`: the script path is
#     `.claude/scripts/verify-quote.sh`, optionally behind `./` or an absolute prefix, no `..`,
#     then exactly two words (the URL and the quote, each one quoted or unquoted word)
# Denied: any other command word, any redirect (`&>`, `1&>`, `>|`, `<>` too; every unquoted `>`
# is checked) outside the scratchpad or /dev/null, `$(`, backticks, `${`, env assignments,
# unquoted heredocs, a lone `&` (it runs the next command unchecked), process substitution
# `<(…)` / `>(…)`, unbalanced quotes, `..` in a scratchpad path, and any segment of a compound
# command that fails the above, and an unquoted word-initial `#` (bash and the quote scan would
# disagree inside a comment). Fail closed: unreadable input is denied. Every bypass closed on
# 2026-10-26 was measured against this file first.
# Exit 0 = allow. Exit 2 = deny; stderr is shown to the agent.

INPUT=$(cat)

deny() {
  echo "review-bash-gate: DENIED — $1. Hunters, the review judge and the research critic/judge may run only read-only git and throwaway scripts under the session scratchpad; the research critic/judge may also run git grep and verify-quote.sh (policy: .claude/guides/adversarial-review.md § Tool boundaries; this is policy, not an error — do not retry the same command)" >&2
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
    if (!GATED[who]) return process.stdout.write("allow");
    var cmd = String((j.tool_input || {}).command || "");
    if (!cmd.trim()) return process.stdout.write("empty command");
    // `cwd` follows the persisted directory of the Bash tool (measured 2026-10-26), so a `cd` from an
    // earlier call is visible here.
    process.stdout.write(verdict(cmd, String(j.cwd || process.cwd()), who));
  });
  var path = require("path");

  var GATED = { "adversarial-reviewer":1, "review-judge":1, "research-critic":1, "research-judge":1 };
  // The one script research-critic/research-judge may run, with exactly a URL and a quote after it.
  var VQ_PATH = /^(\.\/|\/[^\s]+\/)?\.claude\/scripts\/verify-quote\.sh$/;
  var VQ_WORD = "(?:\"[^\"\\\\]*\"|\x27[^\x27\\\\]*\x27|[^\\s\"\x27\\\\]+)";
  var VQ_CMD = new RegExp("^bash\\s+(\\S+)\\s+" + VQ_WORD + "\\s+" + VQ_WORD + "$");
  var SCRATCH = /^\/tmp\/claude-[^\/\s]+\/[^\s]*\/scratchpad\/[^\s]*$/;
  function isScratch(p) {
    p = p.replace(/^["\x27]|["\x27]$/g, "");
    return SCRATCH.test(p) && !/(^|\/)\.\.(\/|$)/.test(p) && !/\/\.\.\//.test(p);
  }
  // `-C <path>` is the one global option allowed before the subcommand; `-c` stays out (core.pager,
  // core.fsmonitor and diff.external turn a read-only subcommand into arbitrary execution).
  var GIT_C = /^git((?:\s+-C\s+(?:"[^"]*"|\x27[^\x27]*\x27|[^\s"\x27]+))*)\s+/;
  var GIT_RO = /^(status|diff|log|show|merge-base|rev-parse|branch\s+--show-current|check-ignore|ls-files)(\s|$)/;
  var FILTERS = { cat:1, head:1, tail:1, wc:1, grep:1, rg:1, sed:1, sort:1, uniq:1, cut:1, tr:1, ls:1, find:1,
    sha256sum:1, xargs:1, awk:1, diff:1, comm:1, jq:1, stat:1, basename:1, dirname:1, realpath:1, pwd:1,
    date:1, echo:1, printf:1, "true":1 };
  var XARGS_OK = { sha256sum:1, wc:1, grep:1, cat:1 };
  var FIND_ACTIONS = { "-delete":1, "-exec":1, "-execdir":1, "-ok":1, "-okdir":1, "-fprint":1, "-fprint0":1,
    "-fprintf":1, "-fls":1 };

  // The command with every quoted or backslash-escaped character replaced by `_`, so operator checks
  // see only what the shell parses as syntax (`grep "a & b"` has no `&`). null when a quote is open.
  function unquoted(s) {
    var out = "", q = "";
    for (var i = 0; i < s.length; i++) {
      var c = s[i];
      if (c === "\\" && q !== "\x27") { out += "__"; i++; continue; }
      if (q) { if (c === q) { q = ""; out += c; } else out += "_"; continue; }
      if (c === "\x27" || c === "\"") q = c;
      out += c;
    }
    return q ? null : out;
  }
  // GNU tools take any unambiguous prefix of a long option (`sort --outp` is `--output`, `sed --in`
  // is `--in-place`: measured 2026-10-26), so a long option matches every denied name it prefixes.
  function longOpt(args, names) {
    for (var i = 0; i < args.length; i++) {
      var m = args[i].match(/^--([^=]+)/); if (!m) continue;
      for (var k = 0; k < names.length; k++) if (names[k].indexOf(m[1]) === 0) return "--" + names[k];
    }
    return "";
  }
  function some(args, re) { for (var i = 0; i < args.length; i++) if (re.test(args[i])) return args[i]; return ""; }
  function operands(args) { return args.filter(function (a) { return !/^-/.test(a); }); }
  // Tools where a word starting with `-` changes what runs or what is written: an unquoted glob in
  // their arguments can expand to a file named like an option (measured 2026-10-26: a file named
  // `--pre=sh` made `rg x *` run sh on each file).
  var GLOB_SENSITIVE = { sed:1, sort:1, rg:1, find:1, awk:1, xargs:1, uniq:1 };
  // Every unquoted `>` is a redirect operator (`>`, `>>`, `>|`, `&>`, `N>`, `<>`); its target must be
  // the scratchpad or /dev/null, and `>&N` / `>&-` fd dups are fine. Scanning the whole command
  // instead of matching a prefix pattern per segment closes `1&>file` and `>|file` (measured 2026-10-26).
  function redirects(shell, bare) {
    for (var i = bare.indexOf(">"); i >= 0; i = bare.indexOf(">", i + 1)) {
      if (bare[i - 1] === ">") continue;
      var k = i + 1;
      if (bare[k] === ">" || bare[k] === "|") k++;
      var dup = bare[k] === "&"; if (dup) k++;
      while (k < bare.length && (bare[k] === " " || bare[k] === "\t")) k++;
      var e = k;
      while (e < bare.length && !/[\s;&|<>()]/.test(bare[e])) e++;
      var t = shell.slice(k, e).replace(/["\x27\\]/g, "");
      if (dup && /^(\d+|-)$/.test(t)) continue;
      if (t === "/dev/null" || isScratch(t)) continue;
      return "redirect to " + (t || "nothing") + " (only the session scratchpad or /dev/null)";
    }
    return "";
  }

  function verdict(cmd, cwd, who) {
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
    // 3. Syntax the split below does not model, looked for outside quotes: a lone `&` runs the next
    //    command unchecked, and `<(…)` / `>(…)` run one inside an argument (measured 2026-10-26).
    var bare = unquoted(shell);
    if (bare === null) return "unbalanced quotes";
    // Every check below reads `bare`, so it trusts unquoted() to end each quote where bash does. A
    // comment is where they part (bash ignores a quote after `#`), so a word-initial unquoted `#` is
    // denied rather than modelled.
    if (/(^|[\s;&|()])#/.test(bare)) return "a shell comment (#): write the command without it";
    if (/[<>]\(/.test(bare)) return "process substitution <(…) / >(…)";
    if (/&/.test(bare.replace(/&&|[<>]&(\d+|-)|&>>?/g, ""))) return "a lone & (it would run the next command unchecked)";
    if (/\$["\x27]/.test(bare)) return "$\x27…\x27 / $\"…\" quoting (its escapes hide what the program receives)";
    if (/\{[^\s}]*(,|\.\.)/.test(bare)) return "brace expansion {a,b} / {1..3} (it turns one word into several)";
    var rd = redirects(shell, bare); if (rd) return rd;
    // 4. Every segment of a compound command must pass. The split ignores quotes, so a separator
    //    inside quotes only over-splits: the piece after it starts with a quote and is denied.
    var segs = shell.split(/\n|&&|\|\||;|\|(?!\|)/), cwdScratch = false;
    for (var i = 0; i < segs.length; i++) {
      var s = segs[i].trim(); if (!s) continue;
      var r = checkSegment(s, cwdScratch, cwd, who); if (r !== "allow") return r;
      var cdm = s.match(/^cd\s+(\S+)$/); if (cdm && isScratch(cdm[1])) cwdScratch = true;
    }
    return "allow";
  }

  function checkSegment(s, cwdScratch, cwd, who) {
    var research = who === "research-critic" || who === "research-judge";
    var w = s.split(/\s+/), cw = w[0];
    // The arguments as the program receives them: quotes and backslashes removed (`\x27-i\x27` is -i).
    var args = s.replace(/["\x27\\]/g, "").split(/\s+/).slice(1), hit;
    if (cw === "timeout") { w = w.slice(1); while (w.length && /^-|^\d/.test(w[0])) w = w.slice(1); return checkSegment(w.join(" "), cwdScratch, cwd, who); }
    if (research && cw === "bash") {
      var vm = s.match(VQ_CMD);
      if (!vm || !VQ_PATH.test(vm[1]) || /(^|\/)\.\.(\/|$)/.test(vm[1])) return "bash is allowed only as bash .claude/scripts/verify-quote.sh <url> \x27<quote>\x27 (no .. in the path, exactly two arguments)";
      return "allow";
    }
    if (cw === "git") {
      var gm = s.match(GIT_C), sub = gm ? s.slice(gm[0].length) : "";
      var grepOk = research && /^grep(\s|$)/.test(sub);
      if (grepOk && (some(args, /^-[a-zA-Z]*O/) || longOpt(args, ["open-files-in-pager"]))) return "git grep -O runs a program";
      if (!grepOk && !GIT_RO.test(sub)) return "git \x27" + (sub.split(/\s+/)[0] || "") + "\x27 is not read-only";
      // Every path a hunter may write is under /tmp/claude-, and a repo there can carry a .git/config
      // whose core.fsmonitor runs on `git status` (measured 2026-10-26). Resolve where git will run.
      if (cwdScratch) return "git run from the scratchpad (a repo written there can execute its config)";
      var dir = cwd, cre = /-C\s+("[^"]*"|\x27[^\x27]*\x27|[^\s"\x27]+)/g, cm;
      while ((cm = cre.exec(gm[1]))) dir = path.posix.resolve(dir, cm[1].replace(/^["\x27]|["\x27]$/g, ""));
      if (/^\/tmp\/claude-/.test(path.posix.normalize(dir) + "/")) return "git against " + dir + " (a repo under /tmp/claude- can execute its config)";
      if (/--output/.test(s)) return "git --output writes a file";
      return "allow";
    }
    if (cw === "node" || cw === "python3") {
      var nargs = w.slice(1);
      if (cw === "python3") { if (nargs[0] !== "-I") return "python3 without -I (isolated mode)"; nargs = nargs.slice(1); }
      if (!nargs.length || /^-/.test(nargs[0])) return cw + " with a flag or inline code instead of a scratchpad script";
      var p = nargs[0];
      if (isScratch(p)) return "allow";
      if (cwdScratch && !/^\//.test(p) && !/(^|\/)\.\.(\/|$)/.test(p)) return "allow";
      return cw + " script outside the session scratchpad: " + p;
    }
    if (cw === "cd" || cw === "mkdir" || cw === "tee") {
      // Every path operand counts: `tee <repo file> <scratchpad file>` wrote the repo file (measured 2026-10-26).
      if (cw === "mkdir" && args[0] !== "-p") return "mkdir without -p";
      var ops = operands(args);
      if (!ops.length) return cw + " without a scratchpad path";
      for (var o = 0; o < ops.length; o++) if (!isScratch(ops[o])) return cw + " outside the session scratchpad: " + ops[o];
      return "allow";
    }
    if (!FILTERS[cw]) return "command \x27" + cw + "\x27 is not on the read-only list";
    if (GLOB_SENSITIVE[cw]) {
      var sb = unquoted(s);
      if (sb === null) return "unbalanced quotes";
      if (/[*?[]/.test(sb)) return "unquoted glob in " + cw + " arguments (a file named like an option, e.g. --pre=sh or -i, would become one); quote it, or name the files";
    }
    if (cw === "sed") {
      // --sandbox makes sed itself refuse e (run a command), r and w (files), and the s///e and s///w
      // flags. It must come first: after a `--` it is a file name, and e ran (measured 2026-10-26).
      if (args[0] !== "--sandbox") return "sed without --sandbox as its first argument (sed --sandbox -n \x271,20p\x27 <file>)";
      if (some(args, /^-[a-zA-Z]*i/) || longOpt(args, ["in-place"])) return "sed -i edits in place";
    }
    if (cw === "sort" && (hit = longOpt(args, ["output", "compress-program"]) || (some(args, /^-[a-zA-Z]*o/) ? "-o" : ""))) return "sort " + hit + " writes a file or runs a program";
    if (cw === "rg" && (hit = longOpt(args, ["pre", "pre-glob", "hostname-bin"]))) return "rg " + hit + " runs a program";
    if (cw === "uniq" && operands(args).filter(function (a) { return !/^\d+$/.test(a); }).length > 1) return "uniq with a second file writes it";
    if (cw === "find" && args.some(function (a) { return FIND_ACTIONS[a]; })) return "find with a writing or executing action";
    if (cw === "awk") {
      // gawk -f/-i/-l/-E load code and -o/-p/-d write files; `@f()` calls system() indirectly and
      // @load/@include load code (measured 2026-10-26: `f = "sys" "tem"; @f(…)` ran).
      if ((hit = some(args, /^-[^Fv-]|^--./))) return "awk option " + hit + " (only -F and -v)";
      if (/[>@]|system\s*\(/.test(args.join(" "))) return "awk program writes or executes (>, system() or @)";
    }
    if (cw === "xargs") {
      // Only options that take no argument, or a number: one that takes a word (-I, -d, -a, -E, …)
      // made that word look like the command (measured 2026-10-26: `xargs -I cat sh -c …` ran sh).
      var a = args, k = 0;
      while (k < a.length && /^-/.test(a[k])) {
        if (/^(-0|-r|-t|-x|--null|--no-run-if-empty|--verbose|--exit)$/.test(a[k])) k++;
        else if (/^-[nPLs]\d+$|^--(max-args|max-procs|max-lines|max-chars)=\d+$/.test(a[k])) k++;
        else if (/^-[nPLs]$/.test(a[k]) && /^\d+$/.test(a[k + 1] || "")) k += 2;
        else return "xargs option " + a[k] + " (only -0 -r -t -x and numeric -n/-P/-L/-s)";
      }
      if (!XARGS_OK[a[k]]) return "xargs onto \x27" + (a[k] || "") + "\x27 (only sha256sum, wc, grep, cat)";
    }
    return "allow";
  }
' 2>/dev/null)

[ -z "$VERDICT" ] && deny "could not read the tool call (malformed input or node unavailable)"
[ "$VERDICT" = "allow" ] && exit 0
deny "$VERDICT"
