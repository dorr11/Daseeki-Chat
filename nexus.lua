-- Daseeki Chat — nexus.lua
-- Wave 2: reconciler/sync agent. Optional Daseeki-Nexus bridge: registers the
-- `chatcfg` namespace when Nexus is present (store-and-forward, rev-gated,
-- NSREQ backfill — the delegates precedent exactly); LWW by server-time `at`.
-- Fully type-guarded; Chat is unchanged without Nexus. Placeholder: registers nothing.

local ADDON, ns = ...
ns.Nexus = ns.Nexus or {}
