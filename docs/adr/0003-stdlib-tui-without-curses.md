# 0003. TUI with stdlib + pastel; no curses in 0.6.0

- **Status:** Accepted
- **Date:** 2026-06-22
- **Context:** The terminal dashboard needs colors, box drawing, keyboard input, and periodic redraw. Ruby offers `curses`/`ncurses`, third-party TUI gems, or stdlib (`io/console`, ANSI escape sequences, `Signal.trap("WINCH")`). The pre-0.3.x gemspec listed `tty-screen` but did not use it. Adding native extension dependencies increases install friction in containers and CI.
- **Decision:** For release **0.6.0**, the TUI uses **stdlib only** for terminal control (clear, alternate screen, winsize, non-blocking stdin) plus **`pastel ~> 0.8`** for ANSI colors. Box borders are simple Unicode (`┌─┐│└┘`). **No `curses`**, **no `tty-screen`**, **no full-screen TUI framework**.
- **Consequences:**
  - Scroll and partial redraw are implemented manually ([ADR 0004](0004-scroll-state-and-alternate-screen.md)).
  - Possible flicker on slow SSH links — acceptable for 5s poll interval; reconsider curses in **0.7+** only if flicker remains a reported problem.
  - Single optional runtime dependency (`pastel`); `--no-color` disables ANSI.
  - Modals and help overlay reuse the same print-and-clear loop as the main dashboard.

**Related:** [CLI UI spec](../cli/ui-spec.md), [CLI TDD — Module layout](../cli/tdd.md#module-layout)
