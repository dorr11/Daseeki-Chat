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

return UI
