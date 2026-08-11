-- Daseeki Chat — names.lua  (Wave 2: pipeline, real)
-- Player-name class coloring, GUID-FIRST: on era 11509 every CHAT_MSG_* player
-- event carries the sender GUID in arg12, and GetPlayerInfoByGUID's second
-- return is the class token — the highest-quality source. Discipline:
--   * the GUID is consulted only when non-empty and not the all-zeros
--     sentinel ("0000000000000000") — both arrive in the wild (game fact);
--   * a COLD answer (the API returns nothing for an unencountered player) is
--     an unknown, never a guess: the name stays uncolored, nothing is cached
--     (Class 4 — absence of proof is not absence);
--   * an answered GUID is cached by name, so repeat senders cost ZERO further
--     API calls (the budget pin).
-- The sighting cache is the FALLBACK only: roster/guild/friends/target/
-- mouseover/who events (the game-facts register's list) feed the same cache
-- for senders whose events carry no usable GUID. Localized class names from
-- those sources reverse-map through LOCALIZED_CLASS_NAMES_FEMALE then _MALE.
--
-- Rendering rides decor.lua's LINK decorator surface: the engine hands us the
-- display text of each |Hplayer:...|h link and rebuilds the link itself, so
-- the click payload is untouchable by construction. Only a virgin client
-- display ("[Name]", no escapes) is ever styled — restyled text no longer
-- matches, which makes the decorator idempotent under replays. Bracket
-- styling is minimal per the suite voice: square (default) / angle / none.
--
-- The chatClassColorOverride CVar (Classic-line kill switch: "1" force-
-- disables class colors client-wide) is MANAGED BOTH WAYS: enable holds it at
-- "0", any external flip back to "1" while we are active is re-asserted on
-- CVAR_UPDATE (echo-guarded, bounded), and disable hands back the value we
-- found. Persistence of sighted classes is OPT-IN (chardb, realm-scoped).

local ADDON, ns = ...

local GUID_SENTINEL = "0000000000000000"

local Names = {
    active = false,
    cache  = {},          -- session cache: key -> class token
    _origOverride = nil,  -- chatClassColorOverride found at enable
    _settingCVar  = false,
}
ns.Names = Names

local DEFAULTS = {
    brackets = "square",   -- "square" | "angle" | "none"
    persist  = false,      -- realm-scoped class cache in the per-character store
}

local function cfg()
    return (ns.db and ns.db.names) or DEFAULTS
end

----------------------------------------------------------------------
-- Keys and class tokens.
----------------------------------------------------------------------

local function shortName(name)
    name = tostring(name or ""):gsub("%s+$", "")   -- trailing-space client bug
    if name == "" then return nil end
    local amb = _G.Ambiguate
    if type(amb) == "function" then
        local ok, res = pcall(amb, name, "none")
        if ok and type(res) == "string" and res ~= "" then return res end
    end
    return (name:gsub("%-.*$", ""))
end

local function keyFor(name)
    local short = shortName(name)
    return short and short:lower() or nil
end

-- Accept a class token outright, or reverse-map a localized class name
-- through the client's female-then-male tables (the spec's observed order).
local function toToken(class)
    if type(class) ~= "string" or class == "" then return nil end
    local fem = _G.LOCALIZED_CLASS_NAMES_FEMALE
    if type(fem) == "table" and fem[class] then return fem[class] end
    local male = _G.LOCALIZED_CLASS_NAMES_MALE
    if type(male) == "table" and male[class] then return male[class] end
    if class == class:upper() then return class end   -- already a token
    return nil
end

-- Class token -> hex, honoring the cross-addon override convention first:
-- CUSTOM_CLASS_COLORS, then C_ClassColor, then RAID_CLASS_COLORS. No match =
-- nil = UNCOLORED (never a guessed gray).
function Names.ClassHex(token)
    if type(token) ~= "string" then return nil end
    local c
    local custom = _G.CUSTOM_CLASS_COLORS
    if type(custom) == "table" then c = custom[token] end
    if not c and _G.C_ClassColor and type(_G.C_ClassColor.GetClassColor) == "function" then
        local ok, got = pcall(_G.C_ClassColor.GetClassColor, token)
        if ok then c = got end
    end
    if not c then
        local rcc = _G.RAID_CLASS_COLORS
        if type(rcc) == "table" then c = rcc[token] end
    end
    if type(c) ~= "table" or type(c.r) ~= "number" then return nil end
    return ("%02x%02x%02x"):format(
        math.floor(math.max(0, math.min(1, c.r)) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, c.g)) * 255 + 0.5),
        math.floor(math.max(0, math.min(1, c.b)) * 255 + 0.5))
end

----------------------------------------------------------------------
-- The cache: session map first, realm-scoped persisted store second (opt-in).
----------------------------------------------------------------------

local function realmStore(createIfMissing)
    if not ns.chardb then return nil end
    local realmFn = _G.GetRealmName
    local realm = type(realmFn) == "function" and realmFn() or nil
    realm = (type(realm) == "string" and realm ~= "") and realm or "Unknown"
    local root = ns.chardb.names
    if type(root) ~= "table" then
        if not createIfMissing then return nil end
        root = { realms = {} }
        ns.chardb.names = root
    end
    if type(root.realms) ~= "table" then root.realms = {} end
    local store = root.realms[realm]
    if type(store) ~= "table" then
        if not createIfMissing then return nil end
        store = {}
        root.realms[realm] = store
    end
    return store
end

function Names.CacheGet(key)
    if type(key) ~= "string" then return nil end
    local hit = Names.cache[key]
    if hit then return hit end
    if cfg().persist then
        local store = realmStore(false)
        return store and store[key] or nil
    end
    return nil
end

local function cacheSet(key, token)
    if type(key) ~= "string" or key == "" or type(token) ~= "string" then return end
    Names.cache[key] = token
    if cfg().persist then
        local store = realmStore(true)
        if store then store[key] = token end
    end
end

function Names.WipeSession()
    Names.cache = {}
end

-- Public sighting entry point (the roster handlers below all land here, and
-- so can future sources). Accepts a token or a localized class name.
function Names.NoteSighting(name, class)
    local key = keyFor(name)
    local token = toToken(class)
    if key and token then cacheSet(key, token) end
end

----------------------------------------------------------------------
-- GUID-first resolution on chat events. The handler only FEEDS the cache;
-- rendering reads the cache at decoration time, so the addon-handler-vs-
-- client-storage ordering coin-flip (Class 2) cannot matter.
----------------------------------------------------------------------

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_CHANNEL",
}

local function onChatEvent(event, ...)
    if not Names.active then return end
    local sender = select(2, ...)
    local guid   = select(12, ...)
    local key = keyFor(sender)
    if not key then return end
    if Names.CacheGet(key) then return end   -- known: zero API calls (budget)
    if type(guid) == "string" and guid ~= "" and guid ~= GUID_SENTINEL then
        local api = _G.GetPlayerInfoByGUID
        if type(api) == "function" then
            local ok, _, token = pcall(api, guid)
            if ok and type(token) == "string" and token ~= "" then
                cacheSet(key, token)
            end
            -- A cold answer caches NOTHING: the name stays uncolored until a
            -- warm source answers (Class 4 — never present absence as fact).
        end
    end
end

----------------------------------------------------------------------
-- Sighting-cache fill sources (fallback only). Every API is guarded — these
-- run against whatever the client (or the harness sim) actually provides.
----------------------------------------------------------------------

local function seedSelf()
    local nameFn, classFn = _G.UnitName, _G.UnitClass
    if type(nameFn) == "function" and type(classFn) == "function" then
        local okN, name = pcall(nameFn, "player")
        local okC, _, token = pcall(classFn, "player")
        if okN and okC then Names.NoteSighting(name, token) end
    end
end

local function fillGuild()
    local numFn, infoFn = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    if type(numFn) ~= "function" or type(infoFn) ~= "function" then return end
    local ok, n = pcall(numFn)
    if not ok or type(n) ~= "number" then return end
    for i = 1, n do
        local okI, name, _, _, _, classLoc, _, _, _, _, _, classToken = pcall(infoFn, i)
        if okI and name then Names.NoteSighting(name, classToken or classLoc) end
    end
end

local function fillFriends()
    local CF = _G.C_FriendList
    if type(CF) ~= "table" or type(CF.GetNumFriends) ~= "function"
        or type(CF.GetFriendInfoByIndex) ~= "function" then return end
    local ok, n = pcall(CF.GetNumFriends)
    if not ok or type(n) ~= "number" then return end
    for i = 1, n do
        local okI, info = pcall(CF.GetFriendInfoByIndex, i)
        if okI and type(info) == "table" and info.name then
            Names.NoteSighting(info.name, info.className)
        end
    end
end

local function fillGroup()
    local inRaid = type(_G.IsInRaid) == "function" and _G.IsInRaid()
    if inRaid and type(_G.GetNumGroupMembers) == "function"
        and type(_G.GetRaidRosterInfo) == "function" then
        local ok, n = pcall(_G.GetNumGroupMembers)
        if not ok or type(n) ~= "number" then return end
        for i = 1, n do
            local okI, name, _, _, _, classLoc, classToken = pcall(_G.GetRaidRosterInfo, i)
            if okI and name then Names.NoteSighting(name, classToken or classLoc) end
        end
    elseif type(_G.GetNumSubgroupMembers) == "function"
        and type(_G.UnitName) == "function" and type(_G.UnitClass) == "function" then
        local ok, n = pcall(_G.GetNumSubgroupMembers)
        if not ok or type(n) ~= "number" then return end
        for i = 1, n do
            local unit = "party" .. i
            local okN, name = pcall(_G.UnitName, unit)
            local okC, _, token = pcall(_G.UnitClass, unit)
            if okN and okC and name then Names.NoteSighting(name, token) end
        end
    end
end

local function noteUnit(unit)
    -- Friendly players only (the spec's gate: hostiles are not cached).
    if type(_G.UnitIsPlayer) ~= "function" or type(_G.UnitIsFriend) ~= "function" then return end
    local okP, isP = pcall(_G.UnitIsPlayer, unit)
    local okF, isF = pcall(_G.UnitIsFriend, "player", unit)
    if not (okP and isP and okF and isF) then return end
    if type(_G.UnitName) == "function" and type(_G.UnitClass) == "function" then
        local okN, name = pcall(_G.UnitName, unit)
        local okC, _, token = pcall(_G.UnitClass, unit)
        if okN and okC and name then Names.NoteSighting(name, token) end
    end
end

local function fillWho()
    local CF = _G.C_FriendList
    if type(CF) ~= "table" or type(CF.GetNumWhoResults) ~= "function"
        or type(CF.GetWhoInfo) ~= "function" then return end
    local ok, n = pcall(CF.GetNumWhoResults)
    if not ok or type(n) ~= "number" then return end
    for i = 1, n do
        local okI, info = pcall(CF.GetWhoInfo, i)
        if okI and type(info) == "table" and info.fullName then
            Names.NoteSighting(info.fullName, info.filename or info.classStr)
        end
    end
end

----------------------------------------------------------------------
-- The link decorator: display text only, on virgin client displays only.
----------------------------------------------------------------------

local function decoratePlayerLink(linkType, payload, display)
    if not Names.active then return nil end
    if linkType ~= "player" then return nil end
    -- Only a virgin client display ("[Name]", no escapes/braces) is styled;
    -- anything already styled falls through -> idempotent under replays.
    local inner = display:match("^%[([^|%[%]{}]*)%]$")
    if not inner or inner == "" then return nil end
    local full = payload:match("^([^:]+)")
    local key = keyFor(full and full ~= "" and full or inner)
    local token = key and Names.CacheGet(key) or nil
    local hex = token and Names.ClassHex(token) or nil
    local body = hex and ("|cff" .. hex .. inner .. "|r") or inner
    local b = cfg().brackets or "square"
    local styled
    if b == "angle" then styled = "<" .. body .. ">"
    elseif b == "none" then styled = body
    else styled = "[" .. body .. "]" end
    if styled == display then return nil end
    return styled
end

----------------------------------------------------------------------
-- chatClassColorOverride: managed both ways (see header).
----------------------------------------------------------------------

local function assertOverride()
    if type(_G.GetCVar) ~= "function" or type(_G.SetCVar) ~= "function" then return end
    if _G.GetCVar("chatClassColorOverride") ~= "0" then
        Names._settingCVar = true
        _G.SetCVar("chatClassColorOverride", "0")
        Names._settingCVar = false
    end
end

local function onCVarUpdate(event, name, value)
    if not Names.active or Names._settingCVar then return end
    if name ~= "chatClassColorOverride" then return end
    if tostring(value) ~= "0" then assertOverride() end
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

local subs = {}   -- event -> handler, for symmetric teardown

local function sub(event, handler)
    subs[event] = handler
    ns:RegisterEvent(event, handler)
end

function Names.OnEnable()
    Names.active = true
    if ns.db then ns.EnsureDefaults(ns.db, { names = DEFAULTS }) end
    if ns.chardb then ns.EnsureDefaults(ns.chardb, { names = { realms = {} } }) end

    -- The kill-switch CVar: remember what we found, then hold it open.
    if type(_G.GetCVar) == "function" then
        Names._origOverride = _G.GetCVar("chatClassColorOverride")
    end
    assertOverride()
    sub("CVAR_UPDATE", onCVarUpdate)

    -- GUID-first feed.
    for _, event in ipairs(CHAT_EVENTS) do sub(event, onChatEvent) end

    -- Sighting fallback feeds (all guarded; events per the game-facts register).
    sub("GUILD_ROSTER_UPDATE", function() fillGuild() end)
    sub("FRIENDLIST_UPDATE", function() fillFriends() end)
    sub("GROUP_ROSTER_UPDATE", function() fillGroup() end)
    sub("WHO_LIST_UPDATE", function() fillWho() end)
    sub("PLAYER_TARGET_CHANGED", function() noteUnit("target") end)
    sub("UPDATE_MOUSEOVER_UNIT", function() noteUnit("mouseover") end)
    sub("PLAYER_LEVEL_UP", function() seedSelf() end)
    sub("PLAYER_LEAVING_WORLD", function() Names.WipeSession() end)
    seedSelf()

    ns.Decor.RegisterLinkDecorator("names", 10, decoratePlayerLink)
end

function Names.OnDisable()
    Names.active = false
    ns.Decor.UnregisterLinkDecorator("names")
    for event, handler in pairs(subs) do
        ns:UnregisterEvent(event, handler)
    end
    subs = {}
    -- Hand the kill switch back exactly as found.
    if Names._origOverride ~= nil and Names._origOverride ~= "0"
        and type(_G.GetCVar) == "function" and type(_G.SetCVar) == "function"
        and _G.GetCVar("chatClassColorOverride") == "0" then
        Names._settingCVar = true
        _G.SetCVar("chatClassColorOverride", Names._origOverride)
        Names._settingCVar = false
    end
    Names._origOverride = nil
    Names.WipeSession()
end

ns.RegisterModule("names", Names)

ns.RegisterDebugCommand("names", "class-color state: cache size, CVar posture ('names reset' wipes the realm store)", function(rest)
    if (rest or ""):match("^reset") then
        if ns.chardb and type(ns.chardb.names) == "table" then ns.chardb.names.realms = {} end
        Names.WipeSession()
        ns:Print("names: session cache and realm store wiped")
        return
    end
    local n = 0
    for _ in pairs(Names.cache) do n = n + 1 end
    local cvar = type(_G.GetCVar) == "function" and _G.GetCVar("chatClassColorOverride") or "?"
    ns:Print(("names: %s, %d cached, brackets=%s persist=%s chatClassColorOverride=%s")
        :format(Names.active and "active" or "inactive", n,
            tostring(cfg().brackets), tostring(cfg().persist), tostring(cvar)))
end)

----------------------------------------------------------------------
-- Self-tests (suite "names").
----------------------------------------------------------------------

local function testNames(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local f1 = Sim.Frame(1)
    local function newest() return f1.historyBuffer:GetEntryAtIndex(1).message end

    -- ── Phase 0: inertness. ──────────────────────────────────────────────────
    ck(Names.active == false, "phase 0: module inactive after disabled login")
    ck(next(Names.cache) == nil, "phase 0: cache untouched while disabled")
    ck(_G.GetCVar("chatClassColorOverride") == "1",
        "phase 0: the hostile CVar default is untouched while disabled")

    -- ── Phase 1: enable — CVar managed, self seeded. ─────────────────────────
    ns.SetModuleEnabled("names", true)
    ck(Names.active == true, "phase 1: enabled")
    ck(_G.GetCVar("chatClassColorOverride") == "0",
        "phase 1: enable holds the kill-switch CVar at 0")
    ck(Names.CacheGet("tester") == "WARLOCK", "phase 1: self class seeded into the cache")

    -- ── Phase 2: GUID-first coloring + the budget pin. ───────────────────────
    local b2 = Sim.CallCount("GetPlayerInfoByGUID")
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "hello there",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    ck(Names.CacheGet("puu") == "WARRIOR", "phase 2: GUID resolved and cached under the short name")
    ck(newest():find("|cffc79c6ePuu|r", 1, true) ~= nil,
        "phase 2: the very first message from a GUID-bearing sender is class-colored")
    ck(newest():find("|Hplayer:Puu-Whitemane", 1, true) ~= nil,
        "phase 2: the click payload is byte-intact through coloring")
    for i = 1, 3 do
        Sim.SendChat{ event = "CHAT_MSG_SAY", text = "again " .. i,
            sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    end
    ck(Sim.CallCount("GetPlayerInfoByGUID") == b2 + 1,
        "phase 2 BUDGET: four messages from one sender = exactly one GUID lookup")

    -- ── Phase 3: the zero-GUID sentinel — no lookup, no color, no guess. ─────
    local b3 = Sim.CallCount("GetPlayerInfoByGUID")
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "who am I",
        sender = "Mystery", guid = "zero" }
    ck(Sim.CallCount("GetPlayerInfoByGUID") == b3,
        "phase 3 RED CONTROL: the all-zeros sentinel never reaches the API")
    ck(newest():find("|h[Mystery]|h", 1, true) ~= nil,
        "phase 3: the sentinel sender's name is UNCOLORED (virgin display kept)")
    ck(Names.CacheGet("mystery") == nil, "phase 3: nothing was cached for the sentinel")

    -- ── Phase 4: a cold GUID — one lookup, nothing invented. ─────────────────
    local b4 = Sim.CallCount("GetPlayerInfoByGUID")
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "boo",
        sender = "Ghost", guid = "Player-1-99999999" }
    ck(Sim.CallCount("GetPlayerInfoByGUID") == b4 + 1, "phase 4: the cold GUID was asked once")
    ck(newest():find("|h[Ghost]|h", 1, true) ~= nil,
        "phase 4 RED CONTROL: a cold answer leaves the name uncolored — never guessed")
    ck(Names.CacheGet("ghost") == nil, "phase 4: a cold answer caches nothing (Class 4)")

    -- ── Phase 5: sighting fallback + localized-name mapping. ─────────────────
    Names.NoteSighting("Choco-Whitemane", "Mage")   -- localized, cross-realm form
    ck(Names.CacheGet("choco") == "MAGE", "phase 5: localized class name mapped to its token")
    Sim.SendChat{ event = "CHAT_MSG_WHISPER", text = "psst",
        sender = "Choco-Whitemane" }               -- guid nil -> "" on the wire
    ck(newest():find("|cff69ccf0Choco|r", 1, true) ~= nil,
        "phase 5: a GUID-less whisper colors from the sighting cache (fallback path)")

    -- ── Phase 6: channel coverage feeds the cache too. ───────────────────────
    Sim.playerDB["Player-1-00000003"] = { name = "Rhee", localizedClass = "Warlock", classToken = "WARLOCK" }
    Sim.SendChat{ event = "CHAT_MSG_CHANNEL", text = "wts stuff",
        sender = "Rhee", guid = "Player-1-00000003",
        channelNumber = 2, channelName = "World" }
    ck(Names.CacheGet("rhee") == "WARLOCK", "phase 6: channel messages feed the GUID-first cache")
    ck(newest():find("|cff9482c9Rhee|r", 1, true) ~= nil,
        "phase 6: the channel line's sender is class-colored")

    -- ── Phase 7: bracket styling (display only, payload untouched). ──────────
    ns.db.names.brackets = "angle"
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "angled",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    ck(newest():find("|h<|cffc79c6ePuu|r>|h", 1, true) ~= nil,
        "phase 7: angle brackets style the display")
    ns.db.names.brackets = "none"
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "bare",
        sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    ck(newest():find("|h|cffc79c6ePuu|r|h", 1, true) ~= nil,
        "phase 7: 'none' drops the brackets entirely")
    ns.db.names.brackets = "square"
    -- Custom color override convention wins over RAID_CLASS_COLORS.
    _G.CUSTOM_CLASS_COLORS = { WARRIOR = { r = 1, g = 0, b = 0 } }
    ck(Names.ClassHex("WARRIOR") == "ff0000", "phase 7: CUSTOM_CLASS_COLORS is honored first")
    _G.CUSTOM_CLASS_COLORS = nil
    ck(Names.ClassHex("WARRIOR") == "c79c6e", "phase 7: RAID_CLASS_COLORS fallback returns")

    -- ── Phase 8: the CVar fight, both ways, bounded. ─────────────────────────
    local sets8 = Sim.CallCount("SetCVar")
    _G.SetCVar("chatClassColorOverride", "1")   -- something flips the kill switch
    ck(_G.GetCVar("chatClassColorOverride") == "0",
        "phase 8 RED CONTROL: an external flip to 1 is re-asserted back to 0")
    ck(Sim.CallCount("SetCVar") == sets8 + 2,
        "phase 8: exactly one re-assert (external + ours = 2 writes, no echo storm)")

    -- ── Phase 9: disable hands the CVar back; re-enable re-holds it. ─────────
    ns.SetModuleEnabled("names", false)
    ck(_G.GetCVar("chatClassColorOverride") == "1",
        "phase 9: disable restored the value found at enable")
    ck(ns.EventHandlerCount("CHAT_MSG_SAY") == 0,
        "phase 9: every chat-event subscription was handed back (inertness)")
    ns.SetModuleEnabled("names", true)
    ck(_G.GetCVar("chatClassColorOverride") == "0", "phase 9: re-enable re-holds the CVar")

    -- ── Phase 10: persistence is OPT-IN, realm-scoped, and survives a world
    -- exit that wipes the session cache. ─────────────────────────────────────
    Names.NoteSighting("Fleet", "MAGE")
    ck((ns.chardb.names.realms["TestRealm"] or {}).fleet == nil,
        "phase 10: persist OFF (default) writes nothing to chardb")
    ns.db.names.persist = true
    Names.NoteSighting("Mimi", "MAGE")
    ck(ns.chardb.names.realms["TestRealm"].mimi == "MAGE",
        "phase 10: persist ON stores realm-scoped in the per-character store")
    Sim.DispatchEvent("PLAYER_LEAVING_WORLD")
    ck(Names.CacheGet("fleet") == nil, "phase 10: world exit wiped the session-only sighting")
    ck(Names.CacheGet("mimi") == "MAGE", "phase 10: the persisted sighting survived the wipe")
    ns.db.names.persist = false

    -- Tidy for the suites that run after us (the wave convention).
    Sim.ResetCalls()
end

ns:RegisterSelfTest("names", function(verbose)
    local fails = {}
    local ok, err = pcall(testNames, fails)
    if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL names :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS names") end
    return #fails == 0
end)

return Names
