-- Daseeki Chat — history.lua  (Wave 2: history/badges agent, real)
-- Cross-session chat history, per character, bounded.
--
-- The mechanism, in the game-facts register's terms (spec §7.1/§7.6):
--   * CAPTURE at the delivery seam: every window's AddMessage is wrapped (our
--     own wrapper, gated on History.active) and each line is shadowed into a
--     bounded per-window ring with the FINAL STORED text (read back from the
--     buffer's newest entry after the client stored it — never the raw
--     AddMessage argument, so capture is independent of wrapper install
--     order), its colors, and a GetServerTime() EPOCH stamp per line — the
--     ring buffer's own `timestamp` is GetTime() uptime and dies across
--     sessions (the register's rule).
--   * SNAPSHOT the shadow rings into the per-character store (ns.chardb —
--     DaseekiChatCharDB, never synced) on the LOGOUT bus beat, plus an
--     opportunistic batched write on a timer so a crash loses little. NEVER a
--     SavedVariables write per message (cost discipline).
--   * RESTORE on the ENTERING_WORLD bus beat (fresh login OR reload — the
--     beat's isLogin/isReload args distinguish them from a plain zone-in),
--     deferred one timer beat so same-event client handlers settle (Class 2).
--     Lines backfill via the buffer's public PushFront, RE-STAMPED with
--     current-uptime-equivalent times derived from the stored server-time
--     deltas: ts = nowUptime - (nowServer - storedEpoch). Raw stored uptime
--     stamps from the previous session are bogus (often in the future) — the
--     suite's red control proves it.
--   * HONESTY: restored lines are display artifacts. They never pass through
--     AddMessage or the event pipeline (so decor/stamps cannot re-decorate
--     them — they carry their final text) and each entry is marked
--     daseekiRestored = true; the divider additionally daseekiDivider = true.
--
-- INERTNESS: nothing is touched until OnEnable. The AddMessage wrappers are
-- installed once, on the first enable, and their bodies gate on History.active
-- (the skin.lua hooksecurefunc precedent — a disabled module is behaviorally
-- absent even though the wrapper shell remains). Bus subscriptions are given
-- back in OnDisable.
--
-- All display glyphs ASCII (the tofu law); divider ink is the theme's muted
-- token via Daseeki-Core — zero hardcoded colors.

local ADDON, ns = ...

local History = {
    active          = false,
    hookedFrames    = {},    -- frame -> true (wrapper installed; body gates on active)
    rings           = {},    -- window id -> array of { m, r, g, b, t } oldest -> newest
    dirty           = false, -- rings differ from the stored snapshot
    flushQueued     = false, -- a batched snapshot write is pending on the timer seam
    restoredSession = false, -- double-restore guard; cleared on LOGOUT
    lastRestore     = nil,   -- { reason, verdict, windows, lines, skippedAge }
    stats           = { captured = 0, snapshotWrites = 0, lastWriteReason = nil },
}
ns.History = History

local COMBAT_LOG_ID = 2      -- never captured/restored (combat spam is not chat)
local SNAPSHOT_SECS = 30     -- opportunistic batch cadence (through C_Timer — the
                             -- harness-visible timer seam; never per-message)
local DEFAULT_CAP   = 250    -- lines kept per window
local DEFAULT_AGE_H = 168    -- restore age cutoff, hours (the survey's outer bound)

----------------------------------------------------------------------
-- Config. The account store gets a `history` branch (additive: this file loads
-- before ADDON_LOADED, so core's EnsureDefaults picks the branch up at
-- DB_READY). The per-character store gets an EMPTY `history` table on purpose:
-- the `snapshot` key inside it is unknown to the healer, so a stored snapshot
-- passes through EnsureDefaults untouched — a typed default there would HEAL
-- the snapshot away on every login.
----------------------------------------------------------------------

ns.DEFAULTS.history = {
    cap         = DEFAULT_CAP,
    maxAgeHours = DEFAULT_AGE_H,
    optOut      = {},          -- [windowId] = true -> window excluded entirely
}
ns.CHAR_DEFAULTS.history = {}

local function cfg()
    return (ns.db and ns.db.history) or ns.DEFAULTS.history
end

local function capOf()
    local cap = tonumber(cfg().cap)
    if not cap or cap < 10 then cap = cap and 10 or DEFAULT_CAP end
    if cap > 1000 then cap = 1000 end
    return cap
end

local function maxAgeSecs()
    local h = tonumber(cfg().maxAgeHours)
    if not h or h <= 0 then h = DEFAULT_AGE_H end   -- Class 5: 0 is an answer,
    return h * 3600                                  -- but not a sane cutoff
end

local function optedOut(id)
    local oo = cfg().optOut
    return type(oo) == "table" and oo[id] == true
end

function History.SetWindowOptOut(id, out)
    id = tonumber(id)
    if not id then return end
    local c = ns.db and ns.db.history
    if not c then return end
    if type(c.optOut) ~= "table" then c.optOut = {} end
    if out then c.optOut[id] = true else c.optOut[id] = nil end
end

----------------------------------------------------------------------
-- Pure helpers (the harness tests these directly).
----------------------------------------------------------------------

-- |K...|k protected spans are session-scoped Battle.net tokens: stored raw
-- they render as garbage next session, so they become "???" at capture (the
-- survey-recorded rule; same shape as skin.lua's DefangLine pass — kept
-- surgical here because everything ELSE, hyperlinks and colors included, must
-- survive verbatim for a faithful restore).
function History.SanitizeForStore(text)
    if type(text) ~= "string" then return nil end
    return (text:gsub("|K.-|k", "???"))
end

-- The restamp rule: a restored line's buffer timestamp must be the CURRENT
-- session's uptime equivalent of its true age, derived from the stored
-- server-time delta. Clamped so no restored line ever sits in the future.
function History.RestampFor(nowUptime, nowServer, storedEpoch)
    local ts = nowUptime - (nowServer - storedEpoch)
    if ts > nowUptime then ts = nowUptime end
    return ts
end

local function fmtEpoch(t)
    local d = _G.date
    if type(d) == "function" then
        local ok, s = pcall(d, "%m/%d %H:%M", t)
        if ok and type(s) == "string" then return s end
    end
    return tostring(t)
end

local function unwrap(v)   -- headIndex/maxElements arrive wrapped { value = n }
    return type(v) == "table" and v.value or v
end

----------------------------------------------------------------------
-- Snapshot writes (batched; the ONLY SavedVariables mutations in this file).
----------------------------------------------------------------------

function History.BuildSnapshot()
    local gst = _G.GetServerTime
    local snap = { at = gst and gst() or 0, windows = {} }
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do          -- numeric walk: stable
        if id ~= COMBAT_LOG_ID and not optedOut(id) then
            local ring = History.rings[id]
            if ring and #ring > 0 then
                local lines = {}
                for i = 1, #ring do
                    local e = ring[i]
                    lines[i] = { m = e.m, r = e.r, g = e.g, b = e.b, t = e.t }
                end
                snap.windows[id] = { lines = lines }
            end
        end
    end
    return snap
end

function History.WriteSnapshot(reason)
    local store = ns.chardb and ns.chardb.history
    if type(store) ~= "table" then return false end
    store.snapshot = History.BuildSnapshot()
    History.dirty = false
    History.stats.snapshotWrites = History.stats.snapshotWrites + 1
    History.stats.lastWriteReason = reason
    return true
end

local function scheduleFlush()
    if History.flushQueued then return end
    local CT = _G.C_Timer
    if not (CT and CT.After) then return end
    History.flushQueued = true
    CT.After(SNAPSHOT_SECS, function()
        History.flushQueued = false
        if History.active and History.dirty then
            History.WriteSnapshot("timer")
        end
    end)
end

----------------------------------------------------------------------
-- Capture: the delivery seam. One wrapper per window, installed on first
-- enable, body gated on History.active. Restored lines never come through
-- here (they enter via PushFront), so they are never re-captured as new.
----------------------------------------------------------------------

local function onLine(id, text, r, g, b)
    if not History.active then return end
    if id == COMBAT_LOG_ID or optedOut(id) then return end
    local m = History.SanitizeForStore(text)
    if not m then return end
    local gst = _G.GetServerTime
    local ring = History.rings[id]
    if not ring then ring = {}; History.rings[id] = ring end
    ring[#ring + 1] = {
        m = m,
        r = tonumber(r) or 1, g = tonumber(g) or 1, b = tonumber(b) or 1,
        t = gst and gst() or 0,
    }
    local cap = capOf()
    while #ring > cap do table.remove(ring, 1) end
    History.stats.captured = History.stats.captured + 1
    History.dirty = true
    scheduleFlush()
end

local function installFrameWrapper(id)
    local frame = _G["ChatFrame" .. id]
    if not frame or History.hookedFrames[frame] then return end
    local orig = frame.AddMessage
    if type(orig) ~= "function" then return end
    History.hookedFrames[frame] = true
    frame.AddMessage = function(self, text, r, g, b, ...)
        local r1, r2, r3, r4 = orig(self, text, r, g, b, ...)
        -- Capture from the STORED entry, never the raw argument: sibling
        -- wrappers (decor's seam and its post-adds) can sit on either side of
        -- this one depending on enable order, so the `text` argument is pre-
        -- or post-decoration by install-order accident. The newest buffer
        -- entry AFTER orig() returned is the line as the player sees it — the
        -- final displayed text — which makes capture order-independent by
        -- construction. The argument is only the fallback for a frame whose
        -- buffer cannot be read.
        local storedText, sr, sg, sb = text, r, g, b
        local buf = self.historyBuffer
        if type(buf) == "table" and type(buf.GetEntryAtIndex) == "function" then
            local okE, e = pcall(buf.GetEntryAtIndex, buf, 1)
            if okE and type(e) == "table" and type(e.message) == "string" then
                storedText = e.message
                sr, sg, sb = e.r or r, e.g or g, e.b or b
            end
        end
        onLine(id, storedText, sr, sg, sb)
        return r1, r2, r3, r4
    end
end

----------------------------------------------------------------------
-- Restore. Backfills each window's PUBLIC ring buffer via PushFront:
-- divider first, then the kept lines newest-first, which lands them BEFORE
-- any live content in correct oldest->newest reading order. Bounded by the
-- buffer's real room (PushFront on a full ring evicts the NEWEST end — live
-- lines — so we never push more than fits, reserving one slot for the
-- divider). The shadow ring is re-seeded from the snapshot regardless of
-- display room, so history persists across many sessions until age/cap
-- eviction, not just one hop.
----------------------------------------------------------------------

function History.Restore(reason)
    if History.restoredSession then return false, "already-restored" end
    History.restoredSession = true
    local rep = { reason = reason, windows = 0, lines = 0, skippedAge = 0,
                  verdict = "no-snapshot" }
    History.lastRestore = rep

    local store = ns.chardb and ns.chardb.history
    local snap = type(store) == "table" and store.snapshot or nil
    if type(snap) ~= "table" or type(snap.windows) ~= "table" then
        return false, rep.verdict
    end
    local gt, gst = _G.GetTime, _G.GetServerTime
    if not (gt and gst) then rep.verdict = "no-clock" return false, rep.verdict end
    local nowUp, nowSrv = gt(), gst()
    local ageCut = maxAgeSecs()

    -- Divider ink: the theme's muted token (never hardcoded).
    local UI = _G.DaseekiUI
    local dr, dg, db_ = 0.5, 0.5, 0.5
    if UI and UI.Color then dr, dg, db_ = UI.Color("muted") end
    local dividerText = ("-- session from %s --"):format(fmtEpoch(tonumber(snap.at) or nowSrv))

    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        if id ~= COMBAT_LOG_ID and not optedOut(id) then
            local wsnap = snap.windows[id]
            local frame = _G["ChatFrame" .. id]
            local buf = frame and frame.historyBuffer
            if type(wsnap) == "table" and type(wsnap.lines) == "table"
                and type(buf) == "table" and type(buf.PushFront) == "function" then
                -- Age filter, order preserved (oldest -> newest).
                local kept = {}
                for i = 1, #wsnap.lines do
                    local ln = wsnap.lines[i]
                    if type(ln) == "table" and type(ln.m) == "string"
                        and type(ln.t) == "number" then
                        if (nowSrv - ln.t) <= ageCut then
                            kept[#kept + 1] = ln
                        else
                            rep.skippedAge = rep.skippedAge + 1
                        end
                    end
                end
                if #kept > 0 then
                    -- Re-seed the shadow ring first (original epoch stamps kept),
                    -- live captures already in it appended after.
                    local seeded = {}
                    for i = 1, #kept do
                        local ln = kept[i]
                        seeded[#seeded + 1] = { m = ln.m, r = ln.r or 1,
                            g = ln.g or 1, b = ln.b or 1, t = ln.t }
                    end
                    local ring = History.rings[id]
                    if ring then
                        for i = 1, #ring do seeded[#seeded + 1] = ring[i] end
                    end
                    local cap = capOf()
                    while #seeded > cap do table.remove(seeded, 1) end
                    History.rings[id] = seeded
                    History.dirty = true

                    -- Display backfill, bounded by real room.
                    local maxN = tonumber(unwrap(buf.maxElements)) or 128
                    local have = 0
                    if type(frame.GetNumMessages) == "function" then
                        local okN, gotN = pcall(frame.GetNumMessages, frame)
                        have = (okN and tonumber(gotN)) or 0
                    end
                    local room = maxN - have - 1        -- one slot for the divider
                    if room > 0 then
                        local take = math.min(#kept, room)
                        buf:PushFront({
                            message = dividerText,
                            r = dr, g = dg, b = db_,
                            timestamp = History.RestampFor(nowUp, nowSrv,
                                tonumber(snap.at) or nowSrv),
                            daseekiRestored = true,
                            daseekiDivider  = true,
                        })
                        for i = #kept, #kept - take + 1, -1 do
                            local ln = kept[i]
                            buf:PushFront({
                                message = ln.m,
                                r = ln.r or 1, g = ln.g or 1, b = ln.b or 1,
                                timestamp = History.RestampFor(nowUp, nowSrv, ln.t),
                                daseekiRestored = true,
                                daseekiEpoch    = ln.t,
                            })
                        end
                        rep.windows = rep.windows + 1
                        rep.lines = rep.lines + take
                    end
                end
            end
        end
    end
    if History.dirty then scheduleFlush() end
    rep.verdict = "ok"
    return true, "ok"
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function History.OnEnable()
    History.active = true
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        installFrameWrapper(id)
    end
    History.busWorld = History.busWorld or function(isLogin, isReload)
        if not History.active then return end
        if not (isLogin or isReload) then return end    -- plain zone-in: never restore
        local reason = isReload and "reload" or "login"
        local CT = _G.C_Timer
        if CT and CT.After then
            -- One beat's deferral: same-event client handlers settle first
            -- (Class 2 — the beat itself is already post-PLAYER_ENTERING_WORLD).
            CT.After(0, function()
                if History.active then History.Restore(reason) end
            end)
        else
            History.Restore(reason)
        end
    end
    History.busLogout = History.busLogout or function()
        if not History.active then return end
        History.WriteSnapshot("logout")
        -- The session ends here (logout or reload): drop the in-memory rings —
        -- the next session re-seeds them FROM the snapshot at restore, so
        -- keeping them would double every line if this Lua state survives
        -- (it does under the harness's NewSession approximation; in the real
        -- client the state dies anyway, so this is semantically free).
        History.rings = {}
        History.restoredSession = false     -- the next session may restore
    end
    ns:On("ENTERING_WORLD", History.busWorld)
    ns:On("LOGOUT", History.busLogout)
end

function History.OnDisable()
    History.active = false
    if History.busWorld then ns:Off("ENTERING_WORLD", History.busWorld) end
    if History.busLogout then ns:Off("LOGOUT", History.busLogout) end
end

ns.RegisterModule("history", History)

ns.RegisterDebugCommand("history", "cross-session history: ring stats + last restore verdict", function()
    ns:Print(("history: %s, cap=%d/window, age cutoff=%dh, batch=%ds"):format(
        History.active and "active" or "inactive", capOf(),
        math.floor(maxAgeSecs() / 3600), SNAPSHOT_SECS))
    local shown = 0
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local ring = History.rings[id]
        if (ring and #ring > 0) or optedOut(id) then
            shown = shown + 1
            ns:Print(("  window %d: %d line(s)%s"):format(id, ring and #ring or 0,
                optedOut(id) and " (opted out)" or ""))
        end
    end
    if shown == 0 then ns:Print("  no lines captured yet") end
    ns:Print(("  captured=%d  snapshot writes=%d (last: %s)  dirty=%s"):format(
        History.stats.captured, History.stats.snapshotWrites,
        tostring(History.stats.lastWriteReason), tostring(History.dirty)))
    local lr = History.lastRestore
    if lr then
        ns:Print(("  last restore [%s]: %s -- %d line(s) into %d window(s), %d age-skipped"):format(
            tostring(lr.reason), tostring(lr.verdict),
            lr.lines or 0, lr.windows or 0, lr.skippedAge or 0))
    else
        ns:Print("  last restore: (none this session)")
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "history"). Pure parts always run; the live parts drive
-- the module against the harness's unkind chat simulator (capture ->
-- snapshot -> NewSession -> restore round trip, with the uptime-reset trap as
-- the red control). In-game (no sim) the live parts are skipped, not faked.
----------------------------------------------------------------------

local function testPure(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local S = History.SanitizeForStore
    ck(S("plain text") == "plain text", "pure: plain text stores verbatim")
    ck(S("hi |Kq9|k there") == "hi ??? there", "pure: |K span stored as ??? (session-scoped token)")
    ck(S("|Hitem:19019|h[Thunderfury]|h stays") == "|Hitem:19019|h[Thunderfury]|h stays",
        "pure: hyperlinks survive capture verbatim (faithful restore)")
    ck(S(nil) == nil, "pure: non-string capture is refused, not coerced")

    local R = History.RestampFor
    ck(R(100, 5000, 4700) == -200, "pure: restamp = nowUp - (nowSrv - epoch)")
    ck(R(100, 5000, 4990) == 90, "pure: a 10s-old line restamps 10s back")
    ck(R(100, 5000, 6000) == 100, "pure: a future epoch clamps to now (never in the future)")
end

local function testLive(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local HT  = _G.__DaseekiChatHarnessTimer
    local UI  = _G.DaseekiUI
    if not (Sim and HT and UI) then
        if verbose then ns:Print("  history: live checks skipped (no simulator)") end
        return
    end
    local cf1, cf3, cf4 = _G.ChatFrame1, _G.ChatFrame3, _G.ChatFrame4

    -- ── Phase 0: INERTNESS. The harness logged in with history disabled. ──────
    ck(History.active == false, "phase 0: inactive after disabled login")
    ck(next(History.hookedFrames) == nil, "phase 0: zero AddMessage wrappers while disabled (the pin)")
    ck(next(History.rings) == nil, "phase 0: nothing captured while disabled")

    -- ── Phase 1: enable + capture at the delivery seam. ───────────────────────
    ns.SetModuleEnabled("history", true)
    ck(History.active == true, "phase 1: enabled")
    local wrapped = 0
    for f in pairs(History.hookedFrames) do wrapped = wrapped + 1 end
    ck(wrapped == (_G.NUM_CHAT_WINDOWS or 10), "phase 1: all ten permanent windows wrapped")

    local line1 = Sim.SendChat{ event = "CHAT_MSG_SAY", text = "first",
                                sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    local ring1 = History.rings[1]
    ck(ring1 and #ring1 == 1, "phase 1: a routed line was captured into the shadow ring")
    -- Composition-honest restatement of the round-1 pin: sibling pipeline
    -- modules are legitimately live in the merged world, so byte-equality
    -- with the sim's RAW formatted line encoded a single-module assumption.
    -- The capture's contract is the STORED displayed line, substance intact
    -- (phase 1b below pins the raw-vs-decorated branches explicitly).
    local stored1 = cf1.historyBuffer:GetEntryAtIndex(1)
    ck(ring1 and stored1 and ring1[1].m == stored1.message,
        "phase 1: captured text is the STORED displayed line (capture source = the buffer)")
    ck(ring1 and ring1[1].m:find("first", 1, true) ~= nil
        and ring1[1].m:find("|Hplayer:Puu-Whitemane", 1, true) ~= nil
        and line1 ~= nil,
        "phase 1: the line's substance (text + click payload) survived to the capture")
    ck(ring1 and ring1[1].t == _G.GetServerTime(),
        "phase 1: the capture stamp is EPOCH server time, not uptime")
    cf1:AddMessage("secret |Kq7|k here", 0.2, 0.4, 0.6)
    ck(#ring1 == 2 and ring1[2].m == "secret ??? here",
        "phase 1: |K span sanitized at capture")
    ck(ring1[2].r == 0.2 and ring1[2].g == 0.4 and ring1[2].b == 0.6,
        "phase 1: line colors captured")

    _G.ChatFrame2:AddMessage("combat spam", 1, 1, 1)
    ck(History.rings[2] == nil, "phase 1: the combat log is never captured")

    -- Per-window opt-out gates capture.
    ns.db.history.optOut[3] = true
    cf3:AddMessage("unwanted", 1, 1, 1)
    ck(History.rings[3] == nil, "phase 1: an opted-out window is not captured")
    ns.db.history.optOut[3] = nil
    cf3:AddMessage("wanted", 1, 1, 1)
    ck(History.rings[3] and #History.rings[3] == 1, "phase 1: clearing the opt-out resumes capture")

    -- ── Phase 1b: CAPTURE SOURCE — the store, not the argument (the wrapper-
    -- order defect, fixed and pinned). With decoration live, the stored line
    -- differs from the AddMessage argument, and the capture must equal the
    -- STORED text whichever wrapper sat outermost — order-independent by
    -- construction. With the engine off, stored == raw and capture equals
    -- both. ──────────────────────────────────────────────────────────────────
    ns.Decor.RegisterDecorator("t_hist_capture", 50, function(text)
        return text .. " ~deco~"
    end)
    cf1:AddMessage("capture-source probe", 1, 1, 1)
    local ring1b = History.rings[1]
    local stored1b = cf1.historyBuffer:GetEntryAtIndex(1)
    ck(stored1b and stored1b.message == "capture-source probe ~deco~",
        "phase 1b: the decorator demonstrably changed the stored line")
    ck(stored1b and ring1b[#ring1b].m == stored1b.message,
        "phase 1b: decor ON — history captured the DECORATED stored text, regardless of enable order")
    ck(ring1b[#ring1b].m ~= "capture-source probe",
        "phase 1b RED CONTROL: the raw AddMessage argument was NOT what got captured")
    ns.Decor.UnregisterDecorator("t_hist_capture")
    ns.SetModuleEnabled("decor", false)
    cf1:AddMessage("raw probe", 1, 1, 1)
    ck(ring1b[#ring1b].m == "raw probe",
        "phase 1b: decor OFF — the capture equals the raw line")
    ns.SetModuleEnabled("decor", true)

    -- ── Phase 2: batch-write budget — NEVER a per-message SV write. ──────────
    local store = ns.chardb.history
    local writes0 = History.stats.snapshotWrites
    for i = 1, 5 do cf1:AddMessage("burst " .. i, 1, 1, 1) end
    ck(History.stats.snapshotWrites == writes0, "phase 2: bursts cause ZERO immediate SV writes")
    ck(store.snapshot == nil, "phase 2: the store is untouched until the batch timer")
    HT.advance(SNAPSHOT_SECS)
    ck(History.stats.snapshotWrites == writes0 + 1,
        "phase 2: exactly ONE batched write after the timer beat")
    ck(History.dirty == false, "phase 2: the write cleared the dirty flag")
    HT.advance(SNAPSHOT_SECS)
    ck(History.stats.snapshotWrites == writes0 + 1,
        "phase 2: a clean timer beat writes NOTHING (dirty-gated)")

    -- Bounds: the ring trims to the config cap, oldest evicted.
    ns.db.history.cap = 10   -- config floor
    for i = 1, 14 do cf4:AddMessage("bulk " .. i, 1, 1, 1) end
    local ring4 = History.rings[4]
    ck(ring4 and #ring4 == 10, "phase 2: ring trimmed to the config cap")
    ck(ring4 and ring4[1].m == "bulk 5" and ring4[#ring4].m == "bulk 14",
        "phase 2: trim evicts the OLDEST lines")
    ns.db.history.cap = DEFAULT_CAP

    -- ── Phase 3: LOGOUT snapshot. ─────────────────────────────────────────────
    local ring1Count = #History.rings[1]
    -- Red-control material: the newest buffer entry's RAW uptime stamp, this session.
    local rawUptimeStamp = cf1.historyBuffer:GetEntryAtIndex(1).timestamp
    local epochOfNewest  = History.rings[1][#History.rings[1]].t
    Sim.Logout()
    local snap = store.snapshot
    ck(type(snap) == "table" and snap.at == _G.GetServerTime(),
        "phase 3: LOGOUT wrote a snapshot stamped with server time")
    ck(snap.windows[1] and #snap.windows[1].lines == ring1Count,
        "phase 3: window 1 snapshot holds the full ring")
    ck(snap.windows[2] == nil, "phase 3: no combat-log branch in the snapshot")
    ck(History.stats.lastWriteReason == "logout", "phase 3: the write was the logout beat's")

    -- ── Phase 4: NewSession — the cross-session trap, then restore. ───────────
    Sim.NewSession()
    -- RED CONTROL: the previous session's raw uptime stamps are BOGUS now.
    -- The uptime clock reset under them, so the age they imply against the new
    -- session's clock is wildly wrong versus the line's TRUE server-time age
    -- (the sim hops the server epoch a full hour per session): an hour-old
    -- line would read as fresh. THIS is why capture stamps epoch time.
    local impliedAge = _G.GetTime() - rawUptimeStamp
    local trueAge    = _G.GetServerTime() - epochOfNewest
    ck(math.abs(trueAge - impliedAge) > 3000,
        ("phase 4 RED CONTROL: raw uptime stamps lie about age across sessions "
         .. "(implied %.1fs vs true %.1fs)"):format(impliedAge, trueAge))
    ck(cf1:GetNumMessages() == 0, "phase 4: the fresh session's buffer starts empty")

    Sim.ResetCalls()
    Sim.EnterWorld(true, false)     -- fresh login
    HT.flush()
    local n1 = cf1:GetNumMessages()
    ck(n1 == ring1Count + 1, "phase 4: window 1 backfilled (lines + one divider), got " .. n1)
    ck(Sim.CallCount("AddMessage") == 0,
        "phase 4 HONESTY: restore never touches AddMessage (no pipeline re-entry)")
    ck(Sim.CallCount("historyBuffer.PushFront") > 0, "phase 4: backfill went through PushFront")

    -- Order: restored oldest first, divider LAST of the restored block.
    ck(cf1:GetMessageInfo(1) == snap.windows[1].lines[1].m,
        "phase 4: oldest restored line reads first")
    local divCount, divIdx = 0, nil
    for i = 1, #cf1.historyBuffer.list do
        local e = cf1.historyBuffer.list[i]
        if e.daseekiDivider then divCount = divCount + 1 divIdx = i end
    end
    ck(divCount == 1, "phase 4: exactly ONE divider (got " .. divCount .. ")")
    ck(divIdx == n1, "phase 4: the divider sits after the restored block")
    local div = cf1.historyBuffer.list[divIdx]
    ck(div and div.message:match("^%-%- session from .+ %-%-$") ~= nil,
        "phase 4: divider text is the ASCII session marker")
    local mr, mg, mb = UI.Color("muted")
    ck(div and math.abs(div.r - mr) < 1e-6 and math.abs(div.g - mg) < 1e-6
        and math.abs(div.b - mb) < 1e-6,
        "phase 4: divider ink is the theme's muted TOKEN")

    -- Every restored entry is marked; restamp math holds: the line's
    -- uptime-age equals its true server-age (within the epoch's 1s floor).
    local allMarked, restampOk = true, true
    for i = 1, #cf1.historyBuffer.list do
        local e = cf1.historyBuffer.list[i]
        if not e.daseekiRestored then allMarked = false end
        if e.daseekiEpoch then
            local upAge  = _G.GetTime() - e.timestamp
            local srvAge = _G.GetServerTime() - e.daseekiEpoch
            if math.abs(upAge - srvAge) > 1.01 then restampOk = false end
            if e.timestamp > _G.GetTime() then restampOk = false end
        end
    end
    ck(allMarked, "phase 4: every restored entry carries daseekiRestored (display artifact)")
    ck(restampOk, "phase 4 RESTAMP: uptime-age == server-age for every restored line")
    local newestRestored = cf1.historyBuffer.list[divIdx - 1]
    ck(newestRestored and newestRestored.daseekiEpoch == epochOfNewest,
        "phase 4: the newest restored line is last session's newest capture")

    -- Verdict surface.
    local lr = History.lastRestore
    ck(lr and lr.verdict == "ok" and lr.reason == "login",
        "phase 4: restore verdict recorded (ok/login)")
    ck(lr and lr.lines >= ring1Count, "phase 4: verdict line count covers window 1")

    -- ── Phase 5: double-restore guard + live-after-restore ordering. ─────────
    Sim.EnterWorld(false, false)    -- plain zone-in
    HT.flush()
    Sim.EnterWorld(true, false)     -- a repeated login beat (defensive)
    HT.flush()
    divCount = 0
    for i = 1, #cf1.historyBuffer.list do
        if cf1.historyBuffer.list[i].daseekiDivider then divCount = divCount + 1 end
    end
    ck(divCount == 1, "phase 5: zone-ins and repeat beats never double-restore")

    -- Sibling pipeline modules (decor's seam + names/urls decorators) are
    -- legitimately live in the merged world and may restyle a line before the
    -- client stores it, so byte-equality with the sim's raw formatted line
    -- encoded a single-module assumption. The pin keeps everything it proved:
    -- the live line is the NEWEST stored entry (so it sits after the divider
    -- and after every restored line), it is live content (not a restored
    -- artifact), and its substance — the message text and the sender's click
    -- payload — survived whatever decoration ran.
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "post-restore",
                  sender = "Choco", guid = "Player-1-00000002" }
    local liveTotal  = cf1:GetNumMessages()
    local liveStored = cf1:GetMessageInfo(liveTotal)
    ck(liveStored ~= nil
        and liveStored:find("post-restore", 1, true) ~= nil
        and liveStored:find("|Hplayer:Choco", 1, true) ~= nil,
        "phase 5: the live line is the newest stored entry, substance intact")
    local liveEntry = cf1.historyBuffer:GetEntryAtIndex(1)
    ck(liveEntry and not liveEntry.daseekiRestored,
        "phase 5: live content lands AFTER the divider (newest entry is live, not restored)")
    local divAt5
    for i = 1, #cf1.historyBuffer.list do
        if cf1.historyBuffer.list[i].daseekiDivider then divAt5 = i end
    end
    ck(divAt5 ~= nil and divAt5 < liveTotal,
        "phase 5: the divider sits strictly before the live line")
    ck(#History.rings[1] == ring1Count + 1,
        "phase 5: the ring re-seeded from the snapshot and keeps growing (multi-hop persistence)")

    -- ── Phase 6: restore honors the per-window opt-out (reload path). ────────
    Sim.Logout()                    -- snapshot now includes windows 1, 3, 4
    ck(store.snapshot.windows[3] ~= nil, "phase 6: window 3 is in the snapshot")
    Sim.NewSession()
    ns.db.history.optOut[3] = true
    History.rings[3] = nil
    Sim.EnterWorld(false, true)     -- RELOAD: the isReload arm of the guard
    HT.flush()
    ck(cf3:GetNumMessages() == 0, "phase 6: an opted-out window is not restored")
    ck(cf1:GetNumMessages() > 0, "phase 6: other windows restored on the reload beat")
    ck(History.lastRestore and History.lastRestore.reason == "reload",
        "phase 6: the reload beat restores too (verdict says reload)")
    ns.db.history.optOut[3] = nil

    -- ── Phase 7: disable is inert; re-enable never double-wraps. ─────────────
    ns.SetModuleEnabled("history", false)
    local ringN = #History.rings[1]
    cf1:AddMessage("while disabled", 1, 1, 1)
    ck(#History.rings[1] == ringN, "phase 7: a disabled module captures nothing")
    ns.SetModuleEnabled("history", true)
    cf1:AddMessage("after re-enable", 1, 1, 1)
    ck(#History.rings[1] == ringN + 1,
        "phase 7: re-enable captures each line exactly ONCE (no double wrap)")

    -- Leave the world tidy for the suites after us.
    HT.flush()
    Sim.ResetCalls()
end

ns:RegisterSelfTest("history", function(verbose)
    local fails = {}
    local ok, err = pcall(testPure, fails)
    if not ok then fails[#fails + 1] = "pure error: " .. tostring(err) end
    ok, err = pcall(testLive, fails, verbose)
    if not ok then fails[#fails + 1] = "live error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL history :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS history") end
    return #fails == 0
end)

return History
