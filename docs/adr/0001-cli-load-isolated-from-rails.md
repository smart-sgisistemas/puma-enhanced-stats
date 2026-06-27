# 0001. CLI loaded only in executables, not Rails boot

- **Status:** Accepted
- **Date:** 2026-06-22
- **Context:** The gem integrates with Puma and Rails via a Railtie and prepends Puma internals at load time ([`lib/puma/enhanced/stats.rb`](../../lib/puma/enhanced/stats.rb)). A terminal dashboard CLI adds executables, TUI code, and optional dependencies (`pastel`). Loading CLI code during every Rails boot would increase memory, slow boot, and risk accidental coupling between dashboard tooling and request-path code.
- **Decision:** The CLI lives under `lib/puma/enhanced/stats/cli/` and is required **only** from executables (`exe/puma-enhanced-stats`, `exe/puma-enhanced-stats-stub`). The main entry point [`lib/puma/enhanced/stats.rb`](../../lib/puma/enhanced/stats.rb) does **not** require CLI modules. `pumactl enhanced-stats` and `GET /enhanced-stats` remain the non-interactive integration path.
- **Consequences:**
  - Server-side gem stays lean for production apps that never install the CLI binary.
  - CLI can be tested in isolation with a stub HTTP server.
  - Contributors must not add `require "puma/enhanced/stats/cli"` to the Railtie or main require chain.
  - Packaging must declare `bindir` and `executables` in the gemspec so `bundle exec puma-enhanced-stats` works.

**Related:** [CLI TDD](../cli/tdd.md), [Architecture](../architecture.md#terminal-cli-standalone)
