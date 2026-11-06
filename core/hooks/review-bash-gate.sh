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
#     path; a relative script after a `cd` into one; `cd` to exactly the project root
#     ($CLAUDE_PROJECT_DIR, by realpath), so an agent whose cwd moved into its scratchpad can return
#   A `cd` (absolute path only: a relative one follows CDPATH) moves the later commands of the call
#   only as `cd <path> && …`, never after `|` or `||` and with only `&&` / `|` after it, since bash
#   would otherwise run them in a subshell, skip the cd, or carry on after a failed one
#   - writing such a script: a redirect, `tee` or a *quoted* heredoc whose targets are all
#     scratchpad paths
#   - read-only filters: cat, head, tail, wc, grep, rg (never --pre/--pre-glob/--hostname-bin),
#     sed (only as `sed --sandbox …`, never -i), sort (never -o/--output/--compress-program),
#     uniq (at most one file: a second one is written), cut, tr, ls,
#     find (never -delete/-exec/-execdir/-ok/-okdir/-fprint/-fprint0/-fprintf/-fls), sha256sum,
#     xargs (only -0 -r -t -x and numeric -n/-P/-L/-s, onto sha256sum/wc/grep/cat),
#     awk (options -F/-v only; no `>`, `|`, system() or `@` in the program), diff, comm, jq, stat,
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
#     `.claude/scripts/verify-quote.sh`, optionally behind `./` or an absolute prefix, no `..`, and
#     its realpath (from the call's cwd) must equal that of $CLAUDE_PROJECT_DIR/.claude/scripts/
#     verify-quote.sh (a copy elsewhere, a symlink or a missing file is denied); then exactly two
#     words (the URL and the quote, each built from "…", '…', backslash-escaped characters and
#     unquoted characters without * ? [, so 'don'\''t' is one word)
#   Compound commands are split at separators outside quotes only (`grep 'a; b'` is one command).
# Denied: any other command word, any redirect (`&>`, `1&>`, `>|`, `<>` too; every unquoted `>`
# is checked) outside the scratchpad or /dev/null, `$(`, backticks, `${`, env assignments,
# unquoted heredocs and any heredoc but `<<'WORD'` / `<<"WORD"` (no `<<-`; a `<<` inside quotes is
# text, not a heredoc; the header line must end on its line and the body at a line exactly WORD),
# a lone `&` (it runs the next command unchecked), process substitution
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
  var path = require("path"), fs = require("fs");

  var GATED = { "adversarial-reviewer":1, "review-judge":1, "research-critic":1, "research-judge":1 };
  // The one script research-critic/research-judge may run, with exactly a URL and a quote after it.
  var VQ_PATH = /^(\.\/|\/[^\s]+\/)?\.claude\/scripts\/verify-quote\.sh$/;
  // One shell word in pieces, as bash reads it: "…" (no backslash), \x27…\x27, a backslash-escaped
  // character (\x27don\x27\\\x27\x27t\x27 is one word: measured 2026-11-06), or plain characters without a glob.
  var VQ_WORD = "(?:\"[^\"\\\\]*\"|\x27[^\x27]*\x27|\\\\\\S|[^\\s\"\x27\\\\*?\\[])+";
  // Where the one allowed script really is: the project root is CLAUDE_PROJECT_DIR (the hook has no git).
  function projectRoot() { return process.env.CLAUDE_PROJECT_DIR || process.cwd(); }
  // `cd <project root>` is allowed, so an agent whose cwd moved into its scratchpad can get back to
  // where the relative script and a repo it may run git in are (measured 2026-11-06).
  function isRoot(word, cwd) {
    try { return fs.realpathSync(path.resolve(cwd, word.replace(/^["\x27]|["\x27]$/g, ""))) === fs.realpathSync(projectRoot()); }
    catch (e) { return false; }
  }
  function vqPinned(word, cwd) {
    try {
      var root = projectRoot();
      return fs.realpathSync(path.resolve(cwd, word)) === fs.realpathSync(path.join(root, ".claude/scripts/verify-quote.sh"));
    } catch (e) { return false; }
  }
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

  // Index of the first `<<` that bash parses as an operator: outside quotes and not escaped, with the
  // same quote rules as unquoted(). `<<<` (a here-string) is skipped. -1 when there is none.
  function heredocAt(s) {
    var q = "";
    for (var i = 0; i < s.length; i++) {
      var c = s[i];
      if (c === "\\" && q !== "\x27") { i++; continue; }
      if (q) { if (c === q) q = ""; continue; }
      if (c === "\x27" || c === "\"") { q = c; continue; }
      if (c === "<" && s[i + 1] === "<") { if (s[i + 2] === "<") { i += 2; continue; } return i; }
    }
    return -1;
  }

  function verdict(cmd, cwd, who) {
    // 1. Split off a heredoc body: it is script content, scanned for nothing. Only one shape is
    //    modelled, and anything else is denied: an unquoted `<<` (heredocAt) followed by one quoted
    //    word, `<<\x27EOF\x27` or `<<"EOF"`, that ends the word, and a body that ends at the first line
    //    exactly equal to it. A `<<` inside quotes is no heredoc to bash (measured 2026-11-05: a
    //    quoted one hid a real command); `<<-` ends at a tab-indented line; `<<\x27E\x27X` ends at EX.
    var shell = cmd, at = heredocAt(cmd);
    if (at >= 0) {
      var rest = cmd.slice(at);
      if (/^<<-/.test(rest)) return "<<- heredoc (it ends at a tab-indented line); use <<\x27EOF\x27";
      var un = rest.match(/^<<\s*([A-Za-z_][A-Za-z0-9_]*)/);
      if (un) return "unquoted heredoc (<<" + un[1] + ") expands shell inside the script; use <<\x27" + un[1] + "\x27";
      var m = rest.match(/^<<\s*(["\x27])([A-Za-z_][A-Za-z0-9_]*)\1(?=[ \t;&|<>)]|\n)[^\n]*\n/);
      if (!m) return "heredoc shape not modelled (only <<\x27WORD\x27 or <<\"WORD\" ending the word)";
      // The body starts after the logical line, so the header line must end where it ends: no quote
      // left open and no backslash-newline (either would start the body later than the split here).
      var hl = rest.slice(0, m[0].length - 1);
      if (unquoted(hl) === null || /\\$/.test(hl)) return "heredoc header line continues onto the next line (open quote or trailing backslash)";
      var head = at + m[0].length, lines = cmd.slice(head).split("\n"), n = -1;
      for (var li = 0; li < lines.length; li++) if (lines[li] === m[2]) { n = li; break; }
      if (n < 0) return "heredoc without a line that is exactly its terminator " + m[2];
      shell = cmd.slice(0, head - 1) + (n + 1 < lines.length ? "\n" + lines.slice(n + 1).join("\n") : "");
      if (/<</.test(shell.slice(at + 2))) return "more than one heredoc";
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
    // 4. Every segment of a compound command must pass. Separators are found in `bare`, so a `;`,
    //    `|` or `&&` inside quotes stays in its word (a quote with `;` was split and denied:
    //    measured 2026-11-06). `bare` has the length of `shell`, so its indices cut `shell`.
    var segs = [], seps = [], from = 0;   // seps[i]: the separator after segs[i] ("" at the end)
    for (var k = 0; k < bare.length; k++) {
      var two = bare.substr(k, 2);
      if (two === "&&" || two === "||") { segs.push(shell.slice(from, k)); seps.push(two); from = k + 2; k++; }
      else if (bare[k] === "\n" || bare[k] === ";" || bare[k] === "|") { segs.push(shell.slice(from, k)); seps.push(bare[k]); from = k + 1; }
    }
    segs.push(shell.slice(from)); seps.push("");
    var last = -1; for (var q = 0; q < segs.length; q++) if (segs[q].trim()) last = q;
    var cwdScratch = false;
    for (var i = 0; i < segs.length; i++) {
      var s = segs[i].trim(); if (!s) continue;
      var r = checkSegment(s, cwdScratch, cwd, who); if (r !== "allow") return r;
      if (!/^cd(\s|$)/.test(s)) continue;
      // A cd moves later commands only where bash surely ran it, in this shell, before them: not after
      // | or || (a subshell, or skipped), not before | (a subshell), and with only && or | after it
      // (after ; || or a newline the rest also runs when the cd failed, in the old directory).
      // Security review of 3c4a885, 2026-11-06: `cd <root> | bash <relative verify-quote>` ran the
      // scratchpad copy while the gate resolved the root one.
      var before = i ? seps[i - 1] : "";
      if (before === "|" || before === "||") return "cd after | or || (it runs in a subshell or not at all); start with cd <path> &&";
      for (var q2 = i; q2 < last; q2++)
        if (!(seps[q2] === "&&" || (q2 > i && seps[q2] === "|"))) return "after a cd, join commands with && (and | after the first one): with ; || or a newline they also run in the old directory when the cd fails";
      var cdm = s.match(/^cd\s+(\S+)$/); if (!cdm) return "cd takes exactly one path";
      var tgt = cdm[1].replace(/^["\x27]|["\x27]$/g, "");
      if (!/^\//.test(tgt)) return "cd to a relative path (CDPATH can send it elsewhere); give the absolute path";
      if (isScratch(cdm[1])) { cwdScratch = true; cwd = path.posix.normalize(tgt); }
      else if (isRoot(cdm[1], cwd)) { cwd = projectRoot(); cwdScratch = false; }
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
      if (!vm || !VQ_PATH.test(vm[1]) || /(^|\/)\.\.(\/|$)/.test(vm[1]) || !vqPinned(vm[1], cwd)) return "bash is allowed only as bash .claude/scripts/verify-quote.sh <url> \x27<quote>\x27 (the project\x27s own script, no .. in the path, exactly two arguments, no unquoted glob; an apostrophe in the quote is \x27don\x27\\\x27\x27t\x27). From any other directory use the absolute path, bash " + path.join(projectRoot(), ".claude/scripts/verify-quote.sh") + " …, or cd " + projectRoot() + " first";
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
      if (cw === "cd" && ops.length === 1 && isRoot(ops[0], cwd)) return "allow";
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
      // `|` too: `print | "cmd"`, `"cmd" | getline` and gawk `|&` run a command (measured 2026-11-06).
      // An alternation /a|b/ is denied with it; use grep -E for that.
      if (/[>|@]|system\s*\(/.test(args.join(" "))) return "awk program writes or executes (>, |, system() or @); for /a|b/ use grep -E";
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
