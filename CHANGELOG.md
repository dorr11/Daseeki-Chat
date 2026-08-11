# Changelog

## Unreleased — first release

Daseeki Chat replaces Prat on this account: a skin-over treatment of the game's
own ten chat windows, drawn in the shared Daseeki look, with one account-spanning
chat configuration that every character — including a brand-new one — reconciles
to automatically at login.

This entry accumulates until 1.0.0 ships. Foundation so far:

- Repo skeleton, module lifecycle, `/dchat` slash surface with an extensible
  `debug` subcommand registry, additive-and-healing SavedVariables init.
- Suite-themed chat skin: token-driven window backdrops and tab styling, themed
  attached edit box, Core font roles applied to every window, configurable text
  fading, and a per-window copy-chat affordance (era has no clipboard; the copy
  window pre-selects the text for Ctrl+C).
- **Channel-colored tabs.** Each chat tab is inked by the channel that window is
  actually for: a guild window's tab in guild-chat green, a single-channel
  window's tab in that channel's color, the combat log in its own muted
  treatment. Dominance is strict — a window earns a color only when its routing
  (message groups and channels, from the shared config) collapses to exactly one
  identity, so the busy default window keeps the standard treatment. The colors
  are the *game's own* chat colors, read live, so they follow your color settings
  and update the moment you change one. The selected tab wears its color at full
  strength under an accent underline; the rest are dimmed.
- **Timestamp divider.** With timestamps on, a subtle hairline separates the
  stamp column from the message text. It measures the real width of your chosen
  stamp format, and it is absent whenever timestamps are.
- **Colored channel prefix in the edit box.** The attached input's sticky-channel
  label ("Guild:", "2. World:") wears that channel's color and keeps up with a
  color change made while the box is open.
- **Icon rail (off by default).** An optional slim strip on a window's left edge
  with three affordances Chat already has: copy chat, settings, and jump to the
  newest line. Nothing new hides behind them.
- Every one of the four is a separate switch under `/dchat debug skin`; turning
  the tab colors off restores the previous look exactly.
- The headless harness with the unkind chat simulator: the 10-window client
  model, async server-gated channel joins, mutable per-frame ring buffers with
  uptime stamps, GUID-carrying era message events, the edit box's sticky-channel
  header beat, and call counting throughout.
