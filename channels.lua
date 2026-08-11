-- Daseeki Chat — channels.lua
-- Wave 2: reconciler/sync agent. Channel membership + deterministic numbering
-- (>=0.5s pacing, verify loops) + color re-imposition BY NAME on every
-- join/renumber. Placeholder: registers nothing.

local ADDON, ns = ...
ns.Channels = ns.Channels or {}
