#!/usr/bin/env python3
"""Truncate a Claude Code transcript so a too-large session can be resumed.

Claude Code's .jsonl is append-only: /compact writes a `compact_boundary`
marker plus a summary message and appends them, but never removes the messages
it summarized. `--resume` replays the whole file, so a session that compacted
successfully can still fail to reload -- and every retry makes the file bigger.

Cutting the file drops the old turns and leaves a valid transcript. Cuts are
only taken at points that cannot orphan a tool_result -- a compact boundary, or
a user turn carrying no tool results -- because the API rejects a tool_result
whose matching tool_use was removed.

  python3 prune-session.py <session.jsonl>            # dry run
  python3 prune-session.py <session.jsonl> --apply    # backup, then truncate
  options: --budget=500000   --hours=3
"""
import datetime, json, os, shutil, sys

CHARS_PER_TOKEN = 3.1   # empirical for mixed prose + code + tool output
IMAGE_CHARS = 5000      # an image costs ~1.6k tok whatever its base64 size
                        # (a `document` block is different -- see weight())
DEFAULT_BUDGET = 500_000
DEFAULT_HOURS = 3.0


def load(path):
    order = []
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if line.strip():
            order.append((i, json.loads(line)))
    return order


def weight(rec):
    """Characters this record contributes to the replayed context.

    Base64 payloads are skipped: a 400 KB screenshot costs the model ~1.6k
    tokens, not 100k, so counting its characters wildly overstates the cost.
    """
    total = [0]
    def walk(node):
        if isinstance(node, str):
            total[0] += len(node)
        elif isinstance(node, list):
            for x in node:
                walk(x)
        elif isinstance(node, dict):
            if node.get("type") == "image":
                total[0] += IMAGE_CHARS
                return
            if node.get("type") == "document":
                # A PDF/doc attachment IS tokenized -- pages become text plus
                # images -- so unlike a screenshot its payload really does cost
                # roughly its own size. Count it.
                total[0] += len((node.get("source") or {}).get("data") or "")
                return
            for k, v in node.items():
                if k not in ("source", "data"):
                    walk(v)
    walk((rec.get("message") or {}).get("content"))
    if isinstance(rec.get("content"), str):
        total[0] += len(rec["content"])
    return total[0]


def when(rec):
    ts = rec.get("timestamp")
    if not ts:
        return None
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))


def safe_cut_points(order):
    """Lines the transcript can be cut at without orphaning a tool_result."""
    pts = []
    for i, rec in order:
        if rec.get("subtype") == "compact_boundary":
            pts.append(i)
            continue
        if rec.get("type") != "user":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str):
            pts.append(i)
        elif isinstance(content, list) and not any(
            isinstance(b, dict) and b.get("type") == "tool_result" for b in content
        ):
            pts.append(i)
    return pts


def cost_from(costs, line):
    """Token cost of keeping everything from `line` onward."""
    return sum(c for i, c in costs if i >= line) / CHARS_PER_TOKEN


def choose_cut_point(order, cuts, costs, budget_tokens, hours):
    """Keep the last `hours` of work, as long as it fits `budget_tokens`.

    Prefers the oldest cut that still covers the retention window, then slides
    forward -- dropping the oldest turns -- until the result fits the budget.
    Raises if even the newest cut is too big; that session can't be salvaged by
    truncation and should be restarted from its handoff summary instead.
    """
    at = {i: when(r) for i, r in order}
    stamps = [t for t in at.values() if t]
    if not stamps:
        raise SystemExit("transcript has no timestamps -- cannot apply a time window")
    newest = max(stamps)
    target = newest - datetime.timedelta(hours=hours)

    # newest cut at or before the target keeps the whole window intact
    covering = [c for c in cuts if (at.get(c) or newest) <= target]
    start = covering[-1] if covering else cuts[0]

    for cut in [c for c in cuts if c >= start]:
        if cost_from(costs, cut) <= budget_tokens:
            return cut

    raise SystemExit(
        f"even the newest cut point ({cuts[-1]}) costs "
        f"~{cost_from(costs, cuts[-1])/1000:,.0f}k tok, over the "
        f"{budget_tokens/1000:,.0f}k budget.\n"
        "-> start a fresh session from the handoff summary instead."
    )


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    apply_ = "--apply" in sys.argv
    budget, hours = DEFAULT_BUDGET, DEFAULT_HOURS
    for a in sys.argv[2:]:
        if a.startswith("--budget="):
            budget = int(a.split("=", 1)[1])
        elif a.startswith("--hours="):
            hours = float(a.split("=", 1)[1])

    order = load(path)
    costs = [(i, weight(r)) for i, r in order]
    cuts = safe_cut_points(order)
    if not cuts:
        sys.exit("no safe cut point found in this transcript")

    total = sum(c for _, c in costs) / CHARS_PER_TOKEN
    print(f"file      : {path}")
    print(f"entries   : {len(order)}   safe cut points: {len(cuts)}")
    print(f"full cost : ~{total/1000:,.0f}k tok")
    print(f"budget    : ~{budget/1000:,.0f}k tok   retention: {hours}h\n")

    cut = choose_cut_point(order, cuts, costs, budget, hours)
    kept = [(i, r) for i, r in order if i >= cut]
    first = next((when(r) for _, r in kept if when(r)), None)
    last = max(t for t in (when(r) for _, r in order) if t)
    span = (last - first).total_seconds() / 3600 if first else 0

    print(f"cut at line {cut} -> keeps {len(kept)} entries "
          f"(~{cost_from(costs, cut)/1000:,.0f}k tok, {span:.1f}h of history)")

    if not apply_:
        print("\n(dry run -- re-run with --apply to write)")
        return

    shutil.copy2(path, path + ".bak")
    surviving = {r.get("uuid") for _, r in kept}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        for _, rec in kept:
            if rec.get("parentUuid") and rec["parentUuid"] not in surviving:
                rec["parentUuid"] = None
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    os.replace(tmp, path)
    print(f"\nbackup : {path}.bak\nwrote  : {path}")


if __name__ == "__main__":
    main()
