# Changelog

## 0.2.0 — 2026-06-16

### Added

- **`puma-enhanced-stats` CLI** (`exe/puma-enhanced-stats`) — terminal dashboard for the enhanced-stats JSON contract
  - Boxed sections: HEADER, SUMMARY, per-worker panels, optional FOOTER in watch mode
  - Color bars with WARN/CRIT thresholds for backlog, threads, RSS, and CPU
  - Dynamic in-flight request table columns (built-in + custom `request` / `session` fields)
- **CLI flags**
  - Connection (same as `pumactl`): `-S` / `--state`, `-C` / `--control-url`, `--url`, `-T` / `--token`
  - `-w` / `--watch` — auto-refresh using server `sync_interval_seconds`
  - `--top` — local **SYSTEM** (load, CPU, memory) and **PROCESSES** (Puma workers) blocks
  - `--compact` — two-column worker grid (terminal ≥ 120 cols, max 2 workers)
  - `--json` — raw JSON to stdout
  - `--no-color` — plain text (CI-friendly)
  - `--worker N` — single-worker view
  - `--sort` — `cpu`, `rss`, `backlog`, or `index` (workers and PROCESSES table)
- Aggregated **SUMMARY** row: global backlog, threads in use, pool capacity free, in-flight count
- Dependencies: `pastel`, `tty-screen`
- `PumaCompat` helpers for Puma 6/7/8 control ping formats and worker boot hooks

### Changed

- Builds on **0.1.4** middleware and snapshot improvements (`RequestStartMiddleware`, `RequestsMiddleware`, per-interval `truncated` / `dropped_count`)

## 0.1.4 — 2026-06-16

### Added

- `RequestStartMiddleware` as the outermost Rails layer; sets `HTTP_X_REQUEST_START` (`t=<unix>`) when the header is missing so `started_at` is consistent across proxies
- `HTTP_X_REQUEST_START` parsing in the in-flight registry (`started_at_for`)

### Changed

- Renamed `CurrentRequestsRegistry` to `CurrentRequests`
- Renamed `Middleware` to `RequestsMiddleware`; appended as the innermost Rails middleware layer (closest to the router)
- Railtie stack: `insert_before 0` for `RequestStartMiddleware`, `use` for `RequestsMiddleware` (session middleware still runs earlier on the request path)
- `truncated` and `dropped_count` in worker snapshots are per-sync-interval deltas; reset after each `CurrentRequests#snapshot`
- Removed `Normalizer`; snapshot assembly logic consolidated into `Snapshot`

## 0.1.3 — 2026-06-15

### Fixed

- Rails 7.0 boot failure: use `config.session_store` (already resolved by Rails) instead of `ActionDispatch::Session.resolve_store` (added in Rails 7.1)

### Changed

- CI matrix tests Rails 7.0.10, 7.1.6, and 7.2.2 (via `RAILS_VERSION`) across Ruby 3.0–3.4

## 0.1.2 — 2026-06-15

### Fixed

- CI Docker image: install `procps` so `ProcessMetrics` specs run on Alpine Ruby 3.2+ (BusyBox `ps` lacks `-p`)

## 0.1.1 — 2026-06-13

### Changed

- Minimum supported Puma version raised from 6.0 to 8.0
- CI matrix includes Ruby 3.4

## 0.1.0 — 2026-06-13

### Added

- Zero-config activation via Gemfile and Rails Railtie middleware (inserted after the session store)
- Optional `enhanced_stats` DSL in `config/puma.rb`:
  - `request` and `session` field extractors
  - `request_limit`, `limit_policy`, `sync_interval`, `max_field_length`
- Built-in request fields: `remote_ip`, `method`, `path_info`
- `GET /enhanced-stats` on the Puma control app
- `pumactl enhanced-stats` command
- JSON contract v1 ([schema/enhanced-stats-v1.json](schema/enhanced-stats-v1.json)) with:
  - `meta`, `summary`, and per-worker `puma`, `process`, and `requests` sections
  - In-flight request items with `elapsed_ms`, optional `session` fields, and registry metadata
  - Cluster `synced_at` from worker ping (`null` until first report); `summary.workers_reporting` counts workers with enhanced stats
- In-flight request registry with policies:
  - `keep_longest` (default) — evicts newest entry when full
  - `reject_new` — drops new registrations when full
- Field value truncation via `max_field_length` with `truncated` flag in snapshots
- Registry builds entries outside the mutex; duplicate request ids replace prior entries
- Cluster sync via `_enhanced_stats` injected into worker ping payloads (`WorkerWrite` → `WorkerHandle`)
- `sync_interval` overrides Puma `worker_check_interval` in cluster mode
- On-demand process metrics via `ProcessMetrics.read` (`ps` on Linux/macOS)
- `before_worker_boot` hook clears the in-flight registry when a cluster worker boots

### Requirements

- Ruby >= 3.0
- Rails >= 7.0, < 8
- Puma >= 8.0
