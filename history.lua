-- Daseeki Chat — history.lua
-- Wave 2: history/badges agent. Cross-session history: per-frame ring-buffer
-- snapshot at logout/reload, server-time stamping, restamp-on-restore
-- (uptime-based entries fade instantly otherwise); per-character, bounded.
-- Placeholder: registers nothing.

local ADDON, ns = ...
ns.History = ns.History or {}
