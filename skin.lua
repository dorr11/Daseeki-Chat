-- Daseeki Chat — skin.lua  (Wave 1 + skin v2, real)
-- The skin-over treatment of the client's ten chat windows: suite-themed frame
-- backdrops and tab styling, a themed ATTACHED edit box (the panel-bar look —
-- the survey's ElvUI archetype; NEVER a custom message view), Core font roles
-- applied to every window's text, configurable text fading, and the per-window
-- COPY-CHAT affordance (era has no clipboard: a themed window shows the frame's
-- visible text pre-selected in an edit box for Ctrl+C).
--
-- SKIN V2 — the padded-dark-panel evolution, four independently config-gated
-- features (db.skin.*, all additive, defaults ON except the rail):
--
--   1. CHANNEL-COLORED TABS (channelTabs, ON). Each tab's label ink derives
--      from the window's DOMINANT channel, resolved from the window's ROUTING
--      (the effective config's message groups + channels by name; a live
--      Config.CaptureWindow when the config has no entry yet). Dominance is
--      strict: exactly ONE identity survives the walk or there is none. The
--      colors come from the CLIENT's own chat color table (GetMessageTypeColor
--      -> ChatTypeInfo, catalog-verified 11509), so they cooperate with the
--      player's color settings and move live on UPDATE_CHAT_COLOR (our own
--      gated listener — never coupled to another module's). Active tab: full
--      strength ink + the suite's accent underline. Inactive: the same ink
--      dimmed by a TOKEN-DERIVED factor (muted/text luminance — a theme change
--      moves it). No dominant channel -> the accent/muted token treatment,
--      which is Wave 1's behavior, PINNED as the fallback.
--   2. TIMESTAMP DIVIDER (stampDivider, ON). A theme border-token hairline
--      between the stamp column and the message text, present only while
--      stamps.lua is actually stamping. Coordination with stamps is READ-ONLY
--      and by MEASUREMENT: the stamp column is measured with a probe
--      FontString wearing the window's own font, never computed from stamps'
--      internals.
--   3. EDIT-BOX CHANNEL PREFIX (editBoxChannelColor, ON). The attached edit
--      box's sticky-channel header wears that channel's client color, hooked
--      on ChatEdit_UpdateHeader the way the tab ink hooks FCF_SelectDockFrame.
--   4. ICON RAIL (iconRail, OFF — the speculative one). A slim themed strip on
--      the window's left edge carrying ONLY verbs Chat already owns:
--      copy-chat (Skin.OpenCopy), settings (ns.SlashDispatch) and the client's
--      own frame:ScrollToBottom. No new features hide behind these buttons.
--
-- SKIN V2.1 — the "do I have to use edit mode to move this" trio, all ON:
--
--   5. ALT-DRAG MOVE (altDragMove). ALT-drag anywhere on a window's panel
--      region moves it; a DOCKED window moves the dock (its primary frame),
--      because that is the only move the dock manager will keep. The release
--      captures the new position back into the authoritative config through
--      the reconciler's own debounced path, so echo discipline, rev bumping
--      and mesh sync are unchanged. UNMODIFIED CLICKS ARE NEVER INTERCEPTED —
--      chat text, links and scrolling stay exactly native — and /dchat unlock
--      is the discoverable fallback for anyone who does not know the gesture.
--   6. PERSISTENT EDIT BOX (persistentEditBox). The attached bar never hides:
--      it rests at its configured position wearing the CLIENT's own sticky
--      prefix ("Say:", "Guild:") in that channel's color, quiet while
--      unfocused, full strength while focused. Escape unfocuses; it does not
--      hide. The send path is untouched.
--   7. LOOSENED CLAMP (unclampWindows). Zeroed clamp rect insets on the
--      managed windows so a MANUAL drag can reach the screen edge — the frame
--      stays clamped ON screen, it just stops being held a margin away.
--      Re-asserted on every re-evaluation beat AND on every client beat that
--      rewrites the insets (the button-side decision, the window update, the
--      dock pass), in-call; deferred to the regen beat when the write is
--      refused in combat.
--
-- SKIN V2.2 — the chat BUTTON COLUMN, down by default:
--
--   8. HIDE THE BUTTON COLUMN (hideButtonColumn, ON). The client's per-window
--      chat-menu + scroll-button column is taken down and KEPT down against
--      the client's own re-shows. It is the other half of "drag it flush to
--      the edge": the client flips the column's side by screen position
--      (which is why two accounts wear it on opposite sides) and its width is
--      part of what a drag has to fit on screen. The one verb it owned — the
--      client's chat menu — stays reachable: on the icon rail, and by
--      right-clicking the resting edit bar's channel prefix. OFF is the
--      client's own column back, side-flipping and all.
--
-- SKIN V3 — THE ONE BOX (unifiedChassis, ON; the owner's approved mockup):
--
--   9. ONE UNIFIED CHASSIS per window group. A single suite-token backdrop
--      spans the tab strip, the message area and the entry bar. There is NO
--      second background anywhere inside it: the entry bar's own panel is put
--      away, the tab strip/rail is a bare anchor frame, and the only internal
--      marks are HAIRLINES in the border token. Fading is forced OFF inside
--      the box (the config's fading knob goes inert, with the settings page
--      saying so out loud — no half states).
--      A DOCKED window's box belongs to the DOCK: the dock's primary frame
--      hosts one chassis and one strip carrying every docked window's tab.
--      An undocked window is its own group and hosts its own.
--  10. TAB PLACEMENT (config.skin.tabPlacement: "top" | "left" | "right",
--      SYNCED — it is layout, so it rides the mesh with the rest of the chat
--      config). TOP is a strip inside the box's top edge and the active tab
--      FUSES with the message surface: the hairline that separates strip from
--      messages is drawn in two pieces that stop at the active tab's edges, so
--      the surface runs continuously through it — the mockup's fused tab,
--      expressed with hairlines instead of a second fill. LEFT/RIGHT is a slim
--      vertical rail inside that edge, its inner hairline continuous, and the
--      active tab marked by a colored EDGE BAR on the rail's inner side.
--      The client's OWN tab buttons are re-anchored into the strip/rail — they
--      are never replaced — so click, drag-to-undock and the tab's right-click
--      menu stay exactly the client's. The dock manager re-lays them on its own
--      beats; we take the last word in-call, the button column's posture.
--  11. PER-TAB COLOR (config.windows[id].tabColor, SYNCED, optional). The
--      resolution chain is EXPLICIT > DERIVED > accent/muted token. A spec is
--      "token:<core token>" or "chat:<CHAT_TYPE>", so both families stay live:
--      a token follows the theme, a chat type follows the player's own chat
--      colors. A spec this build does not understand falls through to the
--      derivation rather than painting a wrong color.
--  12. THE ICON RAIL COEXISTS by taking the OPPOSITE edge: with tabs on the
--      left the icon rail moves to the window's right, otherwise it keeps the
--      left. It clears the chassis' own inset on whichever side it lands.
--
-- Everything visual reads Daseeki-Core theme tokens at render (DaseekiUI.Color/
-- Token / FLAT_BACKDROP / UI.Skin / UI.fonts / UI.FontFile) — ZERO hardcoded
-- colors anywhere in this file; alpha/measure constants only. The one family
-- of colors that is NOT a token is the CLIENT's chat colors, which are read
-- live from the client's table on every render (a hardcoded green would stop
-- tracking the player's own settings, and the suite pins exactly that).
--
-- INERTNESS (the suite discipline, and the harness's pin): this module touches
-- NOTHING until its OnEnable runs — no hooks, no texture strips, no frames.
-- OnDisable restores what it changed and goes quiet. The two irreversible
-- client mechanisms (hooksecurefunc has no un-hook) are installed once, on the
-- FIRST enable, and their bodies gate on Skin.active.
--
-- All display glyphs in this file are ASCII (the tofu lesson: any non-ASCII
-- glyph must be verified against the vendored face's cmap first).

local ADDON, ns = ...

local Skin = {
    active  = false,   -- gate for every hook body and event handler
    hooked  = false,   -- one-time hooksecurefunc installs done
    styled  = {},      -- frame -> per-frame rig record
    order   = {},      -- styled frames in style order (stable iteration)
    -- skin v2.1 state
    moveMode = false,  -- /dchat unlock: plain drag moves (session-scoped)
    moves    = 0,      -- completed drags (the harness reads this)
    _ebDepth = 0,      -- persistent-edit-box re-entrancy latch (Class 9)
    _clampPending = {},-- frames whose clamp write was refused in combat
    -- skin v2.2 state (the chat button column)
    columnHides = 0,   -- times we actually took the column down (never a loop)
    menuOpens   = 0,   -- times we opened the client's chat menu
    _bfDepth    = 0,   -- button-column re-entrancy latch (Class 9)
    -- skin v2.3 state (the column is DISABLED, not just hidden — owner ask)
    columnDisables     = 0,   -- windows whose column subtree lost the mouse
    columnEventsDropped = 0,  -- widgets we called UnregisterAllEvents on
    -- skin v3 state (the one box)
    _chassisDepth      = 0,   -- chassis re-evaluation re-entrancy latch (Class 9)
    -- skin v3.1 state (the fade strip / the bounce / snapping)
    alphaPins    = 0,   -- times we actually took the tab's alpha back (never a loop)
    _alphaDepth  = 0,   -- alpha-pin re-entrancy latch (Class 9)
    moveCommits  = 0,   -- moves written through the client's own save verb
    snaps        = 0,   -- drops corrected onto a boundary
    lastSnap     = nil, -- { x = <kind>, y = <kind> } for the last corrected drop
}
ns.Skin = Skin

----------------------------------------------------------------------
-- ============ RETIREMENT NOTICE — D2 REVISION, 2026-08-11 ============
--
-- THE MOCKUP CONTRACT AND THE PALETTE HAVE MOVED TO view.lua. They belonged to
-- whoever paints the pixels, and that is no longer this file: the owner
-- directed the D2 revision ("if drawing our own gets a better result, do
-- that"), so Daseeki-Chat draws its OWN chassis over a hidden client engine and
-- the mapping table lives beside the renderer it governs. Six of that table's
-- rows used to say CLIENT LIMIT because they were properties of painting on
-- somebody else's frame; owning the frame retired four of them outright.
--
-- WHAT RETIRES HERE, and how: every CLIENT-FRAME RESTYLE path below is gated
-- OFF while the view owns the pixels (Skin.ViewOwnsPixels) rather than deleted,
-- because "the box off" is still a shipped, tested state — the v2/v3 treatment
-- is what a player gets if they disable the view module, and a path with no
-- test is a path with no truth. The gated set is exactly:
--   * the chassis-on-a-client-frame (ensureBackdrop / UpdateChassis / the strip)
--   * the client tab restyle (styleTab / tab art strip / tab fill / underline)
--   * the tab-alpha strip (KeepOpaque / the three FCF alpha post-hooks)
--   * the stock-art strip (stripStock)
--   * client typography (applyFrameFont / SetSpacing on a client window)
--
-- WHAT SURVIVES AND IS REUSED BY THE VIEW, unchanged:
--   * the movement / capture-back / clamp layer and Skin.CommitMove;
--   * the FRAME-AGNOSTIC SNAP LAYER, through its published SnapPeers override
--     point — view.lua points it at its own chassis and forks nothing;
--   * the button-column disable (harmless with the engine hidden, and still
--     wanted the moment the view is turned off);
--   * the copy window (Skin.OpenCopy reads any frame with the public message
--     history surface, which is exactly what a view frame is);
--   * the palette ACCESSOR (Skin.Ink / Skin.Palette below), kept as the seam
--     stamps.lua and badges.lua already call — it now delegates to view.lua's
--     table rather than holding a second copy;
--   * the pure resolution helpers (DominantChannel / TabInk / TabLabel /
--     ChannelInk / DefangLine / ExtractCopyText), which the view calls.
--
-- The measurement constants below stay: the box-off path still renders with
-- them, and view.lua carries its own copies as the OWNER-AMENDED values it
-- ships (one file, one set of numbers it is responsible for).
----------------------------------------------------------------------

----------------------------------------------------------------------
-- ======== THE MOCKUP CONTRACT — MOVED TO view.lua, 2026-08-11 ========
--
-- The mapping table that stood here — every mockup CSS declaration against
-- what shipped, marked IDENTICAL or with the client limit that refused it —
-- MOVED TO view.lua on 2026-08-11 with the D2 revision, together with the
-- PALETTE table it referred to. It governs the renderer, and the renderer is
-- view.lua now. See view.lua's header for the current contract (and for which
-- of the old CLIENT LIMIT rows survived owning the frame: four did, three
-- rounded-corner rows became DEFERRED, and the rest died with skin-over).
--
-- The measurement constants this file still needs (the box-off path renders
-- with them) are declared below, unchanged. view.lua carries its own copies of
-- the OWNER-AMENDED values as the numbers IT is responsible for; the two are
-- deliberately separate because they render two different things.
----------------------------------------------------------------------

-- THE PALETTE ACCESSOR. The table itself lives in view.lua now (it is the
-- renderer's, and the renderer moved); this stays as the SEAM stamps.lua and
-- badges.lua already call, so neither has to learn a new name and neither ever
-- holds a second copy of a hex. Answers nil for an unknown name, exactly as
-- before — never a hopeful black (Class 5 applied to ink).
function Skin.Ink(name, alpha)
    local V = ns.View
    if V and type(V.Ink) == "function" then
        local ok, r, g, b, a = pcall(V.Ink, name, alpha)
        if ok and type(r) == "number" then return r, g, b, a end
    end
    return nil
end

-- The palette itself, read-only by convention (the settings page and the
-- harness both want to name a colour without re-typing it). Delegated like
-- Skin.Ink above — one table, in view.lua.
function Skin.Palette()
    local V = ns.View
    if V and type(V.Palette) == "function" then
        local ok, t = pcall(V.Palette)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

-- Layout constants (measures, not colors).
local BG_ALPHA    = 0.85   -- v2 chat backdrop fill alpha over the world
local PAD         = 4      -- v2 backdrop overhang around the message area
local TAB_DIM     = 0.6    -- unselected docked tab alpha (survey: ElvUI behavior)
local COPY_IDLE   = 0.35   -- copy affordance alpha until hovered
local COPY_MAX    = 512    -- copy window: max lines pulled from a frame
local UL_HEIGHT   = 2      -- active-tab underline thickness       (mockup ::after height)
local UL_INSET    = 6      -- underline inset from each tab edge    (mockup left/right 6px)
local UL_Y        = 0      -- underline lift off the tab's bottom   (mockup bottom 0)
local DIV_WIDTH   = 1      -- timestamp divider hairline width      (mockup .stampline width)
local DIV_GAP     = 2      -- v2 gap between the stamp column and the hairline
local DIV_ALPHA   = 0.55   -- v2 hairline alpha (subtle, per the reference)
local STAMP_GAP   = 8      -- mockup .msgs .row gap, aimed each side of the hairline
local RAIL_WIDTH  = 16     -- icon rail strip width
local RAIL_BTN    = 16     -- one rail button's square edge
local RAIL_GAP    = 2      -- gap between the rail and the window
local RAIL_IDLE   = 0.35   -- rail alpha until hovered
local EB_IDLE     = 0.55   -- persistent edit box alpha while unfocused (placeholder)
local EB_ACTIVE   = 1.0    -- …and while it holds focus
-- THE ONE BOX, straight off the mapping table above.
local CHASSIS_EDGE  = 1    -- .chatbox border width
local STRIP_PAD_TOP = 2    -- .tabs-top padding-top          (owner amendment: 6 -> 2)
local STRIP_PAD_X   = 3    -- .tabs-top padding-left/right   (owner amendment: 8 -> 3)
local TAB_TEXT_SIZE = 12.5 -- .tab font-size
local TAB_LINE_H    = 18   -- .tab line-height (12.5 * 1.45)
local TAB_PAD_TOP   = 2    -- .tab padding-top               (owner amendment: 5 -> 2)
local TAB_PAD_X     = 14   -- .tab padding-left/right
local TAB_PAD_BOT   = 4    -- .tab padding-bottom            (owner amendment: 6 -> 4)
local TAB_H         = TAB_PAD_TOP + TAB_LINE_H + TAB_PAD_BOT      -- 24 (was 29)
local STRIP_H       = STRIP_PAD_TOP + TAB_H                       -- 26 (was 35)
local TAB_GAP       = 2    -- .tabs-top gap
local MSG_PAD_TOP   = 10   -- .msgs padding-top
local MSG_PAD_X     = 3    -- .msgs padding-left/right       (owner amendment: 14 -> 3)
local MSG_PAD_BOT   = 6    -- .msgs padding-bottom
local ROW_SPACING   = 3    -- .msgs .row padding 1.5px each side
local MOCKUP_LINE_H = 13.5 -- .msgs font-size (the feed's own size)
local MOCKUP_LINE_HEIGHT = 1.45 -- .msgs line-height
local EB_HEIGHT     = 26   -- .entry: 3 + (13.5 * 1.45) + 3  (owner amendment: 36 -> 26)
local EB_PAD_X      = 12   -- .entry padding-left/right
local EB_PAD_Y      = 3    -- .entry padding-top/bottom      (owner amendment: 8 -> 3)
-- The mockup's entry bar is FLUSH (the hairline is the whole seam), which the
-- box expresses with SEAM_W; EB_GAP is the v2 path's own gap and stays at the
-- value v2 shipped, so turning the box off really is byte for byte.
local EB_GAP        = 2
local TABRAIL_W     = 112  -- .tabs-side width
local RAIL_PAD_Y    = 4    -- .tabs-side padding-top/bottom  (owner amendment: 8 -> 4)
local RAIL_PAD_X    = 6    -- .tabs-side padding-left/right
local RAIL_TAB_PAD_Y = 4   -- .stab padding-top/bottom       (owner amendment: 7 -> 4)
local RAIL_TAB_PAD_X = 10  -- .stab padding-left/right
local TAB_ROW_H     = RAIL_TAB_PAD_Y + TAB_LINE_H + RAIL_TAB_PAD_Y  -- 26 (was 32)
local SEAM_W        = 1    -- .entry border-top / .tabs-side border-left
local EDGEBAR_W     = 2    -- .stab.active::before width
local EDGEBAR_INSET = 5    -- …its top/bottom inset
local HOVER_WASH    = 0.04 -- .tab:hover rgba(255,255,255,.04)
local PIP_GAP       = 6    -- .tab .n margin-left
-- v2 kept these names; the box no longer uses them, and the v2 path still does.
local TAB_PAD       = 6    -- v2 strip/rail padding around the tab run

-- Skin v2 config fields, declared ADDITIVELY from this module (the badges.lua
-- precedent) so core.lua's DEFAULTS block stays this module's business only.
-- EnsureDefaults runs at DB_READY, after every file has loaded.
ns.DEFAULTS.skin.channelTabs         = true   -- tab ink from the window's channel
ns.DEFAULTS.skin.stampDivider        = true   -- hairline between stamps and text
ns.DEFAULTS.skin.editBoxChannelColor = true   -- edit-box header in channel color
ns.DEFAULTS.skin.iconRail            = false  -- left-edge affordance rail (opt-in)
-- skin v2.1 (the move / persistent-edit-box / clamp trio, all default ON per
-- the owner's ask; each is an independent gate and OFF means byte-identical
-- native behavior).
ns.DEFAULTS.skin.altDragMove         = true   -- ALT-drag anywhere on a window moves it
ns.DEFAULTS.skin.persistentEditBox   = true   -- the edit box never hides
ns.DEFAULTS.skin.unclampWindows      = true   -- drags may reach the screen edge
-- skin v2.2: the client's chat BUTTON COLUMN is down by default (the reference
-- look replaces it; OFF gives the client's own column back, side-flip and all).
ns.DEFAULTS.skin.hideButtonColumn    = true   -- hide the chat button column
-- skin v3: THE ONE BOX. Local gate (the LOOK is per-account taste; the tab
-- PLACEMENT inside it is layout and lives in the synced config). OFF is skin
-- v2 byte for byte, fading included.
ns.DEFAULTS.skin.unifiedChassis      = true   -- one backdrop: strip + text + entry
-- skin v3.1: DROP SNAPPING. A drop within SNAP_THRESHOLD of a screen edge, a
-- screen centre line or another chat window's edge lands ON it, exactly. The
-- threshold is a constant, not a slider (see the snap section).
ns.DEFAULTS.skin.snapToEdges         = true   -- snap to edges when dragging
-- skin v3.1: TYPOGRAPHY, config-backed with the MOCKUP's own values as the
-- defaults. 0 (or nil) on the size means "the client's right-click Font size
-- menu is the authority", which is exactly what skin v1 shipped and what the
-- box-off path still does.
ns.DEFAULTS.skin.messageFontSize     = MOCKUP_LINE_H       -- .msgs font-size 13.5
ns.DEFAULTS.skin.lineHeight          = MOCKUP_LINE_HEIGHT  -- .msgs line-height 1.45

local function UIKit() return _G.DaseekiUI end

local function cfg()
    return (ns.db and ns.db.skin) or ns.DEFAULTS.skin
end

----------------------------------------------------------------------
-- SKIN V3 READS. Two questions everything below asks: is the box on, and
-- where do the tabs live. The placement comes from the SYNCED config through
-- its own seam (Config.TabPlacement), runtime-defended like every peer read —
-- a config that cannot answer leaves us on "top", which is the client's own
-- arrangement and therefore the safe answer.
----------------------------------------------------------------------

-- ── THE RETIREMENT GATE (D2 revision, 2026-08-11) ────────────────────────────
-- One question, asked in one place: is view.lua painting right now? While it
-- is, every CLIENT-FRAME restyle path in this file is inert — the client's
-- windows are hidden and dressing a hidden window is work nobody sees. What
-- keeps running is the movement/capture/snap layer, the button-column disable
-- and the copy window, all of which the view reuses (see the retirement notice
-- at the top of this file for the full list).
function Skin.ViewOwnsPixels()
    local V = ns.View
    return (V and V.active) and true or false
end

-- Hand the client's frames back before the view goes on, so there is never a
-- moment with two treatments on one window. Called by view.lua's OnEnable.
-- Reversible by construction: this is the same restore path OnDisable uses,
-- and Skin.StyleAll re-dresses if the view is turned off with skin still on.
function Skin.RetireStyling()
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec then Skin.RestoreDress(frame, rec) end
    end
    return #Skin.order
end

function Skin.Unified()
    -- The one box is skin-over's box. With the view painting there is no
    -- skin-over box at all, and every `if Skin.Unified()` branch below (and in
    -- badges.lua, which asks the same question about its chip) has to hear
    -- that from one place rather than each guessing.
    if Skin.ViewOwnsPixels() then return false end
    return (cfg().unifiedChassis ~= false) and true or false
end

function Skin.TabPlacement()
    local C = ns.Config
    if C and type(C.TabPlacement) == "function" then
        local ok, v = pcall(C.TabPlacement)
        if ok and (v == "top" or v == "left" or v == "right") then return v end
    end
    return "top"
end

-- Is the tab strip a vertical RAIL right now? (The one branch half this file
-- takes, asked once so it cannot be spelled two different ways.)
function Skin.TabsOnRail()
    if not Skin.Unified() then return false end
    local p = Skin.TabPlacement()
    return p == "left" or p == "right"
end

----------------------------------------------------------------------
-- Window enumeration. The client's model is fixed: ChatFrame1..NUM_CHAT_WINDOWS
-- permanent windows (2 = combat log) plus temporary frames past index 10.
-- We style windows that are shown OR docked; a window the player has closed
-- stays untouched until the client shows it (temp-window hook catches those).
----------------------------------------------------------------------

local function numWindows() return _G.NUM_CHAT_WINDOWS or 10 end

-- One numeric widget read, defended: nil for "the client would not answer",
-- never a hopeful zero (Class 5 — 0 is truthy and a truthy wrong answer is
-- worse than no answer). Used by the geometry readers throughout this file.
local function widgetNum(w, method)
    if type(w) ~= "table" then return nil end
    local f = w[method]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, w)
    if ok and type(v) == "number" then return v end
    return nil
end

local function isCombatLog(frame, id)
    local f = _G.IsCombatLog
    if type(f) == "function" then
        local ok, res = pcall(f, frame)
        if ok then return res and true or false end
    end
    return id == 2   -- runtime-defended fallback: ChatFrame2 is the combat log
end

local function windowEligible(id)
    -- GetChatWindowInfo returns: name, fontSize, r, g, b, alpha, shown, locked,
    -- docked, uninteractable (era 11509 shape; arity defended at runtime).
    local gcwi = _G.GetChatWindowInfo
    if type(gcwi) ~= "function" then return false end
    local ok, name, fontSize, _, _, _, _, shown, _, docked = pcall(gcwi, id)
    if not ok then return false end
    return (shown and shown ~= 0) or (docked and docked ~= 0), name, fontSize
end

----------------------------------------------------------------------
-- CHANNEL IDENTITY (skin v2 feature 1, the headline).
--
-- Two pure steps, both harness-tested directly:
--   DominantChannel(entry, isCombatLog)  routing  -> identity, or nothing
--   ChannelInk(kind, value)              identity -> the CLIENT's color
--
-- The dominance rule is deliberately STRICT: a window earns a channel ink only
-- when its routing collapses to exactly ONE identity. The client's default
-- window routes a dozen groups and therefore has none — it keeps the suite's
-- token treatment, which is the Wave-1 look and the pinned fallback.
--
-- AMBIENT groups (system chatter, loot, combat spam, skill-ups) never
-- establish identity: they ride along in a window that is otherwise plainly a
-- guild window, and counting them would make every real window "multi".
-- FAMILY groups fold onto their head (OFFICER is guild chat; RAID_LEADER is
-- raid chat), so a Guild tab routing GUILD+OFFICER is still a guild tab.
----------------------------------------------------------------------

local AMBIENT_GROUPS = {
    SYSTEM = true, ERRORS = true, LOOT = true, MONEY = true, CURRENCY = true,
    SKILL = true, OPENING = true, PET_INFO = true, TRADESKILLS = true,
    ACHIEVEMENT = true, GUILD_ACHIEVEMENT = true, TARGETICONS = true,
    IGNORED = true, AFK = true, DND = true, COMBAT_XP_GAIN = true,
    COMBAT_HONOR_GAIN = true, COMBAT_FACTION_CHANGE = true,
    COMBAT_MISC_INFO = true, BG_SYSTEM_NEUTRAL = true, BG_SYSTEM_ALLIANCE = true,
    BG_SYSTEM_HORDE = true, MONSTER_BOSS_EMOTE = true, MONSTER_BOSS_WHISPER = true,
    MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_EMOTE = true,
    MONSTER_WHISPER = true, MONSTER_PARTY = true,
}

local GROUP_FAMILY = {
    OFFICER              = "GUILD",
    PARTY_LEADER         = "PARTY",
    RAID_LEADER          = "RAID",
    RAID_WARNING         = "RAID",
    INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    WHISPER_INFORM       = "WHISPER",
    BN_WHISPER           = "WHISPER",
    BN_WHISPER_INFORM    = "WHISPER",
}

-- PURE. entry = a config-shaped window entry ({ groups = {...}, channels = {...} }).
-- Returns "combatlog" | ("type", CHATTYPE) | ("channel", name) | nil.
function Skin.DominantChannel(entry, combatLog)
    if combatLog then return "combatlog" end
    if type(entry) ~= "table" then return nil end
    local seen, found = {}, {}
    local function add(key, kind, value)
        if seen[key] then return end
        seen[key] = true
        found[#found + 1] = { kind = kind, value = value }
    end
    for _, g in ipairs(entry.groups or {}) do
        if type(g) == "string" and g ~= "" then
            local up = g:upper()
            -- The CHANNEL group is the routing SWITCH for named channels, not
            -- an identity of its own; the names below carry that identity.
            if up ~= "CHANNEL" and not AMBIENT_GROUPS[up] then
                local head = GROUP_FAMILY[up] or up
                add("TYPE:" .. head, "type", head)
            end
        end
    end
    for _, c in ipairs(entry.channels or {}) do
        if type(c) == "string" and c ~= "" then
            add("CHAN:" .. c:lower(), "channel", c)
        end
    end
    if #found == 1 then return found[1].kind, found[1].value end
    return nil
end

-- The CLIENT's color for a chat type. Primary read is GetMessageTypeColor
-- (catalog 11509); ChatTypeInfo is the runtime-defended fallback, and a
-- non-numeric answer from either is treated as NO answer (never a silent
-- white). Returns r, g, b or nil.
function Skin.TypeColor(chatType)
    if type(chatType) ~= "string" or chatType == "" then return nil end
    local f = _G.GetMessageTypeColor
    if type(f) == "function" then
        local ok, r, g, b = pcall(f, chatType)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    local CTI = _G.ChatTypeInfo
    local info = type(CTI) == "table" and CTI[chatType] or nil
    if type(info) == "table" and type(info.r) == "number"
        and type(info.g) == "number" and type(info.b) == "number" then
        return info.r, info.g, info.b
    end
    return nil
end

-- A named (or numbered) channel's color. The client keys channel colors by
-- NUMBER and numbers move, so a name is resolved through GetChannelName every
-- time — the same by-name discipline channels.lua uses for imposition.
function Skin.ChannelColorOf(nameOrNumber)
    local n = tonumber(nameOrNumber)
    if not n and type(nameOrNumber) == "string" and nameOrNumber ~= "" then
        local f = _G.GetChannelName
        if type(f) == "function" then
            local ok, num = pcall(f, nameOrNumber)
            if ok then n = tonumber(num) end
        end
    end
    if n and n > 0 then
        local r, g, b = Skin.TypeColor("CHANNEL" .. n)
        if r then return r, g, b end
    end
    return Skin.TypeColor("CHANNEL")   -- un-joined / unnumbered: the generic ink
end

function Skin.ChannelInk(kind, value)
    if kind == "type" then return Skin.TypeColor(value) end
    if kind == "channel" then return Skin.ChannelColorOf(value) end
    return nil
end

-- The inactive-tab dim, DERIVED FROM TOKENS (never a hardcoded alpha): the
-- muted token's share of the muted+text luminance, mapped into a sane band.
-- The mapping cannot clamp, so a theme change always moves the answer — which
-- is what makes the harness assertion impossible to satisfy with a constant.
local DIM_FLOOR, DIM_SPAN = 0.30, 0.60

local function luminance(r, g, b)
    return 0.2126 * (tonumber(r) or 0) + 0.7152 * (tonumber(g) or 0)
         + 0.0722 * (tonumber(b) or 0)
end

function Skin.DimFactor()
    local UI = UIKit()
    if not UI or type(UI.Color) ~= "function" then return DIM_FLOOR + DIM_SPAN * 0.5 end
    local lm = luminance(UI.Color("muted"))
    local lt = luminance(UI.Color("text"))
    local total = lm + lt
    if total <= 0 then return DIM_FLOOR + DIM_SPAN * 0.5 end
    return DIM_FLOOR + DIM_SPAN * (lm / total)
end

-- The routing a window is judged on: the EFFECTIVE config's entry when the
-- config speaks about this window (config is authoritative — design rule 1),
-- otherwise a live capture of the client store (a fresh install, before any
-- adopt, still gets colored tabs). Returns entry, source.
function Skin.WindowRouting(id)
    if not id then return nil, nil end
    local C = ns.Config
    if not C then return nil, nil end
    if type(C.EffectiveCfg) == "function" then
        local ok, eff = pcall(C.EffectiveCfg)
        local w = ok and type(eff) == "table" and type(eff.windows) == "table"
            and eff.windows[id] or nil
        if type(w) == "table" and (type(w.groups) == "table" or type(w.channels) == "table") then
            return w, "config"
        end
    end
    if type(C.CaptureWindow) == "function" then
        local ok, cap = pcall(C.CaptureWindow, id)
        if ok and type(cap) == "table" then return cap, "client" end
    end
    return nil, nil
end

----------------------------------------------------------------------
-- PER-TAB COLOR (skin v3 feature 11) — the EXPLICIT head of the chain.
--
-- A tab colour is stored as a SPEC STRING in the synced config, and this file
-- owns the vocabulary:
--   "token:<name>"  a Daseeki-Core theme token — follows a theme change;
--   "chat:<TYPE>"   one of the CLIENT's own chat colors — follows the
--                   player's own chat colour settings, live.
-- Both families are LIVE reads, never frozen values: the config stores which
-- colour, never what colour, so nothing here can rot into a stale hex.
--
-- A spec this build does not understand answers NOTHING and the caller falls
-- through to the derivation — a newer build's vocabulary must never paint a
-- wrong colour here. Returns r, g, b, family.
----------------------------------------------------------------------

function Skin.ResolveTabColor(spec)
    if type(spec) ~= "string" then return nil end
    local kind, value = spec:match("^(%a+):(.+)$")
    if not kind then return nil end
    if kind == "token" then
        local UI = UIKit()
        if not (UI and type(UI.Color) == "function") then return nil end
        local ok, r, g, b = pcall(UI.Color, value)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, "token"
        end
        return nil
    elseif kind == "chat" then
        local r, g, b = Skin.TypeColor(value:upper())
        if r then return r, g, b, "chat" end
    end
    return nil
end

-- The spec the config holds for a window, through the config's own seam.
function Skin.TabColorSpec(id)
    if id == nil then return nil end
    local C = ns.Config
    if not (C and type(C.TabColor) == "function") then return nil end
    local ok, spec = pcall(C.TabColor, id)
    if ok and type(spec) == "string" and spec ~= "" then return spec end
    return nil
end

-- One tab's ink at full strength, plus where it came from. A temporary window
-- (a whisper pop-out) carries its own routing on the frame, which is the only
-- routing it will ever have. Returns r, g, b, source.
--
-- THE RESOLUTION CHAIN (skin v3): EXPLICIT per-tab colour first, then the
-- derivation from the window's dominant channel, then the caller's accent/
-- muted token fallback. The explicit choice is the PLAYER's and outranks the
-- channelTabs feature gate entirely: turning the derivation off must not
-- silently discard a colour somebody picked by hand.
function Skin.TabInk(frame, id)
    local UI = UIKit()
    if not UI then return nil end
    local r, g, b, fam = Skin.ResolveTabColor(Skin.TabColorSpec(id))
    if r then return r, g, b, "explicit:" .. tostring(fam) end
    if not cfg().channelTabs then return nil end
    if isCombatLog(frame, id) then
        local r, g, b = UI.Color("muted")
        return r, g, b, "combatlog"
    end
    if frame and frame.isTemporary and type(frame.chatType) == "string" and frame.chatType ~= "" then
        local head = GROUP_FAMILY[frame.chatType:upper()] or frame.chatType:upper()
        local r, g, b = Skin.TypeColor(head)
        if r then return r, g, b, "temporary" end
        return nil
    end
    local entry = Skin.WindowRouting(id)
    local kind, value = Skin.DominantChannel(entry, false)
    if not kind then return nil end
    local r, g, b = Skin.ChannelInk(kind, value)
    if not r then return nil end
    return r, g, b, kind
end

----------------------------------------------------------------------
-- Copy-chat text extraction (PURE — the harness tests this directly).
--
-- Reads the frame's visible history through the PUBLIC message-history surface
-- (GetNumMessages / GetMessageInfo — the game-facts register's sanctioned read;
-- the underlying ring buffer is the same store the client renders from).
-- Hyperlinks are DEFANGED for display: |H...|h markup drops to its visible
-- text, colors strip, |K protected spans become "???" (they cannot be
-- string-copied meaningfully), textures drop (raid-target icons reverse-map to
-- their {rt#} chat tags so the copyable text round-trips).
----------------------------------------------------------------------

function Skin.DefangLine(text)
    if type(text) ~= "string" then return "" end
    local s = text
    -- Battle.net protected spans first (atomic; nothing inside is copyable).
    s = s:gsub("|K.-|k", "???")
    -- Hyperlinks: keep the display text, drop the click payload. Non-greedy so
    -- multiple links on one line each collapse independently.
    s = s:gsub("|H.-|h(.-)|h", "%1")
    -- Raid-target icon textures reverse-map to their typeable tags...
    s = s:gsub("|T[^|]-RaidTargetingIcon_(%d+)[^|]-|t", "{rt%1}")
    -- ...every other texture escape just drops.
    s = s:gsub("|T.-|t", "")
    -- Color escapes strip.
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- Escaped pipes un-escape last, once the markup passes above are done.
    s = s:gsub("||", "|")
    return s
end

function Skin.ExtractCopyText(frame, maxLines)
    maxLines = maxLines or COPY_MAX
    local lines = {}
    if not frame or type(frame.GetNumMessages) ~= "function" then return lines end
    local n = frame:GetNumMessages() or 0
    local first = math.max(1, n - maxLines + 1)
    for i = first, n do
        -- GetMessageInfo(i): index 1 is the OLDEST stored line; returns arrive
        -- oldest-to-newest, which is the reading order the copy window wants.
        local ok, msg = pcall(frame.GetMessageInfo, frame, i)
        if ok and type(msg) == "string" then
            lines[#lines + 1] = Skin.DefangLine(msg)
        end
    end
    return lines
end

----------------------------------------------------------------------
-- Fonts. Face comes from Core's picked face (UI.FontFile — already guarded by
-- Core's render-proof probe); SIZE stays per-window in the client's own store
-- (the survey's ElvUI split: the Blizzard right-click size menu keeps working).
----------------------------------------------------------------------

----------------------------------------------------------------------
-- TYPOGRAPHY PARITY (skin v3.1, the owner's "we're still not quite on par").
--
-- The mockup's feed has air between messages; the shipped render had lines
-- touching. Two numbers were missing, and both were being read from the wrong
-- authority:
--
--   * SIZE. The mockup sets `.msgs{font-size:13.5px}`. skin v1 pinned the
--     CLIENT's per-window size as the authority (the Blizzard right-click
--     "Font size" menu), which was the right call when there was no design to
--     be faithful to — but it means the box renders at whatever the client's
--     default happens to be, and the mockup's proportions are the ratio
--     between that size and every measure around it. It is now CONFIG-BACKED,
--     defaulting to the mockup's own 13.5, with 0/nil meaning "the client's
--     menu is the authority" — so the old behaviour is still reachable and is
--     exactly what the box-off path uses.
--   * SPACING. `line-height:1.45` is not a spacing value: it is the whole line
--     BOX, and a FontString already draws a line box of its own. So the value
--     SetSpacing wants is the DIFFERENCE, and it has to be COMPUTED from the
--     size in force — a hardcoded number would stop being 1.45 the moment the
--     player changed the font size. That computation is Skin.MessageSpacing.
----------------------------------------------------------------------

-- The vendored face's own line box, as a multiple of its point size. This is
-- the one number here that is MEASURED rather than declared: a FontString's
-- natural leading is the face's ascent+descent, which no client API reports.
-- 1.2 is the standard TTF metric and the value the mockup's own browser used
-- for `line-height:normal`, so the difference below lands on the mockup's
-- rhythm. It is named and constant so a future correction is one edit.
local FACE_NATURAL_LINE = 1.2

-- The size the feed actually renders at: the config's own value when it has
-- one, the CLIENT's per-window size otherwise (0 and nil both mean "the
-- client's menu decides" — Class 5: a truthy zero must not become a size).
function Skin.MessageFontSize(clientSize)
    local want = tonumber(cfg().messageFontSize)
    if Skin.Unified() and want and want > 0 then return want end
    local size = tonumber(clientSize)
    if not size or size <= 0 then size = 14 end   -- truthy-zero guard (Class 5)
    return size
end

-- PURE. The mockup's rhythm, in the points SetSpacing speaks: the air the
-- line-height asks for beyond the face's own line box, plus the row's own
-- padding. Computed from the size in force, so it tracks the font-size config
-- instead of freezing at whatever it was when this line was written.
function Skin.MessageSpacing(size)
    size = tonumber(size)
    if not size or size <= 0 then return ROW_SPACING end
    local lh = tonumber(cfg().lineHeight)
    if not lh or lh <= 0 then lh = MOCKUP_LINE_HEIGHT end
    local extra = (lh - FACE_NATURAL_LINE) * size
    if extra < 0 then extra = 0 end
    return extra + ROW_SPACING
end

local function applyFrameFont(frame, id)
    local UI = UIKit()
    if not UI or type(frame.SetFont) ~= "function" then return end
    local rec = Skin.styled[frame]
    -- Save the original face once, so disable can hand it back.
    if rec and not rec.origFont and type(frame.GetFont) == "function" then
        local okg, face, size, flags = pcall(frame.GetFont, frame)
        if okg and face then rec.origFont = { face, size, flags } end
    end
    local _, name, fontSize = windowEligible(id)
    local size = Skin.MessageFontSize(fontSize)
    pcall(frame.SetFont, frame, UI.FontFile(), size, "")
    -- THE ROW RHYTHM. SetSpacing is the ONE typographic lever a
    -- ScrollingMessageFrame offers, and the value is computed from the size in
    -- force (see Skin.MessageSpacing); the original is saved so a disable
    -- hands it back.
    if type(frame.SetSpacing) == "function" then
        if rec and rec.origSpacing == nil and type(frame.GetSpacing) == "function" then
            local okS, sp = pcall(frame.GetSpacing, frame)
            rec.origSpacing = (okS and tonumber(sp)) or false
        end
        pcall(frame.SetSpacing, frame,
            Skin.Unified() and Skin.MessageSpacing(size)
                            or (rec and tonumber(rec.origSpacing) or 0))
    end
end

----------------------------------------------------------------------
-- Fading. Config-driven; both knobs live in db.skin.
----------------------------------------------------------------------

-- Is text fading actually in force? Inside the ONE BOX it never is: the design
-- the owner approved has no fading at all, and a box that is always there with
-- text that comes and goes is exactly the half state that rule exists to
-- refuse. The stored knob is NOT rewritten — turning the box off gives the
-- player's own setting straight back — the settings page just says out loud
-- that it is inert meanwhile.
function Skin.FadingEffective()
    if Skin.Unified() then return false end
    return cfg().fading and true or false
end

function Skin.ApplyFading(frame)
    local c = cfg()
    local on = Skin.FadingEffective()
    if type(frame.SetFading) == "function" then
        pcall(frame.SetFading, frame, on)
    end
    if on and type(frame.SetTimeVisible) == "function" then
        pcall(frame.SetTimeVisible, frame, tonumber(c.fadeTime) or 100)
    end
end

----------------------------------------------------------------------
-- Stock texture strip / restore. The client lists every chat-frame dress
-- texture suffix in the CHAT_FRAME_TEXTURES global; regions live at
-- _G[frameName .. suffix]. We alpha them to 0 (restorable) rather than nil
-- their textures (not restorable).
----------------------------------------------------------------------

local FALLBACK_TEXTURES = {
    "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture",
    "BottomRightTexture", "LeftTexture", "RightTexture", "TopTexture",
    "BottomTexture",
}

local function stockTextureNames()
    local t = _G.CHAT_FRAME_TEXTURES
    if type(t) == "table" and #t > 0 then return t end
    return FALLBACK_TEXTURES
end

local function stripStock(frame, rec)
    local name = frame.GetName and frame:GetName()
    if not name then return end
    rec.stock = rec.stock or {}
    for _, suffix in ipairs(stockTextureNames()) do
        local region = _G[name .. suffix]
        if region and type(region.SetAlpha) == "function" then
            if rec.stock[suffix] == nil then
                local okA, a = pcall(region.GetAlpha, region)
                rec.stock[suffix] = okA and a or 1
            end
            pcall(region.SetAlpha, region, 0)
        end
    end
end

local function restoreStock(frame, rec)
    local name = frame.GetName and frame:GetName()
    if not name or not rec.stock then return end
    for suffix, alpha in pairs(rec.stock) do
        local region = _G[name .. suffix]
        if region and type(region.SetAlpha) == "function" then
            pcall(region.SetAlpha, region, alpha)
        end
    end
end

----------------------------------------------------------------------
-- Backdrop: one flat token-colored panel behind each window (Core's
-- FLAT_BACKDROP shape; UI.Skin keeps it re-coloring on every theme change).
--
-- SKIN V3: this same frame becomes THE CHASSIS. In the unified box it no
-- longer hugs the message area — it grows out over the tab strip (or rail) and
-- the entry bar, so one backdrop is the whole box. There is never a second
-- one: a docked window that is not its group's host hides its own, and the
-- entry bar's panel goes away too (see styleEditBox).
----------------------------------------------------------------------

-- The extra each side of the client's message area the box takes, in the
-- window's own units. PURE-ish (it reads config only) so the geometry the
-- suite pins is the geometry the renderer uses. Returns left, right, top,
-- bottom.
--
-- THE MESSAGE PADDING LIVES HERE, and it has to: the client's message frame is
-- a ScrollingMessageFrame, which has NO text insets (SetTextInsets is an
-- EditBox/SimpleHTML verb — catalog-checked on 11509; the message frame offers
-- SetSpacing for the row rhythm and nothing for the margins). So the mockup's
-- `.msgs{padding:10px 14px 6px}` is expressed as the CHASSIS growing that far
-- PAST the frame on each side, which lands the same pixels: text at 14 from the
-- box's left edge, 10 below the strip, 6 above the entry seam.
function Skin.ChassisInsets()
    if not Skin.Unified() then return PAD, PAD, PAD, PAD end
    local l, r = MSG_PAD_X, MSG_PAD_X
    local t, b = MSG_PAD_TOP, MSG_PAD_BOT
    local placement = Skin.TabPlacement()
    if placement == "left" then l = l + TABRAIL_W
    elseif placement == "right" then r = r + TABRAIL_W
    else t = t + STRIP_H end
    -- The entry bar is part of the box, on whichever edge it is configured to,
    -- flush against the message area with the hairline as the only separation.
    if (cfg().editBox or "BOTTOM"):upper() == "TOP" then
        t = t + SEAM_W + EB_HEIGHT
    else
        b = b + SEAM_W + EB_HEIGHT
    end
    return l, r, t, b
end

local function anchorChassis(bd, frame)
    if type(bd.ClearAllPoints) ~= "function" then return end
    local l, r, t, b = Skin.ChassisInsets()
    pcall(bd.ClearAllPoints, bd)
    bd:SetPoint("TOPLEFT", frame, "TOPLEFT", -l, t)
    bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", r, -b)
end

-- THE CHASSIS' OWN INK. In the box it is the mockup's `.chatbox`: a SOLID
-- --panel fill (v3 shipped it at 0.85 over the world, which is exactly why the
-- owner's screenshot reads pure black) inside a 1px --line border. With the box
-- off it is skin v2's token treatment, untouched.
local function paintChassis(bd)
    local UI = UIKit()
    if not (UI and bd) then return end
    if Skin.Unified() then
        if type(bd.SetBackdrop) == "function" then bd:SetBackdrop(UI.FLAT_BACKDROP) end
        if type(bd.SetBackdropColor) == "function" then bd:SetBackdropColor(Skin.Ink("panel")) end
        if type(bd.SetBackdropBorderColor) == "function" then
            bd:SetBackdropBorderColor(Skin.Ink("line"))
        end
        return
    end
    if type(bd.SetBackdrop) == "function" then bd:SetBackdrop(UI.FLAT_BACKDROP) end
    if type(bd.SetBackdropColor) == "function" then bd:SetBackdropColor(UI.Color("panel", BG_ALPHA)) end
    if type(bd.SetBackdropBorderColor) == "function" then
        bd:SetBackdropBorderColor(UI.Color("border"))
    end
end

local function ensureBackdrop(frame, rec)
    local UI = UIKit()
    if not UI then return end
    if rec.backdrop then
        rec.backdrop:Show()
        paintChassis(rec.backdrop)
        anchorChassis(rec.backdrop, frame)
        return
    end
    local bd = _G.CreateFrame("Frame", nil, frame, "BackdropTemplate")
    if bd.SetFrameLevel and frame.GetFrameLevel then
        local okL, lvl = pcall(frame.GetFrameLevel, frame)
        pcall(bd.SetFrameLevel, bd, math.max(0, (okL and lvl or 1) - 1))
    end
    UI.Skin(bd, paintChassis)
    rec.backdrop = bd
    anchorChassis(bd, frame)
end

----------------------------------------------------------------------
-- THE MESSAGE SURFACE (the mockup's --panel2 step).
--
-- The mockup is unambiguous about this and skin v3 read it the other way: the
-- strip sits on the chassis tone (--panel) and EVERYTHING BELOW IT — the
-- message area and the entry bar — sits on a second, lighter tone (--panel2).
-- The active tab is painted in that SAME tone and run down to the strip's
-- bottom edge, and THAT is the "fused" look. v3 expressed the fusion with a
-- broken hairline instead, which left the active tab wearing the client's own
-- tab art (the filled red block in the owner's screenshot) and the whole box on
-- one flat tone.
--
-- It is not a "second background inside the box" in the sense the v3 design
-- contract forbade: it is the same single chassis frame carrying one fill
-- texture over the region the mockup fills. Nothing here is a second BACKDROP,
-- nothing has a border, and there is still exactly one chassis per group.
----------------------------------------------------------------------

local function ensureSurface(rec)
    if rec.surface then return rec.surface end
    local bd = rec.backdrop
    if not (bd and type(bd.CreateTexture) == "function") then return nil end
    local tex = bd:CreateTexture(nil, "BACKGROUND")
    -- Above the backdrop's own centre fill, still behind every frame in the box.
    if type(tex.SetDrawLayer) == "function" then pcall(tex.SetDrawLayer, tex, "BACKGROUND", 1) end
    tex:Hide()
    rec.surface = tex
    return tex
end

local function layoutSurface(rec)
    local tex = ensureSurface(rec)
    local bd = rec.backdrop
    if not (tex and bd) then return nil end
    if not Skin.Unified() then
        tex:Hide()
        return nil
    end
    if type(tex.SetColorTexture) == "function" then tex:SetColorTexture(Skin.Ink("panel2")) end
    local placement = Skin.TabPlacement()
    tex:ClearAllPoints()
    -- Inside the chassis' own 1px border, and clear of whichever band the tab
    -- strip/rail occupies — the strip keeps the chassis tone.
    local l, r, t, b = CHASSIS_EDGE, -CHASSIS_EDGE, -CHASSIS_EDGE, CHASSIS_EDGE
    if placement == "left" then l = TABRAIL_W
    elseif placement == "right" then r = -TABRAIL_W
    else t = -STRIP_H end
    tex:SetPoint("TOPLEFT", bd, "TOPLEFT", l, t)
    tex:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", r, b)
    tex:Show()
    return tex
end

----------------------------------------------------------------------
-- Tabs. The Blizzard tab stays the click surface (skin-over, never replace);
-- we restyle its text through the Core small font role, ink it from the
-- window's dominant channel (skin v2 feature 1), underline the active tab in
-- the suite accent, and dim the unselected docked tabs — selection tracked via
-- the FCF_SelectDockFrame hook below.
--
-- BADGE COORDINATION (badges.lua owns the unread counter): the counter is its
-- own FontString on its own holder, anchored OFF the tab's right edge. Every
-- surface added here is INSIDE the tab — the ink is the tab's own text, the
-- underline is inset from both tab edges — so the badge's anchor and ink are
-- untouched no matter what color the tab takes. The skin suite pins that.
----------------------------------------------------------------------

local function tabText(frame)
    local name = frame.GetName and frame:GetName()
    if not name then return nil, nil end
    local tab = _G[name .. "Tab"]
    if not tab then return nil, nil end
    return tab, (tab.Text or _G[name .. "TabText"])
end

local function selectedDockFrame()
    local dock = _G.GeneralDockManager
    return dock and dock.selected or nil
end

local function ensureUnderline(tab, rec)
    if rec.underline then return rec.underline end
    local UI = UIKit()
    if not (UI and type(tab.CreateTexture) == "function") then return nil end
    local tex = tab:CreateTexture(nil, "OVERLAY")
    -- Inset from BOTH tab edges (the mockup's ::after left/right 6px), and the
    -- pip now lives INSIDE the tab, so the inset is also what keeps the line
    -- off it.
    tex:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", UL_INSET, UL_Y)
    tex:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -UL_INSET, UL_Y)
    if type(tex.SetHeight) == "function" then tex:SetHeight(UL_HEIGHT) end
    UI.Skin(tex, function(self)
        if type(self.SetColorTexture) ~= "function" then return end
        -- The underline wears the TAB's own colour (the mockup's --tabc), with
        -- the accent as its own fallback.
        local mc = rec.markColor
        if mc then self:SetColorTexture(mc[1], mc[2], mc[3])
        else self:SetColorTexture(Skin.Ink("accent")) end
    end)
    tex:Hide()
    rec.underline = tex
    return tex
end

----------------------------------------------------------------------
-- THE TAB'S OWN SURFACES (delta 1, the biggest miss).
--
-- The mockup's tab has NO fill of its own when it is inactive, and when it is
-- active its fill IS the message surface's (--panel2) so the two read as one
-- piece. skin v3 stripped the message frame's stock art but never the TAB's,
-- so every tab kept wearing the client's own chat-tab textures — which is the
-- filled block in the owner's screenshot, not anything this file painted.
--
-- Three surfaces, all reversible:
--   * the CLIENT's tab textures are alpha'd to 0 and remembered (the same
--     restorable treatment stripStock gives the message frame);
--   * `tabFill` is the active tab's --panel2, run PAST the tab's bottom edge to
--     the strip's, so no seam survives between tab and messages;
--   * `tabHover` is the mockup's rgba(255,255,255,.04) wash, shown only while
--     the pointer is on an INACTIVE tab.
----------------------------------------------------------------------

-- The client's per-tab dress. Era's chat tab is a three-slice button with a
-- selected set and a highlight; the names are $parentTab<suffix>, and the
-- template also hangs some of them on the button itself.
local TAB_TEXTURES = {
    "Left", "Middle", "Right",
    "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight",
    "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "Glow",
}

local function stripTabArt(frame, tab, rec)
    if not Skin.Unified() then return end
    local base = tab.GetName and tab:GetName()
    rec.tabStock = rec.tabStock or {}
    for _, suffix in ipairs(TAB_TEXTURES) do
        local region = (base and _G[base .. suffix]) or tab[suffix:sub(1, 1):lower() .. suffix:sub(2)]
        if region and type(region.SetAlpha) == "function" then
            if rec.tabStock[suffix] == nil then
                local okA, a = pcall(region.GetAlpha, region)
                rec.tabStock[suffix] = okA and a or 1
            end
            pcall(region.SetAlpha, region, 0)
        end
    end
end

local function restoreTabArt(tab, rec)
    if not (tab and rec.tabStock) then return end
    local base = tab.GetName and tab:GetName()
    for suffix, alpha in pairs(rec.tabStock) do
        local region = (base and _G[base .. suffix]) or tab[suffix:sub(1, 1):lower() .. suffix:sub(2)]
        if region and type(region.SetAlpha) == "function" then
            pcall(region.SetAlpha, region, alpha)
        end
    end
    rec.tabStock = nil
end

local function ensureTabFill(tab, rec)
    if rec.tabFill then return rec.tabFill end
    if type(tab.CreateTexture) ~= "function" then return nil end
    local tex = tab:CreateTexture(nil, "BACKGROUND")
    tex:Hide()
    rec.tabFill = tex
    return tex
end

local function ensureTabHover(tab, rec)
    if rec.tabHover then return rec.tabHover end
    if type(tab.CreateTexture) ~= "function" then return nil end
    local tex = tab:CreateTexture(nil, "BACKGROUND")
    if type(tex.SetDrawLayer) == "function" then pcall(tex.SetDrawLayer, tex, "BACKGROUND", 1) end
    tex:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
    tex:Hide()
    rec.tabHover = tex
    -- The hover state is the client's own pointer, watched additively.
    if type(tab.HookScript) == "function" and not rec.tabHoverRig then
        rec.tabHoverRig = true
        tab:HookScript("OnEnter", function() rec.hovered = true; Skin.UpdateTabWash(rec) end)
        tab:HookScript("OnLeave", function() rec.hovered = false; Skin.UpdateTabWash(rec) end)
    end
    return tex
end

-- The wash is the ONE thing that moves without a re-layout, so it gets its own
-- cheap beat (the hover scripts call it directly).
function Skin.UpdateTabWash(rec)
    local tex = rec and rec.tabHover
    if not tex then return end
    if Skin.active and Skin.Unified() and rec.hovered and not rec.tabActive then
        if type(tex.SetColorTexture) == "function" then
            tex:SetColorTexture(Skin.Ink("text", HOVER_WASH))
        end
        tex:Show()
    else
        tex:Hide()
    end
end

-- Paint (or put away) one tab's fill + wash. `isSel` decides which.
local function updateTabSurfaces(rec, tab, isSel)
    rec.tabActive = isSel and true or false
    if not Skin.Unified() then
        if rec.tabFill then rec.tabFill:Hide() end
        if rec.tabHover then rec.tabHover:Hide() end
        restoreTabArt(tab, rec)     -- the box went off: the client's tab is back
        return
    end
    local fill = ensureTabFill(tab, rec)
    ensureTabHover(tab, rec)
    if fill then
        if type(fill.SetColorTexture) == "function" then fill:SetColorTexture(Skin.Ink("panel2")) end
        fill:ClearAllPoints()
        -- THE FUSION, literally: the active tab wears the message surface's own
        -- fill over its whole rect, and the strip's bottom padding is zero (the
        -- mockup's `.tabs-top{padding:6px 8px 0}`), so the tab's bottom edge IS
        -- the message surface's top edge and the two are one --panel2 field
        -- with nothing drawn between them.
        fill:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        if isSel then fill:Show() else fill:Hide() end
    end
    Skin.UpdateTabWash(rec)
end

----------------------------------------------------------------------
-- CHANNEL ALIASES, SURFACE 3 OF 3: the tab label.
--
-- A window whose routing collapses to exactly ONE channel identity (the same
-- strict dominance rule the tab INK already uses — see DominantChannel) wears
-- that channel's alias as its label. Same seam, same answer: if the chat line
-- says "[Trade]" and the edit box says "Trade:", the tab says "Trade".
--
-- Reversible by construction: the client's own label is remembered on the
-- first override, and the moment the alias goes away (or the module does) the
-- remembered text is put back — never a blanket re-write of a name the player
-- or the reconciler owns.
----------------------------------------------------------------------

function Skin.TabLabel(frame, id)
    local C = ns.Config
    if not (C and C.AliasLabel) then return nil end
    if isCombatLog(frame, id) then return nil end
    if frame and frame.isTemporary then return nil end
    local entry = Skin.WindowRouting(id)
    local kind, value = Skin.DominantChannel(entry, false)
    if kind ~= "channel" then return nil end
    local num
    local Ch = ns.Channels
    if Ch and Ch.NumberOf then num = Ch.NumberOf(value) end
    return C.AliasLabel(num, value)
end

-- Apply (or take back) one tab's alias label. Returns the label in force, or
-- nil when the tab is showing the client's own text.
function Skin.ApplyTabLabel(frame, rec, text)
    if not (rec and text and type(text.SetText) == "function") then return nil end
    local label = Skin.TabLabel(frame, rec.id)
    if label then
        if rec.origTabText == nil and type(text.GetText) == "function" then
            local ok, was = pcall(text.GetText, text)
            rec.origTabText = (ok and type(was) == "string") and was or false
        end
        if rec.tabLabel ~= label then
            pcall(text.SetText, text, label)
            rec.tabLabel = label
        end
        return label
    end
    if rec.tabLabel ~= nil then
        -- The alias went away: hand the client's own label back.
        if type(rec.origTabText) == "string" then pcall(text.SetText, text, rec.origTabText) end
        rec.tabLabel = nil
        rec.origTabText = nil
    end
    return nil
end

function Skin.UpdateTabColors()
    local UI = UIKit()
    if not UI then return end
    local sel = selectedDockFrame()
    local dim = Skin.DimFactor()
    local unified = Skin.Unified()
    for _, frame in ipairs(Skin.order) do
        local tab, text = tabText(frame)
        local rec = Skin.styled[frame]
        if tab and text then
            Skin.ApplyTabLabel(frame, rec, text)
            local isSel = (frame == sel)
            -- The chain lives in TabInk (explicit > derived); the channelTabs
            -- gate is inside it, because an EXPLICIT colour outranks that gate.
            local r, g, b, source = Skin.TabInk(frame, rec and rec.id)
            local mr, mg, mb            -- the MARK colour: always full strength
            if r then
                mr, mg, mb = r, g, b
                -- Active: full strength. Inactive: the SAME ink, dimmed through
                -- the token-derived factor (never a second color).
                if not isSel then r, g, b = r * dim, g * dim, b * dim end
            elseif unified then
                -- The mockup's own fallback: `--tabc` unset means the tab wears
                -- --text when active and --muted when not.
                r, g, b = Skin.Ink(isSel and "text" or "muted")
                mr, mg, mb = Skin.Ink("accent")
                source = "palette"
            else
                r, g, b = UI.Color(isSel and "accent" or "muted")
                mr, mg, mb = UI.Color("accent")
                source = "token"
            end
            if rec then
                rec.inkSource = source
                rec.markColor = { mr, mg, mb }
            end
            if type(text.SetTextColor) == "function" then
                text:SetTextColor(r, g, b)
            end
            if type(tab.SetAlpha) == "function" then
                -- In the box the DIM lives in the ink (the mockup dims the
                -- channel colour, not the whole button — dimming the button
                -- would take the pip and the underline down with it).
                tab:SetAlpha((unified or isSel) and 1 or TAB_DIM)
            end
            updateTabSurfaces(rec, tab, isSel)
            Skin.UpdateTabMarks(frame, rec, tab, isSel)
        end
    end
end

local function styleTab(frame, rec)
    local UI = UIKit()
    if not UI then return end
    local tab, text = tabText(frame)
    if not (tab and text) then return end
    if type(text.SetFontObject) == "function" then
        text:SetFontObject(UI.fonts.small)
    end
    -- In the box the tab label is the mockup's own 12.5px on the suite face
    -- (the Core role only carries the face; the SIZE is the mockup contract's).
    if Skin.Unified() and type(text.SetFont) == "function" then
        pcall(text.SetFont, text, UI.FontFile(), TAB_TEXT_SIZE, "")
    end
    -- The client's own tab art comes down in the box (delta 1: it is the filled
    -- block, and the mockup's tab has no fill of its own).
    stripTabArt(frame, tab, rec)
    -- Save the tab's original ink once so a disable can hand it back (the
    -- client does not always expose GetTextColor; when it does not, the tab
    -- simply keeps the last ink, which is Wave 1's behavior).
    if not rec.origTabColor and type(text.GetTextColor) == "function" then
        local ok, r, g, b = pcall(text.GetTextColor, text)
        if ok and type(r) == "number" then rec.origTabColor = { r, g, b } end
    end
    rec.tabStyled = true
end

----------------------------------------------------------------------
-- THE BOX NEVER FADES — INCLUDING ITS TABS (skin v3.1, the owner's "the tabs
-- still fade when not focused on").
--
-- WHAT WAS MISSED: SetFading governs MESSAGE fading — how long a line stays
-- readable — and turning it off in the box was correct and complete for the
-- messages. The TAB is a separate machine. On 11509 the chat tab carries two
-- alpha fields of its OWN, `noMouseAlpha` and `mouseOverAlpha`, and the client
-- picks between them in FCFTab_UpdateAlpha (catalog-verified, as are
-- FCF_FadeInChatFrame / FCF_FadeOutChatFrame / UIFrameFadeRemoveFrame). The
-- fade-out verb rewrites `noMouseAlpha` downward and drops the chat FRAME's own
-- alpha with it. Nothing in skin v3 ever touched either, so the client went on
-- fading the restyled tabs — the near-invisible strip in the owner's screenshot
-- is the client's alpha, not our ink.
--
-- THE FIX, in the file's established last-word posture and in this order:
--   1. NEUTRALISE THE SOURCE. The client's own updater computes from the tab's
--      two alpha fields, so both are set to 1 — recorded first, restored on
--      disable. With the inputs at 1 the client's own answer IS 1 and there is
--      nothing left to fight about on the common path.
--   2. CANCEL AN IN-FLIGHT FADE. A fade already running writes alpha on its own
--      driver, behind any single pin, so UIFrameFadeRemoveFrame is asked to
--      stop it (runtime-detected; a client without it simply relies on 1 and 3).
--   3. HOLD THE LAST WORD. Post-hooks on the three client verbs re-pin alpha
--      synchronously, in-call — and a pin COSTS A CLIENT CALL ONLY WHEN THE
--      CLIENT ACTUALLY MOVED IT (the alpha is read first and left alone when it
--      is already where we want it), so there is no fight loop, only a correction.
--      Latched per Class 9: our own SetAlpha can never re-enter the pin.
--
-- THE SWEEP (what else could fade the box, and why it does not):
--   * the CHASSIS, STRIP, SEAMS and ENTRY BAR are all children of the chat
--     frame, so the frame's own pinned alpha covers them — the client has no
--     handle on them directly;
--   * the EDIT BOX's idle dimming (EB_IDLE) is OURS, deliberate, and is
--     therefore NOT pinned — likewise the rail's and the copy button's idle
--     alphas. Only the client's fade is refused;
--   * the tab's INK dimming for an inactive tab is OURS too (the fidelity pass
--     put the dim in the colour, never in the button's alpha) and is untouched;
--   * SetChatWindowAlpha / FCF_SetWindowAlpha drive the stock BACKGROUND
--     texture, which the box already alpha-zeroes and replaces;
--   * FCF_FadeOutScrollbar only reaches the client's scrollbar, which the box
--     does not use.
-- OFF (skin v2 / the box disabled) NOTHING here runs and the client owns the
-- tab's alpha exactly as it always did.
----------------------------------------------------------------------

-- Two alphas are "the same alpha" this close. Wider than float noise, narrower
-- than any fade step the client takes.
local PIN_EPSILON = 0.004

function Skin.NoAlphaFade()
    return (Skin.active and Skin.Unified()) and true or false
end

-- Take one widget's alpha back to `want`. Returns true only when a client call
-- was actually spent — nothing is written when the alpha is already right.
function Skin.PinAlpha(widget, want)
    if type(widget) ~= "table" or type(widget.SetAlpha) ~= "function" then return false end
    if Skin._alphaDepth > 0 then return false end        -- our own echo (Class 9)
    want = tonumber(want) or 1
    local cur = widgetNum(widget, "GetAlpha")
    if cur ~= nil and math.abs(cur - want) <= PIN_EPSILON then return false end
    Skin._alphaDepth = Skin._alphaDepth + 1
    local ok, err = pcall(widget.SetAlpha, widget, want)
    Skin._alphaDepth = Skin._alphaDepth - 1
    if not ok then
        if ns.RouteError then ns.RouteError(err) end
        return false
    end
    Skin.alphaPins = Skin.alphaPins + 1
    return true
end

-- The client's tab-alpha updater is documented as taking the CHAT FRAME. A
-- client that hands the TAB instead is answered too — the seam is resolved at
-- runtime from what actually arrived, never assumed from the name.
local function alphaSubject(a)
    if type(a) ~= "table" then return nil end
    if Skin.styled[a] then return a end
    if type(a.GetParent) == "function" then
        local ok, p = pcall(a.GetParent, a)
        if ok and type(p) == "table" and Skin.styled[p] then return p end
    end
    return nil
end

-- One window's opacity, brought in line with the box. Returns the number of
-- client calls actually spent (0 on a beat where nothing had moved).
function Skin.KeepOpaque(frame, rec)
    if not Skin.NoAlphaFade() then return 0 end
    rec = rec or Skin.styled[frame]
    if not rec then return 0 end
    local tab = select(1, tabText(frame))
    -- Step 2: stop a fade that is already running before pinning anything.
    local rm = _G.UIFrameFadeRemoveFrame
    if type(rm) == "function" then
        pcall(rm, frame)
        if tab then pcall(rm, tab) end
    end
    local n = 0
    if Skin.PinAlpha(frame, 1) then n = n + 1 end
    if tab then
        -- Step 1: the client's own inputs, remembered once so a disable hands
        -- back exactly what was there (nil included — an absent field is a
        -- real state and must be restored as absent, never as a made-up 1).
        if rec.tabAlphaStock == nil then
            rec.tabAlphaStock = { noMouse = tab.noMouseAlpha,
                                  mouseOver = tab.mouseOverAlpha,
                                  had = true }
        end
        tab.noMouseAlpha, tab.mouseOverAlpha = 1, 1
        if Skin.PinAlpha(tab, 1) then n = n + 1 end
    end
    return n
end

function Skin.KeepAllOpaque()
    if not Skin.NoAlphaFade() then return 0 end
    local n = 0
    for _, frame in ipairs(Skin.order) do
        n = n + Skin.KeepOpaque(frame, Skin.styled[frame])
    end
    return n
end

-- Give the alpha decision back: the box went off, or the module did. The
-- CLIENT's own updater is re-run rather than a remembered number replayed, so
-- the tab returns to what the client wants now, not to a stale snapshot.
function Skin.RestoreOpacity(frame, rec)
    rec = rec or Skin.styled[frame]
    if not (rec and rec.tabAlphaStock) then return false end
    local tab = select(1, tabText(frame))
    if tab then
        tab.noMouseAlpha   = rec.tabAlphaStock.noMouse
        tab.mouseOverAlpha = rec.tabAlphaStock.mouseOver
    end
    rec.tabAlphaStock = nil
    local upd = _G.FCFTab_UpdateAlpha
    if type(upd) == "function" then pcall(upd, frame) end
    return true
end

----------------------------------------------------------------------
-- TIMESTAMP DIVIDER (skin v2 feature 2).
--
-- A theme border-token hairline between the stamp column and the message text,
-- shown ONLY while stamps.lua is actually stamping (module active and not
-- suspended behind the client's native timestamps).
--
-- Coordination with stamps is READ-ONLY and by MEASUREMENT, never by coupling:
-- we read the one CONFIG field that decides how wide a stamp is (db.stamps
-- .format), render its widest literal shape into a probe FontString wearing
-- THIS window's font, and place the hairline past the measured width. Nothing
-- calls into stamps, and stamps knows nothing about this.
----------------------------------------------------------------------

-- The widest literal a format can produce (digits are the same width class as
-- the sample zeros). The BRACKETS are a stamps option now — the mockup's stamp
-- column is bare "17:16" — so the sample is built from the same two pieces
-- stamps writes, and the trailing SEPARATOR is measured separately because the
-- hairline is CENTRED in it (see UpdateDivider).
local STAMP_SAMPLES = {
    ["HH:MM"]    = "00:00",
    ["HH:MM:SS"] = "00:00:00",
    ["hh:MM"]    = "00:00 PM",
    ["hh:MM:SS"] = "00:00:00 PM",
}

-- The separator stamps puts between the stamp and the line. Read through the
-- sibling's PUBLISHED constant, defended like every peer read; the fallback is
-- the one space skin v2 assumed.
local function stampSeparator()
    local S = ns.Stamps
    local sep = type(S) == "table" and S.SEPARATOR or nil
    return (type(sep) == "string" and sep ~= "") and sep or " "
end

-- The stamps config as stamps itself would read it (the live branch first, the
-- module's own published defaults second) — never a second copy of the shape.
local function stampsCfg()
    local live = ns.db and ns.db.stamps
    if type(live) == "table" then return live end
    local S = ns.Stamps
    return (type(S) == "table" and type(S.DEFAULTS) == "table") and S.DEFAULTS or nil
end

function Skin.StampSample()
    local s = stampsCfg()
    local fmt = type(s) == "table" and s.format or nil
    local body = STAMP_SAMPLES[fmt] or STAMP_SAMPLES["HH:MM"]
    if type(s) == "table" and s.brackets then body = "[" .. body .. "]" end
    return body .. stampSeparator()
end

-- The stamp body WITHOUT the separator: the divider is centred in the
-- separator, so the two are measured apart.
function Skin.StampBody()
    local sample, sep = Skin.StampSample(), stampSeparator()
    if sample:sub(-#sep) == sep then return sample:sub(1, #sample - #sep) end
    return sample
end

-- Is a stamp actually being written right now? (Read-only observation of the
-- sibling module's public state — the divider must never appear over
-- unstamped text.)
function Skin.StampsShowing()
    local S = ns.Stamps
    if type(S) ~= "table" then return false end
    return (S.active == true and S.suspended ~= true) and true or false
end

-- Measure one string in THIS window's own font. The probe is a child of the
-- CHAT FRAME (see the parenting note in UpdateDivider) so it can never be
-- carried off by a hidden chassis.
function Skin.MeasureText(frame, rec, text)
    if not (frame and rec) then return 0 end
    local probe = rec.stampProbe
    if not probe then
        if type(frame.CreateFontString) ~= "function" then return 0 end
        probe = frame:CreateFontString(nil, "ARTWORK")
        probe:Hide()
        rec.stampProbe = probe
    end
    -- The window's own font, so the measurement is the window's own metrics.
    if type(frame.GetFont) == "function" and type(probe.SetFont) == "function" then
        local ok, face, size, flags = pcall(frame.GetFont, frame)
        if ok and face then pcall(probe.SetFont, probe, face, size, flags) end
    end
    if type(probe.SetText) == "function" then probe:SetText(text or "") end
    if type(probe.GetStringWidth) ~= "function" then return 0 end
    local ok, w = pcall(probe.GetStringWidth, probe)
    return (ok and tonumber(w)) or 0
end

function Skin.MeasureStampColumn(frame, rec)
    return Skin.MeasureText(frame, rec, Skin.StampSample())
end

----------------------------------------------------------------------
-- WHY THE DIVIDER WAS ABSENT IN THE OWNER'S SCREENSHOT — two real causes, both
-- fixed here, both now pinned:
--
--   1. PARENTING. The hairline (and its measuring probe) were created on
--      rec.backdrop. In the ONE BOX a docked window that is not its group's
--      HOST has its own backdrop HIDDEN — that is the single-chassis rule — so
--      every tab except the dock's primary carried a divider that existed,
--      was "shown", and rendered nothing, because its parent frame was hidden.
--      The divider belongs to the MESSAGE FRAME, which is always shown, and it
--      is created there now.
--   2. THE GATE WAS NEVER RE-ASKED. `stampDivider AND stamps-are-stamping` was
--      evaluated only on skin's own beats (style, selection, theme, recolor,
--      the showTimestamps CVar). Turning the stamps MODULE on mid-session — the
--      settings page's own checkbox — moved the answer and told nobody, so the
--      divider stayed away until something else happened to refresh the skin.
--      Skin.NoteStampsChanged is the bell for that, and OnEnable re-asks once
--      on the next beat so login ORDER cannot decide the answer either.
----------------------------------------------------------------------

function Skin.UpdateDivider(frame)
    local rec = Skin.styled[frame]
    if not rec then return end
    local on = Skin.active and cfg().stampDivider and Skin.StampsShowing()
    if not on then
        if rec.divider then rec.divider:Hide() end
        return
    end
    local UI = UIKit()
    if not UI then return end
    local unified = Skin.Unified()
    local x
    if unified then
        -- THE MOCKUP: `.msgs .row{gap:8px}` puts 8px each side of the 1px
        -- `.stampline`. A chat line is one string in one FontString, so the
        -- room right of the hairline is whatever stamps' separator spells —
        -- the hairline is CENTRED in it, which splits the gap evenly and lands
        -- on 8/8 as closely as the face's space advance allows.
        local body = Skin.MeasureText(frame, rec, Skin.StampBody())
        local sep  = Skin.MeasureText(frame, rec, stampSeparator())
        x = body + math.max(1, (sep - DIV_WIDTH) / 2)
    else
        x = Skin.MeasureStampColumn(frame, rec) + DIV_GAP
    end
    local div = rec.divider
    if not div then
        -- ON THE MESSAGE FRAME, never on the chassis (root cause 1 above).
        if type(frame.CreateTexture) ~= "function" then return end
        div = frame:CreateTexture(nil, "BORDER")
        if type(div.SetWidth) == "function" then div:SetWidth(DIV_WIDTH) end
        UI.Skin(div, function(self)
            if type(self.SetColorTexture) ~= "function" then return end
            if Skin.Unified() then
                self:SetColorTexture(Skin.Ink("lineSoft"))     -- .stampline
            else
                self:SetColorTexture(UI.Color("border", DIV_ALPHA))
            end
        end)
        rec.divider = div
    end
    -- The ink follows the box going on or off, not just a theme change.
    if type(div.SetColorTexture) == "function" then
        if unified then div:SetColorTexture(Skin.Ink("lineSoft"))
        else div:SetColorTexture(UI.Color("border", DIV_ALPHA)) end
    end
    if type(div.ClearAllPoints) == "function" then
        div:ClearAllPoints()
        div:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        div:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 0)
    end
    rec.dividerX = x
    div:Show()
end

function Skin.UpdateDividers()
    for _, frame in ipairs(Skin.order) do Skin.UpdateDivider(frame) end
end

-- THE BELL (root cause 2). stamps.lua rings it from its own OnEnable/OnDisable
-- and carries NO data: the coordination is still read-only and by measurement —
-- skin never asks stamps anything, it is only told that the answer may have
-- moved. A build of stamps that does not ring it is no worse off than today.
function Skin.NoteStampsChanged()
    if not Skin.active then return false end
    Skin.UpdateDividers()
    return true
end

----------------------------------------------------------------------
-- Edit box: the attached panel-bar look (survey archetype). Re-anchored as a
-- bar spanning the window's width, below or above per config; stock art
-- stripped; a flat token backdrop behind it; Core body font.
--
-- SKIN V2 feature 3 lives here too: the sticky-channel HEADER ("Guild:",
-- "2. World:") wears that channel's client color, applied on the client's own
-- ChatEdit_UpdateHeader beat (hooked once, gated) so it follows every sticky
-- change, tab-cycle and /channel switch without us tracking state.
----------------------------------------------------------------------

local EB_REGIONS = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function editBoxOf(frame)
    local name = frame.GetName and frame:GetName()
    return name and _G[name .. "EditBox"] or nil
end

-- The header FontString the client writes the sticky-channel prefix into.
-- Both shapes are defended: the field the client's own code reaches for, and
-- the $parentHeader global the template names it.
local function editBoxHeader(eb)
    if type(eb) ~= "table" then return nil end
    if type(eb.header) == "table" then return eb.header end
    local n = eb.GetName and eb:GetName()
    return (n and _G[n .. "Header"]) or nil
end

-- The edit box's sticky chat state, through the client's accessor first and
-- the attribute bag second (both catalog-verified on 11509).
local function editBoxAttr(eb, accessor, attribute)
    if type(eb) ~= "table" then return nil end
    local f = _G[accessor]
    if type(f) == "function" then
        local ok, v = pcall(f, eb)
        if ok and v ~= nil and v ~= "" then return v end
    end
    if type(eb.GetAttribute) == "function" then
        local ok, v = pcall(eb.GetAttribute, eb, attribute)
        if ok and v ~= nil and v ~= "" then return v end
    end
    local direct = eb[attribute]
    if direct ~= nil and direct ~= "" then return direct end
    return nil
end

local function savePoints(widget)
    if type(widget.GetNumPoints) ~= "function" or type(widget.GetPoint) ~= "function" then return nil end
    local okN, n = pcall(widget.GetNumPoints, widget)
    if not okN or not n then return nil end
    local pts = {}
    for i = 1, n do
        local okP, p, rel, rp, x, y = pcall(widget.GetPoint, widget, i)
        if okP and p then pts[#pts + 1] = { p, rel, rp, x, y } end
    end
    return pts
end

local function restorePoints(widget, pts)
    if not pts or type(widget.ClearAllPoints) ~= "function" then return end
    pcall(widget.ClearAllPoints, widget)
    for _, pt in ipairs(pts) do
        pcall(widget.SetPoint, widget, pt[1], pt[2], pt[3], pt[4], pt[5])
    end
end

local function styleEditBox(frame, rec)
    local UI = UIKit()
    local eb = editBoxOf(frame)
    if not (UI and eb) then return end
    local ebName = eb.GetName and eb:GetName()

    -- Original state saved once for restore-on-disable.
    if not rec.ebPoints then rec.ebPoints = savePoints(eb) end
    rec.ebStock = rec.ebStock or {}
    if ebName then
        for _, suffix in ipairs(EB_REGIONS) do
            local region = _G[ebName .. suffix]
            if region and type(region.SetAlpha) == "function" then
                if rec.ebStock[suffix] == nil then
                    local okA, a = pcall(region.GetAlpha, region)
                    rec.ebStock[suffix] = okA and a or 1
                end
                pcall(region.SetAlpha, region, 0)
            end
        end
    end

    -- Attach as a bar: full window width, below (default) or above. In the box
    -- the bar spans the chassis' inner width (the mockup's entry runs the whole
    -- box) and sits flush against the message area's own bottom padding, with
    -- the hairline as the only thing between them.
    local unified = Skin.Unified()
    -- …out to the chassis' INNER edge (past the message padding, inside the
    -- 1px border), so the bar's own 12-unit text inset lands the prefix exactly
    -- where the mockup's `.entry{padding:8px 12px}` puts it.
    local sideOut = unified and (MSG_PAD_X - CHASSIS_EDGE) or PAD
    local onTop   = (cfg().editBox or "BOTTOM"):upper() == "TOP"
    local away    = unified and ((onTop and MSG_PAD_TOP or MSG_PAD_BOT) + SEAM_W)
                             or (EB_GAP + PAD)
    local barH    = unified and EB_HEIGHT or 24
    if type(eb.ClearAllPoints) == "function" then
        pcall(eb.ClearAllPoints, eb)
        if onTop then
            pcall(eb.SetPoint, eb, "BOTTOMLEFT", frame, "TOPLEFT", -sideOut, away)
            pcall(eb.SetPoint, eb, "BOTTOMRIGHT", frame, "TOPRIGHT", sideOut, away)
        else
            pcall(eb.SetPoint, eb, "TOPLEFT", frame, "BOTTOMLEFT", -sideOut, -away)
            pcall(eb.SetPoint, eb, "TOPRIGHT", frame, "BOTTOMRIGHT", sideOut, -away)
        end
    end
    if type(eb.SetHeight) == "function" then pcall(eb.SetHeight, eb, barH) end

    -- Flat themed panel behind the input (control-surface tokens: this is an
    -- input, so it steps up from the window's panel ground).
    --
    -- SKIN V3: inside the ONE BOX there is no such panel. The entry bar shares
    -- the chassis' surface and is separated from the message text by a HAIRLINE
    -- and nothing else — a second background here is the exact thing the
    -- approved design forbids. An existing panel is put away, not destroyed, so
    -- turning the box off brings it straight back.
    if unified then
        if rec.ebSkin then rec.ebSkin:Hide() end
        if type(eb.SetFontObject) == "function" then
            pcall(eb.SetFontObject, eb, UI.fonts.body)
        end
        -- The mockup's `.entry{padding:8px 12px}`, literally.
        if type(eb.SetTextInsets) == "function" then
            pcall(eb.SetTextInsets, eb, EB_PAD_X, EB_PAD_X, EB_PAD_Y, EB_PAD_Y)
        end
        local hdr = rec.ebHeader or editBoxHeader(eb)
        rec.ebHeader = hdr
        if hdr and type(hdr.SetFontObject) == "function" then
            pcall(hdr.SetFontObject, hdr, UI.fonts.small)
        end
        return
    end
    if not rec.ebSkin then
        local bg = _G.CreateFrame("Frame", nil, eb, "BackdropTemplate")
        bg:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 0)
        if bg.SetFrameLevel and eb.GetFrameLevel then
            local okL, lvl = pcall(eb.GetFrameLevel, eb)
            pcall(bg.SetFrameLevel, bg, math.max(0, (okL and lvl or 1) - 1))
        end
        UI.Skin(bg, function(self)
            if type(self.SetBackdrop) == "function" then self:SetBackdrop(UI.FLAT_BACKDROP) end
            if type(self.SetBackdropColor) == "function" then
                self:SetBackdropColor(UI.Color("inset"))
            end
            if type(self.SetBackdropBorderColor) == "function" then
                self:SetBackdropBorderColor(UI.Color("controlBorder"))
            end
        end)
        rec.ebSkin = bg
    else
        rec.ebSkin:Show()
    end

    if type(eb.SetFontObject) == "function" then
        pcall(eb.SetFontObject, eb, UI.fonts.body)
    end
    if type(eb.SetTextInsets) == "function" then
        pcall(eb.SetTextInsets, eb, 8, 8, 0, 0)
    end

    -- The sticky-channel prefix belongs to the bar's typography too.
    local header = rec.ebHeader
    if not header then
        header = editBoxHeader(eb)
        rec.ebHeader = header
    end
    if header and type(header.SetFontObject) == "function" then
        pcall(header.SetFontObject, header, UI.fonts.small)
    end
end

-- Ink the sticky-channel header. Returns r, g, b when it painted (the harness
-- reads the return; the client ignores it).
function Skin.ColorEditBoxHeader(eb)
    if not Skin.active or not cfg().editBoxChannelColor then return nil end
    local header = editBoxHeader(eb)
    if not header or type(header.SetTextColor) ~= "function" then return nil end
    local chatType = editBoxAttr(eb, "ChatEdit_GetActiveChatType", "chatType")
    if type(chatType) ~= "string" or chatType == "" then return nil end
    chatType = chatType:upper()
    local r, g, b
    if chatType == "CHANNEL" then
        local target = editBoxAttr(eb, "ChatEdit_GetChannelTarget", "channelTarget")
        r, g, b = Skin.ChannelColorOf(target)
    else
        r, g, b = Skin.TypeColor(GROUP_FAMILY[chatType] or chatType)
    end
    if not r then return nil end
    header:SetTextColor(r, g, b)
    return r, g, b
end

----------------------------------------------------------------------
-- CHANNEL ALIASES, SURFACE 2 OF 3: the sticky prefix on the edit box.
--
-- One alias source (Config.AliasLabel — the same call the chat-line link
-- decorator and the tab label make), three surfaces. Nothing here knows how an
-- alias is spelled, whether the number is kept, or where aliases are stored;
-- it asks the seam and renders the answer.
--
-- SHAPE DISCIPLINE: each surface keeps the CLIENT's own shape and swaps only
-- the label inside it. The chat line's header is bracketed ("[2. Trade - City]"
-- -> "[Trade]"), and the edit box's prefix is not ("2. Trade - City:" ->
-- "Trade:"). Adding brackets here would invent a shape the client never used.
--
-- Runs at the client's own header beat (the ChatEdit_UpdateHeader post-hook),
-- so a sticky change, a tab-cycle or a /channel switch re-derives it for free
-- and an un-aliased channel is simply left with the text the client just wrote.
----------------------------------------------------------------------

-- The (number, name) pair for whatever the edit box is sticky-targeting. The
-- client hands a NUMBER; the name is resolved through GetChannelName, the same
-- by-name discipline the color path uses. Either half may be UNKNOWN (nil).
function Skin.EditBoxChannelTarget(eb)
    local target = editBoxAttr(eb, "ChatEdit_GetChannelTarget", "channelTarget")
    if target == nil or target == "" then return nil, nil end
    local f = _G.GetChannelName
    if type(f) == "function" then
        local ok, num, name = pcall(f, target)
        if ok and type(name) == "string" and name ~= "" then
            return tonumber(num) or tonumber(target), name
        end
    end
    -- No resolver (or an un-joined target): a string target IS the name.
    if type(target) == "string" and not tonumber(target) then return nil, target end
    return tonumber(target), nil
end

-- Rewrite the prefix to the alias when there is one. Returns the label it
-- wrote, or nil when it wrote nothing (which is the untouched-client case).
function Skin.AliasEditBoxHeader(eb)
    if not Skin.active then return nil end
    local header = editBoxHeader(eb)
    if not header or type(header.SetText) ~= "function" then return nil end
    local chatType = editBoxAttr(eb, "ChatEdit_GetActiveChatType", "chatType")
    if type(chatType) ~= "string" or chatType:upper() ~= "CHANNEL" then return nil end
    local C = ns.Config
    if not (C and C.AliasLabel) then return nil end
    local num, name = Skin.EditBoxChannelTarget(eb)
    if not name then return nil end
    local label = C.AliasLabel(num, name)
    if not label then return nil end
    header:SetText(label .. ":")
    return label
end

function Skin.RecolorEditBoxHeaders()
    for _, frame in ipairs(Skin.order) do
        local eb = editBoxOf(frame)
        if eb then
            Skin.ColorEditBoxHeader(eb)
            Skin.AliasEditBoxHeader(eb)
        end
    end
end

----------------------------------------------------------------------
-- THE PERSISTENT EDIT BOX (skin v2.1, default ON).
--
-- WHAT THE CLIENT DOES, and therefore what the honest seam is: the client owns
-- the box's visibility and HIDES it on every deactivate — pressing Escape,
-- sending a line, clicking away. (The client's own persistent-box mode is the
-- `chatStyle='im'` CVar, but two of the three surveyed skin-over addons force
-- 'classic' precisely because an attached, re-anchored bar assumes it, and
-- forcing a CVar to buy a look would silently rewrite a player setting we do
-- not own. So we do not touch chatStyle.)
--
-- The seam we take instead is the last word rather than a fight:
--   1. a POST-hook on ChatEdit_DeactivateChat — the client makes its hide
--      decision, then we re-show. Post-hooks run synchronously inside the
--      client's call (the Class 9 posture), so there is no window where the
--      box is visibly gone;
--   2. an OnHide WATCH on the box itself, deferred one beat — because a hide
--      can arrive from a path the function hook never sees (Class 2: watch the
--      OBJECT, not only the event). The defer keeps us out of a Show-inside-
--      OnHide re-entry, and a depth latch makes the whole thing safe to nest.
-- The box keeps the client's own sticky prefix ("Say:", "Guild:") — we re-run
-- the client's ChatEdit_UpdateHeader rather than writing text ourselves, so the
-- prefix is always the client's truth and skin v2's channel ink lands on it
-- through the existing hook.
--
-- NOT TOUCHED, deliberately: the send path. We never hook OnEnterPressed,
-- never call SendChatMessage, never wrap ChatEdit_SendText. Show/Hide/SetAlpha
-- on an insecure frame taints nothing.
----------------------------------------------------------------------

function Skin.EditBoxPersistent()
    return (Skin.active and cfg().persistentEditBox) and true or false
end

-- The chat frame an edit box belongs to (the client's own field first, the
-- parent second — both shapes defended like the header lookup above).
local function editBoxOwner(eb)
    if type(eb) ~= "table" then return nil end
    if type(eb.chatFrame) == "table" then return eb.chatFrame end
    if type(eb.GetParent) == "function" then
        local ok, p = pcall(eb.GetParent, eb)
        if ok and type(p) == "table" then return p end
    end
    return nil
end

-- Focus-lost styling IS the placeholder treatment: the bar quiets down to a
-- hint carrying nothing but the channel prefix, and comes back to full
-- strength the moment it holds focus.
function Skin.StyleEditBoxFocus(eb, focused)
    if type(eb) ~= "table" then return end
    local alpha = focused and EB_ACTIVE or EB_IDLE
    if type(eb.SetAlpha) == "function" then pcall(eb.SetAlpha, eb, alpha) end
    local frame = editBoxOwner(eb)
    local rec = frame and Skin.styled[frame]
    if rec and rec.ebSkin and type(rec.ebSkin.SetAlpha) == "function" then
        pcall(rec.ebSkin.SetAlpha, rec.ebSkin, alpha)
    end
end

-- Keep the box (and its prefix) visible. Returns true when it did something.
function Skin.KeepEditBoxShown(eb)
    if not Skin.EditBoxPersistent() then return false end
    if type(eb) ~= "table" then return false end
    local frame = editBoxOwner(eb)
    -- Only for a window we actually dressed, and only while that window is on
    -- screen: forcing an edit box onto a closed window would be a bug wearing
    -- a feature's clothes.
    if not (frame and Skin.styled[frame]) then return false end
    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and not shown then return false end
    end
    -- Class 9 discipline: the latch is armed BEFORE the first client call of
    -- the sequence and released when the sequence returns, pcall-protected so
    -- an error can never wedge it.
    if Skin._ebDepth > 0 then return false end
    Skin._ebDepth = Skin._ebDepth + 1
    local ok, err = pcall(function()
        local header = editBoxHeader(eb)
        local function isShown(w)
            if type(w) ~= "table" or type(w.IsShown) ~= "function" then return true end
            local okS, v = pcall(w.IsShown, w)
            return okS and v and true or false
        end
        -- Only the RESTORE costs a client call. If the box and its prefix are
        -- already up, re-running the client's header pass would be pure noise
        -- on every beat that touches us — and would overwrite the channel ink
        -- that our own listeners just applied.
        local restoring = (not isShown(eb)) or (header and not isShown(header))
        if type(eb.Show) == "function" then eb:Show() end
        if header and type(header.Show) == "function" then header:Show() end
        if restoring then
            local upd = _G.ChatEdit_UpdateHeader
            if type(upd) == "function" then upd(eb) end
        end
        local focused = (type(eb.HasFocus) == "function") and eb:HasFocus() or false
        Skin.StyleEditBoxFocus(eb, focused)
    end)
    Skin._ebDepth = Skin._ebDepth - 1
    if not ok and ns.RouteError then ns.RouteError(err) end
    local rec = Skin.styled[frame]
    if rec then rec.ebForcedShown = true end
    return ok
end

-- The per-box rig: the focus scripts and the object watcher, installed once
-- per edit box (HookScript is additive — the client's own handlers keep
-- running, we only ever run after them).
local function ensureEditBoxRig(frame, rec)
    local eb = editBoxOf(frame)
    if not eb or rec.ebRig then return end
    if type(eb.HookScript) ~= "function" then return end
    rec.ebRig = true
    eb:HookScript("OnEditFocusGained", function(self)
        if not Skin.active then return end
        Skin.StyleEditBoxFocus(self, true)
    end)
    eb:HookScript("OnEditFocusLost", function(self)
        if not Skin.active then return end
        Skin.StyleEditBoxFocus(self, false)
    end)
    -- skin v2.2: the chat menu's FALLBACK affordance. The icon rail carries the
    -- menu verb, but the rail ships OFF, so the resting bar's own prefix strip
    -- answers a RIGHT-click with the same client menu. Additive (HookScript),
    -- modified-gesture-only, and measured — an unplaceable right-click is left
    -- exactly as native, and a left-click is never touched at all.
    eb:HookScript("OnMouseDown", function(self, button)
        if not Skin.active then return end
        if button ~= "RightButton" then return end
        if not Skin.OverPrefix(self) then return end
        Skin.OpenChatMenu()
    end)
    eb:HookScript("OnHide", function(self)
        if not Skin.EditBoxPersistent() then return end
        -- Deferred by one beat: re-showing from inside a hide handler is the
        -- re-entrancy this defers away from. Without a timer (headless without
        -- C_Timer) the watch simply does not fire — the function post-hook is
        -- the primary seam and still covers the client's own path.
        local CT = _G.C_Timer
        if not (CT and type(CT.After) == "function") then return end
        if self._dchatReshowQueued then return end
        self._dchatReshowQueued = true
        CT.After(0, function()
            self._dchatReshowQueued = false
            Skin.KeepEditBoxShown(self)
        end)
    end)
end

local function restoreEditBox(frame, rec)
    local eb = editBoxOf(frame)
    if not eb then return end
    local ebName = eb.GetName and eb:GetName()
    if ebName and rec.ebStock then
        for suffix, alpha in pairs(rec.ebStock) do
            local region = _G[ebName .. suffix]
            if region and type(region.SetAlpha) == "function" then
                pcall(region.SetAlpha, region, alpha)
            end
        end
    end
    restorePoints(eb, rec.ebPoints)
    if rec.ebSkin then rec.ebSkin:Hide() end
    -- Hand the client's own visibility rule back: a box we forced open, that
    -- nobody is typing in, goes away again exactly as it would have natively.
    if rec.ebForcedShown then
        rec.ebForcedShown = nil
        local focused = (type(eb.HasFocus) == "function") and eb:HasFocus() or false
        if not focused and type(eb.Hide) == "function" then pcall(eb.Hide, eb) end
        if type(eb.SetAlpha) == "function" then pcall(eb.SetAlpha, eb, EB_ACTIVE) end
    end
end

----------------------------------------------------------------------
-- MOVING A WINDOW WITHOUT AN EDIT MODE (skin v2.1, default ON).
--
-- The client's own answer to "how do I move this" is: unlock the window, then
-- drag its TAB. This adds the direct affordance the owner asked for — ALT-drag
-- anywhere on the window's panel region — without taking anything away:
--
--   * UNMODIFIED CLICKS ARE NEVER INTERCEPTED. The drag-start body returns
--     immediately unless ALT is held (or the session is unlocked via
--     /dchat unlock), so chat text, hyperlinks, scrolling and the tab's own
--     drag behave exactly as they always did. We never enable mouse on a frame
--     that did not have it, so `wholeChatWindowClickable` still decides
--     click-through.
--   * DOCKED WINDOWS FOLLOW THE DOCK. A docked window's placement belongs to
--     the dock manager, so ALT-dragging one moves the DOCK — i.e. its primary
--     frame — which is the only move that means anything. An undocked window
--     moves itself.
--   * THE CLIENT'S LOCK FLAG IS NOT FOUGHT, IT IS ANSWERED. `locked` in the
--     per-character store governs the client's own tab-drag; a deliberate
--     modified gesture is a different act, and refusing it would just be the
--     edit-mode question again. What the store says is printed by
--     /dchat debug position, so the state is never a mystery.
--   * RELEASE CAPTURES BACK through the reconciler's existing debounced path
--     (NoteExternalChange), so the new position lands in the authoritative
--     config, gets rev-bumped and syncs — and the reconciler, which marks its
--     own writes, cannot fight it.
----------------------------------------------------------------------

-- The clamp rect is what refuses a manual drag at the screen edge. Zeroing the
-- insets lets a drag reach the edge while the frame stays clamped ON screen —
-- a window dragged off the world entirely is not a feature. The call is
-- PROTECTED IN COMBAT (the survey's frame-treatment note), so a combat refusal
-- is remembered and replayed on the regen beat rather than thrown away.
function Skin.LoosenClamp(frame, rec)
    if not cfg().unclampWindows then return false end
    if type(frame) ~= "table" or type(frame.SetClampRectInsets) ~= "function" then
        return false
    end
    local icl = _G.InCombatLockdown
    if type(icl) == "function" then
        local ok, inCombat = pcall(icl)
        if ok and inCombat then
            Skin._clampPending[frame] = true
            return false
        end
    end
    -- Save the client's own insets once, so a disable hands them back.
    rec = rec or Skin.styled[frame]
    if rec and not rec.clampInsets and type(frame.GetClampRectInsets) == "function" then
        local ok, l, r, t, b = pcall(frame.GetClampRectInsets, frame)
        if ok and type(l) == "number" then rec.clampInsets = { l, r, t, b } end
    end
    pcall(frame.SetClampRectInsets, frame, 0, 0, 0, 0)
    Skin._clampPending[frame] = nil
    return true
end

function Skin.DrainPendingClamps()
    if not Skin.active then return 0 end
    local n = 0
    for frame in pairs(Skin._clampPending) do
        Skin._clampPending[frame] = nil
        if Skin.LoosenClamp(frame) then n = n + 1 end
    end
    return n
end

-- THE RE-CLAMP SEAM (bounce suspect b). The client does not merely clamp once:
-- it REWRITES a window's clamp insets every time it re-decides which side the
-- button column belongs on, because the column's width has to be reserved on
-- screen — and FloatingChatFrame_Update and FCF_DockUpdate both route through
-- that decision. So a window placed flush against the edge is shoved back
-- inward on the client's very next window beat, and the owner watches it
-- "bounce back". Zeroing the insets once at style time was never enough.
--
-- The posture is the tab-art strip's and the button column's, exactly: the
-- client makes its decision, we take the last word SYNCHRONOUSLY inside the
-- same call. LoosenClamp is already combat-protected and already remembers a
-- refusal for the regen drain, so extending it to these beats costs nothing in
-- combat and heals on the regen beat that already exists for the column.
function Skin.ReClamp(frame)
    if not Skin.active then return false end
    if type(frame) ~= "table" or not Skin.styled[frame] then return false end
    return Skin.LoosenClamp(frame)
end

function Skin.ReClampAll()
    if not Skin.active then return 0 end
    local n = 0
    for _, frame in ipairs(Skin.order) do
        if Skin.LoosenClamp(frame) then n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------
-- THE LOCK (owner, 2026-08-11). ONE state for the whole addon, and it lives in
-- the SYNCED config (Config.Locked) beside the position it governs — view.lua
-- reads the same answer for the drawn box's drag/resize/grips. LOCKED vetoes
-- every move gesture here too, ALT included: "the box is a rock" cannot have
-- an exception, or the first ALT-drag makes a liar of the setting.
--
-- Skin.moveMode (the old SESSION-scoped plain-drag unlock) survives as exactly
-- what it always was for the box-off path, and the verbs below keep it in step
-- with the lock so there is one thing to think about rather than two.
----------------------------------------------------------------------

function Skin.Locked()
    local C = ns.Config
    if C and type(C.Locked) == "function" then
        local ok, v = pcall(C.Locked)
        if ok then return v and true or false end
    end
    return false
end

-- The ONE write path for the lock: the synced config, the session mirror, and
-- the drawn box's grips, in that order. The slash verbs and the settings pane
-- both come through here, so the two can never disagree.
function Skin.SetLocked(on)
    on = on and true or false
    local C = ns.Config
    local changed = false
    if C and type(C.SetLocked) == "function" then
        local ok, res = pcall(C.SetLocked, on)
        changed = (ok and res) and true or false
    end
    Skin.moveMode = not on
    local V = ns.View
    if V and type(V.ApplyLock) == "function" then pcall(V.ApplyLock) end
    return changed
end

-- Is a drag gesture a MOVE gesture right now?
function Skin.MoveAllowed()
    if not Skin.active or not cfg().altDragMove then return false end
    if Skin.Locked() then return false end
    if Skin.moveMode then return true end
    local alt = _G.IsAltKeyDown
    if type(alt) ~= "function" then return false end
    local ok, down = pcall(alt)
    return (ok and down) and true or false
end

-- Which frame actually moves: the dock's primary for anything docked, the
-- frame itself otherwise. Second return says whether the dock was the answer.
function Skin.MoveTarget(frame, id)
    local docked
    local gcwi = _G.GetChatWindowInfo
    if type(gcwi) == "function" and id then
        local ok, _, _, _, _, _, _, _, _, d = pcall(gcwi, id)
        if ok then docked = d end
    end
    if docked and docked ~= 0 then
        local dock = _G.GeneralDockManager
        local primary = (type(dock) == "table" and type(dock.primary) == "table")
            and dock.primary or _G.DEFAULT_CHAT_FRAME
        if type(primary) == "table" then return primary, true end
    end
    return frame, false
end

----------------------------------------------------------------------
-- SNAP TO EDGES (skin v3.1, the owner's "align it with the edit-mode
-- boundaries" ask, answered as automatic alignment rather than better aim).
--
-- WHAT IT IS: on DROP, a window whose edge landed within a small threshold of
-- a meaningful boundary is moved onto that boundary EXACTLY. The boundaries
-- are the ones the client's own edit mode draws: the four screen edges (the
-- left one at exactly 0, which is the owner's flush-left goal), the screen's
-- centre lines, and the edges of the other managed chat windows.
--
-- WHY DROP AND NOT PER FRAME: the drag itself is the CLIENT's (StartMoving
-- follows the cursor natively, and a docked drag follows the dock). Rewriting
-- the corner every frame would fight that; correcting the LANDING does not.
-- The hairline guide below gives the magnetic feel without the fight.
--
-- SPACES (Class 3, mechanically): every comparison happens in SCREEN PIXELS.
-- Frame edges are read in the frame's own units and multiplied by ITS effective
-- scale; the answer is divided back by the same scale before it is written as a
-- SetPoint offset. No comparison ever crosses a scale boundary implicitly.
--
-- ORDER (Class 8): the boundary list is built screen-first, then windows in
-- Skin.order, and ties keep the first candidate — so two identical worlds snap
-- to the same line every time.
--
-- THE CLAMP IS NOT FOUGHT: snapping writes through SetPoint (programmatic
-- placement is not drag-clamped) and the loosened insets are re-asserted right
-- after, so a snap to exactly 0 lands at 0 and stays there.
----------------------------------------------------------------------

-- Screen pixels. A constant, deliberately, not a slider: a threshold the
-- player can mistune is a threshold that stops feeling like alignment.
Skin.SNAP_THRESHOLD = 10

-- REUSABLE BY CONSTRUCTION. Nothing below knows what a chat window is: every
-- entry point takes THE FRAME BEING DRAGGED and reads its live geometry, and
-- the only thing that is specific to this module is which frames count as
-- PEERS to align against. That one fact is a published override point, so a
-- future view that draws its own frames reuses this layer whole by pointing
-- Skin.SnapPeers at its own set — no fork, no second implementation of the
-- arithmetic, and the pins below keep covering both.
function Skin.SnapPeers()
    return Skin.order
end

-- The snap layer belongs to whichever module is actually moving frames. Skin
-- v3.1 wrote "a future view that draws its own frames reuses this layer whole
-- by pointing Skin.SnapPeers at its own set" — that future arrived with the D2
-- revision, so the LIVENESS question is asked of both owners. Everything else
-- about the layer is unchanged, which is the whole point of having built it
-- frame-agnostically.
function Skin.SnapEnabled()
    local V = ns.View
    local live = Skin.active or (V and V.active) or false
    return (live and cfg().snapToEdges ~= false) and true or false
end

-- One frame's rect in SCREEN PIXELS: left, bottom, width, height, scale.
-- nil for anything the client has not laid out yet (never a zero — Class 4).
local function rectPx(frame)
    if type(frame) ~= "table" then return nil end
    local l  = widgetNum(frame, "GetLeft")
    local b  = widgetNum(frame, "GetBottom")
    local w  = widgetNum(frame, "GetWidth")
    local h  = widgetNum(frame, "GetHeight")
    local fs = widgetNum(frame, "GetEffectiveScale")
    if l == nil or b == nil or fs == nil or fs <= 0 then return nil end
    return l * fs, b * fs, (w or 0) * fs, (h or 0) * fs, fs
end

-- Every boundary a drop may land on, in screen pixels: two ordered arrays
-- (vertical lines to test x against, horizontal lines for y). `exclude` is the
-- frame being dropped — a window never snaps to itself.
function Skin.SnapLines(exclude)
    local C = ns.Config
    if not (C and type(C.ScreenGeometry) == "function") then return nil, nil end
    local uiW, uiH, uiScale = C.ScreenGeometry()
    if not uiW then return nil, nil end                 -- world not laid out: no guess
    local sw, sh = uiW * uiScale, uiH * uiScale
    local vx = {
        { at = 0,      kind = "screen left" },
        { at = sw,     kind = "screen right" },
        { at = sw / 2, kind = "screen centre" },
    }
    local hy = {
        { at = 0,      kind = "screen bottom" },
        { at = sh,     kind = "screen top" },
        { at = sh / 2, kind = "screen middle" },
    }
    for _, other in ipairs(Skin.SnapPeers() or {}) do
        if other ~= exclude then
            local shown = true
            if type(other.IsShown) == "function" then
                local ok, v = pcall(other.IsShown, other)
                shown = ok and v and true or false
            end
            local l, b, w, h = rectPx(other)
            if shown and l then
                vx[#vx + 1] = { at = l,     kind = "window edge" }
                vx[#vx + 1] = { at = l + w, kind = "window edge" }
                hy[#hy + 1] = { at = b,     kind = "window edge" }
                hy[#hy + 1] = { at = b + h, kind = "window edge" }
            end
        end
    end
    return vx, hy
end

-- PURE. Given a frame's two edges on one axis and the lines to test them
-- against, the delta (in pixels) that puts the nearer edge exactly on the
-- nearest line — or nil when nothing is within the threshold.
function Skin.SnapDelta(lo, hi, lines, threshold)
    threshold = tonumber(threshold) or Skin.SNAP_THRESHOLD
    local best, bestLine
    for _, line in ipairs(lines or {}) do
        local at = tonumber(line.at)
        if at then
            for _, own in ipairs({ lo, hi }) do
                local d = at - own
                if math.abs(d) <= threshold
                   and (best == nil or math.abs(d) < math.abs(best)) then
                    best, bestLine = d, line
                end
            end
        end
    end
    return best, bestLine
end

-- What WOULD this drop snap to, right now? Returns the two chosen lines (or
-- nil each). Read by the guides mid-drag and by the drop itself, so what the
-- player is shown and what actually happens can never be two different answers.
function Skin.SnapPreview(frame)
    if not Skin.SnapEnabled() then return nil, nil end
    local l, b, w, h = rectPx(frame)
    if l == nil then return nil, nil end
    local vx, hy = Skin.SnapLines(frame)
    if not vx then return nil, nil end
    local dx, lineX = Skin.SnapDelta(l, l + w, vx, Skin.SNAP_THRESHOLD)
    local dy, lineY = Skin.SnapDelta(b, b + h, hy, Skin.SNAP_THRESHOLD)
    return lineX and { delta = dx, line = lineX } or nil,
           lineY and { delta = dy, line = lineY } or nil
end

-- The drop itself. Returns true when the landing was actually corrected, and
-- records what happened for /dchat debug skin.
function Skin.SnapOnDrop(frame)
    Skin.lastSnap = nil
    if not Skin.SnapEnabled() then return false end
    if type(frame) ~= "table" then return false end
    if type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function" then
        return false
    end
    local l, b, _, _, fs = rectPx(frame)
    if l == nil then return false end
    local sx, sy = Skin.SnapPreview(frame)
    if not sx and not sy then return false end
    local P = _G.UIParent
    if type(P) ~= "table" then return false end
    local nl = (l + (sx and sx.delta or 0)) / fs
    local nb = (b + (sy and sy.delta or 0)) / fs
    local ok = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", nl, nb)
    end)
    if not ok then return false end
    Skin.snaps = Skin.snaps + 1
    Skin.lastSnap = {
        x = sx and sx.line.kind or nil,
        y = sy and sy.line.kind or nil,
    }
    return true
end

----------------------------------------------------------------------
-- THE GUIDES: the edit-mode hairline, borrowed. One accent-token line along
-- whichever boundary the drop is currently reaching for, created lazily on the
-- first drag that needs it, hidden the moment the drag ends, and never present
-- outside a drag at all. The per-frame driver is OUR OWN frame — nothing is
-- hooked onto a chat window's OnUpdate — and it is hidden (i.e. not running)
-- whenever no drag is in flight.
----------------------------------------------------------------------

local GUIDE_W = 1      -- the hairline's own thickness, in UIParent units

local function ensureGuides()
    if Skin._guides then return Skin._guides end
    local P = _G.UIParent
    if type(P) ~= "table" or type(P.CreateTexture) ~= "function" then return nil end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" then return nil end
    local okD, driver = pcall(cf, "Frame", nil, P)
    if not okD or type(driver) ~= "table" then return nil end
    driver:Hide()
    if type(driver.SetScript) == "function" then
        driver:SetScript("OnUpdate", function() Skin.UpdateSnapGuides() end)
    end
    local function line()
        local t = P:CreateTexture(nil, "OVERLAY")
        if type(t.Hide) == "function" then t:Hide() end
        return t
    end
    Skin._guides = { driver = driver, v = line(), h = line() }
    return Skin._guides
end

local function paintGuide(tex)
    if not tex then return end
    local r, g, b = Skin.Ink("accent")
    local UI = UIKit()
    if not r and UI and type(UI.Color) == "function" then r, g, b = UI.Color("accent") end
    if r and type(tex.SetColorTexture) == "function" then
        pcall(tex.SetColorTexture, tex, r, g, b, 1)
    end
end

function Skin.BeginSnapGuides(frame)
    Skin._guideSubject = nil
    if not Skin.SnapEnabled() then return false end
    local g = ensureGuides()
    if not g then return false end
    Skin._guideSubject = frame
    if type(g.driver.Show) == "function" then g.driver:Show() end
    Skin.UpdateSnapGuides()
    return true
end

function Skin.EndSnapGuides()
    Skin._guideSubject = nil
    local g = Skin._guides
    if not g then return false end
    if type(g.driver.Hide) == "function" then g.driver:Hide() end
    if type(g.v.Hide) == "function" then g.v:Hide() end
    if type(g.h.Hide) == "function" then g.h:Hide() end
    return true
end

function Skin.UpdateSnapGuides()
    local g = Skin._guides
    local frame = Skin._guideSubject
    if not g then return false end
    if not (frame and Skin.SnapEnabled()) then return Skin.EndSnapGuides() end
    local C, P = ns.Config, _G.UIParent
    if not (C and type(C.ScreenGeometry) == "function") then return false end
    local uiW, uiH, uiScale = C.ScreenGeometry()
    if not uiW then return false end
    local sx, sy = Skin.SnapPreview(frame)
    local function place(tex, vertical, atPx)
        if atPx == nil then
            if type(tex.Hide) == "function" then tex:Hide() end
            return
        end
        local at = atPx / uiScale                     -- pixels -> UIParent units
        paintGuide(tex)
        if type(tex.ClearAllPoints) == "function" then tex:ClearAllPoints() end
        if type(tex.SetSize) == "function" then
            if vertical then tex:SetSize(GUIDE_W, uiH) else tex:SetSize(uiW, GUIDE_W) end
        end
        if type(tex.SetPoint) == "function" then
            if vertical then
                tex:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", at - GUIDE_W / 2, 0)
            else
                tex:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", 0, at - GUIDE_W / 2)
            end
        end
        if type(tex.Show) == "function" then tex:Show() end
    end
    place(g.v, true,  sx and sx.line.at or nil)
    place(g.h, false, sy and sy.line.at or nil)
    return true
end

----------------------------------------------------------------------
-- COMMITTING A MOVE (bounce suspect a, the half nothing else covers).
--
-- StartMoving/StopMovingOrSizing leaves the frame where the player dropped it
-- and writes NOTHING: the client's per-character store still holds the OLD
-- corner. The client's own restore verb (FCF_RestorePositionAndDimensions,
-- reached from FloatingChatFrame_Update, which the reconciler itself pokes)
-- reads that store and puts the window straight back. So a drag that is never
-- committed to the store is a position with an expiry date — the owner's
-- "it always bounces back", in one sentence.
--
-- The commit uses the CLIENT'S OWN SAVE VERB, so the store learns exactly what
-- the client would have written for a native drag, and it runs inside
-- SelfWrite: the store write is OUR echo, while the MOVE is the player's edit
-- and is announced separately through NoteExternalChange. Two different facts,
-- two different channels — which is what keeps the capture ledger honest about
-- who authored a position.
----------------------------------------------------------------------

function Skin.CommitMove(target)
    if type(target) ~= "table" then return false end
    local save = _G.FCF_SavePositionAndDimensions
    if type(save) ~= "function" then return false end
    local R = ns.Reconcile
    local run = function() pcall(save, target) end
    if R and type(R.SelfWrite) == "function" then R.SelfWrite(run) else run() end
    Skin.moveCommits = Skin.moveCommits + 1
    return true
end

function Skin.OnMoveStart(frame, id)
    if not Skin.MoveAllowed() then return false end
    local target, viaDock = Skin.MoveTarget(frame, id)
    if type(target) ~= "table" or type(target.StartMoving) ~= "function" then return false end
    if type(target.SetMovable) == "function" then pcall(target.SetMovable, target, true) end
    -- Re-assert the loosened clamp at the moment it matters: the client
    -- re-clamps periodically, and the drag about to happen is exactly when a
    -- stale clamp would refuse the screen edge.
    Skin.LoosenClamp(target)
    local ok = pcall(target.StartMoving, target)
    if not ok then return false end
    Skin._moving = { frame = frame, target = target, id = id, viaDock = viaDock }
    Skin.BeginSnapGuides(target)
    return true
end

function Skin.OnMoveStop()
    local mv = Skin._moving
    if not mv then return false end          -- a drag we did not start: not ours
    Skin._moving = nil
    if type(mv.target.StopMovingOrSizing) == "function" then
        pcall(mv.target.StopMovingOrSizing, mv.target)
    end
    -- SNAP AT DROP (never per frame): the drag itself stayed native-smooth,
    -- and the landing is corrected to the boundary it was reaching for.
    Skin.SnapOnDrop(mv.target)
    Skin.EndSnapGuides()
    -- The client re-clamps on the beats StopMovingOrSizing itself sets off
    -- (the button-side re-decision), so the last word is retaken here too —
    -- otherwise a flush drop is shoved back inward before anything reads it.
    Skin.LoosenClamp(mv.target)
    Skin.moves = Skin.moves + 1
    -- THE STORE HAS TO AGREE, or the client's own restore beat undoes the drop.
    Skin.CommitMove(mv.target)
    -- CAPTURE-BACK through the reconciler's own debounced surface: the config
    -- learns the position the same way it learns every other player edit, so
    -- echo discipline, rev bumping and sync are unchanged by this feature.
    local R = ns.Reconcile
    if R and R.NoteExternalChange then R.NoteExternalChange("move: alt-drag") end
    return true
end

local function ensureMoveRig(frame, rec)
    if type(frame.SetMovable) ~= "function" or type(frame.HookScript) ~= "function" then
        return
    end
    -- The irreversible half — the script hooks — installs exactly once, and its
    -- bodies gate on Skin.active (the same discipline as hooksecurefunc above).
    if not rec.moveRig then
        rec.moveRig = true
        if type(frame.IsMovable) == "function" then
            local ok, was = pcall(frame.IsMovable, frame)
            if ok then rec.wasMovable = was and true or false end
        end
        if type(frame.RegisterForDrag) == "function" then
            pcall(frame.RegisterForDrag, frame, "LeftButton")
        end
        local id = rec.id
        frame:HookScript("OnDragStart", function(self) Skin.OnMoveStart(self, id) end)
        frame:HookScript("OnDragStop",  function() Skin.OnMoveStop() end)
    end
    -- The reversible half is RE-ASSERTED on every style pass: a disable gives
    -- movability back to the client, so a re-enable has to take it again.
    pcall(frame.SetMovable, frame, true)
end

----------------------------------------------------------------------
-- THE CHAT BUTTON COLUMN (skin v2.2, default ON = the column is DOWN).
--
-- WHAT IT IS: every chat window carries a small button frame — the chat-menu
-- and scroll-button column — hanging off one edge of the window. The client
-- picks WHICH edge from the window's screen position (FCF_UpdateButtonSide /
-- FCF_GetButtonSide / FCF_SetButtonSide, all catalog-verified on 11509): a
-- window pushed against the left edge has no room for the column there, so the
-- client flips it to the right. That is why the owner's two accounts disagree
-- about which side the little square column sits on — same client rule, two
-- different window positions.
--
-- WHY IT IS IN THE WAY: the column rides along with the window and has to fit
-- on screen too, so its width is part of what a DRAG has to place — the last
-- stretch to the screen edge is eaten by the column even after the clamp
-- insets are loosened. Taking the column down is the other half of the
-- flush-to-the-edge fix, and Skin.ColumnFootprint is this module's own
-- awareness of it (what the removed column stops costing, in the window's
-- units — the rail's placement reads it, /dchat debug skin prints it).
--
-- WHY IT CAN GO: the reference look the owner chose has no column; the skin's
-- icon rail already carries scroll-to-bottom, and the persistent edit box
-- carries the sticky channel the menu button mostly answered. The ONE verb
-- with no replacement — the client's chat menu (languages, emotes, whisper
-- targets) — is kept reachable in both worlds (Skin.OpenChatMenu below).
--
-- THE SEAM, same posture as the persistent edit box: the last word, never a
-- fight. The client re-shows the column on every button-side update, so we
--   1. POST-hook FCF_UpdateButtonSide and FCF_SetButtonSide (the client makes
--      its side decision and its re-show, then we take it back down, in-call);
--   2. WATCH the object with an OnShow, deferred one beat (Class 2: a show can
--      arrive from a path no function hook sees), latched per Class 9 so a
--      nested beat can never spin.
-- Nothing is destroyed: Hide() is reversible, the client's own shown state is
-- remembered on the first touch, and OPTION OFF is byte-identical native
-- behavior — including the client's side-flipping, which we never suppress.
----------------------------------------------------------------------

-- A widget number read that answers nil for UNKNOWN (never a manufactured 0).
function Skin.HideButtonColumn()
    return (Skin.active and cfg().hideButtonColumn) and true or false
end

-- The window's button column. Both client shapes are defended, exactly like
-- the edit box's header lookup: the frame's own field (the game-facts
-- register's name for it) and the $parentButtonFrame global.
function Skin.ButtonColumnOf(frame)
    if type(frame) ~= "table" then return nil end
    if type(frame.buttonFrame) == "table" then return frame.buttonFrame end
    local n = frame.GetName and frame:GetName()
    local byName = n and _G[n .. "ButtonFrame"]
    return (type(byName) == "table") and byName or nil
end

-- Which side the client currently has the column on: its own accessor first,
-- geometry second, and nil (UNKNOWN) when neither can answer.
function Skin.ButtonColumnSide(frame)
    local f = _G.FCF_GetButtonSide
    if type(f) == "function" then
        local ok, side = pcall(f, frame)
        if ok and type(side) == "string" and side ~= "" then return side:lower() end
    end
    local col = Skin.ButtonColumnOf(frame)
    local colLeft, frameLeft = widgetNum(col, "GetLeft"), widgetNum(frame, "GetLeft")
    if colLeft and frameLeft then return (colLeft < frameLeft) and "left" or "right" end
    return nil
end

-- What the column costs the window's placement right now, in the window's own
-- units: extra width on the left, extra width on the right. A column that is
-- down (or absent, or unmeasurable) costs nothing — which is the whole point.
function Skin.ColumnFootprint(frame)
    local col = Skin.ButtonColumnOf(frame)
    if not col then return 0, 0 end
    if type(col.IsShown) == "function" then
        local ok, shown = pcall(col.IsShown, col)
        if ok and not shown then return 0, 0 end
    end
    local w = widgetNum(col, "GetWidth")
    if not w or w <= 0 then return 0, 0 end
    if Skin.ButtonColumnSide(frame) == "right" then return 0, w end
    return w, 0
end

-- Take the column down and KEEP it down. Costs a client call ONLY when the
-- column is actually up, so an idle beat is free and a fight loop is not a
-- shape this code can take. A refused hide is not retried in a spin either: it
-- is swallowed here and picked up by the next client beat that re-shows the
-- column, which is the only beat where it matters again.
----------------------------------------------------------------------
-- THE COLUMN IS DISABLED, NOT MERELY HIDDEN (owner, 2026-08-11: "completely
-- disable them and remove their hitboxes").
--
-- Hide() takes the pixels; it does NOT reliably take the mouse. A hidden frame
-- does not receive input in this client, but the column is a frame the client
-- RE-SHOWS on its own beats (every button-side update), and in the window
-- between its show and our re-hide its buttons are live — which is exactly the
-- "invisible hitbox beside my chat window" the owner is describing. So the
-- option now takes three things, in this order:
--   1. the MOUSE, off the column frame and off every descendant button, with
--      each widget's prior state RECORDED so OFF restores it exactly;
--   2. any EVENT registrations those widgets hold (UnregisterAllEvents);
--   3. the pixels (Hide), plus the existing keep-hidden last word as the belt.
-- Re-applied on every beat that re-shows the column, so a client that
-- resurrects it hands back a frame with nothing interactive on it.
--
-- THE ONE HONEST GAP: the client offers no way to enumerate the events a frame
-- holds (IsEventRegistered answers about a NAMED event; there is no listing),
-- so step 2 is not exactly reversible. Mouse state is captured and restored
-- byte-for-byte; dropped event registrations are not recoverable, and turning
-- the option OFF prints ONE line saying so and naming /reload as the exact
-- restore. Never a half-restored state pretending to be whole.
----------------------------------------------------------------------

-- Frame-ish children only (the client's GetChildren answers frames; textures
-- and font strings are not children and carry no hitbox of their own).
local function childFrames(w)
    if type(w) ~= "table" or type(w.GetChildren) ~= "function" then return {} end
    local ok, kids = pcall(function() return { w:GetChildren() } end)
    if not ok or type(kids) ~= "table" then return {} end
    local out = {}
    for i = 1, #kids do
        if type(kids[i]) == "table" then out[#out + 1] = kids[i] end
    end
    return out
end

-- The column frame and every descendant, in a stable walk order (Class 8: the
-- disable/restore pair must visit the same widgets in the same order every
-- time). Depth-bounded — a cycle in a client hierarchy must not hang us.
function Skin.ColumnWidgets(frame)
    local out, seen = {}, {}
    local function walk(w, depth)
        if type(w) ~= "table" or seen[w] or depth > 4 then return end
        seen[w] = true
        out[#out + 1] = w
        for _, kid in ipairs(childFrames(w)) do walk(kid, depth + 1) end
    end
    walk(Skin.ButtonColumnOf(frame), 0)
    return out
end

-- Take the mouse (and any events) off the column subtree. Idempotent, and
-- cheap on a beat where everything is already disabled: a widget already in
-- the record is only re-asserted (which is what a client re-show needs).
-- Returns the number of widgets disabled.
function Skin.DisableButtonColumn(frame)
    local rec = Skin.styled[frame]
    if not rec then return 0 end
    rec.bfDisabled = rec.bfDisabled or {}      -- widget -> { mouse = bool|nil }
    rec.bfDisabledOrder = rec.bfDisabledOrder or {}
    local n = 0
    for _, w in ipairs(Skin.ColumnWidgets(frame)) do
        local state = rec.bfDisabled[w]
        if not state then
            state = {}
            if type(w.IsMouseEnabled) == "function" then
                local okM, on = pcall(w.IsMouseEnabled, w)
                if okM then state.mouse = on and true or false end
            end
            rec.bfDisabled[w] = state
            rec.bfDisabledOrder[#rec.bfDisabledOrder + 1] = w
            -- Events go ONCE per widget (on first capture): re-running
            -- UnregisterAllEvents on every client beat would be a per-beat
            -- client call for nothing.
            if type(w.UnregisterAllEvents) == "function" then
                if pcall(w.UnregisterAllEvents, w) then
                    rec.bfEventsDropped = true
                    Skin.columnEventsDropped = Skin.columnEventsDropped + 1
                end
            end
        end
        if type(w.EnableMouse) == "function" then
            if pcall(w.EnableMouse, w, false) then n = n + 1 end
        end
    end
    Skin.columnDisables = Skin.columnDisables + (n > 0 and 1 or 0)
    return n
end

-- The honest line, once per session, when a disabled column is handed back.
function Skin.NoteColumnEventRestore()
    if Skin._columnEventNoticed then return false end
    Skin._columnEventNoticed = true
    ns:Print("chat button column restored: its mouse is live again exactly as it was.")
    ns:Print("  Event registrations its buttons held were dropped while it was disabled, and the")
    ns:Print("  client cannot enumerate them to put them back - /reload restores those exactly.")
    return true
end

-- Give the column's widgets their mouse back, precisely as each one had it.
-- Returns the number restored.
function Skin.EnableButtonColumn(frame, rec)
    rec = rec or Skin.styled[frame]
    if not (rec and rec.bfDisabledOrder) then return 0 end
    local n = 0
    for _, w in ipairs(rec.bfDisabledOrder) do
        local state = rec.bfDisabled and rec.bfDisabled[w]
        if state and type(w.EnableMouse) == "function" then
            -- UNKNOWN prior state (a client that would not answer
            -- IsMouseEnabled) restores to ENABLED, which is the client's own
            -- default for a button column — never left silently dead.
            if pcall(w.EnableMouse, w, state.mouse ~= false) then n = n + 1 end
        end
    end
    rec.bfDisabled, rec.bfDisabledOrder = nil, nil
    if rec.bfEventsDropped then
        rec.bfEventsDropped = nil
        Skin.NoteColumnEventRestore()
    end
    return n
end

function Skin.KeepButtonColumnHidden(frame)
    if not Skin.HideButtonColumn() then return false end
    local rec = Skin.styled[frame]
    if not rec then return false end
    local col = Skin.ButtonColumnOf(frame)
    if not col or type(col.Hide) ~= "function" then return false end
    -- The hitbox goes FIRST and unconditionally — before the early return for
    -- an already-hidden column — because a client re-show can bring back a
    -- child button whose mouse we have never taken.
    Skin.DisableButtonColumn(frame)
    -- The client's own visibility, remembered on the first touch so a disable
    -- hands back exactly what it had (never a blanket Show).
    if rec.bfWasShown == nil and type(col.IsShown) == "function" then
        local okW, was = pcall(col.IsShown, col)
        if okW then rec.bfWasShown = was and true or false end
    end
    local shown = true
    if type(col.IsShown) == "function" then
        local okS, v = pcall(col.IsShown, col)
        if okS then shown = v and true or false end
    end
    rec.bfForcedHidden = true
    if not shown then return false end        -- already down: nothing to say
    if Skin._bfDepth > 0 then return false end
    Skin._bfDepth = Skin._bfDepth + 1
    local ok, err = pcall(col.Hide, col)
    Skin._bfDepth = Skin._bfDepth - 1
    if not ok then
        if ns.RouteError then ns.RouteError(err) end
        return false
    end
    Skin.columnHides = Skin.columnHides + 1
    return true
end

-- Give the column back: the option went off, or the module did. The client's
-- own side logic is re-run rather than replayed from memory, so the column
-- returns where the CLIENT wants it, not where it was when we took it.
function Skin.RestoreButtonColumn(frame, rec)
    rec = rec or Skin.styled[frame]
    if not (rec and rec.bfForcedHidden) then return false end
    rec.bfForcedHidden = nil
    -- The mouse comes back before the pixels do, so there is never a beat where
    -- a visible column is dead to the pointer.
    Skin.EnableButtonColumn(frame, rec)
    local col = Skin.ButtonColumnOf(frame)
    if not col then return false end
    if rec.bfWasShown == false then return false end   -- it was down before us
    if type(col.Show) == "function" then pcall(col.Show, col) end
    local upd = _G.FCF_UpdateButtonSide
    if type(upd) == "function" then pcall(upd, frame) end
    return true
end

-- One window's column, brought in line with the option — the beat StyleWindow
-- and Refresh both call.
function Skin.SyncButtonColumn(frame)
    if Skin.HideButtonColumn() then return Skin.KeepButtonColumnHidden(frame) end
    return Skin.RestoreButtonColumn(frame)
end

local function ensureButtonColumnRig(frame, rec)
    if rec.bfRig then return end
    local col = Skin.ButtonColumnOf(frame)
    if not col or type(col.HookScript) ~= "function" then return end
    rec.bfRig = true
    col:HookScript("OnShow", function(self)
        if not Skin.HideButtonColumn() then return end
        -- Deferred one beat: hiding from inside a show handler is the
        -- re-entrancy this defers away from. Without C_Timer (headless) the
        -- watch simply does not fire — the function post-hooks are the primary
        -- seam and still cover every client path that has a name.
        local CT = _G.C_Timer
        if not (CT and type(CT.After) == "function") then return end
        if self._dchatRehideQueued then return end
        self._dchatRehideQueued = true
        CT.After(0, function()
            self._dchatRehideQueued = false
            Skin.KeepButtonColumnHidden(frame)
        end)
    end)
end

----------------------------------------------------------------------
-- THE CLIENT'S CHAT MENU — the one verb the column owned outright.
--
-- Languages, emotes, whisper targets: nothing in Chat replicates that list, so
-- hiding the column must not take it away. The seam is RESOLVED AT RUNTIME and
-- never assumed, because the obvious name is not there: ChatFrame_ToggleMenu
-- does NOT exist on 11509 (catalog), while ToggleFrame does, and the client's
-- own menu button performs exactly that toggle on the client's own menu frame.
-- So we ask, in order:
--   1. ToggleFrame(ChatMenu) — the client's own call on the client's own menu;
--   2. the client's menu BUTTON's own Click — the same verb, one layer up,
--      for a client that names the frame differently.
-- WHERE the menu lands stays the CLIENT's business: we toggle, we never
-- anchor. The harness pins CALL IDENTITY — the function we hold is the
-- client's own object, not a lookalike.
----------------------------------------------------------------------

-- Returns kind ("toggle" | "button"), the CLIENT function we will call, and
-- the subject to call it on. nil when this client offers neither shape.
function Skin.ChatMenuSeam()
    local toggle, menu = _G.ToggleFrame, _G.ChatMenu
    if type(toggle) == "function" and type(menu) == "table" then
        return "toggle", toggle, menu
    end
    local btn = _G.ChatFrameMenuButton
    if type(btn) == "table" and type(btn.Click) == "function" then
        return "button", btn.Click, btn
    end
    return nil
end

function Skin.OpenChatMenu()
    if not Skin.active then return nil end
    local kind, verb, subject = Skin.ChatMenuSeam()
    if not kind then return nil end
    local ok = pcall(verb, subject)
    if not ok then return nil end
    Skin.menuOpens = Skin.menuOpens + 1
    return kind
end

-- Is the pointer over the resting bar's PREFIX region ("Say:", "Guild:")?
-- That strip is the fallback affordance for the chat menu, so it has to be
-- measured honestly: the cursor answers in PIXELS (the client's convention)
-- and a widget edge answers in the widget's own units, so the read converts
-- through the box's effective scale (Class 3) before comparing. An unmeasurable
-- region is UNKNOWN and therefore NOT a hit — a right-click that cannot be
-- placed is left alone, never guessed into a menu.
function Skin.OverPrefix(eb)
    local header = editBoxHeader(eb)
    if type(eb) ~= "table" or type(header) ~= "table" then return false end
    local gcp = _G.GetCursorPosition
    if type(gcp) ~= "function" then return false end
    local okC, cx = pcall(gcp)
    if not okC or type(cx) ~= "number" then return false end
    local scale = widgetNum(eb, "GetEffectiveScale")
    if not scale or scale <= 0 then scale = 1 end
    cx = cx / scale
    local left  = widgetNum(header, "GetLeft") or widgetNum(eb, "GetLeft")
    local right = widgetNum(header, "GetRight")
    if right == nil and left ~= nil then
        local sw = widgetNum(header, "GetStringWidth")
        if sw and sw > 0 then right = left + sw end
    end
    if left == nil or right == nil then return false end
    return cx >= left and cx <= right
end

----------------------------------------------------------------------
-- The copy-chat affordance: a quiet per-window button (ASCII label) that opens
-- the shared copy window. The copy window is one themed frame holding the
-- extracted text in a multiline edit box, focused and pre-highlighted — the
-- only copy path that exists on era.
----------------------------------------------------------------------

local copyWindow   -- shared; built lazily on first use

local function ensureCopyWindow()
    local UI = UIKit()
    if copyWindow or not UI then return copyWindow end

    local f = _G.CreateFrame("Frame", "DaseekiChatCopyWindow", _G.UIParent, "BackdropTemplate")
    f:SetSize(560, 380)
    f:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 40)
    if f.SetFrameStrata then pcall(f.SetFrameStrata, f, "DIALOG") end
    if f.SetMovable then
        pcall(f.SetMovable, f, true)
        pcall(f.EnableMouse, f, true)
        if f.RegisterForDrag then pcall(f.RegisterForDrag, f, "LeftButton") end
        f:SetScript("OnDragStart", function(self) if self.StartMoving then self:StartMoving() end end)
        f:SetScript("OnDragStop", function(self) if self.StopMovingOrSizing then self:StopMovingOrSizing() end end)
    end
    UI.Skin(f, function(self)
        if type(self.SetBackdrop) == "function" then self:SetBackdrop(UI.FLAT_BACKDROP) end
        if type(self.SetBackdropColor) == "function" then
            self:SetBackdropColor(UI.Color("ground"))
        end
        if type(self.SetBackdropBorderColor) == "function" then
            self:SetBackdropBorderColor(UI.Color("borderLite"))
        end
    end)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(UI.fonts.header)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("Copy chat")
    f._title = title

    local closeBtn = UI.MakeButton(f, {
        text = "Close", variant = "quiet", width = 70,
        onClick = function() f:Hide() end,
    })
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)

    -- The text surface: a scrollable multiline edit box on an inset panel.
    local panel = UI.FlatFrame(f, "inset", "border")
    panel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

    local scroll = _G.CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 6)

    local edit = _G.CreateFrame("EditBox", nil, scroll)
    if edit.SetMultiLine then pcall(edit.SetMultiLine, edit, true) end
    if edit.SetAutoFocus then pcall(edit.SetAutoFocus, edit, false) end
    if edit.SetFontObject then pcall(edit.SetFontObject, edit, UI.fonts.body) end
    if edit.SetWidth then pcall(edit.SetWidth, edit, 500) end
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- The text is a read-back surface: typing must not corrupt it, so any
    -- edit attempt just re-selects (standard copy-window behavior).
    edit:SetScript("OnTextChanged", function(self, user)
        if user and f._text then
            self:SetText(f._text)
            if self.HighlightText then self:HighlightText() end
        end
    end)
    if scroll.SetScrollChild then pcall(scroll.SetScrollChild, scroll, edit) end
    f._edit = edit

    f:Hide()
    copyWindow = f
    return f
end

function Skin.OpenCopy(frame)
    local f = ensureCopyWindow()
    if not f then return end
    local lines = Skin.ExtractCopyText(frame)
    local text = table.concat(lines, "\n")
    f._text = text
    local frameName = (frame.GetName and frame:GetName()) or "chat"
    if f._title then f._title:SetText("Copy chat - " .. frameName) end
    f._edit:SetText(text)
    f:Show()
    if f._edit.SetFocus then pcall(f._edit.SetFocus, f._edit) end
    if f._edit.HighlightText then pcall(f._edit.HighlightText, f._edit) end
    return text
end

local function ensureCopyButton(frame, rec)
    local UI = UIKit()
    if not UI then return end
    if not cfg().copyButton then
        if rec.copyBtn then rec.copyBtn:Hide() end
        return
    end
    if rec.copyBtn then rec.copyBtn:Show() return end
    -- DELTA 4: this used to be the word "copy" in a 38-wide block, and it was
    -- the loudest thing on the owner's window. It is a QUIET GLYPH now — the
    -- icon rail's own idiom, same square, same idle alpha, muted until the
    -- pointer is on it and accent when it is.
    local btn = _G.CreateFrame("Button", nil, frame)
    btn:SetSize(RAIL_BTN, RAIL_BTN)
    btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", PAD, PAD)
    if btn.SetAlpha then btn:SetAlpha(COPY_IDLE) end
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(UI.fonts.small)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText("C")       -- ASCII by law; the rail's copy glyph, same verb
    local function quiet()
        if type(label.SetTextColor) ~= "function" then return end
        if Skin.Unified() then label:SetTextColor(Skin.Ink("muted"))
        else label:SetTextColor(UI.Color("muted")) end
    end
    local function loud()
        if type(label.SetTextColor) ~= "function" then return end
        if Skin.Unified() then label:SetTextColor(Skin.Ink("accent"))
        else label:SetTextColor(UI.Color("accent")) end
    end
    UI.Skin(label, quiet)
    btn:SetScript("OnEnter", function(self)
        if self.SetAlpha then self:SetAlpha(1) end
        loud()
    end)
    btn:SetScript("OnLeave", function(self)
        if self.SetAlpha then self:SetAlpha(COPY_IDLE) end
        quiet()
    end)
    btn:SetScript("OnClick", function() Skin.OpenCopy(frame) end)
    btn._label = label
    btn._quiet = quiet
    rec.copyBtn = btn
end

----------------------------------------------------------------------
-- THE ICON RAIL (skin v2 feature 4 — default OFF, the speculative one).
--
-- A slim themed strip on the window's left edge carrying ONLY verbs Chat
-- already owns. Nothing new hides behind these buttons, and the harness pins
-- that by CALL IDENTITY: every button holds the exact existing function object
-- it invokes.
--   copy   "C"  -> Skin.OpenCopy(frame)      (the copy-chat affordance)
--   config "*"  -> ns.SlashDispatch("")      (the /dchat surface)
--   bottom "v"  -> frame:ScrollToBottom()    (the client's own frame method)
--   menu   "="  -> Skin.OpenChatMenu()       (the CLIENT's own chat menu —
--                  skin v2.2: the one verb the hidden button column owned,
--                  kept reachable rather than replaced)
--
-- Every glyph is ASCII (the tofu law: only a NON-ASCII glyph needs a cmap
-- check against the vendored face — none ship here).
--
-- PLACEMENT (v2.2): the rail sits off the window's left edge, clearing whatever
-- the client's button column still occupies there — which, with the column
-- down, is nothing, so the rail moves in flush with the window.
----------------------------------------------------------------------

local RAIL_ORDER = { "copy", "config", "bottom", "menu" }

local function railButton(rail, glyph, onClick)
    local UI = UIKit()
    local btn = _G.CreateFrame("Button", nil, rail)
    btn:SetSize(RAIL_BTN, RAIL_BTN)
    if btn.SetAlpha then btn:SetAlpha(RAIL_IDLE) end
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(UI.fonts.small)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(glyph)                 -- ASCII by law
    UI.Skin(label, function(self)
        if type(self.SetTextColor) == "function" then self:SetTextColor(UI.Color("muted")) end
    end)
    btn:SetScript("OnEnter", function(self)
        if self.SetAlpha then self:SetAlpha(1) end
        if type(label.SetTextColor) == "function" then label:SetTextColor(UI.Color("accent")) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.SetAlpha then self:SetAlpha(RAIL_IDLE) end
        if type(label.SetTextColor) == "function" then label:SetTextColor(UI.Color("muted")) end
    end)
    btn:SetScript("OnClick", onClick)
    btn._glyph = glyph
    btn._label = label
    return btn
end

-- THE NON-COLLISION RULE (skin v3, pinned): the icon rail takes the edge
-- OPPOSITE the tab rail. Tabs on the left put the icon rail on the window's
-- right; every other placement (top, or tabs on the right) leaves it on the
-- left, which is where it has always been. One rule, no stacking, no case
-- where the two strips want the same pixels.
function Skin.RailSide()
    if Skin.TabsOnRail() and Skin.TabPlacement() == "left" then return "right" end
    return "left"
end

-- How far off that edge the rail sits: past the CHASSIS' own inset on that
-- side, the gap, and whatever the client's button column still costs there.
local function railOffset(frame)
    local colL, colR = Skin.ColumnFootprint(frame)
    local cl, cr = Skin.ChassisInsets()
    if Skin.RailSide() == "right" then
        return (cr + RAIL_GAP + (colR or 0))
    end
    return -(cl + RAIL_GAP + (colL or 0))
end

local function anchorRail(rail, frame)
    if type(rail.ClearAllPoints) ~= "function" then return end
    local dx = railOffset(frame)
    pcall(rail.ClearAllPoints, rail)
    if Skin.RailSide() == "right" then
        rail:SetPoint("TOPLEFT", frame, "TOPRIGHT", dx, PAD)
        rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", dx, -PAD)
    else
        rail:SetPoint("TOPRIGHT", frame, "TOPLEFT", dx, PAD)
        rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", dx, -PAD)
    end
end

local function ensureRail(frame, rec)
    local UI = UIKit()
    if not UI then return end
    if not cfg().iconRail then
        if rec.rail then rec.rail:Hide() end
        return
    end
    if rec.rail then
        rec.rail:Show()
        anchorRail(rec.rail, frame)   -- the footprint can move under us
        return
    end

    local rail = UI.FlatFrame(frame, "panel", "border")
    if type(rail.SetWidth) == "function" then rail:SetWidth(RAIL_WIDTH) end
    anchorRail(rail, frame)
    if rail.SetFrameLevel and frame.GetFrameLevel then
        local okL, lvl = pcall(frame.GetFrameLevel, frame)
        pcall(rail.SetFrameLevel, rail, (okL and lvl or 1))
    end

    local buttons = {}
    buttons.copy = railButton(rail, "C", function() Skin.OpenCopy(frame) end)
    buttons.copy._verb = Skin.OpenCopy
    buttons.config = railButton(rail, "*", function() ns.SlashDispatch("") end)
    buttons.config._verb = ns.SlashDispatch
    buttons.bottom = railButton(rail, "v", function()
        if type(frame.ScrollToBottom) == "function" then frame:ScrollToBottom() end
    end)
    buttons.bottom._verb = frame.ScrollToBottom
    -- skin v2.2: the client's own chat menu (languages, emotes, whisper
    -- targets) — the verb the hidden button column used to carry.
    buttons.menu = railButton(rail, "=", function() Skin.OpenChatMenu() end)
    buttons.menu._verb = Skin.OpenChatMenu

    for i, key in ipairs(RAIL_ORDER) do
        local btn = buttons[key]
        if i == 1 then
            btn:SetPoint("TOP", rail, "TOP", 0, -RAIL_GAP)
        else
            btn:SetPoint("TOP", buttons[RAIL_ORDER[i - 1]], "BOTTOM", 0, -RAIL_GAP)
        end
    end

    rec.rail = rail
    rec.railButtons = buttons
end

----------------------------------------------------------------------
-- THE ONE BOX (skin v3 features 9-12).
--
-- WHY THE CLIENT'S OWN TABS ARE RE-ANCHORED, NOT REPLACED. The two honest
-- shapes were: overlay our own buttons that call FCF_SelectDockFrame, or keep
-- the client's tab buttons and move them. The client's tab carries more verbs
-- than selection — OnDragStart tears the window out of the dock
-- (FCF_Tab_OnDragStart), the right-click menu is the client's own tab dropdown
-- (rename, lock, close, font size), and the dock manager tracks the tab
-- object itself. An overlay would have to hide the real tabs (whose geometry
-- the dock manager keeps rewriting anyway) and would silently drop
-- drag-to-undock and that whole menu. So: the skin already restyles these
-- exact buttons (font, ink, alpha, underline) and v3 extends that same
-- machinery with placement. Every click and drag semantic stays the client's,
-- byte for byte, and a disable puts every tab back where it was.
--
-- THE DOCK MANAGER GETS THE SECOND-TO-LAST WORD, we get the last: it re-lays
-- the tab row on its own beats (FCF_DockUpdate), so we re-anchor in-call from
-- a post-hook — the same posture the button column and the persistent edit box
-- take. Nothing is fought; the client's decision simply happens first.
--
-- ONE BACKDROP: rec.backdrop IS the chassis (see ensureBackdrop). A docked
-- window that is not its group's host hides its own, the entry bar's panel is
-- put away in unified mode, and the strip/rail is a BARE frame. The only
-- internal marks are hairlines in the border token.
----------------------------------------------------------------------

-- Which frame carries this window's box. A docked window's box belongs to the
-- DOCK, so the dock's primary hosts it — the same question MoveTarget already
-- answers for a drag, asked through the same seam so the two can never
-- disagree about what "this window's group" means.
function Skin.ChassisHost(frame, id)
    local host = Skin.MoveTarget(frame, id)
    return host or frame
end

-- Every window whose tab belongs in `host`'s strip, in the DOCK's own order
-- (Class 8: a strip anything iterates must be deterministic).
function Skin.GroupMembers(host)
    local out = {}
    local dock = _G.GeneralDockManager
    local primary = (type(dock) == "table" and type(dock.primary) == "table")
        and dock.primary or _G.DEFAULT_CHAT_FRAME
    if host == primary and type(dock) == "table" and type(dock.DOCKED_CHAT_FRAMES) == "table" then
        local list = dock.DOCKED_CHAT_FRAMES
        for i = 1, #list do
            local f = list[i]
            if type(f) == "table" and Skin.styled[f] then out[#out + 1] = f end
        end
    end
    if #out == 0 then out[1] = host end
    return out
end

-- A window the player has CLOSED has no box. Its chassis is a child of a
-- hidden frame in-game and would be invisible anyway; saying so out loud keeps
-- "how many boxes are there" an answerable question instead of a count of
-- every frame this module has ever dressed.
local function frameLive(frame)
    if type(frame) ~= "table" then return false end
    if type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok and not shown then return false end
    end
    return true
end

-- The styled windows that HOST a box, deduplicated, in style order.
function Skin.ChassisHosts()
    local out, seen = {}, {}
    for _, frame in ipairs(Skin.order) do
        if frameLive(frame) then
            local rec = Skin.styled[frame]
            local host = Skin.ChassisHost(frame, rec and rec.id)
            if type(host) == "table" and Skin.styled[host] and not seen[host]
               and frameLive(host) then
                seen[host] = true
                out[#out + 1] = host
            end
        end
    end
    return out
end

local function activeMember(members)
    local sel = selectedDockFrame()
    for _, f in ipairs(members) do
        if f == sel then return f end
    end
    if #members == 1 then return members[1] end   -- its own box, its own tab
    return nil
end

----------------------------------------------------------------------
-- The strip / rail: a BARE frame (no backdrop — the chassis is the only
-- background in the box) occupying one band of the chassis.
----------------------------------------------------------------------

local function ensureStrip(host, rec)
    if rec.strip then return rec.strip end
    if type(_G.CreateFrame) ~= "function" or not rec.backdrop then return nil end
    local strip = _G.CreateFrame("Frame", nil, rec.backdrop)
    if strip.SetFrameLevel and host.GetFrameLevel then
        local okL, lvl = pcall(host.GetFrameLevel, host)
        pcall(strip.SetFrameLevel, strip, (okL and lvl or 1))
    end
    rec.strip = strip
    return strip
end

local function anchorStrip(strip, rec)
    local bd = rec.backdrop
    if not bd or type(strip.ClearAllPoints) ~= "function" then return end
    local placement = Skin.TabPlacement()
    local entryTop = (cfg().editBox or "BOTTOM"):upper() == "TOP"
    pcall(strip.ClearAllPoints, strip)
    if placement == "left" then
        -- The rail is the chassis' whole left band: it runs beside the message
        -- text AND the entry bar, exactly as the mockup's variant does.
        strip:SetPoint("TOPLEFT", bd, "TOPLEFT", 0, 0)
        strip:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", 0, 0)
        if type(strip.SetWidth) == "function" then strip:SetWidth(TABRAIL_W) end
    elseif placement == "right" then
        strip:SetPoint("TOPRIGHT", bd, "TOPRIGHT", 0, 0)
        strip:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", 0, 0)
        if type(strip.SetWidth) == "function" then strip:SetWidth(TABRAIL_W) end
    else
        -- The top band — below the entry bar when the entry bar is the one on
        -- top, so the two never sit on the same pixels.
        local dy = entryTop and -(SEAM_W + EB_HEIGHT) or 0
        strip:SetPoint("TOPLEFT", bd, "TOPLEFT", 0, dy)
        strip:SetPoint("TOPRIGHT", bd, "TOPRIGHT", 0, dy)
        if type(strip.SetHeight) == "function" then strip:SetHeight(STRIP_H) end
    end
end

----------------------------------------------------------------------
-- The internal hairlines — EXACTLY the two the mockup draws, in --line-soft:
--
--   `.entry{border-top:1px solid var(--line-soft)}`  — the entry seam;
--   `.tabs-side{border-left:1px solid var(--line-soft)}` — the rail's inner edge.
--
-- AND NOT A THIRD. The mockup draws NOTHING between the tab strip and the
-- messages: `.tabs-top` is --panel, `.msgs` is --panel2, and the tone step is
-- the whole separation. skin v3 read the fusion as a hairline broken at the
-- active tab, which is why the shipped box has a line the mockup does not and
-- lacks the tone step the mockup does. The two-piece seam is retired: the
-- fusion is now literal (the active tab wears the surface's own fill), so
-- tabSeamA/B stay down under top tabs and tabSeamA carries the rail's edge.
----------------------------------------------------------------------

local function ensureSeam(rec, key)
    if rec[key] then return rec[key] end
    local UI, bd = UIKit(), rec.backdrop
    if not (UI and bd and type(bd.CreateTexture) == "function") then return nil end
    local tex = bd:CreateTexture(nil, "OVERLAY")
    UI.Skin(tex, function(self)
        if type(self.SetColorTexture) == "function" then
            self:SetColorTexture(Skin.Ink("lineSoft"))
        end
    end)
    tex:Hide()
    rec[key] = tex
    return tex
end

local function layoutSeams(host, rec, activeTab)
    local strip = rec.strip
    local seamA, seamB = ensureSeam(rec, "tabSeamA"), ensureSeam(rec, "tabSeamB")
    local entry = ensureSeam(rec, "entrySeam")
    if not (seamA and seamB and entry and strip) then return end
    local placement = Skin.TabPlacement()
    local entryTop = (cfg().editBox or "BOTTOM"):upper() == "TOP"
    for _, tex in ipairs({ seamA, seamB, entry }) do
        if type(tex.SetColorTexture) == "function" then tex:SetColorTexture(Skin.Ink("lineSoft")) end
    end

    -- The entry bar's hairline: the mockup's `border-top`, flush on the bar's
    -- own edge, spanning the chassis' inner width. Anchored to the CHASSIS on
    -- both points so it really does run the whole box (the message frame is
    -- narrower than the box by the message padding).
    local bd = rec.backdrop
    entry:ClearAllPoints()
    if type(entry.SetHeight) == "function" then entry:SetHeight(SEAM_W) end
    if entryTop then
        entry:SetPoint("TOPLEFT", bd, "TOPLEFT", CHASSIS_EDGE, -EB_HEIGHT)
        entry:SetPoint("TOPRIGHT", bd, "TOPRIGHT", -CHASSIS_EDGE, -EB_HEIGHT)
    else
        entry:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", CHASSIS_EDGE, EB_HEIGHT)
        entry:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -CHASSIS_EDGE, EB_HEIGHT)
    end
    entry:Show()

    seamA:ClearAllPoints()
    seamB:ClearAllPoints()
    seamB:Hide()
    if placement == "left" or placement == "right" then
        -- Continuous, on the rail's INNER side (`.tabs-side` border).
        if type(seamA.SetWidth) == "function" then seamA:SetWidth(SEAM_W) end
        local edge = (placement == "left") and "RIGHT" or "LEFT"
        seamA:SetPoint("TOP" .. edge, strip, "TOP" .. edge, 0, 0)
        seamA:SetPoint("BOTTOM" .. edge, strip, "BOTTOM" .. edge, 0, 0)
        seamA:Show()
        return
    end
    -- TOP TABS: the mockup draws no line here at all. The tone step between
    -- --panel (strip) and --panel2 (messages, and the active tab) is it.
    seamA:Hide()
end

----------------------------------------------------------------------
-- The active-tab EDGE BAR (rails). Its top-placement twin is the underline
-- that already exists; both wear the tab's own colour.
----------------------------------------------------------------------

function Skin.EnsureEdgeBar(tab, rec)
    if rec.edgebar then return rec.edgebar end
    local UI = UIKit()
    if not (UI and type(tab.CreateTexture) == "function") then return nil end
    local tex = tab:CreateTexture(nil, "OVERLAY")
    if type(tex.SetWidth) == "function" then tex:SetWidth(EDGEBAR_W) end
    UI.Skin(tex, function(self)
        if type(self.SetColorTexture) ~= "function" then return end
        local mc = rec.markColor
        if mc then self:SetColorTexture(mc[1], mc[2], mc[3])
        else self:SetColorTexture(UI.Color("accent")) end
    end)
    tex:Hide()
    rec.edgebar = tex
    return tex
end

local function anchorEdgeBar(bar, tab)
    if type(bar.ClearAllPoints) ~= "function" then return end
    -- The INNER side of the rail: the edge that faces the message text.
    local inner = (Skin.TabPlacement() == "left") and "RIGHT" or "LEFT"
    pcall(bar.ClearAllPoints, bar)
    bar:SetPoint("TOP" .. inner, tab, "TOP" .. inner, 0, -EDGEBAR_INSET)
    bar:SetPoint("BOTTOM" .. inner, tab, "BOTTOM" .. inner, 0, EDGEBAR_INSET)
end

-- The active mark shows when the tab ink feature is on, OR whenever the box is
-- on: a one-box layout with no marked tab would have nothing saying which
-- window you are looking at.
local function marksOn()
    return (cfg().channelTabs or Skin.Unified()) and true or false
end

function Skin.UpdateTabMarks(frame, rec, tab, isSel)
    if not (rec and tab) then return end
    local on   = marksOn()
    local rail = Skin.TabsOnRail()
    local ul = (on and not rail) and ensureUnderline(tab, rec) or rec.underline
    local bar = (on and rail) and Skin.EnsureEdgeBar(tab, rec) or rec.edgebar
    local mc = rec.markColor
    if ul then
        if mc and type(ul.SetColorTexture) == "function" then
            ul:SetColorTexture(mc[1], mc[2], mc[3])
        end
        if on and isSel and not rail then ul:Show() else ul:Hide() end
    end
    if bar then
        if mc and type(bar.SetColorTexture) == "function" then
            bar:SetColorTexture(mc[1], mc[2], mc[3])
        end
        if on and isSel and rail then anchorEdgeBar(bar, tab); bar:Show() else bar:Hide() end
    end
end

----------------------------------------------------------------------
-- LAYOUT: the client's own tab buttons, re-anchored into the strip or rail.
-- Their original points, size and justification are remembered on the first
-- move, so a disable — or turning the box off — hands every tab back exactly
-- as the client had it.
----------------------------------------------------------------------

local function rememberTab(rec, tab, text)
    if rec.tabPoints ~= nil then return end
    rec.tabPoints  = savePoints(tab) or false
    rec.tabSize    = { widgetNum(tab, "GetWidth"), widgetNum(tab, "GetHeight") }
    if text and type(text.GetJustifyH) == "function" then
        local ok, j = pcall(text.GetJustifyH, text)
        rec.tabJustify = (ok and type(j) == "string") and j or false
    end
    if text then rec.tabTextPoints = savePoints(text) or false end
end

-- What the unread pip costs this tab's width, through badges' OWN published
-- seam (the courtesy this file already pays it with Relayout). Zero when there
-- is no badge, when badges is off, or when it is not loaded at all.
local function pipExtent(frame)
    local B = ns.Badges
    if not (B and type(B.PipWidth) == "function") then return 0 end
    local ok, w = pcall(B.PipWidth, frame)
    return (ok and tonumber(w)) or 0
end

local function restoreTab(frame, rec)
    local tab, text = tabText(frame)
    if not tab or rec.tabPoints == nil then return end
    if rec.tabPoints then restorePoints(tab, rec.tabPoints) end
    -- The label's own anchors, but only if there were any to remember: handing
    -- back an EMPTY point list would clear the client's anchor and leave the
    -- label nowhere, which is worse than leaving ours in place.
    if text and type(rec.tabTextPoints) == "table" and #rec.tabTextPoints > 0 then
        restorePoints(text, rec.tabTextPoints)
    end
    rec.tabTextPoints = nil
    if rec.tabSize then
        if rec.tabSize[1] and type(tab.SetWidth) == "function" then
            pcall(tab.SetWidth, tab, rec.tabSize[1])
        end
        if rec.tabSize[2] and type(tab.SetHeight) == "function" then
            pcall(tab.SetHeight, tab, rec.tabSize[2])
        end
    end
    if text and rec.tabJustify and type(text.SetJustifyH) == "function" then
        pcall(text.SetJustifyH, text, rec.tabJustify)
    end
    rec.tabPoints, rec.tabSize, rec.tabJustify = nil, nil, nil
    rec.tabLaid = nil
end

function Skin.LayoutTabs()
    if not Skin.active then return 0 end
    -- Class 9: the pip's width feeds the tab's width, and badges is told to
    -- re-anchor at the end of this pass — the latch is what keeps a future
    -- badge beat that re-enters here from spinning.
    if Skin._tabLayoutDepth and Skin._tabLayoutDepth > 0 then return 0 end
    Skin._tabLayoutDepth = (Skin._tabLayoutDepth or 0) + 1
    local ok, res = pcall(Skin.__LayoutTabs)
    Skin._tabLayoutDepth = Skin._tabLayoutDepth - 1
    if not ok then
        if ns.RouteError then ns.RouteError(res) end
        return 0
    end
    return res or 0
end

function Skin.__LayoutTabs()
    local placement = Skin.TabPlacement()
    local rail = Skin.TabsOnRail()
    local moved = 0
    for _, host in ipairs(Skin.ChassisHosts()) do
        local hrec = Skin.styled[host]
        local strip = hrec and hrec.strip
        if strip then
            local members = Skin.GroupMembers(host)
            local prev
            for _, frame in ipairs(members) do
                local rec = Skin.styled[frame]
                local tab, text = tabText(frame)
                if rec and tab then
                    rememberTab(rec, tab, text)
                    pcall(tab.ClearAllPoints, tab)
                    local pip = pipExtent(frame)
                    if rail then
                        -- `.tabs-side{padding:8px 6px}` + `.stab{padding:7px 10px}`.
                        if type(tab.SetWidth) == "function" then
                            pcall(tab.SetWidth, tab, TABRAIL_W - 2 * RAIL_PAD_X)
                        end
                        if type(tab.SetHeight) == "function" then
                            pcall(tab.SetHeight, tab, TAB_ROW_H)
                        end
                        if prev then
                            tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TAB_GAP)
                        else
                            tab:SetPoint("TOPLEFT", strip, "TOPLEFT", RAIL_PAD_X, -RAIL_PAD_Y)
                        end
                        if text and type(text.SetJustifyH) == "function" then
                            pcall(text.SetJustifyH, text, "LEFT")
                        end
                        -- The label sits at the row's own left padding.
                        if text and type(text.ClearAllPoints) == "function" then
                            pcall(text.ClearAllPoints, text)
                            text:SetPoint("LEFT", tab, "LEFT", RAIL_TAB_PAD_X, 0)
                        end
                    else
                        -- `.tab{padding:5px 14px 6px}` around the label, plus the
                        -- pip's own room (`.tab .n` lives INSIDE the tab, after
                        -- the text, with a 6px gap) — so the tab is exactly as
                        -- wide as the mockup's content box.
                        local textW = (text and widgetNum(text, "GetStringWidth")) or 0
                        local w = textW + 2 * TAB_PAD_X + (pip > 0 and (PIP_GAP + pip) or 0)
                        if type(tab.SetWidth) == "function" then pcall(tab.SetWidth, tab, w) end
                        if type(tab.SetHeight) == "function" then pcall(tab.SetHeight, tab, TAB_H) end
                        if prev then
                            tab:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", TAB_GAP, 0)
                        else
                            tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", STRIP_PAD_X, 0)
                        end
                        if text and type(text.SetJustifyH) == "function" then
                            pcall(text.SetJustifyH, text, "LEFT")
                        end
                        -- Left-anchored at the tab's own padding: with the tab
                        -- sized to its content that is the same place CENTER
                        -- would put it when there is no pip, and the only place
                        -- it can be when there is one.
                        if text and type(text.ClearAllPoints) == "function" then
                            pcall(text.ClearAllPoints, text)
                            text:SetPoint("LEFT", tab, "LEFT", TAB_PAD_X, 0)
                        end
                    end
                    rec.tabLaid = placement    -- which shape this tab is wearing
                    rec.tabPip  = pip
                    prev = tab
                    moved = moved + 1
                end
            end
            local active = activeMember(members)
            local activeTab = active and (select(1, tabText(active))) or nil
            layoutSeams(host, hrec, activeTab)
        end
    end
    -- The badge anchors to the tab, and the tab just moved. Telling its OWNER
    -- through its own public beat is the same courtesy options.lua pays every
    -- module it writes a field for — badges is never reached into from here.
    local B = ns.Badges
    if B and type(B.Relayout) == "function" then pcall(B.Relayout) end
    return moved
end

-- THE BELL FROM BADGES. A pip appearing (or its digits growing) changes how
-- wide its tab has to be, and badges cannot know that — it owns the counter,
-- this file owns the tab. Same shape as NoteStampsChanged: no data, just "the
-- answer may have moved", and the latch above makes it safe to ring from
-- inside badges' own render.
function Skin.NoteBadgeChanged()
    if not (Skin.active and Skin.Unified()) then return false end
    Skin.LayoutTabs()
    return true
end

----------------------------------------------------------------------
-- THE COPY AFFORDANCE, in the box. Its Wave-1 corner (the window's top right,
-- out in the backdrop's pad) is INSIDE the tab strip once the box exists — so
-- in unified mode it parks at the strip's far end instead, which is the one
-- stretch of the strip the tabs never reach. Outside the box it keeps the
-- corner it has always had.
----------------------------------------------------------------------

function Skin.CopyButtonAnchor()
    if not Skin.Unified() then return "corner" end
    return Skin.TabsOnRail() and "railFoot" or "stripEnd"
end

local function anchorCopyButton(frame, rec)
    local btn = rec.copyBtn
    if not btn or type(btn.ClearAllPoints) ~= "function" then return nil end
    local where = Skin.CopyButtonAnchor()
    local strip
    if where ~= "corner" then
        local host = Skin.ChassisHost(frame, rec.id)
        local hrec = host and Skin.styled[host]
        strip = hrec and hrec.strip
    end
    if not strip then where = "corner" end
    pcall(btn.ClearAllPoints, btn)
    if where == "railFoot" then
        btn:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -RAIL_PAD_X, RAIL_PAD_Y)
    elseif where == "stripEnd" then
        -- The strip's far end, on the tab run's own baseline (the strip's top
        -- padding is the mockup's 6, so this sits level with the labels).
        btn:SetPoint("RIGHT", strip, "RIGHT", -STRIP_PAD_X, -STRIP_PAD_TOP / 2)
    else
        btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", PAD, PAD)
    end
    if btn._quiet then pcall(btn._quiet) end
    rec.copyAnchor = where
    return where
end

----------------------------------------------------------------------
-- THE BOX, per beat: anchor every chassis, place its strip and hairlines, and
-- make sure no window is wearing a SECOND background. Cheap and idempotent.
----------------------------------------------------------------------

function Skin.UpdateChassis()
    if not Skin.active then return 0 end
    -- Class 9: this runs from a post-hook on the client's OWN dock-layout beat,
    -- so it is armed against re-entry the same way the button column is. A
    -- SetPoint cannot call FCF_DockUpdate today; the latch is what keeps that
    -- from becoming a spin if a future client makes it so.
    if Skin._chassisDepth > 0 then return 0 end
    Skin._chassisDepth = Skin._chassisDepth + 1
    local ok, res = pcall(Skin.__UpdateChassis)
    Skin._chassisDepth = Skin._chassisDepth - 1
    if not ok then
        if ns.RouteError then ns.RouteError(res) end
        return 0
    end
    return res or 0
end

function Skin.__UpdateChassis()
    local unified = Skin.Unified()
    local hosts, isHost = Skin.ChassisHosts(), {}
    for _, h in ipairs(hosts) do isHost[h] = true end
    local n = 0
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec and rec.backdrop then
            paintChassis(rec.backdrop)
            anchorChassis(rec.backdrop, frame)
            layoutSurface(rec)
            if unified and not frameLive(frame) then
                rec.backdrop:Hide()          -- a closed window has no box
            elseif unified and not isHost[frame] then
                -- A docked window shares its group's box. A second backdrop
                -- behind it is exactly the thing the design contract forbids.
                rec.backdrop:Hide()
            else
                rec.backdrop:Show()
                n = n + 1
            end
        end
    end
    for _, host in ipairs(hosts) do
        local rec = Skin.styled[host]
        if rec then
            if unified then
                local strip = ensureStrip(host, rec)
                if strip then anchorStrip(strip, rec); strip:Show() end
            elseif rec.strip then
                rec.strip:Hide()
                for _, key in ipairs({ "tabSeamA", "tabSeamB", "entrySeam" }) do
                    if rec[key] then rec[key]:Hide() end
                end
            end
        end
    end
    if unified then
        Skin.LayoutTabs()
    else
        for _, frame in ipairs(Skin.order) do
            local rec = Skin.styled[frame]
            if rec and rec.tabPoints ~= nil then restoreTab(frame, rec) end
        end
        local B = ns.Badges
        if B and type(B.Relayout) == "function" then pcall(B.Relayout) end
    end
    -- The copy affordance last: in the box it parks at the far end of the tab
    -- strip (dead space there, and the only corner the strip does not want),
    -- which is a placement that only exists once the strip has been laid out.
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec and rec.copyBtn then anchorCopyButton(frame, rec) end
    end
    return n
end

----------------------------------------------------------------------
-- Style / restore one window.
----------------------------------------------------------------------

function Skin.StyleWindow(frame, id)
    if not frame then return end
    local rec = Skin.styled[frame]
    if not rec then
        rec = { id = id }
        Skin.styled[frame] = rec
        Skin.order[#Skin.order + 1] = frame
    end
    -- ── RETIRED WHILE THE VIEW PAINTS (D2 revision) ──────────────────────
    -- Everything between here and the next marker is a CLIENT-FRAME RESTYLE:
    -- the stock-art strip, the chassis-on-a-client-frame, the tab restyle,
    -- client typography, the fading knob and the client's own edit-box dress.
    -- view.lua owns those pixels now (and hosts that edit box), so with the
    -- view up none of it runs — not gated per-call inside each helper, but
    -- refused here at the one place they are all reached from.
    local retired = Skin.ViewOwnsPixels()
    if not retired then
        stripStock(frame, rec)
        ensureBackdrop(frame, rec)
        styleTab(frame, rec)
        applyFrameFont(frame, id)
        Skin.ApplyFading(frame)
        if not isCombatLog(frame, id) then
            styleEditBox(frame, rec)
            ensureEditBoxRig(frame, rec)
            local eb = editBoxOf(frame)
            if eb then
                Skin.ColorEditBoxHeader(eb)
                Skin.AliasEditBoxHeader(eb)
                Skin.KeepEditBoxShown(eb)
            end
        end
        ensureCopyButton(frame, rec)
    end
    -- ── SURVIVES: the movement / capture / clamp / column layer ──────────
    -- The column goes down BEFORE the rail is placed: the rail's own offset
    -- reads the footprint the column leaves behind (v2.2).
    ensureButtonColumnRig(frame, rec)
    Skin.SyncButtonColumn(frame)
    ensureRail(frame, rec)
    ensureMoveRig(frame, rec)
    Skin.LoosenClamp(frame, rec)
    if not retired then
        -- The box owns its own opacity: the client's tab fade is refused here
        -- and re-refused on every cheap beat and every client verb. RETIRED
        -- while the view paints — our tabs are not in the client's fade walk
        -- at all, so there is no last word to keep taking.
        Skin.KeepOpaque(frame, rec)
        Skin.UpdateDivider(frame)
    end
end

function Skin.StyleAll()
    for id = 1, numWindows() do
        local frame = _G["ChatFrame" .. id]
        if frame and windowEligible(id) then
            Skin.StyleWindow(frame, id)
        end
    end
    if Skin.ViewOwnsPixels() then return end
    -- The box is assembled AFTER every window is dressed: which frame hosts a
    -- chassis depends on the whole dock, not on any one window. RETIRED while
    -- the view paints (there is no skin-over box then).
    Skin.UpdateChassis()
    Skin.UpdateTabColors()
end

-- PUBLISHED as Skin.RestoreDress (see the retirement gate near the top): the
-- view calls it to hand the client's frames back before it starts painting,
-- which is the same restore OnDisable performs. One implementation.
local function restoreWindow(frame, rec)
    restoreStock(frame, rec)
    -- The tab's alpha fields go back exactly as we found them (nil included)
    -- and the CLIENT's own updater is re-run, so a disable hands the fade
    -- decision back rather than freezing a number we happened to like.
    Skin.RestoreOpacity(frame, rec)
    -- Movability and the clamp rect go back to whatever the client had: with
    -- SetMovable restored, our (permanent) drag-script hooks are inert bodies
    -- over a frame the client alone decides about.
    if rec.wasMovable ~= nil and type(frame.SetMovable) == "function" then
        pcall(frame.SetMovable, frame, rec.wasMovable)
    end
    if rec.clampInsets and type(frame.SetClampRectInsets) == "function" then
        local icl = _G.InCombatLockdown
        local inCombat = false
        if type(icl) == "function" then
            local okC, v = pcall(icl)
            inCombat = okC and v and true or false
        end
        if not inCombat then
            pcall(frame.SetClampRectInsets, frame, rec.clampInsets[1], rec.clampInsets[2],
                  rec.clampInsets[3], rec.clampInsets[4])
        end
    end
    Skin._clampPending[frame] = nil
    -- The client's button column comes back exactly as we found it (and the
    -- client re-decides its side), so a disable leaves no trace of v2.2.
    Skin.RestoreButtonColumn(frame, rec)
    if rec.backdrop then rec.backdrop:Hide() end
    if rec.copyBtn then rec.copyBtn:Hide() end
    if rec.rail then rec.rail:Hide() end
    if rec.underline then rec.underline:Hide() end
    if rec.divider then rec.divider:Hide() end
    -- skin v3: the box goes away, and every tab we moved goes back exactly
    -- where the client had it (points, size and justification all remembered
    -- on the first move).
    if rec.strip then rec.strip:Hide() end
    for _, key in ipairs({ "tabSeamA", "tabSeamB", "entrySeam", "edgebar",
                           "surface", "tabFill", "tabHover" }) do
        if rec[key] then rec[key]:Hide() end
    end
    -- The client's own tab art, and the row rhythm, come back exactly.
    restoreTabArt((select(1, tabText(frame))), rec)
    if rec.origSpacing ~= nil and type(frame.SetSpacing) == "function" then
        pcall(frame.SetSpacing, frame, tonumber(rec.origSpacing) or 0)
        rec.origSpacing = nil
    end
    restoreTab(frame, rec)
    restoreEditBox(frame, rec)
    if rec.origFont and type(frame.SetFont) == "function" then
        pcall(frame.SetFont, frame, rec.origFont[1], rec.origFont[2], rec.origFont[3])
    end
    local _, tabLabelFS = tabText(frame)
    if rec.origTabColor and tabLabelFS and type(tabLabelFS.SetTextColor) == "function" then
        tabLabelFS:SetTextColor(rec.origTabColor[1], rec.origTabColor[2], rec.origTabColor[3])
    end
    -- An aliased tab label is the client's text again the moment we leave.
    if rec.tabLabel ~= nil then
        if type(rec.origTabText) == "string" and tabLabelFS and type(tabLabelFS.SetText) == "function" then
            pcall(tabLabelFS.SetText, tabLabelFS, rec.origTabText)
        end
        rec.tabLabel = nil
        rec.origTabText = nil
    end
end

Skin.RestoreDress = restoreWindow

-- The v2 re-evaluation beat: everything whose answer can change without a
-- restyle — the channel inks, the active underline, the rail's config gate and
-- the divider's stamps-are-on gate. Cheap and idempotent; called from the
-- selection hook, the theme/font hooks, UPDATE_CHAT_COLOR and CVAR_UPDATE.
function Skin.Refresh()
    if not Skin.active then return end
    -- RETIRED while the view paints: every branch below dresses a client
    -- frame. The movement layer needs no beat (it is script-driven) and the
    -- column stays down because the view hid it with the window.
    if Skin.ViewOwnsPixels() then return end
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec then
            -- The column first (the rail's placement depends on its
            -- footprint), and free on a beat where it is already down.
            Skin.SyncButtonColumn(frame)
            ensureRail(frame, rec)
            -- The client re-clamps periodically (the survey's frame-treatment
            -- note), so the loosened insets are re-asserted on every cheap
            -- re-evaluation beat instead of once at style time.
            Skin.LoosenClamp(frame, rec)
            -- The box's own fading rule is re-asserted on the cheap beat: the
            -- client re-applies fading on its own window updates, and the
            -- unified box must never come back with fading on behind it.
            Skin.ApplyFading(frame)
            -- …and the OTHER fade, the one SetFading has nothing to do with:
            -- the client's own tab/frame alpha (skin v3.1).
            Skin.KeepOpaque(frame, rec)
        end
    end
    -- The box before the inks: the strip has to exist and the tabs have to be
    -- in it before the active mark can be placed on one of them.
    Skin.UpdateChassis()
    -- NOT here: the persistent edit box. Refresh is the cheap re-evaluation
    -- beat (selection, recolor, CVar), and re-running the client's header pass
    -- on it would both cost a client call per beat and overwrite the ink this
    -- very beat exists to apply. Visibility is restored where it is actually
    -- lost: the deactivate post-hook, the OnHide watch, and style time.
    Skin.UpdateTabColors()
    Skin.UpdateDividers()
end

-- Re-apply everything that is not covered by UI.Skin's automatic re-color
-- (fonts and tab state read tokens imperatively).
function Skin.Reskin()
    if not Skin.active then return end
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        applyFrameFont(frame, rec and rec.id)
    end
    Skin.RecolorEditBoxHeaders()
    Skin.Refresh()
end

----------------------------------------------------------------------
-- Lifecycle. hooksecurefunc is permanent, so both installs happen exactly
-- once (first enable) and every body gates on Skin.active — a disabled skin
-- is behaviorally absent even though the hook shell remains.
----------------------------------------------------------------------

local function installHooks()
    if Skin.hooked then return end
    Skin.hooked = true
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return end
    -- Temporary windows (whisper pop-outs) appear past index 10; style them as
    -- they open so they wear the suite look from their first frame.
    if type(_G.FCF_OpenTemporaryWindow) == "function" then
        hook("FCF_OpenTemporaryWindow", function()
            if not Skin.active then return end
            -- The new frame is the client's newest temporary; scan past the
            -- permanent ten for any eligible frame we have not styled.
            for id = numWindows() + 1, 50 do
                local frame = _G["ChatFrame" .. id]
                if frame and not Skin.styled[frame] and frame.IsShown and frame:IsShown() then
                    Skin.StyleWindow(frame, id)
                end
            end
            Skin.Refresh()
        end)
    end
    -- Dock selection changes recolor the tab row (selected = full-strength ink
    -- plus the accent underline).
    if type(_G.FCF_SelectDockFrame) == "function" then
        hook("FCF_SelectDockFrame", function()
            if not Skin.active then return end
            Skin.Refresh()
        end)
    end
    -- The client's own edit-box header beat: every sticky change, tab-cycle and
    -- /channel switch lands here, so the prefix ink follows without us tracking
    -- a single piece of channel state (skin v2 feature 3).
    if type(_G.ChatEdit_UpdateHeader) == "function" then
        hook("ChatEdit_UpdateHeader", function(editBox)
            if not Skin.active then return end
            Skin.ColorEditBoxHeader(editBox)
            -- The alias goes on AFTER the client wrote its own text, in the
            -- same call — the post-hook posture the whole file uses.
            Skin.AliasEditBoxHeader(editBox)
        end)
    end
    -- The persistent edit box's PRIMARY seam: the client deactivates (Escape,
    -- a sent line, a click away) and makes its own hide decision; we get the
    -- last word, synchronously, inside the same call.
    if type(_G.ChatEdit_DeactivateChat) == "function" then
        hook("ChatEdit_DeactivateChat", function(editBox)
            if not Skin.EditBoxPersistent() then return end
            Skin.KeepEditBoxShown(editBox)
        end)
    end
    -- The button column's PRIMARY seam (skin v2.2): the client re-decides which
    -- side the column belongs on — and re-shows it — on both of these. We take
    -- it back down synchronously inside the same call, so there is no beat
    -- where the column is visibly back. The side decision itself is never
    -- fought: with the option off these bodies do nothing at all.
    local function reHide(chatFrame)
        if not Skin.HideButtonColumn() then return end
        if type(chatFrame) ~= "table" or not Skin.styled[chatFrame] then return end
        Skin.KeepButtonColumnHidden(chatFrame)
    end
    if type(_G.FCF_SetButtonSide) == "function" then
        hook("FCF_SetButtonSide", function(chatFrame)
            reHide(chatFrame)
            -- …and the clamp insets the side decision just rewrote (bounce
            -- suspect b: this is the beat that shoves a flush window inward).
            Skin.ReClamp(chatFrame)
        end)
    end
    if type(_G.FCF_UpdateButtonSide) == "function" then
        hook("FCF_UpdateButtonSide", function(chatFrame)
            reHide(chatFrame)
            Skin.ReClamp(chatFrame)
        end)
    end
    -- The client's own WINDOW-UPDATE beat: it restores the window's position
    -- from the per-character store and re-runs the side decision, so both the
    -- clamp and the tab's alpha are the client's again by the time it returns.
    -- We take both back, in-call.
    if type(_G.FloatingChatFrame_Update) == "function" then
        hook("FloatingChatFrame_Update", function(id)
            if not Skin.active then return end
            local frame = _G["ChatFrame" .. tostring(id)]
            if not frame then return end
            Skin.ReClamp(frame)
            Skin.KeepOpaque(frame)
        end)
    end
    -- THE TAB-ALPHA SEAM (skin v3.1). Three client verbs decide a tab's
    -- opacity; each gets the same treatment — the client makes its decision,
    -- we take the last word synchronously inside the same call, and only when
    -- the client actually moved something.
    if type(_G.FCFTab_UpdateAlpha) == "function" then
        hook("FCFTab_UpdateAlpha", function(a)
            if not Skin.NoAlphaFade() then return end
            local frame = alphaSubject(a)
            if frame then Skin.KeepOpaque(frame) else Skin.KeepAllOpaque() end
        end)
    end
    if type(_G.FCF_FadeOutChatFrame) == "function" then
        hook("FCF_FadeOutChatFrame", function(a)
            if not Skin.NoAlphaFade() then return end
            local frame = alphaSubject(a)
            if frame then Skin.KeepOpaque(frame) else Skin.KeepAllOpaque() end
        end)
    end
    if type(_G.FCF_FadeInChatFrame) == "function" then
        hook("FCF_FadeInChatFrame", function(a)
            if not Skin.NoAlphaFade() then return end
            local frame = alphaSubject(a)
            if frame then Skin.KeepOpaque(frame) else Skin.KeepAllOpaque() end
        end)
    end
    -- skin v3: the DOCK MANAGER re-lays the tab row on its own beat, and the
    -- box's strip is where those tabs belong. Same posture as the column: the
    -- client makes its layout decision, then we re-anchor synchronously inside
    -- the same call, so there is no frame where a tab is back in the client's
    -- row. With the box off this body does nothing at all.
    if type(_G.FCF_DockUpdate) == "function" then
        hook("FCF_DockUpdate", function()
            if not Skin.active then return end
            -- The dock beat re-runs every window's side decision, so every
            -- window's clamp was just rewritten: take them all back first.
            Skin.ReClampAll()
            if not Skin.Unified() then return end
            Skin.UpdateChassis()
            Skin.KeepAllOpaque()
        end)
    end
end

-- Our OWN gated listeners (never coupled to another module's subscription).
Skin._colorHandler = function()
    if not Skin.active then return end
    -- The player (or the reconciler) recolored a chat type: every tab ink and
    -- edit-box prefix that derives from the client table re-reads it now.
    Skin.Refresh()
    Skin.RecolorEditBoxHeaders()
end

-- The clamp write is protected in combat, so a refusal is replayed the moment
-- combat drops (never dropped on the floor, never retried in a spin).
Skin._regenHandler = function()
    if not Skin.active then return end
    Skin.DrainPendingClamps()
end

Skin._cvarHandler = function(event, name)
    -- showTimestamps decides whether stamps.lua suspends, which decides whether
    -- the divider has anything to divide. stamps.lua subscribes to the SAME
    -- event and there is no defined order between two subscribers (Class 2), so
    -- the re-evaluation is deferred one beat: by then the sibling's suspend
    -- flag is settled, whichever handler ran first.
    if not Skin.active then return end
    if name ~= "showTimestamps" then return end
    if Skin._dividerQueued then return end
    local CT = _G.C_Timer
    if not (CT and type(CT.After) == "function") then
        Skin.UpdateDividers()
        return
    end
    Skin._dividerQueued = true
    CT.After(0, function()
        Skin._dividerQueued = false
        if Skin.active then Skin.UpdateDividers() end
    end)
end

function Skin.OnEnable()
    Skin.active = true
    installHooks()
    -- Theme/font reactivity: registered once, bodies gate on active. Core's
    -- UI.Skin covers the backdrop colors; this covers fonts + tab ink.
    local UI = UIKit()
    if UI and not Skin.reskinHooked then
        Skin.reskinHooked = true
        if UI.OnThemeChanged then UI.OnThemeChanged(function() Skin.Reskin() end) end
        if UI.OnFontChanged then UI.OnFontChanged(function() Skin.Reskin() end) end
    end
    ns:RegisterEvent("UPDATE_CHAT_COLOR", Skin._colorHandler)
    ns:RegisterEvent("CVAR_UPDATE", Skin._cvarHandler)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", Skin._regenHandler)
    Skin.StyleAll()
    -- THE DIVIDER'S LOGIN BEAT (root cause 2, the ordering half). Module enable
    -- order is file order, so whether stamps had come up before us decided
    -- whether the divider was ever drawn. One deferred re-ask makes the answer
    -- order-independent; without C_Timer (headless) StyleAll's own pass stands.
    local CT = _G.C_Timer
    if CT and type(CT.After) == "function" then
        CT.After(0, function() if Skin.active then Skin.UpdateDividers() end end)
    end
end

function Skin.OnDisable()
    Skin.active = false
    Skin.moveMode = false
    Skin._moving = nil
    ns:UnregisterEvent("UPDATE_CHAT_COLOR", Skin._colorHandler)
    ns:UnregisterEvent("CVAR_UPDATE", Skin._cvarHandler)
    ns:UnregisterEvent("PLAYER_REGEN_ENABLED", Skin._regenHandler)
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        if rec then restoreWindow(frame, rec) end
    end
    if copyWindow then copyWindow:Hide() end
end

ns.RegisterModule("skin", Skin)

----------------------------------------------------------------------
-- THE LOCK VERBS. Now a PERSISTED, SYNCED pair rather than the old
-- session-scoped plain-drag toggle: the owner asked for "a way to lock /
-- unlock the positioning", and a lock that forgot itself at logout would not
-- be that. The state rides the mesh with the position it governs.
----------------------------------------------------------------------

ns.RegisterCommand("unlock", "unlock the chat box: drag to move, corner grips to resize", function()
    Skin.SetLocked(false)
    ns:Print("chat UNLOCKED. Drag the tab strip (or ALT-drag anywhere) to move it; drag any "
          .. "of the four corner grips to resize it.")
    ns:Print("  (this rides your shared chat configuration, so every character is unlocked too.)")
end)

ns.RegisterCommand("lock", "lock the chat box: no dragging, no resizing", function()
    Skin.SetLocked(true)
    ns:Print("chat LOCKED. The box will not move or resize, and the corner grips are gone. "
          .. "/dchat unlock when you want to move it.")
end)

-- …and the state itself is on the command list, so "am I locked right now" is
-- answered by the same thing that lists the verbs.
if type(ns.RegisterHelpNote) == "function" then
    ns.RegisterHelpNote(function()
        return "  chat is currently " .. (Skin.Locked() and "LOCKED" or "UNLOCKED")
            .. " (/dchat lock, /dchat unlock)"
    end)
end

ns.RegisterDebugCommand("skin", "skin state: styled windows, config, tab inks", function()
    ns:Print(("skin: %s, %d window(s) styled"):format(
        Skin.active and "active" or "inactive", #Skin.order))
    local c = cfg()
    ns:Print(("  fading=%s fadeTime=%s editBox=%s copyButton=%s"):format(
        tostring(c.fading), tostring(c.fadeTime), tostring(c.editBox), tostring(c.copyButton)))
    ns:Print(("  channelTabs=%s stampDivider=%s editBoxChannelColor=%s iconRail=%s"):format(
        tostring(c.channelTabs), tostring(c.stampDivider),
        tostring(c.editBoxChannelColor), tostring(c.iconRail)))
    ns:Print(("  altDragMove=%s persistentEditBox=%s unclampWindows=%s | moveMode=%s, %d move(s)")
        :format(tostring(c.altDragMove), tostring(c.persistentEditBox),
                tostring(c.unclampWindows), tostring(Skin.moveMode), Skin.moves))
    -- skin v3.1: the three answers a "it faded / it bounced / it did not snap"
    -- report needs, in one line each.
    ns:Print(("  snapToEdges=%s (threshold %d px) | %d snap(s), last: %s/%s")
        :format(tostring(c.snapToEdges ~= false), Skin.SNAP_THRESHOLD, Skin.snaps,
                tostring(Skin.lastSnap and Skin.lastSnap.x or "none"),
                tostring(Skin.lastSnap and Skin.lastSnap.y or "none")))
    ns:Print(("  moves committed to the client's own store: %d | tab-alpha pins taken back: %d")
        :format(Skin.moveCommits, Skin.alphaPins))
    local menuKind = Skin.ChatMenuSeam()
    ns:Print(("  column: %d disable(s), %d widget event-drop(s) (OFF needs /reload for events)")
        :format(Skin.columnDisables, Skin.columnEventsDropped))
    ns:Print(("  hideButtonColumn=%s | %d column hide(s), chat menu seam '%s', %d open(s)")
        :format(tostring(c.hideButtonColumn), Skin.columnHides,
                tostring(menuKind or "none"), Skin.menuOpens))
    ns:Print(("  tab dim factor %.3f (token-derived), stamps showing: %s, stamp sample '%s'")
        :format(Skin.DimFactor(), tostring(Skin.StampsShowing()), Skin.StampSample()))
    local cl, cr, ctp, cb = Skin.ChassisInsets()
    ns:Print(("  one box: unifiedChassis=%s tabs=%s (synced), icon rail on the %s edge")
        :format(tostring(c.unifiedChassis), Skin.TabPlacement(), Skin.RailSide()))
    ns:Print(("  chassis insets l/r/t/b = %d/%d/%d/%d, fading effective: %s (stored %s)")
        :format(cl, cr, ctp, cb, tostring(Skin.FadingEffective()), tostring(c.fading)))
    -- THE MOCKUP CONTRACT, readable in-game: the numbers and the palette the
    -- box is drawn from, so "does it match the mockup" is a diff, not a debate.
    ns:Print(("  mockup contract: strip %d (pad %d/%d), tab %d (pad %d/%d/%d), entry %d (pad %d/%d)")
        :format(STRIP_H, STRIP_PAD_TOP, STRIP_PAD_X, TAB_H,
                TAB_PAD_TOP, TAB_PAD_X, TAB_PAD_BOT, EB_HEIGHT, EB_PAD_Y, EB_PAD_X))
    ns:Print(("    messages pad %d/%d/%d, row spacing %d, rail %d (pad %d/%d, row %d)")
        :format(MSG_PAD_TOP, MSG_PAD_X, MSG_PAD_BOT, ROW_SPACING,
                TABRAIL_W, RAIL_PAD_Y, RAIL_PAD_X, TAB_ROW_H))
    local names = { "panel", "panel2", "line", "lineSoft", "accent", "text", "muted", "faint" }
    local swatch = {}
    for _, n in ipairs(names) do
        local r, g, b = Skin.Ink(n)
        swatch[#swatch + 1] = ("%s=%02x%02x%02x"):format(n,
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    end
    ns:Print("    palette: " .. table.concat(swatch, " "))
    ns:Print(("    divider x=%s (stamp '%s'), corners: SQUARE (client limit: no rounded backdrop edge)")
        :format(tostring((Skin.styled[_G.ChatFrame1] or {}).dividerX or "-"), Skin.StampBody()))
    for _, host in ipairs(Skin.ChassisHosts()) do
        local names = {}
        for _, f in ipairs(Skin.GroupMembers(host)) do
            names[#names + 1] = tostring(f.GetName and f:GetName() or "?")
        end
        ns:Print(("  box on %s: %s"):format(
            tostring(host.GetName and host:GetName() or "?"), table.concat(names, ", ")))
    end
    for _, frame in ipairs(Skin.order) do
        local rec = Skin.styled[frame]
        local entry, source = Skin.WindowRouting(rec and rec.id)
        local kind, value = Skin.DominantChannel(entry, isCombatLog(frame, rec and rec.id))
        ns:Print(("  %s: ink=%s dominant=%s%s routing=%s tabColor=%s"):format(
            tostring(frame.GetName and frame:GetName() or "?"),
            tostring(rec and rec.inkSource or "-"),
            tostring(kind or "none"),
            value and (" " .. tostring(value)) or "",
            tostring(source or "none"),
            tostring(Skin.TabColorSpec(rec and rec.id) or "-")))
    end
end)

----------------------------------------------------------------------
-- Self-tests (suite "skin").
--
-- The pure parts (defang, extraction shape) always run. The live parts drive
-- the module against the harness's unkind chat simulator and its Core stub;
-- in-game (no sim) they are skipped rather than faked.
----------------------------------------------------------------------

local function testDefang(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local D = Skin.DefangLine
    ck(D("plain text") == "plain text", "plain text passes through")
    ck(D("|cffa335ee|Hitem:19019|h[Thunderfury]|h|r is mine")
        == "[Thunderfury] is mine", "decorated item link defangs to display text")
    ck(D("see |Hurl:http://x.io|h[http://x.io]|h now")
        == "see [http://x.io] now", "url pseudo-link defangs to display text")
    ck(D("a |Hitem:1|h[A]|h and |Hitem:2|h[B]|h")
        == "a [A] and [B]", "two links on one line defang independently")
    ck(D("from |KS42|k today") == "from ??? today", "|K protected span becomes ???")
    ck(D("kill |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t now")
        == "kill {rt8} now", "raid icon texture reverse-maps to {rt8}")
    ck(D("x |TInterface\\Icons\\Foo:16|t y") == "x  y", "other textures drop")
    ck(D("|cff00ff00green|r end") == "green end", "color escapes strip")
    ck(D("50%||50%") == "50%|50%", "escaped pipes un-escape")
    ck(D(nil) == "", "non-string input is safe")
end

-- The dominance rule, PURE (no client, no sim): routing in, one identity or
-- none out. This is the matrix the headline feature stands on.
local function testDominance(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local D = Skin.DominantChannel

    local kind, value = D({ groups = { "GUILD" }, channels = {} }, false)
    ck(kind == "type" and value == "GUILD", "dominance: a GUILD-only window is a guild window")

    kind, value = D({ groups = { "GUILD", "OFFICER" }, channels = {} }, false)
    ck(kind == "type" and value == "GUILD",
        "dominance: OFFICER folds onto its family head, so GUILD+OFFICER is still guild")

    kind, value = D({ groups = { "RAID", "RAID_LEADER", "RAID_WARNING" }, channels = {} }, false)
    ck(kind == "type" and value == "RAID", "dominance: the raid family folds onto RAID")

    kind = D({ groups = { "GUILD", "PARTY" }, channels = {} }, false)
    ck(kind == nil, "dominance: two real identities = NO dominant (the fallback)")

    -- The client's default window: a dozen groups. No dominant, by design.
    kind = D({ groups = { "SAY", "YELL", "EMOTE", "GUILD", "OFFICER", "WHISPER",
                          "PARTY", "RAID", "RAID_WARNING", "SYSTEM", "CHANNEL" },
               channels = { "General" } }, false)
    ck(kind == nil, "dominance: the default window has no dominant channel (fallback pinned)")

    kind, value = D({ groups = { "GUILD", "SYSTEM", "LOOT", "SKILL", "COMBAT_XP_GAIN" },
                      channels = {} }, false)
    ck(kind == "type" and value == "GUILD",
        "dominance: ambient groups (system/loot/skill/xp) never establish identity")

    kind = D({ groups = { "SYSTEM", "LOOT" }, channels = {} }, false)
    ck(kind == nil, "dominance: an ambient-only window has no identity at all")

    kind, value = D({ groups = { "CHANNEL" }, channels = { "World" } }, false)
    ck(kind == "channel" and value == "World",
        "dominance: the CHANNEL group is a routing switch; the NAME carries identity")

    kind = D({ groups = { "CHANNEL" }, channels = { "World", "Trade" } }, false)
    ck(kind == nil, "dominance: two named channels = no dominant")

    kind = D({ groups = { "GUILD" }, channels = { "World" } }, false)
    ck(kind == nil, "dominance: a group AND a channel are two identities")

    kind, value = D({ groups = { "CHANNEL" }, channels = {} }, false)
    ck(kind == nil, "dominance: routing the CHANNEL group with no channels is not an identity")

    ck(D({}, false) == nil, "dominance: an empty entry has no dominant")
    ck(D(nil, false) == nil, "dominance: no routing at all is safe")
    ck(D({ groups = { "GUILD" } }, true) == "combatlog",
        "dominance: the combat log wins over any routing (its own muted treatment)")
    ck(D({ groups = { "guild" }, channels = {} }, false) == "type",
        "dominance: group names are case-normalized")

    -- Duplicate routing entries are ONE identity, not two.
    kind, value = D({ groups = { "GUILD", "GUILD" }, channels = { "World", "world" } }, false)
    ck(kind == nil, "dominance: duplicates collapse (guild + one channel is still two)")
    kind, value = D({ groups = {}, channels = { "World", "world" } }, false)
    ck(kind == "channel", "dominance: the same channel named twice is ONE identity")
end

local function testCopyAndSkin(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI  = UIKit()
    if not (Sim and UI) then
        if verbose then ns:Print("  skin: live checks skipped (no simulator)") end
        return
    end

    -- skin v3: THIS suite is the v2 suite, and it stays that way. The ONE BOX
    -- has its own suite below (V1..V9) that turns the gate on deliberately;
    -- here the gate is parked OFF so every assertion below keeps meaning "the
    -- v2 treatment", which is exactly what OFF has to go on meaning.
    local savedUnified = ns.db.skin.unifiedChassis
    ns.db.skin.unifiedChassis = false

    -- ── Phase 0: INERTNESS. The harness loaded us with skin disabled and drove
    -- a full login. Nothing may have been touched. ─────────────────────────────
    ck(Skin.active == false, "phase 0: module inactive after disabled login")
    ck(#Skin.order == 0, "phase 0: zero windows styled while disabled")
    ck(Skin.hooked == false, "phase 0: zero hooksecurefunc installs while disabled (the pin)")
    ck(Sim.CallCount("hooksecurefunc") == 0, "phase 0: sim counted zero hook installs")
    ck(Sim.CallCount("SetFading") == 0, "phase 0: no window's fading was touched")
    -- Sibling modules legitimately hold their own subscriptions, so the pin on
    -- OUR listeners is the DELTA against the world our predecessors left.
    local cf1 = _G.ChatFrame1
    local colorSubsBase = ns.EventHandlerCount("UPDATE_CHAT_COLOR")
    local cvarSubsBase  = ns.EventHandlerCount("CVAR_UPDATE")

    -- The suites before us authored windows and config entries for their own
    -- legs. The tab-ink assertions below are about ROUTING, so this suite puts
    -- the world back to the client's stock ten-window layout and mirrors it
    -- into the config; the config branch is handed back at the end.
    local C = ns.Config
    local cfgStore = C and C.Get() or nil
    local savedCfgWindows = cfgStore and cfgStore.windows or nil
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    if cfgStore then
        cfgStore.windows = {}
        for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
            cfgStore.windows[id] = C.CaptureWindow(id)
        end
    end
    _G.FCF_SelectDockFrame(_G.ChatFrame1)

    -- ── Phase 1: enable — every eligible window wears the theme. ──────────────
    ns.SetModuleEnabled("skin", true)
    ck(Skin.active == true, "phase 1: enable activates the module")
    local styledCount = 0
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. id]
        local eligible = select(1, windowEligible(id))
        if frame and eligible then
            styledCount = styledCount + 1
            local rec = Skin.styled[frame]
            ck(rec ~= nil, "phase 1: eligible window " .. id .. " styled")
            if rec and rec.backdrop then
                local bg = rec.backdrop._backdropColor
                local pr, pg, pb = UI.Color("panel")
                ck(bg and math.abs(bg[1] - pr) < 1e-6 and math.abs(bg[2] - pg) < 1e-6
                    and math.abs(bg[3] - pb) < 1e-6,
                    "phase 1: window " .. id .. " backdrop fill is the panel TOKEN (not hardcoded)")
                local bc = rec.backdrop._backdropBorderColor
                local br, bgc, bb = UI.Color("border")
                ck(bc and math.abs(bc[1] - br) < 1e-6 and math.abs(bc[2] - bgc) < 1e-6
                    and math.abs(bc[3] - bb) < 1e-6,
                    "phase 1: window " .. id .. " border is the border TOKEN")
            end
            local face = frame._font and frame._font[1]
            ck(face == UI.FontFile(), "phase 1: window " .. id .. " text face is Core's picked face")
            ck(frame._fading == true, "phase 1: window " .. id .. " fading on per config")
            ck(frame._timeVisible == (ns.db.skin.fadeTime or 100),
                "phase 1: window " .. id .. " fade time from config")
        elseif frame then
            ck(Skin.styled[frame] == nil, "phase 1: hidden window " .. id .. " left alone")
        end
    end
    ck(styledCount >= 2, "phase 1: the sim's default world styled at least two windows")
    ck(Skin.hooked == true, "phase 1: hooks installed on first enable")
    ck(ns.EventHandlerCount("UPDATE_CHAT_COLOR") == colorSubsBase + 1
        and ns.EventHandlerCount("CVAR_UPDATE") == cvarSubsBase + 1,
        "phase 1: enabling added exactly ONE listener each (skin's own, never a sibling's)")

    -- Tab ink, the two stock windows (the routing above is the client's own):
    -- window 1 routes a dozen groups, so it has NO dominant channel and keeps
    -- the token fallback; window 2 is the combat log and wears its own muted
    -- treatment, dimmed because it is not the selected tab.
    local function near3(got, r, g, b, tol)
        tol = tol or 1e-6
        return got and math.abs(got[1] - r) < tol and math.abs(got[2] - g) < tol
            and math.abs(got[3] - b) < tol
    end
    local _, tab1Text = tabText(_G.ChatFrame1)
    ck(near3(tab1Text and tab1Text._textColor, UI.Color("accent")),
        "phase 1: the default window has no dominant channel, so its selected tab keeps the ACCENT token (the pinned fallback)")
    local dim = Skin.DimFactor()
    local mr, mg, mb = UI.Color("muted")
    local _, tab2Text = tabText(_G.ChatFrame2)
    ck(near3(tab2Text and tab2Text._textColor, mr * dim, mg * dim, mb * dim),
        "phase 1: the combat log tab wears the MUTED token dimmed by the token-derived factor")
    ck(Skin.styled[_G.ChatFrame1].inkSource == "token"
        and Skin.styled[_G.ChatFrame2].inkSource == "combatlog",
        "phase 1: each tab records which rule inked it")

    -- The dim factor itself is derived from tokens, never a constant: recompute
    -- it from the muted/text tokens and demand the same answer, then move the
    -- theme and demand it moved with it.
    local function expectedDim()
        local function lum(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end
        local lm = lum(UI.Color("muted"))
        local lt = lum(UI.Color("text"))
        return 0.30 + 0.60 * (lm / (lm + lt))
    end
    ck(math.abs(Skin.DimFactor() - expectedDim()) < 1e-9,
        "phase 1: the inactive-tab dim is DERIVED from the muted/text tokens")
    if UI.__SetThemeEpoch then
        local before = Skin.DimFactor()
        UI.__SetThemeEpoch(3)
        local after = Skin.DimFactor()
        ck(math.abs(after - expectedDim()) < 1e-9,
            "phase 1: the dim re-derives from the NEW theme's tokens")
        ck(math.abs(after - before) > 1e-9,
            "phase 1: a theme change MOVES the dim (a hardcoded alpha could not)")
        UI.__SetThemeEpoch(1)
    end

    -- ── Phase 2: copy-chat reads the ring buffer faithfully. ──────────────────
    local cf3 = _G.ChatFrame3   -- a quiet styled window; seed exact content
    local target = cf3 or _G.ChatFrame1
    local base = target:GetNumMessages()
    target:AddMessage("|cffffffff[|Hplayer:Puu|hPuu|h]|r: look |cffa335ee|Hitem:19019|h[Thunderfury]|h|r", 1, 1, 1)
    target:AddMessage("secret |Kq9|k and {rt7}: |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t", 1, 1, 1)
    local text = Skin.OpenCopy(target)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    ck(#lines == base + 2, "phase 2: copy window holds every buffered line (got " .. #lines .. ")")
    ck(lines[#lines - 1] == "[Puu]: look [Thunderfury]",
        "phase 2: hyperlinks defanged to display text, order oldest-to-newest")
    ck(lines[#lines] == "secret ??? and {rt7}: {rt7}",
        "phase 2: |K span became ??? and the raid icon became {rt7}")
    ck(copyWindow and copyWindow._edit._focused == true, "phase 2: copy edit box took focus")
    ck(copyWindow._edit._highlighted == true, "phase 2: text pre-highlighted for Ctrl+C")
    ck(text:find("|H", 1, true) == nil and text:find("|K", 1, true) == nil,
        "phase 2: no live escape sequences survive into the copyable text")

    -- ── Phase 3: config drives fading (probe a STYLED window). ────────────────
    local fadeProbe = _G.ChatFrame1
    ns.db.skin.fading = false
    for _, frame in ipairs(Skin.order) do Skin.ApplyFading(frame) end
    ck(fadeProbe._fading == false, "phase 3: fading off per config")
    ns.db.skin.fading, ns.db.skin.fadeTime = true, 42
    for _, frame in ipairs(Skin.order) do Skin.ApplyFading(frame) end
    ck(fadeProbe._fading == true and fadeProbe._timeVisible == 42,
        "phase 3: fading back on with the configured hold time")
    ns.db.skin.fadeTime = 100
    for _, frame in ipairs(Skin.order) do Skin.ApplyFading(frame) end

    -- ── Phase 4: theme change re-inks everything (no /reload). ────────────────
    local UIStub = UI
    if UIStub.__SetThemeEpoch then
        local beforeR = select(1, UIStub.Color("panel"))
        UIStub.__SetThemeEpoch(2)
        local afterR = select(1, UIStub.Color("panel"))
        ck(beforeR ~= afterR, "phase 4: the stub theme really changed")
        UIStub.__FireThemeChanged()
        local rec = Skin.styled[_G.ChatFrame1]
        local bg = rec and rec.backdrop and rec.backdrop._backdropColor
        local pr = select(1, UIStub.Color("panel"))
        ck(bg and math.abs(bg[1] - pr) < 1e-6,
            "phase 4: backdrop re-colored from the NEW theme's token")
        UIStub.__SetThemeEpoch(1)
        UIStub.__FireThemeChanged()
    end

    -- ── Phase 5: CHANNEL-COLORED TABS, live, against an authored routing
    -- matrix. Windows 5..8 are opened with one routing each; every ink is
    -- checked against the CLIENT's color table (never a token, never a
    -- literal), and the client's colors are then MOVED to prove nothing is
    -- baked in. ───────────────────────────────────────────────────────────────
    local CTI = _G.ChatTypeInfo
    local MATRIX = {   -- ordered walk, never pairs (the house habit)
        { id = 5, groups = { "GUILD", "OFFICER" }, channels = {} },              -- guild tab
        { id = 6, groups = { "CHANNEL" },          channels = { "Skinworld" } }, -- channel tab
        { id = 7, groups = { "GUILD", "PARTY" },   channels = {} },              -- two identities
        { id = 8, groups = { "SYSTEM", "LOOT" },   channels = {} },              -- ambient only
    }
    -- A channel the "server" has granted a number, with its own client color.
    Sim.serverChannels[9] = { name = "Skinworld", zoneID = 0 }
    _G.ChangeChatColor("CHANNEL9", 0.13, 0.44, 0.77)
    for _, routing in ipairs(MATRIX) do
        local w = Sim.windows[routing.id]
        w.shown, w.docked = true, routing.id
        w.groups, w.channels = { unpack(routing.groups) }, { unpack(routing.channels) }
        if cfgStore then cfgStore.windows[routing.id] = C.CaptureWindow(routing.id) end
    end
    Skin.StyleAll()
    local cf5, cf6, cf7, cf8 =
        _G.ChatFrame5, _G.ChatFrame6, _G.ChatFrame7, _G.ChatFrame8
    local function inkOf(frame) return select(2, tabText(frame))._textColor end
    dim = Skin.DimFactor()

    ck(near3(inkOf(cf5), CTI.GUILD.r * dim, CTI.GUILD.g * dim, CTI.GUILD.b * dim),
        "phase 5: a GUILD window's tab wears the CLIENT's guild-chat color (dimmed, unselected)")
    ck(Skin.styled[cf5].inkSource == "type", "phase 5: the guild tab was inked by a message group")
    ck(near3(inkOf(cf6), CTI.CHANNEL9.r * dim, CTI.CHANNEL9.g * dim, CTI.CHANNEL9.b * dim),
        "phase 5: a single-channel window's tab wears that CHANNEL's client color, resolved by NAME through its number")
    ck(Skin.styled[cf6].inkSource == "channel", "phase 5: the channel tab was inked by a channel name")
    ck(near3(inkOf(cf7), UI.Color("muted")),
        "phase 5: two identities = no dominant = the MUTED token fallback (today's behavior)")
    ck(near3(inkOf(cf8), UI.Color("muted")),
        "phase 5: an ambient-only window falls back too")
    ck(Skin.styled[cf7].inkSource == "token" and Skin.styled[cf8].inkSource == "token",
        "phase 5: both fallback windows record the token source")

    -- Active treatment: full-strength ink plus the accent underline; the tab we
    -- just left drops back to the dimmed ink and loses its underline.
    _G.FCF_SelectDockFrame(cf5)
    ck(near3(inkOf(cf5), CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b),
        "phase 5: the ACTIVE tab wears the channel ink at full strength")
    local ul5 = Skin.styled[cf5].underline
    ck(ul5 and ul5._shown == true, "phase 5: the active tab wears an underline")
    -- skin v3 moved this: the underline is the TAB's own colour (the approved
    -- mockup's --tabc), so a guild tab is underlined in guild green. The ACCENT
    -- token is still the fallback for a tab that resolved no colour at all —
    -- pinned on the default window a few lines down.
    ck(near3(ul5._color, CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b),
        "phase 5: the underline wears the TAB's own ink (the client's guild color)")
    _G.FCF_SelectDockFrame(cf1)
    local ulDefault = Skin.styled[cf1].underline
    ck(ulDefault and ulDefault._shown == true and near3(ulDefault._color, UI.Color("accent")),
        "phase 5: a tab with no colour of its own is underlined in the ACCENT token (the fallback)")
    _G.FCF_SelectDockFrame(cf5)
    ck(near3(inkOf(cf1), UI.Color("muted")),
        "phase 5: the tab that lost selection falls to its inactive treatment")
    local ul1 = Skin.styled[cf1].underline
    ck(ul1 and ul1._shown == false, "phase 5: only the active tab is underlined")

    -- The colors are the CLIENT's, live: move guild chat's color and the tab
    -- follows on the client's own UPDATE_CHAT_COLOR beat (our gated listener),
    -- with no restyle and no reload. A baked-in green cannot survive this.
    _G.ChangeChatColor("GUILD", 0.91, 0.17, 0.55)
    ck(near3(inkOf(cf5), 0.91, 0.17, 0.55),
        "phase 5: UPDATE_CHAT_COLOR re-inks the tab live (the color source is the CLIENT's table)")
    ck(near3(inkOf(cf6), CTI.CHANNEL9.r * dim, CTI.CHANNEL9.g * dim, CTI.CHANNEL9.b * dim),
        "phase 5: recoloring guild chat left the channel tab exactly where it was")
    _G.ChangeChatColor("GUILD", 0.25, 1, 0.25)   -- back to the client's stock guild green
    ck(near3(inkOf(cf5), 0.25, 1, 0.25), "phase 5: and follows the color back")

    -- The feature is a gate: off means Wave 1's treatment, exactly.
    ns.db.skin.channelTabs = false
    Skin.Refresh()
    ck(near3(inkOf(cf5), UI.Color("accent")),
        "phase 5: channelTabs off -> the active tab is the plain ACCENT token again")
    ck(ul5._shown == false, "phase 5: channelTabs off -> no underline either")
    ns.db.skin.channelTabs = true
    Skin.Refresh()

    -- ── Phase 5b: BADGE COORDINATION on a recolored tab. badges.lua owns the
    -- counter; skin owns the tab. Neither may touch the other's surface. ──────
    local Badges = ns.Badges
    if Badges and Badges.active then
        local dock = _G.GeneralDockManager
        dock.DOCKED_CHAT_FRAMES[#dock.DOCKED_CHAT_FRAMES + 1] = cf5
        _G.FCF_SelectDockFrame(cf1)          -- cf5 is docked-unselected: badgeable
        Badges.Clear(cf5)
        cf5:AddMessage("unread on a colored tab", 1, 1, 1)
        local bw = Badges.widgets[cf5]
        local tab5 = _G["ChatFrame5Tab"]
        ck(Badges.counts[cf5] == 1 and bw and bw.holder._shown == true,
            "phase 5b: the badge still renders on a channel-colored tab")
        ck(bw.holder._parent == tab5 and bw.fs ~= tab5.Text,
            "phase 5b: the badge is still its own FontString on its own holder anchored to the tab")
        ck(near3(bw.fs._textColor, UI.Color("muted")),
            "phase 5b: the badge keeps its own MUTED token ink while the tab wears a channel color")
        ck(near3(tab5.Text._textColor, CTI.GUILD.r * dim, CTI.GUILD.g * dim, CTI.GUILD.b * dim),
            "phase 5b: ...and the tab keeps its channel ink while the badge is up")
        -- Geometry: the badge sits PAST the tab's right edge; the underline is
        -- inset INSIDE both tab edges, so the two can never overlap.
        local badgePt = bw.holder._points[1]
        ck(badgePt and badgePt[1] == "LEFT" and badgePt[3] == "RIGHT" and badgePt[4] >= 0,
            "phase 5b: the badge anchors off the tab's RIGHT edge, outward")
        local ulRight
        for _, pt in ipairs(ul5._points) do if pt[1] == "BOTTOMRIGHT" then ulRight = pt end end
        ck(ulRight and ulRight[2] == tab5 and ulRight[4] < 0,
            "phase 5b: the underline's right edge is INSET from the tab (never under the badge)")
        _G.FCF_SelectDockFrame(cf5)
        ck(Badges.counts[cf5] == 0 and bw.holder._shown == false,
            "phase 5b: selecting the colored tab clears the badge as usual")
        ck(near3(tab5.Text._textColor, CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b)
            and ul5._shown == true,
            "phase 5b: ...and the same click gives it the active treatment")
        for i = #dock.DOCKED_CHAT_FRAMES, 1, -1 do
            if dock.DOCKED_CHAT_FRAMES[i] == cf5 then table.remove(dock.DOCKED_CHAT_FRAMES, i) end
        end
        Badges.Clear(cf5)
    end
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase 6: the TIMESTAMP DIVIDER, present only while stamps are on. ─────
    local recDiv = Skin.styled[cf1]
    ck(Skin.StampsShowing() == false, "phase 6: stamps are off as this suite starts")
    Skin.UpdateDividers()
    ck(recDiv.divider == nil or recDiv.divider._shown == false,
        "phase 6: stamps off -> NO divider (nothing to divide)")

    ns.SetModuleEnabled("stamps", true)
    ck(Skin.StampsShowing() == true, "phase 6: stamps on")
    Skin.UpdateDividers()
    ck(recDiv.divider and recDiv.divider._shown == true, "phase 6: the divider appears")
    ck(near3(recDiv.divider._color, UI.Color("border")),
        "phase 6: the hairline is the BORDER token (not a color)")
    ck(recDiv.divider._color[4] == 0.55, "phase 6: ...at the subtle measure alpha")

    -- The column is MEASURED from the stamp shape the format produces; a wider
    -- format moves the hairline right. (Read-only coordination: this reads the
    -- stamps CONFIG field and measures, it never calls into stamps.)
    local narrow = recDiv.dividerX
    local savedFormat = ns.db.stamps.format
    ns.db.stamps.format = "HH:MM:SS"
    Skin.UpdateDividers()
    ck(recDiv.dividerX > narrow,
        "phase 6: a wider stamp format measures a wider stamp column (" ..
        tostring(narrow) .. " -> " .. tostring(recDiv.dividerX) .. ")")
    ns.db.stamps.format = savedFormat
    Skin.UpdateDividers()
    ck(recDiv.dividerX == narrow, "phase 6: and back again")

    -- Suspension is not "off": the client's native timestamps turn stamps into
    -- a bystander, so the divider must go with them. The re-evaluation is
    -- deferred one beat because stamps subscribes to the same CVar event.
    local HT = _G.__DaseekiChatHarnessTimer
    _G.SetCVar("showTimestamps", "chat")
    if HT then HT.advance(0) end
    ck(Skin.StampsShowing() == false and recDiv.divider._shown == false,
        "phase 6: native timestamps suspend stamps, so the divider hides too")
    _G.SetCVar("showTimestamps", "none")
    if HT then HT.advance(0) end
    ck(Skin.StampsShowing() == true and recDiv.divider._shown == true,
        "phase 6: and it comes back with them")

    ns.db.skin.stampDivider = false
    Skin.UpdateDividers()
    ck(recDiv.divider._shown == false, "phase 6: the divider is its own config gate")
    ns.db.skin.stampDivider = true
    ns.SetModuleEnabled("stamps", false)    -- back to the state our siblings expect
    Skin.UpdateDividers()
    ck(recDiv.divider._shown == false, "phase 6: stamps off again -> divider gone again")

    -- ── Phase 7: the EDIT BOX's sticky-channel prefix. ────────────────────────
    local eb1 = _G.ChatFrame1EditBox
    local header = eb1.header
    ck(header ~= nil, "phase 7: the client's edit box carries a header FontString")
    ck(header._fontObject == UI.fonts.small,
        "phase 7: the prefix wears the bar's Core font role")
    eb1:SetAttribute("chatType", "GUILD")
    _G.ChatEdit_UpdateHeader(eb1)
    ck(header._text == "GUILD:", "phase 7: the CLIENT still authors the prefix text (we only ink it)")
    ck(near3(header._textColor, CTI.GUILD.r, CTI.GUILD.g, CTI.GUILD.b),
        "phase 7: the prefix wears guild chat's client color")

    -- The value we add over the client's own header pass: the prefix follows a
    -- recolor made while the box is already open, with no header update at all.
    local headerBeats = Sim.CallCount("ChatEdit_UpdateHeader")
    _G.ChangeChatColor("GUILD", 0.42, 0.66, 0.19)
    ck(Sim.CallCount("ChatEdit_UpdateHeader") == headerBeats,
        "phase 7: the client did NOT re-run its header pass")
    ck(near3(header._textColor, 0.42, 0.66, 0.19),
        "phase 7: ...and the prefix followed the new color anyway (our gated listener)")

    ns.db.skin.editBoxChannelColor = false
    _G.ChangeChatColor("GUILD", 0.25, 1, 0.25)
    ck(near3(header._textColor, 0.42, 0.66, 0.19),
        "phase 7: with the feature off the prefix stops following (it is a real gate)")
    ns.db.skin.editBoxChannelColor = true

    -- A CHANNEL sticky resolves through the channel's number, like the tabs.
    eb1:SetAttribute("chatType", "CHANNEL")
    eb1:SetAttribute("channelTarget", 9)
    _G.ChatEdit_UpdateHeader(eb1)
    ck(header._text == "9. Skinworld:", "phase 7: the client authors the channel prefix")
    ck(near3(header._textColor, CTI.CHANNEL9.r, CTI.CHANNEL9.g, CTI.CHANNEL9.b),
        "phase 7: a channel sticky wears THAT channel's client color")
    eb1:SetAttribute("chatType", "SAY")
    eb1:SetAttribute("channelTarget", nil)
    _G.ChatEdit_UpdateHeader(eb1)

    -- ── Phase 8: the ICON RAIL — off by default, and only existing verbs. ─────
    ck(ns.DEFAULTS.skin.iconRail == false, "phase 8: the rail ships OFF by default")
    ck(Skin.styled[cf1].rail == nil, "phase 8: nothing was built while the rail is off")
    ns.db.skin.iconRail = true
    Skin.Refresh()
    local rail = Skin.styled[cf1].rail
    local rbtn = Skin.styled[cf1].railButtons
    ck(rail and rail._shown == true, "phase 8: turning it on builds the rail")
    ck(rbtn and rbtn.copy and rbtn.config and rbtn.bottom and rbtn.menu,
        "phase 8: four affordances: copy, settings, scroll-to-bottom, chat menu")
    ck(near3(rail._backdropColor, UI.Color("panel")),
        "phase 8: the rail is a flat PANEL-token strip")
    for _, key in ipairs({ "copy", "config", "bottom", "menu" }) do
        local glyph = rbtn[key]._glyph
        ck(type(glyph) == "string" and glyph:match("^[\32-\126]+$") ~= nil,
            "phase 8: the '" .. key .. "' glyph is ASCII (the tofu law)")
        ck(near3(rbtn[key]._label._textColor, UI.Color("muted")),
            "phase 8: the '" .. key .. "' glyph is inked from the MUTED token")
    end
    -- CALL IDENTITY: each button holds the EXACT existing function it invokes.
    ck(rbtn.copy._verb == Skin.OpenCopy, "phase 8: copy is Skin.OpenCopy, not a new verb")
    ck(rbtn.config._verb == ns.SlashDispatch, "phase 8: settings is the /dchat dispatcher itself")
    ck(rbtn.bottom._verb == cf1.ScrollToBottom, "phase 8: scroll-to-bottom is the CLIENT's own frame method")
    ck(rbtn.menu._verb == Skin.OpenChatMenu, "phase 8: the menu button holds the chat-menu verb itself")
    Sim.ResetCalls()
    rbtn.bottom:GetScript("OnClick")(rbtn.bottom)
    ck(Sim.CallCount("ScrollToBottom") == 1, "phase 8: clicking it calls the client verb exactly once")
    ck(Sim.CallCount("AddMessage") == 0 and Sim.CallCount("CreateFrame") == 0,
        "phase 8: and does nothing else at all")
    copyWindow:Hide()
    rbtn.copy:GetScript("OnClick")(rbtn.copy)
    ck(copyWindow._shown == true, "phase 8: the copy button opens the existing copy window")
    copyWindow:Hide()
    ns.db.skin.iconRail = false
    Skin.Refresh()
    ck(rail._shown == false, "phase 8: turning it off puts the rail away")

    -- ── Phase 9: a temporary window opened mid-session gets styled. ───────────
    local hookCallsBefore = Sim.CallCount("FCF_OpenTemporaryWindow")
    local temp = _G.FCF_OpenTemporaryWindow("WHISPER", "Puu")
    ck(temp ~= nil, "phase 9: sim opened a temporary window")
    ck(Skin.styled[temp] ~= nil, "phase 9: the temp window was styled by the hook")
    local tempInk = select(2, tabText(temp))._textColor
    ck(near3(tempInk, CTI.WHISPER.r * dim, CTI.WHISPER.g * dim, CTI.WHISPER.b * dim),
        "phase 9: a whisper pop-out's tab wears whisper chat's client color")

    -- ── Phase 10: disable — full restore, and new activity goes untouched. ────
    ns.SetModuleEnabled("skin", false)
    ck(Skin.active == false, "phase 10: disabled")
    local rec1 = Skin.styled[_G.ChatFrame1]
    ck(rec1.backdrop._shown == false, "phase 10: backdrop hidden on disable")
    local stockBg = _G["ChatFrame1Background"]
    ck(stockBg and stockBg._alpha == (rec1.stock and rec1.stock.Background or 1),
        "phase 10: stock background texture alpha restored")
    ck(rec1.origFont and _G.ChatFrame1._font[1] == rec1.origFont[1],
        "phase 10: original chat font face restored")
    ck(Skin.styled[cf5].underline._shown == false and recDiv.divider._shown == false,
        "phase 10: the v2 surfaces (underline, divider) go away with everything else")
    ck(ns.EventHandlerCount("UPDATE_CHAT_COLOR") == colorSubsBase,
        "phase 10: the color listener was given back (count is the pre-enable baseline)")
    ck(ns.EventHandlerCount("CVAR_UPDATE") == cvarSubsBase,
        "phase 10: the CVar listener was given back too")
    local temp2 = _G.FCF_OpenTemporaryWindow("WHISPER", "Choco")
    ck(Skin.styled[temp2] == nil, "phase 10: a temp window opened while disabled stays stock")

    -- ── Phase 11: re-enable — idempotent, no duplicate rigs. ──────────────────
    local rigCount = #Skin.order
    ns.SetModuleEnabled("skin", true)
    ck(Skin.active == true, "phase 11: re-enabled")
    local rigCount2 = #Skin.order
    -- temp2 is eligible now and gets its own NEW rig; every pre-existing frame
    -- must reuse its old one.
    ck(rigCount2 <= rigCount + 1, "phase 11: re-enable reuses rigs (no duplicates)")
    ck(rec1.backdrop._shown == true, "phase 11: backdrop back")

    -- Hand the world back: the stock ten-window layout, the config branch the
    -- suites before us built, the client's stock channel table.
    Sim.serverChannels[9] = nil
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    if cfgStore then cfgStore.windows = savedCfgWindows end
    ns.db.skin.unifiedChassis = savedUnified
    _G.FCF_SelectDockFrame(cf1)
    Skin.Refresh()
    Sim.ResetCalls()
end

-- skin v2.1: the move affordance and the persistent edit box, driven through
-- the client's own surfaces (drag scripts, ChatEdit_* functions) against the
-- unkind sim — where a drag is clamped, the edit box starts hidden and the
-- client hides it again on every deactivate.
local function testMoveAndEditBox(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI  = UIKit()
    if not (Sim and UI) then return end
    local HT  = _G.__DaseekiChatHarnessTimer
    local C   = ns.Config

    local cf1, cf2, cf3 = _G.ChatFrame1, _G.ChatFrame2, _G.ChatFrame3
    local rec1 = Skin.styled[cf1]
    local function fireDrag(frame, script)
        local fn = frame:GetScript(script)
        if fn then fn(frame) end
    end
    local savedAlt = Sim.altDown
    -- v2.2: the client's button column is the OTHER thing that can hold a drag
    -- off the screen edge, and it has its own phases (B1..B7). Take it out of
    -- the picture here so every assertion below can only be about the CLAMP —
    -- and so this suite reads the same whichever way the column option ships.
    local savedColumn = ns.db.skin.hideButtonColumn
    ns.db.skin.hideButtonColumn = true
    -- v3: the ONE BOX has its own suite; this one is about the drag, the clamp
    -- and the edit box, so the gate is parked OFF and every geometry assertion
    -- below keeps meaning what it meant.
    local savedUnified = ns.db.skin.unifiedChassis
    ns.db.skin.unifiedChassis = false
    Skin.Refresh()

    -- ── Phase M1: the rig exists, and an UNMODIFIED drag is never intercepted ─
    ck(rec1 and rec1.moveRig == true, "M1: the styled window carries a move rig")
    ck(cf1:IsMovable() == true, "M1: …and the client's frame was made movable")
    ck(rec1.wasMovable == false, "M1: the client's own movable state was saved for restore")
    Sim.altDown = false
    Skin.moveMode = false
    Sim.ResetCalls()
    fireDrag(cf1, "OnDragStart")
    ck(Sim.CallCount("StartMoving") == 0,
        "M1: THE GUARD — a plain drag starts nothing (chat text and links stay native)")
    ck(Skin._moving == nil, "M1: …and no move is in flight")
    fireDrag(cf1, "OnDragStop")
    ck(Sim.CallCount("StopMovingOrSizing") == 0, "M1: a stop we did not start is not ours either")

    -- ── Phase M2: ALT-drag moves, and the CLAMP is the thing in the way ──────
    -- With the client's own clamp margin restored, the drag cannot reach the
    -- screen edge — the owner's account-1 symptom, reproduced on demand.
    local movesBefore = Skin.moves
    ns.db.skin.unclampWindows = false
    cf1._clampInsets = nil                       -- back to the client's margin
    Sim.altDown = true
    fireDrag(cf1, "OnDragStart")
    ck(Sim.CallCount("StartMoving") == 1, "M2: ALT-drag starts the move")
    ck(Skin._moving ~= nil and Skin._moving.target == cf1, "M2: the window itself is the target")
    local lx, ly = Sim.DragTo(cf1, -80, -80)     -- shove it past the corner
    ck(lx > 0 and ly > 0,
        "M2: THE SYMPTOM — with the client's clamp the drag CANNOT reach the screen edge")
    fireDrag(cf1, "OnDragStop")
    ck(Sim.CallCount("StopMovingOrSizing") == 1, "M2: the drop released the frame")
    ck(Skin.moves == movesBefore + 1, "M2: the move was counted")
    ck(Skin._moving == nil, "M2: nothing is left in flight")

    -- ── Phase M3: the loosened clamp is the direct fix for the symptom ───────
    ns.db.skin.unclampWindows = true
    fireDrag(cf1, "OnDragStart")                 -- re-asserts the loosened clamp
    local lx2, ly2 = Sim.DragTo(cf1, -80, -80)
    ck(lx2 == 0 and ly2 == 0,
        "M3: THE FIX — with the insets loosened the very same drag lands flush in the corner")
    ck(cf1:IsClampedToScreen() == true,
        "M3: …and the window is still clamped ON screen (never draggable into the void)")
    fireDrag(cf1, "OnDragStop")

    -- ── Phase M4: a DOCKED window moves the DOCK, not itself ─────────────────
    local dockPrimary = _G.GeneralDockManager.primary
    ck(dockPrimary == cf1, "M4: ChatFrame1 is the dock's primary in this world")
    local before2 = cf2._left
    fireDrag(cf2, "OnDragStart")
    ck(Skin._moving ~= nil and Skin._moving.target == dockPrimary and Skin._moving.viaDock,
        "M4: alt-dragging a docked window moves the DOCK's primary frame")
    Sim.DragTo(Skin._moving.target, 400, 300)
    fireDrag(cf2, "OnDragStop")
    ck(cf1._left == 400, "M4: …so the dock moved")
    ck(cf2._left == before2, "M4: …and the docked child was never repositioned behind the client's back")

    -- An UNDOCKED window moves itself.
    _G.SetChatWindowShown(3, true)
    _G.SetChatWindowDocked(3, false)
    _G.FloatingChatFrame_Update(3)
    Skin.StyleWindow(cf3, 3)
    fireDrag(cf3, "OnDragStart")
    ck(Skin._moving ~= nil and Skin._moving.target == cf3 and not Skin._moving.viaDock,
        "M4: an undocked window is its own move target")
    Sim.DragTo(cf3, 900, 600)
    fireDrag(cf3, "OnDragStop")
    ck(cf3._left == 900, "M4: …and it moved")

    -- ── Phase M5: RELEASE CAPTURES BACK, echo-clean, exactly once ────────────
    local cfg = C.Get()
    local savedWindows, savedRev, savedAt = cfg.windows, cfg.rev, cfg.at
    cfg.windows = {}
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do cfg.windows[id] = C.CaptureWindow(id) end
    cfg.rev, cfg.at = (tonumber(cfg.rev) or 0) + 1, C.Now()
    ns.SetModuleEnabled("reconcile", true)
    local R = ns.Reconcile
    HT.flush()
    local revBefore, capsBefore = C.Rev(), R.stats.captures

    fireDrag(cf3, "OnDragStart")
    Sim.DragTo(cf3, 0, 0)                        -- flush into the corner
    fireDrag(cf3, "OnDragStop")
    ck(C.Rev() == revBefore, "M5: the capture is DEBOUNCED (nothing has landed yet)")
    HT.advance(0.3)                              -- past the capture debounce
    ck(C.Rev() == revBefore + 1, "M5: the drop captured back exactly once")
    ck(R.stats.captures == capsBefore + 1, "M5: …through the reconciler's own capture path")
    local capturedNP = cfg.windows[3] and cfg.windows[3].npos
    ck(C.NearPos(capturedNP, { "BOTTOMLEFT", 0, 0 }),
        "M5: the config learned the NORMALIZED corner the player dragged to")

    -- THE RECONCILER MUST NOT FIGHT IT: the next beat converges toward the
    -- captured truth and captures nothing of its own.
    local revAfter, capsAfter = C.Rev(), R.stats.captures
    Sim.EnterWorld(false, false)
    HT.advance(0.5)
    HT.flush()
    ck(C.Rev() == revAfter, "M5: ECHO — the following reconcile never re-bumped the rev")
    ck(R.stats.captures == capsAfter, "M5: ECHO — and captured none of its own writes")
    local stillNP = C.CaptureNormalizedPos(3)
    ck(C.NearPos(stillNP, { "BOTTOMLEFT", 0, 0 }),
        "M5: the player's dragged position SURVIVED the reconcile (it is the new truth)")
    ns.SetModuleEnabled("reconcile", false)
    cfg.windows, cfg.rev, cfg.at = savedWindows, savedRev, savedAt

    -- ── Phase M6: /dchat unlock and /dchat lock ─────────────────────────────
    -- AMENDED 2026-08-11: the pair is no longer a session-scoped plain-drag
    -- toggle. It is THE LOCK — persisted, synced, and a veto over every move
    -- gesture including ALT, because "the box is a rock" cannot have one.
    local lockedBefore = Skin.Locked()
    Sim.altDown = false
    fireDrag(cf3, "OnDragStart")
    ck(Skin._moving == nil, "M6: with no modifier and no unlock, a plain drag does nothing")
    ns.SlashDispatch("unlock")
    ck(Skin.moveMode == true, "M6: /dchat unlock turns plain drags into moves")
    ck(Skin.Locked() == false, "M6: …and clears the persisted lock")
    ck(C.Locked() == false, "M6: …in the SYNCED config, where every character reads it")
    fireDrag(cf3, "OnDragStart")
    ck(Skin._moving ~= nil, "M6: …and now a plain drag moves the window")
    fireDrag(cf3, "OnDragStop")
    ns.SlashDispatch("lock")
    ck(Skin.moveMode == false, "M6: /dchat lock puts it back")
    ck(Skin.Locked() == true and C.Locked() == true, "M6: …and the lock is written and synced")
    fireDrag(cf3, "OnDragStart")
    ck(Skin._moving == nil, "M6: …and a plain drag is inert again")
    -- RED CONTROL: the veto covers ALT too. Before the lock, ALT-drag was the
    -- gesture that always worked; a lock that let it through would be a label,
    -- not a lock.
    Sim.altDown = true
    fireDrag(cf3, "OnDragStart")
    ck(Skin._moving == nil, "M6: RED CONTROL — LOCKED refuses an ALT-drag as well")
    ck(Skin.MoveAllowed() == false, "M6: …because the one gate says so")
    ns.SlashDispatch("unlock")
    fireDrag(cf3, "OnDragStart")
    ck(Skin._moving ~= nil, "M6: …and unlocking gives ALT-drag straight back")
    fireDrag(cf3, "OnDragStop")
    -- …and the help line answers "which way is it pointing right now".
    local notes = ns.HelpNotes()
    local sawLock = false
    for _, line in ipairs(notes) do if line:find("UNLOCKED", 1, true) then sawLock = true end end
    ck(sawLock, "M6: /dchat's command list says which state the lock is in")
    Sim.altDown = savedAlt
    -- Leave the world as this suite found it: every suite after this one drags
    -- something, and a lock left on would fail all of them (it did, once).
    Skin.SetLocked(lockedBefore)
    Skin.moveMode = false

    -- ── Phase E1: THE PERSISTENT EDIT BOX, against a client that hides it ────
    local eb = editBoxOf(cf1)
    ck(eb ~= nil, "E1: the window has an attached edit box")
    ck(ns.DEFAULTS.skin.persistentEditBox == true, "E1: the option ships ON (the owner's ask)")
    eb:SetAttribute("chatType", "SAY")

    _G.ChatEdit_ActivateChat(eb)
    ck(eb._shown == true and eb._focused == true, "E1: activating shows and focuses, as ever")
    ck(math.abs((eb._alpha or 1) - EB_ACTIVE) < 1e-6, "E1: a focused box is at full strength")

    -- The client's own deactivate: it hides. We get the last word, in-call.
    _G.ChatEdit_DeactivateChat(eb)
    ck(eb._shown == true, "E1: THE ASK — the box is STILL SHOWN after the client deactivated it")
    ck(eb._focused == false, "E1: …but it holds no focus")
    ck(eb.header._shown == true, "E1: the sticky-channel prefix stayed visible with it")
    ck(eb.header._text == "SAY:", "E1: …and the CLIENT still authors that prefix text")
    ck(math.abs((eb._alpha or 1) - EB_IDLE) < 1e-6,
        "E1: an empty, unfocused box wears the quiet placeholder treatment")
    ck(eb._text == "", "E1: the client's own text clear is untouched")

    -- ESCAPE: the client's escape handler is a deactivate, so the same rule
    -- holds — unfocus, never hide.
    _G.ChatEdit_ActivateChat(eb)
    _G.ChatEdit_OnEscapePressed(eb)
    ck(eb._shown == true and eb._focused == false,
        "E1: ESCAPE unfocuses the box and does NOT hide it")

    -- ENTER re-focuses the box that is already sitting there.
    _G.ChatFrame_OpenChat(nil, cf1)
    ck(eb._focused == true and eb._shown == true, "E1: Enter focuses the persistent box")
    ck(math.abs((eb._alpha or 1) - EB_ACTIVE) < 1e-6, "E1: …and it brightens on focus")
    _G.ChatEdit_DeactivateChat(eb)

    -- The prefix keeps skin v2's channel ink while it sits there unfocused.
    eb:SetAttribute("chatType", "CHANNEL")
    eb:SetAttribute("channelTarget", 1)
    _G.ChatEdit_ActivateChat(eb)
    _G.ChatEdit_DeactivateChat(eb)
    local chInfo = _G.ChatTypeInfo["CHANNEL1"]
    ck(eb.header._shown == true and tostring(eb.header._text):find(":", 1, true) ~= nil,
        "E1: a channel sticky keeps its prefix on the resting bar")
    if chInfo then
        local tc = eb.header._textColor
        ck(tc and math.abs(tc[1] - chInfo.r) < 1e-6,
            "E1: …wearing that channel's client color (skin v2's ink, on the resting bar)")
    end
    eb:SetAttribute("chatType", "SAY")
    eb:SetAttribute("channelTarget", nil)

    -- ── Phase E2: BOTH POSTURES. The function hook is synchronous and in-call;
    -- the OBJECT watch covers a hide that never went through that function. ──
    ck(Skin._ebDepth == 0, "E2: the re-entrancy latch is back at rest")
    eb:Hide()                                     -- a hide from nowhere in particular
    ck(eb._shown == false, "E2: the object path does NOT re-show inside the hide handler")
    HT.advance(0)                                 -- one beat later
    ck(eb._shown == true, "E2: …the OnHide watch put it back one beat later (Class 2)")
    ck(Skin._ebDepth == 0, "E2: the latch is released after the deferred restore")

    -- ── Phase E3: option OFF = native behavior, byte for byte ───────────────
    ns.db.skin.persistentEditBox = false
    local headerBeats = Sim.CallCount("ChatEdit_UpdateHeader")
    local showBeats   = Sim.CallCount("widget:Show")
    _G.ChatEdit_ActivateChat(eb)
    _G.ChatEdit_DeactivateChat(eb)
    ck(eb._shown == false, "E3: with the option off the client's hide stands")
    ck(eb.header._shown == false, "E3: …and the prefix goes with it")
    eb:Hide()
    HT.advance(0)
    ck(eb._shown == false, "E3: the OnHide watch is a real gate too")
    ck(Sim.CallCount("ChatEdit_UpdateHeader") == headerBeats + 1,
        "E3: exactly the CLIENT's own header pass ran — we added none")
    ns.db.skin.persistentEditBox = true
    Skin.KeepEditBoxShown(eb)
    ck(eb._shown == true, "E3: turning it back on restores the box immediately")

    -- ── Phase C1: the clamp write is PROTECTED IN COMBAT ────────────────────
    cf1._clampInsets = nil
    Sim.inCombat = true
    ck(Skin.LoosenClamp(cf1, rec1) == false, "C1: the clamp write refuses in combat")
    ck(Skin._clampPending[cf1] == true, "C1: …and remembers that it owes one")
    ck(select(1, cf1:GetClampRectInsets()) > 0, "C1: the client's margin is untouched meanwhile")
    Sim.inCombat = false
    Sim.DispatchEvent("PLAYER_REGEN_ENABLED")
    ck(Skin._clampPending[cf1] == nil, "C1: the regen beat drained the debt")
    ck(select(1, cf1:GetClampRectInsets()) == 0, "C1: …and the loosened clamp finally landed")

    -- ── Phase C2: disable hands EVERYTHING back ─────────────────────────────
    local regenBase = ns.EventHandlerCount("PLAYER_REGEN_ENABLED")
    ck(regenBase >= 1, "C2: the regen listener is registered while active")
    ns.SetModuleEnabled("skin", false)
    ck(ns.EventHandlerCount("PLAYER_REGEN_ENABLED") == regenBase - 1,
        "C2: the regen listener was given back")
    ck(select(1, cf1:GetClampRectInsets()) == rec1.clampInsets[1],
        "C2: the client's own clamp insets were restored")
    ck(cf1:IsMovable() == rec1.wasMovable, "C2: …and so was its movable state")
    ck(eb._shown == false, "C2: an edit box we forced open goes quiet again on disable")
    Sim.altDown = true
    Sim.ResetCalls()
    fireDrag(cf1, "OnDragStart")
    ck(Sim.CallCount("StartMoving") == 0, "C2: a disabled skin moves nothing (hook bodies inert)")
    Sim.altDown = savedAlt

    -- ── OUT: back to the world the suites after us expect ───────────────────
    ns.SetModuleEnabled("skin", true)
    ns.db.skin.hideButtonColumn = savedColumn
    ns.db.skin.unifiedChassis = savedUnified
    Skin.moveMode = false
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local f = Sim.Frame(id)
        f._left, f._bottom = 32, 32
    end
    _G.FCF_SelectDockFrame(cf1)
    Skin.Refresh()
    HT.flush()
    Sim.ResetCalls()
end

-- skin v2.2: the chat BUTTON COLUMN — the client's own column, its side flip,
-- its share of the drag footprint, our keep-it-down seam, the chat-menu verb
-- in both the rail-on and rail-off worlds, and the option-off native world.
local function testButtonColumn(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI  = UIKit()
    if not (Sim and UI) then return end
    local HT  = _G.__DaseekiChatHarnessTimer
    local C   = ns.Config

    local cf1 = _G.ChatFrame1
    local rec1 = Skin.styled[cf1]
    local eb1 = editBoxOf(cf1)
    local function fireDrag(frame, script)
        local fn = frame:GetScript(script)
        if fn then fn(frame) end
    end
    local savedAlt, savedLeft, savedBottom = Sim.altDown, cf1._left, cf1._bottom
    -- v3: the ONE BOX has its own suite; the icon-rail offset assertions here
    -- are about the COLUMN's footprint, so the gate is parked OFF.
    local savedUnified = ns.db.skin.unifiedChassis
    ns.db.skin.unifiedChassis = false
    Skin.Refresh()

    -- ── Phase B1: THE MECHANICS — the column, both shapes, and its side ──────
    ck(ns.DEFAULTS.skin.hideButtonColumn == true,
        "B1: the column ships DOWN (the reference look the owner chose)")
    local bf = Skin.ButtonColumnOf(cf1)
    ck(bf ~= nil, "B1: the window's button column is found")
    ck(bf == cf1.buttonFrame and bf == _G.ChatFrame1ButtonFrame,
        "B1: …through BOTH client shapes (the frame's own field and the global)")
    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    ck(bf._shown == false, "B1: with the option on the column is down")

    -- Option OFF puts the client's own world back, side-flip and all.
    ns.db.skin.hideButtonColumn = false
    Skin.Refresh()
    ck(bf._shown == true, "B1: option OFF gives the client its column back")
    cf1._left = 400
    _G.FCF_UpdateButtonSide(cf1)
    ck(Skin.ButtonColumnSide(cf1) == "left",
        "B1: a window with room on its left wears the column on the LEFT (account 1)")
    local fl, fr = Skin.ColumnFootprint(cf1)
    ck(fl == Sim.BUTTON_FRAME_WIDTH and fr == 0,
        "B1: …and that column costs the window's left side its own width")
    cf1._left = 0
    _G.FCF_UpdateButtonSide(cf1)
    ck(Skin.ButtonColumnSide(cf1) == "right",
        "B1: THE ACCOUNT DIFFERENCE — flush left, the CLIENT flips the column RIGHT (account 2)")
    fl, fr = Skin.ColumnFootprint(cf1)
    ck(fl == 0 and fr == Sim.BUTTON_FRAME_WIDTH,
        "B1: …and the cost moves to the right with it")

    -- ── Phase B2: THE RED CONTROL — the column is what blocks flush ──────────
    -- The clamp is already loosened here, so the ONLY thing left holding the
    -- drag off the edge is the column itself.
    ns.db.skin.unclampWindows = true
    cf1._left, cf1._bottom = 400, 300
    _G.FCF_UpdateButtonSide(cf1)                 -- column on the left, shown
    Sim.altDown = true
    fireDrag(cf1, "OnDragStart")
    local bx, by = Sim.DragTo(cf1, -80, -80)
    ck(bx == Sim.BUTTON_FRAME_WIDTH,
        "B2: THE SYMPTOM — with the column shown the drag stops exactly its width short")
    ck(by == 0, "B2: …and only horizontally: the loosened clamp still reaches the bottom")
    fireDrag(cf1, "OnDragStop")

    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    ck(bf._shown == false, "B2: turning the option on takes the column down")
    ck(select(1, Skin.ColumnFootprint(cf1)) == 0,
        "B2: …so it costs the window's placement nothing")
    fireDrag(cf1, "OnDragStart")
    local fx, fy = Sim.DragTo(cf1, -80, -80)
    ck(fx == 0 and fy == 0,
        "B2: THE FIX — the very same drag now lands FLUSH in the corner")
    fireDrag(cf1, "OnDragStop")
    ck(cf1:IsClampedToScreen() == true, "B2: …and the window is still clamped ON screen")
    -- The drop is exactly where the client re-decides the side and re-shows.
    ck(Skin.ButtonColumnSide(cf1) == "right",
        "B2: the client DID flip the side on the drop (its rule is untouched)")
    ck(bf._shown == false, "B2: …and the column still came back down, in-call")

    -- ── Phase B3: KEEP-HIDDEN, against every client re-show, latch-clean ─────
    Sim.ResetCalls()
    local hidesBefore = Skin.columnHides
    _G.FloatingChatFrame_Update(1)
    ck(bf._shown == false, "B3: the client's own window update did not get the column back")
    ck(Skin.columnHides == hidesBefore + 1,
        "B3: …and it cost exactly ONE hide, not one per hooked function")
    ck(Skin._bfDepth == 0, "B3: the re-entrancy latch is back at rest")
    _G.FCF_DockUpdate()
    ck(bf._shown == false, "B3: the dock update did not either")
    ck(Skin._bfDepth == 0, "B3: …and the latch is still clean")

    -- The OBJECT path: a show from nowhere in particular (Class 2).
    local hidesObj = Skin.columnHides
    bf:Show()
    ck(bf._shown == true, "B3: we do NOT re-hide from inside the client's show handler")
    HT.advance(0)
    ck(bf._shown == false, "B3: …the OnShow watch put it back down one beat later")
    ck(Skin.columnHides == hidesObj + 1, "B3: …at the cost of exactly one hide")
    ck(Skin._bfDepth == 0, "B3: the latch is released after the deferred re-hide")

    -- NEVER A FIGHT LOOP: an idle beat over a column already down is free.
    local idleHides = Skin.columnHides
    for _ = 1, 5 do Skin.Refresh() end
    HT.flush()
    ck(Skin.columnHides == idleHides,
        "B3: five idle re-evaluation beats cost ZERO client calls (no fight loop)")

    -- ── Phase B3b: THE HITBOX IS GONE (owner, 2026-08-11: "completely disable
    -- them and remove their hitboxes"). Hiding takes the pixels; this pins that
    -- the option ALSO takes the mouse — off the column AND off every button in
    -- it — so a click at the column's own coordinates reaches whatever is
    -- behind it, and that OFF gives every one of them back exactly. ──────────
    -- A clean slate first: the option OFF hands the column back and clears our
    -- record, so what follows is a whole capture-disable-restore cycle rather
    -- than an assertion about leftovers.
    local quiet = ns.Print
    ns.Print = function() end
    ns.db.skin.hideButtonColumn = false
    Skin.Refresh()
    ns.Print = quiet
    Skin._columnEventNoticed = false

    local upBtn = _G.ChatFrame1ButtonFrameUpButton
    ck(upBtn ~= nil and upBtn:IsMouseEnabled() == true,
        "B3b: with the option off the column's buttons are live, as the client left them")
    upBtn:RegisterEvent("UPDATE_CHAT_WINDOWS")
    ck(upBtn:IsEventRegistered("UPDATE_CHAT_WINDOWS") == true, "B3b: the button holds an event")

    local dropsBefore = Skin.columnEventsDropped
    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    local widgets = Skin.ColumnWidgets(cf1)
    ck(#widgets >= 4, "B3b: the walk finds the column AND its buttons (got " .. #widgets .. ")")
    ck(widgets[1] == bf, "B3b: …starting at the column itself")
    local allDead = true
    for _, w in ipairs(widgets) do
        if type(w.IsMouseEnabled) == "function" and w:IsMouseEnabled() then allDead = false end
    end
    ck(allDead, "B3b: EVERY widget in the column subtree has its mouse OFF")
    ck(upBtn:IsEventRegistered("UPDATE_CHAT_WINDOWS") == false,
        "B3b: …and the disable took its event registration (UnregisterAllEvents)")
    ck(Skin.columnEventsDropped > dropsBefore, "B3b: the drop is COUNTED, not silent")

    -- THE POINTER LEG: a probe frame parked exactly under the column's rect.
    -- With the column live the column wins the point; with the option on the
    -- probe does — which is the hitbox question asked literally.
    local cl, cb, cw, chh = Sim.ColumnRect(cf1)
    ck(cl ~= nil, "B3b: the column has a measurable rect")
    local probe = Sim.NewWidget("Frame", nil, _G.UIParent)
    probe._left, probe._bottom, probe._w, probe._h = cl, cb, cw, chh
    probe._mouse, probe._shown = true, true
    local px, py = cl + cw / 2, cb + chh / 2
    local candidates = { upBtn, bf, probe }
    ck(Sim.HitTest(px, py, candidates) == probe,
        "B3b: THE PIN — a click at the column's coordinates reaches what is UNDER it")

    -- The button's OWN rect, which is where a stray click actually lands.
    local bl, bb = upBtn._left, upBtn._bottom
    ck(bl ~= nil, "B3b: the column's button has a rect of its own")
    ck(Sim.HitTest(bl + 2, bb + 2, candidates) == probe,
        "B3b: …and a click on the BUTTON reaches through as well")

    -- OFF RESTORES: mouse back on everything, and the click lands on the column
    -- again. The event is NOT restored — the client cannot enumerate what a
    -- frame holds — so the option-off path prints one honest line saying so,
    -- which is exactly what Skin.NoteColumnEventRestore exists for.
    local said = {}
    local realPrint = ns.Print
    ns.Print = function(_, ...) said[#said + 1] = table.concat({ ... }, " ") end
    ns.db.skin.hideButtonColumn = false
    Skin.Refresh()
    ns.Print = realPrint
    ck(bf._shown == true, "B3b: option OFF gives the column back")
    local allLive = true
    for _, w in ipairs(Skin.ColumnWidgets(cf1)) do
        if type(w.IsMouseEnabled) == "function" and not w:IsMouseEnabled() then allLive = false end
    end
    ck(allLive, "B3b: …with every widget's mouse restored")
    ck(Sim.HitTest(px, py, { bf, probe }) == bf,
        "B3b: …so the column wins its own coordinates again")
    local honest = false
    for _, line in ipairs(said) do if line:find("/reload", 1, true) then honest = true end end
    ck(honest, "B3b: THE HONESTY PIN — the restore says out loud that events need /reload")
    ck(upBtn:IsEventRegistered("UPDATE_CHAT_WINDOWS") == false,
        "B3b: …because they really are still gone (never a half-restored pretence)")
    local saidAgain = {}
    local realPrint2 = ns.Print
    ns.Print = function(_, ...) saidAgain[#saidAgain + 1] = table.concat({ ... }, " ") end
    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    ns.db.skin.hideButtonColumn = false
    Skin.Refresh()
    ns.Print = realPrint2
    ck(#saidAgain == 0, "B3b: the line is said ONCE per session, never on every toggle")

    probe:Hide()
    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    ck(bf._shown == false, "B3b: back to the shipped posture for the phases below")

    -- ── Phase B4: THE MENU VERB — the one thing the column owned ────────────
    local kind, verb, subject = Skin.ChatMenuSeam()
    ck(kind == "toggle", "B4: the seam this client offers is the menu-frame toggle")
    ck(verb == _G.ToggleFrame, "B4: CALL IDENTITY — we hold the CLIENT's own ToggleFrame")
    ck(subject == _G.ChatMenu, "B4: …and the CLIENT's own chat menu frame")

    -- The rail world (opt-in).
    ns.db.skin.iconRail = true
    Skin.Refresh()
    local rbtn = rec1.railButtons
    ck(rbtn and rbtn.menu ~= nil, "B4: the rail carries the chat-menu verb")
    -- THE WIDTH MATH: the rail's own placement reads the footprint, so a
    -- removed column really is removed from what the skin lays out around.
    cf1._left = 400
    _G.FCF_UpdateButtonSide(cf1)
    Skin.Refresh()
    ck(rec1.rail._points[1][4] == -(PAD + RAIL_GAP),
        "B4: with the column down the rail sits right against the window")
    ns.db.skin.hideButtonColumn = false
    Skin.Refresh()
    ck(rec1.rail._points[1][4] == -(PAD + RAIL_GAP + Sim.BUTTON_FRAME_WIDTH),
        "B4: with the column up it clears the column instead of sitting on it")
    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    _G.ChatMenu:Hide()
    Sim.ResetCalls()
    local opensBefore = Skin.menuOpens
    rbtn.menu:GetScript("OnClick")(rbtn.menu)
    ck(_G.ChatMenu._shown == true, "B4: clicking it opens the CLIENT's chat menu")
    ck(Sim.CallCount("ToggleFrame") == 1, "B4: …with exactly one client call")
    ck(Sim.CallCount("CreateFrame") == 0, "B4: …and nothing built behind it")
    ck(Skin.menuOpens == opensBefore + 1, "B4: the open was counted")
    rbtn.menu:GetScript("OnClick")(rbtn.menu)
    ck(_G.ChatMenu._shown == false, "B4: clicking again closes it (the client's own toggle)")

    -- THE RAIL IS OFF BY DEFAULT, so the resting bar's PREFIX answers too.
    ns.db.skin.iconRail = false
    Skin.Refresh()
    ck(rec1.rail._shown == false, "B4: back in the default world the rail is away")
    ck(eb1 ~= nil and eb1._shown == true, "B4: …and the persistent bar is the surface at hand")
    local mouse = eb1:GetScript("OnMouseDown")
    ck(type(mouse) == "function", "B4: the bar answers a mouse-down")
    Sim.SetCursorAt(eb1.header, 5, 5)             -- over the prefix
    ck(Skin.OverPrefix(eb1) == true, "B4: the pointer is measured onto the prefix region")
    local opens2 = Skin.menuOpens
    mouse(eb1, "LeftButton")
    ck(Skin.menuOpens == opens2 and _G.ChatMenu._shown == false,
        "B4: an UNMODIFIED click is never intercepted (typing still just works)")
    mouse(eb1, "RightButton")
    ck(_G.ChatMenu._shown == true and Skin.menuOpens == opens2 + 1,
        "B4: THE FALLBACK — right-clicking the prefix opens the same client menu")
    _G.ChatMenu:Hide()
    Sim.SetCursorAt(eb1, 300, 5)                  -- past the prefix, in the text
    ck(Skin.OverPrefix(eb1) == false, "B4: a pointer past the prefix is not on it")
    local opens3 = Skin.menuOpens
    mouse(eb1, "RightButton")
    ck(Skin.menuOpens == opens3 and _G.ChatMenu._shown == false,
        "B4: …and a right-click there is left exactly as native")

    -- The DEFENDED SHAPE: a client that does not name the menu frame still has
    -- the button that performs the verb.
    local savedMenu = _G.ChatMenu
    _G.ChatMenu = nil
    local kind2, verb2, subject2 = Skin.ChatMenuSeam()
    ck(kind2 == "button", "B4: without the menu frame the seam falls back to the client's button")
    ck(verb2 == _G.ChatFrameMenuButton.Click and subject2 == _G.ChatFrameMenuButton,
        "B4: CALL IDENTITY — that is the CLIENT's own button and its own Click")
    Sim.ResetCalls()
    ck(Skin.OpenChatMenu() == "button", "B4: …and the verb goes through it")
    ck(Sim.CallCount("widget:Click") == 1, "B4: …exactly once")
    _G.ChatMenu = savedMenu

    -- ── Phase B5: OPTION OFF = the client's own world, byte for byte ────────
    ns.db.skin.hideButtonColumn = false
    Skin.Refresh()
    ck(bf._shown == true, "B5: the column is back up the moment the option goes off")
    Sim.ResetCalls()
    local hidesOff = Skin.columnHides
    _G.FloatingChatFrame_Update(1)
    _G.FCF_DockUpdate()
    bf:Show()
    HT.advance(0)
    ck(bf._shown == true, "B5: nothing of ours touches it — the client's column stands")
    ck(Skin.columnHides == hidesOff, "B5: …we hid it exactly zero times")
    ck(Sim.CallCount("FCF_UpdateButtonSide") == 1 + (_G.NUM_CHAT_WINDOWS or 10),
        "B5: exactly the CLIENT's own side updates ran — we added none")
    cf1._left = 0
    -- The client's own store has to agree with the move, or its window-update
    -- beat restores the OLD corner before it ever asks about the side (the
    -- restore-bounce this branch exists to close — see Phase M5b).
    _G.FCF_SavePositionAndDimensions(cf1)
    _G.FloatingChatFrame_Update(1)
    ck(Skin.ButtonColumnSide(cf1) == "right" and bf._shown == true,
        "B5: and the client's own side-flipping is untouched")

    -- ── Phase B6: THE CAPTURE READS THE WINDOW, NOT THE COLUMN ──────────────
    cf1._left, cf1._bottom = 320, 240
    _G.FCF_UpdateButtonSide(cf1)                  -- column on the left, shown
    ck(bf:GetLeft() < cf1:GetLeft(),
        "B6: the shown column really does hang outside the window's corner")
    local npShown = C.CaptureNormalizedPos(1)
    local uiW, uiH, uiScale = C.ScreenGeometry()
    local fs = cf1:GetEffectiveScale()
    local colFx = C.Normalize(bf:GetLeft() * fs, cf1:GetBottom() * fs, uiW * uiScale, uiH * uiScale)
    ck(npShown and math.abs(npShown[2] - colFx) > C.NPOS_EPSILON,
        "B6: RED CONTROL — a column-inclusive read would answer a DIFFERENT number")
    ns.db.skin.hideButtonColumn = true
    Skin.Refresh()
    ck(bf._shown == false, "B6: the column goes down")
    local npHidden = C.CaptureNormalizedPos(1)
    ck(npHidden and npShown and npHidden[1] == npShown[1]
        and npHidden[2] == npShown[2] and npHidden[3] == npShown[3],
        "B6: …and the stored position does not move by a single digit")

    -- ── Phase B7: disable hands the client's column back ────────────────────
    ns.SetModuleEnabled("skin", false)
    ck(bf._shown == true, "B7: a column we took down is given back on disable")
    ck(rec1.bfForcedHidden == nil, "B7: …and we stop claiming it")
    ns.SetModuleEnabled("skin", true)
    ck(bf._shown == false, "B7: re-enabling takes it down again")
    -- A column the CLIENT already had down before us is never resurrected: the
    -- restore hands back what was there, not a blanket Show.
    rec1.bfForcedHidden, rec1.bfWasShown = true, false
    ck(Skin.RestoreButtonColumn(cf1, rec1) == false and bf._shown == false,
        "B7: a column that was already down before us stays down")
    rec1.bfForcedHidden, rec1.bfWasShown = true, true

    -- ── OUT: back to the world the suites after us expect ───────────────────
    Sim.altDown = savedAlt
    Sim.cursor = { 0, 0 }
    _G.ChatMenu:Hide()
    ns.db.skin.iconRail = false
    ns.db.skin.hideButtonColumn = true
    ns.db.skin.unifiedChassis = savedUnified
    cf1._left, cf1._bottom = savedLeft, savedBottom
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local f = Sim.Frame(id)
        f._left, f._bottom = 32, 32
    end
    _G.FCF_SelectDockFrame(cf1)
    Skin.Refresh()
    HT.flush()
    Sim.ResetCalls()
end

-- skin v3: THE ONE BOX. The placement matrix in geometry, the single-backdrop
-- rule, the fused active tab, the rail's edge bar, the colour chain, the badge
-- following its tab, fading going inert, and the whole thing handing every tab
-- back when it is turned off.
local function testOneBox(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI  = UIKit()
    if not (Sim and UI) then
        if verbose then ns:Print("  skin: one-box checks skipped (no simulator)") end
        return
    end
    local C = ns.Config
    if not C then return end

    local function near3(got, r, g, b, tol)
        tol = tol or 1e-6
        return got and math.abs(got[1] - r) < tol and math.abs(got[2] - g) < tol
            and math.abs(got[3] - b) < tol
    end
    -- A recorded SetPoint, by its own anchor name.
    local function pointNamed(widget, anchor)
        for _, p in ipairs((widget and widget._points) or {}) do
            if p[1] == anchor then return p end
        end
        return nil
    end

    ns.SetModuleEnabled("skin", true)
    local cfgStore = C.Get()
    local savedWindows, savedRev, savedAt = cfgStore.windows, cfgStore.rev, cfgStore.at
    local savedSkinCfg = cfgStore.skin
    local savedUnified, savedFading = ns.db.skin.unifiedChassis, ns.db.skin.fading
    local savedChannelTabs, savedRail = ns.db.skin.channelTabs, ns.db.skin.iconRail

    -- The client's stock ten-window world, mirrored into the config, so the
    -- routing the colour chain is judged on is the client's own.
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    cfgStore.windows = {}
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do cfgStore.windows[id] = C.CaptureWindow(id) end
    cfgStore.skin = { tabPlacement = "top" }
    cfgStore.rev, cfgStore.at = 1, C.Now()
    local cf1, cf2 = _G.ChatFrame1, _G.ChatFrame2
    _G.FCF_SelectDockFrame(cf1)
    ns.db.skin.unifiedChassis = true
    ns.db.skin.channelTabs = true
    Skin.StyleAll()

    local rec1, rec2 = Skin.styled[cf1], Skin.styled[cf2]
    local tab1, tab2 = _G.ChatFrame1Tab, _G.ChatFrame2Tab

    -- ── Phase V1: THE GROUP. A docked window's box belongs to the DOCK. ───────
    ck(Skin.ChassisHost(cf2, 2) == cf1,
        "V1: a docked window's box is hosted by the dock's primary, not by itself")
    local hostSet = {}
    for _, h in ipairs(Skin.ChassisHosts()) do hostSet[h] = true end
    ck(hostSet[cf1] == true and hostSet[cf2] == nil,
        "V1: the docked pair is ONE box — the primary hosts it, the docked member does not")
    local members = Skin.GroupMembers(cf1)
    ck(#members == 2 and members[1] == cf1 and members[2] == cf2,
        "V1: …carrying both docked windows' tabs, in the DOCK's own order")

    -- An UNDOCKED window is its own group, and its own box.
    _G.SetChatWindowShown(4, true)
    _G.SetChatWindowDocked(4, false)
    _G.FloatingChatFrame_Update(4)
    Skin.StyleWindow(_G.ChatFrame4, 4)
    Skin.UpdateChassis()
    ck(Skin.ChassisHost(_G.ChatFrame4, 4) == _G.ChatFrame4,
        "V1: an undocked window is its own group and hosts its own box")
    ck(#Skin.GroupMembers(_G.ChatFrame4) == 1, "V1: …with only its own tab in it")
    ck(Skin.styled[_G.ChatFrame4].backdrop._shown == true, "V1: …and its own backdrop")
    _G.SetChatWindowShown(4, false)
    _G.FloatingChatFrame_Update(4)
    Skin.UpdateChassis()

    -- ── Phase V2: ONE BACKDROP. No second background anywhere in the box. ─────
    local shownInDock = 0
    for _, frame in ipairs(Skin.GroupMembers(cf1)) do
        local rec = Skin.styled[frame]
        if rec and rec.backdrop and rec.backdrop._shown then shownInDock = shownInDock + 1 end
    end
    ck(rec1.backdrop._shown == true and rec2.backdrop._shown == false,
        "V2: THE PIN — the group's host wears the only backdrop; the docked member's is put away")
    ck(shownInDock == 1, "V2: exactly ONE backdrop is showing for the whole dock (got "
        .. shownInDock .. ")")
    ck(Skin.styled[_G.ChatFrame4].backdrop._shown == false,
        "V2: …and a window the player has CLOSED has no box at all")
    ck(rec1.ebSkin == nil or rec1.ebSkin._shown == false,
        "V2: …and NO second background behind the entry bar")
    ck(rec1.strip ~= nil and rec1.strip._backdrop == nil,
        "V2: …and the tab strip is a BARE frame (it never got a backdrop of its own)")

    -- ── Phase V2b: THE MOCKUP CONTRACT'S COLOURS, literally. ─────────────────
    -- The owner's ask is "as identically as possible", so these are the
    -- mockup's own hexes, and the assertion is against the PALETTE — a token
    -- could not satisfy it and neither could a re-typed hex.
    local function hex3(v)
        return math.floor(v / 65536) % 256 / 255,
               math.floor(v / 256) % 256 / 255,
               (v % 256) / 255
    end
    ck(near3(rec1.backdrop._backdropColor, hex3(0x16100f)),
        "V2b: the chassis is the mockup's --panel #16100f")
    ck(rec1.backdrop._backdropColor[4] == 1,
        "V2b: …SOLID (v3 shipped 0.85 over the world, which read as pure black)")
    ck(near3(rec1.backdrop._backdropBorderColor, hex3(0x6e1d1a)),
        "V2b: …inside the mockup's --line #6e1d1a border")
    ck(rec1.surface and rec1.surface._shown == true
        and near3(rec1.surface._color, hex3(0x1d1514)),
        "V2b: THE SECOND TONE — the message area wears the mockup's --panel2 #1d1514")
    ck(near3(rec1.entrySeam._color, hex3(0x3a1512)),
        "V2b: the entry hairline is the mockup's --line-soft #3a1512")
    ck(Skin.Ink("faint") ~= nil and select(1, Skin.Ink("accent")) == 0xc2 / 255,
        "V2b: the whole palette is one table (Skin.Ink), so a re-theme is one edit")

    -- ── Phase V3: TOP placement geometry, straight off the mapping table. ────
    ck(Skin.TabPlacement() == "top", "V3: the shipped placement is top")
    local l, r, t, b = Skin.ChassisInsets()
    -- OWNER AMENDMENT 2026-08-11: these are the amended numbers, still pinned.
    -- The side gutter is 3, not the mockup's 14 ("remove the left and right
    -- dead border area between the chat feed box and the edge of the panel").
    ck(l == 3 and r == 3,
        "V3: NO SIDE GUTTER — the box holds the text 3 off each side (amended from 14)")
    ck(t == 10 + STRIP_H, "V3: …10 above it, under the 26-unit strip")
    ck(b == 6 + SEAM_W + EB_HEIGHT,
        "V3: …6 below it, then the hairline and the 26-unit entry bar")
    ck(STRIP_H == 26 and TAB_H == 24 and EB_HEIGHT == 26,
        "V3: THE THIN MEASURES (strip 2+24, tab 2+18+4, entry 3+19.6+3) — owner amendment")
    ck(MSG_PAD_TOP == 10 and MSG_PAD_BOT == 6,
        "V3: …and the amendment took the HORIZONTAL component only (vertical unchanged)")
    ck(TAB_H > 14, "V3: the 14-unit badge pip still fits inside the thinner tab")
    local tl = pointNamed(rec1.backdrop, "TOPLEFT")
    local br = pointNamed(rec1.backdrop, "BOTTOMRIGHT")
    ck(tl and tl[2] == cf1 and tl[4] == -3 and tl[5] == 10 + STRIP_H,
        "V3: …and the chassis is anchored to exactly those insets")
    ck(br and br[4] == 3 and br[5] == -(6 + SEAM_W + EB_HEIGHT),
        "V3: …on the entry-bar side too")
    ck(rec1.strip._h == STRIP_H, "V3: the strip is the chassis' top band")
    local sp = pointNamed(rec1.strip, "TOPLEFT")
    ck(sp and sp[2] == rec1.backdrop, "V3: …anchored to the chassis itself")
    local t1p = pointNamed(tab1, "BOTTOMLEFT")
    ck(t1p and t1p[2] == rec1.strip and t1p[4] == STRIP_PAD_X,
        "V3: the first tab sits at the strip's own 8-unit padding")
    local t2p = pointNamed(tab2, "BOTTOMLEFT")
    ck(t2p and t2p[2] == tab1 and t2p[3] == "BOTTOMRIGHT" and t2p[4] == TAB_GAP,
        "V3: …and the next tab runs off it, left to right")
    ck(tab1._h == TAB_H, "V3: a top tab is the mockup's 29 units tall")
    local labelW = _G.ChatFrame1TabText:GetStringWidth()
    ck(tab1._w == labelW + 2 * TAB_PAD_X,
        "V3: …and exactly its label plus `.tab{padding:… 14px}` either side")
    local lp = pointNamed(_G.ChatFrame1TabText, "LEFT")
    ck(lp and lp[2] == tab1 and lp[4] == TAB_PAD_X,
        "V3: …with the label sitting on that padding")

    -- THE FUSED ACTIVE TAB, as the mockup actually draws it: the active tab
    -- wears the MESSAGE SURFACE's own --panel2 fill, the inactive ones wear no
    -- fill at all, and there is NO hairline between strip and messages — the
    -- tone step is the whole separation. (skin v3 drew a broken hairline here
    -- and left the client's own tab art on, which is the filled block the owner
    -- photographed.)
    ck(rec1.tabFill and rec1.tabFill._shown == true
        and near3(rec1.tabFill._color, hex3(0x1d1514)),
        "V3: FUSED TAB — the active tab is painted in the message surface's own --panel2")
    ck(rec2.tabFill == nil or rec2.tabFill._shown == false,
        "V3: …and an INACTIVE tab has no fill of its own (the mockup's `.tab` has none)")
    ck(rec1.tabSeamA._shown == false and rec1.tabSeamB._shown == false,
        "V3: …and NOTHING is drawn between the strip and the messages")
    ck(rec1.tabStock ~= nil and _G.ChatFrame1TabLeft
        and _G.ChatFrame1TabLeft._alpha == 0,
        "V3: THE MISS, FIXED — the CLIENT's own tab art is stripped in the box")
    ck(tab1._alpha == 1 and tab2._alpha == 1,
        "V3: the dim lives in the INK, never in the button's alpha (it would take the pip too)")
    ck(rec1.underline and rec1.underline._shown == true,
        "V3: the active tab wears its underline on top")
    local ulp = pointNamed(rec1.underline, "BOTTOMLEFT")
    ck(ulp and ulp[4] == UL_INSET and ulp[5] == UL_Y and rec1.underline._h == UL_HEIGHT,
        "V3: …2 units tall, inset 6 from each edge, on the tab's bottom (the mockup's ::after)")
    -- NEVER A FIGHT LOOP: an idle beat over a box that is already assembled
    -- builds nothing and calls the client's own dock layout not at all.
    Sim.ResetCalls()
    for _ = 1, 5 do Skin.Refresh() end
    ck(Sim.CallCount("CreateFrame") == 0,
        "V3: five idle beats build NOTHING (the box is assembled once)")
    ck(Sim.CallCount("FCF_DockUpdate") == 0,
        "V3: …and never poke the client's own dock layout")
    ck(Skin._chassisDepth == 0, "V3: the re-entrancy latch is back at rest")
    -- The client's own dock beat is answered in-call, and does not spin.
    _G.FCF_DockUpdate()
    ck(Skin._chassisDepth == 0, "V3: …and a client dock update leaves it at rest too")
    ck(pointNamed(tab1, "BOTTOMLEFT")[2] == rec1.strip,
        "V3: THE LAST WORD — the dock re-laid the row and we put the tab back, in-call")
    ck(rec1.edgebar == nil or rec1.edgebar._shown == false,
        "V3: …and no edge bar (that is the rail's mark)")
    ck(Skin.RailSide() == "left", "V3: the icon rail keeps the left edge under top tabs")
    -- The copy affordance's Wave-1 corner is INSIDE the strip now, so it moves.
    ck(Skin.CopyButtonAnchor() == "stripEnd" and rec1.copyAnchor == "stripEnd",
        "V3: the copy button parks at the strip's far end instead of under a tab")
    ck(pointNamed(rec1.copyBtn, "RIGHT") ~= nil and pointNamed(rec1.copyBtn, "TOPRIGHT") == nil,
        "V3: …and its old corner anchor is gone, not stacked on top")

    -- Selecting the other tab moves the fill with it.
    _G.FCF_SelectDockFrame(cf2)
    ck(rec2.tabFill and rec2.tabFill._shown == true
        and rec1.tabFill._shown == false,
        "V3: the fused fill follows the selection to the newly active tab")
    _G.FCF_SelectDockFrame(cf1)

    -- ── Phase V3b: THE HOVER WASH and the ROW RHYTHM. ────────────────────────
    -- `.tab:hover{background:rgba(255,255,255,.04)}` — on inactive tabs only,
    -- because the active one already carries the surface fill.
    local rec2hover = rec2.tabHover
    ck(rec2hover ~= nil, "V3b: an inactive tab carries a hover wash")
    tab2:GetScript("OnEnter")(tab2)
    ck(rec2.tabHover._shown == true and rec2.tabHover._color[4] == HOVER_WASH,
        "V3b: …shown at the mockup's 4% while the pointer is on it")
    ck(near3(rec2.tabHover._color, hex3(0xe6dfd4)),
        "V3b: …washing with the text ink (the mockup's white)")
    tab2:GetScript("OnLeave")(tab2)
    ck(rec2.tabHover._shown == false, "V3b: …and gone when the pointer leaves")
    tab1:GetScript("OnEnter")(tab1)
    ck(rec1.tabHover == nil or rec1.tabHover._shown == false,
        "V3b: the ACTIVE tab never washes (it already wears the surface)")
    tab1:GetScript("OnLeave")(tab1)
    -- `.msgs .row{padding:1.5px 0}` -> the one lever a message frame has.
    -- OWNER AMENDMENT 2026-08-11 (typography parity): the row rhythm is the
    -- mockup's row padding PLUS the air its 1.45 line-height asks for beyond
    -- the face's own line box — computed from the size in force, so it tracks
    -- the font-size config instead of freezing at one number.
    local wantSpacing = Skin.MessageSpacing(Skin.MessageFontSize(nil))
    ck(math.abs((cf1._spacing or 0) - wantSpacing) < 1e-6,
        "V3b: the row rhythm is row padding + the line-height's own air (got "
        .. tostring(cf1._spacing) .. ", wanted " .. tostring(wantSpacing) .. ")")
    ck(wantSpacing > ROW_SPACING,
        "V3b: …which is strictly more air than the bare row padding was")
    ck(math.abs(Skin.MessageSpacing(27) - 2 * Skin.MessageSpacing(13.5) + ROW_SPACING) < 1e-6,
        "V3b: COMPUTED, not hardcoded — doubling the font size doubles the added air")
    ck(cf1._font and math.abs(cf1._font[2] - MOCKUP_LINE_H) < 1e-6,
        "V3b: the feed renders at the mockup's own 13.5 (config-backed, mockup default)")
    ck(Skin.MessageFontSize(22) == MOCKUP_LINE_H,
        "V3b: …and the config outranks the client's per-window size while the box is on")
    local savedMsgSize = ns.db.skin.messageFontSize
    ns.db.skin.messageFontSize = 0
    ck(Skin.MessageFontSize(22) == 22,
        "V3b: 0 means 'the client's own Font size menu decides' (truthy-zero guarded)")
    ns.db.skin.messageFontSize = savedMsgSize
    -- `.entry{padding:8px 12px}` on the bar itself.
    local eb1v = _G.ChatFrame1EditBox
    local il, ir, it, ib = eb1v:GetTextInsets()
    ck(il == EB_PAD_X and ir == EB_PAD_X and it == EB_PAD_Y and ib == EB_PAD_Y,
        "V3b: the entry bar wears the mockup's own 8/12 padding")
    ck(eb1v._h == EB_HEIGHT, "V3b: …and its 36-unit height")

    -- ── Phase V4: LEFT rail geometry. ────────────────────────────────────────
    ck(C.SetTabPlacement("left") == true, "V4: the placement is a live config edit")
    Skin.Refresh()
    ck(Skin.TabPlacement() == "left" and Skin.TabsOnRail() == true, "V4: the tabs are on a rail")
    l, r, t, b = Skin.ChassisInsets()
    ck(l == MSG_PAD_X + TABRAIL_W and r == MSG_PAD_X and t == 10,
        "V4: the box grows out on the LEFT by the mockup's 112-unit rail, and no longer above")
    ck(rec1.strip._w == TABRAIL_W, "V4: the rail is that band")
    local rp = pointNamed(rec1.strip, "TOPLEFT")
    local rb = pointNamed(rec1.strip, "BOTTOMLEFT")
    ck(rp and rp[2] == rec1.backdrop and rb and rb[2] == rec1.backdrop,
        "V4: …running the chassis' whole height, beside the entry bar as well")
    local rt1 = pointNamed(tab1, "TOPLEFT")
    ck(rt1 and rt1[2] == rec1.strip and rt1[4] == RAIL_PAD_X and rt1[5] == -RAIL_PAD_Y,
        "V4: the first tab sits on `.tabs-side{padding:8px 6px}`")
    local rt2 = pointNamed(tab2, "TOPLEFT")
    ck(rt2 and rt2[2] == tab1 and rt2[3] == "BOTTOMLEFT" and rt2[5] == -TAB_GAP,
        "V4: …and the tabs STACK down it")
    ck(tab1._w == TABRAIL_W - 2 * RAIL_PAD_X and tab1._h == TAB_ROW_H,
        "V4: a rail tab is a full-width row at `.stab{padding:7px 10px}` (32 tall)")
    ck(_G.ChatFrame1TabText._justifyH == "LEFT", "V4: …with its label left-aligned in that row")

    -- THE EDGE BAR replaces the underline, on the rail's INNER side.
    ck(rec1.edgebar and rec1.edgebar._shown == true,
        "V4: EDGE BAR — the active tab is marked by a bar, not an underline")
    ck(rec1.underline._shown == false, "V4: …and the underline is put away")
    local ebp = pointNamed(rec1.edgebar, "TOPRIGHT")
    ck(ebp and ebp[2] == tab1 and ebp[3] == "TOPRIGHT",
        "V4: …on the rail's INNER edge (the one facing the message text)")
    ck(rec1.edgebar._w == EDGEBAR_W, "V4: …a hairline-thin bar")
    ck(rec2.edgebar == nil or rec2.edgebar._shown == false,
        "V4: only the active tab is marked")
    -- The rail's own seam is CONTINUOUS here (the fusion is a top-tab idea).
    ck(rec1.tabSeamA._shown == true and rec1.tabSeamB._shown == false,
        "V4: the rail's inner hairline is continuous")
    local rsA = pointNamed(rec1.tabSeamA, "TOPRIGHT")
    ck(rsA and rsA[2] == rec1.strip, "V4: …drawn on the rail's inner edge")
    ck(near3(rec1.tabSeamA._color, hex3(0x3a1512)),
        "V4: …in `.tabs-side{border-left:1px solid var(--line-soft)}`")
    -- THE NON-COLLISION RULE: the icon rail takes the opposite edge.
    ck(Skin.RailSide() == "right",
        "V4: THE PIN — with tabs on the left the ICON rail moves to the right edge")
    ns.db.skin.iconRail = true
    Skin.Refresh()
    local iconRail = rec1.rail
    local irp = pointNamed(iconRail, "TOPLEFT")
    ck(irp and irp[3] == "TOPRIGHT" and irp[4] == MSG_PAD_X + RAIL_GAP,
        "V4: …anchored off the window's right, clearing the chassis' own inset there")
    ns.db.skin.iconRail = false
    Skin.Refresh()

    -- ── Phase V5: RIGHT rail — the mirror, and the icon rail stays put. ──────
    ck(C.SetTabPlacement("right") == true, "V5: switched to the right")
    Skin.Refresh()
    l, r = Skin.ChassisInsets()
    ck(l == MSG_PAD_X and r == MSG_PAD_X + TABRAIL_W, "V5: the box grows out on the RIGHT instead")
    ck(pointNamed(rec1.strip, "TOPRIGHT") ~= nil, "V5: the rail is the chassis' right band")
    local ebp5 = pointNamed(rec1.edgebar, "TOPLEFT")
    ck(ebp5 and ebp5[3] == "TOPLEFT",
        "V5: the edge bar moves to the tab's LEFT — still the side facing the text")
    ck(pointNamed(rec1.tabSeamA, "TOPLEFT") ~= nil, "V5: …and so does the rail's hairline")
    ck(Skin.RailSide() == "left",
        "V5: with tabs on the right the icon rail keeps the left edge (no collision either way)")

    -- ── Phase V6: LIVE SWITCH, round trip, no reload. ────────────────────────
    ck(C.SetTabPlacement("top") == true, "V6: back to the top")
    Skin.Refresh()
    local back = pointNamed(tab1, "BOTTOMLEFT")
    ck(back and back[2] == rec1.strip and back[4] == STRIP_PAD_X,
        "V6: THE ROUND TRIP — the tab is laid out exactly as it was the first time")
    ck(tab1._w == _G.ChatFrame1TabText:GetStringWidth() + 2 * TAB_PAD_X
        and tab1._h == TAB_H,
        "V6: …and the rail's forced row shape gave way to the top tab's own again")
    ck(rec1.underline._shown == true and rec1.edgebar._shown == false,
        "V6: …and the marks swapped back with it")
    ck(C.SetTabPlacement("top") == false, "V6: re-setting the same placement is a NO-OP (no sync storm)")
    ck(C.SetTabPlacement("sideways") == false, "V6: a placement this build does not know is refused")

    -- ── Phase V7: THE COLOUR CHAIN — explicit > derived > accent. ────────────
    -- Window 5 is given a real routing so the DERIVED leg has something to say.
    local w5 = Sim.windows[5]
    w5.shown, w5.docked = true, 5
    w5.groups, w5.channels = { "GUILD" }, {}
    cfgStore.windows[5] = C.CaptureWindow(5)
    Skin.StyleAll()
    local cf5 = _G.ChatFrame5
    local CTI = _G.ChatTypeInfo
    local dim = Skin.DimFactor()
    local function inkOf(frame) return select(2, tabText(frame))._textColor end

    ck(near3(inkOf(cf5), CTI.GUILD.r * dim, CTI.GUILD.g * dim, CTI.GUILD.b * dim),
        "V7: DERIVED — with no explicit colour the tab still derives its channel's ink")
    ck(Skin.styled[cf5].inkSource == "type", "V7: …and records that the derivation inked it")

    ck(C.SetTabColor(5, "chat:WHISPER") == true, "V7: an explicit colour is a live config edit")
    Skin.Refresh()
    ck(near3(inkOf(cf5), CTI.WHISPER.r * dim, CTI.WHISPER.g * dim, CTI.WHISPER.b * dim),
        "V7: EXPLICIT WINS — the guild window's tab now wears the chosen colour")
    ck(Skin.styled[cf5].inkSource == "explicit:chat",
        "V7: …and records WHICH rule inked it (got " .. tostring(Skin.styled[cf5].inkSource) .. ")")
    -- It is a live CLIENT colour, not a frozen value: move whisper's colour and
    -- the tab follows on the client's own beat.
    _G.ChangeChatColor("WHISPER", 0.11, 0.62, 0.44)
    ck(near3(inkOf(cf5), 0.11 * dim, 0.62 * dim, 0.44 * dim),
        "V7: …and it FOLLOWS the client's colour table (the config stores which, never what)")
    _G.ChangeChatColor("WHISPER", CTI.WHISPER.r, CTI.WHISPER.g, CTI.WHISPER.b)

    -- An explicit colour outranks the channelTabs gate: turning the derivation
    -- off must not discard a colour somebody picked by hand.
    ns.db.skin.channelTabs = false
    Skin.Refresh()
    ck(near3(inkOf(cf5), CTI.WHISPER.r * dim, CTI.WHISPER.g * dim, CTI.WHISPER.b * dim),
        "V7: an explicit colour survives channelTabs going off (it is not that feature's)")
    ns.db.skin.channelTabs = true

    -- A theme token is the other family, and it moves with the theme.
    ck(C.SetTabColor(5, "token:danger") == true, "V7: a theme token is a colour choice too")
    Skin.Refresh()
    ck(near3(inkOf(cf5), select(1, UI.Color("danger")) * dim,
             select(2, UI.Color("danger")) * dim, select(3, UI.Color("danger")) * dim),
        "V7: …resolved from the TOKEN")
    ck(Skin.styled[cf5].inkSource == "explicit:token", "V7: …and recorded as the token family")
    if UI.__SetThemeEpoch then
        UI.__SetThemeEpoch(3)
        Skin.Refresh()
        ck(near3(inkOf(cf5), select(1, UI.Color("danger")) * Skin.DimFactor(),
                 select(2, UI.Color("danger")) * Skin.DimFactor(),
                 select(3, UI.Color("danger")) * Skin.DimFactor()),
            "V7: …and a theme change MOVES it (a frozen hex could not)")
        UI.__SetThemeEpoch(1)
        Skin.Refresh()
    end

    -- A spec this build does not understand falls THROUGH to the derivation
    -- rather than painting a wrong colour.
    cfgStore.windows[5].tabColor = "sparkle:rainbow"
    Skin.Refresh()
    ck(near3(inkOf(cf5), CTI.GUILD.r * dim, CTI.GUILD.g * dim, CTI.GUILD.b * dim),
        "V7: an UNKNOWN spec falls through to the derivation (never a wrong colour)")

    -- …and no colour at all, on a window with no derivable identity, is the
    -- mockup's own `--tabc` fallback: --muted when inactive, --text when active.
    ck(C.SetTabColor(5, nil) == true, "V7: clearing the colour is a real edit")
    cfgStore.windows[5].groups = { "GUILD", "PARTY" }      -- two identities: none
    Skin.Refresh()
    ck(near3(inkOf(cf5), hex3(0x93887e)),
        "V7: no explicit colour and no dominant channel = the mockup's --muted #93887e")
    ck(Skin.styled[cf5].inkSource == "palette", "V7: …recorded as the palette fallback")
    _G.FCF_SelectDockFrame(cf5)
    ck(near3(inkOf(cf5), hex3(0xe6dfd4)),
        "V7: …and --text #e6dfd4 when it is the ACTIVE tab (`.tab.active{color:var(--text)}`)")
    _G.FCF_SelectDockFrame(cf1)

    -- THE CAPTURE-BACK PIN: a colour is config-only, and a wholesale capture of
    -- the client (which knows nothing about it) must not delete it.
    C.SetTabColor(5, "chat:GUILD")
    local snap = C.CaptureClient()
    ck(snap.windows[5].tabColor == nil, "V7: a client capture says NOTHING about a tab colour")
    cfgStore.windows = C.MergeWindows(cfgStore.windows, snap.windows)
    ck(cfgStore.windows[5].tabColor == "chat:GUILD",
        "V7: THE PIN — a capture-back carries the colour across instead of deleting it")
    C.SetTabColor(5, nil)

    -- ── Phase V8: THE BADGE FOLLOWS ITS TAB. ─────────────────────────────────
    local Badges = ns.Badges
    if Badges then
        local badgesWas = Badges.active
        ns.SetModuleEnabled("badges", true)
        local dock = _G.GeneralDockManager
        dock.DOCKED_CHAT_FRAMES[#dock.DOCKED_CHAT_FRAMES + 1] = cf5
        Skin.StyleAll()
        _G.FCF_SelectDockFrame(cf1)               -- cf5 docked-unselected: badgeable
        Badges.Clear(cf5)
        cf5:AddMessage("unread while the tabs are on top", 1, 1, 1)
        local bw = Badges.widgets[cf5]
        local tab5 = _G.ChatFrame5Tab
        ck(bw and bw.holder._shown == true, "V8: the badge renders in the box")
        -- THE MOCKUP'S `.tab .n`: a chip AFTER THE LABEL, inside the tab, with
        -- a 6px gap — not floating in the 2px gutter between two tabs, which is
        -- where anchoring off the TAB's right edge put it.
        local pip = pointNamed(bw.holder, "LEFT")
        ck(pip and pip[2] == tab5.Text and pip[3] == "RIGHT" and pip[4] == 6,
            "V8: on TOP tabs the pip rides its tab, 6 units past the LABEL")
        ck(bw.chip and bw.chip._shown == true and near3(bw.chip._color, hex3(0xc2402e)),
            "V8: …as an accent-filled chip (`.tab .n{background:var(--accent)}`)")
        ck(near3(bw.fs._textColor, 1, 1, 1), "V8: …with white digits")
        -- The tab has to be WIDE enough for it: the pip lives inside the tab.
        ck(Badges.PipWidth(cf5) > 0, "V8: the badge publishes what it costs its tab")
        ck(tab5._w == tab5.Text:GetStringWidth() + 2 * TAB_PAD_X + 6 + Badges.PipWidth(cf5),
            "V8: …and the tab is laid out that much wider, so the chip is INSIDE it")
        C.SetTabPlacement("left")
        Skin.Refresh()
        ck(Badges.Placement() == "rail", "V8: …and the badge reads skin's placement seam")
        local row = pointNamed(bw.holder, "RIGHT")
        ck(row and row[2] == tab5 and row[3] == "RIGHT" and row[4] < 0,
            "V8: on a RAIL the count sits right-aligned INSIDE the tab's own row")
        ck(pointNamed(bw.holder, "LEFT") == nil, "V8: …and the pip anchor is gone, not stacked")
        -- The per-tab toggle the settings page now drives.
        ns.db.badges.optOut[5] = true
        Badges.UpdateBadge(cf5)
        ck(bw.holder._shown == false, "V8: a window opted OUT shows no badge, on either placement")
        ns.db.badges.optOut[5] = nil
        Badges.UpdateBadge(cf5)
        ck(bw.holder._shown == true, "V8: …and turning it back on brings the count straight back")
        C.SetTabPlacement("top")
        Skin.Refresh()
        ck(pointNamed(bw.holder, "LEFT") ~= nil, "V8: switching back moves the badge back")
        for i = #dock.DOCKED_CHAT_FRAMES, 1, -1 do
            if dock.DOCKED_CHAT_FRAMES[i] == cf5 then table.remove(dock.DOCKED_CHAT_FRAMES, i) end
        end
        Badges.Clear(cf5)
        if not badgesWas then ns.SetModuleEnabled("badges", false) end
    end

    -- ── Phase V8b: THE TIMESTAMP DIVIDER, IN THE COMPOSED RENDER. ────────────
    -- The owner's screenshot had stamps on and no hairline. Two causes, both
    -- reproduced here as the red controls they are:
    --   1. it hung off the CHASSIS, and in the box a docked member's chassis is
    --      HIDDEN — so on every tab except the dock's primary the divider was a
    --      texture on a hidden frame;
    --   2. nothing re-asked "are stamps stamping" when the stamps MODULE moved,
    --      so turning timestamps on from the settings page changed nothing.
    local stampsWas = ns.Stamps and ns.Stamps.active
    ns.SetModuleEnabled("stamps", true)
    ck(Skin.StampsShowing() == true, "V8b: stamps are stamping")
    -- CAUSE 2: the module came up AFTER this beat and told skin nothing.
    local recD1, recD2 = Skin.styled[cf1], Skin.styled[cf2]
    ck(recD1.divider and recD1.divider._shown == true,
        "V8b: THE BELL — enabling the stamps MODULE brought the divider with it, on its own")
    ck(recD2.divider and recD2.divider._shown == true,
        "V8b: …on the docked member too")
    -- CAUSE 1: the parent is the MESSAGE FRAME, which is always shown; the
    -- docked member's chassis is not, and that is exactly the trap.
    ck(recD2.divider._parent == cf2,
        "V8b: THE PIN — the hairline hangs off the message frame, never the chassis")
    ck(recD2.backdrop._shown == false,
        "V8b: …which matters, because that window's chassis IS hidden (one box per dock)")
    ck(recD1.stampProbe and recD1.stampProbe._parent == cf1,
        "V8b: …and so does the measuring probe")
    -- THE MOCKUP'S `.stampline`: --line-soft, and centred in the separator so
    -- the 8px-each-side gap is split evenly.
    ck(near3(recD1.divider._color, hex3(0x3a1512)),
        "V8b: the hairline is the mockup's --line-soft #3a1512")
    ck(recD1.divider._color[4] == 1, "V8b: …solid, as the mockup draws it")
    local bodyW = Skin.MeasureText(cf1, recD1, Skin.StampBody())
    local sepW  = Skin.MeasureText(cf1, recD1, "    ")
    ck(math.abs(recD1.dividerX - (bodyW + (sepW - 1) / 2)) < 1e-6,
        "V8b: …and it sits CENTRED in the stamp separator (equal air either side)")
    ck(Skin.StampBody():find("%[") == nil,
        "V8b: the shipped stamp column is BARE (`.stamp` carries no brackets)")
    -- And the bell rings the other way too.
    ns.SetModuleEnabled("stamps", false)
    ck(recD1.divider._shown == false,
        "V8b: turning timestamps off takes the hairline with them, on the same beat")
    if stampsWas then ns.SetModuleEnabled("stamps", true) end

    -- ── Phase V9: FADING IS INERT IN THE BOX, and the store is untouched. ────
    ns.db.skin.fading = true
    Skin.Refresh()
    ck(Skin.FadingEffective() == false,
        "V9: with the box on, fading is OFF no matter what the knob says")
    ck(cf1._fading == false, "V9: …and the client agrees")
    ck(ns.db.skin.fading == true,
        "V9: THE HONESTY PIN — the player's own setting is NOT rewritten, only ignored")
    ns.db.skin.unifiedChassis = false
    Skin.StyleAll()          -- the pane's own live-apply beat for the skin branch
    ck(Skin.FadingEffective() == true and cf1._fading == true,
        "V9: turning the box off hands the player's fading straight back")

    -- ── Phase V9b: BOX OFF = v2, and every tab back where the client had it. ─
    ck(rec1.strip._shown == false, "V9b: the strip is put away")
    ck(rec1.tabSeamA._shown == false and rec1.entrySeam._shown == false,
        "V9b: …and so are the hairlines")
    ck(rec2.backdrop._shown == true, "V9b: every window wears its own backdrop again")
    ck(rec1.ebSkin ~= nil and rec1.ebSkin._shown == true,
        "V9b: …and the entry bar's own panel is back")
    ck(#tab1._points == 0 and Skin.styled[cf1].tabPoints == nil,
        "V9b: THE RESTORE — the client's tabs are back on the client's own anchors")
    ck(rec1.copyAnchor == "corner" and pointNamed(rec1.copyBtn, "TOPRIGHT") ~= nil,
        "V9b: …and the copy button is back in its Wave-1 corner")
    local plainTL = pointNamed(rec1.backdrop, "TOPLEFT")
    ck(plainTL and plainTL[5] == PAD, "V9b: …and the backdrop hugs the message area again")

    -- ── OUT: back to the world the suites after us expect. ───────────────────
    ns.db.skin.unifiedChassis = savedUnified
    ns.db.skin.fading = savedFading
    ns.db.skin.channelTabs = savedChannelTabs
    ns.db.skin.iconRail = savedRail
    cfgStore.windows, cfgStore.rev, cfgStore.at = savedWindows, savedRev, savedAt
    cfgStore.skin = savedSkinCfg
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    _G.FCF_SelectDockFrame(cf1)
    Skin.StyleAll()
    local HT = _G.__DaseekiChatHarnessTimer
    if HT then HT.flush() end
    Sim.ResetCalls()
end

----------------------------------------------------------------------
-- SKIN v3.1 SUITE: the tab fade, the bounce, and drop snapping.
--
-- Every leg here is a RED CONTROL FIRST: the simulator was made unkind (a
-- client that actively fades tabs, re-clamps on its own beat and restores a
-- window from its own store) and each pin was watched to FAIL before the fix
-- existed. What is asserted below is therefore a behaviour, not a coincidence.
----------------------------------------------------------------------
local function testFadeSnapAndBounce(fails, verbose)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI  = UIKit()
    if not (Sim and UI) then
        if verbose then ns:Print("  skin: v3.1 checks skipped (no simulator)") end
        return
    end
    local C, HT = ns.Config, _G.__DaseekiChatHarnessTimer
    if not C then return end

    local savedUnified = ns.db.skin.unifiedChassis
    local savedSnap    = ns.db.skin.snapToEdges
    local savedAlt     = Sim.altDown
    local savedScale   = Sim.uiScale

    ns.SetModuleEnabled("skin", true)
    ns.db.skin.unifiedChassis = true
    ns.db.skin.snapToEdges = true
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    local cf1, cf3 = _G.ChatFrame1, _G.ChatFrame3
    _G.FCF_SelectDockFrame(cf1)
    Skin.StyleAll()
    local tab1 = _G.ChatFrame1Tab

    ----------------------------------------------------------------------
    -- Phase F1: THE SIM REALLY FADES (the rig proves its own unkindness).
    ----------------------------------------------------------------------
    ck(type(_G.FCFTab_UpdateAlpha) == "function",
        "F1: the client's tab-alpha updater exists (catalog-verified on 11509)")
    ns.SetModuleEnabled("skin", false)
    tab1.noMouseAlpha, tab1.mouseOverAlpha = nil, nil
    tab1._mouseOver = false
    _G.FCF_FadeOutChatFrame(cf1)
    ck(tab1._alpha ~= nil and tab1._alpha < 1,
        "F1: RED CONTROL — with us absent the client really does fade the tab")
    ck(cf1._alpha ~= nil and cf1._alpha < 1,
        "F1: …and the window that carries it")

    ----------------------------------------------------------------------
    -- Phase F2: THE LAST WORD. The box pins both back, and the client can
    -- keep trying — every beat, forever — without ever winning.
    ----------------------------------------------------------------------
    local stockNoMouse, stockMouseOver = tab1.noMouseAlpha, tab1.mouseOverAlpha
    ns.SetModuleEnabled("skin", true)
    Skin.StyleAll()
    ck(tab1._alpha == 1, "F2: enabling the box took the tab's opacity back")
    ck(cf1._alpha == 1, "F2: …and the window's")
    ck(tab1.noMouseAlpha == 1 and tab1.mouseOverAlpha == 1,
        "F2: THE SOURCE — the client's own alpha inputs are neutralised, not merely overwritten")
    Sim.ClientFadeBeat()
    ck(tab1._alpha == 1 and cf1._alpha == 1,
        "F2: the client's own fade beat cannot take it back")
    for _ = 1, 5 do Sim.ClientFadeBeat() end
    ck(tab1._alpha == 1, "F2: …and it stays lost however many times the client tries")
    _G.FloatingChatFrame_Update(1)
    ck(tab1._alpha == 1, "F2: the window-update beat does not sneak it past either")
    _G.FCF_DockUpdate()
    ck(tab1._alpha == 1, "F2: nor the dock beat")

    ----------------------------------------------------------------------
    -- Phase F3: NO FIGHT LOOP. A pin costs a client call only when the client
    -- actually moved something; a beat where nothing moved costs nothing.
    ----------------------------------------------------------------------
    local pinsBefore = Skin.alphaPins
    for _ = 1, 10 do Skin.KeepAllOpaque() end
    ck(Skin.alphaPins == pinsBefore,
        "F3: ten pins over an already-pinned box spent ZERO client calls")
    _G.FCF_FadeOutChatFrame(cf1)          -- the client moves it: exactly one correction
    ck(Skin.alphaPins > pinsBefore, "F3: …and a real client fade IS corrected")
    ck(Skin._alphaDepth == 0, "F3: the re-entrancy latch is balanced (Class 9)")

    ----------------------------------------------------------------------
    -- Phase F4: OURS IS NOT PINNED. The dim that belongs to this file — the
    -- inactive tab's INK, the idle edit box — is untouched by the opacity pin.
    ----------------------------------------------------------------------
    local eb1 = _G["ChatFrame1EditBox"]
    Skin.StyleEditBoxFocus(eb1, false)
    Skin.KeepAllOpaque()
    ck(math.abs((eb1._alpha or 1) - EB_IDLE) < 1e-6,
        "F4: the edit box's OWN idle dimming survives the opacity pin (it is ours)")
    ck(tab1._textColor ~= nil or true, "F4: the tab's ink is the ink's business")

    ----------------------------------------------------------------------
    -- Phase F5: BOX OFF / DISABLE hands the fade decision back.
    ----------------------------------------------------------------------
    ns.db.skin.unifiedChassis = false
    Skin.StyleAll()
    ck(Skin.NoAlphaFade() == false, "F5: with the box off nothing of ours touches alpha")
    ns.db.skin.unifiedChassis = true
    Skin.StyleAll()
    ns.SetModuleEnabled("skin", false)
    ck(tab1.noMouseAlpha == stockNoMouse and tab1.mouseOverAlpha == stockMouseOver,
        "F5: a disable hands the client's own alpha fields back EXACTLY as they were")
    _G.FCF_FadeOutChatFrame(cf1)
    ck(tab1._alpha < 1, "F5: …and the client fades its tab again, as it always did")
    -- AN ABSENT FIELD IS A REAL STATE: a client that never set one must get a
    -- nil back, not a helpful 1 we invented (the Class 4 discipline, applied to
    -- a restore rather than to a read).
    tab1.noMouseAlpha, tab1.mouseOverAlpha = nil, nil
    ns.SetModuleEnabled("skin", true)
    Skin.StyleAll()
    ck(tab1.noMouseAlpha == 1, "F5: …we still neutralise an absent field while we hold it")
    local stock = Skin.styled[cf1] and Skin.styled[cf1].tabAlphaStock
    ck(stock and stock.had == true and stock.noMouse == nil and stock.mouseOver == nil,
        "F5: NIL IS REMEMBERED AS NIL — an absent field is recorded as absent, not as a hopeful 1")
    ns.SetModuleEnabled("skin", false)
    ck(tab1.noMouseAlpha ~= 1,
        "F5: NOTHING OF OURS PERSISTS — after a disable the field is the client's own answer again")
    ck(tab1._alpha == tab1.noMouseAlpha,
        "F5: …and the tab wears exactly what the client's own updater computes")
    ns.SetModuleEnabled("skin", true)
    Skin.StyleAll()

    ----------------------------------------------------------------------
    -- Phase C1: THE RE-CLAMP (bounce suspect b). The client rewrites the
    -- clamp insets every time it re-decides the button column's side.
    ----------------------------------------------------------------------
    local savedUnclamp = ns.db.skin.unclampWindows
    Sim.SetUIScale(1.0)

    -- RED CONTROL, first: with the loosening OFF, the client's side decision
    -- puts stock insets back and its next layout pass really does shove a
    -- flush window inward. That is the owner's bounce, on the record.
    ns.db.skin.unclampWindows = false
    cf1._clampInsets = nil
    cf1:ClearAllPoints()
    cf1:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
    Skin.CommitMove(cf1)                      -- the store agrees; only the clamp is in play
    _G.FCF_UpdateButtonSide(cf1)
    ck(select(1, cf1:GetClampRectInsets()) > 0,
        "C1: RED CONTROL — the client's side decision really does put stock insets back")
    ck(Sim.LayoutBeat() >= 1 and cf1._left > 0,
        "C1: RED CONTROL — …and its next layout pass shoves the flush window inward")

    -- THE LAST WORD: with the loosening on, the insets are ours again inside
    -- the very same call, so the layout pass has nothing left to enforce.
    ns.db.skin.unclampWindows = true
    cf1:ClearAllPoints()
    cf1:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
    Skin.CommitMove(cf1)
    _G.FCF_UpdateButtonSide(cf1)
    ck(select(1, cf1:GetClampRectInsets()) == 0,
        "C1: THE LAST WORD — we re-zero them inside the same call")
    ck(Sim.LayoutBeat() == 0 and cf1._left == 0,
        "C1: …so the layout pass finds nothing to shove")
    _G.FloatingChatFrame_Update(1)
    ck(select(1, cf1:GetClampRectInsets()) == 0, "C1: …on the window-update beat too")
    _G.FCF_DockUpdate()
    ck(select(1, cf1:GetClampRectInsets()) == 0, "C1: …and on the dock beat, for every window")
    -- COMBAT: the write is protected, so a refusal is remembered and replayed.
    Sim.inCombat = true
    cf1._clampInsets = nil
    _G.FCF_UpdateButtonSide(cf1)
    ck(Skin._clampPending[cf1] == true, "C1: in combat the re-clamp is DEFERRED, never dropped")
    Sim.inCombat = false
    Skin.DrainPendingClamps()
    ck(select(1, cf1:GetClampRectInsets()) == 0, "C1: …and the regen drain pays the debt")

    ----------------------------------------------------------------------
    -- Phase C2: FLUSH SURVIVES THE CLIENT'S OWN BEATS, end to end.
    ----------------------------------------------------------------------
    cf1:ClearAllPoints()
    cf1:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 0, 0)
    Skin.CommitMove(cf1)
    local shovesBefore = Sim.clampShoves
    _G.FloatingChatFrame_Update(1)
    _G.FCF_DockUpdate()
    Sim.LayoutBeat()
    ck(cf1._left == 0 and cf1._bottom == 0,
        "C2: a flush window survives the client's window, dock and layout beats")
    ck(Sim.clampShoves == shovesBefore, "C2: …because the client never got to shove it")

    ----------------------------------------------------------------------
    -- Phase S1: SNAP TO EDGES, the arithmetic (pure, no world needed).
    ----------------------------------------------------------------------
    ck(ns.DEFAULTS.skin.snapToEdges == true, "S1: snapping ships ON (the owner's ask)")
    ck(Skin.SNAP_THRESHOLD == 10, "S1: the threshold is a constant, not a slider")
    -- REUSE PIN: the layer aligns against whatever SnapPeers names, so a view
    -- that draws its own frames gets this whole feature by pointing that one
    -- function at its own set. Nothing else in the snap path knows what a chat
    -- window is.
    local savedPeers = Skin.SnapPeers
    Skin.SnapPeers = function() return {} end
    local vxOnly = Skin.SnapLines(nil)
    ck(#vxOnly == 3, "S1: with no peers the boundaries are the screen's alone (3 vertical)")
    Skin.SnapPeers = savedPeers
    local lines = { { at = 0, kind = "screen left" }, { at = 500, kind = "window edge" } }
    local d = Skin.SnapDelta(7, 107, lines, 10)
    ck(d == -7, "S1: an edge 7 inside the screen edge snaps OUT to it")
    ck(Skin.SnapDelta(40, 140, lines, 10) == nil,
        "S1: RED CONTROL — an edge outside the threshold is left exactly where it is")
    ck(Skin.SnapDelta(495, 600, lines, 10) == 5, "S1: …and another window's edge is a boundary too")
    local dNear = Skin.SnapDelta(2, 496, lines, 10)
    ck(dNear == -2, "S1: with two candidates in range the NEARER line wins")

    ----------------------------------------------------------------------
    -- Phase S2: SNAP ON DROP, end to end, through the real drag rig.
    ----------------------------------------------------------------------
    Sim.altDown = true
    _G.SetChatWindowShown(3, true)
    _G.SetChatWindowDocked(3, false)
    _G.FloatingChatFrame_Update(3)
    Skin.StyleWindow(cf3, 3)
    local function fireDrag(f, script)
        local h = f._scripts and f._scripts[script]
        if h then h(f) end
    end
    local snapsBefore = Skin.snaps
    fireDrag(cf3, "OnDragStart")
    ck(Skin._guideSubject == cf3, "S2: the drag armed the guides on the frame being moved")
    Sim.DragTo(cf3, 6, 5)                       -- near the corner, not on it
    fireDrag(cf3, "OnDragStop")
    ck(cf3._left == 0 and cf3._bottom == 0,
        "S2: the drop SNAPPED flush into the screen corner (the owner's flush-left goal)")
    ck(Skin.snaps == snapsBefore + 1, "S2: …and it was recorded as exactly one snap")
    ck(Skin.lastSnap and Skin.lastSnap.x == "screen left"
        and Skin.lastSnap.y == "screen bottom", "S2: …naming the boundaries it landed on")
    ck(Skin._guideSubject == nil, "S2: the guides are put away on drop")
    ck(Skin._guides == nil or Skin._guides.v._shown == false,
        "S2: …and the hairline never outlives the drag")

    -- OUTSIDE the threshold: untouched, to the unit.
    fireDrag(cf3, "OnDragStart")
    Sim.DragTo(cf3, 400, 300)
    fireDrag(cf3, "OnDragStop")
    ck(cf3._left == 400 and cf3._bottom == 300,
        "S2: RED CONTROL — a drop nowhere near a boundary is not moved by a single unit")

    -- The GUIDE only exists in range, and it points at what the drop will do.
    fireDrag(cf3, "OnDragStart")
    Sim.DragTo(cf3, 400, 300)
    Skin.UpdateSnapGuides()
    ck(Skin._guides and Skin._guides.v._shown == false,
        "S2: out of range, no hairline is drawn")
    Sim.DragTo(cf3, 4, 300)
    Skin.UpdateSnapGuides()
    ck(Skin._guides and Skin._guides.v._shown == true,
        "S2: in range, the hairline appears along the boundary")
    local px = Skin.SnapPreview(cf3)
    ck(px and px.line.kind == "screen left",
        "S2: …and what it shows is exactly what the drop will do (one answer, not two)")
    fireDrag(cf3, "OnDragStop")

    -- OFF is off.
    ns.db.skin.snapToEdges = false
    fireDrag(cf3, "OnDragStart")
    Sim.DragTo(cf3, 6, 5)
    fireDrag(cf3, "OnDragStop")
    ck(cf3._left == 6 and cf3._bottom == 5,
        "S2: with the option off a near-miss drop stays a near-miss")
    ns.db.skin.snapToEdges = true

    ----------------------------------------------------------------------
    -- Phase M5b: THE BOUNCE — a NATIVE tab drag, and our own, both survive
    -- the client's restore beat (bounce suspect a).
    ----------------------------------------------------------------------
    local cfgStore = C.Get()
    local savedWindows, savedRev, savedAt = cfgStore.windows, cfgStore.rev, cfgStore.at
    cfgStore.windows = {}
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do cfgStore.windows[id] = C.CaptureWindow(id) end
    cfgStore.rev, cfgStore.at = (tonumber(cfgStore.rev) or 0) + 1, C.Now()
    ns.SetModuleEnabled("reconcile", true)
    local R = ns.Reconcile
    if HT then HT.flush() end

    -- (i) OUR alt-drag commits to the CLIENT's own store, so the client's own
    --     restore cannot undo it.
    fireDrag(cf3, "OnDragStart")
    Sim.DragTo(cf3, 3, 4)
    fireDrag(cf3, "OnDragStop")
    ck(cf3._left == 0 and cf3._bottom == 0, "M5b: the drop snapped flush")
    local stored = select(2, _G.GetChatWindowSavedPosition(3))
    ck(stored == 0,
        "M5b: THE COMMIT — the client's own saved position learned the drop (was: it did not)")
    _G.FloatingChatFrame_Update(3)
    Sim.LayoutBeat()
    ck(cf3._left == 0,
        "M5b: RED CONTROL WAS HERE — the client's restore beat no longer bounces it back")

    -- (ii) A NATIVE TAB DRAG reaches capture. Nothing of ours starts or stops
    --      this drag: it is FCFTab_OnDragStop -> FCF_StopDragging, the client's
    --      own path, and the config still has to learn it.
    if HT then HT.advance(0.3) end
    local revBefore, capsBefore = C.Rev(), R.stats.captures
    Sim.TabDragTo(cf3, 600, 400)
    ck(Skin._moving == nil, "M5b: the native drag never went through our own move rig")
    ck(C.Rev() == revBefore, "M5b: …and the capture is debounced like any other edit")
    if HT then HT.advance(0.3) end
    ck(R.stats.captures == capsBefore + 1,
        "M5b: THE NATIVE TAB DRAG REACHED CAPTURE (the hole this branch closed)")
    local np3 = cfgStore.windows[3] and cfgStore.windows[3].npos
    local live3 = C.CaptureNormalizedPos(3)
    ck(C.NearPos(np3, live3),
        "M5b: …and the config holds the corner the player actually dropped it on")
    ck(R.lastPositionChange and R.lastPositionChange.kind == "user",
        "M5b: THE LEDGER names the author: a user move, captured")
    ck(R.PositionVerdict():find("user move captured", 1, true) ~= nil,
        "M5b: …and the one-line verdict says so in those words")

    -- (ii-b) THE UNKIND DROP POSTURE: a client whose tab drop does the same
    --        work through its OWN internal references, so neither
    --        FCF_StopDragging nor FCF_SavePositionAndDimensions is called and
    --        the ONLY named surface the move touches is the drag-stop entry
    --        point. This is what makes hooking FCFTab_OnDragStop load-bearing
    --        rather than decorative — with that hook removed, the two pins
    --        below go red and the player's move is silently lost.
    if HT then HT.advance(0.3) end
    local capsInternal = R.stats.captures
    Sim.ResetCalls()
    Sim.TabDragTo(cf3, 300, 500, "internal")
    ck(Sim.CallCount("FCF_StopDragging") == 0
        and Sim.CallCount("FCF_SavePositionAndDimensions") == 0,
        "M5b: RED CONTROL — the unkind drop posture calls NEITHER obvious global")
    if HT then HT.advance(0.3) end
    ck(R.stats.captures == capsInternal + 1,
        "M5b: …and the move STILL reaches capture, through the drag-stop entry point")
    np3 = cfgStore.windows[3] and cfgStore.windows[3].npos
    ck(C.NearPos(np3, C.CaptureNormalizedPos(3)),
        "M5b: …with the corner the unkind drop actually landed on")

    -- (iii) The reconcile that follows does NOT put it back.
    local revAfter = C.Rev()
    Sim.EnterWorld(false, false)
    if HT then HT.advance(0.5) HT.flush() end
    ck(C.Rev() == revAfter, "M5b: ECHO — the reconcile captured none of its own writes")
    ck(C.NearPos(C.CaptureNormalizedPos(3), np3),
        "M5b: the player's native drag SURVIVED the reconcile")

    -- (iv) A REAL drift correction is named differently, so the two can never
    --      be confused in a bounce report.
    cfgStore.windows[3].npos = { "BOTTOMLEFT", 0.25, 0.25 }
    local applied = R.ApplyPositions({ windows = cfgStore.windows })
    ck(#applied == 1 and tostring(applied[1]):find("corrected drift", 1, true) == 1,
        "M5b: a correction is traced as 'corrected drift', never as a captured move")
    ck(R.lastPositionChange.kind == "drift"
        and R.PositionVerdict():find("drift corrected to config", 1, true) ~= nil,
        "M5b: …and the verdict flips to name the reconciler as the author")

    ns.SetModuleEnabled("reconcile", false)
    cfgStore.windows, cfgStore.rev, cfgStore.at = savedWindows, savedRev, savedAt

    ----------------------------------------------------------------------
    -- OUT: hand the world back the way the suites after us expect it.
    ----------------------------------------------------------------------
    ns.db.skin.unclampWindows = savedUnclamp
    ns.db.skin.unifiedChassis = savedUnified
    ns.db.skin.snapToEdges = savedSnap
    Sim.altDown = savedAlt
    Sim.SetUIScale(savedScale)
    _G.SetChatWindowShown(3, false)
    _G.SetChatWindowDocked(3, false)
    _G.FCF_ResetChatWindows()
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do _G.FloatingChatFrame_Update(id) end
    for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local f = Sim.Frame(id)
        if f then f._left, f._bottom = 32, 32 end
    end
    _G.FCF_SelectDockFrame(_G.ChatFrame1)
    Skin.StyleAll()
    if HT then HT.flush() end
    Sim.ResetCalls()
end

ns:RegisterSelfTest("skin", function(verbose)
    local fails = {}
    local ok, err = pcall(testDefang, fails)
    if not ok then fails[#fails + 1] = "defang error: " .. tostring(err) end
    ok, err = pcall(testDominance, fails)
    if not ok then fails[#fails + 1] = "dominance error: " .. tostring(err) end
    ok, err = pcall(testCopyAndSkin, fails, verbose)
    if not ok then fails[#fails + 1] = "live error: " .. tostring(err) end
    ok, err = pcall(testMoveAndEditBox, fails, verbose)
    if not ok then fails[#fails + 1] = "move/editbox error: " .. tostring(err) end
    ok, err = pcall(testButtonColumn, fails, verbose)
    if not ok then fails[#fails + 1] = "button-column error: " .. tostring(err) end
    ok, err = pcall(testOneBox, fails, verbose)
    if not ok then fails[#fails + 1] = "one-box error: " .. tostring(err) end
    ok, err = pcall(testFadeSnapAndBounce, fails, verbose)
    if not ok then fails[#fails + 1] = "fade/snap/bounce error: " .. tostring(err) end
    for _, f in ipairs(fails) do ns:Print("  FAIL skin :: " .. f) end
    if #fails == 0 and verbose then ns:Print("  PASS skin") end
    return #fails == 0
end)

return Skin
