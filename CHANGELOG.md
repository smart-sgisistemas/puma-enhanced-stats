# Changelog

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
- Puma >= 6.0
