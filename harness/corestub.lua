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
--   UI.FontFile / UI.GetFont / UI.GetFontScale
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

local VENDORED_FACE = "Interface\\AddOns\\Daseeki-Core\\fonts\\FiraSansCondensed-Medium.ttf"
function UI.FontFile() return VENDORED_FACE end
function UI.FontFileRaw() return VENDORED_FACE end
function UI.GetFont() return "Fira Sans Condensed Medium" end
function UI.GetFontScale() return 1.0 end
function UI.IsFaceFallback() return false, nil end

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
-- Deliberately NOT modeled: layout, scroll, geometry. Those are Core's, they
-- are pinned in Core's own repo, and pretending to have them here would only
-- invite assertions that prove nothing.
----------------------------------------------------------------------

local Suite = { sections = {}, regOrder = {} }
_G.DaseekiSuite = Suite

function Suite:RegisterAddon(def)
    if type(def) ~= "table" or not def.id then return nil end
    if not self.sections[def.id] then self.regOrder[#self.regOrder + 1] = def.id end
    self.sections[def.id] = def
    return def
end
function Suite:RegisterCorePage(def) return self:RegisterAddon(def) end
function Suite:Open(id) self._opened = id end
function Suite:ShowAddon(id, sectionId) self._shown = { id, sectionId } end

function UI.__RegisteredAddon(id) return Suite.sections[id] end
function UI.__ClearRegistry() Suite.sections, Suite.regOrder = {}, {} end

-- A recording widget. `_opts` is the exact table the page builder handed the
-- factory, so a test drives the control by calling _opts.set / _opts.get.
local function recWidget(kind, opts, pane, section)
    local w = { _kind = kind, _opts = opts or {}, _section = section }
    w.Refresh = function()
        local get = w._opts.get
        if type(get) == "function" then
            local ok, v = pcall(get)
            w._value = ok and v or nil
        end
        w._refreshes = (w._refreshes or 0) + 1
        return w._value
    end
    w.Refresh()
    pane.controls[#pane.controls + 1] = w
    return w
end

local function newRecFlow(pane, section)
    local flow = { _section = section }
    local function adder(kind)
        return function(self, opts) return recWidget(kind, opts, pane, self._section) end
    end
    flow.Checkbox        = adder("checkbox")
    flow.Slider          = adder("slider")
    flow.Dropdown        = adder("dropdown")
    flow.EditBox         = adder("editbox")
    flow.Button          = adder("button")
    flow.SegmentedChoice = adder("segmented")
    flow.List            = adder("list")
    function flow:Label(text)
        local w = recWidget("label", { text = text }, pane, self._section)
        w._text = text
        return w
    end
    function flow:Hint(text)
        local w = recWidget("hint", { text = text }, pane, self._section)
        w._text = text
        w._label = { SetText = function(_, t) w._text = t end,
                     GetText = function() return w._text end }
        pane.hints[#pane.hints + 1] = w
        return w
    end
    function flow:AddSeparator()
        return recWidget("separator", {}, pane, self._section)
    end
    function flow:AddRow(opts)
        local row = newRecFlow(pane, self._section)
        row._isRow = true
        pane.rows[#pane.rows + 1] = row
        return row
    end
    function flow:AddSection(title)
        pane.sections[#pane.sections + 1] = title
        return newRecFlow(pane, title)
    end
    return flow
end

-- Build (and refresh) one registered section, returning the recording pane.
-- Mirrors Core's own order: build once, then refresh — the sequence hub.lua
-- runs inside its show latch.
function UI.__BuildPane(addonId, sectionId)
    local def = Suite.sections[addonId]
    if not def then return nil end
    local section
    for _, s in ipairs(def.sections or {}) do
        if not sectionId or s.id == sectionId then section = s break end
    end
    if not section then return nil end
    local pane = { controls = {}, sections = {}, rows = {}, hints = {},
                   addonId = addonId, sectionId = section.id }
    local flow = newRecFlow(pane, nil)
    if section.build then section.build(flow) end
    if section.refresh then section.refresh(pane) end
    section._pane = pane
    return pane
end

-- Re-run a built section's refresh (the beat Core runs on every re-show).
function UI.__RefreshPane(addonId, sectionId)
    local def = Suite.sections[addonId]
    if not def then return nil end
    for _, s in ipairs(def.sections or {}) do
        if (not sectionId or s.id == sectionId) and s.refresh then
            s.refresh(s._pane)
            return s._pane
        end
    end
    return nil
end

return UI
