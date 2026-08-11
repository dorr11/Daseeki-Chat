-- Daseeki Chat — urls.lua  (Wave 2: pipeline, real)
-- URL detection over PROTECTED text (decor.lua lifts every |H...|h hyperlink,
-- |K span, texture and raid token before this decorator ever runs, so an
-- item/spell link can never be corrupted or re-matched here — structurally,
-- not by discipline). One body decorator, one gsub pass per message: the text
-- is walked as whitespace-delimited tokens (which IS the spec's "start of
-- body or after whitespace" anchor — a maximal %S+ run can begin nowhere
-- else) and each token is classified in code, not by a pattern zoo.
--
-- Families (the Prat spec's behavioral matching, with its flagged defects
-- consciously fixed):
--   1. explicit scheme  — letter, then letters/digits/+/./-, then "://",
--      then any non-space run. No scheme whitelist, no TLD gate.
--   2. www. prefix      — validated as a multi-label host, TLD-gated.
--   3. bare domain      — one-or-more labels + all-letters terminal label,
--      optional :port and /path, TLD-gated.
--   Consciously fixed vs the observed addon: trailing punctuation (.,;:!?
--   quotes, and an unpaired closing paren) is NOT captured into the URL, and
--   a leading ( [ quote is stripped before matching. Emails are out of scope
--   for v1 (the spec's mid-word email family is a defect magnet).
--
-- THE TLD GATE is a maintained set, one place, dated — the anti-lesson is the
-- observed addon's frozen 2008 IANA snapshot that fails every modern gTLD.
-- Honest staleness note lives on the table itself.
--
-- Rendering: a matched URL becomes an "addon:dchaturl:" custom hyperlink in
-- the suite's accent token ink, display bracketed by config. Clicking routes
-- through SetItemRef (raw-replaced once, body gated, originals chained) to a
-- select-all edit-box popup — era has no clipboard API; a focused,
-- pre-highlighted edit box is the only copy affordance that exists.

local ADDON, ns = ...

local Urls = {
    active = false,
    hookedItemRef = false,
    _stats = { matches = 0, clicks = 0 },
}
ns.Urls = Urls

local DEFAULTS = {
    brackets = true,   -- display the URL in [brackets]
}

-- Published for the settings pane's bind-check (see stamps.lua's note).
Urls.DEFAULTS = DEFAULTS

local LINK_PREFIX = "addon:dchaturl:"
local POPUP_ID = "DASEEKI_CHAT_URL"

local function cfg()
    return (ns.db and ns.db.urls) or DEFAULTS
end

----------------------------------------------------------------------
-- The TLD gate.
-- Curated 2026-08-10 from the current IANA registry's high-traffic slice:
-- the classic generics, the modern gTLDs that actually appear in chat, and
-- the common ccTLDs. HONEST STALENESS NOTE: the full registry holds ~1450
-- entries and moves; this set does not auto-update. A miss on an exotic TLD
-- leaves the text plain (scheme:// always works regardless) — extend the set
-- HERE, in this one place, as misses appear.
----------------------------------------------------------------------

local TLDS = {}
for _, t in ipairs({
    -- classic generics
    "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz", "name",
    "pro", "aero", "asia", "cat", "coop", "jobs", "mobi", "museum", "tel",
    "travel", "post", "xxx",
    -- modern gTLDs seen in the wild
    "app", "dev", "page", "xyz", "online", "site", "website", "store", "shop",
    "blog", "club", "news", "live", "life", "world", "today", "space", "tech",
    "cloud", "email", "group", "plus", "one", "top", "vip", "win", "fun",
    "art", "design", "studio", "video", "wiki", "chat", "games", "game",
    "stream", "link", "click", "download", "zone", "network", "digital",
    "ai",
    -- common ccTLDs (many used as generics)
    "us", "uk", "de", "fr", "nl", "be", "es", "it", "pt", "se", "no", "fi",
    "dk", "pl", "cz", "sk", "at", "ch", "ie", "is", "ru", "ua", "by", "kz",
    "tr", "gr", "ro", "bg", "hu", "hr", "rs", "si", "lt", "lv", "ee", "il",
    "sa", "ae", "qa", "in", "pk", "lk", "cn", "jp", "kr", "tw", "hk", "sg",
    "my", "th", "vn", "ph", "id", "au", "nz", "ca", "mx", "br", "ar", "cl",
    "co", "pe", "uy", "za", "eg", "ma", "ng", "ke", "io", "gg", "im", "je",
    "sh", "ac", "tv", "fm", "am", "ws", "cc", "me", "su", "eu", "to", "ly",
    "gd", "nu",
}) do TLDS[t] = true end

local function gatedTld(label)
    return type(label) == "string" and TLDS[label:lower()] == true
end

----------------------------------------------------------------------
-- Token classification (pure; the suite drives it directly).
----------------------------------------------------------------------

local TRAIL_PUNCT = {
    ["."] = true, [","] = true, [";"] = true, [":"] = true,
    ["!"] = true, ["?"] = true, ["'"] = true, ["\""] = true,
}
local LEAD_PUNCT = {
    ["("] = true, ["["] = true, ["'"] = true, ["\""] = true,
}

-- Split a token into lead punctuation, core candidate, trail punctuation.
function Urls.SplitTrim(tok)
    local lead, trail = "", ""
    while #tok > 0 and LEAD_PUNCT[tok:sub(1, 1)] do
        lead = lead .. tok:sub(1, 1)
        tok = tok:sub(2)
    end
    while #tok > 0 do
        local ch = tok:sub(-1)
        if TRAIL_PUNCT[ch] then
            tok = tok:sub(1, -2)
            trail = ch .. trail
        elseif ch == ")" and not tok:find("(", 1, true) then
            tok = tok:sub(1, -2)
            trail = ch .. trail
        else
            break
        end
    end
    return lead, tok, trail
end

-- Classify one whitespace-delimited candidate. Returns the URL, or nil.
function Urls.Classify(tok)
    if type(tok) ~= "string" or tok == "" then return nil end
    -- Escapes and protection placeholders are never URL material. The engine
    -- already lifted real links; a stray pipe means markup we must not touch.
    if tok:find("|", 1, true) or tok:find("\1", 1, true) or tok:find("\2", 1, true) then
        return nil
    end
    if tok:find("@", 1, true) then return nil end   -- emails: out of scope (v1)
    -- Family 1: explicit scheme. Any well-formed scheme, no TLD gate.
    if tok:match("^%a[%w%+%.%-]*://%S") then return tok end
    -- Families 2/3: host [:port] [/path], TLD-gated. (www. is just a label.)
    local host, rest = tok:match("^([%w_%%%-%.]+)(.*)$")
    if not host or host == "" then return nil end
    if rest ~= "" then
        if not (rest:match("^:%d+$") or rest:match("^:%d+/%S*$") or rest:match("^/%S*$")) then
            return nil
        end
    end
    if not host:find("%.") then return nil end
    if host:find("%.%.") or host:sub(1, 1) == "." or host:sub(-1) == "." then return nil end
    local tld = host:match("%.(%a%a+)$")   -- all-letters terminal label, >= 2
    if not tld or not gatedTld(tld) then return nil end
    return tok
end

----------------------------------------------------------------------
-- Rendering.
----------------------------------------------------------------------

local function accentHex()
    local UI = _G.DaseekiUI
    if UI and UI.Color then
        local ok, r, g, b = pcall(UI.Color, "accent")
        if ok and type(r) == "number" then
            return ("%02x%02x%02x"):format(
                math.floor(math.max(0, math.min(1, r)) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, g)) * 255 + 0.5),
                math.floor(math.max(0, math.min(1, b)) * 255 + 0.5))
        end
    end
    return "ffffff"
end

function Urls.BuildLink(url)
    local disp = cfg().brackets and ("[" .. url .. "]") or url
    return ("|cff%s|H%s%s|h%s|h|r"):format(accentHex(), LINK_PREFIX, url, disp)
end

-- The body decorator: one gsub pass; matches are injected through the
-- engine's lift() so no later decorator (and no restore quirk) can touch the
-- link markup we just minted.
local function decorateBody(text, lift)
    if not Urls.active then return text end
    return (text:gsub("(%s?)(%S+)", function(ws, tok)
        local lead, core, trail = Urls.SplitTrim(tok)
        local url = core ~= "" and Urls.Classify(core) or nil
        if not url then return ws .. tok end
        Urls._stats.matches = Urls._stats.matches + 1
        return ws .. lead .. lift(Urls.BuildLink(url)) .. trail
    end))
end

----------------------------------------------------------------------
-- Click -> the select-all copy popup (the only copy path on era).
----------------------------------------------------------------------

local function ensureDialog()
    local dialogs = _G.StaticPopupDialogs
    if type(dialogs) ~= "table" or dialogs[POPUP_ID] then return end
    local function hideParent(box)
        local p = box and box.GetParent and box:GetParent()
        if p and p.Hide then p:Hide() end
    end
    dialogs[POPUP_ID] = {
        text = "%s",
        button1 = _G.OKAY or "Okay",
        hasEditBox = 1,
        editBoxWidth = 350,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,   -- game fact: popup slots are scarce; hint away from collisions
        OnShow = function(self)
            local eb = self.editBox
                or (self.GetName and _G[tostring(self:GetName()) .. "EditBox"])
            local url = self.data
            if eb and url then
                eb:SetText(url)
                if eb.SetFocus then eb:SetFocus() end
                if eb.HighlightText then eb:HighlightText() end
            end
        end,
        EditBoxOnEscapePressed = hideParent,
        EditBoxOnEnterPressed = hideParent,
        EditBoxOnTextChanged = function(self, userInput)
            -- Read-back surface: a user edit re-fills and re-selects, so the
            -- copy keystroke always grabs the whole URL.
            local p = self.GetParent and self:GetParent()
            local url = p and p.data
            if userInput and url and self.GetText and self:GetText() ~= url then
                self:SetText(url)
                if self.HighlightText then self:HighlightText() end
            end
        end,
    }
end

function Urls.ShowCopyPopup(url)
    if type(url) ~= "string" or url == "" then return end
    Urls._stats.clicks = Urls._stats.clicks + 1
    ensureDialog()
    if type(_G.StaticPopup_Show) ~= "function" then return end
    local dialog = _G.StaticPopup_Show(POPUP_ID, "URL: " .. url, nil, url)
    if type(dialog) == "table" and dialog.data == nil then dialog.data = url end
    return dialog
end

-- SetItemRef carries every unhandled link click. Raw-replaced ONCE on first
-- enable (the client would otherwise route our invented type into the item-
-- reference tooltip as an invalid link); our type is always swallowed, the
-- popup only fires while the module is active, everything else chains to the
-- original untouched.
local function installClickHook()
    if Urls.hookedItemRef then return end
    Urls.hookedItemRef = true
    local orig = _G.SetItemRef
    _G.SetItemRef = function(ref, ...)
        if type(ref) == "string" and ref:sub(1, #LINK_PREFIX) == LINK_PREFIX then
            if Urls.active then
                Urls.ShowCopyPopup(ref:sub(#LINK_PREFIX + 1))
            end
            return
        end
        if type(orig) == "function" then return orig(ref, ...) end
    end
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function Urls.OnEnable()
    Urls.active = true
    if ns.db then ns.EnsureDefaults(ns.db, { urls = DEFAULTS }) end
    ensureDialog()
    installClickHook()
    ns.Decor.RegisterDecorator("urls", 50, decorateBody)
end

function Urls.OnDisable()
    Urls.active = false
    ns.Decor.UnregisterDecorator("urls")
end

ns.RegisterModule("urls", Urls)

ns.RegisterDebugCommand("urls", "url detection state: matches, clicks, TLD set size", function()
    local n = 0
    for _ in pairs(TLDS) do n = n + 1 end
    ns:Print(("urls: %s, %d match(es), %d click(s), %d TLD(s) in the gate, brackets=%s")
        :format(Urls.active and "active" or "inactive",
            Urls._stats.matches, Urls._stats.clicks, n, tostring(cfg().brackets)))
end)

----------------------------------------------------------------------
-- Self-tests (suite "urls").
----------------------------------------------------------------------

local function testUrls(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local Decor = ns.Decor

    -- ── Phase 0: inertness. ──────────────────────────────────────────────────
    ck(Urls.active == false, "phase 0: module inactive after disabled login")
    ck(Urls.hookedItemRef == false, "phase 0: SetItemRef untouched while disabled")
    ck(Decor.Process("see www.example.com now") == "see www.example.com now",
        "phase 0: URL-ish text passes untouched while disabled")

    -- ── Phase 1: enable + the scheme family (no TLD gate). ───────────────────
    ns.SetModuleEnabled("urls", true)
    ck(Urls.active == true, "phase 1: enabled")
    local out1 = Decor.Process("get https://foo.blog/x?a=1 now")
    ck(out1:find("|Haddon:dchaturl:https://foo.blog/x?a=1|h", 1, true) ~= nil,
        "phase 1: scheme URLs linkify with the full URL as payload")
    ck(out1:find("[https://foo.blog/x?a=1]", 1, true) ~= nil,
        "phase 1: display is the bracketed URL")
    ck(out1:find("|cff" .. accentHex(), 1, true) ~= nil,
        "phase 1: link ink is the theme ACCENT token, not a hardcoded color")
    ck(Decor.Process("join ts3server://voice.example now")
        :find("|Haddon:dchaturl:ts3server://voice.example|h", 1, true) ~= nil,
        "phase 1: any well-formed scheme linkifies (no whitelist, no gate)")

    -- ── Phase 2: the www family + the TLD gate. ──────────────────────────────
    ck(Decor.Process("visit www.example.com rocks")
        :find("|Haddon:dchaturl:www.example.com|h", 1, true) ~= nil,
        "phase 2: www.-prefixed hosts linkify")
    local plain2 = "visit www.example.qqzzt now"
    ck(Decor.Process(plain2) == plain2,
        "phase 2 RED CONTROL: a garbage terminal label fails the TLD gate and stays plain")

    -- ── Phase 3: bare domains — and the anti-frozen-snapshot pin. ────────────
    ck(Decor.Process("meet at example.com today")
        :find("|Haddon:dchaturl:example.com|h", 1, true) ~= nil,
        "phase 3: a bare two-label domain linkifies")
    ck(Decor.Process("grab foo.xyz now")
        :find("|Haddon:dchaturl:foo.xyz|h", 1, true) ~= nil,
        "phase 3 RED CONTROL: a post-2008 gTLD passes — the gate is NOT a frozen snapshot")
    ck(Decor.Process("logs at raid.example.io/report tonight")
        :find("|Haddon:dchaturl:raid.example.io/report|h", 1, true) ~= nil,
        "phase 3: multi-label host with a path linkifies")
    ck(Decor.Process("server at play.example.gg:8085 now")
        :find("|Haddon:dchaturl:play.example.gg:8085|h", 1, true) ~= nil,
        "phase 3: host:port linkifies")
    local plain3 = "totally.fake garbage and a version number 1.2.3 stay plain"
    ck(Decor.Process(plain3) == plain3,
        "phase 3: non-TLD dots (and dotted numbers) never linkify")

    -- ── Phase 4: punctuation discipline (the consciously-fixed defect). ──────
    local out4 = Decor.Process("see example.com.")
    ck(out4 == "see " .. Urls.BuildLink("example.com") .. ".",
        "phase 4: a sentence-final dot stays OUTSIDE the URL")
    local out4b = Decor.Process("(see www.example.com)")
    ck(out4b == "(see " .. Urls.BuildLink("www.example.com") .. ")",
        "phase 4: wrapping parens stay outside the URL")

    -- ── Phase 5: protection pin — item/spell links can NEVER match. ──────────
    local itemUrlLink = "|cffa335ee|Hitem:19019|h[www.thunderfury.com]|h|r"
    local out5 = Decor.Process("look " .. itemUrlLink .. " at www.example.com")
    ck(out5:find(itemUrlLink, 1, true) ~= nil,
        "phase 5 RED CONTROL: an item link with a URL-ish display is byte-intact")
    ck(out5:find("|Haddon:dchaturl:www.example.com|h", 1, true) ~= nil,
        "phase 5: the real URL beside it still linkified")
    ck(Decor.Process(out5) == out5,
        "phase 5: re-processing an already-decorated line changes nothing (idempotent)")

    -- ── Phase 6: click -> the select-all popup; foreign links chain through. ─
    local D = _G.StaticPopupDialogs[POPUP_ID]
    ck(D ~= nil, "phase 6: the popup dialog is registered")
    if D then
        ck(D.hasEditBox == 1 and D.editBoxWidth == 350, "phase 6: wide edit box declared")
        ck(D.timeout == 0 and D.whileDead == 1 and D.hideOnEscape == 1,
            "phase 6: no timeout, usable while dead, escape closes")
        ck(D.preferredIndex ~= nil, "phase 6: preferredIndex set (popup-slot collision hint)")
        -- Drive OnShow against a fake popup: the edit box must be filled,
        -- focused and pre-highlighted — zero extra clicks before Ctrl+C.
        local fakeBox = Sim.NewWidget("EditBox", nil, nil)
        local fake = { data = "https://x.io", editBox = fakeBox }
        D.OnShow(fake)
        ck(fakeBox._text == "https://x.io", "phase 6: edit box pre-filled with the URL")
        ck(fakeBox._focused == true, "phase 6: edit box focused")
        ck(fakeBox._highlighted == true, "phase 6: text pre-highlighted for the copy keystroke")
    end
    local popsBefore = Sim.CallCount("StaticPopup_Show")
    local origRefCalls = Sim.CallCount("SetItemRef")
    _G.SetItemRef(LINK_PREFIX .. "https://x.io")
    ck(Sim.CallCount("StaticPopup_Show") == popsBefore + 1,
        "phase 6: clicking our link type opens the popup")
    ck(Sim.CallCount("SetItemRef") == origRefCalls,
        "phase 6: our link type is swallowed — the client's handler never sees it")
    _G.SetItemRef("item:19019")
    ck(Sim.CallCount("SetItemRef") == origRefCalls + 1,
        "phase 6: foreign link types chain through to the original untouched")

    -- ── Phase 7: budget — one pass, however many URLs. ───────────────────────
    local p0 = Decor._stats.protects
    local m0 = Urls._stats.matches
    Decor.Process("a.com then b.net then www.c.org done", nil)
    ck(Decor._stats.protects == p0 + 1, "phase 7 BUDGET: three URLs, one protect pass")
    ck(Urls._stats.matches == m0 + 3, "phase 7: all three URLs matched in that one pass")

    -- ── Phase 8: live through the seam, then disable. ────────────────────────
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "check www.example.com",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    local live = Sim.Frame(1).historyBuffer:GetEntryAtIndex(1).message
    ck(live:find("|Haddon:dchaturl:www.example.com|h", 1, true) ~= nil,
        "phase 8: a live chat line through the seam carries the copy link")
    ns.SetModuleEnabled("urls", false)
    ck(Decor.Process("see example.com now") == "see example.com now",
        "phase 8: disabled module linkifies nothing")
    ns.SetModuleEnabled("urls", true)

    -- Tidy for the suites that run after us (the wave convention).
    Sim.ResetCalls()
end

ns:RegisterSelfTest("urls", function(verbose)
    local fails = {}
    local ok, err = pcall(testUrls, fails)
    if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL urls :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS urls") end
    return #fails == 0
end)

return Urls
