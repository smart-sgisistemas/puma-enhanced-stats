# CLI UI / functional specification

How the **`puma-enhanced-stats`** terminal dashboard **must look and behave**. Target **0.6.0**.

- **Implementation modules:** [tdd.md](tdd.md)
- **HTTP fields:** [JSON contract](../json-contract.md)

Mockups use **78 characters per line** (76 useful columns between `│` and `│`). Borders: simple Unicode only (`┌─┐│└┘`).

---

## Scope

- Boxed dashboard with colors and proportional bars (`MetricLine`) or label + badge (`LabelLine`).
- Sections: **HEADER → TOP → PROCESSES → SUMMARY → WORKERS → FOOTER**; optional **OUTSIDE PUMA** (toggle `O`).
- TOP and PROCESSES hidden with `--no-top` or key **`t`**.
- Six frame layouts; request display inline/stack/auto; prefs in **`~/.pesrc`** (key **`W`** save).
- Modals: Design, Sort, Filter, Help (`?`/`h`). Watch scroll persists between polls ([ADR 0004](../adr/0004-scroll-state-and-alternate-screen.md)).
- Worker `rss`/`cpu` from CLI `ProcessSampler`, not JSON.

---

## Alignment grid

| Column (1-based) | Content |
|------------------|---------|
| 1 | `│` |
| 2 | space |
| 3–22 | **label** (20 chars) |
| 23 | space |
| 24–35 | **value** (12) — **`X / Y`** when a limit exists |
| 36 | space |
| 37–58 | **bar** `[` + 20 + `]` (MetricLine) or **22 spaces** (LabelLine) |
| 59 | space |
| 60–76 | **suffix** — `%`, badge (`ok`, `info`, `WARN`, `CRIT`, `stale N WARN`, `Puma ~…`) |

**Rule:** `[` at column **37**; suffix/badge at column **60** on every MetricLine and LabelLine.

**Exceptions (no grid):** Load (TOP), PROCESSES table, request tables, registry line, modals, footer.

Templates:

```text
MetricLine: {label.ljust(20)} {value.ljust(12)} [{bar 20}] {suffix}
LabelLine:  {label.ljust(20)} {value.ljust(12)} {' ' * 22} {badge}
```

---

## MetricLine vs LabelLine

**`X / Y`:** every metric with a known denominator shows `numerator / denominator` in value (12 chars, truncate with `…`).

**Anti-duplication (SUMMARY):** JSON has 10 `summary` fields; UI shows **7 lines**:

| Schema field | UI treatment |
|--------------|--------------|
| `workers_total` | Denominator of **Workers reporting** — no own line |
| `workers_stale` | Badge **`stale N`** on Workers reporting when `reporting < total` |
| `max_threads_total` | Denominator for Backlog/Busy/Pool — no own line |

| Component | Renderer |
|-----------|----------|
| `synced_at` | LabelLine |
| `requests_dropped`, `requests_truncated` | LabelLine |
| Load (TOP) | free text |
| PROCESSES, requests, `elapsed` | table / text |
| backlog, threads, pool, in-flight, cpu, rss, mem | MetricLine |

Example:

```text
│ backlog              3 / 5        [████████████░░░░░░░░] CRIT              │
│ synced_at            8s ago                              WARN              │
│ Requests truncated   yes                                 info              │
```

---

## Screen skeleton

```text
┌─────────────────────── PUMA ENHANCED STATS ─ v0.6.0 ───────────────────────┐
│ cluster │ sync 5s │ collected 14:32:01                                     │
└────────────────────────────────────────────────────────────────────────────┘
┌─────────────────────────── TOP ─ ocultável (t) ────────────────────────────┐
└────────────────────────────────────────────────────────────────────────────┘
┌──────────────────────── PROCESSES ─ ocultável (t) ─────────────────────────┐
└────────────────────────────────────────────────────────────────────────────┘
┌───────────────────────────────── SUMMARY ──────────────────────────────────┐
└────────────────────────────────────────────────────────────────────────────┘
┌─────────────────── WORKER 0 ─ pid 48201 ─ synced 2s ago ───────────────────┐
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────── FOOTER ──────────────────────────────────┐
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Full dashboard — layout `stacked` (~78 cols)

```text
┌─────────────────────── PUMA ENHANCED STATS ─ v0.6.0 ───────────────────────┐
│ cluster │ sync 5s │ collected 14:32:01                                     │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────── TOP ─ app-server.local ──────────────────────────┐
│ Load   0.42   0.38   0.35        (1 / 5 / 15 min)                          │
│ CPU    usr 12% sys 4% idle 84%    [████░░░░░░░░░░░░░░░░] 16%               │
│ Memory               3.2G / 16G   [████░░░░░░░░░░░░░░░░] 20%               │
│ Swap                 0B / 2.0G    [░░░░░░░░░░░░░░░░░░░░] 0%                │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────── PROCESSES ─ sorted by cpu ─ refresh 5s ──────────────────┐
│  PID     %CPU  %MEM     RSS  RUN/CAP  BACKLOG  POOL  W#                    │
│  48202  42.7   2.5   398M     5/0        2     0    1                      │
│  48201  18.2   2.6   412M     3/2        0     2    0                      │
│  48200   0.3   0.8   128M       -        -     -    M                      │
└────────────────────────────────────────────────────────────────────────────┘
┌───────────────────────────────── SUMMARY ──────────────────────────────────┐
│ Workers reporting    2 / 3        [█████████████░░░░░░░] 67%  stale 1 WARN │
│ Requests in flight   7 / 300      [█░░░░░░░░░░░░░░░░░░░] 2%                │
│ Requests dropped     2                                   WARN              │
│ Requests truncated   yes                                 info              │
│ Backlog total        3 / 15       [████░░░░░░░░░░░░░░░░] CRIT              │
│ Busy threads         6 / 15       [████████░░░░░░░░░░░░] 40%               │
│ Pool capacity        9 / 15       [████████████░░░░░░░░] 60%               │
└────────────────────────────────────────────────────────────────────────────┘
┌─────────────────── WORKER 0 ─ pid 48201 ─ synced 2s ago ───────────────────┐
│ synced_at            2s ago                              ok                │
│ backlog              0 / 5        [░░░░░░░░░░░░░░░░░░░░] ok                │
│ running              3 / 5        [████████████░░░░░░░░] 60%               │
│ pool_capacity        2 / 5        [████████░░░░░░░░░░░░] 40%               │
│ busy_threads         3 / 5        [████████████░░░░░░░░] 60%               │
│ rss                  128M / 16G   [████░░░░░░░░░░░░░░░░] 12%               │
│ cpu                  18 / 100%    [████░░░░░░░░░░░░░░░░] 18%               │
│ registry 5/100 keep_longest truncated no dropped 0                         │
│ IN-FLIGHT (2/100)  sort: elapsed  filter: —                                │
│ ELAPSED  ID    METHOD PATH              REMOTE                             │
│ 4m 8s    7f3… GET    /api/v2/…         203.0.113.45                        │
│ 48.0s    a1    POST   /webhooks/stripe  54.187.255.0                       │
└────────────────────────────────────────────────────────────────────────────┘
┌───────────────── WORKER 1 ─ pid 48202 ─ [CRIT] backlog 2 ──────────────────┐
│ synced_at            2s ago                              ok                │
│ backlog              2 / 5        [████████░░░░░░░░░░░░] CRIT              │
│ running              5 / 5        [████████████████████] CRIT              │
│ pool_capacity        0 / 5        [░░░░░░░░░░░░░░░░░░░░] CRIT              │
│ busy_threads         5 / 5        [████████████████████] CRIT              │
│ rss                  398M / 16G   [██████████░░░░░░░░░░] 39%               │
│ cpu                  43 / 100%    [██████████░░░░░░░░░░] 43%               │
│ registry 1/100 keep_longest truncated no dropped 0                         │
│ IN-FLIGHT (1/100)  sort: elapsed  filter: —                                │
│ ELAPSED  ID    METHOD PATH              REMOTE                             │
│ 3.1s    b2    GET    /health           127.0.0.1                           │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────── FOOTER ──────────────────────────────────┐
│ refresh 5s │ layout: stacked │ requests: auto→inline │ top+proc: on        │
│ r d l i o f O ? W save │ j k [ ] scroll │ x clear │ 0-9 focus │ Ctrl+C quit│
└────────────────────────────────────────────────────────────────────────────┘
```

---

## SUMMARY

Seven visible lines; schema mapping:

| Schema field | UI line | Renderer | Denominator |
|--------------|---------|----------|-------------|
| `workers_reporting` | Workers reporting | MetricLine | / `workers_total`; `stale N` if stale |
| `requests_in_flight` | Requests in flight | MetricLine | / Σ `request_limit` |
| `requests_dropped_total` | Requests dropped | LabelLine | WARN if > 0 |
| `requests_truncated` | Requests truncated | LabelLine | **info** if true (never WARN) |
| `backlog_total` | Backlog total | MetricLine | / `max_threads_total` |
| `busy_threads_total` | Busy threads | MetricLine | / `max_threads_total` |
| `pool_capacity_total` | Pool capacity | MetricLine | / `max_threads_total` |

Conditional **Host vs Puma** LabelLine after pool when attribution warn/crit ([below](#host-vs-puma-resourceattribution)).

When all workers report: `Workers reporting 3 / 3 … ok` (no stale badge). When `requests_truncated == false`: text `no`, no badge.

---

## TOP (host)

```text
┌────────────────────────── TOP ─ app-server.local ──────────────────────────┐
│ Load   0.42   0.38   0.35        (1 / 5 / 15 min)                          │
│ CPU    usr 12% sys 4% idle 84%    [████░░░░░░░░░░░░░░░░] 16%               │
│ Memory               3.2G / 16G   [████░░░░░░░░░░░░░░░░] 20%               │
│ Swap                 0B / 2.0G    [░░░░░░░░░░░░░░░░░░░░] 0%                │
└────────────────────────────────────────────────────────────────────────────┘
```

Memory/Swap use MetricLine grid; CPU uses free prefix with `[` at col 37; Load is free text.

When host hot (≥ ~60% CPU or mem ratio), CPU/Memory lines may show suffix **`Puma ~X%`** / **`Puma ~Y`**.

Optional footer hint when cgroup limit detected: `mem limit 512 MiB (cgroup)`.

---

## PROCESSES

All **local Puma** processes: workers from JSON + master from state file (`M`).

| Column | Source |
|--------|--------|
| PID | JSON / state file |
| %CPU, %MEM, RSS | `ProcessSampler` |
| RUN/CAP | `puma.running` / pool from JSON |
| BACKLOG, POOL | JSON |
| W# | `workers[].index`; master = **M** |

Sort: `--sort cpu|rss|backlog|index` or default **severity** (backlog CRIT first). Master row shows `-` for Puma columns when no worker stats.

Layout `compact`: TOP and PROCESSES off.

---

## Workers

Order inside box: **sync** (LabelLine) → **puma** metrics (MetricLine) → **process** rss/cpu (MetricLine) → registry (text) → requests.

Worker `X / Y` denominators: backlog/running/pool/busy / `max_threads`; rss / `MemoryCapacity.total`; cpu / `100%`; in-flight header / `request_limit`.

### Worker sync freshness

`interval = meta.worker_check_interval_seconds` (single: always ok).

| Age since `synced_at` | Badge |
|-----------------------|-------|
| `null` | CRIT — never synced |
| ≤ interval | ok |
| ≤ 2× interval | WARN |
| > 2× interval | CRIT |

Box title mirrors worst state: `synced 2s ago`, `[WARN] stale 8s`, `[CRIT] not synced`.

---

## Requests

Two independent axes in `Options`:

| Axis | Values | Default |
|------|--------|---------|
| Frame layout | stacked, two_column, split, grid, focus, compact | stacked |
| Request display | auto, inline, stack | auto |

**Auto:** if all columns fit → inline; else stack (`└ field: value`).

**Column order (canonical):** elapsed · id · method · path_info · remote_ip · custom · session.*

Headers: ELAPSED · ID · METHOD · PATH · REMOTE · (custom) · SESSION.*

**`elapsed`:** text only, **no bar**.

**Compact + stack:** truncated primary line repeats full value below:

```text
│ path truncado  /api/v2/organizations/acme-corp/rep…                        │
│   └ path_info: /api/v2/organizations/acme-corp/reports/quarterly/2026/Q1/  │
│              export/detailed?format=csv&locale=pt-BR                       │
```

Long lists: window `[offset .. offset+limit)`; header `IN-FLIGHT (4-7/42)`; hint `… +N more below (j)`.

---

## Frame layouts

| Mode | Min cols | Behavior |
|------|----------|----------|
| `stacked` | always | Default vertical stack |
| `two_column` | ≥ 120 | TOP \| SUMMARY; workers 2-col; PROCESSES full width between |
| `split` | ≥ 100 | TOP \| SUMMARY side by side; PROCESSES full; workers full width |
| `grid` | ≥ 120 | Workers 2-col only |
| `focus` | — | One worker full screen (`0`–`9`) |
| `compact` | rows ≤ 20 or manual | TOP+PROCESSES off; SUMMARY 7 lines; one worker; stack if truncate |

Unavailable modes fall back with footer hint: `layout: stacked (saved two_column, need 120 cols)`.

**Keys:** `d` Design modal; `l` cycle layout; `i` cycle request display; `0`–`9` focus worker.

Design modal lists modes with `[ok]` or needs-N-cols hint.

---

## Host vs Puma (ResourceAttribution)

Three levels ([ADR 0005](../adr/0005-host-vs-puma-resource-attribution.md)):

1. **TOP suffix** — `Puma ~18%` when host hot and gap exists.
2. **SUMMARY line** — `Host vs Puma CPU92/M78` LabelLine, WARN/CRIT, no bar.
3. **OUTSIDE PUMA** — top 3 non-Puma by CPU; toggle **`O`**; max 3 rows, no scroll.

Example (Sidekiq eating CPU):

```text
│ CPU    usr 85% sys 6% idle 9%     [███████████████████░] 91% Puma ~14%     │
│ Host vs Puma         CPU91/M74                           CRIT              │
┌ OUTSIDE PUMA ─ top 3 by cpu ─ press O hide ────────────────────────────────┐
│  9912    72.4   2.8   210M  sidekiq 7.2                                    │
└────────────────────────────────────────────────────────────────────────────┘
```

When aligned: no suffix, no extra SUMMARY line, no outsiders panel.

**Degraded:** CLI remote from Puma → no attribution, PROCESSES `—`.

---

## Modals

| Key | Modal |
|-----|-------|
| `d` | Design (layout + request display) |
| `o` | Sort requests |
| `f` | Filter requests |
| `?`, `h` | Help |

While modal open: dashboard frozen underneath; poll may continue but screen does not redraw until Esc.

Filter quick keys in modal: `G`/`P`/`U`/`D`; active filter shown in worker box header.

---

## Help (`?` / `h`)

Static content in `HelpContent` — six tabs:

| Tab | Content |
|-----|---------|
| Atalhos | Full key map |
| Seções | HEADER, TOP, PROCESSES, SUMMARY, WORKERS, OUTSIDE PUMA, FOOTER |
| SUMMARY | 7 lines, X/Y, stale, Host vs Puma |
| Worker | synced_at, puma, rss/cpu, registry, in-flight |
| TOP & host | Load, Puma ~, outsiders, degraded mode |
| Badges | ok / info / WARN / CRIT rules |

Navigate: `←`/`→` or `n`/`p` tabs; `↑`/`↓` scroll within tab.

`--help` on CLI lists flags only; footer note points to `?` in watch mode.

---

## Footer

Normal:

```text
│ refresh 5s │ layout: stacked │ requests: auto→inline │ top+proc: on        │
│ r d l i o f O ? W save │ j k [ ] scroll │ x clear │ 0-9 focus │ Ctrl+C quit│
```

After **`W`:** brief `saved preferences to ~/.pesrc` message.

---

## Scroll and refresh

| Type | Behavior |
|------|----------|
| Emulator scrollback | Alternate screen — shell preserved on exit |
| In-app scroll | `ScrollState` offsets survive poll refresh |

**Enter watch:** `\e[?1049h`. **Exit:** restore main buffer.

| Key | Action |
|-----|--------|
| `j` / `k` | ±1 request line (focused worker) |
| `[` / `]` | ±page_size requests |
| `J` / `K` | optional worker page scroll |

**Rules:** refresh updates metrics, keeps offset; clamp when count drops; modals don't reset offset; **`x`** clear filters does not reset scroll.

Mockup with scroll:

```text
│ IN-FLIGHT (4-6/42)  sort: elapsed  filter: —                               │
│ … rows 4–6 …                                                               │
│ … +36 more below · j/k line · [ ] page                                     │
```

---

## Colors and alerts

| Level | Color | When |
|-------|-------|------|
| ok | green | within limits |
| info | cyan | informative — **`requests_truncated`**, registry truncated |
| warn | yellow | ratio > 75%, sync ≤ 2× interval, dropped, stale |
| crit | red | ratio > 90%, **backlog > 0**, sync null or > 2× interval |

**Absolute rules:**

- **Backlog > 0** → always CRIT (worker and SUMMARY).
- **`requests_truncated`** → **info**, never WARN.

**Default worker sort (severity):** backlog CRIT → never synced → sync CRIT → sync WARN → in-flight % → CPU → index asc.

---

## Acceptance criteria

Implementations and specs must satisfy:

1. Grid: `[` at col **37**, suffix at col **60** on MetricLine/LabelLine.
2. SUMMARY exactly **7** lines (+ optional Host vs Puma).
3. `requests_truncated` badge is **info**.
4. Mockups at 78 cols match rendered output in stub scenario `mixed`.
5. Width 200 + inline: no `└ method:` stack lines.
6. Width 55: stack mode with `└ path_info:`.
7. Scroll offset unchanged across two simulated polls when count stable.

---

## Related

- [TDD](tdd.md)
- [ADRs](../adr/README.md)
- [JSON contract](../json-contract.md)
