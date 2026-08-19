-- Daseeki Chat — nexus.lua  (Wave 2, reconciler/sync agent — REAL)
--
-- The OPTIONAL Daseeki-Nexus bridge: when Nexus is present, the authoritative
-- chat config rides its mesh as the `chatcfg` namespace, following the
-- Nexus "delegates" namespace precedent EXACTLY:
--
--   * ACCOUNT-GRANULAR: ownerKey is omitted on registration, so it defaults
--     to this account's Nexus id — one payload per ACCOUNT, one rev to gate.
--   * The payload is { v, at, cfg }: `cfg` is the whole config (windows,
--     colors-by-name, join list) and `at` is the SERVER-TIME stamp of the
--     last local edit. Per-owner transport is the Sync store's
--     owner-wins-by-rev; the CROSS-owner rule (which account's copy IS the
--     config) is last-writer-wins on `at`, resolved at read time by
--     config.lua's PickWinner — rev then smallest owner as deterministic
--     tiebreaks.
--   * provide() returns NIL until the owner has ever adopted/edited (rev 0):
--     a fresh install broadcasts NOTHING. After the first edit an "emptier"
--     config still publishes — a deliberate clear must out-write older state.
--   * STORE-AND-FORWARD, REV-GATING and NSREQ BACKFILL are the mesh's own
--     machinery — registering the namespace buys all three. OLD CLIENTS ARE
--     SAFE BY CONSTRUCTION (the delegates/attune argument verbatim): a peer
--     that has never heard of `chatcfg` caches the payload silently, errors
--     on nothing, and replays it to its consumer the moment it updates.
--   * RECEIVE NEVER ADOPTS: onRemote only pumps a bus beat (CHATCFG_REMOTE);
--     the reconciler re-resolves the effective winner at read time. Local
--     ADOPTION happens only on the edit path (Config.AdoptEffective, before
--     a local edit publishes).
--
-- WITHOUT NEXUS: every probe here fails soft (type-guarded at every step),
-- the config stays account-local, and everything else in Daseeki-Chat is
-- byte-for-byte identical. The bridge moves ONLY the config blob — no chat
-- text ever rides the mesh.
--
-- This file is PASSIVE (the Bags nexus.lua precedent): no lifecycle module,
-- no hooks, no client events — only bus listeners and guarded calls into the
-- PUBLIC Daseeki.Sync surface. The .toc's OptionalDeps line is a load-order
-- statement so Nexus (and Daseeki.Sync) exist before our registration runs.

local ADDON, ns = ...

local Nexus = {}
ns.Nexus = Nexus

Nexus.NS_KEY     = "chatcfg"
Nexus.registered = false

----------------------------------------------------------------------
-- RELAY TRACE (2026-08-18). The chatcfg stall — cross-account config that
-- stopped arriving — cost a three-account SavedVariables diff to see, because
-- neither side of the bridge recorded what it had last done. The defect was in
-- Nexus's transport (its receive-side seq gate refused every frame its own
-- priority queue had reordered, which is every backfill answer), but the
-- diagnosis was slow because OUR half was equally silent: nothing said when we
-- last published, and nothing said when we last heard from a given account.
--
-- These are the Chat-side half of a one-paste verdict (`/dchat debug nexus`):
--   publishes / lastPublishAt / lastPublishRev   did WE put anything on the wire
--   remoteBeats / lastRemote[owner]              did anything ARRIVE, and from whom
-- Run it on both accounts and diff: an owner whose `at` differs between the two
-- pastes, with no recent beat on the stale side, is a transport stall; the same
-- `at` on both sides with a drifted UI is a reconciler question instead.
----------------------------------------------------------------------

Nexus.publishes      = 0     -- MarkDirty calls that reached Daseeki.Sync
Nexus.lastPublishAt  = nil   -- server time of the last one
Nexus.lastPublishRev = nil   -- the rev it carried
Nexus.remoteBeats    = 0     -- onRemote deliveries (live frames + login replay)
Nexus.lastRemote     = {}    -- [ownerKey] = { at = <server time>, n = <count> }

----------------------------------------------------------------------
-- PRESENCE PROBE. `G` is injectable for the harness; every step is a type
-- guard and failure comes with a human reason.
----------------------------------------------------------------------

local REQUIRED_FNS = { "RegisterNamespace", "Get", "MarkDirty", "LocalOwnerKey" }

function Nexus.Sync(G)
    G = G or _G
    if type(G) ~= "table" then return nil, "no global table" end
    local D = G.Daseeki
    if type(D) ~= "table" then
        return nil, "Daseeki-Nexus is not installed (no Daseeki global)"
    end
    local S = D.Sync
    if type(S) ~= "table" then
        return nil, "Daseeki.Sync is not published (older Nexus build?)"
    end
    for _, fname in ipairs(REQUIRED_FNS) do
        if type(S[fname]) ~= "function" then
            return nil, "Daseeki.Sync lacks " .. fname .. " (namespace API mismatch)"
        end
    end
    return S
end

function Nexus.Present(G)
    return (Nexus.Sync(G)) ~= nil
end

----------------------------------------------------------------------
-- The namespace spec callbacks.
----------------------------------------------------------------------

-- Our wire payload. nil until rev > 0 (fresh installs publish nothing).
function Nexus.Provide()
    local C = ns.Config
    if not (C and C.Snapshot) then return nil end
    return C.Snapshot()
end

-- Our monotonic wire rev = the config's local edit counter (rev-gated
-- propagation: a re-publish of an unchanged rev is a no-op on every peer).
function Nexus.Rev()
    local C = ns.Config
    return (C and C.Rev and C.Rev()) or 0
end

-- RECEIVE NEVER ADOPTS: the Sync store already holds the peer's payload
-- (ApplyInbound put it there before calling us). Pump the beat; the
-- reconciler decides whether the new winner means drift to correct.
function Nexus.OnRemote(ownerKey, _data)
    -- Trace first, so a beat is recorded even if a listener throws.
    local C = ns.Config
    local at = (C and C.Now and C.Now()) or 0
    Nexus.remoteBeats = (Nexus.remoteBeats or 0) + 1
    if type(ownerKey) == "string" then
        local rec = Nexus.lastRemote[ownerKey]
        if rec then rec.at, rec.n = at, (rec.n or 0) + 1
        else Nexus.lastRemote[ownerKey] = { at = at, n = 1 } end
    end
    if ns.Fire then ns:Fire("CHATCFG_REMOTE", ownerKey) end
end

----------------------------------------------------------------------
-- Registration (idempotent; re-registering just refreshes the spec).
----------------------------------------------------------------------

function Nexus.Register(G)
    local S, why = Nexus.Sync(G)
    if not S then return false, why end
    local ok, err = pcall(S.RegisterNamespace, Nexus.NS_KEY, {
        -- ownerKey omitted ON PURPOSE: defaults to this account's Nexus id
        -- (account-granular — the delegates/attune precedent).
        provide  = Nexus.Provide,
        rev      = Nexus.Rev,
        onRemote = Nexus.OnRemote,
    })
    if not ok then
        if ns.RouteError then ns.RouteError(err) end
        return false, "RegisterNamespace raised"
    end
    Nexus.registered = true
    return true
end

----------------------------------------------------------------------
-- The consumer surface config.lua resolves LWW through.
----------------------------------------------------------------------

-- OUR owner key on the mesh ("" without Nexus — the local-only world).
function Nexus.LocalOwner(G)
    local S = Nexus.Sync(G)
    if not S then return "" end
    local ok, o = pcall(S.LocalOwnerKey, Nexus.NS_KEY)
    return (ok and type(o) == "string") and o or ""
end

-- Every PEER account's payload as an LWW candidate { at, rev, owner, cfg }.
-- Our own owner key is EXCLUDED — the live local config replaces it (the
-- Sync.Get self-immunity, restated). Deterministic assembly: owners sorted
-- (Class 8). A malformed peer payload contributes nothing (receive-side heal).
function Nexus.RemoteCandidates(G)
    local S = Nexus.Sync(G)
    if not S then return {} end
    local ok, view = pcall(S.Get, Nexus.NS_KEY)
    if not ok or type(view) ~= "table" then return {} end
    local mine = Nexus.LocalOwner(G)
    local owners = {}
    for o in pairs(view) do
        if type(o) == "string" and o ~= mine then owners[#owners + 1] = o end
    end
    table.sort(owners)
    local out = {}
    for _, o in ipairs(owners) do
        local data = view[o]
        if type(data) == "table" and type(data.cfg) == "table" then
            out[#out + 1] = {
                at    = tonumber(data.at) or 0,
                rev   = 0,   -- peer revs are per-owner transport gates, not LWW input
                owner = o,
                cfg   = data.cfg,
            }
        end
    end
    return out
end

-- Publish beat: snapshot our provide() into the Sync store and queue the
-- mesh push (debounced, chunked, store-and-forward on the Nexus side).
-- Config.Bump calls this after every local edit; safe no-op without Nexus.
function Nexus.MarkDirty(G)
    if not Nexus.registered then return false end
    local S = Nexus.Sync(G)
    if not S then return false end
    local ok = pcall(S.MarkDirty, Nexus.NS_KEY)
    if ok then
        local C = ns.Config
        Nexus.publishes      = (Nexus.publishes or 0) + 1
        Nexus.lastPublishAt  = (C and C.Now and C.Now()) or 0
        Nexus.lastPublishRev = Nexus.Rev()
    end
    return ok and true or false
end

----------------------------------------------------------------------
-- Wiring: register as soon as the world allows (Nexus loads before us via
-- OptionalDeps, so its Sync surface exists at our ADDON_LOADED). Publishing
-- happens on edits (Config.Bump -> MarkDirty); Nexus's own login pass
-- delivers cached remote owners and advertises rev hashes.
----------------------------------------------------------------------

local function tryRegister()
    if Nexus.registered then return end
    Nexus.Register()
end

ns:On("DB_READY", tryRegister)
ns:On("LOGIN", tryRegister)
if ns.state and ns.state.loaded then tryRegister() end

----------------------------------------------------------------------
-- Debug surface.
----------------------------------------------------------------------

ns.RegisterDebugCommand("nexus", "chatcfg bridge: presence, owner, candidates", function()
    local S, why = Nexus.Sync()
    if not S then
        ns:Print("nexus bridge: inactive — " .. tostring(why))
        ns:Print("  the config is account-local; everything else is unchanged")
        return
    end
    ns:Print(("nexus bridge: present, namespace '%s' %s"):format(
        Nexus.NS_KEY, Nexus.registered and "registered" or "NOT registered"))
    ns:Print("  local owner: " .. tostring(Nexus.LocalOwner()))
    local snap = Nexus.Provide()
    if snap then
        ns:Print(("  publishing: rev %d, at %d"):format(Nexus.Rev(), tonumber(snap.at) or 0))
    else
        ns:Print("  publishing: nothing (config never adopted/edited)")
    end

    ------------------------------------------------------------------
    -- THE RELAY VERDICT. Paste this block from BOTH accounts and diff it: an
    -- owner whose `at` differs across the two pastes, with no recent beat on the
    -- stale side, is a TRANSPORT stall (take it to /dsn debug mesh, ns-lastrecv
    -- and ns-refusals). Identical `at` on both sides with a drifted UI is a
    -- RECONCILER question instead (/dchat debug reconcile).
    ------------------------------------------------------------------
    local nowT = (ns.Config and ns.Config.Now and ns.Config.Now()) or 0
    local function ago(at)
        if not at or at <= 0 then return "never" end
        return ("%ds ago"):format(nowT - at)
    end
    ns:Print(("  outbound: %d publish(es), last rev %s at %s (%s)"):format(
        Nexus.publishes or 0, tostring(Nexus.lastPublishRev or "-"),
        tostring(Nexus.lastPublishAt or 0), ago(Nexus.lastPublishAt)))
    ns:Print(("  inbound: %d remote beat(s) across %d owner(s)"):format(
        Nexus.remoteBeats or 0, (function()
            local n = 0
            for _ in pairs(Nexus.lastRemote) do n = n + 1 end
            return n
        end)()))

    local cands = Nexus.RemoteCandidates()
    ns:Print(("  %d peer candidate(s)"):format(#cands))
    for _, cand in ipairs(cands) do
        local beat = Nexus.lastRemote[cand.owner]
        ns:Print(("    %s at %d | last beat %s (%d)"):format(
            tostring(cand.owner), cand.at, ago(beat and beat.at), (beat and beat.n) or 0))
    end
    -- An owner we have HEARD FROM but hold no usable candidate for is the loudest
    -- possible symptom (a payload arrived and was unreadable), so name it.
    local seen = {}
    for _, cand in ipairs(cands) do seen[cand.owner] = true end
    for owner, rec in pairs(Nexus.lastRemote) do
        if not seen[owner] and owner ~= Nexus.LocalOwner() then
            ns:Print(("    %s BEAT WITHOUT A CANDIDATE — %d beat(s), last %s"):format(
                tostring(owner), rec.n or 0, ago(rec.at)))
        end
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "nexus"). The Nexus side is a MINIMAL IN-SUITE STUB of
-- the public Daseeki.Sync surface — Nexus itself is never imported (its own
-- repo pins the transport; this suite pins OUR side of the contract).
----------------------------------------------------------------------

local function stubSync()
    local S
    S = {
        registered     = {},   -- key -> spec
        markDirtyCalls = 0,
        remote         = {},   -- ownerKey -> data (the peer payload store)
        RegisterNamespace = function(key, spec)
            S.registered[key] = spec
            return true
        end,
        -- The real Sync.Get merges stored remote owners with OUR live
        -- provide() under our own owner key; the stub mirrors that.
        Get = function(key)
            local view = {}
            for o, d in pairs(S.remote) do view[o] = d end
            local spec = S.registered[key]
            if spec and spec.provide then
                local ok, data = pcall(spec.provide)
                if ok and data ~= nil then view["ACC-SELF"] = data end
            end
            return view
        end,
        LocalOwnerKey = function() return "ACC-SELF" end,
        MarkDirty = function(key)
            S.markDirtyCalls = S.markDirtyCalls + 1
            return true
        end,
    }
    return S
end

local function testDetection(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    -- Absent Nexus: every probe fails SOFT with a readable reason, and the
    -- config path is unchanged (local-only).
    local S, why = Nexus.Sync({})
    ck(S == nil and type(why) == "string" and why:find("not installed"),
        "absent Nexus probes soft with a reason")
    ck(Nexus.Sync({ Daseeki = {} }) == nil, "Daseeki without Sync refuses")
    ck(Nexus.Sync({ Daseeki = { Sync = { Get = function() end } } }) == nil,
        "a partial Sync surface refuses (API mismatch guard)")
    ck(Nexus.Present({}) == false, "Present is false without Nexus")
    ck(select(1, Nexus.Register({})) == false, "Register fails soft")
    ck(type(Nexus.RemoteCandidates({})) == "table" and #Nexus.RemoteCandidates({}) == 0,
        "no Nexus = zero remote candidates")
    ck(Nexus.LocalOwner({}) == "", "no Nexus = empty local owner key")

    -- The live headless world has no Daseeki global either: the bridge never
    -- self-registered during this whole harness run.
    if _G.Daseeki == nil then
        ck(Nexus.registered == false, "no self-registration happened headless")
        ck(Nexus.MarkDirty() == false, "MarkDirty is a safe no-op unregistered")
    end

    -- Config edits work with the bridge absent (the local-only contract).
    local C = ns.Config
    local c = C.Get()
    local revBefore = C.Rev()
    ck(C.Bump() == true, "a config edit succeeds without Nexus")
    ck(C.Rev() == revBefore + 1, "the rev advanced locally")
    c.rev = revBefore   -- restore for later suites' arithmetic
end

local function testContract(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local C = ns.Config
    local c = C.Get()

    local prevDaseeki = _G.Daseeki
    local prevRegistered = Nexus.registered
    local stub = stubSync()
    _G.Daseeki = { Sync = stub }
    Nexus.registered = false

    -- Registration: the exact delegates spec shape.
    ck(Nexus.Register() == true, "registration succeeds against the stub")
    local spec = stub.registered[Nexus.NS_KEY]
    ck(type(spec) == "table", "the chatcfg namespace was registered")
    ck(type(spec.provide) == "function" and type(spec.onRemote) == "function"
        and type(spec.rev) == "function",
        "provide/rev/onRemote are all wired")
    ck(spec.ownerKey == nil,
        "ownerKey is OMITTED (account-granular default — the delegates precedent)")

    -- Fresh install publishes NOTHING.
    c.rev, c.at = 0, 0
    ck(spec.provide() == nil, "rev 0 provides nil (a fresh install broadcasts nothing)")

    -- After an edit: the { v, at, cfg } payload, rev-gated.
    c.rev, c.at = 2, 500000
    c.windows = { [1] = { name = "Mine" } }
    c.colors = { world = { r = 1, g = 0, b = 0 } }
    c.join = { { 1, "General" } }
    local payload = spec.provide()
    ck(type(payload) == "table" and payload.v == 1 and payload.at == 500000,
        "the payload is the { v, at, cfg } delegates shape")
    ck(payload.cfg.windows[1].name == "Mine" and payload.cfg.colors.world.r == 1,
        "the payload carries the whole config")
    ck(spec.rev() == 2, "the wire rev is the config's edit counter")

    -- Edits publish through MarkDirty (Config.Bump -> Nexus.MarkDirty).
    local dirtyBefore = stub.markDirtyCalls
    local pubBefore = Nexus.publishes
    C.Bump()
    ck(stub.markDirtyCalls == dirtyBefore + 1, "an edit queues exactly one mesh publish")

    -- RELAY TRACE: the publish is RECORDED. Without this the Chat half of a
    -- stall verdict is "we think we sent something", which is what made the
    -- 2026-08-18 chatcfg stall take a three-account store diff to place.
    ck(Nexus.publishes == pubBefore + 1, "the publish was not counted")
    ck((Nexus.lastPublishAt or 0) > 0, "the publish carried no timestamp")
    ck(Nexus.lastPublishRev == C.Rev(), "the recorded publish rev is not the config's rev")

    -- LWW through the real Config path, remote candidates from the stub store.
    c.rev, c.at = 3, 8000
    stub.remote["ACC-B"] = { v = 1, at = 9000,
        cfg = { windows = { [1] = { name = "Theirs" } }, colors = {}, join = {} } }
    stub.remote["ACC-JUNK"] = "malformed"
    local cands = Nexus.RemoteCandidates()
    ck(#cands == 1 and cands[1].owner == "ACC-B" and cands[1].at == 9000,
        "peer candidates assemble (self excluded, malformed healed out)")
    local eff, owner = C.EffectiveCfg()
    ck(owner == "ACC-B" and eff.windows[1].name == "Theirs",
        "a newer peer `at` wins the effective config at READ time")
    ck(c.windows[1].name == "Mine",
        "...and reading NEVER wrote the local store (receive never adopts)")

    -- RECEIVE NEVER ADOPTS, through the registered onRemote itself.
    local pumped = nil
    local listener = function(ownerKey) pumped = ownerKey end
    local beatsBefore = Nexus.remoteBeats
    ns:On("CHATCFG_REMOTE", listener)
    spec.onRemote("ACC-B", stub.remote["ACC-B"])
    ns:Off("CHATCFG_REMOTE", listener)
    ck(pumped == "ACC-B", "onRemote pumps the bus beat")
    ck(c.windows[1].name == "Mine" and C.Rev() == 3,
        "onRemote wrote NOTHING into the local config")

    -- RELAY TRACE: the beat is RECORDED per owner. "Did anything arrive from
    -- that account, and when" is the question a stall is placed by.
    ck(Nexus.remoteBeats == beatsBefore + 1, "the remote beat was not counted")
    ck(type(Nexus.lastRemote["ACC-B"]) == "table" and Nexus.lastRemote["ACC-B"].n >= 1,
        "no per-owner beat row was recorded")
    ck((Nexus.lastRemote["ACC-B"].at or 0) > 0, "the beat row carried no timestamp")
    -- A second beat from the same owner updates the row rather than adding one.
    spec.onRemote("ACC-B", stub.remote["ACC-B"])
    ck(Nexus.lastRemote["ACC-B"].n == 2, "repeat beats from one owner were not accumulated")
    -- ...and a malformed ownerKey is traced without creating a junk row.
    local beatsBeforeBad = Nexus.remoteBeats
    spec.onRemote(nil, nil)
    ck(Nexus.remoteBeats == beatsBeforeBad + 1, "a malformed beat was not counted")
    ck(Nexus.lastRemote[nil] == nil, "a malformed ownerKey created a row")

    -- ADOPT-EFFECTIVE-BEFORE-EDIT: the edit path adopts the winner, keeps the
    -- local rev counter, and the following bump publishes winner+edit.
    ck(C.AdoptEffective() == true, "a winning peer copy adopts on the EDIT path")
    ck(c.windows[1].name == "Theirs", "the winner's sections landed locally")
    ck(C.Rev() == 3, "the local rev counter is KEPT on adoption (delegates law)")

    -- When the local copy wins, adoption is a no-op.
    c.at = 9500
    c.windows[1].name = "Mine Again"
    ck(C.AdoptEffective() == false, "a winning local copy never re-adopts")
    ck(c.windows[1].name == "Mine Again", "local sections untouched")

    -- `at` tie: the local candidate carries its real rev, a peer carries 0 —
    -- the deterministic tiebreak keeps the local copy (no flicker).
    c.at = 9000
    local eff2, owner2 = C.EffectiveCfg()
    ck(owner2 == "ACC-SELF", "an `at` tie resolves to the higher-rev local copy")

    _G.Daseeki = prevDaseeki
    Nexus.registered = prevRegistered
    ck(Nexus.MarkDirty() == false or Nexus.Present(),
        "with the stub gone the bridge is soft-off again")
end

ns:RegisterSelfTest("nexus", function(verbose)
    local suites = {
        { name = "detection + local-only fallback", fn = testDetection },
        { name = "chatcfg contract + LWW + adopt",  fn = testContract },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local ok, err = pcall(suite.fn, fails)
        if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
        local passed = #fails == 0
        if not passed then allPass = false end
        if verbose and ns.Print then
            if passed then ns:Print("  PASS nexus/" .. suite.name)
            else for _, f in ipairs(fails) do ns:Print("  FAIL nexus/" .. suite.name .. " :: " .. f) end end
        end
    end
    return allPass
end)

return Nexus
