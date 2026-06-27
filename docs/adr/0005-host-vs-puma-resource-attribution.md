# 0005. Host vs Puma resource attribution (ResourceAttribution)

- **Status:** Accepted
- **Date:** 2026-06-22
- **Context:** TOP shows CPU and memory for the **host or cgroup** where the CLI runs. Worker boxes and PROCESSES show only **Puma** PIDs from the JSON. High host usage with quiet Puma workers (e.g. Sidekiq, Postgres on the same machine) misleads operators into blaming Puma backlog. The dashboard must not become a full `top` clone.
- **Decision:** Introduce **`ResourceAttribution`** with three progressive disclosure levels:
  1. **TOP suffix** — `Puma ~X%` / `Puma ~Y` on CPU/Memory lines when host usage is elevated (≥ ~60%).
  2. **SUMMARY line** — optional `LabelLine` `Host vs Puma` when CPU/memory **gap** crosses warn/crit thresholds (not a JSON field).
  3. **OUTSIDE PUMA panel** — top **3** non-Puma processes by CPU, lazy `ps` scan, toggle **`O`**, hidden by default; auto-show only when warn/crit + enough terminal rows.
  Outsiders scan runs **on demand**, not every 5s poll.
- **Consequences:**
  - Honest limitations documented: summed RSS ≠ host memory; `%cpu` can exceed 100% multi-core; remote CLI omits attribution entirely.
  - `TopRenderer`, `SummaryRenderer`, and `OutsidersRenderer` share one `Attribution` object per frame.
  - `--no-top` and layout `compact` disable all three levels.
  - Future ADR (e.g. 0006) if curses or outsider sort-by-rss is added.

**Related:** [CLI UI spec — Host vs Puma](../cli/ui-spec.md#host-vs-puma-resourceattribution), [CLI TDD](../cli/tdd.md#resourceattribution)
