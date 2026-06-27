# Documentation

Guides for **puma-enhanced-stats** v1.0.0. The gem exposes in-flight HTTP requests and Puma thread-pool counters through a stable JSON contract on the Puma control app, plus a standalone terminal dashboard CLI.

## Reading order

| Guide | Audience | Topics |
|-------|----------|--------|
| [Operations](operations.md) | App operators, SRE | DSL, cluster tuning, troubleshooting |
| [JSON contract](json-contract.md) | Integrators, tooling authors | Schema v1 fields, Puma-aligned keys, single vs cluster |
| [Security](security.md) | Security reviewers, operators | Control app, tokens, session fields, PII |
| [Architecture](architecture.md) | Contributors | Data flow, Puma hooks, separation from `/stats` |
| [CLI — technical design](cli/tdd.md) | CLI implementers | Modules, flags, stub, watch loop |
| [CLI — UI spec](cli/ui-spec.md) | CLI implementers, review | Mockups, grid, modals, badges |
| [ADRs](adr/README.md) | Contributors | Design decisions (server + CLI) |

## Quick links

- [README](../README.md) — installation and quick start
- [JSON Schema v1](../schema/enhanced-stats-v1.json) — current machine-readable contract
- [Sample payload v1](../spec/fixtures/enhanced-stats-v1.sample.json) — full example
- [CLI documentation](cli/README.md) — terminal dashboard
- [CHANGELOG](../CHANGELOG.md) — release history
- [CONTRIBUTING](../CONTRIBUTING.md) — development workflow

## Product status

- **Control app / `pumactl`** — supported (`GET /enhanced-stats`, `pumactl enhanced-stats`)
- **Terminal dashboard CLI** — implemented on the CLI branch ([cli/tdd.md](cli/tdd.md), [cli/ui-spec.md](cli/ui-spec.md))

## Version

Documentation matches gem **v1.0.0** (JSON API) unless noted otherwise; CLI docs describe the dashboard shipped on the CLI branch.
