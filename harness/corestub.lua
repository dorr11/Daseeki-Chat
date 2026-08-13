-- =====================================================================
-- Daseeki-Chat harness — Daseeki-Core (DaseekiUI) stub.
--
-- A SIM of Core's public surface, not a copy: every color token resolves to a
-- deterministic SENTINEL color derived from the token NAME (plus a theme
-- epoch), so a test asserting "the widget wears UI.Color('panel')" proves the
-- addon read the TOKEN — a hardcoded color can never accidentally match.
-- Changing the epoch models a theme switch (every token moves), which is how
-- the reskin-on-ThemeChanged tests drive the addon.
--
-- Surface implemented (matching Daseeki-Core theme.lua/daseekiui.lua):
--   UI.Token / UI.Color / UI.FLAT_BACKDROP
--   UI.Skin / UI.FlatFrame / UI.MakeButton
--   UI.fonts (header/body/muted/small/accent/danger/ceremonial/microLabel/numeral)
--   UI.FontFile / UI.FontFileRaw / UI.GetFont / UI.GetFontScale
--   UI.fontRegistry / UI.RegisterFont / UI.FontNames  (the face registry Chat
--     RESOLVES its own chat-only face out of, read-only)
--   UI.OnThemeChanged / UI.OnFontChanged
-- Harness-only extras (double-underscored so nothing shippable can mistake
-- them for API): UI.__SetThemeEpoch(n), UI.__FireThemeChanged(),
-- UI.__FireFontChanged().
--
-- Requires chatsim.lua first (CreateFrame comes from the widget sim).
-- =====================================================================

local UI = {}
_G.DaseekiUI = UI

UI.FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Numeric tokens keep Core's real values (layout math must not drift under
-- test); color tokens are sentinels.
local NUMERIC_TOKENS = {
    rowGap = 10, sectionGap = 22, contentMaxW = 880,
    headerSize = 15, bodySize = 12, smallSize = 11,
}

local themeEpoch = 1

local function tokenColor(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 100003 end
    -- The epoch shifts every channel by a fixed step so epoch 1 vs 2 ALWAYS
    -- differ (no hash-collision flake).
    local r = ((h % 80) + themeEpoch * 7) / 100
    local g = (((math.floor(h / 80)) % 80) + themeEpoch * 5) / 100
    local b = (((math.floor(h / 6400)) % 80) + themeEpoch * 3) / 100
    return r, g, b
end

function UI.Token(name)
    if NUMERIC_TOKENS[name] then return NUMERIC_TOKENS[name] end
    return { tokenColor(name) }
end

function UI.Color(name, alpha)
    local r, g, b = tokenColor(name)
    return r, g, b, alpha or 1
end

-- Re-skin registry (real Core shape: run now + on every theme change).
local skins    = {}   -- ordered { obj, fn }
local themeCbs = {}
local fontCbs  = {}

function UI.Skin(obj, fn)
    fn(obj)
    skins[#skins + 1] = { obj, fn }
    return obj
end
function UI.OnThemeChanged(fn) themeCbs[#themeCbs + 1] = fn end
function UI.OnFontChanged(fn) fontCbs[#fontCbs + 1] = fn end

function UI.__SetThemeEpoch(n) themeEpoch = n end
function UI.__FireThemeChanged()
    for _, s in ipairs(skins) do pcall(s[2], s[1]) end
    for _, fn in ipairs(themeCbs) do pcall(fn) end
end
function UI.__FireFontChanged()
    for _, fn in ipairs(fontCbs) do pcall(fn) end
end

-- Shared font objects: plain recording stubs (widget-shaped enough for
-- SetFontObject consumers).
local function fontObject(role)
    return { _role = role,
        SetFont = function(self, face, size, flags) self._font = { face, size, flags } return true end,
        GetFont = function(self) local f = self._font or {}; return f[1], f[2], f[3] end,
        SetTextColor = function(self, r, g, b, a) self._textColor = { r, g, b, a } end,
        SetJustifyH = function(self, j) self._justifyH = j end,
    }
end
UI.fonts = {
    header = fontObject("header"), body = fontObject("body"),
    muted = fontObject("muted"), small = fontObject("small"),
    accent = fontObject("accent"), danger = fontObject("danger"),
    ceremonial = fontObject("ceremonial"), microLabel = fontObject("microLabel"),
    numeral = fontObject("numeral"),
}

----------------------------------------------------------------------
-- THE FONT REGISTRY — modeled on Core's real one (theme.lua), because Chat now
-- READS it (2026-08-12: the chat-only face resolves a NAME to a PATH out of
-- UI.fontRegistry). The old stub answered ONE constant path for every question
-- and a three-name list that did not match the registry — which is a KIND
-- client: a name-to-path resolver cannot be wrong when every name resolves to
-- the same file, and a picker cannot offer an unresolvable name when the list
-- and the registry never meet. Both hazards are real, so both are modeled:
--   * the names ARE the registry's keys (Core builds its picker the same way);
--   * every face has its OWN path, so "the box is wearing the face I picked"
--     is a claim with teeth;
--   * "Fira Sans Condensed Medium" is Core's SHIPPED default and maps to the
--     vendored file, exactly as the real registry does.
-- One registered name deliberately has no counterpart in FontNames' sort order
-- surprises: the list is sorted case-insensitively, as Core sorts it.
----------------------------------------------------------------------

local VENDORED_FACE = "Interface\\AddOns\\Daseeki-Core\\fonts\\FiraSansCondensed-Medium.ttf"
local FACE_FALLBACK = "Fonts\\FRIZQT__.TTF"

UI.fontRegistry = {
    ["Fira Sans Condensed Medium"] = VENDORED_FACE,
    ["Friz Quadrata"] = FACE_FALLBACK,
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\SKURRI.TTF",
    ["2002"]          = "Fonts\\2002.TTF",
    ["2002 Bold"]     = "Fonts\\2002B.TTF",
}
function UI.RegisterFont(name, path)
    if type(name) ~= "string" or name == "" then return end
    if type(path) ~= "string" or path == "" then return end
    if UI.fontRegistry[name] == nil then UI.fontRegistry[name] = path end
end

function UI.FontFileRaw() return UI.fontRegistry[UI.GetFont()] or FACE_FALLBACK end
function UI.FontFile() return UI.FontFileRaw() end
function UI.IsFaceFallback() return false, nil end

----------------------------------------------------------------------
-- THE SUITE-WIDE APPEARANCE SETTINGS (theme.lua's own accessors).
--
-- Modeled because the options rework's General section OFFERS them rather than
-- copying them: Font / Text size / Theme are Core's, and a chat-local copy
-- would be two settings that disagree. The sim keeps Core's real shape —
-- Get/Set pairs plus the name lists the pickers are built from — and firing the
-- theme callbacks on SetTheme is Core's own live-apply posture (which is also
-- Class 9's synchronous in-call dispatch: every listener runs to completion
-- before the setter returns).
----------------------------------------------------------------------

local fontChoice, fontScale = "Fira Sans Condensed Medium", 1.0
local themeOrder = { "Field Ledger", "Midnight", "Parchment" }
local themeName  = themeOrder[1]

function UI.GetFont() return fontChoice end
-- Core's own shape: the registry's keys, sorted case-insensitively.
function UI.FontNames()
    local names = {}
    for name in pairs(UI.fontRegistry) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end
function UI.SetFont(name)
    if type(name) ~= "string" or name == "" then return end
    fontChoice = name
    UI.__FireFontChanged()
end

function UI.GetFontScale() return fontScale end
function UI.SetFontScale(n)
    n = tonumber(n) or 1.0
    if n < 0.85 then n = 0.85 elseif n > 1.3 then n = 1.3 end
    fontScale = n
    UI.__FireFontChanged()
end

function UI.GetThemeName()  return themeName end
function UI.GetThemeNames() return themeOrder end
function UI.SetTheme(name)
    local ok = false
    for _, n in ipairs(themeOrder) do if n == name then ok = true end end
    if not ok then return end
    themeName = name
    -- A theme change moves every token: the epoch is what makes a test that
    -- asserts "the widget wears UI.Color('panel')" prove the addon RE-READ it.
    themeEpoch = themeEpoch + 1
    UI.__FireThemeChanged()
end

function UI.FlatFrame(parent, bgToken, borderToken)
    local f = _G.CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.Skin(f, function(self)
        self:SetBackdrop(UI.FLAT_BACKDROP)
        self:SetBackdropColor(UI.Color(bgToken or "panel"))
        self:SetBackdropBorderColor(UI.Color(borderToken or "border"))
    end)
    return f
end

function UI.MakeButton(parent, opts)
    opts = opts or {}
    local btn = _G.CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(opts.height or 24)
    btn:SetWidth(opts.width or 80)
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(UI.fonts.body)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(opts.text or "")
    UI.Skin(btn, function(self)
        self:SetBackdrop(UI.FLAT_BACKDROP)
        self:SetBackdropColor(UI.Color(opts.variant == "quiet" and "panel" or "control"))
        self:SetBackdropBorderColor(UI.Color(opts.variant == "danger" and "danger" or "controlBorder"))
    end)
    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
    btn._label = label
    return btn
end

----------------------------------------------------------------------
-- w2/options: THE HUB + THE FLOW API (additive).
--
-- Daseeki-Core's hub is where every suite addon's settings page lives
-- (DaseekiSuite:RegisterAddon{ flow = true }, sections with build(flow) /
-- refresh, and Core:ShowAddon driving them inside its Begin/EndShow latch).
-- The pane cannot be BUILT headless with real frames, so this stub models the
-- two things a test actually needs to be honest about:
--   1. REGISTRATION — the def an addon hands the hub, recorded verbatim, so a
--      suite can assert the id/title/flow/sections contract;
--   2. THE FLOW API — a recording implementation of the widget factories, so
--      build(flow) runs the REAL page builder and every control's get/set
--      closure is captured and drivable. A control that reads or writes the
--      wrong config field then fails a test instead of failing a player.
--
-- ════════════════════════════════════════════════════════════════════════
-- THE UNKIND REWRITE (2026-08-12) — "THERE ARE NO LABELS ON THE DROP DOWNS"
-- ════════════════════════════════════════════════════════════════════════
--
-- The owner's UAT found four surfaces rendering with NO CAPTION AT ALL: the
-- General dropdowns, the channel rows, the Tabs sub-tab buttons and the
-- per-tab channel checkboxes. Every one of them was GREEN here. The recording
-- flow was KINDER THAN CORE in three separate, independently fatal ways, and
-- each one hid one of the three real root causes:
--
--   KINDNESS 1 — "a Label always renders." Core's UI.MakeLabel returns a FRAME
--     carrying no `uiWidth` and never sized. Core's row arranger then does
--     `ww = w.uiWidth or w:GetWidth()` (= 0) and `w:SetWidth(ww)` — a
--     ZERO-WIDTH frame inside the clipping ScrollChild, which culls it and its
--     FontString. Core's own file names this exact defect class three times in
--     comments (the checkbox fix, the segmented fix, the stackBlocks net) and
--     the ROW-ITEM net it added covers HEIGHT only. So every `row:Label("Font")`
--     caption in the pane was invisible, and the dropdown beside it moved 8
--     units left. The stub recorded a label object and called it drawn.
--     => modeled: rec items carry Core's real uiWidth/_fillWidth, the row
--        ARRANGES them by Core's own rule, and an item left at width 0 is
--        CULLED (IsDrawn() == false).
--
--   KINDNESS 2 — "anything answers SetText." A Core Label is a FRAME; a frame
--     has no SetText, and the caption lives on frame._label. options.lua's
--     RefreshChannelRows called `ui.label:SetText(text)` behind a
--     `type(...)=="function"` guard, so in game the guard was false, the
--     `elseif ui.label._text` fallback did not match either, and the channel
--     name was NEVER WRITTEN. Here every rec widget answered SetText.
--     => modeled: a rec label has NO SetText method, exactly like the frame.
--
--   KINDNESS 3 — "Button:SetText paints the button." A real Button HAS a
--     SetText method, but Core's UI.MakeButton never calls SetFontString, so
--     the text goes to a fontstring that does not exist and the caption keeps
--     whatever it was born with. options_tabs.lua's nav relabel tried
--     `btn:SetText` FIRST — it "succeeded", the `elseif btn._label` branch was
--     unreachable, and all four sub-tab buttons stayed blank forever.
--     => modeled: a rec button HAS SetText, and it writes to a dead field that
--        no caption is ever read from — Core's behaviour exactly.
--
-- The pane audit (UI.__PaneAudit) turns all three into red: every shown
-- control must carry a DRAWN caption, either its own or a drawn Label in its
-- own row. A caption the kit does not draw is a failure, not a courtesy.
--
-- Still deliberately NOT modeled: scroll, clipping, pixel geometry. Those are
-- Core's and are pinned in Core's own repo. What IS modeled is the arithmetic
-- that decides whether a widget has a rect at all, because that is the
-- arithmetic that decided whether the owner could read his own settings.
----------------------------------------------------------------------

local Suite = { sections = {}, regOrder = {} }
_G.DaseekiSuite = Suite

function Suite:RegisterAddon(def)
    if type(def) ~= "table" or not def.id then return nil end
    -- Core's own synthesis: a def with no sections gets ONE implicit legacy
    -- section built from its addon-level build/options/refresh, so a legacy
    -- caller still has a page the hub can select.
    if not def.sections or #def.sections == 0 then
        def.sections = { { id = "_main", title = def.title or def.id,
                           build = def.build, options = def.options,
                           refresh = def.refresh, legacy = true } }
    else
        local defaultLegacy = not def.flow
        for i, s in ipairs(def.sections) do
            s.id = s.id or ("s" .. i)
            if s.legacy == nil then s.legacy = defaultLegacy end
        end
    end
    if not self.sections[def.id] then self.regOrder[#self.regOrder + 1] = def.id end
    self.sections[def.id] = def
    return def
end
function Suite:RegisterCorePage(def) return self:RegisterAddon(def) end

----------------------------------------------------------------------
-- THE HUB WINDOW, AS CORE ACTUALLY BEHAVES
-- (Daseeki-Core @919e544 — hub.lua ShowAddonPass/EnsureHub + core.lua
-- Open/Toggle/GetAddonSection, read not guessed).
--
-- ════════════════════════════════════════════════════════════════════════
-- THE KINDNESS THAT SHIPPED A DEFECT (owner UAT, 2026-08-12: "right clicking
-- the tab and clicking 'Open Settings' doesnt seem to work")
-- ════════════════════════════════════════════════════════════════════════
-- This stub used to be two recorders:
--     function Suite:Open(id) self._opened = id end
--     function Suite:ShowAddon(id, sectionId) self._shown = { id, sectionId } end
-- No window, no registry check, and — fatally — SYMMETRICAL: either call read
-- as "the settings opened". Real Core is not symmetrical at all:
--
--   * Core:ShowAddon SELECTS a page and NOTHING ELSE. It calls EnsureHub
--     (which CREATES the window HIDDEN), hides every built pane, records the
--     selection and shows the section's PANE. It never calls window:Show().
--     On any session where the player has not already opened the Daseeki
--     window, ShowAddon is completely invisible.
--   * Core:Open is the ONLY call that shows the window:
--         function Core:Open(id, sectionId)
--             self:EnsureHub()
--             if id then self:ShowAddon(id, sectionId) end
--             self.window:Show()
--         end
--     …and it shows the window even when the id is unknown, because
--     ShowAddon's refusal is silent — the player lands on the hub's default
--     page rather than on nothing.
--   * An UNREGISTERED addon id selects nothing: ShowAddonPass returns false
--     before it touches the selection record.
--   * An unknown SECTION id falls back to the addon's FIRST section
--     (Core:GetAddonSection), and a nil section id falls back to the section
--     that addon was last shown on.
--   * EnsureHub picks a default selection the first time it builds the window
--     (last addon, else the first suite entry ALPHABETICALLY by title).
--
-- All of that is modeled below. Class 9's Begin/EndShow latch is deliberately
-- NOT: it is Core's own contract, pinned in Core's own repo, and nothing in
-- this addon re-enters the hub from a build/refresh.
----------------------------------------------------------------------

-- Core's GetSuiteOrder: alphabetical by DISPLAY TITLE, ties broken on id.
local function suiteOrder()
    local out = {}
    for i, id in ipairs(Suite.regOrder) do out[i] = id end
    local function key(id)
        local def = Suite.sections[id]
        return string.lower(tostring((def and def.title) or id or ""))
    end
    table.sort(out, function(a, b)
        local ka, kb = key(a), key(b)
        if ka == kb then return a < b end
        return ka < kb
    end)
    return out
end

function Suite:GetAddonSections(addonId)
    local a = self.sections[addonId]
    return a and a.sections or {}
end

function Suite:GetAddonSection(addonId, sectionId)
    local secs = self:GetAddonSections(addonId)
    if sectionId then
        for _, s in ipairs(secs) do if s.id == sectionId then return s end end
    end
    return secs[1]
end

-- Builds the window HIDDEN and picks a default selection, exactly as Core's
-- EnsureHub does. Re-entrant-safe the same way Core's is: self.window is set
-- before the default ShowAddon runs.
function Suite:EnsureHub()
    if self.window then return self.window end
    self.window = { shown = false }
    self._lastSectionByAddon = self._lastSectionByAddon or {}
    local startId = self._lastAddon
    if not (startId and self.sections[startId]) then startId = suiteOrder()[1] end
    if startId then self:ShowAddon(startId) end
    return self.window
end

function Suite:ShowAddon(addonId, sectionId)
    self:EnsureHub()
    local addon = self.sections[addonId]
    if not addon then return false end                  -- a page that is not there
    sectionId = sectionId or self._lastSectionByAddon[addonId]
    local section = self:GetAddonSection(addonId, sectionId)
    if not section then return false end
    self._currentAddon, self._currentSection = addonId, section.id
    self._lastAddon = addonId
    self._lastSectionByAddon[addonId] = section.id
    self._shows = (self._shows or 0) + 1
    -- AND THAT IS ALL. The window's own shown state is untouched, because
    -- Core's ShowAddonPass never calls window:Show().
    return true
end
function Suite:ShowSection(id) return self:ShowAddon(id) end

function Suite:Open(addonId, sectionId)
    self:EnsureHub()
    if addonId then self:ShowAddon(addonId, sectionId) end
    self.window.shown = true            -- unconditional, as Core's Open is
    self._opens = (self._opens or 0) + 1
end

function Suite:Toggle(addonId, sectionId)
    self:EnsureHub()
    if self.window.shown then self.window.shown = false return end
    if addonId then self:ShowAddon(addonId, sectionId) end
    self.window.shown = true
end

function UI.__RegisteredAddon(id) return Suite.sections[id] end

-- What a PLAYER can see of the hub right now: is the window up, and which page
-- is it on. A test asserting "Open Settings worked" has to ask both.
function UI.__HubShown() return (Suite.window and Suite.window.shown) and true or false end
function UI.__HubBuilt() return Suite.window ~= nil end
function UI.__HubPage()  return Suite._currentAddon, Suite._currentSection end
function UI.__HubClose() if Suite.window then Suite.window.shown = false end end

-- HARNESS ONLY: model a session in which an addon never registered its page
-- (the state the inertness gate already pins as reachable — a module the
-- player turned off never reaches the hub at all). Returns the def so the
-- caller can put it back.
function UI.__RemoveAddon(id)
    local def = Suite.sections[id]
    if not def then return nil end
    Suite.sections[id] = nil
    for i, v in ipairs(Suite.regOrder) do
        if v == id then table.remove(Suite.regOrder, i) break end
    end
    if Suite._currentAddon == id then Suite._currentAddon, Suite._currentSection = nil, nil end
    if Suite._lastAddon == id then Suite._lastAddon = nil end
    return def
end

function UI.__ClearRegistry()
    Suite.sections, Suite.regOrder = {}, {}
    Suite.window = nil
    Suite._currentAddon, Suite._currentSection, Suite._lastAddon = nil, nil, nil
    Suite._lastSectionByAddon = {}
end

-- ── CORE'S OWN LAYOUT CONSTANTS (daseekiui.lua, read not guessed) ──────────
local ITEM_GAP = 8            -- horizontal gap between row items
-- The hub's content width, both ends. hub.lua: overhead is 264px and MIN_W is
-- 1140, so avail = min(W - 264, contentMaxW 880) — 876 at the narrowest window
-- the hub can be dragged to, 880 at any larger one. A pane that overflows 876
-- overflows for real, on a window the player can actually make.
UI.MIN_CONTENT_W = 876
UI.MAX_CONTENT_W = 880

-- A fontstring stub: the object Core's factories hang a caption on
-- (frame._label). It is NOT the widget — that distinction is the whole of
-- kindness 2 above.
local function recFontString(text)
    local fs = { _text = text or "" }
    function fs:SetText(t) self._text = tostring(t or "") end
    function fs:GetText() return self._text end
    function fs:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
    function fs:GetTextColor()
        local c = self._textColor or {}
        return c[1], c[2], c[3], c[4]
    end
    function fs:SetJustifyH(j) self._justifyH = j end
    -- A deterministic width MODEL (not a measurement): the stub has no font
    -- engine, and a flat "7 units a character" is enough to answer the only
    -- question the layout asks — is this wider than zero.
    function fs:GetStringWidth() return #self._text * 7 end
    return fs
end

-- Which kinds draw a caption of their own, and where it comes from. Straight
-- off daseekiui.lua: a Checkbox/Button/Label/Hint always draw one; a
-- Dropdown/EditBox draw one ONLY when opts.label is a non-empty string
-- (`hasLabel`), and draw NOTHING otherwise; a Segmented/Slider/List/Separator/
-- EditorCard have no caption of their own at all.
local CAPTION_FROM = {
    checkbox = function(o) return o.label end,
    button   = function(o) return o.text end,
    label    = function(o) return o.text end,
    hint     = function(o) return o.text end,
    dropdown = function(o) return (type(o.label) == "string" and o.label ~= "") and o.label or nil end,
    editbox  = function(o) return (type(o.label) == "string" and o.label ~= "") and o.label or nil end,
    slider   = function(o) return o.label end,
    editorcard = function(o) return o.title end,
}
-- Core's _fillWidth flags, verbatim: these stretch to the row's remaining
-- width, so they can never be culled. Everything else must carry a uiWidth or
-- it is a zero-width frame.
local FILL_WIDTH = {
    slider = true, editbox = true, hint = true, list = true,
    separator = true, editorcard = true,
}
-- The CONTROLS a player is expected to read a caption on. A separator has
-- nothing to say; a dropdown with no caption is the owner's screenshot.
local NEEDS_CAPTION = {
    checkbox = true, dropdown = true, editbox = true, button = true,
    slider = true, segmented = true,
}

-- Core's own intrinsic widths, per factory (daseekiui.lua).
local function intrinsicWidth(kind, opts, label)
    if kind == "dropdown"  then return opts.width or 180 end
    if kind == "editbox"   then return opts.width or 200 end
    if kind == "slider"    then return opts.width or 200 end
    if kind == "checkbox"  then return 18 + 6 + (label and #label * 7 or 0) + 4 end
    if kind == "button"    then return opts.width or math.max(80, (opts.text and #opts.text * 7 or 40) + 28) end
    if kind == "segmented" then
        local x = 0
        for _, c in ipairs(opts.choices or {}) do
            local t = (type(c) == "table") and (c.text or tostring(c.value)) or tostring(c)
            x = x + math.max(52, #t * 7 + 22) + 4
        end
        return math.max(1, x - 4)
    end
    -- LABEL AND HINT ANSWER NOTHING, exactly as Core's factories do. That nil
    -- is kindness 1's whole hazard: it is what becomes SetWidth(0).
    return nil
end

-- A recording widget. `_opts` is the exact table the page builder handed the
-- factory, so a test drives the control by calling _opts.set / _opts.get.
local function recWidget(kind, opts, pane, section, row)
    opts = opts or {}
    local w = { _kind = kind, _opts = opts, _section = section, _row = row,
                _shown = true, _width = 0, _height = 0 }

    local caption = CAPTION_FROM[kind] and CAPTION_FROM[kind](opts) or nil
    if caption ~= nil then w._label = recFontString(tostring(caption)) end
    w.uiWidth   = intrinsicWidth(kind, opts, caption)
    w._fillWidth = FILL_WIDTH[kind] or false

    function w:SetWidth(v) self._width = tonumber(v) or 0 end
    function w:GetWidth() return self._width or 0 end
    function w:SetHeight(v) self._height = tonumber(v) or 0 end
    function w:GetHeight() return self._height or 0 end
    function w:Show() self._shown = true end
    function w:Hide() self._shown = false end
    function w:SetShown(on) self._shown = on and true or false end
    function w:IsShown() return self._shown and true or false end

    -- KINDNESS 3, MODELED. A real Button has SetText; Core's MakeButton never
    -- calls SetFontString, so the text lands nowhere a caption is read from.
    -- The dead field exists so a test can prove the write happened AND that it
    -- changed nothing a player can see.
    if kind == "button" then
        function w:SetText(t) self._deadButtonText = tostring(t or "") end
        function w:GetText() return self._deadButtonText or "" end
    end
    -- KINDNESS 2, MODELED: a label is a FRAME. No SetText, at all. The caption
    -- is on w._label, which is where Core puts it and where an honest caller
    -- has to write.

    --   KINDNESS 4 — "set() is how an edit box saves." The stub used to expose
    --     an edit box as nothing but its `_opts` table, so every suite drove a
    --     field by CALLING `_opts.set(value)` directly. That tests the setter
    --     and never the WIDGET: it silently assumes something invokes `set`
    --     when the player finishes typing. Core's UI.MakeEditBox wires exactly
    --     TWO scripts — OnEnterPressed (commit) and OnEscapePressed (revert) —
    --     and NO OnEditFocusLost, so a player who types and then clicks away
    --     loses the lot and `set` is never called. That is the owner's "the
    --     TRADE nickname still does not save", and it survived a whole green
    --     suite because the sim had no focus and no keys to lose it with.
    --     => modeled: a rec editbox carries a real `editBox` with text, FOCUS
    --     and a script table, and it is born with CORE'S OWN two handlers and
    --     no third one. The hazard is present in the stub, so a suite that
    --     drives the widget the way a player does can see it.
    if kind == "editbox" then
        local box = { _text = "", _focused = false, _scripts = {} }
        function box:SetScript(name, fn) self._scripts[name] = fn end
        function box:GetScript(name) return self._scripts[name] end
        function box:HasScript() return true end
        function box:SetText(t) self._text = tostring(t or "") end
        function box:GetText() return self._text end
        function box:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
        function box:SetAutoFocus() end
        function box:HasFocus() return self._focused and true or false end
        function box:SetFocus() self._focused = true end
        -- Losing focus FIRES OnEditFocusLost — but only if the box actually had
        -- focus, exactly like the client.
        function box:ClearFocus()
            if not self._focused then return end
            self._focused = false
            local fn = self._scripts.OnEditFocusLost
            if type(fn) == "function" then fn(self) end
        end

        -- CORE'S OWN WIRING, VERBATIM (daseekiui.lua UI.MakeEditBox). Enter
        -- commits and drops focus; Escape repaints from `get` and drops focus;
        -- NOTHING listens for focus loss. A consumer that wants the third
        -- handler has to install it, and that install is what the suite pins.
        box:SetScript("OnEnterPressed", function(self)
            if type(opts.set) == "function" then opts.set(self:GetText()) end
            self:ClearFocus()
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(type(opts.get) == "function" and opts.get() or "")
            self:ClearFocus()
        end)

        -- ── HOW A SUITE DRIVES ONE, as a player does ────────────────────────
        -- Click in, type, and then leave by one of the three real exits.
        function box:PlayerTypes(text)
            self:SetFocus()
            self:SetText(text)
            return self
        end
        local function fire(self, name)
            local fn = self._scripts[name]
            if type(fn) == "function" then fn(self) end
            return self
        end
        function box:PressEnter()  return fire(self, "OnEnterPressed") end
        function box:PressEscape() return fire(self, "OnEscapePressed") end
        -- The exit the owner took: click somewhere else. No key is pressed;
        -- the box simply loses focus.
        function box:ClickAway() self:ClearFocus() return self end

        w.editBox = box
    end

    -- What a player can actually READ on this widget right now.
    function w:Caption()
        local t = self._label and self._label:GetText() or nil
        if t == nil or t == "" then return nil end
        return t
    end
    -- …and whether the widget has a rect at all (the culling rule).
    function w:IsDrawn()
        if not self._shown then return false end
        return (self._width or 0) >= 1
    end

    w.Refresh = function()
        local get = w._opts.get
        if type(get) == "function" then
            local ok, v = pcall(get)
            w._value = ok and v or nil
        end
        -- Core's own frame.Refresh REPAINTS THE BOX from `get` (daseekiui.lua:
        -- `frame.Refresh = function() box:SetText(opts.get and (opts.get() or "")) end`).
        -- Modeling it is what makes a lost edit visible: the field goes back to
        -- saying what the config says, which is exactly what the owner saw.
        if w.editBox then w.editBox:SetText(w._value or "") end
        w._refreshes = (w._refreshes or 0) + 1
        return w._value
    end
    w.Refresh()
    pane.controls[#pane.controls + 1] = w
    if row then row._items[#row._items + 1] = w end
    return w
end

-- CORE'S ROW ARRANGER, the non-centered path, verbatim in its arithmetic
-- (daseekiui.lua newRow.arrange). This is the function that decides whether a
-- caption exists on screen, so it is the function the stub has to run.
local function arrangeRow(row, width)
    local leftX, over = 0, false
    for _, w in ipairs(row._items) do
        if w._shown then
            local ww = w._fillWidth and nil or (w.uiWidth or w:GetWidth())
            if w._fillWidth then ww = math.max(40, width - leftX) end
            -- `if ww then w:SetWidth(ww) end` — and when uiWidth is nil AND the
            -- widget was never sized, ww is 0 and this is SetWidth(0).
            if ww then w:SetWidth(ww) end
            leftX = leftX + (ww or w.uiWidth or 80) + ITEM_GAP
        end
    end
    if leftX - ITEM_GAP > width then over = true end
    row._laidWidth = leftX - ITEM_GAP
    row._overflow = over
    return over
end

local function newRecFlow(pane, section, row)
    local flow = { _section = section, _row = row }
    -- Core's `convenience(name)`: a widget added to a FLOW gets a row of its
    -- own; one added to a ROW joins that row. Both paths end in the same row
    -- arranger, which is why both have to exist here.
    local function adder(kind)
        return function(self, opts)
            if self._row then return recWidget(kind, opts, pane, self._section, self._row) end
            local r = self:AddRow()
            return recWidget(kind, opts, pane, self._section, r._row)
        end
    end
    flow.Checkbox        = adder("checkbox")
    flow.Slider          = adder("slider")
    flow.Dropdown        = adder("dropdown")
    flow.EditBox         = adder("editbox")
    flow.Button          = adder("button")
    flow.SegmentedChoice = adder("segmented")
    flow.List            = adder("list")
    function flow:Label(text, o)
        o = o or {}
        o.text = text
        if self._row then return recWidget("label", o, pane, self._section, self._row) end
        local r = self:AddRow()
        return recWidget("label", o, pane, self._section, r._row)
    end
    function flow:Hint(text)
        local w = recWidget("hint", { text = text }, pane, self._section, self._row)
        w._text = text
        pane.hints[#pane.hints + 1] = w
        return w
    end
    function flow:AddSeparator()
        return recWidget("separator", {}, pane, self._section, self._row)
    end
    -- Core's bordered, titled card that hosts a nested flow (MakeEditorCard).
    -- The form language's GROUP BOX is this widget, so the stub carries it.
    function flow:EditorCard(opts)
        local card = recWidget("editorcard", opts or {}, pane, self._section, self._row)
        card.uiHeight = (opts and opts.height) or 180
        card.flow = newRecFlow(pane, self._section, nil)
        card.flow._card = card
        function card:Relayout() self._relayouts = (self._relayouts or 0) + 1 end
        pane.cards[#pane.cards + 1] = card
        return card
    end
    function flow:AddRow(opts)
        local r = { _items = {}, _opts = opts }
        local sub = newRecFlow(pane, self._section, r)
        r._flow = sub
        sub._isRow = true
        pane.rows[#pane.rows + 1] = r
        -- A row created on a CARD's flow belongs to that card's own pane, but
        -- the widths it lays against are the card's inner width.
        r._avail = self._card and "card" or "pane"
        return sub
    end
    -- Core's two-column checkbox grid (AddChecklist). It self-sizes every box,
    -- so a checklist box is never culled — which is exactly why the form
    -- language reaches for it.
    function flow:AddChecklist(items)
        local grid = { _boxes = {}, _kind = "checklist" }
        for _, it in ipairs(items or {}) do
            local box = recWidget("checkbox", it, pane, self._section, nil)
            box:SetWidth(box.uiWidth or 1)     -- MakeCheckbox self-sizes (Core)
            grid._boxes[#grid._boxes + 1] = box
        end
        pane.checklists[#pane.checklists + 1] = grid
        return grid
    end
    function flow:AddSection(title)
        pane.sections[#pane.sections + 1] = title
        return newRecFlow(pane, title, nil)
    end
    return flow
end

-- Lay every recorded row at a given content width, exactly as Core's pane
-- Layout would. Called at both ends of the hub's real width range, so an
-- overflow only the NARROW window shows is still a failure.
function UI.__ArrangePane(pane, width)
    width = width or UI.MIN_CONTENT_W
    pane._arrangedAt = width
    pane._overflowRows = {}
    for _, r in ipairs(pane.rows or {}) do
        -- A card's inner flow lays against the card's inner width, not the
        -- page's (MakeEditorCard's inner pane is padded by 10 a side).
        local avail = (r._avail == "card") and (width - 20) or width
        if arrangeRow(r, avail) then
            pane._overflowRows[#pane._overflowRows + 1] = r
        end
    end
    return pane
end

-- THE PANE AUDIT — the red control for the blank-label defect class.
-- Returns a list of problem strings; empty means every control a player can
-- see carries a caption a player can read.
function UI.__PaneAudit(pane)
    local out = {}
    if type(pane) ~= "table" then return { "no pane" } end
    -- Which row a control sits in, and the drawn labels in that row.
    for _, w in ipairs(pane.controls or {}) do
        if w._shown and NEEDS_CAPTION[w._kind] then
            local own = w:Caption()
            local drawnOwn = own and w:IsDrawn()
            local via = nil
            if not drawnOwn and w._row then
                for _, sib in ipairs(w._row._items) do
                    if sib ~= w and sib._kind == "label" and sib._shown
                       and sib:Caption() and sib:IsDrawn() then
                        via = sib:Caption()
                        break
                    end
                end
            end
            if not drawnOwn and not via then
                local why
                if own and not w:IsDrawn() then
                    why = "its own caption is CULLED (width " .. tostring(w:GetWidth()) .. ")"
                elseif own then
                    why = "?"
                else
                    why = "no caption, and no drawn label in its row"
                end
                out[#out + 1] = ("%s [%s]: %s"):format(w._kind,
                    tostring(own or (w._opts and (w._opts.id or w._opts.text)) or "?"), why)
            end
        end
        -- A caption that EXISTS but is culled is a defect even when a sibling
        -- rescues the control: it is text the builder meant to show.
        if w._shown and w._kind == "label" and w:Caption() and not w:IsDrawn() then
            out[#out + 1] = ("label [%s]: written but CULLED (width %s)")
                :format(w:Caption(), tostring(w:GetWidth()))
        end
    end
    for _, r in ipairs(pane._overflowRows or {}) do
        out[#out + 1] = ("a row overflows the page (%d items, %s of %s units)")
            :format(#r._items, tostring(r._laidWidth), tostring(pane._arrangedAt))
    end
    -- TWO ITEMS BOTH CLAIMING THE REMAINING WIDTH. Core's row arranger gives
    -- the FIRST `_fillWidth` item everything left over, so the second is
    -- squeezed to its 40-unit floor — which is why the channel rows rendered as
    -- one enormous hex field beside a stub of a rename field. Any row with two
    -- of them is that defect, whether or not anybody has looked at it yet.
    for _, r in ipairs(pane.rows or {}) do
        local fills = {}
        for _, w in ipairs(r._items) do
            if w._shown and w._fillWidth then fills[#fills + 1] = w._kind end
        end
        if #fills > 1 then
            out[#out + 1] = ("a row carries %d items that all claim the remaining width (%s): "
                .. "the first swallows it and the rest are squeezed to Core's 40-unit floor")
                :format(#fills, table.concat(fills, ","))
        end
    end
    return out
end

-- Build (and refresh) one registered section, returning the recording pane.
-- Mirrors Core's own order: build once, then refresh — the sequence hub.lua
-- runs inside its show latch — and then LAYS IT OUT, because a pane that has
-- never been laid out cannot answer whether anything is on screen.
function UI.__BuildPane(addonId, sectionId)
    local def = Suite.sections[addonId]
    if not def then return nil end
    local section
    for _, s in ipairs(def.sections or {}) do
        if not sectionId or s.id == sectionId then section = s break end
    end
    if not section then return nil end
    local pane = { controls = {}, sections = {}, rows = {}, hints = {},
                   cards = {}, checklists = {},
                   addonId = addonId, sectionId = section.id }
    local flow = newRecFlow(pane, nil, nil)
    pane.flow = flow
    if section.build then section.build(flow) end
    if section.refresh then section.refresh(pane) end
    UI.__ArrangePane(pane, UI.MIN_CONTENT_W)
    section._pane = pane
    return pane
end

-- Re-run a built section's refresh (the beat Core runs on every re-show), then
-- re-lay it: a refresh that re-points a pooled row changes what is on screen,
-- so the arrangement has to follow it.
function UI.__RefreshPane(addonId, sectionId, width)
    local def = Suite.sections[addonId]
    if not def then return nil end
    for _, s in ipairs(def.sections or {}) do
        if (not sectionId or s.id == sectionId) and s.refresh then
            s.refresh(s._pane)
            if s._pane then UI.__ArrangePane(s._pane, width or UI.MIN_CONTENT_W) end
            return s._pane
        end
    end
    return nil
end

return UI
