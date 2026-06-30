# ADR 0007: Lazy snapshot from thread-local env

## Status

Accepted

Supersedes [ADR 0006](0006-thread-local-current-requests.md) (thread-local **entries** built at register time).

## Context

After ADR 0006, `CurrentRequests` built JSON-ready entries on every request (`register`), even though consumers only read them on snapshot/worker ping. Field extraction ran on the request hot path unnecessarily.

## Decision

1. **Remove `CurrentRequests`** entirely.

2. **`Middleware`** stores only the live Rack `env` in thread-local storage (`Thread.current[KEY]`).

3. On middleware entry, stamp `env["puma.enhanced_stats.started_at"]` with `Time.now.iso8601(6)` so `started_at` reflects request start, not snapshot time.

4. **`Snapshot#server_row`** scans `Thread.list` for thread-local envs, runs field extractors, and returns in-flight `requests` at read time.

5. **Configuration** comes from `server.options[:enhanced_stats]` (set by the `enhanced_stats` DSL in `puma.rb`), with `Configuration.default` as fallback.

6. Worker pipe uses **`Snapshot.server(server:, index:)`** — a flat worker row; the sender thread skips writes until `@server` is present. HTTP responses use **`Snapshot.single`** (single mode) or **`Snapshot.cluster`** (cluster master).

## Consequences

### Positive

- Request hot path: thread-local set/clear + timestamp stamp only (no extractor loops).
- Simpler codebase (no registry singleton, no global `Stats.configuration`).
- Extractors see **current** `env` / `rack.session` at snapshot time (useful for session fields).

### Negative

- Snapshot/pipe cost includes field extraction (moved from register to read path — acceptable for 1–5 s intervals).
- `started_at` depends on middleware stamping an internal env key.

## Alternatives considered

| Alternative | Why rejected |
|-------------|--------------|
| Keep building entries at register | Wasted work on every request |
| Snapshot-time `Time.now` for `started_at` | Wrong semantics |
| Separate registry class wrapping env | Extra layer without benefit |
| Global `Stats.configuration` | Config belongs on `server.options` from Puma DSL |
