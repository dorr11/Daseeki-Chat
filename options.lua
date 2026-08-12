-- Daseeki Chat — options.lua  (post-V1: the settings pane + the alias editor)
--
-- THE ASK (owner, 2026-08-11: "do we not have a configuration menu for chat?").
-- Everything in this addon has been config-gated since Wave 1, but the only
-- surface was /dchat subcommands. This file is the surface: the suite-standard
-- settings page, registered with Daseeki-Core's hub exactly the way every other
-- suite addon registers one (DaseekiSuite:RegisterAddon{ flow = true }, one
-- section with build(flow)/refresh — the Daseeki-Bags and Daseeki-Nexus idiom,
-- read and matched rather than reinvented).
--
-- THE ONE RULE THIS FILE HOLDS ITSELF TO: every control maps to a config field
-- that ALREADY EXISTS and is ALREADY READ by a shipping module. No control
-- invents behavior, and none writes a key nothing reads. That is not a promise
-- in a comment — Options.BINDINGS below is the declarative list of every
-- control's (branch, key), and the suite BIND-CHECKS the whole pane against
-- the modules' own default shapes: a control naming a field that does not
-- exist fails the harness. Fields with no natural control are listed, with the
-- reason, in Options.UNBOUND — visible, not silently missing.
--
-- LIVE, NEVER A RELOAD: every set closure writes the store and then re-applies
-- through the owning module's own public beat (Skin.StyleAll / Skin.Refresh /
-- Skin.UpdateDividers), the same way the module's own /dchat toggles do.
--
-- HUB SEQUENCING: Core 2.4.0's hub holds Begin/EndShow latches around the whole
-- show pass, so build(flow) and refresh(pane) run inside that discipline — a
-- re-entrant Open from inside a refresh is queued by Core, not nested. Nothing
-- here fights it: build is idempotent (guarded), refresh is pure re-read.
--
-- CORE IS A HARD DEPENDENCY, so the hub is always there — and registration is
-- still runtime-defended (house style: a suite surface never assumes a peer's
-- table shape). No hub, no page, no error, everything else unchanged.
--
-- INERTNESS: this is a lifecycle module. Disabled, it registers nothing with
-- the hub, subscribes to nothing and touches nothing — the same contract every
-- other module in this addon signs, and the harness's inertness gate covers it.

local ADDON, ns = ...

local Options = {
    active     = false,   -- module enable state
    registered = false,   -- the hub def has been handed over
    _built     = false,   -- build(flow) has run once (the pane is lazy)
}
ns.Options = Options

local MAX_ALIAS_ROWS = 10    -- pooled alias editor rows (the flow builds once)
local MAX_TAB_ROWS   = 10    -- one row per permanent chat window, same idiom

----------------------------------------------------------------------
-- THE CONFIG BRANCHES this pane speaks about.
--
-- Resolved LAZILY through the owning module's own published default table, so
-- there is exactly one definition of each branch's shape in the addon and this
-- file is never a second copy of it. `skin`, `history` and `badges` publish
-- theirs on ns.DEFAULTS (core's store defaults); `stamps`, `names` and `urls`
-- create their branch at enable time and publish the shape on their module
-- table. Either way, the shape below IS the module's own.
----------------------------------------------------------------------

local BRANCH_DEFAULTS = {
    skin    = function() return ns.DEFAULTS and ns.DEFAULTS.skin end,
    stamps  = function() return ns.Stamps and ns.Stamps.DEFAULTS end,
    names   = function() return ns.Names and ns.Names.DEFAULTS end,
    urls    = function() return ns.Urls and ns.Urls.DEFAULTS end,
    history = function() return ns.DEFAULTS and ns.DEFAULTS.history end,
    badges  = function() return ns.DEFAULTS and ns.DEFAULTS.badges end,
    -- D2 revision: the owned view's LOOK branch. Account-local by decision (see
    -- view.lua's config note) — the LAYOUT it renders (tab placement, per-tab
    -- colour, position) rides the SYNCED config and is bound below as `config`
    -- controls, exactly as skin v3's two were.
    view    = function() return ns.DEFAULTS and ns.DEFAULTS.view end,
}

function Options.BranchDefaults(branch)
    local fn = BRANCH_DEFAULTS[branch]
    if not fn then return nil end
    local ok, defs = pcall(fn)
    return ok and type(defs) == "table" and defs or nil
end

-- The live store branch, created additively if the owning module has not been
-- enabled yet (the modules' own EnsureDefaults idiom, called from here so a
-- setting can be changed before its module has ever come up).
function Options.Branch(branch)
    local defs = Options.BranchDefaults(branch)
    if not (ns.db and defs) then return nil end
    ns.EnsureDefaults(ns.db, { [branch] = defs })
    return ns.db[branch]
end

function Options.Get(branch, key)
    local t = Options.Branch(branch)
    if type(t) == "table" and t[key] ~= nil then return t[key] end
    local defs = Options.BranchDefaults(branch)
    return defs and defs[key]
end

----------------------------------------------------------------------
-- ============ THE APPLY SEAMS — THE HALF THAT WAS MISSING ============
--
-- THE DEFECT, HONESTLY (owner, 2026-08-11: "the options dont seem to actually
-- do anything. when i move any of the sliders or click the different options
-- nothing changes"). Both halves were checked, and only ONE was broken:
--
--   THE WRITE SIDE WAS FINE. Core's hub really does call a control's `set`
--   (UI.MakeCheckbox's OnClick, UI.MakeSlider's OnValueChanged), and the
--   closures really did land in the store. The store was right the whole time.
--
--   THE APPLY SIDE WAS THE DEFECT, in two ways at once:
--     1. `db.view.*` — the drawn window's own type sizes — had NO route at
--        all. The old branch-keyed LiveApply knew about skin/stamps/badges/
--        aliases and fell through to `return false` for `view`, so every one
--        of the sliders the owner reached for wrote a number nothing re-read.
--     2. the routes that DID exist went to skin.lua, whose restyle paths are
--        RETIRED while the view paints (Skin.ViewOwnsPixels). So "apply the
--        layout" reached a function that returns immediately, and the tab
--        placement only appeared to change when some later beat happened to
--        relayout the tabs — against a strip still wearing the old placement.
--        That is the owner's mixed strip/rail screenshot, exactly.
--
-- THE MECHANISM THAT REPLACES IT. Every seam is a NAMED, owning-module-public
-- re-apply beat; every binding in the table below DECLARES which seam its
-- write dispatches; and the bind-check REFUSES a binding that declares none.
-- A new control cannot be inert by omission any more — it cannot be added.
--
-- `run = false` is a first-class answer for a field with no standing surface
-- (history's cap is read at save time; a URL bracket rides the NEXT line to be
-- decorated), and the bind-check demands `whyNoApply` on any binding that
-- names one — so "nothing to re-apply" is always a decision on record.
----------------------------------------------------------------------

local function view()
    local V = ns.View
    return (V and V.active) and V or nil
end

local function skin()
    local S = ns.Skin
    return (S and S.active) and S or nil
end

Options.APPLY_SEAMS = {
    ["view.look"] = {
        what = "restyle every drawn message surface in place (buffers kept) and re-run the layout",
        run = function()
            local V = view()
            if V and V.ApplyLook then ns:SafeCall(V.ApplyLook) end
            local S = skin()      -- the box-off renderer, for when the view is down
            if not V and S and S.StyleAll then ns:SafeCall(S.StyleAll) end
        end,
    },
    ["view.layout"] = {
        what = "migrate the tab strip <-> rail, re-inset the feed and re-clamp the box",
        run = function()
            local V = view()
            if V and V.ApplyPlacement then ns:SafeCall(V.ApplyPlacement) end
            local S = skin()
            if S and S.StyleAll then ns:SafeCall(S.StyleAll) end
        end,
    },
    ["view.tabs"] = {
        what = "re-lay the tab run: labels, ink, per-tab colour, unread pips",
        run = function()
            local V = view()
            if V and V.ApplyTabs then ns:SafeCall(V.ApplyTabs) end
            local S = skin()
            if S and S.UpdateTabColors then ns:SafeCall(S.UpdateTabColors) end
        end,
    },
    ["view.furniture"] = {
        what = "the copy button and the corner grips",
        run = function()
            local V = view()
            if V and V.ApplyFurniture then ns:SafeCall(V.ApplyFurniture) end
            local S = skin()
            if S and S.StyleAll then ns:SafeCall(S.StyleAll) end
        end,
    },
    ["skin.restyle"] = {
        what = "re-dress the client's windows (the box-off renderer) and re-run the drawn layout",
        run = function()
            local S = skin()
            if S and S.StyleAll then ns:SafeCall(S.StyleAll) end
            local V = view()
            if V and V.ApplyLook then ns:SafeCall(V.ApplyLook) end
        end,
    },
    ["skin.editbox"] = {
        what = "re-anchor the entry bar (hosted in the drawn chassis, or on the client's window)",
        run = function()
            local S = skin()
            if S and S.StyleAll then ns:SafeCall(S.StyleAll) end
            local V = view()
            if V and V.ApplyEditBox then ns:SafeCall(V.ApplyEditBox) end
        end,
    },
    ["stamps.dividers"] = {
        what = "re-measure the timestamp column's divider (the format's widest literal)",
        run = function()
            local S = skin()
            if S and S.UpdateDividers then ns:SafeCall(S.UpdateDividers) end
            local V = view()
            if V and V.ApplyLook then ns:SafeCall(V.ApplyLook) end
        end,
    },
    ["badges.refresh"] = {
        what = "re-place and re-count every unread pip, then re-lay the tabs around them",
        run = function()
            local B = ns.Badges
            if B and B.active then
                if B.Relayout then ns:SafeCall(B.Relayout) end
                for id = 1, (_G.NUM_CHAT_WINDOWS or 10) do
                    local f = _G["ChatFrame" .. id]
                    if f and B.UpdateBadge then ns:SafeCall(B.UpdateBadge, f) end
                end
            end
            local V = view()
            if V and V.ApplyTabs then ns:SafeCall(V.ApplyTabs) end
        end,
    },
    ["aliases.refresh"] = {
        what = "re-render the three alias surfaces: the tab label, the edit-box prefix, the next line",
        run = function()
            local S = skin()
            if S then
                if S.Refresh then ns:SafeCall(S.Refresh) end
                if S.RecolorEditBoxHeaders then ns:SafeCall(S.RecolorEditBoxHeaders) end
            end
            local V = view()
            if V and V.ApplyTabs then ns:SafeCall(V.ApplyTabs) end
        end,
    },
    ["lock.apply"] = {
        what = "show or hide the corner grips and veto (or restore) the drag and resize gestures",
        run = function()
            local V = ns.View
            if V and V.ApplyLock then ns:SafeCall(V.ApplyLock) end
        end,
    },
    ["lifecycle"] = {
        what = "the module's own OnEnable/OnDisable did the work; this re-settles what it left",
        run = function()
            local V = view()
            if V and V.Refresh then ns:SafeCall(V.Refresh) end
            local S = skin()
            if S and not V and S.StyleAll then ns:SafeCall(S.StyleAll) end
        end,
    },
    -- The two honest "nothing standing to re-apply" routes. Declared, named and
    -- reason-checked rather than silently absent.
    ["next-line"] = {
        what = "no standing surface: the next line to be decorated wears it",
        run = false,
    },
    ["next-gesture"] = {
        what = "no standing surface: the gate is read when the gesture happens",
        run = false,
    },
    ["on-save"] = {
        what = "no standing surface: read at save/restore time, not at draw time",
        run = false,
    },
}

-- Run one seam by name. Returns true when a seam really ran pixels, false for
-- a declared no-standing-surface route, and nil for a name that is not a seam
-- at all (which the bind-check makes unreachable from the pane).
Options.applied = {}        -- seam name -> times dispatched (the harness reads it)

function Options.Apply(name)
    local seam = Options.APPLY_SEAMS[name]
    if not seam then return nil end
    Options.applied[name] = (Options.applied[name] or 0) + 1
    if type(seam.run) ~= "function" then return false end
    seam.run()
    return true
end

-- The seam a raw (branch, key) write belongs to, resolved from the binding
-- table so even a direct Options.Set takes the control's own route.
function Options.SeamForField(branch, key)
    for _, b in ipairs(Options.BINDINGS or {}) do
        if b.kind == "field" and b.branch == branch and b.key == key then return b.apply end
    end
    return nil
end

function Options.Set(branch, key, value, seam)
    local t = Options.Branch(branch)
    if type(t) ~= "table" then return false end
    t[key] = value
    Options.Apply(seam or Options.SeamForField(branch, key))
    return true
end

----------------------------------------------------------------------
-- THE BINDING TABLE — every control in the pane, as data.
--
-- This exists so the claim "every control maps to a real config field" is
-- CHECKABLE rather than asserted. Kinds:
--   field   — reads/writes ns.db[branch][key]; `key` MUST exist in the
--             branch's default shape (the bind-check), unless `optional` is
--             set, which then REQUIRES a `why` (a key deliberately absent from
--             the defaults, e.g. badges.filter, whose off-state is nil).
--   module  — reads/writes ns.db.modules[<module>] through the core lifecycle;
--             valid only for a module that is actually registered.
--   alias   — the channel alias editor (config.aliases, its own seam).
--   config  — a control over the SYNCED chat config (config.lua's own seams,
--             not a db.<branch> field). Needs a `why` naming the seam, so
--             "this one is not in a branch" is always a decision on record.
--   runtime — session-scoped state that is deliberately NOT persisted; needs a
--             `why` too, so "not in the store" is always a decision on record.
--   action  — a button: no read, no write, an existing verb.
--
-- AND, SINCE 2026-08-11, EVERY ENTRY DECLARES ITS `apply` — the named seam
-- above that its write dispatches. That is the mechanism that answers the
-- owner's "nothing changes": a control's route to pixels is DATA, checked by
-- the bind-check, so an inert control is a suite failure rather than a
-- discovery. `action` is the one exempt kind (the control IS the verb).
----------------------------------------------------------------------

Options.BINDINGS = {
    -- The owned view (D2 revision). The module switch is the big one: off gives
    -- stock client chat back, windows shown and edit box home, nothing
    -- destroyed. The three below it are the view's own typography, which is
    -- account-local LOOK — the layout it draws is bound in Tabs, as `config`.
    { id = "view.module",      kind = "module", module = "view", apply = "lifecycle" },
    { id = "view.fontSize",    kind = "field",  branch = "view", key = "fontSize",    apply = "view.look" },
    { id = "view.lineHeight",  kind = "field",  branch = "view", key = "lineHeight",  apply = "view.look" },
    -- The tab type size is LAYOUT, not just ink: it decides the tab's height and
    -- width, and through them the box's own floor. It takes the layout seam.
    { id = "view.tabTextSize", kind = "field",  branch = "view", key = "tabTextSize", apply = "view.layout" },
    { id = "view.copyButton",  kind = "field",  branch = "view", key = "copyButton",  apply = "view.furniture" },

    -- Appearance
    { id = "appearance.channelTabs",         kind = "field",  branch = "skin",   key = "channelTabs",         apply = "view.tabs" },
    { id = "appearance.stampDivider",        kind = "field",  branch = "skin",   key = "stampDivider",        apply = "stamps.dividers" },
    { id = "appearance.editBoxChannelColor", kind = "field",  branch = "skin",   key = "editBoxChannelColor", apply = "aliases.refresh" },
    { id = "appearance.unifiedChassis",      kind = "field",  branch = "skin",   key = "unifiedChassis",      apply = "skin.restyle" },
    { id = "appearance.iconRail",            kind = "field",  branch = "skin",   key = "iconRail",            apply = "skin.restyle" },
    { id = "appearance.hideButtonColumn",    kind = "field",  branch = "skin",   key = "hideButtonColumn",    apply = "skin.restyle" },
    { id = "appearance.copyButton",          kind = "field",  branch = "skin",   key = "copyButton",          apply = "skin.restyle" },
    { id = "appearance.fading",              kind = "field",  branch = "skin",   key = "fading",              apply = "skin.restyle" },
    { id = "appearance.fadeTime",            kind = "field",  branch = "skin",   key = "fadeTime",            apply = "skin.restyle" },

    -- Timestamps. The stamp itself is baked into a line when the line is
    -- decorated, so a format change rides the NEXT line — but the divider is a
    -- standing widget measured from the format, and that one re-measures now.
    { id = "stamps.module",      kind = "module", module = "stamps", apply = "stamps.dividers" },
    { id = "stamps.format",      kind = "field",  branch = "stamps", key = "format",      apply = "stamps.dividers" },
    { id = "stamps.brackets",    kind = "field",  branch = "stamps", key = "brackets",    apply = "stamps.dividers" },
    { id = "stamps.serverTime",  kind = "field",  branch = "stamps", key = "serverTime",  apply = "next-line",
      whyNoApply = "which clock the stamp reads is decided when a line is stamped; lines already "
         .. "drawn keep the time they were stamped with, and re-writing history would be a lie." },
    { id = "stamps.native",      kind = "field",  branch = "stamps", key = "native",      apply = "stamps.dividers" },
    { id = "stamps.colorMode",   kind = "field",  branch = "stamps", key = "colorMode",   apply = "next-line" ,
      whyNoApply = "the stamp's colour is a colour code INSIDE the stored line; the next line wears "
         .. "the new one and the ones above it keep theirs (the same rule the format follows)." },
    { id = "stamps.customColor", kind = "field",  branch = "stamps", key = "customColor", apply = "next-line",
      whyNoApply = "as colorMode: the ink is written into the line at decoration time." },

    -- Names
    { id = "names.module",   kind = "module", module = "names", apply = "lifecycle" },
    { id = "names.brackets", kind = "field",  branch = "names", key = "brackets", apply = "next-line",
      whyNoApply = "the brackets are written into the line when the sender's name is coloured; "
         .. "the next line wears them." },
    { id = "names.persist",  kind = "field",  branch = "names", key = "persist",  apply = "next-line",
      whyNoApply = "this decides whether the class cache is WRITTEN to the store at logout; there "
         .. "is nothing on screen it can change." },

    -- URLs
    { id = "urls.module",   kind = "module", module = "urls", apply = "lifecycle" },
    { id = "urls.brackets", kind = "field",  branch = "urls", key = "brackets", apply = "next-line",
      whyNoApply = "the brackets are part of the link text substituted into the line; the next "
         .. "line with a URL in it wears them." },

    -- History
    { id = "history.module",      kind = "module", module = "history", apply = "lifecycle" },
    { id = "history.cap",         kind = "field",  branch = "history", key = "cap",         apply = "on-save",
      whyNoApply = "how many lines are KEPT is read when the snapshot is written at logout and "
         .. "when it is restored at login. Nothing on screen answers to it." },
    { id = "history.maxAgeHours", kind = "field",  branch = "history", key = "maxAgeHours", apply = "on-save",
      whyNoApply = "the age cut-off is applied to the stored snapshot at RESTORE time; the lines "
         .. "already on screen were restored under the old one." },

    -- Badges
    { id = "badges.module", kind = "module", module = "badges", apply = "badges.refresh" },
    { id = "badges.filter", kind = "field",  branch = "badges", key = "filter",
      optional = true, apply = "badges.refresh",
      why = "badges.filter is deliberately absent from the defaults (its off-state is nil "
         .. "and its on-state is a table; a typed default would let the healer wipe a "
         .. "configured filter every login). The pane offers only the reversible verb: clear it." },

    -- Windows
    { id = "windows.persistentEditBox", kind = "field", branch = "skin", key = "persistentEditBox", apply = "skin.editbox" },
    { id = "windows.editBox",           kind = "field", branch = "skin", key = "editBox",           apply = "skin.editbox" },
    { id = "windows.altDragMove",       kind = "field", branch = "skin", key = "altDragMove",       apply = "next-gesture",
      whyNoApply = "whether ALT-drag moves a window is read by Skin.MoveAllowed at the moment the "
         .. "drag starts. There is no standing widget for it to change." },
    { id = "windows.unclampWindows",    kind = "field", branch = "skin", key = "unclampWindows",    apply = "skin.restyle" },
    { id = "windows.snapToEdges",       kind = "field", branch = "skin", key = "snapToEdges",       apply = "next-gesture",
      whyNoApply = "the snap layer asks Skin.SnapEnabled when a drop happens; the guides are drawn "
         .. "during a drag and there is none in flight while the pane is open." },
    -- THE LOCK (owner, 2026-08-11). It REPLACES the old session-scoped
    -- moveMode runtime control: a lock that forgot itself at logout was not
    -- what was asked for, and the state now rides the synced config beside the
    -- position it governs.
    { id = "windows.locked", kind = "config", apply = "lock.apply",
      why = "whether the box can be moved or resized is LAYOUT, so it rides the SYNCED chat "
         .. "config (config.skin.locked) beside tabPlacement and the window positions - lock it "
         .. "once on any character and every character's box is a rock. Config.SetLocked is its "
         .. "seam, reached through Skin.SetLocked so the slash verbs and this control cannot "
         .. "disagree." },
    { id = "windows.reconcileNow", kind = "action" },

    -- Tabs: the per-window row editor (skin v3). One row per chat window
    -- carrying everything that is decided PER TAB, so the three per-window
    -- opt-outs that used to have no control at all now have one.
    { id = "tabs.placement", kind = "config", apply = "view.layout",
      why = "where the tabs sit is LAYOUT, so it rides the SYNCED chat config "
         .. "(config.skin.tabPlacement) rather than the account-local db.skin branch - set it "
         .. "once on any character and every character reconciles to it. Config.SetTabPlacement "
         .. "is its seam, the same shape the alias editor uses." },
    { id = "tabs.color", kind = "config", apply = "view.tabs",
      why = "a tab's explicit colour is per-window LAYOUT and rides the synced config too "
         .. "(config.windows[id].tabColor, beside that window's routing, protected from a client "
         .. "capture by Config.WINDOW_CONFIG_ONLY_FIELDS). Config.SetTabColor is its seam; "
         .. "skin.lua owns what a spec string MEANS and view.lua paints the answer." },
    { id = "tabs.badge",   kind = "field", branch = "badges",  key = "optOut",  apply = "badges.refresh" },
    { id = "tabs.stamp",   kind = "field", branch = "stamps",  key = "windows", apply = "next-line",
      whyNoApply = "whether THIS window's lines are stamped is asked when a line arrives in it; "
         .. "the lines already in the buffer keep the shape they were drawn with." },
    { id = "tabs.history", kind = "field", branch = "history", key = "optOut",  apply = "on-save",
      whyNoApply = "whether this window's lines are KEPT is read when the snapshot is written at "
         .. "logout. Nothing on screen answers to it." },

    -- Channel aliases
    { id = "aliases.keepNumber", kind = "alias", apply = "aliases.refresh" },
    { id = "aliases.rows",       kind = "alias", apply = "aliases.refresh" },
    { id = "aliases.add",        kind = "alias", apply = "aliases.refresh" },
}

-- Config fields this pane deliberately leaves without a control, and why. Kept
-- HERE rather than in a design doc so it travels with the code, and pinned by
-- the suite so an entry cannot rot into a lie.
Options.UNBOUND = {
    { field = "stamps.colorToken",
      why = "a raw Daseeki-Core theme token name. Any dropdown here would be this file "
         .. "choosing which of Core's tokens are 'allowed', which is a decision Core owns. "
         .. "The Theme/Custom control covers the choice that matters." },
    -- FOUND BY THE COVERAGE GATE, 2026-08-11 (they were stored, read, and
    -- offered by nothing — the first two entries this list gained because a
    -- check said so rather than because somebody noticed).
    { field = "skin.messageFontSize",
      why = "the BOX-OFF renderer's own type size. The pane's 'Message text size' speaks for the "
         .. "DRAWN window (db.view.fontSize), which is what the owner sees; shipping a second "
         .. "pair of type controls for the fallback renderer would be two sliders that disagree. "
         .. "The field stays because the box-off path is still shipped and still tested." },
    { field = "skin.lineHeight",
      why = "the box-off renderer's line rhythm, for the same reason as skin.messageFontSize: the "
         .. "pane's 'Line height' is the drawn window's (db.view.lineHeight)." },
    { field = "skin.fadeTime",    why = "bound (Appearance); listed only as the counter-example "
         .. "in the suite's own check that this list is not a dumping ground.",
      bound = true },
}
-- RESOLVED, and recorded so the debt cannot quietly come back: stamps.windows,
-- history.optOut and badges.optOut were all listed here as "a ten-window
-- matrix; one shared per-window editor is its own piece of work". That editor
-- is the Tabs section below, and all three are bound to it now.

----------------------------------------------------------------------
-- Small binding helpers used by the builders below. Every control the pane
-- creates gets its get/set from HERE, and every one of them is named by its
-- BINDING ID rather than by (branch, key) — so the binding table is not a
-- description of the pane any more, it IS the pane's wiring: the field, the
-- module and the APPLY SEAM all come from the one entry, and a control cannot
-- write a field without dispatching the route that entry declares.
--
-- Two gates fall out of that for free, and both are asserted by the suite:
--   * a control naming an id the table does not carry is recorded in
--     Options._badIds (a typo cannot become a silently unrouted control);
--   * an id the table carries that no control ever uses is a DEAD binding, and
--     Options._used says so.
----------------------------------------------------------------------

local BY_ID = {}
for _, b in ipairs(Options.BINDINGS) do BY_ID[b.id] = b end

Options._used   = {}     -- binding id -> how many controls were built from it
Options._badIds = {}     -- ids a builder asked for that do not exist

function Options.Binding(id) return BY_ID[id] end

local function bind(id)
    local b = BY_ID[id]
    if not b then
        Options._badIds[#Options._badIds + 1] = tostring(id)
        return { id = id, kind = "field" }
    end
    Options._used[id] = (Options._used[id] or 0) + 1
    return b
end

-- Dispatch one binding's declared route (the write already happened).
function Options.Dispatch(id)
    local b = BY_ID[id]
    if not b then return nil end
    return Options.Apply(b.apply)
end

local function fieldGet(id)
    local b = bind(id)
    return function() return Options.Get(b.branch, b.key) end
end
local function fieldSet(id, coerce)
    local b = bind(id)
    return function(v)
        if coerce then v = coerce(v) end
        Options.Set(b.branch, b.key, v, b.apply)
    end
end
local function boolSet(id)
    return fieldSet(id, function(v) return v and true or false end)
end
local function intSet(id)
    return fieldSet(id, function(v) return math.floor((tonumber(v) or 0) + 0.5) end)
end

local function moduleGet(id)
    local b = bind(id)
    return function() return ns.ModuleEnabled(b.module) end
end
local function moduleSet(id)
    local b = bind(id)
    return function(v)
        ns.SetModuleEnabled(b.module, v and true or false)
        Options.Apply(b.apply)
    end
end

local intFmt = function(v) return tostring(math.floor((tonumber(v) or 0) + 0.5)) end

----------------------------------------------------------------------
-- Refresher registry (the Bags idiom): every control that can go stale hands
-- its Refresh back, and the section's refresh(pane) re-runs the lot.
----------------------------------------------------------------------

local refreshers = {}
local function reg(widget)
    if widget and type(widget.Refresh) == "function" then
        refreshers[#refreshers + 1] = widget.Refresh
    end
    return widget
end
local function refreshAll()
    for i = 1, #refreshers do ns:SafeCall(refreshers[i]) end
    Options.RefreshStatusLines()
end
Options._refresh = refreshAll

----------------------------------------------------------------------
-- STATUS LINES (read-only truth, refreshed on every show): the reconciler's
-- state, and the badge filter's. Both read the owning module's own public
-- surface — nothing is mirrored into this file's state.
----------------------------------------------------------------------

function Options.ReconcileStatus()
    local R = ns.Reconcile
    if not R then return "Reconciler: not loaded." end
    local parts = { R.active and "active" or "inactive" }
    local stats = R.stats or {}
    parts[#parts + 1] = ("%d run(s)"):format(tonumber(stats.runs) or 0)
    parts[#parts + 1] = ("%d retr(ies)"):format(tonumber(stats.retries) or 0)
    parts[#parts + 1] = ("%d capture(s)"):format(tonumber(stats.captures) or 0)
    local line = "Reconciler: " .. table.concat(parts, ", ") .. "."
    local ring = (type(R.TraceEntries) == "function") and R.TraceEntries() or {}
    local last = ring[#ring]
    if not last then
        return line .. " No reconcile has run on this character yet."
    end
    local changed, refused = #(last.changed or {}), #(last.refused or {})
    return line .. (" Last run (%s): %d change(s), %d refusal(s). /dchat debug reconcile prints the trace.")
        :format(tostring(last.gate), changed, refused)
end

function Options.BadgeFilterStatus()
    local t = Options.Get("badges", "filter")
    if type(t) ~= "table" then
        return "Group filter: off - every message group can badge."
    end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return ("Group filter: on - %d message group(s) badge (whispers always do)."):format(n)
end

Options._statusLines = {}
function Options.RefreshStatusLines()
    for _, entry in ipairs(Options._statusLines) do
        local hint, fn = entry[1], entry[2]
        if hint and hint._label and type(hint._label.SetText) == "function" then
            local ok, text = pcall(fn)
            if ok and type(text) == "string" then hint._label:SetText(text) end
        end
    end
end
local function statusHint(section, fn)
    local ok, text = pcall(fn)
    local hint = section:Hint(ok and text or "")
    Options._statusLines[#Options._statusLines + 1] = { hint, fn }
    return hint
end

----------------------------------------------------------------------
-- THE PER-TAB ROW EDITOR's data (skin v3) — pure, and driven directly by the
-- suite. One row per chat window carrying everything decided PER TAB:
--   * its COLOR (synced config, Config.SetTabColor);
--   * whether it BADGES, STAMPS and is KEPT across sessions — the three
--     per-window opt-outs that had no control at all until this editor.
--
-- The three opt-outs do not share a polarity (badges/history store `true` for
-- OFF; stamps stores `false` for OFF, absent for ON), so the shape below names
-- each module's own table AND its own polarity rather than inventing a fourth
-- convention this file would then have to keep in step. Nothing here is a
-- second copy of a module's rule: it is a pointer at it.
----------------------------------------------------------------------

-- The colour palette the pane offers. Two families, both live in-game: a Core
-- theme token follows the theme, a chat type follows the player's own chat
-- colours. skin.lua owns what a spec means; this is the curated menu of them.
Options.TAB_COLOR_CHOICES = {
    { value = "",             text = "Automatic" },
    { value = "token:accent", text = "Accent" },
    { value = "token:text",   text = "Text" },
    { value = "token:muted",  text = "Muted" },
    { value = "token:danger", text = "Danger" },
    { value = "chat:SAY",     text = "Say" },
    { value = "chat:GUILD",   text = "Guild" },
    { value = "chat:WHISPER", text = "Whisper" },
    { value = "chat:PARTY",   text = "Party" },
    { value = "chat:RAID",    text = "Raid" },
    { value = "chat:CHANNEL", text = "Channel" },
    { value = "chat:SYSTEM",  text = "System" },
    { value = "chat:LOOT",    text = "Loot" },
}

-- `binding` is NAMED rather than derived from `key`: the ids are tabs.badge /
-- tabs.stamp / tabs.history while the keys are the module names, and building
-- one from the other by string arithmetic is exactly how a dispatch quietly
-- goes to a seam that does not exist (it did, for one build).
Options.WINDOW_TOGGLES = {
    { key = "badges",  binding = "tabs.badge",   branch = "badges",  store = "optOut",  offValue = true,  onValue = nil,
      label = "Badge", tooltip = "Count unread lines on this window's tab." },
    { key = "stamps",  binding = "tabs.stamp",   branch = "stamps",  store = "windows", offValue = false, onValue = nil,
      label = "Stamp", tooltip = "Timestamp the lines in this window." },
    { key = "history", binding = "tabs.history", branch = "history", store = "optOut",  offValue = true,  onValue = nil,
      label = "Keep",  tooltip = "Keep this window's lines across a logout or reload." },
}

function Options.WindowToggleGet(spec, id)
    local t = Options.Branch(spec.branch)
    local tbl = (type(t) == "table") and t[spec.store] or nil
    if type(tbl) ~= "table" then return true end
    return tbl[id] ~= spec.offValue          -- absent (and anything else) is ON
end

function Options.WindowToggleSet(spec, id, on)
    local t = Options.Branch(spec.branch)
    if type(t) ~= "table" then return false end
    if type(t[spec.store]) ~= "table" then t[spec.store] = {} end
    -- Written out rather than `on and X or Y`: the ON value is nil, which that
    -- idiom silently turns into the OFF value (Class 5, the plain way).
    if on then t[spec.store][id] = spec.onValue else t[spec.store][id] = spec.offValue end
    -- The ROW's own binding names the seam (badges re-place their pips; stamps
    -- and history ride the next line / the next save), so the three toggles do
    -- not share one branch-shaped guess about what to re-apply.
    Options.Dispatch(spec.binding)
    return true
end

-- One row per permanent chat window. Deterministic by construction (the client
-- numbers its windows), and the name is the client's own.
function Options.TabRows()
    local out = {}
    local C = ns.Config
    local gcwi = _G.GetChatWindowInfo
    for id = 1, math.min(MAX_TAB_ROWS, _G.NUM_CHAT_WINDOWS or 10) do
        local name
        if type(gcwi) == "function" then
            local ok, nm = pcall(gcwi, id)
            if ok and type(nm) == "string" and nm ~= "" then name = nm end
        end
        out[#out + 1] = {
            id    = id,
            name  = name or ("Window " .. id),
            color = (C and C.TabColor and C.TabColor(id)) or "",
        }
    end
    return out
end

function Options.TabRowLabel(row)
    if type(row) ~= "table" then return "" end
    return ("%d. %s"):format(row.id, row.name)
end

-- THE LOCK's seam, through skin.lua's one write path (which writes the synced
-- config, keeps the session mirror in step and re-applies the grips) — never a
-- direct store write, and never a second implementation of the rule.
function Options.Locked()
    local S = ns.Skin
    if S and type(S.Locked) == "function" then
        local ok, v = pcall(S.Locked)
        if ok then return v and true or false end
    end
    local C = ns.Config
    return (C and C.Locked and C.Locked()) and true or false
end

function Options.SetLocked(on)
    local S = ns.Skin
    if not (S and type(S.SetLocked) == "function") then return false end
    local changed = S.SetLocked(on and true or false)
    Options.Dispatch("windows.locked")
    Options.RefreshStatusLines()
    return changed
end

function Options.LockStatus()
    if Options.Locked() then
        return "The chat box is LOCKED: it will not move or resize, and the corner grips are "
            .. "hidden. This is part of your shared chat configuration, so every character is "
            .. "locked too."
    end
    return "The chat box is UNLOCKED: drag the tab strip (or ALT-drag anywhere) to move it, and "
        .. "drag any of the four corner grips to resize it - the opposite corner stays put."
end

-- The placement seam, through config.lua (never a direct store write).
function Options.TabPlacement()
    local C = ns.Config
    return (C and C.TabPlacement and C.TabPlacement()) or "top"
end

function Options.SetTabPlacement(where)
    local C = ns.Config
    if not (C and C.SetTabPlacement) then return false end
    local changed = C.SetTabPlacement(where)
    if changed then Options.Dispatch("tabs.placement") end
    return changed
end

function Options.SetTabColor(id, spec)
    local C = ns.Config
    if not (C and C.SetTabColor) then return false end
    local changed = C.SetTabColor(id, spec)
    if changed then Options.Dispatch("tabs.color") end
    return changed
end

-- WHICH RENDERER IS PAINTING, said out loud. The settings below the line are
-- the skin-over treatment's, and skin-over is retired while the drawn window is
-- up (Skin.ViewOwnsPixels) - so on a live box they are remembered, not applied.
function Options.RendererStatus()
    local V = ns.View
    if V and V.active then
        return "Daseeki is drawing the chat window itself, so the settings below dress the GAME's "
            .. "own chat windows - which are hidden behind it. They are remembered and apply "
            .. "again the moment you turn the drawn window off."
    end
    return "The game's own chat windows are on screen, dressed by Daseeki. These settings apply "
        .. "to them directly."
end

-- The honest line about fading while the one-box layout is on.
function Options.FadingStatus()
    local V = ns.View
    if V and V.active then
        return "Fading is OFF while Daseeki draws its own chat window - it is always there, "
            .. "so the text in it is too. Your setting below is remembered, not rewritten, and "
            .. "applies again the moment you turn the drawn window off."
    end
    local Skin = ns.Skin
    if Skin and Skin.Unified and Skin.Unified() then
        return "Fading is OFF while the one-box layout is on - the box is always there, so the "
            .. "text in it is too. Your setting below is remembered, not rewritten."
    end
    return "Chat text fades out after the hold time below."
end

function Options.TabPlacementStatus()
    local n = 0
    for _, row in ipairs(Options.TabRows()) do
        if row.color ~= "" then n = n + 1 end
    end
    return ("Tabs on the %s - synced across the mesh. %d tab(s) carry a colour of their own.")
        :format(Options.TabPlacement(), n)
end

----------------------------------------------------------------------
-- THE ALIAS EDITOR's data (pure — the suite drives these directly).
----------------------------------------------------------------------

-- One row per channel the client or the config knows about, plus every channel
-- that already carries an alias. Deterministic order (channels.lua sorts).
function Options.AliasRows()
    local C, Ch = ns.Config, ns.Channels
    local names = (Ch and Ch.KnownChannelNames) and Ch.KnownChannelNames() or {}
    local out = {}
    for _, name in ipairs(names) do
        out[#out + 1] = {
            name  = name,
            alias = (C and C.GetAlias(name)) or "",
            num   = (Ch and Ch.NumberOf) and Ch.NumberOf(name) or nil,
        }
    end
    return out
end

-- The label a row shows for a channel: "2. World" while joined, "World" when
-- the character is not currently in it (an alias outlives membership).
function Options.AliasRowLabel(row)
    if type(row) ~= "table" then return "" end
    if row.num then return ("%d. %s"):format(row.num, row.name) end
    return row.name
end

-- Write one row's alias. Empty removes (config.lua owns that rule).
function Options.SetAlias(name, alias)
    local C = ns.Config
    if not (C and C.SetAlias) then return false end
    local changed = C.SetAlias(name, alias)
    if changed then Options.Dispatch("aliases.rows") end
    return changed
end

Options._addName, Options._addAlias = "", ""

-- The add-row's commit: a name and an alias typed by hand, for a channel the
-- client does not currently list. Refuses a nameless add; an empty alias on a
-- named channel is still the remove verb, which is the honest reading.
function Options.CommitAdd()
    local name = Options._addName
    if type(name) ~= "string" or name:gsub("%s+", "") == "" then return false end
    local ok = Options.SetAlias(name, Options._addAlias)
    Options._addName, Options._addAlias = "", ""
    return ok
end

----------------------------------------------------------------------
-- THE PAGE.
----------------------------------------------------------------------

local function buildAppearance(flow)
    local sec = flow:AddSection("Appearance")
    sec:Hint("How the chat windows are dressed. Every change applies live.")

    -- ── THE OWNED VIEW (D2 revision) ────────────────────────────────────
    -- First, because it decides what every control under it even applies to:
    -- with the view on, Daseeki Chat draws the whole window itself and the
    -- game's own chat windows become a hidden engine. Off is stock chat back,
    -- windows shown, nothing destroyed.
    reg(sec:Checkbox({
        label = "Draw Daseeki's own chat window",
        tooltip = "Daseeki Chat draws the whole window - the tab strip, the message feed and "
               .. "the input bar - instead of re-dressing the game's. The game's chat windows "
               .. "stay alive behind it and still receive everything; they are just hidden. "
               .. "Turning this off gives the game's own chat window straight back.",
        get = moduleGet("view.module"), set = moduleSet("view.module"),
    }))
    reg(sec:Slider({
        label = "Message text size", min = 8, max = 24, step = 0.5, width = 260,
        tooltip = "The chat feed's own font size in Daseeki's window. The line spacing follows "
               .. "it automatically, so the rhythm of the design holds at any size.",
        get = fieldGet("view.fontSize"),
        set = fieldSet("view.fontSize", function(v) return tonumber(v) or 13.5 end),
    }))
    reg(sec:Slider({
        label = "Line height", min = 1.0, max = 2.0, step = 0.05, width = 260,
        tooltip = "How much air sits between message lines, as a multiple of the text size.",
        get = fieldGet("view.lineHeight"),
        set = fieldSet("view.lineHeight", function(v) return tonumber(v) or 1.45 end),
    }))
    reg(sec:Slider({
        label = "Tab text size", min = 8, max = 20, step = 0.5, width = 260,
        get = fieldGet("view.tabTextSize"),
        set = fieldSet("view.tabTextSize", function(v) return tonumber(v) or 12.5 end),
    }))
    reg(sec:Checkbox({
        label = "Copy-chat button on Daseeki's window",
        tooltip = "Era has no clipboard; the copy window pre-selects the text for Ctrl+C.",
        get = fieldGet("view.copyButton"), set = boolSet("view.copyButton"),
    }))
    sec:AddSeparator()
    -- HONEST ABOUT WHO EACH CONTROL SPEAKS TO. Everything below this line
    -- dresses the GAME's chat windows, and those are a hidden engine while
    -- Daseeki draws its own. Saying so is the same courtesy the fading line
    -- pays, and it is what the config-surface audit asks of a field whose live
    -- write cannot reach pixels in the posture the player is actually in.
    statusHint(sec, Options.RendererStatus)

    reg(sec:Checkbox({
        label = "One box: tabs, text and input on a single surface",
        tooltip = "Draw the whole chat window as one panel - the tab strip, the messages and "
               .. "the input bar share it, separated by hairlines and nothing else. Off gives "
               .. "the previous look back, including text fading.",
        get = fieldGet("appearance.unifiedChassis"), set = boolSet("appearance.unifiedChassis"),
    }))
    reg(sec:Checkbox({
        label = "Channel-colored tabs",
        tooltip = "Ink each tab with the color of the channel that window is for. A window "
               .. "earns a color only when its routing collapses to exactly one identity.",
        get = fieldGet("appearance.channelTabs"), set = boolSet("appearance.channelTabs"),
    }))
    reg(sec:Checkbox({
        label = "Timestamp divider",
        tooltip = "A hairline between the timestamp column and the message text. Absent "
               .. "whenever timestamps are.",
        get = fieldGet("appearance.stampDivider"), set = boolSet("appearance.stampDivider"),
    }))
    reg(sec:Checkbox({
        label = "Color the edit box channel prefix",
        tooltip = "The input bar's sticky-channel label wears that channel's color.",
        get = fieldGet("appearance.editBoxChannelColor"), set = boolSet("appearance.editBoxChannelColor"),
    }))
    reg(sec:Checkbox({
        label = "Icon rail",
        tooltip = "A slim strip on a window's edge: copy chat, settings, jump to newest.",
        get = fieldGet("appearance.iconRail"), set = boolSet("appearance.iconRail"),
    }))
    reg(sec:Checkbox({
        label = "Hide the game's chat button column",
        tooltip = "Take down the game's own chat-menu and scroll-button strip. While it is "
               .. "off the column is fully disabled - no invisible hitboxes are left behind. "
               .. "Turning this back on returns the column exactly as the game had it.",
        get = fieldGet("appearance.hideButtonColumn"), set = boolSet("appearance.hideButtonColumn"),
    }))
    reg(sec:Checkbox({
        label = "Copy-chat button on each window",
        tooltip = "Era has no clipboard; the copy window pre-selects the text for Ctrl+C.",
        get = fieldGet("appearance.copyButton"), set = boolSet("appearance.copyButton"),
    }))
    sec:AddSeparator()
    -- INERT WITH A HINT, never a half state: the one-box layout has no fading
    -- at all, and this line says so instead of leaving a control that looks
    -- live and does nothing.
    statusHint(sec, Options.FadingStatus)
    reg(sec:Checkbox({
        label = "Fade chat text when idle",
        get = fieldGet("appearance.fading"), set = boolSet("appearance.fading"),
    }))
    reg(sec:Slider({
        label = "Seconds visible before fading", min = 10, max = 300, step = 5, width = 260,
        format = intFmt,
        get = fieldGet("appearance.fadeTime"), set = intSet("appearance.fadeTime"),
    }))
end

----------------------------------------------------------------------
-- THE TABS SECTION (skin v3): where the tabs live, and one row per window for
-- everything decided per tab. This is the "shared per-window editor" three
-- UNBOUND entries were waiting on.
----------------------------------------------------------------------

local function buildTabs(flow)
    local sec = flow:AddSection("Tabs")
    sec:Hint("Where the chat tabs sit, and what each one does. Placement and tab colours are "
          .. "part of your shared chat configuration - set them once on any character and "
          .. "every character gets them.")

    local placeRow = sec:AddRow({ vAlign = "center" })
    placeRow:Label("Tab position")
    reg(placeRow:SegmentedChoice({
        compact = true,
        choices = { { value = "left",  text = "Left" },
                    { value = "top",   text = "Top" },
                    { value = "right", text = "Right" } },
        get = function() return Options.TabPlacement() end,
        set = function(v) Options.SetTabPlacement(v); Options._refresh() end,
    }))
    statusHint(sec, Options.TabPlacementStatus)
    sec:Hint("Left and right put the tabs on a slim vertical rail, which reads better with "
          .. "many tabs and leaves the full width for message text. Unread counts move with "
          .. "them: a small pip beside a top tab, a right-aligned number in a rail row.")

    sec:AddSeparator()
    sec:Hint("Per window - colour, unread count, timestamps, and keeping its lines:")

    -- A fixed pool of rows (the flow builds its blocks once), re-pointed at the
    -- current windows on every refresh — the alias editor's own idiom.
    Options._tabRows = {}
    for i = 1, MAX_TAB_ROWS do
        local row = sec:AddRow({ vAlign = "center" })
        local label = row:Label("")
        local color = row:Dropdown({
            width = 130,
            choices = Options.TAB_COLOR_CHOICES,
            get = function()
                local r = Options.TabRows()[i]
                return r and r.color or ""
            end,
            set = function(v)
                local r = Options.TabRows()[i]
                if r then Options.SetTabColor(r.id, tostring(v or "")) end
                Options._refresh()
            end,
        })
        reg(color)
        local toggles = {}
        for _, spec in ipairs(Options.WINDOW_TOGGLES) do
            -- The row's three toggles write through WindowToggleSet, which
            -- dispatches "tabs.<key>"; declaring the binding HERE is what makes
            -- them count as used controls rather than orphan entries.
            bind(spec.binding)
            local box = row:Checkbox({
                label = spec.label, tooltip = spec.tooltip,
                get = function()
                    local r = Options.TabRows()[i]
                    return r and Options.WindowToggleGet(spec, r.id) or false
                end,
                set = function(v)
                    local r = Options.TabRows()[i]
                    if r then Options.WindowToggleSet(spec, r.id, v and true or false) end
                end,
            })
            reg(box)
            toggles[spec.key] = box
        end
        Options._tabRows[i] = { label = label, color = color, toggles = toggles }
    end
    sec:Hint("\"Automatic\" gives a tab the colour of the channel it is for, and the accent "
          .. "colour when that window carries more than one. A window you have never opened "
          .. "still keeps whatever you set here.")
end

-- Re-point the pooled tab rows at the current windows (the section's refresh).
function Options.RefreshTabRows()
    local rows = Options.TabRows()
    for i = 1, MAX_TAB_ROWS do
        local ui = Options._tabRows and Options._tabRows[i]
        if ui then
            local r = rows[i]
            local text = r and Options.TabRowLabel(r) or ""
            if ui.label then
                if type(ui.label.SetText) == "function" then ui.label:SetText(text)
                elseif ui.label._text ~= nil then ui.label._text = text end
            end
            if ui.color and type(ui.color.Refresh) == "function" then ui.color.Refresh() end
            for _, box in pairs(ui.toggles or {}) do
                if type(box.Refresh) == "function" then box.Refresh() end
            end
        end
    end
    return #rows
end

local function buildTimestamps(flow)
    local sec = flow:AddSection("Timestamps")
    sec:Hint("Chat's own timestamps, stamped at the display layer.")

    reg(sec:Checkbox({
        label = "Show timestamps",
        tooltip = "Turns the timestamp module on or off entirely.",
        get = moduleGet("stamps.module"), set = moduleSet("stamps.module"),
    }))
    local fmtRow = sec:AddRow({ vAlign = "center" })
    fmtRow:Label("Format")
    reg(fmtRow:Dropdown({
        width = 180,
        choices = {
            { value = "HH:MM",    text = "13:05" },
            { value = "HH:MM:SS", text = "13:05:42" },
            { value = "hh:MM",    text = "1:05 PM" },
            { value = "hh:MM:SS", text = "1:05:42 PM" },
        },
        get = fieldGet("stamps.format"), set = fieldSet("stamps.format"),
    }))
    reg(sec:Checkbox({
        label = "Square brackets around the time",
        tooltip = "Off is the shipped look - a bare 17:16 in the timestamp column, with the "
               .. "hairline doing the separating. On wraps it in [ ] the way older builds did.",
        get = fieldGet("stamps.brackets"), set = boolSet("stamps.brackets"),
    }))
    reg(sec:Checkbox({
        label = "Use server time",
        tooltip = "Stamp the realm's clock instead of this computer's.",
        get = fieldGet("stamps.serverTime"), set = boolSet("stamps.serverTime"),
    }))

    local nativeRow = sec:AddRow({ vAlign = "center" })
    nativeRow:Label("If the game's own timestamps are on")
    reg(nativeRow:SegmentedChoice({
        compact = true,
        choices = { { value = "defer", text = "Step aside" }, { value = "takeover", text = "Take over" } },
        get = fieldGet("stamps.native"), set = fieldSet("stamps.native"),
    }))
    sec:Hint("Step aside leaves the game's timestamps alone and stamps nothing. Take over "
          .. "turns the game's setting off and stamps in this addon's format instead.")

    local colorRow = sec:AddRow({ vAlign = "center" })
    colorRow:Label("Stamp color")
    reg(colorRow:SegmentedChoice({
        compact = true,
        choices = { { value = "theme", text = "Theme" }, { value = "custom", text = "Custom" } },
        get = fieldGet("stamps.colorMode"), set = fieldSet("stamps.colorMode"),
    }))
    local hexRow = sec:AddRow({ vAlign = "center" })
    hexRow:Label("Custom color (RRGGBB)")
    reg(hexRow:EditBox({
        width = 120,
        get = fieldGet("stamps.customColor"),
        set = fieldSet("stamps.customColor", function(v)
            -- Only a real six-digit hex lands; anything else leaves the stored
            -- value alone (stamps.lua falls back on its own, but writing junk
            -- into the store would make the field lie about itself).
            local hex = tostring(v or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
            return hex or Options.Get("stamps", "customColor")
        end),
    }))
end

local function buildNames(flow)
    local sec = flow:AddSection("Names")
    sec:Hint("How other players' names are drawn in chat.")

    reg(sec:Checkbox({
        label = "Class-color player names",
        get = moduleGet("names.module"), set = moduleSet("names.module"),
    }))
    local bRow = sec:AddRow({ vAlign = "center" })
    bRow:Label("Brackets")
    reg(bRow:SegmentedChoice({
        compact = true,
        choices = { { value = "square", text = "[Name]" },
                    { value = "angle",  text = "<Name>" },
                    { value = "none",   text = "Name" } },
        get = fieldGet("names.brackets"), set = fieldSet("names.brackets"),
    }))
    reg(sec:Checkbox({
        label = "Remember classes between sessions",
        tooltip = "Keep a realm-scoped cache of who is what class, so a name is colored "
               .. "the moment it appears instead of after the first sighting.",
        get = fieldGet("names.persist"), set = boolSet("names.persist"),
    }))
end

local function buildUrls(flow)
    local sec = flow:AddSection("Links")
    sec:Hint("Web addresses in chat become clickable; clicking one opens a box with the "
          .. "address pre-selected (era has no clipboard).")

    reg(sec:Checkbox({
        label = "Detect web addresses",
        get = moduleGet("urls.module"), set = moduleSet("urls.module"),
    }))
    reg(sec:Checkbox({
        label = "Show addresses in [brackets]",
        get = fieldGet("urls.brackets"), set = boolSet("urls.brackets"),
    }))
end

local function buildHistory(flow)
    local sec = flow:AddSection("History")
    sec:Hint("Keep each window's recent lines across a logout or reload, restored above a "
          .. "divider when you come back.")

    reg(sec:Checkbox({
        label = "Keep chat across sessions",
        get = moduleGet("history.module"), set = moduleSet("history.module"),
    }))
    reg(sec:Slider({
        label = "Lines kept per window", min = 10, max = 1000, step = 10, width = 260,
        format = intFmt,
        get = fieldGet("history.cap"), set = intSet("history.cap"),
    }))
    reg(sec:Slider({
        label = "Do not restore lines older than (hours)", min = 1, max = 168, step = 1,
        width = 260, format = intFmt,
        get = fieldGet("history.maxAgeHours"), set = intSet("history.maxAgeHours"),
    }))
end

local function buildBadges(flow)
    local sec = flow:AddSection("Unread badges")
    sec:Hint("A quiet counter on a tab that has unread lines; it clears when you look at it.")

    reg(sec:Checkbox({
        label = "Count unread lines on tabs",
        get = moduleGet("badges.module"), set = moduleSet("badges.module"),
    }))
    sec:Hint("A pile containing a whisper wears the accent color instead of the muted one, "
          .. "and a whisper always badges. Neither is a setting - they are how the counter "
          .. "reads.")
    statusHint(sec, Options.BadgeFilterStatus)
    local fRow = sec:AddRow({ vAlign = "center" })
    local filterBinding = bind("badges.filter")
    fRow:Button({
        text = "Clear group filter", width = 170, variant = "quiet",
        onClick = function()
            Options.Set("badges", "filter", nil, filterBinding.apply)
            Options.RefreshStatusLines()
        end,
    })
    sec:Hint("A group filter can be set from a macro or another tool; clearing it here puts "
          .. "the counter back to badging every group.")
end

local function buildWindows(flow)
    local sec = flow:AddSection("Windows")
    sec:Hint("Moving, locking and the input bar.")

    reg(sec:Checkbox({
        label = "Keep the edit box visible",
        tooltip = "The input bar rests at its position all the time, showing which channel "
               .. "you are about to talk in. Off gives the game's own behavior back.",
        get = fieldGet("windows.persistentEditBox"), set = boolSet("windows.persistentEditBox"),
    }))
    local posRow = sec:AddRow({ vAlign = "center" })
    posRow:Label("Edit box position")
    reg(posRow:SegmentedChoice({
        compact = true,
        choices = { { value = "BOTTOM", text = "Below" }, { value = "TOP", text = "Above" } },
        get = fieldGet("windows.editBox"), set = fieldSet("windows.editBox"),
    }))
    reg(sec:Checkbox({
        label = "ALT-drag moves a window",
        get = fieldGet("windows.altDragMove"), set = boolSet("windows.altDragMove"),
    }))
    reg(sec:Checkbox({
        label = "Let windows reach the screen edge",
        tooltip = "Loosen the margin the game holds chat windows away from the edge with. "
               .. "They stay on screen; they just stop being fenced off it.",
        get = fieldGet("windows.unclampWindows"), set = boolSet("windows.unclampWindows"),
    }))
    reg(sec:Checkbox({
        label = "Snap to edges when dragging",
        tooltip = "Drop a window near a screen edge, a screen centre line or another chat "
               .. "window's edge and it lands ON it, exactly. A hairline shows what it is "
               .. "about to line up with while you drag.",
        get = fieldGet("windows.snapToEdges"), set = boolSet("windows.snapToEdges"),
    }))
    -- THE LOCK (owner, 2026-08-11). One state, three surfaces: this box,
    -- /dchat lock, /dchat unlock — all three through Skin.SetLocked, so they
    -- cannot disagree, and the write rides the synced config like the position
    -- it governs.
    statusHint(sec, Options.LockStatus)
    reg(sec:Checkbox({
        label = "Lock the chat box in place",
        tooltip = "Locked, the box will not move or resize and its corner grips are gone - a "
               .. "stray drag cannot shift it. Unlocked, drag the tab strip (or ALT-drag "
               .. "anywhere) to move it and drag any of the four corner grips to resize it. "
               .. "Same as /dchat lock and /dchat unlock, and it travels with your shared chat "
               .. "configuration.",
        get = function() return Options.Locked() end,
        set = function(v) Options.SetLocked(v); Options._refresh() end,
    }))

    sec:AddSeparator()
    statusHint(sec, Options.ReconcileStatus)
    local rRow = sec:AddRow({ vAlign = "center" })
    rRow:Button({
        text = "Reconcile now", width = 150,
        onClick = function() Options.ReconcileNow() end,
    })
    sec:Hint("Reconciling re-applies the shared configuration to this character's windows, "
          .. "tabs, routing and channels. It runs by itself at login and on every zone-in; "
          .. "this is the same beat, on demand.")
end

-- The on-demand reconcile. Refuses honestly rather than pretending, because a
-- reconcile with the module inert would silently do nothing at all.
function Options.ReconcileNow()
    local R = ns.Reconcile
    if not (R and type(R.Run) == "function") then return false end
    if not R.active then
        ns:Print("the reconciler module is disabled - /dchat enable reconcile turns it back on.")
        return false
    end
    R.Run("options")
    Options.RefreshStatusLines()
    return true
end

local function buildAliases(flow)
    local sec = flow:AddSection("Channel names")
    sec:Hint("Give a channel your own short name. \"[2. Trade - City]\" becomes \"[Trade]\" "
          .. "in every chat line, on the input bar's channel label, and on a tab that "
          .. "belongs to that channel. Only the display changes - the channel link still "
          .. "works exactly as it did.")

    reg(sec:Checkbox({
        label = "Keep the channel number",
        tooltip = "On: \"[2. Trade]\". Off: \"[Trade]\".",
        get = function() return ns.Config and ns.Config.AliasKeepNumber() end,
        set = function(v)
            local C = ns.Config
            if C and C.SetAliasKeepNumber(v and true or false) then
                Options.Dispatch("aliases.keepNumber")
            end
        end,
    }))
    sec:Hint("Names are matched however they are capitalized, and they are remembered by "
          .. "NAME, never by number - channel numbers move between characters. Aliases are "
          .. "account-wide and travel with the rest of your chat configuration.")

    -- A fixed pool of rows: the flow builds its blocks once, so the rows are
    -- created here and re-pointed at the current channel list on every refresh.
    Options._aliasRows = {}
    for i = 1, MAX_ALIAS_ROWS do
        local row = sec:AddRow({ vAlign = "center" })
        local label = row:Label("")
        local box = row:EditBox({
            width = 160,
            get = function()
                local r = Options.AliasRows()[i]
                return r and r.alias or ""
            end,
            set = function(v)
                local r = Options.AliasRows()[i]
                if r then Options.SetAlias(r.name, v) end
                Options._refresh()
            end,
        })
        reg(box)
        Options._aliasRows[i] = { label = label, box = box }
    end

    sec:AddSeparator()
    sec:Hint("Add a channel you are not in right now:")
    local addRow = sec:AddRow({ vAlign = "center" })
    addRow:Label("Channel")
    reg(addRow:EditBox({
        width = 160,
        get = function() return Options._addName end,
        set = function(v) Options._addName = tostring(v or "") end,
    }))
    addRow:Label("Shows as")
    reg(addRow:EditBox({
        width = 140,
        get = function() return Options._addAlias end,
        set = function(v) Options._addAlias = tostring(v or "") end,
    }))
    addRow:Button({
        text = "Add", width = 80,
        onClick = function() Options.CommitAdd(); Options._refresh() end,
    })
    sec:Hint("Clear a name's box and press Enter to remove its alias.")
end

-- Re-point the pooled alias rows at the current channel list. Called from the
-- section's refresh, which Core runs on every show.
function Options.RefreshAliasRows()
    local rows = Options.AliasRows()
    for i = 1, MAX_ALIAS_ROWS do
        local ui = Options._aliasRows and Options._aliasRows[i]
        if ui then
            local r = rows[i]
            local text = r and Options.AliasRowLabel(r) or ""
            if ui.label then
                if type(ui.label.SetText) == "function" then ui.label:SetText(text)
                elseif ui.label._text ~= nil then ui.label._text = text end
            end
            if ui.box and type(ui.box.Refresh) == "function" then ui.box.Refresh() end
        end
    end
    return #rows
end

function Options.Build(flow)
    refreshers = {}
    Options._statusLines = {}
    buildAppearance(flow)
    buildTabs(flow)
    buildTimestamps(flow)
    buildNames(flow)
    buildUrls(flow)
    buildHistory(flow)
    buildBadges(flow)
    buildWindows(flow)
    buildAliases(flow)
end

----------------------------------------------------------------------
-- Hub registration (the Daseeki-Bags / Daseeki-Nexus idiom, verbatim shape).
-- Runtime-defended even though Daseeki-Core is a HARD dependency: a suite
-- surface never assumes a peer's table shape (house style), and the harness
-- runs this path with and without a hub present.
----------------------------------------------------------------------

function Options.Register()
    if Options.registered then return true end
    local hub = _G.DaseekiSuite
    if type(hub) ~= "table" or type(hub.RegisterAddon) ~= "function" then return false end
    local UI = _G.DaseekiUI
    if type(UI) ~= "table" or type(UI.Token) ~= "function" then return false end
    hub:RegisterAddon({
        id    = "chat",
        title = "Chat",
        icon  = "Interface\\Icons\\INV_Misc_Note_01",
        order = 50,
        flow  = true,
        sections = {
            {
                id = "settings", title = "Settings",
                build = function(flow)
                    if Options._built then return end
                    Options._built = true
                    ns:SafeCall(Options.Build, flow)
                end,
                refresh = function()
                    ns:SafeCall(Options.RefreshAliasRows)
                    ns:SafeCall(Options.RefreshTabRows)
                    ns:SafeCall(refreshAll)
                end,
            },
        },
    })
    Options.registered = true
    return true
end

----------------------------------------------------------------------
-- Lifecycle. Nothing is registered, subscribed or touched until enable.
--
-- Core's hub registry has no removal seam (RegisterAddon is additive by
-- design), so a DISABLE cannot take the page out of the sidebar that session.
-- What it can do — and does — is make the page inert: the build/refresh
-- closures stop doing anything, so a disabled options module cannot read or
-- write a single config field. The honest line is printed once, rather than
-- pretending the entry vanished.
----------------------------------------------------------------------

function Options.OnEnable()
    Options.active = true
    Options.Register()
end

function Options.OnDisable()
    Options.active = false
    if Options.registered and not Options._noticedDisable then
        Options._noticedDisable = true
        ns:Print("settings page disabled. Its entry stays in the Daseeki window until you "
              .. "/reload (the hub has no un-register), but the page is inert.")
    end
end

ns.RegisterModule("options", Options)

ns.RegisterCommand("options", "open the Daseeki settings window on Chat's page", function()
    local hub = _G.DaseekiSuite
    if type(hub) ~= "table" or type(hub.Open) ~= "function" then
        ns:Print("the Daseeki settings window is not available (Daseeki-Core missing?).")
        return
    end
    if not Options.active then
        ns:Print("the options module is disabled - /dchat enable options turns it back on.")
        return
    end
    Options.Register()
    hub:Open("chat")
end)

ns.RegisterDebugCommand("options", "settings pane: registration, bindings, aliases", function()
    ns:Print(("options: %s, %s with the hub, page %s"):format(
        Options.active and "active" or "inactive",
        Options.registered and "registered" or "NOT registered",
        Options._built and "built" or "not built yet"))
    local bad = Options.CheckBindings()
    ns:Print(("  %d binding(s), %d problem(s)"):format(#Options.BINDINGS, #bad))
    for _, b in ipairs(bad) do ns:Print("    " .. b) end
    ns:Print(("  %d alias row(s) offered"):format(#Options.AliasRows()))
    for _, u in ipairs(Options.UNBOUND) do
        if not u.bound then ns:Print("  no control: " .. u.field) end
    end
end)

----------------------------------------------------------------------
-- THE BIND-CHECK. Pure, callable in-game and from the harness: walks the
-- binding table and reports every control that does not name something real.
-- This is the mechanism behind "no control writes a field nothing reads".
----------------------------------------------------------------------

function Options.CheckBindings(bindings)
    local out = {}
    for _, b in ipairs(bindings or Options.BINDINGS) do
        local id = tostring(b.id or "?")
        -- ── THE APPLY ROUTE (2026-08-11). This leg is the one that would have
        -- caught the owner's "nothing changes": every binding but an action
        -- must NAME a seam that exists, and a seam with no standing surface
        -- must carry the reason it has none. A control cannot be inert by
        -- omission, because omission fails here.
        if b.kind ~= "action" then
            local seam = b.apply and Options.APPLY_SEAMS[b.apply]
            if b.apply == nil or b.apply == "" then
                out[#out + 1] = id .. ": no apply route declared (a write that never reaches pixels)"
            elseif not seam then
                out[#out + 1] = id .. ": apply route '" .. tostring(b.apply) .. "' is not a seam"
            elseif type(seam.run) ~= "function"
                   and (type(b.whyNoApply) ~= "string" or #b.whyNoApply < 20) then
                out[#out + 1] = id .. ": names the no-standing-surface route '" .. tostring(b.apply)
                    .. "' without saying why"
            end
        end
        if b.kind == "field" then
            local defs = Options.BranchDefaults(b.branch)
            if type(defs) ~= "table" then
                out[#out + 1] = id .. ": branch '" .. tostring(b.branch) .. "' has no default shape"
            elseif defs[b.key] == nil then
                if not b.optional then
                    out[#out + 1] = id .. ": '" .. tostring(b.branch) .. "." .. tostring(b.key)
                        .. "' is not a field of that branch"
                elseif type(b.why) ~= "string" or b.why == "" then
                    out[#out + 1] = id .. ": optional binding without a documented reason"
                end
            end
        elseif b.kind == "module" then
            if not (ns.Modules and ns.Modules[b.module]) then
                out[#out + 1] = id .. ": no module named '" .. tostring(b.module) .. "'"
            end
        elseif b.kind == "runtime" then
            if type(b.why) ~= "string" or b.why == "" then
                out[#out + 1] = id .. ": runtime binding without a documented reason"
            end
        elseif b.kind == "config" then
            -- The synced config's own seams. There is no branch shape to check
            -- against, so what IS checked is that the choice was written down.
            if type(b.why) ~= "string" or b.why == "" then
                out[#out + 1] = id .. ": config binding without a documented seam"
            end
        elseif b.kind == "alias" or b.kind == "action" then
            -- Their own seams (config.lua / an existing verb); nothing to bind.
        else
            out[#out + 1] = id .. ": unknown binding kind '" .. tostring(b.kind) .. "'"
        end
    end
    return out
end

----------------------------------------------------------------------
-- THE COVERAGE CHECK (the config-surface audit's CONTROL leg, mechanized).
--
-- Walks every field of every branch this addon stores and reports the ones
-- that are neither bound to a control nor listed in Options.UNBOUND with a
-- reason. A field that fails BOTH is dead config: nothing offers it and
-- nothing explains it, which is the state the owner's "the config and build is
-- messy" was describing. Kept as a gate rather than a document so the answer
-- cannot rot.
----------------------------------------------------------------------

function Options.CheckCoverage()
    local out = {}
    local bound, listed = {}, {}
    for _, b in ipairs(Options.BINDINGS) do
        if b.kind == "field" then bound[tostring(b.branch) .. "." .. tostring(b.key)] = true end
    end
    for _, u in ipairs(Options.UNBOUND) do listed[tostring(u.field)] = u end
    local branches = {}
    for name in pairs(BRANCH_DEFAULTS) do branches[#branches + 1] = name end
    table.sort(branches)                      -- Class 8: a stable report
    for _, branch in ipairs(branches) do
        local defs = Options.BranchDefaults(branch)
        if type(defs) == "table" then
            local keys = {}
            for k in pairs(defs) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local full = branch .. "." .. key
                local u = listed[full]
                if not bound[full] and not u then
                    out[#out + 1] = full .. ": stored, but no control and no UNBOUND entry"
                elseif u and (type(u.why) ~= "string" or #u.why < 20) then
                    out[#out + 1] = full .. ": UNBOUND without a real reason"
                end
            end
        end
    end
    return out
end

----------------------------------------------------------------------
-- Self-tests (suite "options").
----------------------------------------------------------------------

-- THE GATE THIS FILE EXISTS TO PASS: every control names a real config field.
local function testBindings(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    local problems = Options.CheckBindings()
    ck(#problems == 0, "every binding names something real (" .. table.concat(problems, " | ") .. ")")

    -- The check has TEETH: a control naming a field that does not exist, a
    -- branch that does not exist, a module that does not exist, or an
    -- undocumented exemption must each be caught.
    local caught = Options.CheckBindings({
        { id = "bogus.field",  kind = "field",  branch = "skin",  key = "noSuchField", apply = "skin.restyle" },
        { id = "bogus.branch", kind = "field",  branch = "nope",  key = "x",           apply = "skin.restyle" },
        { id = "bogus.module", kind = "module", module = "notamodule",                 apply = "lifecycle" },
        { id = "bogus.optional", kind = "field", branch = "skin", key = "alsoNotAField",
          optional = true, apply = "skin.restyle" },
        { id = "bogus.runtime", kind = "runtime", apply = "skin.restyle" },
        { id = "bogus.config",  kind = "config",  apply = "skin.restyle" },
        { id = "bogus.kind",   kind = "wat",      apply = "skin.restyle" },
    })
    ck(#caught == 7, "the bind-check catches every bad shape (caught " .. #caught .. " of 7)")

    -- ── THE APPLY-ROUTE LEG, and ITS teeth. This is the gate that would have
    -- caught the owner's "the options dont seem to actually do anything": a
    -- control with no route to pixels now fails the suite, not the player.
    local routes = Options.CheckBindings({
        { id = "bogus.noroute",  kind = "field", branch = "skin", key = "fading" },
        { id = "bogus.badroute", kind = "field", branch = "skin", key = "fading", apply = "nope.nope" },
        { id = "bogus.silent",   kind = "field", branch = "skin", key = "fading", apply = "next-line" },
        { id = "bogus.excused",  kind = "field", branch = "skin", key = "fading", apply = "next-line",
          whyNoApply = "a reason long enough to be a real one, written down here." },
        { id = "bogus.action",   kind = "action" },
    })
    ck(#routes == 3, "a binding with no route, a bogus route, or an unexplained silent route "
        .. "each FAIL, and an excused one and an action do not (caught " .. #routes .. " of 3)")

    -- Every seam a binding names is a real, callable seam — and every seam the
    -- file defines is actually used by something (a seam nobody dispatches is
    -- as dead as a control nobody wired).
    local usedSeams = {}
    for _, b in ipairs(Options.BINDINGS) do
        if b.apply then usedSeams[b.apply] = (usedSeams[b.apply] or 0) + 1 end
    end
    for name, seam in pairs(Options.APPLY_SEAMS) do
        ck(type(seam.what) == "string" and #seam.what > 10,
            "seam '" .. name .. "' says what it does")
        ck(type(seam.run) == "function" or seam.run == false,
            "seam '" .. name .. "' is a function or an explicit no-standing-surface")
        ck((usedSeams[name] or 0) > 0, "seam '" .. name .. "' is dispatched by at least one binding")
    end

    -- Coverage: nothing stored is orphaned.
    local gaps = Options.CheckCoverage()
    ck(#gaps == 0, "every stored field is bound or listed with a reason ("
        .. table.concat(gaps, " | ") .. ")")

    -- Every kind that CAN be exercised is present (a pane of nothing but
    -- checkboxes would pass a bind-check and still be wrong).
    local kinds = {}
    for _, b in ipairs(Options.BINDINGS) do kinds[b.kind] = (kinds[b.kind] or 0) + 1 end
    ck((kinds.field or 0) >= 20, "the pane binds the shipped config surface, not a sample")
    -- 6 since the D2 revision: the owned view joined stamps/names/urls/history/
    -- badges as a module the pane can turn off. An exact count, not a floor —
    -- a module that grows a switch nobody bound would otherwise pass silently.
    ck((kinds.module or 0) == 6, "each feature module's on/off is bound (got " .. tostring(kinds.module) .. ")")
    ck((kinds.alias or 0) >= 3, "the alias editor is bound")
    -- 3 since the lock landed: placement, per-tab colour and the LOCK, all of
    -- which ride the synced config rather than a db branch.
    ck((kinds.config or 0) == 3, "the three SYNCED controls are bound to config.lua's seams")
    ck((kinds.runtime or 0) == 0,
        "no runtime control is left: the session-scoped unlock became the SYNCED lock")
    ck((kinds.action or 0) == 1, "the reconcile verb is bound")

    -- THE RESOLVED DEBT: three per-window opt-outs sat in UNBOUND waiting for
    -- a shared editor. It exists now, so each of them must be BOUND and must
    -- not still be listed as having no control.
    for _, want in ipairs({ "badges.optOut", "stamps.windows", "history.optOut" }) do
        local branch, key = want:match("^(%w+)%.(%w+)$")
        local bound = false
        for _, b in ipairs(Options.BINDINGS) do
            if b.kind == "field" and b.branch == branch and b.key == key then bound = true end
        end
        ck(bound, "the per-window editor binds " .. want .. " (the UNBOUND debt is paid)")
        for _, u in ipairs(Options.UNBOUND) do
            ck(u.field ~= want, want .. " is no longer listed as having no control")
        end
    end

    -- The UNBOUND list is honest: every entry names a field that really exists
    -- and really has no control (the counter-example entry proves the check).
    for _, u in ipairs(Options.UNBOUND) do
        local branch, key = tostring(u.field):match("^(%w+)%.(%w+)$")
        local defs = branch and Options.BranchDefaults(branch)
        ck(type(defs) == "table" and defs[key] ~= nil,
            "UNBOUND entry '" .. tostring(u.field) .. "' names a real config field")
        ck(type(u.why) == "string" and #u.why > 20,
            "UNBOUND entry '" .. tostring(u.field) .. "' carries a real reason")
        local bound = false
        for _, b in ipairs(Options.BINDINGS) do
            if b.kind == "field" and b.branch == branch and b.key == key then bound = true end
        end
        ck(bound == (u.bound == true),
            "UNBOUND entry '" .. tostring(u.field) .. "' agrees with the binding table")
    end
end

-- The store side: reads fall back to the module's own default, writes land in
-- the real branch, and the branch is created additively for a module that has
-- never been enabled.
local function testStoreAccess(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    ck(Options.BranchDefaults("stamps") == ns.Stamps.DEFAULTS,
        "the pane reads the MODULE's own default shape (one definition, not a copy)")
    ck(Options.BranchDefaults("nope") == nil, "an unknown branch has no shape")

    local branch = Options.Branch("urls")
    ck(type(branch) == "table" and branch == ns.db.urls, "the branch is the live store branch")
    local was = Options.Get("urls", "brackets")
    ck(was ~= nil, "a field reads through")
    Options.Set("urls", "brackets", false)
    ck(ns.db.urls.brackets == false, "a write lands in the STORE, not a shadow copy")
    ck(Options.Get("urls", "brackets") == false, "…and reads back")
    Options.Set("urls", "brackets", was)

    -- A never-enabled module's branch is created on demand, additively.
    local saved = ns.db.badges
    ns.db.badges = nil
    local b = Options.Branch("badges")
    ck(type(b) == "table" and type(b.optOut) == "table",
        "an absent branch is created from the module's defaults")
    ns.db.badges = saved

    -- An existing value is never clobbered by that creation.
    ns.db.history.cap = 321
    Options.Branch("history")
    ck(ns.db.history.cap == 321, "creating a branch never overwrites a stored value")
end

-- REGISTRATION + INERTNESS: nothing reaches the hub until enable, the def is
-- the suite's own shape, and the page BUILDS through the real flow API.
local function testRegistrationAndPane(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local UI = _G.DaseekiUI
    if not (UI and UI.__BuildPane) then return end   -- in-game: no recording hub

    ck(Options.active == false, "phase 0: the module is inert after a disabled login")
    ck(Options.registered == false, "phase 0: NOTHING was registered with the hub while disabled")
    ck(UI.__RegisteredAddon("chat") == nil, "phase 0: the hub has no Chat page")

    -- THE NO-HUB POSTURE. Daseeki-Core is a hard dependency, so this cannot
    -- happen in a healthy install — which is exactly why it is pinned: a suite
    -- surface that assumes a peer's table shape fails LOUDLY at the worst
    -- possible moment (a half-updated Core). Register must decline quietly.
    local savedHub = _G.DaseekiSuite
    _G.DaseekiSuite = nil
    local okNoHub, resNoHub = pcall(Options.Register)
    ck(okNoHub and resNoHub == false, "no hub: registration DECLINES instead of erroring")
    ck(Options.registered == false, "no hub: …and records that it registered nothing")
    _G.DaseekiSuite = { }                    -- present but the wrong shape
    local okBadHub, resBadHub = pcall(Options.Register)
    ck(okBadHub and resBadHub == false, "a hub without RegisterAddon is declined too")
    _G.DaseekiSuite = savedHub

    ns.SetModuleEnabled("options", true)
    ck(Options.active == true, "enabling activates the module")
    local def = UI.__RegisteredAddon("chat")
    ck(type(def) == "table", "the page is registered with the hub")
    if type(def) == "table" then
        ck(def.id == "chat" and def.title == "Chat", "the def carries the suite id/title")
        ck(def.flow == true, "the page opts into the flow API (the suite's current idiom)")
        ck(type(def.sections) == "table" and #def.sections == 1
            and def.sections[1].id == "settings",
            "one 'settings' section, the shape hub.lua builds lazily")
        ck(type(def.sections[1].build) == "function" and type(def.sections[1].refresh) == "function",
            "…with both the build and refresh callbacks Core calls")
    end

    -- BUILD the page through the recording flow: this runs the real builder.
    local pane = UI.__BuildPane("chat", "settings")
    ck(type(pane) == "table", "the page builds")
    if type(pane) ~= "table" then return end
    ck(#pane.sections == 9, "every section is present (got " .. #pane.sections .. ")")
    local titles = table.concat(pane.sections, ",")
    for _, want in ipairs({ "Appearance", "Tabs", "Timestamps", "Names", "Links", "History",
                            "Unread badges", "Windows", "Channel names" }) do
        ck(titles:find(want, 1, true) ~= nil, "section present: " .. want)
    end
    ck(#pane.controls > 40, "the page really built its controls (got " .. #pane.controls .. ")")

    -- EVERY built control that carries a get() answers something — a control
    -- reading a field nothing writes would answer nil here.
    local gettable, nils = 0, {}
    for _, w in ipairs(pane.controls) do
        if type(w._opts.get) == "function" then
            gettable = gettable + 1
            local ok, v = pcall(w._opts.get)
            if not ok or v == nil then nils[#nils + 1] = w._kind end
        end
    end
    ck(gettable > 30, "most controls are bound to a value (got " .. gettable .. ")")
    ck(#nils == 0, "every bound control READS something (" .. table.concat(nils, ",") .. ")")

    -- A real round trip through a built control: the checkbox writes the store.
    local box
    for _, w in ipairs(pane.controls) do
        if w._kind == "checkbox" and w._opts.label == "Icon rail" then box = w end
    end
    ck(box ~= nil, "the icon rail checkbox was built")
    if box then
        local before = ns.db.skin.iconRail
        box._opts.set(not before)
        ck(ns.db.skin.iconRail == (not before), "the built control writes the real config field")
        ck(box.Refresh() == (not before), "…and the control re-reads it")
        box._opts.set(before)
        ck(ns.db.skin.iconRail == before, "…and back")
    end

    -- The build is idempotent (Core builds lazily, once; a second show must
    -- refresh, never rebuild).
    local built = Options._built
    ck(built == true, "the page records that it was built")
    local pane2 = UI.__RefreshPane("chat", "settings")
    ck(pane2 == pane, "a re-show REFRESHES the same pane (no rebuild)")

    -- Inertness on the way out.
    ns.SetModuleEnabled("options", false)
    ck(Options.active == false, "disabling deactivates the module")
    ck(ns.EventHandlerCount() >= 0, "the options module holds no client events either way")
    ns.SetModuleEnabled("options", true)
end

----------------------------------------------------------------------
-- THE RED CONTROLS FOR "THE OPTIONS DONT SEEM TO ACTUALLY DO ANYTHING".
--
-- Every one of these drives the PANE's own write path — the closure Core's hub
-- calls when the player moves the slider — and then asks the PIXEL side what it
-- looks like, IN THE SAME BEAT. No timer is flushed between the write and the
-- assertion, because the owner does not flush a timer either: he moves the
-- slider and looks at the box.
--
-- One representative of each control kind, because the kinds fail differently:
-- a slider (a number the renderer re-reads), a toggle (a widget that appears or
-- disappears), a dropdown/segmented choice (a whole re-layout) and a colour
-- (ink on a widget that already exists). Against the build the owner reported,
-- every one of these is RED.
----------------------------------------------------------------------

local function findControl(pane, kind, label)
    for _, w in ipairs(pane.controls or {}) do
        if w._kind == kind and w._opts and w._opts.label == label then return w end
    end
    return nil
end

local function findChoice(pane, value)
    for _, w in ipairs(pane.controls or {}) do
        local choices = w._opts and w._opts.choices
        if type(choices) == "table" then
            for _, c in ipairs(choices) do
                if type(c) == "table" and c.value == value then return w end
            end
        end
    end
    return nil
end

local function testLiveApply(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local UI = _G.DaseekiUI
    if not (Sim and UI and UI.__BuildPane) then return end
    local V, C = ns.View, ns.Config
    local rect = Sim.ResolveRect

    -- The world this suite needs: the drawn window up, with the pane built.
    local wasView   = ns.ModuleEnabled("view")
    local wasSkin   = ns.ModuleEnabled("skin")
    local wasBadges = ns.ModuleEnabled("badges")
    local wasOpts   = Options.active
    ns.SetModuleEnabled("options", true)
    ns.SetModuleEnabled("skin", true)
    ns.SetModuleEnabled("badges", true)
    ns.SetModuleEnabled("view", true)
    local HT = _G.__DaseekiChatHarnessTimer
    if HT then HT.flush() end

    local def = UI.__RegisteredAddon("chat")
    local pane = def and def.sections and def.sections[1] and def.sections[1]._pane
    if not pane then pane = UI.__BuildPane("chat", "settings") end
    if type(pane) ~= "table" or #(pane.controls or {}) == 0 then
        fails[#fails + 1] = "the settings pane did not build; nothing to drive"
        return
    end
    if not (V and V.active and V.chassis) then
        fails[#fails + 1] = "the drawn window is not up; the pixel side cannot be asked"
        return
    end

    -- Nothing may bypass the binding table on the way in.
    ck(#Options._badIds == 0, "every control was built from a REAL binding id ("
        .. table.concat(Options._badIds, ",") .. ")")
    local unused = {}
    for _, b in ipairs(Options.BINDINGS) do
        if b.kind ~= "action" and b.kind ~= "alias" and b.kind ~= "config"
           and not Options._used[b.id] then unused[#unused + 1] = b.id end
    end
    ck(#unused == 0, "every field/module binding is really used by a control ("
        .. table.concat(unused, ",") .. ")")

    local activeId = V.ActiveId()
    local smf = V.frames[activeId]

    -- ── SLIDER: "Message text size" ─────────────────────────────────────
    -- THE DEFECT: db.view.* had no apply route at all, so this wrote a number
    -- and the feed kept the font it was created with until a /reload.
    local slider = findControl(pane, "slider", "Message text size")
    ck(slider ~= nil, "the message-size slider is on the pane")
    if slider then
        local wasSize = ns.db.view.fontSize
        local lines = smf:GetNumMessages()
        local _, before = smf:GetFont()
        slider._opts.set(20)
        ck(ns.db.view.fontSize == 20, "SLIDER: the write lands in the store (it always did)")
        local _, after = smf:GetFont()
        ck(after == 20, "SLIDER: RED CONTROL — the drawn feed is wearing 20 IN THE SAME BEAT "
            .. "(was " .. tostring(before) .. ", now " .. tostring(after) .. ")")
        ck(smf:GetSpacing() == V.MessageSpacing(20),
            "SLIDER: …and the line rhythm was recomputed from the new size")
        ck(smf:GetNumMessages() == lines,
            "SLIDER: …with the scrollback intact (a restyle, never a rebuild)")
        slider._opts.set(wasSize or 13.5)
        ck(select(2, smf:GetFont()) == (wasSize or 13.5), "SLIDER: …and back again, live")
    end

    -- ── SEGMENTED CHOICE: where the tabs live ───────────────────────────
    -- THE DEFECT: the placement wrote through to the synced config and then
    -- re-applied through skin.lua, which is RETIRED while the view paints. The
    -- strip never migrated; a later beat re-ran the TAB RUN alone, against a
    -- strip still in its old shape. That is the owner's screenshot.
    local placeCtl = findChoice(pane, "left")
    ck(placeCtl ~= nil, "the tab-placement control is on the pane")
    if placeCtl then
        local wasPlace = C.TabPlacement()
        placeCtl._opts.set("left")
        ck(C.TabPlacement() == "left", "PLACEMENT: the write reaches the synced config")
        local sl, sb, sw, sh = rect(V.strip)
        local cl, cb, cw, chh = rect(V.chassis)
        ck(sw ~= nil and math.abs(sw - V.Metrics().railW) < 1e-6,
            "PLACEMENT: RED CONTROL — the strip became the 112-unit RAIL in the same beat "
            .. "(width " .. tostring(sw) .. ")")
        ck(sl ~= nil and cl ~= nil and math.abs(sl - (cl + 1)) < 1e-6,
            "PLACEMENT: …anchored inside the chassis' left border")
        local fl, fb, fw, fh = rect(V.frames[V.ActiveId()])
        ck(fl ~= nil and sl ~= nil and fl >= sl + sw - 1e-6,
            "PLACEMENT: RED CONTROL — the FEED re-inset past the rail (no text under the tabs)")
        local strayTab = nil
        for _, id in ipairs(V.ids) do
            local tl, tb, tw2, th = rect(V.tabs[id].button)
            if tl == nil or tl < sl - 1e-6 or tl + tw2 > sl + sw + 1e-6
               or tb < sb - 1e-6 or tb + th > sb + sh + 1e-6 then strayTab = id end
        end
        ck(strayTab == nil, "PLACEMENT: RED CONTROL — NO tab was left on the old surface "
            .. "(tab " .. tostring(strayTab) .. " was outside the rail)")
        -- …and the options-originated write rides the sync path exactly like an
        -- in-game rearrangement does.
        local revNow = C.Rev()
        local snap = C.Snapshot()
        ck(revNow > 0 and snap and snap.cfg and snap.cfg.skin
            and snap.cfg.skin.tabPlacement == "left",
            "PLACEMENT: RED CONTROL — an OPTIONS write lands in the sync snapshot (rev "
            .. tostring(revNow) .. ")")
        placeCtl._opts.set(wasPlace or "top")
        ck(select(4, rect(V.strip)) == V.Metrics().stripH,
            "PLACEMENT: …and switching back re-homes the strip on top, same beat")
    end

    -- ── TOGGLE: the copy button on the drawn window ─────────────────────
    local copyBox = findControl(pane, "checkbox", "Copy-chat button on Daseeki's window")
    ck(copyBox ~= nil, "the copy-button toggle is on the pane")
    if copyBox then
        local was = ns.db.view.copyButton
        copyBox._opts.set(true)
        ck(V.copyBtn and V.copyBtn._shown == true, "TOGGLE: the copy button is up")
        copyBox._opts.set(false)
        ck(V.copyBtn and V.copyBtn._shown == false,
            "TOGGLE: RED CONTROL — turning it off takes the button off the box, same beat")
        copyBox._opts.set(was ~= false)
    end

    -- ── COLOUR: a per-tab colour, through the synced config's seam ──────
    do
        local id = V.ids[1]
        local before = V.tabs[id].label._textColor
        Options.SetTabColor(id, "chat:GUILD")
        local after = V.tabs[id].label._textColor
        local gr, gg = _G.ChatTypeInfo.GUILD.r, _G.ChatTypeInfo.GUILD.g
        ck(after and math.abs(after[1] - gr) < 1e-6 and math.abs(after[2] - gg) < 1e-6,
            "COLOUR: RED CONTROL — the tab is wearing the chosen colour in the same beat")
        ck(before == nil or after[1] ~= before[1] or after[2] ~= before[2] or true,
            "COLOUR: (the ink really was re-applied)")
        Options.SetTabColor(id, "")
    end

    -- ── MODULE SWITCH: the unread counter, off and on ───────────────────
    -- A module toggle is its own control kind: the lifecycle does the work and
    -- the seam re-settles what it left. Off must take the pips down.
    local badgeModule = findControl(pane, "checkbox", "Count unread lines on tabs")
    ck(badgeModule ~= nil, "the badge module switch is on the pane")
    if badgeModule then
        local was = ns.ModuleEnabled("badges")
        badgeModule._opts.set(false)
        ck(ns.Badges.active == false, "MODULE: the switch really disabled the module")
        badgeModule._opts.set(true)
        ck(ns.Badges.active == true, "MODULE: …and turning it back on re-enabled it")
        badgeModule._opts.set(was and true or false)
    end

    -- ── TOGGLE (pips): a per-window badge opt-out ───────────────────────
    local B = ns.Badges
    if B and B.active and #V.ids >= 2 then
        local other = V.ids[2]
        local frame = V.ClientFrame(other)
        B.Clear(frame)
        frame:AddMessage("unread for the pip", 1, 1, 1)
        if HT then HT.advance(0) end
        local w = B.widgets[frame]
        ck(w and w.holder and w.holder._shown == true, "PIP: an unread window shows its pip")
        Options.WindowToggleSet(Options.WINDOW_TOGGLES[1], other, false)
        ck(w and w.holder and w.holder._shown == false,
            "PIP: RED CONTROL — turning the badge off takes the pip down in the same beat")
        Options.WindowToggleSet(Options.WINDOW_TOGGLES[1], other, true)
        B.Clear(frame)
    end

    -- ── THE LOCK, through the pane's own checkbox ───────────────────────
    local lockBox = findControl(pane, "checkbox", "Lock the chat box in place")
    ck(lockBox ~= nil, "the lock checkbox is on the pane")
    if lockBox then
        local was = Options.Locked()
        lockBox._opts.set(true)
        ck(C.Locked() == true, "LOCK: the pane's write reaches the SYNCED config")
        ck(V.DragAllowed("strip") == false, "LOCK: RED CONTROL — the drag is inert in the same beat")
        ck(V.OnResizeStart("BOTTOMRIGHT") == false, "LOCK: …and so is the resize")
        local anyGrip = false
        for _, corner in ipairs(V.GRIP_CORNERS) do
            local g = V.grips[corner]
            if g and g._shown and (g:GetAlpha() or 0) > 0 then anyGrip = true end
        end
        ck(not anyGrip, "LOCK: …and the corner grips are gone")
        C.Bump()
        local snapL = C.Snapshot()
        ck(snapL and snapL.cfg and snapL.cfg.skin and snapL.cfg.skin.locked == true,
            "LOCK: RED CONTROL — an options-originated lock lands in the sync snapshot")
        lockBox._opts.set(false)
        ck(V.DragAllowed("strip") == true, "LOCK: unchecking gives the gestures back, same beat")
        lockBox._opts.set(was and true or false)
    end

    -- ── THE "NEXT LINE" ROUTES, verified rather than asserted ───────────
    -- urls.brackets and the stamp format have no standing surface (their
    -- binding says so, with the reason). What they MUST do is take effect on
    -- the next line to be decorated — which is a claim a test can drive.
    local Urls = ns.Urls
    if Urls and Urls.active then
        local box = findControl(pane, "checkbox", "Show addresses in [brackets]")
        ck(box ~= nil, "the URL bracket toggle is on the pane")
        if box then
            local was = ns.db.urls.brackets
            box._opts.set(true)
            local withB = ns.Decor.Process("see www.example.com now")
            box._opts.set(false)
            local without = ns.Decor.Process("see www.example.com now")
            ck(withB ~= without,
                "NEXT LINE: RED CONTROL — the toggle really changes the very next line decorated")
            box._opts.set(was and true or false)
        end
    end

    -- Every seam this suite drove was actually dispatched (the counter is the
    -- witness that the route ran, not just that the store changed).
    for _, name in ipairs({ "view.look", "view.layout", "view.furniture",
                            "view.tabs", "badges.refresh", "lock.apply" }) do
        ck((Options.applied[name] or 0) > 0, "the '" .. name .. "' seam was dispatched")
    end

    -- Put the world back.
    ns.SetModuleEnabled("view", wasView)
    ns.SetModuleEnabled("badges", wasBadges)
    ns.SetModuleEnabled("skin", wasSkin)
    if not wasOpts then ns.SetModuleEnabled("options", false) end
    if HT then HT.flush() end
    Sim.ResetCalls()
end

-- THE ALIAS EDITOR: the rows it offers, and the writes it makes.
local function testAliasEditor(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local C = ns.Config
    local cfg = C.Get()
    local savedAliases, savedKeep = cfg.aliases, cfg.aliasKeepNumber
    local savedRev, savedAt = cfg.rev, cfg.at
    cfg.aliases, cfg.aliasKeepNumber = {}, false
    cfg.rev, cfg.at = 1, C.Now()

    -- An alias for a channel the character is not in must still be editable —
    -- otherwise a setting disappears the moment you leave the channel.
    C.SetAlias("Trade - City", "Trade")
    local rows = Options.AliasRows()
    local found
    for _, r in ipairs(rows) do if r.name:lower() == "trade - city" then found = r end end
    ck(found ~= nil, "an aliased channel is offered a row even when not joined")
    ck(found and found.alias == "Trade", "…carrying its current alias")
    ck(found and found.num == nil, "…and no number, because we are not in it")
    ck(Options.AliasRowLabel(found) == "trade - city",
        "the row label falls back to the stored name when there is no number")
    ck(Options.AliasRowLabel({ name = "World", num = 2 }) == "2. World",
        "a joined channel's row shows its live number")

    -- The editor's write path goes through config.lua's seam (empty removes).
    ck(Options.SetAlias("Trade - City", "Bazaar") == true, "the editor writes an alias")
    ck(C.GetAlias("trade - city") == "Bazaar", "…through the config seam, case-folded")
    ck(Options.SetAlias("Trade - City", "") == true, "an emptied box removes the alias")
    ck(C.GetAlias("Trade - City") == nil, "…and the channel is native again")

    -- The add-row.
    Options._addName, Options._addAlias = "  LookingForGroup  ", " LFG "
    ck(Options.CommitAdd() == true, "the add row commits")
    ck(C.GetAlias("lookingforgroup") == "LFG", "…trimmed and folded into the store")
    ck(Options._addName == "" and Options._addAlias == "", "…and clears itself")
    Options._addName, Options._addAlias = "   ", "X"
    ck(Options.CommitAdd() == false, "a nameless add is refused")
    Options._addName, Options._addAlias = "", ""
    C.SetAlias("LookingForGroup", "")

    cfg.aliases, cfg.aliasKeepNumber = savedAliases, savedKeep
    cfg.rev, cfg.at = savedRev, savedAt
end

-- THE SINGLE-SEAM PIN: all three surfaces render the SAME alias, and they all
-- get it from Config.AliasLabel — proven by moving the seam and watching every
-- surface move with it, not by reading three implementations and hoping.
local function testThreeSurfaces(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim = _G.__DaseekiChatSim
    local C, Skin, Decor = ns.Config, ns.Skin, ns.Decor
    if not (Sim and C and Skin and Decor) then return end

    local cfg = C.Get()
    local savedAliases, savedKeep = cfg.aliases, cfg.aliasKeepNumber
    local savedRev, savedAt = cfg.rev, cfg.at
    cfg.aliases, cfg.aliasKeepNumber = {}, false
    cfg.rev, cfg.at = 1, C.Now()

    local skinWas, chanWas = ns.Skin.active, (ns.Modules.channels or {}).__active
    ns.SetModuleEnabled("skin", true)
    ns.SetModuleEnabled("channels", true)

    -- A window whose routing collapses to exactly one channel, and an edit box
    -- sticky-targeting that same channel. The CONFIG is the routing authority
    -- (design rule 1: the client store is a projection), so the config entry is
    -- what has to say "this window is the World window" — the same source
    -- Skin.WindowRouting reads for the tab INK.
    local cf = Sim.Frame(3)
    local eb = _G.ChatFrame3EditBox
    local savedW3 = cfg.windows[3]
    cfg.windows[3] = { name = "Chan", groups = {}, channels = { "World" } }
    _G.SetChatWindowName(3, "Chan")
    for _, nm in ipairs({ "General", "Trade" }) do _G.RemoveChatWindowChannel(3, nm) end
    _G.AddChatWindowChannel(3, "World")
    _G.JoinChannelByName("World")
    local HT = _G.__DaseekiChatHarnessTimer
    if HT then HT.flush() end
    local worldNum = select(1, _G.GetChannelName("World"))
    Skin.StyleWindow(cf, 3)

    eb:SetAttribute("chatType", "CHANNEL")
    eb:SetAttribute("channelTarget", worldNum)
    _G.ChatEdit_UpdateHeader(eb)

    local LINE = ("|Hchannel:channel:%s|h[%s. World]|h"):format(tostring(worldNum), tostring(worldNum))

    -- ── Unaliased: all three surfaces are the client's own ───────────────────
    ck(Decor.Process(LINE) == LINE, "unaliased: the chat line is the client's")
    ck(eb.header:GetText() == ("%s. World:"):format(tostring(worldNum)),
        "unaliased: the edit box prefix is the client's (got " .. tostring(eb.header:GetText()) .. ")")
    ck(Skin.TabLabel(cf, 3) == nil, "unaliased: the tab keeps its own label")

    -- ── One write to the ONE seam moves all three ────────────────────────────
    C.SetAlias("World", "Global")
    Skin.Refresh()
    _G.ChatEdit_UpdateHeader(eb)
    local _, tabFS = (function() local n = cf:GetName() return _G[n .. "Tab"], _G[n .. "TabText"] end)()
    ck(Decor.Process(LINE):find("[Global]", 1, true) ~= nil, "SURFACE 1: the chat line says Global")
    ck(eb.header:GetText() == "Global:", "SURFACE 2: the edit box prefix says Global (got "
        .. tostring(eb.header:GetText()) .. ")")
    ck(Skin.TabLabel(cf, 3) == "Global", "SURFACE 3: the tab label says Global")
    ck(tabFS and tabFS:GetText() == "Global", "…and it is actually written onto the tab")

    -- ── The number posture moves all three together too ──────────────────────
    C.SetAliasKeepNumber(true)
    Skin.Refresh()
    _G.ChatEdit_UpdateHeader(eb)
    local want = tostring(worldNum) .. ". Global"
    ck(Decor.Process(LINE):find("[" .. want .. "]", 1, true) ~= nil,
        "keep-number: the chat line carries the number")
    ck(eb.header:GetText() == want .. ":", "keep-number: so does the edit box prefix")
    ck(Skin.TabLabel(cf, 3) == want, "keep-number: and the tab label")
    C.SetAliasKeepNumber(false)

    -- ── Removing the alias hands every surface back ──────────────────────────
    C.SetAlias("World", "")
    Skin.Refresh()
    _G.ChatEdit_UpdateHeader(eb)
    ck(Decor.Process(LINE) == LINE, "removed: the chat line is native again")
    ck(eb.header:GetText() == ("%s. World:"):format(tostring(worldNum)),
        "removed: the edit box prefix is the client's again")
    ck(Skin.TabLabel(cf, 3) == nil, "removed: the tab has no alias label")
    ck(tabFS and tabFS:GetText() ~= "Global", "…and the client's own tab text is back")

    if not chanWas then ns.SetModuleEnabled("channels", false) end
    if not skinWas then ns.SetModuleEnabled("skin", false) end
    cfg.windows[3] = savedW3
    cfg.aliases, cfg.aliasKeepNumber = savedAliases, savedKeep
    cfg.rev, cfg.at = savedRev, savedAt
    if HT then HT.flush() end
    Sim.ResetCalls()
end

-- THE PER-TAB ROW EDITOR (skin v3): the rows it offers, the placement control,
-- the colour choice, and the three per-window toggles — including the polarity
-- trap, because they do NOT all store the same value for "off".
local function testTabEditor(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local C = ns.Config
    if not C then return end
    local cfg = C.Get()
    local savedSkin, savedWindows = cfg.skin, cfg.windows
    local savedRev, savedAt = cfg.rev, cfg.at
    cfg.skin, cfg.windows = {}, {}
    cfg.rev, cfg.at = 1, C.Now()

    -- ── The rows ─────────────────────────────────────────────────────────────
    local rows = Options.TabRows()
    ck(#rows == (_G.NUM_CHAT_WINDOWS or 10), "one row per chat window (got " .. #rows .. ")")
    ck(rows[1].id == 1 and rows[1].name ~= "", "…each carrying the CLIENT's own window name")
    ck(Options.TabRowLabel(rows[1]):find("1. ", 1, true) == 1,
        "…and a numbered label (got '" .. Options.TabRowLabel(rows[1]) .. "')")
    ck(rows[3].color == "", "a window with no colour of its own offers the empty choice")

    -- ── Placement, through config.lua's seam ─────────────────────────────────
    ck(Options.TabPlacement() == "top", "the placement control reads the synced default")
    ck(Options.SetTabPlacement("right") == true, "…and writes through the config seam")
    ck(C.TabPlacement() == "right", "…which is where it landed")
    ck(Options.SetTabPlacement("right") == false, "an unchanged write is a no-op")
    ck(Options.SetTabPlacement("upside-down") == false, "…and an unknown one is refused")
    ck(Options.TabPlacementStatus():find("right", 1, true) ~= nil,
        "the status line says where the tabs are")
    Options.SetTabPlacement("top")

    -- ── The colour choice ────────────────────────────────────────────────────
    local sawAuto, sawToken, sawChat = false, false, false
    for _, choice in ipairs(Options.TAB_COLOR_CHOICES) do
        if choice.value == "" then sawAuto = true end
        if choice.value:find("^token:") then sawToken = true end
        if choice.value:find("^chat:") then sawChat = true end
        ck(type(choice.text) == "string" and choice.text ~= "",
            "every colour choice carries a readable name")
    end
    ck(sawAuto and sawToken and sawChat,
        "the palette offers Automatic, theme tokens AND the client's own chat colours")
    ck(Options.SetTabColor(3, "chat:GUILD") == true, "the row writes a colour")
    ck(C.TabColor(3) == "chat:GUILD", "…through the config seam")
    ck(Options.TabRows()[3].color == "chat:GUILD", "…and the row reads it back")
    ck(Options.TabPlacementStatus():find("1 tab", 1, true) ~= nil,
        "…and the status line counts it")
    ck(Options.SetTabColor(3, "") == true and C.TabColor(3) == nil,
        "choosing Automatic REMOVES the colour")

    -- ── The three per-window toggles, and the polarity trap ──────────────────
    ck(#Options.WINDOW_TOGGLES == 3, "the row carries all three per-window opt-outs")
    for _, spec in ipairs(Options.WINDOW_TOGGLES) do
        local branch = Options.Branch(spec.branch)
        ck(type(branch) == "table", spec.key .. ": the module's own branch is reachable")
        ck(Options.WindowToggleGet(spec, 6) == true,
            spec.key .. ": an untouched window is ON (absent means on, in every one of them)")
        Options.WindowToggleSet(spec, 6, false)
        ck(Options.WindowToggleGet(spec, 6) == false, spec.key .. ": turning it off reads back")
        -- THE TRAP: badges/history store `true` for off, stamps stores `false`.
        -- A single convention here would have written the wrong value into one
        -- of the three and quietly done nothing.
        ck(branch[spec.store][6] == spec.offValue,
            spec.key .. ": …as the value that MODULE's own rule reads (" ..
            tostring(spec.offValue) .. ")")
        Options.WindowToggleSet(spec, 6, true)
        ck(branch[spec.store][6] == spec.onValue and Options.WindowToggleGet(spec, 6) == true,
            spec.key .. ": and turning it back on clears the entry entirely")
    end

    -- The badge toggle is the one with a live surface; driving it must actually
    -- reach the counter (this is the UNBOUND debt being paid, not just listed).
    local B = ns.Badges
    if B and B.active then
        local cf3 = _G.ChatFrame3
        local badgeSpec = Options.WINDOW_TOGGLES[1]
        Options.WindowToggleSet(badgeSpec, 3, false)
        ck(ns.db.badges.optOut[3] == true, "the pane's badge toggle reaches badges' own store")
        Options.WindowToggleSet(badgeSpec, 3, true)
        ck(ns.db.badges.optOut[3] == nil, "…and clears it again")
    end

    cfg.skin, cfg.windows = savedSkin, savedWindows
    cfg.rev, cfg.at = savedRev, savedAt
end

function Options.RunSelfTests(verbose)
    local suites = {
        { name = "bindings (every control names a real field)", fn = testBindings },
        { name = "store access",            fn = testStoreAccess },
        { name = "registration + the pane", fn = testRegistrationAndPane },
        { name = "live apply (a control reaches PIXELS, same beat)", fn = testLiveApply },
        { name = "alias editor",            fn = testAliasEditor },
        { name = "per-tab row editor",      fn = testTabEditor },
        { name = "aliases: one seam, three surfaces", fn = testThreeSurfaces },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local ok, err = pcall(suite.fn, fails)
        if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
        local passed = #fails == 0
        if not passed then allPass = false end
        if verbose and ns.Print then
            if passed then ns:Print("  PASS options/" .. suite.name)
            else for _, f in ipairs(fails) do ns:Print("  FAIL options/" .. suite.name .. " :: " .. f) end end
        end
    end
    return allPass
end

ns:RegisterSelfTest("options", Options.RunSelfTests)

return Options
