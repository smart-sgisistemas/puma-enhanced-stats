# ADR 0006: Thread-local CurrentRequests

## Status

Accepted

Superseded by [ADR 0007](0007-lazy-snapshot-from-env.md) (lazy build in Snapshot; middleware stores env only).

## Context

`CurrentRequests` tracked in-flight HTTP requests with a process-wide `Hash` keyed by
`action_dispatch.request_id`, protected by a `Mutex`. Registration, unregistration, and
snapshots all contended on that lock.

Puma assigns one active request per worker thread. Requests waiting in the thread pool
`@todo` queue never pass through `Middleware` — only executing requests are
registered.

Configurable limits (`request_limit`, `:keep_longest`, `:reject_new`, `dropped_count`)
existed to cap registry memory and handle overload. In practice the physical ceiling is
`busy_threads` per worker, not an arbitrary hash size. Configurations with more threads
than `request_limit` silently dropped tracked requests.

## Decision

1. Store the current request entry in thread-local storage:

   ```ruby
   Thread.current.thread_variable_set(KEY, entry)
   ```

   Use `thread_variable_set` / `thread_variable_get`, not fiber-local `Thread.current[:key]`,
   because this gem targets Puma's one-thread-per-request model.

2. Build snapshots by scanning all live threads:

   ```ruby
   Thread.list.filter_map { |t| t.thread_variable_get(KEY) }
   ```

   Non-Puma threads without an entry are ignored. Cost is O(threads) on each worker ping
   (typically 1–5 seconds), which is acceptable for a monitoring endpoint.

3. Remove registry limit policies and related configuration (`request_limit`, `limit_policy`).

4. Bump JSON contract to **schema v2**, removing obsolete fields:
   - `workers[].requests.meta.request_limit`
   - `workers[].requests.meta.limit_policy`
   - `workers[].requests.meta.dropped_count`
   - `summary.requests_dropped_total`

## Consequences

### Positive

- No mutex on the request hot path.
- Simpler implementation aligned with Puma threading.
- High-thread configurations no longer lose tracked requests to eviction.
- Memory bounded naturally by thread pool size.

### Negative

- Snapshot depends on `Thread.list` (includes reactor, GC, app threads — filtered by key).
- `items` order in snapshots is not stable.
- Breaking change for JSON v1 consumers and `puma.rb` DSL options removed in 1.0.0.
- Not suitable for async servers (Falcon) without fiber-local storage — out of scope.

## Alternatives considered

| Alternative | Why rejected |
|-------------|--------------|
| Keep Hash + Mutex | Unnecessary contention; artificial limit vs physical model |
| Fiber-local storage | Wrong isolation model for Puma; needed only for async servers |
| Soft-deprecate v1 fields | User chose explicit schema v2 breaking change |
| Access Puma `ProcessorThread` list | No public API |
