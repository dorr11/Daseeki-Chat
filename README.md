# Daseeki Chat

A modern, configurable chat window for WoW Classic Era. Skins the game's own
chat windows in the shared Daseeki look, and — the flagship — keeps tabs,
channels, colors, fonts and layout in one account-spanning configuration that
every character reconciles to automatically at login. Zero per-character setup.

Status: pre-release (0.9.x). The 1.0.0 feature set is settled in
`DASEEKI_CHAT_DESIGN.md` (kept outside this repo with the suite design docs).

## Requires

- **Required: [Daseeki Core](../Daseeki-Core)** — the shared theme, font and
  widget system every Daseeki window is drawn with. Hard dependency.
- Optional: [Daseeki Nexus](../Daseeki-Nexus) — when present, the chat config
  syncs across accounts over the Nexus mesh (`chatcfg` namespace). Without it,
  config is account-local and everything else works.

## Development

- `harness/run-selftests.cmd [CHAT_DIR]` — headless self-test suite under real
  Lua 5.1 (toc parse/identity gates, the unkind chat simulator, then every
  registered suite). Exit 0 = all pass.
