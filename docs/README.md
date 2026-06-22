# Documentation

Guides for **puma-enhanced-stats** v0.5.1. The gem exposes in-flight HTTP requests and Puma thread-pool counters through a stable JSON contract on the Puma control app.

## Reading order

| Guide | Audience | Topics |
|-------|----------|--------|
| [Operations](operations.md) | App operators, SRE | DSL, limits, cluster tuning, troubleshooting |
| [JSON contract](json-contract.md) | Integrators, tooling authors | Schema v1 fields, deltas, single vs cluster |
| [Security](security.md) | Security reviewers, operators | Control app, tokens, session fields, PII |
| [Architecture](architecture.md) | Contributors | Data flow, Puma hooks, separation from `/stats` |

## Quick links

- [README](../README.md) — installation and quick start
- [JSON Schema](../schema/enhanced-stats-v1.json) — machine-readable contract
- [Sample payload](../spec/fixtures/enhanced-stats-v1.sample.json) — full example
- [CHANGELOG](../CHANGELOG.md) — release history
- [CONTRIBUTING](../CONTRIBUTING.md) — development workflow

## Product status

- **Control app / `pumactl`** — supported (`GET /enhanced-stats`, `pumactl enhanced-stats`)
- **Terminal dashboard CLI** — removed in 0.4.0 (planned to return in a future release); use HTTP or `pumactl` instead

## Version

Documentation matches gem **v0.5.1** unless noted otherwise.
