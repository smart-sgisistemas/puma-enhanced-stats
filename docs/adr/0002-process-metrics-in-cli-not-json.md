# 0002. Process metrics via local ProcessSampler, not JSON v1

- **Status:** Accepted
- **Date:** 2026-06-22
- **Context:** Early gem versions exposed `workers[].process` (RSS, CPU) in the HTTP payload. Schema v1 (gem 0.5.x) removed that field to keep the contract focused on Puma/thread-pool and in-flight request data. The terminal dashboard still needs per-process RSS/CPU for worker boxes and the PROCESSES table.
- **Decision:** The CLI enriches the JSON locally via **`ProcessSampler`**, reading `rss` and `%cpu` with `ps -p PID` (batch where possible). TOP host metrics come from **`HostMetrics`** (load, CPU usr/sys/idle, memory, swap). Neither is added back to the JSON schema.
- **Consequences:**
  - JSON contract stays stable; integrators are not tied to host-specific process data.
  - CLI must run **co-located** with Puma workers for meaningful PROCESSES/RSS lines (same machine or same container). Remote HTTP-only use shows `—` for process metrics — documented as degraded mode.
  - `elapsed` and other derived fields are also CLI-only ([JSON contract](../json-contract.md)).
  - Implementation reuses patterns from pre-0.4.0 `ProcessMetrics` / `HostMetrics`, adapted per-PID.

**Related:** [CLI TDD — Data contract](../cli/tdd.md#data-contract), [ADR 0005](0005-host-vs-puma-resource-attribution.md)
