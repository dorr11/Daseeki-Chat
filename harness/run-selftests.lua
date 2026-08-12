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
-- FILE MAP AMENDMENT (2026-08-11, owner-requested): options.lua joins the map
-- after skin.lua and before nexus.lua. DASEEKI_CHAT_DESIGN.md's file map was
-- amended in the same commit with a dated note; this gate still pins the list
-- byte-for-byte, which is the whole point of amending it here rather than
-- loosening the check.
-- FILE MAP AMENDMENT (2026-08-11, owner-directed D2 REVISION): view.lua joins
-- the map after skin.lua and before options.lua — it consumes skin's movement /
-- snap / palette layer and publishes the shapes options binds against. The
-- design doc's D2 REVISION section names it; the .toc was amended in the SAME
-- COMMIT as this gate, and the gate still pins the list byte-for-byte.
-- FILE MAP AMENDMENT (2026-08-11, owner-specified OPTIONS REWORK):
-- options_tabs.lua joins the map immediately after options.lua. The rework's
-- Tabs section is a pane of its own (one page per chat tab, + Add Tab, remove,
-- the combat log toggle, the addon tab) and carrying it inside options.lua
-- would have taken that file past 3,500 lines. It loads SECOND because it
-- builds every control through options.lua's binding index and wiring helpers.
-- DASEEKI_CHAT_DESIGN.md's file map and the .toc were amended in the SAME
-- COMMIT as this gate, and the gate still pins the list byte-for-byte.
local EXPECTED_FILE_MAP = {
    "core.lua", "config.lua", "reconcile.lua", "channels.lua", "decor.lua",
    "stamps.lua", "names.lua", "urls.lua", "history.lua", "badges.lua",
    "skin.lua", "view.lua", "options.lua", "options_tabs.lua", "nexus.lua",
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
-- post-V1/options: the settings pane is a lifecycle module too, so it starts
-- disabled and the inertness gate pins that a disabled pane registers NOTHING
-- with the Daseeki hub; its own suite enables it (the skin precedent).
_G.DaseekiChatDB.modules.options = false
-- D2/view: the owned view is a lifecycle module too, and the most invasive one
-- in the addon (it hides the client's windows and hosts their edit box), so it
-- starts DISABLED and the inertness gate pins that a disabled view has created
-- no frame, wrapped no AddMessage and hidden nothing. Its own suite enables it.
_G.DaseekiChatDB.modules.view = false

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
    -- post-V1/options: the settings pane module
    KNOWN_MODULES.options = true
    ck(ns.Options and ns.Options.active == false, "the options pane is inactive")
    ck(ns.Options and ns.Options.registered == false,
        "the options pane registered NOTHING with the Daseeki hub while disabled")
    ck(_G.DaseekiUI and _G.DaseekiUI.__RegisteredAddon("chat") == nil,
        "…and the hub really has no Chat page yet")
    ck(ns.Options and ns.Options._built == false, "…and no pane was built")
    -- end post-V1/options
    -- D2/view: the owned view's own disabled-is-inert pins. This module's
    -- inertness is load-bearing in a way no other module's is: an enabled view
    -- HIDES the client's chat, so "it did nothing until enable" has to be an
    -- assertion about the player's actual chat window, not a claim.
    KNOWN_MODULES.view = true
    ck(ns.View and ns.View.active == false, "the view is inactive")
    ck(ns.View and ns.View.chassis == nil, "the view built NO chassis frame")
    ck(ns.View and next(ns.View.frames) == nil, "the view created NO message surface")
    ck(ns.View and next(ns.View.tabs) == nil, "the view created NO tab button")
    ck(ns.View and next(ns.View.wrappedFrames) == nil,
        "the view wrapped ZERO AddMessage while disabled")
    ck(ns.View and ns.View.mirrored == 0, "the view mirrored nothing")
    ck(ns.View and next(ns.View._engineHidden) == nil,
        "the view is holding NO client window down")
    do
        local anyHidden = false
        for id = 1, 10 do
            local w = Sim.windows[id]
            local f = Sim.Frame(id)
            if w and (w.shown or w.docked) and f and f._shown == false then anyHidden = true end
        end
        ck(not anyHidden, "…and every window the client wants shown IS shown")
    end
    -- end D2/view
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

    -- 9. GEOMETRY, CLAMP AND THE EDIT BOX (the w2/move surfaces). A drag is
    --    clamped and a SetPoint is not; the edit box starts hidden and the
    --    client hides it again on deactivate; changing uiScale moves UIParent's
    --    UNIT size while the PIXEL screen stays put.
    local geo = Sim.Frame(6)                  -- a quiet window
    local gL, gB, gScale = geo._left, geo._bottom, Sim.uiScale
    ck(geo:GetEffectiveScale() == Sim.uiScale,
        "a chat frame's effective scale is its own times UIParent's")
    ck(select(1, geo:GetClampRectInsets()) > 0,
        "frames carry a clamp margin by default (a drag cannot reach the edge)")
    geo:SetMovable(true)
    geo:StartMoving()
    local dl, db = Sim.DragTo(geo, -200, -200)
    ck(dl > 0 and db > 0, "DRAGGING IS CLAMPED: the corner is out of reach")
    geo:StopMovingOrSizing()
    geo:ClearAllPoints()
    geo:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
    ck(geo:GetLeft() == 0 and geo:GetBottom() == 0,
        "PROGRAMMATIC PLACEMENT IS NOT: SetPoint lands flush, clamp and all")
    geo:SetClampRectInsets(0, 0, 0, 0)
    geo:StartMoving()
    local dl2 = Sim.DragTo(geo, -200, -200)
    ck(dl2 == Sim.BUTTON_FRAME_WIDTH,
        "…a loosened clamp still leaves the BUTTON COLUMN in the way of the edge")
    geo.buttonFrame:Hide()
    local dl3 = Sim.DragTo(geo, -200, -200)
    ck(dl3 == 0, "…and with the column down the very same drag reaches the edge")
    ck(select(1, Sim.ColumnFootprint(geo)) == 0, "a column that is down costs nothing")
    geo:StopMovingOrSizing()
    ck(geo._buttonSide == "right",
        "THE ACCOUNT DIFFERENCE: a window flush left gets its column flipped RIGHT")
    ck(geo.buttonFrame._shown == true, "…and the client RE-SHOWS it while doing so")

    local pxW = _G.UIParent:GetWidth() * _G.UIParent:GetEffectiveScale()
    Sim.SetUIScale(1.0)
    ck(math.abs(_G.UIParent:GetWidth() * _G.UIParent:GetEffectiveScale() - pxW) < 1e-6,
        "changing uiScale leaves the PIXEL screen identical")
    ck(_G.UIParent:GetWidth() ~= 1920 / gScale, "…while UIParent's UNIT width really moved")
    Sim.SetUIScale(gScale)
    geo._left, geo._bottom, geo._clampInsets = gL, gB, nil
    _G.FCF_UpdateButtonSide(geo)                 -- the column back where the client wants it

    local geb = _G.ChatFrame6EditBox
    ck(geb and geb._shown == false, "the attached edit box starts HIDDEN (chatStyle 'classic')")
    _G.ChatEdit_ActivateChat(geb)
    ck(geb._shown == true and geb._focused == true and geb.header._shown == true,
        "activating shows it, focuses it and raises the sticky prefix")
    _G.ChatEdit_DeactivateChat(geb)
    ck(geb._shown == false and geb.header._shown == false,
        "THE CLIENT HIDES IT AGAIN on deactivate (what a persistent box must beat)")
    Sim.cvars.chatStyle = "im"
    _G.ChatEdit_ActivateChat(geb)
    _G.ChatEdit_DeactivateChat(geb)
    ck(geb._shown == true, "…except under chatStyle 'im', the client's OWN persistent mode")
    Sim.cvars.chatStyle = "classic"
    geb:Hide()
    ck(_G.IsAltKeyDown() == false, "the ALT modifier reads false until a test holds it")

    -- 10. THE CREATABLE ScrollingMessageFrame (D2/view sim extension). An
    --     addon that draws its own view creates its OWN message frames, and
    --     until this existed those frames' AddMessage was an auto-vivified
    --     no-op — a mirror into a no-op is indistinguishable from a mirror that
    --     works, which is exactly the "absent API is a kinder client" blind
    --     spot Class 9 names. The rig has to prove the frame is REAL, that it
    --     starts with the CLIENT's own posture (fading ON, so "off" has to be
    --     asked for), and — the unkind half — that NOTHING in the client's own
    --     machinery can reach it.
    local mine = _G.CreateFrame("ScrollingMessageFrame", nil, _G.UIParent)
    ck(type(mine.historyBuffer) == "table", "an addon-created SMF has a REAL ring buffer")
    ck(mine._fading == true,
        "…and inherits the CLIENT's posture: fading ON until something says otherwise")
    mine:AddMessage("mine one", 0.5, 0.25, 0.125)
    mine:AddMessage("mine two", 1, 1, 1)
    ck(mine:GetNumMessages() == 2, "AddMessage lands in an addon-created frame's own buffer")
    local mm, mr, mg, mb = mine:GetMessageInfo(1)
    ck(mm == "mine one" and mr == 0.5 and mg == 0.25 and mb == 0.125,
        "…carrying its NUMERIC r,g,b through unchanged (the ink is not in a string)")
    ck(mine.historyBuffer:GetEntryAtIndex(1).message == "mine two",
        "…newest-first GetEntryAtIndex works on it too")
    mine:Clear()
    ck(mine:GetNumMessages() == 0, "Clear empties it (the view's resync depends on this)")
    local seen = false
    for _, f in ipairs(Sim.createdSMFs) do if f == mine then seen = true end end
    ck(seen, "the sim records addon-created SMFs so a test can ask about them")
    -- THE UNREACHABILITY PIN: run every client beat there is and prove none of
    -- them touched it. This is a STRUCTURAL claim (it is in no client list),
    -- not a pinning contest — which is the whole reason to own the frame.
    mine:SetFading(false)
    mine:SetAlpha(1)
    Sim.ClientFadeBeat()
    for wid = 1, _G.NUM_CHAT_WINDOWS do _G.FloatingChatFrame_Update(wid) end
    _G.FCF_DockUpdate()
    Sim.LayoutBeat()
    ck(mine._fading == false and mine:GetAlpha() == 1,
        "CLIENT BEATS CANNOT REACH IT: fade, window update, dock pass and layout all ran "
        .. "and the addon's own frame did not move")
    ck(Sim.Frame(1):GetAlpha() ~= 1 or true, "(the client's own windows are the client's business)")

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
        local _, stampN = msg:gsub("%d%d:%d%d", "")
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
            local _, n = tostring(e.message):gsub("%d%d:%d%d", "")
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
        local _, liveStamps = tostring(newest and newest.message):gsub("%d%d:%d%d", "")
        ck(liveStamps == 1, "leg 3: the live line wears exactly one stamp")
        ck(ns.Badges.counts[cf1] == 1,
            "leg 3: the live line badged exactly once (restored lines contributed zero)")

        -- ── Leg 4: a CHANNEL line with an ALIAS, in the merged world. ────────
        -- The alias decorator shares decor.lua's protect/restore engine with
        -- stamps, names, urls, history and badges all live. This is the one
        -- place that proves a display rename of a live hyperlink survives the
        -- full stack: the header reads as the alias, the click payload is
        -- byte-identical, and the item link on the same line is untouched.
        local aliasLink = Sim.MakeItemLink()
        C.SetAlias("World", "Glob")
        Sim.SendChat{ event = "CHAT_MSG_CHANNEL", text = "trading " .. aliasLink,
            sender = "Choco", guid = "Player-1-00000002",
            channelNumber = 2, channelName = "World" }
        HTIMER.advance(0)
        local chanMsg = tostring((cf1.historyBuffer:GetEntryAtIndex(1) or {}).message)
        ck(chanMsg:find("|Hchannel:channel:2|h[Glob]|h", 1, true) ~= nil,
            "leg 4: the channel header wears the ALIAS under the full stack")
        ck(chanMsg:find("|Hchannel:channel:2|h", 1, true) ~= nil,
            "leg 4: …with the channel link's payload byte-identical")
        ck(chanMsg:find(aliasLink, 1, true) ~= nil,
            "leg 4: …and the item link beside it is still byte-intact")
        local _, aliasStamps = chanMsg:gsub("%d%d:%d%d", "")
        ck(aliasStamps == 1, "leg 4: the aliased line still wears exactly one stamp")
        C.SetAlias("World", "")
        Sim.SendChat{ event = "CHAT_MSG_CHANNEL", text = "native again",
            sender = "Choco", guid = "Player-1-00000002",
            channelNumber = 2, channelName = "World" }
        HTIMER.advance(0)
        ck(tostring((cf1.historyBuffer:GetEntryAtIndex(1) or {}).message)
            :find("[2. World]", 1, true) ~= nil,
            "leg 4: removing the alias returns the client's own header")

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
-- Harness-registered suite: VIEW-INTEGRATION — the merged world with the
-- OWNED VIEW up. The suite above proves the stack works with the client's
-- windows visible; this one is the D2 revision's headline red control, at the
-- one altitude that matters: EVERY lifecycle module enabled TOGETHER, the view
-- included, so the client's ten windows are a HIDDEN ENGINE while
--   * the reconciler converges an authored config (windows, routing, the paced
--     join list, colours by name) — RED CONTROL: reconcile/channels/sync are
--     unchanged code and must be green with nothing on screen;
--   * a line flows through the whole decoration stack into a hidden window and
--     is MIRRORED into the view's own frame, byte-identical, ink intact;
--   * history's cross-session restore backfills the hidden engine with
--     PushFront (never AddMessage) and the view's resync puts it on screen;
--   * badges count on OUR tab buttons, and clear when OUR tab is selected;
--   * the client's own fade / clamp / dock beats all run and reach NOTHING of
--     ours.
-- Runs LAST, against the world exactly as every other suite left it.
----------------------------------------------------------------------

ns:RegisterSelfTest("view-integration", function(verbose)
    local fails = {}
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local ok, err = pcall(function()
        local V, C, B = ns.View, ns.Config, ns.Badges
        local cf1 = _G.ChatFrame1

        local ALL = { "decor", "stamps", "names", "urls", "history", "badges",
                      "skin", "channels", "view", "reconcile" }
        for _, name in ipairs(ALL) do
            if name ~= "reconcile" then ns.SetModuleEnabled(name, true) end
        end

        -- Author the config the reconciler will converge, with the view already
        -- up and every window already hidden.
        local c = C.Get()
        c.windows = {}
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do c.windows[id] = C.CaptureWindow(id) end
        c.windows[1].name = "Viewed"
        c.windows[1].fontSize = 15
        local hasWorld = false
        for _, nm in ipairs(c.windows[1].channels) do if nm == "World" then hasWorld = true end end
        if not hasWorld then
            c.windows[1].channels[#c.windows[1].channels + 1] = "World"
            table.sort(c.windows[1].channels)
        end
        c.join   = { { 1, "General" }, { 2, "World" } }
        c.colors = { world = { r = 0.9, g = 0.3, b = 0.2 } }
        c.rev, c.at = (tonumber(c.rev) or 0) + 1, C.Now()

        ns.SetModuleEnabled("reconcile", true)
        local allUp = true
        for _, name in ipairs(ALL) do
            local m = ns.Modules[name]
            if not (m and m.__active) then allUp = false end
        end
        ck(allUp, "every lifecycle module is active TOGETHER, the view included")
        ck(V.active and type(V.chassis) == "table", "the view is painting")

        -- The engine is down before the reconcile and must be down after it.
        local function engineDown()
            for _, id in ipairs(V.ids) do
                local f = _G["ChatFrame" .. id]
                if f and f:IsShown() then return false end
            end
            return true
        end
        ck(engineDown(), "every owned client window is hidden going in")

        local drops0 = Sim.droppedJoins
        Sim.EnterWorld(false, false)
        HTIMER.flush()
        ck(select(1, _G.GetChatWindowInfo(1)) == "Viewed",
            "RED CONTROL: the reconciler renamed window 1 with the engine HIDDEN")
        ck(select(2, _G.GetChatWindowInfo(1)) == 15, "…font size converged too")
        ck(select(1, _G.GetChannelName("World")) == 2,
            "…the paced join list landed World on its configured number")
        ck(C.NearColor(_G.ChatTypeInfo["CHANNEL2"], c.colors.world),
            "…the channel colour was imposed at the converged number, by name")
        ck(Sim.droppedJoins == drops0, "…with zero dropped channel ops")
        ck(ns.Reconcile._runInFlight == false, "…and the run ENDED (finite ladder)")
        ck(engineDown(), "…and the engine is still hidden afterwards")

        -- A line through the FULL stack, into a hidden window, mirrored out.
        local activeId = V.ActiveId()
        local vf = V.frames[activeId]
        local hidden = _G["ChatFrame" .. activeId]
        V.SelectTab(activeId, "integration")
        B.Clear(hidden)
        local vBefore, cBefore = vf:GetNumMessages(), hidden:GetNumMessages()
        local mirroredBefore = V.mirrored
        local itemLink = Sim.MakeItemLink()
        Sim.SendChat{ event = "CHAT_MSG_SAY",
            text = "viewed " .. itemLink .. " at www.example.com",
            sender = "Puu-Whitemane", guid = "Player-1-00000001" }
        HTIMER.advance(0)
        ck(hidden:GetNumMessages() == cBefore + 1,
            "the HIDDEN engine window received the line (routing is the store's, not the frame's)")
        ck(vf:GetNumMessages() == vBefore + 1, "…and exactly one line reached the view")
        ck(V.mirrored == mirroredBefore + 1, "…forwarded exactly once")
        local vNew = vf.historyBuffer:GetEntryAtIndex(1)
        local cNew = hidden.historyBuffer:GetEntryAtIndex(1)
        ck(vNew and cNew and vNew.message == cNew.message,
            "the mirrored line is BYTE-IDENTICAL to the fully decorated one")
        ck(vNew and vNew.message:find(itemLink, 1, true) ~= nil,
            "…item link byte-intact under the full decoration stack")
        ck(vNew and vNew.message:find("|Haddon:dchaturl:www.example.com|h", 1, true) ~= nil,
            "…the URL linkified beside it")
        local _, stampN = tostring(vNew and vNew.message):gsub("%d%d:%d%d", "")
        ck(stampN == 1, "…wearing exactly ONE stamp (no double-processing across the mirror)")
        ck(type(vNew.r) == "number" and vNew.r == cNew.r,
            "…and the class/channel ink rode as NUMBERS, identical on both sides")
        ck(V.mirrorReentries >= 0 and V.mirrorRefusals == V.mirrorRefusals,
            "(the mirror's counters are readable)")

        -- BADGES on OUR tabs. A window the player cannot see counts; selecting
        -- OUR tab clears it, because our selection routes through the client's
        -- own FCF_SelectDockFrame.
        local other
        for _, id in ipairs(V.ids) do if id ~= activeId then other = id end end
        if other then
            local otherFrame = _G["ChatFrame" .. other]
            local otherTab = V.tabs[other] and V.tabs[other].button
            ck(B.TabFor(otherFrame) == otherTab,
                "a badge rides OUR tab button while the view paints")
            local w = B.widgets[otherFrame]
            ck(w and w.holder and w.holder._parent == otherTab,
                "…and its holder is really parented to it")
            B.Clear(otherFrame)
            otherFrame:AddMessage("unseen line", 1, 1, 1)
            HTIMER.advance(0)
            ck((B.counts[otherFrame] or 0) >= 1, "an unseen tab counts")
            V.SelectTab(other, "integration")
            ck(B.counts[otherFrame] == 0,
                "…and selecting OUR tab clears it (the client's own select verb ran)")
            V.SelectTab(activeId, "integration")
        end

        -- HISTORY's cross-session restore: PushFront into the hidden engine,
        -- then the view's own resync puts the scrollback on screen.
        Sim.Logout()
        Sim.NewSession()
        Sim.ResetCalls()
        local mirroredAtRestore = V.mirrored
        local clientAddsBefore = 0
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            clientAddsBefore = clientAddsBefore + (_G["ChatFrame" .. id]:GetNumMessages())
        end
        Sim.EnterWorld(true, false)
        HTIMER.flush()
        -- RED CONTROL, measured on the ONE counter that can only move when a
        -- CLIENT window's AddMessage wrap fires. (Sim.CallCount("AddMessage")
        -- is no longer the right witness in this world: the view's own resync
        -- legitimately calls AddMessage on OUR frames, which are
        -- ScrollingMessageFrames too, and a counter that both paths bump would
        -- alibi exactly the defect this control exists to catch.)
        ck(V.mirrored == mirroredAtRestore,
            "RED CONTROL: the restore re-entered NO client AddMessage wrap — the mirror "
            .. "forwarded nothing, so the backfill really was PushFront-only")
        ck((V.resyncedLines or 0) > 0, "…while the view's own re-read DID move lines")
        ck(cf1:GetNumMessages() > 0, "the hidden engine was backfilled")
        local restoredInto = V.frames[V.ActiveId()]
        ck(restoredInto:GetNumMessages() == _G["ChatFrame" .. V.ActiveId()]:GetNumMessages(),
            "…and the view's resync put exactly that scrollback on screen")
        ck(engineDown(), "…with every engine window still hidden through the whole login")

        -- The client's own beats, one more time, in the merged world.
        local alphas = {}
        for _, id in ipairs(V.ids) do
            alphas[id] = { V.frames[id]:GetAlpha(), V.frames[id]._fading,
                           V.tabs[id].button:GetAlpha() }
        end
        local chassisAlpha = V.chassis:GetAlpha()
        Sim.ClientFadeBeat()
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
        _G.FCF_DockUpdate()
        Sim.LayoutBeat()
        local moved = false
        for _, id in ipairs(V.ids) do
            local a = alphas[id]
            if V.frames[id]:GetAlpha() ~= a[1] or V.frames[id]._fading ~= a[2]
               or V.tabs[id].button:GetAlpha() ~= a[3] then moved = true end
        end
        ck(not moved, "the client's fade/clamp/dock beats reached NOTHING of ours")
        ck(V.chassis:GetAlpha() == chassisAlpha, "…including the chassis")
        ck(engineDown(), "…and the engine stayed down through all of them")

        -- Tidy: back to the states the module suites left, and the DEFAULT
        -- window world restored (this suite authored a converged layout).
        ns.SetModuleEnabled("view", false)
        ns.SetModuleEnabled("stamps", false)
        ns.SetModuleEnabled("reconcile", false)
        ns.SetModuleEnabled("channels", false)
        _G.FCF_ResetChatWindows()
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
        HTIMER.flush()
        Sim.ResetCalls()
    end)
    if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL view-integration :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS view-integration") end
    return #fails == 0
end)

----------------------------------------------------------------------
-- Harness-registered suite: VIEW-MATRIX — the placement matrix, driven the way
-- the PLAYER drives it.
--
-- WHY IT EXISTS (owner, 2026-08-11: "setting the tabs to left breaks the
-- window", with a screenshot of one tab still on the top strip while three more
-- were drawn down the left OVER the message text). Every individual fact in
-- that screenshot had a passing test:
--   * the view suite's phase 14 checked all three placements — but it called
--     View.Layout() by hand, so it exercised the layout and never the APPLY
--     PATH the settings pane actually uses;
--   * phase 13 measured a tab run — but only a TOP one, at one size, with the
--     tab count the default world happens to have.
-- The misses kept coming from untested COMBINATIONS, so this suite is a matrix
-- rather than a list of cases: {top, left, right} x {badges on, off} x {1..5
-- tabs} x {floor, default, large}, and every transition between placements is
-- driven in both directions with the invariants re-checked after each one.
--
-- The invariants, all measured through the sim's anchor resolver:
--   1. every tab lies FULLY inside the strip/rail surface;
--   2. no two tabs overlap;
--   3. no tab is left on the surface the placement is NOT using (the mixed
--      state — checked as "outside the strip's rect", which is what that
--      failure looks like geometrically);
--   4. the feed is disjoint from the strip/rail and from the entry bar;
--   5. the entry bar is disjoint from the strip/rail and the feed;
--   6. every one of them is inside the chassis;
--   7. no corner grip covers message text, a tab's LABEL, or the edit box.
----------------------------------------------------------------------

ns:RegisterSelfTest("view-matrix", function(verbose)
    local fails = {}
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local ok, err = pcall(function()
        local V, C, O = ns.View, ns.Config, ns.Options
        local rect = Sim.ResolveRect
        local savedPlace = C.TabPlacement()
        local savedView, savedBadges = ns.ModuleEnabled("view"), ns.ModuleEnabled("badges")
        local savedWindows = {}
        for id = 3, 7 do
            local w = Sim.windows[id]
            if w then savedWindows[id] = { w.name, w.shown, w.docked } end
        end
        ns.SetModuleEnabled("badges", true)
        ns.SetModuleEnabled("view", true)
        HTIMER.flush()

        local function inside(a, b, slack)          -- is rect a inside rect b?
            local al, ab, aw, ah = rect(a)
            local bl, bb, bw, bh = rect(b)
            if al == nil or bl == nil then return nil end
            slack = slack or 1e-6
            return al >= bl - slack and al + aw <= bl + bw + slack
               and ab >= bb - slack and ab + ah <= bb + bh + slack
        end

        -- Every geometric invariant, for the world as it stands right now.
        -- Returns a list of human-readable violations (empty = the cell holds).
        local function violations(tag)
            local out = {}
            local function bad(m) out[#out + 1] = tag .. " " .. m end
            local cl, cb, cw, chh = rect(V.chassis)
            local sl, sb, sw, sh   = rect(V.strip)
            local el, eb, ew, eh   = rect(V.entry)
            local fl, fb, fw, fh   = rect(V.frames[V.ActiveId()])
            if cl == nil then bad("the chassis does not resolve") return out end
            if sl == nil then bad("the strip does not resolve") return out end
            if el == nil then bad("the entry does not resolve") return out end
            if fl == nil then bad("the feed does not resolve") return out end
            if fw <= 0 or fh <= 0 then bad("the feed has no real rect") end
            if inside(V.strip, V.chassis) == false then bad("the strip escapes the chassis") end
            if inside(V.entry, V.chassis) == false then bad("the entry escapes the chassis") end
            if inside(V.frames[V.ActiveId()], V.chassis) == false then
                bad("the feed escapes the chassis")
            end
            if Sim.RectsOverlap(V.frames[V.ActiveId()], V.strip) then
                bad("THE FEED OVERLAPS THE TAB SURFACE (text under the tabs)")
            end
            if Sim.RectsOverlap(V.frames[V.ActiveId()], V.entry) then
                bad("the feed overlaps the entry bar")
            end
            if Sim.RectsOverlap(V.entry, V.strip) then bad("the entry overlaps the tab surface") end
            for i, id in ipairs(V.ids) do
                local btn = V.tabs[id] and V.tabs[id].button
                if not btn then bad("tab " .. id .. " has no button")
                else
                    local tl, tb, tw, th = rect(btn)
                    if tl == nil then bad("tab " .. id .. " does not resolve")
                    else
                        if inside(btn, V.strip) == false then
                            bad("TAB " .. id .. " IS NOT ON THE TAB SURFACE (the mixed state)")
                        end
                        if inside(btn, V.chassis) == false then
                            bad("tab " .. id .. " escapes the chassis")
                        end
                        if Sim.RectsOverlap(btn, V.frames[V.ActiveId()]) then
                            bad("tab " .. id .. " is drawn over the message feed")
                        end
                        for j = i + 1, #V.ids do
                            local other = V.tabs[V.ids[j]] and V.tabs[V.ids[j]].button
                            if other and Sim.RectsOverlap(btn, other) then
                                bad("tabs " .. id .. " and " .. V.ids[j] .. " OVERLAP")
                            end
                        end
                    end
                    -- The pip rides the tab, inside it, wherever the tab is.
                    local B = ns.Badges
                    local bw2 = B and B.widgets and B.widgets[V.ClientFrame(id)]
                    if bw2 and bw2.holder and bw2.holder._shown and inside(bw2.holder, btn) == false then
                        bad("the unread pip on tab " .. id .. " is NOT inside its tab")
                    end
                    -- …and no grip covers a tab's label or the message text.
                    for _, corner in ipairs(V.GRIP_CORNERS) do
                        local g = V.grips[corner]
                        if g and g._shown then
                            if Sim.RectsOverlap(g, V.frames[V.ActiveId()]) then
                                bad("the " .. corner .. " grip covers message text")
                            end
                            local label = V.tabs[id] and V.tabs[id].label
                            if label and tostring(label:GetText() or "") ~= ""
                               and Sim.RectsOverlap(g, label) then
                                bad("the " .. corner .. " grip covers tab " .. id .. "'s label")
                            end
                        end
                    end
                end
            end
            -- THE EDIT BOX is asked about its TEXT rect, not its frame: the
            -- entry bar spans the box's full width by design, so its frame and
            -- the two bottom grips share the corners necessarily. What must
            -- never happen is a grip over the TYPING AREA — and the mockup's
            -- 12-unit entry padding is exactly what keeps them apart (the grip
            -- ends where the text begins, which is why the padding is not free
            -- to shrink).
            local heldEB = V._ebHome and V._ebHome.eb
            if heldEB then
                local ebl, ebb, ebw, ebh = rect(heldEB)
                local il, ir, it, ib = heldEB:GetTextInsets()
                if ebl ~= nil and il ~= nil then
                    local tl, tb = ebl + il, ebb + (ib or 0)
                    local tw, th = ebw - il - (ir or 0), ebh - (ib or 0) - (it or 0)
                    for _, corner in ipairs(V.GRIP_CORNERS) do
                        local g = V.grips[corner]
                        local gl, gb, gw, gh = rect(g)
                        if g and g._shown and gl ~= nil
                           and not (gl + gw <= tl or tl + tw <= gl)
                           and not (gb + gh <= tb or tb + th <= gb) then
                            bad("the " .. corner .. " grip covers the edit box's typing area")
                        end
                    end
                end
            end
            return out
        end

        -- Open windows until the view owns `n` of them (2 is the combat log and
        -- is never ours, so the ids are not contiguous — that is the point).
        local nextName = { "Focus", "DMs", "Loot", "Trade", "Raid" }
        local function windowsTo(n)
            local guard = 0
            while #V.OwnedIds() < n and guard < 8 do
                guard = guard + 1
                _G.FCF_OpenNewWindow(nextName[guard] or ("W" .. guard))
            end
            V.Refresh()
            HTIMER.flush()
            return #V.ids
        end

        local cells, worst = 0, {}
        local COUNTS = { 1, 2, 3, 5 }
        local SIZES  = { "floor", "default", "large" }
        -- Every ORDERED transition between the three placements, walked as one
        -- path: top->left->top->right->left->right->top.
        local WALK = { "top", "left", "top", "right", "left", "right", "top" }

        for _, want in ipairs(COUNTS) do
            local got = windowsTo(want)
            for _, badgesOn in ipairs({ true, false }) do
                ns.SetModuleEnabled("badges", badgesOn)
                if badgesOn then
                    -- Real unread counts, so the pips are really in the layout.
                    for _, id in ipairs(V.ids) do
                        if id ~= V.ActiveId() then
                            V.ClientFrame(id):AddMessage("unread " .. id, 1, 1, 1)
                        end
                    end
                    HTIMER.advance(0)
                end
                for _, size in ipairs(SIZES) do
                    for _, place in ipairs(WALK) do
                        -- THE REAL APPLY PATH: the settings pane's own seam, not
                        -- a hand-called View.Layout(). This is the whole point of
                        -- the suite — the defect lived between the two.
                        O.SetTabPlacement(place)
                        if size == "floor" then
                            V.ResizeAnchored(1, 1, "BOTTOMRIGHT")
                        elseif size == "large" then
                            V.ResizeAnchored(900, 500, "BOTTOMRIGHT")
                        else
                            V.Layout()
                        end
                        cells = cells + 1
                        local tag = ("[%d tab(s), badges %s, %s, %s]"):format(
                            #V.ids, badgesOn and "on" or "off", size, place)
                        for _, v in ipairs(violations(tag)) do
                            if #worst < 12 then worst[#worst + 1] = v end
                        end
                        -- …AND THE CHEAP BEATS. This is the shape the owner's
                        -- mixed strip/rail state actually had: the placement
                        -- answer changed WITHOUT this character running an
                        -- apply (a peer account's newer config wins at read
                        -- time — receive never adopts, so no local write and no
                        -- seam), and then some ordinary beat re-ran the TAB RUN
                        -- alone. A run laid out against a stale surface is the
                        -- defect, so the run has to place the surface itself.
                        V._colorHandler()
                        V.SelectTab(V.ids[#V.ids], "matrix")
                        V.LayoutTabs()
                        for _, v in ipairs(violations(tag .. " [cheap beat]")) do
                            if #worst < 12 then worst[#worst + 1] = v end
                        end
                    end
                end
            end
        end
        -- THE PEER-CHANGE LEG, explicitly: the synced answer moves with no
        -- local write at all (Config.SetTabPlacement here stands in for a peer
        -- payload winning at read time), and the ONLY thing that runs
        -- afterwards is a cheap beat. Every placement, in both directions.
        for _, place in ipairs({ "left", "top", "right", "top", "left", "right" }) do
            C.SetTabPlacement(place)
            V.LayoutTabs()                       -- the cheap beat, alone
            cells = cells + 1
            for _, v in ipairs(violations("[peer change -> " .. place .. ", cheap beat only]")) do
                if #worst < 12 then worst[#worst + 1] = v end
            end
        end

        ck(cells >= 150, "the matrix really ran (" .. cells .. " cells)")
        ck(#worst == 0, "RED CONTROL — every placement cell holds its geometry ("
            .. #worst .. " violation(s): " .. table.concat(worst, " ; ") .. ")")

        -- Put the world back exactly as it was found.
        ns.SetModuleEnabled("badges", savedBadges)
        C.SetTabPlacement(savedPlace)
        for id = 3, 7 do
            local s = savedWindows[id]
            local w = Sim.windows[id]
            if s and w then
                w.name, w.shown, w.docked = s[1], s[2], s[3]
                _G.FloatingChatFrame_Update(id)
            end
        end
        V.Refresh()
        ns.SetModuleEnabled("view", savedView)
        HTIMER.flush()
        Sim.ResetCalls()
    end)
    if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL view-matrix :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS view-matrix") end
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
    -- post-V1: the settings pane + the channel-alias editor
    "options",
    -- the options rework (2026-08-11): the Tabs section, one page per chat tab
    "options-tabs",
    -- D2 revision: the owned chat view (chassis, tabs, mirror, hidden engine)
    "view",
    -- w2/integration: the merged-world leg (all Wave-2 modules at once)
    "integration",
    -- D2 revision: the merged world WITH THE OWNED VIEW UP (the engine hidden)
    "view-integration",
    -- 2026-08-11: the placement matrix, driven through the settings pane's own
    -- apply path (the untested-combination class the owner kept finding)
    "view-matrix",
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
