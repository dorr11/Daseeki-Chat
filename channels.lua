-- Daseeki Chat — channels.lua  (Wave 2, reconciler/sync agent — REAL)
--
-- Channel membership + DETERMINISTIC NUMBERING + color re-imposition BY NAME.
-- Everything here is built on the server-state facts the survey proved
-- (game-facts register §7.3) and the sim makes unkind:
--
--   * Joins/leaves are ASYNC server ops completing ~0.5s later via
--     CHAT_MSG_CHANNEL_NOTICE; ops issued <0.5s apart are DROPPED SILENTLY.
--     Every op here is paced >= OP_PACING apart — the pacing is PROVEN by the
--     suite (zero dropped ops across a full converge), not assumed.
--   * The notice fires BEFORE GetChannelList reflects the change — no
--     conclusion is ever drawn from the list inside a notice handler; verify
--     reads happen a LAND_WAIT after the last op.
--   * The list is DARK until ~0.5s after PLAYER_ENTERING_WORLD (Class 6): the
--     WARMTH gate below is the one door every list read goes through. Dark is
--     UNKNOWN, never "no channels".
--   * Numbers are join-order state: leaves leave HOLES, joins fill the LOWEST
--     hole. Deterministic numbering is engineered the Prat-proven way:
--     throwaway placeholder channels pin the low holes so a real join lands on
--     its target number, then the placeholders are left (paced); permutations
--     among already-joined channels use C_ChatInfo.SwapChatChannelsByChannelIndex.
--   * The client keys channel COLORS by NUMBER (CHANNELn); config keys them by
--     NAME. Colors are re-imposed on every YOU_JOINED/YOU_CHANGED notice and
--     after every swap this file performs — permanently (reconciler rule 6).
--   * A join the server never grants REFUSES onto the ladder: converge rounds
--     are bounded, the refusal is reported to the caller (the reconciler
--     traces it), and nothing ever spins.
--
-- ChatFrame_AddChannel does NOT exist on 11509 — window routing lives in
-- reconcile.lua via AddChatWindowChannel (runtime-detected there). This file
-- owns MEMBERSHIP only.
--
-- INERTNESS: everything is installed in OnEnable (one event registration, one
-- bus listener) and given back in OnDisable; in-flight converges and warm
-- polls are token-cancelled. Disabled = the client sees nothing from us.

local ADDON, ns = ...

local Channels = {
    active         = false,
    stats          = { converges = 0, rounds = 0, ops = 0, refused = 0 },
    _listWarm      = false,
    _warmByTimeout = false,
    _warmToken     = 0,
    _convToken     = 0,
    _converge      = nil,
    _selfOps       = {},          -- nameLower -> pending own-op count (echo discipline)
    _lastOpUptime  = -math.huge,  -- pacing anchor, uptime clock
}
ns.Channels = Channels

----------------------------------------------------------------------
-- Constants. OP_PACING clears the 0.5s server throttle with margin (the Prat
-- recipe's "0.5s + error count" is echoed in the round backoff below).
----------------------------------------------------------------------

local OP_PACING  = 0.6    -- seconds between any two channel server ops
local LAND_WAIT  = 0.7    -- join round-trip (~0.5s) + the state beat after the notice
local WARM_POLL  = 0.5    -- list warmth probe interval
local WARM_TRIES = 6      -- bounded ceiling (3s): a channel-less character warms by timeout
local MAX_ROUNDS = 4      -- membership re-plan rounds per converge
local PIN_PREFIX = "DaseekiPin"   -- throwaway number-pinning channels

Channels.PIN_PREFIX = PIN_PREFIX

----------------------------------------------------------------------
-- Small helpers.
----------------------------------------------------------------------

local function after(delay, fn)
    local T = _G.C_Timer
    if T and type(T.After) == "function" then
        T.After(delay, fn)
    elseif ns.RouteError then
        ns.RouteError("channels: C_Timer absent; scheduled op dropped")
    end
end

local function uptime()
    local f = _G.GetTime
    if type(f) == "function" then
        local ok, t = pcall(f)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

local function isPin(name)
    return type(name) == "string" and name:sub(1, #PIN_PREFIX) == PIN_PREFIX
end
Channels.IsPin = isPin

-- All hook/timer bodies route through this so the reconciler's capture-back
-- never captures our own actions (echo discipline, reconciler rule 3).
function Channels.SelfWrite(fn)
    local R = ns.Reconcile
    if R and R.SelfWrite then return R.SelfWrite(fn) end
    local ok, err = pcall(fn)
    if not ok and ns.RouteError then ns.RouteError(err) end
    return ok
end

----------------------------------------------------------------------
-- The ONE list reader. Returns byNum (number -> name) or nil when the list
-- answers nothing — dark or genuinely empty; only the warmth gate may decide
-- which. Parses pairs OR triples defensively (the flat shape drifts across
-- client generations; the register documents triples on era).
----------------------------------------------------------------------

local function listRead()
    local f = _G.GetChannelList
    if type(f) ~= "function" then return nil end
    local ok, res = pcall(function() return { f() } end)
    if not ok or type(res) ~= "table" or #res == 0 then return nil end
    local byNum = {}
    local i, count = 1, 0
    while i <= #res do
        local n = res[i]
        if type(n) == "number" and type(res[i + 1]) == "string" then
            byNum[n] = res[i + 1]
            count = count + 1
            i = i + 2
            if type(res[i]) == "boolean" then i = i + 1 end   -- optional third slot
        else
            i = i + 1
        end
    end
    if count == 0 then return nil end
    return byNum
end
Channels.ListRead = listRead

----------------------------------------------------------------------
-- WARMTH (Class 6 made mechanical). The list is dark for ~0.5s after
-- PLAYER_ENTERING_WORLD; nothing in this addon draws a conclusion from it
-- until this gate opens. Event-gated on ENTERING_WORLD, then a bounded
-- verify loop — never a lone timer guess: warmth is declared when the list
-- ANSWERS, and only the ceiling (a character genuinely in zero channels is
-- indistinguishable from dark) declares it by timeout, honestly flagged.
----------------------------------------------------------------------

function Channels.IsListWarm() return Channels._listWarm end

function Channels.BeginWarmPoll()
    Channels._listWarm = false
    Channels._warmByTimeout = false
    Channels._warmToken = Channels._warmToken + 1
    local token = Channels._warmToken
    local tries = 0
    local function poll()
        if token ~= Channels._warmToken or not Channels.active then return end
        tries = tries + 1
        if listRead() then
            Channels._listWarm = true
        elseif tries >= WARM_TRIES then
            Channels._listWarm = true
            Channels._warmByTimeout = true
        else
            after(WARM_POLL, poll)
            return
        end
        if ns.Fire then ns:Fire("CHANNEL_LIST_WARM", Channels._warmByTimeout) end
    end
    after(WARM_POLL, poll)
end

-- The join list as config stores it: { { number, name }, ... } sorted by
-- number. nil while dark (UNKNOWN — Class 6), and nil when warmth came only
-- by timeout with nothing readable (an unreadable list is not an empty one).
-- Our own pins are scaffolding and never captured.
function Channels.CaptureJoinList()
    if not Channels._listWarm then return nil end
    local byNum = listRead()
    if not byNum then
        if Channels._warmByTimeout then return nil end
        return {}
    end
    local nums = {}
    for n in pairs(byNum) do nums[#nums + 1] = n end
    table.sort(nums)
    local out = {}
    for _, n in ipairs(nums) do
        if not isPin(byNum[n]) then
            out[#out + 1] = { n, byNum[n] }
        end
    end
    return out
end

----------------------------------------------------------------------
-- COLOR RE-IMPOSITION BY NAME. The effective config (cross-account winner)
-- is the authority; the write is diff-gated (no UPDATE_CHAT_COLOR spam) and
-- SELF-MARKED so capture-back never sees our own re-assertion.
----------------------------------------------------------------------

local function configColors()
    local C = ns.Config
    if not (C and C.EffectiveCfg) then return nil end
    local cfg = C.EffectiveCfg()
    return cfg and cfg.colors or nil
end

function Channels.ImposeColor(num, name)
    num = tonumber(num)
    if not num or num <= 0 or type(name) ~= "string" or name == "" then return end
    if isPin(name) then return end
    local colors = configColors()
    local want = colors and colors[name:lower()]
    if type(want) ~= "table" then return end
    local CTI = _G.ChatTypeInfo
    local info = type(CTI) == "table" and CTI["CHANNEL" .. num] or nil
    local C = ns.Config
    if info and C and C.NearColor and C.NearColor(info, want) then return end
    local cc = _G.ChangeChatColor
    if type(cc) ~= "function" then return end
    Channels.SelfWrite(function()
        cc("CHANNEL" .. num, tonumber(want.r) or 1, tonumber(want.g) or 1, tonumber(want.b) or 1)
    end)
end

function Channels.ImposeAllColors()
    if not Channels._listWarm then return end
    local byNum = listRead()
    if not byNum then return end
    for n = 1, (_G.MAX_WOW_CHAT_CHANNELS or 20) do   -- sorted walk (Class 8 hygiene)
        if byNum[n] then Channels.ImposeColor(n, byNum[n]) end
    end
end

----------------------------------------------------------------------
-- CHANNEL ALIASES ON THE CHAT LINE (the owner's Prat ask: "custom channel
-- names"). The client writes a channel's header as the DISPLAY TEXT of a
-- hyperlink — |Hchannel:channel:2|h[2. Trade - City]|h — so renaming it is a
-- display edit over a live link, which is the single most dangerous shape in
-- this whole addon (the Prat coupling bug's home ground).
--
-- WHICH IS WHY IT IS A LINK DECORATOR, not a text substitution: decor.lua's
-- link-decorator class parses the link STRUCTURALLY, hands a decorator the
-- display text ONLY, and rebuilds the link from the original type and payload
-- itself. The payload is therefore untouchable BY CONSTRUCTION rather than by
-- our care, and a return carrying link markup is rejected wholesale by the
-- engine. Nothing here can corrupt a channel link even if it tries.
--
-- The lookup is BY NAME, case-folded (config.lua owns the seam). The number in
-- the header is display, never identity — it moves between characters and
-- sessions, which is the entire reason channels.lua exists.
----------------------------------------------------------------------

function Channels.AliasLinkDecorator(linkType, payload, display)
    if linkType ~= "channel" then return nil end          -- every other link: untouched
    local C = ns.Config
    if not (C and C.ParseChannelDisplay and C.AliasLabel) then return nil end
    local num, name = C.ParseChannelDisplay(display)
    if not name then return nil end                        -- unusual shape: never guess
    local label = C.AliasLabel(num, name)
    if not label then return nil end                       -- unaliased: render native
    return "[" .. label .. "]"
end

-- Channel names the alias editor can offer: everything the LIVE list knows,
-- unioned with the configured join list and with any name that already carries
-- an alias (so a channel you are not in right now never vanishes from its own
-- setting). Sorted, de-duplicated by folded name; our own pins never appear.
function Channels.KnownChannelNames()
    local seen, out = {}, {}
    local function add(name)
        if type(name) ~= "string" or name == "" or isPin(name) then return end
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = name
    end
    local byNum = listRead()
    if byNum then
        local nums = {}
        for n in pairs(byNum) do nums[#nums + 1] = n end
        table.sort(nums)
        for _, n in ipairs(nums) do add(byNum[n]) end
    end
    local C = ns.Config
    if C and C.EffectiveCfg then
        local ok, eff = pcall(C.EffectiveCfg)
        if ok and type(eff) == "table" and type(eff.join) == "table" then
            for _, pair in ipairs(eff.join) do
                if type(pair) == "table" then add(pair[2]) end
            end
        end
    end
    if C and C.AliasList then
        for _, a in ipairs(C.AliasList()) do add(a.key) end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-- The channel number the client currently has for a name (nil = not joined).
function Channels.NumberOf(name)
    if type(name) ~= "string" or name == "" then return nil end
    local f = _G.GetChannelName
    if type(f) ~= "function" then return nil end
    local ok, num = pcall(f, name)
    if not ok then return nil end
    num = tonumber(num)
    if not num or num <= 0 then return nil end
    return num
end

----------------------------------------------------------------------
-- The notice handler: the ONE standing client subscription. On every join /
-- renumber the color is re-imposed by name (rule 6, permanently). A notice we
-- did not cause is a PLAYER edit — the reconciler is told so capture-back can
-- fold it into the config. The list is NOT read here (event-before-state).
----------------------------------------------------------------------

local function onChannelNotice(event, kind, _, _, _, _, _, _, num, name)
    if not Channels.active then return end
    if type(name) ~= "string" or name == "" then return end
    local low = name:lower()
    local selfOp = (Channels._selfOps[low] or 0) > 0
    if selfOp then
        Channels._selfOps[low] = Channels._selfOps[low] - 1
        if Channels._selfOps[low] <= 0 then Channels._selfOps[low] = nil end
    end
    if kind == "YOU_JOINED" or kind == "YOU_CHANGED" then
        Channels.ImposeColor(num, name)
    end
    if not selfOp and not isPin(name) then
        local R = ns.Reconcile
        if R and R.NoteExternalChange then
            R.NoteExternalChange("channel " .. tostring(kind) .. " " .. name)
        end
    end
end

----------------------------------------------------------------------
-- CONVERGE: drive membership + numbering to the desired join list.
--   desired: array of { number, name } (config.join). Healed + sorted here.
--   onDone(result): result = { ok, refused = {names}, rounds, ops }.
--
-- Round shape (plan-from-snapshot, execute paced, verify, re-plan — the
-- staged retrying loop the survey proved):
--   round:   leaves of undesired channels; joins with pin padding so each
--            lands on its target (or anywhere, to be swapped); all ops paced.
--   verify:  a LAND_WAIT after the last op (notice-before-state), re-read,
--            missing names -> next round with OP_PACING + errorCount backoff,
--            bounded by MAX_ROUNDS; still missing -> REFUSED.
--   swaps:   fix permutations in place (SwapChatChannelsByChannelIndex is a
--            local reorder — no server round-trip, no pacing) with color
--            re-imposition for both numbers touched.
--   cleanup: leave the pins (paced; leaves make holes, holes are the goal),
--            then impose all colors and report.
----------------------------------------------------------------------

local function maxChannels() return _G.MAX_WOW_CHAT_CHANNELS or 20 end

local function normalizeDesired(desired)
    local out, seen = {}, {}
    for _, e in ipairs(type(desired) == "table" and desired or {}) do
        if type(e) == "table" then
            local n, name = tonumber(e[1]), e[2]
            if n and n >= 1 and n <= maxChannels()
               and type(name) == "string" and name ~= "" and not isPin(name)
               and not seen[name:lower()] then
                seen[name:lower()] = true
                out[#out + 1] = { n, name }
            end
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local function alive(st)
    return Channels.active and Channels._converge == st and st.token == Channels._convToken
end

local function markSelf(name)
    local low = name:lower()
    Channels._selfOps[low] = (Channels._selfOps[low] or 0) + 1
end

local function issueJoin(name, temporary)
    markSelf(name)
    local fn = temporary and (_G.JoinTemporaryChannel or _G.JoinChannelByName)
                          or _G.JoinChannelByName
    if type(fn) == "function" then
        Channels.SelfWrite(function() fn(name) end)
    end
end

local function issueLeave(name)
    markSelf(name)
    local fn = _G.LeaveChannelByName
    if type(fn) == "function" then
        Channels.SelfWrite(function() fn(name) end)
    end
end

-- Execute ops one per OP_PACING, respecting the module-wide pacing anchor so
-- two back-to-back converges (or a converge after a warm-up op) never squeeze
-- under the server throttle.
local function runOps(st, ops, done)
    if #ops == 0 then done() return end
    local i = 0
    local function step()
        if not alive(st) then return end
        i = i + 1
        local op = ops[i]
        if not op then done() return end
        op()
        st.ops = st.ops + 1
        Channels.stats.ops = Channels.stats.ops + 1
        Channels._lastOpUptime = uptime()
        after(OP_PACING, step)
    end
    local since = uptime() - Channels._lastOpUptime
    if since < OP_PACING then
        after(OP_PACING - since, step)
    else
        step()
    end
end

local roundStep, verifyMembership, swapPhase, cleanupPins, finish

roundStep = function(st)
    if not alive(st) then return end
    st.round = st.round + 1
    Channels.stats.rounds = Channels.stats.rounds + 1
    local byNum = listRead() or {}
    local byName = {}
    for n, name in pairs(byNum) do byName[name:lower()] = n end

    local wantNames = {}
    for _, e in ipairs(st.desired) do wantNames[e[2]:lower()] = e[1] end

    local ops = {}
    -- Predicted occupancy this round: current, minus the leaves we will issue.
    local predicted = {}
    for n, name in pairs(byNum) do predicted[n] = name end

    -- (1) Leaves: joined channels the config does not want. Pins stay until
    -- cleanup (they are holding numbers open on purpose).
    local leaveNums = {}
    for n in pairs(byNum) do leaveNums[#leaveNums + 1] = n end
    table.sort(leaveNums)                       -- deterministic op order (Class 8)
    for _, n in ipairs(leaveNums) do
        local name = byNum[n]
        if not wantNames[name:lower()] and not isPin(name) then
            ops[#ops + 1] = function() issueLeave(name) end
            predicted[n] = nil
        end
    end

    -- (2) Joins, targets ascending, pin-padding the lower holes so the real
    -- join lands on its target number (joins fill the LOWEST hole — the fact
    -- the whole recipe stands on).
    local function lowestFree()
        for n = 1, maxChannels() do
            if predicted[n] == nil then return n end
        end
        return nil
    end
    for _, e in ipairs(st.desired) do
        local target, name = e[1], e[2]
        if not byName[name:lower()] then
            local guard = 0
            while guard <= maxChannels() do
                guard = guard + 1
                local free = lowestFree()
                if not free then break end                       -- world is full: refuse via verify
                if free == target then
                    ops[#ops + 1] = function() issueJoin(name, false) end
                    predicted[free] = name
                    break
                elseif free < target then
                    local pin = PIN_PREFIX .. free
                    ops[#ops + 1] = function() issueJoin(pin, true) end
                    predicted[free] = pin
                    st.pins[pin] = true
                else
                    -- target is occupied (a permutation to fix later): land
                    -- membership anywhere and let the swap phase renumber.
                    ops[#ops + 1] = function() issueJoin(name, false) end
                    predicted[free] = name
                    break
                end
            end
        end
    end

    runOps(st, ops, function()
        after(LAND_WAIT, function() verifyMembership(st) end)
    end)
end

verifyMembership = function(st)
    if not alive(st) then return end
    local byNum = listRead() or {}
    local byName = {}
    for n, name in pairs(byNum) do byName[name:lower()] = n end
    local missing = {}
    for _, e in ipairs(st.desired) do
        if not byName[e[2]:lower()] then missing[#missing + 1] = e[2] end
    end
    if #missing > 0 and st.round < MAX_ROUNDS then
        st.errors = st.errors + 1
        -- The Prat backoff: base pacing + the error count, re-planned from a
        -- fresh snapshot. Bounded by MAX_ROUNDS — refusal, never a spin.
        after(OP_PACING + st.errors, function() roundStep(st) end)
        return
    end
    for _, name in ipairs(missing) do st.refused[#st.refused + 1] = name end
    swapPhase(st, byNum, byName)
end

swapPhase = function(st, byNum, byName)
    if not alive(st) then return end
    local CI = _G.C_ChatInfo
    local swap = CI and CI.SwapChatChannelsByChannelIndex
    if type(swap) == "function" then
        for _, e in ipairs(st.desired) do
            local target, name = e[1], e[2]
            local cur = byName[name:lower()]
            if cur and cur ~= target then
                Channels.SelfWrite(function() swap(cur, target) end)
                local displaced = byNum[target]
                byNum[target], byNum[cur] = name, displaced
                byName[name:lower()] = target
                if displaced then byName[displaced:lower()] = cur end
                -- Colors key by NUMBER: both touched numbers get their names'
                -- colors re-imposed immediately (swaps fire no notice).
                Channels.ImposeColor(target, name)
                if displaced then Channels.ImposeColor(cur, displaced) end
            end
        end
    end
    cleanupPins(st)
end

cleanupPins = function(st)
    if not alive(st) then return end
    local byNum = listRead() or {}
    local ops = {}
    local nums = {}
    for n in pairs(byNum) do nums[#nums + 1] = n end
    table.sort(nums)
    for _, n in ipairs(nums) do
        if isPin(byNum[n]) then
            local name = byNum[n]
            ops[#ops + 1] = function() issueLeave(name) end
        end
    end
    runOps(st, ops, function()
        if #ops > 0 then
            after(LAND_WAIT, function() finish(st) end)
        else
            finish(st)
        end
    end)
end

finish = function(st)
    if not alive(st) then return end
    Channels.ImposeAllColors()
    -- Refused/dropped self-marks must never leak onto a later PLAYER op.
    Channels._selfOps = {}
    Channels._converge = nil
    if #st.refused > 0 then
        Channels.stats.refused = Channels.stats.refused + #st.refused
    end
    local result = { ok = #st.refused == 0, refused = st.refused,
                     rounds = st.round, ops = st.ops }
    if st.onDone then
        local ok, err = pcall(st.onDone, result)
        if not ok and ns.RouteError then ns.RouteError(err) end
    end
    if st.rerun then
        local r = st.rerun
        st.rerun = nil
        Channels.Converge(r.desired, r.onDone)
    end
end

function Channels.Converge(desired, onDone)
    if not Channels.active or not Channels._listWarm then
        if onDone then
            local ok, err = pcall(onDone, { ok = false, refused = {},
                rounds = 0, ops = 0, note = "channels inactive or list dark" })
            if not ok and ns.RouteError then ns.RouteError(err) end
        end
        return false
    end
    local normal = normalizeDesired(desired)
    if Channels._converge then
        Channels._converge.rerun = { desired = normal, onDone = onDone }
        return true
    end
    Channels._convToken = Channels._convToken + 1
    local st = {
        token = Channels._convToken,
        desired = normal,
        onDone = onDone,
        round = 0, errors = 0, ops = 0,
        refused = {}, pins = {},
    }
    Channels._converge = st
    Channels.stats.converges = Channels.stats.converges + 1
    roundStep(st)
    return true
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function Channels.OnEnable()
    Channels.active = true
    Channels._noticeHandler = Channels._noticeHandler or function(event, ...)
        onChannelNotice(event, ...)
    end
    ns:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", Channels._noticeHandler)
    Channels._ewListener = Channels._ewListener or function()
        if Channels.active then Channels.BeginWarmPoll() end
    end
    ns:On("ENTERING_WORLD", Channels._ewListener)
    -- The alias decorator rides decor.lua's certified link path. Registered
    -- here and given back in OnDisable, exactly like names.lua's own link
    -- decorator: with this module inert, channels render the client's text.
    local D = ns.Decor
    if D and D.RegisterLinkDecorator then
        D.RegisterLinkDecorator("chanalias", 20, Channels.AliasLinkDecorator)
    end
    -- Enabled after world-enter (login order / a live /dchat enable): warm now.
    if ns.state.inWorld then Channels.BeginWarmPoll() end
end

function Channels.OnDisable()
    Channels.active = false
    if Channels._noticeHandler then
        ns:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE", Channels._noticeHandler)
    end
    if Channels._ewListener then
        ns:Off("ENTERING_WORLD", Channels._ewListener)
    end
    local D = ns.Decor
    if D and D.UnregisterLinkDecorator then D.UnregisterLinkDecorator("chanalias") end
    Channels._warmToken = Channels._warmToken + 1   -- cancels any in-flight poll
    Channels._convToken = Channels._convToken + 1   -- orphans any in-flight converge
    Channels._converge = nil
    Channels._listWarm = false
    Channels._selfOps = {}
end

ns.RegisterModule("channels", Channels)

ns.RegisterDebugCommand("channels", "channel state: warmth, list, converge stats", function()
    ns:Print(("channels: %s, list %s%s"):format(
        Channels.active and "active" or "inactive",
        Channels._listWarm and "WARM" or "dark",
        Channels._warmByTimeout and " (by timeout)" or ""))
    local join = Channels.CaptureJoinList()
    if join then
        for _, e in ipairs(join) do
            ns:Print(("  %d. %s"):format(e[1], e[2]))
        end
    else
        ns:Print("  (list unknown)")
    end
    ns:Print(("  stats: %d converge(s), %d round(s), %d op(s), %d refusal(s)")
        :format(Channels.stats.converges, Channels.stats.rounds,
                Channels.stats.ops, Channels.stats.refused))
end)

----------------------------------------------------------------------
-- Self-tests (suite "channels"). Live legs drive the module against the
-- unkind sim; skipped in-game.
----------------------------------------------------------------------

local function currentNumberOf(name)
    local byNum = listRead() or {}
    for n, nm in pairs(byNum) do
        if nm == name then return n end
    end
    return nil
end

local function testWarmthAndCapture(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer

    ns.SetModuleEnabled("channels", true)
    ck(Channels.active, "module enables")
    ck(ns.EventHandlerCount("CHAT_MSG_CHANNEL_NOTICE") == 1,
        "exactly one notice subscription while enabled")

    Sim.NewSession()
    Sim.EnterWorld(false, false)
    -- Class 6, the trap itself: at PEW+0 the list is DARK and warmth is shut.
    ck(Channels.IsListWarm() == false, "list is not warm at PEW+0")
    ck(Channels.CaptureJoinList() == nil, "a dark list captures as UNKNOWN (nil)")
    -- The first poll and the sim's populate tie at +0.5 and the poll can lose
    -- the coin flip (Class 2's ordering reality); the NEXT poll settles it.
    HT.advance(1.0)
    ck(Channels.IsListWarm() == true, "warmth opens when the list answers")
    ck(Channels._warmByTimeout == false, "warmth came from an ANSWER, not the ceiling")
    local join = Channels.CaptureJoinList()
    ck(type(join) == "table" and #join == 1 and join[1][1] == 1 and join[1][2] == "General",
        "the warm capture reads the zone channel at its number")
end

local function testConvergeAndPacing(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer

    -- Fresh warm world (1.0s: the poll can lose the +0.5 ordering coin flip).
    Sim.NewSession()
    Sim.EnterWorld(false, false)
    HT.advance(1.0)
    ck(Channels.IsListWarm(), "warm before converge")

    -- PACING PROVEN: a full three-channel converge with ZERO dropped ops.
    local drops0 = Sim.droppedJoins
    local result
    Channels.Converge({ { 1, "General" }, { 2, "Alpha" }, { 3, "Beta" } },
        function(res) result = res end)
    HT.flush()
    ck(result ~= nil and result.ok, "converge completes and reports ok")
    ck(Sim.droppedJoins == drops0,
        "ZERO ops were dropped (pacing proven, not assumed)")
    ck(currentNumberOf("General") == 1 and currentNumberOf("Alpha") == 2
        and currentNumberOf("Beta") == 3, "all channels landed on their numbers")

    -- DETERMINISTIC NUMBERING FROM A SHUFFLED START: same membership, permuted
    -- numbers -> the swap primitive fixes it without a single server op drop.
    Channels.Converge({ { 1, "General" }, { 2, "Beta" }, { 3, "Alpha" } },
        function(res) result = res end)
    HT.flush()
    ck(result.ok, "permutation converge completes")
    ck(currentNumberOf("Beta") == 2 and currentNumberOf("Alpha") == 3,
        "a shuffled start converges to the configured numbering")
    ck(Sim.droppedJoins == drops0, "still zero dropped ops")

    -- PLACEHOLDER PINNING: a target with holes below it. Fresh world, desired
    -- Trade at 4 -> pins occupy 2 and 3, Trade lands on 4, pins are left.
    Sim.NewSession()
    Sim.EnterWorld(false, false)
    HT.advance(1.0)
    drops0 = Sim.droppedJoins
    Channels.Converge({ { 1, "General" }, { 4, "Trade" } },
        function(res) result = res end)
    HT.flush()
    ck(result.ok, "pinned converge completes")
    ck(currentNumberOf("Trade") == 4, "the pinned join landed on its exact number")
    local finalJoin = Channels.CaptureJoinList()
    local pinSeen = false
    for _, e in ipairs(finalJoin or {}) do
        if Channels.IsPin(e[2]) then pinSeen = true end
    end
    ck(not pinSeen, "every placeholder pin was left afterwards")
    ck(#finalJoin == 2, "final membership is exactly the desired set")
    ck(Sim.droppedJoins == drops0, "pinning stayed inside the pacing envelope")
end

local function testColorsAndRefusal(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    if not Sim then return end
    local HT = _G.__DaseekiChatHarnessTimer
    local Config = ns.Config

    -- COLOR SURVIVES RENUMBER. Configure a color by NAME, renumber the channel
    -- via a player-style leave/rejoin (holes + lowest-hole refill), and the
    -- standing notice handler re-imposes it at the NEW number.
    Sim.NewSession()
    Sim.EnterWorld(false, false)
    HT.advance(1.0)
    local c = Config.Get()
    c.rev, c.at = 5, Config.Now()
    c.colors = { trade = { r = 0.5, g = 0.25, b = 0.75 } }
    c.join = {}

    local result
    Channels.Converge({ { 1, "General" }, { 2, "Trade" }, { 3, "Filler" } },
        function(res) result = res end)
    HT.flush()
    ck(result.ok, "setup converge completes")
    local CTI = _G.ChatTypeInfo
    ck(Config.NearColor(CTI["CHANNEL2"], c.colors.trade),
        "the configured color is imposed at Trade's number after converge")

    -- Renumber: leave Filler (hole at 3), leave Trade (hole at 2), rejoin
    -- Trade -> it lands at 2's hole... so drop General too for a real shift:
    -- leave General (hole at 1), rejoin Trade -> lands at 1. All ops paced.
    HT.advance(OP_PACING)
    _G.LeaveChannelByName("Trade")
    HT.advance(OP_PACING)
    _G.LeaveChannelByName("General")
    HT.advance(OP_PACING)
    _G.JoinChannelByName("Trade")
    HT.flush()
    local newNum = currentNumberOf("Trade")
    ck(newNum == 1, "the rejoin filled the lowest hole (renumbered)")
    ck(Config.NearColor(CTI["CHANNEL" .. newNum], c.colors.trade),
        "the color FOLLOWED THE NAME to the new number (notice-driven re-imposition)")

    -- The re-imposition was self-marked: config rev untouched by our own
    -- ChangeChatColor (echo discipline holds even with reconcile inert).
    ck(Config.Rev() == 5, "color re-imposition never bumped the config rev")

    -- REFUSAL PATH: a channel the server never grants refuses in bounded
    -- rounds — no spin, no drop-storm, the refusal is REPORTED.
    Sim.NewSession()
    Sim.EnterWorld(false, false)
    HT.advance(1.0)
    Sim.opts.refuseJoins = { Ghost = true }
    local drops0 = Sim.droppedJoins
    local opsBefore = Channels.stats.ops
    Channels.Converge({ { 1, "General" }, { 2, "Ghost" } },
        function(res) result = res end)
    HT.flush()   -- an unbounded retry loop would hang this flush; it returns
    ck(result ~= nil, "the refused converge still completes (bounded rounds)")
    ck(result.ok == false, "the result is honestly not-ok")
    local named = false
    for _, r in ipairs(result.refused) do if r == "Ghost" then named = true end end
    ck(named, "the refusal names the channel")
    ck(result.rounds <= MAX_ROUNDS, "rounds respected the bound")
    ck(currentNumberOf("Ghost") == nil, "the refused channel is not in the list")
    ck(Sim.droppedJoins == drops0, "pacing held even through the retry rounds")
    ck(Channels.stats.ops > opsBefore, "the retries really issued ops")
    Sim.opts.refuseJoins = {}

    -- Inertness on the way out: disable = zero standing subscriptions.
    ns.SetModuleEnabled("channels", false)
    ck(Channels.active == false, "module disables")
    ck(ns.EventHandlerCount("CHAT_MSG_CHANNEL_NOTICE") == 0,
        "the notice subscription was given back (inert when disabled)")
    ck(Channels.IsListWarm() == false, "warmth resets on disable (no stale gate)")
    HT.flush()
    Sim.ResetCalls()
end

-- CHANNEL ALIASES on the chat line. The decorator is exercised through the
-- REAL engine (Decor.Process — decorators run there whether or not the seam is
-- installed), so every claim below is the shipping path, not a shim. The pins
-- extend decor.lua's own protect/reject pins onto this decorator specifically:
-- the payload must be byte-identical across a display rename, and a decorator
-- that tries to emit link markup must be refused by the engine.
local function testAliasDecorator(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Decor, C = ns.Decor, ns.Config
    if not (Decor and C) then ck(false, "decor/config missing") return end

    local cfg = C.Get()
    local savedAliases, savedKeep = cfg.aliases, cfg.aliasKeepNumber
    local savedRev, savedAt = cfg.rev, cfg.at
    cfg.aliases, cfg.aliasKeepNumber = {}, false
    cfg.rev, cfg.at = 1, C.Now()

    local wasActive = Channels.active
    ns.SetModuleEnabled("channels", true)

    local TRADE = "|Hchannel:channel:2|h[2. Trade - City]|h"
    local ITEM  = "|cffa335ee|Hitem:19019|h[Thunderfury, Blessed Blade]|h|r"
    local PLAYER = "|Hplayer:Puu-Whitemane:101|h[Puu]|h"
    local line = TRADE .. " " .. PLAYER .. ": look " .. ITEM .. " www.example.com"

    -- ── Unaliased: the client's own bytes, untouched ─────────────────────────
    ck(Decor.Process(line) == line,
        "an UNALIASED channel renders the client's line byte-identical")

    -- ── Aliased: display swapped, payload byte-identical ─────────────────────
    C.SetAlias("Trade - City", "Trade")
    local out = Decor.Process(line)
    ck(out:find("|Hchannel:channel:2|h[Trade]|h", 1, true) ~= nil,
        "the channel header displays the ALIAS (got: " .. tostring(out:match("|Hchannel:.-|h.-|h")) .. ")")
    ck(out:find("|Hchannel:channel:2|h", 1, true) ~= nil,
        "THE PAYLOAD IS BYTE-IDENTICAL across the rename (the link still clicks)")
    ck(out:find("[2. Trade - City]", 1, true) == nil, "the client's own header text is gone")
    ck(out:find(ITEM, 1, true) ~= nil, "a NON-CHANNEL link on the same line is untouched")
    ck(out:find(PLAYER, 1, true) ~= nil, "…and so is the player link")
    ck(out:find("www.example.com", 1, true) ~= nil, "…and the body text is not this decorator's business")

    -- ── Case folding, both directions ────────────────────────────────────────
    local upper = "|Hchannel:channel:2|h[2. TRADE - CITY]|h"
    ck(Decor.Process(upper):find("[Trade]", 1, true) ~= nil,
        "the lookup folds case: a SHOUTED channel name still aliases")
    C.SetAlias("world", "W")
    ck(Decor.Process("|Hchannel:channel:5|h[5. World]|h"):find("[W]", 1, true) ~= nil,
        "…and an alias stored under a folded key matches the client's capitalization")

    -- ── The number-keep toggle, both ways ────────────────────────────────────
    C.SetAliasKeepNumber(true)
    ck(Decor.Process(TRADE):find("[2. Trade]", 1, true) ~= nil,
        "keep-number ON renders '[2. Trade]'")
    ck(Decor.Process(TRADE):find("|Hchannel:channel:2|h", 1, true) ~= nil,
        "…with the payload still byte-identical")
    C.SetAliasKeepNumber(false)
    ck(Decor.Process(TRADE):find("[Trade]", 1, true) ~= nil
        and Decor.Process(TRADE):find("[2. Trade]", 1, true) == nil,
        "keep-number OFF renders the clean '[Trade]' again")

    -- ── An unnumbered channel header still aliases by name ───────────────────
    C.SetAlias("Guild", "G")
    ck(Decor.Process("|Hchannel:GUILD|h[Guild]|h"):find("|Hchannel:GUILD|h[G]|h", 1, true) ~= nil,
        "an unnumbered channel header aliases by name (payload untouched)")
    C.SetAlias("Guild", "")

    -- ── THE REJECT PIN, on THIS decorator: the engine refuses markup ─────────
    -- An alias is player-typed text. If someone types link markup into the
    -- alias field, the engine's own reject rule must throw the whole return
    -- away rather than emit it — decor.lua's phase-4 red control, reached
    -- through the alias path instead of a test decorator.
    C.SetAlias("Trade - City", "|Hboom:1|hgotcha|h")
    ck(Decor.Process(TRADE) == TRADE,
        "AN ALIAS CARRYING LINK MARKUP IS REJECTED WHOLESALE (the line is untouched)")
    C.SetAlias("Trade - City", "|TInterface\\Icons\\Foo:16|t")
    ck(Decor.Process(TRADE) == TRADE, "…and a texture escape is refused the same way")
    C.SetAlias("Trade - City", "Trade")

    -- ── Protection still belongs to the engine, not to us ────────────────────
    local hostileDisplay = "|Hchannel:channel:9|h[9. www.evil.com]|h"
    ck(Decor.Process(hostileDisplay) == hostileDisplay,
        "a URL-ish channel display with no alias is left exactly alone")

    -- ── Inertness: disable the module and the aliases stop rendering ─────────
    ns.SetModuleEnabled("channels", false)
    ck(Decor.Process(TRADE) == TRADE,
        "with the module inert the decorator is GONE (client text returns)")
    local _, nl = Decor.DecoratorCount()
    ck(nl == 0 or Decor.Process(TRADE) == TRADE,
        "…because the registration was given back, not merely gated")

    if wasActive then ns.SetModuleEnabled("channels", true) end
    cfg.aliases, cfg.aliasKeepNumber = savedAliases, savedKeep
    cfg.rev, cfg.at = savedRev, savedAt
end

ns:RegisterSelfTest("channels", function(verbose)
    local suites = {
        { name = "warmth gate + capture",       fn = testWarmthAndCapture },
        { name = "converge: pacing + numbering", fn = testConvergeAndPacing },
        { name = "colors by name + refusal",     fn = testColorsAndRefusal },
        { name = "alias link decorator",         fn = testAliasDecorator },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local ok, err = pcall(suite.fn, fails)
        if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
        local passed = #fails == 0
        if not passed then allPass = false end
        if verbose and ns.Print then
            if passed then ns:Print("  PASS channels/" .. suite.name)
            else for _, f in ipairs(fails) do ns:Print("  FAIL channels/" .. suite.name .. " :: " .. f) end end
        end
    end
    return allPass
end)

return Channels
