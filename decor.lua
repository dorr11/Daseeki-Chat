-- Daseeki Chat — decor.lua  (Wave 2: pipeline, real)
-- The shared message pipeline: ONE seam per chat window (an AddMessage wrap)
-- and a protect-tokenize-restore engine that every display feature rides.
--
-- THE STRUCTURAL LAW (the Prat coupling bug, made impossible): hyperlink
-- protection is UNCONDITIONAL and lives HERE, in the engine, never in a
-- feature. Before any decorator pattern runs, every |H...|h hyperlink
-- (color-decorated or bare), every |K...|k protected span, every texture
-- escape and every raid-target token is lifted out of the text and replaced
-- by an opaque placeholder ("\1<serial>\2" — an alphabet no URL, name or
-- link pattern can satisfy); decorators run over the protected text only;
-- placeholders are restored last, in one pass, with a function replacement
-- (so restored text is never re-scanned and needs no escaping). Disabling
-- any feature — or every feature — can therefore never remove protection,
-- because protection is not a feature: it is the transport. The suite pins
-- this with the exact red control the Prat spec flags (URL-ish text around a
-- live item link while everything is disabled or actively hostile).
--
-- Two decorator classes:
--   * body decorators  fn(protectedText, lift, frame) -> newText
--       Ascending priority order over protected text. Output a decorator
--       injects via lift() is itself tokenized, so a later decorator can
--       never corrupt an earlier decorator's link markup.
--   * link decorators  fn(linkType, payload, display, frame) -> newDisplay
--       Run at lift time on each hyperlink, STRUCTURALLY: the engine parses
--       |H<type>:<payload>|h<display>|h, offers only the display text, and
--       rebuilds the link itself. A decorator cannot touch a payload even by
--       being malicious — returns carrying |H/|h/|K/|T markup are rejected.
--
-- Consumers: stamps.lua registers a POST-ADD observer (runs after the client
-- stores the line — the display-layer beat); names.lua registers a link
-- decorator; urls.lua registers a body decorator. Each registers in its own
-- OnEnable and unregisters in OnDisable, so the engine can run with zero
-- features, and a post-add feature keeps working with decoration disabled —
-- no coupling in either direction.
--
-- INERTNESS: nothing installs until the first OnEnable of a seam consumer.
-- The per-frame AddMessage wraps and the one hooksecurefunc (temp-window
-- catcher) are permanent once installed (first enable) and their bodies gate
-- on live state — the skin.lua precedent. Combat-log windows are never
-- touched (survey law: no chat addon hooks the combat log).

local ADDON, ns = ...

local Decor = {
    active = false,      -- decoration gate (the module's enable state)
    hooked = false,      -- one-time temp-window hooksecurefunc installed
    _stats = { processes = 0, protects = 0, restores = 0 },
}
ns.Decor = Decor

----------------------------------------------------------------------
-- Registries.
----------------------------------------------------------------------

local bodyDecorators = {}   -- ordered by (priority, seq): { name, priority, seq, fn }
local linkDecorators = {}   -- same shape
local postAdds       = {}   -- registration order: { name, fn(frame) }
local regSeq         = 0

local function removeNamed(list, name)
    for i = #list, 1, -1 do
        if list[i].name == name then table.remove(list, i) end
    end
end

local function insertSorted(list, entry)
    list[#list + 1] = entry
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.seq < b.seq
    end)
end

function Decor.RegisterDecorator(name, priority, fn)
    removeNamed(bodyDecorators, name)
    regSeq = regSeq + 1
    insertSorted(bodyDecorators, { name = name, priority = tonumber(priority) or 50, seq = regSeq, fn = fn })
end
function Decor.UnregisterDecorator(name) removeNamed(bodyDecorators, name) end

function Decor.RegisterLinkDecorator(name, priority, fn)
    removeNamed(linkDecorators, name)
    regSeq = regSeq + 1
    insertSorted(linkDecorators, { name = name, priority = tonumber(priority) or 50, seq = regSeq, fn = fn })
end
function Decor.UnregisterLinkDecorator(name) removeNamed(linkDecorators, name) end

function Decor.RegisterPostAdd(name, fn)
    for i = 1, #postAdds do
        if postAdds[i].name == name then postAdds[i].fn = fn return end
    end
    postAdds[#postAdds + 1] = { name = name, fn = fn }
end
function Decor.UnregisterPostAdd(name)
    for i = #postAdds, 1, -1 do
        if postAdds[i].name == name then table.remove(postAdds, i) end
    end
end

function Decor.DecoratorCount() return #bodyDecorators, #linkDecorators, #postAdds end

----------------------------------------------------------------------
-- Secret values (era game fact): certain payloads cannot be string-handled;
-- every path passes them through untouched. Shimmed absent (older clients).
----------------------------------------------------------------------

local function isSecret(v)
    local f = _G.issecretvalue
    if type(f) == "function" then
        local ok, res = pcall(f, v)
        return ok and res or false
    end
    return false
end

----------------------------------------------------------------------
-- The protect pass. Placeholder alphabet: "\1<serial>\2". Control bytes never
-- occur in server chat (and are stripped from input as insurance), digits
-- alone satisfy no URL/name/link pattern, and the delimiters make every token
-- unambiguous, so a single function-replacement gsub restores losslessly
-- without reverse-serial bookkeeping or escaping.
----------------------------------------------------------------------

-- Raid-target tokens: {rt1}..{rt8} plus the named tags (ICON_TAG_LIST words).
local RAID_WORDS = {
    star = true, circle = true, diamond = true, triangle = true,
    moon = true, square = true, cross = true, skull = true,
}

-- Run link decorators over one lifted hyperlink, structurally. If nothing
-- changes (or the shape is unusual) the ORIGINAL bytes are kept — the engine
-- only ever rebuilds when a decorator actually edited the display text.
local function runLinkDecorators(s, frame)
    if #linkDecorators == 0 then return s end
    local colorPrefix, ty, pay, disp =
        s:match("^(|c%x%x%x%x%x%x%x%x)|H([^:|]+):(.-)|h(.-)|h|r$")
    if not ty then
        colorPrefix = nil
        ty, pay, disp = s:match("^|H([^:|]+):(.-)|h(.-)|h$")
    end
    if not ty then return s end   -- colon-less/unusual link: never guess
    local changed = false
    for i = 1, #linkDecorators do
        local ok, nd = pcall(linkDecorators[i].fn, ty, pay, disp, frame)
        if not ok then
            ns.RouteError(nd)
        elseif type(nd) == "string" and nd ~= disp
            and not nd:find("|H", 1, true) and not nd:find("|h", 1, true)
            and not nd:find("|K", 1, true) and not nd:find("|T", 1, true) then
            disp, changed = nd, true
        end
    end
    if not changed then return s end
    local core = "|H" .. ty .. ":" .. pay .. "|h" .. disp .. "|h"
    if colorPrefix then return colorPrefix .. core .. "|r" end
    return core
end

local function protect(text, frame)
    Decor._stats.protects = Decor._stats.protects + 1
    local store, n = {}, 0
    local function lift(s)
        n = n + 1
        store[n] = s
        return "\1" .. n .. "\2"
    end
    -- 1. Color-decorated hyperlinks first, so the color wrapper travels WITH
    --    its link and a later pass cannot orphan the |r (the Prat-spec rank
    --    ordering, reproduced).
    text = text:gsub("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r",
        function(s) return lift(runLinkDecorators(s, frame)) end)
    -- 2. Bare hyperlinks.
    text = text:gsub("|H.-|h.-|h",
        function(s) return lift(runLinkDecorators(s, frame)) end)
    -- 3. Battle.net protected spans (atomic by client law).
    text = text:gsub("|K.-|k", lift)
    -- 4. Texture escapes.
    text = text:gsub("|T.-|t", lift)
    -- 5. Raid-target tokens (one pass; non-matches fall through untouched).
    text = text:gsub("{(%w+)}", function(w)
        local lw = w:lower()
        if RAID_WORDS[lw] or lw:match("^rt%d+$") then
            return lift("{" .. w .. "}")
        end
        -- returning nil keeps the original {word} unlifted
    end)
    return text, store, lift
end

local function restore(text, store)
    Decor._stats.restores = Decor._stats.restores + 1
    return (text:gsub("\1(%d+)\2", function(k)
        return store[tonumber(k)] or ("\1" .. k .. "\2")
    end))
end

----------------------------------------------------------------------
-- Process — the whole pipeline over one line. Pure over its input; callable
-- headless. One protect pass and one restore pass per message NO MATTER HOW
-- MANY decorators are registered (the budget pin).
----------------------------------------------------------------------

function Decor.Process(text, frame)
    if type(text) ~= "string" then return text end
    Decor._stats.processes = Decor._stats.processes + 1
    -- \r exploit guard (game fact: an embedded carriage return fakes extra
    -- chat lines) + placeholder-byte hygiene before tokenizing.
    if text:find("\r", 1, true) then text = text:gsub("\r", " ") end
    if text:find("\1", 1, true) or text:find("\2", 1, true) then
        text = text:gsub("[\1\2]", "")
    end
    local protected, store, lift = protect(text, frame)
    for i = 1, #bodyDecorators do
        local d = bodyDecorators[i]
        local ok, res = pcall(d.fn, protected, lift, frame)
        if not ok then
            ns.RouteError(res)
        elseif type(res) == "string" then
            protected = res
        end
    end
    return restore(protected, store)
end

----------------------------------------------------------------------
-- The seam: one AddMessage wrap per window. Decoration runs pre-store (gated
-- on Decor.active); post-add observers run AFTER the client stored the line —
-- the newest history-buffer entry is the line just printed, which is exactly
-- the display-layer beat stamps.lua needs. Post-adds are present only while
-- their owner module is enabled (registered in OnEnable, gone in OnDisable),
-- so an empty loop is the disabled state.
----------------------------------------------------------------------

local seams     = {}   -- frame -> original AddMessage
local seamOrder = {}   -- frames in install order

local function isCombatLogFrame(frame)
    local f = _G.IsCombatLog
    if type(f) == "function" then
        local ok, res = pcall(f, frame)
        if ok then return res and true or false end
    end
    return frame == _G.ChatFrame2   -- runtime-defended fallback
end

function Decor.HasSeam(frame) return seams[frame] ~= nil end
function Decor.SeamCount() return #seamOrder end

local function installSeam(frame)
    if not frame or seams[frame] then return end
    if isCombatLogFrame(frame) then return end
    local orig = frame.AddMessage
    if type(orig) ~= "function" then return end
    seams[frame] = orig
    seamOrder[#seamOrder + 1] = frame
    frame.AddMessage = function(f, text, ...)
        if Decor.active and type(text) == "string" and not isSecret(text) then
            text = Decor.Process(text, f)
        end
        orig(f, text, ...)
        for i = 1, #postAdds do
            local ok, err = pcall(postAdds[i].fn, f)
            if not ok then ns.RouteError(err) end
        end
    end
end

-- Install seams on every current window (permanent ten minus the combat log,
-- plus any already-open temporaries) and arm the temp-window catcher once.
-- Consumers (stamps) call this from their OnEnable too, so the seam exists
-- whether or not the decoration engine itself is enabled.
function Decor.EnsureSeams()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        installSeam(_G["ChatFrame" .. id])
    end
    for id = (_G.NUM_CHAT_WINDOWS or 10) + 1, 50 do
        local frame = _G["ChatFrame" .. id]
        if frame then installSeam(frame) end
    end
    if not Decor.hooked then
        Decor.hooked = true
        local hook = _G.hooksecurefunc
        if type(hook) == "function" and type(_G.FCF_OpenTemporaryWindow) == "function" then
            hook("FCF_OpenTemporaryWindow", function()
                -- Body gates on live state: with everything disabled this
                -- scan never runs and new windows stay untouched.
                if not (Decor.active or #postAdds > 0) then return end
                for id = (_G.NUM_CHAT_WINDOWS or 10) + 1, 50 do
                    local frame = _G["ChatFrame" .. id]
                    if frame and not seams[frame] then installSeam(frame) end
                end
            end)
        end
    end
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function Decor.OnEnable()
    Decor.active = true
    Decor.EnsureSeams()
end

function Decor.OnDisable()
    -- The wraps stay as gated shells (the hooksecurefunc precedent): with
    -- active false and no post-adds registered, a wrapped AddMessage is a
    -- byte-exact pass-through — the suite pins that, not just asserts it.
    Decor.active = false
end

ns.RegisterModule("decor", Decor)

ns.RegisterDebugCommand("pipeline", "message pipeline: seams, decorators, stats", function()
    local nb, nl, np = Decor.DecoratorCount()
    ns:Print(("pipeline: %s, %d seam(s), %d body / %d link decorator(s), %d post-add(s)")
        :format(Decor.active and "active" or "inactive", Decor.SeamCount(), nb, nl, np))
    ns:Print(("  processed=%d protect-passes=%d restore-passes=%d")
        :format(Decor._stats.processes, Decor._stats.protects, Decor._stats.restores))
end)

----------------------------------------------------------------------
-- Self-tests (suite "decor").
----------------------------------------------------------------------

local function testEngine(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim

    -- ── Phase 0: inertness + the disabled-EVERYTHING red control. ────────────
    ck(Decor.active == false, "phase 0: module inactive after disabled login")
    ck(Decor.SeamCount() == 0, "phase 0: zero seams installed while disabled")
    ck(Decor.hooked == false, "phase 0: temp-window hook not installed while disabled")
    if Sim then
        -- Nothing enabled anywhere in the pipeline: a hyperlink surrounded by
        -- URL-ish text must land in the buffer byte-identical to the client's
        -- own line (the Prat coupling bug's victim scenario, ground state).
        local line = Sim.SendChat{ event = "CHAT_MSG_SAY",
            text = "see www.example.com and " .. Sim.MakeItemLink() .. " at example.com.",
            sender = "Puu-Whitemane", guid = "Player-1-00000001" }
        local newest = Sim.Frame(1).historyBuffer:GetEntryAtIndex(1)
        ck(newest and newest.message == line,
            "phase 0 RED CONTROL: with everything disabled the stored line is byte-identical")
    end

    -- ── Phase 1: pure protect/restore roundtrip (zero decorators). ───────────
    local roundtrips = {
        "plain text with no markup at all",
        "|cffa335ee|Hitem:19019|h[Thunderfury, Blessed Blade]|h|r drops",
        "|Hplayer:Puu-Whitemane:101|h[Puu]|h says hi",
        "from |Kq7|k with love",
        "kill {rt8} then {skull} now",
        "icon |TInterface\\Icons\\Foo:16|t here",
        "escaped 50%||50% pipes",
        "|Hchannel:channel:2|h[2. World]|h |Hplayer:A:9|h[A]|h: mixed |Hitem:1|h[x.y]|h end",
        "www.example.com stays raw while nothing is enabled",
    }
    for _, s in ipairs(roundtrips) do
        ck(Decor.Process(s) == s, "phase 1: lossless roundtrip: " .. s:sub(1, 40))
    end
    ck(Decor.Process("a\rb") == "a b", "phase 1: \\r exploit neutralized to a space")

    -- ── Phase 2: THE coupling red control — a hostile body decorator cannot
    -- touch a hyperlink, a |K span, or a raid token, because protection is the
    -- engine's, not any feature's. ───────────────────────────────────────────
    local itemLink = "|cffa335ee|Hitem:19019|h[www.thunderfury.com]|h|r"
    Decor.RegisterDecorator("t_hostile", 50, function(text)
        return (text:gsub("%.", "!"))   -- corrupts every dot it can see
    end)
    local out = Decor.Process("look " .. itemLink .. " at www.example.com or |Kx.y|k {rt3}")
    ck(out:find(itemLink, 1, true) ~= nil,
        "phase 2 RED CONTROL: hostile decorator ran, item link (URL-ish display!) is byte-intact")
    ck(out:find("|Kx.y|k", 1, true) ~= nil, "phase 2: |K span survived the hostile decorator")
    ck(out:find("{rt3}", 1, true) ~= nil, "phase 2: raid token survived the hostile decorator")
    ck(out:find("www!example!com", 1, true) ~= nil,
        "phase 2: plain body text WAS transformed (the decorator did run)")
    Decor.UnregisterDecorator("t_hostile")
    ck(Decor.Process("back to " .. itemLink) == "back to " .. itemLink,
        "phase 2: unregistered decorator leaves a pure roundtrip again")

    -- ── Phase 3: priority order (ascending, stable). ─────────────────────────
    Decor.RegisterDecorator("t_second", 20, function(text) return text .. "B" end)
    Decor.RegisterDecorator("t_first", 10, function(text) return text .. "A" end)
    ck(Decor.Process("x") == "xAB", "phase 3: decorators run in ascending priority order")
    Decor.UnregisterDecorator("t_second")
    Decor.UnregisterDecorator("t_first")

    -- ── Phase 4: link decorators are structural — display only, payload
    -- untouchable, malicious returns rejected. ───────────────────────────────
    Decor.RegisterLinkDecorator("t_upper", 10, function(ty, pay, disp)
        if ty == "item" then return disp:upper() end
    end)
    local out4 = Decor.Process("get " .. itemLink .. " now")
    ck(out4:find("|Hitem:19019|h", 1, true) ~= nil, "phase 4: payload byte-intact through a display edit")
    ck(out4:find("[WWW.THUNDERFURY.COM]", 1, true) ~= nil, "phase 4: display text transformed")
    ck(out4:find("|cffa335ee", 1, true) ~= nil and out4:find("|h|r", 1, true) ~= nil,
        "phase 4: the color wrapper still travels with its link")
    Decor.UnregisterLinkDecorator("t_upper")
    Decor.RegisterLinkDecorator("t_evil", 10, function() return "|h|Hboom:1|hgotcha" end)
    ck(Decor.Process("a " .. itemLink) == "a " .. itemLink,
        "phase 4 RED CONTROL: a link decorator returning link markup is rejected wholesale")
    Decor.UnregisterLinkDecorator("t_evil")

    -- ── Phase 5: budget — one protect pass + one restore pass per message,
    -- regardless of decorator count (no re-walk per decorator). ──────────────
    Decor.RegisterDecorator("t_b1", 10, function(t) return t end)
    Decor.RegisterDecorator("t_b2", 20, function(t) return t end)
    Decor.RegisterDecorator("t_b3", 30, function(t) return t end)
    local p0, r0 = Decor._stats.protects, Decor._stats.restores
    Decor.Process("one message " .. itemLink .. " with three decorators registered")
    ck(Decor._stats.protects == p0 + 1, "phase 5 BUDGET: exactly one protect pass per message")
    ck(Decor._stats.restores == r0 + 1, "phase 5 BUDGET: exactly one restore pass per message")
    Decor.UnregisterDecorator("t_b1")
    Decor.UnregisterDecorator("t_b2")
    Decor.UnregisterDecorator("t_b3")
end

local function testSeam(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end

    -- ── Phase 6: enable — seams on every window except the combat log. ───────
    ns.SetModuleEnabled("decor", true)
    ck(Decor.active == true, "phase 6: enabled")
    ck(Decor.SeamCount() > 0, "phase 6: seams installed")
    ck(Decor.HasSeam(Sim.Frame(1)) == true, "phase 6: ChatFrame1 has the seam")
    ck(Decor.HasSeam(Sim.Frame(2)) == false, "phase 6: the combat log is NEVER seamed")

    -- Zero decorators + live seam: still a byte-exact roundtrip.
    local line = Sim.SendChat{ event = "CHAT_MSG_SAY",
        text = "live " .. Sim.MakeItemLink() .. " at www.example.com.",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    local newest = Sim.Frame(1).historyBuffer:GetEntryAtIndex(1)
    ck(newest and newest.message == line,
        "phase 6 RED CONTROL: active engine with zero decorators stores a byte-identical line")

    -- A live decorator transforms body text but not the links in it.
    Decor.RegisterDecorator("t_tag", 50, function(text) return text .. " ~tag~" end)
    local line2 = Sim.SendChat{ event = "CHAT_MSG_SAY", text = "decorate me",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    local n2 = Sim.Frame(1).historyBuffer:GetEntryAtIndex(1)
    ck(n2 and n2.message:find("~tag~", 1, true) ~= nil, "phase 6: live decoration reached the buffer")
    ck(n2 and n2.message:find("|Hplayer:Puu-Whitemane", 1, true) ~= nil,
        "phase 6: the player link's payload rode through untouched")
    Decor.UnregisterDecorator("t_tag")

    -- Post-adds run AFTER the client stored the line.
    local sawCount
    Decor.RegisterPostAdd("t_probe", function(frame)
        if frame == Sim.Frame(4) then sawCount = frame:GetNumMessages() end
    end)
    local before = Sim.Frame(4):GetNumMessages()
    Sim.Frame(4):AddMessage("post-add ordering probe", 1, 1, 1)
    ck(sawCount == before + 1,
        "phase 6: post-add observers run after the line is IN the buffer (display-layer beat)")
    Decor.UnregisterPostAdd("t_probe")

    -- A temporary window opened mid-session gets the seam via the hook.
    local temp = _G.FCF_OpenTemporaryWindow("WHISPER", "Zed")
    ck(temp and Decor.HasSeam(temp) == true, "phase 6: a new temporary window is seamed on open")

    -- ── Phase 7: disable — the wrap is a byte-exact pass-through even with a
    -- hostile decorator still registered. ────────────────────────────────────
    Decor.RegisterDecorator("t_hostile2", 50, function(text) return (text:gsub("%.", "!")) end)
    ns.SetModuleEnabled("decor", false)
    ck(Decor.active == false, "phase 7: disabled")
    local line3 = Sim.SendChat{ event = "CHAT_MSG_SAY",
        text = "off " .. Sim.MakeItemLink() .. " at www.example.com.",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    local n3 = Sim.Frame(1).historyBuffer:GetEntryAtIndex(1)
    ck(n3 and n3.message == line3,
        "phase 7 RED CONTROL: disabled pipeline + registered hostile decorator = byte-identical line")
    Decor.UnregisterDecorator("t_hostile2")

    -- Leave the engine enabled for the sibling feature suites, and hand the
    -- sim's call counters back clean (suites that run after us pin pristine
    -- counts — the wave convention).
    ns.SetModuleEnabled("decor", true)
    Sim.ResetCalls()
end

ns:RegisterSelfTest("decor", function(verbose)
    local fails = {}
    local ok, err = pcall(testEngine, fails)
    if not ok then fails[#fails + 1] = "engine error: " .. tostring(err) end
    ok, err = pcall(testSeam, fails)
    if not ok then fails[#fails + 1] = "seam error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL decor :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS decor") end
    return #fails == 0
end)

return Decor
