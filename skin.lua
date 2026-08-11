-- Daseeki Chat — skin.lua  (Wave 1 + skin v2, real)
-- The skin-over treatment of the client's ten chat windows: suite-themed frame
-- backdrops and tab styling, a themed ATTACHED edit box (the panel-bar look —
-- the survey's ElvUI archetype; NEVER a custom message view), Core font roles
-- applied to every window's text, configurable text fading, and the per-window
-- COPY-CHAT affordance (era has no clipboard: a themed window shows the frame's
-- visible text pre-selected in an edit box for Ctrl+C).
--
-- SKIN V2 — the padded-dark-panel evolution, four independently config-gated
-- features (db.skin.*, all additive, defaults ON except the rail):
--
--   1. CHANNEL-COLORED TABS (channelTabs, ON). Each tab's label ink derives
--      from the window's DOMINANT channel, resolved from the window's ROUTING
--      (the effective config's message groups + channels by name; a live
--      Config.CaptureWindow when the config has no entry yet). Dominance is
--      strict: exactly ONE identity survives the walk or there is none. The
--      colors come from the CLIENT's own chat color table (GetMessageTypeColor
--      -> ChatTypeInfo, catalog-verified 11509), so they cooperate with the
--      player's color settings and move live on UPDATE_CHAT_COLOR (our own
--      gated listener — never coupled to another module's). Active tab: full
--      strength ink + the suite's accent underline. Inactive: the same ink
--      dimmed by a TOKEN-DERIVED factor (muted/text luminance — a theme change
--      moves it). No dominant channel -> the accent/muted token treatment,
--      which is Wave 1's behavior, PINNED as the fallback.
--   2. TIMESTAMP DIVIDER (stampDivider, ON). A theme border-token hairline
--      between the stamp column and the message text, present only while
--      stamps.lua is actually stamping. Coordination with stamps is READ-ONLY
--      and by MEASUREMENT: the stamp column is measured with a probe
--      FontString wearing the window's own font, never computed from stamps'
--      internals.
--   3. EDIT-BOX CHANNEL PREFIX (editBoxChannelColor, ON). The attached edit
--      box's sticky-channel header wears that channel's client color, hooked
--      on ChatEdit_UpdateHeader the way the tab ink hooks FCF_SelectDockFrame.
--   4. ICON RAIL (iconRail, OFF — the speculative one). A slim themed strip on
--      the window's left edge carrying ONLY verbs Chat already owns:
--      copy-chat (Skin.OpenCopy), settings (ns.SlashDispatch) and the client's
--      own frame:ScrollToBottom. No new features hide behind these buttons.
--
-- Everything visual reads Daseeki-Core theme tokens at render (DaseekiUI.Color/
-- Token / FLAT_BACKDROP / UI.Skin / UI.fonts / UI.FontFile) — ZERO hardcoded
-- colors anywhere in this file; alpha/measure constants only. The one family
-- of colors that is NOT a token is the CLIENT's chat colors, which are read
-- live from the client's table on every render (a hardcoded green would stop
-- tracking the player's own settings, and the suite pins exactly that).
--
-- INERTNESS (the suite discipline, and the harness's pin): this module touches
-- NOTHING until its OnEnable runs — no hooks, no texture strips, no frames.
-- OnDisable restores what it changed and goes quiet. The two irreversible
-- client mechanisms (hooksecurefunc has no un-hook) are installed once, on the
-- FIRST enable, and their bodies gate on Skin.active.
--
-- All display glyphs in this file are ASCII (the tofu lesson: any non-ASCII
-- glyph must be verified against the vendored face's cmap first).

local ADDON, ns = ...

local Skin = {
    active  = false,   -- gate for every hook body and event handler
    hooked  = false,   -- one-time hooksecurefunc installs done
    styled  = {},      -- frame -> per-frame rig record
    order   = {},      -- styled frames in style order (stable iteration)
}
ns.Skin = Skin

-- Layout constants (measures, not colors).
local BG_ALPHA    = 0.85   -- chat backdrop fill alpha over the world
local PAD         = 4      -- backdrop overhang around the message area
local EB_HEIGHT   = 24     -- attached edit box bar height
local EB_GAP      = 2      -- gap between chat frame and the edit box bar
local TAB_DIM     = 0.6    -- unselected docked tab alpha (survey: ElvUI behavior)
local COPY_IDLE   = 0.35   -- copy affordance alpha until hovered
local COPY_MAX    = 512    -- copy window: max lines pulled from a frame
local UL_HEIGHT   = 2      -- active-tab accent underline thickness
local UL_INSET    = 4      -- underline inset from each tab edge (never under the badge)
local UL_Y        = 1      -- underline lift off the tab's bottom edge
local DIV_WIDTH   = 1      -- timestamp divider hairline width
local DIV_GAP     = 2      -- gap between the stamp column and the hairline
local DIV_ALPHA   = 0.55   -- hairline alpha (subtle, per the reference)
local RAIL_WIDTH  = 16     -- icon rail strip width
local RAIL_BTN    = 16     -- one rail button's square edge
local RAIL_GAP    = 2      -- gap between the rail and the window
local RAIL_IDLE   = 0.35   -- rail alpha until hovered

-- Skin v2 config fields, declared ADDITIVELY from this module (the badges.lua
-- precedent) so core.lua's DEFAULTS block stays this module's business only.
-- EnsureDefaults runs at DB_READY, after every file has loaded.
ns.DEFAULTS.skin.channelTabs         = true   -- tab ink from the window's channel
ns.DEFAULTS.skin.stampDivider        = true   -- hairline between stamps and text
ns.DEFAULTS.skin.editBoxChannelColor = true   -- edit-box header in channel color
ns.DEFAULTS.skin.iconRail            = false  -- left-edge affordance rail (opt-in)

local function UIKit() return _G.DaseekiUI end

local function cfg()
    return (ns.db and ns.db.skin) or ns.DEFAULTS.skin
end

----------------------------------------------------------------------
-- Window enumeration. The client's model is fixed: ChatFrame1..NUM_CHAT_WINDOWS
-- permanent windows (2 = combat log) plus temporary frames past index 10.
-- We style windows that are shown OR docked; a window the player has closed
-- stays untouched until the client shows it (temp-window hook catches those).
----------------------------------------------------------------------

local function numWindows() return _G.NUM_CHAT_WINDOWS or 10 end

local function isCombatLog(frame, id)
    local f = _G.IsCombatLog
    if type(f) == "function" then
        local ok, res = pcall(f, frame)
        if ok then return res and true or false end
    end
    return id == 2   -- runtime-defended fallback: ChatFrame2 is the combat log
end

local function windowEligible(id)
    -- GetChatWindowInfo returns: name, fontSize, r, g, b, alpha, shown, locked,
    -- docked, uninteractable (era 11509 shape; arity defended at runtime).
    local gcwi = _G.GetChatWindowInfo
    if type(gcwi) ~= "function" then return false end
    local ok, name, fontSize, _, _, _, _, shown, _, docked = pcall(gcwi, id)
    if not ok then return false end
    return (shown and shown ~= 0) or (docked and docked ~= 0), name, fontSize
end

----------------------------------------------------------------------
-- CHANNEL IDENTITY (skin v2 feature 1, the headline).
--
-- Two pure steps, both harness-tested directly:
--   DominantChannel(entry, isCombatLog)  routing  -> identity, or nothing
--   ChannelInk(kind, value)              identity -> the CLIENT's color
--
-- The dominance rule is deliberately STRICT: a window earns a channel ink only
-- when its routing collapses to exactly ONE identity. The client's default
-- window routes a dozen groups and therefore has none — it keeps the suite's
-- token treatment, which is the Wave-1 look and the pinned fallback.
--
-- AMBIENT groups (system chatter, loot, combat spam, skill-ups) never
-- establish identity: they ride along in a window that is otherwise plainly a
-- guild window, and counting them would make every real window "multi".
-- FAMILY groups fold onto their head (OFFICER is guild chat; RAID_LEADER is
-- raid chat), so a Guild tab routing GUILD+OFFICER is still a guild tab.
----------------------------------------------------------------------

local AMBIENT_GROUPS = {
    SYSTEM = true, ERRORS = true, LOOT = true, MONEY = true, CURRENCY = true,
    SKILL = true, OPENING = true, PET_INFO = true, TRADESKILLS = true,
    ACHIEVEMENT = true, GUILD_ACHIEVEMENT = true, TARGETICONS = true,
    IGNORED = true, AFK = true, DND = true, COMBAT_XP_GAIN = true,
    COMBAT_HONOR_GAIN = true, COMBAT_FACTION_CHANGE = true,
    COMBAT_MISC_INFO = true, BG_SYSTEM_NEUTRAL = true, BG_SYSTEM_ALLIANCE = true,
    BG_SYSTEM_HORDE = true, MONSTER_BOSS_EMOTE = true, MONSTER_BOSS_WHISPER = true,
    MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_EMOTE = true,
    MONSTER_WHISPER = true, MONSTER_PARTY = true,
}

local GROUP_FAMILY = {
    OFFICER              = "GUILD",
    PARTY_LEADER         = "PARTY",
    RAID_LEADER          = "RAID",
    RAID_WARNING         = "RAID",
    INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    WHISPER_INFORM       = "WHISPER",
    BN_WHISPER           = "WHISPER",
    BN_WHISPER_INFORM    = "WHISPER",
}

-- PURE. entry = a config-shaped window entry ({ groups = {...}, channels = {...} }).
-- Returns "combatlog" | ("type", CHATTYPE) | ("channel", name) | nil.
function Skin.DominantChannel(entry, combatLog)
    if combatLog then return "combatlog" end
    if type(entry) ~= "table" then return nil end
    local seen, found = {}, {}
    local function add(key, kind, value)
        if seen[key] then return end
        seen[key] = true
        found[#found + 1] = { kind = kind, value = value }
    end
    for _, g in ipairs(entry.groups or {}) do
        if type(g) == "string" and g ~= "" then
            local up = g:upper()
            -- The CHANNEL group is the routing SWITCH for named channels, not
            -- an identity of its own; the names below carry that identity.
            if up ~= "CHANNEL" and not AMBIENT_GROUPS[up] then
                local head = GROUP_FAMILY[up] or up
                add("TYPE:" .. head, "type", head)
            end
        end
    end
    for _, c in ipairs(entry.channels or {}) do
        if type(c) == "string" and c ~= "" then
            add("CHAN:" .. c:lower(), "channel", c)
        end
    end
    if #found == 1 then return found[1].kind, found[1].value end
    return nil
end

-- The CLIENT's color for a chat type. Primary read is GetMessageTypeColor
-- (catalog 11509); ChatTypeInfo is the runtime-defended fallback, and a
-- non-numeric answer from either is treated as NO answer (never a silent
-- white). Returns r, g, b or nil.
function Skin.TypeColor(chatType)
    if type(chatType) ~= "string" or chatType == "" then return nil end
    local f = _G.GetMessageTypeColor
    if type(f) == "function" then
        local ok, r, g, b = pcall(f, chatType)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    local CTI = _G.ChatTypeInfo
    local info = type(CTI) == "table" and CTI[chatType] or nil
    if type(info) == "table" and type(info.r) == "number"
        and type(info.g) == "number" and type(info.b) == "number" then
        return info.r, info.g, info.b
    end
    return nil
end

-- A named (or numbered) channel's color. The client keys channel colors by
-- NUMBER and numbers move, so a name is resolved through GetChannelName every
-- time — the same by-name discipline channels.lua uses for imposition.
function Skin.ChannelColorOf(nameOrNumber)
    local n = tonumber(nameOrNumber)
    if not n and type(nameOrNumber) == "string" and nameOrNumber ~= "" then
        local f = _G.GetChannelName
        if type(f) == "function" then
            local ok, num = pcall(f, nameOrNumber)
            if ok then n = tonumber(num) end
        end
    end
    if n and n > 0 then
        local r, g, b = Skin.TypeColor("CHANNEL" .. n)
        if r then return r, g, b end
    end
    return Skin.TypeColor("CHANNEL")   -- un-joined / unnumbered: the generic ink
end

function Skin.ChannelInk(kind, value)
    if kind == "type" then return Skin.TypeColor(value) end
    if kind == "channel" then return Skin.ChannelColorOf(value) end
    return nil
end

-- The inactive-tab dim, DERIVED FROM TOKENS (never a hardcoded alpha): the
-- muted token's share of the muted+text luminance, mapped into a sane band.
-- The mapping cannot clamp, so a theme change always moves the answer — which
-- is what makes the harness assertion impossible to satisfy with a constant.
local DIM_FLOOR, DIM_SPAN = 0.30, 0.60

local function luminance(r, g, b)
    return 0.2126 * (tonumber(r) or 0) + 0.7152 * (tonumber(g) or 0)
         + 0.0722 * (tonumber(b) or 0)
end

function Skin.DimFactor()
    local UI = UIKit()
    if not UI or type(UI.Color) ~= "function" then return DIM_FLOOR + DIM_SPAN * 0.5 end
    local lm = luminance(UI.Color("muted"))
    local lt = luminance(UI.Color("text"))
    local total = lm + lt
    if total <= 0 then return DIM_FLOOR + DIM_SPAN * 0.5 end
    return DIM_FLOOR + DIM_SPAN * (lm / total)
end

-- The routing a window is judged on: the EFFECTIVE config's entry when the
-- config speaks about this window (config is authoritative — design rule 1),
-- otherwise a live capture of the client store (a fresh install, before any
-- adopt, still gets colored tabs). Returns entry, source.
function Skin.WindowRouting(id)
    if not id then return nil, nil end
    local C = ns.Config
    if not C then return nil, nil end
    if type(C.EffectiveCfg) == "function" then
        local ok, eff = pcall(C.EffectiveCfg)
        local w = ok and type(eff) == "table" and type(eff.windows) == "table"
            and eff.windows[id] or nil
        if type(w) == "table" and (type(w.groups) == "table" or type(w.channels) == "table") then
            return w, "config"
        end
    end
    if type(C.CaptureWindow) == "function" then
        local ok, cap = pcall(C.CaptureWindow, id)
        if ok and type(cap) == "table" then return cap, "client" end
    end
    return nil, nil
end

-- One tab's ink at full strength, plus where it came from. A temporary window
-- (a whisper pop-out) carries its own routing on the frame, which is the only
-- routing it will ever have. Returns r, g, b, source.
function Skin.TabInk(frame, id)
    local UI = UIKit()
    if not UI then return nil end
    if not cfg().channelTabs then return nil end
    if isCombatLog(frame, id) then
        local r, g, b = UI.Color("muted")
        return r, g, b, "combatlog"
    end
    if frame and frame.isTemporary and type(frame.chatType) == "string" and frame.chatType ~= "" then
        local head = GROUP_FAMILY[frame.chatType:upper()] or frame.chatType:upper()
        local r, g, b = Skin.TypeColor(head)
        if r then return r, g, b, "temporary" end
        return nil
    end
    local entry = Skin.WindowRouting(id)
    local kind, value = Skin.DominantChannel(entry, false)
    if not kind then return nil end
    local r, g, b = Skin.ChannelInk(kind, value)
    if not r then return nil end
    return r, g, b, kind
end

----------------------------------------------------------------------
-- Copy-chat text extraction (PURE — the harness tests this directly).
--
-- Reads the frame's visible history through the PUBLIC message-history surface
-- (GetNumMessages / GetMessageInfo — the game-facts register's sanctioned read;
-- the underlying ring buffer is the same store the client renders from).
-- Hyperlinks are DEFANGED for display: |H...|h markup drops to its visible
-- text, colors strip, |K protected spans become "???" (they cannot be
-- string-copied meaningfully), textures drop (raid-target icons reverse-map to
-- their {rt#} chat tags so the copyable text round-trips).
----------------------------------------------------------------------

function Skin.DefangLine(text)
    if type(text) ~= "string" then return "" end
    local s = text
    -- Battle.net protected spans first (atomic; nothing inside is copyable).
    s = s:gsub("|K.-|k", "???")
    -- Hyperlinks: keep the display text, drop the click payload. Non-greedy so
    -- multiple links on one line each collapse independently.
    s = s:gsub("|H.-|h(.-)|h", "%1")
    -- Raid-target icon textures reverse-map to their typeable tags...
    s = s:gsub("|T[^|]-RaidTargetingIcon_(%d+)[^|]-|t", "{rt%1}")
    -- ...every other texture escape just drops.
    s = s:gsub("|T.-|t", "")
    -- Color escapes strip.
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Escaped pipes un-escape last, once the markup passes above are done.
    s = s:gsub("||", "|")
    return s
end

function Skin.ExtractCopyText(frame, maxLines)
    maxLines = maxLines or COPY_MAX
    local lines = {}
    if not frame or type(frame.GetNumMessages) ~= "function" then return lines end
    local n = frame:GetNumMessages() or 0
    local first = math.max(1, n - maxLines + 1)
    for i = first, n do
        -- GetMessageInfo(i): index 1 is the OLDEST stored line; returns arrive
        -- oldest-to-newest, which is the reading order the copy window wants.
        local ok, msg = pcall(frame.GetMessageInfo, frame, i)
        if ok and type(msg) == "string" then
            lines[#lines + 1] = Skin.DefangLine(msg)
        end
    end
    return lines
end

----------------------------------------------------------------------
-- Fonts. Face comes from Core's picked face (UI.FontFile — already guarded by
-- Core's render-proof probe); SIZE stays per-window in the client's own store
-- (the survey's ElvUI split: the Blizzard right-click size menu keeps working).
----------------------------------------------------------------------

local function applyFrameFont(frame, id)
    local UI = UIKit()
    if not UI or type(frame.SetFont) ~= "function" then return end
    local rec = Skin.styled[frame]
    -- Save the original face once, so disable can hand it back.
    if rec and not rec.origFont and type(frame.GetFont) == "function" then
        local okg, face, size, flags = pcall(frame.GetFont, frame)
        if okg and face then rec.origFont = { face, size, flags } end
    end
    local _, name, fontSize = windowEligible(id)
    local size = tonumber(fontSize)
    if not size or size <= 0 then size = 14 end   -- truthy-zero guard (Class 5)
    pcall(frame.SetFont, frame, UI.FontFile(), size, "")
end

----------------------------------------------------------------------
-- Fading. Config-driven; both knobs live in db.skin.
----------------------------------------------------------------------

function Skin.ApplyFading(frame)
    local c = cfg()
    if type(frame.SetFading) == "function" then
        pcall(frame.SetFading, frame, c.fading and true or false)
    end
    if c.fading and type(frame.SetTimeVisible) == "function" then
        pcall(frame.SetTimeVisible, frame, tonumber(c.fadeTime) or 100)
    end
end

----------------------------------------------------------------------
-- Stock texture strip / restore. The client lists every chat-frame dress
-- texture suffix in the CHAT_FRAME_TEXTURES global; regions live at
-- _G[frameName .. suffix]. We alpha them to 0 (restorable) rather than nil
-- their textures (not restorable).
----------------------------------------------------------------------

local FALLBACK_TEXTURES = {
    "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture",
    "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture",
    "BottomTexture",
}

local function stockTextureNames()
    local t = _G.CHAT_FRAME_TEXTURES
    if type(t) == "table" and #t > 0 then return t end
    return FALLBACK_TEXTURES
end

local function stripStock(frame, rec)
    local name = frame.GetName and frame:GetName()
    if not name then return end
    rec.stock = rec.stock or {}
    for _, suffix in ipairs(stockTextureNames()) do
        local region = _G[name .. suffix]
        if region and type(region.SetAlpha) == "function" then
            if rec.stock[suffix] == nil then
                local okA, a = pcall(region.GetAlpha, region)
                rec.stock[suffix] = okA and a or 1
            end
            pcall(region.SetAlpha, region, 0)
        end
    end
end

local function restoreStock(frame, rec)
    local name = frame.GetName and frame:GetName()
    if not name or not rec.stock then return end
    for suffix, alpha in pairs(rec.stock) do
        local region = _G[name .. suffix]
        if region and type(region.SetAlpha) == "function" then
            pcall(region.SetAlpha, region, alpha)
        end
    end
end

----------------------------------------------------------------------
-- Backdrop: one flat token-colored panel behind each window (Core's
-- FLAT_BACKDROP shape; UI.Skin keeps it re-coloring on every theme change).
----------------------------------------------------------------------

local function ensureBackdrop(frame, rec)
    local UI = UIKit()
    if not UI or rec.backdrop then
        if rec.backdrop then rec.backdrop:Show() end
        return
    end
    local bd = _G.CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bd:SetPoint("TOPLEFT", frame, "TOPLEFT", -PAD, PAD)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PAD, -PAD)
    if bd.SetFrameLevel and frame.GetFrameLevel then
        local okL, lvl = pcall(frame.GetFrameLevel, frame)
        pcall(bd.SetFrameLevel, bd, math.max(0, (okL and lvl or 1) - 1))
    end
    UI.Skin(bd, function(self)
        if type(self.SetBackdrop) == "function" then self:SetBackdrop(UI.FLAT_BACKDROP) end
        if type(self.SetBackdropColor) == "function" then
            self:SetBackdropColor(UI.Color("panel", BG_ALPHA))
        end
        if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(UI.Color("border"))
        end
    end)
    rec.backdrop = bd
end

----------------------------------------------------------------------
-- Tabs. The Blizzard tab stays the click surface (skin-over, never replace);
-- we restyle its text through the Core small font role, ink it from the
-- window's dominant channel (skin v2 feature 1), underline the active tab in
-- the suite accent, and dim the unselected docked tabs — selection tracked via
-- the FCF_SelectDockFrame hook below.
--
-- BADGE COORDINATION (badges.lua owns the unread counter): the counter is its
-- own FontString on its own holder, anchored OFF the tab's right edge. Every
-- surface added here is INSIDE the tab — the ink is the tab's own text, the
-- underline is inset from both tab edges — so the badge's anchor and ink are
-- untouched no matter what color the tab takes. The skin suite pins that.
----------------------------------------------------------------------

local function tabText(frame)
    local name = frame.GetName and frame:GetName()
    if not name then return nil, nil end
    local tab = _G[name .. "Tab"]
    if not tab then return nil, nil end
    return tab, (tab.Text or _G[name .. "TabText"])
end

local function selectedDockFrame()
    local dock = _G.GeneralDockManager
    return dock and dock.selected or nil
end

local function ensureUnderline(tab, rec)
    if rec.underline then return rec.underline end
    local UI = UIKit()
    if not (UI and type(tab.CreateTexture) == "function") then return nil end
    local tex = tab:CreateTexture(nil, "OVERLAY")
    -- Inset from BOTH tab edges: the badge sits past the tab's right edge and
    -- must never be crossed by this line.
    tex:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", UL_INSET, UL_Y)
    tex:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -UL_INSET, UL_Y)
    if type(tex.SetHeight) == "function" then tex:SetHeight(UL_HEIGHT) end
    UI.Skin(tex, function(self)
        if type(self.SetColorTexture) == "function" then
            self:SetColorTexture(UI.Color("accent"))
        end
    end)
    tex:Hide()
    rec.underline = tex
    return tex
end

function Skin.UpdateTabColors()
    local UI = UIKit()
    if not UI then return end
    local sel = selectedDockFrame()
    local dim = Skin.DimFactor()
    local channelTabs = cfg().channelTabs and true or false
    for _, frame in ipairs(Skin.order) do
        local tab, text = tabText(frame)
        local rec = Skin.styled[frame]
        if tab and text then
            local isSel = (frame == sel)
            local r, g, b, source
            if channelTabs then
                r, g, b, source = Skin.TabInk(frame, rec and rec.id)
            end
            if r then
                -- Active: full strength. Inactive: the SAME channel ink, dimmed
                -- through the token-derived factor (never a second color).
                if not isSel then r, g, b = r * dim, g * dim, b * dim end
            else
                r, g, b = UI.Color(isSel and "accent" or "muted")
                source = "token"
            end
            if rec then rec.inkSource = source end
            if type(text.SetTextColor) == "function" then
                text:SetTextColor(r, g, b)
            end
            if type(tab.SetAlpha) == "function" then
                tab:SetAlpha(isSel and 1 or TAB_DIM)
            end
            if rec then
                local ul = channelTabs and ensureUnderline(tab, rec) or rec.underline
                if ul then
                    if channelTabs and isSel then ul:Show() else ul:Hide() end
                end
            end
        end
    end
end

local function styleTab(frame, rec)
    local UI = UIKit()
    if not UI then return end
    local tab, text = tabText(frame)
    if not (tab and text) then return end
    if type(text.SetFontObject) == "function" then
        text:SetFontObject(UI.fonts.small)
    end
    -- Save the tab's original ink once so a disable can hand it back (the
    -- client does not always expose GetTextColor; when it does not, the tab
    -- simply keeps the last ink, which is Wave 1's behavior).
    if not rec.origTabColor and type(text.GetTextColor) == "function" then
        local ok, r, g, b = pcall(text.GetTextColor, text)
        if ok and type(r) == "number" then rec.origTabColor = { r, g, b } end
    end
    rec.tabStyled = true
end

----------------------------------------------------------------------
-- TIMESTAMP DIVIDER (skin v2 feature 2).
--
-- A theme border-token hairline between the stamp column and the message text,
-- shown ONLY while stamps.lua is actually stamping (module active and not
-- suspended behind the client's native timestamps).
--
-- Coordination with stamps is READ-ONLY and by MEASUREMENT, never by coupling:
-- we read the one CONFIG field that decides how wide a stamp is (db.stamps
-- .format), render its widest literal shape into a probe FontString wearing
-- THIS window's font, and place the hairline past the measured width. Nothing
-- calls into stamps, and stamps knows nothing about this.
----------------------------------------------------------------------

-- The widest literal a format can produce (digits are the same width class as
-- the sample zeros; the trailing space is the separator stamps writes).
local STAMP_SAMPLES = {
    ["HH:MM"]    = "[00:00] ",
    ["HH:MM:SS"] = "[00:00:00] ",
    ["hh:MM"]    = "[00:00 PM] ",
    ["hh:MM:SS"] = "[00:00:00 PM] ",
}

function Skin.StampSample()
    local s = ns.db and ns.db.stamps
    local fmt = type(s) == "table" and s.format or nil
    return STAMP_SAMPLES[fmt] or STAMP_SAMPLES["HH:MM"]
end

-- Is a stamp actually being written right now? (Read-only observation of the
-- sibling module's public state — the divider must never appear over
-- unstamped text.)
function Skin.StampsShowing()
    local S = ns.Stamps
    if type(S) ~= "table" then return false end
    return (S.active == true and S.suspended ~= true) and true or false
end

function Skin.MeasureStampColumn(frame, rec)
    if not (frame and rec) then return 0 end
    local probe = rec.stampProbe
    if not probe then
        local host = rec.backdrop or frame
        if type(host.CreateFontString) ~= "function" then return 0 end
        probe = host:CreateFontString(nil, "ARTWORK")
        probe:Hide()
        rec.stampProbe = probe
    end
    -- The window's own font, so the measurement is the window's own metrics.
    if type(frame.GetFont) == "function" and type(probe.SetFont) == "function" then
        local ok, face, size, flags = pcall(frame.GetFont, frame)
        if ok and face then pcall(probe.SetFont, probe, face, size, flags) end
    end
    if type(probe.SetText) == "function" then probe:SetText(Skin.StampSample()) end
    if type(probe.GetStringWidth) ~= "function" then return 0 end
    local ok, w = pcall(probe.GetStringWidth, probe)
    return (ok and tonumber(w)) or 0
end

function Skin.UpdateDivider(frame)
    local rec = Skin.styled[frame]
    if not rec then return end
    local on = Skin.active and cfg().stampDivider and Skin.StampsShowing()
    if not on then
        if rec.divider then rec.divider:Hide() end
        return
    end
    local UI = UIKit()
    if not UI then return end
    local x = Skin.MeasureStampColumn(frame, rec) + DIV_GAP
    local div = rec.divider
    if not div then
        local host = rec.backdrop or frame
        if type(host.CreateTexture) ~= "function" then return end
        div = host:CreateTexture(nil, "BORDER")
        if type(div.SetWidth) == "function" then div:SetWidth(DIV_WIDTH) end
        UI.Skin(div, function(self)
            if type(self.SetColorTexture) == "function" then
                self:SetColorTexture(UI.Color("border", DIV_ALPHA))
            end
        end)
        rec.divider = div
    end
    if type(div.ClearAllPoints) == "function" then
        div:ClearAllPoints()
        div:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        div:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 0)
    end
    rec.dividerX = x
    div:Show()
end

function Skin.UpdateDividers()
    for _, frame in ipairs(Skin.order) do Skin.UpdateDivider(frame) end
end

----------------------------------------------------------------------
-- Edit box: the attached panel-bar look (survey archetype). Re-anchored as a
-- bar spanning the window's width, below or above per config; stock art
-- stripped; a flat token backdrop behind it; Core body font.
--
-- SKIN V2 feature 3 lives here too: the sticky-channel HEADER ("Guild:",
-- "2. World:") wears that channel's client color, applied on the client's own
-- ChatEdit_UpdateHeader beat (hooked once, gated) so it follows every sticky
-- change, tab-cycle and /channel switch without us tracking state.
----------------------------------------------------------------------

local EB_REGIONS = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function editBoxOf(frame)
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. "EditBox"] or nil
end

-- The header FontString the client writes the sticky-channel prefix into.
-- Both shapes are defended: the field the client's own code reaches for, and
-- the $parentHeader global the template names it.
local function editBoxHeader(eb)
    if type(eb) ~= "table" then return nil end
    if type(eb.header) == "table" then return eb.header end
    local n = eb.GetName and eb:GetName()
    return (n and _G[n .. "Header"]) or nil
end

-- The edit box's sticky chat state, through the client's accessor first and
-- the attribute bag second (both catalog-verified on 11509).
local function editBoxAttr(eb, accessor, attribute)
    if type(eb) ~= "table" then return nil end
    local f = _G[accessor]
    if type(f) == "function" then
        local ok, v = pcall(f, eb)
        if ok and v ~= nil and v ~= "" then return v end
    end
    if type(eb.GetAttribute) == "function" then
        local ok, v = pcall(eb.GetAttribute, eb, attribute)
        if ok and v ~= nil and v ~= "" then return v end
    end
    local direct = eb[attribute]
    if direct ~= nil and direct ~= "" then return direct end
    return nil
end

local function savePoints(widget)
    if type(widget.GetNumPoints) ~= "function" or type(widget.GetPoint) ~= "function" then return nil end
    local okN, n = pcall(widget.GetNumPoints, widget)
    if not okN or not n then return nil end
    local pts = {}
    for i = 1, n do
        local okP, p, rel, rp, x, y = pcall(widget.GetPoint, widget, i)
        if okP and p then pts[#pts + 1] = { p, rel, rp, x, y } end
    end
    return pts
end

local function restorePoints(widget, pts)
    if not pts or type(widget.ClearAllPoints) ~= "function" then return end
    pcall(widget.ClearAllPoints, widget)
    for _, pt in ipairs(pts) do
        pcall(widget.SetPoint, widget, pt[1], pt[2], pt[3], pt[4], pt[5])
    end
end

local function styleEditBox(frame, rec)
    local UI = UIKit()
    local eb = editBoxOf(frame)
    if not (UI and eb) then return end
    local ebName = eb.GetName and eb:GetName()

    -- Original state saved once for restore-on-disable.
    if not rec.ebPoints then rec.ebPoints = savePoints(eb) end
    rec.ebStock = rec.ebStock or {}
    if ebName then
        for _, suffix in ipairs(EB_REGIONS) do
            local region = _G[ebName .. suffix]
            if region and type(region.SetAlpha) == "function" then
                if rec.ebStock[suffix] == nil then
                    local okA, a = pcall(region.GetAlpha, region)
                    rec.ebStock[suffix] = okA and a or 1
                end
                pcall(region.SetAlpha, region, 0)
            end
        end
    end

    -- Attach as a bar: full window width, below (default) or above.
    if type(eb.ClearAllPoints) == "function" then
        pcall(eb.ClearAllPoints, eb)
        if (cfg().editBox or "BOTTOM"):upper() == "TOP" then
            pcall(eb.SetPoint, eb, "BOTTOMLEFT", frame, "TOPLEFT", -PAD, EB_GAP + PAD)
            pcall(eb.SetPoint, eb, "BOTTOMRIGHT", frame, "TOPRIGHT", PAD, EB_GAP + PAD)
        else
            pcall(eb.SetPoint, eb, "TOPLEFT", frame, "BOTTOMLEFT", -PAD, -(EB_GAP + PAD))
            pcall(eb.SetPoint, eb, "TOPRIGHT", frame, "BOTTOMRIGHT", PAD, -(EB_GAP + PAD))
        end
    end
    if type(eb.SetHeight) == "function" then pcall(eb.SetHeight, eb, EB_HEIGHT) end

    -- Flat themed panel behind the input (control-surface tokens: this is an
    -- input, so it steps up from the window's panel ground).
    if not rec.ebSkin then
        local bg = _G.CreateFrame("Frame", nil, eb, "BackdropTemplate")
        bg:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 0)
        if bg.SetFrameLevel and eb.GetFrameLevel then
            local okL, lvl = pcall(eb.GetFrameLevel, eb)
            pcall(bg.SetFrameLevel, bg, math.max(0, (okL and lvl or 1) - 1))
        end
        UI.Skin(bg, function(self)
            if type(self.SetBackdrop) == "function" then self:SetBackdrop(UI.FLAT_BACKDROP) end
            if type(self.SetBackdropColor) == "function" then
                self:SetBackdropColor(UI.Color("inset"))
            end
            if type(self.SetBackdropBorderColor) == "function" then
                self:SetBackdropBorderColor(UI.Color("controlBorder"))
            end
        end)
        rec.ebSkin = bg
    else
        rec.ebSkin:Show()
    end

    if type(eb.SetFontObject) == "function" then
        pcall(eb.SetFontObject, eb, UI.fonts.body)
    end
    if type(eb.SetTextInsets) == "function" then
        pcall(eb.SetTextInsets, eb, 8, 8, 0, 0)
    end

    -- The sticky-channel prefix belongs to the bar's typography too.
    local header = rec.ebHeader
    if not header then
        header = editBoxHeader(eb)
        rec.ebHeader = header
    end
    if header and type(header.SetFontObject) == "function" then
        pcall(header.SetFontObject, header, UI.fonts.small)
    end
end

-- Ink the sticky-channel header. Returns r, g, b when it painted (the harness
-- reads the return; the client ignores it).
function Skin.ColorEditBoxHeader(eb)
    if not Skin.active or not cfg().editBoxChannelColor then return nil end
    local header = editBoxHeader(eb)
    if not header or type(header.SetTextColor) ~= "function" then return nil end
    local chatType = editBoxAttr(eb, "ChatEdit_GetActiveChatType", "chatType")
    if type(chatType) ~= "string" or chatType == "" then return nil end
    chatType = chatType:upper()
    local r, g, b
    if chatType == "CHANNEL" then
        local target = editBoxAttr(eb, "ChatEdit_GetChannelTarget", "channelTarget")
        r, g, b = Skin.ChannelColorOf(target)
    else
        r, g, b = Skin.TypeColor(GROUP_FAMILY[chatType] or chatType)
    end
    if not r then return nil end
    header:SetTextColor(r, g, b)
    return r, g, b
end

function Skin.RecolorEditBoxHeaders()
    for _, frame in ipairs(Skin.order) do
        local eb = editBoxOf(frame)
        if eb then Skin.ColorEditBoxHeader(eb) end
    end
end

local function restoreEditBox(frame, rec)
    local eb = editBoxOf(frame)
    if not eb then return end
    local ebName = eb.GetName and eb:GetName()
    if ebName and rec.ebStock then
        for suffix, alpha in pairs(rec.ebStock) do
            local region = _G[ebName .. suffix]
            if region and type(region.SetAlpha) == "function" then
                pcall(region.SetAlpha, region, alpha)
            end
        end
    end
    restorePoints(eb, rec.ebPoints)
    if rec.ebSkin then rec.ebSkin:Hide() end
end

----------------------------------------------------------------------
-- The copy-chat affordance: a quiet per-window button (ASCII label) that opens
-- the shared copy window. The copy window is one themed frame holding the
-- extracted text in a multiline edit box, focused and pre-highlighted — the
-- only copy path that exists on era.
----------------------------------------------------------------------

local copyWindow   -- shared; built lazily on first use

local function ensureCopyWindow()
    local UI = UIKit()
    if copyWindow or not UI then return copyWindow end

    local f = _G.CreateFrame("Frame", "DaseekiChatCopyWindow", _G.UIParent, "BackdropTemplate")
    f:SetSize(560, 380)
    f:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 40)
    if f.SetFrameStrata then pcall(f.SetFrameStrata, f, "DIALOG") end
    if f.SetMovable then
        pcall(f.SetMovable, f, true)
        pcall(f.EnableMouse, f, true)
        if f.RegisterForDrag then pcall(f.RegisterForDrag, f, "LeftButton") end
        f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    end
    UI.Skin(f, function(self)
        if type(self.SetBackdrop) == "function" then self:SetBackdrop(UI.FLAT_BACKDROP) end
        if type(self.SetBackdropColor) == "function" then
            self:SetBackdropColor(UI.Color("ground"))
        end
        if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(UI.Color("borderLite"))
        end
    end)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(UI.fonts.header)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("Copy chat")
    f._title = title

    local closeBtn = UI.MakeButton(f, {
        text = "Close", variant = "quiet", width = 70,
        onClick = function() f:Hide() end,
    })
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)

    -- The text surface: a scrollable multiline edit box on an inset panel.
    local panel = UI.FlatFrame(f, "inset", "border")
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

    local scroll = _G.CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 6)

    local edit = _G.CreateFrame("EditBox", nil, scroll)
    if edit.SetMultiLine then pcall(edit.SetMultiLine, edit, true) end
    if edit.SetAutoFocus then pcall(edit.SetAutoFocus, edit, false) end
    if edit.SetFontObject then pcall(edit.SetFontObject, edit, UI.fonts.body) end
    if edit.SetWidth then pcall(edit.SetWidth, edit, 500) end
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- The text is a read-back surface: typing must not corrupt it, so any
    -- edit attempt just re-selects (standard copy-window behavior).
    edit:SetScript("OnTextChanged", function(self, user)
        if user and f._text then
            self:SetText(f._text)
            if self.HighlightText then self:HighlightText() end
        end
    end)
    if scroll.SetScrollChild then pcall(scroll.SetScrollChild, scroll, edit) end
    f._edit = edit

    f:Hide()
    copyWindow = f
    return f
end

function Skin.OpenCopy(frame)
    local f = ensureCopyWindow()
    if not f then return end
    local lines = Skin.ExtractCopyText(frame)
    local text = table.concat(lines, "\n")
    f._text = text
    local frameName = (frame.GetName and frame:GetName()) or "chat"
    if f._title then f._title:SetText("Copy chat - " .. frameName) end
    f._edit:SetText(text)
    f:Show()
    if f._edit.SetFocus then pcall(f._edit.SetFocus, f._edit) end
    if f._edit.HighlightText then pcall(f._edit.HighlightText, f._edit) end
    return text
end

local function ensureCopyButton(frame, rec)
    local UI = UIKit()
    if not UI then return end
    if not cfg().copyButton then
        if rec.copyBtn then rec.copyBtn:Hide() end
        return
    end
    if rec.copyBtn then rec.copyBtn:Show() return end
    local btn = _G.CreateFrame("Button", nil, frame)
    btn:SetSize(38, 16)
    btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", PAD, PAD)
    if btn.SetAlpha then btn:SetAlpha(COPY_IDLE) end
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(UI.fonts.small)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText("copy")    -- ASCII by law
    UI.Skin(label, function(self)
        if type(self.SetTextColor) == "function" then self:SetTextColor(UI.Color("muted")) end
    end)
    btn:SetScript("OnEnter", function(self)
        if self.SetAlpha then self:SetAlpha(1) end
        if type(label.SetTextColor) == "function" then label:SetTextColor(UI.Color("accent")) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.SetAlpha then self:SetAlpha(COPY_IDLE) end
        if type(label.SetTextColor) == "function" then label:SetTextColor(UI.Color("muted")) end
    end)
    btn:SetScript("OnClick", function() Skin.OpenCopy(frame) end)
    rec.copyBtn = btn
end

----------------------------------------------------------------------
-- THE ICON RAIL (skin v2 feature 4 — default OFF, the speculative one).
--
-- A slim themed strip on the window's left edge carrying ONLY verbs Chat
-- already owns. Nothing new hides behind these buttons, and the harness pins
-- that by CALL IDENTITY: every button holds the exact existing function object
-- it invokes.
--   copy   "C"  -> Skin.OpenCopy(frame)      (the copy-chat affordance)
--   config "*"  -> ns.SlashDispatch("")      (the /dchat surface)
--   bottom "v"  -> frame:ScrollToBottom()    (the client's own frame method)
--
-- Every glyph is ASCII (the tofu law: only a NON-ASCII glyph needs a cmap
-- check against the vendored face — none ship here).
----------------------------------------------------------------------

local RAIL_ORDER = { "copy", "config", "bottom" }

local function railButton(rail, glyph, onClick)
    local UI = UIKit()
    local btn = _G.CreateFrame("Button", nil, rail)
    btn:SetSize(RAIL_BTN, RAIL_BTN)
    if btn.SetAlpha then btn:SetAlpha(RAIL_IDLE) end
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(UI.fonts.small)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(glyph)                 -- ASCII by law
    UI.Skin(label, function(self)
        if type(self.SetTextColor) == "function" then self:SetTextColor(UI.Color("muted")) end
    end)
    btn:SetScript("OnEnter", function(self)
        if self.SetAlpha then self:SetAlpha(1) end
        if type(label.SetTextColor) == "function" then label:SetTextColor(UI.Color("accent")) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.SetAlpha then self:SetAlpha(RAIL_IDLE) end
        if type(label.SetTextColor) == "function" then label:SetTextColor(UI.Color("muted")) end
    end)
    btn:SetScript("OnClick", onClick)
    btn._glyph = glyph
    btn._label = label
    return btn
end

local function ensureRail(frame, rec)
    local UI = UIKit()
    if not UI then return end
    if not cfg().iconRail then
        if rec.rail then rec.rail:Hide() end
        return
    end
    if rec.rail then rec.rail:Show() return end

    local rail = UI.FlatFrame(frame, "panel", "border")
    if type(rail.SetWidth) == "function" then rail:SetWidth(RAIL_WIDTH) end
    rail:SetPoint("TOPRIGHT", frame, "TOPLEFT", -(PAD + RAIL_GAP), PAD)
    rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -(PAD + RAIL_GAP), -PAD)
    if rail.SetFrameLevel and frame.GetFrameLevel then
        local okL, lvl = pcall(frame.GetFrameLevel, frame)
        pcall(rail.SetFrameLevel, rail, (okL and lvl or 1))
    end

    local buttons = {}
    buttons.copy = railButton(rail, "C", function() Skin.OpenCopy(frame) end)
    buttons.copy._verb = Skin.OpenCopy
    buttons.config = railButton(rail, "*", function() ns.SlashDispatch("") end)
    buttons.config._verb = ns.SlashDispatch
    buttons.bottom = railButton(rail, "v", function()
        if type(frame.ScrollToBottom) == "function" then frame:ScrollToBottom() end
    end)
    buttons.bottom._verb = frame.ScrollToBottom

    for i, key in ipairs(RAIL_ORDER) do
        local btn = buttons[key]
        if i == 1 then
            btn:SetPoint("TOP", rail, "TOP", 0, -RAIL_GAP)
        else
            btn:SetPoint("TOP", buttons[RAIL_ORDER[i - 1]], "BOTTOM", 0, -RAIL_GAP)
        end
    end

    rec.rail = rail
    rec.railButtons = buttons
end

----------------------------------------------------------------------
-- Style / restore one window.
----------------------------------------------------------------------

function Skin.StyleWindow(frame, id)
    if not frame then return end
    local rec = Skin.styled[frame]
    if not rec then
        rec = { id = id }
        Skin.styled[frame] = rec
        Skin.order[#Skin.order + 1] = frame
    end
    stripStock(frame, rec)
    ensureBackdrop(frame, rec)
    styleTab(frame, rec)
    applyFrameFont(frame, id)
    Skin.ApplyFading(frame)
    if not isCombatLog(frame, id) then
        styleEditBox(frame, rec)
        local eb = editBoxOf(frame)
        if eb then Skin.ColorEditBoxHeader(eb) end
    end
    ensureCopyButton(frame, rec)
    ensureRail(frame, rec)
    Skin.UpdateDivider(frame)
end

local function restoreWindow(frame, rec)
    restoreStock(frame, rec)
    if rec.backdrop then rec.backdrop:Hide() end
    if rec.copyBtn then rec.copyBtn:Hide() end
    if rec.rail then rec.rail:Hide() end
    if rec.underline then rec.underline:Hide() end
    if rec.divider then rec.divider:Hide() end
    restoreEditBox(frame, rec)
    if rec.origFont and type(frame.SetFont) == "function" then
        pcall(frame.SetFont, frame, rec.origFont[1], rec.origFont[2], rec.origFont[3])
    end
    if rec.origTabColor then
        local _, text = tabText(frame)
        if text and type(text.SetTextColor) == "function" then
            text:SetTextColor(rec.origTabColor[1], rec.origTabColor[2], rec.origTabColor[3])
        end
    end
end

function Skin.StyleAll()
    for id = 1, numWindows() do
        local frame = _G["ChatFrame" .. id]
        if frame and windowEligible(id) then
            Skin.StyleWindow(frame, id)
        end
    end
    Skin.UpdateTabColors()
end

-- The v2 re-evaluation beat: everything whose answer can change without a
-- restyle — the channel inks, the active underline, the rail's config gate and
-- the divider's stamps-are-on gate. Cheap and idempotent; called from the
-- selection hook, the theme/font hooks, UPDATE_CHAT_COLOR and CVAR_UPDATE.
function Skin.Refresh()
    if not Skin.active then return end
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec then ensureRail(frame, rec) end
    end
    Skin.UpdateTabColors()
    Skin.UpdateDividers()
end

-- Re-apply everything that is not covered by UI.Skin's automatic re-color
-- (fonts and tab state read tokens imperatively).
function Skin.Reskin()
    if not Skin.active then return end
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        applyFrameFont(frame, rec and rec.id)
    end
    Skin.RecolorEditBoxHeaders()
    Skin.Refresh()
end

----------------------------------------------------------------------
-- Lifecycle. hooksecurefunc is permanent, so both installs happen exactly
-- once (first enable) and every body gates on Skin.active — a disabled skin
-- is behaviorally absent even though the hook shell remains.
----------------------------------------------------------------------

local function installHooks()
    if Skin.hooked then return end
    Skin.hooked = true
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return end
    -- Temporary windows (whisper pop-outs) appear past index 10; style them as
    -- they open so they wear the suite look from their first frame.
    if type(_G.FCF_OpenTemporaryWindow) == "function" then
        hook("FCF_OpenTemporaryWindow", function()
            if not Skin.active then return end
            -- The new frame is the client's newest temporary; scan past the
            -- permanent ten for any eligible frame we have not styled.
            for id = numWindows() + 1, 50 do
                local frame = _G["ChatFrame" .. id]
                if frame and not Skin.styled[frame] and frame.IsShown and frame:IsShown() then
                    Skin.StyleWindow(frame, id)
                end
            end
            Skin.Refresh()
        end)
    end
    -- Dock selection changes recolor the tab row (selected = full-strength ink
    -- plus the accent underline).
    if type(_G.FCF_SelectDockFrame) == "function" then
        hook("FCF_SelectDockFrame", function()
            if not Skin.active then return end
            Skin.Refresh()
        end)
    end
    -- The client's own edit-box header beat: every sticky change, tab-cycle and
    -- /channel switch lands here, so the prefix ink follows without us tracking
    -- a single piece of channel state (skin v2 feature 3).
    if type(_G.ChatEdit_UpdateHeader) == "function" then
        hook("ChatEdit_UpdateHeader", function(editBox)
            if not Skin.active then return end
            Skin.ColorEditBoxHeader(editBox)
        end)
    end
end

-- Our OWN gated listeners (never coupled to another module's subscription).
Skin._colorHandler = function()
    if not Skin.active then return end
    -- The player (or the reconciler) recolored a chat type: every tab ink and
    -- edit-box prefix that derives from the client table re-reads it now.
    Skin.Refresh()
    Skin.RecolorEditBoxHeaders()
end

Skin._cvarHandler = function(event, name)
    -- showTimestamps decides whether stamps.lua suspends, which decides whether
    -- the divider has anything to divide. stamps.lua subscribes to the SAME
    -- event and there is no defined order between two subscribers (Class 2), so
    -- the re-evaluation is deferred one beat: by then the sibling's suspend
    -- flag is settled, whichever handler ran first.
    if not Skin.active then return end
    if name ~= "showTimestamps" then return end
    if Skin._dividerQueued then return end
    local CT = _G.C_Timer
    if not (CT and type(CT.After) == "function") then
        Skin.UpdateDividers()
        return
    end
    Skin._dividerQueued = true
    CT.After(0, function()
        Skin._dividerQueued = false
        if Skin.active then Skin.UpdateDividers() end
    end)
end

function Skin.OnEnable()
    Skin.active = true
    installHooks()
    -- Theme/font reactivity: registered once, bodies gate on active. Core's
    -- UI.Skin covers the backdrop colors; this covers fonts + tab ink.
    local UI = UIKit()
    if UI and not Skin.reskinHooked then
        Skin.reskinHooked = true
        if UI.OnThemeChanged then UI.OnThemeChanged(function() Skin.Reskin() end) end
        if UI.OnFontChanged then UI.OnFontChanged(function() Skin.Reskin() end) end
    end
    ns:RegisterEvent("UPDATE_CHAT_COLOR", Skin._colorHandler)
    ns:RegisterEvent("CVAR_UPDATE", Skin._cvarHandler)
    Skin.StyleAll()
end

function Skin.OnDisable()
    Skin.active = false
    ns:UnregisterEvent("UPDATE_CHAT_COLOR", Skin._colorHandler)
    ns:UnregisterEvent("CVAR_UPDATE", Skin._cvarHandler)
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec then restoreWindow(frame, rec) end
    end
    if copyWindow then copyWindow:Hide() end
end

ns.RegisterModule("skin", Skin)

ns.RegisterDebugCommand("skin", "skin state: styled windows, config, tab inks", function()
    ns:Print(("skin: %s, %d window(s) styled"):format(
        Skin.active and "active" or "inactive", #Skin.order))
    local c = cfg()
    ns:Print(("  fading=%s fadeTime=%s editBox=%s copyButton=%s"):format(
        tostring(c.fading), tostring(c.fadeTime), tostring(c.editBox), tostring(c.copyButton)))
    ns:Print(("  channelTabs=%s stampDivider=%s editBoxChannelColor=%s iconRail=%s"):format(
        tostring(c.channelTabs), tostring(c.stampDivider),
        tostring(c.editBoxChannelColor), tostring(c.iconRail)))
    ns:Print(("  tab dim factor %.3f (token-derived), stamps showing: %s, stamp sample '%s'")
        :format(Skin.DimFactor(), tostring(Skin.StampsShowing()), Skin.StampSample()))
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        local entry, source = Skin.WindowRouting(rec and rec.id)
        local kind, value = Skin.DominantChannel(entry, isCombatLog(frame, rec and rec.id))
        ns:Print(("  %s: ink=%s dominant=%s%s routing=%s"):format(
            tostring(frame.GetName and frame:GetName() or "?"),
            tostring(rec and rec.inkSource or "-"),
            tostring(kind or "none"),
            value and (" " .. tostring(value)) or "",
            tostring(source or "none")))
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "skin").
--
-- The pure parts (defang, extraction shape) always run. The live parts drive
-- the module against the harness's unkind chat simulator and its Core stub;
-- in-game (no sim) they are skipped rather than faked.
----------------------------------------------------------------------

local function testDefang(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local D = Skin.DefangLine
    ck(D("plain text") == "plain text", "plain text passes through")
    ck(D("|cffa335ee|Hitem:19019|h[Thunderfury]|h|r is mine")
        == "[Thunderfury] is mine", "decorated item link defangs to display text")
    ck(D("see |Hurl:http://x.io|h[http://x.io]|h now")
        == "see [http://x.io] now", "url pseudo-link defangs to display text")
    ck(D("a |Hitem:1|h[A]|h and |Hitem:2|h[B]|h")
        == "a [A] and [B]", "two links on one line defang independently")
    ck(D("from |KS42|k today") == "from ??? today", "|K protected span becomes ???")
    ck(D("kill |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t now")
        == "kill {rt8} now", "raid icon texture reverse-maps to {rt8}")
    ck(D("x |TInterface\\Icons\\Foo:16|t y") == "x  y", "other textures drop")
    ck(D("|cff00ff00green|r end") == "green end", "color escapes strip")
    ck(D("50%||50%") == "50%|50%", "escaped pipes un-escape")
    ck(D(nil) == "", "non-string input is safe")
end

-- The dominance rule, PURE (no client, no sim): routing in, one identity or
-- none out. This is the matrix the headline feature stands on.
local function testDominance(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local D = Skin.DominantChannel

    local kind, value = D({ groups = { "GUILD" }, channels = {} }, false)
    ck(kind == "type" and value == "GUILD", "dominance: a GUILD-only window is a guild window")

    kind, value = D({ groups = { "GUILD", "OFFICER" }, channels = {} }, false)
    ck(kind == "type" and value == "GUILD",
        "dominance: OFFICER folds onto its family head, so GUILD+OFFICER is still guild")

    kind, value = D({ groups = { "RAID", "RAID_LEADER", "RAID_WARNING" }, channels = {} }, false)
    ck(kind == "type" and value == "RAID", "dominance: the raid family folds onto RAID")

    kind = D({ groups = { "GUILD", "PARTY" }, channels = {} }, false)
    ck(kind == nil, "dominance: two real identities = NO dominant (the fallback)")

    -- The client's default window: a dozen groups. No dominant, by design.
    kind = D({ groups = { "SAY", "YELL", "EMOTE", "GUILD", "OFFICER", "WHISPER",
                          "PARTY", "RAID", "RAID_WARNING", "SYSTEM", "CHANNEL" },
               channels = { "General" } }, false)
    ck(kind == nil, "dominance: the default window has no dominant channel (fallback pinned)")

    kind, value = D({ groups = { "GUILD", "SYSTEM", "LOOT", "SKILL", "COMBAT_XP_GAIN" },
                      channels = {} }, false)
    ck(kind == "type" and value == "GUILD",
        "dominance: ambient groups (system/loot/skill/xp) never establish identity")

    kind = D({ groups = { "SYSTEM", "LOOT" }, channels = {} }, false)
    ck(kind == nil, "dominance: an ambient-only window has no identity at all")

    kind, value = D({ groups = { "CHANNEL" }, channels = { "World" } }, false)
    ck(kind == "channel" and value == "World",
        "dominance: the CHANNEL group is a routing switch; the NAME carries identity")

    kind = D({ groups = { "CHANNEL" }, channels = { "World", "Trade" } }, false)
    ck(kind == nil, "dominance: two named channels = no dominant")

    kind = D({ groups = { "GUILD" }, channels = { "World" } }, false)
    ck(kind == nil, "dominance: a group AND a channel are two identities")

    kind, value = D({ groups = { "CHANNEL" }, channels = {} }, false)
    ck(kind == nil, "dominance: routing the CHANNEL group with no channels is not an identity")

    ck(D({}, false) == nil, "dominance: an empty entry has no dominant")
    ck(D(nil, false) == nil, "dominance: no routing at all is safe")
    ck(D({ groups = { "GUILD" } }, true) == "combatlog",
        "dominance: the combat log wins over any routing (its own muted treatment)")
    ck(D({ groups = { "guild" }, channels = {} }, false) == "type",
        "dominance: group names are case-normalized")

    -- Duplicate routing entries are ONE identity, not two.
    kind, value = D({ groups = { "GUILD", "GUILD" }, channels = { "World", "world" } }, false)
    ck(kind == nil, "dominance: duplicates collapse (guild + one channel is still two)")
    kind, value = D({ groups = {}, channels = { "World", "world" } }, false)
    ck(kind == "channel", "dominance: the same channel named twice is ONE identity")
end

local function testCopyAndSkin(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI  = UIKit()
    if not (Sim and UI) then
        if verbose then ns:Print("  skin: live checks skipped (no simulator)") end
        return
    end

    -- ── Phase 0: INERTNESS. The harness loaded us with skin disabled and drove
    -- a full login. Nothing may have been touched. ─────────────────────────────
    ck(Skin.active == false, "phase 0: module inactive after disabled login")
    ck(#Skin.order == 0, "phase 0: zero windows styled while disabled")
    ck(Skin.hooked == false, "phase 0: zero hooksecurefunc installs while disabled (the pin)")
    ck(Sim.CallCount("hooksecurefunc") == 0, "phase 0: sim counted zero hook installs")
    ck(Sim.CallCount("SetFading") == 0, "phase 0: no window's fading was touched")
    -- Sibling modules legitimately hold their own subscriptions, so the pin on
    -- OUR listeners is the DELTA against the world our predecessors left.
    local cf1 = _G.ChatFrame1
    local colorSubsBase = ns.EventHandlerCount("UPDATE_CHAT_COLOR")
    local cvarSubsBase  = ns.EventHandlerCount("CVAR_UPDATE")

    -- The suites before us authored windows and config entries for their own
    -- legs. The tab-ink assertions below are about ROUTING, so this suite puts
    -- the world back to the client's stock ten-window layout and mirrors it
    -- into the config; the config branch is handed back at the end.
    local C = ns.Config
    local cfgStore = C and C.Get() or nil
    local savedCfgWindows = cfgStore and cfgStore.windows or nil
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    if cfgStore then
        cfgStore.windows = {}
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            cfgStore.windows[id] = C.CaptureWindow(id)
        end
    end
    _G.FCF_SelectDockFrame(_G.ChatFrame1)

    -- ── Phase 1: enable — every eligible window wears the theme. ──────────────
    ns.SetModuleEnabled("skin", true)
    ck(Skin.active == true, "phase 1: enable activates the module")
    local styledCount = 0
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. id]
        local eligible = select(1, windowEligible(id))
        if frame and eligible then
            styledCount = styledCount + 1
            local rec = Skin.styled[frame]
            ck(rec ~= nil, "phase 1: eligible window " .. id .. " styled")
            if rec and rec.backdrop then
                local bg = rec.backdrop._backdropColor
                local pr, pg, pb = UI.Color("panel")
                ck(bg and math.abs(bg[1] - pr) < 1e-6 and math.abs(bg[2] - pg) < 1e-6
                    and math.abs(bg[3] - pb) < 1e-6,
                    "phase 1: window " .. id .. " backdrop fill is the panel TOKEN (not hardcoded)")
                local bc = rec.backdrop._backdropBorderColor
                local br, bgc, bb = UI.Color("border")
                ck(bc and math.abs(bc[1] - br) < 1e-6 and math.abs(bc[2] - bgc) < 1e-6
                    and math.abs(bc[3] - bb) < 1e-6,
                    "phase 1: window " .. id .. " border is the border TOKEN")
            end
            local face = frame._font and frame._font[1]
            ck(face == UI.FontFile(), "phase 1: window " .. id .. " text face is Core's picked face")
            ck(frame._fading == true, "phase 1: window " .. id .. " fading on per config")
            ck(frame._timeVisible == (ns.db.skin.fadeTime or 100),
                "phase 1: window " .. id .. " fade time from config")
        elseif frame then
            ck(Skin.styled[frame] == nil, "phase 1: hidden window " .. id .. " left alone")
        end
    end
    ck(styledCount >= 2, "phase 1: the sim's default world styled at least two windows")
    ck(Skin.hooked == true, "phase 1: hooks installed on first enable")
    ck(ns.EventHandlerCount("UPDATE_CHAT_COLOR") == colorSubsBase + 1
        and ns.EventHandlerCount("CVAR_UPDATE") == cvarSubsBase + 1,
        "phase 1: enabling added exactly ONE listener each (skin's own, never a sibling's)")

    -- Tab ink, the two stock windows (the routing above is the client's own):
    -- window 1 routes a dozen groups, so it has NO dominant channel and keeps
    -- the token fallback; window 2 is the combat log and wears its own muted
    -- treatment, dimmed because it is not the selected tab.
    local function near3(got, r, g, b, tol)
        tol = tol or 1e-6
        return got and math.abs(got[1] - r) < tol and math.abs(got[2] - g) < tol
            and math.abs(got[3] - b) < tol
    end
    local _, tab1Text = tabText(_G.ChatFrame1)
    ck(near3(tab1Text and tab1Text._textColor, UI.Color("accent")),
        "phase 1: the default window has no dominant channel, so its selected tab keeps the ACCENT token (the pinned fallback)")
    local dim = Skin.DimFactor()
    local mr, mg, mb = UI.Color("muted")
    local _, tab2Text = tabText(_G.ChatFrame2)
    ck(near3(tab2Text and tab2Text._textColor, mr * dim, mg * dim, mb * dim),
        "phase 1: the combat log tab wears the MUTED token dimmed by the token-derived factor")
    ck(Skin.styled[_G.ChatFrame1].inkSource == "token"
        and Skin.styled[_G.ChatFrame2].inkSource == "combatlog",
        "phase 1: each tab records which rule inked it")

    -- The dim factor itself is derived from tokens, never a constant: recompute
    -- it from the muted/text tokens and demand the same answer, then move the
    -- theme and demand it moved with it.
    local function expectedDim()
        local function lum(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end
        local lm = lum(UI.Color("muted"))
        local lt = lum(UI.Color("text"))
        return 0.30 + 0.60 * (lm / (lm + lt))
    end
    ck(math.abs(Skin.DimFactor() - expectedDim()) < 1e-9,
        "phase 1: the inactive-tab dim is DERIVED from the muted/text tokens")
    if UI.__SetThemeEpoch then
        local before = Skin.DimFactor()
        UI.__SetThemeEpoch(3)
        local after = Skin.DimFactor()
        ck(math.abs(after - expectedDim()) < 1e-9,
            "phase 1: the dim re-derives from the NEW theme's tokens")
        ck(math.abs(after - before) > 1e-9,
            "phase 1: a theme change MOVES the dim (a hardcoded alpha could not)")
        UI.__SetThemeEpoch(1)
    end

    -- ── Phase 2: copy-chat reads the ring buffer faithfully. ──────────────────
    local cf3 = _G.ChatFrame3   -- a quiet styled window; seed exact content
    local target = cf3 or _G.ChatFrame1
    local base = target:GetNumMessages()
    target:AddMessage("|cffffffff[|Hplayer:Puu|hPuu|h]|r: look |cffa335ee|Hitem:19019|h[Thunderfury]|h|r", 1, 1, 1)
    target:AddMessage("secret |Kq9|k and {rt7}: |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t", 1, 1, 1)
    local text = Skin.OpenCopy(target)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    ck(#lines == base + 2, "phase 2: copy window holds every buffered line (got " .. #lines .. ")")
    ck(lines[#lines - 1] == "[Puu]: look [Thunderfury]",
        "phase 2: hyperlinks defanged to display text, order oldest-to-newest")
    ck(lines[#lines] == "secret ??? and {rt7}: {rt7}",
        "phase 2: |K span became ??? and the raid icon became {rt7}")
    ck(copyWindow and copyWindow._edit._focused == true, "phase 2: copy edit box took focus")
    ck(copyWindow._edit._highlighted == true, "phase 2: text pre-highlighted for Ctrl+C")
    ck(text:find("|H", 1, true) == nil and text:find("|K", 1, true) == nil,
        "phase 2: no live escape sequences survive into the copyable text")

    -- ── Phase 3: config drives fading (probe a STYLED window). ────────────────
    local fadeProbe = _G.ChatFrame1
    ns.db.skin.fading = false
    for _, frame in ipairs(Skin.order) do Skin.ApplyFading(frame) end
    ck(fadeProbe._fading == false, "phase 3: fading off per config")
    ns.db.skin.fading, ns.db.skin.fadeTime = true, 42
    for _, frame in ipairs(Skin.order) do Skin.ApplyFading(frame) end
    ck(fadeProbe._fading == true and fadeProbe._timeVisible == 42,
        "phase 3: fading back on with the configured hold time")
    ns.db.skin.fadeTime = 100
    for _, frame in ipairs(Skin.order) do Skin.ApplyFading(frame) end

    -- ── Phase 4: theme change re-inks everything (no /reload). ────────────────
    local UIStub = UI
    if UIStub.__SetThemeEpoch then
        local beforeR = select(1, UIStub.Color("panel"))
        UIStub.__SetThemeEpoch(2)
        local afterR = select(1, UIStub.Color("panel"))
        ck(beforeR ~= afterR, "phase 4: the stub theme really changed")
        UIStub.__FireThemeChanged()
        local rec = Skin.styled[_G.ChatFrame1]
        local bg = rec and rec.backdrop and rec.backdrop._backdropColor
        local pr = select(1, UIStub.Color("panel"))
        ck(bg and math.abs(bg[1] - pr) < 1e-6,
            "phase 4: backdrop re-colored from the NEW theme's token")
        UIStub.__SetThemeEpoch(1)
        UIStub.__FireThemeChanged()
    end

    -- ── Phase 5: CHANNEL-COLORED TABS, live, against an authored routing
    -- matrix. Windows 5..8 are opened with one routing each; every ink is
    -- checked against the CLIENT's color table (never a token, never a
    -- literal), and the client's colors are then MOVED to prove nothing is
    -- baked in. ───────────────────────────────────────────────────────────────
    local CTI = _G.ChatTypeInfo
    local MATRIX = {   -- ordered walk, never pairs (the house habit)
        { id = 5, groups = { "GUILD", "OFFICER" }, channels = {} },              -- guild tab
        { id = 6, groups = { "CHANNEL" },          channels = { "Skinworld" } }, -- channel tab
        { id = 7, groups = { "GUILD", "PARTY" },   channels = {} },              -- two identities
        { id = 8, groups = { "SYSTEM", "LOOT" },   channels = {} },              -- ambient only
    }
    -- A channel the "server" has granted a number, with its own client color.
    Sim.serverChannels[9] = { name = "Skinworld", zoneID = 0 }
    _G.ChangeChatColor("CHANNEL9", 0.13, 0.44, 0.77)
    for _, routing in ipairs(MATRIX) do
        local w = Sim.windows[routing.id]
        w.shown, w.docked = true, routing.id
        w.groups, w.channels = { unpack(routing.groups) }, { unpack(routing.channels) }
        if cfgStore then cfgStore.windows[routing.id] = C.CaptureWindow(routing.id) end
    end
    Skin.StyleAll()
    local cf5, cf6, cf7, cf8 =
        _G.ChatFrame5, _G.ChatFrame6, _G.ChatFrame7, _G.ChatFrame8
    local function inkOf(frame) return select(2, tabText(frame))._textColor end
    dim = Skin.DimFactor()

    ck(near3(inkOf(cf5), CTI.GUILD.r * dim, CTI.GUILD.g * dim, CTI.GUILD.b * dim),
        "phase 5: a GUILD window's tab wears the CLIENT's guild-chat color (dimmed, unselected)")
    ck(Skin.styled[cf5].inkSource == "type", "phase 5: the guild tab was inked by a message group")
    ck(near3(inkOf(cf6), CTI.CHANNEL9.r * dim, CTI.CHANNEL9.g * dim, CTI.CHANNEL9.b * dim),
        "phase 5: a single-channel window's tab wears that CHANNEL's client color, resolved by NAME through its number")
    ck(Skin.styled[cf6].inkSource == "channel", "phase 5: the channel tab was inked by a channel name")
    ck(near3(inkOf(cf7), UI.Color("muted")),
        "phase 5: two identities = no dominant = the MUTED token fallback (today's behavior)")
    ck(near3(inkOf(cf8), UI.Color("muted")),
        "phase 5: an ambient-only window falls back too")
    ck(Skin.styled[cf7].inkSource == "token" and Skin.styled[cf8].inkSource == "token",
        "phase 5: both fallback windows record the token source")

    -- Active treatment: full-strength ink plus the accent underline; the tab we
    -- just left drops back to the dimmed ink and loses its underline.
    _G.FCF_SelectDockFrame(cf5)
    ck(near3(inkOf(cf5), CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b),
        "phase 5: the ACTIVE tab wears the channel ink at full strength")
    local ul5 = Skin.styled[cf5].underline
    ck(ul5 and ul5._shown == true, "phase 5: the active tab wears the accent underline")
    ck(near3(ul5._color, UI.Color("accent")),
        "phase 5: the underline is the ACCENT token (not a color)")
    ck(near3(inkOf(cf1), UI.Color("muted")),
        "phase 5: the tab that lost selection falls to its inactive treatment")
    local ul1 = Skin.styled[cf1].underline
    ck(ul1 and ul1._shown == false, "phase 5: only the active tab is underlined")

    -- The colors are the CLIENT's, live: move guild chat's color and the tab
    -- follows on the client's own UPDATE_CHAT_COLOR beat (our gated listener),
    -- with no restyle and no reload. A baked-in green cannot survive this.
    _G.ChangeChatColor("GUILD", 0.91, 0.17, 0.55)
    ck(near3(inkOf(cf5), 0.91, 0.17, 0.55),
        "phase 5: UPDATE_CHAT_COLOR re-inks the tab live (the color source is the CLIENT's table)")
    ck(near3(inkOf(cf6), CTI.CHANNEL9.r * dim, CTI.CHANNEL9.g * dim, CTI.CHANNEL9.b * dim),
        "phase 5: recoloring guild chat left the channel tab exactly where it was")
    _G.ChangeChatColor("GUILD", 0.25, 1, 0.25)   -- back to the client's stock guild green
    ck(near3(inkOf(cf5), 0.25, 1, 0.25), "phase 5: and follows the color back")

    -- The feature is a gate: off means Wave 1's treatment, exactly.
    ns.db.skin.channelTabs = false
    Skin.Refresh()
    ck(near3(inkOf(cf5), UI.Color("accent")),
        "phase 5: channelTabs off -> the active tab is the plain ACCENT token again")
    ck(ul5._shown == false, "phase 5: channelTabs off -> no underline either")
    ns.db.skin.channelTabs = true
    Skin.Refresh()

    -- ── Phase 5b: BADGE COORDINATION on a recolored tab. badges.lua owns the
    -- counter; skin owns the tab. Neither may touch the other's surface. ──────
    local Badges = ns.Badges
    if Badges and Badges.active then
        local dock = _G.GeneralDockManager
        dock.DOCKED_CHAT_FRAMES[#dock.DOCKED_CHAT_FRAMES + 1] = cf5
        _G.FCF_SelectDockFrame(cf1)          -- cf5 is docked-unselected: badgeable
        Badges.Clear(cf5)
        cf5:AddMessage("unread on a colored tab", 1, 1, 1)
        local bw = Badges.widgets[cf5]
        local tab5 = _G["ChatFrame5Tab"]
        ck(Badges.counts[cf5] == 1 and bw and bw.holder._shown == true,
            "phase 5b: the badge still renders on a channel-colored tab")
        ck(bw.holder._parent == tab5 and bw.fs ~= tab5.Text,
            "phase 5b: the badge is still its own FontString on its own holder anchored to the tab")
        ck(near3(bw.fs._textColor, UI.Color("muted")),
            "phase 5b: the badge keeps its own MUTED token ink while the tab wears a channel color")
        ck(near3(tab5.Text._textColor, CTI.GUILD.r * dim, CTI.GUILD.g * dim, CTI.GUILD.b * dim),
            "phase 5b: ...and the tab keeps its channel ink while the badge is up")
        -- Geometry: the badge sits PAST the tab's right edge; the underline is
        -- inset INSIDE both tab edges, so the two can never overlap.
        local badgePt = bw.holder._points[1]
        ck(badgePt and badgePt[1] == "LEFT" and badgePt[3] == "RIGHT" and badgePt[4] >= 0,
            "phase 5b: the badge anchors off the tab's RIGHT edge, outward")
        local ulRight
        for _, pt in ipairs(ul5._points) do if pt[1] == "BOTTOMRIGHT" then ulRight = pt end end
        ck(ulRight and ulRight[2] == tab5 and ulRight[4] < 0,
            "phase 5b: the underline's right edge is INSET from the tab (never under the badge)")
        _G.FCF_SelectDockFrame(cf5)
        ck(Badges.counts[cf5] == 0 and bw.holder._shown == false,
            "phase 5b: selecting the colored tab clears the badge as usual")
        ck(near3(tab5.Text._textColor, CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b)
            and ul5._shown == true,
            "phase 5b: ...and the same click gives it the active treatment")
        for i = #dock.DOCKED_CHAT_FRAMES, 1, -1 do
            if dock.DOCKED_CHAT_FRAMES[i] == cf5 then table.remove(dock.DOCKED_CHAT_FRAMES, i) end
        end
        Badges.Clear(cf5)
    end
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase 6: the TIMESTAMP DIVIDER, present only while stamps are on. ─────
    local recDiv = Skin.styled[cf1]
    ck(Skin.StampsShowing() == false, "phase 6: stamps are off as this suite starts")
    Skin.UpdateDividers()
    ck(recDiv.divider == nil or recDiv.divider._shown == false,
        "phase 6: stamps off -> NO divider (nothing to divide)")

    ns.SetModuleEnabled("stamps", true)
    ck(Skin.StampsShowing() == true, "phase 6: stamps on")
    Skin.UpdateDividers()
    ck(recDiv.divider and recDiv.divider._shown == true, "phase 6: the divider appears")
    ck(near3(recDiv.divider._color, UI.Color("border")),
        "phase 6: the hairline is the BORDER token (not a color)")
    ck(recDiv.divider._color[4] == 0.55, "phase 6: ...at the subtle measure alpha")

    -- The column is MEASURED from the stamp shape the format produces; a wider
    -- format moves the hairline right. (Read-only coordination: this reads the
    -- stamps CONFIG field and measures, it never calls into stamps.)
    local narrow = recDiv.dividerX
    local savedFormat = ns.db.stamps.format
    ns.db.stamps.format = "HH:MM:SS"
    Skin.UpdateDividers()
    ck(recDiv.dividerX > narrow,
        "phase 6: a wider stamp format measures a wider stamp column (" ..
        tostring(narrow) .. " -> " .. tostring(recDiv.dividerX) .. ")")
    ns.db.stamps.format = savedFormat
    Skin.UpdateDividers()
    ck(recDiv.dividerX == narrow, "phase 6: and back again")

    -- Suspension is not "off": the client's native timestamps turn stamps into
    -- a bystander, so the divider must go with them. The re-evaluation is
    -- deferred one beat because stamps subscribes to the same CVar event.
    local HT = _G.__DaseekiChatHarnessTimer
    _G.SetCVar("showTimestamps", "chat")
    if HT then HT.advance(0) end
    ck(Skin.StampsShowing() == false and recDiv.divider._shown == false,
        "phase 6: native timestamps suspend stamps, so the divider hides too")
    _G.SetCVar("showTimestamps", "none")
    if HT then HT.advance(0) end
    ck(Skin.StampsShowing() == true and recDiv.divider._shown == true,
        "phase 6: and it comes back with them")

    ns.db.skin.stampDivider = false
    Skin.UpdateDividers()
    ck(recDiv.divider._shown == false, "phase 6: the divider is its own config gate")
    ns.db.skin.stampDivider = true
    ns.SetModuleEnabled("stamps", false)    -- back to the state our siblings expect
    Skin.UpdateDividers()
    ck(recDiv.divider._shown == false, "phase 6: stamps off again -> divider gone again")

    -- ── Phase 7: the EDIT BOX's sticky-channel prefix. ────────────────────────
    local eb1 = _G.ChatFrame1EditBox
    local header = eb1.header
    ck(header ~= nil, "phase 7: the client's edit box carries a header FontString")
    ck(header._fontObject == UI.fonts.small,
        "phase 7: the prefix wears the bar's Core font role")
    eb1:SetAttribute("chatType", "GUILD")
    _G.ChatEdit_UpdateHeader(eb1)
    ck(header._text == "GUILD:", "phase 7: the CLIENT still authors the prefix text (we only ink it)")
    ck(near3(header._textColor, CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b),
        "phase 7: the prefix wears guild chat's client color")

    -- The value we add over the client's own header pass: the prefix follows a
    -- recolor made while the box is already open, with no header update at all.
    local headerBeats = Sim.CallCount("ChatEdit_UpdateHeader")
    _G.ChangeChatColor("GUILD", 0.42, 0.66, 0.19)
    ck(Sim.CallCount("ChatEdit_UpdateHeader") == headerBeats,
        "phase 7: the client did NOT re-run its header pass")
    ck(near3(header._textColor, 0.42, 0.66, 0.19),
        "phase 7: ...and the prefix followed the new color anyway (our gated listener)")

    ns.db.skin.editBoxChannelColor = false
    _G.ChangeChatColor("GUILD", 0.25, 1, 0.25)
    ck(near3(header._textColor, 0.42, 0.66, 0.19),
        "phase 7: with the feature off the prefix stops following (it is a real gate)")
    ns.db.skin.editBoxChannelColor = true

    -- A CHANNEL sticky resolves through the channel's number, like the tabs.
    eb1:SetAttribute("chatType", "CHANNEL")
    eb1:SetAttribute("channelTarget", 9)
    _G.ChatEdit_UpdateHeader(eb1)
    ck(header._text == "9. Skinworld:", "phase 7: the client authors the channel prefix")
    ck(near3(header._textColor, CTI.CHANNEL9.r, CTI.CHANNEL9.g, CTI.CHANNEL9.b),
        "phase 7: a channel sticky wears THAT channel's client color")
    eb1:SetAttribute("chatType", "SAY")
    eb1:SetAttribute("channelTarget", nil)
    _G.ChatEdit_UpdateHeader(eb1)

    -- ── Phase 8: the ICON RAIL — off by default, and only existing verbs. ─────
    ck(ns.DEFAULTS.skin.iconRail == false, "phase 8: the rail ships OFF by default")
    ck(Skin.styled[cf1].rail == nil, "phase 8: nothing was built while the rail is off")
    ns.db.skin.iconRail = true
    Skin.Refresh()
    local rail = Skin.styled[cf1].rail
    local rbtn = Skin.styled[cf1].railButtons
    ck(rail and rail._shown == true, "phase 8: turning it on builds the rail")
    ck(rbtn and rbtn.copy and rbtn.config and rbtn.bottom,
        "phase 8: three affordances: copy, settings, scroll-to-bottom")
    ck(near3(rail._backdropColor, UI.Color("panel")),
        "phase 8: the rail is a flat PANEL-token strip")
    for _, key in ipairs({ "copy", "config", "bottom" }) do
        local glyph = rbtn[key]._glyph
        ck(type(glyph) == "string" and glyph:match("^[\32-\126]+$") ~= nil,
            "phase 8: the '" .. key .. "' glyph is ASCII (the tofu law)")
        ck(near3(rbtn[key]._label._textColor, UI.Color("muted")),
            "phase 8: the '" .. key .. "' glyph is inked from the MUTED token")
    end
    -- CALL IDENTITY: each button holds the EXACT existing function it invokes.
    ck(rbtn.copy._verb == Skin.OpenCopy, "phase 8: copy is Skin.OpenCopy, not a new verb")
    ck(rbtn.config._verb == ns.SlashDispatch, "phase 8: settings is the /dchat dispatcher itself")
    ck(rbtn.bottom._verb == cf1.ScrollToBottom, "phase 8: scroll-to-bottom is the CLIENT's own frame method")
    Sim.ResetCalls()
    rbtn.bottom:GetScript("OnClick")(rbtn.bottom)
    ck(Sim.CallCount("ScrollToBottom") == 1, "phase 8: clicking it calls the client verb exactly once")
    ck(Sim.CallCount("AddMessage") == 0 and Sim.CallCount("CreateFrame") == 0,
        "phase 8: and does nothing else at all")
    copyWindow:Hide()
    rbtn.copy:GetScript("OnClick")(rbtn.copy)
    ck(copyWindow._shown == true, "phase 8: the copy button opens the existing copy window")
    copyWindow:Hide()
    ns.db.skin.iconRail = false
    Skin.Refresh()
    ck(rail._shown == false, "phase 8: turning it off puts the rail away")

    -- ── Phase 9: a temporary window opened mid-session gets styled. ───────────
    local hookCallsBefore = Sim.CallCount("FCF_OpenTemporaryWindow")
    local temp = _G.FCF_OpenTemporaryWindow("WHISPER", "Puu")
    ck(temp ~= nil, "phase 9: sim opened a temporary window")
    ck(Skin.styled[temp] ~= nil, "phase 9: the temp window was styled by the hook")
    local tempInk = select(2, tabText(temp))._textColor
    ck(near3(tempInk, CTI.WHISPER.r * dim, CTI.WHISPER.g * dim, CTI.WHISPER.b * dim),
        "phase 9: a whisper pop-out's tab wears whisper chat's client color")

    -- ── Phase 10: disable — full restore, and new activity goes untouched. ────
    ns.SetModuleEnabled("skin", false)
    ck(Skin.active == false, "phase 10: disabled")
    local rec1 = Skin.styled[_G.ChatFrame1]
    ck(rec1.backdrop._shown == false, "phase 10: backdrop hidden on disable")
    local stockBg = _G["ChatFrame1Background"]
    ck(stockBg and stockBg._alpha == (rec1.stock and rec1.stock.Background or 1),
        "phase 10: stock background texture alpha restored")
    ck(rec1.origFont and _G.ChatFrame1._font[1] == rec1.origFont[1],
        "phase 10: original chat font face restored")
    ck(Skin.styled[cf5].underline._shown == false and recDiv.divider._shown == false,
        "phase 10: the v2 surfaces (underline, divider) go away with everything else")
    ck(ns.EventHandlerCount("UPDATE_CHAT_COLOR") == colorSubsBase,
        "phase 10: the color listener was given back (count is the pre-enable baseline)")
    ck(ns.EventHandlerCount("CVAR_UPDATE") == cvarSubsBase,
        "phase 10: the CVar listener was given back too")
    local temp2 = _G.FCF_OpenTemporaryWindow("WHISPER", "Choco")
    ck(Skin.styled[temp2] == nil, "phase 10: a temp window opened while disabled stays stock")

    -- ── Phase 11: re-enable — idempotent, no duplicate rigs. ──────────────────
    local rigCount = #Skin.order
    ns.SetModuleEnabled("skin", true)
    ck(Skin.active == true, "phase 11: re-enabled")
    local rigCount2 = #Skin.order
    -- temp2 is eligible now and gets its own NEW rig; every pre-existing frame
    -- must reuse its old one.
    ck(rigCount2 <= rigCount + 1, "phase 11: re-enable reuses rigs (no duplicates)")
    ck(rec1.backdrop._shown == true, "phase 11: backdrop back")

    -- Hand the world back: the stock ten-window layout, the config branch the
    -- suites before us built, the client's stock channel table.
    Sim.serverChannels[9] = nil
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    if cfgStore then cfgStore.windows = savedCfgWindows end
    _G.FCF_SelectDockFrame(cf1)
    Skin.Refresh()
    Sim.ResetCalls()
end

ns:RegisterSelfTest("skin", function(verbose)
    local fails = {}
    local ok, err = pcall(testDefang, fails)
    if not ok then fails[#fails + 1] = "defang error: " .. tostring(err) end
    ok, err = pcall(testDominance, fails)
    if not ok then fails[#fails + 1] = "dominance error: " .. tostring(err) end
    ok, err = pcall(testCopyAndSkin, fails, verbose)
    if not ok then fails[#fails + 1] = "live error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL skin :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS skin") end
    return #fails == 0
end)

return Skin
