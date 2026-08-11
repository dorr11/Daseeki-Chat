-- Daseeki Chat — skin.lua  (Wave 1, real)
-- The skin-over treatment of the client's ten chat windows: suite-themed frame
-- backdrops and tab styling, a themed ATTACHED edit box (the panel-bar look —
-- the survey's ElvUI archetype; NEVER a custom message view), Core font roles
-- applied to every window's text, configurable text fading, and the per-window
-- COPY-CHAT affordance (era has no clipboard: a themed window shows the frame's
-- visible text pre-selected in an edit box for Ctrl+C).
--
-- Everything visual reads Daseeki-Core theme tokens at render (DaseekiUI.Color/
-- Token / FLAT_BACKDROP / UI.Skin / UI.fonts / UI.FontFile) — ZERO hardcoded
-- colors anywhere in this file; alpha/measure constants only.
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
-- we restyle its text through the Core small font role and dim the unselected
-- docked tabs — selection tracked via the FCF_SelectDockFrame hook below.
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

function Skin.UpdateTabColors()
    local UI = UIKit()
    if not UI then return end
    local sel = selectedDockFrame()
    for _, frame in ipairs(Skin.order) do
        local tab, text = tabText(frame)
        if tab and text then
            local isSel = (frame == sel)
            if type(text.SetTextColor) == "function" then
                text:SetTextColor(UI.Color(isSel and "accent" or "muted"))
            end
            if type(tab.SetAlpha) == "function" then
                tab:SetAlpha(isSel and 1 or TAB_DIM)
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
    rec.tabStyled = true
end

----------------------------------------------------------------------
-- Edit box: the attached panel-bar look (survey archetype). Re-anchored as a
-- bar spanning the window's width, below or above per config; stock art
-- stripped; a flat token backdrop behind it; Core body font.
----------------------------------------------------------------------

local EB_REGIONS = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function editBoxOf(frame)
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. "EditBox"] or nil
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
    end
    ensureCopyButton(frame, rec)
end

local function restoreWindow(frame, rec)
    restoreStock(frame, rec)
    if rec.backdrop then rec.backdrop:Hide() end
    if rec.copyBtn then rec.copyBtn:Hide() end
    restoreEditBox(frame, rec)
    if rec.origFont and type(frame.SetFont) == "function" then
        pcall(frame.SetFont, frame, rec.origFont[1], rec.origFont[2], rec.origFont[3])
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

-- Re-apply everything that is not covered by UI.Skin's automatic re-color
-- (fonts and tab state read tokens imperatively).
function Skin.Reskin()
    if not Skin.active then return end
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        applyFrameFont(frame, rec and rec.id)
    end
    Skin.UpdateTabColors()
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
            Skin.UpdateTabColors()
        end)
    end
    -- Dock selection changes recolor the tab row (accent = selected).
    if type(_G.FCF_SelectDockFrame) == "function" then
        hook("FCF_SelectDockFrame", function()
            if not Skin.active then return end
            Skin.UpdateTabColors()
        end)
    end
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
    Skin.StyleAll()
end

function Skin.OnDisable()
    Skin.active = false
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec then restoreWindow(frame, rec) end
    end
    if copyWindow then copyWindow:Hide() end
end

ns.RegisterModule("skin", Skin)

ns.RegisterDebugCommand("skin", "skin state: styled windows, config, activity", function()
    ns:Print(("skin: %s, %d window(s) styled"):format(
        Skin.active and "active" or "inactive", #Skin.order))
    local c = cfg()
    ns:Print(("  fading=%s fadeTime=%s editBox=%s copyButton=%s"):format(
        tostring(c.fading), tostring(c.fadeTime), tostring(c.editBox), tostring(c.copyButton)))
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

    -- Tab ink: selected wears accent, others muted (token values, not colors).
    local sel = _G.GeneralDockManager and _G.GeneralDockManager.selected
    for _, frame in ipairs(Skin.order) do
        local _, text = tabText(frame)
        if text and text._textColor then
            local want = { UI.Color(frame == sel and "accent" or "muted") }
            ck(math.abs(text._textColor[1] - want[1]) < 1e-6,
                "phase 1: tab ink for " .. tostring(frame:GetName()) .. " reads the right token")
        end
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

    -- ── Phase 5: a temporary window opened mid-session gets styled. ───────────
    local hookCallsBefore = Sim.CallCount("FCF_OpenTemporaryWindow")
    local temp = _G.FCF_OpenTemporaryWindow("WHISPER", "Puu")
    ck(temp ~= nil, "phase 5: sim opened a temporary window")
    ck(Skin.styled[temp] ~= nil, "phase 5: the temp window was styled by the hook")

    -- ── Phase 6: disable — full restore, and new activity goes untouched. ─────
    ns.SetModuleEnabled("skin", false)
    ck(Skin.active == false, "phase 6: disabled")
    local rec1 = Skin.styled[_G.ChatFrame1]
    ck(rec1.backdrop._shown == false, "phase 6: backdrop hidden on disable")
    local stockBg = _G["ChatFrame1Background"]
    ck(stockBg and stockBg._alpha == (rec1.stock and rec1.stock.Background or 1),
        "phase 6: stock background texture alpha restored")
    ck(rec1.origFont and _G.ChatFrame1._font[1] == rec1.origFont[1],
        "phase 6: original chat font face restored")
    local temp2 = _G.FCF_OpenTemporaryWindow("WHISPER", "Choco")
    ck(Skin.styled[temp2] == nil, "phase 6: a temp window opened while disabled stays stock")

    -- ── Phase 7: re-enable — idempotent, no duplicate rigs. ───────────────────
    local rigCount = #Skin.order
    ns.SetModuleEnabled("skin", true)
    ck(Skin.active == true, "phase 7: re-enabled")
    local rigCount2 = #Skin.order
    -- temp2 is eligible now and gets its own NEW rig; every pre-existing frame
    -- must reuse its old one.
    ck(rigCount2 <= rigCount + 1, "phase 7: re-enable reuses rigs (no duplicates)")
    ck(rec1.backdrop._shown == true, "phase 7: backdrop back")
end

ns:RegisterSelfTest("skin", function(verbose)
    local fails = {}
    local ok, err = pcall(testDefang, fails)
    if not ok then fails[#fails + 1] = "defang error: " .. tostring(err) end
    ok, err = pcall(testCopyAndSkin, fails, verbose)
    if not ok then fails[#fails + 1] = "live error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL skin :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS skin") end
    return #fails == 0
end)

return Skin
