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
    aliases = {},     -- [channel name, lowercased] = display alias (see below)
    aliasKeepNumber = false,   -- "[2. Trade]" instead of "[Trade]"
    -- LAYOUT that rides the mesh (see below). `locked` joined it 2026-08-11
    -- (the owner's "i need a way to lock / unlock the positioning"): where the
    -- box IS rides the mesh already, so whether it can be MOVED belongs beside
    -- it — lock on one character and every character's box is a rock.
    --
    -- THE OPTIONS REWORK (2026-08-11) added two more, for the same reason and
    -- into the same already-whitelisted section:
    --   combatLogTab   — does our tab strip carry a Combat Log tab (hosting the
    --                    client's own log frame inside the chassis)?
    --   routeAddonLines— do addon-originated lines go to the addon tab?
    -- Both are LAYOUT decisions about the strip, so a player answers them once
    -- and every character gets the answer.
    skin    = { tabPlacement = "top", locked = false,
                combatLogTab = false, routeAddonLines = true },
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
-- SCALE-NORMALIZED POSITIONS (the cross-account fidelity fix).
--
-- THE PROBLEM, stated honestly: the client's saved position is expressed in
-- the account's own UI units. Two accounts on one machine sharing one
-- Config.wtf can still carry DIFFERENT effective scales (uiScale and friends
-- are per-account, server-synced, and invisible on disk), and a raw offset
-- that means "flush against the left edge" on one account means "24 units in"
-- on the other. Worse, a MANUAL DRAG is clamped by the frame's clamp rect,
-- so the edge may be unreachable by dragging on one account and reachable on
-- the other — the owner's long-standing annoyance, pre-dating this addon.
--
-- THE FIX: store the window's bottom-left corner as a FRACTION OF THE SCREEN.
--   capture  : live geometry -> pixels -> fraction   (this file)
--   reconcile: fraction -> the LOCAL account's units -> ClearAllPoints+SetPoint
--              (reconcile.lua; programmatic placement is not drag-clamped)
-- Same config -> same on-screen placement on every account, whatever the
-- hidden CVars say.
--
-- WIRE-COMPAT (additive, with a deprecation window): the legacy `pos` tuple
-- (the client's own saved-position triple) keeps being captured and written
-- exactly as before, so an OLD build reading a NEW config still reads `pos`
-- and behaves as it always did. `npos` rides alongside; new builds prefer it
-- and fall back to `pos` when it is absent. Nothing about LWW changes — `at`
-- and `rev` still stamp the whole config, and a mixed-build mesh converges on
-- the same winner it would have before.
--
-- UNKNOWN IS NOT ZERO (Class 4/6, made mechanical): before the client has laid
-- a frame out, GetLeft/GetBottom answer nil. A nil read captures as NO npos —
-- never as 0,0 — and every comparator treats a missing npos as "no opinion",
-- so a dark read can neither wipe a stored position nor spin the retry ladder.
----------------------------------------------------------------------

-- Compared as a fraction of the screen: 0.002 is 0.2% of the screen edge
-- (~4 px across 1920). Below that, two positions ARE the same position, and
-- treating float round-trip noise as drift would fight the player forever.
Config.NPOS_EPSILON = 0.002

local function widgetNum(w, method)
    if type(w) ~= "table" then return nil end
    local f = w[method]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, w)
    if ok and type(v) == "number" then return v end
    return nil
end

-- UIParent's live geometry: width, height (its OWN units) and its effective
-- scale. nil when the client has not laid the world out (never a zero).
function Config.ScreenGeometry()
    local P = _G.UIParent
    local w = widgetNum(P, "GetWidth")
    local h = widgetNum(P, "GetHeight")
    local s = widgetNum(P, "GetEffectiveScale") or 1
    if not w or not h or w <= 0 or h <= 0 or s <= 0 then return nil end
    return w, h, s
end

-- PURE. Screen-space pixels -> fraction of the screen. Rounded to 6 places so
-- the emission stays byte-stable across captures (Class 8 lives downstream of
-- this: a jittering last digit would change every serialization).
function Config.Normalize(px, py, screenW, screenH)
    if type(px) ~= "number" or type(py) ~= "number" then return nil end
    if type(screenW) ~= "number" or type(screenH) ~= "number"
       or screenW <= 0 or screenH <= 0 then return nil end
    local function round6(v) return math.floor(v * 1e6 + 0.5) / 1e6 end
    return round6(px / screenW), round6(py / screenH)
end

-- PURE. Fraction of the screen -> SetPoint offsets. Offsets are read in the
-- ANCHORED frame's own coordinate space, so the UIParent-units answer is
-- converted through the scale RATIO (Class 3: convert into the compared
-- frame's space, never assume the chains match).
function Config.Denormalize(fx, fy, uiW, uiH, uiScale, frameScale)
    if type(fx) ~= "number" or type(fy) ~= "number" then return nil end
    if type(uiW) ~= "number" or type(uiH) ~= "number" then return nil end
    frameScale = tonumber(frameScale)
    uiScale    = tonumber(uiScale)
    if not frameScale or frameScale <= 0 or not uiScale or uiScale <= 0 then return nil end
    local ratio = uiScale / frameScale
    return fx * uiW * ratio, fy * uiH * ratio
end

-- One window's normalized position, read from LIVE geometry (the store's own
-- tuple is in units we do not control and cannot compare across accounts).
-- Returns { "BOTTOMLEFT", fx, fy } or nil for UNKNOWN.
function Config.CaptureNormalizedPos(id)
    local frame = _G["ChatFrame" .. tostring(id)]
    if type(frame) ~= "table" then return nil end
    local uiW, uiH, uiScale = Config.ScreenGeometry()
    if not uiW then return nil end
    local left   = widgetNum(frame, "GetLeft")
    local bottom = widgetNum(frame, "GetBottom")
    local fs     = widgetNum(frame, "GetEffectiveScale") or uiScale
    if left == nil or bottom == nil or fs <= 0 then return nil end
    local fx, fy = Config.Normalize(left * fs, bottom * fs, uiW * uiScale, uiH * uiScale)
    if fx == nil then return nil end
    return { "BOTTOMLEFT", fx, fy }
end

-- ── THE SAME DISCIPLINE, APPLIED TO SIZE (`ndim`, 2026-08-11) ────────────────
--
-- The owner asked for a resizable chat box, and a size stored in raw UI units
-- has EXACTLY the cross-account problem the position had: two accounts sharing
-- one Config.wtf can carry different effective scales, so "430 units wide"
-- covers different amounts of screen on each. `ndim` is the window's size as a
-- FRACTION OF THE PIXEL SCREEN — the same measurement `npos` makes of the
-- corner, made of the extent — and it rides in exactly the same places:
--   * captured here, alongside npos, from LIVE geometry;
--   * carried inside `windows`, which Candidates / Snapshot / AdoptEffective
--     already name — so it syncs for the same reason `tabColor` does, and the
--     aliases lesson ("a section not named in all three is silently
--     account-local forever") is satisfied without a new section;
--   * preserved through a capture-back that could not read it (mergeWindows);
--   * compared with TOLERANCE rather than exactly (a measurement, not a token);
--   * replayed by the reconciler at login (Reconcile.ApplySizes).
-- No anchor token: an extent has no anchor. `{ fw, fh }`, and nothing else.
--
-- UNKNOWN IS NOT ZERO, again: a frame the client has not laid out answers nil
-- for its width, and a nil read captures as NO ndim — never as a zero-sized
-- window, which is the one value that would make a box the player cannot find.
function Config.CaptureNormalizedDim(id)
    local frame = _G["ChatFrame" .. tostring(id)]
    if type(frame) ~= "table" then return nil end
    local uiW, uiH, uiScale = Config.ScreenGeometry()
    if not uiW then return nil end
    local w  = widgetNum(frame, "GetWidth")
    local h  = widgetNum(frame, "GetHeight")
    local fs = widgetNum(frame, "GetEffectiveScale") or uiScale
    if w == nil or h == nil or w <= 0 or h <= 0 or fs <= 0 then return nil end
    local fw, fh = Config.Normalize(w * fs, h * fs, uiW * uiScale, uiH * uiScale)
    if fw == nil or fw <= 0 or fh <= 0 then return nil end
    return { fw, fh }
end

-- Do two normalized sizes mean the same extent? nil on EITHER side is UNKNOWN
-- and therefore agreement — the npos rule, verbatim, for the same reason.
function Config.NearDim(a, b)
    if a == nil or b == nil then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local function near(x, y)
        return math.abs((tonumber(x) or 0) - (tonumber(y) or 0)) <= Config.NPOS_EPSILON
    end
    return near(a[1], b[1]) and near(a[2], b[2])
end

-- Do two normalized positions mean the same placement? A nil on EITHER side is
-- UNKNOWN and therefore agreement — the same discipline the dark channel list
-- gets. Anchors must match exactly; the fractions compare with tolerance.
function Config.NearPos(a, b)
    if a == nil or b == nil then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if tostring(a[1]) ~= tostring(b[1]) then return false end
    local function near(x, y)
        return math.abs((tonumber(x) or 0) - (tonumber(y) or 0)) <= Config.NPOS_EPSILON
    end
    return near(a[2], b[2]) and near(a[3], b[3])
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
    -- The scale-normalized corner rides ALONGSIDE the legacy tuple (additive,
    -- deprecation window). Absent when the geometry is not resolvable yet.
    w.npos = Config.CaptureNormalizedPos(id)
    -- …and so does the scale-normalized SIZE, for the same reasons and with the
    -- same absent-when-unreadable rule.
    w.ndim = Config.CaptureNormalizedDim(id)
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

-- Windows land wholesale from a capture — EXCEPT that a window whose npos the
-- capture could not read (dark geometry) keeps the one the config already
-- holds. An unreadable corner is an unknown, and an unknown must never delete
-- a position the player (or a peer account) set (Class 4).
-- Per-window fields the CONFIG owns OUTRIGHT: no client capture ever speaks
-- about them, so a wholesale capture-back must carry them across rather than
-- delete them. This is `npos`'s Class 4 rule generalized — an unknown must
-- never become a deletion — and it is what keeps a per-tab colour alive
-- through the very next window drag.
-- `addonSink` joined 2026-08-11 (the options rework's addon tab): which window
-- is the addon tab is a CONFIG fact no client capture can see, so it rides the
-- same carry-across rule tabColor does or the very next window drag deletes it.
local WINDOW_CONFIG_ONLY_FIELDS = { "tabColor", "addonSink" }
Config.WINDOW_CONFIG_ONLY_FIELDS = WINDOW_CONFIG_ONLY_FIELDS

local function mergeWindows(prev, snapWindows)
    local out = copyCfg(snapWindows or {})
    if type(prev) ~= "table" then return out end
    for id, w in pairs(out) do
        if type(w) == "table" then
            local old = prev[id]
            if w.npos == nil and type(old) == "table" and type(old.npos) == "table" then
                w.npos = copyCfg(old.npos)
            end
            -- ndim rides the identical rule: an unreadable SIZE is an unknown,
            -- and an unknown must never delete the one the player (or a peer
            -- account) set.
            if w.ndim == nil and type(old) == "table" and type(old.ndim) == "table" then
                w.ndim = copyCfg(old.ndim)
            end
            if type(old) == "table" then
                for _, f in ipairs(WINDOW_CONFIG_ONLY_FIELDS) do
                    if w[f] == nil and old[f] ~= nil then
                        w[f] = (type(old[f]) == "table") and copyCfg(old[f]) or old[f]
                    end
                end
            end
        end
    end
    -- A window the config speaks about that the capture does not mention at all
    -- (a config-only entry, e.g. a colour set for a window this character has
    -- never opened) is KEPT whole for the same reason.
    for id, old in pairs(prev) do
        if out[id] == nil and type(old) == "table" then out[id] = copyCfg(old) end
    end
    return out
end
Config.MergeWindows = mergeWindows

-- FIRST-RUN ADOPT (reconciler rule 5's second half): the current client state
-- BECOMES the initial config. Never a default layout, never a wizard.
function Config.AdoptClient(snap)
    local c = Config.Get()
    if not c then return false end
    snap = snap or Config.CaptureClient()
    c.windows = mergeWindows(c.windows, snap.windows)
    if snap.join then c.join = copyCfg(snap.join) end
    if snap.colors then
        for k, v in pairs(snap.colors) do c.colors[k] = copyCfg(v) end
    end
    Config.Bump()
    return true
end

-- The window fields a capture speaks about, compared EXACTLY (deterministic
-- serialization). `npos` and `ndim` are deliberately not here: they are
-- measurements, so they compare with tolerance through NearPos / NearDim —
-- see WindowDiffers.
local WINDOW_EXACT_FIELDS = {
    "name", "fontSize", "r", "g", "b", "alpha", "shown", "locked", "docked",
    "uninteractable", "dim", "pos", "groups", "channels",
}

-- ONE rule for "did this window change", used by both the capture-back gate
-- and the reconciler's verify, so the two can never disagree about drift.
-- A capture with no entry at all says NOTHING (it is not a deletion).
function Config.WindowDiffers(snapW, cfgW)
    if type(snapW) ~= "table" then return false end
    if type(cfgW) ~= "table" then return true end
    for _, f in ipairs(WINDOW_EXACT_FIELDS) do
        if not serEq(snapW[f], cfgW[f]) then return true end
    end
    if not Config.NearPos(snapW.npos, cfgW.npos) then return true end
    return not Config.NearDim(snapW.ndim, cfgW.ndim)
end

-- Would a capture change the stored config? (The capture-back gate.)
function Config.SectionsDiffer(snap)
    local c = Config.Get()
    if not c or type(snap) ~= "table" then return false end
    local sw, cw = snap.windows or {}, c.windows or {}
    for id = 1, numWindows() do
        if Config.WindowDiffers(sw[id], cw[id]) then return true end
    end
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
    c.windows = mergeWindows(c.windows, snap.windows)
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
            -- ALIASES RIDE THE SAME CANDIDATE as every other section. They are
            -- named EXPLICITLY here (and in Snapshot / AdoptEffective) rather
            -- than riding "for free": this assembly is a whitelist, not a copy
            -- of the store, so a new section that is not listed is silently
            -- account-local forever. The suite pins all three sites.
            cfg   = { windows = c.windows, colors = c.colors, join = c.join,
                      aliases = c.aliases, aliasKeepNumber = c.aliasKeepNumber,
                      -- skin v3: the tab strip's PLACEMENT rides here too.
                      skin = c.skin },
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
    c.aliases = copyCfg(cfg.aliases or {})
    c.aliasKeepNumber = cfg.aliasKeepNumber and true or false
    c.skin    = copyCfg(cfg.skin or {})
    return true
end

----------------------------------------------------------------------
-- CHANNEL ALIASES — the ONE seam every surface renders a channel through.
--
-- THE PROBLEM (the owner's ask, Prat's "custom channel names"): the client
-- writes a channel's header as "[2. Trade - City]" and that string is DISPLAY
-- TEXT inside the |Hchannel:...|h[...]|h hyperlink. Renaming it is a display
-- concern and must never touch the payload — which is exactly what decor.lua's
-- LINK DECORATOR class guarantees by construction (a decorator is handed the
-- display text only and the engine rebuilds the link itself).
--
-- KEYED BY NAME, case-folded, NEVER by number: channel numbers are a per-
-- character, per-session accident (channels.lua exists because of it), so an
-- alias keyed by number would follow the wrong channel the first time the
-- list renumbers — the same lesson the color-by-name rule above is built on.
--
-- ACCOUNT-WIDE and mesh-synced: aliases live in the config alongside colors,
-- resolve through EffectiveCfg (so a peer account's winning copy shows here
-- without a local write), and edits go through the adopt-effective-then-bump
-- path every other edit uses.
--
-- Three surfaces render an aliased channel — the chat line (decor link
-- decorator), the edit box's sticky prefix and the channel-colored tab label —
-- and all three call AliasLabel below. That single-seam property is pinned by
-- the suite: there is no second place that knows how an alias is spelled.
----------------------------------------------------------------------

-- The storage key for a channel name: trimmed, lower-cased. nil for anything
-- that is not a usable name (Class 5: an empty string is not a channel).
local function aliasKey(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name:lower()
end
Config.AliasKey = aliasKey

-- An alias as it is STORED: trimmed; empty means "no alias" (the remove verb).
local function aliasValue(alias)
    if type(alias) ~= "string" then return nil end
    alias = alias:gsub("^%s+", ""):gsub("%s+$", "")
    if alias == "" then return nil end
    return alias
end
Config.AliasValue = aliasValue

-- The EFFECTIVE alias table (cross-account winner first, local store second) —
-- the same read discipline channel colors use.
function Config.Aliases()
    local eff = Config.EffectiveCfg()
    if type(eff) == "table" and type(eff.aliases) == "table" then return eff.aliases end
    local c = Config.Get()
    if c and type(c.aliases) == "table" then return c.aliases end
    return {}
end

function Config.GetAlias(name)
    local key = aliasKey(name)
    if not key then return nil end
    return aliasValue(Config.Aliases()[key])
end

-- Set (or, with an empty/nil alias, REMOVE) one channel's alias. An unchanged
-- write is a no-op and never bumps rev (no sync storm from re-typing the same
-- text). Returns true when the config actually moved.
function Config.SetAlias(name, alias)
    local key = aliasKey(name)
    if not key then return false end
    local want = aliasValue(alias)
    if Config.GetAlias(key) == want then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.aliases) ~= "table" then c.aliases = {} end
    c.aliases[key] = want
    Config.Bump()
    return true
end

function Config.AliasKeepNumber()
    local eff = Config.EffectiveCfg()
    if type(eff) == "table" and eff.aliasKeepNumber ~= nil then
        return eff.aliasKeepNumber == true
    end
    local c = Config.Get()
    return (c and c.aliasKeepNumber == true) or false
end

function Config.SetAliasKeepNumber(on)
    on = on and true or false
    if Config.AliasKeepNumber() == on then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    c.aliasKeepNumber = on
    Config.Bump()
    return true
end

-- Every alias the config holds, sorted by key (Class 8: a listing anything
-- iterates must be deterministic). Entries: { key = , alias = }.
function Config.AliasList()
    local keys = {}
    for k, v in pairs(Config.Aliases()) do
        if type(k) == "string" and aliasValue(v) then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local out = {}
    local t = Config.Aliases()
    for _, k in ipairs(keys) do
        out[#out + 1] = { key = k, alias = aliasValue(t[k]) }
    end
    return out
end

-- ── THE CLIENT'S LONG FORM (owner defect, 2026-08-12) ───────────────────────
-- `GetChannelName` answers a ZONE channel's name with its zone glued on —
-- "General - Stormwind City", "Trade - City" — and that is the string every
-- surface that asks the client gets back. The owner's entry indicator read
-- "5. General - Stormwind City:" because the chip mirrored that string instead
-- of resolving the channel's IDENTITY and rendering our own word for it.
--
-- PURE, and the ONE place that knows the client's long form. Everything before
-- the first " - " is the channel; the rest is the zone the character happens to
-- be standing in, which is not part of what the channel is called. A name with
-- no " - " is already short and comes back unchanged.
function Config.ChannelShortName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    local short = name:match("^(.-)%s+%-%s+%S.*$")
    if short and short ~= "" then return short end
    return name
end

-- WHAT A CHANNEL IS CALLED ON OUR SURFACES — alias first, the client's SHORT
-- name otherwise, and never the zone-suffixed long form. This is AliasLabel
-- with a floor under it, so a surface that must always have a word to draw
-- (the entry chip) asks THIS and a surface that renders the client's own shape
-- when there is no alias (the chat line, the tab) keeps asking AliasLabel.
--
-- The alias is looked up under the client's full name FIRST and the short name
-- SECOND: the chat line's own display text carries the short form ("[5.
-- General]") while the settings row carries whatever the client listed, so an
-- alias written from either surface lights the other one up.
function Config.ChannelLabel(number, name)
    local label = Config.AliasLabel(number, name)
    if label then return label end
    local short = Config.ChannelShortName(name)
    if not short then return nil end
    if short ~= name then
        label = Config.AliasLabel(number, short)
        if label then return label end
    end
    if Config.AliasKeepNumber() then
        local n = tonumber(number)
        if n then return n .. ". " .. short end
    end
    return short
end

-- PURE. Split a channel link's DISPLAY text into its number and its name:
--   "[2. Trade - City]" -> "2", "Trade - City"
--   "[Guild]"           -> nil, "Guild"
-- Anything that is not the bracketed shape answers nothing (never a guess).
function Config.ParseChannelDisplay(display)
    if type(display) ~= "string" then return nil, nil end
    local inner = display:match("^%[(.*)%]$")
    if not inner or inner == "" then return nil, nil end
    local num, name = inner:match("^(%d+)%.%s*(.+)$")
    if num then return num, name end
    return nil, inner
end

-- THE SEAM. Given a channel number (may be nil/unknown) and its NAME, answer
-- the display core every surface renders — "Trade", or "2. Trade" when the
-- keep-number option is on — or nil when this channel has no alias, which is
-- every surface's instruction to render the client's own text untouched.
function Config.AliasLabel(number, name)
    local alias = Config.GetAlias(name)
    if not alias then return nil end
    local n = number ~= nil and tostring(number) or ""
    if n ~= "" and Config.AliasKeepNumber() then
        return n .. ". " .. alias
    end
    return alias
end

----------------------------------------------------------------------
-- SKIN LAYOUT (skin v3) — the tab strip's PLACEMENT and each window's
-- explicit tab COLOUR.
--
-- WHY THEY LIVE HERE and not in the account-local db.skin branch: both are
-- LAYOUT. "Where are my tabs" and "what colour is my Guild tab" are answers a
-- player gives once, and a layout the mesh does not carry has to be re-chosen
-- on every account — the exact thing this config exists to prevent. They ride
-- the same LWW candidate as windows/colors/join/aliases and resolve through
-- EffectiveCfg, so a peer account's newer choice shows here with no local
-- write (receive never adopts).
--
-- THE WHITELIST, learned the hard way with aliases: Candidates, Snapshot and
-- AdoptEffective each NAME the sections they carry. A section that is not
-- named in all three is silently account-local forever. `skin` is named in
-- all three above and `tabColor` rides inside `windows`, which already is —
-- and mergeWindows keeps it alive through a capture-back (see
-- WINDOW_CONFIG_ONLY_FIELDS). The suite pins every one of those sites.
--
-- OLD-READER TOLERANCE: a peer on a pre-v3 build reads the payload through
-- the same copyCfg that keeps unknown keys, so `skin` simply rides along in
-- its store untouched and un-rendered. Nothing about the wire changed shape.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- ============ THE CONFIG SURFACE AUDIT (2026-08-11) ============
--
-- WHY IT EXISTS (owner, 2026-08-11: "seems theres a lot of misses here the
-- config and build is messy. please review it and clean it up"). Every field
-- this addon stores is checked on FOUR legs, and a field that fails all four is
-- dead config and gets deleted rather than documented:
--   READ    — some shipping module reads it;
--   LIVE    — a write reaches PIXELS without a /reload, through a named
--             apply seam (options.lua's Options.APPLY_SEAMS; the binding
--             names which one, and the bind-check refuses a binding that
--             names none);
--   SYNC    — it rides the mesh (named in Candidates + Snapshot +
--             AdoptEffective — the aliases lesson) or is deliberately
--             account-local WITH the reason recorded;
--   CONTROL — it is bound in Options.BINDINGS, or listed in Options.UNBOUND
--             with its reason. Options.CheckCoverage() is the gate: a stored
--             field that is neither fails the suite.
--
-- ── db.view.* (ACCOUNT-LOCAL: the LOOK is per-monitor taste — view.lua's
--    config note is the recorded reason) ────────────────────────────────────
--   fontSize     READ view.MessageFontSize | LIVE view.look   | CONTROL slider
--   lineHeight   READ view.MessageSpacing  | LIVE view.look   | CONTROL slider
--   tabTextSize  READ view.TabTextSize     | LIVE view.layout | CONTROL slider
--   copyButton   READ view.EnsureCopyButton| LIVE view.furniture | CONTROL box
--
-- ── db.skin.* (ACCOUNT-LOCAL: skin-over's own look + the gesture gates) ────
--   unifiedChassis, channelTabs, stampDivider, editBoxChannelColor, iconRail,
--   hideButtonColumn, copyButton, fading, fadeTime
--        READ skin.lua | LIVE skin.restyle / skin.tabs / skin.dividers
--        | CONTROL Appearance. NOTE: with the DRAWN window on, the skin-over
--        renderer is retired (Skin.ViewOwnsPixels), so several of these speak
--        only to the box-off path. The pane says so in a status line rather
--        than offering a control that silently does nothing.
--   persistentEditBox, editBox   READ skin + view.LayoutEditBox
--        | LIVE skin.editbox | CONTROL Windows
--   altDragMove, snapToEdges     READ at gesture time (Skin.MoveAllowed /
--        Skin.SnapEnabled) | LIVE next-gesture (no standing surface — the
--        reason is recorded on the binding) | CONTROL Windows
--   unclampWindows               READ skin.LoosenClamp | LIVE skin.restyle
--        | CONTROL Windows
--   messageFontSize, lineHeight  READ skin-over typography (box-off only)
--        | CONTROL Options.UNBOUND, with the reason
--
-- ── config.skin.* (SYNCED — named in all three whitelist sites) ────────────
--   tabPlacement  READ view/skin/badges | LIVE view.layout | CONTROL Tabs
--   locked        READ view.DragAllowed + view resize + Skin.MoveAllowed
--                 | LIVE lock.apply | CONTROL General + /dchat lock|unlock
--   combatLogTab  READ view.CombatLogTab (OwnedIds + the hosting)
--                 | LIVE view.tabset | CONTROL Tabs (options rework)
--   routeAddonLines READ view.ClassifierArmed | LIVE view.tabset
--                 | CONTROL Tabs (options rework). OFF = the classifier decides
--                 nothing at all and every line takes its old path.
--
-- ── config.windows[id].* (SYNCED inside `windows`) ─────────────────────────
--   name, fontSize, r, g, b, alpha, shown, docked, uninteractable, groups,
--   channels      READ+APPLIED by reconcile.lua at login and on demand
--                 | CONTROL the reconciler owns them (Options.UNBOUND does not
--                 list them: they are not settings, they are the projection)
--   locked        THE CLIENT's own per-window flag captured from
--                 GetChatWindowInfo — NOT this addon's lock. Named here so the
--                 two can never be confused: ours is config.skin.locked.
--   pos, dim      the client's raw pair, kept for diffing
--   npos, ndim    the NORMALIZED pair the reconciler actually replays
--                 | LIVE written by every move/resize commit
--   tabColor      READ view.TabInk | LIVE view.tabs | CONTROL the tab's page
--   addonSink     READ view.RefreshRouting (which tab is the addon tab)
--                 | LIVE view.tabset | CONTROL Tabs (options rework). A
--                 CONFIG-ONLY field: no client capture speaks about it, so it
--                 rides WINDOW_CONFIG_ONLY_FIELDS beside tabColor.
--
-- ── config.join / config.colors (SYNCED; the options rework's channel rows) ─
--   join          the ORDER: { number, name } intent, drag-to-reorder in
--                 General | LIVE channels.order | CONTROL the channel rows
--   colors        per-channel colour BY NAME | LIVE channels.colors
--                 | CONTROL the channel rows' swatch
----------------------------------------------------------------------

Config.TAB_PLACEMENTS = { "top", "left", "right" }

function Config.IsTabPlacement(v)
    for _, p in ipairs(Config.TAB_PLACEMENTS) do
        if v == p then return true end
    end
    return false
end

-- The EFFECTIVE placement (cross-account winner first, local store second,
-- "top" — the client's own arrangement — as the answer when nobody has said).
function Config.TabPlacement()
    local eff = Config.EffectiveCfg()
    local s = (type(eff) == "table" and type(eff.skin) == "table") and eff.skin or nil
    if s and Config.IsTabPlacement(s.tabPlacement) then return s.tabPlacement end
    local c = Config.Get()
    s = (c and type(c.skin) == "table") and c.skin or nil
    if s and Config.IsTabPlacement(s.tabPlacement) then return s.tabPlacement end
    return "top"
end

function Config.SetTabPlacement(where)
    if not Config.IsTabPlacement(where) then return false end
    if Config.TabPlacement() == where then return false end     -- no sync storm
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.skin) ~= "table" then c.skin = {} end
    c.skin.tabPlacement = where
    Config.Bump()
    return true
end

----------------------------------------------------------------------
-- THE LOCK (owner, 2026-08-11: "i need a way to lock / unlock the positioning
-- and also when unlocked i should be able to click and drag a corner to
-- re-size it").
--
-- It lives in the SYNCED skin section beside tabPlacement, for the reason the
-- whitelist note above gives: a lock that were account-local would have to be
-- re-set on every character, and the box's POSITION already rides the mesh —
-- an addon that syncs where the box is and not whether it can be moved is
-- telling half a story.
--
-- DEFAULT: UNLOCKED. The box has been unconditionally movable since it was
-- drawn, and a build that silently locked it would take a capability away from
-- a session that never asked. The affordance (four visible corner grips) is
-- what changes, not the posture.
----------------------------------------------------------------------

-- The EFFECTIVE lock: the cross-account winner first, the local store second,
-- UNLOCKED when nobody has said (never a hopeful `true` — a lock nobody chose
-- reads to the player as a broken window).
function Config.Locked()
    local eff = Config.EffectiveCfg()
    local s = (type(eff) == "table" and type(eff.skin) == "table") and eff.skin or nil
    if s and type(s.locked) == "boolean" then return s.locked end
    local c = Config.Get()
    s = (c and type(c.skin) == "table") and c.skin or nil
    if s and type(s.locked) == "boolean" then return s.locked end
    return false
end

function Config.SetLocked(on)
    on = on and true or false
    if Config.Locked() == on then return false end             -- no sync storm
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.skin) ~= "table" then c.skin = {} end
    c.skin.locked = on
    Config.Bump()
    return true
end

-- One window's EXPLICIT tab colour, as the SPEC STRING the renderer resolves
-- ("token:accent", "chat:GUILD" — skin.lua owns that vocabulary; this file
-- only stores and syncs it). nil means "no explicit choice", which is the
-- renderer's instruction to derive the colour as it always has.
function Config.TabColor(id)
    id = tonumber(id)
    if not id then return nil end
    local function pick(cfg)
        local w = (type(cfg) == "table" and type(cfg.windows) == "table") and cfg.windows[id] or nil
        if type(w) ~= "table" then return nil, false end
        local v = w.tabColor
        if type(v) == "string" and v ~= "" then return v, true end
        return nil, true                    -- this copy SPEAKS about the window
    end
    local v, spoke = pick(Config.EffectiveCfg())
    if v then return v end
    if spoke then return nil end            -- the winner says "no colour here"
    v = pick(Config.Get())
    return v
end

-- Set (or, with nil/"", REMOVE) one window's explicit tab colour.
function Config.SetTabColor(id, spec)
    id = tonumber(id)
    if not id then return false end
    if spec ~= nil and type(spec) ~= "string" then return false end
    if spec == "" then spec = nil end
    if Config.TabColor(id) == spec then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.windows) ~= "table" then c.windows = {} end
    if type(c.windows[id]) ~= "table" then c.windows[id] = {} end
    c.windows[id].tabColor = spec
    Config.Bump()
    return true
end

----------------------------------------------------------------------
-- ====== THE OPTIONS REWORK's SEAMS (2026-08-11, owner-specified) ======
--
-- The rework's General/Tabs sections write CONFIG, never the client: the pane
-- names an intent, the reconciler (windows) or channels.lua (numbering) makes
-- the client agree, and the mesh carries the answer to every character. Every
-- setter below therefore follows the ONE shape this file has used since the
-- alias editor landed:
--
--   read EFFECTIVE first (a peer account's newer copy is the truth) -> refuse
--   an unchanged write (no sync storm) -> AdoptEffective (publish on top of
--   the winner, never "stale world + my change") -> write -> Bump.
--
-- WHITELIST STATUS OF EVERYTHING TOUCHED HERE, said out loud because the
-- aliases lesson cost a build: channel ORDER rides `join`, channel COLOURS
-- ride `colors`, per-tab NAME/ROUTING/addonSink ride `windows`, and the combat
-- log + addon-routing toggles ride `skin`. All four sections are named in
-- Candidates, Snapshot AND AdoptEffective already — the suite asserts each of
-- the three sites for each of the four.
----------------------------------------------------------------------

-- ── CHANNEL ORDER (the drag-and-drop reorder's write path) ────────────────
--
-- The config's `join` list IS the order: it is the { number, name } intent
-- channels.lua's deterministic numbering engineers the client toward. A drag
-- therefore RENUMBERS; it never joins or leaves. That distinction is the whole
-- safety property of this control — a reorder that could add a channel would
-- be a reorder that can spam the server with joins.

-- The effective join list (winner first), normalized to a sorted array.
function Config.JoinList()
    local eff = Config.EffectiveCfg()
    local j = (type(eff) == "table" and type(eff.join) == "table") and eff.join or nil
    if not j then
        local c = Config.Get()
        j = (c and type(c.join) == "table") and c.join or {}
    end
    local out = {}
    for _, e in ipairs(j) do
        if type(e) == "table" and tonumber(e[1]) and type(e[2]) == "string" and e[2] ~= "" then
            out[#out + 1] = { tonumber(e[1]), e[2] }
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

-- The channel NAMES in configured order (what a reorder list renders).
function Config.ChannelOrder()
    local out = {}
    for _, e in ipairs(Config.JoinList()) do out[#out + 1] = e[2] end
    return out
end

-- PURE. Given the current ordered names and a desired order, answer the join
-- list the config should hold: MEMBERSHIP IS PRESERVED EXACTLY (a name not
-- currently in the join list is ignored; a name in it that the desired order
-- forgot keeps its relative place at the end), numbers become 1..N.
function Config.ReorderJoin(current, desired)
    local have, seen = {}, {}
    for _, name in ipairs(current or {}) do
        if type(name) == "string" and name ~= "" then have[name:lower()] = name end
    end
    local out = {}
    for _, name in ipairs(desired or {}) do
        local key = type(name) == "string" and name:lower() or nil
        if key and have[key] and not seen[key] then
            seen[key] = true
            out[#out + 1] = { #out + 1, have[key] }
        end
    end
    for _, name in ipairs(current or {}) do
        local key = name:lower()
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = { #out + 1, name }
        end
    end
    return out
end

function Config.SetChannelOrder(names)
    if type(names) ~= "table" then return false end
    local want = Config.ReorderJoin(Config.ChannelOrder(), names)
    if serEq(want, Config.JoinList()) then return false end     -- no sync storm
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    c.join = copyCfg(want)
    Config.Bump()
    return true
end

-- Move one channel to a 1-based slot in the order (what a dropped row asks
-- for). Refuses a name the join list does not carry.
function Config.MoveChannel(name, toIndex)
    if type(name) ~= "string" then return false end
    local order = Config.ChannelOrder()
    local from
    for i, n in ipairs(order) do if n:lower() == name:lower() then from = i end end
    if not from then return false end
    toIndex = math.max(1, math.min(#order, math.floor(tonumber(toIndex) or from)))
    if toIndex == from then return false end
    local moved = table.remove(order, from)
    table.insert(order, toIndex, moved)
    return Config.SetChannelOrder(order)
end

-- ── CHANNEL COLOURS (the per-row swatch) ──────────────────────────────────
-- Stored BY NAME (the client keys them by number and numbers move); imposed
-- onto the client by channels.lua's ImposeColor on every join/renumber.

function Config.ChannelColors()
    local eff = Config.EffectiveCfg()
    if type(eff) == "table" and type(eff.colors) == "table" then return eff.colors end
    local c = Config.Get()
    return (c and type(c.colors) == "table") and c.colors or {}
end

function Config.ChannelColor(name)
    local key = aliasKey(name)
    if not key then return nil end
    local v = Config.ChannelColors()[key]
    if type(v) ~= "table" then return nil end
    return { r = tonumber(v.r) or 1, g = tonumber(v.g) or 1, b = tonumber(v.b) or 1 }
end

-- nil r REMOVES the colour (the channel goes back to the client's own).
function Config.SetChannelColor(name, r, g, b)
    local key = aliasKey(name)
    if not key then return false end
    local want
    if r ~= nil then
        local function ch(v) v = tonumber(v) or 0 if v < 0 then v = 0 elseif v > 1 then v = 1 end return v end
        want = { r = ch(r), g = ch(g), b = ch(b) }
    end
    local have = Config.ChannelColor(key)
    if want == nil and have == nil then return false end
    if want and have and Config.NearColor(want, have) then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.colors) ~= "table" then c.colors = {} end
    c.colors[key] = want
    Config.Bump()
    return true
end

-- ── PER-WINDOW (per-TAB) FACTS: name, message groups, channel routing ─────

-- The EFFECTIVE entry for one window. Read-only.
--
-- ONE CONFIG ANSWERS, NEVER TWO BLENDED. If a winner exists, its `windows`
-- table speaks for the WHOLE tab set — a per-id fallback to the local store
-- would answer with a tab the winner deleted (and, found by the suite, would
-- report OUR addon sink while a peer's copy is the one in force). The local
-- store answers only when there is no candidate at all: rev 0, first run.
function Config.WindowEntry(id)
    id = tonumber(id)
    if not id then return nil end
    local eff = Config.EffectiveCfg()
    if type(eff) == "table" then
        local w = (type(eff.windows) == "table") and eff.windows[id] or nil
        return type(w) == "table" and w or nil
    end
    local c = Config.Get()
    local w = (c and type(c.windows) == "table") and c.windows[id] or nil
    return type(w) == "table" and w or nil
end

-- Every window id the CONFIG declares live (shown or docked), ascending. The
-- tab set the pane offers a page for.
function Config.WindowIds()
    local out = {}
    for id = 1, numWindows() do
        local w = Config.WindowEntry(id)
        if type(w) == "table" and (w.shown == true or (w.docked and w.docked ~= false)) then
            out[#out + 1] = id
        end
    end
    return out
end

local function editWindow(id, mutate)
    id = tonumber(id)
    if not id then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.windows) ~= "table" then c.windows = {} end
    if type(c.windows[id]) ~= "table" then c.windows[id] = copyCfg(Config.WindowEntry(id) or {}) end
    mutate(c.windows[id])
    Config.Bump()
    return true
end
Config.EditWindow = editWindow

function Config.WindowName(id)
    local w = Config.WindowEntry(id)
    return (type(w) == "table" and type(w.name) == "string") and w.name or ""
end

function Config.SetWindowName(id, name)
    if type(name) ~= "string" then return false end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end                 -- a nameless tab is not a rename
    if Config.WindowName(id) == name then return false end
    return editWindow(id, function(w) w.name = name end)
end

-- The message groups this window carries, sorted (the capture's own shape).
function Config.WindowGroups(id)
    local w = Config.WindowEntry(id)
    local out = {}
    if type(w) == "table" and type(w.groups) == "table" then
        for _, g in ipairs(w.groups) do if type(g) == "string" then out[#out + 1] = g end end
    end
    table.sort(out)
    return out
end

function Config.WindowHasGroup(id, group)
    if type(group) ~= "string" then return false end
    for _, g in ipairs(Config.WindowGroups(id)) do if g == group then return true end end
    return false
end

function Config.SetWindowGroup(id, group, on)
    if type(group) ~= "string" or group == "" then return false end
    on = on and true or false
    if Config.WindowHasGroup(id, group) == on then return false end
    local want = {}
    for _, g in ipairs(Config.WindowGroups(id)) do
        if g ~= group then want[#want + 1] = g end
    end
    if on then want[#want + 1] = group end
    table.sort(want)
    return editWindow(id, function(w) w.groups = want end)
end

function Config.WindowChannels(id)
    local w = Config.WindowEntry(id)
    local out = {}
    if type(w) == "table" and type(w.channels) == "table" then
        for _, n in ipairs(w.channels) do if type(n) == "string" then out[#out + 1] = n end end
    end
    table.sort(out)
    return out
end

function Config.WindowHasChannel(id, name)
    if type(name) ~= "string" then return false end
    for _, n in ipairs(Config.WindowChannels(id)) do
        if n:lower() == name:lower() then return true end
    end
    return false
end

function Config.SetWindowChannel(id, name, on)
    if type(name) ~= "string" or name == "" then return false end
    on = on and true or false
    if Config.WindowHasChannel(id, name) == on then return false end
    local want = {}
    for _, n in ipairs(Config.WindowChannels(id)) do
        if n:lower() ~= name:lower() then want[#want + 1] = n end
    end
    if on then want[#want + 1] = name end
    table.sort(want)
    return editWindow(id, function(w) w.channels = want end)
end

-- ── ADD / REMOVE A TAB (config-first, the reconciler converges) ───────────
--
-- THE RULE THE OWNER'S "+ Add Tab" IS BUILT ON: nothing here creates a frame.
-- The config gains a window entry, the reconciler's own convergeWindow writes
-- it onto the client store (SetChatWindowName/Shown/Docked + routing), and the
-- view rebuilds its strip from the client's own eligibility read. One path in,
-- and it is the SAME path a login takes on a brand-new character.

Config.COMBAT_LOG_ID = 2      -- the client's own, and never ours to re-use

-- The lowest window id nothing (config or client) is using. nil when the
-- client's ten are full — a refusal, never a silent overwrite.
function Config.NewWindowId()
    for id = 1, numWindows() do
        if id ~= Config.COMBAT_LOG_ID then
            local w = Config.WindowEntry(id)
            local live = type(w) == "table" and (w.shown == true or (w.docked and w.docked ~= false))
            if not live then
                local have = Config.CaptureWindow(id)
                if not have or (have.shown ~= true and (have.docked == false or have.docked == nil)) then
                    return id
                end
            end
        end
    end
    return nil
end

-- The dock index a new tab takes: one past the highest the config knows.
local function nextDockIndex()
    local top = 0
    for id = 1, numWindows() do
        local w = Config.WindowEntry(id)
        local d = type(w) == "table" and tonumber(w.docked) or nil
        if d and d > top then top = d end
    end
    return top + 1
end

-- opts = { name =, addonSink = , groups = , channels = }
-- Returns the new id, or nil + a reason.
function Config.AddWindow(opts)
    opts = type(opts) == "table" and opts or {}
    local id = Config.NewWindowId()
    if not id then return nil, "no free chat window (the client has ten)" end
    local name = type(opts.name) == "string" and opts.name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then name = "Chat " .. id end
    -- The look fields come from the window the player already has, so a new tab
    -- is not a differently-dressed stranger in the engine.
    local base = Config.WindowEntry(1) or Config.CaptureWindow(1) or {}
    local dock = nextDockIndex()
    local groups, channels = {}, {}
    for _, g in ipairs(type(opts.groups) == "table" and opts.groups or {}) do
        if type(g) == "string" then groups[#groups + 1] = g end
    end
    for _, n in ipairs(type(opts.channels) == "table" and opts.channels or {}) do
        if type(n) == "string" then channels[#channels + 1] = n end
    end
    table.sort(groups); table.sort(channels)
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return nil, "no store" end
    if type(c.windows) ~= "table" then c.windows = {} end
    c.windows[id] = {
        name = name, fontSize = tonumber(base.fontSize) or 14,
        r = tonumber(base.r) or 0, g = tonumber(base.g) or 0, b = tonumber(base.b) or 0,
        alpha = tonumber(base.alpha) or 0.25,
        shown = true, locked = false, docked = dock, uninteractable = false,
        groups = groups, channels = channels,
    }
    if opts.addonSink then c.windows[id].addonSink = true end
    Config.Bump()
    return id
end

-- Which tabs the config OWNS the removal of. The primary window is never
-- removable (it is the dock's own and the view's chassis host), and neither is
-- the client's combat log (its tab is a toggle, not a tab we made).
function Config.RemovableWindow(id)
    id = tonumber(id)
    if not id or id <= 1 or id == Config.COMBAT_LOG_ID then return false end
    local ids = Config.WindowIds()
    for _, live in ipairs(ids) do if live == id then return true end end
    return false
end

-- Remove = the config says CLOSED, loudly. The entry stays (emptied) rather
-- than being deleted, because a deleted entry is a config that says NOTHING
-- about the window — and a window the config is silent about is a window the
-- reconciler will never close on the next character.
function Config.RemoveWindow(id)
    if not Config.RemovableWindow(id) then return false end
    return editWindow(id, function(w)
        w.shown = false
        w.docked = false
        w.groups = {}
        w.channels = {}
        w.addonSink = nil
        w.tabColor = nil
    end)
end

-- ── THE ADDON TAB ─────────────────────────────────────────────────────────

-- The window flagged as the addon sink, or nil. Lowest id wins if a peer
-- account somehow flagged two (deterministic, never pairs()-ordered).
function Config.AddonSinkId()
    for id = 1, numWindows() do
        local w = Config.WindowEntry(id)
        if type(w) == "table" and w.addonSink == true
           and (w.shown == true or (w.docked and w.docked ~= false)) then
            return id
        end
    end
    return nil
end

function Config.SetAddonSink(id, on)
    on = on and true or false
    id = tonumber(id)
    if not id then return false end
    local cur = Config.AddonSinkId()
    if on and cur == id then return false end
    if not on and cur ~= id then return false end
    return editWindow(id, function(w) w.addonSink = on or nil end)
end

function Config.RouteAddonLines()
    local eff = Config.EffectiveCfg()
    local s = (type(eff) == "table" and type(eff.skin) == "table") and eff.skin or nil
    if s and type(s.routeAddonLines) == "boolean" then return s.routeAddonLines end
    local c = Config.Get()
    s = (c and type(c.skin) == "table") and c.skin or nil
    if s and type(s.routeAddonLines) == "boolean" then return s.routeAddonLines end
    return true
end

function Config.SetRouteAddonLines(on)
    on = on and true or false
    if Config.RouteAddonLines() == on then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.skin) ~= "table" then c.skin = {} end
    c.skin.routeAddonLines = on
    Config.Bump()
    return true
end

-- ── THE COMBAT LOG TAB ────────────────────────────────────────────────────
-- OFF by default: the design's rule 6 (the combat log stays native) is what
-- ships, and this is the owner's opt-in to hosting it in the chassis.

function Config.CombatLogTab()
    local eff = Config.EffectiveCfg()
    local s = (type(eff) == "table" and type(eff.skin) == "table") and eff.skin or nil
    if s and type(s.combatLogTab) == "boolean" then return s.combatLogTab end
    local c = Config.Get()
    s = (c and type(c.skin) == "table") and c.skin or nil
    if s and type(s.combatLogTab) == "boolean" then return s.combatLogTab end
    return false
end

function Config.SetCombatLogTab(on)
    on = on and true or false
    if Config.CombatLogTab() == on then return false end
    Config.AdoptEffective()
    local c = Config.Get()
    if not c then return false end
    if type(c.skin) ~= "table" then c.skin = {} end
    c.skin.combatLogTab = on
    Config.Bump()
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
        cfg = copyCfg({ windows = c.windows, colors = c.colors, join = c.join,
                        aliases = c.aliases, aliasKeepNumber = c.aliasKeepNumber,
                        skin = c.skin }),
    }
end

----------------------------------------------------------------------
-- DIFF: config intent vs a client snapshot, as readable strings for the
-- reconciler's verify + trace ring. One-way (config-authoritative): fields
-- the config does not speak about are not drift.
----------------------------------------------------------------------

local WINDOW_FIELDS = WINDOW_EXACT_FIELDS

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
                -- The normalized corner is a MEASUREMENT: it converges within
                -- a tolerance, and a snapshot that could not read the geometry
                -- says nothing at all (never a retry-ladder spin on a dark
                -- read).
                if type(a.npos) == "table" and not Config.NearPos(a.npos, b.npos) then
                    diffs[#diffs + 1] = "window " .. id .. " npos"
                end
                -- …and the normalized SIZE, on the identical footing.
                if type(a.ndim) == "table" and not Config.NearDim(a.ndim, b.ndim) then
                    diffs[#diffs + 1] = "window " .. id .. " ndim"
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
    local aliases = Config.AliasList()
    ns:Print(("  %d channel alias(es), numbers %s"):format(
        #aliases, Config.AliasKeepNumber() and "KEPT" or "dropped"))
    for _, a in ipairs(aliases) do
        ns:Print(("    %s -> %s"):format(a.key, a.alias))
    end
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

-- SCALE-NORMALIZED POSITIONS: the pure conversions, the round trip at two
-- different UI scales (THE cross-account leg), the unknown-is-not-zero rule,
-- and the tolerance that keeps a measurement from reading as drift forever.
local function testNormalizedPositions(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    -- ── The conversions, pure ────────────────────────────────────────────────
    local fx, fy = Config.Normalize(192, 108, 1920, 1080)
    ck(fx == 0.1 and fy == 0.1, "Normalize: pixels over the pixel screen = a fraction")
    ck(Config.Normalize(0, 0, 1920, 1080) == 0, "Normalize: the screen corner is 0")
    ck(Config.Normalize(1, 1, 0, 1080) == nil, "Normalize: a zero screen answers nil, never a division")
    ck(Config.Normalize(nil, 1, 1920, 1080) == nil, "Normalize: a missing coordinate answers nil")

    -- Denormalize converts into the ANCHORED FRAME's units, so the scale ratio
    -- is part of the answer (Class 3).
    local ox, oy = Config.Denormalize(0.5, 0.25, 1000, 800, 0.65, 0.65)
    ck(math.abs(ox - 500) < 1e-9 and math.abs(oy - 200) < 1e-9,
        "Denormalize: equal scales = plain fraction of UIParent's units")
    ox = Config.Denormalize(0.5, 0.25, 1000, 800, 0.65, 1.3)
    ck(math.abs(ox - 250) < 1e-9,
        "Denormalize: a frame at twice UIParent's scale needs half the offset")
    ck(Config.Denormalize(0.5, 0.5, 1000, 800, 0.65, 0) == nil,
        "Denormalize: a zero frame scale answers nil, never infinity")

    -- ── NearPos: the comparison rule everything else leans on ────────────────
    local NP = Config.NearPos
    ck(NP({ "BOTTOMLEFT", 0.5, 0.5 }, { "BOTTOMLEFT", 0.5, 0.5 }), "NearPos: identical agrees")
    ck(NP({ "BOTTOMLEFT", 0.5, 0.5 }, { "BOTTOMLEFT", 0.5008, 0.4995 }),
        "NearPos: sub-tolerance jitter is the SAME position")
    ck(not NP({ "BOTTOMLEFT", 0.5, 0.5 }, { "BOTTOMLEFT", 0.52, 0.5 }),
        "NearPos: a real move is a real difference")
    ck(not NP({ "BOTTOMLEFT", 0.5, 0.5 }, { "TOPRIGHT", 0.5, 0.5 }),
        "NearPos: a different anchor is a different position")
    ck(NP(nil, { "BOTTOMLEFT", 0.5, 0.5 }) and NP({ "BOTTOMLEFT", 0.5, 0.5 }, nil),
        "NearPos: an UNKNOWN side never manufactures a difference (Class 6 discipline)")

    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local frame = Sim.Frame(1)
    local savedScale, savedLeft, savedBottom = Sim.uiScale, frame._left, frame._bottom

    -- ── THE CROSS-ACCOUNT LEG ────────────────────────────────────────────────
    -- Account A runs at uiScale 0.65 and parks the window flush in the screen's
    -- bottom-left corner. Account B runs at 1.0. The SAME normalized config has
    -- to put the window in the same place on the screen — which is the whole
    -- reason the field exists.
    Sim.SetUIScale(0.65)
    frame._left, frame._bottom = 0, 0
    local npA = Config.CaptureNormalizedPos(1)
    ck(type(npA) == "table" and npA[1] == "BOTTOMLEFT",
        "capture: the normalized corner is written against BOTTOMLEFT")
    ck(npA[2] == 0 and npA[3] == 0, "capture: flush in the corner normalizes to 0,0")

    -- A quarter of the way across and a fifth of the way up, on account A.
    local uiW, uiH, uiScale = Config.ScreenGeometry()
    frame._left   = 0.25 * uiW
    frame._bottom = 0.20 * uiH
    npA = Config.CaptureNormalizedPos(1)
    ck(math.abs(npA[2] - 0.25) < 1e-6 and math.abs(npA[3] - 0.20) < 1e-6,
        "capture: a quarter across the screen captures as 0.25 regardless of the units")

    -- Account B: a DIFFERENT effective scale, same config, same fraction.
    Sim.SetUIScale(1.0)
    local uiW2, uiH2, uiScale2 = Config.ScreenGeometry()
    ck(uiW2 ~= uiW, "the scale change really did change UIParent's unit width")
    ck(math.abs(uiW2 * uiScale2 - uiW * uiScale) < 1e-6,
        "…while the PIXEL screen is identical (the thing both accounts share)")
    local ox2, oy2 = Config.Denormalize(npA[2], npA[3], uiW2, uiH2, uiScale2,
        frame:GetEffectiveScale())
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", ox2, oy2)
    local npB = Config.CaptureNormalizedPos(1)
    ck(Config.NearPos(npA, npB),
        "THE CROSS-ACCOUNT LEG: the same normalized config lands on the same fraction at scale 1.0")
    ck(math.abs(npB[2] - 0.25) < 1e-6, "…and it is still exactly a quarter across")

    -- The raw offsets are NOT the same number — which is exactly why storing
    -- them was the bug.
    local oxA = Config.Denormalize(npA[2], npA[3], uiW, uiH, uiScale, 0.65)
    ck(math.abs(oxA - ox2) > 1,
        "the RAW offset differs between the two accounts (the defect the fraction retires)")

    Sim.SetUIScale(savedScale)
    frame._left, frame._bottom = savedLeft, savedBottom

    -- ── UNKNOWN IS NOT ZERO ──────────────────────────────────────────────────
    local hidLeft = frame._left
    frame._left = nil                       -- the pre-layout world
    ck(Config.CaptureNormalizedPos(1) == nil,
        "an unresolved corner captures as UNKNOWN (nil), never as 0,0")
    local w = Config.CaptureWindow(1)
    ck(w.npos == nil, "…and the window entry simply carries no npos")
    frame._left = hidLeft

    -- A capture that could not read the geometry must not DELETE a position
    -- the config holds (merge, not replace).
    local prev = { [1] = { npos = { "BOTTOMLEFT", 0.4, 0.4 } } }
    local snapWindows = { [1] = { name = "W" } }
    local merged = Config.MergeWindows(prev, snapWindows)
    ck(Config.SerEq(merged[1].npos, { "BOTTOMLEFT", 0.4, 0.4 }),
        "a dark capture keeps the stored npos (an unknown never deletes)")
    merged[1].npos[2] = 0.9
    ck(prev[1].npos[2] == 0.4, "…and the merge handed back a copy, not a reference")
    local snapWithPos = { [1] = { name = "W", npos = { "BOTTOMLEFT", 0.7, 0.7 } } }
    ck(Config.MergeWindows(prev, snapWithPos)[1].npos[2] == 0.7,
        "a capture that DID read the geometry wins over the stored value")

    -- ── TOLERANCE, where it matters: the capture-back gate ───────────────────
    local cfgW  = { name = "W", npos = { "BOTTOMLEFT", 0.500000, 0.500000 } }
    local snapW = { name = "W", npos = { "BOTTOMLEFT", 0.500400, 0.499700 } }
    ck(Config.WindowDiffers(snapW, cfgW) == false,
        "WindowDiffers: float round-trip noise is NOT an edit (no rev-bump storm)")
    snapW.npos = { "BOTTOMLEFT", 0.55, 0.5 }
    ck(Config.WindowDiffers(snapW, cfgW) == true, "WindowDiffers: a real move IS an edit")
    snapW.npos = nil
    ck(Config.WindowDiffers(snapW, cfgW) == false,
        "WindowDiffers: a dark geometry read says nothing about the position")
    snapW.name = "Renamed"
    ck(Config.WindowDiffers(snapW, cfgW) == true,
        "WindowDiffers: every other field still compares EXACTLY")
    ck(Config.WindowDiffers(nil, cfgW) == false,
        "WindowDiffers: no capture at all is not a deletion")

    -- ── THE EDGE, EXACTLY (bounce suspect c) ────────────────────────────────
    -- A flush-left window is npos x = 0, and 0 is the one number a position
    -- pipeline is most likely to fumble: Lua's 0 is truthy (Class 5), a
    -- rounding step can push it to 1e-17, and a tolerance can either mistake it
    -- for drift or mistake real drift for it. Every step of the round trip is
    -- pinned at exactly 0 and at a hair off it, because "it always bounces
    -- back" would look identical whichever of those went wrong.
    local SW, SH, SC = 1920, 1080, 1.0
    local fx, fy = Config.Normalize(0, 0, SW, SH)
    ck(fx == 0 and fy == 0,
        "npos@0: a corner AT the screen edge normalizes to exactly 0, not to nil and not to noise")
    local ox, oy = Config.Denormalize(0, 0, SW / SC, SH / SC, SC, SC)
    ck(ox == 0 and oy == 0, "npos@0: …and denormalizes straight back to 0")
    -- Through a non-1 scale chain, both ways, still exact.
    local fx2 = Config.Normalize(0, 0, SW, SH)
    local ox2 = Config.Denormalize(fx2, 0, SW / 0.65, SH / 0.65, 0.65, 0.65)
    ck(ox2 == 0, "npos@0: exact through a 0.65 scale chain too (no epsilon creep inward)")
    -- A hair off zero survives as a hair off zero.
    local fxTiny = Config.Normalize(0.001 * SW, 0, SW, SH)
    ck(math.abs(fxTiny - 0.001) < 1e-9, "npos@0.001: a hair off the edge round-trips as itself")
    ck(math.abs(Config.Denormalize(0.001, 0, SW, SH, 1, 1) - 0.001 * SW) < 1e-6,
        "npos@0.001: …and back out to the same pixel")
    -- THE TOLERANCE, at the edge, in BOTH directions.
    ck(Config.NearPos({ "BOTTOMLEFT", 0, 0 }, { "BOTTOMLEFT", 0.001, 0 }) == true,
        "npos@0: a stored near-0 and a live 0 ARE the same position (never nudged inward)")
    ck(Config.NearPos({ "BOTTOMLEFT", 0, 0 }, { "BOTTOMLEFT", 0.01, 0 }) == false,
        "npos@0: RED CONTROL — a real 1%-of-screen gap is still a real difference")
    ck(Config.WindowDiffers({ name = "W", npos = { "BOTTOMLEFT", 0, 0 } },
                            { name = "W", npos = { "BOTTOMLEFT", 0.001, 0 } }) == false,
        "npos@0: …so a snapped flush drop never rev-bumps against a near-0 stored corner")
    ck(Config.Normalize(0, 0, 0, SH) == nil,
        "npos@0: a zero SCREEN is refused outright (0 is a truthy lie, Class 5)")

    -- ── WIRE-COMPAT: additive, both fields, old shapes still read ────────────
    local c = Config.Get()
    local savedWindows, savedRev, savedAt = c.windows, c.rev, c.at
    c.windows = { [1] = { name = "Old", pos = { "BOTTOMLEFT", 32, 32 } } }   -- a pre-npos config
    c.rev, c.at = 5, 1000
    ck(Config.DiffList({ windows = c.windows }, { windows = { [1] = { name = "Old",
        pos = { "BOTTOMLEFT", 32, 32 } } } })[1] == nil,
        "a config written by an OLDER build (no npos) still reconciles clean")
    c.windows[1].npos = { "BOTTOMLEFT", 0.1, 0.2 }
    local snapshot = Config.Snapshot()
    ck(Config.SerEq(snapshot.cfg.windows[1].npos, { "BOTTOMLEFT", 0.1, 0.2 }),
        "npos rides the wire payload alongside the legacy pos tuple")
    ck(Config.SerEq(snapshot.cfg.windows[1].pos, { "BOTTOMLEFT", 32, 32 }),
        "…and the legacy tuple is still published for older readers")
    c.windows, c.rev, c.at = savedWindows, savedRev, savedAt
end

-- CHANNEL ALIASES: the storage rules (case-folding, remove-on-empty, the
-- no-op guard), the pure display parse/label seam, and the WIRE leg — the one
-- that would silently rot, because the candidate/snapshot assembly is a
-- whitelist and a new section that is not named there never leaves the account.
local function testAliases(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local c = Config.Get()
    if not c then ck(false, "no config store attached") return end
    local savedAliases, savedKeep = c.aliases, c.aliasKeepNumber
    local savedRev, savedAt = c.rev, c.at
    c.aliases, c.aliasKeepNumber = {}, false
    c.rev, c.at = 1, Config.Now()   -- local candidate wins over an absent mesh

    -- ── Storage: case-folded key, trimmed value, empty removes ───────────────
    ck(Config.GetAlias("Trade - City") == nil, "an un-aliased channel answers nothing")
    ck(Config.SetAlias("Trade - City", "Trade") == true, "setting an alias reports the edit")
    ck(Config.GetAlias("Trade - City") == "Trade", "the alias reads back")
    ck(Config.GetAlias("trade - city") == "Trade", "lookup is CASE-FOLDED")
    ck(Config.GetAlias("TRADE - CITY") == "Trade", "…in both directions")
    ck(c.aliases["trade - city"] == "Trade", "the stored key is the folded name")
    ck(Config.SetAlias("  Trade - City  ", "  Trade  ") == false,
        "a whitespace-only difference is the SAME write (no-op, no bump)")
    local revBefore = Config.Rev()
    ck(Config.SetAlias("Trade - City", "Trade") == false, "an unchanged write is a no-op")
    ck(Config.Rev() == revBefore, "…and never bumps rev (no sync storm)")
    ck(Config.SetAlias("Trade - City", "Commerce") == true, "a real change writes")
    ck(Config.Rev() == revBefore + 1, "…and bumps rev exactly once")
    ck(Config.SetAlias("Trade - City", "") == true, "an EMPTY alias is the remove verb")
    ck(Config.GetAlias("Trade - City") == nil, "…and the channel renders native again")
    ck(c.aliases["trade - city"] == nil, "…with the key gone from the store")
    ck(Config.SetAlias("", "x") == false and Config.SetAlias(nil, "x") == false,
        "a nameless channel is not an alias (Class 5: empty is not a name)")

    -- ── The pure display parse ───────────────────────────────────────────────
    local n, nm = Config.ParseChannelDisplay("[2. Trade - City]")
    ck(n == "2" and nm == "Trade - City", "parse: the numbered client shape splits")
    n, nm = Config.ParseChannelDisplay("[Guild]")
    ck(n == nil and nm == "Guild", "parse: an unnumbered channel header has no number")
    n, nm = Config.ParseChannelDisplay("[10. World]")
    ck(n == "10" and nm == "World", "parse: two-digit numbers split too")
    ck(select(2, Config.ParseChannelDisplay("2. Trade")) == nil,
        "parse: an UNBRACKETED string is not the shape (never a guess)")
    ck(select(2, Config.ParseChannelDisplay("[]")) == nil, "parse: an empty bracket answers nothing")
    ck(select(2, Config.ParseChannelDisplay(nil)) == nil, "parse: a non-string answers nothing")

    -- ── AliasLabel: the single seam, both number postures ────────────────────
    Config.SetAlias("Trade - City", "Trade")
    ck(Config.AliasKeepNumber() == false, "the shipped default DROPS the number (the clean alias)")
    ck(Config.AliasLabel("2", "Trade - City") == "Trade", "label: default is the bare alias")
    ck(Config.AliasLabel(nil, "Trade - City") == "Trade", "label: an unknown number changes nothing")
    ck(Config.SetAliasKeepNumber(true) == true, "the keep-number option writes")
    ck(Config.AliasLabel("2", "Trade - City") == "2. Trade", "label: keep-number restores the prefix")
    ck(Config.AliasLabel(nil, "Trade - City") == "Trade",
        "label: keep-number with NO number is still the bare alias (never '. Trade')")
    ck(Config.SetAliasKeepNumber(true) == false, "an unchanged option write is a no-op")
    Config.SetAliasKeepNumber(false)
    ck(Config.AliasLabel(2, "General") == nil,
        "label: an UNALIASED channel answers nothing (the render-native instruction)")

    -- ── THE CLIENT'S LONG FORM, and the label with a floor under it ──────────
    -- (owner defect 2026-08-12: the entry indicator read the client's
    -- "5. General - Stormwind City:" instead of his nickname.)
    ck(Config.ChannelShortName("General - Stormwind City") == "General",
        "short: the zone comes off the client's own channel name")
    ck(Config.ChannelShortName("Trade - City") == "Trade", "short: …however the zone is spelled")
    ck(Config.ChannelShortName("LookingForGroup") == "LookingForGroup",
        "short: a name with no zone comes back unchanged")
    ck(Config.ChannelShortName("  World  ") == "World", "short: …trimmed")
    ck(Config.ChannelShortName(nil) == nil and Config.ChannelShortName("") == nil,
        "short: a non-name answers nothing (Class 5)")
    ck(Config.ChannelLabel(5, "General - Stormwind City") == "General",
        "label-with-floor: an UNALIASED channel still has a word — the SHORT one, never "
        .. "the zone-suffixed long form")
    Config.SetAlias("General - Stormwind City", "ZONE")
    ck(Config.ChannelLabel(5, "General - Stormwind City") == "ZONE",
        "label-with-floor: …and the owner's nickname wins when there is one")
    Config.SetAlias("General - Stormwind City", "")
    Config.SetAlias("General", "ZONE2")
    ck(Config.ChannelLabel(5, "General - Stormwind City") == "ZONE2",
        "label-with-floor: RED CONTROL — an alias stored against the SHORT name (which is "
        .. "what the chat line's own display text carries) is found too — one channel, one "
        .. "nickname, whichever surface named it")
    Config.SetAlias("General", "")

    -- ── Deterministic listing ────────────────────────────────────────────────
    Config.SetAlias("World", "W")
    Config.SetAlias("General", "Gen")
    local list = Config.AliasList()
    ck(#list == 3, "the listing holds every alias (got " .. #list .. ")")
    ck(list[1].key == "general" and list[2].key == "trade - city" and list[3].key == "world",
        "the listing is SORTED by key (Class 8)")

    -- ── THE WIRE LEG: aliases ride the payload and the candidate ─────────────
    local snap = Config.Snapshot()
    ck(type(snap) == "table" and type(snap.cfg.aliases) == "table",
        "the wire payload carries the alias table")
    ck(snap.cfg.aliases["trade - city"] == "Trade", "…with the aliases in it")
    ck(snap.cfg.aliasKeepNumber == false, "…and the number posture beside them")
    snap.cfg.aliases["trade - city"] = "mutated"
    ck(Config.GetAlias("Trade - City") == "Trade", "the payload is a COPY, not a reference")
    local cands = Config.Candidates()
    local mineHasAliases = false
    for _, cand in ipairs(cands) do
        if type(cand.cfg) == "table" and type(cand.cfg.aliases) == "table"
            and cand.cfg.aliases["world"] == "W" then mineHasAliases = true end
    end
    ck(mineHasAliases, "the LOCAL candidate carries aliases (so LWW can resolve them)")

    -- A peer's winning copy is what the read seam answers, WITHOUT a local
    -- write — the same receive-never-adopts rule every other section has.
    local Nx = ns.Nexus
    local savedRemote = Nx and Nx.RemoteCandidates
    if Nx then
        Nx.RemoteCandidates = function()
            return { { at = Config.Now() + 500, rev = 0, owner = "peer",
                       cfg = { aliases = { ["world"] = "PEER-W" }, aliasKeepNumber = true } } }
        end
        ck(Config.GetAlias("World") == "PEER-W",
            "a peer's newer alias is the EFFECTIVE one (read-time resolution)")
        ck(Config.AliasKeepNumber() == true, "…including its number posture")
        ck(c.aliases["world"] == "W", "…and the local store was NOT written (receive never adopts)")
        Nx.RemoteCandidates = savedRemote
    end

    c.aliases, c.aliasKeepNumber = savedAliases, savedKeep
    c.rev, c.at = savedRev, savedAt
end

-- SKIN LAYOUT: the storage rules, and — the leg that would silently rot — THE
-- WIRE. The candidate/snapshot/adopt assembly is a WHITELIST, so a section
-- that is not named at all three sites never leaves the account. This suite
-- visits all three for `skin`, and the per-window `tabColor` gets the extra
-- pin its shape needs: a client capture knows nothing about it, so a
-- capture-back must carry it across rather than delete it.
local function testSkinLayout(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local c = Config.Get()
    local savedSkin, savedWindows = c.skin, c.windows
    local savedRev, savedAt = c.rev, c.at
    c.skin, c.windows = {}, {}
    c.rev, c.at = 1, Config.Now()

    -- ── Placement: the vocabulary, the default, the no-op guard ──────────────
    ck(Config.TabPlacement() == "top", "an unset placement is TOP (the client's own arrangement)")
    ck(Config.IsTabPlacement("left") and Config.IsTabPlacement("right")
        and Config.IsTabPlacement("top"), "three placements, and they are named")
    ck(Config.IsTabPlacement("diagonal") == false, "…and nothing else is one")
    ck(Config.SetTabPlacement("left") == true, "a placement edit lands")
    ck(Config.TabPlacement() == "left", "…and reads back")
    ck(Config.SetTabPlacement("left") == false, "re-setting the same placement is a NO-OP")
    ck(Config.SetTabPlacement("sideways") == false, "an unknown placement is refused outright")
    ck(Config.TabPlacement() == "left", "…and changes nothing")

    -- ── Per-window colour: a spec string, stored and removable ───────────────
    ck(Config.TabColor(3) == nil, "a window with no explicit colour answers nothing")
    ck(Config.SetTabColor(3, "chat:GUILD") == true, "a colour edit lands")
    ck(Config.TabColor(3) == "chat:GUILD", "…and reads back as the SPEC, never a resolved value")
    ck(Config.SetTabColor(3, "chat:GUILD") == false, "re-setting the same colour is a NO-OP")
    ck(Config.SetTabColor(3, "") == true and Config.TabColor(3) == nil,
        "an emptied colour is the REMOVE verb")
    ck(Config.SetTabColor(3, "token:accent") == true, "…and it can be set again")
    ck(Config.SetTabColor("x", "token:accent") == false, "a non-window id is refused")
    ck(Config.SetTabColor(3, 42) == false, "…and so is a colour that is not a spec string")

    -- ── THE CAPTURE-BACK PIN: config-only fields survive a wholesale merge ───
    local snapWindows = { [3] = { name = "W3", groups = {}, channels = {} } }
    local merged = Config.MergeWindows(c.windows, snapWindows)
    ck(merged[3].tabColor == "token:accent",
        "THE PIN — a capture that says nothing about tabColor does not DELETE it")
    ck(merged[3].name == "W3", "…while the client's own fields land wholesale, as ever")
    local orphan = Config.MergeWindows({ [7] = { tabColor = "chat:RAID" } }, snapWindows)
    ck(orphan[7] and orphan[7].tabColor == "chat:RAID",
        "…and a config-only window entry survives a capture that has no entry for it")

    -- ── THE WIRE, all three whitelist sites ──────────────────────────────────
    local snap = Config.Snapshot()
    ck(type(snap) == "table" and type(snap.cfg.skin) == "table",
        "SITE 1: the wire payload carries the skin section")
    ck(snap.cfg.skin.tabPlacement == "left", "…with the placement in it")
    ck(snap.cfg.windows[3].tabColor == "token:accent",
        "…and the per-window colour rides inside `windows`, which already travelled")
    snap.cfg.skin.tabPlacement = "mutated"
    ck(Config.TabPlacement() == "left", "the payload is a COPY, not a reference")

    local mine
    for _, cand in ipairs(Config.Candidates()) do
        if cand.owner == Config.LocalOwnerKey() then mine = cand end
    end
    ck(mine and type(mine.cfg.skin) == "table" and mine.cfg.skin.tabPlacement == "left",
        "SITE 2: the LWW candidate carries it too (an unlisted section is account-local forever)")

    local Nx = ns.Nexus
    local savedRemote = Nx and Nx.RemoteCandidates
    if Nx then
        Nx.RemoteCandidates = function()
            return { { at = Config.Now() + 500, rev = 0, owner = "peer",
                       cfg = { skin = { tabPlacement = "right" },
                               windows = { [3] = { tabColor = "chat:WHISPER" } } } } }
        end
        ck(Config.TabPlacement() == "right",
            "a peer's newer placement is the EFFECTIVE one (read-time resolution)")
        ck(Config.TabColor(3) == "chat:WHISPER", "…and so is its per-tab colour")
        ck(c.skin.tabPlacement == "left",
            "…and the local store was NOT written (receive never adopts)")
        -- An EDIT adopts the winner first, then publishes on top of it.
        Config.SetTabPlacement("top")
        ck(c.skin.tabPlacement == "top", "SITE 3: an edit lands on the local store")
        ck(c.windows[3] and c.windows[3].tabColor == "chat:WHISPER",
            "SITE 3: …and AdoptEffective pulled the peer's whole config in first")
        Nx.RemoteCandidates = savedRemote
    end

    -- OLD-READER TOLERANCE: a payload from a build that never heard of `skin`
    -- reconciles clean, and this build simply answers its default.
    c.skin = nil
    ck(Config.TabPlacement() == "top", "a config with no skin section at all is safe")
    ck(type(Config.TabColor(3)) == "string",
        "…and the per-window colours it does hold are untouched by that")
    ck(Config.SetTabPlacement("right") == true and c.skin.tabPlacement == "right",
        "…and the section is rebuilt on the next edit rather than erroring")

    c.skin, c.windows = savedSkin, savedWindows
    c.rev, c.at = savedRev, savedAt
end

-- THE OPTIONS REWORK's SEAMS: channel order + colours, per-tab routing, the
-- add/remove verbs, the addon sink and the two strip toggles — plus THE
-- WHITELIST PIN for every one of them (Candidates + Snapshot + AdoptEffective,
-- the three sites the aliases lesson named).
local function testReworkSeams(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local c = Config.Get()
    if not c then return end
    local savedWindows, savedJoin, savedColors, savedSkin =
        c.windows, c.join, c.colors, c.skin
    local savedRev, savedAt = c.rev, c.at
    c.windows, c.join, c.colors, c.skin = {}, {}, {}, {}
    c.rev, c.at = 1, Config.Now()

    -- ── CHANNEL ORDER: a reorder RENUMBERS and never changes membership ──────
    c.join = { { 1, "General" }, { 2, "Trade" }, { 3, "World" } }
    ck(table.concat(Config.ChannelOrder(), ",") == "General,Trade,World",
        "the order reads out of the join list, numbers ascending")
    ck(Config.MoveChannel("World", 1) == true, "a dropped row moves a channel")
    ck(table.concat(Config.ChannelOrder(), ",") == "World,General,Trade",
        "…to the slot it was dropped on, everything else shifting down")
    ck(#Config.JoinList() == 3 and Config.JoinList()[1][1] == 1
        and Config.JoinList()[3][1] == 3,
        "…and the join list is renumbered 1..N (the numbering engine's intent)")
    ck(Config.SetChannelOrder({ "World", "General", "Trade" }) == false,
        "an unchanged order is a no-op (no sync storm)")
    -- THE SAFETY PROPERTY: a name the config is not in cannot be joined by a drag.
    Config.SetChannelOrder({ "NotJoined", "Trade", "World", "General" })
    local names = table.concat(Config.ChannelOrder(), ",")
    ck(names == "Trade,World,General",
        "a reorder NEVER adds membership (got '" .. names .. "')")
    ck(Config.MoveChannel("NotJoined", 1) == false,
        "…and moving a channel the config is not in is refused")

    -- ── CHANNEL COLOURS, by name ─────────────────────────────────────────────
    ck(Config.ChannelColor("Trade") == nil, "an uncoloured channel answers nothing")
    ck(Config.SetChannelColor("Trade", 0.2, 0.4, 0.6) == true, "a swatch writes a colour")
    local col = Config.ChannelColor("TRADE")
    ck(col and math.abs(col.r - 0.2) < 1e-6 and math.abs(col.b - 0.6) < 1e-6,
        "…keyed by NAME, case-folded (numbers move; names do not)")
    ck(Config.SetChannelColor("Trade", 0.2, 0.4, 0.6) == false, "an unchanged colour is a no-op")
    ck(Config.SetChannelColor("Trade", nil) == true and Config.ChannelColor("Trade") == nil,
        "clearing a swatch hands the channel back to the client's own colour")
    Config.SetChannelColor("Trade", 0.2, 0.4, 0.6)

    -- ── PER-TAB NAME + ROUTING ───────────────────────────────────────────────
    c.windows[1] = { name = "General", shown = true, docked = 1,
                     groups = { "SAY", "GUILD" }, channels = { "General" } }
    ck(Config.WindowName(1) == "General", "a tab reads its configured name")
    ck(Config.SetWindowName(1, "  Main  ") == true and Config.WindowName(1) == "Main",
        "a rename trims and lands")
    ck(Config.SetWindowName(1, "Main") == false, "an unchanged rename is a no-op")
    ck(Config.SetWindowName(1, "   ") == false, "a nameless rename is refused")
    ck(Config.WindowHasGroup(1, "SAY") and not Config.WindowHasGroup(1, "YELL"),
        "the group tree reads the configured routing")
    ck(Config.SetWindowGroup(1, "YELL", true) == true and Config.WindowHasGroup(1, "YELL"),
        "checking a group writes it")
    ck(table.concat(Config.WindowGroups(1), ",") == "GUILD,SAY,YELL",
        "…sorted, which is the shape the capture and the diff both speak")
    ck(Config.SetWindowGroup(1, "YELL", true) == false, "an unchanged group is a no-op")
    ck(Config.SetWindowGroup(1, "YELL", false) == true and not Config.WindowHasGroup(1, "YELL"),
        "unchecking removes it")
    ck(Config.SetWindowChannel(1, "Trade", true) == true and Config.WindowHasChannel(1, "TRADE"),
        "channel routing is by name, case-folded")
    ck(Config.SetWindowChannel(1, "Trade", false) == true
        and not Config.WindowHasChannel(1, "Trade"), "…and unchecks again")

    -- ── ADD A TAB (config-first) ─────────────────────────────────────────────
    local before = Config.Rev()
    local newId, why = Config.AddWindow({ name = "Loot" })
    ck(type(newId) == "number" and newId >= 3,
        "+ Add Tab picks a free window id (got " .. tostring(newId) .. " " .. tostring(why) .. ")")
    if newId then
        local w = Config.WindowEntry(newId)
        ck(w and w.shown == true and w.name == "Loot",
            "…and writes a LIVE window entry the reconciler can converge")
        ck(w and type(w.docked) == "number" and w.docked > 1, "…docked past the ones we had")
        ck(Config.Rev() > before, "…and the add is a rev-bumping, syncable edit")
        local live = Config.WindowIds()
        local found = false
        for _, id in ipairs(live) do if id == newId then found = true end end
        ck(found, "…and the new tab is in the config's live tab set")
        ck(Config.NewWindowId() ~= newId, "…so the NEXT add picks a different id")

        -- ── REMOVE ──────────────────────────────────────────────────────────
        ck(Config.RemovableWindow(1) == false, "the primary window is never removable")
        ck(Config.RemovableWindow(Config.COMBAT_LOG_ID) == false,
            "…and neither is the client's combat log")
        ck(Config.RemovableWindow(newId) == true, "a tab the config made IS removable")
        ck(Config.RemoveWindow(newId) == true, "removing it lands")
        local gone = Config.WindowEntry(newId)
        ck(type(gone) == "table" and gone.shown == false and gone.docked == false,
            "…as a config that says CLOSED (an ENTRY, so the next character closes it too)")
        ck(Config.RemoveWindow(1) == false, "…and the primary refuses the verb outright")
    end

    -- ── THE ADDON SINK ───────────────────────────────────────────────────────
    local sinkId = Config.AddWindow({ name = "Addon", addonSink = true })
    ck(Config.AddonSinkId() == sinkId, "the addon tab is found by its config flag")
    ck(Config.SetAddonSink(sinkId, true) == false, "an unchanged flag is a no-op")
    -- The flag is CONFIG-ONLY: a wholesale capture-back must not delete it.
    local merged = Config.MergeWindows(c.windows,
        { [sinkId] = { name = "Addon", shown = true, groups = {}, channels = {} } })
    ck(merged[sinkId] and merged[sinkId].addonSink == true,
        "addonSink survives a capture-back (WINDOW_CONFIG_ONLY_FIELDS carries it)")
    ck(Config.RouteAddonLines() == true, "addon routing defaults ON once a tab exists")
    ck(Config.SetRouteAddonLines(false) == true and Config.RouteAddonLines() == false,
        "…and the toggle is the recoverable red control")
    Config.SetRouteAddonLines(true)
    ck(Config.SetAddonSink(sinkId, false) == true and Config.AddonSinkId() == nil,
        "unflagging leaves no sink at all")
    Config.SetAddonSink(sinkId, true)

    -- ── THE COMBAT LOG TOGGLE ────────────────────────────────────────────────
    ck(Config.CombatLogTab() == false, "the combat log tab is OFF by default (rule 6 ships)")
    ck(Config.SetCombatLogTab(true) == true and Config.CombatLogTab() == true,
        "…and the toggle turns it on")
    ck(Config.SetCombatLogTab(true) == false, "an unchanged toggle is a no-op")

    -- ── THE WHITELIST, all three sites, for all four sections ────────────────
    local snap = Config.Snapshot()
    ck(type(snap) == "table" and type(snap.cfg) == "table", "the wire payload exists")
    if type(snap) == "table" and type(snap.cfg) == "table" then
        ck(type(snap.cfg.join) == "table" and #snap.cfg.join > 0,
            "SITE 1 (Snapshot): the channel ORDER rides the wire")
        ck(type(snap.cfg.colors) == "table" and snap.cfg.colors["trade"] ~= nil,
            "SITE 1 (Snapshot): the channel COLOURS ride the wire")
        ck(type(snap.cfg.windows) == "table"
            and snap.cfg.windows[sinkId] and snap.cfg.windows[sinkId].addonSink == true,
            "SITE 1 (Snapshot): the tab set + addon sink ride the wire")
        ck(type(snap.cfg.skin) == "table" and snap.cfg.skin.combatLogTab == true,
            "SITE 1 (Snapshot): the combat log + addon-routing toggles ride the wire")
    end
    local mine
    for _, cand in ipairs(Config.Candidates()) do
        if cand.owner == Config.LocalOwnerKey() then mine = cand end
    end
    ck(mine and type(mine.cfg.join) == "table" and type(mine.cfg.colors) == "table"
        and type(mine.cfg.windows) == "table" and type(mine.cfg.skin) == "table",
        "SITE 2 (Candidates): every rework section is in the LWW candidate")

    local Nx = ns.Nexus
    local savedRemote = Nx and Nx.RemoteCandidates
    if Nx then
        Nx.RemoteCandidates = function()
            return { { at = Config.Now() + 500, rev = 0, owner = "peer",
                       cfg = { join = { { 1, "Peer" } },
                               colors = { peer = { r = 1, g = 0, b = 0 } },
                               windows = { [5] = { name = "PeerTab", shown = true,
                                                   docked = 5, addonSink = true,
                                                   groups = {}, channels = {} } },
                               skin = { combatLogTab = false, routeAddonLines = false } } } }
        end
        ck(Config.ChannelOrder()[1] == "Peer", "a peer's newer ORDER is the effective one")
        ck(Config.ChannelColor("Peer") ~= nil, "…and its channel colours")
        ck(Config.AddonSinkId() == 5, "…and its addon tab")
        ck(Config.CombatLogTab() == false and Config.RouteAddonLines() == false,
            "…and its strip toggles")
        ck(c.skin.combatLogTab == true, "…with the local store untouched (receive never adopts)")
        Config.SetCombatLogTab(true)
        ck(c.join[1] and c.join[1][2] == "Peer",
            "SITE 3 (AdoptEffective): an edit pulls the peer's ORDER in first")
        ck(c.colors.peer ~= nil, "SITE 3 (AdoptEffective): …and its colours")
        ck(c.windows[5] and c.windows[5].addonSink == true,
            "SITE 3 (AdoptEffective): …and its tab set")
        ck(c.skin.routeAddonLines == false,
            "SITE 3 (AdoptEffective): …and its strip toggles")
        Nx.RemoteCandidates = savedRemote
    end

    c.windows, c.join, c.colors, c.skin = savedWindows, savedJoin, savedColors, savedSkin
    c.rev, c.at = savedRev, savedAt
end

ns:RegisterSelfTest("config", function(verbose)
    local suites = {
        { name = "deterministic serialization", fn = testSerialization },
        { name = "capture + first-run adopt",   fn = testCaptureAndAdopt },
        { name = "LWW + wire payload",          fn = testLWW },
        { name = "scale-normalized positions",  fn = testNormalizedPositions },
        { name = "channel aliases",             fn = testAliases },
        { name = "skin layout: placement + per-tab colour", fn = testSkinLayout },
        { name = "the options rework's seams (order/colours/tabs/sink)", fn = testReworkSeams },
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
