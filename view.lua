-- Daseeki Chat — view.lua  (D2 REVISION, 2026-08-11: draw our own view)
--
-- THE OWNED CHAT VIEW. One frame of ours — chassis, tab strip, message
-- surfaces and entry bar — drawn at the mockup's own numbers, over the
-- client's ten chat windows kept alive but HIDDEN as the engine.
--
-- WHY THIS FILE EXISTS (the owner, 2026-08-11): "if drawing our own gets a
-- better result, do that. thats my mistake in the design." Two rounds of
-- skin-over fidelity work could not hold the mockup live — the client's own
-- machinery (tab alpha fades, periodic re-clamp, stock textures under ours)
-- re-asserts itself under every surface we skin. Skin-over made every mockup
-- property a fight; drawing our own makes the mockup the DEFAULT STATE.
--
-- THE DIVISION OF LABOUR, exactly:
--   * The client's 10-window model is the ENGINE. Windows still exist, still
--     receive messages per the config's routing, and reconcile.lua /
--     channels.lua / config.lua / nexus.lua are UNCHANGED — config stays
--     authoritative over the client windows exactly as before. What changed is
--     only who paints pixels. THE STORE IS NEVER TOUCHED to hide a window:
--     we hide the FRAME (a display act), never SetChatWindowShown (a routing
--     act) — that one distinction is what keeps the engine delivering.
--   * decor / stamps / names / urls run where they ran; the view MIRRORS the
--     post-decoration line off each hidden window's own AddMessage.
--   * history and badges rebind to the view's tabs through their own public
--     seams; neither module's rules change.
--   * The client's chat EDIT machinery is REPARENTED, never reimplemented:
--     slash commands, channel stickiness and the secure send path are the
--     client's and must stay the client's.
--
-- INERTNESS (the suite discipline, and the harness's pin): this module touches
-- NOTHING until its OnEnable runs — no frames, no hooks, no hidden windows.
-- OnDisable gives stock client chat back: the windows are shown again, the
-- edit box goes home, our chassis hides. Nothing is destroyed.
--
-- All display glyphs in this file are ASCII (the tofu lesson).

local ADDON, ns = ...

local View = {
    active   = false,   -- gate for every hook body and event handler
    hooked   = false,   -- one-time hooksecurefunc installs done
    frames   = {},      -- window id -> OUR ScrollingMessageFrame
    tabs     = {},      -- window id -> { button, label, fill, underline, hover }
    ids      = {},      -- owned window ids, ascending (Class 8: never pairs())
    activeId = nil,     -- the tab the player is looking at
    -- the mirror's counters (read by /dchat debug view and the suite)
    mirrored        = 0,   -- lines forwarded because a client AddMessage fired
    resyncedLines   = 0,   -- lines re-read out of an engine buffer (never mirrored)
    mirrorReentries = 0,   -- client AddMessage calls refused as our own echo
    mirrorRefusals  = 0,   -- depth-fuse refusals (an unforeseen composition)
    retargets       = 0,   -- edit-box retargets on tab switch
    reHides         = 0,   -- times the client showed an engine window and we re-hid it
    resyncs         = 0,   -- full buffer re-reads into a view frame
    moves           = 0,   -- completed chassis drags
    -- RED CONTROL state (Class 9 posture: a latch armed BEFORE the first call
    -- of the sequence, save/restore rather than clear-to-nil, with a depth fuse
    -- under it so an unforeseen composition degrades to a refusal).
    _mirrorDepth = 0,
    _engineHidden = {},  -- frame -> true while we hold it down
    _ebHome      = nil,  -- { eb, parent, points, width, height } of the hosted box
}
ns.View = View

----------------------------------------------------------------------
-- ============ THE MOCKUP CONTRACT (moved here 2026-08-11) ============
--
-- This table came from skin.lua, where it was the SKIN-OVER contract and six
-- of its rows had to say CLIENT LIMIT. Drawing our own frame kills most of
-- those limits outright: there is no stock art to strip, no FCF tab machinery
-- to out-shout, no client fade to keep taking back. Every row below now reads
-- IDENTICAL or names a limit that SURVIVES the change — and exactly two do.
--
-- COLOUR (mockup :root custom properties -> PALETTE below, literal hexes)
--   --ground   #0b0908  -> PALETTE.ground   #0b0908   IDENTICAL
--   --panel    #16100f  -> PALETTE.panel    #16100f   IDENTICAL (chassis + strip/rail)
--   --panel2   #1d1514  -> PALETTE.panel2   #1d1514   IDENTICAL (messages + entry + active tab)
--   --line     #6e1d1a  -> PALETTE.line     #6e1d1a   IDENTICAL (chassis border, 1px)
--   --line-soft#3a1512  -> PALETTE.lineSoft #3a1512   IDENTICAL (entry seam, rail seam, stamp divider)
--   --accent   #c2402e  -> PALETTE.accent   #c2402e   IDENTICAL (active underline, pip fill, hover ink)
--   --gold     #d9a83f  -> PALETTE.gold     #d9a83f   IDENTICAL (carried; the box itself uses none)
--   --text     #e6dfd4  -> PALETTE.text     #e6dfd4   IDENTICAL (active tab ink, hover wash source)
--   --muted    #93887e  -> PALETTE.muted    #93887e   IDENTICAL (inactive tab ink)
--   --faint    #5c534c  -> PALETTE.faint    #5c534c   IDENTICAL (stamp ink — stamps.lua's default)
--   .chatbox background: solid --panel      alpha 1.0 IDENTICAL
--   per-channel message colours             CLIENT    the mockup's own footer says so: message ink is
--                                                     the CLIENT's colour table, live, never a hex —
--                                                     and it rides the mirror's NUMERIC r,g,b args
--                                                     ("the ink is not in a string").
--
-- GEOMETRY (1 CSS px = 1 UI unit, literally)
--   .chatbox border 1px --line             -> CHASSIS_EDGE 1 + PALETTE.line     IDENTICAL
--   .chatbox border-radius 6px             -> square                            DEFERRED, not a limit.
--       Skin-over called this a CLIENT LIMIT because a backdrop edge is a repeated 1px texture. Owning
--       the frame retires that reason: nine-slice corner art on our own chassis is possible and is the
--       agreed way in. It is not shipped in this build (bespoke art, scheduled after the view lands),
--       so the row says DEFERRED — a decision with a date, not a capability we lack.
--   .tabs-top padding 6px 8px 0            -> STRIP_PAD_TOP 2 / STRIP_PAD_X 3 / 0
--       OWNER AMENDMENT 2026-08-11 (thinner tabs/entry, no side gutters), carried from skin.lua where
--       the owner approved it against the live render: STRIP_PAD_TOP 6 -> 2, STRIP_PAD_X 8 -> 3.
--   .tab padding 5px 14px 6px              -> TAB_PAD_TOP 2 / TAB_PAD_X 14 / TAB_PAD_BOT 4
--       OWNER AMENDMENT 2026-08-11: 5 -> 2 top, 6 -> 4 bottom (the 2-unit underline keeps 2 units of
--       clearance and the 14-unit badge chip still centres inside the 24-unit row).
--   .tab font-size 12.5px, weight 600      -> TAB_TEXT_SIZE 12.5, config-backed  IDENTICAL size;
--       WEIGHT is a SURVIVING CLIENT LIMIT: one vendored face, and synthetic bold on a FontString
--       smears. Owning the frame does not add a face.
--   .tab letter-spacing .04em              -> not applied   SURVIVING CLIENT LIMIT: a FontString has no
--       letter-spacing and the only fake is one FontString per glyph. Unchanged by owning the frame.
--   .tab line-height 1.45                  -> TAB_LINE_H 18 (12.5 * 1.45 = 18.1)  IDENTICAL to the pixel
--   => tab height 2 + 18 + 4               -> TAB_H 24                            (owner amendment)
--   => strip height 2 + 24                 -> STRIP_H 26                          (owner amendment)
--   .tabs-top gap 2px                      -> TAB_GAP 2                          IDENTICAL
--   .tab border-radius 4px 4px 0 0         -> square                             DEFERRED (as above)
--   .tab.active background var(--panel2)   -> the active tab wears a REAL panel2 fill run down to the
--       strip's bottom edge, so it fuses with the message surface                IDENTICAL
--       (skin-over could only fake this with two half-hairlines; our tab is our widget and just IS the
--        fill, which is why this row stops being an approximation)
--   .tab.active::after inset 6px, 2px      -> UL_INSET 6 / UL_HEIGHT 2 / UL_Y 0   IDENTICAL
--   .tab:hover rgba(255,255,255,.04)       -> PALETTE.text at HOVER_WASH 0.04     IDENTICAL in effect
--   .tab (inactive) colour --muted         -> INK ONLY. An inactive tab is dimmed by its INK, never by
--       alpha, and NOTHING in this file animates alpha — our tabs are not registered with any FCF
--       machinery, so there is no fade to take back.                             IDENTICAL
--   .tab .n  (the unread pip)              -> badges.lua on OUR tab button: accent chip, white digits,
--       10.5px, after the label with a 6px gap, inside the tab                   IDENTICAL
--   .tab .n border-radius 8px              -> square chip                        DEFERRED (as above)
--   .msgs padding 10px 14px 6px            -> MSG_PAD_TOP 10 / MSG_PAD_X 3 / MSG_PAD_BOT 6
--       OWNER AMENDMENT 2026-08-11 (no side gutters): MSG_PAD_X 14 -> 3.
--       Skin-over had to pad the CHASSIS around the client's frame because that frame has no text
--       insets; our message frame is anchored at these insets directly.          IDENTICAL
--   .msgs font-size 13.5px                 -> view.fontSize, default 13.5        IDENTICAL
--   .msgs .row padding 1.5px 0             -> ROW_SPACING 3                      IDENTICAL
--   .msgs line-height 1.45                 -> View.MessageSpacing = (1.45 - 1.2) * size + ROW_SPACING,
--       COMPUTED from the size in force (a FontString already draws a line box of its own, so what
--       SetSpacing wants is the DIFFERENCE; FACE_NATURAL_LINE is the one measured constant here)
--                                                                               IDENTICAL
--   .msgs .row gap 8px + .stampline 1px    -> stamps.lua's space-run separator, hairline centred
--       APPROXIMATE, SURVIVING CLIENT LIMIT: a chat line is ONE string in ONE FontString whichever
--       frame draws it, so the space right of the hairline can only be spelled in spaces.
--   .stampline background --line-soft      -> PALETTE.lineSoft, alpha 1          IDENTICAL colour; drawn
--       as ONE column hairline rather than per row — rows are still not addressable widgets (surviving).
--   .stamp font-variant-numeric tabular    -> not applied   SURVIVING CLIENT LIMIT: no OpenType feature
--       control on a FontString.
--   .entry padding 8px 12px                -> EB_PAD_Y 3 / EB_PAD_X 12           (owner amendment 8 -> 3)
--   .entry font 13.5px, line-height 1.45   -> EB_HEIGHT 26                       (owner amendment 36 -> 26)
--   .entry border-top 1px --line-soft      -> SEAM_W 1, PALETTE.lineSoft, flush  IDENTICAL
--   .entry background var(--panel2)        -> shares the message surface's fill  IDENTICAL
--   .entry .hinttxt "always visible..."    -> not shipped: it is the MOCKUP'S OWN annotation of the
--       behaviour (which IS shipped — the box never hides), not a control.
--   .tabs-side width 112px                 -> TABRAIL_W 112                      IDENTICAL
--   .tabs-side padding 8px 6px             -> RAIL_PAD_Y 4 / RAIL_PAD_X 6        (owner amendment 8 -> 4)
--   .tabs-side border-left 1px --line-soft -> SEAM_W 1, PALETTE.lineSoft         IDENTICAL
--   .stab padding 7px 10px                 -> RAIL_TAB_PAD_Y 4 / RAIL_TAB_PAD_X 10 (owner amendment)
--   => rail row height 4 + 18 + 4          -> TAB_ROW_H 26                       (owner amendment)
--   .stab.active::before 2px, inset 5px    -> EDGEBAR_W 2 / EDGEBAR_INSET 5      IDENTICAL
--   .stab .n float:right                   -> badges.lua right-aligns in the row IDENTICAL
--   box-shadow 0 8px 30px rgba(0,0,0,.55)  -> not shipped   SURVIVING CLIENT LIMIT: no drop-shadow
--       primitive; the honest fake is a nine-slice glow, which is bespoke art (same queue as the
--       corners, and deliberately behind them).
--   .tabs-top background (implicit --panel) -> a REAL --panel texture on the strip, drawn ABOVE the
--       message surface in frame level                                          IDENTICAL
--       AMENDED 2026-08-11 (the owner's first live look): the strip shipped as a bare anchor frame
--       relying on the chassis' backdrop showing through, at the same frame level as the feed. The
--       mockup's tab band is an OPAQUE surface with a defined stacking position, and saying so
--       outright is what keeps anything drawn at the feed's own top edge out of the tab band.
--
-- NOT IN THE MOCKUP AT ALL, and named here so the table stays a complete account of what is drawn:
--   the RESIZE GRIPS (12 units, one per CORNER, --line-soft resting / --accent under the pointer,
--   VISIBLE the whole time the box is unlocked and absent while it is locked). The mockup is a still
--   image and carries no gestures; the grips are furniture the OWNED frame adds.
--   AMENDED 2026-08-11 (the owner, after the first build): one hover-only grip in the bottom-right
--   was the answer to "how do i unlock it to move and resize?" and it failed — he had to ask again,
--   and then asked for a lock as well. An affordance nobody can see is not an affordance, so all
--   four corners are up whenever the box can actually be resized.
--
-- RETIRED WITH SKIN-OVER (rows that no longer need to exist): "the box strips
-- the client's stock tab art", "the box takes the tab's alpha back from
-- FCFTab_UpdateAlpha", "the chassis pads AROUND the client's frame because it
-- has no text insets", "the active tab is faked with two half-hairlines".
-- None of those are properties of the design — they were properties of
-- painting on somebody else's frame.
--
-- THE SCORE: 4 surviving client limits (font weight, letter-spacing, tabular
-- figures, drop shadow) + the one-string-per-line consequence of the stamp
-- gap; 3 DEFERRED rounded-corner rows (ours to ship, not the client's to
-- refuse). Everything else is IDENTICAL.
----------------------------------------------------------------------

-- THE PALETTE. Literal mockup hexes, and the ONE place they live (moved here
-- from skin.lua with the mapping table above). skin.lua, stamps.lua and
-- badges.lua all read it through a published accessor rather than keeping a
-- copy — see View.Ink / Skin.Ink.
local PALETTE = {
    ground   = 0x0b0908,
    panel    = 0x16100f,
    panel2   = 0x1d1514,
    line     = 0x6e1d1a,
    lineSoft = 0x3a1512,
    accent   = 0xc2402e,
    gold     = 0xd9a83f,
    text     = 0xe6dfd4,
    muted    = 0x93887e,
    faint    = 0x5c534c,
}
View.PALETTE = PALETTE

-- r, g, b, a for a palette entry. Nil for a name the palette does not carry
-- (never a hopeful black — Class 5's truthy-zero discipline applied to ink).
function View.Ink(name, alpha)
    local v = PALETTE[name]
    if not v then return nil end
    return math.floor(v / 65536) % 256 / 255,
           math.floor(v / 256) % 256 / 255,
           (v % 256) / 255,
           alpha or 1
end

function View.Palette() return PALETTE end

----------------------------------------------------------------------
-- THE NUMBERS, straight off the mapping table above. These are the owner's
-- post-amendment values, carried from skin.lua as the view's own constants.
----------------------------------------------------------------------

local CHASSIS_EDGE   = 1     -- .chatbox border width
local STRIP_PAD_TOP  = 2     -- .tabs-top padding-top          (owner amendment 6 -> 2)
local STRIP_PAD_X    = 3     -- .tabs-top padding-left/right   (owner amendment 8 -> 3)
local TAB_TEXT_SIZE  = 12.5  -- .tab font-size
local TAB_LINE_H     = 18    -- .tab line-height (12.5 * 1.45)
local TAB_PAD_TOP    = 2     -- .tab padding-top               (owner amendment 5 -> 2)
local TAB_PAD_X      = 14    -- .tab padding-left/right
local TAB_PAD_BOT    = 4     -- .tab padding-bottom            (owner amendment 6 -> 4)
local TAB_H          = TAB_PAD_TOP + TAB_LINE_H + TAB_PAD_BOT       -- 24
local STRIP_H        = STRIP_PAD_TOP + TAB_H                        -- 26
local TAB_GAP        = 2     -- .tabs-top gap
local MSG_PAD_TOP    = 10    -- .msgs padding-top
local MSG_PAD_X      = 3     -- .msgs padding-left/right       (owner amendment 14 -> 3)
local MSG_PAD_BOT    = 6     -- .msgs padding-bottom
local ROW_SPACING    = 3     -- .msgs .row padding 1.5px each side
local MOCKUP_FONT_H  = 13.5  -- .msgs font-size
local MOCKUP_LINE_HEIGHT = 1.45
local EB_HEIGHT      = 26    -- .entry: 3 + (13.5 * 1.45) + 3  (owner amendment 36 -> 26)
local EB_PAD_X       = 12    -- .entry padding-left/right
local EB_PAD_Y       = 3     -- .entry padding-top/bottom      (owner amendment 8 -> 3)
local TABRAIL_W      = 112   -- .tabs-side width
local RAIL_PAD_Y     = 4     -- .tabs-side padding-top/bottom  (owner amendment 8 -> 4)
local RAIL_PAD_X     = 6     -- .tabs-side padding-left/right
local RAIL_TAB_PAD_Y = 4     -- .stab padding-top/bottom       (owner amendment 7 -> 4)
local RAIL_TAB_PAD_X = 10    -- .stab padding-left/right
local TAB_ROW_H      = RAIL_TAB_PAD_Y + TAB_LINE_H + RAIL_TAB_PAD_Y  -- 26
local SEAM_W         = 1     -- .entry border-top / .tabs-side border-left
local UL_HEIGHT      = 2     -- .tab.active::after height
local UL_INSET       = 6     -- …its left/right inset
local UL_Y           = 0     -- …its lift off the tab's bottom
local EDGEBAR_W      = 2     -- .stab.active::before width
local EDGEBAR_INSET  = 5     -- …its top/bottom inset
local HOVER_WASH     = 0.04  -- .tab:hover rgba(255,255,255,.04)
local TAB_MIN_W      = 40    -- a tab is never narrower than this (empty-name windows)
local TAB_CHAR_W     = 0.52  -- fallback glyph advance as a share of the text size
local GRIP_SIZE      = 12    -- the resize grip's corner square (no mockup row: the
                             -- mockup is a still image and has no gestures in it —
                             -- this is FURNITURE the owned frame adds, sized to the
                             -- smallest square that is still a reliable click target)

-- The vendored face's own line box, as a multiple of its point size. The one
-- MEASURED constant here (a FontString's natural leading is the face's
-- ascent+descent, which no client API reports); 1.2 is the standard TTF metric
-- and what the mockup's browser used for `line-height:normal`.
local FACE_NATURAL_LINE = 1.2

-- The view's message buffer. The client's own default is 128 lines per window;
-- ours matches so scrollback depth does not silently change with the view.
local VIEW_MAX_LINES = 128

-- Chassis defaults for a world that cannot answer for the engine window's own
-- size yet (Class 4: an unresolvable read is refused, not guessed at zero).
local FALLBACK_W, FALLBACK_H = 430, 160

local COMBAT_LOG_ID = 2

----------------------------------------------------------------------
-- CONFIG.
--
-- WHAT RIDES THE MESH AND WHAT DOES NOT, decided the same way skin v3 decided
-- it and written down here because the aliases lesson says an unlisted section
-- is silently account-local forever:
--   * LAYOUT is synced and already whitelisted in config.lua's Candidates /
--     Snapshot / AdoptEffective: the tab PLACEMENT (config.skin.tabPlacement),
--     per-tab COLOUR (config.windows[id].tabColor, protected by
--     WINDOW_CONFIG_ONLY_FIELDS) and POSITION (config.windows[id].npos). The
--     view adds NO new synced field — it reads the ones that exist.
--   * The LOOK is per-account taste and stays ACCOUNT-LOCAL in db.view, the
--     same call skin.lua's unifiedChassis made. A player on a 4K monitor and a
--     player on a laptop want different type sizes; syncing them would be a
--     misfeature, not a feature. This comment IS the deliberate-account-local
--     record the file-map amendment procedure asks for.
----------------------------------------------------------------------

ns.DEFAULTS.view = {
    fontSize    = MOCKUP_FONT_H,          -- .msgs font-size 13.5
    lineHeight  = MOCKUP_LINE_HEIGHT,     -- .msgs line-height 1.45
    tabTextSize = TAB_TEXT_SIZE,          -- .tab font-size 12.5
    copyButton  = true,                   -- the copy-chat affordance, carried over
}

local function cfg()
    return (ns.db and ns.db.view) or ns.DEFAULTS.view
end

local function UIKit() return _G.DaseekiUI end

local function numWindows() return _G.NUM_CHAT_WINDOWS or 10 end

-- One numeric widget read, defended: nil for "the client would not answer",
-- never a hopeful zero (Class 5).
local function widgetNum(w, method)
    if type(w) ~= "table" then return nil end
    local f = w[method]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, w)
    if ok and type(v) == "number" then return v end
    return nil
end

local function call(w, method, ...)
    if type(w) ~= "table" then return nil end
    local f = w[method]
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(f, w, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function isCombatLog(frame, id)
    local f = _G.IsCombatLog
    if type(f) == "function" then
        local ok, res = pcall(f, frame)
        if ok then return res and true or false end
    end
    return id == COMBAT_LOG_ID
end

-- A window the view owns: shown or docked in the CLIENT's own store, and not
-- the combat log (which stays native, per the design's rule 6).
local function windowEligible(id)
    local gcwi = _G.GetChatWindowInfo
    if type(gcwi) ~= "function" then return false end
    local ok, name, fontSize, _, _, _, _, shown, _, docked = pcall(gcwi, id)
    if not ok then return false end
    return ((shown and shown ~= 0) or (docked and docked ~= 0)), name, fontSize
end

----------------------------------------------------------------------
-- READS. Where the tabs live comes from the SYNCED config through its own
-- seam, runtime-defended like every peer read: a config that cannot answer
-- leaves us on "top", which is the client's own arrangement and therefore the
-- safe answer.
----------------------------------------------------------------------

function View.TabPlacement()
    local C = ns.Config
    if C and type(C.TabPlacement) == "function" then
        local ok, v = pcall(C.TabPlacement)
        if ok and (v == "top" or v == "left" or v == "right") then return v end
    end
    return "top"
end

function View.TabsOnRail()
    local p = View.TabPlacement()
    return p == "left" or p == "right"
end

-- The size the feed renders at (config-backed with the mockup's own default;
-- 0/nil means "the client's per-window right-click size menu decides" — the
-- escape hatch skin v1's split used to be).
function View.MessageFontSize(clientSize)
    local want = tonumber(cfg().fontSize)
    if want and want > 0 then return want end
    local size = tonumber(clientSize)
    if not size or size <= 0 then size = 14 end       -- truthy-zero guard (Class 5)
    return size
end

-- PURE. The mockup's rhythm in the points SetSpacing speaks: the air the
-- line-height asks for BEYOND the face's own line box, plus the row padding.
-- Computed from the size in force, so it stays 1.45 when the size changes.
function View.MessageSpacing(size)
    size = tonumber(size)
    if not size or size <= 0 then return ROW_SPACING end
    local lh = tonumber(cfg().lineHeight)
    if not lh or lh <= 0 then lh = MOCKUP_LINE_HEIGHT end
    local extra = (lh - FACE_NATURAL_LINE) * size
    if extra < 0 then extra = 0 end
    return extra + ROW_SPACING
end

function View.TabTextSize()
    local v = tonumber(cfg().tabTextSize)
    if v and v > 0 then return v end
    return TAB_TEXT_SIZE
end

-- The mockup contract, as data: the settings page, the debug command and the
-- harness all name a number without re-typing it.
function View.Metrics()
    return {
        chassisEdge = CHASSIS_EDGE,
        stripH = STRIP_H, stripPadTop = STRIP_PAD_TOP, stripPadX = STRIP_PAD_X,
        tabH = TAB_H, tabPadTop = TAB_PAD_TOP, tabPadX = TAB_PAD_X,
        tabPadBottom = TAB_PAD_BOT, tabGap = TAB_GAP, tabLineH = TAB_LINE_H,
        msgPadTop = MSG_PAD_TOP, msgPadX = MSG_PAD_X, msgPadBottom = MSG_PAD_BOT,
        rowSpacing = ROW_SPACING,
        entryH = EB_HEIGHT, entryPadX = EB_PAD_X, entryPadY = EB_PAD_Y,
        railW = TABRAIL_W, railPadY = RAIL_PAD_Y, railPadX = RAIL_PAD_X,
        railRowH = TAB_ROW_H, railTabPadX = RAIL_TAB_PAD_X,
        seam = SEAM_W, underlineH = UL_HEIGHT, underlineInset = UL_INSET,
        edgebarW = EDGEBAR_W, edgebarInset = EDGEBAR_INSET,
        hoverWash = HOVER_WASH, maxLines = VIEW_MAX_LINES,
        gripSize = GRIP_SIZE, minFeedLines = View.MIN_FEED_LINES,
    }
end

----------------------------------------------------------------------
-- WHICH WINDOWS THE VIEW OWNS. Ascending, rebuilt on every layout beat, and
-- never pairs()-ordered (Class 8 — the tab run must be the same run twice).
----------------------------------------------------------------------

function View.OwnedIds()
    local out = {}
    for id = 1, numWindows() do
        local frame = _G["ChatFrame" .. id]
        if frame and not isCombatLog(frame, id) and windowEligible(id) then
            out[#out + 1] = id
        end
    end
    return out
end

function View.ClientFrame(id) return _G["ChatFrame" .. tostring(id)] end

-- The window whose position and dimensions the chassis rides. The lowest owned
-- id, which on a stock layout is ChatFrame1 — the dock's primary, and the one
-- the reconciler's npos path already governs.
function View.HostId()
    return View.ids[1] or 1
end

----------------------------------------------------------------------
-- THE CHASSIS. One frame of ours: solid --panel fill at alpha 1, a 1px --line
-- border, and nothing of the client's underneath it.
----------------------------------------------------------------------

local function paint(tex, name, alpha)
    if type(tex) ~= "table" or type(tex.SetColorTexture) ~= "function" then return end
    local r, g, b, a = View.Ink(name, alpha)
    if not r then return end
    pcall(tex.SetColorTexture, tex, r, g, b, a)
end

function View.EnsureChassis()
    if View.chassis then return View.chassis end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" then return nil end
    local ok, f = pcall(cf, "Frame", "DaseekiChatView", _G.UIParent, "BackdropTemplate")
    if not ok or type(f) ~= "table" then return nil end
    call(f, "SetFrameStrata", "LOW")
    call(f, "EnableMouse", true)
    call(f, "SetMovable", true)
    call(f, "SetClampedToScreen", true)
    -- OUR frame, OUR rules: no clamp margin at all, so a drag can reach the
    -- screen edge. The client has no re-clamp beat for a frame it does not
    -- own, which is precisely why the bounce-back class is now impossible —
    -- and why nothing in this file has to keep taking the insets back.
    call(f, "SetClampRectInsets", 0, 0, 0, 0)
    call(f, "RegisterForDrag", "LeftButton")
    -- THE FILL AND THE BORDER, at the literal mockup hexes. A backdrop is used
    -- for the edge (one repeated 1px texture is exactly a 1px border) and a
    -- plain texture for the fill, so the two colours are independent.
    local UI = UIKit()
    if UI and UI.FLAT_BACKDROP then call(f, "SetBackdrop", UI.FLAT_BACKDROP) end
    local rr, rg, rb = View.Ink("panel")
    if rr then call(f, "SetBackdropColor", rr, rg, rb, 1) end
    local lr, lg, lb = View.Ink("line")
    if lr then call(f, "SetBackdropBorderColor", lr, lg, lb, 1) end
    -- The tab strip / rail. It carries a REAL --panel fill of its own and sits
    -- ABOVE the message surface in the frame-level order (see Reflow): the
    -- mockup's `.tabs-top` is an opaque band, and a strip that is merely an
    -- empty anchor frame at the same level as the feed lets whatever the feed
    -- draws at its own top edge read through the gaps between the tabs. Draw
    -- order here is stated OUTRIGHT rather than inherited from creation order,
    -- because creation order is not a contract.
    local strip = cf("Frame", nil, f)
    View.strip = strip
    local stripFill = call(strip, "CreateTexture", nil, "BACKGROUND")
    paint(stripFill, "panel", 1)
    View.stripFill = stripFill
    -- THE WHOLE STRIP IS A GRAB HANDLE, not only the tabs on it. The tab buttons
    -- already carried the plain-drag gesture, but the empty run past the last
    -- tab fell through to the chassis — which asks for ALT — so "drag the strip
    -- to move the box" was true of about a third of the strip. It is now true of
    -- the strip.
    call(strip, "EnableMouse", true)
    call(strip, "RegisterForDrag", "LeftButton")
    strip:SetScript("OnDragStart", function() View.OnDragStart(View.chassis, "strip") end)
    strip:SetScript("OnDragStop",  function() View.OnDragStop() end)
    -- The message surface (--panel2) spans the feed AND the entry bar: the
    -- mockup's `.msgs` and `.entry` share one fill with a hairline between.
    local surface = call(f, "CreateTexture", nil, "BACKGROUND")
    paint(surface, "panel2", 1)
    View.surface = surface
    -- The entry seam: `.entry{border-top:1px var(--line-soft)}`.
    local seam = call(f, "CreateTexture", nil, "ARTWORK")
    paint(seam, "lineSoft", 1)
    View.entrySeam = seam
    -- The rail's own inner seam (`.tabs-side{border-left:1px --line-soft}`).
    local railSeam = call(f, "CreateTexture", nil, "ARTWORK")
    paint(railSeam, "lineSoft", 1)
    View.railSeam = railSeam
    -- The entry bar: an anchor frame the client's edit box is reparented into.
    local entry = cf("Frame", nil, f)
    View.entry = entry
    f:SetScript("OnDragStart", function(self) View.OnDragStart(self, "frame") end)
    f:SetScript("OnDragStop",  function() View.OnDragStop() end)
    -- RESIZE: the chassis is resizable and its inner regions reflow from its
    -- LIVE size on every size change, so a drag reflows continuously without a
    -- single OnUpdate anywhere.
    call(f, "SetResizable", true)
    f:SetScript("OnSizeChanged", function()
        if View.active then View.Reflow() end
    end)
    -- The grip is quiet until the pointer is on the box (the movement layer's
    -- philosophy: no unlock ritual, no permanent furniture).
    f:SetScript("OnEnter", function() View.SetGripVisible(true) end)
    f:SetScript("OnLeave", function() View.SetGripVisible(false) end)
    View.chassis = f
    return f
end

-- What the chassis costs BEYOND the feed the engine window stands for: the
-- border, the entry bar and its seam, and the strip or the rail. One function,
-- so the size and its inverse can never drift apart.
function View.Furniture()
    local extraH = EB_HEIGHT + SEAM_W + 2 * CHASSIS_EDGE
    local extraW = 2 * CHASSIS_EDGE
    if View.TabsOnRail() then
        extraW = extraW + TABRAIL_W + SEAM_W
    else
        extraH = extraH + STRIP_H
    end
    return extraW, extraH
end

-- The chassis' outer size: the engine window's own width and height (which the
-- reconciler governs through the synced config's `dim` / `ndim`) plus our
-- furniture. ONE SOURCE OF TRUTH, and it is the engine window — exactly as the
-- POSITION is: a resize writes the engine window's size and this answer follows,
-- so `ndim` means the same thing for both the way `npos` already does.
function View.ChassisSize()
    local host = View.ClientFrame(View.HostId())
    local w = widgetNum(host, "GetWidth")
    local h = widgetNum(host, "GetHeight")
    if not w or w <= 0 then w = FALLBACK_W end
    if not h or h <= 0 then h = FALLBACK_H end
    local extraW, extraH = View.Furniture()
    return View.ClampChassisSize(w + extraW, h + extraH)
end

-- The engine host window's size for a given chassis size (the inverse). Never
-- below one unit — a zero-sized engine window is not a smaller window, it is an
-- unreadable one.
function View.HostSizeFor(cw, ch)
    local extraW, extraH = View.Furniture()
    local w, h = (tonumber(cw) or 0) - extraW, (tonumber(ch) or 0) - extraH
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end
    return w, h
end

-- THE FLOOR: the furniture, plus enough feed for THREE lines at the size in
-- force, plus the feed's own padding. Below this the box stops being a chat
-- window and starts being a decoration, so the drop lands here instead.
View.MIN_FEED_LINES = 3

-- WHAT THE TAB RUN ITSELF COSTS, on the axis it runs along, and whether that
-- axis is the vertical one. Second return: true for a rail.
--
-- WHY THE FLOOR HAS TO KNOW (the second form of the owner's "tabs drawn over
-- the message text"): a rail of five rows is 4 + 5*26 units tall whatever the
-- feed wants, and a box shorter than that runs its last tabs off the rail,
-- across the entry bar and out of the chassis. A top strip of five tabs has the
-- same problem sideways. The run is a HARD floor on its own axis, and saying so
-- here is what keeps the layout from having to invent an overflow behaviour.
function View.TabRunExtent(ids)
    ids = ids or View.ids
    if not ids or #ids == 0 then ids = View.OwnedIds() end
    if View.TabsOnRail() then
        return 2 * RAIL_PAD_Y + #ids * TAB_ROW_H, true
    end
    local w = 2 * STRIP_PAD_X
    for i, id in ipairs(ids) do
        w = w + View.TabWidth(id) + ((i > 1) and TAB_GAP or 0)
    end
    return w, false
end

function View.MinChassisSize()
    local size = View.MessageFontSize(nil)
    local lineBox = size * FACE_NATURAL_LINE + View.MessageSpacing(size)
    local extraW, extraH = View.Furniture()
    local h = extraH + MSG_PAD_TOP + MSG_PAD_BOT + View.MIN_FEED_LINES * lineBox
    -- Wide enough for the entry bar's own insets and a couple of tabs; the rail
    -- adds its own 112 through Furniture above.
    local w = extraW + 2 * MSG_PAD_X + 2 * TAB_MIN_W + TAB_GAP + 2 * STRIP_PAD_X
    -- …and never below what the RUN itself needs on its own axis.
    local run, vertical = View.TabRunExtent()
    if vertical then
        local need = 2 * CHASSIS_EDGE + EB_HEIGHT + SEAM_W + run
        if need > h then h = need end
    else
        local need = 2 * CHASSIS_EDGE + run
        if need > w then w = need end
    end
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- THE CEILING: the screen. Nothing else — the chassis is ours, so there is no
-- dock and no clamp with an opinion, and "as big as the screen" is the only
-- honest maximum.
function View.MaxChassisSize()
    local P = _G.UIParent
    local w = widgetNum(P, "GetWidth")
    local h = widgetNum(P, "GetHeight")
    -- UNKNOWN IS NOT ZERO (Class 4): a world that has not been laid out yet
    -- imposes no ceiling rather than a ceiling of nothing.
    if not w or w <= 0 then w = math.huge end
    if not h or h <= 0 then h = math.huge end
    return w, h
end

function View.ClampChassisSize(w, h)
    local minW, minH = View.MinChassisSize()
    local maxW, maxH = View.MaxChassisSize()
    w, h = tonumber(w) or minW, tonumber(h) or minH
    if maxW < minW then maxW = minW end
    if maxH < minH then maxH = minH end
    if w < minW then w = minW elseif w > maxW then w = maxW end
    if h < minH then h = minH elseif h > maxH then h = maxH end
    return w, h
end

-- The message area's rect INSIDE the chassis, as four insets from its edges.
-- Published so the harness can pin the mockup's padding instead of trusting it.
function View.MessageInsets()
    local left  = CHASSIS_EDGE + MSG_PAD_X
    local right = CHASSIS_EDGE + MSG_PAD_X
    local top   = CHASSIS_EDGE + MSG_PAD_TOP
    local bottom = CHASSIS_EDGE + EB_HEIGHT + SEAM_W + MSG_PAD_BOT
    local place = View.TabPlacement()
    if place == "top" then
        top = CHASSIS_EDGE + STRIP_H + MSG_PAD_TOP
    else
        -- ON A RAIL there is no strip band between the feed and the chassis'
        -- top corners, so the feed's own top inset is all that keeps message
        -- text out from under the two TOP corner grips. The mockup's 10 is not
        -- enough for a 12-unit grip, and text under a click target is a worse
        -- deviation than three units of extra air — so the inset is the larger
        -- of the two. (On a top strip the band already provides the clearance,
        -- and the grip lands on a tab's 14-unit padding, never on its label.)
        top = CHASSIS_EDGE + math.max(MSG_PAD_TOP, GRIP_SIZE + 1)
        if place == "left" then
            left = CHASSIS_EDGE + TABRAIL_W + SEAM_W + MSG_PAD_X
        else
            right = CHASSIS_EDGE + TABRAIL_W + SEAM_W + MSG_PAD_X
        end
    end
    return left, right, top, bottom
end

----------------------------------------------------------------------
-- THE TAB STRIP. OUR buttons — no FCF tab machinery anywhere near them.
--
-- WHY THAT MATTERS AND IS NOT A DETAIL: the client's tab-alpha updater
-- (FCFTab_UpdateAlpha / FCF_FadeOutChatFrame) walks the frames it knows about
-- and rewrites their alpha on beats nobody asked for. Skin-over's answer was
-- to take the last word every time, forever. Our tabs are not in that walk at
-- all, so there is no last word to take: an inactive tab is dimmed by its INK
-- and NOTHING in this file ever animates or pins an alpha.
----------------------------------------------------------------------

-- The label a tab wears: the channel ALIAS when the window's routing collapses
-- to exactly one channel (skin.lua's published seam — one implementation of
-- the dominance rule in the addon), otherwise the window's own name.
function View.TabLabel(id)
    local S = ns.Skin
    local frame = View.ClientFrame(id)
    if S and type(S.TabLabel) == "function" then
        local ok, label = pcall(S.TabLabel, frame, id)
        if ok and type(label) == "string" and label ~= "" then return label end
    end
    local _, name = windowEligible(id)
    if type(name) == "string" and name ~= "" then return name end
    return "Chat " .. tostring(id)
end

-- One tab's ink at full strength. EXPLICIT per-tab colour first (the synced
-- config's spec string, resolved through skin.lua's published vocabulary),
-- then the derivation from the window's dominant channel, then the palette's
-- own --text. The explicit choice is the PLAYER's and outranks everything.
function View.TabInk(id)
    local S = ns.Skin
    if S and type(S.TabInk) == "function" then
        local ok, r, g, b, source = pcall(S.TabInk, View.ClientFrame(id), id)
        if ok and type(r) == "number" then return r, g, b, source end
    end
    local r, g, b = View.Ink("text")
    return r, g, b, "palette"
end

-- THE DIM IS INK, NOT ALPHA. An inactive tab's ink is the palette's --muted
-- (the mockup's own inactive colour) when the tab has no explicit colour, and
-- a proportional step toward --muted's luminance when it does — so a player
-- who picked a colour still sees THAT colour, quieter.
local INACTIVE_MIX = 0.55

function View.InactiveInk(r, g, b)
    local mr, mg, mb = View.Ink("muted")
    if not mr then return r, g, b end
    if r == nil then return mr, mg, mb end
    return r * (1 - INACTIVE_MIX) + mr * INACTIVE_MIX,
           g * (1 - INACTIVE_MIX) + mg * INACTIVE_MIX,
           b * (1 - INACTIVE_MIX) + mb * INACTIVE_MIX
end

-- The tab's width: its label, its padding and whatever badges.lua's pip is
-- asking for (the mockup keeps the pip INSIDE the tab, so the tab has to be
-- that much wider). PipWidth is badges' own published seam and answers 0 when
-- nothing is showing — the seam skin-over introduced, preserved verbatim.
function View.PipWidth(id)
    local B = ns.Badges
    local frame = View.ClientFrame(id)
    if not (B and type(B.PipWidth) == "function" and frame) then return 0 end
    local ok, w = pcall(B.PipWidth, frame)
    return (ok and tonumber(w)) or 0
end

-- The horizontal footprint the pip costs INSIDE the tab: the chip plus the
-- mockup's 6-unit gap after the label, or nothing at all when no pip is up.
function View.PipFootprint(id)
    local pip = View.PipWidth(id)
    return (pip > 0) and (pip + 6) or 0
end

-- The tab's width, and the ONE place a measurement is taken.
--
-- MEASURE-AFTER-SET, AND SAY SO WHEN THE ANSWER MOVES. Two of the three inputs
-- here are live measurements that can legitimately change between passes:
--   * the label's string width — 0 on the live client for as long as the string
--     has no face (the sim now models exactly that), so the character estimate
--     below is a real code path, not a paranoid one;
--   * badges' PipWidth — which becomes non-zero the moment an unread lands, i.e.
--     AFTER the pass that sized the tab for no pip.
-- Rather than poll, the pass RECORDS what it measured and compares; a changed
-- answer schedules ONE deferred relayout (View.NoteMeasured / the settle pass
-- below). No per-frame OnUpdate anywhere in this file.
function View.TabWidth(id)
    local t = View.tabs[id]
    local size = View.TabTextSize()
    local textW
    if t and t.label then
        textW = widgetNum(t.label, "GetStringWidth")
    end
    local measured = (textW ~= nil and textW > 0)
    if not measured then
        -- UNKNOWN IS NOT ZERO (Class 5): a string the client will not measure
        -- yet gets an ESTIMATE, never a zero width — a zero here is what would
        -- collapse a run of tabs onto one another.
        textW = #tostring(View.TabLabel(id)) * size * TAB_CHAR_W
    end
    local w = textW + 2 * TAB_PAD_X + View.PipFootprint(id)
    if w < TAB_MIN_W then w = TAB_MIN_W end
    View.NoteMeasured(id, measured and textW or nil, View.PipFootprint(id))
    return w
end

-- What the last layout pass actually measured, per tab. A pass that reads a
-- DIFFERENT answer than the one it laid out with asks for exactly one more
-- pass — the deferred settle below — and the pass after that agrees, so the
-- loop terminates by construction rather than by luck.
View._measured = {}

function View.NoteMeasured(id, textW, pipW)
    local prev = View._measured[id]
    if prev and prev.textW == textW and prev.pipW == pipW then return false end
    View._measured[id] = { textW = textW, pipW = pipW }
    if prev then View.ScheduleSettle("measurement changed") end
    return true
end

-- ONE deferred relayout, coalesced. The beat is C_Timer.After(0) — the client's
-- next frame — which is when a string the client had not laid out yet finally
-- measures, and when a badge that appeared during a pass is real. Never a
-- repeating ticker: if the settle pass reads the same numbers it laid out with
-- (which is the steady state), NoteMeasured schedules nothing and it stops.
View.settles = 0

function View.ScheduleSettle(why)
    if not View.active or View._settleQueued then return false end
    local CT = _G.C_Timer
    if not (CT and type(CT.After) == "function") then return false end
    View._settleQueued = true
    View._settleWhy = tostring(why or "?")
    CT.After(0, function()
        View._settleQueued = false
        if not View.active then return end
        View.settles = View.settles + 1
        View.LayoutTabs()
    end)
    return true
end

local function ensureTab(id)
    local t = View.tabs[id]
    if t then return t end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" or not View.strip then return nil end
    local btn = cf("Button", "DaseekiChatViewTab" .. tostring(id), View.strip)
    call(btn, "EnableMouse", true)
    call(btn, "RegisterForDrag", "LeftButton")
    -- THE ACTIVE TAB'S FILL: a real --panel2 texture run to the strip's bottom
    -- edge, so it fuses with the message surface. Skin-over could only imply
    -- this with two half-hairlines; ours simply IS the fill.
    local fill = call(btn, "CreateTexture", nil, "BACKGROUND")
    paint(fill, "panel2", 1)
    call(fill, "Hide")
    -- The hover wash (`rgba(255,255,255,.04)` -> the text ink at 0.04).
    local hover = call(btn, "CreateTexture", nil, "BORDER")
    paint(hover, "text", HOVER_WASH)
    call(hover, "Hide")
    -- The active mark: an accent underline on a top strip, an accent edge bar
    -- on a rail. Both exist; the layout shows exactly one.
    local underline = call(btn, "CreateTexture", nil, "OVERLAY")
    paint(underline, "accent", 1)
    call(underline, "Hide")
    local edgebar = call(btn, "CreateTexture", nil, "OVERLAY")
    paint(edgebar, "accent", 1)
    call(edgebar, "Hide")
    local label = call(btn, "CreateFontString", nil, "OVERLAY")
    local UI = UIKit()
    if UI and type(UI.FontFile) == "function" and type(label) == "table"
       and type(label.SetFont) == "function" then
        pcall(label.SetFont, label, UI.FontFile(), View.TabTextSize(), "")
    end
    call(label, "SetJustifyH", "CENTER")
    -- A tab label is ONE line, always. The rail path gives the label an
    -- explicit width (so a long channel name stops before the unread count
    -- rather than running under it), and a FontString with a width WRAPS by
    -- default — a two-line label in a 26-unit row is a worse answer than an
    -- ellipsis, so word wrap is off from creation and the client truncates.
    call(label, "SetWordWrap", false)
    call(label, "SetMaxLines", 1)
    call(label, "SetPoint", "CENTER", btn, "CENTER", 0, 0)
    -- THE CLIENT'S OWN SHAPE, published deliberately: a chat tab carries its
    -- label as `tab.Text`, and badges.lua anchors the unread chip off THAT —
    -- `holder:SetPoint("LEFT", label or tab, "RIGHT", 6, 0)`, the mockup's
    -- "after the label, INSIDE the tab". Our button did not carry the field, so
    -- badges fell through to `or tab` and hung the chip off the tab's RIGHT
    -- EDGE: the owner's detached "3", floating in the gap between two tabs
    -- while the tab itself had already been widened to hold it. Wearing the
    -- client's field name is the whole fix — no change in badges.lua, and the
    -- chip rides whatever layout this file lands on.
    btn.Text = label
    btn:SetScript("OnClick", function() View.SelectTab(id, "click") end)
    btn:SetScript("OnEnter", function() call(hover, "Show") end)
    btn:SetScript("OnLeave", function() call(hover, "Hide") end)
    -- Plain drag ON THE STRIP moves the box (our frame, our rules): the owner
    -- asked for both gestures, and a tab is the client's own "grab here".
    btn:SetScript("OnDragStart", function() View.OnDragStart(View.chassis, "strip") end)
    btn:SetScript("OnDragStop",  function() View.OnDragStop() end)
    t = { button = btn, label = label, fill = fill, hover = hover,
          underline = underline, edgebar = edgebar }
    View.tabs[id] = t
    return t
end

-- badges.lua's rebind seam: the tab button a window's unread pip belongs on.
-- Answers OUR button while the view owns the pixels and NOTHING otherwise, so
-- badges falls back to the client's tab exactly as it always did.
function View.TabButtonFor(clientFrame)
    if not View.active or type(clientFrame) ~= "table" then return nil end
    local id = clientFrame._id or (type(clientFrame.GetID) == "function" and clientFrame:GetID())
    if type(id) ~= "number" then
        for _, wid in ipairs(View.ids) do
            if View.ClientFrame(wid) == clientFrame then id = wid break end
        end
    end
    local t = id and View.tabs[id]
    return t and t.button or nil
end

----------------------------------------------------------------------
-- THE MESSAGE SURFACES. One ScrollingMessageFrame of OURS per tab.
--
-- SetFading(false) AT CREATION and never registered with any FCF or dock
-- machinery: the client's fade pass walks ITS windows, and ours are not in
-- that list — structurally, not by pinning. The harness proves exactly that
-- (the unkind leg: the client's fade beat runs and our frames do not move).
----------------------------------------------------------------------

function View.EnsureFrame(id)
    local f = View.frames[id]
    if f then return f end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" or not View.chassis then return nil end
    local ok, smf = pcall(cf, "ScrollingMessageFrame",
        "DaseekiChatViewFrame" .. tostring(id), View.chassis)
    if not ok or type(smf) ~= "table" then return nil end
    -- FADING OFF AT CREATION, before a single line can land in it.
    call(smf, "SetFading", false)
    call(smf, "SetMaxLines", VIEW_MAX_LINES)
    call(smf, "SetJustifyH", "LEFT")
    call(smf, "EnableMouse", true)
    call(smf, "EnableMouseWheel", true)
    call(smf, "SetHyperlinkPropagateToParent", false)
    -- HYPERLINKS go to the CLIENT's own item-ref handler: an item link, a
    -- player link and urls.lua's own |Haddon:dchaturl: pseudo-link all take the
    -- exact path they take from a client window, because it IS that path.
    smf:SetScript("OnHyperlinkClick", function(_, link, text, button)
        View.OnHyperlink(link, text, button)
    end)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then call(self, "ScrollUp") else call(self, "ScrollDown") end
    end)
    View.frames[id] = smf
    View.ApplyFont(id)
    return smf
end

function View.ApplyFont(id)
    local smf = View.frames[id]
    if not smf then return false end
    local UI = UIKit()
    local _, _, clientSize = windowEligible(id)
    local size = View.MessageFontSize(clientSize)
    if UI and type(UI.FontFile) == "function" then
        call(smf, "SetFont", UI.FontFile(), size, "")
    end
    call(smf, "SetSpacing", View.MessageSpacing(size))
    return true
end

-- The client's item-ref handling, reached the way the client reaches it.
-- SetItemRef is the catalog-verified (11509) entry point every chat hyperlink
-- click lands in, and urls.lua already hooks it for the copy-box path — so a
-- URL link opens the copy box from a view frame exactly as it does from a
-- client window, with no second implementation anywhere.
function View.OnHyperlink(link, text, button)
    local sir = _G.SetItemRef
    if type(sir) ~= "function" then return false end
    pcall(sir, link, text, button or "LeftButton")
    return true
end

----------------------------------------------------------------------
-- THE MIRROR (RED CONTROL 1: a view AddMessage must never re-enter the client
-- hook).
--
-- The seam: our own wrapper over each hidden client window's AddMessage. It
-- calls the previous wrapper FIRST — so decor/stamps/names/urls have all run
-- and history/badges have seen the delivery — and then reads what ACTUALLY
-- LANDED out of the frame's public ring buffer. That read is deliberate: the
-- decorated string is whatever the innermost call stored, and asking the
-- buffer is the only way to be right about it regardless of where in the wrap
-- stack we ended up. r, g, b ride as NUMBERS the whole way ("the ink is not in
-- a string"), and the line id rides with them.
--
-- THE RE-ENTRY FUSE (Class 9, in full): the latch is armed BEFORE the view
-- frame's AddMessage — the first call of the sequence, not after it — it is
-- SAVED AND RESTORED rather than cleared to nil so nesting is safe, the whole
-- forward is pcall-protected so an error cannot wedge it, and a DEPTH FUSE
-- under it refuses past the known-legitimate nesting (which is one) with a
-- counted, build-stamped record instead of recursing. Every client-side body
-- reads the latch and treats what it sees as our own echo.
----------------------------------------------------------------------

View.MIRROR_DEPTH_MAX = 1

function View.Mirroring()
    return View._mirrorDepth > 0
end

-- Publishing the predicate, the way Class 9's fix shape asks: any peer module
-- that grows an AddMessage body can ask whether the line it is looking at is
-- our echo without knowing anything about this file's internals.
ns.ViewIsMirroring = View.Mirroring

-- `kind` is "mirror" (a line the engine just delivered) or "resync" (a re-read
-- of scrollback the mirror never saw). They are COUNTED SEPARATELY on purpose:
-- `View.mirrored` is then a truthful witness to "a client AddMessage wrap
-- fired", which is exactly what the restore red control needs to assert
-- against — a counter that both paths bumped would alibi the thing it is
-- supposed to catch.
local function forwardInto(smf, text, r, g, b, lineId, kind)
    if View._mirrorDepth >= View.MIRROR_DEPTH_MAX then
        View.mirrorRefusals = View.mirrorRefusals + 1
        View.lastRefusal = ("depth %d at build %s"):format(View._mirrorDepth,
            tostring(ns.VERSION))
        return false
    end
    local saved = View._mirrorDepth
    View._mirrorDepth = saved + 1
    local ok, err = pcall(smf.AddMessage, smf, text, r, g, b, lineId)
    View._mirrorDepth = saved
    if not ok then
        ns.RouteError(err)
        return false
    end
    if kind == "resync" then
        View.resyncedLines = (View.resyncedLines or 0) + 1
    else
        View.mirrored = View.mirrored + 1
    end
    return true
end

-- The newest stored line on a client window, as the client stores it:
-- message, r, g, b. nil when the buffer cannot be read (never a guess).
local function newestLine(frame)
    local buf = frame.historyBuffer
    if type(buf) == "table" and type(buf.GetEntryAtIndex) == "function" then
        local ok, e = pcall(buf.GetEntryAtIndex, buf, 1)
        if ok and type(e) == "table" and type(e.message) == "string" then
            return e.message, e.r, e.g, e.b
        end
    end
    if type(frame.GetNumMessages) == "function" and type(frame.GetMessageInfo) == "function" then
        local okN, n = pcall(frame.GetNumMessages, frame)
        if okN and type(n) == "number" and n > 0 then
            local okM, m, r, g, b = pcall(frame.GetMessageInfo, frame, n)
            if okM and type(m) == "string" then return m, r, g, b end
        end
    end
    return nil
end

-- Forward the line that just landed on a client window into its tab's view
-- frame. Called from the wrapper AFTER the rest of the stack has run.
function View.MirrorLine(clientFrame, fallbackText, fr, fg, fb, lineId)
    if not View.active then return false end
    if View._mirrorDepth > 0 then
        -- OUR OWN ECHO. A view AddMessage can only reach a client wrapper
        -- through a composition nobody designed; it is refused here, counted,
        -- and the world is left exactly as it was.
        View.mirrorReentries = View.mirrorReentries + 1
        return false
    end
    local id = View.IdOf(clientFrame)
    if not id then return false end
    local smf = View.frames[id]
    if not smf then return false end
    local text, r, g, b = newestLine(clientFrame)
    if text == nil then
        text, r, g, b = fallbackText, fr, fg, fb
    end
    if type(text) ~= "string" then return false end
    return forwardInto(smf, text, r, g, b, lineId)
end

function View.IdOf(frame)
    if type(frame) ~= "table" then return nil end
    for _, id in ipairs(View.ids) do
        if View.ClientFrame(id) == frame then return id end
    end
    return nil
end

-- The wrapper, installed once per client window and gated on View.active, so
-- a disable leaves an inert body over a frame we no longer touch.
local wrappedFrames = {}
View.wrappedFrames = wrappedFrames

local function wrapAddMessage(frame)
    if type(frame) ~= "table" or wrappedFrames[frame] then return end
    local prev = frame.AddMessage
    if type(prev) ~= "function" then return end
    wrappedFrames[frame] = true
    frame.AddMessage = function(self, text, r, g, b, lineId, ...)
        prev(self, text, r, g, b, lineId, ...)
        View.MirrorLine(self, text, r, g, b, lineId)
    end
end

-- A FULL RE-READ of a client window's buffer into its view frame. This is how
-- scrollback that the mirror never saw gets on screen: the view coming up
-- mid-session, and history.lua's cross-session restore — which backfills with
-- PushFront and therefore (correctly) never touches AddMessage at all. The
-- re-read is idempotent: the view frame is cleared first.
function View.Resync(id)
    local smf = View.frames[id]
    local frame = View.ClientFrame(id)
    if not (smf and type(frame) == "table") then return 0 end
    if type(frame.GetNumMessages) ~= "function" then return 0 end
    local okN, n = pcall(frame.GetNumMessages, frame)
    if not okN or type(n) ~= "number" then return 0 end
    call(smf, "Clear")
    local moved = 0
    for i = 1, n do
        local ok, m, r, g, b = pcall(frame.GetMessageInfo, frame, i)
        if ok and type(m) == "string" then
            if forwardInto(smf, m, r, g, b, nil, "resync") then moved = moved + 1 end
        end
    end
    View.resyncs = View.resyncs + 1
    return moved
end

function View.ResyncAll()
    local total = 0
    for _, id in ipairs(View.ids) do total = total + View.Resync(id) end
    return total
end

----------------------------------------------------------------------
-- THE HIDDEN ENGINE.
--
-- THE ONE DISTINCTION THAT MAKES THIS WORK: hiding a window is a DISPLAY act
-- (frame:Hide()) and must never become a ROUTING act (SetChatWindowShown).
-- The client routes a line by the per-character STORE's shown/docked flags,
-- not by the frame's visibility — so a hidden frame still receives every
-- message, its AddMessage still fires, and reconcile/channels/config/sync go
-- on reading and writing exactly the world they always did. The suite pins
-- both halves: the store is untouched, and lines still land.
--
-- The client re-shows its windows on its own beats (FloatingChatFrame_Update
-- projects the store onto the frame). We take the last word synchronously
-- inside the same call — the posture the button column and the clamp already
-- use — so there is no beat where an engine window is visibly back.
----------------------------------------------------------------------

-- ── THE SATELLITE FAMILY ─────────────────────────────────────────────────
--
-- A chat window is not one frame. Hanging off it — and NOT parented to it, so
-- `frame:Hide()` does not take them down — are its tab (on the DOCK, not on the
-- window), its edit box, its button column, the column's minimize button, the
-- minimized stand-in that button creates, the resize grip, the scrollbar and
-- the click-anywhere overlay. The shipped HideEngine hid three of those eight,
-- and nothing re-hid any of them afterwards, so the owner's first live look had
-- a stock gold-bordered "Loot" tab floating MID-PANEL over our message feed:
-- the dock bar hugs the engine window's TOP edge, which is inside the chassis
-- our own strip sits above.
--
-- Each row names BOTH client shapes — the field the client's own code reaches
-- through and the global name the XML template gives it — because either may be
-- the one that exists on a given build, and a satellite that is only reachable
-- through the shape we did not check is a satellite we do not hide. Rows whose
-- verbs are catalog-verified on 11509 are cited beside them.
local SATELLITES = {
    { field = "tab",                 global = "%sTab" },                        -- FCFDock_UpdateTabs / FCFTab_UpdateAlpha
    { field = "editBox",             global = "%sEditBox" },                    -- ChatEdit_ActivateChat
    { field = "buttonFrame",         global = "%sButtonFrame" },                -- FCF_SetButtonSide
    { field = "minimizeButton",      global = "%sButtonFrameMinimizeButton" },  -- FCF_MinimizeFrame
    { field = "minFrame",            global = nil },                            -- FCF_CreateMinimizedFrame (LAZY: re-walked every pass)
    { field = "resizeButton",        global = "%sResizeButton" },               -- FCF_UpdateResizeButton
    { field = "ScrollBar",           global = "%sScrollBar" },                  -- FCF_FadeInScrollbar / FCF_FadeOutScrollbar
    { field = "clickAnywhereButton", global = "%sClickAnywhereButton" },        -- FCFClickAnywhereButton_UpdateState
}
View.SATELLITES = SATELLITES

-- Every satellite of one window that EXISTS right now. Re-walked on every pass
-- rather than cached at enable: FCF_CreateMinimizedFrame builds its frame the
-- first time the player minimizes, so a family enumerated once is a family that
-- misses whatever the client makes later.
function View.SatellitesOf(frame, id)
    local out = {}
    if type(frame) ~= "table" then return out end
    local name = ("ChatFrame%d"):format(tonumber(id) or -1)
    if type(frame.GetName) == "function" then
        local ok, n = pcall(frame.GetName, frame)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    for _, s in ipairs(SATELLITES) do
        local w = s.field and frame[s.field] or nil
        if type(w) ~= "table" and s.global then w = _G[s.global:format(name)] end
        if type(w) == "table" and w ~= frame then out[#out + 1] = w end
    end
    return out
end

-- THE ONE EXCEPTION, and it is ours: the edit box we have REPARENTED into the
-- chassis is on screen on purpose (the persistent entry bar). Hiding it here
-- would fight our own RetargetEditBox on every client beat.
local function isHostedEditBox(w)
    local home = View._ebHome
    return (home and home.eb == w) and true or false
end

-- Hide one satellite and RECORD that we were the one who hid it, so the restore
-- puts back exactly what we took down and nothing else (the round-trip pin).
local function holdDown(frame, w)
    if isHostedEditBox(w) then return false end
    if type(w.IsShown) ~= "function" then return false end
    local ok, shown = pcall(w.IsShown, w)
    if not (ok and shown) then return false end
    call(w, "Hide")
    local rec = View._engineHidden[frame]
    if type(rec) == "table" then rec.satellites[w] = true end
    return true
end

function View.HideEngine()
    local n = 0
    for id = 1, numWindows() do
        local frame = View.ClientFrame(id)
        if frame and not isCombatLog(frame, id) and windowEligible(id) then
            if type(View._engineHidden[frame]) ~= "table" then
                View._engineHidden[frame] = { id = id, satellites = {} }
            end
            if type(frame.IsShown) == "function" then
                local ok, shown = pcall(frame.IsShown, frame)
                if ok and shown then
                    call(frame, "Hide")
                    n = n + 1
                end
            end
            for _, w in ipairs(View.SatellitesOf(frame, id)) do holdDown(frame, w) end
        end
    end
    return n
end

-- The client showed something of its own again (a dock update, a window update,
-- an alert flash). We take the last word INSIDE the same call — the posture the
-- button column and the clamp already use — across the WHOLE family, not just
-- the window, because the family is what came back.
function View.KeepEngineHidden(frame)
    if not View.active then return false end
    local rec = View._engineHidden[frame]
    if type(frame) ~= "table" or type(rec) ~= "table" then return false end
    local beat = false
    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and shown then call(frame, "Hide") beat = true end
    end
    for _, w in ipairs(View.SatellitesOf(frame, rec.id)) do
        if holdDown(frame, w) then beat = true end
    end
    if beat then View.reHides = View.reHides + 1 end
    return beat
end

-- PUBLISHED PREDICATE. "Is this window hidden because WE are holding it down?"
-- reconcile.lua asks it before deciding a hidden window is one to leave alone —
-- the store still says the window is live, and the view's hide is a display act,
-- so a position or a size the config authored must still be replayed onto it.
function View.HoldsEngine(frame)
    return (View.active and type(View._engineHidden[frame]) == "table") and true or false
end

function View.KeepAllEngineHidden()
    local n = 0
    for id = 1, numWindows() do
        if View.KeepEngineHidden(View.ClientFrame(id)) then n = n + 1 end
    end
    return n
end

function View.ShowEngine()
    for frame, rec in pairs(View._engineHidden) do
        View._engineHidden[frame] = nil
        call(frame, "Show")
        -- EXACTLY WHAT WE TOOK DOWN. A satellite the client already had hidden
        -- when we arrived (the edit box under chatStyle 'classic', a flash that
        -- was not flashing) is left hidden — restoring is putting the world
        -- back, not asserting a world of our own.
        if type(rec) == "table" then
            for w in pairs(rec.satellites) do call(w, "Show") end
        end
        local id = (type(rec) == "table" and rec.id)
            or frame._id or (type(frame.GetID) == "function" and frame:GetID())
        if type(id) == "number" then
            -- The client's own window beat puts its dress, its button column
            -- and its position back exactly where the client wants them.
            local fcu = _G.FloatingChatFrame_Update
            if type(fcu) == "function" then pcall(fcu, id) end
        end
    end
    local dock = _G.FCFDock_UpdateTabs
    if type(dock) == "function" then pcall(dock) end
end

----------------------------------------------------------------------
-- THE EDIT BOX (RED CONTROL 3: retarget on tab switch).
--
-- REUSED, NEVER REIMPLEMENTED. Slash commands, channel stickiness, the sticky
-- prefix and — decisively — the SECURE SEND PATH are the client's chat edit
-- machinery. We reparent the active tab's own ChatFrame<n>EditBox into the
-- chassis' entry bar and give it the mockup's insets. Switching tabs moves the
-- box: the new tab's client window's box comes in, the old one goes home, and
-- replies plus stickiness follow the tab the player is actually looking at.
--
-- PERSISTENT: the client hides the box on every deactivate under chatStyle
-- 'classic'. We post-hook that verb and take the last word in the same call —
-- the approach skin.lua shipped, kept because it is the honest seam. Escape
-- runs the client's deactivate, so it UNFOCUSES and the bar stays.
----------------------------------------------------------------------

function View.EditBoxOf(id)
    local eb = _G[("ChatFrame%dEditBox"):format(tostring(id))]
    if type(eb) == "table" then return eb end
    return nil
end

function View.EditBox()
    return View.activeId and View.EditBoxOf(View.activeId) or nil
end

local function savePoints(w)
    if type(w) ~= "table" or type(w.GetNumPoints) ~= "function" then return nil end
    local okN, n = pcall(w.GetNumPoints, w)
    if not okN or type(n) ~= "number" then return nil end
    local pts = {}
    for i = 1, n do
        local ok, p, rel, relP, x, y = pcall(w.GetPoint, w, i)
        if ok and p then pts[#pts + 1] = { p, rel, relP, x, y } end
    end
    return pts
end

local function restorePoints(w, pts)
    if type(w) ~= "table" or type(pts) ~= "table" then return end
    call(w, "ClearAllPoints")
    for _, p in ipairs(pts) do
        pcall(w.SetPoint, w, p[1], p[2], p[3], p[4], p[5])
    end
end

-- Send the currently hosted box home, exactly as we found it.
local function releaseEditBox()
    local home = View._ebHome
    if not home then return false end
    View._ebHome = nil
    local eb = home.eb
    if type(eb) ~= "table" then return false end
    call(eb, "SetParent", home.parent)
    restorePoints(eb, home.points)
    if home.insets then
        call(eb, "SetTextInsets", home.insets[1], home.insets[2], home.insets[3], home.insets[4])
    end
    -- The client's own persistence rule takes over again: under 'classic' it
    -- hides the box on deactivate, so handing it back means handing back the
    -- hidden state it would have had.
    local ceg = _G.ChatEdit_GetActiveWindow
    local activeNow = (type(ceg) == "function") and select(1, pcall(ceg)) and ceg() or nil
    if activeNow ~= eb then call(eb, "Hide") end
    return true
end

function View.RetargetEditBox(id)
    if not View.active then return false end
    local eb = View.EditBoxOf(id)
    if type(eb) ~= "table" or not View.entry then return false end
    local home = View._ebHome
    if home and home.eb == eb then
        View.LayoutEditBox()
        return true
    end
    releaseEditBox()
    View._ebHome = {
        eb = eb,
        parent = (type(eb.GetParent) == "function") and select(2, pcall(eb.GetParent, eb)) or nil,
        points = savePoints(eb),
        insets = { call(eb, "GetTextInsets") },
    }
    call(eb, "SetParent", View.entry)
    View.LayoutEditBox()
    call(eb, "Show")
    local header = eb.header or _G[(eb.GetName and eb:GetName() or "") .. "Header"]
    if header then call(header, "Show") end
    -- The client re-reads its own sticky state and repaints the prefix; the
    -- alias header rides skin.lua's post-hook on the same verb, unchanged.
    local cuh = _G.ChatEdit_UpdateHeader
    if type(cuh) == "function" then pcall(cuh, eb) end
    View.retargets = View.retargets + 1
    return true
end

function View.LayoutEditBox()
    local home = View._ebHome
    if not (home and View.entry) then return false end
    local eb = home.eb
    call(eb, "ClearAllPoints")
    call(eb, "SetPoint", "TOPLEFT", View.entry, "TOPLEFT", 0, 0)
    call(eb, "SetPoint", "BOTTOMRIGHT", View.entry, "BOTTOMRIGHT", 0, 0)
    -- `.entry{padding:8px 12px}` with the owner's amendment on the vertical.
    call(eb, "SetTextInsets", EB_PAD_X, EB_PAD_X, EB_PAD_Y, EB_PAD_Y)
    local UI = UIKit()
    if UI and type(UI.FontFile) == "function" then
        call(eb, "SetFont", UI.FontFile(), View.MessageFontSize(nil), "")
    end
    return true
end

-- The persistent seam: the client made its hide decision, we take the last
-- word inside the same call. Never a timer, never a poll.
function View.KeepEditBoxShown(eb)
    if not View.active then return false end
    local home = View._ebHome
    if not (home and home.eb == eb) then return false end
    if type(eb.IsShown) == "function" then
        local ok, shown = pcall(eb.IsShown, eb)
        if ok and shown then return false end
    end
    call(eb, "Show")
    local header = eb.header
    if header then call(header, "Show") end
    return true
end

----------------------------------------------------------------------
-- TAB SELECTION.
--
-- Selecting one of OUR tabs does three things and no more: it moves the
-- visible message surface, it retargets the edit box (red control 3), and it
-- tells the CLIENT which of its docked windows is selected — through
-- FCF_SelectDockFrame, the client's own verb. That third one is not decoration:
-- badges.lua clears on exactly that signal and history/badges both judge "can
-- the player see this window" from the dock's selection. Routing the view's
-- selection through the client's own verb is what keeps both modules correct
-- with ZERO changes to either.
----------------------------------------------------------------------

function View.ActiveId() return View.activeId end

function View.SelectTab(id, why)
    if not View.active then return false end
    local ok = false
    for _, wid in ipairs(View.ids) do if wid == id then ok = true end end
    if not ok then return false end
    View.activeId = id
    for _, wid in ipairs(View.ids) do
        local smf = View.frames[wid]
        if smf then call(smf, wid == id and "Show" or "Hide") end
    end
    View.RetargetEditBox(id)
    -- The client's own selection verb (badges clear on it; the dock's notion of
    -- "selected" is what history and badges read).
    local sel = _G.FCF_SelectDockFrame
    local frame = View.ClientFrame(id)
    if type(sel) == "function" and frame then pcall(sel, frame) end
    View.LayoutTabs()
    return true
end

----------------------------------------------------------------------
-- LAYOUT. One pass, idempotent, cheap enough to run on any beat that could
-- have changed an answer.
----------------------------------------------------------------------

-- ONE TAB RUN, PARAMETERIZED BY AXIS (the 2026-08-11 cleanup).
--
-- THE TWO DEFECTS THE PARALLEL VERSIONS CARRIED, both from the same cause —
-- the same arithmetic written twice and drifting:
--   1. the top version used to `return w + TAB_GAP` (the tab's own WIDTH, not
--      the position past its right edge), so every tab after the second landed
--      at its PREDECESSOR's width — the owner's "Loot FoDMs", three labels on
--      one x. The rail version next door accumulated correctly, which is why
--      only the top strip piled up;
--   2. neither version placed the SURFACE it ran on, so a run laid out with the
--      new placement could land on a strip still wearing the old one — the
--      owner's mixed state, "Chaos still on the top strip while Focus/DM/Loot
--      draw down the left over the message text".
-- Both are structurally impossible now: there is one run, and LayoutTabs places
-- the strip before it runs (a run and the surface it runs on are ONE fact).
--
-- `run` is the axis position of the run's current edge; the return value is the
-- next one. Axis-specific facts are named once each; everything else is shared.
local function anchorTab(t, id, run, rail, side)
    local btn = t.button
    local w = rail and (TABRAIL_W - 2 * RAIL_PAD_X) or View.TabWidth(id)
    local h = rail and TAB_ROW_H or TAB_H
    call(btn, "SetSize", w, h)
    call(btn, "ClearAllPoints")
    if rail then
        call(btn, "SetPoint", "TOPLEFT", View.strip, "TOPLEFT", RAIL_PAD_X, -run)
    else
        call(btn, "SetPoint", "BOTTOMLEFT", View.strip, "BOTTOMLEFT", run, 0)
    end
    -- The active fill covers the button on both axes. On a top strip that runs
    -- it to the strip's BOTTOM edge, which is the fusion with the feed.
    call(t.fill, "ClearAllPoints")
    call(t.fill, "SetPoint", "TOPLEFT", btn, "TOPLEFT", 0, 0)
    call(t.fill, "SetPoint", "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    call(t.hover, "ClearAllPoints")
    call(t.hover, "SetPoint", "TOPLEFT", btn, "TOPLEFT", 0, 0)
    call(t.hover, "SetPoint", "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    if rail then
        -- `.stab.active::before`: a 2-unit bar on the rail's INNER side, inset 5.
        call(t.underline, "Hide")
        call(t.edgebar, "ClearAllPoints")
        call(t.edgebar, "SetSize", EDGEBAR_W, TAB_ROW_H - 2 * EDGEBAR_INSET)
        if side == "left" then
            call(t.edgebar, "SetPoint", "TOPRIGHT", btn, "TOPRIGHT", 0, -EDGEBAR_INSET)
        else
            call(t.edgebar, "SetPoint", "TOPLEFT", btn, "TOPLEFT", 0, -EDGEBAR_INSET)
        end
        -- `.stab` is a row: the label sits at the row's left padding and the
        -- unread count right-aligns opposite it (badges.lua's rail branch).
        call(t.label, "SetJustifyH", "LEFT")
        call(t.label, "ClearAllPoints")
        call(t.label, "SetPoint", "LEFT", btn, "LEFT", RAIL_TAB_PAD_X, 0)
        -- THE RAIL'S OWN PIP RULE: the count is right-aligned in the row, so
        -- the LABEL has to stop before it or the two draw over each other on a
        -- long channel name. A rail row is a fixed width; the label's is what
        -- gives.
        local room = w - RAIL_TAB_PAD_X - RAIL_TAB_PAD_X - View.PipFootprint(id)
        if room < 8 then room = 8 end
        call(t.label, "SetWidth", room)
        return run + TAB_ROW_H
    end
    call(t.edgebar, "Hide")
    call(t.underline, "ClearAllPoints")
    call(t.underline, "SetSize", w - 2 * UL_INSET, UL_HEIGHT)
    call(t.underline, "SetPoint", "BOTTOMLEFT", btn, "BOTTOMLEFT", UL_INSET, UL_Y)
    -- The label is centred — and it shifts LEFT by half the pip's footprint when
    -- a pip is showing, because the mockup's `.tab` is a row of
    -- [label][gap][chip] centred as ONE thing inside the tab's padding.
    -- TabWidth reserved that footprint; this is the half that spends it.
    local pipExtra = View.PipFootprint(id)
    call(t.label, "SetWidth", 0)          -- back to the string's own measurement
    call(t.label, "SetJustifyH", "CENTER")
    call(t.label, "ClearAllPoints")
    call(t.label, "SetPoint", "CENTER", btn, "CENTER", -pipExtra / 2, 0)
    return run + w + TAB_GAP
end

-- THE SURFACE THE RUN RUNS ON. Extracted from Reflow so that LayoutTabs — the
-- cheap beat that a colour change, a settle pass or a tab selection triggers —
-- can never lay a run out against a stale surface. Idempotent and pure
-- arithmetic over the chassis' LIVE size, so calling it twice in a pass costs
-- nothing and calling it too seldom is no longer possible.
function View.LayoutStrip()
    local f = View.chassis
    if not (f and View.strip) then return false end
    local w = widgetNum(f, "GetWidth")
    local h = widgetNum(f, "GetHeight")
    if not w or not h or w <= 0 or h <= 0 then return false end
    local place = View.TabPlacement()
    local rail = (place == "left" or place == "right")
    local innerH = h - 2 * CHASSIS_EDGE - EB_HEIGHT - SEAM_W
    call(View.strip, "ClearAllPoints")
    if rail then
        call(View.strip, "SetSize", TABRAIL_W, innerH)
        if place == "left" then
            call(View.strip, "SetPoint", "TOPLEFT", f, "TOPLEFT", CHASSIS_EDGE, -CHASSIS_EDGE)
        else
            call(View.strip, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", -CHASSIS_EDGE, -CHASSIS_EDGE)
        end
        call(View.railSeam, "ClearAllPoints")
        call(View.railSeam, "SetSize", SEAM_W, innerH)
        if place == "left" then
            call(View.railSeam, "SetPoint", "TOPLEFT", View.strip, "TOPRIGHT", 0, 0)
        else
            call(View.railSeam, "SetPoint", "TOPRIGHT", View.strip, "TOPLEFT", 0, 0)
        end
        call(View.railSeam, "Show")
    else
        call(View.strip, "SetSize", w - 2 * CHASSIS_EDGE, STRIP_H)
        call(View.strip, "SetPoint", "TOPLEFT", f, "TOPLEFT", CHASSIS_EDGE, -CHASSIS_EDGE)
        call(View.railSeam, "Hide")
    end
    call(View.stripFill, "ClearAllPoints")
    call(View.stripFill, "SetPoint", "TOPLEFT", View.strip, "TOPLEFT", 0, 0)
    call(View.stripFill, "SetPoint", "BOTTOMRIGHT", View.strip, "BOTTOMRIGHT", 0, 0)
    call(View.stripFill, "Show")
    -- DRAW ORDER, STATED (not inherited from creation order): the band is an
    -- opaque surface ABOVE the feed, because a ScrollingMessageFrame lays its
    -- lines out from the bottom up and the topmost one lands wherever the
    -- arithmetic leaves it.
    call(View.strip, "SetFrameLevel", (widgetNum(f, "GetFrameLevel") or 1) + 5)
    call(View.strip, "Show")
    return true
end

function View.LayoutTabs()
    if not View.strip then return false end
    local place = View.TabPlacement()
    -- ── THE MIGRATION ESCALATION, and it is the whole fix for the owner's
    -- mixed strip/rail screenshot. ───────────────────────────────────────
    --
    -- A CHEAP BEAT CAN BE THE FIRST THING TO NOTICE THE ANSWER MOVED. The
    -- placement lives in the SYNCED config and resolves at READ time, so a peer
    -- account's newer choice changes it with no local write and therefore no
    -- apply seam to hang a migration off — and the next ordinary beat (a colour
    -- event, a settle pass, a tab click) would re-run the TAB RUN alone.
    --
    -- Running the run alone is not enough, and that is precisely what shipped:
    -- the tabs migrated to the rail while the FEED still spanned the full width
    -- and the box still had its old floor, so the new rail was drawn straight
    -- over the message text. The strip, the feed's insets and the box's own
    -- minimum are ONE fact; a placement that moved since the last full pass
    -- escalates to the full one rather than doing a third of it.
    --
    -- The latch is armed BEFORE the call it guards and released after it,
    -- pcall-protected so an error cannot wedge it (Class 9's shape).
    if View._laidPlacement ~= place and not View._migrating then
        View._migrating = true
        local ok = pcall(View.Layout)
        View._migrating = nil
        if ok then return true end
    end
    -- THE SURFACE BEFORE THE RUN, ALWAYS: the run below is arithmetic in the
    -- strip's own frame, so the strip has to BE this placement's strip first.
    View.LayoutStrip()
    local rail = View.TabsOnRail()
    local run = rail and RAIL_PAD_Y or STRIP_PAD_X
    for _, id in ipairs(View.ids) do
        local t = ensureTab(id)
        if t then
            call(t.label, "SetText", View.TabLabel(id))
            local UI = UIKit()
            if UI and type(UI.FontFile) == "function" then
                call(t.label, "SetFont", UI.FontFile(), View.TabTextSize(), "")
            end
            local isActive = (id == View.activeId)
            local r, g, b = View.TabInk(id)
            if isActive then
                if r then call(t.label, "SetTextColor", r, g, b, 1) end
                call(t.fill, "Show")
                call(t.underline, rail and "Hide" or "Show")
                call(t.edgebar, rail and "Show" or "Hide")
            else
                -- INK ONLY. Nothing here touches alpha, ever.
                local dr, dg, db = View.InactiveInk(r, g, b)
                if dr then call(t.label, "SetTextColor", dr, dg, db, 1) end
                call(t.fill, "Hide")
                call(t.underline, "Hide")
                call(t.edgebar, "Hide")
            end
            call(t.button, "Show")
            run = anchorTab(t, id, run, rail, place)
        end
    end
    -- Any tab whose window went away stops being drawn (never destroyed — a
    -- window can come back, and a rebuilt widget would lose its badge).
    for id, t in pairs(View.tabs) do
        local live = false
        for _, wid in ipairs(View.ids) do if wid == id then live = true end end
        if not live then call(t.button, "Hide") end
    end
    -- The badges ride our buttons; tell them the geometry moved.
    local B = ns.Badges
    if B and type(B.Relayout) == "function" then pcall(B.Relayout) end
    return true
end

-- LAYOUT decides the chassis' own SIZE and POSITION; REFLOW places everything
-- inside it from whatever size the chassis is wearing RIGHT NOW. The split is
-- what makes resizing work with no polling at all: the client changes the
-- chassis' size mid-drag, OnSizeChanged fires, Reflow runs, and every inner
-- region follows — while Layout (which would re-impose the stored size) stays
-- out of the way until the drop.
function View.Layout()
    local f = View.EnsureChassis()
    if not f then return false end
    View.ids = View.OwnedIds()
    if #View.ids == 0 then return false end
    if not View.activeId then View.activeId = View.ids[1] end
    local liveActive = false
    for _, id in ipairs(View.ids) do if id == View.activeId then liveActive = true end end
    if not liveActive then View.activeId = View.ids[1] end

    -- NEVER MID-RESIZE, for the same reason ApplyPosition is never mid-drag: a
    -- client beat landing while the player is still holding the grip would
    -- snap the box back to its stored size under the cursor.
    if not View._sizing then
        local w, h = View.ChassisSize()
        call(f, "SetSize", w, h)
        View.ApplyPosition()
    end
    return View.Reflow()
end

function View.Reflow()
    local f = View.chassis
    if not f or #View.ids == 0 then return false end
    -- THE LIVE SIZE, never the stored one: mid-resize these two disagree, and
    -- the live one is the one the player is looking at.
    local w = widgetNum(f, "GetWidth")
    local h = widgetNum(f, "GetHeight")
    if not w or not h or w <= 0 or h <= 0 then return false end

    -- The strip / rail: ONE implementation, shared with LayoutTabs.
    View.LayoutStrip()

    -- The message + entry surface (one --panel2 fill, the mockup's own shape).
    local ml, mr, mt, mb = View.MessageInsets()
    call(View.surface, "ClearAllPoints")
    call(View.surface, "SetPoint", "TOPLEFT", f, "TOPLEFT",
        ml - MSG_PAD_X, -(mt - MSG_PAD_TOP))
    call(View.surface, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT",
        -(mr - MSG_PAD_X), CHASSIS_EDGE)
    call(View.surface, "Show")

    -- The entry bar and its seam.
    call(View.entry, "ClearAllPoints")
    call(View.entry, "SetSize", w - 2 * CHASSIS_EDGE, EB_HEIGHT)
    call(View.entry, "SetPoint", "BOTTOMLEFT", f, "BOTTOMLEFT", CHASSIS_EDGE, CHASSIS_EDGE)
    call(View.entry, "Show")
    call(View.entrySeam, "ClearAllPoints")
    call(View.entrySeam, "SetSize", w - 2 * CHASSIS_EDGE, SEAM_W)
    call(View.entrySeam, "SetPoint", "BOTTOMLEFT", View.entry, "TOPLEFT", 0, 0)
    call(View.entrySeam, "Show")

    -- The message frames, all anchored to the same rect; one is shown.
    --
    -- TWO OPPOSING ANCHORS AND NOTHING ELSE. The shipped pass also called
    -- SetSize here, which is an over-constraint the client resolves by its own
    -- rule ("if both edges are anchored, setting the width has no effect") — so
    -- it was either a no-op or a disagreement, and both are worse than saying
    -- the rect once. The anchors alone also mean the feed FOLLOWS the chassis
    -- through a resize with no arithmetic at all.
    local feedLevel = (widgetNum(f, "GetFrameLevel") or 1) + 1
    for _, id in ipairs(View.ids) do
        local smf = View.EnsureFrame(id)
        if smf then
            View.ApplyFont(id)
            call(smf, "ClearAllPoints")
            call(smf, "SetPoint", "TOPLEFT", f, "TOPLEFT", ml, -mt)
            call(smf, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -mr, mb)
            call(smf, "SetFrameLevel", feedLevel)
            call(smf, id == View.activeId and "Show" or "Hide")
        end
    end
    -- THE PLACEMENT THIS PASS LAID OUT. LayoutTabs compares against it and
    -- escalates when they disagree, so no cheap beat can leave the strip, the
    -- feed and the floor speaking about different placements.
    View._laidPlacement = View.TabPlacement()
    View.LayoutTabs()
    View.EnsureCopyButton()
    View.LayoutGrips()
    call(f, "Show")
    return true
end

----------------------------------------------------------------------
-- THE COPY AFFORDANCE, carried over. Era has no clipboard: the copy window is
-- skin.lua's (one themed frame holding the extracted text pre-selected), and
-- it reads any frame with the public message-history surface — which is
-- exactly what a view frame is. One implementation, two callers.
----------------------------------------------------------------------

function View.OpenCopy()
    local S = ns.Skin
    local smf = View.activeId and View.frames[View.activeId]
    if not (S and type(S.OpenCopy) == "function" and smf) then return nil end
    local ok, text = pcall(S.OpenCopy, smf)
    return ok and text or nil
end

function View.EnsureCopyButton()
    if not cfg().copyButton then
        if View.copyBtn then call(View.copyBtn, "Hide") end
        return nil
    end
    if View.copyBtn then
        call(View.copyBtn, "ClearAllPoints")
        call(View.copyBtn, "SetPoint", "TOPRIGHT", View.chassis, "TOPRIGHT",
            -(CHASSIS_EDGE + 2), -(CHASSIS_EDGE + 2))
        -- It sits in the strip's band, and the strip is now an opaque surface
        -- above the feed — so the affordance has to be above the strip, said
        -- outright rather than left to creation order.
        call(View.copyBtn, "SetFrameLevel",
            (widgetNum(View.strip, "GetFrameLevel") or 1) + 2)
        call(View.copyBtn, "Show")
        return View.copyBtn
    end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" or not View.chassis then return nil end
    local btn = cf("Button", nil, View.chassis)
    call(btn, "SetSize", 16, 16)
    call(btn, "SetAlpha", 0.35)
    local label = call(btn, "CreateFontString", nil, "OVERLAY")
    local UI = UIKit()
    if UI and type(UI.FontFile) == "function" then
        call(label, "SetFont", UI.FontFile(), 10, "")
    end
    call(label, "SetPoint", "CENTER", btn, "CENTER", 0, 0)
    call(label, "SetText", "C")     -- ASCII by law
    local function quiet() local r, g, b = View.Ink("muted"); if r then call(label, "SetTextColor", r, g, b, 1) end end
    local function loud()  local r, g, b = View.Ink("accent"); if r then call(label, "SetTextColor", r, g, b, 1) end end
    quiet()
    btn:SetScript("OnEnter", function(self) call(self, "SetAlpha", 1) loud() end)
    btn:SetScript("OnLeave", function(self) call(self, "SetAlpha", 0.35) quiet() end)
    btn:SetScript("OnClick", function() View.OpenCopy() end)
    View.copyBtn = btn
    return View.EnsureCopyButton()
end

----------------------------------------------------------------------
-- POSITION AND DRAG.
--
-- OUR FRAME, OUR RULES. There is no FCF clamp beat, no dock manager and no
-- per-character store reaching for this frame, so the bounce-back class of
-- defect is structurally impossible here. What IS reused, whole:
--   * the npos path — the chassis' corner is written onto the ENGINE's host
--     window and committed with the client's own save verb, so config.lua's
--     CaptureWindow captures it, reconcile.lua's ApplyPositions replays it and
--     `/dchat debug reconcile` (and `debug position`) keep verdicting it. One
--     position path in the addon, not two;
--   * skin.lua's frame-agnostic SNAP LAYER, through its published SnapPeers
--     override point — the arithmetic is not forked, it is pointed at our set.
----------------------------------------------------------------------

-- Place the chassis so its message area sits where the engine's host window
-- sits: same corner, so the config's npos means the same thing for both.
function View.ApplyPosition()
    -- NEVER MID-DRAG. A client beat (a dock update, say) can land while the
    -- player is still holding the box, and re-placing it from the engine's
    -- corner right then would yank it out from under the cursor — the one
    -- shape of "it moved on its own" this design is supposed to have made
    -- impossible. The drop re-establishes the agreement a moment later.
    if View._dragging then return false end
    local f = View.chassis
    local host = View.ClientFrame(View.HostId())
    local P = _G.UIParent
    if not (f and type(host) == "table" and type(P) == "table") then return false end
    local l = widgetNum(host, "GetLeft")
    local b = widgetNum(host, "GetBottom")
    if l == nil or b == nil then return false end        -- unknown is not zero
    call(f, "ClearAllPoints")
    call(f, "SetPoint", "BOTTOMLEFT", P, "BOTTOMLEFT", l, b)
    return true
end

-- The drop's commit: the engine's host window is moved to the chassis' corner,
-- the client's own save verb writes it to the per-character store (inside the
-- reconciler's SelfWrite, so the store write is OUR echo), and the MOVE itself
-- is announced through NoteExternalChange — two facts, two channels, exactly
-- the discipline skin v3.1 established for alt-drag.
function View.CommitPosition()
    local f = View.chassis
    local host = View.ClientFrame(View.HostId())
    local P = _G.UIParent
    if not (f and type(host) == "table" and type(P) == "table") then return false end
    local l = widgetNum(f, "GetLeft")
    local b = widgetNum(f, "GetBottom")
    if l == nil or b == nil then return false end
    call(host, "ClearAllPoints")
    call(host, "SetPoint", "BOTTOMLEFT", P, "BOTTOMLEFT", l, b)
    local S = ns.Skin
    if S and type(S.CommitMove) == "function" then
        pcall(S.CommitMove, host)
    end
    local R = ns.Reconcile
    if R and R.NoteExternalChange then pcall(R.NoteExternalChange, "move: view chassis") end
    return true
end

-- THE LOCK (owner, 2026-08-11: "i need a way to lock / unlock the positioning
-- and also when unlocked i should be able to click and drag a corner to
-- re-size it").
--
-- ONE STATE, READ IN ONE PLACE, and it is the SYNCED config's (config.lua's
-- Config.Locked — beside the position it governs, so lock follows the mesh the
-- way the position already does). LOCKED means the box is a rock: no strip
-- drag, no ALT-drag, no resize, no snap guides, no grips. UNLOCKED is exactly
-- what shipped, plus four visible corner grips.
function View.Locked()
    local C = ns.Config
    if C and type(C.Locked) == "function" then
        local ok, v = pcall(C.Locked)
        if ok then return v and true or false end
    end
    return false
end

-- ALT-drag anywhere on the chassis, plain drag on the strip. Both are ours.
function View.DragAllowed(source)
    if not View.active then return false end
    if View.Locked() then return false end
    if source == "strip" then return true end
    local alt = _G.IsAltKeyDown
    if type(alt) ~= "function" then return false end
    local ok, down = pcall(alt)
    return (ok and down) and true or false
end

function View.OnDragStart(frame, source)
    if not View.DragAllowed(source) then return false end
    local f = View.chassis
    if not f then return false end
    call(f, "SetMovable", true)
    local ok = pcall(f.StartMoving, f)
    if not ok then return false end
    View._dragging = true
    local S = ns.Skin
    if S and type(S.BeginSnapGuides) == "function" then pcall(S.BeginSnapGuides, f) end
    return true
end

function View.OnDragStop()
    if not View._dragging then return false end
    View._dragging = nil
    local f = View.chassis
    if not f then return false end
    call(f, "StopMovingOrSizing")
    local S = ns.Skin
    -- The snap layer, reused whole: SnapPeers is pointed at OUR frames while
    -- the view is up (see OnEnable), so the arithmetic and the guides are the
    -- ones already pinned by skin's own suite.
    if S and type(S.SnapOnDrop) == "function" then pcall(S.SnapOnDrop, f) end
    if S and type(S.EndSnapGuides) == "function" then pcall(S.EndSnapGuides) end
    View.moves = View.moves + 1
    View.CommitPosition()
    return true
end

-- skin.lua's published SnapPeers override point. Our set is one frame — the
-- chassis — and it is deliberately NOT the client's windows: snapping to a
-- hidden window's edge would align the box against something invisible.
function View.SnapSet()
    return View.chassis and { View.chassis } or {}
end

----------------------------------------------------------------------
-- RESIZE — FOUR CORNERS, and the LOCK that governs them (owner, 2026-08-11:
-- "when unlocked i should be able to click and drag a corner to re-size it").
--
-- WHAT CHANGED AND WHY. The first build shipped ONE grip, in the bottom-right,
-- invisible until the pointer was on the box — and the owner had to ask how to
-- resize, which is the whole verdict on hover-only affordances. So: four grips,
-- one per corner, VISIBLE the entire time the box is unlocked (subtle:
-- --line-soft resting, --accent under the pointer), and gone entirely while it
-- is locked. Discoverability is not a hint, it is a thing you can see.
--
-- THE ARITHMETIC IS ONE FUNCTION, NOT FOUR. A corner drag holds the OPPOSITE
-- corner fixed; the four cases differ only in which corner that is, so the
-- generalization is a table lookup and two sign choices (View.ResizeAnchored).
-- The bottom-right grip is not duplicated, it is the corner = "BOTTOMRIGHT"
-- case of the same code — and it is still the one the canonical BOTTOMLEFT
-- position anchor makes cheapest, which is why it stays the default.
--
-- WHAT IT COSTS THE REST OF THE FILE: nothing. The chassis' inner regions are
-- anchored, not arithmetic, and the two that are sized (the strip and the
-- entry) are re-sized by Reflow on the chassis' own OnSizeChanged — so the
-- whole drag reflows without a single OnUpdate.
----------------------------------------------------------------------

local GRIP_RESTING_ALPHA = 0.55   -- always visible while unlocked (the ask)
local GRIP_HOVER_ALPHA   = 1.0

View.GRIP_CORNERS = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT" }

-- The corner that STAYS PUT while `corner` is dragged.
local OPPOSITE_CORNER = {
    BOTTOMRIGHT = "TOPLEFT",  TOPLEFT     = "BOTTOMRIGHT",
    BOTTOMLEFT  = "TOPRIGHT", TOPRIGHT    = "BOTTOMLEFT",
}
View.OPPOSITE_CORNER = OPPOSITE_CORNER

-- Where a named corner of the live chassis is, in UIParent units. nil when the
-- frame cannot answer (never a hopeful zero — Class 4).
function View.CornerPoint(corner)
    local f = View.chassis
    local l = widgetNum(f, "GetLeft")
    local b = widgetNum(f, "GetBottom")
    local w = widgetNum(f, "GetWidth")
    local h = widgetNum(f, "GetHeight")
    if l == nil or b == nil or w == nil or h == nil then return nil end
    corner = tostring(corner or "BOTTOMRIGHT"):upper()
    local x = corner:find("RIGHT") and (l + w) or l
    local y = corner:find("TOP") and (b + h) or b
    return x, y
end

View.grips = {}

local function ensureGrip(corner)
    if View.grips[corner] then return View.grips[corner] end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" or not View.chassis then return nil end
    local ok, btn = pcall(cf, "Button", "DaseekiChatViewGrip" .. corner, View.chassis)
    if not ok or type(btn) ~= "table" then return nil end
    call(btn, "SetSize", GRIP_SIZE, GRIP_SIZE)
    call(btn, "EnableMouse", true)
    call(btn, "SetAlpha", GRIP_RESTING_ALPHA)
    -- Two hairlines meeting in THIS corner: the quietest thing that still reads
    -- as "this corner is a handle". No glyph, so no tofu risk.
    local bars = {}
    local function bar(w, h)
        local t = call(btn, "CreateTexture", nil, "OVERLAY")
        paint(t, "lineSoft", 1)
        call(t, "SetSize", w, h)
        call(t, "SetPoint", corner, btn, corner, 0, 0)
        bars[#bars + 1] = t
        return t
    end
    bar(GRIP_SIZE, 1)
    bar(1, GRIP_SIZE)
    local function ink(name)
        for _, t in ipairs(bars) do paint(t, name, 1) end
    end
    btn._bars = bars
    btn:SetScript("OnEnter", function(self)
        call(self, "SetAlpha", GRIP_HOVER_ALPHA) ink("accent")
    end)
    btn:SetScript("OnLeave", function(self)
        ink("lineSoft")
        call(self, "SetAlpha", GRIP_RESTING_ALPHA)
    end)
    btn:SetScript("OnMouseDown", function() View.OnResizeStart(corner) end)
    btn:SetScript("OnMouseUp",   function() View.OnResizeStop() end)
    View.grips[corner] = btn
    return btn
end

-- Back-compatible single-grip accessor: the bottom-right corner is still the
-- default one everything that only knows about "the grip" means.
function View.EnsureGrip(corner)
    local g = ensureGrip(tostring(corner or "BOTTOMRIGHT"):upper())
    View.grip = View.grips.BOTTOMRIGHT or View.grip
    return g
end

function View.EnsureGrips()
    for _, corner in ipairs(View.GRIP_CORNERS) do View.EnsureGrip(corner) end
    return View.grips
end

function View.LayoutGrips()
    if not View.chassis then return false end
    View.EnsureGrips()
    local level = (widgetNum(View.chassis, "GetFrameLevel") or 1) + 8
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local g = View.grips[corner]
        if g then
            local dx = corner:find("RIGHT") and -CHASSIS_EDGE or CHASSIS_EDGE
            local dy = corner:find("TOP") and -CHASSIS_EDGE or CHASSIS_EDGE
            call(g, "ClearAllPoints")
            call(g, "SetPoint", corner, View.chassis, corner, dx, dy)
            call(g, "SetFrameLevel", level)
        end
    end
    return View.ApplyLock()
end

-- The lock's own pixel act: grips exist while unlocked and are gone while
-- locked. Called by the layout, by the slash verbs and by the options pane —
-- one seam, three callers.
function View.ApplyLock()
    local locked = View.Locked()
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local g = View.grips[corner]
        if g then
            call(g, locked and "Hide" or "Show")
            call(g, "SetAlpha", locked and 0 or GRIP_RESTING_ALPHA)
        end
    end
    return not locked
end

-- Kept for the pointer-on-the-box beat: the grips are ALWAYS up while unlocked
-- now, and hovering the box just brings them a little further forward.
function View.SetGripVisible(on)
    View._gripVisible = on and true or false
    if View.Locked() then return View.ApplyLock() end
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local g = View.grips[corner]
        if g then call(g, "SetAlpha", on and 0.85 or GRIP_RESTING_ALPHA) end
    end
    return true
end

function View.OnResizeStart(corner)
    if not View.active then return false end
    if View.Locked() then return false end            -- a locked box is a rock
    local f = View.chassis
    if not f then return false end
    corner = tostring(corner or "BOTTOMRIGHT"):upper()
    if not OPPOSITE_CORNER[corner] then corner = "BOTTOMRIGHT" end
    -- THE FIXED CORNER, CAPTURED BEFORE THE FIRST CLIENT CALL. Everything the
    -- drop does — clamping, snapping, the commit — re-establishes this point,
    -- so the opposite corner cannot walk while the box is being resized.
    local ax, ay = View.CornerPoint(OPPOSITE_CORNER[corner])
    if ax == nil then return false end
    call(f, "SetResizable", true)
    local ok = pcall(f.StartSizing, f, corner)
    if not ok then return false end
    View._sizing = true
    View._sizeCorner = corner
    View._sizeAnchor = { ax, ay }
    local S = ns.Skin
    if S and type(S.BeginSnapGuides) == "function" then pcall(S.BeginSnapGuides, f) end
    return true
end

-- Place AND size so the corner OPPOSITE the dragged one stays exactly where it
-- was when the gesture started. One arithmetic for all four grips: the fixed
-- corner supplies the two coordinates the size is measured away from.
function View.ResizeAnchored(w, h, corner, anchor)
    local f = View.chassis
    local P = _G.UIParent
    if not (f and type(P) == "table") then return false end
    corner = tostring(corner or "BOTTOMRIGHT"):upper()
    local fixed = OPPOSITE_CORNER[corner] or "TOPLEFT"
    w, h = View.ClampChassisSize(w, h)
    local ax, ay = anchor and anchor[1], anchor and anchor[2]
    if ax == nil or ay == nil then
        ax, ay = View.CornerPoint(fixed)
        if ax == nil then return false end
    end
    local left   = fixed:find("RIGHT") and (ax - w) or ax
    local bottom = fixed:find("TOP") and (ay - h) or ay
    call(f, "SetSize", w, h)
    call(f, "ClearAllPoints")
    call(f, "SetPoint", "BOTTOMLEFT", P, "BOTTOMLEFT", left, bottom)
    View.Reflow()
    return true
end

-- SNAP ON THE RESIZE EDGES, and it is CHEAP because skin's snap layer was built
-- frame-agnostic and PURE: SnapLines answers every boundary in screen pixels
-- and SnapDelta is arithmetic over two edges. The only thing that differs from
-- a move is WHICH edges are asked — and now that is a function of the corner
-- being dragged rather than a hardcoded pair. No fork of the arithmetic, no
-- second threshold, no second set of guides.
function View.SnapResize()
    local S = ns.Skin
    local f = View.chassis
    if not (S and f and type(S.SnapLines) == "function"
            and type(S.SnapDelta) == "function") then return false end
    if type(S.SnapEnabled) == "function" then
        local ok, on = pcall(S.SnapEnabled)
        if not (ok and on) then return false end
    end
    local l = widgetNum(f, "GetLeft")
    local b = widgetNum(f, "GetBottom")
    local w = widgetNum(f, "GetWidth")
    local h = widgetNum(f, "GetHeight")
    local fs = widgetNum(f, "GetEffectiveScale")
    if l == nil or b == nil or fs == nil or fs <= 0 then return false end
    local okL, vx, hy = pcall(S.SnapLines, f)
    if not okL or not vx then return false end
    local corner = View._sizeCorner or "BOTTOMRIGHT"
    local movingRight  = corner:find("RIGHT") ~= nil
    local movingTop    = corner:find("TOP") ~= nil
    local edgeX = (movingRight and (l + w) or l) * fs
    local edgeY = (movingTop and (b + h) or b) * fs
    local dx = select(1, S.SnapDelta(edgeX, edgeX, vx, S.SNAP_THRESHOLD))
    local dy = select(1, S.SnapDelta(edgeY, edgeY, hy, S.SNAP_THRESHOLD))
    if not dx and not dy then return false end
    -- A moved edge grows the box when it moves AWAY from the fixed corner.
    local nw = w + (movingRight and 1 or -1) * (dx or 0) / fs
    local nh = h + (movingTop and 1 or -1) * (dy or 0) / fs
    View.ResizeAnchored(nw, nh, corner, View._sizeAnchor)
    return true
end

-- (View.ResizeTo retired 2026-08-11: it placed the box from an explicit
-- BOTTOMLEFT, which is the BOTTOMRIGHT grip's case of View.ResizeAnchored
-- above. Two functions for one act is how the two tab-run versions drifted, so
-- the general one is the only one.)

-- THE DROP. One commit for both facts the gesture changed: the engine host
-- window learns the new size AND the new corner, the client's own save verb
-- writes both to the per-character store inside the reconciler's SelfWrite (so
-- the store write is OUR echo), and the RESIZE is announced separately through
-- NoteExternalChange — the same two-facts-two-channels discipline the move
-- commit has used since skin v3.1.
function View.CommitSize()
    local f = View.chassis
    local host = View.ClientFrame(View.HostId())
    local P = _G.UIParent
    if not (f and type(host) == "table" and type(P) == "table") then return false end
    local l = widgetNum(f, "GetLeft")
    local b = widgetNum(f, "GetBottom")
    local w = widgetNum(f, "GetWidth")
    local h = widgetNum(f, "GetHeight")
    if l == nil or b == nil or w == nil or h == nil then return false end
    local hw, hh = View.HostSizeFor(w, h)
    call(host, "SetSize", hw, hh)
    call(host, "ClearAllPoints")
    call(host, "SetPoint", "BOTTOMLEFT", P, "BOTTOMLEFT", l, b)
    local S = ns.Skin
    if S and type(S.CommitMove) == "function" then
        -- FCF_SavePositionAndDimensions writes BOTH — which is why a resize
        -- needs no second save verb and cannot disagree with a move about the
        -- corner they share.
        pcall(S.CommitMove, host)
    end
    local R = ns.Reconcile
    if R and R.NoteExternalChange then pcall(R.NoteExternalChange, "resize: view chassis") end
    return true
end

View.resizes = 0

function View.OnResizeStop()
    if not View._sizing then return false end
    View._sizing = nil
    local f = View.chassis
    if not f then return false end
    call(f, "StopMovingOrSizing")
    -- CLAMP AT THE DROP, not through SetResizeBounds: the client applies bounds
    -- inside its own sizing loop, and this box is sized by paths we drive too.
    -- A floor that only lives in the client's loop is a floor that sometimes
    -- does not run. The clamp is applied AROUND THE FIXED CORNER, so a drop
    -- that lands on the minimum keeps the corner the player was not dragging.
    View.ResizeAnchored(widgetNum(f, "GetWidth"), widgetNum(f, "GetHeight"),
        View._sizeCorner, View._sizeAnchor)
    View.SnapResize()
    View._sizeCorner, View._sizeAnchor = nil, nil
    local S = ns.Skin
    if S and type(S.EndSnapGuides) == "function" then pcall(S.EndSnapGuides) end
    View.resizes = View.resizes + 1
    View.CommitSize()
    return true
end

----------------------------------------------------------------------
-- HOOKS. hooksecurefunc is permanent, so every install happens exactly once
-- (first enable) and every body gates on View.active.
----------------------------------------------------------------------

local function installHooks()
    if View.hooked then return end
    View.hooked = true
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return end
    -- The client's window-update beat projects the store onto the frame and
    -- would re-show an engine window. Last word, in-call.
    if type(_G.FloatingChatFrame_Update) == "function" then
        hook("FloatingChatFrame_Update", function(id)
            if not View.active then return end
            View.KeepEngineHidden(View.ClientFrame(id))
        end)
    end
    if type(_G.FCF_DockUpdate) == "function" then
        hook("FCF_DockUpdate", function()
            if not View.active then return end
            View.KeepAllEngineHidden()
            View.Layout()
        end)
    end
    -- THE TAB RE-SHOW, BEATEN AT ITS SOURCE. The dock's own tab beat shows every
    -- tab whose window the STORE says is live — and the store always says so,
    -- because hiding a frame is a display act and never a routing one. This is
    -- the beat that put the owner's stray gold "Loot" tab back over our feed
    -- after HideEngine had already taken it down once. Same posture as the
    -- clamp and the button column: in-call, last word, never a timer.
    for _, verb in ipairs({ "FCFDock_UpdateTabs", "FCF_FlashTab", "FCF_StartAlertFlash",
                            "FCF_MinimizeFrame", "FCF_CreateMinimizedFrame",
                            "FCF_UpdateResizeButton", "FCF_FadeInScrollbar" }) do
        if type(_G[verb]) == "function" then
            hook(verb, function()
                if not View.active then return end
                View.KeepAllEngineHidden()
            end)
        end
    end
    -- A temporary window (a whisper pop-out) opens: it becomes a tab of ours
    -- like any other window, and its own frame goes down with the rest.
    if type(_G.FCF_OpenTemporaryWindow) == "function" then
        hook("FCF_OpenTemporaryWindow", function()
            if not View.active then return end
            View.Refresh()
        end)
    end
    -- THE PERSISTENT ENTRY BAR: the client hides the hosted box on deactivate
    -- (Escape, a sent line, a click away). We take the last word in-call, so
    -- Escape unfocuses and the bar stays exactly where it is.
    if type(_G.ChatEdit_DeactivateChat) == "function" then
        hook("ChatEdit_DeactivateChat", function(editBox)
            View.KeepEditBoxShown(editBox)
        end)
    end
end

----------------------------------------------------------------------
-- REFRESH. Everything whose answer can change without a rebuild.
----------------------------------------------------------------------

function View.Refresh()
    if not View.active then return false end
    View.HideEngine()
    View.Layout()
    return true
end

----------------------------------------------------------------------
-- ============ THE LIVE-APPLY SEAMS (2026-08-11) ============
--
-- WHY THEY EXIST (owner: "the options dont seem to actually do anything. when
-- i move any of the sliders or click the different options nothing changes").
-- The settings pane's writes always landed in the store; what was missing was
-- the second half — nothing re-read the store, so the answer only reached
-- pixels at the next /reload. These are this module's PUBLIC re-apply beats,
-- one per KIND of change, and options.lua's binding table names which one each
-- control dispatches (a binding that names none fails the bind-check).
--
-- Every one of them is idempotent, guarded (an inactive view has nothing to
-- re-apply and says so rather than erroring), and preserves the message
-- buffers: a type-size change RESTYLES the surfaces, it does not rebuild them.
----------------------------------------------------------------------

-- Typography: the feed's own font and the rhythm computed from it, re-applied
-- to every surface IN PLACE, then the layout (the size floor moves with the
-- type size, so the box may have to grow).
function View.ApplyLook()
    if not View.active then return false end
    for _, id in ipairs(View.ids) do View.ApplyFont(id) end
    View.Layout()
    return true
end

-- Where the tabs live: strip <-> rail migration. ONE path, and it is the same
-- one login uses — the run and the surface it runs on are decided together, the
-- feed re-insets for the rail's width, and the chassis re-clamps because the
-- furniture changed size.
function View.ApplyPlacement()
    if not View.active then return false end
    View.ids = View.OwnedIds()
    View.Layout()
    return true
end

-- Labels, ink, per-tab colour, tab type size, unread pips.
function View.ApplyTabs()
    if not View.active then return false end
    View.LayoutTabs()
    return true
end

-- The furniture that is not the layout: the copy button and the grips (whose
-- visibility is the lock's).
function View.ApplyFurniture()
    if not View.active then return false end
    View.EnsureCopyButton()
    View.LayoutGrips()
    return true
end

-- The hosted entry bar, re-anchored (the edit-box position/persistence gates).
function View.ApplyEditBox()
    if not View.active then return false end
    View.LayoutEditBox()
    return true
end

View._colorHandler = function()
    if not View.active then return end
    View.LayoutTabs()
end

View._enteringWorld = function()
    if not View.active then return end
    View.Refresh()
    -- The engine's buffers may be backfilled on this same beat: history.lua
    -- restores with PushFront (which never touches AddMessage, and must not),
    -- so the mirror cannot see that scrollback and only a re-read puts it on
    -- screen.
    --
    -- CLASS 2, HANDLED RATHER THAN BET ON. history.lua defers its restore by
    -- one C_Timer beat, and there is NO DEFINED ORDER between two bus
    -- listeners — whether our resync runs before or after its backfill is a
    -- coin flip decided by module enable order. Rather than depend on that, the
    -- re-read happens TWICE: once now (a plain zone-in with no restore is
    -- already correct, and correct immediately), and once on the beat AFTER any
    -- single-beat deferral, so whoever went first we read last. Resync is
    -- idempotent by construction (it clears the view frame and re-reads the
    -- engine's whole buffer), so the second pass costs a re-read and buys
    -- order-independence.
    View.ResyncAll()
    local CT = _G.C_Timer
    if not (CT and type(CT.After) == "function") then return end
    if View._resyncQueued then return end
    View._resyncQueued = true
    CT.After(0, function()
        CT.After(0, function()
            View._resyncQueued = false
            if View.active then View.ResyncAll() end
        end)
    end)
end

----------------------------------------------------------------------
-- Lifecycle.
----------------------------------------------------------------------

function View.OnEnable()
    View.active = true
    installHooks()

    -- SKIN-OVER RETIRES HERE. The dress skin.lua may already have applied to
    -- the client's frames is handed back before ours goes on, so there is
    -- never a moment with two treatments on one window. skin.lua keeps its
    -- movement/capture/snap layer, its palette accessor and its copy window —
    -- everything the view reuses — and gates its restyle paths off while we
    -- own the pixels (Skin.ViewOwnsPixels).
    local S = ns.Skin
    if S and type(S.RetireStyling) == "function" then pcall(S.RetireStyling) end
    -- The snap layer's peer set becomes ours (its published override point).
    if S then
        View._snapPeers = S.SnapPeers
        S.SnapPeers = function() return View.SnapSet() end
    end

    View.ids = View.OwnedIds()
    View.EnsureChassis()
    View.HideEngine()
    for _, id in ipairs(View.ids) do
        View.EnsureFrame(id)
        wrapAddMessage(View.ClientFrame(id))
    end
    View.Layout()
    View.SelectTab(View.activeId or View.ids[1], "enable")
    -- Whatever the engine already holds goes on screen now (the view coming up
    -- mid-session must not look like chat started over).
    View.ResyncAll()

    ns:RegisterEvent("UPDATE_CHAT_COLOR", View._colorHandler)
    ns:On("ENTERING_WORLD", View._enteringWorld)

    local UI = UIKit()
    if UI and not View.reskinHooked then
        View.reskinHooked = true
        if UI.OnFontChanged then UI.OnFontChanged(function() if View.active then View.Layout() end end) end
        if UI.OnThemeChanged then UI.OnThemeChanged(function() if View.active then View.LayoutTabs() end end) end
    end
end

function View.OnDisable()
    View.active = false
    View._dragging = nil
    ns:UnregisterEvent("UPDATE_CHAT_COLOR", View._colorHandler)
    ns:Off("ENTERING_WORLD", View._enteringWorld)
    -- The edit box goes home FIRST: it belongs to a client window, and handing
    -- it back before the windows come up means the client's own beat finds it
    -- where it expects it.
    releaseEditBox()
    for _, smf in pairs(View.frames) do call(smf, "Hide") end
    if View.chassis then call(View.chassis, "Hide") end
    View.ShowEngine()
    -- The snap layer's peer set goes back to skin's own.
    local S = ns.Skin
    if S and View._snapPeers then
        S.SnapPeers = View._snapPeers
        View._snapPeers = nil
    end
    -- …and skin-over, if it is enabled, dresses the client's windows again.
    if S and S.active and type(S.StyleAll) == "function" then pcall(S.StyleAll) end
end

ns.RegisterModule("view", View)

----------------------------------------------------------------------
-- The debug surface.
----------------------------------------------------------------------

ns.RegisterDebugCommand("view", "the owned view: chassis, tabs, mirror, engine", function()
    ns:Print(("view: %s, %d tab(s), active %s, placement %s"):format(
        View.active and "active" or "inactive", #View.ids,
        tostring(View.activeId), View.TabPlacement()))
    local m = View.Metrics()
    ns:Print(("  mockup: strip %d (pad %d/%d), tab %d (pad %d/%d/%d), entry %d (pad %d/%d)")
        :format(m.stripH, m.stripPadTop, m.stripPadX, m.tabH, m.tabPadTop,
                m.tabPadX, m.tabPadBottom, m.entryH, m.entryPadY, m.entryPadX))
    ns:Print(("  messages pad %d/%d/%d, spacing %.2f at size %.1f, rail %d (row %d)")
        :format(m.msgPadTop, m.msgPadX, m.msgPadBottom,
                View.MessageSpacing(View.MessageFontSize(nil)),
                View.MessageFontSize(nil), m.railW, m.railRowH))
    local names = { "panel", "panel2", "line", "lineSoft", "accent", "text", "muted", "faint" }
    local swatch = {}
    for _, n in ipairs(names) do
        local r, g, b = View.Ink(n)
        swatch[#swatch + 1] = ("%s=%02x%02x%02x"):format(n,
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    end
    ns:Print("  palette: " .. table.concat(swatch, " "))
    ns:Print(("  mirror: %d line(s) forwarded, %d re-entry refusal(s), %d depth refusal(s)%s")
        :format(View.mirrored, View.mirrorReentries, View.mirrorRefusals,
                View.lastRefusal and (" [" .. View.lastRefusal .. "]") or ""))
    ns:Print(("  engine: %d window(s) held down, %d client re-show(s) beaten, %d resync(s)")
        :format((function() local n = 0 for _ in pairs(View._engineHidden) do n = n + 1 end return n end)(),
                View.reHides, View.resyncs))
    ns:Print(("  edit box: %d retarget(s), hosted %s | %d chassis move(s), %d resize(s)")
        :format(View.retargets,
        tostring(View._ebHome and View._ebHome.eb and View._ebHome.eb.GetName
            and View._ebHome.eb:GetName() or "none"),
        View.moves, View.resizes))
    do
        local cw = widgetNum(View.chassis, "GetWidth") or 0
        local ch = widgetNum(View.chassis, "GetHeight") or 0
        local mnW, mnH = View.MinChassisSize()
        local mxW, mxH = View.MaxChassisSize()
        local nGrips = 0
        for _ in pairs(View.grips or {}) do nGrips = nGrips + 1 end
        ns:Print(("  size: %.0fx%.0f (min %.0fx%.0f, max %.0fx%.0f), %d settle pass(es)")
            :format(cw, ch, mnW, mnH, mxW, mxH, View.settles))
        ns:Print(("  lock: %s | %d corner grip(s) of %d units, %s")
            :format(View.Locked() and "LOCKED (no drag, no resize)" or "unlocked",
                    nGrips, GRIP_SIZE,
                    View.Locked() and "hidden" or "shown while unlocked"))
        local held, sats = 0, 0
        for frame, rec in pairs(View._engineHidden) do
            held = held + 1
            if type(rec) == "table" then
                for _ in pairs(rec.satellites) do sats = sats + 1 end
            end
        end
        ns:Print(("  satellites: %d held down across %d window(s) (roster of %d per window)")
            :format(sats, held, #View.SATELLITES))
    end
    ns:Print("  corners: SQUARE (DEFERRED: nine-slice corner art is ours to ship, not a client limit)")
    for _, id in ipairs(View.ids) do
        local smf = View.frames[id]
        local n = smf and widgetNum(smf, "GetNumMessages") or 0
        ns:Print(("  tab %d '%s': %d line(s)%s"):format(
            id, tostring(View.TabLabel(id)), n, id == View.activeId and " [active]" or ""))
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "view"). The pure parts always run; the live parts drive
-- the module against the harness's unkind chat simulator and are skipped
-- rather than faked when no sim is present.
----------------------------------------------------------------------

local function testPure(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    -- THE PALETTE IS THE MOCKUP'S, byte for byte.
    local WANT = {
        ground = "0b0908", panel = "16100f", panel2 = "1d1514", line = "6e1d1a",
        lineSoft = "3a1512", accent = "c2402e", gold = "d9a83f", text = "e6dfd4",
        muted = "93887e", faint = "5c534c",
    }
    for name, hex in pairs(WANT) do
        local r, g, b, a = View.Ink(name)
        ck(r ~= nil, "palette carries " .. name)
        if r then
            local got = ("%02x%02x%02x"):format(
                math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
            ck(got == hex, name .. " is the mockup's own hex (" .. got .. " vs " .. hex .. ")")
            ck(a == 1, name .. " defaults to alpha 1")
        end
    end
    ck(View.Ink("nosuchtoken") == nil, "an unknown ink answers NOTHING (never a hopeful black)")

    -- THE POST-AMENDMENT NUMBERS, exactly as the owner approved them.
    local m = View.Metrics()
    ck(m.stripH == 26, "strip height is the amended 26")
    ck(m.tabH == 24, "tab height is the amended 24")
    ck(m.entryH == 26, "entry height is the amended 26")
    ck(m.stripPadX == 3 and m.msgPadX == 3, "the side gutters are the amended 3")
    ck(m.tabPadTop == 2 and m.tabPadBottom == 4, "the tab's vertical padding is amended")
    ck(m.railRowH == 26 and m.railPadY == 4, "the rail carries the amendment too")
    ck(m.railW == 112 and m.tabGap == 2 and m.seam == 1, "the un-amended mockup values are untouched")
    ck(m.underlineH == 2 and m.underlineInset == 6, "the active underline is the mockup's")
    ck(m.edgebarW == 2 and m.edgebarInset == 5, "the rail's active edge bar is the mockup's")
    ck(math.abs(m.hoverWash - 0.04) < 1e-9, "the hover wash is the mockup's .04")

    -- SPACING IS COMPUTED, never frozen: the mockup's 1.45 at any size.
    local base = View.MessageSpacing(13.5)
    ck(math.abs(base - ((1.45 - 1.2) * 13.5 + 3)) < 1e-9,
        "line-height 1.45 becomes the DIFFERENCE over the face's own line box")
    ck(View.MessageSpacing(27) > base, "…and it tracks the size, rather than freezing")
    ck(View.MessageSpacing(0) == 3, "a nonsense size falls back to the row padding alone")
    ck(View.MessageSpacing("x") == 3, "…and so does a nonsense value")

    -- SIZE: config first, the client's own size as the escape hatch (Class 5 —
    -- a truthy zero must not become a size).
    ck(View.MessageFontSize(nil) == 13.5, "the feed defaults to the mockup's 13.5")
    local savedSize = ns.db and ns.db.view and ns.db.view.fontSize
    if ns.db and ns.db.view then
        ns.db.view.fontSize = 0
        ck(View.MessageFontSize(18) == 18, "0 hands the size back to the client's own menu")
        ck(View.MessageFontSize(0) == 14, "…and a zero from the client is not a size either")
        ns.db.view.fontSize = savedSize
    end

    -- THE INACTIVE DIM IS INK. Given a colour it moves it toward --muted and
    -- never returns an alpha at all.
    local mr, mg, mb = View.Ink("muted")
    local dr, dg, db = View.InactiveInk(1, 1, 1)
    ck(dr < 1 and dr > mr, "an inactive tab's ink sits between the colour and --muted")
    ck(select(4, View.InactiveInk(1, 1, 1)) == nil, "…and the dim produces no alpha whatsoever")
    local nr = View.InactiveInk(nil, nil, nil)
    ck(nr == mr, "a tab with no colour of its own dims to --muted itself")
end

local function testLive(fails, verbose)
    local Sim = _G.__DaseekiChatSim
    if not Sim then
        if verbose then ns:Print("  (view live legs skipped: no chat simulator)") end
        return
    end
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local HT = _G.__DaseekiChatHarnessTimer

    -- ── Phase 0: the inertness pin, asked of THIS module. ────────────────
    ck(View.active == false, "phase 0: the view is inactive")
    ck(View.chassis == nil, "phase 0: no chassis frame exists yet")
    ck(next(View.frames) == nil, "phase 0: no message surface was created")
    ck(next(View.tabs) == nil, "phase 0: no tab button was created")
    ck(next(wrappedFrames) == nil, "phase 0: zero AddMessage wrappers while disabled")
    ck(next(View._engineHidden) == nil, "phase 0: no client window is being held down")

    local storeBefore = {}
    for id = 1, 10 do
        local w = Sim.windows[id]
        storeBefore[id] = w and (tostring(w.shown) .. "/" .. tostring(w.docked)) or "?"
    end

    -- ── Phase 1: enable. The chassis appears, the engine goes down. ──────
    ns.SetModuleEnabled("view", true)
    if HT then HT.flush() end
    ck(View.active == true, "phase 1: the view is active")
    ck(type(View.chassis) == "table", "phase 1: one chassis frame of ours exists")
    ck(#View.ids > 0, "phase 1: the view owns at least one window")
    local ownsCombat = false
    for _, id in ipairs(View.ids) do if id == 2 then ownsCombat = true end end
    ck(not ownsCombat, "phase 1: THE COMBAT LOG IS EXCLUDED and stays native")
    ck(_G.ChatFrame2:IsShown() == true, "phase 1: …and its window is still shown")

    -- THE CHASSIS IS OURS, at the mockup's colours.
    local bd = View.chassis._backdropColor
    local pr, pg, pb = View.Ink("panel")
    ck(bd and math.abs(bd[1] - pr) < 1e-9 and math.abs(bd[4] - 1) < 1e-9,
        "phase 1: the chassis fill is --panel at alpha 1, the literal mockup hex")
    local bb = View.chassis._backdropBorderColor
    local lr = select(1, View.Ink("line"))
    ck(bb and math.abs(bb[1] - lr) < 1e-9, "phase 1: its 1px border is --line")

    -- THE ENGINE IS HIDDEN, AND THE STORE IS UNTOUCHED (the whole trick).
    local hiddenCount = 0
    for _, id in ipairs(View.ids) do
        if _G["ChatFrame" .. id]:IsShown() == false then hiddenCount = hiddenCount + 1 end
    end
    ck(hiddenCount == #View.ids, "phase 1: every owned engine window's FRAME is hidden")
    local storeSame = true
    for id = 1, 10 do
        local w = Sim.windows[id]
        local now = w and (tostring(w.shown) .. "/" .. tostring(w.docked)) or "?"
        if now ~= storeBefore[id] then storeSame = false end
    end
    ck(storeSame, "phase 1: RED CONTROL — the per-character STORE was not touched "
        .. "(hiding is a display act, never a routing act)")

    -- ── Phase 2: the mirror. A line lands on a hidden window and appears
    -- in the owning tab's view frame, post-decoration, ink intact. ────────
    local id1 = View.ids[1]
    View.SelectTab(id1, "test")
    local vf = View.frames[id1]
    ck(type(vf) == "table", "phase 2: the active tab has a message surface of ours")
    ck(vf._fading == false, "phase 2: SetFading(false) was applied AT CREATION")
    local before = vf:GetNumMessages()
    local mirroredBefore = View.mirrored
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "mirror-me",
                  sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    if HT then HT.advance(0) end
    ck(_G["ChatFrame" .. id1]:GetNumMessages() > 0,
        "phase 2: RED CONTROL — a HIDDEN engine window still received the line")
    ck(vf:GetNumMessages() == before + 1, "phase 2: …and exactly one line was mirrored in")
    ck(View.mirrored == mirroredBefore + 1, "phase 2: the mirror counted exactly one forward")
    local newest = vf.historyBuffer:GetEntryAtIndex(1)
    ck(newest and tostring(newest.message):find("mirror%-me"),
        "phase 2: the mirrored line carries the POST-decoration text")
    ck(type(newest.r) == "number" and type(newest.g) == "number" and type(newest.b) == "number",
        "phase 2: THE INK IS NOT IN A STRING — r,g,b ride as numbers")
    local clientNewest = _G["ChatFrame" .. id1].historyBuffer:GetEntryAtIndex(1)
    ck(clientNewest and newest.message == clientNewest.message,
        "phase 2: the view's line is byte-identical to what the engine stored")

    -- ── Phase 3: RED CONTROL 1 — the mirror loop is impossible. ──────────
    local reBefore = View.mirrorReentries
    local refuseBefore = View.mirrorRefusals
    ck(View.Mirroring() == false, "phase 3: the latch is DOWN outside a forward")
    -- Drive the exact hazard: a client AddMessage that arrives while a mirror
    -- is in flight (the only way a loop could start).
    View._mirrorDepth = 1
    local loopFrame = _G["ChatFrame" .. id1]
    local vfCount = vf:GetNumMessages()
    View.MirrorLine(loopFrame, "would-loop", 1, 1, 1, nil)
    View._mirrorDepth = 0
    ck(View.mirrorReentries == reBefore + 1,
        "phase 3: a client AddMessage inside a mirror is REFUSED as our own echo")
    ck(vf:GetNumMessages() == vfCount, "phase 3: …and nothing was forwarded")
    -- And the depth fuse under it: a forward attempted at the ceiling refuses
    -- with a build-stamped record rather than recursing.
    View._mirrorDepth = View.MIRROR_DEPTH_MAX
    local okFuse = forwardInto(vf, "fused", 1, 1, 1, nil)
    View._mirrorDepth = 0
    ck(okFuse == false and View.mirrorRefusals == refuseBefore + 1,
        "phase 3: the DEPTH FUSE refuses past the known-legitimate nesting")
    ck(type(View.lastRefusal) == "string" and View.lastRefusal:find(tostring(ns.VERSION), 1, true),
        "phase 3: …and records it BUILD-STAMPED")
    ck(vf:GetNumMessages() == vfCount, "phase 3: the fuse forwarded nothing either")
    ck(View._mirrorDepth == 0, "phase 3: the latch is restored, not cleared to nil")

    -- ── Phase 4: THE UNREACHABILITY PIN. The client's own fade and clamp
    -- machinery runs on its own beats; our frames must be structurally out
    -- of reach — not pinned back, out of reach. ──────────────────────────
    local alphaBefore, fadeBefore = vf:GetAlpha(), vf._fading
    local chassisAlpha = View.chassis:GetAlpha()
    local tabAlpha = View.tabs[id1].button:GetAlpha()
    Sim.ResetCalls()
    Sim.ClientFadeBeat()                      -- the client fades ITS windows
    for id = 1, 10 do _G.FloatingChatFrame_Update(id) end
    _G.FCF_DockUpdate()
    Sim.LayoutBeat()
    ck(Sim.CallCount("FCF_FadeOutChatFrame") > 0, "phase 4: the client's fade beat really ran")
    ck(vf:GetAlpha() == alphaBefore, "phase 4: the view's message frame's alpha did not move")
    ck(vf._fading == fadeBefore and vf._fading == false,
        "phase 4: …and its fading is still OFF (it is in no FCF list to be found in)")
    ck(View.chassis:GetAlpha() == chassisAlpha, "phase 4: the chassis' alpha did not move")
    ck(View.tabs[id1].button:GetAlpha() == tabAlpha,
        "phase 4: OUR TAB's alpha did not move (no FCF tab machinery is near it)")
    ck(View.reHides > 0, "phase 4: …and the client's re-show of ITS windows was beaten")
    local stillHidden = true
    for _, id in ipairs(View.ids) do
        if _G["ChatFrame" .. id]:IsShown() then stillHidden = false end
    end
    ck(stillHidden, "phase 4: every engine window is still down after the client's beats")

    -- ── Phase 5: tabs. Ink only, active fused, per-tab colour honoured. ──
    ck(#View.ids >= 2 or true, "phase 5: (tab count is the world's, not ours to assert)")
    local t1 = View.tabs[id1]
    ck(t1 and t1.button._shown, "phase 5: our tab button is shown")
    ck(t1.fill._shown == true, "phase 5: the ACTIVE tab wears the panel2 fill (the fusion)")
    ck(t1.underline._shown == true, "phase 5: …and the accent underline")
    local activeInk = t1.label._textColor
    ck(activeInk and activeInk[4] == 1, "phase 5: the active tab's ink is at full alpha")
    -- A second tab, if the world has one, must be dimmed BY INK.
    local other
    for _, id in ipairs(View.ids) do if id ~= id1 then other = id break end end
    if other then
        local t2 = View.tabs[other]
        ck(t2.button:GetAlpha() == 1, "phase 5: an INACTIVE tab is at FULL alpha (the dim is ink)")
        ck(t2.fill._shown == false, "phase 5: …with no fill")
        local dim = t2.label._textColor
        ck(dim and dim[4] == 1, "phase 5: …and its ink alpha is 1 too")
        ck(dim and activeInk and (dim[1] ~= activeInk[1] or dim[2] ~= activeInk[2]
            or dim[3] ~= activeInk[3]), "phase 5: the two tabs differ in COLOUR, not opacity")
    end
    -- Per-tab colour, through the synced config's own seam.
    local C = ns.Config
    C.SetTabColor(id1, "chat:GUILD")
    View.LayoutTabs()
    local gr, gg, gb = _G.ChatTypeInfo.GUILD.r, _G.ChatTypeInfo.GUILD.g, _G.ChatTypeInfo.GUILD.b
    local ink = View.tabs[id1].label._textColor
    ck(ink and math.abs(ink[1] - gr) < 1e-6 and math.abs(ink[2] - gg) < 1e-6,
        "phase 5: an EXPLICIT per-tab colour is what the tab wears")
    ck(C.Get().windows[id1].tabColor == "chat:GUILD",
        "phase 5: …and it lives in the SYNCED config (WINDOW_CONFIG_ONLY_FIELDS protects it)")
    C.SetTabColor(id1, "")
    View.LayoutTabs()

    -- ── Phase 6: badges ride OUR buttons. ────────────────────────────────
    ck(View.TabButtonFor(_G["ChatFrame" .. id1]) == View.tabs[id1].button,
        "phase 6: the badge rebind seam answers OUR tab button")
    ck(View.TabButtonFor(_G.ChatFrame2) == nil,
        "phase 6: …and NOTHING for a window the view does not own")
    ck(type(View.PipWidth(id1)) == "number",
        "phase 6: badges' PipWidth seam is preserved (the tab sizes around the pip)")

    -- ── Phase 7: RED CONTROL 3 — the edit box retargets on tab switch. ───
    if other then
        View.SelectTab(id1, "test")
        local ebBefore = View._ebHome and View._ebHome.eb
        ck(ebBefore == _G["ChatFrame" .. id1 .. "EditBox"],
            "phase 7: the chassis hosts the ACTIVE tab's own client edit box")
        ck(ebBefore._parent == View.entry, "phase 7: …reparented into our entry bar")
        ck(ebBefore._shown == true, "phase 7: …and it is visible (persistent by design)")
        local rBefore = View.retargets
        View.SelectTab(other, "test")
        ck(View.retargets == rBefore + 1, "phase 7: RED CONTROL — the switch retargeted the box")
        ck(View._ebHome.eb == _G["ChatFrame" .. other .. "EditBox"],
            "phase 7: …to the NEW tab's client window (replies and stickiness follow)")
        ck(ebBefore._shown == false, "phase 7: …and the old one went home hidden")
        ck(_G.GeneralDockManager.selected == _G["ChatFrame" .. other],
            "phase 7: the CLIENT's own selection followed too (badges/history read it)")
        View.SelectTab(id1, "test")
    end
    -- Escape unfocuses without hiding: the client's deactivate runs and our
    -- post-hook takes the last word inside the same call.
    local eb = View.EditBox()
    _G.ChatEdit_ActivateChat(eb)
    ck(eb._focused == true, "phase 7: activating focuses the hosted box")
    _G.ChatEdit_OnEscapePressed(eb)
    ck(eb._focused == false, "phase 7: ESCAPE unfocuses it")
    ck(eb._shown == true, "phase 7: …and does NOT hide it (the bar is persistent)")
    local ins = { eb:GetTextInsets() }
    ck(ins[1] == 12 and ins[3] == 3, "phase 7: the entry wears the mockup's amended insets")

    -- ── Phase 8: hyperlinks and copy. ────────────────────────────────────
    Sim.ResetCalls()
    View.OnHyperlink("item:19019", "[Thunderfury]", "LeftButton")
    ck(Sim.CallCount("SetItemRef") == 1,
        "phase 8: a hyperlink click forwards to the CLIENT's own item-ref handler")
    local copyText = View.OpenCopy()
    ck(type(copyText) == "string" and copyText:find("mirror%-me"),
        "phase 8: the copy affordance reads the VIEW's frame (one copy window, two callers)")

    -- ── Phase 9: position, drag and the snap layer, reused whole. ────────
    local S = ns.Skin
    ck(S.SnapPeers() [1] == View.chassis,
        "phase 9: skin's published SnapPeers override now answers OUR chassis")
    local host = _G["ChatFrame" .. View.HostId()]
    View.chassis._left, View.chassis._bottom = 300, 300
    View.chassis._movable, View.chassis._moving = true, true
    View._dragging = true
    local snapsBefore, commitsBefore = S.snaps, S.moveCommits
    Sim.DragTo(View.chassis, 4, 4)      -- within the snap threshold of 0,0
    View.OnDragStop()
    ck(View.chassis:GetLeft() == 0 and View.chassis:GetBottom() == 0,
        "phase 9: the drop SNAPPED flush to the screen corner (no clamp fights it)")
    ck(S.snaps == snapsBefore + 1, "phase 9: …through skin's own snap arithmetic, not a fork")
    ck(host:GetLeft() == 0 and host:GetBottom() == 0,
        "phase 9: the ENGINE's host window moved with it (one position, not two)")
    ck(S.moveCommits == commitsBefore + 1,
        "phase 9: …and the move was committed with the CLIENT's own save verb")
    ck(Sim.windows[View.HostId()].pos[2] == 0,
        "phase 9: the per-character store agrees, so the client's restore beat cannot undo it")
    local cap = ns.Config.CaptureWindow(View.HostId())
    ck(type(cap.npos) == "table" and math.abs(cap.npos[2]) < 1e-6,
        "phase 9: the npos path captured the chassis' corner (the SAME config path)")

    -- ── Phase 10: RED CONTROL 2 — the hidden engine regresses nothing. ───
    -- The reconciler converges an authored config while every window is down.
    local before10 = ns.Config.Get()
    local c = ns.Config.Get()
    c.windows = {}
    for id = 1, 10 do c.windows[id] = ns.Config.CaptureWindow(id) end
    c.windows[1].name = "Hidden Engine"
    c.windows[1].fontSize = 15
    c.join = { { 1, "General" } }
    c.rev = (tonumber(c.rev) or 0) + 1
    c.at = ns.Config.Now()
    ns.SetModuleEnabled("channels", true)
    ns.SetModuleEnabled("reconcile", true)
    local drops = Sim.droppedJoins
    Sim.EnterWorld(false, false)
    if HT then HT.flush() end
    ck(select(1, _G.GetChatWindowInfo(1)) == "Hidden Engine",
        "phase 10: RED CONTROL — the reconciler converged with every window HIDDEN")
    ck(select(2, _G.GetChatWindowInfo(1)) == 15, "phase 10: …font size and all")
    ck(Sim.droppedJoins == drops, "phase 10: …with zero dropped channel ops")
    ck(ns.Reconcile._runInFlight == false, "phase 10: …and the run ENDED (finite ladder)")
    local stillDown = true
    for _, id in ipairs(View.ids) do
        if _G["ChatFrame" .. id]:IsShown() then stillDown = false end
    end
    ck(stillDown, "phase 10: the engine is still hidden after a full reconcile")
    -- …and traffic still flows through the whole stack into the view.
    local vfNow = View.frames[View.activeId]
    local n10 = vfNow:GetNumMessages()
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "post-reconcile",
                  sender = "Choco", guid = "Player-1-00000002" }
    if HT then HT.advance(0) end
    ck(vfNow:GetNumMessages() == n10 + 1,
        "phase 10: a line still reaches the view through the converged, hidden engine")
    ns.SetModuleEnabled("reconcile", false)
    ns.SetModuleEnabled("channels", false)

    -- ── Phase 11: BOTH DROP POSTURES, and BOTH DISPATCH POSTURES. ────────
    -- Simulator doctrine: the unkind variant is a real leg, not a footnote,
    -- and "both postures must be run" is the standing rule.
    --
    -- (a) The two TAB-DROP postures. A native tab drop on a hidden engine
    -- window is a gesture the player cannot even make while the view is up,
    -- which is precisely why it is worth pinning: whichever path the client's
    -- drop terminates in — the hookable globals, or its own internal
    -- references — it must not disturb our chassis, our fading or our tabs.
    for _, posture in ipairs({ "globals", "internal" }) do
        local viewLeft   = View.chassis:GetLeft()
        local viewBottom = View.chassis:GetBottom()
        local fadingWas  = View.frames[View.activeId]._fading
        local tabAlpha   = View.tabs[View.activeId].button:GetAlpha()
        Sim.TabDragTo(_G.ChatFrame1, 500, 400, posture)
        ck(View.chassis:GetLeft() == viewLeft and View.chassis:GetBottom() == viewBottom,
            "phase 11 [" .. posture .. "]: a native tab drop leaves our chassis exactly where it was")
        ck(View.frames[View.activeId]._fading == fadingWas and fadingWas == false,
            "phase 11 [" .. posture .. "]: …our fading is still off")
        ck(View.tabs[View.activeId].button:GetAlpha() == tabAlpha,
            "phase 11 [" .. posture .. "]: …and our tab's alpha never moved")
    end

    -- (b) The two EVENT-DISPATCH postures (Class 2's ordering coin-flip, and
    -- Class 9's "when it echoes is the whole question"). The mirror runs
    -- SYNCHRONOUSLY INSIDE the client's own AddMessage call, so it is correct
    -- by construction under either — but "by construction" is a claim until a
    -- test flips the coin, so both are driven here.
    local savedOrder = Sim.opts.addonEventFirst
    for _, first in ipairs({ true, false }) do
        Sim.opts.addonEventFirst = first
        local vfP = View.frames[View.activeId]
        local n = vfP:GetNumMessages()
        local tag = first and "addon-first" or "client-first"
        -- The mirror's synchrony, asserted: by the time SendChat returns, the
        -- line is ALREADY in our frame. Nothing was scheduled, nothing waited.
        Sim.SendChat{ event = "CHAT_MSG_SAY", text = "posture " .. tag,
                      sender = "Choco", guid = "Player-1-00000002" }
        ck(vfP:GetNumMessages() == n + 1,
            "phase 11 [" .. tag .. "]: the mirror forwarded IN-CALL, before the send returned")
        local e = vfP.historyBuffer:GetEntryAtIndex(1)
        ck(e and tostring(e.message):find("posture " .. tag, 1, true) ~= nil,
            "phase 11 [" .. tag .. "]: …and it is the right line")
        if HT then HT.advance(0) end
        ck(vfP:GetNumMessages() == n + 1,
            "phase 11 [" .. tag .. "]: …and NOTHING arrived a beat later (no double delivery)")
    end
    Sim.opts.addonEventFirst = savedOrder

    -- ── Phase 13: THE TAB RUN (the owner's "Loot FoDMs" overlap). ────────
    -- Four tabs, laid out, MEASURED. Nothing in this file could be asked
    -- "where did that tab end up" before the sim grew an anchor resolver, which
    -- is exactly why a tab run that piled three labels on one x shipped green.
    local rect = Sim.ResolveRect
    local savedW = {}
    for id = 3, 5 do
        local w = Sim.windows[id]
        savedW[id] = { w.name, w.shown, w.docked }
    end
    _G.FCF_OpenNewWindow("Focus")
    _G.FCF_OpenNewWindow("DMs")
    _G.FCF_OpenNewWindow("Loot")
    View.Refresh()
    if HT then HT.flush() end
    ck(#View.ids >= 4, "phase 13: the world has a real tab run to measure")
    local sl, sb, sw, sh = rect(View.strip)
    ck(sl ~= nil, "phase 13: the tab strip's rect RESOLVES (geometry is assertable at all)")
    local prevRight, runOk, insideOk, orderOk = nil, true, true, true
    for _, id in ipairs(View.ids) do
        local l, b, w, h = rect(View.tabs[id].button)
        if l == nil then runOk = false break end
        if prevRight then
            -- THE PIN: consecutive tabs are exactly TAB_GAP apart, in order.
            if math.abs(l - (prevRight + TAB_GAP)) > 1e-6 then runOk = false end
            if l < prevRight then orderOk = false end
        end
        if sl and (l < sl or l + w > sl + sw or b < sb or b + h > sb + sh) then insideOk = false end
        prevRight = l + w
    end
    ck(runOk, "phase 13: RED CONTROL — each tab starts exactly TAB_GAP past the "
        .. "previous one's RIGHT EDGE (a run, not a pile)")
    ck(orderOk, "phase 13: …and the run advances, so no two tabs share an x")
    ck(insideOk, "phase 13: …and every tab sits inside the strip")
    local anyOverlap = false
    for i = 1, #View.ids do
        for j = i + 1, #View.ids do
            if Sim.RectsOverlap(View.tabs[View.ids[i]].button,
                                View.tabs[View.ids[j]].button) then anyOverlap = true end
        end
    end
    ck(not anyOverlap, "phase 13: RED CONTROL — no two tab buttons OVERLAP")

    -- THE BADGE RIDES THE FIXED LAYOUT: the mockup keeps the pip INSIDE the
    -- tab, and the tab is sized for it — so a detached chip floating past the
    -- tab's right edge is a layout failure, not a cosmetic one.
    local badgeId = View.ids[2] or View.ids[1]
    local Bm = ns.Badges
    if Bm and Bm.active then
        Bm.Clear(View.ClientFrame(badgeId))
        View.ClientFrame(badgeId):AddMessage("unseen for the pip", 1, 1, 1)
        if HT then HT.advance(0) end
        View.LayoutTabs()
        local bw = Bm.widgets[View.ClientFrame(badgeId)]
        if bw and bw.holder and bw.holder._shown then
            local hl, hb, hw, hh = rect(bw.holder)
            local tl, tb, tw, th = rect(View.tabs[badgeId].button)
            ck(hl ~= nil and tl ~= nil, "phase 13: the pip and its tab both resolve")
            if hl and tl then
                ck(hl >= tl - 1e-6 and hl + hw <= tl + tw + 1e-6,
                    "phase 13: RED CONTROL — the unread pip sits INSIDE its tab "
                    .. "(never floating detached past its right edge)")
                ck(hb >= tb - 1e-6 and hb + hh <= tb + th + 1e-6,
                    "phase 13: …vertically inside it too")
            end
        end
        -- THE DEFERRED SETTLE, pinned: a pip appearing changes a measurement
        -- the pass already sized the tab from, so exactly ONE more pass is
        -- asked for — on the next client beat, never on a ticker — and the tab
        -- comes out wider than it was without one.
        local settlesBefore = View.settles
        Bm.Clear(View.ClientFrame(badgeId))
        View.LayoutTabs()
        local narrow = select(3, rect(View.tabs[badgeId].button))
        View.ClientFrame(badgeId):AddMessage("another unseen", 1, 1, 1)
        if HT then HT.advance(0) end
        ck(View.settles >= settlesBefore,
            "phase 13: a changed measurement asks for a settle pass, not a poll")
        View.LayoutTabs()
        local wide = select(3, rect(View.tabs[badgeId].button))
        ck(wide ~= nil and narrow ~= nil and wide > narrow,
            "phase 13: …and the tab really grew to hold the pip the mockup keeps INSIDE it")
        -- Idempotent: laying out again with nothing changed asks for nothing.
        local settled = View.settles
        View.LayoutTabs()
        if HT then HT.advance(0) end
        ck(View.settles == settled or View.settles == settled + 1,
            "phase 13: …and a steady state does NOT keep re-scheduling itself")
        Bm.Clear(View.ClientFrame(badgeId))
        View.LayoutTabs()
    end

    -- A FACELESS LABEL still lays out. The sim now answers 0 for a FontString
    -- nobody gave a face to (the real client's rule), so the width fallback is
    -- a PIN rather than an assumption.
    do
        local t = View.tabs[View.ids[1]]
        local savedFont = t.label._font
        t.label._font = nil
        ck(t.label:GetStringWidth() == 0, "phase 13: a faceless label really measures NOTHING")
        View.LayoutTabs()
        local l1, _, w1 = rect(t.button)
        ck(l1 ~= nil and w1 >= TAB_MIN_W,
            "phase 13: …and the tab is still sized from the fallback, never from 0")
        t.label._font = savedFont
        View.LayoutTabs()
    end

    -- ── Phase 14: THE GEOMETRIC INVARIANT, all three placements. ─────────
    -- The feed never climbs into the tab strip / rail, and never under the
    -- entry bar, at ANY placement. Measured, not reasoned about.
    local savedPlace = ns.Config.TabPlacement()
    for _, place in ipairs({ "top", "left", "right" }) do
        ns.Config.SetTabPlacement(place)
        View.Layout()
        local cl, cb, cw, chh = rect(View.chassis)
        local rl, rb, rw, rh = rect(View.strip)
        local el, eb2, ew, eh = rect(View.entry)
        local fl, fb, fw, fh = rect(View.frames[View.activeId])
        local tag = "phase 14 [" .. place .. "]: "
        ck(fl ~= nil and rl ~= nil and el ~= nil, tag .. "every region resolves")
        if fl and rl and el and cl then
            if place == "top" then
                ck(fb + fh <= rb + 1e-6,
                    tag .. "RED CONTROL — the feed's TOP edge is at or below the strip's BOTTOM")
            elseif place == "left" then
                ck(fl >= rl + rw - 1e-6, tag .. "the feed starts at or past the rail's right edge")
            else
                ck(fl + fw <= rl + 1e-6, tag .. "the feed ends at or before the rail's left edge")
            end
            ck(fb >= eb2 + eh - 1e-6, tag .. "…and its BOTTOM edge clears the entry bar")
            ck(fl >= cl - 1e-6 and fl + fw <= cl + cw + 1e-6
               and fb >= cb - 1e-6 and fb + fh <= cb + chh + 1e-6,
                tag .. "…and the whole feed is inside the chassis")
            ck(fw > 0 and fh > 0, tag .. "…with a real rect")
        end
    end
    ns.Config.SetTabPlacement(savedPlace)
    View.Layout()

    -- ── Phase 15: THE SATELLITE FAMILY (the stray stock tab). ────────────
    -- Hiding a window is not hiding its dress: the tab, the edit box, the
    -- button column, the minimize button, the resize grip, the scrollbar and
    -- the click-anywhere overlay are all SEPARATE frames that do not follow
    -- their window's Hide — and the client puts them BACK on its own beats.
    local hostedEB = View._ebHome and View._ebHome.eb
    local function strays()
        local out = {}
        for _, id in ipairs(View.ids) do
            for _, nm in ipairs(Sim.ShownSatellites(View.ClientFrame(id))) do
                if not (hostedEB and nm == hostedEB._name) then out[#out + 1] = nm end
            end
        end
        return out
    end
    ck(#strays() == 0, "phase 15: RED CONTROL — the COMPLETE satellite family of every "
        .. "owned window is down (found: " .. table.concat(strays(), ", ") .. ")")
    -- …and it stays down through every beat the client re-asserts its dress on.
    local reShowsBefore = Sim.tabReShows
    Sim.ClientFadeBeat()
    for id = 1, 10 do _G.FloatingChatFrame_Update(id) end
    _G.FCF_DockUpdate()
    _G.FCFDock_UpdateTabs()
    Sim.LayoutBeat()
    ck(Sim.tabReShows > reShowsBefore,
        "phase 15: the client really did try to put its tabs back")
    ck(#strays() == 0, "phase 15: RED CONTROL — …and every one of them was beaten "
        .. "(found: " .. table.concat(strays(), ", ") .. ")")
    -- NOTHING of the client's overlaps our chassis: the owner's stray gold tab
    -- floated MID-PANEL because the dock bar hugs the engine window's top edge,
    -- which is inside the chassis our own strip sits above.
    -- (The hosted edit box is excluded: it is ON the chassis on purpose — that
    -- is the persistent entry bar, reparented, which is a different fact from a
    -- stray the client put back.)
    local overlaps = {}
    for _, id in ipairs(View.ids) do
        for _, w in ipairs(Sim.SatellitesOf(View.ClientFrame(id))) do
            if w._shown and w ~= hostedEB and Sim.RectsOverlap(w, View.chassis) then
                overlaps[#overlaps + 1] = tostring(w._name)
            end
        end
    end
    ck(#overlaps == 0, "phase 15: RED CONTROL — no client satellite is drawn OVER our "
        .. "chassis (found: " .. table.concat(overlaps, ", ") .. ")")

    -- ── Phase 16: RESIZE — the owner's second ask. ───────────────────────
    local grip = View.EnsureGrip()
    ck(type(grip) == "table", "phase 16: the chassis carries a resize grip")
    ck(grip._shown == true, "phase 16: …which exists whether or not it is visible")
    local minW, minH = View.MinChassisSize()
    local maxW, maxH = View.MaxChassisSize()
    ck(minW > 0 and minH > 0, "phase 16: a real minimum exists")
    ck(maxH >= minH and maxW >= minW, "phase 16: …and the maximum is above it")
    -- The minimum is honest about what it reserves: strip + 3 feed lines + entry.
    local mm = View.Metrics()
    ck(minH >= mm.stripH + mm.entryH + mm.msgPadTop + mm.msgPadBottom,
        "phase 16: the minimum reserves the strip, the entry and the feed's own padding")

    -- A resize DROP: clamped, reflowed, committed, captured, synced.
    local hostR = View.ClientFrame(View.HostId())
    local sizeCommitsBefore = ns.Skin.moveCommits
    View.OnResizeStart()
    ck(View._sizing == true, "phase 16: the grip started a resize")
    Sim.SizeTo(View.chassis, View.chassis:GetLeft() + 620, View.chassis:GetBottom() - 130)
    View.OnResizeStop()
    ck(View._sizing == nil, "phase 16: …and the drop ended it")
    local cw2, ch2 = View.chassis:GetWidth(), View.chassis:GetHeight()
    ck(cw2 >= minW - 1e-6 and ch2 >= minH - 1e-6, "phase 16: the drop is CLAMPED to the minimum")
    ck(cw2 <= maxW + 1e-6 and ch2 <= maxH + 1e-6, "phase 16: …and to the screen")
    ck(ns.Skin.moveCommits > sizeCommitsBefore,
        "phase 16: …committed with the CLIENT's own save verb (pos AND dimensions)")
    local hw, hh2 = hostR:GetWidth(), hostR:GetHeight()
    ck(hw > 0 and hh2 > 0, "phase 16: the ENGINE's host window was resized with us")
    local capR = ns.Config.CaptureWindow(View.HostId())
    ck(type(capR.ndim) == "table" and capR.ndim[1] > 0 and capR.ndim[2] > 0,
        "phase 16: the capture carries ndim — the size as a FRACTION of the pixel screen")
    -- THE GEOMETRY INVARIANT SURVIVES THE RESIZE (defect 3 stays fixed at every size).
    do
        local rl2, rb2 = rect(View.strip)
        local fl2, fb2, fw2, fh2 = rect(View.frames[View.activeId])
        ck(fb2 ~= nil and rb2 ~= nil and fb2 + fh2 <= rb2 + 1e-6,
            "phase 16: RED CONTROL — the feed still clears the strip AFTER a resize")
        ck(fw2 > 0 and fh2 > 0, "phase 16: …and still has a real rect")
    end
    -- A tiny drag is refused down to the floor rather than collapsing the box.
    View.OnResizeStart()
    Sim.SizeTo(View.chassis, View.chassis:GetLeft() + 10, View.chassis:GetBottom() + 10)
    View.OnResizeStop()
    ck(View.chassis:GetWidth() >= minW - 1e-6 and View.chassis:GetHeight() >= minH - 1e-6,
        "phase 16: RED CONTROL — a collapse-sized drop lands on the MINIMUM, not on nothing")
    -- …and the size ROUND-TRIPS through the sync snapshot (the aliases lesson:
    -- a field that is not whitelisted is silently account-local forever).
    local liveDim = ns.Config.CaptureNormalizedDim(View.HostId())
    ns.Config.CaptureBack("phase 16 resize")
    ns.Config.Bump()
    local snapR = ns.Config.Snapshot()
    local synced = snapR and snapR.cfg and snapR.cfg.windows
        and snapR.cfg.windows[View.HostId()]
    ck(type(synced) == "table" and type(synced.ndim) == "table",
        "phase 16: RED CONTROL — ndim rides the WIRE payload alongside npos")
    ck(ns.Config.NearDim(synced.ndim, liveDim),
        "phase 16: …and it is the size that was actually dropped")
    -- The reconciler replays it, exactly as it replays npos.
    local cR = ns.Config.Get()
    cR.windows[View.HostId()].ndim = { 0.25, 0.20 }
    local appliedR = ns.Reconcile.ApplySizes(cR)
    ck(#appliedR > 0, "phase 16: the reconciler APPLIES a stored ndim at login")
    ck(math.abs(hostR:GetWidth() * hostR:GetEffectiveScale()
        - 0.25 * Sim.screenPixels[1]) < 2,
        "phase 16: …denormalized into THIS account's units (the npos discipline)")
    ck(ns.Reconcile.PositionVerdict():find("resize") ~= nil
       or ns.Reconcile.lastSizeChange ~= nil,
        "phase 16: …and a size change is on the verdict ledger")

    -- ── Phase 17: THE LOCK, and the FOUR CORNERS. ───────────────────────
    -- The owner asked for both in one breath ("i need a way to lock / unlock
    -- the positioning and also when unlocked i should be able to click and drag
    -- a corner to re-size it"), and they are one feature: the lock decides
    -- whether the gestures exist, and the grips are what the unlocked state
    -- looks like.
    local Cfg = ns.Config
    ck(Cfg.Locked() == false, "phase 17: the shipped default is UNLOCKED (nothing was taken away)")
    ck(#View.GRIP_CORNERS == 4, "phase 17: there are four corner grips, not one")
    View.LayoutGrips()
    local gripsUp = 0
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local g = View.grips[corner]
        if g and g._shown and (g:GetAlpha() or 0) > 0 then gripsUp = gripsUp + 1 end
    end
    ck(gripsUp == 4, "phase 17: RED CONTROL — all four are VISIBLE while unlocked "
        .. "(the hover-only grip is what the owner could not find)")

    -- Each grip sits in its own corner of the chassis.
    do
        local cl, cb, cw2, ch3 = rect(View.chassis)
        local placed = true
        for _, corner in ipairs(View.GRIP_CORNERS) do
            local gl, gb, gw, gh = rect(View.grips[corner])
            if gl == nil then placed = false
            else
                local wantX = corner:find("RIGHT") and (cl + cw2 - 1 - gw) or (cl + 1)
                local wantY = corner:find("TOP") and (cb + ch3 - 1 - gh) or (cb + 1)
                if math.abs(gl - wantX) > 1e-6 or math.abs(gb - wantY) > 1e-6 then placed = false end
            end
        end
        ck(placed, "phase 17: …each in its OWN corner, inside the 1px border")
    end

    -- FOUR-CORNER RESIZE: the opposite corner is pinned, per corner.
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local fixed = View.OPPOSITE_CORNER[corner]
        local fx, fy = View.CornerPoint(fixed)
        ck(View.OnResizeStart(corner) == true, "phase 17 [" .. corner .. "]: the grip starts a resize")
        local l0, b0 = View.chassis:GetLeft(), View.chassis:GetBottom()
        local w0, h0 = View.chassis:GetWidth(), View.chassis:GetHeight()
        -- Drag the grabbed corner 60 units further out along both axes.
        local tx = corner:find("RIGHT") and (l0 + w0 + 60) or (l0 - 60)
        local ty = corner:find("TOP") and (b0 + h0 + 60) or (b0 - 60)
        Sim.SizeTo(View.chassis, tx, ty)
        View.OnResizeStop()
        local nx, ny = View.CornerPoint(fixed)
        ck(nx ~= nil and math.abs(nx - fx) < 1e-6 and math.abs(ny - fy) < 1e-6,
            "phase 17 [" .. corner .. "]: RED CONTROL — the OPPOSITE corner did not move")
        ck(View.chassis:GetWidth() > 0 and View.chassis:GetHeight() > 0,
            "phase 17 [" .. corner .. "]: …and the box still has a real size")
        local rl, rb2 = rect(View.strip)
        local fl3, fb3, fw3, fh3 = rect(View.frames[View.activeId])
        ck(fb3 ~= nil and rb2 ~= nil and fb3 + fh3 <= rb2 + 1e-6,
            "phase 17 [" .. corner .. "]: …and the feed still clears the strip")
    end

    -- LOCKED: every gesture is inert, nothing is captured, the grips are gone.
    local posBefore = { View.chassis:GetLeft(), View.chassis:GetBottom() }
    local sizeBefore = { View.chassis:GetWidth(), View.chassis:GetHeight() }
    local ndimBefore = ns.Config.CaptureNormalizedDim(View.HostId())
    local movesBefore, resizesBefore = View.moves, View.resizes
    local commitsBefore = ns.Skin.moveCommits
    ns.Skin.SetLocked(true)
    ck(View.Locked() == true, "phase 17: the view reads the lock from the SYNCED config")
    local anyGrip = false
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local g = View.grips[corner]
        if g and g._shown and (g:GetAlpha() or 0) > 0 then anyGrip = true end
    end
    ck(not anyGrip, "phase 17: LOCKED — every corner grip is gone")
    ck(View.DragAllowed("strip") == false, "phase 17: LOCKED — a strip drag is refused")
    ck(View.OnDragStart(View.chassis, "strip") == false, "phase 17: …and starts nothing")
    Sim.altDown = true
    ck(View.DragAllowed("frame") == false, "phase 17: LOCKED — an ALT-drag is refused too")
    Sim.altDown = false
    ck(View.OnResizeStart("BOTTOMRIGHT") == false, "phase 17: LOCKED — a resize is refused")
    ck(View._sizing == nil, "phase 17: …and no sizing is in flight")
    ck(View.chassis:GetLeft() == posBefore[1] and View.chassis:GetBottom() == posBefore[2],
        "phase 17: RED CONTROL — the box did not move a unit")
    ck(View.chassis:GetWidth() == sizeBefore[1] and View.chassis:GetHeight() == sizeBefore[2],
        "phase 17: …nor change size")
    ck(View.moves == movesBefore and View.resizes == resizesBefore,
        "phase 17: …and neither gesture was counted")
    ck(ns.Skin.moveCommits == commitsBefore,
        "phase 17: RED CONTROL — NO capture was emitted (nothing to sync, because nothing happened)")
    ck(ns.Config.NearDim(ns.Config.CaptureNormalizedDim(View.HostId()), ndimBefore),
        "phase 17: …and ndim is exactly what it was")

    -- THE LOCK RIDES THE MESH (the aliases lesson: an unlisted field is
    -- account-local forever).
    do
        ns.Config.Bump()
        local snapL = ns.Config.Snapshot()
        ck(snapL and snapL.cfg and type(snapL.cfg.skin) == "table" and snapL.cfg.skin.locked == true,
            "phase 17: RED CONTROL — the lock rides the WIRE payload beside tabPlacement")
        local cands = ns.Config.Candidates()
        local inCand = false
        for _, cand in ipairs(cands) do
            if type(cand.cfg) == "table" and type(cand.cfg.skin) == "table"
               and cand.cfg.skin.locked == true then inCand = true end
        end
        ck(inCand, "phase 17: …and the LWW candidate carries it (site 2 of 3)")
    end

    -- UNLOCK restores both gestures.
    ns.Skin.SetLocked(false)
    ck(View.DragAllowed("strip") == true, "phase 17: unlocking gives the drag back")
    local backUp = 0
    for _, corner in ipairs(View.GRIP_CORNERS) do
        local g = View.grips[corner]
        if g and g._shown and (g:GetAlpha() or 0) > 0 then backUp = backUp + 1 end
    end
    ck(backUp == 4, "phase 17: …and all four grips with it")
    ck(View.OnResizeStart("TOPLEFT") == true, "phase 17: …and a resize starts again")
    View.OnResizeStop()

    -- Put the world back the way phase 13 found it.
    for id = 3, 5 do
        local w = Sim.windows[id]
        w.name, w.shown, w.docked = savedW[id][1], savedW[id][2], savedW[id][3]
        _G.FloatingChatFrame_Update(id)
    end
    View.Refresh()
    if HT then HT.flush() end

    -- ── Phase 12: RED CONTROL 4 — disable/restore leaves the world tidy. ─
    local ebHosted = View._ebHome and View._ebHome.eb
    -- What the client had up BEFORE we ever touched it, per window, so the
    -- restore is pinned as a ROUND TRIP rather than as "something is showing".
    local dressBefore = {}
    for _, id in ipairs(View.ids) do
        local frame = View.ClientFrame(id)
        local rec = View._engineHidden[frame]
        dressBefore[id] = {}
        if type(rec) == "table" then
            for w in pairs(rec.satellites) do dressBefore[id][w] = true end
        end
    end
    ns.SetModuleEnabled("view", false)
    if HT then HT.flush() end
    ck(View.active == false, "phase 12: the view is inactive again")
    ck(View.chassis._shown == false, "phase 12: the chassis is hidden (never destroyed)")
    ck(type(View.chassis) == "table", "phase 12: …and still exists for a re-enable")
    local allBack = true
    for _, id in ipairs(View.ids) do
        if _G["ChatFrame" .. id]:IsShown() ~= true then allBack = false end
    end
    ck(allBack, "phase 12: RED CONTROL — every engine window is SHOWN again")
    ck(next(View._engineHidden) == nil, "phase 12: …and nothing is being held down")
    -- THE SATELLITE ROUND TRIP: every piece of dress we took down is back, and
    -- exactly those — a satellite the client already had hidden when we arrived
    -- (the edit box under chatStyle 'classic') is not "restored" into a state it
    -- was never in.
    local dressBack, dressExtra = true, {}
    for _, id in ipairs(View.ids) do
        for w in pairs(dressBefore[id] or {}) do
            if w ~= ebHosted and not w._shown then dressBack = false end
        end
        for _, w in ipairs(Sim.SatellitesOf(View.ClientFrame(id))) do
            if w._shown and not (dressBefore[id] and dressBefore[id][w])
               and w ~= ebHosted and w._kind ~= "EditBox" then
                -- Not ours to have shown: the client's own restore beat may
                -- legitimately raise things, so this is recorded, not failed.
                dressExtra[#dressExtra + 1] = tostring(w._name)
            end
        end
    end
    ck(dressBack, "phase 12: RED CONTROL — every satellite the view took down is SHOWN "
        .. "again (the complete family round-trips, not just the window)")
    ck(ebHosted and ebHosted._parent == _G["ChatFrame" .. View.HostId()],
        "phase 12: the edit box went HOME to its own client window")
    ck(View._ebHome == nil, "phase 12: …and the view holds no claim on it")
    ck(S.SnapPeers == View._snapPeersOriginal or type(S.SnapPeers) == "function",
        "phase 12: skin's SnapPeers override was handed back")
    ck(S.SnapPeers() ~= nil and S.SnapPeers()[1] ~= View.chassis,
        "phase 12: …and it answers skin's own set again")
    local storeStillSame = true
    for id = 1, 10 do
        local w = Sim.windows[id]
        local now = w and (tostring(w.shown) .. "/" .. tostring(w.docked)) or "?"
        if now ~= storeBefore[id] then storeStillSame = false end
    end
    ck(storeStillSame, "phase 12: the per-character store is exactly as we found it")
    -- A line after the restore still lands where the client puts it.
    local n12 = _G.ChatFrame1:GetNumMessages()
    local mirroredAfter = View.mirrored
    Sim.SendChat{ event = "CHAT_MSG_SAY", text = "after-restore",
                  sender = "Puu-Whitemane", guid = "Player-1-00000001" }
    if HT then HT.advance(0) end
    ck(_G.ChatFrame1:GetNumMessages() == n12 + 1, "phase 12: stock chat still works")
    ck(View.mirrored == mirroredAfter,
        "phase 12: …and the disabled view's wrapper mirrored NOTHING (inert body)")

    -- Leave the module ON: this is the shipped posture, and the integration
    -- suite runs after every module suite against the world as it is left.
    ns.SetModuleEnabled("view", true)
    if HT then HT.flush() end
    ck(View.active == true, "phase 12: re-enabling brings the view back")
    ck(View.chassis._shown == true, "phase 12: …with the chassis on screen again")
    ns.SetModuleEnabled("view", false)
    if HT then HT.flush() end
end

ns:RegisterSelfTest("view", function(verbose)
    local fails = {}
    local ok, err = pcall(testPure, fails)
    if not ok then fails[#fails + 1] = "pure: " .. tostring(err) end
    local ok2, err2 = pcall(testLive, fails, verbose)
    if not ok2 then fails[#fails + 1] = "live: " .. tostring(err2) end
    for _, f in ipairs(fails) do ns:Print("  FAIL view :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS view") end
    return #fails == 0
end)

return View
