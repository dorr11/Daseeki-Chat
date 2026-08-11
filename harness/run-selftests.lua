-- =====================================================================
-- Daseeki-Chat headless self-test harness  (REAL Lua 5.1)
--
-- Loads the whole shipping load list under the UNKIND chat simulator
-- (harness/chatsim.lua) and the Daseeki-Core sentinel stub
-- (harness/corestub.lua), runs the release gates (toc parse / toc identity /
-- inertness / chat-sim rig), then every ns:RegisterSelfTest suite.
--
-- Usage:  lua5.1 run-selftests.lua [CHAT_DIR]
--   CHAT_DIR defaults to the repo root one level up from this file.
--   Exit code 0 = ALL PASS.
-- =====================================================================

local HARNESS_DIR = (arg[0]:match("^(.*)[\\/][^\\/]+$")) or "."
local function slash(p) return (p:gsub("\\", "/")) end
HARNESS_DIR = slash(HARNESS_DIR)
local CHAT_DIR = slash(arg[1] or (HARNESS_DIR .. "/.."))

local function P(rel) return CHAT_DIR .. "/" .. rel end
local function H(rel) return HARNESS_DIR .. "/" .. rel end

local ADDON = "Daseeki-Chat"

----------------------------------------------------------------------
-- Captured print log
----------------------------------------------------------------------
local realprint = print
local LOG = {}
local function logline(s) LOG[#LOG + 1] = s end
local function flushlog() for i = 1, #LOG do realprint(LOG[i]) end LOG = {} end

local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

----------------------------------------------------------------------
-- 0) TOC PARSE GATE (the Bags/Nexus silent-green lesson: loadfile-assert
--    EVERY .lua the .toc ships, before anything runs — a file that does not
--    compile never registers its suites, and the runner only iterates suites
--    that DID register).
----------------------------------------------------------------------
local TOC_FILE = "Daseeki-Chat.toc"

local function readTocLuaFiles(tocPath)
    local fh, oerr = io.open(tocPath, "r")
    if not fh then return nil, "cannot open " .. tocPath .. ": " .. tostring(oerr) end
    local files = {}
    for line in fh:lines() do
        line = line:gsub("^\239\187\191", "")          -- strip UTF-8 BOM
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():sub(-4) == ".lua" then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    fh:close()
    return files
end

realprint("=== toc parse gate :: loadfile() every .lua in " .. TOC_FILE .. " ===")
local TOC_LUA, tocErr = readTocLuaFiles(P(TOC_FILE))
if not TOC_LUA or #TOC_LUA == 0 then
    realprint("  [FAIL] " .. (tocErr or (TOC_FILE .. " listed no .lua files")))
    realprint("=== toc parse gate: FAIL ===")
    os.exit(1)
end
local parseFails = 0
for _, rel in ipairs(TOC_LUA) do
    local pfn, perr = loadfile(P(rel))
    if not pfn then
        parseFails = parseFails + 1
        realprint("  [PARSE FAIL] " .. rel)
        realprint("        " .. tostring(perr))
    end
end
if parseFails > 0 then
    realprint(string.format("=== toc parse gate: FAIL (%d of %d file(s) do not compile) ===",
        parseFails, #TOC_LUA))
    os.exit(1)
end
realprint(string.format("  [ok] %d .lua file(s) in %s compile", #TOC_LUA, TOC_FILE))
realprint("=== toc parse gate: PASS ===")
realprint("")

----------------------------------------------------------------------
-- 0b) TOC IDENTITY GATE
--   1. SavedVariables must declare DaseekiChatDB, SavedVariablesPerCharacter
--      must declare DaseekiChatCharDB (an undeclared global is ERASED at the
--      next logout — Bags AT-RISK-1).
--   2. Dependencies must carry Daseeki-Core (hard, honest — N1); OptionalDeps
--      must carry Daseeki-Nexus and must NOT also list Core.
--   3. ## Version must match core.lua's ns.VERSION (gate C.12 shape).
--   4. .pkgmeta must exist, relate daseeki-core, and ignore harness/dev.
--   5. THE FILE MAP IS LAW: the .toc's .lua list must be exactly the design
--      doc's file map, in order — three Wave-2 agents fill these files in
--      place and never touch the .toc.
----------------------------------------------------------------------
local EXPECTED_FILE_MAP = {
    "core.lua", "config.lua", "reconcile.lua", "channels.lua", "decor.lua",
    "stamps.lua", "names.lua", "urls.lua", "history.lua", "badges.lua",
    "skin.lua", "nexus.lua",
}

local function tocDirective(src, key)
    for line in src:gmatch("[^\r\n]+") do
        local v = line:match("^%s*##%s*" .. key .. "%s*:%s*(.-)%s*$")
        if v then return v end
    end
    return nil
end

realprint("=== toc identity gate :: SavedVariables + deps + version + file map ===")
local idFails = 0
local tocSrc = readFile(P(TOC_FILE))
if not tocSrc then
    idFails = idFails + 1
    realprint("  [FAIL] cannot read " .. TOC_FILE)
else
    local sv = tocDirective(tocSrc, "SavedVariables") or ""
    if not sv:find("DaseekiChatDB", 1, true) then
        idFails = idFails + 1
        realprint("  [FAIL] SavedVariables does not declare DaseekiChatDB (it would be erased at logout)")
    end
    local svpc = tocDirective(tocSrc, "SavedVariablesPerCharacter") or ""
    if not svpc:find("DaseekiChatCharDB", 1, true) then
        idFails = idFails + 1
        realprint("  [FAIL] SavedVariablesPerCharacter does not declare DaseekiChatCharDB")
    end
    if idFails == 0 then realprint("  [ok] both SavedVariables globals declared") end

    local hard, optional = {}, {}
    for name in (tocDirective(tocSrc, "Dependencies") or ""):gmatch("[^,%s]+") do hard[name] = true end
    for name in (tocDirective(tocSrc, "RequiredDeps") or ""):gmatch("[^,%s]+") do hard[name] = true end
    for name in (tocDirective(tocSrc, "OptionalDeps") or ""):gmatch("[^,%s]+") do optional[name] = true end
    if not hard["Daseeki-Core"] then
        idFails = idFails + 1
        realprint("  [FAIL] Daseeki-Core is not a hard ## Dependencies entry (N1: there is no Core-less rendering path)")
    end
    if optional["Daseeki-Core"] then
        idFails = idFails + 1
        realprint("  [FAIL] Daseeki-Core listed on BOTH Dependencies and OptionalDeps")
    end
    if not optional["Daseeki-Nexus"] then
        idFails = idFails + 1
        realprint("  [FAIL] Daseeki-Nexus missing from OptionalDeps (load-order statement for the chatcfg bridge)")
    end
    if hard["Daseeki-Nexus"] then
        idFails = idFails + 1
        realprint("  [FAIL] Daseeki-Nexus must NOT be a hard dependency (Chat runs unchanged without it)")
    end
    if hard["Daseeki-Core"] and optional["Daseeki-Nexus"] and not optional["Daseeki-Core"] and not hard["Daseeki-Nexus"] then
        realprint("  [ok] Dependencies: Daseeki-Core hard, Daseeki-Nexus optional")
    end

    local tocVersion = tocDirective(tocSrc, "Version")
    local coreSrc = readFile(P("core.lua"))
    local coreVersion = coreSrc and coreSrc:match('ns%.VERSION%s*=%s*"([^"]+)"')
    if not tocVersion then
        idFails = idFails + 1
        realprint("  [FAIL] " .. TOC_FILE .. " has no ## Version line")
    elseif not coreVersion then
        idFails = idFails + 1
        realprint("  [FAIL] cannot read ns.VERSION from core.lua")
    elseif tocVersion ~= coreVersion then
        idFails = idFails + 1
        realprint(("  [FAIL] ## Version %s does not match core.lua ns.VERSION %s")
            :format(tocVersion, coreVersion))
    else
        realprint("  [ok] ## Version " .. tocVersion .. " consistent with core.lua")
    end

    -- The file map is law.
    local mapOk = #TOC_LUA == #EXPECTED_FILE_MAP
    if mapOk then
        for i = 1, #EXPECTED_FILE_MAP do
            if TOC_LUA[i] ~= EXPECTED_FILE_MAP[i] then mapOk = false break end
        end
    end
    if not mapOk then
        idFails = idFails + 1
        realprint("  [FAIL] the .toc .lua list is not the design doc's file map (exact files, exact order):")
        realprint("         expected: " .. table.concat(EXPECTED_FILE_MAP, ", "))
        realprint("         got:      " .. table.concat(TOC_LUA, ", "))
    else
        realprint("  [ok] file map matches the design doc (" .. #EXPECTED_FILE_MAP .. " files, in order)")
    end
end

do
    local pkg = readFile(P(".pkgmeta"))
    if not pkg then
        idFails = idFails + 1
        realprint("  [FAIL] .pkgmeta is missing")
    else
        if not pkg:lower():find("daseeki%-core") then
            idFails = idFails + 1
            realprint("  [FAIL] .pkgmeta has no daseeki-core required-dependency relation")
        end
        local ignoresHarness = false
        for line in pkg:gmatch("[^\r\n]+") do
            if line:match("^%s*%-%s*harness%s*$") then ignoresHarness = true end
        end
        if not ignoresHarness then
            idFails = idFails + 1
            realprint("  [FAIL] .pkgmeta does not ignore harness/ (dev tooling would ship)")
        end
        if pkg:lower():find("daseeki%-core") and ignoresHarness then
            realprint("  [ok] .pkgmeta relates daseeki-core and ignores harness/")
        end
    end
end

if idFails > 0 then
    realprint(string.format("=== toc identity gate: FAIL (%d problem(s)) ===", idFails))
    os.exit(1)
end
realprint("=== toc identity gate: PASS ===")
realprint("")

----------------------------------------------------------------------
-- WoW global aliases + error routing recorder
----------------------------------------------------------------------
_G.strmatch = string.match
_G.strfind  = string.find
_G.strsub   = string.sub
_G.format   = string.format
_G.wipe     = function(t) for k in pairs(t) do t[k] = nil end return t end

_G.geterrorhandler = function()
    return function(err) realprint("  !! routed error: " .. tostring(err)) end
end

----------------------------------------------------------------------
-- QUEUE-AND-PUMP TIMER (simulator doctrine: "scheduled" and "ran" are
-- different words; a no-op or inline C_Timer erases the gap a whole defect
-- class lives in). Deadline order, schedule-order tiebreak (Class 8), nested
-- callbacks picked up in the same sweep, flush() as the between-suites broom.
----------------------------------------------------------------------
local HTIMER = { clock = 0, queue = {}, seq = 0, ran = 0, peak = 0 }

function HTIMER.After(delay, fn)
    if type(fn) ~= "function" then return end
    HTIMER.seq = HTIMER.seq + 1
    HTIMER.queue[#HTIMER.queue + 1] =
        { at = HTIMER.clock + (tonumber(delay) or 0), fn = fn, seq = HTIMER.seq }
    if #HTIMER.queue > HTIMER.peak then HTIMER.peak = #HTIMER.queue end
end
function HTIMER.pending() return #HTIMER.queue end

local function drain(target, all)
    while true do
        local best, bi
        for i = 1, #HTIMER.queue do
            local t = HTIMER.queue[i]
            if (all or t.at <= target) and
               (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                best, bi = t, i
            end
        end
        if not best then break end
        table.remove(HTIMER.queue, bi)
        if best.at > HTIMER.clock then HTIMER.clock = best.at end
        HTIMER.ran = HTIMER.ran + 1
        local ok, err = pcall(best.fn)
        if not ok then realprint("  !! harness timer callback error: " .. tostring(err)) end
    end
    if target and target > HTIMER.clock then HTIMER.clock = target end
end

function HTIMER.advance(dt) drain(HTIMER.clock + (tonumber(dt) or 0), false) end
function HTIMER.flush()     drain(nil, true) end
function HTIMER.reset()     HTIMER.queue, HTIMER.seq = {}, 0 end

_G.C_Timer = { After = function(delay, fn) HTIMER.After(delay, fn) end }
_G.__DaseekiChatHarnessTimer = HTIMER

----------------------------------------------------------------------
-- Install the unkind chat simulator + the Core sentinel stub.
----------------------------------------------------------------------
local Sim = assert(loadfile(H("chatsim.lua")), "chatsim.lua failed to compile")()
assert(loadfile(H("corestub.lua")), "corestub.lua failed to compile")()

----------------------------------------------------------------------
-- SavedVariables preset: skin starts DISABLED so the inertness gate below can
-- pin "disabled module = zero hooks" against a full login. The skin suite
-- enables it itself (phase 1) and leaves it enabled.
-- Wave-2 agents append their lifecycle modules here (each marked): every
-- feature module starts DISABLED for the gate; its own suite enables it.
----------------------------------------------------------------------
_G.DaseekiChatDB = { modules = { skin = false } }
-- w2/history suites: history + badges also start DISABLED, so the inertness
-- gate below pins THEIR disabled-is-inert contract against the same login;
-- each suite enables its own module (the skin pattern) and leaves it enabled.
_G.DaseekiChatDB.modules.history = false
_G.DaseekiChatDB.modules.badges  = false
-- w2/pipeline suites: the pipeline modules also start disabled so the
-- inertness gate pins them against a full login; each suite enables its
-- own module (the skin precedent).
_G.DaseekiChatDB.modules.decor  = false
_G.DaseekiChatDB.modules.stamps = false
_G.DaseekiChatDB.modules.names  = false
_G.DaseekiChatDB.modules.urls   = false
-- w2/reconciler suites: reconcile + channels start disabled for the same gate
_G.DaseekiChatDB.modules.reconcile = false
_G.DaseekiChatDB.modules.channels = false

----------------------------------------------------------------------
-- ns namespace + suite-registration sentinel (Bags precedent: intercept the
-- RegisterSelfTest assignment via __newindex so core.lua's own registration is
-- seen, and wrap every suite between two timer flushes for isolation).
----------------------------------------------------------------------
local ns = {}
local registeredSuites = {}
local suiteOrder       = {}
setmetatable(ns, {
    __newindex = function(t, k, v)
        if k == "RegisterSelfTest" and type(v) == "function" then
            rawset(t, k, function(self, name, fn)
                name = tostring(name)
                if not registeredSuites[name] then
                    registeredSuites[name] = true
                    suiteOrder[#suiteOrder + 1] = name
                end
                return v(self, name, function(...)
                    HTIMER.flush()
                    local r = fn(...)
                    HTIMER.flush()
                    return r
                end)
            end)
        else
            rawset(t, k, v)
        end
    end,
})

----------------------------------------------------------------------
-- Load addon files in .toc order (the parsed list IS the load list — the file
-- map gate above already pinned it to the design map).
----------------------------------------------------------------------
local loadResults = {}
for _, rel in ipairs(TOC_LUA) do
    local fn, err = loadfile(P(rel))
    if not fn then
        loadResults[#loadResults + 1] = { rel, false, "compile: " .. tostring(err) }
    else
        local ok, rerr = pcall(fn, ADDON, ns)
        loadResults[#loadResults + 1] = { rel, ok, rerr }
    end
end

-- Re-point ns.Print at the captured log (core's Print prefixes color escapes).
function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    logline(table.concat(parts, "\t"))
end

realprint("=== Daseeki-Chat harness :: file load ===")
local criticalFail = false
for _, r in ipairs(loadResults) do
    realprint(string.format("  [%s] %s%s", r[2] and "ok  " or "FAIL", r[1],
        r[2] and "" or ("  -> " .. tostring(r[3]))))
    if not r[2] then criticalFail = true end
end
if criticalFail then
    realprint("!!! a file failed to load -- aborting.")
    os.exit(2)
end
realprint("")

----------------------------------------------------------------------
-- Drive a full login with the skin module DISABLED.
----------------------------------------------------------------------
Sim.Login(ADDON)
Sim.EnterWorld()
HTIMER.flush()

----------------------------------------------------------------------
-- INERTNESS GATE — disabled = ZERO hooks (the pin). After a complete login
-- with every feature module disabled, the client must have seen NOTHING from
-- us beyond core's four lifecycle event registrations.
----------------------------------------------------------------------
realprint("=== inertness gate :: disabled module = zero hooks ===")
local inertPass = true
do
    local function ck(c, m)
        if not c then inertPass = false; realprint("  [FAIL] " .. m) end
    end
    ck(ns.Skin ~= nil, "ns.Skin exists")
    ck(ns.Skin and ns.Skin.active == false, "skin is inactive")
    ck(ns.Skin and ns.Skin.hooked == false, "skin installed no hooksecurefunc")
    ck(Sim.CallCount("hooksecurefunc") == 0, "the sim counted ZERO hooksecurefunc calls")
    ck(Sim.CallCount("SetFading") == 0, "no chat frame's fading was touched")
    ck(ns.EventHandlerCount() == 4,
        "only core's 4 lifecycle events are registered (got " .. ns.EventHandlerCount() .. ")")
    -- Every registered module must be in KNOWN_MODULES AND flagged disabled
    -- in the SavedVariables preset above, or this gate is hollow. Wave agents
    -- append their names inside their own marked block; the count derives
    -- from the set so the blocks union-merge mechanically.
    local KNOWN_MODULES = { skin = true }
    -- w2/history suites: history + badges registered in Wave 2
    KNOWN_MODULES.history, KNOWN_MODULES.badges = true, true
    -- w2/pipeline suites: pipeline modules registered in Wave 2
    KNOWN_MODULES.decor, KNOWN_MODULES.stamps, KNOWN_MODULES.names, KNOWN_MODULES.urls =
        true, true, true, true
    -- end w2/pipeline suites
    -- w2/reconciler suites: reconcile + channels registered in Wave 2
    KNOWN_MODULES.reconcile = true
    KNOWN_MODULES.channels = true
    -- end w2/reconciler suites
    local knownCount = 0
    for _ in pairs(KNOWN_MODULES) do knownCount = knownCount + 1 end
    ck(#ns.ModuleOrder == knownCount,
        "exactly " .. knownCount .. " known modules are registered (got " .. #ns.ModuleOrder .. ")")
    for _, name in ipairs(ns.ModuleOrder) do
        ck(KNOWN_MODULES[name], "module '" .. name .. "' is in KNOWN_MODULES")
    end
    -- w2/history suites: disabled history/badges are behaviorally absent too.
    ck(ns.History and ns.History.active == false, "history is inactive")
    ck(ns.History and next(ns.History.hookedFrames) == nil,
        "history wrapped no AddMessage while disabled")
    ck(ns.Badges and ns.Badges.active == false, "badges is inactive")
    ck(ns.Badges and next(ns.Badges.hookedFrames) == nil,
        "badges wrapped no AddMessage while disabled")
    ck(ns.Badges and ns.Badges.globalHooked == false,
        "badges installed no hooksecurefunc while disabled")
    -- w2/pipeline suites: disabled-is-inert pins for the pipeline modules
    -- (the skin pattern: a module that never enabled has touched NOTHING).
    ck(ns.Decor and ns.Decor.active == false, "decor is inactive")
    ck(ns.Decor and ns.Decor.SeamCount() == 0, "decor installed ZERO AddMessage seams")
    ck(ns.Decor and ns.Decor.hooked == false, "decor installed no temp-window hook")
    ck(ns.Stamps and ns.Stamps.active == false, "stamps is inactive")
    ck(ns.Names and ns.Names.active == false, "names is inactive")
    ck(ns.Names and next(ns.Names.cache) == nil, "names cached nothing while disabled")
    ck(_G.GetCVar("chatClassColorOverride") == "1",
        "the hostile chatClassColorOverride default is UNTOUCHED while names is disabled")
    ck(_G.GetCVar("showTimestamps") == "none",
        "the showTimestamps CVar is untouched while stamps is disabled")
    ck(ns.Urls and ns.Urls.active == false, "urls is inactive")
    ck(ns.Urls and ns.Urls.hookedItemRef == false, "urls left SetItemRef untouched")
    -- end w2/pipeline suites
    -- w2/reconciler suites: disabled-is-inert pins for reconcile + channels
    -- (the __active flag is the module runtime's own record of enablement).
    for _, name in ipairs({ "reconcile", "channels" }) do
        local m = ns.Modules and ns.Modules[name]
        ck(m and not m.__active,
            "module '" .. name .. "' is inert at the gate (disabled login)")
    end
    -- end w2/reconciler suites
    local styledAny = false
    for i = 1, 10 do
        local f = Sim.Frame(i)
        local bg = _G["ChatFrame" .. i .. "Background"]
        if (bg and bg._alpha == 0) then styledAny = true end
    end
    ck(not styledAny, "no stock chat texture was stripped while disabled")
    if inertPass then realprint("  [ok] a disabled module is behaviorally absent") end
end
realprint("=== inertness gate: " .. (inertPass and "PASS" or "FAIL") .. " ===")
realprint("")

----------------------------------------------------------------------
-- CHAT SIM GATE — the rig proving itself. A sim that is secretly kind (inline
-- timers, synchronous joins, warm lists) would wave broken Wave-2 code
-- through, so every unkindness is asserted here before any suite runs.
----------------------------------------------------------------------
realprint("=== chat sim gate :: the rig proves its own unkindness ===")
local simPass = true
do
    local function ck(c, m)
        if not c then simPass = false; realprint("  [FAIL] " .. m) end
    end

    -- 1. Timers QUEUE (never inline), fire deadline-order with schedule-order
    --    tiebreak, nested pickups in the same sweep.
    HTIMER.flush()
    local order = {}
    _G.C_Timer.After(0, function() order[#order + 1] = "a0" end)
    ck(#order == 0, "C_Timer.After(0) queues; it must not run inline")
    _G.C_Timer.After(0, function() order[#order + 1] = "b0" end)
    _G.C_Timer.After(0.5, function()
        order[#order + 1] = "c50"
        _G.C_Timer.After(0, function() order[#order + 1] = "d-nested" end)
    end)
    _G.C_Timer.After(0.1, function() order[#order + 1] = "e10" end)
    HTIMER.advance(1.0)
    ck(table.concat(order, ",") == "a0,b0,e10,c50,d-nested",
        "deadline order + schedule tiebreak + nested pickup (got " .. table.concat(order, ",") .. ")")

    -- 2. Ring buffer: uptime stamps, newest-first GetEntryAtIndex, mutability,
    --    the WRAPPED headIndex/maxElements shape, cap trimming.
    local cf = Sim.Frame(4)   -- a quiet window
    cf:AddMessage("one", 1, 1, 1)
    HTIMER.advance(1.0)
    cf:AddMessage("two", 1, 1, 1)
    ck(cf:GetNumMessages() == 2, "AddMessage lands in the frame buffer")
    ck(cf:GetMessageInfo(1) == "one", "GetMessageInfo(1) is the OLDEST line")
    local newest = cf.historyBuffer:GetEntryAtIndex(1)
    ck(newest and newest.message == "two", "historyBuffer:GetEntryAtIndex(1) is the NEWEST entry")
    ck(type(newest.timestamp) == "number" and newest.timestamp < 1e6,
        "entry timestamps are UPTIME-based (small numbers), never epoch")
    ck(type(cf.historyBuffer.maxElements) == "table" and cf.historyBuffer.maxElements.value,
        "maxElements is the WRAPPED { value = n } shape by default (unkind)")
    ck(type(cf.historyBuffer.headIndex) == "table", "headIndex is wrapped too")
    newest.message = "two (edited)"
    ck(cf:GetMessageInfo(2) == "two (edited)", "buffer entries are MUTABLE in place")
    local cap = cf.historyBuffer.maxElements.value
    for i = 1, cap + 5 do cf:AddMessage("bulk " .. i, 1, 1, 1) end
    ck(cf:GetNumMessages() == cap, "the buffer trims to maxElements (oldest evicted)")

    -- 3. Era message events: full 17-arg shape, GUID in arg12, sentinel and
    --    nil-info cases, ADDON-HANDLER-FIRST ordering, hyperlink-bearing
    --    client lines.
    local probe = _G.CreateFrame("Frame")
    local got = {}
    probe:RegisterEvent("CHAT_MSG_SAY")
    probe:SetScript("OnEvent", function(self, event, ...)
        got = { event = event, args = { ... },
                bufferAtEvent = Sim.Frame(1):GetNumMessages() }
    end)
    local preCount = Sim.Frame(1):GetNumMessages()
    local line = Sim.SendChat{ event = "CHAT_MSG_SAY", text = "hello world",
                               sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    ck(got.event == "CHAT_MSG_SAY" and got.args[1] == "hello world", "event delivered with text in arg1")
    ck(got.args[2] == "Puu-Whitemane", "sender (Name-Realm) in arg2")
    ck(got.args[12] == "Player-1-00000001", "sender GUID rides in arg12 (the era fact)")
    ck(got.bufferAtEvent == preCount,
        "UNKIND ORDERING: the addon handler ran BEFORE the client stored the line")
    ck(Sim.Frame(1):GetNumMessages() == preCount + 1, "the client routed the line afterwards")
    ck(line:find("|Hplayer:", 1, true) ~= nil, "the client-formatted line carries a player hyperlink")
    local locClass, token = _G.GetPlayerInfoByGUID("Player-1-00000001")
    ck(locClass == "Warrior" and token == "WARRIOR", "GetPlayerInfoByGUID resolves a known GUID")
    local _, zeroInfo = Sim.SendChat{ event = "CHAT_MSG_SAY", text = "who am I",
                                      sender = "Mystery", guid = "zero" }
    ck(zeroInfo[12] == "0000000000000000", "the all-zeros GUID sentinel is deliverable")
    ck(_G.GetPlayerInfoByGUID("0000000000000000") == nil, "the sentinel resolves to NOTHING")
    ck(_G.GetPlayerInfoByGUID("Player-1-99999999") == nil, "an unencountered GUID resolves to NOTHING")

    -- 4. Channel-routed traffic reaches only windows whose store routes it.
    _G.AddChatWindowChannel(1, "World")
    local w4Before = Sim.Frame(4):GetNumMessages()
    local chanLine = Sim.SendChat{ event = "CHAT_MSG_CHANNEL", text = Sim.MakeItemLink(),
                                   sender = "Choco", guid = "Player-1-00000002",
                                   channelNumber = 2, channelName = "World" }
    ck(Sim.Frame(1):GetMessageInfo(Sim.Frame(1):GetNumMessages()):find("|Hitem:", 1, true) ~= nil,
        "a CHANNEL line with an embedded item link landed in the routed window")
    ck(Sim.Frame(4):GetNumMessages() == w4Before, "an unrouted window stayed silent")
    ck(chanLine:find("|Hchannel:channel:2|h", 1, true) ~= nil, "the channel header is a real hyperlink")
    ck(_G.ChatFrame_AddChannel == nil,
        "ChatFrame_AddChannel is ABSENT (not in the 11509 catalog; use AddChatWindowChannel)")

    -- 5. Async channels: joins complete later, throttled joins DROP, the
    --    notice fires BEFORE the list updates, holes refill lowest-first,
    --    the swap primitive works.
    HTIMER.flush()
    Sim.ResetCalls()
    local notices = {}
    local listAtNotice
    probe:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    probe:SetScript("OnEvent", function(self, event, ...)
        if event == "CHAT_MSG_CHANNEL_NOTICE" then
            local kind, _, _, _, _, _, _, num, name = ...
            notices[#notices + 1] = { kind = kind, num = num, name = name }
            if kind == "YOU_JOINED" then listAtNotice = { _G.GetChannelList() } end
        end
    end)
    local dropsBefore = Sim.droppedJoins
    _G.JoinChannelByName("World2")
    _G.JoinChannelByName("TooFast")        -- <0.5s after the previous op
    ck(Sim.droppedJoins == dropsBefore + 1, "a join issued <0.5s after another is DROPPED silently")
    ck(#notices == 0, "nothing has completed yet (joins are server round-trips)")
    HTIMER.advance(0.5)
    ck(#notices == 1 and notices[1].kind == "YOU_JOINED" and notices[1].name == "World2",
        "the join completed ~0.5s later via CHAT_MSG_CHANNEL_NOTICE")
    local sawInNoticeList = false
    for _, v in ipairs(listAtNotice or {}) do if v == "World2" then sawInNoticeList = true end end
    ck(not sawInNoticeList,
        "EVENT BEFORE STATE: GetChannelList inside the notice handler does NOT show the join yet")
    HTIMER.advance(0.1)
    local nowList = { _G.GetChannelList() }
    local sawNow = false
    for _, v in ipairs(nowList) do if v == "World2" then sawNow = true end end
    ck(sawNow, "…and shows it one beat later")
    ck(Sim.CallCount("JoinChannelByName") == 2, "call counting works (2 joins issued)")

    -- Leave -> hole -> lowest-hole refill -> swap.
    HTIMER.advance(0.5)
    local generalNum = select(1, _G.GetChannelName("General"))
    _G.LeaveChannelByName("General")
    HTIMER.flush()
    ck(Sim.serverChannels[generalNum] == nil,
        "leaving left a HOLE at the old number")
    HTIMER.advance(0.5)
    _G.JoinChannelByName("Osiris")
    HTIMER.flush()
    local osirisNum = select(1, _G.GetChannelName("Osiris"))
    ck(osirisNum == generalNum, "a new join fills the LOWEST hole (numbers get reused)")
    local worldNum = select(1, _G.GetChannelName("World2"))
    _G.C_ChatInfo.SwapChatChannelsByChannelIndex(osirisNum, worldNum)
    ck(select(2, _G.GetChannelName(osirisNum)) == "World2",
        "SwapChatChannelsByChannelIndex renumbers in place")

    -- 6. Hostile CVar defaults (the two that silently bite).
    ck(_G.GetCVar("chatStyle") == "im", "chatStyle defaults to 'im' (must be forced by code that needs classic)")
    ck(_G.GetCVar("chatClassColorOverride") == "1",
        "chatClassColorOverride defaults to 1 (class colors force-disabled until managed)")
    local cvarEvents = 0
    probe:RegisterEvent("CVAR_UPDATE")
    local prevScript = probe:GetScript("OnEvent")
    probe:SetScript("OnEvent", function(self, event, ...)
        if event == "CVAR_UPDATE" then cvarEvents = cvarEvents + 1
        elseif prevScript then prevScript(self, event, ...) end
    end)
    _G.SetCVar("chatStyle", "classic")
    ck(cvarEvents == 1 and _G.GetCVar("chatStyle") == "classic", "SetCVar lands and announces via CVAR_UPDATE")

    -- 7. Batch replay doubles a buffer (the double-stamp trap, ready-made).
    local cf5 = Sim.Frame(5)
    cf5:AddMessage("r1", 1, 1, 1); cf5:AddMessage("r2", 1, 1, 1)
    Sim.ReplayBuffer(cf5)
    ck(cf5:GetNumMessages() == 4, "ReplayBuffer re-adds every stored line")

    -- 8. New session: uptime RESETS, server epoch does not, buffers clear.
    local upBefore, epochBefore = _G.GetTime(), _G.GetServerTime()
    Sim.NewSession()
    ck(_G.GetTime() < upBefore, "NewSession resets the uptime clock (old buffer stamps go bogus)")
    ck(_G.GetServerTime() >= epochBefore, "…while the server epoch keeps advancing")
    ck(Sim.Frame(5):GetNumMessages() == 0, "…and frame buffers start empty")
    local darkList = { _G.GetChannelList() }
    ck(#darkList == 0, "…and the channel list is DARK again until the world populates")

    -- Restore the world for the suites: fresh session, logged in, in world.
    probe:UnregisterEvent("CHAT_MSG_SAY")
    probe:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    probe:UnregisterEvent("CVAR_UPDATE")
    Sim.EnterWorld(false, false)
    HTIMER.flush()
    Sim.ResetCalls()
end
realprint("=== chat sim gate: " .. (simPass and "PASS" or "FAIL") .. " ===")
realprint("")

----------------------------------------------------------------------
-- Harness-registered suite: placeholders parse and register NOTHING. The
-- three Wave-2 agents each replace their own files; until then every
-- placeholder is an empty module table with no events, no hooks, no suites.
----------------------------------------------------------------------
local PLACEHOLDER_KEYS = {
    -- EMPTY as of Wave 2 complete: every design-doc file is REAL now, each
    -- covered by its own suite. The roster (and this suite) stays as the
    -- mechanism for any future file added placeholder-first.
}

ns:RegisterSelfTest("placeholders", function(verbose)
    local fails = {}
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    for key, file in pairs(PLACEHOLDER_KEYS) do
        local t = ns[key]
        ck(type(t) == "table", file .. " registered its ns." .. key .. " table")
        if type(t) == "table" then
            ck(next(t) == nil, file .. " is a pure placeholder (empty table, no behavior)")
        end
    end
    -- No placeholder registered a lifecycle module.
    local moduleSet = {}
    for _, name in ipairs(ns.ModuleOrder) do moduleSet[name] = true end
    for key in pairs(PLACEHOLDER_KEYS) do
        ck(not moduleSet[key:lower()], key .. " did not register a lifecycle module")
    end
    for _, f in ipairs(fails) do ns:Print("  FAIL placeholders :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS placeholders") end
    return #fails == 0
end)

----------------------------------------------------------------------
-- Harness-registered suite: INTEGRATION — the "it all runs at once" reality
-- no per-branch suite ever saw. EVERY Wave-2 lifecycle module (decor, stamps,
-- names, urls, history, badges, skin, channels, reconcile — config.lua and
-- nexus.lua are passive/bridge files exercised through them) is enabled
-- TOGETHER, a reconcile CONVERGES an authored config (leg 0), then one
-- message flows, a cross-session restore happens, and badges count — all in
-- the converged world — pinning that the stacked AddMessage wraps (decor seam
-- + history shadow + badges delivery), the post-add observers, the restore
-- path AND the reconciler's window/channel convergence do not corrupt each
-- other under the merged enable permutation:
--   * the reconciler converges windows, the join list (deterministic
--     numbers, paced — zero dropped ops) and channel colors by name while
--     the whole pipeline is live;
--   * protection holds under full decoration load (item link byte-intact);
--   * exactly ONE stamp per stored line (no double-processing across wraps);
--   * history captures the line; restore backfills via PushFront ONLY (zero
--     AddMessage re-entry), the divider sits strictly before live content;
--   * restored lines never badge (they bypass the delivery seam); a live line
--     after the restore badges exactly once; the reconciler's re-login
--     converge adds no lines and re-lands the join list.
-- Runs last (after every module suite), against the world exactly as the
-- suites left it — which IS the point.
----------------------------------------------------------------------

ns:RegisterSelfTest("integration", function(verbose)
    local fails = {}
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local ok, err = pcall(function()
        local cf1  = _G.ChatFrame1
        local dock = _G.GeneralDockManager
        local C    = ns.Config

        local ALL_MODULES = { "decor", "stamps", "names", "urls", "history",
                              "badges", "skin", "channels", "reconcile" }

        -- Every module up together (explicit, not inherited: stamps' suite
        -- deliberately leaves itself disabled for skin; the reconciler wave's
        -- suites leave reconcile/channels disabled). Order matters twice:
        -- channels before reconcile (the warm gate), and reconcile LAST —
        -- after the config below is authored — so even its enable-path run
        -- converges toward THIS config, never a predecessor suite's leftover.
        for _, name in ipairs(ALL_MODULES) do
            if name ~= "reconcile" then ns.SetModuleEnabled(name, true) end
        end

        -- ── Leg 0: author a config, then a reconcile converges it with the
        -- whole stack live. The authored intent: window 1 renamed + resized,
        -- the current routing kept (captured), "World" routed and joined at a
        -- deterministic number, its color held by name. ──────────────────────
        local c = C.Get()
        c.windows = {}
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            c.windows[id] = C.CaptureWindow(id)
        end
        c.windows[1].name = "Merged"
        c.windows[1].fontSize = 15
        local hasWorld = false
        for _, nm in ipairs(c.windows[1].channels) do
            if nm == "World" then hasWorld = true end
        end
        if not hasWorld then
            c.windows[1].channels[#c.windows[1].channels + 1] = "World"
            table.sort(c.windows[1].channels)
        end
        c.join   = { { 1, "General" }, { 2, "World" } }
        c.colors = { world = { r = 0.9, g = 0.3, b = 0.2 } }
        c.rev = (tonumber(c.rev) or 0) + 1
        c.at  = C.Now()

        ns.SetModuleEnabled("reconcile", true)
        local allUp = true
        for _, name in ipairs(ALL_MODULES) do
            local m = ns.Modules[name]
            if not (m and m.__active) then allUp = false end
        end
        ck(allUp, "leg 0: every Wave-2 lifecycle module is active together")

        local drops0 = Sim.droppedJoins
        Sim.EnterWorld(false, false)   -- plain zone-in: the reconcile beat, no restore
        HTIMER.flush()                 -- warm poll + paced joins + verify ladder settle
        ck(select(1, _G.GetChatWindowInfo(1)) == "Merged",
            "leg 0: the reconciler renamed window 1 from the authored config")
        local _, fs0 = _G.GetChatWindowInfo(1)
        ck(fs0 == 15, "leg 0: window 1 font size converged")
        ck(select(1, _G.GetChannelName("World")) == 2,
            "leg 0: the join list landed World on its configured number")
        ck(C.NearColor(_G.ChatTypeInfo["CHANNEL2"], c.colors.world),
            "leg 0: the channel color imposed at the converged number, by name")
        ck(Sim.droppedJoins == drops0,
            "leg 0: pacing held through the merged-world converge (zero dropped ops)")
        local w1cap = C.CaptureWindow(1)
        local routed = false
        for _, nm in ipairs(w1cap.channels) do if nm == "World" then routed = true end end
        ck(routed, "leg 0: window 1 routes the configured channel")
        ck(ns.Reconcile._runInFlight == false, "leg 0: the reconcile run ENDED (finite ladder)")

        -- ── Leg 1: one message through the full stack, in the CONVERGED world.
        _G.FCF_SelectDockFrame(_G.ChatFrame2)   -- window 1 docked-unselected: badgeable
        ns.Badges.Clear(cf1)
        Sim.ResetCalls()
        local itemLink = Sim.MakeItemLink()
        Sim.SendChat{ event = "CHAT_MSG_SAY",
            text = "all-hands " .. itemLink .. " at www.example.com",
            sender = "Puu-Whitemane", guid = "Player-1-00000001" }
        HTIMER.advance(0)
        local stored = cf1.historyBuffer:GetEntryAtIndex(1)
        local msg = stored and stored.message or ""
        ck(msg:find(itemLink, 1, true) ~= nil,
            "leg 1: the item link is byte-intact under the FULL decoration stack")
        ck(msg:find("|Haddon:dchaturl:www.example.com|h", 1, true) ~= nil,
            "leg 1: the URL linkified beside it")
        ck(msg:find("|Hplayer:Puu%-Whitemane") ~= nil,
            "leg 1: the sender's click payload is intact")
        local _, stampN = msg:gsub("%[%d%d:%d%d%]", "")
        ck(stampN == 1, "leg 1: exactly ONE stamp on the stored line (got " .. stampN .. ")")
        ck(ns.Badges.counts[cf1] == 1, "leg 1: the unseen window badged exactly once")
        local ring = ns.History.rings[1]
        ck(ring and #ring > 0 and ring[#ring].m:find("all-hands", 1, true) ~= nil,
            "leg 1: history captured the line at the delivery seam")

        -- ── Leg 2: cross-session restore with everything still enabled. ─────
        _G.FCF_SelectDockFrame(cf1)             -- clear the badge before the hop
        Sim.Logout()                            -- snapshot beat
        Sim.NewSession()
        _G.FCF_SelectDockFrame(_G.ChatFrame2)   -- window 1 unseen again: a restore
        ns.Badges.Clear(cf1)                    -- that (wrongly) re-delivered WOULD badge
        Sim.ResetCalls()
        Sim.EnterWorld(true, false)
        HTIMER.flush()
        ck(Sim.CallCount("AddMessage") == 0,
            "leg 2: restore re-entered NO AddMessage wrap (PushFront only, whole stack live)")
        ck(cf1:GetNumMessages() > 0, "leg 2: window 1 was backfilled")
        local divAt, divCount = nil, 0
        for i = 1, #cf1.historyBuffer.list do
            local e = cf1.historyBuffer.list[i]
            if e.daseekiDivider then divCount = divCount + 1 divAt = i end
        end
        ck(divCount == 1, "leg 2: exactly one divider (got " .. divCount .. ")")
        ck(divAt == cf1:GetNumMessages(),
            "leg 2: with no live traffic yet, the divider is the newest entry")
        local allRestored, doubleStamped = true, false
        for i = 1, #cf1.historyBuffer.list do
            local e = cf1.historyBuffer.list[i]
            if not e.daseekiRestored then allRestored = false end
            local _, n = tostring(e.message):gsub("%[%d%d:%d%d%]", "")
            if n > 1 then doubleStamped = true end
        end
        ck(allRestored, "leg 2: every backfilled entry is marked daseekiRestored")
        ck(not doubleStamped, "leg 2: no restored line wears more than one stamp")
        ck(ns.Badges.counts[cf1] == 0,
            "leg 2: restored lines badge NOTHING (they bypass the delivery seam)")
        -- The reconciler rode the same login beat: the fresh session's empty
        -- server list was re-converged (joins are server ops, never lines).
        ck(select(1, _G.GetChannelName("World")) == 2,
            "leg 2: the reconciler re-landed the join list on the fresh session")
        ck(ns.Reconcile._runInFlight == false, "leg 2: the login reconcile run ended")

        -- ── Leg 3: live traffic after the restore, full stack still up. ──────
        Sim.SendChat{ event = "CHAT_MSG_SAY", text = "back-live",
            sender = "Choco", guid = "Player-1-00000002" }
        HTIMER.advance(0)
        local total = cf1:GetNumMessages()
        local newest = cf1.historyBuffer:GetEntryAtIndex(1)
        ck(newest and not newest.daseekiRestored
            and tostring(newest.message):find("back-live", 1, true) ~= nil,
            "leg 3: live content lands after the divider (newest entry is live)")
        ck(divAt < total, "leg 3: the divider sits strictly before the live line")
        local _, liveStamps = tostring(newest and newest.message):gsub("%[%d%d:%d%d%]", "")
        ck(liveStamps == 1, "leg 3: the live line wears exactly one stamp")
        ck(ns.Badges.counts[cf1] == 1,
            "leg 3: the live line badged exactly once (restored lines contributed zero)")

        -- Tidy: focused window back; stamps and the reconciler wave back to
        -- the states their own suites left (disabled); the DEFAULT window
        -- world restored (this suite authored a converged layout); timers
        -- drained, counters clean.
        _G.FCF_SelectDockFrame(cf1)
        ns.SetModuleEnabled("stamps", false)
        ns.SetModuleEnabled("reconcile", false)
        ns.SetModuleEnabled("channels", false)
        _G.FCF_ResetChatWindows()
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            _G.FloatingChatFrame_Update(id)
        end
        HTIMER.flush()
        Sim.ResetCalls()
    end)
    if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL integration :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS integration") end
    return #fails == 0
end)

----------------------------------------------------------------------
-- Expected-suite roster (the softer silent-green catch: a file that loads but
-- never registers reads as ALL PASS to a runner that only iterates what
-- registered).
----------------------------------------------------------------------
local EXPECTED_SUITES = { "core", "skin", "placeholders",
    -- w2/history suites
    "history", "badges",
    -- w2/pipeline suites
    "decor", "stamps", "names", "urls",
    -- w2/reconciler suites
    "config", "reconcile", "channels", "nexus",
    -- w2/integration: the merged-world leg (all Wave-2 modules at once)
    "integration",
}

realprint("=== expected-suite roster (" .. #EXPECTED_SUITES .. " suites) ===")
local rosterPass, gotCount = true, 0
local expectedSet = {}
for _, name in ipairs(EXPECTED_SUITES) do expectedSet[name] = true end
for _, name in ipairs(EXPECTED_SUITES) do
    if registeredSuites[name] then
        gotCount = gotCount + 1
    else
        rosterPass = false
        realprint("  [MISSING] suite \"" .. name .. "\" never registered")
    end
end
for _, name in ipairs(suiteOrder) do
    if not expectedSet[name] then
        realprint("  [note] new suite \"" .. name .. "\" is not in EXPECTED_SUITES (add it to the roster)")
    end
end
realprint(string.format("  %d of %d expected suite(s) registered", gotCount, #EXPECTED_SUITES))
realprint("=== expected-suite roster: " .. (rosterPass and "PASS" or "FAIL") .. " ===")
realprint("")

----------------------------------------------------------------------
-- Run all suites
----------------------------------------------------------------------
realprint("=== ns:RunRegisteredSelfTests (real Lua 5.1) ===")
local ok, pass = pcall(function() return ns:RunRegisteredSelfTests(true) end)
flushlog()
if not ok then
    realprint("HARNESS ERROR: " .. tostring(pass))
    os.exit(3)
end

local overall = pass and rosterPass and inertPass and simPass
realprint("")
realprint("############################################################")
realprint("# toc parse gate (compiles)   : PASS (else we exited 1 above)")
realprint("# toc identity gate           : PASS (else we exited 1 above)")
realprint("# inertness gate (disabled=0) : " .. (inertPass and "PASS" or "FAIL"))
realprint("# chat sim gate (unkind rig)  : " .. (simPass and "PASS" or "FAIL"))
realprint("# expected-suite roster       : " .. (rosterPass and "PASS" or "FAIL"))
realprint("# registered self-test suites : " .. (pass and "PASS" or "FAIL"))
realprint("# Daseeki-Chat self-tests     : " .. (overall and "ALL PASS" or "RED (see above)"))
realprint("############################################################")
os.exit(overall and 0 or 1)
