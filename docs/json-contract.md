# JSON contract

`/enhanced-stats` returns the same shape as Puma `GET /stats`, plus flat gem extensions. There is **no** `schema_version`, `meta`, or `summary` envelope.

| Artifact | Location |
|----------|----------|
| Schema | [schema/enhanced-stats-v1.json](../schema/enhanced-stats-v1.json) (`oneOf` cluster \| single) |
| Sample (cluster) | [enhanced-stats-v1.sample.json](../spec/fixtures/enhanced-stats-v1.sample.json) |

CI validates via [spec/contract/enhanced_stats_v1_spec.rb](../spec/contract/enhanced_stats_v1_spec.rb).

See [ADR 0008](adr/0008-enhanced-stats-puma-aligned-json.md).

## Cluster mode

Native Puma cluster keys, then flat aggregates, then enhanced worker rows, then `versions`:

| Key | Description |
|-----|-------------|
| `started_at`, `workers`, `phase`, `booted_workers`, `old_workers` | From native `/stats` |
| `collected_at` | ISO 8601 (`iso8601(6)`) when the master assembled this response |
| `workers_total`, `workers_reporting`, `workers_stale` | Worker row counts (`workers_reporting` = rows with non-null `last_enhanced_checkin`) |
| `requests_in_flight` | Sum of `worker_status[].requests.size` |
| `backlog_total`, `busy_threads_total`, `max_threads_total`, `pool_capacity_total` | Sums from `worker_status[].last_enhanced_status` |
| `worker_status[]` | Native identity fields + enhanced overlay |
| `versions` | Native Puma versions + `puma-enhanced-stats` |

### `worker_status[]` (cluster)

| Field | Description |
|-------|-------------|
| `index`, `pid`, `phase`, `booted`, `started_at` | From native `/stats` (native `last_checkin` / `last_status` are **not** exposed) |
| `last_enhanced_checkin` | ISO 8601 (`iso8601(6)`) of last enhanced pipe write; `null` until first ping |
| `last_enhanced_status` | Puma pool counters (`Puma::Server::STAT_METHODS`) from the enhanced pipe |
| `requests` | Array of in-flight request entries |

## Single mode

Flat Puma pool counters at root (`Puma::Server::STAT_METHODS`, zero-filled then merged with `@server.stats`) plus:

| Key | Description |
|-----|-------------|
| `collected_at` | Response assembly time (`iso8601(6)`) |
| `backlog`, `running`, … | `Puma::Server::STAT_METHODS`; zero-filled when `@server` is absent (`Single#enhanced_stats` before boot) |
| `requests_in_flight` | `requests.size` |
| `requests` | In-flight request array |
| `versions.puma-enhanced-stats` | Gem version (required); native `puma` / `ruby` keys appear only when present on `@server.stats` |

`started_at` is included only when present on `@server.stats` (not part of native `Puma::Server#stats`).

No `worker_status`, no `last_enhanced_checkin`, no `last_enhanced_status`.

## `requests[]` entry shape

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | `action_dispatch.request_id` |
| `started_at` | yes | From `env["puma.enhanced_stats.started_at"]` (middleware stamp, `iso8601(6)`) |
| `method`, `path_info`, `remote_ip` | no* | Default request fields |
| `session` | yes | Configured session fields; `{}` when none configured |

\*Defaults are populated unless replaced in the DSL.

Field values longer than `max_field_length` are truncated with suffix `"…"` (not configurable). No truncation flag is exposed.

## Wire format (cluster pipe)

Workers send: `{ index, pid, stats, requests: [...] }` via `Snapshot.server`. The sender thread writes only when `@server` is present. The master stores the row on `WorkerHandle#enhanced_ping!`.

## Querying

```bash
curl "http://127.0.0.1:9293/enhanced-stats?token=SECRET"
bundle exec pumactl -S tmp/puma.state enhanced-stats
```

Invalid or missing `token` returns **403 Forbidden**.
