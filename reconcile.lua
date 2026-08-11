-- Daseeki Chat — reconcile.lua  (Wave 2, reconciler/sync agent — REAL)
--
-- THE FLAGSHIP: the login/zone-in reconciler. The design doc's six reconciler
-- rules are the spec of this file:
--
--   1. Config is authoritative; the client's per-character chat state is a
--      projection (config.lua owns the model).
--   2. At login/entering world the reconciler diffs client vs config and
--      converges windows, tabs, routing, fonts, position, channels. The gate
--      is EVENT-DRIVEN: the ENTERING_WORLD bus beat plus channels.lua's
--      CHANNEL_LIST_WARM signal — never a lone timer guess (Class 2), and
--      never a conclusion from the dark channel list (Class 6).
--   3. CAPTURE-BACK: player edits observed on the same client surfaces
--      (hooks on the FCF-family operations + UPDATE_CHAT_COLOR) are diffed
--      into the config, rev-bumped, synced. ECHO DISCIPLINE: every write the
--      reconciler makes is wrapped in SelfWrite, so capture-back can never
--      capture our own actions — proven by call counts in the suite (the
--      echo-storm red control).
--   4. Convergence is VERIFY-AND-RETRY on a finite ladder, with a persisted,
--      bounded, build-stamped TRACE RING in the per-character store: every
--      reconcile records what changed, what refused, and why.
--      /dchat debug reconcile prints it.
--   5. Brand-new character with a config anywhere: the full layout
--      materializes on first login. No config anywhere: ADOPT the current
--      client state as the initial config (never impose defaults).
--   6. Channel-join failures refuse onto the ladder with a trace record;
--      colors re-impose by name on every join/renumber (channels.lua).
--
-- Window writes go through the client's WRITABLE PER-CHARACTER STORE
-- (SetChatWindow* + FloatingChatFrame_Update(id) + FCF_DockUpdate — the
-- write-then-poke reality: store writes do NOT move frames until poked).
-- Channel routing uses AddChatWindowChannel(id, name):
-- **ChatFrame_AddChannel does NOT exist on 11509** — both surfaces are
-- runtime-detected defensively.
--
-- INERTNESS: subscriptions install in OnEnable and are given back in
-- OnDisable. hooksecurefunc has no un-hook, so the capture hooks install once
-- on the FIRST enable and every body gates on Reconcile.active.

local ADDON, ns = ...

local Reconcile = {
    active     = false,
    hooked     = false,
    stats      = { runs = 0, retries = 0, captures = 0 },
    _selfDepth = 0,
}
ns.Reconcile = Reconcile

----------------------------------------------------------------------
-- Constants.
----------------------------------------------------------------------

local LADDER           = { 1.0, 2.0, 4.0, 8.0 }  -- retry delays after a failed verify
local VERIFY_WAIT      = 0.7                     -- store beats settle before the verify read
local CAPTURE_DEBOUNCE = 0.25                    -- player-edit capture coalescing
local TRACE_MAX        = 40                      -- persisted trace ring bound

Reconcile.LADDER = LADDER
Reconcile.TRACE_MAX = TRACE_MAX

local function after(delay, fn)
    local T = _G.C_Timer
    if T and type(T.After) == "function" then
        T.After(delay, fn)
    elseif ns.RouteError then
        ns.RouteError("reconcile: C_Timer absent; step dropped")
    end
end

local function numWindows() return _G.NUM_CHAT_WINDOWS or 10 end

----------------------------------------------------------------------
-- ECHO DISCIPLINE (rule 3). Every client write the reconciler (or
-- channels.lua) performs runs inside SelfWrite; the capture hooks and the
-- UPDATE_CHAT_COLOR handler skip anything observed while the depth is > 0.
-- The sim's hooksecurefunc (like the client's) runs post-hooks synchronously
-- inside the call, so the depth is always visible to them.
----------------------------------------------------------------------

function Reconcile.SelfWrite(fn, ...)
    Reconcile._selfDepth = Reconcile._selfDepth + 1
    local ok, err = pcall(fn, ...)
    Reconcile._selfDepth = Reconcile._selfDepth - 1
    if not ok and ns.RouteError then ns.RouteError(err) end
    return ok
end

function Reconcile.InSelfWrite()
    return Reconcile._selfDepth > 0
end

----------------------------------------------------------------------
-- THE TRACE RING (rule 4): per-character (never synced), bounded,
-- build-stamped. chardb.reconcile.trace = array, oldest first.
----------------------------------------------------------------------

local function traceRing()
    if not ns.chardb then return nil end
    if type(ns.chardb.reconcile) ~= "table" then ns.chardb.reconcile = {} end
    local area = ns.chardb.reconcile
    if type(area.trace) ~= "table" then area.trace = {} end
    return area.trace
end

function Reconcile.Trace(entry)
    local ring = traceRing()
    if not ring or type(entry) ~= "table" then return end
    entry.at = entry.at or (ns.Config and ns.Config.Now and ns.Config.Now()) or 0
    entry.build = ns.VERSION
    ring[#ring + 1] = entry
    while #ring > TRACE_MAX do table.remove(ring, 1) end
end

function Reconcile.TraceEntries()
    return traceRing() or {}
end

----------------------------------------------------------------------
-- CAPTURE-BACK (rule 3): hooks on the FCF-family conveniences (the surfaces
-- the Blizzard UI itself routes player edits through) + UPDATE_CHAT_COLOR for
-- channel color edits. Debounced; wholesale capture-diff lives in config.lua.
----------------------------------------------------------------------

-- EVERY NAMED SURFACE A USER-INITIATED CHANGE CAN END IN. The position half of
-- this list is the answer to the owner's "it always bounces back": a move the
-- capture layer never sees is a move the config never learns, and the very next
-- verify pass "corrects" the player back to the stored corner. So the audit is
-- exhaustive by construction — every way a chat window can move on 11509:
--
--   1. OUR alt-drag              -> skin.lua's OnMoveStop -> NoteExternalChange
--                                   (+ Skin.CommitMove, which makes the CLIENT's
--                                   own store agree so its restore beat cannot
--                                   undo the drop);
--   2. the NATIVE TAB DRAG       -> FCFTab_OnDragStop -> FCF_StopDragging
--                                   -> FCF_SavePositionAndDimensions. All three
--                                   are hooked, because a client that routes a
--                                   drop through only one of them still has to
--                                   reach capture — and FCFTab_OnDragStop is the
--                                   entry point that runs on EVERY tab drop,
--                                   including the ones that never reach
--                                   FCF_StopDragging's undocked path;
--   3. a DROP ONTO / TEAR OFF the dock -> FCFDock_AddChatFrame /
--                                   FCFDock_RemoveChatFrame (a real relocation
--                                   that touches neither of the above);
--   4. FCF_ResetChatWindows      -> the player asking for the stock layout back;
--   5. FCF_RestorePositionAndDimensions -> NOT a user move. Deliberately absent:
--      it is the CLIENT correcting a window from its own store, and capturing it
--      would teach the config the client's answer as if the player had chosen it.
local CAPTURE_HOOKS = {
    "FCF_SetWindowName", "FCF_SetChatWindowFontSize", "FCF_SetWindowColor",
    "FCF_SetWindowAlpha", "FCF_DockFrame", "FCF_UnDockFrame", "FCF_Close",
    "FCF_OpenNewWindow", "FCF_SavePositionAndDimensions", "FCF_StopDragging",
    "FCFTab_OnDragStop", "FCFDock_AddChatFrame", "FCFDock_RemoveChatFrame",
    "FCF_ResetChatWindows",
}
Reconcile.CAPTURE_HOOKS = CAPTURE_HOOKS

----------------------------------------------------------------------
-- THE POSITION LEDGER: one line that names the AUTHOR of the last thing that
-- moved a window.
--
-- "It bounced back" is two completely different bugs wearing the same
-- sentence. Either the player's move never reached the config and the verify
-- pass put the window back where the config still says (a capture hole), or
-- the config genuinely holds that corner and the reconciler is correctly
-- restoring it (a stale/peer config). Guessing between them costs a round trip
-- with the owner every time; the ledger answers it in one line, and
-- /dchat debug reconcile prints it first.
----------------------------------------------------------------------

Reconcile.lastPositionChange = nil   -- { kind = "user"|"drift", why, detail, at, build }

local function fmtNPosShort(np)
    if type(np) ~= "table" then return "none" end
    return string.format("%s %.4f,%.4f", tostring(np[1]),
        tonumber(np[2]) or 0, tonumber(np[3]) or 0)
end

function Reconcile.NotePositionChange(kind, why, detail)
    Reconcile.lastPositionChange = {
        kind   = (kind == "user") and "user" or "drift",
        why    = tostring(why or "?"),
        detail = detail and tostring(detail) or nil,
        at     = (ns.Config and ns.Config.Now and ns.Config.Now()) or 0,
        build  = ns.VERSION,
    }
    return Reconcile.lastPositionChange
end

-- The one-line verdict. Deliberately phrased so the two answers cannot be
-- confused for each other at a glance.
function Reconcile.PositionVerdict()
    local e = Reconcile.lastPositionChange
    if not e then
        return "last position change: none this session (nothing has moved a window)"
    end
    local head = (e.kind == "user")
        and "last position change: user move captured"
        or  "last position change: drift corrected to config"
    return ("%s @ %s (%s%s)"):format(head, tostring(e.at), e.why,
        e.detail and (" | " .. e.detail) or "")
end

-- Every window's stored corner right now, as a comparable snapshot. Used to
-- tell "the capture learned a MOVE" from "the capture learned a rename".
local function positionFingerprint()
    local C = ns.Config
    local c = C and C.Get() or nil
    local out = {}
    local w = (type(c) == "table" and type(c.windows) == "table") and c.windows or {}
    for id = 1, numWindows() do
        local e = w[id]
        out[id] = (type(e) == "table" and type(e.npos) == "table")
            and fmtNPosShort(e.npos) or "none"
    end
    return out
end

-- The FIRST window whose corner the capture actually changed (deterministic:
-- lowest id, never a pairs() lottery — Class 8), or nil when none did.
local function firstMovedWindow(before)
    local after = positionFingerprint()
    for id = 1, numWindows() do
        if before[id] ~= after[id] then
            return ("window %d npos %s -> %s"):format(id, tostring(before[id]),
                tostring(after[id]))
        end
    end
    return nil
end

function Reconcile.ScheduleCapture(why)
    if not Reconcile.active then return end
    Reconcile._pendingWhy = tostring(why or "?")
    if Reconcile._captureQueued then return end
    Reconcile._captureQueued = true
    after(CAPTURE_DEBOUNCE, function()
        Reconcile._captureQueued = false
        if not Reconcile.active then return end
        local C = ns.Config
        if not (C and C.CaptureBack) then return end
        local before = positionFingerprint()
        local changed = C.CaptureBack(Reconcile._pendingWhy)
        if changed then
            Reconcile.stats.captures = Reconcile.stats.captures + 1
            local moved = firstMovedWindow(before)
            local line = Reconcile._pendingWhy .. " -> rev " .. tostring(C.Rev())
            if moved then
                -- Named distinctly from the reconciler's own corrections below:
                -- a bounce report reads one of these two phrases and stops.
                line = "captured user move: " .. moved .. " (via " .. line .. ")"
                Reconcile.NotePositionChange("user", Reconcile._pendingWhy, moved)
            end
            Reconcile.Trace({ gate = "capture", changed = { line } })
        end
    end)
end

-- channels.lua reports player-driven membership changes here.
function Reconcile.NoteExternalChange(why)
    Reconcile.ScheduleCapture(why)
end

local function installHooks()
    if Reconcile.hooked then return end
    Reconcile.hooked = true
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return end
    for _, name in ipairs(CAPTURE_HOOKS) do
        if type(_G[name]) == "function" then
            local capturedName = name
            hook(capturedName, function()
                if Reconcile.active and Reconcile._selfDepth == 0 then
                    Reconcile.ScheduleCapture(capturedName)
                end
            end)
        end
    end
end

----------------------------------------------------------------------
-- WINDOW CONVERGENCE: config -> the client's per-character store.
----------------------------------------------------------------------

-- Runtime-detected channel routing (the 11509 fact: AddChatWindowChannel /
-- RemoveChatWindowChannel are the real surface; the ChatFrame_* globals are
-- checked second purely as a defensive shim for client drift).
local function addChannelToWindow(id, name)
    if type(_G.AddChatWindowChannel) == "function" then
        _G.AddChatWindowChannel(id, name)
    elseif type(_G.ChatFrame_AddChannel) == "function" then
        local frame = _G["ChatFrame" .. id]
        if frame then _G.ChatFrame_AddChannel(frame, name) end
    end
end

local function removeChannelFromWindow(id, name)
    if type(_G.RemoveChatWindowChannel) == "function" then
        _G.RemoveChatWindowChannel(id, name)
    elseif type(_G.ChatFrame_RemoveChannel) == "function" then
        local frame = _G["ChatFrame" .. id]
        if frame then _G.ChatFrame_RemoveChannel(frame, name) end
    end
end

-- Converge one window. Returns a list of field names written (empty = clean).
local function convergeWindow(id, want)
    local C = ns.Config
    local have = C.CaptureWindow(id)
    if not have or type(want) ~= "table" then return {} end
    local dirty = {}
    local function W(cond, field, fn, ...)
        if cond and type(fn) == "function" then
            local args = { ... }
            Reconcile.SelfWrite(function() fn(unpack(args)) end)
            dirty[#dirty + 1] = field
        end
    end
    W(want.name ~= nil and have.name ~= want.name, "name",
        _G.SetChatWindowName, id, want.name)
    W(want.fontSize ~= nil and have.fontSize ~= want.fontSize, "fontSize",
        _G.SetChatWindowSize, id, want.fontSize)
    W((want.r ~= nil or want.g ~= nil or want.b ~= nil)
        and not (have.r == want.r and have.g == want.g and have.b == want.b), "color",
        _G.SetChatWindowColor, id, want.r or 0, want.g or 0, want.b or 0)
    W(want.alpha ~= nil and have.alpha ~= want.alpha, "alpha",
        _G.SetChatWindowAlpha, id, want.alpha)
    W(want.shown ~= nil and have.shown ~= want.shown, "shown",
        _G.SetChatWindowShown, id, want.shown)
    W(want.locked ~= nil and have.locked ~= want.locked, "locked",
        _G.SetChatWindowLocked, id, want.locked)
    W(want.docked ~= nil and not C.SerEq(have.docked, want.docked), "docked",
        _G.SetChatWindowDocked, id, want.docked)
    W(want.uninteractable ~= nil and have.uninteractable ~= want.uninteractable,
        "uninteractable", _G.SetChatWindowUninteractable, id, want.uninteractable)
    if type(want.dim) == "table" and not C.SerEq(have.dim, want.dim) then
        W(true, "dim", _G.SetChatWindowSavedDimensions, id, want.dim[1], want.dim[2])
    end
    if type(want.pos) == "table" and not C.SerEq(have.pos, want.pos) then
        W(true, "pos", _G.SetChatWindowSavedPosition, id,
            want.pos[1], want.pos[2], want.pos[3])
    end

    -- Message groups: set-rewrite when different (sorted, deterministic).
    if type(want.groups) == "table" and not C.SerEq(have.groups, want.groups) then
        local frame = _G["ChatFrame" .. id]
        if frame and type(_G.ChatFrame_RemoveAllMessageGroups) == "function"
                 and type(_G.ChatFrame_AddMessageGroup) == "function" then
            Reconcile.SelfWrite(function()
                _G.ChatFrame_RemoveAllMessageGroups(frame)
                for _, g in ipairs(want.groups) do
                    _G.ChatFrame_AddMessageGroup(frame, g)
                end
            end)
            dirty[#dirty + 1] = "groups"
        end
    end

    -- Channel routing BY NAME: add the missing, remove the unwanted.
    if type(want.channels) == "table" and not C.SerEq(have.channels, want.channels) then
        local haveSet, wantSet = {}, {}
        for _, nm in ipairs(have.channels) do haveSet[nm] = true end
        for _, nm in ipairs(want.channels) do wantSet[nm] = true end
        Reconcile.SelfWrite(function()
            for _, nm in ipairs(want.channels) do
                if not haveSet[nm] then addChannelToWindow(id, nm) end
            end
            for _, nm in ipairs(have.channels) do
                if not wantSet[nm] then removeChannelFromWindow(id, nm) end
            end
        end)
        dirty[#dirty + 1] = "channels"
    end

    -- The write-then-poke reality: the frame re-reads the store only when told.
    if #dirty > 0 and type(_G.FloatingChatFrame_Update) == "function" then
        Reconcile.SelfWrite(_G.FloatingChatFrame_Update, id)
    end
    return dirty
end

function Reconcile.ConvergeWindows(cfg)
    local changed = {}
    local want = type(cfg) == "table" and cfg.windows or nil
    if type(want) ~= "table" then return changed end
    for id = 1, numWindows() do
        local dirty = convergeWindow(id, want[id])
        if #dirty > 0 then
            changed[#changed + 1] = "window " .. id .. ": " .. table.concat(dirty, ",")
        end
    end
    if #changed > 0 and type(_G.FCF_DockUpdate) == "function" then
        Reconcile.SelfWrite(_G.FCF_DockUpdate)
    end
    -- Positions land AFTER the dock settles: the store + dock decide which
    -- frames exist and where the dock sits, and only then does the normalized
    -- placement have a stable world to write into. Runs unconditionally —
    -- a window can drift in position without any store field changing.
    for _, p in ipairs(Reconcile.ApplyPositions(cfg)) do
        changed[#changed + 1] = p
    end
    return changed
end

----------------------------------------------------------------------
-- SCALE-NORMALIZED PLACEMENT (the cross-account fidelity fix, apply half).
--
-- config.lua captures the window's corner as a FRACTION OF THE SCREEN; here it
-- is converted back through THIS account's own effective scale and applied
-- with ClearAllPoints + SetPoint. Two properties do the work:
--   1. Same fraction + local scale = same on-screen corner on every account,
--      whatever the invisible per-account CVars are set to.
--   2. Programmatic placement is NOT drag-clamped, so a corner captured flush
--      against the screen edge on one account lands flush on the other — the
--      account-1 "cannot drag it to the edge" symptom stops mattering.
-- Every write runs inside SelfWrite, so the capture layer never mistakes our
-- placement for a player edit (echo discipline, rule 3).
----------------------------------------------------------------------

local function dockPrimary()
    local dock = _G.GeneralDockManager
    if type(dock) == "table" and type(dock.primary) == "table" then return dock.primary end
    return _G.DEFAULT_CHAT_FRAME
end

-- May we place this window ourselves? A DOCKED window's placement belongs to
-- the dock manager — moving it independently would fight the client every
-- frame — so only the dock's PRIMARY carries the dock's position. Undocked
-- windows place themselves. A hidden window is left alone entirely.
function Reconcile.PlaceableWindow(id, want)
    local frame = _G["ChatFrame" .. tostring(id)]
    if type(frame) ~= "table" then return nil end
    local docked = type(want) == "table" and want.docked or nil
    if docked and docked ~= 0 and frame ~= dockPrimary() then return nil end
    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and not shown then return nil end
    end
    return frame
end

-- Apply one normalized corner. Returns true when the placement was written.
function Reconcile.PlacePoint(frame, npos)
    local C = ns.Config
    if not (C and type(npos) == "table") then return false end
    local uiW, uiH, uiScale = C.ScreenGeometry()
    if not uiW then return false end                    -- world not laid out: no guess
    local fs = uiScale
    if type(frame.GetEffectiveScale) == "function" then
        local ok, v = pcall(frame.GetEffectiveScale, frame)
        if ok and type(v) == "number" and v > 0 then fs = v end
    end
    local ox, oy = C.Denormalize(tonumber(npos[2]), tonumber(npos[3]), uiW, uiH, uiScale, fs)
    if ox == nil then return false end
    -- BOTTOMLEFT is the ONE anchor a capture ever writes; anything else in the
    -- store is a foreign/older shape and is placed as a bottom-left corner
    -- rather than guessed at.
    if type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function" then
        return false
    end
    return Reconcile.SelfWrite(function()
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", ox, oy)
    end)
end

function Reconcile.ApplyPositions(cfg)
    local applied = {}
    local C = ns.Config
    local want = (C and type(cfg) == "table") and cfg.windows or nil
    if type(want) ~= "table" then return applied end
    for id = 1, numWindows() do
        local w = want[id]
        local np = type(w) == "table" and w.npos or nil
        if type(np) == "table" then
            local frame = Reconcile.PlaceableWindow(id, w)
            if frame then
                local have = C.CaptureNormalizedPos(id)
                -- Already there (within the measurement tolerance)? Then this
                -- is not drift and writing again would only be noise. NOTE the
                -- edge case this makes safe on purpose: a corner captured at
                -- exactly 0 and a stored corner a hair off 0 agree, so a flush
                -- window is never nudged inward by float noise (see the npos
                -- round-trip pins in config.lua).
                if have == nil or not C.NearPos(have, np) then
                    if Reconcile.PlacePoint(frame, np) then
                        local detail = ("window %d npos %s -> %s"):format(id,
                            fmtNPosShort(have), fmtNPosShort(np))
                        -- Named distinctly from a captured user move: this is
                        -- the reconciler putting a window BACK, and the ledger
                        -- says so in those words.
                        applied[#applied + 1] = "corrected drift: " .. detail
                        Reconcile.NotePositionChange("drift",
                            "reconcile:" .. tostring(Reconcile._gate or "?"), detail)
                    end
                end
            end
        end
    end
    return applied
end

-- Colors that config wants but the client's CHANNELn slots do not show yet
-- (checked against the CURRENT number of each joined channel).
function Reconcile.VerifyColors(cfg)
    local diffs = {}
    local C = ns.Config
    local colors = type(cfg) == "table" and cfg.colors or nil
    if type(colors) ~= "table" or next(colors) == nil then return diffs end
    local Ch = ns.Channels
    local join = Ch and Ch.CaptureJoinList and Ch.CaptureJoinList() or nil
    if not join then return diffs end
    local CTI = _G.ChatTypeInfo
    for _, e in ipairs(join) do
        local n, name = e[1], e[2]
        local want = colors[tostring(name):lower()]
        local info = type(CTI) == "table" and CTI["CHANNEL" .. tostring(n)] or nil
        if want and info and not C.NearColor(info, want) then
            diffs[#diffs + 1] = "color " .. name
        end
    end
    return diffs
end

----------------------------------------------------------------------
-- THE RUN: attempt -> converge -> (channels) -> verify -> retry ladder.
----------------------------------------------------------------------

local function finishRun()
    Reconcile._runInFlight = false
    Reconcile._chanResult = nil
    if Reconcile._rerunGate then
        local gate = Reconcile._rerunGate
        Reconcile._rerunGate = nil
        Reconcile.Run(gate)
    end
end

function Reconcile.Verify(cfg, changed)
    if not Reconcile.active then finishRun() return end
    local C = ns.Config
    local snap = C.CaptureClient()
    local diffs = C.DiffList(cfg, snap)
    for _, d in ipairs(Reconcile.VerifyColors(cfg)) do diffs[#diffs + 1] = d end
    local refused = {}
    if Reconcile._chanResult and type(Reconcile._chanResult.refused) == "table" then
        for _, r in ipairs(Reconcile._chanResult.refused) do
            refused[#refused + 1] = "channel join refused: " .. tostring(r)
        end
    end
    local attempt = Reconcile._attempt
    local entry = {
        gate = tostring(Reconcile._gate) .. " attempt " .. attempt,
        changed = changed,
    }
    if #diffs > 0 or #refused > 0 then
        entry.refused = {}
        for _, d in ipairs(diffs) do entry.refused[#entry.refused + 1] = "unconverged: " .. d end
        for _, r in ipairs(refused) do entry.refused[#entry.refused + 1] = r end
    end
    Reconcile.Trace(entry)

    if #diffs > 0 and attempt <= #LADDER then
        Reconcile.stats.retries = Reconcile.stats.retries + 1
        after(LADDER[attempt], function()
            if Reconcile.active and Reconcile._runInFlight then Reconcile.Attempt() end
        end)
    else
        if #diffs > 0 then
            Reconcile.Trace({ gate = tostring(Reconcile._gate) .. " EXHAUSTED",
                refused = { ("%d item(s) still unconverged after %d attempt(s)")
                    :format(#diffs, attempt) } })
        end
        finishRun()
    end
end

function Reconcile.Attempt()
    if not Reconcile.active then finishRun() return end
    local C = ns.Config
    if not C then finishRun() return end
    Reconcile._attempt = (Reconcile._attempt or 0) + 1
    Reconcile._chanResult = nil

    -- Rule 5, second half: no config ANYWHERE -> adopt the client state.
    if not C.HasAnyConfig() then
        C.AdoptClient(nil)
        Reconcile.Trace({ gate = tostring(Reconcile._gate),
            changed = { "first run: adopted client state as the initial config (rev "
                        .. tostring(C.Rev()) .. ")" } })
        finishRun()
        return
    end

    -- Read-time resolution: converge toward the cross-account WINNER (receive
    -- never adopts; the local store is only written by edit paths).
    local cfg, owner = C.EffectiveCfg()
    if type(cfg) ~= "table" then finishRun() return end
    Reconcile._winnerOwner = owner

    local changed = Reconcile.ConvergeWindows(cfg)

    local Ch = ns.Channels
    local wantJoin = type(cfg.join) == "table" and #cfg.join > 0
    if not Reconcile._opts.windowsOnly and Ch and Ch.active and Ch.IsListWarm() then
        if wantJoin then
            Ch.Converge(cfg.join, function(result)
                Reconcile._chanResult = result
                after(VERIFY_WAIT, function()
                    if Reconcile.active and Reconcile._runInFlight then
                        Reconcile.Verify(cfg, changed)
                    end
                end)
            end)
            return
        end
        -- No join intent: still keep colors imposed for whatever is joined.
        Ch.ImposeAllColors()
    end
    after(VERIFY_WAIT, function()
        if Reconcile.active and Reconcile._runInFlight then
            Reconcile.Verify(cfg, changed)
        end
    end)
end

function Reconcile.Run(gate, opts)
    if not Reconcile.active then return end
    if Reconcile._runInFlight then
        Reconcile._rerunGate = gate    -- coalesce; the fresh beat reruns after
        return
    end
    Reconcile._runInFlight = true
    Reconcile._attempt = 0
    Reconcile._gate = gate or "?"
    Reconcile._opts = opts or {}
    Reconcile.stats.runs = Reconcile.stats.runs + 1
    Reconcile.Attempt()
end

----------------------------------------------------------------------
-- Lifecycle wiring. ENTERING_WORLD arms the run; CHANNEL_LIST_WARM fires it
-- (the two-signal gate). With the channels module inert the reconciler still
-- converges WINDOWS on a short grace — it just never touches membership and
-- never reads the dark list.
----------------------------------------------------------------------

Reconcile._ewListener = function(isLogin, isReload)
    if not Reconcile.active then return end
    Reconcile._pendingGate = isLogin and "login" or (isReload and "reload" or "zone")
    local Ch = ns.Channels
    if not (Ch and Ch.active) then
        after(0.5, function()
            if Reconcile.active then
                Reconcile.Run(Reconcile._pendingGate or "zone", { windowsOnly = true })
            end
        end)
    end
end

Reconcile._warmListener = function()
    if not Reconcile.active then return end
    local gate = Reconcile._pendingGate or "warm"
    Reconcile._pendingGate = nil
    Reconcile.Run(gate)
end

Reconcile._remoteListener = function()
    -- A peer's config arrived (nexus.lua pumped the bus; the STORE holds it —
    -- receive never adopts). If the new winner differs, converge toward it.
    if not Reconcile.active or not ns.state.inWorld then return end
    if Reconcile._remoteQueued then return end
    Reconcile._remoteQueued = true
    after(1.0, function()
        Reconcile._remoteQueued = false
        if Reconcile.active and ns.state.inWorld then Reconcile.Run("remote") end
    end)
end

Reconcile._colorHandler = function(event, chatType)
    if not Reconcile.active or Reconcile._selfDepth > 0 then return end
    if type(chatType) == "string" and chatType:match("^CHANNEL%d+$") then
        Reconcile.ScheduleCapture("UPDATE_CHAT_COLOR " .. chatType)
    end
end

function Reconcile.OnEnable()
    Reconcile.active = true
    installHooks()
    ns:RegisterEvent("UPDATE_CHAT_COLOR", Reconcile._colorHandler)
    ns:On("ENTERING_WORLD", Reconcile._ewListener)
    ns:On("CHANNEL_LIST_WARM", Reconcile._warmListener)
    ns:On("CHATCFG_REMOTE", Reconcile._remoteListener)
    -- Enabled while already in-world (live /dchat enable): reconcile now,
    -- through the same warm gate.
    if ns.state.inWorld then
        local Ch = ns.Channels
        if Ch and Ch.active and Ch.IsListWarm and Ch.IsListWarm() then
            Reconcile.Run("enable")
        elseif Ch and Ch.active then
            Reconcile._pendingGate = "enable"
        else
            after(0.5, function()
                if Reconcile.active then Reconcile.Run("enable", { windowsOnly = true }) end
            end)
        end
    end
end

function Reconcile.OnDisable()
    Reconcile.active = false
    ns:UnregisterEvent("UPDATE_CHAT_COLOR", Reconcile._colorHandler)
    ns:Off("ENTERING_WORLD", Reconcile._ewListener)
    ns:Off("CHANNEL_LIST_WARM", Reconcile._warmListener)
    ns:Off("CHATCFG_REMOTE", Reconcile._remoteListener)
    Reconcile._runInFlight = false
    Reconcile._rerunGate = nil
    Reconcile._captureQueued = false
end

ns.RegisterModule("reconcile", Reconcile)

ns.RegisterDebugCommand("reconcile", "the reconcile trace ring (what changed, what refused, why)", function()
    local ring = Reconcile.TraceEntries()
    ns:Print(("reconcile: %s | %d run(s), %d retr(ies), %d capture(s)"):format(
        Reconcile.active and "active" or "inactive",
        Reconcile.stats.runs, Reconcile.stats.retries, Reconcile.stats.captures))
    -- THE VERDICT, first and on one line: the next "it bounced back" report
    -- names its own author without anyone having to read the ring.
    ns:Print("  " .. Reconcile.PositionVerdict())
    if #ring == 0 then
        ns:Print("  trace ring is empty (no reconcile has run on this character)")
        return
    end
    local first = math.max(1, #ring - 9)
    for i = #ring, first, -1 do
        local e = ring[i]
        ns:Print(("  [%d] %s (build %s, at %s)"):format(
            i, tostring(e.gate), tostring(e.build), tostring(e.at)))
        for _, c in ipairs(e.changed or {}) do ns:Print("      changed: " .. tostring(c)) end
        for _, r in ipairs(e.refused or {}) do ns:Print("      refused: " .. tostring(r)) end
    end
end)

----------------------------------------------------------------------
-- THE DIAGNOSIS SURFACE: /dchat debug position.
--
-- Everything that decides where a chat window actually lands, printed side by
-- side: the scale chain, UIParent's dimensions in both units and pixels, the
-- clamp state (which is what refuses a manual drag at the screen edge), the
-- client's own saved-position tuple, the live corner, and the normalized
-- corner the config holds. Run it on BOTH accounts and diff the two outputs:
-- whatever differs IS the invisible client difference, on the record.
----------------------------------------------------------------------

local function fmtNum(v)
    if type(v) ~= "number" then return "n/a" end
    return string.format("%.2f", v)
end

local function fmtNPos(np)
    if type(np) ~= "table" then return "none" end
    return string.format("%s %.6f %.6f", tostring(np[1]),
        tonumber(np[2]) or 0, tonumber(np[3]) or 0)
end

local function widgetNumber(w, method)
    if type(w) ~= "table" or type(w[method]) ~= "function" then return nil end
    local ok, v = pcall(w[method], w)
    if ok and type(v) == "number" then return v end
    return nil
end

ns.RegisterDebugCommand("position", "the scale/clamp/position chain per window (run on BOTH accounts and diff)", function()
    local C = ns.Config
    if not C then ns:Print("position: config module missing") return end
    local getCVar = _G.GetCVar
    local function cv(name)
        if type(getCVar) ~= "function" then return "?" end
        local ok, v = pcall(getCVar, name)
        return (ok and v ~= nil) and tostring(v) or "?"
    end
    ns:Print(("position: build %s | CVars uiScale=%s useUiScale=%s")
        :format(tostring(ns.VERSION), cv("uiScale"), cv("useUiScale")))
    local uiW, uiH, uiScale = C.ScreenGeometry()
    if not uiW then
        ns:Print("  UIParent geometry is NOT resolvable right now (nothing else can be trusted)")
        return
    end
    ns:Print(("  UIParent: %s x %s units, effective scale %.4f, %s x %s px")
        :format(fmtNum(uiW), fmtNum(uiH), uiScale,
                fmtNum(uiW * uiScale), fmtNum(uiH * uiScale)))
    local cfg = select(1, C.EffectiveCfg()) or {}
    local windows = type(cfg.windows) == "table" and cfg.windows or {}
    for id = 1, numWindows() do
        local frame = _G["ChatFrame" .. id]
        local info = C.CaptureWindow(id)
        if frame and info and (info.shown or info.docked) then
            local eff = widgetNumber(frame, "GetEffectiveScale")
            local own = widgetNumber(frame, "GetScale")
            ns:Print(("  ChatFrame%d (%s): shown=%s docked=%s placeable=%s")
                :format(id, tostring(info.name), tostring(info.shown),
                        tostring(info.docked),
                        tostring(Reconcile.PlaceableWindow(id, windows[id]) ~= nil)))
            ns:Print(("      scale: own %s, effective %s (UIParent %.4f)")
                :format(fmtNum(own), fmtNum(eff), uiScale))
            local clamped = "?"
            if type(frame.IsClampedToScreen) == "function" then
                local ok, v = pcall(frame.IsClampedToScreen, frame)
                if ok then clamped = tostring(v and true or false) end
            end
            local l, r, t, b = "?", "?", "?", "?"
            if type(frame.GetClampRectInsets) == "function" then
                local ok, a1, a2, a3, a4 = pcall(frame.GetClampRectInsets, frame)
                if ok then l, r, t, b = fmtNum(a1), fmtNum(a2), fmtNum(a3), fmtNum(a4) end
            end
            ns:Print(("      clamp: clampedToScreen=%s insets L%s R%s T%s B%s")
                :format(clamped, l, r, t, b))
            local left, bottom = widgetNumber(frame, "GetLeft"), widgetNumber(frame, "GetBottom")
            ns:Print(("      live:  left %s bottom %s units -> %s %s px")
                :format(fmtNum(left), fmtNum(bottom),
                        fmtNum(left and eff and left * eff),
                        fmtNum(bottom and eff and bottom * eff)))
            local p = info.pos or {}
            ns:Print(("      saved: pos %s %s %s | npos %s")
                :format(tostring(p[1]), fmtNum(p[2]), fmtNum(p[3]), fmtNPos(info.npos)))
            local wantNP = type(windows[id]) == "table" and windows[id].npos or nil
            local agree = C.NearPos(info.npos, wantNP)
            ns:Print(("      config: npos %s (agrees with live: %s)")
                :format(fmtNPos(wantNP), tostring(agree)))
        end
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "reconcile"). Live legs drive the full module against
-- the unkind sim; skipped in-game.
----------------------------------------------------------------------

local function testConvergenceMatrix(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer
    local Config, Channels = ns.Config, ns.Channels

    -- Phase 0: INERTNESS. The harness drove a full login with this module
    -- disabled; nothing may have been installed.
    ck(Reconcile.active == false and Reconcile.hooked == false,
        "phase 0: disabled module installed nothing")
    ck(Sim.CallCount("hooksecurefunc") == 0, "phase 0: zero hook installs (the pin)")

    -- ── FRESH CHARACTER MATERIALIZES THE FULL LAYOUT (rule 5, first half) ──
    Sim.NewSession()
    _G.FCF_ResetChatWindows()

    -- The authoritative config: stock baseline for every window, then a real
    -- layout on windows 1 and 3, a join list with deterministic numbers, and
    -- a channel color by name.
    local c = Config.Get()
    c.rev, c.at = 3, Config.Now()
    c.colors, c.join = {}, {}
    c.windows = {}
    for id = 1, 10 do c.windows[id] = Config.CaptureWindow(id) end
    c.windows[1].name = "Main"
    c.windows[1].fontSize = 16
    c.windows[1].groups = { "GUILD", "SAY", "SYSTEM" }
    c.windows[1].channels = { "General", "OsirisTrade" }
    c.windows[3].name = "Trade Watch"
    c.windows[3].shown = true
    c.windows[3].fontSize = 12
    c.windows[3].channels = { "OsirisTrade" }
    c.windows[3].dim = { 300, 150 }
    c.windows[3].pos = { "TOPLEFT", 10, -10 }
    c.join = { { 1, "General" }, { 2, "OsirisTrade" } }
    c.colors = { osiristrade = { r = 0.9, g = 0.4, b = 0.1 } }

    ns.SetModuleEnabled("channels", true)
    ns.SetModuleEnabled("reconcile", true)
    ck(Reconcile.active and Reconcile.hooked, "enable installs the capture layer")
    Sim.ResetCalls()
    local drops0 = Sim.droppedJoins

    Sim.EnterWorld(true, false)
    -- THE DARK-LIST GATE: at PEW+0 the channel list is dark and the
    -- reconciler has written NOTHING (event-gated, never timer-guessed).
    ck(Sim.CallCount("SetChatWindowName") == 0
        and Sim.CallCount("JoinChannelByName") == 0,
        "dark gate: zero writes before the warm signal")

    HT.advance(0.5)   -- the list warms; the run fires through the gate
    HT.flush()        -- paced joins + verify ladder settle

    ck(select(1, _G.GetChatWindowInfo(1)) == "Main", "window 1 renamed from config")
    local _, fs1 = _G.GetChatWindowInfo(1)
    ck(fs1 == 16, "window 1 font size converged")
    ck(Config.SerEq(Config.CaptureWindow(1).groups, { "GUILD", "SAY", "SYSTEM" }),
        "window 1 message groups converged")
    ck(Config.SerEq(Config.CaptureWindow(1).channels, { "General", "OsirisTrade" }),
        "window 1 channel routing converged BY NAME")
    local w3 = Config.CaptureWindow(3)
    ck(w3.name == "Trade Watch" and w3.shown == true and w3.fontSize == 12,
        "window 3 materialized (name/shown/font)")
    ck(Config.SerEq(w3.dim, { 300, 150 }) and Config.SerEq(w3.pos, { "TOPLEFT", 10, -10 }),
        "window 3 dimensions + position converged")
    ck(Sim.Frame(3)._shown == true,
        "the frame was POKED (FloatingChatFrame_Update projected the store)")
    ck(select(1, _G.GetChannelName("OsirisTrade")) == 2,
        "the join list landed OsirisTrade on its configured number")
    ck(Sim.droppedJoins == drops0, "zero channel ops dropped during materialization")
    ck(Config.NearColor(_G.ChatTypeInfo["CHANNEL2"], c.colors.osiristrade),
        "the channel color was imposed at the configured number")
    ck(Config.Rev() == 3, "materializing a fresh character never edits the config")
    local sawLogin = false
    for _, e in ipairs(Reconcile.TraceEntries()) do
        if tostring(e.gate):find("login", 1, true) then sawLogin = true end
    end
    ck(sawLogin, "the trace ring recorded the login reconcile")
end

local function testDriftEchoAndCapture(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer
    local Config = ns.Config
    local c = Config.Get()

    -- ── DRIFT CORRECTION + THE ECHO-STORM RED CONTROL ──────────────────────
    -- Drift the client via RAW store writes (external mutation, no hooks),
    -- then reconcile: the drift is corrected and — the red control — the
    -- reconciler's own writes are NEVER captured back: rev and the capture
    -- counter stay frozen, proven by counts.
    local revBefore = Config.Rev()
    local capsBefore = Reconcile.stats.captures
    _G.SetChatWindowName(1, "Drifted")
    _G.SetChatWindowSize(3, 99)
    Sim.EnterWorld(false, false)    -- the zone-in re-verify beat
    HT.advance(0.5)
    HT.flush()
    ck(select(1, _G.GetChatWindowInfo(1)) == "Main", "drifted name corrected back to config")
    local _, fs3 = _G.GetChatWindowInfo(3)
    ck(fs3 == 12, "drifted font size corrected back to config")
    ck(Config.Rev() == revBefore,
        "ECHO RED CONTROL: a full reconcile pass never bumped the config rev")
    ck(Reconcile.stats.captures == capsBefore,
        "ECHO RED CONTROL: zero capture-backs fired for the reconciler's own writes")

    -- ── CAPTURE-BACK, the positive control: a PLAYER edit through the hooked
    -- FCF surface lands in the config, exactly once. ───────────────────────
    _G.FCF_SetWindowName(Sim.Frame(3), "My Rename")
    HT.advance(0.3)   -- past the capture debounce
    ck(Config.Rev() == revBefore + 1, "a player edit bumped the rev exactly once")
    ck(c.windows[3].name == "My Rename", "the player's rename landed in the config")
    ck(Reconcile.stats.captures == capsBefore + 1, "exactly one capture ran")

    -- The next reconcile RESPECTS the player's captured edit (D3: the
    -- reconciler only corrects drift it did not author).
    Sim.EnterWorld(false, false)
    HT.advance(0.5)
    HT.flush()
    ck(select(1, _G.GetChatWindowInfo(3)) == "My Rename",
        "a captured player edit is the new truth, not drift")

    -- ── UPDATE_CHAT_COLOR capture: a player recolor is captured BY NAME ────
    local revC = Config.Rev()
    _G.ChangeChatColor("CHANNEL2", 0.2, 0.3, 0.4)
    HT.advance(0.3)
    ck(Config.Rev() == revC + 1, "a player channel recolor captures (rev bump)")
    ck(Config.NearColor(c.colors["osiristrade"], { r = 0.2, g = 0.3, b = 0.4 }),
        "the recolor was captured against the channel NAME, not its number")
end

local function testLadderAndTrace(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer
    local Config = ns.Config
    local c = Config.Get()

    -- ── THE RETRY LADDER IS FINITE; A REFUSED JOIN TRACES, NEVER SPINS ─────
    Sim.opts.refuseJoins = { Ghost = true }
    c.join = { { 1, "General" }, { 2, "OsirisTrade" }, { 3, "Ghost" } }
    c.rev = c.rev + 1
    c.at = Config.Now()
    local drops0 = Sim.droppedJoins
    local runsBefore = Reconcile.stats.runs
    Sim.EnterWorld(false, false)
    HT.advance(0.5)
    HT.flush()   -- an unbounded ladder would hang this flush; it terminates
    ck(Reconcile.stats.runs == runsBefore + 1, "one run consumed the refusal")
    ck(Reconcile._runInFlight == false, "the run ENDED (finite ladder)")
    ck(select(1, _G.GetChannelName("Ghost")) == 0, "the refused channel never appeared")
    ck(Sim.droppedJoins == drops0, "pacing held through every retry")
    local sawRefusal, sawExhausted = false, false
    for _, e in ipairs(Reconcile.TraceEntries()) do
        for _, r in ipairs(e.refused or {}) do
            if tostring(r):find("Ghost", 1, true) then sawRefusal = true end
        end
        if tostring(e.gate):find("EXHAUSTED", 1, true) then sawExhausted = true end
    end
    ck(sawRefusal, "the trace names the refused channel")
    ck(sawExhausted, "the trace records the exhausted ladder honestly")
    Sim.opts.refuseJoins = {}

    -- Clean config again; the next beat converges clean.
    c.join = { { 1, "General" }, { 2, "OsirisTrade" } }
    c.rev = c.rev + 1
    c.at = Config.Now()
    Sim.EnterWorld(false, false)
    HT.advance(0.5)
    HT.flush()
    ck(Reconcile._runInFlight == false, "the clean run also ends")

    -- ── TRACE RING: bounded and build-stamped ──────────────────────────────
    for i = 1, Reconcile.TRACE_MAX + 10 do
        Reconcile.Trace({ gate = "synthetic " .. i })
    end
    local ring = Reconcile.TraceEntries()
    ck(#ring == Reconcile.TRACE_MAX, "the ring is bounded at TRACE_MAX")
    ck(ring[#ring].build == ns.VERSION, "entries are build-stamped")
    ck(ring[#ring].gate == "synthetic " .. (Reconcile.TRACE_MAX + 10),
        "the newest entry survives the trim (oldest evicted)")
    -- ── THE ONE-LINE VERDICT: whose move was it? ───────────────────────────
    -- The owner's next "it bounced back" has to name its own author without
    -- anyone reading the ring, so the verdict is asserted as PRINTED OUTPUT,
    -- not merely as a function that returns a string.
    Reconcile.lastPositionChange = nil
    ck(Reconcile.PositionVerdict():find("none this session", 1, true) ~= nil,
        "the verdict says so plainly when nothing has moved a window yet")
    Reconcile.NotePositionChange("user", "FCFTab_OnDragStop", "window 1 npos … -> BOTTOMLEFT 0,0")
    ck(Reconcile.PositionVerdict():find("user move captured", 1, true) ~= nil,
        "a captured player move is named as a USER MOVE")
    Reconcile.NotePositionChange("drift", "reconcile:login", "window 1 npos … -> …")
    local driftLine = Reconcile.PositionVerdict()
    ck(driftLine:find("drift corrected to config", 1, true) ~= nil,
        "a reconciler correction is named as DRIFT, in different words entirely")
    ck(driftLine:find("user move captured", 1, true) == nil,
        "…so the two verdicts can never be misread for each other")

    local said = {}
    local realPrint = ns.Print
    ns.Print = function(_, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        said[#said + 1] = table.concat(parts, " ")
    end
    local ok = pcall(ns.SlashDispatch, "debug reconcile")
    ns.Print = realPrint
    ck(ok, "/dchat debug reconcile prints without error")
    ck(table.concat(said, "\n"):find("last position change:", 1, true) ~= nil,
        "…and it leads with the position verdict, before the ring")

    -- ── OUT: disable both modules; the client hears nothing further ────────
    ns.SetModuleEnabled("reconcile", false)
    ns.SetModuleEnabled("channels", false)
    ck(Reconcile.active == false, "reconcile disables")
    ck(ns.EventHandlerCount("UPDATE_CHAT_COLOR") == 0
        and ns.EventHandlerCount("CHAT_MSG_CHANNEL_NOTICE") == 0,
        "every event subscription was given back")
    ck(ns.EventHandlerCount() == 4, "only core's 4 lifecycle events remain")
    _G.FCF_SetWindowName(Sim.Frame(3), "Silent Edit")
    HT.advance(0.5)
    HT.flush()
    ck(ns.Config.Get().windows[3].name == "My Rename",
        "a disabled reconciler captures NOTHING (hook bodies are inert)")

    -- Tidy (the wave convention: every suite leaves a world the suites after
    -- it can stand on). This suite re-based the client window store wholesale
    -- (NewSession + FCF_ResetChatWindows + converged layouts that tightened
    -- window 1's routing); hand back the DEFAULT window world before leaving.
    -- Both modules are disabled above, so these writes capture nothing and
    -- converge nothing.
    _G.FCF_ResetChatWindows()
    if type(_G.FloatingChatFrame_Update) == "function" then
        for id = 1, numWindows() do
            _G.FloatingChatFrame_Update(id)
        end
    end
    if type(_G.FCF_DockUpdate) == "function" then _G.FCF_DockUpdate() end
    HT.flush()
    Sim.ResetCalls()
end

-- POSITION AUTHORITY: the normalized corner applied through THIS account's own
-- scale, the dock rule, the flush-to-the-edge property that makes the owner's
-- cross-account annoyance moot, and the diagnosis surface that names the
-- difference for the record.
local function testPositionAuthority(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer
    local Config = ns.Config
    local c = Config.Get()

    local savedWindows, savedRev, savedAt = c.windows, c.rev, c.at
    local savedScale = Sim.uiScale
    Sim.SetUIScale(0.65)

    -- A world to place into: window 1 docked (the dock's primary), window 3
    -- shown and undocked, window 4 docked but NOT primary.
    _G.FCF_ResetChatWindows()
    _G.SetChatWindowShown(3, true)
    _G.SetChatWindowDocked(3, false)
    _G.SetChatWindowShown(4, true)
    _G.SetChatWindowDocked(4, 3)
    for id = 1, numWindows() do _G.FloatingChatFrame_Update(id) end
    local f1, f3, f4 = Sim.Frame(1), Sim.Frame(3), Sim.Frame(4)
    f1._left, f1._bottom = 200, 200
    f3._left, f3._bottom = 200, 200
    f4._left, f4._bottom = 200, 200

    c.windows = {}
    for id = 1, numWindows() do c.windows[id] = Config.CaptureWindow(id) end
    -- The authored intent: window 1 FLUSH in the bottom-left corner (the exact
    -- placement a manual drag refuses on the owner's account 1), window 3 at
    -- three quarters across, window 4 somewhere it must NOT be moved to.
    c.windows[1].npos = { "BOTTOMLEFT", 0, 0 }
    c.windows[3].npos = { "BOTTOMLEFT", 0.75, 0.5 }
    c.windows[4].npos = { "BOTTOMLEFT", 0.10, 0.10 }
    c.rev, c.at = (tonumber(c.rev) or 0) + 1, Config.Now()

    ns.SetModuleEnabled("reconcile", true)
    local revBefore, capsBefore = Config.Rev(), Reconcile.stats.captures

    -- ── PLACEMENT IS NOT DRAG-CLAMPED ────────────────────────────────────────
    -- The frames carry the client's own clamp margin; a drag could not put
    -- window 1 in the corner. ClearAllPoints + SetPoint does not care.
    local insL = select(1, f1:GetClampRectInsets())
    ck(insL > 0, "the client's clamp margin is in force (a drag cannot reach the edge)")
    local applied = Reconcile.ApplyPositions({ windows = c.windows })
    ck(#applied == 2, "exactly the two placeable windows were placed (got " .. #applied .. ")")
    local np1 = Config.CaptureNormalizedPos(1)
    ck(np1 and np1[2] == 0 and np1[3] == 0,
        "FLUSH: the dock primary landed exactly in the screen corner, clamp or no clamp")
    local np3 = Config.CaptureNormalizedPos(3)
    ck(Config.NearPos(np3, { "BOTTOMLEFT", 0.75, 0.5 }),
        "an undocked window landed on its configured fraction")
    ck(f4._left == 200 and f4._bottom == 200,
        "a DOCKED non-primary window was left to the dock manager (never placed)")

    -- ── IDEMPOTENT: a second pass writes nothing ─────────────────────────────
    local applied2 = Reconcile.ApplyPositions({ windows = c.windows })
    ck(#applied2 == 0, "a converged position is not re-written (zero churn)")

    -- ── ECHO CONTROL: our own placement is never captured back ───────────────
    HT.flush()
    ck(Config.Rev() == revBefore, "ECHO: placing positions never bumped the config rev")
    ck(Reconcile.stats.captures == capsBefore, "ECHO: zero capture-backs fired for our placement")

    -- ── A HIDDEN WINDOW IS LEFT ALONE ────────────────────────────────────────
    _G.SetChatWindowShown(3, false)
    _G.FloatingChatFrame_Update(3)
    f3._left = 500
    c.windows[3].npos = { "BOTTOMLEFT", 0.25, 0.25 }
    ck(#Reconcile.ApplyPositions({ windows = c.windows }) == 0,
        "a hidden window is never placed")
    ck(f3._left == 500, "…and its geometry is untouched")
    _G.SetChatWindowShown(3, true)
    _G.FloatingChatFrame_Update(3)

    -- ── THE CROSS-ACCOUNT LEG, end to end ────────────────────────────────────
    -- The config above was authored on an account running uiScale 0.65. Log in
    -- on the account running 1.0: the SAME config has to put the window on the
    -- same part of the screen, with no per-account anything.
    Sim.SetUIScale(1.0)
    f1._left, f1._bottom = 300, 300           -- the other account's stale placement
    Reconcile.ApplyPositions({ windows = c.windows })
    local np1b = Config.CaptureNormalizedPos(1)
    ck(np1b and np1b[2] == 0 and np1b[3] == 0,
        "CROSS-ACCOUNT: the same config lands flush in the corner at scale 1.0 too")
    local np3b = Config.CaptureNormalizedPos(3)
    ck(Config.NearPos(np3b, { "BOTTOMLEFT", 0.25, 0.25 }),
        "CROSS-ACCOUNT: and the undocked window lands on the same FRACTION, not the same offset")
    ck(f1._left == 0, "the placement is a real anchor write, readable back through GetLeft")
    Sim.SetUIScale(0.65)

    -- ── A FRAME WITH ITS OWN SCALE (the ratio, end to end) ──────────────────
    -- A chat window can carry a scale of its own on top of UIParent's. The
    -- fraction is a screen fact, so it must land in the same place whatever the
    -- frame's private scale is — which is only true if the conversion goes
    -- through the RATIO and not through a hopeful 1:1 (Class 3).
    local uiW = select(1, Config.ScreenGeometry())
    local savedFrameScale = f3._scale
    f3:SetScale(2.0)
    f3._left, f3._bottom = 111, 111
    c.windows[3].npos = { "BOTTOMLEFT", 0.6, 0.4 }
    Reconcile.ApplyPositions({ windows = c.windows })
    local npScaled = Config.CaptureNormalizedPos(3)
    ck(Config.NearPos(npScaled, { "BOTTOMLEFT", 0.6, 0.4 }),
        "a window with its OWN scale still lands on the configured fraction")
    ck(math.abs(f3._left - 0.6 * uiW / 2.0) < 1e-6,
        "…and it got there through the scale ratio, not a 1:1 offset")
    f3:SetScale(savedFrameScale or 1)
    c.windows[3].npos = { "BOTTOMLEFT", 0.25, 0.25 }
    Reconcile.ApplyPositions({ windows = c.windows })

    -- ── THE WHOLE RECONCILE BEAT CARRIES POSITIONS ───────────────────────────
    f1._left, f1._bottom = 700, 700
    Sim.EnterWorld(false, false)
    HT.advance(0.5)
    HT.flush()
    local np1c = Config.CaptureNormalizedPos(1)
    ck(np1c and np1c[2] == 0, "a normal login/zone-in reconcile re-lands the position")
    ck(Config.Rev() == revBefore, "…and STILL never captures its own placement back")

    -- ── THE DIAGNOSIS SURFACE ────────────────────────────────────────────────
    local said = {}
    local realPrint = ns.Print
    ns.Print = function(_, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        said[#said + 1] = table.concat(parts, " ")
    end
    local okDbg = pcall(ns.SlashDispatch, "debug position")
    ns.Print = realPrint
    ck(okDbg, "/dchat debug position prints without error")
    local blob = table.concat(said, "\n")
    local function has(needle, label)
        ck(blob:find(needle, 1, true) ~= nil, "debug position reports " .. label)
    end
    has("uiScale=", "the uiScale CVar (the suspected hidden per-account difference)")
    has("UIParent:", "UIParent's dimensions")
    has("effective scale", "the effective scale chain")
    has("clampedToScreen=", "the clamp state")
    has("insets L", "the clamp rect insets")
    has("live:", "the live corner")
    has("saved: pos", "the client's own saved-position tuple")
    has("npos", "the normalized corner")
    has("agrees with live", "whether config and reality agree")
    ck(blob:find("ChatFrame1", 1, true) ~= nil, "debug position walks the live windows")

    -- ── OUT: hand the world back the way this file's other suites do ─────────
    ns.SetModuleEnabled("reconcile", false)
    c.windows, c.rev, c.at = savedWindows, savedRev, savedAt
    Sim.SetUIScale(savedScale)
    _G.FCF_ResetChatWindows()
    for id = 1, numWindows() do _G.FloatingChatFrame_Update(id) end
    if type(_G.FCF_DockUpdate) == "function" then _G.FCF_DockUpdate() end
    for id = 1, numWindows() do
        local f = Sim.Frame(id)
        f._left, f._bottom = 32, 32
    end
    HT.flush()
    Sim.ResetCalls()
end

ns:RegisterSelfTest("reconcile", function(verbose)
    local suites = {
        { name = "fresh-character materialization", fn = testConvergenceMatrix },
        { name = "drift + echo control + capture",  fn = testDriftEchoAndCapture },
        { name = "finite ladder + trace ring",      fn = testLadderAndTrace },
        { name = "position authority + diagnosis",  fn = testPositionAuthority },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local ok, err = pcall(suite.fn, fails)
        if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
        local passed = #fails == 0
        if not passed then allPass = false end
        if verbose and ns.Print then
            if passed then ns:Print("  PASS reconcile/" .. suite.name)
            else for _, f in ipairs(fails) do ns:Print("  FAIL reconcile/" .. suite.name .. " :: " .. f) end end
        end
    end
    return allPass
end)

return Reconcile
