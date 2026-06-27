# CLI documentation (`puma-enhanced-stats`)

Design and behavior of the **interactive terminal dashboard** for [enhanced-stats](../json-contract.md) v1. Target release: gem **0.6.0**.

The CLI was removed in 0.4.0; these docs define the 0.6.0 reintroduction.

## Reading order

| Document | Audience | Contents |
|----------|----------|----------|
| [Technical design (TDD)](tdd.md) | Implementers, reviewers | Data flow, modules, flags, stub server, scroll model |
| [UI / functional spec](ui-spec.md) | Implementers, UX review | Mockups, grid layout, modals, badges, keyboard map |
| [ADRs](../adr/README.md) | Architects, contributors | Why key decisions were made |

**Also read (existing):**

- [JSON contract](../json-contract.md) — fields the CLI consumes over HTTP
- [Operations](../operations.md) — cluster tuning, [Docker + CLI](../operations.md#terminal-cli-and-docker)
- [Architecture](../architecture.md) — [gem server vs CLI standalone](../architecture.md#terminal-cli-standalone)

## Document status

| File | Status |
|------|--------|
| [tdd.md](tdd.md) | Complete |
| [ui-spec.md](ui-spec.md) | Complete |
| [ADRs 0001–0005](../adr/README.md) | Complete |

**Source of truth** for CLI behavior: cite these files in issues and PRs, not Cursor plan drafts.

## Quick reference

```bash
# Watch dashboard (default)
bundle exec puma-enhanced-stats

# Single snapshot, no TUI
bundle exec puma-enhanced-stats --no-watch

# Debug with stub HTTP server (no Puma required)
bundle exec puma-enhanced-stats-stub --workers 3 --scenario mixed
bundle exec puma-enhanced-stats -C tcp://127.0.0.1:9293 -T dev

# Docker (recommended)
docker compose exec web bundle exec puma-enhanced-stats
```

In watch mode, press **`?`** or **`h`** for in-app field reference ([ui-spec — Help](ui-spec.md#help-h)).

## Hierarchy

```text
schema/enhanced-stats-v1.json + json-contract.md   ← HTTP contract
        ↓
docs/cli/tdd.md                                    ← how CLI consumes & enriches
        ↓
docs/cli/ui-spec.md                                ← how the screen should look
docs/adr/000N-*.md                                 ← why we decided X
```
