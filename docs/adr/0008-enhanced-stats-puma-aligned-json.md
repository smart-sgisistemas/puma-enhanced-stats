# ADR 0008: Enhanced-stats JSON aligned with Puma `/stats`

## Status

Accepted

## Context

The v1 HTTP envelope (`schema_version`, `meta`, `summary`, `worker_status` with `last_checkin` / `last_status`, `requests.meta` / `requests.items`) duplicated information already available from Puma's native `GET /stats` and added versioning overhead. The gem is not yet in production, so a breaking contract change is acceptable.

Consumers need `/enhanced-stats` to look like `/stats` plus minimal gem extensions: in-flight request arrays, cluster aggregates, and `collected_at`.

## Decision

1. **Base payload** = native Puma `GET /stats` shape (cluster or single), deep-copied at response time.

2. **No envelope** — remove `schema_version`, `SCHEMA_VERSION`, `meta`, and `summary` objects.

3. **Cluster extensions**
   - Flat aggregates (ex-`summary`) **above** `worker_status`: `collected_at`, `workers_total`, `workers_reporting`, `workers_stale`, `requests_in_flight`, pool `*_total` keys.
   - Per worker: `last_enhanced_checkin`, `last_enhanced_status` (all `STAT_METHODS`), `requests` (array). Strip native `last_checkin` / `last_status` from the HTTP output.
   - `versions.puma-enhanced-stats` merged into native `versions` after `worker_status`.

4. **Single extensions** — flat Puma counters at root plus `collected_at`, `requests_in_flight`, `requests` (array), `versions.puma-enhanced-stats`. **No** `last_enhanced_*`, **no** `worker_status`.

5. **`requests`** is an array of in-flight entries (formerly `requests.items`). No `requests.meta`, no `requests_truncated`.

6. **Wire pipe** (cluster) — flat row `{ index, pid, stats, requests: [...] }`; no `truncated` flag.

7. **Sanitize** — field values longer than `max_field_length` are truncated with fixed suffix `"…"`. No truncation metadata is exposed. `truncate_suffix` is not configurable via DSL.

8. **Ordered keys** — cluster: Puma scalars → aggregates → `worker_status` → `versions`. Single: `started_at` → `collected_at` → Puma counters → `requests_in_flight` → `requests` → `versions`.

## Consequences

### Positive

- Parity with Puma `/stats` for tooling and dashboards.
- Simpler contract; no schema version negotiation.
- Less duplication between native ping and enhanced output.

### Negative

- Total breaking change for any consumer of the old envelope.
- Single and cluster shapes differ (no unified `worker_status` wrapper in single mode).

## Alternatives considered

| Alternative | Why rejected |
|-------------|--------------|
| Keep envelope v1 with `schema_version` | Duplicates Puma; extra versioning without production users |
| Duplicate native `last_checkin` / `last_status` alongside enhanced fields | Confusing two sources of truth |
| Keep `requests.meta` / `requests_truncated` | User chose silent truncation and array-only `requests` |
| `last_enhanced_*` on single mode | Redundant with flat Puma counters already at root |
| Configurable `truncate_suffix` | Fixed `"…"` reduces configuration surface |

## References

- [ADR 0007](0007-lazy-snapshot-from-env.md) — lazy in-flight registry; wire row vs HTTP payload
- [docs/json-contract.md](../json-contract.md)
- [schema/enhanced-stats-v1.json](../../schema/enhanced-stats-v1.json)
