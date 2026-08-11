-- Daseeki Chat — stamps.lua  (Wave 2: pipeline, real)
-- Timestamps at the display layer, the Prat-spec mechanism: after the client
-- stores a printed line, mutate the NEWEST history-buffer entry in place
-- (GetEntryAtIndex(1) is the newest — the game fact) and prepend the stamp.
-- Every line a window prints gets stamped — addon output, system messages,
-- loot — not just re-pipelined chat events, and the stamp survives re-layout
-- and rides into copy-chat text.
--
-- Delivery: a POST-ADD observer on decor.lua's per-window seam (ONE seam per
-- window, suite law). Stamping works with the decoration engine disabled —
-- the seam installs for any consumer — which the suite pins (the anti-Prat
-- decoupling control).
--
-- Guards (the Sim.ReplayBuffer trap is the red control):
--   * entry identity — the same newest entry is never stamped twice;
--   * self-recognition — a line whose text already carries our stamp shape
--     (batch replays re-AddMessage already-stamped lines) is left alone;
--   * an explicit BeginBatch/EndBatch bracket for cooperating mass-replays
--     (history restore, copy re-render).
--
-- The client's OWN timestamps (CVar showTimestamps + CHAT_TIMESTAMP_FORMAT):
-- NEVER silently forced (the spec flags Prat's one-way init write as rude).
--   * native = "defer" (default): if native stamps are on, ours suspend with
--     a one-time printed notice; flipping the CVar off un-suspends.
--   * native = "takeover": one-time printed notice, then the CVar goes to
--     "none" and the format global is cleared; OnDisable hands both back.
--   * If the USER turns native stamps back on mid-session, we suspend and
--     say so once — we never fight the user's CVar write.

local ADDON, ns = ...

local Stamps = {
    active      = false,
    suspended   = false,   -- native timestamps are on and we are deferring
    _batchDepth = 0,
    _lastEntry  = nil,     -- entry-identity double-stamp guard
    _tookOver   = false,
    _origNative = nil,     -- CVar value found when takeover fired
    _origFormat = nil,     -- CHAT_TIMESTAMP_FORMAT found when takeover fired
    _settingCVar = false,  -- our own SetCVar echo guard
    _noticedDefer = false,
    _noticedTakeover = false,
    _noticedUserNative = false,
}
ns.Stamps = Stamps

local DEFAULTS = {
    format      = "HH:MM",     -- "HH:MM" | "HH:MM:SS" | "hh:MM" | "hh:MM:SS"
    colorMode   = "theme",     -- "theme" (colorToken) | "custom" (customColor)
    colorToken  = "muted",     -- Daseeki-Core theme token for the stamp ink
    customColor = "979797",    -- RRGGBB when colorMode = "custom"
    serverTime  = false,       -- format the server clock instead of the local one
    native      = "defer",     -- "defer" | "takeover" (see header)
    windows     = {},          -- [windowId] = false to turn a window off (absent = on)
}

-- Published so the settings pane can bind controls against the REAL default
-- shape (and so a control naming a field this module does not have fails a
-- test rather than writing a key nothing reads). The branch itself is still
-- created in OnEnable, exactly as before.
Stamps.DEFAULTS = DEFAULTS

local FORMATS = {
    ["HH:MM"]    = "%H:%M",
    ["HH:MM:SS"] = "%H:%M:%S",
    ["hh:MM"]    = "%I:%M %p",
    ["hh:MM:SS"] = "%I:%M:%S %p",
}

local function cfg()
    return (ns.db and ns.db.stamps) or DEFAULTS
end

local function isSecret(v)
    local f = _G.issecretvalue
    if type(f) == "function" then
        local ok, res = pcall(f, v)
        return ok and res or false
    end
    return false
end

----------------------------------------------------------------------
-- Stamp construction.
----------------------------------------------------------------------

local function stampHex()
    local c = cfg()
    if c.colorMode == "custom" then
        local hex = tostring(c.customColor or ""):match("^%x%x%x%x%x%x$")
        return hex or "979797"
    end
    local UI = _G.DaseekiUI
    if UI and UI.Color then
        local ok, r, g, b = pcall(UI.Color, c.colorToken or "muted")
        if ok and type(r) == "number" then
            return ("%02x%02x%02x"):format(
                math.floor(math.max(0, math.min(1, r)) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, g)) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, b)) * 255 + 0.5))
        end
    end
    return "979797"
end

function Stamps.FormatStamp()
    local c = cfg()
    local code = FORMATS[c.format] or FORMATS["HH:MM"]
    local dateFn = _G.date or (os and os.date)
    if type(dateFn) ~= "function" then return "" end
    local when
    if c.serverTime and type(_G.GetServerTime) == "function" then
        local ok, t = pcall(_G.GetServerTime)
        if ok then when = dateFn(code, t) end
    end
    if not when then when = dateFn(code) end
    return ("|cff%s[%s]|r"):format(stampHex(), tostring(when))
end

-- Our own stamp shape, for the batch-replay guard: a leading (or, for right-
-- justified windows, trailing) colored [digits:digits...] block. Tight enough
-- that ordinary chat starting with a colored bracket number is implausible;
-- the entry-identity guard covers the direct-repeat case exactly.
local STAMP_PRE  = "^|c%x%x%x%x%x%x%x%x%[[%d:%sAPM]+%]|r "
local STAMP_POST = " |c%x%x%x%x%x%x%x%x%[[%d:%sAPM]+%]|r$"

local function windowOn(frame)
    local c = cfg()
    local id
    if frame and type(frame.GetID) == "function" then
        local ok, got = pcall(frame.GetID, frame)
        if ok then id = got end
    end
    if id and id ~= 0 and c.windows and c.windows[id] == false then return false end
    return true
end

----------------------------------------------------------------------
-- The post-add body: stamp the newest stored entry, once.
----------------------------------------------------------------------

function Stamps.StampNewest(frame)
    if not Stamps.active or Stamps.suspended then return end
    if Stamps._batchDepth > 0 then return end
    if not windowOn(frame) then return end
    local buf = frame and frame.historyBuffer
    if not buf or type(buf.GetEntryAtIndex) ~= "function" then return end
    local entry = buf:GetEntryAtIndex(1)   -- 1 = NEWEST (game fact)
    if not entry or entry == Stamps._lastEntry then return end
    local msg = entry.message
    if type(msg) ~= "string" or isSecret(msg) then return end
    if msg:find(STAMP_PRE) or msg:find(STAMP_POST) then
        -- A replayed line that already wears a stamp: remember it, leave it.
        Stamps._lastEntry = entry
        return
    end
    local right = false
    if type(frame.GetJustifyH) == "function" then
        local ok, j = pcall(frame.GetJustifyH, frame)
        right = ok and j == "RIGHT"
    end
    local stamp = Stamps.FormatStamp()
    if stamp ~= "" then
        entry.message = right and (msg .. " " .. stamp) or (stamp .. " " .. msg)
    end
    Stamps._lastEntry = entry
end

function Stamps.BeginBatch() Stamps._batchDepth = Stamps._batchDepth + 1 end
function Stamps.EndBatch() Stamps._batchDepth = math.max(0, Stamps._batchDepth - 1) end

----------------------------------------------------------------------
-- Native-timestamp diplomacy.
----------------------------------------------------------------------

local function notice(text)
    if ns.Print then ns:Print(text) end
end

function Stamps.EvaluateNative()
    local c = cfg()
    local getcv = _G.GetCVar
    local native = type(getcv) == "function" and getcv("showTimestamps") or nil
    if not native or native == "none" then
        Stamps.suspended = false
        return
    end
    if c.native == "takeover" then
        Stamps._tookOver = true
        if Stamps._origNative == nil then Stamps._origNative = native end
        if Stamps._origFormat == nil then Stamps._origFormat = _G.CHAT_TIMESTAMP_FORMAT end
        if type(_G.SetCVar) == "function" then
            Stamps._settingCVar = true
            _G.SetCVar("showTimestamps", "none")
            Stamps._settingCVar = false
        end
        _G.CHAT_TIMESTAMP_FORMAT = nil
        Stamps.suspended = false
        if not Stamps._noticedTakeover then
            Stamps._noticedTakeover = true
            notice("native chat timestamps were on; Daseeki Chat stamps have taken over (they return if you disable the stamps module).")
        end
    else
        Stamps.suspended = true
        if not Stamps._noticedDefer then
            Stamps._noticedDefer = true
            notice("native chat timestamps are on, so Daseeki Chat stamps are deferring to them. Set the stamps 'native' option to 'takeover' to replace them.")
        end
    end
end

local function onCVarUpdate(event, name, value)
    if not Stamps.active or Stamps._settingCVar then return end
    if name ~= "showTimestamps" then return end
    if tostring(value) == "none" then
        Stamps.suspended = false
    else
        -- The user (or another addon) turned native stamps on. Respect it —
        -- NEVER silently force the CVar back (the spec-flagged rudeness).
        Stamps.suspended = true
        if not Stamps._noticedUserNative then
            Stamps._noticedUserNative = true
            notice("native chat timestamps were turned on; Daseeki Chat stamps are pausing so lines are not stamped twice.")
        end
    end
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function Stamps.OnEnable()
    Stamps.active = true
    if ns.db then ns.EnsureDefaults(ns.db, { stamps = DEFAULTS }) end
    ns.Decor.RegisterPostAdd("stamps", Stamps.StampNewest)
    ns.Decor.EnsureSeams()   -- the seam serves any consumer; decor need not be enabled
    Stamps._cvarHandler = ns:RegisterEvent("CVAR_UPDATE", onCVarUpdate)
    Stamps.EvaluateNative()
end

function Stamps.OnDisable()
    Stamps.active = false
    ns.Decor.UnregisterPostAdd("stamps")
    if Stamps._cvarHandler then
        ns:UnregisterEvent("CVAR_UPDATE", Stamps._cvarHandler)
        Stamps._cvarHandler = nil
    end
    -- Hand back what takeover changed — but only what is still ours to hand
    -- back (if the user re-set the CVar themselves, their value stands).
    if Stamps._tookOver then
        local cur = type(_G.GetCVar) == "function" and _G.GetCVar("showTimestamps") or nil
        if cur == "none" and Stamps._origNative and Stamps._origNative ~= "none"
            and type(_G.SetCVar) == "function" then
            Stamps._settingCVar = true
            _G.SetCVar("showTimestamps", Stamps._origNative)
            Stamps._settingCVar = false
        end
        if _G.CHAT_TIMESTAMP_FORMAT == nil then
            _G.CHAT_TIMESTAMP_FORMAT = Stamps._origFormat
        end
        Stamps._tookOver = false
        Stamps._origNative = nil
        Stamps._origFormat = nil
    end
    Stamps._lastEntry = nil
end

ns.RegisterModule("stamps", Stamps)

ns.RegisterDebugCommand("stamps", "timestamp state: format, native CVar posture", function()
    local c = cfg()
    ns:Print(("stamps: %s%s, format=%s color=%s native=%s serverTime=%s")
        :format(Stamps.active and "active" or "inactive",
            Stamps.suspended and " (suspended: native timestamps are on)" or "",
            tostring(c.format), tostring(c.colorMode), tostring(c.native),
            tostring(c.serverTime)))
    local off = {}
    for id, v in pairs(c.windows or {}) do
        if v == false then off[#off + 1] = tostring(id) end
    end
    ns:Print("  windows off: " .. (#off > 0 and table.concat(off, ", ") or "(none)"))
end)

----------------------------------------------------------------------
-- Self-tests (suite "stamps").
----------------------------------------------------------------------

local function testStamps(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local f6, f7 = Sim.Frame(6), Sim.Frame(7)

    -- ── Phase 0: inertness — inactive module stamps nothing (the decor seam
    -- may already exist; its post-add list must not include us). ─────────────
    ck(Stamps.active == false, "phase 0: module inactive after disabled login")
    f6:AddMessage("unstamped baseline", 1, 1, 1)
    local e0 = f6.historyBuffer:GetEntryAtIndex(1)
    ck(e0 and e0.message == "unstamped baseline", "phase 0: no stamp while disabled")

    -- ── Phase 1: enable — the newest entry is mutated in place. ──────────────
    ns.SetModuleEnabled("stamps", true)
    ck(Stamps.active == true, "phase 1: enabled")
    ck(Stamps.suspended == false, "phase 1: not suspended (native CVar is 'none')")
    f6:AddMessage("hello", 1, 1, 1)
    local e1 = f6.historyBuffer:GetEntryAtIndex(1)
    ck(e1 and e1.message:match("^|cff" .. stampHex() .. "%[%d%d:%d%d%]|r hello$") ~= nil,
        "phase 1: newest entry stamped in place, theme-token ink (got " .. tostring(e1 and e1.message) .. ")")

    -- ── Phase 2: THE DECOUPLING PIN — stamping works with the decoration
    -- engine disabled (the seam serves any consumer; anti-Prat structure). ────
    ns.SetModuleEnabled("decor", false)
    f6:AddMessage("engine off", 1, 1, 1)
    local e2 = f6.historyBuffer:GetEntryAtIndex(1)
    ck(e2 and e2.message:match("%[%d%d:%d%d%]|r engine off$") ~= nil,
        "phase 2 RED CONTROL: stamps still land with the decoration engine disabled")
    ns.SetModuleEnabled("decor", true)

    -- ── Phase 3: double-stamp guards. ────────────────────────────────────────
    Stamps.StampNewest(f6)   -- direct re-ask about the same entry
    local e3 = f6.historyBuffer:GetEntryAtIndex(1)
    local _, stamps3 = e3.message:gsub("%[%d%d:%d%d%]", "")
    ck(stamps3 == 1, "phase 3: re-asking about the same entry never stamps twice")
    -- Sim.ReplayBuffer is the ready-made trap: every replayed line already
    -- wears a stamp and must not gain a second one.
    Sim.ReplayBuffer(f6)
    local clean = true
    for i = 1, f6:GetNumMessages() do
        local msg = f6:GetMessageInfo(i)
        local _, count = msg:gsub("%[%d?%d:%d%d[:%d%sAPM]*%]", "")
        if count > 1 then clean = false end
    end
    ck(clean, "phase 3 RED CONTROL: Sim.ReplayBuffer produced no double-stamped line")

    -- ── Phase 4: the explicit batch bracket. ─────────────────────────────────
    Stamps.BeginBatch()
    f6:AddMessage("batched line", 1, 1, 1)
    local e4 = f6.historyBuffer:GetEntryAtIndex(1)
    ck(e4 and e4.message == "batched line", "phase 4: no stamps inside a batch bracket")
    Stamps.EndBatch()
    f6:AddMessage("after batch", 1, 1, 1)
    local e4b = f6.historyBuffer:GetEntryAtIndex(1)
    ck(e4b and e4b.message:find("after batch", 1, true) ~= nil
        and e4b.message:match("%[%d%d:%d%d%]") ~= nil,
        "phase 4: stamping resumes after EndBatch")

    -- ── Phase 5: per-window off switch. ──────────────────────────────────────
    ns.db.stamps.windows[6] = false
    f6:AddMessage("window six off", 1, 1, 1)
    local e5 = f6.historyBuffer:GetEntryAtIndex(1)
    ck(e5 and e5.message == "window six off", "phase 5: a window turned off gets no stamp")
    f7:AddMessage("window seven on", 1, 1, 1)
    local e5b = f7.historyBuffer:GetEntryAtIndex(1)
    ck(e5b and e5b.message:match("%[%d%d:%d%d%]") ~= nil, "phase 5: other windows still stamp")
    ns.db.stamps.windows[6] = nil

    -- ── Phase 6: formats + custom color. ─────────────────────────────────────
    ns.db.stamps.format = "HH:MM:SS"
    f7:AddMessage("with seconds", 1, 1, 1)
    local e6 = f7.historyBuffer:GetEntryAtIndex(1)
    ck(e6 and e6.message:match("%[%d%d:%d%d:%d%d%]") ~= nil, "phase 6: HH:MM:SS format applies")
    ns.db.stamps.format = "hh:MM"
    f7:AddMessage("twelve hour", 1, 1, 1)
    local e6b = f7.historyBuffer:GetEntryAtIndex(1)
    ck(e6b and e6b.message:match("%[%d%d:%d%d") ~= nil, "phase 6: 12h format applies")
    ns.db.stamps.format = "HH:MM"
    ns.db.stamps.colorMode, ns.db.stamps.customColor = "custom", "123456"
    f7:AddMessage("custom ink", 1, 1, 1)
    local e6c = f7.historyBuffer:GetEntryAtIndex(1)
    ck(e6c and e6c.message:find("|cff123456", 1, true) == 1, "phase 6: custom color applies")
    ns.db.stamps.colorMode = "theme"

    -- ── Phase 7: right-justified windows get the stamp appended. ─────────────
    f7:SetJustifyH("RIGHT")
    f7:AddMessage("right side", 1, 1, 1)
    local e7 = f7.historyBuffer:GetEntryAtIndex(1)
    ck(e7 and e7.message:match("^right side |c%x%x%x%x%x%x%x%x%[%d%d:%d%d%]|r$") ~= nil,
        "phase 7: right-justified window appends the stamp")
    f7:SetJustifyH("LEFT")

    -- ── Phase 8: native-CVar diplomacy — never a silent force. ───────────────
    local said = {}
    local realPrint = ns.Print
    ns.Print = function(_, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        said[#said + 1] = table.concat(parts, " ")
    end
    local ok8, err8 = pcall(function()
        -- (a) defer (the default): user turns native stamps on -> we pause,
        -- we say so once, and we do NOT write the CVar.
        local setsBefore = Sim.CallCount("SetCVar")
        _G.SetCVar("showTimestamps", "always")
        ck(Stamps.suspended == true, "phase 8a: native on -> stamps suspend (defer)")
        ck(Sim.CallCount("SetCVar") == setsBefore + 1,
            "phase 8a: only the external write happened — we never forced the CVar")
        ck(_G.GetCVar("showTimestamps") == "always", "phase 8a: the user's value stands")
        f6:AddMessage("native visible", 1, 1, 1)
        local ea = f6.historyBuffer:GetEntryAtIndex(1)
        ck(ea and ea.message == "native visible", "phase 8a: no stamp while suspended")
        ck(#said >= 1, "phase 8a: the pause was announced, not silent")
        local saidBefore = #said
        _G.SetCVar("showTimestamps", "none")
        _G.SetCVar("showTimestamps", "always")
        ck(#said == saidBefore, "phase 8a: the notice prints ONCE, not per flip")

        -- (b) takeover: announced once, CVar to "none", format global cleared.
        _G.CHAT_TIMESTAMP_FORMAT = "[%H:%M] "
        ns.db.stamps.native = "takeover"
        Stamps.EvaluateNative()
        ck(_G.GetCVar("showTimestamps") == "none", "phase 8b: takeover set the CVar to none")
        ck(_G.CHAT_TIMESTAMP_FORMAT == nil, "phase 8b: takeover cleared CHAT_TIMESTAMP_FORMAT")
        ck(Stamps.suspended == false, "phase 8b: our stamps run after takeover")
        f6:AddMessage("takeover stamped", 1, 1, 1)
        local eb = f6.historyBuffer:GetEntryAtIndex(1)
        ck(eb and eb.message:match("%[%d%d:%d%d%]") ~= nil, "phase 8b: stamping active after takeover")

        -- (c) the user fights back mid-session: their write STANDS.
        local setsBeforeC = Sim.CallCount("SetCVar")
        _G.SetCVar("showTimestamps", "always")
        ck(Stamps.suspended == true, "phase 8c: user re-enabled native -> we pause")
        ck(Sim.CallCount("SetCVar") == setsBeforeC + 1,
            "phase 8c: we did not re-force the user's CVar write")
        ck(_G.GetCVar("showTimestamps") == "always", "phase 8c: the user's value stands")

        -- (d) disable restores what is still ours: the format global comes
        -- back; the CVar (now the user's own value) is left alone.
        ns.SetModuleEnabled("stamps", false)
        ck(_G.CHAT_TIMESTAMP_FORMAT == "[%H:%M] ",
            "phase 8d: OnDisable handed back the saved CHAT_TIMESTAMP_FORMAT")
        ck(_G.GetCVar("showTimestamps") == "always",
            "phase 8d: the user's CVar value was not overwritten at disable")
    end)
    ns.Print = realPrint
    if not ok8 then fails[#fails + 1] = "phase 8 error: " .. tostring(err8) end

    -- Tidy the world for the suites that run after us (the wave convention):
    -- native timestamps off, defer posture, and the stamps module left
    -- DISABLED — the skin suite runs later and pins byte-exact copy-chat
    -- text that live stamping would legitimately prepend to. The module's
    -- behavior is fully pinned above; in the real client it simply enables
    -- at login like every default-on module.
    _G.CHAT_TIMESTAMP_FORMAT = nil
    _G.SetCVar("showTimestamps", "none")
    ns.db.stamps.native = "defer"
    ns.SetModuleEnabled("stamps", false)
    ck(Stamps.active == false, "cleanup: stamps disabled and inert for the later suites")
    Sim.ResetCalls()
end

ns:RegisterSelfTest("stamps", function(verbose)
    local fails = {}
    local ok, err = pcall(testStamps, fails)
    if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL stamps :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS stamps") end
    return #fails == 0
end)

return Stamps
