# Architecture Decision Records

Irreversible or controversial decisions for **puma-enhanced-stats** (server JSON contract and terminal dashboard CLI).

Operational detail lives in [CLI TDD](../cli/tdd.md) and [CLI UI spec](../cli/ui-spec.md). ADRs explain **why** a decision was made.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-cli-load-isolated-from-rails.md) | CLI loaded only in executables, not Rails boot | Accepted |
| [0002](0002-process-metrics-in-cli-not-json.md) | Process metrics via local `ProcessSampler`, not JSON v1 | Accepted |
| [0003](0003-stdlib-tui-without-curses.md) | TUI with stdlib + `pastel`; no curses | Accepted |
| [0004](0004-scroll-state-and-alternate-screen.md) | Persistent scroll: `ScrollState` + alternate screen buffer | Accepted |
| [0005](0005-host-vs-puma-resource-attribution.md) | Host vs Puma resource attribution (`ResourceAttribution`) | Accepted |
| [0006](0006-thread-local-current-requests.md) | Thread-local CurrentRequests (superseded) | Superseded |
| [0007](0007-lazy-snapshot-from-env.md) | Lazy snapshot from thread-local env | Accepted |
| [0008](0008-enhanced-stats-puma-aligned-json.md) | Enhanced-stats JSON aligned with Puma `/stats` | Accepted |

## When to write an ADR

- Loading, packaging, or dependency choices that are hard to reverse
- Splitting responsibility between gem server and CLI consumer
- JSON contract or wire-format changes
- UX architecture (scroll model, alternate screen) — not pixel-level layout

**Not an ADR:** field labels, mockups, badge colors, keyboard shortcuts — use [ui-spec.md](../cli/ui-spec.md).

## Template

Copy and increment the number for new decisions:

```markdown
# NNNN. Title

- **Status:** Proposed | Accepted | Superseded by ADR-XXXX
- **Date:** YYYY-MM-DD
- **Context:** What problem or constraint forced a decision?
- **Decision:** What we chose (one clear paragraph).
- **Consequences:** Trade-offs, follow-up work, what we explicitly did not do.
```

## Related docs

- [CLI documentation index](../cli/README.md)
- [Gem architecture](../architecture.md) — server-side components
- [JSON contract](../json-contract.md) — HTTP payload v1 (CLI is a consumer)
