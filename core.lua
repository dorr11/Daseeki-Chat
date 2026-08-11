-- Daseeki Chat — core.lua
-- The addon-namespace plumbing every other file assumes: the shared ns runtime
-- (Print / SafeCall / event dispatch seam / local callback bus / self-test
-- registry), the module lifecycle (enable/disable with the suite's inertness
-- discipline — disabled = zero hooks), the /dchat slash surface with an
-- extensible `debug` subcommand registry, and the SavedVariables init
-- (additive + heal, never destructive).
--
-- Mirrors the Daseeki-Bags 2.0 / Daseeki-Nexus core.lua idioms (same suite,
-- same patterns) as FRESH code — clean-room, no third-party identifiers.
--
-- Headless-safe: every game-only global (CreateFrame, SlashCmdList,
-- geterrorhandler) is guarded, so this real core loads under the test
-- harness's chat simulator and PROVIDES the runtime the harness drives.

local ADDON, ns = ...

ns.ADDON    = ADDON
ns.DISPLAY  = "Daseeki Chat"
ns.VERSION  = "0.9.0"
ns.CHAT_TAG = "|cffc9a24dDaseeki Chat|r"

----------------------------------------------------------------------
-- Error routing (standing suite rule: NEVER a silent pcall — surface every
-- error to the real handler). geterrorhandler is a live global in-game; the
-- harness installs a recorder. Falls back to a re-raise if no handler exists.
----------------------------------------------------------------------

local function routeError(err)
    local geh = _G.geterrorhandler
    local handler = geh and geh()
    if handler then handler(err) else error(err, 0) end
end
ns.RouteError = routeError

----------------------------------------------------------------------
-- Chat print (addon-colored prefix). Freestanding print() is catalog-verified.
----------------------------------------------------------------------

function ns:Print(...)
    print(ns.CHAT_TAG .. ":", ...)
end

----------------------------------------------------------------------
-- SafeCall — pcall a fn and route any error to geterrorhandler (never hide
-- the traceback). Returns the pcall status so callers can branch.
----------------------------------------------------------------------

function ns:SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then routeError(err) end
    return ok, err
end

----------------------------------------------------------------------
-- Event dispatch — THE REGISTRATION SEAM every module uses.
--
-- Modules subscribe with ns:RegisterEvent(event, handler) and — this is the
-- inertness half of the contract — give the subscription BACK with
-- ns:UnregisterEvent(event, handler) in their OnDisable. One shared frame
-- registers each Blizzard event once and fans out to every subscribed handler;
-- a throwing handler is isolated (error routed, siblings still run). When the
-- last handler for an event leaves, the frame unregisters the event too, so a
-- fully disabled module leaves the client seeing NOTHING from us.
----------------------------------------------------------------------

local eventFrame = _G.CreateFrame and _G.CreateFrame("Frame", "DaseekiChatEventFrame")
ns.eventFrame = eventFrame

local eventHandlers = {}   -- event -> array of handler fns

function ns:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        if eventFrame then eventFrame:RegisterEvent(event) end
    end
    list[#list + 1] = handler
    return handler
end

function ns:UnregisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then table.remove(list, i) end
    end
    if #list == 0 then
        eventHandlers[event] = nil
        if eventFrame then eventFrame:UnregisterEvent(event) end
    end
end

-- Introspection for the harness's inertness pins: EventHandlerCount(event)
-- counts one event's handlers; EventHandlerCount() counts them all.
function ns.EventHandlerCount(event)
    if event then
        local list = eventHandlers[event]
        return list and #list or 0
    end
    local n = 0
    for _, list in pairs(eventHandlers) do n = n + #list end
    return n
end

if eventFrame then
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local list = eventHandlers[event]
        if not list then return end
        -- Iterate a snapshot: a handler that unregisters itself (or a sibling)
        -- mid-dispatch must not shift the walk under us.
        local snap = {}
        for i = 1, #list do snap[i] = list[i] end
        for i = 1, #snap do
            local ok, err = pcall(snap[i], event, ...)
            if not ok then routeError(err) end
        end
    end)
end

----------------------------------------------------------------------
-- Local callback bus (in-process signalling between modules; NOT network).
--   ns:On(name, listener)    -- multi-subscriber
--   ns:Off(name, listener)   -- the inertness counterpart
--   ns:Fire(name, ...)       -- safe-calls each listener; one throwing listener
--                               never blocks the others (error routed).
-- Core fires the lifecycle beats every wave hangs off: "DB_READY" (stores
-- attached + healed), "LOGIN", "ENTERING_WORLD" (the reconciler's gate — the
-- client's own restore has run; Class 2 says event-gate, never timer-guess),
-- and "LOGOUT" (history.lua's snapshot moment).
----------------------------------------------------------------------

local callbacks = {}   -- name -> array of listener fns

function ns:On(name, listener)
    local list = callbacks[name]
    if not list then
        list = {}
        callbacks[name] = list
    end
    list[#list + 1] = listener
    return listener
end

function ns:Off(name, listener)
    local list = callbacks[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == listener then table.remove(list, i) end
    end
    if #list == 0 then callbacks[name] = nil end
end

function ns:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    local snap = {}
    for i = 1, #list do snap[i] = list[i] end
    for i = 1, #snap do
        local ok, err = pcall(snap[i], ...)
        if not ok then routeError(err) end
    end
end

----------------------------------------------------------------------
-- Self-test registry (pure-Lua suites; the headless harness runs these, and
-- `/dchat debug selftest` runs them in-game).
----------------------------------------------------------------------

local selfTests = {}   -- ordered { name, fn(verbose) -> ok }

function ns:RegisterSelfTest(name, fn)
    selfTests[#selfTests + 1] = { name = name, fn = fn }
end

function ns:RunRegisteredSelfTests(verbose)
    local allPass = true
    for i = 1, #selfTests do
        if verbose then ns:Print("selftest: " .. selfTests[i].name) end
        local ok, res = pcall(selfTests[i].fn, verbose)
        local passed = ok and res
        if not ok then ns:Print("  FAIL " .. selfTests[i].name .. " :: error " .. tostring(res)) end
        allPass = allPass and passed
    end
    if verbose then
        ns:Print(allPass and "selftest: ALL SUITES PASS" or "selftest: FAILURES ABOVE")
    end
    return allPass
end

----------------------------------------------------------------------
-- SavedVariables — additive + heal, never destructive.
--
-- EnsureDefaults walks the defaults tree and (a) ADDS any missing key,
-- (b) HEALS any value whose type disagrees with the default's type (a corrupt
-- or truncated store must never crash a module at read time), (c) NEVER
-- deletes or rewrites a key the defaults don't know about — user data and
-- future-version data pass through untouched (wire-additive discipline).
----------------------------------------------------------------------

local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = deepCopy(v) end
    return dst
end
ns.DeepCopy = deepCopy

function ns.EnsureDefaults(dst, defaults)
    for k, def in pairs(defaults) do
        local cur = dst[k]
        if cur == nil then
            dst[k] = deepCopy(def)
        elseif type(cur) ~= type(def) then
            dst[k] = deepCopy(def)          -- heal: wrong type is corrupt, reset the branch
        elseif type(def) == "table" then
            ns.EnsureDefaults(cur, def)     -- additive recurse; unknown keys survive
        end
    end
    return dst
end

-- The account store: the authoritative config + module flags. Wave 2's
-- config.lua owns the `config` branch; core owns `schema`, `modules`, `skin`.
ns.DEFAULTS = {
    schema  = 1,
    modules = {},          -- module name -> false to disable (absent = enabled)
    skin = {
        fading     = true,    -- chat text fades after inactivity
        fadeTime   = 100,     -- seconds visible before fading (ElvUI-archetype default)
        editBox    = "BOTTOM",-- attached edit box position: "BOTTOM" or "TOP"
        copyButton = true,    -- per-window copy-chat affordance
    },
}

-- The per-character store: high-churn, never synced (history snapshots land
-- under `history` — Wave 2 history/badges agent).
ns.CHAR_DEFAULTS = {
    schema = 1,
}

function ns.InitSavedVariables()
    _G.DaseekiChatDB     = ns.EnsureDefaults(type(_G.DaseekiChatDB)     == "table" and _G.DaseekiChatDB     or {}, ns.DEFAULTS)
    _G.DaseekiChatCharDB = ns.EnsureDefaults(type(_G.DaseekiChatCharDB) == "table" and _G.DaseekiChatCharDB or {}, ns.CHAR_DEFAULTS)
    ns.db     = _G.DaseekiChatDB
    ns.chardb = _G.DaseekiChatCharDB
end

----------------------------------------------------------------------
-- Module lifecycle — the inertness discipline, made mechanical.
--
-- A module registers ONCE with ns.RegisterModule(name, module). The contract:
--   * module.OnEnable()  — install everything: event subscriptions (via the
--     seam above), secure post-hooks, styling. Called only when the module is
--     enabled, only after PLAYER_LOGIN (or immediately if registered later).
--   * module.OnDisable() — give it all back: ns:UnregisterEvent every
--     subscription, neutralize hook bodies, restore what styling changed.
--   * A module that has never been enabled has touched NOTHING — no hooks, no
--     events, no frames. That is the pin the harness asserts.
-- Enable state persists in db.modules[name] (absent = enabled by default).
----------------------------------------------------------------------

ns.Modules     = {}    -- name -> module table
ns.ModuleOrder = {}    -- registration order (stable; Class 8: never pairs() on the wire)

ns.state = { loaded = false, loggedIn = false, inWorld = false }

function ns.ModuleEnabled(name)
    local flags = ns.db and ns.db.modules
    if flags and flags[name] == false then return false end
    return true
end

local function enableModule(name)
    local m = ns.Modules[name]
    if not m or m.__active then return end
    m.__active = true
    if m.OnEnable then ns:SafeCall(m.OnEnable, m) end
end

local function disableModule(name)
    local m = ns.Modules[name]
    if not m or not m.__active then return end
    m.__active = false
    if m.OnDisable then ns:SafeCall(m.OnDisable, m) end
end

function ns.RegisterModule(name, module)
    if ns.Modules[name] then return ns.Modules[name] end
    ns.Modules[name] = module
    ns.ModuleOrder[#ns.ModuleOrder + 1] = name
    -- Late registration (after login) still honors the lifecycle: an enabled
    -- module comes up now; a disabled one stays inert.
    if ns.state.loggedIn and ns.ModuleEnabled(name) then enableModule(name) end
    return module
end

function ns.SetModuleEnabled(name, on)
    if not ns.Modules[name] then
        ns:Print("no module named '" .. tostring(name) .. "'")
        return
    end
    if ns.db then
        -- Stored as `false` when off and nil when on: an absent key means "the
        -- default", so a later version can change the default without fighting
        -- a store full of explicit `true`s. Explicit if/else, because the
        -- idiomatic `cond and false or nil` COLLAPSES (false is falsey and the
        -- `or` swallows it) — Class 5's falsey-value trap, caught by this
        -- file's own suite on the first harness run.
        if on then ns.db.modules[name] = nil else ns.db.modules[name] = false end
    end
    if ns.state.loggedIn then
        if on then enableModule(name) else disableModule(name) end
    end
end

----------------------------------------------------------------------
-- Slash surface — /dchat, with the `debug` subcommand REGISTRY other modules
-- register into (the design doc's `/dchat debug reconcile` lands there in
-- Wave 2 without touching this file).
----------------------------------------------------------------------

ns.SLASH_COMMANDS = { "/dchat", "/daseekichat" }

local debugCommands = {}   -- name -> { help = string, fn = function(rest) }
local debugOrder    = {}   -- stable listing order

function ns.RegisterDebugCommand(name, help, fn)
    name = tostring(name):lower()
    if not debugCommands[name] then debugOrder[#debugOrder + 1] = name end
    debugCommands[name] = { help = help, fn = fn }
end

function ns.GetDebugCommand(name)
    return debugCommands[tostring(name):lower()]
end

local function dispatch(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "help" then
        ns:Print("Daseeki Chat " .. ns.VERSION .. " — commands:")
        ns:Print("  /dchat status              - module states")
        ns:Print("  /dchat enable <module>     - turn a module on")
        ns:Print("  /dchat disable <module>    - turn a module off (fully inert)")
        ns:Print("  /dchat debug <what>        - diagnostics:")
        for _, name in ipairs(debugOrder) do
            ns:Print("    /dchat debug " .. name .. " - " .. (debugCommands[name].help or ""))
        end
    elseif cmd == "status" then
        for _, name in ipairs(ns.ModuleOrder) do
            local m = ns.Modules[name]
            ns:Print(("  %s: %s%s"):format(name,
                ns.ModuleEnabled(name) and "enabled" or "disabled",
                (m and m.__active) and " (active)" or ""))
        end
    elseif cmd == "enable" or cmd == "disable" then
        local name = (rest or ""):match("^(%S*)"):lower()
        if name == "" then
            ns:Print("usage: /dchat " .. cmd .. " <module>")
        else
            ns.SetModuleEnabled(name, cmd == "enable")
            ns:Print(name .. " " .. cmd .. "d")
        end
    elseif cmd == "debug" then
        local sub, drest = (rest or ""):match("^(%S*)%s*(.-)%s*$")
        sub = (sub or ""):lower()
        local entry = debugCommands[sub]
        if entry then
            ns:SafeCall(entry.fn, drest)
        elseif sub == "" then
            ns:Print("debug commands: " .. table.concat(debugOrder, ", "))
        else
            ns:Print("unknown debug command '" .. sub .. "'. /dchat help lists them.")
        end
    else
        ns:Print("unknown command '" .. cmd .. "'. Try /dchat help.")
    end
end
ns.SlashDispatch = dispatch

if _G.SlashCmdList then
    for i, cmdText in ipairs(ns.SLASH_COMMANDS) do
        _G["SLASH_DASEEKICHAT" .. i] = cmdText
    end
    _G.SlashCmdList["DASEEKICHAT"] = dispatch
end

-- Core's own debug commands. Everything else arrives via the registry.
ns.RegisterDebugCommand("selftest", "run the registered self-test suites", function()
    ns:RunRegisteredSelfTests(true)
end)
ns.RegisterDebugCommand("modules", "list modules and their lifecycle state", function()
    dispatch("status")
end)

----------------------------------------------------------------------
-- Lifecycle wiring
--   ADDON_LOADED (this addon)  -> SavedVariables attach + heal. Fires DB_READY.
--   PLAYER_LOGIN               -> enabled modules come up (OnEnable). Fires LOGIN.
--   PLAYER_ENTERING_WORLD      -> fires ENTERING_WORLD (the reconciler's gate;
--                                 fires again on every zone-in, which is the
--                                 re-verify beat channels.lua wants anyway).
--   PLAYER_LOGOUT              -> fires LOGOUT (history snapshot moment).
----------------------------------------------------------------------

ns:RegisterEvent("ADDON_LOADED", function(_, loaded)
    if loaded ~= ADDON then return end
    ns.InitSavedVariables()
    ns.state.loaded = true
    ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    -- Defensive: a forced load order that skipped ADDON_LOADED must not leave
    -- modules reading a nil db (the store attach is idempotent).
    if not ns.state.loaded then ns.InitSavedVariables() end
    ns.state.loggedIn = true
    for _, name in ipairs(ns.ModuleOrder) do
        if ns.ModuleEnabled(name) then enableModule(name) end
    end
    ns:Fire("LOGIN")
end)

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    ns.state.inWorld = true
    ns:Fire("ENTERING_WORLD", isLogin, isReload)
end)

ns:RegisterEvent("PLAYER_LOGOUT", function()
    ns:Fire("LOGOUT")
end)

----------------------------------------------------------------------
-- Self-tests (pure Lua; suite "core").
----------------------------------------------------------------------

-- Bus + error routing: multi-subscriber, isolation, Off, SafeCall.
local function testBusAndRouting(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    local captured = {}
    local prevGEH = _G.geterrorhandler
    _G.geterrorhandler = function() return function(err) captured[#captured + 1] = err end end

    local ok, err = pcall(function()
        local hits = {}
        local h1 = ns:On("T_MSG", function(a, b) hits[#hits + 1] = "h1:" .. tostring(a) .. "/" .. tostring(b) end)
        ns:On("T_MSG", function(a) hits[#hits + 1] = "h2:" .. tostring(a) end)
        ns:Fire("T_MSG", "x", 7)
        ck(#hits == 2 and hits[1] == "h1:x/7" and hits[2] == "h2:x", "both subscribers fired, in order, with args")

        -- Off removes exactly the given listener.
        ns:Off("T_MSG", h1)
        hits = {}
        ns:Fire("T_MSG", "y")
        ck(#hits == 1 and hits[1] == "h2:y", "Off removed only the named listener")

        -- Isolation: a throwing listener routes its error, siblings still run.
        local reached = false
        ns:On("T_ERR", function() error("boom-in-listener") end)
        ns:On("T_ERR", function() reached = true end)
        local fireOk = pcall(function() ns:Fire("T_ERR") end)
        ck(fireOk and reached, "Fire isolates a throwing listener; later listeners still run")
        local sawBoom = false
        for _, e in ipairs(captured) do if tostring(e):find("boom%-in%-listener") then sawBoom = true end end
        ck(sawBoom, "listener error was ROUTED to geterrorhandler, not swallowed")

        -- SafeCall contract.
        local before = #captured
        ck(ns:SafeCall(function() error("boom-in-safecall") end) == false, "SafeCall returns false on error")
        ck(#captured == before + 1, "SafeCall routed exactly one error")
        ck(ns:SafeCall(function() end) == true, "SafeCall returns true on success")
    end)

    _G.geterrorhandler = prevGEH
    if not ok then fails[#fails + 1] = "suite error: " .. tostring(err) end
end

-- The event seam: register/unregister bookkeeping (the inertness mechanics).
local function testEventSeam(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local h1 = function() end
    local h2 = function() end
    local base = ns.EventHandlerCount("T_EVENT")
    ns:RegisterEvent("T_EVENT", h1)
    ns:RegisterEvent("T_EVENT", h2)
    ck(ns.EventHandlerCount("T_EVENT") == base + 2, "two handlers registered under one event")
    ns:UnregisterEvent("T_EVENT", h1)
    ck(ns.EventHandlerCount("T_EVENT") == base + 1, "unregister removes exactly the named handler")
    ns:UnregisterEvent("T_EVENT", h2)
    ck(ns.EventHandlerCount("T_EVENT") == 0, "last unregister empties the event entirely")
end

-- SavedVariables: additive + heal, never destructive.
local function testDefaults(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local defaults = { a = 1, nest = { x = "hi", y = true }, list = {} }

    -- Additive: missing keys appear, present ones survive.
    local db = { a = 42, extra = "user data", nest = { x = "kept" } }
    ns.EnsureDefaults(db, defaults)
    ck(db.a == 42, "a present value is never overwritten")
    ck(db.extra == "user data", "an unknown key is never deleted (additive)")
    ck(db.nest.x == "kept" and db.nest.y == true, "nested: present kept, missing added")
    ck(type(db.list) == "table", "missing table key added")

    -- Heal: a wrong-typed branch resets to the default.
    local sick = { a = "not a number", nest = "not a table" }
    ns.EnsureDefaults(sick, defaults)
    ck(sick.a == 1, "wrong-typed scalar healed to default")
    ck(type(sick.nest) == "table" and sick.nest.x == "hi", "wrong-typed table healed to default copy")

    -- Healing hands back a COPY: mutating the healed branch must not bleed
    -- into the defaults table (the classic shared-reference corruption).
    sick.nest.x = "mutated"
    ck(defaults.nest.x == "hi", "healed branch is a copy, not a reference into DEFAULTS")
end

-- Module lifecycle: the inertness pin, driven through the real registry.
local function testModuleLifecycle(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local log = {}
    local mod = {
        OnEnable  = function() log[#log + 1] = "enable" end,
        OnDisable = function() log[#log + 1] = "disable" end,
    }

    -- Registered while flagged DISABLED: nothing runs, even post-login.
    ns.db.modules["t_mod"] = false
    ns.RegisterModule("t_mod", mod)
    ck(#log == 0 and not mod.__active, "a disabled module's OnEnable never runs (inertness)")

    -- Flip on: exactly one enable.
    ns.SetModuleEnabled("t_mod", true)
    ck(#log == 1 and log[1] == "enable" and mod.__active, "enabling runs OnEnable once")
    ck(ns.db.modules["t_mod"] == nil, "enabled state stores as nil (default-on discipline)")

    -- Double-enable is a no-op.
    ns.SetModuleEnabled("t_mod", true)
    ck(#log == 1, "re-enabling an active module is a no-op")

    -- Flip off: exactly one disable, persisted as false.
    ns.SetModuleEnabled("t_mod", false)
    ck(#log == 2 and log[2] == "disable" and not mod.__active, "disabling runs OnDisable once")
    ck(ns.db.modules["t_mod"] == false, "disabled state persists as false")

    -- Cleanup (the registry itself is append-only by design; the flag is not).
    ns.db.modules["t_mod"] = nil
end

-- Slash + debug registry: routing, registry extension, unknown fallthrough.
local function testSlash(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local declared = {}
    for _, c in ipairs(ns.SLASH_COMMANDS) do declared[c] = true end
    ck(declared["/dchat"], "/dchat is declared")
    ck(type(ns.SlashDispatch) == "function", "one dispatcher backs every command string")

    -- A module-registered debug command routes with its rest-args.
    local got
    ns.RegisterDebugCommand("t_probe", "test probe", function(rest) got = rest end)
    ns.SlashDispatch("debug t_probe hello world")
    ck(got == "hello world", "debug registry routes subcommand + args")

    -- Unknown debug command answers, never crashes.
    local said = {}
    local realPrint = ns.Print
    ns.Print = function(_, ...) said[#said + 1] = table.concat({ ... }, " ") end
    ns.SlashDispatch("debug t_no_such_thing")
    ns.SlashDispatch("t_not_a_command")
    ns.Print = realPrint
    ck(#said == 2, "unknown debug command and unknown command both answer in chat")

    -- The built-ins are present (the /dchat debug selftest gate).
    ck(ns.GetDebugCommand("selftest") ~= nil, "debug selftest is registered")
    ck(ns.GetDebugCommand("modules") ~= nil, "debug modules is registered")
end

function ns.CoreRunSelfTests(verbose)
    local suites = {
        { name = "bus + error routing", fn = testBusAndRouting },
        { name = "event seam",          fn = testEventSeam },
        { name = "defaults (additive+heal)", fn = testDefaults },
        { name = "module lifecycle",    fn = testModuleLifecycle },
        { name = "slash + debug registry", fn = testSlash },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local okc, e = pcall(suite.fn, fails)
        if not okc then fails[#fails + 1] = "error: " .. tostring(e) end
        local passed = #fails == 0
        if not passed then allPass = false end
        if verbose and ns.Print then
            if passed then ns:Print("  PASS core/" .. suite.name)
            else for _, f in ipairs(fails) do ns:Print("  FAIL core/" .. suite.name .. " :: " .. f) end end
        end
    end
    return allPass
end

ns:RegisterSelfTest("core", ns.CoreRunSelfTests)

return ns
