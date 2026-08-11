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
- The headless harness with the unkind chat simulator: the 10-window client
  model, async server-gated channel joins, mutable per-frame ring buffers with
  uptime stamps, GUID-carrying era message events, and call counting throughout.
