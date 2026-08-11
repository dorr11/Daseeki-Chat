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

local function newWidget(kind, name, parent)
    local w = {
        _kind = kind, _name = name, _parent = parent,
        _shown = true, _alpha = 1,
        _points = {}, _scripts = {}, _children = {}, _unknownCalls = {},
    }
    setmetatable(w, widgetMeta)
    if name then _G[name] = w end
    if parent and parent._children then parent._children[#parent._children + 1] = w end
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
function WIDGET_API.SetSize(self, w, h) self._w, self._h = w, h end
function WIDGET_API.SetWidth(self, w) self._w = w end
function WIDGET_API.SetHeight(self, h) self._h = h end
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
function WIDGET_API.EnableMouse(self, on) self._mouse = on end
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
function WIDGET_API.GetStringWidth(self) return #(self._text or "") * 7 end
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
function WIDGET_API.SetTextInsets(self) end
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

local function insetsOf(self)
    return self._clampInsets or Sim.DEFAULT_CLAMP_INSETS
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
function WIDGET_API.SetResizeBounds(self) end
function WIDGET_API.SetHitRectInsets(self) end
function WIDGET_API.EnableMouseWheel(self) end

-- Drag the frame's bottom-left corner to (left, bottom) IN THE FRAME'S OWN
-- UNITS. Only works while the frame is actually moving (StartMoving), and the
-- client's clamp decides where it is allowed to land. Returns the landed
-- corner so a test can pin "the drag could not reach the edge".
function Sim.DragTo(frame, left, bottom)
    if type(frame) ~= "table" or not frame._moving then return nil end
    local l, b = tonumber(left) or 0, tonumber(bottom) or 0
    if frame:IsClampedToScreen() then
        local P = _G.UIParent
        local ratio = P:GetEffectiveScale() / frame:GetEffectiveScale()
        local pw, ph = P:GetWidth() * ratio, P:GetHeight() * ratio
        local ins = insetsOf(frame)
        local minL, maxL = ins[1], pw - (frame._w or 0) - ins[2]
        local minB, maxB = ins[4], ph - (frame._h or 0) - ins[3]
        if maxL < minL then maxL = minL end
        if maxB < minB then maxB = minB end
        if l < minL then l = minL elseif l > maxL then l = maxL end
        if b < minB then b = minB elseif b > maxB then b = maxB end
    end
    frame._left, frame._bottom = l, b
    return l, b
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

_G.CreateFrame = function(kind, name, parent, template)
    record("CreateFrame")
    local w = newWidget(kind or "Frame", name, parent or _G.UIParent)
    w._template = template
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
    f.historyBuffer = newBuffer(DEFAULT_BUFFER_CAP)
    f.AddMessage      = chatAddMessage
    f.GetNumMessages  = chatGetNumMessages
    f.GetMessageInfo  = chatGetMessageInfo
    -- Stock dress textures, global-named like the client's.
    for _, suffix in ipairs(STOCK_TEXTURES) do
        newWidget("Texture", name .. suffix, f)
    end
    -- Tab + its text.
    local tab = newWidget("Button", name .. "Tab", f)
    tab.Text = newWidget("FontString", name .. "TabText", tab)
    -- Edit box + its stock art regions, parked below the frame like the client.
    local eb = newWidget("EditBox", name .. "EditBox", f)
    eb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -6)
    eb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -6)
    -- skin-v2 sim extension (additive): the sticky-channel HEADER FontString.
    -- Modeled in BOTH client shapes (the `header` field the client's own code
    -- reaches for, and the $parentHeader global the template names) so an addon
    -- that defends either shape is exercised honestly.
    eb.header = newWidget("FontString", name .. "EditBoxHeader", eb)
    eb:SetAttribute("chatType", "SAY")
    eb.chatFrame = f
    -- w2/move sim extension: the client's DEFAULT posture under chatStyle
    -- 'classic' — the edit box (and its prefix) exist but are HIDDEN until
    -- something activates them. A persistent-edit-box feature has to earn the
    -- shown state against this default, never inherit it.
    eb._shown, eb.header._shown = false, false
    eb._mouse = true
    for _, suffix in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
        newWidget("Texture", name .. "EditBox" .. suffix, eb)
    end
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

-- Modifier state (the ALT-drag gesture's gate).
Sim.altDown = false
_G.IsAltKeyDown     = function() record("IsAltKeyDown") return Sim.altDown and true or false end
_G.IsShiftKeyDown   = function() return Sim.shiftDown and true or false end
_G.IsControlKeyDown = function() return Sim.ctrlDown and true or false end

Sim.windows = defaultWindows()
_G.CHAT_FRAMES = {}
for i = 1, _G.NUM_CHAT_WINDOWS do
    makeChatFrame(i)
    _G.CHAT_FRAMES[i] = "ChatFrame" .. i
end
_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1
_G.GeneralDockManager = {
    primary = _G.ChatFrame1,
    selected = _G.ChatFrame1,
    DOCKED_CHAT_FRAMES = { _G.ChatFrame1, _G.ChatFrame2 },
}

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

_G.FloatingChatFrame_Update = function(id)
    record("FloatingChatFrame_Update")
    local w, f = W(id), Sim.Frame(id)
    if not (w and f) then return end
    f._projectedName = w.name
    f._shown = w.shown and true or false
end
_G.FCF_DockUpdate = function() record("FCF_DockUpdate") end

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
_G.FCF_SavePositionAndDimensions = function() record("FCF_SavePositionAndDimensions") end
_G.FCF_StopDragging = function() record("FCF_StopDragging") end
_G.FCF_StartAlertFlash = function() record("FCF_StartAlertFlash") end
_G.FCF_StopAlertFlash = function() record("FCF_StopAlertFlash") end
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
        local ch = num and Sim.serverChannels[num]
        text = ("%s. %s:"):format(tostring(num or "?"), ch and ch.name or "?")
        info = _G.ChatTypeInfo["CHANNEL" .. tostring(num)] or _G.ChatTypeInfo.CHANNEL
    end
    header:SetText(text)
    if info then header:SetTextColor(info.r, info.g, info.b) end
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
            Sim.Frame(id):AddMessage(line, info.r, info.g, info.b)
        end
    end
    return line
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
    Sim._lastChannelOpAt = -math.huge
    for id = 1, _G.NUM_CHAT_WINDOWS do
        local f = Sim.Frame(id)
        f.historyBuffer = newBuffer(DEFAULT_BUFFER_CAP)
    end
end

return Sim
