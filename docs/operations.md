# Operations

Configuration, tuning, and troubleshooting for **puma-enhanced-stats** in production.

## Activation

The gem activates when listed in the Gemfile and loaded via Bundler. No `puma.rb` entry is required for defaults.

The Rails Railtie appends `Middleware` as the **innermost** layer so session middleware runs earlier and `rack.session` is available for session extractors.

## Control app

Enable Puma's control server in `config/puma.rb`:

```ruby
workers 2                    # optional — cluster mode
worker_check_interval 5      # cluster — ping interval (seconds)

activate_control_app "tcp://127.0.0.1:9293", { auth_token: "secret" }
```

Query enhanced stats:

```bash
curl "http://127.0.0.1:9293/enhanced-stats?token=secret"
bundle exec pumactl -S tmp/puma.state enhanced-stats
```

See [Security](security.md) for binding and token guidance.

## `enhanced_stats` DSL

Declare a block in `config/puma.rb` to customize fields and truncation. When declared, the block is **required** (empty blocks are valid).

```ruby
enhanced_stats do
  request :path do |env|
    env["PATH_INFO"]
  end

  session :user_id
  session :tenant_slug do |session|
    session.dig("current_tenant", "slug")
  end

  max_field_length 256
end
```

### Defaults (zero-config)

| Setting | Default |
|---------|---------|
| Request fields | `id`, `started_at`, `remote_ip`, `method`, `path_info` |
| Session fields | none (`session` is always `{}` on each entry until you add extractors) |
| `max_field_length` | `256` characters |
| Truncation suffix | `"…"` (fixed; not configurable) |

### Field extractors

| DSL | Source | Block argument | Stored as |
|-----|--------|----------------|-----------|
| `request` | Rack `env` | `env` | Top-level keys on the entry |
| `session` | `env["rack.session"]` | session hash | Always nested under `"session"`; `{}` when no session fields are configured |

Built-in request fields:

| Name | Extracted from |
|------|----------------|
| `id` | `env["action_dispatch.request_id"]` |
| `started_at` | `env["puma.enhanced_stats.started_at"]` (stamped by middleware on entry, `iso8601(6)`) |
| `remote_ip` | `env["action_dispatch.remote_ip"]` or `env["REMOTE_ADDR"]` |
| `method` | `env["REQUEST_METHOD"]` |
| `path_info` | `env["SCRIPT_NAME"]` + `env["PATH_INFO"]` (no query string) |

Both namespaces are read at **snapshot** time (when `/enhanced-stats` is queried or the worker pipe ping runs), not when the request enters the middleware. The middleware only stores the live Rack `env` and stamps `env["puma.enhanced_stats.started_at"]` with `Time.now.iso8601(6)` on entry.

### In-flight registry size

Since **1.0.0**, each busy Puma worker thread holds at most one in-flight entry in thread-local storage. Compare `worker_status[].requests.size` with `last_enhanced_status.busy_threads` in cluster mode.

### Truncation

String field values longer than `max_field_length` are truncated with suffix `"…"`. No truncation flag is exposed in the JSON response.

## Cluster mode

In cluster mode:

1. `Cluster#run` creates a dedicated Unix pipe on the cluster instance, like Puma's native pipes.
2. Each worker inherits `@options[:enhanced_write_io]` and runs a sender thread every `worker_check_interval`, writing a flat worker row via `Snapshot.server` once `@server` is available.
3. `Cluster` runs a master reader thread; on each line it calls `WorkerHandle#enhanced_ping!` (like native `ping!` → `last_status`).
4. `Cluster#worker` closes the inherited read end in each child process.
5. `GET /enhanced-stats` reads `@workers` via `last_enhanced_status` with Puma's `worker_check_interval`:

```ruby
worker_check_interval 5  # seconds between worker pipe writes
```

Lower values → fresher in-flight data, more master/worker traffic.

`Cluster::Worker#run` closes the inherited read end of the pipe and starts the worker sender thread.

### Pipe buffer

Unix pipe buffers are typically ~64 KB. Keep field sizes reasonable. Very large payloads may block the sender until the master reads.

### Interpreting cluster aggregates

| Signal | Meaning |
|--------|---------|
| `workers_stale > 0` | Some workers have not reported enhanced stats yet (`last_enhanced_checkin` null) |
| High `backlog_total` | Puma accept queue pressure across workers |
| High `busy_threads_total` vs `max_threads_total` | Thread pool saturation |
| `requests_in_flight` ≈ `busy_threads_total` | Expected when threads are serving registered requests |

Compare `worker_status[].last_enhanced_checkin` with `collected_at` to judge staleness.

## Single mode

`Single#enhanced_stats` calls `Snapshot.single` when `@server` is running. Before `start_server`, it returns zero-filled `Puma::Server::STAT_METHODS` counters with empty `requests`. No worker ping cache involved.

## Platform notes

- **Rails required** — middleware depends on Rails load order and `action_dispatch.request_id`.
- No runtime `enabled` flag — include or omit the gem in the Gemfile.

## Limitations

| Limitation | Detail |
|------------|--------|
| Streaming responses | Registry entry is removed when `@app.call` returns, **not** when the response body finishes streaming |
| Cluster staleness | In-flight items reflect the last ping, not live worker state at query time |
| Registry scope | Only executing requests on worker threads — not queued connections |
| Snapshot order | `items` order is not stable across reads |
| Extractor errors | Swallowed silently — failed extractors do not fail the HTTP request |

## Troubleshooting

### Empty `requests` under load

- Compare `requests.size` with `busy_threads` — queued requests are not tracked
- Cluster: data may be stale — check `last_enhanced_checkin` and `worker_check_interval`

### `403` on `/enhanced-stats`

- Missing or wrong `token` query parameter
- Control app not activated or wrong bind URL

### Session fields missing

- Session middleware must run before `Middleware` (Railtie places enhanced stats innermost)
- Session may not be loaded yet for the route — verify `rack.session` in that request phase

### Different data on `/stats` vs `/enhanced-stats`

Expected. Enhanced data is **only** on `/enhanced-stats` and `pumactl enhanced-stats`. Native Puma stats are unchanged.

## Terminal CLI and Docker

The CLI reads **local** process metrics (`ps`, cgroup memory) for worker PIDs from the JSON. For coherent TOP, PROCESSES, and RSS bars, run it **in the same environment as Puma**.

### Recommended

```bash
docker compose exec web bundle exec puma-enhanced-stats
```

Uses the **web** service cgroup/memory limit and can see worker PIDs on that container.

### Compose memory limits

```yaml
services:
  web:
    mem_limit: 512m
```

Without `mem_limit`, the container may see host/VM memory — alert thresholds (75%/90%) use that larger total. Set limits in compose so bars match deploy caps.

### Not recommended

| How you run CLI | Effect |
|-----------------|--------|
| Separate `cli` service, HTTP to `web` | CLI cgroup ≠ Puma; `ps` on JSON PIDs fails → `—` |
| On host, Puma in container | Remote PIDs; use `--json` or `--no-top` |

Connection inside the app container: `ControlDiscovery` reads `config/puma.rb` and/or state file; or `-C tcp://127.0.0.1:9293 -T <token>`.

See [CLI TDD — flags](cli/tdd.md#cli-flags) and [UI spec — degraded mode](cli/ui-spec.md#host-vs-puma-resourceattribution).

## Related docs

- [JSON contract](json-contract.md)
- [Architecture](architecture.md)
- [Security](security.md)
- [CLI TDD](cli/tdd.md)
