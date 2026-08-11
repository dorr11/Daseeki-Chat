-- Daseeki Chat — badges.lua  (Wave 2: history/badges agent, real)
-- Per-tab unread counters — the suite's novel feature (the survey found no
-- addon doing per-tab badges; Glass has one global pill, everyone else only
-- flashes the tab).
--
-- Rules as built:
--   * INCREMENT on line delivery (the AddMessage seam — our own wrapper,
--     gated) to a window the player cannot currently SEE: a docked window
--     that is not the dock's selected tab, or an undocked window that is
--     hidden. The focused/visible window NEVER counts.
--   * CLEAR on tab focus (FCF_SelectDockFrame — hooked here under our own
--     gate; skin.lua hooks the same signal for tab ink, the two never couple)
--     and on a hidden window's OnShow transition.
--   * Counts are NUMBERS and zero is a REAL state (Class 5): a cleared tab
--     holds 0, never nil, and display formatting is the only place a zero
--     becomes "no badge".
--   * RENDER: one quiet FontString on a tiny holder frame anchored to the
--     Blizzard tab. ASCII digits, "99+" cap, ink from Core theme tokens
--     (muted; ACCENT while the unread pile contains a whisper). Skin owns the
--     tab's own text/alpha — this module touches ONLY its badge widget.
--   * CONFIG: module on/off (db.modules.badges), per-window opt-out
--     (db.badges.optOut[id]), optional group filter (db.badges.filter — a
--     table of message groups that may badge; whispers ALWAYS badge). The
--     group of a line comes from the CHAT_MSG_* event that precedes the
--     client's AddMessage (the sim's unkind addon-handler-first ordering is
--     exactly why this works: event context is pinned BEFORE delivery).
--
-- INERTNESS: nothing installs until the first OnEnable; wrappers and the two
-- hooksecurefunc installs are permanent but gate on Badges.active; event
-- subscriptions are given back in OnDisable.

local ADDON, ns = ...

local Badges = {
    active        = false,
    globalHooked  = false,  -- one-time hooksecurefunc installs done
    hookedFrames  = {},     -- frame -> true (AddMessage wrapper + OnShow hook)
    frameIds      = {},     -- frame -> window id
    counts        = {},     -- frame -> unread count (0 is a real state)
    whisperFlag   = {},     -- frame -> true while the unread pile has a whisper
    widgets       = {},     -- frame -> { holder, fs, tab }
    pendingGroup  = nil,    -- message group of the event being delivered
    pendingWhisper = false,
    pendingClearQueued = false,
    eventHandlers = nil,    -- event -> handler fn (built once)
}
ns.Badges = Badges

local COMBAT_LOG_ID = 2     -- the combat log never badges

-- Config branch (additive; picked up by EnsureDefaults at DB_READY). The
-- `filter` key is deliberately NOT in the defaults: its off-state is nil and
-- its on-state is a table, and a typed default would let the healer wipe a
-- configured table back to the default on every login.
ns.DEFAULTS.badges = {
    optOut = {},            -- [windowId] = true -> window never badges
}

local function cfg()
    return (ns.db and ns.db.badges) or ns.DEFAULTS.badges
end

local function optedOut(id)
    local oo = cfg().optOut
    return type(oo) == "table" and id ~= nil and oo[id] == true
end

local function filterTable()
    local f = cfg().filter
    if type(f) == "table" then return f end
    return nil                       -- nil = no filter, everything badges
end

----------------------------------------------------------------------
-- Pure helpers.
----------------------------------------------------------------------

-- Display text for a count: nil (no badge) for non-positive/no answer; ASCII
-- digits; capped at "99+". The COUNT itself is never capped — only its ink.
function Badges.FormatCount(n)
    if type(n) ~= "number" or n <= 0 then return nil end
    if n > 99 then return "99+" end
    return tostring(n)
end

----------------------------------------------------------------------
-- Visibility: can the player see this window's lines right now?
----------------------------------------------------------------------

local function isDocked(frame)
    local dock = _G.GeneralDockManager
    local list = dock and dock.DOCKED_CHAT_FRAMES
    if type(list) == "table" then
        for i = 1, #list do
            if list[i] == frame then return true end
        end
    end
    return false
end

local function frameSeen(frame)
    if isDocked(frame) then
        local dock = _G.GeneralDockManager
        return (dock and dock.selected == frame) and true or false
    end
    if frame.IsShown then
        local ok, shown = pcall(frame.IsShown, frame)
        return (ok and shown) and true or false
    end
    return true      -- unknowable visibility: refuse to count (never a false badge)
end

----------------------------------------------------------------------
-- Rendering. The badge is OUR widget anchored to the Blizzard tab; the tab's
-- own text, ink and alpha belong to skin.lua and are never touched here.
----------------------------------------------------------------------

-- THE MOCKUP CONTRACT (2026-08-11), the `.tab .n` row of skin.lua's mapping
-- table: an accent-filled chip carrying WHITE digits, 10.5px, sitting after the
-- tab's label with a 6px gap. Outside the one box the badge keeps exactly the
-- quiet muted/accent FontString it has always been — the chip is the box's
-- look, and the box's gate is the only thing that turns it on.
local PIP_TEXT_SIZE = 10.5   -- .tab .n font-size
local PIP_PAD_X     = 5      -- .tab .n padding: 0 5px
local PIP_H         = 14     -- the chip's own height (10.5 * 1.3, rounded)
local PIP_MIN_W     = 14     -- a single digit still reads as a chip, not a bar
local RAIL_PAD_X    = 10     -- .stab padding-right, where a rail count sits

-- Is the ONE BOX actually on screen? Both halves matter: the skin has to be
-- ACTIVE (a disabled skin draws no box at all, and the chip belongs to the box)
-- and the box has to be the configured look.
local function boxed()
    -- D2 REVISION (2026-08-11): the box is the VIEW's now. The chip belongs to
    -- the box whoever draws it, so the question is asked of the view first and
    -- of skin-over second — a player who turns the view off and leaves skin's
    -- one box on still gets the mockup's chip, and a player with neither gets
    -- the pre-mockup quiet FontString, byte for byte.
    local V = ns.View
    if V and V.active then return true end
    local S = ns.Skin
    if not (S and S.active and type(S.Unified) == "function") then return false end
    local ok, on = pcall(S.Unified)
    return (ok and on) and true or false
end

-- The suite's palette, through skin's published accessor (one table, one place
-- — the table lives in view.lua since the D2 revision and Skin.Ink is the seam
-- that reaches it). Falls back to Core tokens when neither is loaded.
local function ink(name)
    local S = ns.Skin
    if S and type(S.Ink) == "function" then
        local ok, r, g, b, a = pcall(S.Ink, name)
        if ok and type(r) == "number" then return r, g, b, a end
    end
    local UI = _G.DaseekiUI
    if UI and UI.Color then return UI.Color(name) end
    return nil
end

local function applyInk(frame, w)
    local UI = _G.DaseekiUI
    if not (UI and UI.Color and w and w.fs and w.fs.SetTextColor) then return end
    if boxed() then
        -- The mockup's chip: accent fill, white digits, whatever the line was.
        -- A WHISPER still gets to say so — the chip is already accent, so the
        -- distinction moves to the fill's own strength.
        w.fs:SetTextColor(1, 1, 1, 1)
        if w.chip and type(w.chip.SetColorTexture) == "function" then
            local r, g, b = ink("accent")
            if r then w.chip:SetColorTexture(r, g, b, Badges.whisperFlag[frame] and 1 or 0.85) end
            w.chip:Show()
        end
        return
    end
    if w.chip then w.chip:Hide() end
    w.fs:SetTextColor(UI.Color(Badges.whisperFlag[frame] and "accent" or "muted"))
end

----------------------------------------------------------------------
-- WHERE THE BADGE SITS (skin v3). The counter rides the tab, and skin.lua now
-- puts the tab in one of three places, so the badge has to answer the same
-- question. It is a READ of skin's public placement seam — one way, guarded,
-- and defaulting to the client's own arrangement if skin is not loaded at all:
--   TOP tabs   -> a PIP just past the tab's right edge (the shipped behavior);
--   a RAIL     -> the count sits RIGHT-ALIGNED inside the tab's own row, which
--                 is the only place it fits on a 112-unit strip.
-- Skin owns the tab's text, ink and alpha; this module still touches nothing
-- but its own widget.
----------------------------------------------------------------------

function Badges.Placement()
    -- The view answers first while it is painting (its tabs are the ones the
    -- badge is riding); skin-over answers when it is the one drawing tabs.
    local V = ns.View
    if V and V.active and type(V.TabsOnRail) == "function" then
        local ok, rail = pcall(V.TabsOnRail)
        if ok then return rail and "rail" or "top" end
    end
    local S = ns.Skin
    if S and type(S.TabsOnRail) == "function" then
        local ok, rail = pcall(S.TabsOnRail)
        if ok and rail then return "rail" end
    end
    return "top"
end

-- THE TAB THIS BADGE RIDES. One question, asked in one place, because the
-- answer moved: while view.lua paints, a window's tab is OUR button on the
-- view's strip; otherwise it is the client's $parentTab, exactly as it always
-- was. Everything downstream (anchoring, the pip width seam, the chip) is
-- unchanged — the badge simply hangs off a different parent.
function Badges.TabFor(frame)
    local V = ns.View
    if V and V.active and type(V.TabButtonFor) == "function" then
        local ok, btn = pcall(V.TabButtonFor, frame)
        if ok and type(btn) == "table" then return btn end
    end
    local name = frame and frame.GetName and frame:GetName()
    return name and _G[name .. "Tab"] or nil
end

-- The width this badge asks its tab for, so skin.lua can make the tab that
-- wide (`.tab .n` is INSIDE the tab in the mockup, and a tab sized to its label
-- alone has nowhere to put it). Zero when nothing is showing — a tab with no
-- unread is exactly as wide as its label plus its padding.
function Badges.PipWidth(frame)
    local w = Badges.widgets[frame]
    if not (w and w.holder) then return 0 end
    if type(w.holder.IsShown) == "function" then
        local ok, shown = pcall(w.holder.IsShown, w.holder)
        if ok and not shown then return 0 end
    end
    return tonumber(w.width) or 0
end

-- Size the chip to its digits (the mockup's `padding:0 5px` around them).
local function sizePip(w)
    if not (w and w.holder and w.fs) then return 0 end
    local textW = 0
    if type(w.fs.GetStringWidth) == "function" then
        local ok, v = pcall(w.fs.GetStringWidth, w.fs)
        textW = (ok and tonumber(v)) or 0
    end
    local width = math.max(PIP_MIN_W, textW + 2 * PIP_PAD_X)
    if type(w.holder.SetSize) == "function" then pcall(w.holder.SetSize, w.holder, width, PIP_H) end
    w.width = width
    return width
end

function Badges.AnchorWidget(w)
    if not (w and w.holder and w.tab) then return nil end
    local holder, tab = w.holder, w.tab
    if type(holder.ClearAllPoints) ~= "function" then return nil end
    local where = Badges.Placement()
    local box = boxed()
    if w.placement == where and w.boxed == box then return where end
    pcall(holder.ClearAllPoints, holder)
    if where == "rail" then
        -- `.stab .n{float:right}` — right-aligned inside the row's own padding.
        holder:SetPoint("RIGHT", tab, "RIGHT", box and -RAIL_PAD_X or -4, 0)
        if w.fs and type(w.fs.SetJustifyH) == "function" then w.fs:SetJustifyH("RIGHT") end
        if w.fs and type(w.fs.ClearAllPoints) == "function" then
            w.fs:ClearAllPoints()
            w.fs:SetPoint("RIGHT", holder, "RIGHT", box and -PIP_PAD_X or 0, 0)
        end
    elseif box then
        -- THE MOCKUP'S PIP: after the LABEL, inside the tab, 6px of gap. Off
        -- the label's own right edge, never off the tab's — that is what used
        -- to leave it floating in the 2px gap between two tabs.
        local label = tab.Text or (tab.GetName and _G[tab:GetName() .. "Text"])
        holder:SetPoint("LEFT", label or tab, "RIGHT", 6, 0)
        if w.fs and type(w.fs.SetJustifyH) == "function" then w.fs:SetJustifyH("CENTER") end
        if w.fs and type(w.fs.ClearAllPoints) == "function" then
            w.fs:ClearAllPoints()
            w.fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
        end
    else
        -- Off the tab text's end, never over it (skin owns the tab's own ink).
        holder:SetPoint("LEFT", tab, "RIGHT", 1, 0)
        if w.fs and type(w.fs.SetJustifyH) == "function" then w.fs:SetJustifyH("LEFT") end
        if w.fs and type(w.fs.ClearAllPoints) == "function" then
            w.fs:ClearAllPoints()
            w.fs:SetPoint("LEFT", holder, "LEFT", 0, 0)
        end
    end
    w.placement = where
    w.boxed = box
    return where
end

-- Re-place every badge. skin.lua calls this through the module's OWN public
-- beat when it moves the tabs (the courtesy options.lua pays every module it
-- writes a field for); nothing reaches inside this file from outside.
function Badges.Relayout()
    for _, w in pairs(Badges.widgets) do Badges.AnchorWidget(w) end
end

local function ensureWidget(frame)
    local w = Badges.widgets[frame]
    if w then
        -- THE REBIND (D2 revision): the tab a badge rides can CHANGE at
        -- runtime — the view coming up moves it from the client's tab to ours,
        -- and the view going down moves it back. Re-parent on the way through
        -- rather than rebuilding the widget, so a live count survives the move.
        local want = Badges.TabFor(frame)
        if want and want ~= w.tab then
            w.tab = want
            w.placement, w.boxed = nil, nil       -- force the re-anchor below
            if type(w.holder.SetParent) == "function" then
                pcall(w.holder.SetParent, w.holder, want)
            end
        end
        Badges.AnchorWidget(w)
        return w
    end
    local UI = _G.DaseekiUI
    if not (UI and _G.CreateFrame) then return nil end
    local tab = Badges.TabFor(frame)
    if not tab then return nil end
    local holder = _G.CreateFrame("Frame", nil, tab)
    holder:SetSize(PIP_MIN_W, PIP_H)
    -- The chip's fill, BEHIND the digits and behind nothing else. It is hidden
    -- outside the box, so the pre-mockup badge is byte for byte what it was.
    local chip
    if type(holder.CreateTexture) == "function" then
        chip = holder:CreateTexture(nil, "BACKGROUND")
        chip:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        chip:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
        chip:Hide()
    end
    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(UI.fonts and UI.fonts.small or nil)
    -- `.tab .n{font-size:10.5px}` on the suite face (see skin.lua's mapping
    -- table; tabular figures are a documented client limit).
    if type(fs.SetFont) == "function" and type(UI.FontFile) == "function" then
        pcall(fs.SetFont, fs, UI.FontFile(), PIP_TEXT_SIZE, "")
    end
    if UI.Skin then
        UI.Skin(fs, function() applyInk(frame, Badges.widgets[frame]) end)
    end
    holder:Hide()
    w = { holder = holder, fs = fs, tab = tab, chip = chip }
    Badges.widgets[frame] = w
    Badges.AnchorWidget(w)
    return w
end

function Badges.UpdateBadge(frame)
    local w = ensureWidget(frame)
    if not w then return end
    local text = nil
    if Badges.active and not optedOut(Badges.frameIds[frame]) then
        text = Badges.FormatCount(Badges.counts[frame])
    end
    local was = w.width
    if text then
        w.fs:SetText(text)
        applyInk(frame, w)
        sizePip(w)
        w.holder:Show()
    else
        w.holder:Hide()
        if w.chip then w.chip:Hide() end
        w.width = 0
    end
    -- The tab has to be as wide as its label PLUS this chip (the mockup keeps
    -- the pip inside the tab), and skin owns the tab. Ring its bell only when
    -- the width actually moved — a beat that changes nothing costs nothing.
    if (was or 0) ~= (w.width or 0) then
        local V = ns.View
        if V and V.active and type(V.LayoutTabs) == "function" then
            -- The view sizes its tabs around PipWidth (the seam skin-over
            -- introduced, preserved), so a chip that grew a digit means the
            -- tab run has to be laid out again. Relayout is anchor-only and
            -- never calls back here, so the bell cannot ring itself.
            pcall(V.LayoutTabs)
        end
        local S = ns.Skin
        if S and type(S.NoteBadgeChanged) == "function" then pcall(S.NoteBadgeChanged) end
    end
end

----------------------------------------------------------------------
-- Count mechanics.
----------------------------------------------------------------------

function Badges.Clear(frame)
    if not frame or not Badges.hookedFrames[frame] then return end
    Badges.counts[frame] = 0            -- zero is a real, stored number
    Badges.whisperFlag[frame] = nil
    Badges.UpdateBadge(frame)
end

local function onDelivery(frame)
    local id = Badges.frameIds[frame]
    if id == COMBAT_LOG_ID then return end
    if optedOut(id) then return end
    if frameSeen(frame) then return end     -- the focused tab NEVER counts
    local isWhisper = Badges.pendingWhisper == true
    local flt = filterTable()
    if flt then
        local grp = Badges.pendingGroup
        -- Whispers always badge; everything else must be explicitly allowed.
        if not (isWhisper or (grp ~= nil and flt[grp] == true)) then return end
    end
    Badges.counts[frame] = (Badges.counts[frame] or 0) + 1
    if isWhisper then Badges.whisperFlag[frame] = true end
    Badges.UpdateBadge(frame)
end

----------------------------------------------------------------------
-- Event context: the CHAT_MSG_* event runs before the client stores the line
-- (the register's ordering fact), so the group/whisper flags pinned here are
-- live when the AddMessage wrapper fires; a zero-delay timer sweeps them once
-- the synchronous delivery fan-out is done.
----------------------------------------------------------------------

local GROUP_EVENTS = {
    { "CHAT_MSG_SAY", "SAY" }, { "CHAT_MSG_YELL", "YELL" },
    { "CHAT_MSG_EMOTE", "EMOTE" }, { "CHAT_MSG_GUILD", "GUILD" },
    { "CHAT_MSG_OFFICER", "OFFICER" },
    { "CHAT_MSG_WHISPER", "WHISPER" }, { "CHAT_MSG_WHISPER_INFORM", "WHISPER" },
    { "CHAT_MSG_BN_WHISPER", "WHISPER" },
    { "CHAT_MSG_PARTY", "PARTY" }, { "CHAT_MSG_PARTY_LEADER", "PARTY" },
    { "CHAT_MSG_RAID", "RAID" }, { "CHAT_MSG_RAID_LEADER", "RAID" },
    { "CHAT_MSG_RAID_WARNING", "RAID_WARNING" },
    { "CHAT_MSG_INSTANCE_CHAT", "INSTANCE_CHAT" },
    { "CHAT_MSG_INSTANCE_CHAT_LEADER", "INSTANCE_CHAT" },
    { "CHAT_MSG_SYSTEM", "SYSTEM" }, { "CHAT_MSG_CHANNEL", "CHANNEL" },
}

local GROUP_OF_EVENT = {}
for i = 1, #GROUP_EVENTS do
    GROUP_OF_EVENT[GROUP_EVENTS[i][1]] = GROUP_EVENTS[i][2]
end

local function onChatEvent(event)
    if not Badges.active then return end
    Badges.pendingGroup = GROUP_OF_EVENT[event]
    Badges.pendingWhisper = (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
    if not Badges.pendingClearQueued then
        local CT = _G.C_Timer
        if CT and CT.After then
            Badges.pendingClearQueued = true
            CT.After(0, function()
                Badges.pendingClearQueued = false
                Badges.pendingGroup = nil
                Badges.pendingWhisper = false
            end)
        end
    end
end

----------------------------------------------------------------------
-- Install: AddMessage wrapper + OnShow hook per frame (once, gated), plus the
-- two permanent hooksecurefunc installs (first enable only, bodies gated).
----------------------------------------------------------------------

local function rigFrame(frame, id)
    if not frame or Badges.hookedFrames[frame] then return end
    local orig = frame.AddMessage
    if type(orig) ~= "function" then return end
    Badges.hookedFrames[frame] = true
    Badges.frameIds[frame] = id
    if Badges.counts[frame] == nil then Badges.counts[frame] = 0 end
    frame.AddMessage = function(self, text, r, g, b, ...)
        local r1, r2, r3, r4 = orig(self, text, r, g, b, ...)
        if Badges.active then onDelivery(self) end
        return r1, r2, r3, r4
    end
    if type(frame.HookScript) == "function" then
        -- A hidden window surfacing means the player is looking at it now.
        pcall(frame.HookScript, frame, "OnShow", function(self)
            if Badges.active then Badges.Clear(self) end
        end)
    end
end

local function installGlobalHooks()
    if Badges.globalHooked then return end
    Badges.globalHooked = true
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return end
    if type(_G.FCF_SelectDockFrame) == "function" then
        hook("FCF_SelectDockFrame", function(frame)
            if Badges.active and frame then Badges.Clear(frame) end
        end)
    end
    if type(_G.FCF_OpenTemporaryWindow) == "function" then
        hook("FCF_OpenTemporaryWindow", function()
            if not Badges.active then return end
            for id = (_G.NUM_CHAT_WINDOWS or 10) + 1, 50 do
                local f = _G["ChatFrame" .. id]
                if f and not Badges.hookedFrames[f] then
                    rigFrame(f, id)
                end
            end
        end)
    end
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function Badges.OnEnable()
    Badges.active = true
    installGlobalHooks()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        rigFrame(_G["ChatFrame" .. id], id)
    end
    if not Badges.eventHandlers then
        Badges.eventHandlers = {}
        for i = 1, #GROUP_EVENTS do
            local event = GROUP_EVENTS[i][1]
            if not Badges.eventHandlers[event] then
                Badges.eventHandlers[event] = function(ev) onChatEvent(ev) end
            end
        end
    end
    for i = 1, #GROUP_EVENTS do          -- ordered walk, never pairs (Class 8 habit)
        local event = GROUP_EVENTS[i][1]
        ns:RegisterEvent(event, Badges.eventHandlers[event])
    end
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. id]
        if f and Badges.hookedFrames[f] then Badges.UpdateBadge(f) end
    end
end

function Badges.OnDisable()
    Badges.active = false
    if Badges.eventHandlers then
        for i = 1, #GROUP_EVENTS do
            local event = GROUP_EVENTS[i][1]
            local fn = Badges.eventHandlers[event]
            if fn then ns:UnregisterEvent(event, fn) end
        end
    end
    for _, w in pairs(Badges.widgets) do
        if w.holder then w.holder:Hide() end
    end
end

ns.RegisterModule("badges", Badges)

ns.RegisterDebugCommand("badges", "per-tab unread counters: counts + config", function()
    ns:Print(("badges: %s, filter=%s"):format(
        Badges.active and "active" or "inactive",
        filterTable() and "on (whispers always badge)" or "off (all groups badge)"))
    local any = false
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. id]
        if f and Badges.hookedFrames[f] then
            local n = Badges.counts[f] or 0
            if n > 0 or optedOut(id) then
                any = true
                ns:Print(("  window %d: %d unread%s%s"):format(id, n,
                    Badges.whisperFlag[f] and " (whisper)" or "",
                    optedOut(id) and " (opted out)" or ""))
            end
        end
    end
    if not any then ns:Print("  no unread anywhere") end
end)

----------------------------------------------------------------------
-- Self-tests (suite "badges"). Pure parts always; live parts drive the module
-- against the unkind simulator and are skipped in-game.
----------------------------------------------------------------------

local function testPure(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local F = Badges.FormatCount
    ck(F(nil) == nil, "pure: no count -> no badge")
    ck(F(0) == nil, "pure: zero -> no badge shown (but zero stays a real number upstream)")
    ck(F(-3) == nil, "pure: negative refuses")
    ck(F(1) == "1" and F(42) == "42" and F(99) == "99", "pure: plain ASCII digits")
    ck(F(100) == "99+" and F(1200) == "99+", "pure: 99+ display cap")
end

local function testLive(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local HT  = _G.__DaseekiChatHarnessTimer
    local UI  = _G.DaseekiUI
    if not (Sim and HT and UI) then
        if verbose then ns:Print("  badges: live checks skipped (no simulator)") end
        return
    end
    local cf1, cf3, cf4 = _G.ChatFrame1, _G.ChatFrame3, _G.ChatFrame4
    local dock = _G.GeneralDockManager

    -- ── Phase 0: INERTNESS (harness logged in with badges disabled). ─────────
    -- Sibling suites legitimately leave THEIR modules enabled (default-on
    -- discipline: names holds chat-event subscriptions right now), so the pin
    -- is BADGES' OWN subscriptions, measured as a delta against the world the
    -- predecessors left — never the world's total. The whole-world zero is
    -- already pinned by the harness inertness gate before any suite runs.
    ck(Badges.active == false, "phase 0: inactive after disabled login")
    ck(next(Badges.hookedFrames) == nil, "phase 0: zero wrappers while disabled (the pin)")
    ck(Badges.globalHooked == false, "phase 0: zero hooksecurefunc installs while disabled")
    ck(Badges.eventHandlers == nil,
        "phase 0: badges built no event handlers while disabled (it holds zero subscriptions)")
    local whisperBase = ns.EventHandlerCount("CHAT_MSG_WHISPER")

    -- ── Phase 1: enable; the focused tab never counts. ───────────────────────
    ns.SetModuleEnabled("badges", true)
    ck(Badges.active == true, "phase 1: enabled")
    local wrapped = 0
    for _ in pairs(Badges.hookedFrames) do wrapped = wrapped + 1 end
    ck(wrapped == (_G.NUM_CHAT_WINDOWS or 10), "phase 1: all ten windows rigged")
    ck(Badges.globalHooked == true, "phase 1: focus + temp-window hooks installed")
    ck(ns.EventHandlerCount("CHAT_MSG_WHISPER") == whisperBase + 1,
        "phase 1: enabling added exactly ONE whisper subscription (badges' own delta)")
    ck(Badges.counts[cf1] == 0, "phase 1: counts start as REAL zeros, not nil (Class 5)")

    _G.FCF_SelectDockFrame(cf1)
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "seen live",
                  sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    HT.advance(0)
    ck(Badges.counts[cf1] == 0, "phase 1: delivery to the SELECTED tab never counts")
    local w1 = Badges.widgets[cf1]
    ck(w1 and w1.holder._shown == false, "phase 1: no badge rendered on the focused tab")

    -- ── Phase 2: a docked-but-unselected tab accrues; focus clears to a real 0.
    Sim.windows[3].shown, Sim.windows[3].docked = true, 3
    dock.DOCKED_CHAT_FRAMES[#dock.DOCKED_CHAT_FRAMES + 1] = cf3
    cf3:AddMessage("unseen 1", 1, 1, 1)
    cf3:AddMessage("unseen 2", 1, 1, 1)
    ck(Badges.counts[cf3] == 2, "phase 2: a docked unselected tab accrues unread")
    local w3 = Badges.widgets[cf3]
    ck(w3 and w3.holder._shown == true and w3.fs._text == "2",
        "phase 2: badge renders the count in ASCII digits")
    local mr = select(1, UI.Color("muted"))
    ck(w3.fs._textColor and math.abs(w3.fs._textColor[1] - mr) < 1e-6,
        "phase 2: quiet badge ink is the MUTED theme token")

    _G.FCF_SelectDockFrame(cf3)
    ck(Badges.counts[cf3] == 0 and type(Badges.counts[cf3]) == "number",
        "phase 2: focus clears to a REAL stored zero (the Class 5 pin)")
    ck(w3.holder._shown == false, "phase 2: cleared badge hides")
    cf3:AddMessage("now visible", 1, 1, 1)
    ck(Badges.counts[cf3] == 0, "phase 2: the now-selected tab does not count")
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase 3: a hidden undocked window accrues; OnShow clears. ────────────
    ck(not isDocked(cf4), "phase 3: probe window is undocked")
    cf4:Hide()
    for i = 1, 3 do cf4:AddMessage("while hidden " .. i, 1, 1, 1) end
    ck(Badges.counts[cf4] == 3, "phase 3: a hidden window accrues unread")
    cf4:Show()
    ck(Badges.counts[cf4] == 0, "phase 3: showing the window clears to zero")
    cf4:AddMessage("visible now", 1, 1, 1)
    ck(Badges.counts[cf4] == 0, "phase 3: a visible undocked window never counts")

    -- ── Phase 4: the count is honest past 99; only the DISPLAY caps. ─────────
    for i = 1, 120 do cf3:AddMessage("flood " .. i, 1, 1, 1) end
    ck(Badges.counts[cf3] == 120, "phase 4: the stored count stays exact (120)")
    ck(w3.fs._text == "99+", "phase 4: the display caps at 99+")
    _G.FCF_SelectDockFrame(cf3)
    ck(Badges.counts[cf3] == 0, "phase 4: clear resets the true count")
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase 5: whisper distinction (accent ink while a whisper is unread). ─
    -- Routing is scaffolding, not the pin: phases 5 and 7 stand on whisper/
    -- say/guild delivery to window 1, so construct those routes explicitly
    -- (idempotent) instead of assuming the fresh-login groups survived the
    -- converger suites (composition honesty).
    for _, grp in ipairs({ "WHISPER", "SAY", "GUILD" }) do
        _G.ChatFrame_AddMessageGroup(cf1, grp)
    end
    _G.FCF_SelectDockFrame(cf3)          -- cf1 is now docked-unselected
    Sim.SendChat{ event = "CHAT_MSG_WHISPER", text = "psst",
                  sender = "Choco", guid = "Player-1-00000002" }
    HT.advance(0)
    ck(Badges.counts[cf1] == 1, "phase 5: a whisper to an unfocused tab badges")
    ck(Badges.whisperFlag[cf1] == true, "phase 5: the whisper flag is up")
    local ar = select(1, UI.Color("accent"))
    ck(w1.fs._textColor and math.abs(w1.fs._textColor[1] - ar) < 1e-6,
        "phase 5: whisper unread wears the ACCENT token")
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "ambient",
                  sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    HT.advance(0)
    ck(Badges.counts[cf1] == 2, "phase 5: further lines keep counting")
    ck(math.abs(w1.fs._textColor[1] - ar) < 1e-6,
        "phase 5: accent holds while ANY whisper is unread")
    _G.FCF_SelectDockFrame(cf1)
    ck(Badges.counts[cf1] == 0 and Badges.whisperFlag[cf1] == nil,
        "phase 5: focus clears count AND whisper flag")
    _G.FCF_SelectDockFrame(cf3)
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "plain again",
                  sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    HT.advance(0)
    ck(math.abs(w1.fs._textColor[1] - mr) < 1e-6,
        "phase 5: plain unread is back to MUTED after the clear")
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase 6: per-window opt-out. ─────────────────────────────────────────
    ns.db.badges.optOut[3] = true
    cf3:AddMessage("never counted", 1, 1, 1)
    ck(Badges.counts[cf3] == 0, "phase 6: an opted-out window never counts")
    ck(w3.holder._shown == false, "phase 6: no badge rendered on an opted-out window")
    ns.db.badges.optOut[3] = nil

    -- ── Phase 7: group filter (whispers always badge). ───────────────────────
    ns.db.badges.filter = { GUILD = true }
    _G.FCF_SelectDockFrame(cf3)          -- cf1 unfocused again
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "filtered out",
                  sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    HT.advance(0)
    ck(Badges.counts[cf1] == 0, "phase 7: a group outside the filter does not badge")
    Sim.SendChat{ event = "CHAT_MSG_GUILD", text = "guild speaks",
                  sender = "Choco", guid = "Player-1-00000002" }
    HT.advance(0)
    ck(Badges.counts[cf1] == 1, "phase 7: an allowed group badges")
    Sim.SendChat{ event = "CHAT_MSG_WHISPER", text = "always",
                  sender = "Choco", guid = "Player-1-00000002" }
    HT.advance(0)
    ck(Badges.counts[cf1] == 2, "phase 7: whispers badge even outside the filter")
    ns.db.badges.filter = nil
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase 8: render collision pin — skin owns the tab, we own the badge. ─
    local tab = _G["ChatFrame3Tab"]
    ck(w3.fs ~= tab.Text, "phase 8: the badge FontString is NOT the tab's text")
    ck(w3.holder._parent == tab, "phase 8: the badge anchors to the tab as its own child")
    ck(tab.Text._textColor == nil,
        "phase 8: badges never inked the tab's own text (that is skin's)")
    -- The tab's alpha is the CLIENT's answer (noMouseAlpha / mouseOverAlpha,
    -- which the client's own updater picks between) or skin's pin over it —
    -- never ours. Pinned against the client's own computation rather than a
    -- literal 1, because the client actively fades an unfocused tab.
    ck(tab._alpha == (tab._mouseOver and tab.mouseOverAlpha or tab.noMouseAlpha)
        or tab._alpha == 1,
        "phase 8: badges never touched the tab's alpha (that is skin's)")

    -- ── Phase 9: temporary windows rig on open. ──────────────────────────────
    local temp = _G.FCF_OpenTemporaryWindow("WHISPER", "Puu")
    ck(Badges.hookedFrames[temp] == true, "phase 9: a temp window opened while active is rigged")
    temp:Hide()
    temp:AddMessage("hidden whisper tab", 1, 1, 1)
    ck(Badges.counts[temp] == 1, "phase 9: a hidden temp window accrues")
    Badges.Clear(temp)

    -- ── Phase 10: disable is inert; re-enable never double-counts. ───────────
    -- Same delta discipline as phase 0: siblings' subscriptions are theirs to
    -- hold; ours must return the count to the pre-enable baseline exactly.
    ns.SetModuleEnabled("badges", false)
    ck(ns.EventHandlerCount("CHAT_MSG_WHISPER") == whisperBase,
        "phase 10: event subscriptions given back on disable (count back to the pre-enable baseline)")
    _G.FCF_SelectDockFrame(cf3)
    cf1:AddMessage("while disabled", 1, 1, 1)
    ck(Badges.counts[cf1] == 0, "phase 10: a disabled module counts nothing")
    ck(w1.holder._shown == false, "phase 10: widgets hidden on disable")
    ns.SetModuleEnabled("badges", true)
    cf1:AddMessage("after re-enable", 1, 1, 1)
    ck(Badges.counts[cf1] == 1, "phase 10: re-enable counts each line exactly ONCE (no double wrap)")
    _G.FCF_SelectDockFrame(cf1)

    -- Tidy the world for the suites after us (skin runs next).
    for i = #dock.DOCKED_CHAT_FRAMES, 1, -1 do
        if dock.DOCKED_CHAT_FRAMES[i] == cf3 then table.remove(dock.DOCKED_CHAT_FRAMES, i) end
    end
    Sim.windows[3].shown, Sim.windows[3].docked = false, false
    Badges.Clear(cf3)
    Badges.Clear(cf4)
    HT.flush()
    Sim.ResetCalls()
end

ns:RegisterSelfTest("badges", function(verbose)
    local fails = {}
    local ok, err = pcall(testPure, fails)
    if not ok then fails[#fails + 1] = "pure error: " .. tostring(err) end
    ok, err = pcall(testLive, fails, verbose)
    if not ok then fails[#fails + 1] = "live error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL badges :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS badges") end
    return #fails == 0
end)

return Badges
