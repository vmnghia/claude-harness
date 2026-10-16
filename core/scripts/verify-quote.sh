#!/usr/bin/env bash
# verify-quote.sh <url> <quote> — is <quote> a verbatim substring of the page at <url>?
#
# Mechanical check for web-reader citations (2026-10-16): a quote is citable only
# if the RAW page contains it. Deliberately not WebFetch, which runs a model over the page
# and can hand back a paraphrase. Costs the caller one short command and one line of
# output, no page content in context.
#
# Normalised on BOTH sides, and nothing else: tags stripped, HTML entities decoded,
# whitespace collapsed, typographic quotes/dashes folded, and the syntax WebFetch's
# markdown conversion adds dropped: backticks, `*`/`_` emphasis, `[text](url)` links,
# table pipes (a <table> row comes back as "a | b | c", observed
# 2026-10-16), and line-leading `#`/`>`/`-` markers. Case and
# words are never touched, so a paraphrase, a garbled word or an invented sentence fails.
#
# Output (one line): MATCH | NO MATCH | UNCHECKABLE: <reason>
# Exit: 0 MATCH · 1 NO MATCH · 2 UNCHECKABLE (fetch failed, not HTML/text, or too little
# text, e.g. a JS-rendered shell) · 64 usage. UNCHECKABLE is never a pass.

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: verify-quote.sh <url> <quote>" >&2
  exit 64
fi

URL="$1" QUOTE="$2" node -e '
  const url = process.env.URL, quote = process.env.QUOTE;
  const ENT = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "\x27", nbsp: " ", ndash: "-", mdash: "-",
    lsquo: "\x27", rsquo: "\x27", ldquo: "\"", rdquo: "\"", hellip: "..." };
  const norm = (s) => s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d))
    .replace(/&([a-z]+);/gi, (m, n) => (n.toLowerCase() in ENT ? ENT[n.toLowerCase()] : m))
    .replace(/[‘’]/g, "\x27").replace(/[“”]/g, "\"")
    .replace(/[‐-―]/g, "-").replace(/…/g, "...")
    .replace(/[ ​]/g, " ")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/^[ \t]*(#{1,6}|>|[-+*](?=\s))[ \t]*/gm, "")
    .replace(/[`|]/g, " ").replace(/\*\*?|(^|\s)_+|_+(?=\s|$)/g, "$1")
    .replace(/\s+/g, " ")
    .replace(/ ([.,;:!?)\]])/g, "$1").replace(/([(\[]) /g, "$1")
    .trim();
  const done = (code, msg) => { console.log(msg); process.exit(code); };
  (async () => {
    let res;
    try {
      res = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(20000),
        headers: { "user-agent": "Mozilla/5.0 verify-quote", accept: "text/html,text/plain,*/*" } });
    } catch (e) { return done(2, "UNCHECKABLE: fetch failed (" + (e.cause && e.cause.code || e.name) + ")"); }
    if (!res.ok) return done(2, "UNCHECKABLE: HTTP " + res.status);
    const type = res.headers.get("content-type") || "";
    if (!/html|text|json|xml/i.test(type)) return done(2, "UNCHECKABLE: content-type " + type);
    let body = await res.text();
    body = body.replace(/<(script|style|noscript)\b[\s\S]*?<\/\1>/gi, " ").replace(/<[^>]+>/g, " ");
    const page = norm(body), q = norm(quote);
    if (!q) return done(64, "UNCHECKABLE: empty quote after normalisation");
    if (page.length < 200) return done(2, "UNCHECKABLE: page has under 200 chars of text (JS-rendered?)");
    return page.includes(q) ? done(0, "MATCH") : done(1, "NO MATCH");
  })();
'
