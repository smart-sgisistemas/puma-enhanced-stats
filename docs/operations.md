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

1. Each worker injects `enhanced_stats` into its **PIPE_PING** payload.
2. The master stores the latest payload on `WorkerHandle`.
3. `GET /enhanced-stats` merges cached worker data into JSON.

Tune freshness with Puma's `worker_check_interval`:

```ruby
worker_check_interval 5  # seconds between worker pings
```

Lower values → fresher in-flight data, more master/worker traffic.

`before_worker_boot` clears the in-flight registry when a worker process starts (forked workers begin empty).

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

The master reads `CurrentRequests.snapshot` live when `/enhanced-stats` is requested. Process metrics are sampled at that moment. No worker ping cache involved.

## Platform notes

- **Process metrics** — Linux only, via `/proc`. CPU is sampled between consecutive snapshots (same idea as `top`); the first snapshot returns `cpu_percent: null`.
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

### `process.rss_bytes` / `cpu_percent` always null

- Platform is not Linux
- `/proc` is not mounted (unusual outside Linux containers and hosts)

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
