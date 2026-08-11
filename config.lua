-- Daseeki Chat — config.lua  (Wave 2, reconciler/sync agent — REAL)
--
-- The AUTHORITATIVE config model (design doc, reconciler rule 1): the
-- account-spanning chat configuration lives in DaseekiChatDB.config and the
-- client's per-character chat state is a PROJECTION of it. This file owns:
--
--   * the config SHAPE: windows/tabs (name, shown, docking, lock, font size,
--     background color/alpha, saved dimensions + position, message groups,
--     channel routing BY NAME), channel colors BY NAME (the client keys
--     channel colors by NUMBER and numbers shift — the survey's channel-color-
--     memory lesson, spec §3.4/§7.3), and the JOIN LIST (desired channel name
--     per channel number, the deterministic-numbering intent channels.lua
--     converges toward);
--   * CAPTURE: reading the whole client store into a config-shaped snapshot
--     (the GetChatWindowInfo read family — game-facts register §7.2). Channel
--     state is captured only when the channel list is WARM (Class 6: a dark
--     list is not an empty list; an early read must never become "the player
--     has no channels");
--   * DETERMINISTIC serialization (Class 8): canonical sorted emission, used
--     for equality/diffing and to keep every wire payload byte-stable;
--   * rev + server-time `at` on EVERY edit, and the FIRST-RUN rule (rule 5):
--     no config anywhere -> ADOPT the current client state as the initial
--     config. Never impose defaults;
--   * cross-account LWW (the Nexus delegates precedent, exactly): candidates
--     are the local config plus every mesh owner's payload; newest `at` wins,
--     rev then SMALLEST owner key break ties (deterministic on every client);
--     local edits ADOPT-EFFECTIVE-BEFORE-EDIT so an edit made on the account
--     with the older copy publishes "winner + this change", never "stale world
--     + this change"; the RECEIVE side never adopts (reads re-resolve through
--     EffectiveCfg every time).
--
-- This file is PASSIVE: no lifecycle module, no hooks, no client events.
-- reconcile.lua drives capture-back and convergence; nexus.lua moves the
-- snapshot. Everything here runs headless under the harness sim unchanged.
--
-- Clean-room: written from CHAT_ADDONS_BEHAVIOR_SPEC.md and this suite's own
-- Nexus/Bags repos only. All display text ASCII.

local ADDON, ns = ...

local Config = {}
ns.Config = Config

Config.VER = 1                -- wire payload schema version ({ v, at, cfg })

local function numWindows() return _G.NUM_CHAT_WINDOWS or 10 end

----------------------------------------------------------------------
-- Clock. Server epoch for every `at` stamp (GetServerTime — uptime clocks
-- reset per session and are useless for cross-account LWW).
----------------------------------------------------------------------

function Config.Now()
    local f = _G.GetServerTime
    if type(f) == "function" then
        local ok, t = pcall(f)
        if ok and type(t) == "number" then return t end
    end
    return (os and os.time and os.time()) or 0
end

----------------------------------------------------------------------
-- The stored shape. rev 0 = "never adopted or edited" — the state the
-- first-run rule keys off. EnsureDefaults is additive: user data and
-- future-version keys pass through untouched (wire-additive discipline).
----------------------------------------------------------------------

local CFG_DEFAULTS = {
    ver     = 1,
    rev     = 0,      -- local monotonic edit counter
    at      = 0,      -- server-time stamp of the last local edit
    windows = {},     -- [id] = window entry (see CaptureWindow)
    colors  = {},     -- [channel name, lowercased] = { r, g, b }
    join    = {},     -- array of { number, name } pairs, sorted by number
}

function Config.Get()
    if not ns.db then return nil end
    if type(ns.db.config) ~= "table" then ns.db.config = {} end
    ns.EnsureDefaults(ns.db.config, CFG_DEFAULTS)
    return ns.db.config
end

function Config.Rev()
    local c = Config.Get()
    return c and (tonumber(c.rev) or 0) or 0
end

function Config.HasLocal()
    return Config.Rev() > 0
end

-- Is there a config ANYWHERE (local or any mesh owner)? The first-run rule's
-- question.
function Config.HasAnyConfig()
    if Config.HasLocal() then return true end
    local Nx = ns.Nexus
    if Nx and Nx.RemoteCandidates then
        local ok, rc = pcall(Nx.RemoteCandidates)
        if ok and type(rc) == "table" and #rc > 0 then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Wire-heal deep copy: scalars and tables only (functions/userdata never
-- travel), UNKNOWN KEYS KEPT (a newer build's field survives a round-trip
-- through this build — the delegates copy discipline).
----------------------------------------------------------------------

local function copyCfg(src)
    if type(src) ~= "table" then return {} end
    local out = {}
    for k, v in pairs(src) do
        if type(k) == "string" or type(k) == "number" or type(k) == "boolean" then
            if type(v) == "table" then out[k] = copyCfg(v)
            elseif type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                out[k] = v
            end
        end
    end
    return out
end
Config.CopyCfg = copyCfg

----------------------------------------------------------------------
-- DETERMINISTIC serialization (Class 8: pairs() order differs per table
-- lifetime; anything compared, hashed, or retried must emit sorted).
-- Canonical form: numeric keys ascending, then string keys ascending; strings
-- length-prefixed (no delimiter ambiguity); integers and floats distinct.
----------------------------------------------------------------------

local function serValue(v, out)
    local t = type(v)
    if t == "nil" then
        out[#out + 1] = "!"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "number" then
        if v == math.floor(v) and v > -2 ^ 52 and v < 2 ^ 52 then
            out[#out + 1] = string.format("i%d", v)
        else
            out[#out + 1] = string.format("f%.14g", v)
        end
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        local nums, strs = {}, {}
        for k in pairs(v) do
            if type(k) == "number" then nums[#nums + 1] = k
            elseif type(k) == "string" then strs[#strs + 1] = k end
            -- any other key type is unserializable and skipped
        end
        table.sort(nums)
        table.sort(strs)
        out[#out + 1] = "{"
        for _, k in ipairs(nums) do
            out[#out + 1] = "[i" .. k .. "]="
            serValue(v[k], out)
            out[#out + 1] = ";"
        end
        for _, k in ipairs(strs) do
            out[#out + 1] = "[s" .. #k .. ":" .. k .. "]="
            serValue(v[k], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "?"   -- function/userdata: never on the wire
    end
end

function Config.Serialize(v)
    local out = {}
    serValue(v, out)
    return table.concat(out)
end

local function serEq(a, b)
    return Config.Serialize(a) == Config.Serialize(b)
end
Config.SerEq = serEq

-- Color float compare (ChangeChatColor round-trips floats exactly, but a
-- tolerance keeps a client-side quantization from reading as drift forever).
function Config.NearColor(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local function near(x, y)
        return math.abs((tonumber(x) or 0) - (tonumber(y) or 0)) < 0.001
    end
    return near(a.r, b.r) and near(a.g, b.g) and near(a.b, b.b)
end

----------------------------------------------------------------------
-- CAPTURE: client store -> config-shaped snapshot.
----------------------------------------------------------------------

local function sortedList(...)
    local t = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then t[#t + 1] = v end
    end
    table.sort(t)
    return t
end

-- One window's client store entry, normalized (game-facts §7.2 tuple order:
-- name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable).
function Config.CaptureWindow(id)
    local gcwi = _G.GetChatWindowInfo
    if type(gcwi) ~= "function" then return nil end
    local ok, name, fontSize, r, g, b, alpha, shown, locked, docked, unint = pcall(gcwi, id)
    if not ok then return nil end
    local w = {
        name           = tostring(name or ""),
        fontSize       = tonumber(fontSize) or 14,
        r              = tonumber(r) or 0,
        g              = tonumber(g) or 0,
        b              = tonumber(b) or 0,
        alpha          = tonumber(alpha) or 0,
        shown          = (shown and shown ~= 0) and true or false,
        locked         = (locked and locked ~= 0) and true or false,
        uninteractable = (unint and unint ~= 0) and true or false,
        groups         = {},
        channels       = {},
    }
    -- docked: a dock index number, or false (undocked/closed).
    if type(docked) == "number" and docked ~= 0 then w.docked = docked
    elseif docked then w.docked = 1
    else w.docked = false end

    if type(_G.GetChatWindowMessages) == "function" then
        w.groups = sortedList(_G.GetChatWindowMessages(id))
    end
    if type(_G.GetChatWindowChannels) == "function" then
        -- name,zoneID pairs; keep the names, sorted (routing is BY NAME).
        local flat = { _G.GetChatWindowChannels(id) }
        for i = 1, #flat do
            if type(flat[i]) == "string" then w.channels[#w.channels + 1] = flat[i] end
        end
        table.sort(w.channels)
    end
    if type(_G.GetChatWindowSavedDimensions) == "function" then
        local dw, dh = _G.GetChatWindowSavedDimensions(id)
        w.dim = { tonumber(dw) or 0, tonumber(dh) or 0 }
    end
    if type(_G.GetChatWindowSavedPosition) == "function" then
        local p, x, y = _G.GetChatWindowSavedPosition(id)
        w.pos = { tostring(p or ""), tonumber(x) or 0, tonumber(y) or 0 }
    end
    return w
end

-- Channel colors BY NAME for every currently joined channel (the client keys
-- them CHANNEL<number>; we key them by name so they survive renumbering).
function Config.CaptureChannelColors(join)
    local colors = {}
    local CTI = _G.ChatTypeInfo
    if type(CTI) ~= "table" or type(join) ~= "table" then return colors end
    for _, e in ipairs(join) do
        local n, name = e[1], e[2]
        local info = CTI["CHANNEL" .. tostring(n)]
        if type(info) == "table" and type(name) == "string" and name ~= "" then
            colors[name:lower()] = {
                r = tonumber(info.r) or 1,
                g = tonumber(info.g) or 1,
                b = tonumber(info.b) or 1,
            }
        end
    end
    return colors
end

-- The whole client state. `join`/`colors` are nil (UNKNOWN, not empty) unless
-- the channel list is warm — Class 6 made mechanical.
function Config.CaptureClient()
    local snap = { windows = {} }
    for id = 1, numWindows() do
        snap.windows[id] = Config.CaptureWindow(id)
    end
    local Ch = ns.Channels
    if Ch and Ch.IsListWarm and Ch.IsListWarm() and Ch.CaptureJoinList then
        local join = Ch.CaptureJoinList()
        if join then
            snap.join = join
            snap.colors = Config.CaptureChannelColors(join)
        end
    end
    return snap
end

----------------------------------------------------------------------
-- EDITS. Every mutation lands rev+1 and a fresh server-time `at`, then hands
-- the snapshot to the mesh (guarded — without Nexus the config is simply
-- account-local and everything else is identical).
----------------------------------------------------------------------

function Config.Bump()
    local c = Config.Get()
    if not c then return false end
    c.rev = (tonumber(c.rev) or 0) + 1
    c.at = Config.Now()
    local Nx = ns.Nexus
    if Nx and Nx.MarkDirty then pcall(Nx.MarkDirty) end
    if ns.Fire then ns:Fire("CHATCFG_CHANGED") end
    return true
end

-- FIRST-RUN ADOPT (reconciler rule 5's second half): the current client state
-- BECOMES the initial config. Never a default layout, never a wizard.
function Config.AdoptClient(snap)
    local c = Config.Get()
    if not c then return false end
    snap = snap or Config.CaptureClient()
    c.windows = copyCfg(snap.windows or {})
    if snap.join then c.join = copyCfg(snap.join) end
    if snap.colors then
        for k, v in pairs(snap.colors) do c.colors[k] = copyCfg(v) end
    end
    Config.Bump()
    return true
end

-- Would a capture change the stored config? (The capture-back gate.)
function Config.SectionsDiffer(snap)
    local c = Config.Get()
    if not c or type(snap) ~= "table" then return false end
    if not serEq(snap.windows, c.windows) then return true end
    if snap.join and not serEq(snap.join, c.join) then return true end
    if snap.colors then
        for name, col in pairs(snap.colors) do
            if not serEq(col, c.colors[name]) then return true end
        end
    end
    return false
end

-- CAPTURE-BACK (design D3 / reconciler rule 3): a player edit observed on the
-- client surfaces is diffed into the config and synced. ADOPT-EFFECTIVE first:
-- if a peer account's copy currently wins, this edit publishes on top of the
-- winner (the client was converged to the winner, so the wholesale capture IS
-- "winner + the player's change"). Colors MERGE by name — a capture only sees
-- currently-joined channels and must never delete a color the config holds
-- for a channel the character happens not to be in right now.
function Config.CaptureBack(reason)
    local c = Config.Get()
    if not c then return false end
    local snap = Config.CaptureClient()
    if not Config.SectionsDiffer(snap) then return false end
    Config.AdoptEffective()
    c.windows = copyCfg(snap.windows or {})
    if snap.join then c.join = copyCfg(snap.join) end
    if snap.colors then
        for k, v in pairs(snap.colors) do c.colors[k] = copyCfg(v) end
    end
    Config.Bump()
    return true
end

----------------------------------------------------------------------
-- CROSS-ACCOUNT LWW (the delegates rules, verbatim in spirit):
--   PickWinner: newest `at` wins; rev then SMALLEST owner key break ties, so
--   two stores holding the same candidates always agree (Class 8).
--   Candidates: local (only once rev > 0) then remote owners sorted.
--   AdoptEffective: called by EDIT paths only, never by receive.
----------------------------------------------------------------------

-- PURE. cands = array of { at, rev, owner, cfg }.
function Config.PickWinner(cands)
    local best
    for i = 1, #(cands or {}) do
        local cand = cands[i]
        if type(cand) == "table" and type(cand.cfg) == "table" then
            local at, rev = tonumber(cand.at) or 0, tonumber(cand.rev) or 0
            if not best
               or at > best.atN
               or (at == best.atN and rev > best.revN)
               or (at == best.atN and rev == best.revN
                   and tostring(cand.owner) < tostring(best.owner)) then
                best = { atN = at, revN = rev, owner = cand.owner, cfg = cand.cfg }
            end
        end
    end
    if not best then return nil, nil end
    return best.cfg, best.owner
end

function Config.LocalOwnerKey()
    local Nx = ns.Nexus
    if Nx and Nx.LocalOwner then
        local ok, o = pcall(Nx.LocalOwner)
        if ok and type(o) == "string" then return o end
    end
    return ""
end

-- Deterministic assembly: local candidate first, then remote owners in the
-- bridge's sorted order (nexus.lua sorts; without Nexus the list is just us).
function Config.Candidates()
    local out = {}
    local c = Config.Get()
    if c and (tonumber(c.rev) or 0) > 0 then
        out[#out + 1] = {
            at    = tonumber(c.at) or 0,
            rev   = tonumber(c.rev) or 0,
            owner = Config.LocalOwnerKey(),
            cfg   = { windows = c.windows, colors = c.colors, join = c.join },
        }
    end
    local Nx = ns.Nexus
    if Nx and Nx.RemoteCandidates then
        local ok, rc = pcall(Nx.RemoteCandidates)
        if ok and type(rc) == "table" then
            for i = 1, #rc do out[#out + 1] = rc[i] end
        end
    end
    return out
end

-- The EFFECTIVE config every reader (the reconciler, color re-imposition)
-- resolves against. Read-time resolution: a winning remote payload changes
-- the answer WITHOUT a local write (receive never adopts).
function Config.EffectiveCfg()
    return Config.PickWinner(Config.Candidates())
end

-- Adopt the cross-account winner into the LOCAL store when a peer's copy
-- wins. Called by edit paths only (CaptureBack), never on receive — so this
-- can never loop. The local rev counter is KEPT: rev is a local monotonic
-- edit count; the caller's following Bump makes the edit publishable.
function Config.AdoptEffective()
    local cfg, owner = Config.EffectiveCfg()
    if cfg == nil then return false end
    if owner == Config.LocalOwnerKey() then return false end   -- ours already wins
    local c = Config.Get()
    if not c then return false end
    c.windows = copyCfg(cfg.windows or {})
    c.colors  = copyCfg(cfg.colors or {})
    c.join    = copyCfg(cfg.join or {})
    return true
end

----------------------------------------------------------------------
-- The wire payload (delegates shape): { v, at, cfg }. nil until the config
-- has EVER been adopted/edited — a fresh install must broadcast NOTHING
-- (an empty rev-0 config could win nothing and would only be noise).
----------------------------------------------------------------------

function Config.Snapshot()
    local c = Config.Get()
    if not c or (tonumber(c.rev) or 0) <= 0 then return nil end
    return {
        v   = Config.VER,
        at  = tonumber(c.at) or 0,
        cfg = copyCfg({ windows = c.windows, colors = c.colors, join = c.join }),
    }
end

----------------------------------------------------------------------
-- DIFF: config intent vs a client snapshot, as readable strings for the
-- reconciler's verify + trace ring. One-way (config-authoritative): fields
-- the config does not speak about are not drift.
----------------------------------------------------------------------

local WINDOW_FIELDS = {
    "name", "fontSize", "r", "g", "b", "alpha", "shown", "locked", "docked",
    "uninteractable", "dim", "pos", "groups", "channels",
}

function Config.DiffList(want, have)
    local diffs = {}
    if type(want) ~= "table" or type(have) ~= "table" then return diffs end
    local ww, hw = want.windows or {}, have.windows or {}
    for id = 1, numWindows() do
        local a, b = ww[id], hw[id]
        if type(a) == "table" then
            if type(b) ~= "table" then
                diffs[#diffs + 1] = "window " .. id
            else
                for _, f in ipairs(WINDOW_FIELDS) do
                    if a[f] ~= nil and not serEq(a[f], b[f]) then
                        diffs[#diffs + 1] = "window " .. id .. " " .. f
                    end
                end
            end
        end
    end
    -- Join intent only exists once a warm capture wrote one; an UNKNOWN
    -- snapshot side (dark list) is never judged (Class 6).
    if type(want.join) == "table" and #want.join > 0 and type(have.join) == "table" then
        if not serEq(want.join, have.join) then
            diffs[#diffs + 1] = "join list"
        end
    end
    return diffs
end

----------------------------------------------------------------------
-- Debug surface.
----------------------------------------------------------------------

ns.RegisterDebugCommand("config", "authoritative config: rev, stamp, sections", function()
    local c = Config.Get()
    if not c then ns:Print("config: no store attached yet") return end
    ns:Print(("config: rev %d, at %d (%s)"):format(
        tonumber(c.rev) or 0, tonumber(c.at) or 0,
        (tonumber(c.rev) or 0) > 0 and "adopted" or "FIRST-RUN PENDING"))
    local wn = 0
    for _ in pairs(c.windows or {}) do wn = wn + 1 end
    local cn = 0
    for _ in pairs(c.colors or {}) do cn = cn + 1 end
    ns:Print(("  %d window entr(ies), %d channel color(s), %d join entr(ies)")
        :format(wn, cn, #(c.join or {})))
    local eff, owner = Config.EffectiveCfg()
    if eff then
        ns:Print("  effective winner: " .. ((owner == Config.LocalOwnerKey()) and "this account" or ("account " .. tostring(owner))))
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "config").
----------------------------------------------------------------------

local function testSerialization(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local S = Config.Serialize

    -- Determinism across insertion order (the Class 8 pin).
    local t1 = {}
    t1.beta = { 2, 1 }; t1.alpha = "x"; t1[3] = true; t1[1] = 1.5
    local t2 = {}
    t2[1] = 1.5; t2.alpha = "x"; t2[3] = true; t2.beta = { 2, 1 }
    ck(S(t1) == S(t2), "same content serializes identically regardless of insertion order")

    -- Value changes change the string; shape distinctions hold.
    ck(S({ a = 1 }) ~= S({ a = 2 }), "a changed value changes the emission")
    ck(S({ a = 1 }) ~= S({ b = 1 }), "a changed key changes the emission")
    ck(S(1) ~= S("1"), "number 1 and string '1' are distinct")
    ck(S({ [1] = "x" }) ~= S({ ["1"] = "x" }), "numeric key 1 and string key '1' are distinct")
    ck(S(true) ~= S(1) and S(false) ~= S(nil), "booleans are not numbers, false is not nil")

    -- Length-prefixed strings: no delimiter ambiguity.
    ck(S({ "a;b" }) ~= S({ "a", "b" }), "embedded delimiters cannot collide")
    ck(S("s5:x") ~= S("x"), "a string that LOOKS like the encoding still encodes uniquely")

    -- Floats vs integers.
    ck(S(2) ~= S(2.5), "integer and float emissions differ")
    ck(S(0.9) == S(0.9), "the same float always emits the same bytes")

    -- CopyCfg: unknown keys survive (wire-additive), functions stripped,
    -- copies are independent.
    local src = { known = 1, futureField = "keep me", fn = function() end,
                  nest = { deep = true } }
    local cp = Config.CopyCfg(src)
    ck(cp.futureField == "keep me", "an unknown key rides through the copy (wire-additive)")
    ck(cp.fn == nil, "functions never travel")
    ck(cp.nest.deep == true, "nested tables copy")
    cp.nest.deep = false
    ck(src.nest.deep == true, "the copy is independent of the source")
end

local function testCaptureAndAdopt(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end   -- in-game: capture legs need the sim's store

    -- A known client store to capture.
    _G.FCF_ResetChatWindows()
    local w1 = Config.CaptureWindow(1)
    ck(w1 ~= nil and w1.name == "General", "window 1 captures its stock name")
    ck(w1.shown == true and w1.docked == 1, "shown/docked normalize")
    local sortedOk = true
    for i = 2, #w1.groups do
        if w1.groups[i - 1] > w1.groups[i] then sortedOk = false end
    end
    ck(sortedOk and #w1.groups > 0, "message groups capture SORTED (deterministic emission)")
    ck(#w1.channels == 1 and w1.channels[1] == "General", "channel routing captures by name")
    ck(type(w1.dim) == "table" and type(w1.pos) == "table", "dimensions + position captured")

    -- Store mutation shows up in the next capture.
    _G.SetChatWindowName(3, "Probe")
    _G.AddChatWindowChannel(3, "Zed")
    local w3 = Config.CaptureWindow(3)
    ck(w3.name == "Probe" and w3.channels[1] == "Zed", "store mutations are captured")

    -- Class 6: with the channel list DARK, capture says UNKNOWN (nil), not
    -- empty. (channels.lua's warmth state is authoritative; it is false here
    -- because the module is disabled/dark at this point in the harness run.)
    local snap = Config.CaptureClient()
    ck(type(snap.windows) == "table" and snap.windows[1] ~= nil, "windows always capture")
    ck(snap.join == nil and snap.colors == nil,
        "a dark channel list captures as UNKNOWN (nil), never as empty")

    -- FIRST-RUN ADOPT: no config anywhere -> the client state IS the config.
    local c = Config.Get()
    ck(c ~= nil, "config branch attaches under db")
    c.rev, c.at, c.windows, c.colors, c.join = 0, 0, {}, {}, {}
    ck(Config.HasLocal() == false and Config.HasAnyConfig() == false,
        "rev 0 and no mesh = no config anywhere")
    local t0 = Config.Now()
    ck(Config.AdoptClient() == true, "adopt succeeds")
    ck(Config.Rev() == 1, "adopt is the first edit (rev 1)")
    ck((tonumber(c.at) or 0) >= t0, "adopt stamps server time")
    ck(Config.SerEq(c.windows[1], Config.CaptureWindow(1)),
        "adopted window entries mirror the client store")
    ck(Config.HasAnyConfig() == true, "a config now exists")

    -- Capture-back: a client change diffs in and bumps exactly once.
    _G.SetChatWindowName(3, "Probe Renamed")
    local revBefore = Config.Rev()
    ck(Config.CaptureBack("test") == true, "a real client change captures back")
    ck(Config.Rev() == revBefore + 1, "capture-back bumps rev exactly once")
    ck(c.windows[3].name == "Probe Renamed", "the change landed in the config")
    ck(Config.CaptureBack("test") == false, "no change = no capture, no bump")
    ck(Config.Rev() == revBefore + 1, "an idle capture never bumps")

    -- Color MERGE discipline: a stored color for a channel the character is
    -- not currently in must survive a capture (deletion would need intent).
    c.colors["keepme"] = { r = 0.1, g = 0.2, b = 0.3 }
    local Ch = ns.Channels
    local warmWas = Ch and Ch._listWarm
    if Ch then Ch._listWarm = true end       -- world list is populated here
    _G.SetChatWindowName(3, "Probe Again")   -- force a diff
    ck(Config.CaptureBack("merge-test") == true, "capture with a warm list runs")
    ck(Config.SerEq(c.colors["keepme"], { r = 0.1, g = 0.2, b = 0.3 }),
        "a color for an un-joined channel survives capture (merge, not replace)")
    ck(type(c.join) == "table", "a warm capture writes the join list")
    if Ch then Ch._listWarm = warmWas end
end

local function testLWW(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local P = Config.PickWinner

    local cfgA, cfgB, cfgC = { tag = "A" }, { tag = "B" }, { tag = "C" }
    -- Newest `at` wins.
    local w = P({ { at = 100, rev = 9, owner = "acc1", cfg = cfgA },
                  { at = 200, rev = 1, owner = "acc2", cfg = cfgB } })
    ck(w == cfgB, "newest at wins regardless of rev")
    -- at tie -> higher rev.
    w = P({ { at = 100, rev = 1, owner = "acc1", cfg = cfgA },
            { at = 100, rev = 5, owner = "acc2", cfg = cfgB } })
    ck(w == cfgB, "at tie breaks on higher rev")
    -- at+rev tie -> SMALLEST owner (both stores agree forever).
    w = P({ { at = 100, rev = 2, owner = "acc2", cfg = cfgB },
            { at = 100, rev = 2, owner = "acc1", cfg = cfgA },
            { at = 100, rev = 2, owner = "acc3", cfg = cfgC } })
    ck(w == cfgA, "full tie breaks on smallest owner key (deterministic)")
    -- Malformed candidates contribute nothing; empty answers nil.
    w = P({ { at = 999 }, "junk", { at = 50, rev = 1, owner = "x", cfg = cfgC } })
    ck(w == cfgC, "malformed candidates are healed out")
    ck(P({}) == nil and P(nil) == nil, "no candidates = no winner")

    -- Snapshot: nothing until the first edit; the delegates payload shape after.
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local c = Config.Get()
    c.rev, c.at = 0, 0
    ck(Config.Snapshot() == nil, "a fresh install publishes NOTHING (rev 0)")
    c.rev, c.at = 4, 777000
    c.windows = { [1] = { name = "W", futureField = "ride along" } }
    local snap = Config.Snapshot()
    ck(type(snap) == "table" and snap.v == 1 and snap.at == 777000,
        "snapshot is the { v, at, cfg } wire shape")
    ck(snap.cfg.windows[1].name == "W", "snapshot carries the sections")
    ck(snap.cfg.windows[1].futureField == "ride along",
        "unknown keys ride the wire (additive)")
    snap.cfg.windows[1].name = "mutated"
    ck(c.windows[1].name == "W", "the snapshot is a copy, not a reference")
end

ns:RegisterSelfTest("config", function(verbose)
    local suites = {
        { name = "deterministic serialization", fn = testSerialization },
        { name = "capture + first-run adopt",   fn = testCaptureAndAdopt },
        { name = "LWW + wire payload",          fn = testLWW },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local ok, err = pcall(suite.fn, fails)
        if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
        local passed = #fails == 0
        if not passed then allPass = false end
        if verbose and ns.Print then
            if passed then ns:Print("  PASS config/" .. suite.name)
            else for _, f in ipairs(fails) do ns:Print("  FAIL config/" .. suite.name .. " :: " .. f) end end
        end
    end
    return allPass
end)

return Config
