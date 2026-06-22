# Puma::Enhanced::Stats

Extended statistics for **Puma 8+** on **Rails 7+**: in-flight HTTP requests and thread-pool counters exposed through a stable JSON contract on the control app.

## Overview

| Capability | Description |
|------------|-------------|
| In-flight requests | `id`, `started_at`, method, path, client IP, and optional session fields while a request is active |
| Puma pool stats | `backlog`, `running`, `busy_threads`, `pool_capacity`, and related counters (synced with in-flight data in cluster mode) |
| Cluster aggregation | Master merges enhanced payloads from workers over a dedicated pipe |

Activation is automatic via Bundler. Defaults work with only a Gemfile entry.

**Documentation:** [docs/README.md](docs/README.md) — operations, JSON contract, security, architecture.

## Requirements

- Ruby >= 3.0
- Rails >= 7.0, < 8
- Puma >= 8.0, < 9

## Installation

```ruby
# Gemfile
gem "puma-enhanced-stats", github: "smart-sgisistemas/puma-enhanced-stats", tag: "v0.5.0"
```

```bash
bundle install
```

## Quick start

Enable the control app in `config/puma.rb`:

```ruby
activate_control_app "tcp://127.0.0.1:9293", { auth_token: "secret" }
```

Query enhanced stats:

```bash
curl "http://127.0.0.1:9293/enhanced-stats?token=secret"
bundle exec pumactl -S tmp/puma.state enhanced-stats
```

Invalid or missing tokens receive **403 Forbidden**. See [docs/security.md](docs/security.md).

## Configuration

Optional block in `config/puma.rb`:

```ruby
enhanced_stats do
  session :user_id
  request_limit 100
  limit_policy :keep_longest
  max_field_length 256
end
```

Zero-config defaults: request fields `id`, `started_at`, `remote_ip`, `method`, `path_info`; `session` always `{}` until you add session extractors; `request_limit` 100; `:keep_longest` policy.

Full DSL, limit policies, and cluster tuning: [docs/operations.md](docs/operations.md).

Cluster mode — set ping interval with Puma's `worker_check_interval`:

```ruby
workers 2
worker_check_interval 5
```

## JSON response

The response follows [schema/enhanced-stats-v1.json](schema/enhanced-stats-v1.json) (`schema_version: 1`), assembled by `Snapshot`.

| Section | Purpose |
|---------|---------|
| `meta` | Timestamp, versions, `single` / `cluster` mode |
| `summary` | Cluster-wide workers, in-flight counts, pool totals |
| `workers[]` | Per-worker Puma stats and in-flight `items` |

Each in-flight item includes required `id`, `started_at`, and `session` (empty object when no session fields are configured).

Field reference and delta semantics: [docs/json-contract.md](docs/json-contract.md).  
Sample: [spec/fixtures/enhanced-stats-v1.sample.json](spec/fixtures/enhanced-stats-v1.sample.json).

Native Puma endpoints are unchanged — enhanced data appears **only** on `/enhanced-stats` and `pumactl enhanced-stats`.

## Limitations

- **Streaming bodies** — requests leave the registry when the Rails stack returns, not when the body finishes sending ([architecture](docs/architecture.md)).
- **Cluster freshness** — in-flight data and `workers[].puma` reflect the last enhanced pipe write (up to `worker_check_interval` stale).
- **Rails required** — uses Rails middleware and `action_dispatch.request_id`.

## Terminal CLI

The terminal dashboard CLI was **removed in v0.4.0** (planned to return in a future release). Use HTTP or `pumactl enhanced-stats` instead.

## Development

```bash
bin/setup
bundle exec rake              # unit specs (integration excluded by default in CI matrix)
COVERAGE=true bundle exec rake spec:coverage
bundle exec yard              # API docs → doc/
bin/console
```

Docker:

```bash
docker build -t puma-enhanced-stats:dev .
docker run --rm -v "$(pwd):/app" -w /app puma-enhanced-stats:dev bundle exec rake
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
