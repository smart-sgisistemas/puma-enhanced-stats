# 0004. Persistent scroll via ScrollState and alternate screen buffer

- **Status:** Accepted
- **Date:** 2026-06-22
- **Context:** Watch mode polls every few seconds and redraws the full frame. Without state, long in-flight request lists reset to the top on each refresh — unlike `top`, where the operator keeps reading position. Terminal emulators also conflate scrollback history with live dashboard output unless the alternate screen buffer is used.
- **Decision:**
  1. On watch + TTY, enter the **alternate screen** (`\e[?1049h`, fallback `\e[?47h`) and restore on exit (`Terminal.leave_alternate_screen!` in `ensure`).
  2. Maintain **`ScrollState`** across polls: `request_offset[worker_index]`, optional `worker_offset`, `focus_worker`. Keys `j`/`k`/`[`/`]` adjust offsets without refetching.
  3. After each fetch, **clamp** offsets when counts shrink; do **not** persist scroll in `~/.pesrc` (session-only).
  4. `--no-watch` and `--json` skip alternate screen and scroll.
- **Consequences:**
  - Full-frame clear + redraw each poll (no curses window regions).
  - Modals (Design/Sort/Filter/Help) freeze the visible dashboard; offsets stay intact underneath.
  - `RequestTable` renders a window `[offset .. offset+limit)` with header `IN-FLIGHT (4-7/42)`.
  - Shell scrollback is preserved when the user quits with Ctrl+C.

**Related:** [CLI UI spec — Scroll](../cli/ui-spec.md#scroll-and-refresh), [CLI TDD — Watch loop](../cli/tdd.md#watch-loop)
