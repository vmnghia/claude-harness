---
investigation: <folder>
author: incident-investigator
created: YYYY-MM-DD
---

# Capture sheet: <what these queries settle>

Queries an agent can't run itself (log search, dashboards, a warehouse), written for the owner to
run. Raw results go in **one** file, `results.txt` in this folder, each pasted under its own
`===== Qn =====` marker line. The agent splits it by marker with a script and never reads it
whole; this sheet records only the small numbers below.

## What we know so far

Timeline in one timezone (say which), one line per event, each with its source.

## Queries

### Q1 — <short name>

- **Why:** which hypothesis this confirms or kills, and what result would do which.
- **Where:** system + index/table + time window (state the clock: log ingest time vs event time).
- **Query:**
  ```
  <query, exactly as it should be pasted>
  ```
- **Coverage check:** how to tell the query saw everything it should (e.g. expected number of
  indices/shards/partitions searched). A query over less than you think returns clean, wrong
  answers.
- **Size check:** run with no rows first (count only) when the result could be large.
- **Marker:** `===== Q1 =====`
- **Result:** (filled by the agent from `results.txt`: coverage value, total hits, small aggregates)

### Q2 — …
