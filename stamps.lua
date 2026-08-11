-- Daseeki Chat — stamps.lua
-- Wave 2: pipeline agent. Timestamps: display-layer hook with double-stamp +
-- batch-replay guards; the client's native timestamp CVar respected/warned, not
-- silently forced off. Placeholder: registers nothing.

local ADDON, ns = ...
ns.Stamps = ns.Stamps or {}
