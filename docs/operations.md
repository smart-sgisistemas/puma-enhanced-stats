# Operations

Configuration, tuning, and troubleshooting for **puma-enhanced-stats** in production.

## Activation

The gem activates when listed in the Gemfile and loaded via Bundler. No `puma.rb` entry is required for defaults.

The Rails Railtie appends `CurrentRequestsMiddleware` as the **innermost** layer so session middleware runs earlier and `rack.session` is available for session extractors.

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

Declare a block in `config/puma.rb` to customize fields and limits. When declared, the block is **required** (empty blocks are valid).

```ruby
enhanced_stats do
  request :path do |env|
    env["PATH_INFO"]
  end

  session :user_id
  session :tenant_slug do |session|
    session.dig("current_tenant", "slug")
  end

  request_limit 100
  limit_policy :keep_longest
  max_field_length 256
  truncate_suffix "…"
end
```

### Defaults (zero-config)

| Setting | Default |
|---------|---------|
| Request fields | `id`, `started_at`, `remote_ip`, `method`, `path_info` |
| Session fields | none (`session` is always `{}` on each item until you add extractors) |
| `request_limit` | `100` |
| `limit_policy` | `:keep_longest` |
| `max_field_length` | `256` characters |
| `truncate_suffix` | `…` (U+2026); `""` or `nil` disables suffix |

### Field extractors

| DSL | Source | Block argument | Stored as |
|-----|--------|----------------|-----------|
| `request` | Rack `env` | `env` | Top-level keys on the entry |
| `session` | `env["rack.session"]` | session hash | Always nested under `"session"`; `{}` when no session fields are configured |

Built-in request fields:

| Name | Extracted from |
|------|----------------|
| `id` | `env["action_dispatch.request_id"]` |
| `started_at` | UTC ISO 8601 time at registration (`Time.now.utc`) |
| `remote_ip` | `env["action_dispatch.remote_ip"]` or `env["REMOTE_ADDR"]` |
| `method` | `env["REQUEST_METHOD"]` |
| `path_info` | `env["SCRIPT_NAME"]` + `env["PATH_INFO"]` (no query string) |

Both namespaces are read at **registration** time (when the request enters the middleware).

### Limit policies

When the in-flight registry reaches `request_limit`:

| Policy | Behavior |
|--------|----------|
| `:keep_longest` (default) | Evicts the **newest** in-flight entry, registers the new request, increments `dropped_count` |
| `:reject_new` | Skips registration for the new request, increments `dropped_count` |

`dropped_count` and `truncated` in `requests.meta` are **per-interval deltas** (since the last worker ping or snapshot read), not cumulative lifetime counters.

Insertion order in the registry follows registration order among surviving entries. Under load, slow requests that registered recently may be evicted before they appear long-running in JSON — increase `request_limit` or use `:reject_new` if you need a stable snapshot of already-tracked requests.

### Truncation

String field values longer than `max_field_length` are truncated. When `truncate_suffix` is non-empty, the suffix is appended and the prefix shortened accordingly. When empty, the value is cut at `max_field_length` with no marker. `requests.meta.truncated` flags truncation in the sync interval.

## Cluster mode

In cluster mode:

1. `Cluster#run` creates a dedicated Unix pipe on the cluster instance, like Puma's native pipes.
2. Each worker resolves `@enhanced_write_io` in `Worker#initialize` from the forked cluster runner and runs a sender thread every `worker_check_interval`.
3. `Cluster` runs a master reader thread; on each line it calls `WorkerHandle#enhanced_ping!` (like native `ping!` → `last_status`).
4. `Cluster#worker` closes the inherited read end in each child process.
5. `GET /enhanced-stats` reads `@workers` via `last_enhanced_stats` with Puma's `worker_check_interval`:

```ruby
worker_check_interval 5  # seconds between worker pipe writes
```

Lower values → fresher in-flight data, more master/worker traffic.

`Cluster::Worker#run` clears the in-flight registry, closes the inherited read end of the pipe, and starts the worker sender thread.

### Pipe buffer

Unix pipe buffers are typically ~64 KB. Keep `request_limit` and field sizes reasonable; monitor `requests.meta.truncated`. Very large payloads may block the sender until the master reads.

### Deploy

When upgrading to 0.5.0 from 0.4.x, restart the entire cluster so all workers use the dedicated pipe. Mixed versions (legacy ping piggyback + new pipe) are not supported.

### Interpreting `summary`

| Signal | Meaning |
|--------|---------|
| `workers_stale > 0` | Some workers have not reported enhanced stats yet (`synced_at` null) |
| `requests_dropped_total > 0` | Registry evictions/rejections in the last interval |
| `requests_truncated == true` | At least one field hit `max_field_length` |
| High `backlog_total` | Puma accept queue pressure across workers |
| High `busy_threads_total` vs `max_threads_total` | Thread pool saturation |

Compare `workers[].synced_at` with `meta.collected_at` to judge staleness.

## Single mode

The master reads `CurrentRequests.snapshot` live when `/enhanced-stats` is requested. No worker ping cache involved.

## Platform notes

- **Rails required** — middleware depends on Rails load order and `action_dispatch.request_id`.
- No runtime `enabled` flag — include or omit the gem in the Gemfile.

## Limitations

| Limitation | Detail |
|------------|--------|
| Streaming responses | Registry entry is removed when `@app.call` returns, **not** when the response body finishes streaming |
| Cluster staleness | In-flight items reflect the last ping, not live worker state at query time |
| Registry size | Memory scales with `request_limit` × configured fields; default 100 is conservative |
| Extractor errors | Swallowed silently — failed extractors do not fail the HTTP request |

## Troubleshooting

### Empty `workers[].requests.items` under load

- Registry may be full with `:reject_new` — check `dropped_count`
- With `:keep_longest`, fast turnover evicts recent entries — raise `request_limit`
- Cluster: data may be stale — check `synced_at` and `worker_check_interval`

### `403` on `/enhanced-stats`

- Missing or wrong `token` query parameter
- Control app not activated or wrong bind URL

### Session fields missing

- Session middleware must run before `CurrentRequestsMiddleware` (Railtie places enhanced stats innermost)
- Session may not be loaded yet for the route — verify `rack.session` in that request phase

### Different data on `/stats` vs `/enhanced-stats`

Expected. Enhanced data is **only** on `/enhanced-stats` and `pumactl enhanced-stats`. Native Puma stats are unchanged.

## Related docs

- [JSON contract](json-contract.md)
- [Architecture](architecture.md)
- [Security](security.md)
