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
# Targets (2026-10-22, SSRF hardening): `https:` or `data:` only. The hostname is resolved
# first and loopback, private (RFC 1918, CGNAT), link-local, multicast and unspecified
# addresses are refused, for IPv4, IPv6 and v4-mapped v6. Redirects are followed by hand,
# at most 5 hops, and every hop gets the same check. A quote from a page web-reader cites
# never needs the local network.
#
# Output (one line): MATCH | NO MATCH | UNCHECKABLE: <reason>
# Exit: 0 MATCH · 1 NO MATCH · 2 UNCHECKABLE (refused target, fetch failed, not HTML/text,
# or too little text, e.g. a JS-rendered shell) · 64 usage. UNCHECKABLE is never a pass.

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: verify-quote.sh <url> <quote>" >&2
  exit 64
fi

URL="$1" QUOTE="$2" node -e '
  const url = process.env.URL, quote = process.env.QUOTE;
  const dns = require("dns").promises, net = require("net");
  const ENT = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "\x27", nbsp: " ", ndash: "-", mdash: "-",
    lsquo: "\x27", rsquo: "\x27", ldquo: "\"", rdquo: "\"", hellip: "..." };
  const norm = (s) => s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d))
    .replace(/&([a-z]+);/gi, (m, n) => (n.toLowerCase() in ENT ? ENT[n.toLowerCase()] : m))
    .replace(/[‘’]/g, "\x27").replace(/[“”]/g, "\"")
    .replace(/[‐-―]/g, "-").replace(/…/g, "...")
    .replace(/[ ​]/g, " ")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/^[ \t]*(#{1,6}|>|[-+*](?=\s))[ \t]*/gm, "")
    .replace(/[`|]/g, " ").replace(/\*\*?|(^|\s)_+|_+(?=\s|$)/g, "$1")
    .replace(/\s+/g, " ")
    .replace(/ ([.,;:!?)\]])/g, "$1").replace(/([(\[]) /g, "$1")
    .trim();
  const done = (code, msg) => { console.log(msg); process.exit(code); };

  // --- target policy ---------------------------------------------------------------
  // Blocked ranges, parsed by net.BlockList rather than matched by regex. Any IPv6 literal that
  // embeds an IPv4 address (v4-mapped, v4-compatible, NAT64, 6to4) is refused outright: those
  // forms exist to reach IPv4 targets, and a hex-encoded mapped address would otherwise slip past
  // a dotted-quad check.
  const bl = new net.BlockList(), q = (a, b, c, d) => [a, b, c, d].join(".");   // ranges as numbers: no dotted quad in source
  [[q(0, 0, 0, 0), 8], [q(10, 0, 0, 0), 8], [q(100, 64, 0, 0), 10], [q(127, 0, 0, 0), 8], [q(169, 254, 0, 0), 16],
   [q(172, 16, 0, 0), 12], [q(192, 0, 0, 0), 24], [q(192, 168, 0, 0), 16], [q(198, 18, 0, 0), 15], [q(224, 0, 0, 0), 3]]
    .forEach(([a, p]) => bl.addSubnet(a, p, "ipv4"));
  [["fc00::", 7], ["fe80::", 10], ["fec0::", 10], ["ff00::", 8]].forEach(([a, p]) => bl.addSubnet(a, p, "ipv6"));
  bl.addAddress("::", "ipv6"); bl.addAddress("::1", "ipv6");
  const embedsV4 = (v6) => {
    const v = v6.toLowerCase();
    if (/\d+\.\d+\.\d+\.\d+/.test(v)) return true;                       // dotted quad inside a v6 literal
    const full = expand6(v); if (!full) return true;                          // unparseable: refuse
    return /^0000:0000:0000:0000:0000:(0000|ffff):/.test(full)               // ::a.b.c.d, ::ffff:a.b.c.d (hex form too)
      || /^0064:ff9b:/.test(full) || /^2002:/.test(full);                     // NAT64, 6to4
  };
  const expand6 = (v) => {
    const parts = v.split("::"); if (parts.length > 2) return null;
    const head = parts[0] ? parts[0].split(":") : [], tail = parts[1] ? parts[1].split(":") : [];
    const fill = parts.length === 2 ? 8 - head.length - tail.length : 0; if (fill < 0 || head.length + tail.length + fill !== 8) return null;
    const groups = head.concat(Array(fill).fill("0"), tail);
    if (!groups.every((g) => /^[0-9a-f]{1,4}$/.test(g))) return null;
    return groups.map((g) => g.padStart(4, "0")).join(":");
  };
  const privateIp = (ip) => {
    if (net.isIPv4(ip)) return bl.check(ip, "ipv4") ? "private address " + ip + " refused" : null;
    if (!net.isIPv6(ip)) return "address " + ip + " is neither IPv4 nor IPv6";
    if (bl.check(ip, "ipv6")) return "private address " + ip + " refused";           // ::, ::1, fc00::/7, fe80::/10, ff00::/8
    if (embedsV4(ip)) return "IPv6 literal " + ip + " embeds an IPv4 address; refused";
    return null;
  };
  // Returns null when the URL may be fetched, else the refusal reason.
  const refuse = async (u) => {
    let p; try { p = new URL(u); } catch (e) { return "not a URL"; }
    if (p.protocol === "data:") return null;
    if (p.protocol !== "https:") return "scheme " + p.protocol + " refused (https: only)";
    const host = p.hostname.replace(/^\[|\]$/g, "");
    if (!host) return "no host";
    if (net.isIP(host)) return privateIp(host);
    let addrs;
    try { addrs = await dns.lookup(host, { all: true }); } catch (e) { return "DNS lookup failed (" + (e.code || e.name) + ")"; }
    if (!addrs.length) return "DNS lookup returned nothing";
    for (const a of addrs) { const r = privateIp(a.address); if (r) return r + " (resolved from " + host + ")"; }
    return null;
  };

  (async () => {
    let res, current = url;
    for (let hop = 0; ; hop++) {
      const why = await refuse(current);
      if (why) return done(2, "UNCHECKABLE: " + why);
      try {
        res = await fetch(current, { redirect: "manual", signal: AbortSignal.timeout(20000),
          headers: { "user-agent": "Mozilla/5.0 verify-quote", accept: "text/html,text/plain,*/*" } });
      } catch (e) { return done(2, "UNCHECKABLE: fetch failed (" + (e.cause && e.cause.code || e.name) + ")"); }
      if ([301, 302, 303, 307, 308].includes(res.status)) {
        const loc = res.headers.get("location");
        if (!loc) return done(2, "UNCHECKABLE: redirect without Location");
        if (hop >= 5) return done(2, "UNCHECKABLE: more than 5 redirects");
        current = new URL(loc, current).href;
        continue;
      }
      break;
    }
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
