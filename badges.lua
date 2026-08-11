-- Daseeki Chat — badges.lua
-- Wave 2: history/badges agent. Per-tab unread counters: increment on line-add
-- to non-active windows, clear on tab focus; quiet rendering on the tab skin.
-- Placeholder: registers nothing.

local ADDON, ns = ...
ns.Badges = ns.Badges or {}
