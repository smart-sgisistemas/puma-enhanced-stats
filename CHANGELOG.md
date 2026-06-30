# Changelog

## 1.0.0 — 2026-06-29

First stable release. `/enhanced-stats` returns **Puma `GET /stats` + flat gem extensions** — no `schema_version`, `meta`, or `summary` envelope.

### Added

- **Puma-aligned JSON contract** — cluster and single shapes documented in [ADR 0008](docs/adr/0008-enhanced-stats-puma-aligned-json.md); schema [enhanced-stats-v1.json](schema/enhanced-stats-v1.json).
- **`Snapshot` API** — `Snapshot.server` (wire row), `Snapshot.single` (HTTP single mode), `Snapshot.cluster` (HTTP cluster mode).
- **`Middleware`** — thread-local Rack `env` + `env["puma.enhanced_stats.started_at"]` stamped with `Time.now.iso8601(6)` on entry.
- **`Single#enhanced_stats`** — zero-filled pool counters when `@server` is not yet available (before `start_server`).
- **Cluster pipe** — flat wire row `{ index, pid, stats, requests: [] }`; master stores via `WorkerHandle#enhanced_ping!`.
- **`pumactl enhanced-stats`** and **`GET /enhanced-stats`** on the control app.
- [ADR 0007](docs/adr/0007-lazy-snapshot-from-env.md) — lazy in-flight snapshot from thread-local env at read time.

### Changed

- **Timestamps** — `collected_at`, `started_at`, and `last_enhanced_checkin` use `iso8601(6)` (microsecond precision).
- **Pool counters** — single-mode defaults zero-filled from `Puma::Server::STAT_METHODS`, merged with live `@server.stats`.
- **Truncation** — fixed suffix `"…"`; `truncate_suffix` is not configurable.

### Removed

- `schema_version`, `meta`, `summary`, native `last_checkin` / `last_status` from enhanced HTTP output.
- `requests.meta`, `requests_truncated`, configurable `truncate_suffix`.
- `CurrentRequests` registry — replaced by lazy snapshot in `Snapshot#server_row`.
- `CurrentRequestsMiddleware` — renamed to `Middleware`.

### Requirements

- Ruby >= 3.0
- Rails >= 7.0, < 8
- Puma >= 8.0, < 9

## 0.5.1 — 2026-06-22

### Changed

- **Single mode** — `meta.worker_check_interval_seconds` is always `0` (live read on each request).
- **`Configuration#fields`** — registry keys use symbols (`name.to_sym`).
- **`Snapshot`** — `@collected_at` set in `initialize`; cluster rows call `build_row` directly.

## 0.5.0 — 2026-06-20

### Added

- **Dedicated pipe transport** — cluster workers send enhanced registry snapshots over a Unix pipe instead of piggybacking on the native `PIPE_PING` channel.
- **`launcher.enhanced_stats`** — cluster delegates to `Puma::Cluster#enhanced_stats`, single mode reads live registry via `Snapshot`.
- **`Puma::Cluster::WorkerHandle` prepend** — `last_enhanced_status` and `enhanced_ping!`, mirroring native `ping!` / `@last_status`.
- **`Puma::Cluster` prepend** — pipe IO, reader thread, and `enhanced_stats`.
- **`Puma.enhanced_stats` / `Puma.enhanced_stats_hash`** — in-process access via the same runner as `Puma.stats`.

### Changed

- **`Snapshot`** — assembles JSON from worker cache (cluster) or live registry + `@server.stats` (single).
- **Cluster wire payload** — sourced from `@server.stats` merged with in-flight requests, not from `last_status`.
- Cluster sync interval remains Puma's `worker_check_interval`; staleness semantics unchanged.

### Removed

- **`WorkerWrite`** / **`ClusterWorker`** prepend — no mutation of the native worker ping pipe.
- **`@enhanced_cache` on Cluster** — replaced by state on each `WorkerHandle`.
- **`EnhancedStatsBuilder`** / **`PipeHub`** — pipe and payload assembly live on `Cluster` and `Snapshot`.
- **Process metrics** (`ProcessMetrics`, RSS/CPU via `/proc`) — removed; use external tooling if needed.

### Breaking

- **Cluster restart required** when upgrading from 0.4.x — all workers must run the same gem version.

## 0.4.3 — 2026-06-20

### Changed

- Documentation and CI alignment for Puma 8.

## 0.4.0 — 2026-06-15

### Removed

- **Terminal dashboard CLI** — use HTTP or `pumactl enhanced-stats` instead.

## Earlier versions

See git history for 0.3.x and below.
