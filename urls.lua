-- Daseeki Chat — urls.lua
-- Wave 2: pipeline agent. URL detection (scheme / www / bare-domain+TLD;
-- maintained TLD approach, not a frozen snapshot) + select-all editbox popup
-- (no clipboard on era). Placeholder: registers nothing.

local ADDON, ns = ...
ns.Urls = ns.Urls or {}
