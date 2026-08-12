-- =====================================================================
-- Daseeki-Chat harness — THE UNKIND CHAT SIMULATOR (real Lua 5.1)
--
-- Models the Era 11509 client surfaces the whole addon is built against, per
-- the Room-1 game-facts registers (CHAT_ADDONS_BEHAVIOR_SPEC §7, PRAT §8) and
-- CLIENT_ASYNC_LESSONS. Simulator doctrine: UNKIND BY DEFAULT — every async
-- gap, cold read and ordering coin-flip the live client has is the default
-- profile here, because every defect class in the catalog was invisible under
-- a kind sim.
--
-- The unkindnesses, explicitly:
--   * CHANNEL JOINS ARE SERVER OPS: JoinChannelByName completes ~0.5s later
--     via CHAT_MSG_CHANNEL_NOTICE. A join issued <0.5s after the previous
--     join/leave is DROPPED SILENTLY (the server-throttle reality — this is
--     what forces the >=0.5s pacing + verify-and-retry recipe).
--   * EVENT-BEFORE-STATE: the YOU_JOINED/YOU_LEFT notice fires BEFORE
--     GetChannelList reflects the change (state lands on a 0-delay timer).
--     Code that reads the list inside the notice handler reads the old world.
--   * DARK READS (Class 6): GetChannelList answers NOTHING until ~0.5s after
--     PLAYER_ENTERING_WORLD. An early diff reads "no channels".
--   * ADDON HANDLER FIRST (Class 2): our event frame's CHAT_MSG_* handler runs
--     BEFORE the client's own routing stores the line — reading "the newest
--     buffer entry" inside an event handler sees the PREVIOUS message.
--     (Sim.opts.addonEventFirst = false flips the coin for ordering tests.)
--   * WRAPPED BUFFER FIELDS: historyBuffer.headIndex / .maxElements are
--     `{ value = n }` wrapper tables by default (the newer-client shape the
--     survey warns about; shipping skin-over addons code both shapes).
--     Sim.opts.wrappedBufferFields = false gives the plain shape.
--   * CVAR DEFAULTS ARE HOSTILE: chatStyle="im" (addons that need 'classic'
--     must force it) and chatClassColorOverride="1" (silently disables class
--     colors until managed — names.lua must own this CVar both ways).
--   * NO ChatFrame_AddChannel global: the 11509 API catalog does not list it
--     (only ChatFrame_RemoveChannel + the C-side AddChatWindowChannel pair).
--     Code must use AddChatWindowChannel(id, name) or runtime-detect.
--   * A DRAG IS CLAMPED, A SetPoint IS NOT: dragging a frame (StartMoving +
--     Sim.DragTo) lands inside the clamp rect, so a frame carrying the client's
--     default clamp margin CANNOT be dragged flush to the screen edge;
--     programmatic placement ignores the clamp entirely. Code that only ever
--     drags inherits the owner's account-1 symptom.
--   * THE EDIT BOX STARTS HIDDEN and the client HIDES IT AGAIN on every
--     deactivate (chatStyle 'classic', the default; 'im' is the client's own
--     persistent-box mode). A persistent-edit-box feature must earn the shown
--     state against the hiding posture, every time.
--   * THE CHAT BUTTON COLUMN IS SHOWN, FLIPS SIDES, AND KEEPS COMING BACK:
--     every window carries a button frame (the chat-menu + scroll-button
--     column); the client picks its SIDE from the window's screen position
--     (a window against the left edge gets its column flipped to the right —
--     the owner's two-account difference), re-shows it on every button-side
--     update, and that column's width is part of the window's DRAG FOOTPRINT,
--     so a shown column holds the drag off the screen edge exactly like a
--     clamp margin does. An addon that hides it must earn that, every beat.
--   * UIParent's UNIT size moves with uiScale while the PIXEL screen does not
--     (Sim.SetUIScale) — the cross-account scale difference, made drivable.
--
-- Timestamps: ring-buffer entries carry UPTIME (GetTime) stamps; GetServerTime
-- is a separate epoch clock. Sim.NewSession() resets the uptime base (a fresh
-- client session) while the server epoch keeps advancing — the exact mismatch
-- history.lua exists to survive.
--
-- CALL COUNTING: every simulated API bumps Sim.calls[name]; the budget-
-- assertion idiom is Sim.ResetCalls() ... Sim.CallCount(name) == N.
--
-- The harness timer (_G.__DaseekiChatHarnessTimer, queue-and-pump with a
-- virtual clock) must be installed BEFORE this file loads.
-- =====================================================================

local HTIMER = assert(_G.__DaseekiChatHarnessTimer,
    "chatsim.lua needs _G.__DaseekiChatHarnessTimer installed first")

local Sim = {
    calls        = {},
    opts         = {
        wrappedBufferFields = true,   -- unkind default
        addonEventFirst     = true,   -- unkind default (Class 2 ordering)
        -- w2/reconciler ADDITIVE unkindness (default inert): channel names the
        -- "server" never grants. The join is accepted (it consumes the pacing
        -- slot like a real send) but no notice ever fires and the list never
        -- changes — the refusal-ladder world channels.lua must survive.
        refuseJoins         = {},     -- [name] = true
    },
    droppedJoins = 0,                 -- silently swallowed join/leave requests
    windows      = {},                -- the per-character client chat store
    serverChannels = {},              -- number -> { name=, zoneID= }
    zoneChannels = { "General" },     -- what EnumerateServerChannels offers
    playerDB     = {},                -- guid -> class info
    cvars        = {},
    tempFrames   = {},
    inCombat     = false,
    sessionCount = 1,
}
_G.__DaseekiChatSim = Sim

local function record(name)
    Sim.calls[name] = (Sim.calls[name] or 0) + 1
end
function Sim.CallCount(name) return Sim.calls[name] or 0 end
function Sim.ResetCalls() Sim.calls = {} end

----------------------------------------------------------------------
-- Clocks. Uptime resets per session (GetTime); the server epoch does not.
----------------------------------------------------------------------

Sim._uptimeBase        = 25.0            -- a client never boots at 0
Sim._sessionStartClock = 0
Sim._serverEpochBase   = 1770000000

function Sim.Uptime()
    return Sim._uptimeBase + (HTIMER.clock - Sim._sessionStartClock)
end

_G.GetTime = function() record("GetTime") return Sim.Uptime() end
_G.GetServerTime = function()
    record("GetServerTime")
    return Sim._serverEpochBase + math.floor(HTIMER.clock)
end
_G.date = os.date

----------------------------------------------------------------------
-- Widget stub. Known-semantics methods are implemented for real; any OTHER
-- method auto-vivifies as a recorded no-op (logged in widget._unknownCalls so
-- a test CAN assert none happened). This keeps the sim maintainable for three
-- parallel agents without silently crashing on an unmodeled widget call.
----------------------------------------------------------------------

local WIDGET_API = {}
local widgetMeta

Sim._fontStrings = {}

local function newWidget(kind, name, parent)
    local w = {
        _kind = kind, _name = name, _parent = parent,
        _shown = true, _alpha = 1,
        _points = {}, _scripts = {}, _children = {}, _unknownCalls = {},
    }
    setmetatable(w, widgetMeta)
    if name then _G[name] = w end
    if parent and parent._children then parent._children[#parent._children + 1] = w end
    if kind == "FontString" then Sim._fontStrings[#Sim._fontStrings + 1] = w end
    return w
end
Sim.NewWidget = newWidget

function WIDGET_API.GetName(self) return self._name end
function WIDGET_API.GetParent(self) return self._parent end
function WIDGET_API.SetParent(self, p) self._parent = p end
function WIDGET_API.GetObjectType(self) return self._kind end
-- w2/history sim extension (additive): the real client fires OnShow/OnHide
-- script handlers on a genuine visibility TRANSITION (not on redundant calls);
-- badge clear-on-show rides that fact, so the sim models it.
function WIDGET_API.Show(self)
    local was = self._shown
    self._shown = true
    if not was then
        local fn = self._scripts and self._scripts.OnShow
        if fn then fn(self) end
    end
end
function WIDGET_API.Hide(self)
    local was = self._shown
    self._shown = false
    if was then
        local fn = self._scripts and self._scripts.OnHide
        if fn then fn(self) end
    end
end
function WIDGET_API.SetShown(self, on)
    if on then self:Show() else self:Hide() end
end
-- w2/button-column sim extension: a Button's programmatic Click runs its own
-- OnClick handler (the client's behavior, and the only way an addon can reach
-- a client verb that lives behind a client button).
function WIDGET_API.Click(self, button)
    record("widget:Click")
    local fn = self._scripts and self._scripts.OnClick
    if fn then fn(self, button or "LeftButton") end
end
function WIDGET_API.IsShown(self) return self._shown end
function WIDGET_API.IsVisible(self) return self._shown end
function WIDGET_API.SetAlpha(self, a) self._alpha = a end
function WIDGET_API.GetAlpha(self) return self._alpha end
function WIDGET_API.SetPoint(self, point, rel, relPoint, x, y)
    self._points[#self._points + 1] = { point, rel, relPoint, x, y }
    -- w2/move sim extension: the CANONICAL anchor the position reconciler uses
    -- (BOTTOMLEFT of the frame to BOTTOMLEFT of a relative frame) is modeled
    -- for real, so programmatic placement is READABLE BACK through
    -- GetLeft/GetBottom — and, unlike a drag, is never clamped. Offsets are
    -- read in the ANCHORED frame's units, so the relative frame's corner is
    -- converted through the effective-scale ratio (the Class 3 discipline:
    -- convert into the compared frame's space).
    if point == "BOTTOMLEFT" and relPoint == "BOTTOMLEFT" and type(rel) == "table"
       and type(rel.GetEffectiveScale) == "function" then
        local mine = (type(self.GetEffectiveScale) == "function") and self:GetEffectiveScale() or 1
        if mine ~= 0 then
            local ratio = rel:GetEffectiveScale() / mine
            self._left   = (rel._left or 0) * ratio + (tonumber(x) or 0)
            self._bottom = (rel._bottom or 0) * ratio + (tonumber(y) or 0)
        end
    end
end
function WIDGET_API.ClearAllPoints(self) self._points = {} end
function WIDGET_API.GetNumPoints(self) return #self._points end
function WIDGET_API.GetPoint(self, i)
    local p = self._points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function WIDGET_API.SetAllPoints(self, target) self._allPoints = target or self._parent end
-- view/align sim extension: a REAL size change fires OnSizeChanged, exactly
-- once, exactly like the client — which is the beat an inner layout reflows on
-- while a resize drag is still in flight. A redundant SetSize fires nothing.
local function sizeChanged(self, w, h)
    if self._w == w and self._h == h then return end
    self._w, self._h = w, h
    local fn = self._scripts and self._scripts.OnSizeChanged
    if fn and not self._inSizeChanged then
        self._inSizeChanged = true
        local ok, err = pcall(fn, self, w or 0, h or 0)
        self._inSizeChanged = nil
        if not ok then error(err, 0) end
    end
end
function WIDGET_API.SetSize(self, w, h) sizeChanged(self, w, h) end
function WIDGET_API.SetWidth(self, w) sizeChanged(self, w, self._h) end
function WIDGET_API.SetHeight(self, h) sizeChanged(self, self._w, h) end
function WIDGET_API.GetWidth(self) return self._w or 0 end
function WIDGET_API.GetHeight(self) return self._h or 0 end
function WIDGET_API.SetScript(self, k, fn) self._scripts[k] = fn end
function WIDGET_API.GetScript(self, k) return self._scripts[k] end
function WIDGET_API.HookScript(self, k, fn)
    local prev = self._scripts[k]
    self._scripts[k] = prev and function(...) prev(...); fn(...) end or fn
end
-- skin-v2 sim extension (additive): the attribute bag the client's edit box
-- keeps its sticky chat state in (chatType / channelTarget / tellTarget).
function WIDGET_API.SetAttribute(self, k, v)
    self._attrs = self._attrs or {}
    self._attrs[k] = v
end
function WIDGET_API.GetAttribute(self, k)
    return self._attrs and self._attrs[k] or nil
end
function WIDGET_API.SetFrameLevel(self, l) self._frameLevel = l end
function WIDGET_API.GetFrameLevel(self) return self._frameLevel or 1 end
function WIDGET_API.SetFrameStrata(self, s) self._strata = s end
function WIDGET_API.EnableMouse(self, on) record("EnableMouse") self._mouse = on end
-- w2/options sim extension (additive): the client's own child walk. Answers
-- FRAMES only — textures and font strings are regions, not children, and carry
-- no hitbox of their own, which is precisely the distinction a "remove the
-- hitboxes" feature has to get right.
local FRAME_KINDS = {
    Frame = true, Button = true, EditBox = true, CheckButton = true,
    Slider = true, ScrollFrame = true, ScrollingMessageFrame = true,
    StatusBar = true, GameTooltip = true,
}
function WIDGET_API.GetChildren(self)
    record("GetChildren")
    local out = {}
    for _, kid in ipairs(self._children or {}) do
        if FRAME_KINDS[kid._kind] then out[#out + 1] = kid end
    end
    return unpack(out)
end
-- w2/options sim extension (additive): the client's blanket unregister. The
-- sim tracks which events a frame holds so a test can pin "it held some, and
-- afterwards it holds none" — the client itself offers no such listing, which
-- is the whole reason the restore path has to be honest about /reload.
function WIDGET_API.UnregisterAllEvents(self)
    record("frame:UnregisterAllEvents")
    for event, list in pairs(Sim._eventTargets) do
        for i = #list, 1, -1 do
            if list[i] == self then table.remove(list, i) end
        end
        if #list == 0 then Sim._eventTargets[event] = nil end
    end
    self._events = nil
end
function WIDGET_API.IsEventRegistered(self, event)
    local list = Sim._eventTargets[event]
    if not list then return false end
    for i = 1, #list do if list[i] == self then return true end end
    return false
end
function WIDGET_API.CreateTexture(self, name, layer)
    return newWidget("Texture", name, self)
end
function WIDGET_API.CreateFontString(self, name, layer)
    return newWidget("FontString", name, self)
end
function WIDGET_API.RegisterEvent(self, event)
    record("frame:RegisterEvent")
    local list = Sim._eventTargets[event]
    if not list then list = {}; Sim._eventTargets[event] = list end
    for i = 1, #list do if list[i] == self then return end end
    list[#list + 1] = self
end
function WIDGET_API.UnregisterEvent(self, event)
    record("frame:UnregisterEvent")
    local list = Sim._eventTargets[event]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
end
-- Backdrop family (BackdropTemplate surface).
function WIDGET_API.SetBackdrop(self, spec) self._backdrop = spec end
function WIDGET_API.SetBackdropColor(self, r, g, b, a)
    self._backdropColor = { r, g, b, a }
end
function WIDGET_API.SetBackdropBorderColor(self, r, g, b, a)
    self._backdropBorderColor = { r, g, b, a }
end
-- Texture surface.
function WIDGET_API.SetColorTexture(self, r, g, b, a) self._color = { r, g, b, a } end
function WIDGET_API.SetVertexColor(self, r, g, b, a) self._vertexColor = { r, g, b, a } end
function WIDGET_API.SetTexture(self, tex) self._texture = tex end
function WIDGET_API.SetTexCoord(self) end
-- Text surface (FontString / EditBox / chat frame font).
function WIDGET_API.SetFont(self, face, size, flags)
    self._font = { face, size, flags }
    return true                    -- the success:bool overload (catalog 3917)
end
function WIDGET_API.GetFont(self)
    local f = self._font
    if not f then return nil end
    return f[1], f[2], f[3]
end
function WIDGET_API.SetFontObject(self, obj) self._fontObject = obj end
function WIDGET_API.SetText(self, text)
    self._text = text
    local fn = self._scripts and self._scripts.OnTextChanged
    if fn then fn(self, false) end
end
function WIDGET_API.GetText(self) return self._text or "" end
function WIDGET_API.SetTextColor(self, r, g, b, a) self._textColor = { r, g, b, a } end
-- ── UNKIND STRING WIDTH (view/align sim extension) ───────────────────────────
-- The kind version of this method answered `#text * 7` for ANY FontString the
-- moment it existed — including one that had never been given a face. That is
-- an idealized client. Live on 11509 a FontString measures NOTHING until a font
-- has been applied to it: the client cannot measure glyphs it has no face for,
-- so GetStringWidth answers a flat 0 and keeps answering 0 for as long as the
-- string is faceless. Any layout that sizes a widget FROM that measurement
-- sizes it from nothing.
--
-- THIS IS THE HAZARD THE OVERLAPPING-TAB DEFECT WAS SUSPECTED OF, and the sim
-- hid it completely: every SetFont call in the view is CONDITIONAL on the
-- DaseekiUI kit answering, so on a client where it does not, every tab label is
-- faceless and every width the layout reads is 0. The measured cause turned out
-- to be arithmetic (see the tab-run pin in view.lua), but the width hazard is
-- real, it is now modeled, and the fallback that answers it is now pinned
-- rather than assumed.
--
-- The client's OWN long-lived strings are born with a face (makeChatFrame sets
-- one), so this lands where it is real: on strings an ADDON creates and never
-- gives a font to.
function WIDGET_API.GetStringWidth(self)
    record("GetStringWidth")
    if not (self._font or self._fontObject) then return 0 end
    return #(self._text or "") * 7
end
function WIDGET_API.SetJustifyH(self, j) self._justifyH = j end
function WIDGET_API.GetJustifyH(self) return self._justifyH or "LEFT" end
-- EditBox surface.
function WIDGET_API.SetMultiLine(self, on) self._multiLine = on end
function WIDGET_API.SetAutoFocus(self, on) self._autoFocus = on end
-- w2/move sim extension: focus is a real TRANSITION (like Show/Hide above), so
-- the client's OnEditFocusGained / OnEditFocusLost scripts fire exactly once
-- per genuine change — the beat a persistent edit box styles itself on.
function WIDGET_API.SetFocus(self)
    record("SetFocus")
    local was = self._focused
    self._focused = true
    if not was then
        local fn = self._scripts and self._scripts.OnEditFocusGained
        if fn then fn(self) end
    end
end
function WIDGET_API.ClearFocus(self)
    record("ClearFocus")
    local was = self._focused
    self._focused = false
    if was then
        local fn = self._scripts and self._scripts.OnEditFocusLost
        if fn then fn(self) end
    end
end
function WIDGET_API.HasFocus(self) return self._focused and true or false end
function WIDGET_API.HighlightText(self) record("HighlightText") self._highlighted = true end
-- ui/mockup-fidelity sim extension (additive): the insets are RECORDED now, so
-- the entry bar's mockup padding is a pin instead of a claim.
function WIDGET_API.SetTextInsets(self, l, r, t, b) self._textInsets = { l, r, t, b } end
function WIDGET_API.GetTextInsets(self)
    local i = self._textInsets
    if not i then return 0, 0, 0, 0 end
    return i[1], i[2], i[3], i[4]
end
-- …and the ONE typographic lever a ScrollingMessageFrame has: the row rhythm.
function WIDGET_API.SetSpacing(self, s) self._spacing = s end
function WIDGET_API.GetSpacing(self) return self._spacing or 0 end
-- Draw sublevel, so "the surface is above the backdrop's own fill" is readable.
function WIDGET_API.SetDrawLayer(self, layer, sub) self._drawLayer = { layer, sub } end
function WIDGET_API.SetMaxLetters(self, n) self._maxLetters = n end
function WIDGET_API.SetCursorPosition(self, n) end
function WIDGET_API.SetNumeric(self, on) end
-- ScrollFrame surface.
function WIDGET_API.SetScrollChild(self, child) self._scrollChild = child end
-- ── GEOMETRY + MOVEMENT (w2/move sim extension, additive) ────────────────────
-- Frames carry a REAL bottom-left corner (in their own units) and a scale, so
-- the scale chain (frame -> UIParent -> effective) is honest and a normalized
-- position can be round-tripped. Two placement paths exist and they are NOT
-- equivalent — which is the whole point of the position work:
--   * DRAGGING (StartMoving + Sim.DragTo + StopMovingOrSizing) is CLAMPED by
--     the frame's clamp rect insets, so a frame with the client's default
--     margin CANNOT be dragged flush to the screen edge;
--   * PROGRAMMATIC placement (ClearAllPoints + SetPoint) is NOT clamped, so it
--     lands wherever it is told.
-- The default insets below are modeled from the OWNER-OBSERVED symptom (one
-- account's chat window refuses to sit flush against the edge while another's
-- does), not claimed from the API catalog: the catalog verifies the CALLS
-- (SetClampRectInsets / GetClampRectInsets / IsClampedToScreen /
-- GetEffectiveScale / StartMoving / StopMovingOrSizing), the sim supplies an
-- unkind default so code that never loosens the clamp fails the flush pin.
Sim.DEFAULT_CLAMP_INSETS = { 8, 8, 8, 8 }   -- left, right, top, bottom
-- What the client REWRITES onto a window whenever it re-decides the button
-- column's side (see FCF_SetButtonSide below). Same numbers as the default:
-- the point is that they come BACK, not that they are different.
Sim.STOCK_CLAMP_INSETS   = { 8, 8, 8, 8 }
Sim.clampShoves          = 0                -- times the client shoved a frame back

-- ── THE BUTTON COLUMN'S FOOTPRINT (w2/button-column sim extension) ───────────
-- The chat button frame hangs OFF the window's edge, and its width is part of
-- what the drag has to fit on screen — so a window whose column is shown stops
-- short of the edge by the column's width on top of the clamp margin, and one
-- whose column is hidden does not. Same provenance posture as the clamp insets
-- above: the CALLS are catalog-verified on 11509 (FCF_UpdateButtonSide,
-- FCF_GetButtonSide, FCF_SetButtonSide), the WIDTH and the flush behavior are
-- modeled from the owner's two-account observation (a small square column on
-- the left on one account, on the right on the other, and the window refusing
-- the last stretch to the edge either way).
Sim.BUTTON_FRAME_WIDTH = 30

local function insetsOf(self)
    return self._clampInsets or Sim.DEFAULT_CLAMP_INSETS
end

-- Extra units the shown column eats on the left / on the right (0, 0 when the
-- window has no column or its column is down).
function Sim.ColumnFootprint(frame)
    if type(frame) ~= "table" then return 0, 0 end
    local bf = frame.buttonFrame
    if type(bf) ~= "table" or not bf._shown then return 0, 0 end
    local w = bf._w or 0
    if frame._buttonSide == "right" then return 0, w end
    return w, 0
end

-- w2/options sim extension (additive): POINTER HIT TESTING, the one fact a
-- "remove the hitboxes" feature stands or falls on. A widget is a hit only
-- when it is SHOWN, MOUSE-ENABLED and its rect contains the point; the first
-- candidate that qualifies wins (callers pass their candidates topmost-first,
-- which is the client's own front-to-back order). A widget that fails any of
-- the three is not a hit and whatever is behind it is — which is exactly the
-- question "is the invisible column still eating my clicks?" asks.
function Sim.HitTest(x, y, candidates)
    for _, w in ipairs(candidates or {}) do
        if type(w) == "table" and w._shown and w._mouse ~= false then
            local l, b = w._left, w._bottom
            if l and b then
                local r, t = l + (w._w or 0), b + (w._h or 0)
                if x >= l and x <= r and y >= b and y <= t then return w end
            end
        end
    end
    return nil
end

-- The column's rect right now, in the window's own units (nil when it has no
-- column or the geometry is unreadable).
function Sim.ColumnRect(frame)
    if type(frame) ~= "table" then return nil end
    local bf = frame.buttonFrame
    if type(bf) ~= "table" or bf._left == nil or bf._bottom == nil then return nil end
    return bf._left, bf._bottom, bf._w or 0, bf._h or 0
end

-- ── THE ANCHOR RESOLVER (view/align sim extension) ───────────────────────────
-- THE BLIND SPOT THIS CLOSES, named: until now the sim recorded SetPoint calls
-- but only ever RESOLVED the one special case the position work needed
-- (BOTTOMLEFT -> BOTTOMLEFT). Every other anchor was write-only, so no test
-- could ask the question that matters for a drawn layout — "where does this
-- widget actually END UP" — and a whole class of layout arithmetic (a tab run
-- that piles four tabs on one x, a feed whose top edge climbs into the tab
-- strip) was unassertable BY CONSTRUCTION. An unmeasurable client is a kind
-- client.
--
-- The solver is the client's own model: a widget's rect is fixed by its points,
-- each of which pins one of its own anchor fractions to a coordinate on another
-- widget's rect. Two points on one axis DETERMINE the size (and, exactly like
-- the client, they OUTRANK an explicit SetSize — "if both edges are anchored,
-- setting the width has no effect"); one point plus an explicit size does too.
-- Anything less is genuinely unresolvable and answers nil rather than a zero.
local ANCHOR_H = {
    LEFT = 0, RIGHT = 1, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5,
    TOPLEFT = 0, BOTTOMLEFT = 0, TOPRIGHT = 1, BOTTOMRIGHT = 1,
}
local ANCHOR_V = {
    BOTTOM = 0, TOP = 1, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5,
    BOTTOMLEFT = 0, BOTTOMRIGHT = 0, TOPLEFT = 1, TOPRIGHT = 1,
}

local function solveAxis(cs, explicitSize)
    -- Two constraints at different fractions determine BOTH origin and size.
    for i = 1, #cs do
        for j = i + 1, #cs do
            if cs[i].frac ~= cs[j].frac then
                local a, b = cs[i], cs[j]
                local size = (b.at - a.at) / (b.frac - a.frac)
                return a.at - a.frac * size, size
            end
        end
    end
    if #cs >= 1 and explicitSize then
        return cs[1].at - cs[1].frac * explicitSize, explicitSize
    end
    return nil
end

local resolveRect
resolveRect = function(w, busy)
    if type(w) ~= "table" then return nil end
    busy = busy or {}
    if busy[w] then return nil end                  -- an anchor cycle resolves to nothing
    busy[w] = true
    local function done(a, b, c, d) busy[w] = nil return a, b, c, d end
    if w._allPoints then
        local l, b, ww, hh = resolveRect(w._allPoints, busy)
        return done(l, b, ww, hh)
    end
    -- A FontString has an IMPLICIT size — its measured text box — which is why
    -- anchoring off one (the mockup's pip sits after the tab's LABEL, not after
    -- the tab) resolves at all. Width is the measurement, height the face's own
    -- line box; both fall out of the model already here.
    local iw, ih = w._w, w._h
    if w._kind == "FontString" then
        if iw == nil then iw = w:GetStringWidth() end
        if ih == nil then
            local size = (w._font and tonumber(w._font[2])) or 12
            ih = size * 1.2
        end
    end
    local pts = w._points or {}
    if #pts == 0 then
        if w._left ~= nil and w._bottom ~= nil then
            return done(w._left, w._bottom, iw or 0, ih or 0)
        end
        return done(nil)
    end
    local hc, vc = {}, {}
    for _, p in ipairs(pts) do
        local mine = tostring(p[1] or ""):upper()
        local rel  = p[2] or w._parent
        local theirs = tostring(p[3] or p[1] or ""):upper()
        local x, y = tonumber(p[4]) or 0, tonumber(p[5]) or 0
        local rl, rb, rw, rh = resolveRect(rel, busy)
        if rl ~= nil then
            if ANCHOR_H[mine] and ANCHOR_H[theirs] then
                hc[#hc + 1] = { frac = ANCHOR_H[mine], at = rl + (rw or 0) * ANCHOR_H[theirs] + x }
            end
            if ANCHOR_V[mine] and ANCHOR_V[theirs] then
                vc[#vc + 1] = { frac = ANCHOR_V[mine], at = rb + (rh or 0) * ANCHOR_V[theirs] + y }
            end
        end
    end
    local l, ww = solveAxis(hc, iw)
    local b, hh = solveAxis(vc, ih)
    if l == nil or b == nil then return done(nil) end
    return done(l, b, ww, hh)
end

-- left, bottom, width, height in the widget's own units — or nil for a widget
-- the anchors do not determine (never a hopeful zero).
function Sim.ResolveRect(w) return resolveRect(w) end

-- Do two resolved rects overlap? nil when either cannot be resolved, so a test
-- can tell "they do not overlap" from "nobody could say".
function Sim.RectsOverlap(a, b)
    local al, ab, aw, ah = Sim.ResolveRect(a)
    local bl, bb, bw, bh = Sim.ResolveRect(b)
    if al == nil or bl == nil then return nil end
    if al + aw <= bl or bl + bw <= al then return false end
    if ab + ah <= bb or bb + bh <= ab then return false end
    return true
end

-- ── OCCLUSION (ui/grip-visibility sim extension, 2026-08-12) ────────────────
-- "The grip is at a higher frame level" is not the same claim as "the player
-- can see and click the grip", and the difference is what the owner's "there is
-- still no drag to re-size function. at least not one that's obvious" was
-- about. A test can only tell those two apart if the sim can answer WHO IS ON
-- TOP where two rects meet — so it does.
--
-- The client's own rule, modeled: strata first (a coarse band), frame level
-- second (within a band). A widget with no strata of its own inherits its
-- parent's, exactly as the client does, which is what makes a reparented
-- client edit box answerable at all.
local STRATA_RANK = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

function Sim.EffectiveStrata(w)
    local guard = 0
    while type(w) == "table" and guard < 32 do
        if w._strata then return w._strata end
        w = w._parent
        guard = guard + 1
    end
    return "MEDIUM"
end

-- Is `a` drawn ABOVE `b`? nil when neither can be placed in the order (never a
-- hopeful "yes").
function Sim.DrawsAbove(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local sa = STRATA_RANK[tostring(Sim.EffectiveStrata(a)):upper()]
    local sb = STRATA_RANK[tostring(Sim.EffectiveStrata(b)):upper()]
    if not (sa and sb) then return nil end
    if sa ~= sb then return sa > sb end
    local la = (type(a.GetFrameLevel) == "function") and a:GetFrameLevel() or nil
    local lb = (type(b.GetFrameLevel) == "function") and b:GetFrameLevel() or nil
    if la == nil or lb == nil then return nil end
    return la > lb
end

-- Every candidate that OVERLAPS `target` and is drawn ABOVE it while visible.
-- An empty list is the only honest way to say "nothing is covering this".
function Sim.Occluders(target, candidates)
    local out = {}
    if type(target) ~= "table" then return out end
    for _, c in ipairs(candidates or {}) do
        if type(c) == "table" and c ~= target and c._shown and (c._alpha or 1) > 0 then
            if Sim.RectsOverlap(target, c) and Sim.DrawsAbove(c, target) then
                out[#out + 1] = c._name or c._kind or "?"
            end
        end
    end
    return out
end

function WIDGET_API.SetScale(self, s) self._scale = tonumber(s) or 1 end
function WIDGET_API.GetScale(self) return self._scale or 1 end
function WIDGET_API.GetEffectiveScale(self)
    record("GetEffectiveScale")
    local s = self._scale or 1
    local p = self._parent
    if type(p) == "table" and type(p.GetEffectiveScale) == "function" then
        return s * p:GetEffectiveScale()
    end
    return s
end
function WIDGET_API.GetLeft(self)   return self._left end
function WIDGET_API.GetBottom(self) return self._bottom end
function WIDGET_API.GetRight(self)
    if self._left == nil then return nil end
    return self._left + (self._w or 0)
end
function WIDGET_API.GetTop(self)
    if self._bottom == nil then return nil end
    return self._bottom + (self._h or 0)
end
function WIDGET_API.GetCenter(self)
    if self._left == nil or self._bottom == nil then return nil end
    return self._left + (self._w or 0) / 2, self._bottom + (self._h or 0) / 2
end
function WIDGET_API.SetMovable(self, on) record("SetMovable") self._movable = on and true or false end
function WIDGET_API.IsMovable(self) return self._movable and true or false end
function WIDGET_API.RegisterForDrag(self, ...) self._dragButtons = { ... } end
function WIDGET_API.StartMoving(self)
    record("StartMoving")
    if not self._movable then return end
    self._moving = true
end
function WIDGET_API.StopMovingOrSizing(self)
    record("StopMovingOrSizing")
    self._moving = false
    self._sizing = nil
    self._sizeGrab = nil
    -- w2/button-column sim extension: the window landed somewhere new, so the
    -- client re-decides which side its button column belongs on — and re-shows
    -- it in the process. This is the beat that makes two accounts differ.
    if type(self.buttonFrame) == "table" and type(_G.FCF_UpdateButtonSide) == "function" then
        _G.FCF_UpdateButtonSide(self)
    end
end
function WIDGET_API.IsDragging(self) return self._moving and true or false end
function WIDGET_API.SetClampedToScreen(self, on)
    record("SetClampedToScreen")
    self._clamped = on and true or false
end
function WIDGET_API.IsClampedToScreen(self)
    return self._clamped ~= false
end
function WIDGET_API.SetClampRectInsets(self, l, r, t, b)
    record("SetClampRectInsets")
    self._clampInsets = { tonumber(l) or 0, tonumber(r) or 0, tonumber(t) or 0, tonumber(b) or 0 }
end
function WIDGET_API.GetClampRectInsets(self)
    record("GetClampRectInsets")
    local c = insetsOf(self)
    return c[1], c[2], c[3], c[4]
end
function WIDGET_API.IsMouseEnabled(self) return self._mouse ~= false end
-- ── RESIZING (view/align sim extension) ──────────────────────────────────────
-- The catalog-verified surface (SetResizable / StartSizing /
-- StopMovingOrSizing / SetResizeBounds on 11509) modeled UNKIND, the way the
-- clamp above is: SetResizeBounds only RECORDS the numbers — the sim never
-- enforces them for you — because the live client applies bounds during its own
-- sizing loop and an addon that leans on that for its MIN/MAX has no answer at
-- all on the paths it drives itself. Code that wants a floor has to clamp.
function WIDGET_API.SetResizable(self, on) record("SetResizable") self._resizable = on and true or false end
function WIDGET_API.IsResizable(self) return self._resizable and true or false end
function WIDGET_API.SetResizeBounds(self, minW, minH, maxW, maxH)
    record("SetResizeBounds")
    self._resizeBounds = { minW, minH, maxW, maxH }
end
function WIDGET_API.GetResizeBounds(self)
    local b = self._resizeBounds
    if not b then return nil end
    return b[1], b[2], b[3], b[4]
end
function WIDGET_API.StartSizing(self, point)
    record("StartSizing")
    if not self._resizable then return end
    self._sizing = tostring(point or "BOTTOMRIGHT"):upper()
    -- THE GRAB, recorded the way the client records it: the cursor's SCREEN
    -- position and the frame's rect at the instant of the grab. Everything the
    -- sizing loop does afterwards is a DELTA off this pair, which is what makes
    -- the grab offset survive the drag (see Sim.GripDragTo).
    local l, b, w, h = resolveRect(self)
    if l == nil then l, b, w, h = self._left, self._bottom, self._w or 0, self._h or 0 end
    self._sizeGrab = {
        cx = Sim.cursor[1], cy = Sim.cursor[2],
        l = l or 0, b = b or 0, w = w or 0, h = h or 0,
    }
end
function WIDGET_API.IsResizing(self) return self._sizing and true or false end
function WIDGET_API.SetHitRectInsets(self) end
function WIDGET_API.EnableMouseWheel(self) end

-- The clamp rect, resolved into the frame's OWN units: where the client will
-- allow this frame's bottom-left corner to sit. One implementation, used by
-- BOTH the drag path and the client's own enforcement beat, so the two can
-- never disagree about what "on screen" means.
local function clampBounds(frame)
    local P = _G.UIParent
    local ratio = P:GetEffectiveScale() / frame:GetEffectiveScale()
    local pw, ph = P:GetWidth() * ratio, P:GetHeight() * ratio
    local ins = insetsOf(frame)
    -- The button column rides along with the window, so whatever it covers
    -- has to fit on screen too: a shown column is a margin the drag cannot
    -- spend, on top of the clamp's own.
    local colL, colR = Sim.ColumnFootprint(frame)
    local minL, maxL = ins[1] + colL, pw - (frame._w or 0) - ins[2] - colR
    local minB, maxB = ins[4], ph - (frame._h or 0) - ins[3]
    if maxL < minL then maxL = minL end
    if maxB < minB then maxB = minB end
    return minL, maxL, minB, maxB
end

-- Drag the frame's bottom-left corner to (left, bottom) IN THE FRAME'S OWN
-- UNITS. Only works while the frame is actually moving (StartMoving), and the
-- client's clamp decides where it is allowed to land. Returns the landed
-- corner so a test can pin "the drag could not reach the edge".
function Sim.DragTo(frame, left, bottom)
    if type(frame) ~= "table" or not frame._moving then return nil end
    local l, b = tonumber(left) or 0, tonumber(bottom) or 0
    if frame:IsClampedToScreen() then
        local minL, maxL, minB, maxB = clampBounds(frame)
        if l < minL then l = minL elseif l > maxL then l = maxL end
        if b < minB then b = minB elseif b > maxB then b = maxB end
    end
    frame._left, frame._bottom = l, b
    return l, b
end

-- Drag the sizing grip so the GRABBED CORNER lands at (x, y) in the frame's own
-- units. The corner is whichever one StartSizing was given, and the OPPOSITE
-- corner is held — which is what a corner grip means on the live client.
--
-- WHY IT IS NO LONGER BOTTOMRIGHT-ONLY (2026-08-11): the sim modeled exactly
-- one grip because the addon shipped exactly one, so "the opposite corner stays
-- put" was not a question any test could ask. The owner asked for four corners;
-- an unaskable question is a kind client, so the model grew the other three.
--
-- UNKIND, on purpose: NOTHING is clamped here. The sim will happily size a
-- frame to two units or past the screen, so a min/max that lives only in
-- SetResizeBounds is a min/max that never ran. Returns the landed width, height.
function Sim.SizeTo(frame, x, y)
    if type(frame) ~= "table" or not frame._sizing then return nil end
    local l, b, w, h = Sim.ResolveRect(frame)
    if l == nil then l, b, w, h = frame._left, frame._bottom, frame._w or 0, frame._h or 0 end
    if l == nil then return nil end
    w, h = w or 0, h or 0
    local corner = tostring(frame._sizing):upper()
    local right, top = l + w, b + h
    local nx = tonumber(x) or (corner:find("RIGHT") and right or l)
    local ny = tonumber(y) or (corner:find("TOP") and top or b)
    local nl, nb, nw, nh
    if corner:find("RIGHT") then nl, nw = l, nx - l
    else nl, nw = nx, right - nx end
    if corner:find("TOP") then nb, nh = b, ny - b
    else nb, nh = ny, top - ny end
    frame._left, frame._bottom = nl, nb
    frame:SetSize(nw, nh)
    return nw, nh
end

-- ── THE CURSOR-FAITHFUL SIZING LOOP (resize sim extension, 2026-08-12) ───────
--
-- WHY Sim.SizeTo WAS NOT ENOUGH, named: it takes the corner's destination in
-- the FRAME'S OWN UNITS, so it hands the code under test an answer that is
-- already in the right space. Every scale bug in a resize path lives in the
-- conversion from the pointer's SCREEN PIXELS into those units — and a sim that
-- never makes that conversion cannot fail it. That is the same blind spot
-- Class 9 named: the sim tested the fix, never the hazard.
--
-- So THIS is how a test drags a corner: in SCREEN PIXELS, like a mouse. The
-- model is the client's own: the dragged corner moves by the cursor's DELTA
-- since the grab, converted into the frame's units by the frame's EFFECTIVE
-- SCALE, with the opposite corner held. The GRAB OFFSET therefore survives —
-- grabbing a grip 9 units in from the corner keeps the corner 9 units from the
-- pointer for the whole drag, exactly as the live client behaves — so a test
-- can tell "tracks the mouse" apart from "jumps to the mouse".
--
-- The client's own resize bounds ARE enforced here (unlike SetResizeBounds'
-- record-only posture on the paths WE drive), because during the client's
-- sizing loop the client really does apply them — and a drag that runs past the
-- floor and gets snapped back at release is a corner leaving the cursor.
function Sim.GripDragTo(frame, screenX, screenY)
    if type(frame) ~= "table" or not frame._sizing then return nil end
    local g = frame._sizeGrab
    if not g then return nil end
    local fs = frame:GetEffectiveScale()
    if not fs or fs <= 0 then return nil end
    Sim.cursor = { tonumber(screenX) or g.cx, tonumber(screenY) or g.cy }
    -- Screen pixels -> this frame's units. THE divide the hazard lives in.
    local dx = (Sim.cursor[1] - g.cx) / fs
    local dy = (Sim.cursor[2] - g.cy) / fs
    local corner = tostring(frame._sizing):upper()
    local l, b, w, h = g.l, g.b, g.w, g.h
    local nl, nb, nw, nh = l, b, w, h
    if corner:find("RIGHT") then nw = w + dx else nl, nw = l + dx, w - dx end
    if corner:find("TOP")   then nh = h + dy else nb, nh = b + dy, h - dy end
    -- The client's bounds, applied around the corner that is NOT moving.
    local bounds = frame._resizeBounds
    if bounds then
        local minW, minH, maxW, maxH = bounds[1], bounds[2], bounds[3], bounds[4]
        local cw, ch = nw, nh
        if minW and cw < minW then cw = minW end
        if maxW and maxW > 0 and cw > maxW then cw = maxW end
        if minH and ch < minH then ch = minH end
        if maxH and maxH > 0 and ch > maxH then ch = maxH end
        if cw ~= nw then
            if corner:find("RIGHT") then nw = cw else nl, nw = l + w - cw, cw end
        end
        if ch ~= nh then
            if corner:find("TOP") then nh = ch else nb, nh = b + h - ch, ch end
        end
    end
    frame._left, frame._bottom = nl, nb
    -- AND RE-ANCHOR, because the client's sizing loop really does move the
    -- frame: dragging a LEFT or BOTTOM corner changes the rect's ORIGIN, not
    -- only its size. Writing _left/_bottom alone is invisible to any frame that
    -- resolves its rect through SetPoint (which the chassis does), and that
    -- kindness would hide exactly the half of the gesture — the two corners
    -- that move the box — this model exists to test.
    local P = _G.UIParent
    if P then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", nl, nb)
    end
    frame:SetSize(nw, nh)
    return nw, nh
end

-- Where the DRAGGED corner sits right now, in SCREEN PIXELS — the coordinate
-- space a test can compare against the cursor without converting anything.
function Sim.SizingCornerScreen(frame)
    if type(frame) ~= "table" then return nil end
    local corner = tostring(frame._sizing or "BOTTOMRIGHT"):upper()
    local l, b, w, h = resolveRect(frame)
    if l == nil then l, b, w, h = frame._left, frame._bottom, frame._w or 0, frame._h or 0 end
    if l == nil then return nil end
    local fs = frame:GetEffectiveScale()
    local x = (corner:find("RIGHT") and (l + (w or 0)) or l) * fs
    local y = (corner:find("TOP")   and (b + (h or 0)) or b) * fs
    return x, y
end

-- ── THE CLIENT'S CLAMP *ENFORCEMENT* (w2/bounce sim extension) ───────────────
-- A programmatic SetPoint is not clamped AT THE MOMENT OF THE CALL — which is
-- what makes flush placement possible at all — but the frame is clamped again
-- the next time the CLIENT lays it out. So a window placed (or dragged) flush
-- against the edge is shoved back inside on the very next client beat unless
-- the clamp insets have actually been zeroed. THIS IS "IT BOUNCES BACK",
-- modeled: an addon that zeroes the insets once and never re-asserts them
-- against the client's own re-clamp will watch the owner's window walk inward.
-- Returns true when the frame was actually moved (a test can count the shoves).
function Sim.EnforceClamp(frame)
    if type(frame) ~= "table" then return false end
    if frame._left == nil or frame._bottom == nil then return false end
    if type(frame.IsClampedToScreen) ~= "function" or not frame:IsClampedToScreen() then
        return false
    end
    local minL, maxL, minB, maxB = clampBounds(frame)
    local l, b = frame._left, frame._bottom
    if l < minL then l = minL elseif l > maxL then l = maxL end
    if b < minB then b = minB elseif b > maxB then b = maxB end
    if l == frame._left and b == frame._bottom then return false end
    record("clamp:shove")
    Sim.clampShoves = (Sim.clampShoves or 0) + 1
    frame._left, frame._bottom = l, b
    return true
end

-- The client's own LAYOUT PASS: everything marked dirty by a clamp rewrite is
-- resolved here, after the Lua that dirtied it has returned. A test calls this
-- to ask "and then the client laid the frame out — is it still where I put it?"
-- Returns how many frames were actually shoved.
function Sim.LayoutBeat()
    local n = 0
    local function beat(f)
        if type(f) == "table" and f._clampDirty then
            f._clampDirty = nil
            if Sim.EnforceClamp(f) then n = n + 1 end
        end
    end
    for id = 1, _G.NUM_CHAT_WINDOWS do beat(Sim.Frame(id)) end
    for _, f in ipairs(Sim.tempFrames or {}) do beat(f) end
    return n
end

-- How many FontStrings in the world are FACELESS right now (and therefore
-- measure 0). Published so a test can pin that a layout survived exactly that.
function Sim.FacelessStrings()
    local n = 0
    for _, w in ipairs(Sim._fontStrings) do
        if not (w._font or w._fontObject) then n = n + 1 end
    end
    return n
end
-- Chat-frame display knobs (recorded; the skin fading tests read these).
function WIDGET_API.SetFading(self, on) record("SetFading") self._fading = on and true or false end
function WIDGET_API.SetTimeVisible(self, secs) record("SetTimeVisible") self._timeVisible = secs end
function WIDGET_API.SetMaxLines(self, n) self._maxLines = n end
-- skin-v2 sim extension (additive): RECORDED, so a test can pin that a button
-- really invoked the client's own scroll verb and nothing else.
function WIDGET_API.ScrollToBottom(self) record("ScrollToBottom") end
function WIDGET_API.ScrollUp(self) end
function WIDGET_API.ScrollDown(self) end
function WIDGET_API.AtBottom(self) return true end
function WIDGET_API.ResetAllFadeTimes(self) end
function WIDGET_API.GetID(self) return self._id or 0 end

widgetMeta = {
    __index = function(self, k)
        local fn = WIDGET_API[k]
        if fn then return fn end
        -- Auto-vivified recorded no-op for unmodeled METHODS only (WoW widget
        -- methods are PascalCase): never crashes, never silent — the call
        -- lands in Sim.calls and _unknownCalls. DATA fields (lowercase or
        -- _prefixed: isTemporary, chatType, historyBuffer, _alpha, ...) stay
        -- honestly nil when unset — a truthy auto-stub there would make every
        -- `if frame.isTemporary` read wrong on every widget.
        if type(k) == "string" and k:match("^[A-Z]") then
            return function(w, ...)
                record("widget:" .. tostring(k))
                if type(w) == "table" and type(w._unknownCalls) == "table" then
                    w._unknownCalls[#w._unknownCalls + 1] = k
                end
            end
        end
        return nil
    end,
}

-- ── THE CREATABLE ScrollingMessageFrame (D2/view sim extension) ──────────────
-- Until the view existed, the ONLY message-bearing frames in this sim were the
-- client's own ten, built by makeChatFrame. An addon that creates its OWN
-- ScrollingMessageFrame therefore got a bare widget whose AddMessage was an
-- auto-vivified no-op — and a mirror into a no-op looks exactly like a mirror
-- that works. An absent API is a kinder client (Class 9's secondary blind spot,
-- named), so CreateFrame("ScrollingMessageFrame", ...) now hands back a REAL
-- buffer-backed frame: same ring buffer, same wrapped fields, same
-- AddMessage / GetNumMessages / GetMessageInfo / Clear semantics as a client
-- window's.
--
-- AND THE UNKIND HALF: every frame created this way is recorded in
-- Sim.createdSMFs, and NOTHING in this file's client machinery ever walks that
-- list. The client's fade beat, its re-clamp, its button-side decision and its
-- window update all iterate ChatFrame1..NUM_CHAT_WINDOWS plus Sim.tempFrames —
-- the frames the CLIENT knows about. That is the point: a test can run every
-- client beat there is and assert that an addon-created frame did not move,
-- which is a structural claim rather than a pinning contest.
local attachMessageSurface   -- forward declaration (the buffer lives below)

Sim.createdSMFs = {}

_G.CreateFrame = function(kind, name, parent, template)
    record("CreateFrame")
    local w = newWidget(kind or "Frame", name, parent or _G.UIParent)
    w._template = template
    if kind == "ScrollingMessageFrame" and attachMessageSurface then
        attachMessageSurface(w)
        Sim.createdSMFs[#Sim.createdSMFs + 1] = w
    end
    return w
end
_G.CreateFont = function(name)
    record("CreateFont")
    return newWidget("Font", name, nil)
end

----------------------------------------------------------------------
-- Event delivery. Frames register per-event (widget RegisterEvent above);
-- dispatch walks them in registration order and calls their OnEvent script.
----------------------------------------------------------------------

Sim._eventTargets = {}   -- event -> ordered widget list

local function dispatchEvent(event, ...)
    local list = Sim._eventTargets[event]
    if not list then return end
    local snap = {}
    for i = 1, #list do snap[i] = list[i] end
    for i = 1, #snap do
        local fn = snap[i]._scripts and snap[i]._scripts.OnEvent
        if fn then
            local ok, err = pcall(fn, snap[i], event, ...)
            if not ok then print("  !! sim event handler error (" .. event .. "): " .. tostring(err)) end
        end
    end
end
Sim.DispatchEvent = dispatchEvent

----------------------------------------------------------------------
-- The per-frame PUBLIC ring buffer (game-facts register §7.1):
-- entries { message, r, g, b, timestamp } with UPTIME timestamps, mutable in
-- place, GetEntryAtIndex(1) = NEWEST. headIndex/maxElements default to the
-- wrapped { value = n } shape (see the unkindness list up top).
----------------------------------------------------------------------

local function newBuffer(cap)
    local buf = { list = {} }
    local wrapped = Sim.opts.wrappedBufferFields
    if wrapped then
        buf.headIndex   = { value = 0 }
        buf.maxElements = { value = cap }
    else
        buf.headIndex   = 0
        buf.maxElements = cap
    end
    local function maxN()
        local m = buf.maxElements
        return type(m) == "table" and m.value or m
    end
    local function bumpHead()
        if type(buf.headIndex) == "table" then buf.headIndex.value = buf.headIndex.value + 1
        else buf.headIndex = buf.headIndex + 1 end
    end
    function buf:PushBack(entry)
        record("historyBuffer.PushBack")
        self.list[#self.list + 1] = entry
        while #self.list > maxN() do table.remove(self.list, 1) end
        bumpHead()
        return true
    end
    function buf:PushFront(entry)
        record("historyBuffer.PushFront")
        table.insert(self.list, 1, entry)
        while #self.list > maxN() do table.remove(self.list) end
        return true
    end
    function buf:GetEntryAtIndex(i)      -- 1 = newest (the Prat-spec fact)
        return self.list[#self.list - i + 1]
    end
    function buf:GetNumElements() return #self.list end
    return buf
end

----------------------------------------------------------------------
-- Chat windows: the 10-window model + temporaries. Two layers, on purpose:
--   Sim.windows[id]  — the client's per-character STORE (GetChatWindowInfo /
--                      SetChatWindow* land here)
--   ChatFrame<id>    — the live frame; FloatingChatFrame_Update projects the
--                      store onto it. Store writes do NOT touch the frame
--                      until poked (the write-then-update reality).
----------------------------------------------------------------------

local STOCK_TEXTURES = {
    "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture",
    "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture",
    "BottomTexture",
}
_G.CHAT_FRAME_TEXTURES = STOCK_TEXTURES
-- ui/mockup-fidelity sim extension (additive): the CLIENT's own TAB dress.
-- Era's chat tab is a three-slice button with selected and highlight sets, all
-- global-named $parentTab<suffix>. The addon never stripped these, which is why
-- the shipped one box still wore the client's filled tab art — so the sim has
-- to have them for "the box strips them" to be an assertion rather than a claim.
local TAB_TEXTURES = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
}
_G.NUM_CHAT_WINDOWS = 10
_G.MAX_WOW_CHAT_CHANNELS = 20

local DEFAULT_BUFFER_CAP = 128

local function chatAddMessage(self, text, r, g, b)
    record("AddMessage")
    self.historyBuffer:PushBack({
        message = text, r = r or 1, g = g or 1, b = b or 1,
        timestamp = Sim.Uptime(),
    })
end
local function chatGetNumMessages(self)
    record("GetNumMessages")
    return #self.historyBuffer.list
end
local function chatGetMessageInfo(self, i)   -- 1 = OLDEST (display order)
    record("GetMessageInfo")
    local e = self.historyBuffer.list[i]
    if not e then return nil end
    return e.message, e.r, e.g, e.b
end
local function chatClear(self)
    record("Clear")
    self.historyBuffer.list = {}
end

-- The message surface a ScrollingMessageFrame carries, whether the CLIENT built
-- it (makeChatFrame below) or an ADDON did (the CreateFrame branch above). One
-- implementation, so an addon's own frame cannot accidentally be a kinder one.
attachMessageSurface = function(f, cap)
    f.historyBuffer  = newBuffer(cap or DEFAULT_BUFFER_CAP)
    f.AddMessage     = chatAddMessage
    f.GetNumMessages = chatGetNumMessages
    f.GetMessageInfo = chatGetMessageInfo
    f.Clear          = chatClear
    -- An addon-created frame inherits the CLIENT's own default posture: fading
    -- ON. A view that wants it off has to actually say so, at creation, and the
    -- suite can tell the difference between "off because we asked" and "off
    -- because the sim never turned it on".
    f._fading, f._timeVisible = true, 120
    return f
end

local function makeChatFrame(id)
    local name = "ChatFrame" .. id
    local f = newWidget("ScrollingMessageFrame", name, _G.UIParent)
    f._id = id
    f._font = { "Fonts\\FRIZQT__.TTF", 14, "" }
    f._fading, f._timeVisible = true, 120
    -- w2/move sim extension: a chat frame has real geometry (the client's
    -- stock 430x120 parked near the bottom-left corner) and a live mouse, so
    -- drag, clamp and scale reads all answer honestly.
    f._w, f._h = 430, 120
    f._left, f._bottom = 32, 32
    f._mouse = true
    attachMessageSurface(f, DEFAULT_BUFFER_CAP)
    f._fading, f._timeVisible = true, 120
    -- Stock dress textures, global-named like the client's.
    for _, suffix in ipairs(STOCK_TEXTURES) do
        newWidget("Texture", name .. suffix, f)
    end
    -- ── THE TAB IS NOT THE WINDOW'S CHILD (view/align sim extension) ─────────
    -- THE FACT THE STRAY-TAB DEFECT WAS MADE OF, modeled at last: on 11509 a
    -- chat window's tab is a SEPARATE frame parented to the DOCK (or to
    -- UIParent when the window is undocked), never to the window. So
    -- `frame:Hide()` does not take the tab down with it, and an addon that
    -- hides the window and expects the tab to follow leaves a stock, gold-
    -- bordered tab floating over whatever it drew instead. The old sim parented
    -- the tab to the frame; sim Hide has never cascaded, so the sim happened to
    -- behave right for the wrong reason — and, crucially, NOTHING in the client
    -- model ever put the tab BACK, which is the half that actually escaped.
    local tab = newWidget("Button", name .. "Tab", _G.GeneralDockManager or _G.UIParent)
    tab._chatFrame = f
    f.tab = tab                              -- the field shape the client also carries
    tab.Text = newWidget("FontString", name .. "TabText", tab)
    tab.Text._text = name .. "Tab"          -- a real label, so tab WIDTH is measurable
    tab.Text._font = { "Fonts\\FRIZQT__.TTF", 12, "" }   -- …and a REAL face, like the client's
    tab._w, tab._h = 60, 24
    tab._mouse = true
    for _, suffix in ipairs(TAB_TEXTURES) do
        newWidget("Texture", name .. "Tab" .. suffix, tab)
    end
    -- The alert flash + glow that ride the tab (FCF_FlashTab / FCF_StartAlertFlash
    -- are catalog-verified on 11509). Separate regions, and the flash is SHOWN by
    -- the client on an alert whether or not anybody hid the window.
    tab.flash = newWidget("Texture", name .. "TabFlash", tab)
    tab.flash._shown = false
    tab.glow = newWidget("Texture", name .. "TabGlow", tab)
    tab.glow._shown = false
    -- w2/button-column sim extension: the CHAT BUTTON FRAME — the little
    -- chat-menu + scroll-button column hanging off the window's edge. Modeled
    -- in BOTH client shapes (the frame's own `buttonFrame` field, which is the
    -- Room-1 register's name for it, and the $parentButtonFrame global) and
    -- SHOWN by default, with real geometry of its own so the drag footprint and
    -- any bounding-box mistake are both visible to a test.
    local bf = newWidget("Frame", name .. "ButtonFrame", f)
    bf._w, bf._h = Sim.BUTTON_FRAME_WIDTH, f._h
    bf._left, bf._bottom = f._left - bf._w, f._bottom
    bf._shown = true
    f.buttonFrame = bf
    f._buttonSide = "left"
    -- The column's own buttons carry REAL rects inside it (stacked from the
    -- column's top), so a pointer test can ask about a BUTTON rather than only
    -- about the strip it sits in — the hitbox question is asked of the thing
    -- that actually holds the hitbox.
    for i, suffix in ipairs({ "UpButton", "DownButton", "BottomButton" }) do
        local b = newWidget("Button", name .. "ButtonFrame" .. suffix, bf)
        b._w, b._h = bf._w, 20
        b._left = bf._left
        b._bottom = bf._bottom + bf._h - i * 20
        b._mouse = true
    end
    -- ── THE REST OF THE SATELLITE FAMILY (view/align sim extension) ──────────
    -- Every one of these is its own frame, hanging off the window in the client
    -- and NOT following its Hide. The verbs that prove each one exists on 11509
    -- are named beside it (all catalog-verified globals).
    --   FCF_MinimizeFrame / FCF_MaximizeFrame / FCF_CreateMinimizedFrame
    local minB = newWidget("Button", name .. "ButtonFrameMinimizeButton", bf)
    minB._w, minB._h, minB._mouse = 20, 20, true
    f.minimizeButton = minB
    --   FCF_UpdateResizeButton
    local rez = newWidget("Button", name .. "ResizeButton", f)
    rez._w, rez._h, rez._mouse = 16, 16, true
    f.resizeButton = rez
    --   FCF_FadeInScrollbar / FCF_FadeOutScrollbar
    local sb = newWidget("Frame", name .. "ScrollBar", f)
    sb._w, sb._h = 8, f._h
    f.ScrollBar = sb
    --   FCFClickAnywhereButton_OnLoad / _UpdateState
    local cab = newWidget("Button", name .. "ClickAnywhereButton", f)
    cab._w, cab._h, cab._mouse = f._w, f._h, true
    f.clickAnywhereButton = cab
    -- Edit box + its stock art regions, parked below the frame like the client.
    local eb = newWidget("EditBox", name .. "EditBox", f)
    eb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -6)
    eb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -6)
    -- skin-v2 sim extension (additive): the sticky-channel HEADER FontString.
    -- Modeled in BOTH client shapes (the `header` field the client's own code
    -- reaches for, and the $parentHeader global the template names) so an addon
    -- that defends either shape is exercised honestly.
    eb.header = newWidget("FontString", name .. "EditBoxHeader", eb)
    -- The client's OWN long-lived strings are born with a face (the unkind
    -- width model above only bites strings an ADDON never gave a font to), so
    -- the header MEASURES — which is what makes the client's inset arithmetic
    -- below, and anything that sizes a chip from this label, honest.
    eb.header:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    eb:SetAttribute("chatType", "SAY")
    eb.chatFrame = f
    -- w2/move sim extension: the client's DEFAULT posture under chatStyle
    -- 'classic' — the edit box (and its prefix) exist but are HIDDEN until
    -- something activates them. A persistent-edit-box feature has to earn the
    -- shown state against this default, never inherit it.
    eb._shown, eb.header._shown = false, false
    eb._mouse = true
    -- w2/button-column sim extension: the bar and its sticky prefix carry REAL
    -- geometry, so a pointer test against the PREFIX REGION (the right-click
    -- seam for the chat menu) is answered honestly instead of by guesswork.
    eb._w, eb._h = f._w, 24
    eb._left, eb._bottom = f._left, f._bottom - 30
    eb.header._left, eb.header._bottom = eb._left + 8, eb._bottom + 5
    eb.header._w, eb.header._h = 40, 14
    -- ── THE STOCK DRESS, IN BOTH CLIENT SHAPES (ui/entry-bar sim extension) ──
    -- The template names every region `$parent<Suffix>` as a GLOBAL; the modern
    -- FrameXML the Era client is rebased on ALSO hangs the focus trio off the
    -- box as parentKey FIELDS, which is the shape the client's own focus
    -- handler reaches through. Both are modeled, and deliberately NOT
    -- symmetrically — an addon that defends only one shape must be caught.
    for _, suffix in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
        local t = newWidget("Texture", name .. "EditBox" .. suffix, eb)
        t._w, t._h = 8, 24
    end
    eb.focusLeft  = _G[name .. "EditBoxFocusLeft"]
    eb.focusMid   = _G[name .. "EditBoxFocusMid"]
    eb.focusRight = _G[name .. "EditBoxFocusRight"]
    -- …and they start HIDDEN, exactly as the template declares them: the focus
    -- art only exists while the box has focus.
    eb.focusLeft:Hide(); eb.focusMid:Hide(); eb.focusRight:Hide()
    return f
end

local function defaultWindows()
    local W = {}
    W[1] = { name = "General", fontSize = 14, r = 0, g = 0, b = 0, alpha = 0.25,
             shown = true, locked = true, docked = 1, uninteractable = false,
             groups = { "SAY", "YELL", "EMOTE", "GUILD", "OFFICER", "WHISPER",
                        "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
                        "RAID_WARNING", "SYSTEM", "CHANNEL" },
             channels = { "General" }, dim = { 430, 120 }, pos = { "BOTTOMLEFT", 32, 32 } }
    W[2] = { name = "Combat Log", fontSize = 14, r = 0, g = 0, b = 0, alpha = 0.25,
             shown = true, locked = true, docked = 2, uninteractable = false,
             groups = {}, channels = {}, dim = { 430, 120 }, pos = { "BOTTOMLEFT", 32, 32 } }
    for i = 3, _G.NUM_CHAT_WINDOWS do
        W[i] = { name = "", fontSize = 14, r = 0, g = 0, b = 0, alpha = 0.25,
                 shown = false, locked = false, docked = false, uninteractable = false,
                 groups = {}, channels = {}, dim = { 430, 120 }, pos = { "BOTTOMLEFT", 32, 32 } }
    end
    return W
end

function Sim.Frame(id) return _G["ChatFrame" .. id] end

-- ── THE SCREEN (w2/move sim extension) ───────────────────────────────────────
-- UIParent covers the physical screen: its own-unit size is the pixel size
-- divided by its scale, exactly like the client. Sim.SetUIScale models the
-- per-account uiScale difference the cross-account position work exists to
-- make irrelevant — the PIXEL screen never changes, the UNIT screen does.
Sim.screenPixels = { 1920, 1080 }
Sim.uiScale      = 0.65            -- the owner's shared Config.wtf value

-- Build the world once at load.
_G.UIParent = newWidget("Frame", "UIParent", nil)
_G.UIParent._left, _G.UIParent._bottom = 0, 0

function Sim.SetUIScale(s)
    s = tonumber(s) or 1
    if s <= 0 then s = 1 end
    Sim.uiScale = s
    _G.UIParent._scale = s
    _G.UIParent._w = Sim.screenPixels[1] / s
    _G.UIParent._h = Sim.screenPixels[2] / s
end
Sim.SetUIScale(Sim.uiScale)

_G.GetScreenWidth  = function() return _G.UIParent:GetWidth() end
_G.GetScreenHeight = function() return _G.UIParent:GetHeight() end

-- ── THE POINTER (w2/button-column sim extension) ─────────────────────────────
-- GetCursorPosition answers in PIXELS (the client's own convention): code that
-- compares it with a widget edge must divide by that widget's effective scale
-- first, and the sim's non-1 uiScale makes forgetting that a test failure.
Sim.cursor = { 0, 0 }
function Sim.SetCursorAt(widget, dx, dy)
    local scale = (type(widget) == "table" and type(widget.GetEffectiveScale) == "function")
        and widget:GetEffectiveScale() or 1
    local x = ((widget and widget._left or 0) + (tonumber(dx) or 0)) * scale
    local y = ((widget and widget._bottom or 0) + (tonumber(dy) or 0)) * scale
    Sim.cursor = { x, y }
    return x, y
end
_G.GetCursorPosition = function()
    record("GetCursorPosition")
    return Sim.cursor[1], Sim.cursor[2]
end

-- Modifier state (the ALT-drag gesture's gate).
Sim.altDown = false
_G.IsAltKeyDown     = function() record("IsAltKeyDown") return Sim.altDown and true or false end
_G.IsShiftKeyDown   = function() return Sim.shiftDown and true or false end
_G.IsControlKeyDown = function() return Sim.ctrlDown and true or false end

Sim.windows = defaultWindows()
-- THE DOCK IS A REAL FRAME, and it exists BEFORE the windows do — because a
-- docked window's TAB is parented to IT, not to the window (see makeChatFrame).
-- Modeled as a widget rather than a plain table so the tab family has somewhere
-- honest to hang and a test can ask where the dock bar actually sits.
_G.GeneralDockManager = newWidget("Frame", "GeneralDockManager", _G.UIParent)
_G.CHAT_FRAMES = {}
for i = 1, _G.NUM_CHAT_WINDOWS do
    makeChatFrame(i)
    _G.CHAT_FRAMES[i] = "ChatFrame" .. i
end
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1
_G.GeneralDockManager.primary  = _G.ChatFrame1
_G.GeneralDockManager.selected = _G.ChatFrame1
_G.GeneralDockManager.DOCKED_CHAT_FRAMES = { _G.ChatFrame1, _G.ChatFrame2 }

-- ── THE CLIENT'S CHAT MENU (w2/button-column sim extension) ──────────────────
-- The one verb the button column offers that nothing else replicates:
-- languages, emotes, whisper targets. The client's menu is a FRAME toggled by
-- the column's menu button; ToggleFrame is the catalog-verified (11509) call
-- that does it, and the button is modeled with the OnClick that performs it, so
-- an addon can reach the verb through EITHER shape and a test can pin which.
-- (ChatFrame_ToggleMenu does NOT exist on 11509 — the catalog says so — which
-- is exactly why the seam has to be resolved at runtime, never assumed.)
_G.ChatMenu = newWidget("Frame", "ChatMenu", _G.UIParent)
_G.ChatMenu._shown = false
_G.ToggleFrame = function(frame)
    record("ToggleFrame")
    if type(frame) ~= "table" then return end
    if frame._shown then frame:Hide() else frame:Show() end
end
_G.ChatFrameMenuButton = newWidget("Button", "ChatFrameMenuButton",
    _G.ChatFrame1.buttonFrame)
_G.ChatFrameMenuButton:SetScript("OnClick", function()
    _G.ToggleFrame(_G.ChatMenu)
end)

----------------------------------------------------------------------
-- The per-character store API (GetChatWindowInfo family + FCF conveniences).
----------------------------------------------------------------------

local function W(id) return Sim.windows[id] end

_G.GetChatWindowInfo = function(id)
    record("GetChatWindowInfo")
    local w = W(id)
    if not w then return end
    return w.name, w.fontSize, w.r, w.g, w.b, w.alpha, w.shown, w.locked,
           w.docked, w.uninteractable
end
_G.FCF_GetChatWindowInfo = _G.GetChatWindowInfo
_G.GetChatWindowMessages = function(id)
    record("GetChatWindowMessages")
    local w = W(id)
    if not w then return end
    return unpack(w.groups)
end
_G.GetChatWindowChannels = function(id)
    record("GetChatWindowChannels")
    local w = W(id)
    if not w then return end
    local flat = {}
    for _, name in ipairs(w.channels) do
        flat[#flat + 1] = name
        flat[#flat + 1] = 0        -- zoneID (0 = user channel)
    end
    return unpack(flat)
end
_G.GetChatWindowSavedDimensions = function(id)
    record("GetChatWindowSavedDimensions")
    local w = W(id); if not w then return end
    return w.dim[1], w.dim[2]
end
_G.GetChatWindowSavedPosition = function(id)
    record("GetChatWindowSavedPosition")
    local w = W(id); if not w then return end
    return w.pos[1], w.pos[2], w.pos[3]
end

-- Store writers: land in Sim.windows ONLY. The frame does not change until
-- FloatingChatFrame_Update / FCF_DockUpdate pokes it (two-layer reality).
local function storeWriter(field)
    return function(id, v)
        record("SetChatWindow" .. field)
        local w = W(id); if w then w[field:lower()] = v end
    end
end
_G.SetChatWindowName   = storeWriter("Name")
_G.SetChatWindowSize   = function(id, size) record("SetChatWindowSize")
    local w = W(id); if w then w.fontSize = size end end
_G.SetChatWindowColor  = function(id, r, g, b) record("SetChatWindowColor")
    local w = W(id); if w then w.r, w.g, w.b = r, g, b end end
_G.SetChatWindowAlpha  = function(id, a) record("SetChatWindowAlpha")
    local w = W(id); if w then w.alpha = a end end
_G.SetChatWindowShown  = function(id, v) record("SetChatWindowShown")
    local w = W(id); if w then w.shown = v and true or false end end
_G.SetChatWindowLocked = storeWriter("Locked")
_G.SetChatWindowDocked = storeWriter("Docked")
_G.SetChatWindowUninteractable = storeWriter("Uninteractable")
_G.SetChatWindowSavedDimensions = function(id, w_, h)
    record("SetChatWindowSavedDimensions")
    local w = W(id); if w then w.dim = { w_, h } end
end
_G.SetChatWindowSavedPosition = function(id, point, x, y)
    record("SetChatWindowSavedPosition")
    local w = W(id); if w then w.pos = { point, x, y } end
end

-- ── THE BUTTON COLUMN'S SIDE (w2/button-column sim extension) ────────────────
-- The three catalog-verified calls (11509) plus the client's own rule as the
-- owner's two accounts demonstrate it: a window sitting against the LEFT edge
-- has no room for its column there, so the column flips to the RIGHT; anywhere
-- else it sits on the left. EVERY side update RE-SHOWS the column — that is the
-- posture an addon that hides it has to keep beating.
_G.FCF_GetButtonSide = function(frame)
    record("FCF_GetButtonSide")
    if type(frame) ~= "table" then return nil end
    return frame._buttonSide
end
_G.FCF_SetButtonSide = function(frame, side, forceUpdate)
    record("FCF_SetButtonSide")
    if type(frame) ~= "table" then return nil end
    local bf = frame.buttonFrame
    frame._buttonSide = (side == "right") and "right" or "left"
    if type(bf) == "table" then
        bf._bottom = frame._bottom
        bf._left = (frame._buttonSide == "right")
            and ((frame._left or 0) + (frame._w or 0))
            or  ((frame._left or 0) - (bf._w or 0))
        -- The column's buttons travel with it (they are anchored to it in the
        -- client; the sim keeps their rects coherent so a pointer test is honest).
        local i = 0
        for _, kid in ipairs(bf._children or {}) do
            if kid._kind == "Button" and kid._w then
                i = i + 1
                kid._left = bf._left
                kid._bottom = bf._bottom + (bf._h or 0) - i * (kid._h or 20)
            end
        end
        bf:Show()                       -- THE RE-SHOW
    end
    -- ── THE RE-CLAMP (w2/bounce sim extension) ───────────────────────────────
    -- The column's width has to stay on screen, so the client reserves it in
    -- the window's CLAMP RECT — and it rewrites those insets every time it
    -- re-decides the side. An addon that zeroed them once gets them back here,
    -- unasked, on a beat it did not choose. Same provenance posture as the
    -- re-show above: the CALL is catalog-verified on 11509, the reservation is
    -- modeled from the owner's symptom (the window refuses the last stretch to
    -- the edge, and walks back inward after it is placed there).
    --
    -- ENFORCEMENT IS DEFERRED, DELIBERATELY AND FAITHFULLY: SetClampRectInsets
    -- only stores numbers. The frame is clamped when the client next RESOLVES
    -- its position, i.e. after the Lua call stack unwinds — which is precisely
    -- why an in-call post-hook that re-zeroes the insets preempts the shove,
    -- and why one that arrives a beat late does not. Marking here and shoving
    -- in Sim.LayoutBeat models that gap honestly instead of collapsing it.
    frame._clampInsets = { Sim.STOCK_CLAMP_INSETS[1], Sim.STOCK_CLAMP_INSETS[2],
                           Sim.STOCK_CLAMP_INSETS[3], Sim.STOCK_CLAMP_INSETS[4] }
    frame._clampDirty = true
    return frame._buttonSide
end
_G.FCF_UpdateButtonSide = function(frame)
    record("FCF_UpdateButtonSide")
    if type(frame) ~= "table" then return nil end
    local width = (type(frame.buttonFrame) == "table" and frame.buttonFrame._w)
        or Sim.BUTTON_FRAME_WIDTH
    local side = ((frame._left or 0) < width) and "right" or "left"
    return _G.FCF_SetButtonSide(frame, side)
end

-- ── THE SATELLITE FAMILY, PUBLISHED (view/align sim extension) ───────────────
-- Everything that hangs off ONE chat window and does NOT follow its Hide. The
-- roster is data so a test can walk it rather than re-typing a list that will
-- drift, and so "the addon hides the COMPLETE set" is an assertion instead of a
-- claim. Each entry names the field the client carries and the global name the
-- template gives it; either shape may be the one an addon reaches through.
Sim.SATELLITES = {
    { field = "tab",                 global = "%sTab" },
    { field = "editBox",             global = "%sEditBox" },
    { field = "buttonFrame",         global = "%sButtonFrame" },
    { field = "minimizeButton",      global = "%sButtonFrameMinimizeButton" },
    { field = "minFrame",            global = nil },   -- FCF_CreateMinimizedFrame
    { field = "resizeButton",        global = "%sResizeButton" },
    { field = "ScrollBar",           global = "%sScrollBar" },
    { field = "clickAnywhereButton", global = "%sClickAnywhereButton" },
}

-- Every satellite widget of one window that currently EXISTS, in roster order.
function Sim.SatellitesOf(frame)
    local out = {}
    if type(frame) ~= "table" then return out end
    local name = frame._name or ""
    for _, s in ipairs(Sim.SATELLITES) do
        local w = s.field and frame[s.field] or nil
        if type(w) ~= "table" and s.global then w = _G[s.global:format(name)] end
        if type(w) == "table" then out[#out + 1] = w end
    end
    return out
end

-- The ones still SHOWN. The whole stray-tab question, asked in one call.
function Sim.ShownSatellites(frame)
    local out = {}
    for _, w in ipairs(Sim.SatellitesOf(frame)) do
        if w._shown then out[#out + 1] = w._name or w._kind end
    end
    return out
end

-- ── THE DOCK BAR, AND THE CLIENT PUTTING ITS TABS BACK ───────────────────────
-- Where a tab actually SITS: docked tabs run left-to-right along the bar that
-- hugs the dock primary's TOP edge; an undocked window's tab hugs its own. This
-- geometry is the reason the escaped tab lands MID-PANEL over a view whose
-- chassis extends above the engine window it rides.
--
-- UNKIND, and the half that made the defect: EVERY dock/window beat SHOWS the
-- tabs again. The store says the window is shown (an addon that hides display
-- never touches routing), so the client keeps re-asserting its dress. Hiding a
-- tab once is not a fix; holding the last word is — exactly like the clamp, the
-- button column and the tab alpha before it.
Sim.DOCK_TAB_H = 24
Sim.tabReShows = 0

local function tabRunFor(id)
    local w = W(id)
    if not w then return nil end
    return (w.docked and w.docked ~= 0) and true or false
end

function Sim.LayoutDockTabs()
    local primary = _G.GeneralDockManager and _G.GeneralDockManager.primary
    local pl = (type(primary) == "table") and primary._left or 0
    local pb = (type(primary) == "table") and primary._bottom or 0
    local ph = (type(primary) == "table") and (primary._h or 0) or 0
    local dockL, dockB = pl or 0, (pb or 0) + ph
    _G.GeneralDockManager._left, _G.GeneralDockManager._bottom = dockL, dockB
    _G.GeneralDockManager._w = (type(primary) == "table") and (primary._w or 0) or 0
    _G.GeneralDockManager._h = Sim.DOCK_TAB_H
    local run = dockL
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local f, w = Sim.Frame(id), W(id)
        local tab = f and f.tab
        if tab and w then
            if tabRunFor(id) then
                tab._left, tab._bottom = run, dockB
                run = run + (tab._w or 60)
            else
                tab._left = f._left or 0
                tab._bottom = (f._bottom or 0) + (f._h or 0)
            end
        end
    end
end

-- The client's own tab beat (FCFDock_UpdateTabs is catalog-verified on 11509).
-- It lays the run out and SHOWS every tab whose window the STORE says is live.
_G.FCFDock_UpdateTabs = function()
    record("FCFDock_UpdateTabs")
    Sim.LayoutDockTabs()
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local f, w = Sim.Frame(id), W(id)
        if f and f.tab and w and ((w.shown and w.shown ~= 0) or (w.docked and w.docked ~= 0)) then
            if not f.tab._shown then Sim.tabReShows = Sim.tabReShows + 1 end
            f.tab:Show()
        end
    end
end

_G.FCF_FlashTab = function(frame)
    record("FCF_FlashTab")
    if type(frame) == "table" and type(frame.tab) == "table" and frame.tab.flash then
        frame.tab.flash:Show()
    end
end

-- FCF_CreateMinimizedFrame / FCF_MinimizeFrame / FCF_MaximizeFrame: the
-- minimized stand-in is created LAZILY, which is why an addon that enumerated
-- the family once at enable and never again can still be surprised by it.
_G.FCF_CreateMinimizedFrame = function(frame)
    record("FCF_CreateMinimizedFrame")
    if type(frame) ~= "table" then return nil end
    if type(frame.minFrame) == "table" then return frame.minFrame end
    local mf = newWidget("Frame", (frame._name or "ChatFrame") .. "MinFrame", _G.UIParent)
    mf._w, mf._h, mf._mouse = 120, 24, true
    mf._left, mf._bottom = frame._left or 0, frame._bottom or 0
    frame.minFrame = mf
    return mf
end
_G.FCF_MinimizeFrame = function(frame)
    record("FCF_MinimizeFrame")
    local mf = _G.FCF_CreateMinimizedFrame(frame)
    if mf then mf:Show() end
    return mf
end
_G.FCF_MaximizeFrame = function(frame)
    record("FCF_MaximizeFrame")
    if type(frame) == "table" and type(frame.minFrame) == "table" then frame.minFrame:Hide() end
end

_G.FloatingChatFrame_Update = function(id)
    record("FloatingChatFrame_Update")
    local w, f = W(id), Sim.Frame(id)
    if not (w and f) then return end
    f._projectedName = w.name
    f._shown = w.shown and true or false
    -- THE CLIENT'S OWN RESTORE BEAT (w2/bounce sim extension): the window
    -- update re-places the frame FROM THE PER-CHARACTER STORE. Any move the
    -- store never learned about — an addon's own StartMoving/StopMovingOrSizing
    -- drag, say — is undone right here, by the client, without asking. That is
    -- the second half of "it bounces back".
    if type(_G.FCF_RestorePositionAndDimensions) == "function" then
        _G.FCF_RestorePositionAndDimensions(f)
    end
    -- The client re-evaluates the button side (and re-shows the column) on its
    -- own window-update beat.
    _G.FCF_UpdateButtonSide(f)
    -- …and re-decides the tab's alpha on the same beat.
    if type(_G.FCFTab_UpdateAlpha) == "function" then _G.FCFTab_UpdateAlpha(f) end
    -- THE TAB RE-SHOW (view/align sim extension): the window update projects the
    -- STORE onto the window's dress, and the tab is dress. The store still says
    -- "shown" — hiding a frame is a display act — so the tab comes straight back
    -- on a beat nobody asked for.
    if f.tab and ((w.shown and w.shown ~= 0) or (w.docked and w.docked ~= 0)) then
        if not f.tab._shown then Sim.tabReShows = Sim.tabReShows + 1 end
        f.tab:Show()
        Sim.LayoutDockTabs()
    end
end
_G.FCF_DockUpdate = function()
    record("FCF_DockUpdate")
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local f = Sim.Frame(id)
        if f then _G.FCF_UpdateButtonSide(f) end
    end
    _G.FCFDock_UpdateTabs()
end

_G.FCF_SetWindowName = function(frame, name)
    record("FCF_SetWindowName")
    local w = W(frame._id)
    if w then w.name = name end
    frame._projectedName = name
end
_G.FCF_SetChatWindowFontSize = function(menu, frame, size)
    record("FCF_SetChatWindowFontSize")
    local w = W(frame._id)
    if w then w.fontSize = size end
    local face = frame._font and frame._font[1] or "Fonts\\FRIZQT__.TTF"
    frame._font = { face, size, frame._font and frame._font[3] or "" }
end
_G.FCF_SetWindowColor = function(frame, r, g, b)
    record("FCF_SetWindowColor")
    local w = W(frame._id); if w then w.r, w.g, w.b = r, g, b end
end
_G.FCF_SetWindowAlpha = function(frame, a)
    record("FCF_SetWindowAlpha")
    local w = W(frame._id); if w then w.alpha = a end
end
_G.FCF_OpenNewWindow = function(name)
    record("FCF_OpenNewWindow")
    for id = 3, _G.NUM_CHAT_WINDOWS do
        local w = W(id)
        if w and not w.shown and not w.docked then
            w.name, w.shown, w.docked = name or "New Window", true, id
            local f = Sim.Frame(id)
            f._shown = true
            return f, id
        end
    end
end
_G.FCF_OpenTemporaryWindow = function(chatType, target)
    record("FCF_OpenTemporaryWindow")
    local id = _G.NUM_CHAT_WINDOWS + #Sim.tempFrames + 1
    local f = makeChatFrame(id)
    f.isTemporary, f.chatType, f.chatTarget = true, chatType, target
    Sim.tempFrames[#Sim.tempFrames + 1] = f
    return f
end
_G.FCF_Close = function(frame)
    record("FCF_Close")
    if frame then
        frame._shown = false
        local w = W(frame._id)
        if w then w.shown, w.docked = false, false end
    end
end
_G.FCF_DockFrame = function(frame)
    record("FCF_DockFrame")
    local w = W(frame._id); if w then w.docked = frame._id end
end
_G.FCF_UnDockFrame = function(frame)
    record("FCF_UnDockFrame")
    local w = W(frame._id); if w then w.docked = false end
end
_G.FCF_SelectDockFrame = function(frame)
    record("FCF_SelectDockFrame")
    _G.GeneralDockManager.selected = frame
end
_G.FCF_ResetChatWindows = function()
    record("FCF_ResetChatWindows")
    Sim.windows = defaultWindows()
end

-- ── POSITION: SAVE / RESTORE, AND THE NATIVE TAB DRAG ────────────────────────
-- (w2/bounce sim extension.) The three calls are catalog-verified on 11509
-- (FCF_SavePositionAndDimensions, FCF_RestorePositionAndDimensions,
-- FCF_StopDragging, FCFTab_OnDragStop); what is MODELED here is the two-layer
-- reality the addon has to live in:
--   * the frame's LIVE corner and the per-character store's `pos` tuple are
--     two different facts, and only the client's own SAVE verb makes them
--     agree — StartMoving/StopMovingOrSizing writes NOTHING to the store;
--   * the client's RESTORE verb re-places the frame from the store, and it
--     runs on beats the addon never asked for (FloatingChatFrame_Update).
-- So an addon that moves a window without committing it to the store is
-- writing a position with an expiry date. UNKIND BY DEFAULT: restore really
-- moves the frame, and the clamp is enforced right after it.
local function storePosOf(frame)
    local w = W(type(frame) == "table" and frame._id or nil)
    return w and w.pos or nil
end

_G.FCF_SavePositionAndDimensions = function(frame)
    record("FCF_SavePositionAndDimensions")
    local w = W(type(frame) == "table" and frame._id or nil)
    if not (w and frame._left and frame._bottom) then return end
    w.pos = { "BOTTOMLEFT", frame._left, frame._bottom }
    w.dim = { frame._w or w.dim[1], frame._h or w.dim[2] }
end

_G.FCF_RestorePositionAndDimensions = function(frame)
    record("FCF_RestorePositionAndDimensions")
    if type(frame) ~= "table" then return end
    local p = storePosOf(frame)
    if type(p) ~= "table" then return end
    local point, x, y = tostring(p[1]), tonumber(p[2]) or 0, tonumber(p[3]) or 0
    local P = _G.UIParent
    local ratio = P:GetEffectiveScale() / frame:GetEffectiveScale()
    local ph = P:GetHeight() * ratio
    if point == "TOPLEFT" then
        frame._left, frame._bottom = x, ph + y - (frame._h or 0)
    else
        -- BOTTOMLEFT and anything this sim does not model are read as a
        -- bottom-left corner (the client's own default for a chat window).
        frame._left, frame._bottom = x, y
    end
    -- NOT clamped here, deliberately: the client's restore is a SetPoint, and a
    -- SetPoint is not clamped at the moment of the call. The clamp bites on the
    -- client's next layout beat (FCF_SetButtonSide), and keeping the two apart
    -- is what lets a test tell the RESTORE bounce and the RE-CLAMP bounce
    -- apart instead of watching one alibi the other.
end

-- The drop's real work, held as a LOCAL as well as a global. Both bindings
-- exist because the two DROP POSTURES below differ in exactly one thing:
-- whether the client's tab-drop path passes through the GLOBAL names an addon
-- can hook, or does the same work through its own internal references.
local function stopDragging(frame, savePos)
    if type(frame) ~= "table" then return end
    frame._moving = false
    savePos(frame)
    if type(frame.buttonFrame) == "table" and type(_G.FCF_UpdateButtonSide) == "function" then
        _G.FCF_UpdateButtonSide(frame)
    end
end

_G.FCF_StopDragging = function(frame)
    record("FCF_StopDragging")
    stopDragging(frame, _G.FCF_SavePositionAndDimensions)
end

-- THE TWO DROP POSTURES (simulator doctrine: the unkind one is a real variant,
-- not a footnote). A native tab drop ends in FCFTab_OnDragStop either way; what
-- differs is what it calls next.
--
--   "globals" (default): FCFTab_OnDragStop -> the GLOBAL FCF_StopDragging ->
--       the GLOBAL FCF_SavePositionAndDimensions. An addon hooking either of
--       those two already sees the drop.
--   "internal" (UNKIND): the same work, reached through the client's own
--       internal references, so NEITHER global is called and the ONLY named
--       surface the drop touches is FCFTab_OnDragStop itself. The catalog
--       proves all three names exist on 11509; it does not prove which one the
--       drop path terminates in, and a capture layer that bets on the obvious
--       two is a capture layer with a hole. This posture is what makes hooking
--       the ENTRY POINT load-bearing rather than decorative.
Sim.TAB_DROP_POSTURE = "globals"

local savePositionInternal = function(frame)
    -- Deliberately NOT _G.FCF_SavePositionAndDimensions: an internal reference
    -- captured before any addon loaded is not hookable, which is the point.
    local w = Sim.windows[type(frame) == "table" and frame._id or nil]
    if not (w and frame._left and frame._bottom) then return end
    w.pos = { "BOTTOMLEFT", frame._left, frame._bottom }
    w.dim = { frame._w or w.dim[1], frame._h or w.dim[2] }
end

-- The tab's own drag-stop handler: the entry point a NATIVE tab drag actually
-- ends in. It is a separate global from FCF_StopDragging, which is exactly why
-- a capture layer that hooks only the latter can miss a player's move.
_G.FCFTab_OnDragStop = function(tabOrFrame)
    record("FCFTab_OnDragStop")
    local frame = tabOrFrame
    if type(frame) == "table" and frame._kind == "Button" and type(frame.GetParent) == "function" then
        frame = frame:GetParent()
    end
    if type(frame) ~= "table" then return end
    if Sim.TAB_DROP_POSTURE == "internal" then
        stopDragging(frame, savePositionInternal)
    else
        _G.FCF_StopDragging(frame)
    end
end

-- Drive a NATIVE tab drag end to end: the player grabs the tab, drags the
-- window's corner (clamped like any drag) and lets go. Nothing about this path
-- goes through the addon's own OnDragStart/OnDragStop scripts — it is the
-- client's, start to finish — which is the whole point of the leg.
function Sim.TabDragTo(frame, left, bottom, posture)
    if type(frame) ~= "table" then return nil end
    local saved = Sim.TAB_DROP_POSTURE
    if posture then Sim.TAB_DROP_POSTURE = posture end
    frame._movable = true
    frame._moving = true
    local l, b = Sim.DragTo(frame, left, bottom)
    local tab = _G[(frame._name or "") .. "Tab"]
    _G.FCFTab_OnDragStop(tab or frame)
    Sim.TAB_DROP_POSTURE = saved
    return l, b
end
_G.FCF_StartAlertFlash = function() record("FCF_StartAlertFlash") end
_G.FCF_StopAlertFlash = function() record("FCF_StopAlertFlash") end

-- The dock's own add/remove: a tab dropped ONTO the dock (or torn OFF it) is a
-- player-initiated move that never touches FCF_StopDragging's undocked path.
_G.FCFDock_AddChatFrame = function(dock, frame)
    record("FCFDock_AddChatFrame")
    if type(frame) ~= "table" then return end
    local w = W(frame._id); if w then w.docked = frame._id end
end
_G.FCFDock_RemoveChatFrame = function(dock, frame)
    record("FCFDock_RemoveChatFrame")
    if type(frame) ~= "table" then return end
    local w = W(frame._id); if w then w.docked = false end
end

-- ── THE CLIENT'S OWN TAB ALPHA (w2/fade sim extension) ───────────────────────
-- The defect the owner reported ("the tabs still fade when not focused on")
-- lives HERE, and it was invisible headless because the sim had no tab-alpha
-- machinery at all — an absent API is a kinder client (Class 9's secondary
-- blind spot, named).
--
-- The client's model, catalog-verified on 11509 (FCFTab_UpdateAlpha,
-- FCF_FadeInChatFrame, FCF_FadeOutChatFrame, UIFrameFadeRemoveFrame): the TAB
-- carries two alpha fields of its own — `noMouseAlpha` and `mouseOverAlpha` —
-- and the updater picks between them from the pointer state. The fade-out verb
-- rewrites `noMouseAlpha` DOWN and drops the chat frame's own alpha with it.
-- Neither has anything to do with the message-fading knob (SetFading), which
-- is why disabling that never stopped the tabs fading.
--
-- UNKIND: the beat below fades EVERY window the pointer is not over, every
-- time it runs. Pinning alpha once is not a fix; holding the last word is.
Sim.TAB_NO_MOUSE_ALPHA    = 0.4    -- an unfocused tab, faded by the client
Sim.CHATFRAME_FADED_ALPHA = 0.25   -- …and the window that carries it
_G.DEFAULT_CHATFRAME_ALPHA = 1

local function tabOf(chatFrame)
    if type(chatFrame) ~= "table" then return nil end
    return _G[(chatFrame._name or "") .. "Tab"]
end

_G.FCFTab_UpdateAlpha = function(chatFrame)
    record("FCFTab_UpdateAlpha")
    local tab = tabOf(chatFrame)
    if type(tab) ~= "table" then return end
    if tab.mouseOverAlpha == nil then tab.mouseOverAlpha = 1 end
    if tab.noMouseAlpha   == nil then tab.noMouseAlpha   = Sim.TAB_NO_MOUSE_ALPHA end
    tab:SetAlpha(tab._mouseOver and tab.mouseOverAlpha or tab.noMouseAlpha)
end

_G.FCF_FadeOutChatFrame = function(chatFrame)
    record("FCF_FadeOutChatFrame")
    if type(chatFrame) ~= "table" then return end
    local tab = tabOf(chatFrame)
    if type(tab) == "table" then tab.noMouseAlpha = Sim.TAB_NO_MOUSE_ALPHA end
    chatFrame:SetAlpha(Sim.CHATFRAME_FADED_ALPHA)
    _G.FCFTab_UpdateAlpha(chatFrame)
end

_G.FCF_FadeInChatFrame = function(chatFrame)
    record("FCF_FadeInChatFrame")
    if type(chatFrame) ~= "table" then return end
    local tab = tabOf(chatFrame)
    if type(tab) == "table" then tab.noMouseAlpha = 1 end
    chatFrame:SetAlpha(_G.DEFAULT_CHATFRAME_ALPHA)
    _G.FCFTab_UpdateAlpha(chatFrame)
end

_G.UIFrameFadeRemoveFrame = function(frame)
    record("UIFrameFadeRemoveFrame")
    if type(frame) == "table" then frame._fadeInFlight = nil end
end

-- THE UNKIND BEAT: the client's own per-frame fade pass. Nothing schedules it
-- for you — a test calls it to ask "does the addon still own the tab's alpha
-- after the client has had another go at it?"
function Sim.ClientFadeBeat()
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local f = Sim.Frame(id)
        if f and f._shown then _G.FCF_FadeOutChatFrame(f) end
    end
    for _, f in ipairs(Sim.tempFrames or {}) do
        if f._shown then _G.FCF_FadeOutChatFrame(f) end
    end
end
_G.FCF_GetNumActiveChatFrames = function()
    record("FCF_GetNumActiveChatFrames")
    local n = 0
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local w = W(id)
        if w and (w.shown or w.docked) then n = n + 1 end
    end
    return n
end
_G.IsCombatLog = function(frame)
    record("IsCombatLog")
    return frame == _G.ChatFrame2
end
_G.IsBuiltinChatWindow = function(frame)
    record("IsBuiltinChatWindow")
    return frame and frame._id and frame._id <= _G.NUM_CHAT_WINDOWS or false
end

-- Message-group / channel routing per window. NOTE deliberately absent:
-- ChatFrame_AddChannel (not in the 11509 catalog) — use AddChatWindowChannel.
_G.ChatFrame_AddMessageGroup = function(frame, group)
    record("ChatFrame_AddMessageGroup")
    local w = W(frame._id); if not w then return end
    for _, g in ipairs(w.groups) do if g == group then return end end
    w.groups[#w.groups + 1] = group
end
_G.ChatFrame_RemoveAllMessageGroups = function(frame)
    record("ChatFrame_RemoveAllMessageGroups")
    local w = W(frame._id); if w then w.groups = {} end
end
_G.AddChatWindowChannel = function(id, channel)
    record("AddChatWindowChannel")
    local w = W(id); if not w then return end
    for _, c in ipairs(w.channels) do if c == channel then return end end
    w.channels[#w.channels + 1] = channel
end
_G.RemoveChatWindowChannel = function(id, channel)
    record("RemoveChatWindowChannel")
    local w = W(id); if not w then return end
    for i = #w.channels, 1, -1 do
        if w.channels[i] == channel then table.remove(w.channels, i) end
    end
end
_G.ChatFrame_RemoveChannel = function(frame, channel)
    record("ChatFrame_RemoveChannel")
    _G.RemoveChatWindowChannel(frame._id, channel)
end
_G.ChatFrame_RemoveAllChannels = function(frame)
    record("ChatFrame_RemoveAllChannels")
    local w = W(frame._id); if w then w.channels = {} end
end
_G.ChatFrame_ReceiveAllPrivateMessages = function() record("ChatFrame_ReceiveAllPrivateMessages") end

----------------------------------------------------------------------
-- Channels: the SERVER-STATE part. Everything here is async and throttled —
-- see the unkindness list in the header.
----------------------------------------------------------------------

Sim._lastChannelOpAt   = -math.huge
Sim._channelsPopulated = false
local JOIN_LATENCY = 0.5
local OP_THROTTLE  = 0.5

local function lowestFreeChannelNumber()
    for n = 1, _G.MAX_WOW_CHAT_CHANNELS do
        if not Sim.serverChannels[n] then return n end
    end
end

local function channelNumberOf(name)
    for n, ch in pairs(Sim.serverChannels) do
        if ch.name == name then return n end
    end
end

local function fireChannelNotice(kind, num, name, zoneID)
    -- Era arg shape: a1 notice, a4 "N. Name", a7 zone id, a8 number, a9 base name.
    dispatchEvent("CHAT_MSG_CHANNEL_NOTICE",
        kind, "", nil, ("%d. %s"):format(num, name), "", "",
        zoneID or 0, num, name, 0, 0, "")
end

local function throttled()
    local now = HTIMER.clock
    if (now - Sim._lastChannelOpAt) < OP_THROTTLE then
        Sim.droppedJoins = Sim.droppedJoins + 1
        return true
    end
    Sim._lastChannelOpAt = now
    return false
end

_G.JoinChannelByName = function(name, password, frameId)
    record("JoinChannelByName")
    if type(name) ~= "string" or name == "" then return end
    if throttled() then return end     -- DROPPED SILENTLY (the pacing reality)
    -- w2/reconciler additive: a refused name consumed its send but the server
    -- never grants it — no notice, no list entry, ever.
    if Sim.opts.refuseJoins and Sim.opts.refuseJoins[name] then return end
    _G.C_Timer.After(JOIN_LATENCY, function()
        if channelNumberOf(name) then return end    -- already in: server no-ops
        local n = lowestFreeChannelNumber()
        if not n then return end
        -- EVENT BEFORE STATE: the notice fires now; the list updates a beat later.
        fireChannelNotice("YOU_JOINED", n, name, 0)
        _G.C_Timer.After(0, function()
            Sim.serverChannels[n] = { name = name, zoneID = 0 }
        end)
    end)
    if frameId then _G.AddChatWindowChannel(frameId, name) end
end
_G.JoinTemporaryChannel = _G.JoinChannelByName

_G.LeaveChannelByName = function(nameOrNum)
    record("LeaveChannelByName")
    local num = tonumber(nameOrNum) or channelNumberOf(nameOrNum)
    if not num or not Sim.serverChannels[num] then return end
    if throttled() then return end
    local name = Sim.serverChannels[num].name
    _G.C_Timer.After(JOIN_LATENCY, function()
        fireChannelNotice("YOU_LEFT", num, name, 0)
        _G.C_Timer.After(0, function()
            Sim.serverChannels[num] = nil    -- the number becomes a HOLE
        end)
    end)
end

_G.GetChannelList = function()
    record("GetChannelList")
    if not Sim._channelsPopulated then return end   -- DARK READ (Class 6)
    local nums = {}
    for n in pairs(Sim.serverChannels) do nums[#nums + 1] = n end
    table.sort(nums)
    local flat = {}
    for _, n in ipairs(nums) do
        flat[#flat + 1] = n
        flat[#flat + 1] = Sim.serverChannels[n].name
        flat[#flat + 1] = false
    end
    return unpack(flat)
end
_G.GetChannelName = function(nameOrNum)
    record("GetChannelName")
    local num = tonumber(nameOrNum) or channelNumberOf(nameOrNum)
    if not num or not Sim.serverChannels[num] then return 0 end
    return num, Sim.serverChannels[num].name
end
_G.EnumerateServerChannels = function()
    record("EnumerateServerChannels")
    return unpack(Sim.zoneChannels)
end

----------------------------------------------------------------------
-- Chat type colors + CVars + misc client surface.
----------------------------------------------------------------------

local function ct(r, g, b) return { r = r, g = g, b = b, sticky = 0, flashTab = false } end
_G.ChatTypeInfo = {
    SAY = ct(1, 1, 1), YELL = ct(1, 0.25, 0.25), EMOTE = ct(1, 0.5, 0.25),
    GUILD = ct(0.25, 1, 0.25), OFFICER = ct(0.25, 0.75, 0.25),
    WHISPER = ct(1, 0.5, 1), WHISPER_INFORM = ct(1, 0.5, 1),
    PARTY = ct(0.67, 0.67, 1), PARTY_LEADER = ct(0.46, 0.78, 1),
    RAID = ct(1, 0.5, 0), RAID_LEADER = ct(1, 0.28, 0.04),
    RAID_WARNING = ct(1, 0.28, 0), SYSTEM = ct(1, 1, 0),
    CHANNEL = ct(1, 0.75, 0.75),
}
for i = 1, _G.MAX_WOW_CHAT_CHANNELS do
    _G.ChatTypeInfo["CHANNEL" .. i] = ct(1, 0.75, 0.75)
end
_G.ChatTypeGroup = {
    SAY = { "CHAT_MSG_SAY" }, YELL = { "CHAT_MSG_YELL" },
    GUILD = { "CHAT_MSG_GUILD" }, WHISPER = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" },
    PARTY = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" },
    RAID = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" },
    SYSTEM = { "CHAT_MSG_SYSTEM" }, CHANNEL = { "CHAT_MSG_CHANNEL" },
}
_G.ChangeChatColor = function(chatType, r, g, b)
    record("ChangeChatColor")
    local info = _G.ChatTypeInfo[chatType]
    if info then info.r, info.g, info.b = r, g, b end
    dispatchEvent("UPDATE_CHAT_COLOR", chatType, r, g, b)
end
_G.SetChatColorNameByClass = function(chatType, on)
    record("SetChatColorNameByClass")
    local info = _G.ChatTypeInfo[chatType]
    if info then info.colorNameByClass = on and true or false end
end
_G.GetChatTypeIndex = function(chatType)
    record("GetChatTypeIndex")
    return 1
end
-- skin-v2 sim extension (additive): the client's own color accessor (catalog
-- 11509). Reads the SAME live table ChangeChatColor writes, so anything that
-- caches an answer stops tracking the player's settings and the suite sees it.
_G.GetMessageTypeColor = function(chatType)
    record("GetMessageTypeColor")
    local info = _G.ChatTypeInfo[chatType]
    if not info then return end
    return info.r, info.g, info.b
end

-- skin-v2 sim extension (additive): the edit box's sticky-channel header beat.
-- ChatEdit_UpdateHeader is what the client calls after every sticky change,
-- tab-cycle and /channel switch; addons post-hook it to restyle the prefix.
_G.ChatEdit_GetActiveChatType = function(editBox)
    record("ChatEdit_GetActiveChatType")
    return editBox and editBox:GetAttribute("chatType")
end
_G.ChatEdit_GetChannelTarget = function(editBox)
    record("ChatEdit_GetChannelTarget")
    return editBox and editBox:GetAttribute("channelTarget")
end
_G.ChatEdit_UpdateHeader = function(editBox)
    record("ChatEdit_UpdateHeader")
    if not editBox then return end
    local header = editBox.header
    if not header then return end
    local chatType = editBox:GetAttribute("chatType") or "SAY"
    local text, info = chatType .. ":", _G.ChatTypeInfo[chatType]
    if chatType == "CHANNEL" then
        local num = editBox:GetAttribute("channelTarget")
        local ch = num and Sim.serverChannels[tonumber(num) or -1]
        text = ("%s. %s:"):format(tostring(num or "?"), ch and ch.name or "?")
        info = _G.ChatTypeInfo["CHANNEL" .. tostring(num)] or _G.ChatTypeInfo.CHANNEL
    elseif chatType == "WHISPER" then
        -- The client names the recipient in the prefix (CHAT_WHISPER_SEND_GET).
        text = ("To %s:"):format(tostring(editBox:GetAttribute("tellTarget") or "?"))
    end
    header:SetText(text)
    header:Show()
    if info then header:SetTextColor(info.r, info.g, info.b) end
    -- ── UNKIND, and the whole hazard for an addon that MOVES this prefix ─────
    -- The client's own body does not stop at the text: it re-computes the box's
    -- TEXT INSETS from the header's measured width, so the typed line clears a
    -- prefix drawn INSIDE the box. Any addon that re-homes the prefix (into a
    -- chip of its own, say) and sets its own insets ONCE is overwritten on the
    -- very next sticky change — and a sim that only wrote the text would have
    -- proven a padding that the live client erases. The magic 13 is the
    -- client's own right inset.
    local headerWidth = header:GetStringWidth() or 0
    editBox:SetTextInsets(headerWidth + 13, 13, 0, 0)
end

-- ── THE EDIT BOX's OWN SHOW/HIDE MACHINERY (w2/move sim extension) ───────────
-- The client owns whether the attached edit box is visible, and it HIDES the
-- box on deactivate under the default 'classic' chat style ('im' is the
-- client's own persistent-box mode — the survey's §7.5 fact). Both postures
-- are modeled, because a feature that keeps the box shown must work against
-- the hiding one and must not double-show under the other.
Sim._activeEditBox = nil

_G.ChatEdit_ActivateChat = function(editBox)
    record("ChatEdit_ActivateChat")
    if type(editBox) ~= "table" then return end
    editBox:Show()
    if editBox.header then editBox.header:Show() end
    _G.ChatEdit_UpdateHeader(editBox)
    editBox:SetFocus()
    -- ── UNKIND: THE FOCUS ART COMES BACK, EVERY TIME (ui/entry-bar) ─────────
    -- The client's own focus handler SHOWS the focus texture trio on every
    -- activate. An addon that stripped the stock dress by HIDING those regions
    -- is undone by this beat on every single click into chat; one that dropped
    -- their ALPHA is not, because alpha is a channel the client never writes.
    -- Show/Hide and alpha are modeled as the independent axes they are, so the
    -- difference between the two strips is visible headless.
    if editBox.focusLeft  then editBox.focusLeft:Show()  end
    if editBox.focusMid   then editBox.focusMid:Show()   end
    if editBox.focusRight then editBox.focusRight:Show() end
    Sim._activeEditBox = editBox
end

_G.ChatEdit_DeactivateChat = function(editBox)
    record("ChatEdit_DeactivateChat")
    if type(editBox) ~= "table" then return end
    editBox:SetText("")
    editBox:ClearFocus()
    if editBox.header then editBox.header:Hide() end
    if Sim.cvars.chatStyle ~= "im" then editBox:Hide() end
    if Sim._activeEditBox == editBox then Sim._activeEditBox = nil end
end

_G.ChatEdit_GetActiveWindow = function() return Sim._activeEditBox end

-- ── WHO THE PLAYER LAST WHISPERED (ui/entry-bar sim extension) ───────────────
-- The client's own pair, and they start EMPTY: a fresh session has told nobody,
-- so anything that offers "reply to your last whisper" must earn the target
-- rather than assume one exists. (An absent accessor is a kinder client; so is
-- one that always has an answer.)
Sim.lastToldTarget = nil
Sim.lastTellTarget = nil
_G.ChatEdit_GetLastToldTarget = function()
    record("ChatEdit_GetLastToldTarget")
    return Sim.lastToldTarget
end
_G.ChatEdit_GetLastTellTarget = function()
    record("ChatEdit_GetLastTellTarget")
    return Sim.lastTellTarget
end
_G.ChatEdit_SetLastToldTarget = function(name)
    record("ChatEdit_SetLastToldTarget")
    Sim.lastToldTarget = name
end

-- ── GROUP AND GUILD MEMBERSHIP (ui/entry-bar sim extension) ──────────────────
-- The predicates the CLIENT itself uses to decide which chat targets exist
-- (the register's group-smart send note: IsInGroup / IsInRaid). Modeled as
-- REAL state a test drives, and starting at the honest default for a character
-- who just logged in alone and unguilded — so any menu that offers Party, Raid
-- or Guild has to prove the membership rather than inherit it.
Sim.group = { inParty = false, inRaid = false, inGuild = false, canOfficer = true }

function Sim.SetGroupState(spec)
    for k, v in pairs(spec or {}) do Sim.group[k] = v end
end

_G.IsInGroup = function() record("IsInGroup") return Sim.group.inParty or Sim.group.inRaid end
_G.IsInRaid  = function() record("IsInRaid")  return Sim.group.inRaid end
_G.IsInGuild = function() record("IsInGuild") return Sim.group.inGuild end
_G.GetNumGroupMembers = function()
    record("GetNumGroupMembers")
    if Sim.group.inRaid then return 10 end
    if Sim.group.inParty then return 3 end
    return 0
end
_G.UnitInParty = function() record("UnitInParty") return Sim.group.inParty end
_G.UnitInRaid  = function()
    record("UnitInRaid")
    -- INDEX, not a boolean — and the player's own slot can be 0, which is the
    -- trap a truthiness test on this return walks straight into.
    if not Sim.group.inRaid then return nil end
    return 0
end
_G.C_GuildInfo = _G.C_GuildInfo or {}
_G.C_GuildInfo.CanViewOfficerNote = function()
    record("C_GuildInfo.CanViewOfficerNote")
    return Sim.group.canOfficer and true or false
end

-- The client's LOCALISED chat-type names. Present here so anything that labels
-- a chat target reads the client's word for it rather than shipping an English
-- string of its own — and so a locale where these differ is a change of data,
-- not of code.
_G.SAY, _G.YELL, _G.PARTY = "Say", "Yell", "Party"
_G.RAID, _G.GUILD, _G.OFFICER = "Raid", "Guild", "Officer"
_G.WHISPER = "Whisper"

-- The ENTER path: the client opens (or re-focuses) the frame's edit box.
_G.ChatFrame_OpenChat = function(text, frame)
    record("ChatFrame_OpenChat")
    local f = frame or _G.DEFAULT_CHAT_FRAME
    local n = (type(f) == "table" and f.GetName and f:GetName()) or "ChatFrame1"
    local eb = _G[n .. "EditBox"]
    if not eb then return nil end
    _G.ChatEdit_ActivateChat(eb)
    if text then eb:SetText(text) end
    return eb
end

-- The ESCAPE path, exactly as the client wires it: escape deactivates.
_G.ChatEdit_OnEscapePressed = function(editBox)
    record("ChatEdit_OnEscapePressed")
    _G.ChatEdit_DeactivateChat(editBox)
end

-- CVars: hostile defaults on purpose (see header).
Sim.cvars = {
    showTimestamps = "none",
    chatStyle = "im",
    whisperMode = "inline",
    chatMouseScroll = "1",
    wholeChatWindowClickable = "1",
    chatClassColorOverride = "1",
    blockChannelInvites = "0",
}
_G.GetCVar = function(name) record("GetCVar") return Sim.cvars[name] end
_G.SetCVar = function(name, value)
    record("SetCVar")
    Sim.cvars[name] = tostring(value)
    dispatchEvent("CVAR_UPDATE", name, tostring(value))
end
_G.CHAT_TIMESTAMP_FORMAT = nil
_G.CHAT_FONT_HEIGHTS = { 12, 14, 16, 18, 20 }

_G.hooksecurefunc = function(a, b, c)
    record("hooksecurefunc")
    -- Global-name form: hooksecurefunc("Name", fn). Table form: (tbl, "k", fn).
    local tbl, key, fn
    if type(a) == "table" then tbl, key, fn = a, b, c
    else tbl, key, fn = _G, a, b end
    local orig = tbl[key]
    if type(orig) ~= "function" or type(fn) ~= "function" then return end
    tbl[key] = function(...)
        local r1, r2, r3, r4 = orig(...)
        fn(...)
        return r1, r2, r3, r4
    end
end

_G.issecretvalue = function() return false end
_G.Ambiguate = function(name, mode)
    record("Ambiguate")
    return (tostring(name):gsub("%-.*$", ""))
end
_G.InCombatLockdown = function() return Sim.inCombat end
_G.UnitName = function(unit) return "Tester" end
_G.GetRealmName = function() return "TestRealm" end
_G.UnitClass = function(unit) return "Warlock", "WARLOCK" end
_G.SetItemRef = function(...) record("SetItemRef") end
_G.FlashClientIcon = function() record("FlashClientIcon") end
_G.LoggingChat = function(on) record("LoggingChat") end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which, ...)
    record("StaticPopup_Show")
    return { which = which }
end
_G.SlashCmdList = _G.SlashCmdList or {}

_G.RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
}
_G.LOCALIZED_CLASS_NAMES_MALE   = { Warrior = "WARRIOR", Mage = "MAGE", Warlock = "WARLOCK" }
_G.LOCALIZED_CLASS_NAMES_FEMALE = { Warrior = "WARRIOR", Mage = "MAGE", Warlock = "WARLOCK" }

_G.C_ChatInfo = {
    SwapChatChannelsByChannelIndex = function(a, b)
        record("SwapChatChannelsByChannelIndex")
        Sim.serverChannels[a], Sim.serverChannels[b] =
            Sim.serverChannels[b], Sim.serverChannels[a]
    end,
    SendChatMessage = function(...) record("C_ChatInfo.SendChatMessage") end,
    IsChatLineCensored = function() return false end,
}
_G.SendChatMessage = function(...) record("SendChatMessage") end

----------------------------------------------------------------------
-- Player identity (GUID -> class), for names.lua's GUID-first path.
----------------------------------------------------------------------

Sim.playerDB = {
    ["Player-1-00000001"] = { name = "Puu",   localizedClass = "Warrior", classToken = "WARRIOR" },
    ["Player-1-00000002"] = { name = "Choco", localizedClass = "Mage",    classToken = "MAGE" },
}
Sim.GUID_SENTINEL = "0000000000000000"

_G.GetPlayerInfoByGUID = function(guid)
    record("GetPlayerInfoByGUID")
    local p = Sim.playerDB[guid]
    if not p then return end    -- unknown/sentinel/cold: NOTHING comes back
    return p.localizedClass, p.classToken, "Orc", "Orc", 2, p.name, ""
end

----------------------------------------------------------------------
-- Message traffic. Sim.SendChat delivers a CHAT_MSG_* event with the full
-- era 17-arg shape (GUID in arg12) AND routes the client-formatted,
-- HYPERLINK-BEARING line into every window whose store routes it. Ordering
-- per Sim.opts.addonEventFirst (unkind default: the addon's event handler
-- runs BEFORE the line is in any buffer).
----------------------------------------------------------------------

Sim._lineID = 100

local EVENT_GROUP = {
    CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL", CHAT_MSG_EMOTE = "EMOTE",
    CHAT_MSG_GUILD = "GUILD", CHAT_MSG_OFFICER = "OFFICER",
    CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_WHISPER_INFORM = "WHISPER",
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID_WARNING", CHAT_MSG_SYSTEM = "SYSTEM",
}

local function shortName(sender)
    return (tostring(sender):gsub("%-.*$", ""))
end

local function playerLink(sender, lineID)
    return ("|Hplayer:%s:%d|h[%s]|h"):format(sender, lineID, shortName(sender))
end

local function formatLine(event, args)
    local text, sender, lineID = args[1], args[2], args[11]
    if event == "CHAT_MSG_CHANNEL" then
        return ("|Hchannel:channel:%d|h[%d. %s]|h %s: %s")
            :format(args[8], args[8], args[9], playerLink(sender, lineID), text)
    elseif event == "CHAT_MSG_SAY" then
        return ("%s says: %s"):format(playerLink(sender, lineID), text)
    elseif event == "CHAT_MSG_YELL" then
        return ("%s yells: %s"):format(playerLink(sender, lineID), text)
    elseif event == "CHAT_MSG_WHISPER" then
        return ("%s whispers: %s"):format(playerLink(sender, lineID), text)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        return ("To %s: %s"):format(playerLink(sender, lineID), text)
    elseif event == "CHAT_MSG_SYSTEM" then
        return text
    else
        local tag = (EVENT_GROUP[event] or "?"):gsub("_", " ")
        return ("|Hchannel:%s|h[%s]|h %s: %s")
            :format(EVENT_GROUP[event] or "SAY", tag, playerLink(sender, lineID), text)
    end
end

local function windowRoutes(w, event, args)
    if event == "CHAT_MSG_CHANNEL" then
        for _, c in ipairs(w.channels) do
            if c == args[9] then return true end
        end
        return false
    end
    local group = EVENT_GROUP[event]
    if not group then return false end
    for _, g in ipairs(w.groups) do if g == group then return true end end
    return false
end

local function clientRoute(event, args)
    local line = formatLine(event, args)
    local info = _G.ChatTypeInfo[EVENT_GROUP[event] or "CHANNEL"] or _G.ChatTypeInfo.SAY
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local w = Sim.windows[id]
        if w and (w.shown or w.docked) and windowRoutes(w, event, args) then
            -- THROUGH THE CLIENT'S OWN HANDLER, never straight to AddMessage.
            -- On 11509 ChatFrame_OnEvent hands every CHAT_MSG_* to
            -- ChatFrame_MessageEventHandler, and THAT is the bracket an addon
            -- can tell "the game wrote this line" from "an addon printed this
            -- line" with (view.lua's addon classifier). A sim that called
            -- AddMessage directly would be a KINDER client than the real one in
            -- the precise place the classifier lives — the Class 9 "an absent
            -- API is a kinder client" lesson, applied to a call SHAPE.
            _G.ChatFrame_MessageEventHandler(Sim.Frame(id), event, line,
                info.r, info.g, info.b, args)
        end
    end
    return line
end

-- The client's message-event handler, in the one property that matters here:
-- it is ON THE STACK while the line it is routing lands in the frame. Addons
-- replace this global (Prat does; so does our view's classifier bracket), so
-- it is a plain global function and callers reach it through _G.
_G.ChatFrame_MessageEventHandler = function(frame, event, line, r, g, b)
    record("ChatFrame_MessageEventHandler")
    if type(frame) ~= "table" or type(frame.AddMessage) ~= "function" then return false end
    frame:AddMessage(line, r, g, b)
    return true
end

-- spec = { event=, text=, sender=, guid= ("zero" | a guid string | nil -> ""),
--          channelNumber=, channelName=, flag=, zoneID= }
-- Returns the client-formatted line (for test reference) and the args table.
function Sim.SendChat(spec)
    Sim._lineID = Sim._lineID + 1
    local guid = spec.guid
    if guid == "zero" then guid = Sim.GUID_SENTINEL end
    if guid == nil then guid = "" end
    local event = spec.event or "CHAT_MSG_SAY"
    local args = {
        [1] = spec.text or "", [2] = spec.sender or "Someone",
        [3] = "Common",
        [4] = spec.channelNumber and ("%d. %s"):format(spec.channelNumber, spec.channelName or "") or "",
        [5] = "", [6] = spec.flag or "", [7] = spec.zoneID or 0,
        [8] = spec.channelNumber or 0, [9] = spec.channelName or "",
        [10] = 0, [11] = Sim._lineID, [12] = guid, [13] = 0, [14] = false,
        [15] = nil, [16] = false, [17] = false,
    }
    local line
    if Sim.opts.addonEventFirst then
        dispatchEvent(event, unpack(args, 1, 17))
        line = clientRoute(event, args)
    else
        line = clientRoute(event, args)
        dispatchEvent(event, unpack(args, 1, 17))
    end
    return line, args
end

-- Batch replay: re-AddMessage every stored line of a frame (the double-stamp /
-- re-decoration trap for stamps.lua and decor.lua).
function Sim.ReplayBuffer(frame)
    local snap = {}
    for i = 1, #frame.historyBuffer.list do snap[i] = frame.historyBuffer.list[i] end
    for _, e in ipairs(snap) do
        frame:AddMessage(e.message, e.r, e.g, e.b)
    end
    return #snap
end

-- Link builders for pipeline tests.
function Sim.MakeItemLink(id, name)
    return ("|cffa335ee|Hitem:%d|h[%s]|h|r"):format(id or 19019, name or "Thunderfury")
end
function Sim.MakePlayerLink(name)
    return ("|Hplayer:%s|h[%s]|h"):format(name, name)
end
function Sim.MakeProtected(tag)
    return "|K" .. (tag or "q1") .. "|k"
end

----------------------------------------------------------------------
-- Lifecycle drivers.
----------------------------------------------------------------------

function Sim.Login(addonName)
    dispatchEvent("ADDON_LOADED", addonName or "Daseeki-Chat")
    dispatchEvent("PLAYER_LOGIN")
end

function Sim.EnterWorld(isLogin, isReload)
    -- The client lays its own chat dress out before anybody's ENTERING_WORLD
    -- handler runs: the dock bar is placed and every live window's tab is up.
    if type(_G.FCFDock_UpdateTabs) == "function" then _G.FCFDock_UpdateTabs() end
    dispatchEvent("PLAYER_ENTERING_WORLD",
        isLogin == nil and true or isLogin, isReload or false)
    -- Zone channels + list population land ~0.5s later; until then every
    -- channel read is dark (Class 6).
    _G.C_Timer.After(0.5, function()
        for _, name in ipairs(Sim.zoneChannels) do
            if not channelNumberOf(name) then
                local n = lowestFreeChannelNumber()
                if n then Sim.serverChannels[n] = { name = name, zoneID = 1 } end
            end
        end
        Sim._channelsPopulated = true
    end)
end

function Sim.Logout()
    dispatchEvent("PLAYER_LOGOUT")
end

-- A fresh client session on the SAME loaded addon code: uptime clock resets
-- (ring-buffer stamps from last session are now bogus — history.lua's world),
-- server epoch advances, buffers and server channel state clear.
-- APPROXIMATION, on purpose: addon files are NOT re-executed and SavedVariables
-- globals persist untouched — the addon's in-memory state carries over, which a
-- real reload would rebuild from SavedVariables. Fine for logout/login flow
-- tests; a full cold-load test means re-running the whole harness.
function Sim.NewSession()
    HTIMER.flush()
    Sim.sessionCount = Sim.sessionCount + 1
    Sim._sessionStartClock = HTIMER.clock
    Sim._uptimeBase = 15.0 + Sim.sessionCount   -- fresh, small, obviously reset
    Sim._serverEpochBase = Sim._serverEpochBase + 3600
    Sim._channelsPopulated = false
    Sim.serverChannels = {}
    -- A fresh session has told nobody: the client's last-whisper memory is
    -- session state, not saved state.
    Sim.lastToldTarget, Sim.lastTellTarget = nil, nil
    Sim._lastChannelOpAt = -math.huge
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local f = Sim.Frame(id)
        f.historyBuffer = newBuffer(DEFAULT_BUFFER_CAP)
    end
end

return Sim
