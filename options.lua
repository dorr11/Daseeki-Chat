-- Daseeki Chat — options.lua  (the settings pane: General + Chat History,
-- the wiring every section is built through, and the gates)
--
-- THE ASK (owner, 2026-08-11: "do we not have a configuration menu for chat?").
-- Everything in this addon has been config-gated since Wave 1, but the only
-- surface was /dchat subcommands. This file is the surface: the suite-standard
-- settings page, registered with Daseeki-Core's hub exactly the way every other
-- suite addon registers one (DaseekiSuite:RegisterAddon{ flow = true }, one
-- section with build(flow)/refresh — the Daseeki-Bags and Daseeki-Nexus idiom,
-- read and matched rather than reinvented).
--
-- THE REWORK (owner, 2026-08-11: "we need to rework the config menu, there is
-- a lot of noise in it and it doesnt quite accomplish the goal"). The flat
-- eight-section pane retired; three pages replaced it — GENERAL (dropdowns and
-- toggles only, plus the CHANNELS subsection), TABS (one page per chat tab,
-- built in options_tabs.lua) and CHAT HISTORY. This file owns the first and
-- the third, and the WIRING all three are built through: the branch access,
-- the apply seams, the binding index, the step lists and the gates.
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

-- (The pooled-row counts live with the sections that own them:
-- Options.MAX_CHANNEL_ROWS here, Tabs.MAX_PAGES in options_tabs.lua.)

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
    -- ── THE OPTIONS REWORK's SEAMS (2026-08-11) ─────────────────────────
    ["core.appearance"] = {
        what = "Daseeki-Core applies the theme/font to the whole suite; the drawn window "
            .. "re-lays around the new face and re-inks its tabs",
        run = function()
            local V = view()
            if V and V.ApplyLook then ns:SafeCall(V.ApplyLook) end
            if V and V.ApplyTabs then ns:SafeCall(V.ApplyTabs) end
            local S = skin()
            if S and not V and S.StyleAll then ns:SafeCall(S.StyleAll) end
        end,
    },
    ["config.converge"] = {
        what = "replay the whole configuration onto this character (windows, tabs, routing, "
            .. "channels) and rebuild the drawn tab strip around what landed",
        run = function()
            local R = ns.Reconcile
            if R and R.active and R.Run then ns:SafeCall(R.Run, "options") end
            local V = view()
            if V and V.RebuildTabs then ns:SafeCall(V.RebuildTabs, "options") end
        end,
    },
    ["view.tabset"] = {
        what = "rebuild the drawn tab run itself: surfaces created, the combat log taken in "
            .. "or handed back, the addon tab appearing or leaving",
        run = function()
            local V = view()
            if V and V.RebuildTabs then ns:SafeCall(V.RebuildTabs, "options") end
        end,
    },
    ["channels.order"] = {
        what = "drive the deterministic numbering toward the new channel order, then re-ink "
            .. "the tabs that read a channel identity",
        run = function()
            local C, Ch = ns.Config, ns.Channels
            if C and Ch and Ch.active and type(Ch.IsListWarm) == "function"
               and Ch.IsListWarm() and type(Ch.Converge) == "function" then
                local cfg = C.EffectiveCfg()
                if type(cfg) == "table" and type(cfg.join) == "table" and #cfg.join > 0 then
                    ns:SafeCall(Ch.Converge, cfg.join)
                end
            end
            local V = view()
            if V and V.ApplyTabs then ns:SafeCall(V.ApplyTabs) end
        end,
    },
    ["channels.colors"] = {
        what = "re-impose every configured channel colour BY NAME onto the client's own "
            .. "colour table, which is what the next line in that channel wears",
        run = function()
            local Ch = ns.Channels
            if Ch and Ch.active and type(Ch.ImposeAllColors) == "function" then
                ns:SafeCall(Ch.ImposeAllColors)
            end
            local V = view()
            if V and V.ApplyTabs then ns:SafeCall(V.ApplyTabs) end
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
    -- ── GENERAL: the suite-wide look, through CORE's own seams ──────────
    -- THE `core` KIND (options rework). Font, text size and theme are
    -- Daseeki-Core settings for the WHOLE suite — Core's own Appearance page
    -- owns them and its hub applies them live. Chat does not keep a second
    -- copy: these controls read and write CORE's accessors, so changing one
    -- here is changing it everywhere, which is what "one suite" means. The
    -- kind exists so the bind-check can insist the choice was written down.
    { id = "core.font", kind = "core", apply = "core.appearance",
      why = "UI.GetFont/UI.SetFont — Daseeki-Core's own font registry (built-in faces plus "
         .. "whatever LibSharedMedia has). Storing a chat-local copy would give the player "
         .. "two fonts that disagree and one of them would win at random." },
    { id = "core.fontScale", kind = "core", apply = "core.appearance",
      why = "UI.GetFontScale/UI.SetFontScale — the suite's text scale. Offered here as a "
         .. "DROPDOWN of steps rather than the slider Core's own page uses (the owner: "
         .. "\"I dont want sliders, drop downs are fine\")." },
    { id = "core.theme", kind = "core", apply = "core.appearance",
      why = "UI.GetThemeName/UI.SetTheme — the suite's colour theme, which the drawn chat "
         .. "window reads every token from. Core publishes the list; duplicating it here "
         .. "would be this file deciding which of Core's themes chat is allowed to have." },

    -- The drawn window's own typography (account-local LOOK: per-monitor taste).
    -- Dropdowns of sensible steps, never sliders.
    { id = "general.fontSize",    kind = "field", branch = "view", key = "fontSize",    apply = "view.look" },
    { id = "general.lineHeight",  kind = "field", branch = "view", key = "lineHeight",  apply = "view.look" },
    -- The tab type size is LAYOUT, not just ink: it decides the tab's height
    -- and width, and through them the box's own floor.
    { id = "general.tabTextSize", kind = "field", branch = "view", key = "tabTextSize", apply = "view.layout" },

    -- ── GENERAL / CHANNELS (the flagship of the rework) ─────────────────
    { id = "channels.order", kind = "config", apply = "channels.order",
      why = "the drag-and-drop order IS the config's join list (config.join, already on the "
         .. "wire), which is the { number, name } intent channels.lua's deterministic "
         .. "numbering engineers the client toward. Config.SetChannelOrder is its seam and "
         .. "it RENUMBERS ONLY - a reorder can never join or leave a channel." },
    { id = "channels.color", kind = "config", apply = "channels.colors",
      why = "a channel's colour is stored BY NAME in config.colors (the client keys colours "
         .. "by NUMBER and numbers move between characters - the survey's channel-colour "
         .. "memory lesson). Config.SetChannelColor is the seam; channels.lua re-imposes it "
         .. "onto the client on every join and renumber." },
    { id = "channels.rename", kind = "alias", apply = "aliases.refresh" },
    { id = "channels.add",    kind = "alias", apply = "aliases.refresh" },
    { id = "channels.keepNumber", kind = "alias", apply = "aliases.refresh" },

    -- The owned view (D2 revision). The module switch is the big one: off gives
    -- stock client chat back, windows shown and edit box home, nothing
    -- destroyed. The three below it are the view's own typography, which is
    -- account-local LOOK — the layout it draws is bound in Tabs, as `config`.
    { id = "view.module",      kind = "module", module = "view", apply = "lifecycle" },
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
    { id = "history.divider",     kind = "field",  branch = "history", key = "divider",     apply = "on-save",
      whyNoApply = "whether restored lines sit behind a session rule is read at RESTORE time, "
         .. "on the next login. The lines already on screen were restored under the old "
         .. "answer and re-writing them would be a lie about when they were said." },
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

    -- ── TABS: one PAGE per chat tab (the rework's second section; the
    -- controls themselves live in options_tabs.lua) ─────────────────────
    { id = "tabs.name", kind = "config", apply = "config.converge",
      why = "a tab's NAME is the client's own per-window field and rides the synced config "
         .. "(config.windows[id].name). Config.SetWindowName writes the intent and the "
         .. "reconciler's convergeWindow calls SetChatWindowName - the pane never touches "
         .. "the client store itself." },
    { id = "tabs.group", kind = "config", apply = "config.converge",
      why = "which message groups route to a tab is config.windows[id].groups, replayed by "
         .. "the reconciler through ChatFrame_RemoveAllMessageGroups/AddMessageGroup. "
         .. "Config.SetWindowGroup is the seam; the checkbox tree is a view of it." },
    { id = "tabs.channel", kind = "config", apply = "config.converge",
      why = "which channels route to a tab is config.windows[id].channels (BY NAME), "
         .. "replayed by the reconciler through AddChatWindowChannel. "
         .. "Config.SetWindowChannel is the seam." },
    { id = "tabs.add", kind = "config", apply = "config.converge",
      why = "+ Add Tab is CONFIG-FIRST: Config.AddWindow writes a live window entry and the "
         .. "reconciler creates it on the client, exactly the path a brand-new character "
         .. "takes at login. Nothing here makes a frame." },
    { id = "tabs.remove", kind = "config", apply = "config.converge",
      why = "Config.RemoveWindow writes the entry CLOSED (never deletes it - a config that "
         .. "says nothing about a window is one the reconciler will never close on the next "
         .. "character). The primary window and the combat log refuse the verb." },
    { id = "tabs.combatLog", kind = "config", apply = "view.tabset",
      why = "config.skin.combatLogTab, beside tabPlacement in the already-synced skin "
         .. "section. It changes OUR strip only - the client's log frame is hosted, never "
         .. "re-routed - so its seam rebuilds the tab run rather than the client store." },
    { id = "tabs.addonTab", kind = "config", apply = "config.converge",
      why = "the addon tab is an ordinary config window carrying addonSink = true "
         .. "(Config.SetAddonSink), created and removed through the same Add Tab path. The "
         .. "flag rides WINDOW_CONFIG_ONLY_FIELDS so a capture-back cannot delete it." },
    { id = "tabs.routeAddon", kind = "config", apply = "view.tabset",
      why = "config.skin.routeAddonLines - the recoverable red control over a HEURISTIC "
         .. "classifier. Off (or no addon tab at all) and every line takes exactly the path "
         .. "it always took; view.lua's ClassifierArmed is the one gate." },
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
    { id = "tabs.accent",  kind = "field", branch = "badges",  key = "accentOptOut", apply = "badges.refresh" },
    { id = "tabs.stamp",   kind = "field", branch = "stamps",  key = "windows", apply = "next-line",
      whyNoApply = "whether THIS window's lines are stamped is asked when a line arrives in it; "
         .. "the lines already in the buffer keep the shape they were drawn with." },
    { id = "tabs.history", kind = "field", branch = "history", key = "optOut",  apply = "on-save",
      whyNoApply = "whether this window's lines are KEPT is read when the snapshot is written at "
         .. "logout. Nothing on screen answers to it." },

}

-- Bindings the TABS file adds at load (options_tabs.lua). Declared through
-- this seam rather than by appending to the table above, so the id index stays
-- in step — a control built from an id the index never learned would be
-- recorded in _badIds and fail the suite, which is the whole point of it.
function Options.AddBindings(list)
    for _, b in ipairs(list or {}) do
        Options.BINDINGS[#Options.BINDINGS + 1] = b
        Options._IndexBinding(b)
    end
    return #Options.BINDINGS
end

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
function Options._IndexBinding(b) BY_ID[b.id] = b end
for _, b in ipairs(Options.BINDINGS) do Options._IndexBinding(b) end

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
Options._bind = bind      -- published for options_tabs.lua (one wiring seam)

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

-- Published so options_tabs.lua builds its controls through the SAME wiring
-- (the binding table is the pane's wiring, not a description of it).
Options._fieldGet, Options._fieldSet = fieldGet, fieldSet
Options._boolSet,  Options._moduleGet, Options._moduleSet = boolSet, moduleGet, moduleSet

-- ── NO SLIDERS (the owner's constraint, 2026-08-11: "I dont want sliders,
-- drop downs are fine"). Every number in this pane is a dropdown of sensible
-- steps, and the suite pins that no control of kind "slider" is ever built.
-- The step lists live here, as data, so the pin has something to check.
local function steps(list, fmt)
    local out = {}
    for _, v in ipairs(list) do
        out[#out + 1] = { value = v, text = fmt and fmt(v) or tostring(v) }
    end
    return out
end
local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function px(v) return (v == math.floor(v)) and ("%dpx"):format(v) or ("%.1fpx"):format(v) end

Options.STEPS = {
    fontSize    = steps({ 10, 11, 12, 12.5, 13, 13.5, 14, 15, 16, 18, 20, 22 }, px),
    lineHeight  = steps({ 1.0, 1.1, 1.2, 1.3, 1.45, 1.6, 1.8, 2.0 }, pct),
    tabTextSize = steps({ 10, 11, 12, 12.5, 13, 14, 16, 18 }, px),
    fadeTime    = steps({ 10, 20, 30, 45, 60, 90, 120, 180, 300 },
                        function(v) return ("%d seconds"):format(v) end),
    historyCap  = steps({ 25, 50, 100, 200, 300, 500, 750, 1000 },
                        function(v) return ("%d lines"):format(v) end),
    historyAge  = steps({ 1, 3, 6, 12, 24, 48, 72, 168 }, function(v)
                        if v < 24 then return ("%d hour%s"):format(v, v == 1 and "" or "s") end
                        return ("%d day%s"):format(v / 24, v == 24 and "" or "s")
                  end),
    coreScale   = steps({ 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3 }, pct),
}

-- A dropdown's `get` has to answer one of the offered values or the control
-- shows nothing: snap the stored number to the nearest step.
function Options.NearestStep(list, value)
    local v = tonumber(value)
    if not v then return list[1] and list[1].value end
    local best, bestD
    for _, c in ipairs(list) do
        local d = math.abs((tonumber(c.value) or 0) - v)
        if not bestD or d < bestD then best, bestD = c.value, d end
    end
    return best
end

local function stepGet(id, list)
    local g = fieldGet(id)
    return function() return Options.NearestStep(list, g()) end
end
local function stepSet(id, list)
    return fieldSet(id, function(v) return tonumber(v) or Options.NearestStep(list, nil) end)
end
Options._stepGet, Options._stepSet = stepGet, stepSet

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
    if ns.OptionsTabs and ns.OptionsTabs.Refresh then ns:SafeCall(ns.OptionsTabs.Refresh) end
    Options.RefreshStatusLines()
end
Options._refresh = refreshAll
Options._reg = reg        -- published for options_tabs.lua
function Options._ResetRefreshers() refreshers = {} end

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

Options._statusHint = statusHint      -- published for options_tabs.lua

----------------------------------------------------------------------
-- ============ THE OPTIONS REWORK (owner-specified, 2026-08-11) ============
--
-- THE ASK: "we need to rework the config menu, there is a lot of noise in it
-- and it doesnt quite accomplish the goal" — followed by a full section spec
-- with the client's own per-window config (message groups, global channels,
-- per-group colours, drag-to-reorder channels) as the capability reference.
--
-- The flat eight-section pane RETIRES here. What replaces it is three pages:
--
--   GENERAL  the look, in dropdowns and toggles ONLY (the owner's constraint:
--            "I dont want sliders, drop downs are fine" — the font-size and
--            line-height sliders became dropdowns of sensible steps, and the
--            suite pins that no slider is ever built again), the display group
--            the old Timestamps/Names/Links sections folded into, and the
--            CHANNELS subsection: one row per channel with drag-to-reorder, a
--            colour and a rename.
--   TABS     one page per chat tab (options_tabs.lua), plus + Add Tab, remove,
--            the combat log toggle and the addon tab.
--   HISTORY  retention: keep/lines/age/divider.
--
-- WHAT DID NOT CHANGE, and must not: every control is still declared in
-- Options.BINDINGS with a named apply seam, the bind-check still refuses a
-- control that names nothing real or routes nowhere, and CheckCoverage still
-- fails the suite for a stored field that is neither bound nor excused.
----------------------------------------------------------------------

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

function Options.TabPlacementStatus()
    local C = ns.Config
    local n = 0
    for _, id in ipairs((C and C.WindowIds and C.WindowIds()) or {}) do
        if C.TabColor and C.TabColor(id) then n = n + 1 end
    end
    return ("Tabs on the %s - synced across the mesh. %d tab(s) carry a colour of their own.")
        :format(Options.TabPlacement(), n)
end

-- WHICH RENDERER IS PAINTING, said out loud. The settings in the last group are
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

----------------------------------------------------------------------
-- ============ THE CHANNELS SUBSECTION (the flagship) ============
--
-- One row per channel the client or the config knows about, carrying the three
-- things the owner asked for:
--
--   ORDER   drag a row and the channel's NUMBER changes. The order IS the
--           config's join list, which is the intent channels.lua's
--           deterministic numbering engineers the client toward — so a drag
--           here is a renumber everywhere, on every character. It can never
--           join or leave a channel (Config.SetChannelOrder preserves
--           membership exactly); a row for a channel the config is not in is
--           offered for its NAME and its COLOUR and refuses to be dragged.
--   COLOUR  stored BY NAME (config.colors), re-imposed onto the client on
--           every join and renumber — the channel-colour-memory lesson.
--   RENAME  the alias system, surfaced here. "LookingForGroup" -> "LFG" shows
--           in the chat line, on the edit box's channel prefix and on a tab
--           that belongs to that channel: three surfaces, one seam
--           (Config.AliasLabel), which the suite pins by moving the seam and
--           watching all three follow.
--
-- THE ALIAS EDITOR IS GONE, not duplicated: this IS the alias editor now.
----------------------------------------------------------------------

Options.MAX_CHANNEL_ROWS = 12

local function hexOf(col)
    if type(col) ~= "table" then return "" end
    local function c8(v) return math.floor((tonumber(v) or 0) * 255 + 0.5) end
    return ("%02x%02x%02x"):format(c8(col.r), c8(col.g), c8(col.b))
end
Options.HexOf = hexOf

-- PURE. "rrggbb" (with or without a leading #) -> r, g, b as 0..1 floats, or
-- nil for anything that is not a real six-digit hex (never a guess).
function Options.ParseHex(s)
    local hex = tostring(s or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not hex then return nil end
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

-- The rows, in the order they are drawn: the configured channel order first
-- (those are the draggable ones), then every other channel the client or the
-- config knows about, alphabetically. Deterministic by construction (Class 8).
function Options.ChannelRows()
    local C, Ch = ns.Config, ns.Channels
    local rows, seen = {}, {}
    local function add(name, ordered)
        if type(name) ~= "string" or name == "" then return end
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        local col = (C and C.ChannelColor) and C.ChannelColor(name) or nil
        rows[#rows + 1] = {
            name    = name,
            alias   = (C and C.GetAlias and C.GetAlias(name)) or "",
            num     = (Ch and Ch.NumberOf) and Ch.NumberOf(name) or nil,
            color   = col,
            hex     = hexOf(col),
            ordered = ordered and true or false,
        }
    end
    for _, name in ipairs((C and C.ChannelOrder and C.ChannelOrder()) or {}) do add(name, true) end
    for _, name in ipairs((Ch and Ch.KnownChannelNames and Ch.KnownChannelNames()) or {}) do
        add(name, false)
    end
    return rows
end

-- How many of the rows are actually reorderable (the drag's clamp).
function Options.OrderedRowCount()
    local n = 0
    for _, r in ipairs(Options.ChannelRows()) do if r.ordered then n = n + 1 end end
    return n
end

-- The label a row shows: "2. World" while joined, "World" when the character
-- is not currently in it (a colour and an alias outlive membership).
function Options.ChannelRowLabel(row)
    if type(row) ~= "table" then return "" end
    if row.num then return ("%d. %s"):format(row.num, row.name) end
    return row.name
end

-- ── THE DRAG ENGINE, PURE ────────────────────────────────────────────────
--
-- OUR OWN IMPLEMENTATION, in the hub pane (the spec's own words): the flow API
-- has no reorderable list, and a keyboard-free mouse drag with a drop indicator
-- is what the owner asked for. Everything that DECIDES anything is pure and
-- driven directly by the suite; the frame glue below it only feeds this a row
-- index and paints the indicator.
--
-- CLASS 3 IS LIVE HERE: GetCursorPosition answers in SCREEN PIXELS and a row's
-- edges are in its own effective-scale space. The cursor is divided by the
-- compared frame's effective scale before any comparison happens, every time.

Options._drag = nil          -- { from = index, over = index }

function Options.DraggingRow()
    return Options._drag and Options._drag.from or nil
end

function Options.BeginRowDrag(i)
    i = tonumber(i)
    local rows = Options.ChannelRows()
    local row = i and rows[i]
    if not row then return false end
    -- A channel the config does not carry has no number to change. Refusing is
    -- the honest answer; silently reordering a display list would be a lie.
    if not row.ordered then return false end
    Options._drag = { from = i, over = i }
    return true
end

function Options.DragOver(i)
    if not Options._drag then return false end
    i = tonumber(i)
    if not i then return false end
    local n = Options.OrderedRowCount()
    if n < 1 then return false end
    if i < 1 then i = 1 elseif i > n then i = n end
    Options._drag.over = i
    return true
end

-- Where the drop indicator sits (1-based row index), or nil when nothing is
-- being dragged.
function Options.DropIndex()
    return Options._drag and Options._drag.over or nil
end

function Options.CancelRowDrag()
    Options._drag = nil
end

-- The drop. Returns true when the ORDER actually moved (an unchanged drop is a
-- no-op and never bumps rev — no sync storm from picking a row up and putting
-- it back).
function Options.CommitRowDrag()
    local d = Options._drag
    Options._drag = nil
    if not d then return false end
    local rows = Options.ChannelRows()
    local row = rows[d.from]
    if not row or not row.ordered then return false end
    if d.over == d.from then return false end
    local C = ns.Config
    if not (C and C.MoveChannel) then return false end
    local changed = C.MoveChannel(row.name, d.over)
    if changed then Options.Dispatch("channels.order") end
    return changed
end

-- PURE. Which row a screen-space Y lands on, given each row's { bottom, top }
-- in the SAME space, top row first. Above the first row is the first row and
-- below the last is the last — a drag that leaves the list still has an answer.
function Options.RowIndexAtY(rects, y)
    if type(rects) ~= "table" or #rects == 0 or type(y) ~= "number" then return nil end
    for i, r in ipairs(rects) do
        if type(r) == "table" and y >= r[1] and y <= r[2] then return i end
    end
    if y > rects[1][2] then return 1 end
    return #rects
end

-- ── THE ROW WRITES ───────────────────────────────────────────────────────

function Options.SetChannelColorHex(name, hex)
    local C = ns.Config
    if not (C and C.SetChannelColor) then return false end
    local changed
    if tostring(hex or ""):gsub("%s+", "") == "" then
        changed = C.SetChannelColor(name, nil)          -- the clear verb
    else
        local r, g, b = Options.ParseHex(hex)
        if not r then return false end                  -- junk never lands
        changed = C.SetChannelColor(name, r, g, b)
    end
    if changed then Options.Dispatch("channels.color") end
    return changed
end

function Options.SetChannelColor(name, r, g, b)
    local C = ns.Config
    if not (C and C.SetChannelColor) then return false end
    local changed = C.SetChannelColor(name, r, g, b)
    if changed then Options.Dispatch("channels.color") end
    return changed
end

-- The client's own colour picker, reached the way every addon reaches it. No
-- picker (or a client that does not carry one) leaves the hex box as the path,
-- which is why the row ships both.
function Options.OpenColorPicker(name)
    local CP = _G.ColorPickerFrame
    if type(CP) ~= "table" or type(CP.SetColorRGB) ~= "function" then return false end
    local C = ns.Config
    local cur = (C and C.ChannelColor and C.ChannelColor(name)) or { r = 1, g = 1, b = 1 }
    CP.func = function()
        local get = CP.GetColorRGB or _G.ColorPickerFrame.GetColorRGB
        if type(get) ~= "function" then return end
        local ok, r, g, b = pcall(get, CP)
        if ok and type(r) == "number" then Options.SetChannelColor(name, r, g, b) end
    end
    CP.cancelFunc = function()
        Options.SetChannelColor(name, cur.r, cur.g, cur.b)
    end
    CP.opacityFunc, CP.hasOpacity = nil, false
    CP.previousValues = { r = cur.r, g = cur.g, b = cur.b }
    pcall(CP.SetColorRGB, CP, cur.r, cur.g, cur.b)
    if type(CP.Hide) == "function" then pcall(CP.Hide, CP) end
    if type(CP.Show) == "function" then pcall(CP.Show, CP) end
    return true
end

-- Write one row's alias. Empty removes (config.lua owns that rule).
function Options.SetAlias(name, alias)
    local C = ns.Config
    if not (C and C.SetAlias) then return false end
    local changed = C.SetAlias(name, alias)
    if changed then Options.Dispatch("channels.rename") end
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

function Options.ChannelStatus()
    local rows = Options.ChannelRows()
    local ordered, colored, renamed = 0, 0, 0
    for _, r in ipairs(rows) do
        if r.ordered then ordered = ordered + 1 end
        if r.color then colored = colored + 1 end
        if r.alias ~= "" then renamed = renamed + 1 end
    end
    return ("%d channel(s): %d in your configured order, %d coloured, %d renamed. Order, "
         .. "colours and names are all part of your shared chat configuration.")
        :format(#rows, ordered, colored, renamed)
end

----------------------------------------------------------------------
-- THE DRAG's FRAME GLUE. Everything above decides; this only feeds it a row
-- index and paints a 2px line where the row would land. Every call is
-- type-guarded: the headless flow's rows are plain tables with no scripts, and
-- the pure engine is what the suite drives.
----------------------------------------------------------------------

Options._chanRows = {}

local function rowRects()
    local out = {}
    for i = 1, Options.MAX_CHANNEL_ROWS do
        local ui = Options._chanRows[i]
        local f = ui and ui.row
        if type(f) == "table" and type(f.GetTop) == "function" then
            local okT, top = pcall(f.GetTop, f)
            local okB, bottom = pcall(f.GetBottom, f)
            if okT and okB and type(top) == "number" and type(bottom) == "number" then
                out[#out + 1] = { bottom, top }
            end
        end
    end
    return out
end

function Options.DropIndicator()
    if Options._dropLine then return Options._dropLine end
    local first = Options._chanRows[1] and Options._chanRows[1].row
    if type(first) ~= "table" or type(first.GetParent) ~= "function" then return nil end
    local cf = _G.CreateFrame
    if type(cf) ~= "function" then return nil end
    local ok, f = pcall(cf, "Frame", nil, first:GetParent())
    if not ok or type(f) ~= "table" then return nil end
    if type(f.CreateTexture) == "function" then
        local ok2, tex = pcall(f.CreateTexture, f, nil, "OVERLAY")
        if ok2 and type(tex) == "table" then
            f._tex = tex
            if type(tex.SetAllPoints) == "function" then pcall(tex.SetAllPoints, tex, f) end
            local UI = _G.DaseekiUI
            if UI and UI.Color and type(tex.SetColorTexture) == "function" then
                pcall(tex.SetColorTexture, tex, UI.Color("accent"))
            end
        end
    end
    if type(f.SetHeight) == "function" then pcall(f.SetHeight, f, 2) end
    if type(f.Hide) == "function" then pcall(f.Hide, f) end
    Options._dropLine = f
    return f
end

function Options.PaintDropIndicator()
    local idx = Options.DropIndex()
    local line = Options.DropIndicator()
    if not line then return false end
    local ui = idx and Options._chanRows[idx]
    local row = ui and ui.row
    if not (idx and type(row) == "table" and type(line.SetPoint) == "function") then
        if type(line.Hide) == "function" then pcall(line.Hide, line) end
        return false
    end
    pcall(line.ClearAllPoints, line)
    pcall(line.SetPoint, line, "BOTTOMLEFT", row, "TOPLEFT", 0, 0)
    pcall(line.SetPoint, line, "BOTTOMRIGHT", row, "TOPRIGHT", 0, 0)
    pcall(line.Show, line)
    return true
end

function Options.HideDropIndicator()
    local line = Options._dropLine
    if line and type(line.Hide) == "function" then pcall(line.Hide, line) end
end

-- CLASS 3: the cursor is in screen pixels; a row's edges are in the row's own
-- effective-scale space. Convert INTO the compared frame's space, never the
-- other way round and never "they are probably equal".
function Options.DragAtCursor(anyRow)
    if not Options.DraggingRow() then return false end
    local gcp = _G.GetCursorPosition
    if type(gcp) ~= "function" or type(anyRow) ~= "table" then return false end
    local okC, _, cy = pcall(gcp)
    if not okC or type(cy) ~= "number" then return false end
    local scale = 1
    if type(anyRow.GetEffectiveScale) == "function" then
        local okS, s = pcall(anyRow.GetEffectiveScale, anyRow)
        if okS and type(s) == "number" and s > 0 then scale = s end
    end
    local idx = Options.RowIndexAtY(rowRects(), cy / scale)
    if not idx then return false end
    Options.DragOver(idx)
    Options.PaintDropIndicator()
    return true
end

local function installRowDrag(row, i)
    if type(row) ~= "table" or type(row.SetScript) ~= "function" then return false end
    if type(row.EnableMouse) == "function" then pcall(row.EnableMouse, row, true) end
    if type(row.RegisterForDrag) == "function" then pcall(row.RegisterForDrag, row, "LeftButton") end
    row:SetScript("OnDragStart", function(self)
        if Options.BeginRowDrag(i) then Options.PaintDropIndicator() end
    end)
    row:SetScript("OnDragStop", function(self)
        Options.CommitRowDrag()
        Options.HideDropIndicator()
        Options._refresh()
    end)
    row:SetScript("OnUpdate", function(self)
        if Options.DraggingRow() then Options.DragAtCursor(self) end
    end)
    -- A drag that ends anywhere but on the list still ends: the client fires
    -- OnHide on a pane that goes away mid-gesture, and a latch left up would
    -- reorder on the next unrelated click.
    row:SetScript("OnHide", function()
        if Options.DraggingRow() then
            Options.CancelRowDrag()
            Options.HideDropIndicator()
        end
    end)
    return true
end

----------------------------------------------------------------------
-- SECTION 1 — GENERAL.
----------------------------------------------------------------------

local function buildGeneral(flow)
    local sec = flow:AddSection("General")
    sec:Hint("How chat looks. Everything here applies the moment you change it.")

    -- ── The suite's own look, through Core's seams ───────────────────────
    local UI = _G.DaseekiUI

    local fontRow = sec:AddRow({ vAlign = "center" })
    fontRow:Label("Font")
    local fontBinding = bind("core.font")
    reg(fontRow:Dropdown({
        width = 200,
        choices = (UI and UI.FontNames) and UI.FontNames() or {},
        get = function() return UI and UI.GetFont and UI.GetFont() or "" end,
        set = function(v)
            if UI and UI.SetFont then UI.SetFont(v) end
            Options.Apply(fontBinding.apply)
        end,
    }))

    local sizeRow = sec:AddRow({ vAlign = "center" })
    sizeRow:Label("Text size")
    local scaleBinding = bind("core.fontScale")
    reg(sizeRow:Dropdown({
        width = 120,
        choices = Options.STEPS.coreScale,
        get = function()
            return Options.NearestStep(Options.STEPS.coreScale,
                UI and UI.GetFontScale and UI.GetFontScale() or 1)
        end,
        set = function(v)
            if UI and UI.SetFontScale then UI.SetFontScale(tonumber(v) or 1) end
            Options.Apply(scaleBinding.apply)
        end,
    }))

    local themeRow = sec:AddRow({ vAlign = "center" })
    themeRow:Label("Theme")
    local themeBinding = bind("core.theme")
    reg(themeRow:Dropdown({
        width = 200,
        choices = (UI and UI.GetThemeNames) and UI.GetThemeNames() or {},
        get = function() return UI and UI.GetThemeName and UI.GetThemeName() or "" end,
        set = function(v)
            if UI and UI.SetTheme then UI.SetTheme(v) end
            Options.Apply(themeBinding.apply)
        end,
    }))
    sec:Hint("Font, text size and theme belong to the whole Daseeki suite - changing one here "
          .. "changes it everywhere, and every other Daseeki window follows in the same beat.")

    -- ── The chat feed's own type ─────────────────────────────────────────
    local msgRow = sec:AddRow({ vAlign = "center" })
    msgRow:Label("Message text size")
    reg(msgRow:Dropdown({
        id = "general.fontSize", width = 120, choices = Options.STEPS.fontSize,
        tooltip = "The chat feed's own size in Daseeki's window. The line spacing follows it "
               .. "automatically, so the rhythm of the design holds at any size.",
        get = stepGet("general.fontSize", Options.STEPS.fontSize),
        set = stepSet("general.fontSize", Options.STEPS.fontSize),
    }))
    local lhRow = sec:AddRow({ vAlign = "center" })
    lhRow:Label("Line spacing")
    reg(lhRow:Dropdown({
        id = "general.lineHeight", width = 120, choices = Options.STEPS.lineHeight,
        tooltip = "How much air sits between message lines, as a share of the text size.",
        get = stepGet("general.lineHeight", Options.STEPS.lineHeight),
        set = stepSet("general.lineHeight", Options.STEPS.lineHeight),
    }))
    local ttRow = sec:AddRow({ vAlign = "center" })
    ttRow:Label("Tab text size")
    reg(ttRow:Dropdown({
        id = "general.tabTextSize", width = 120, choices = Options.STEPS.tabTextSize,
        get = stepGet("general.tabTextSize", Options.STEPS.tabTextSize),
        set = stepSet("general.tabTextSize", Options.STEPS.tabTextSize),
    }))

    -- ── Where the tabs live, and the lock ────────────────────────────────
    local placeRow = sec:AddRow({ vAlign = "center" })
    placeRow:Label("Tab style")
    reg(placeRow:Dropdown({
        width = 120,
        choices = { { value = "top",   text = "Top" },
                    { value = "left",  text = "Left" },
                    { value = "right", text = "Right" } },
        get = function() return Options.TabPlacement() end,
        set = function(v) Options.SetTabPlacement(v); Options._refresh() end,
    }))
    statusHint(sec, Options.TabPlacementStatus)
    sec:Hint("Left and right put the tabs on a slim vertical rail, which reads better with many "
          .. "tabs and leaves the full width for message text.")

    statusHint(sec, Options.LockStatus)
    reg(sec:Checkbox({
        label = "Lock the chat box in place",
        tooltip = "Locked, the box will not move or resize and its corner grips are gone - a "
               .. "stray drag cannot shift it. Same as /dchat lock and /dchat unlock, and it "
               .. "travels with your shared chat configuration.",
        get = function() return Options.Locked() end,
        set = function(v) Options.SetLocked(v); Options._refresh() end,
    }))

    -- ── CHANNELS (the flagship subsection) ───────────────────────────────
    sec:AddSeparator()
    sec:Hint("CHANNELS - drag a row by its label to change that channel's number, give it a "
          .. "colour, or give it a shorter name. All three are shared across your characters.")
    statusHint(sec, Options.ChannelStatus)

    reg(sec:Checkbox({
        label = "Keep the channel number in renamed channels",
        tooltip = "On: \"[2. Trade]\". Off: \"[Trade]\".",
        get = function() return ns.Config and ns.Config.AliasKeepNumber() end,
        set = function(v)
            local C = ns.Config
            if C and C.SetAliasKeepNumber(v and true or false) then
                Options.Dispatch("channels.keepNumber")
            end
        end,
    }))

    -- A fixed pool of rows (the flow builds its blocks once), re-pointed at the
    -- current channel list on every refresh.
    bind("channels.order"); bind("channels.color"); bind("channels.rename")
    Options._chanRows = {}
    for i = 1, Options.MAX_CHANNEL_ROWS do
        local row = sec:AddRow({ vAlign = "center" })
        local label = row:Label("")
        local swatch = row:Button({
            text = "Colour", width = 80, variant = "quiet",
            onClick = function()
                local r = Options.ChannelRows()[i]
                if r then Options.OpenColorPicker(r.name) end
            end,
        })
        local hexBox = row:EditBox({
            width = 90,
            get = function()
                local r = Options.ChannelRows()[i]
                return r and r.hex or ""
            end,
            set = function(v)
                local r = Options.ChannelRows()[i]
                if r then Options.SetChannelColorHex(r.name, v) end
                Options._refresh()
            end,
        })
        reg(hexBox)
        local nameBox = row:EditBox({
            width = 140,
            get = function()
                local r = Options.ChannelRows()[i]
                return r and r.alias or ""
            end,
            set = function(v)
                local r = Options.ChannelRows()[i]
                if r then Options.SetAlias(r.name, v) end
                Options._refresh()
            end,
        })
        reg(nameBox)
        Options._chanRows[i] = { row = row, label = label, swatch = swatch,
                                 hexBox = hexBox, nameBox = nameBox }
        installRowDrag(row, i)
    end
    sec:Hint("The colour box takes six hex digits (\"ff8000\"); emptying it hands the channel "
          .. "back to the game's own colour. A channel you are not in right now still keeps "
          .. "its colour and its name - only its ORDER needs you to be in it.")

    sec:AddSeparator()
    sec:Hint("Rename a channel you are not in right now:")
    local addRow = sec:AddRow({ vAlign = "center" })
    addRow:Label("Channel")
    bind("channels.add")
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

    -- ── THE DISPLAY GROUP (the old Timestamps / Names / Links sections) ──
    sec:AddSeparator()
    sec:Hint("DISPLAY - what a chat line is dressed with.")

    reg(sec:Checkbox({
        label = "Show timestamps",
        get = moduleGet("stamps.module"), set = moduleSet("stamps.module"),
    }))
    local fmtRow = sec:AddRow({ vAlign = "center" })
    fmtRow:Label("Time format")
    reg(fmtRow:Dropdown({
        width = 160,
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
        get = fieldGet("stamps.brackets"), set = boolSet("stamps.brackets"),
    }))
    reg(sec:Checkbox({
        label = "Use server time",
        tooltip = "Stamp the realm's clock instead of this computer's.",
        get = fieldGet("stamps.serverTime"), set = boolSet("stamps.serverTime"),
    }))
    reg(sec:Checkbox({
        label = "Timestamp divider",
        tooltip = "A hairline between the timestamp column and the message text.",
        get = fieldGet("appearance.stampDivider"), set = boolSet("appearance.stampDivider"),
    }))
    local nativeRow = sec:AddRow({ vAlign = "center" })
    nativeRow:Label("If the game's own timestamps are on")
    reg(nativeRow:Dropdown({
        width = 140,
        choices = { { value = "defer", text = "Step aside" }, { value = "takeover", text = "Take over" } },
        get = fieldGet("stamps.native"), set = fieldSet("stamps.native"),
    }))
    local colorRow = sec:AddRow({ vAlign = "center" })
    colorRow:Label("Stamp colour")
    reg(colorRow:Dropdown({
        width = 140,
        choices = { { value = "theme", text = "Theme" }, { value = "custom", text = "Custom" } },
        get = fieldGet("stamps.colorMode"), set = fieldSet("stamps.colorMode"),
    }))
    local hexRow = sec:AddRow({ vAlign = "center" })
    hexRow:Label("Custom stamp colour (RRGGBB)")
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

    reg(sec:Checkbox({
        label = "Class-colour player names",
        get = moduleGet("names.module"), set = moduleSet("names.module"),
    }))
    local brRow = sec:AddRow({ vAlign = "center" })
    brRow:Label("Name brackets")
    reg(brRow:Dropdown({
        width = 120,
        choices = { { value = "square", text = "[Name]" },
                    { value = "angle",  text = "<Name>" },
                    { value = "none",   text = "Name" } },
        get = fieldGet("names.brackets"), set = fieldSet("names.brackets"),
    }))
    reg(sec:Checkbox({
        label = "Remember classes between sessions",
        tooltip = "Keep a realm-scoped cache of who is what class, so a name is coloured the "
               .. "moment it appears instead of after the first sighting.",
        get = fieldGet("names.persist"), set = boolSet("names.persist"),
    }))

    reg(sec:Checkbox({
        label = "Detect web addresses",
        tooltip = "Web addresses become clickable; clicking one opens a box with the address "
               .. "pre-selected (era has no clipboard).",
        get = moduleGet("urls.module"), set = moduleSet("urls.module"),
    }))
    reg(sec:Checkbox({
        label = "Show addresses in [brackets]",
        get = fieldGet("urls.brackets"), set = boolSet("urls.brackets"),
    }))

    reg(sec:Checkbox({
        label = "Channel-coloured tabs",
        tooltip = "Ink each tab with the colour of the channel that window is for. A window "
               .. "earns a colour only when its routing collapses to exactly one identity.",
        get = fieldGet("appearance.channelTabs"), set = boolSet("appearance.channelTabs"),
    }))
    reg(sec:Checkbox({
        label = "Colour the edit box channel prefix",
        get = fieldGet("appearance.editBoxChannelColor"), set = boolSet("appearance.editBoxChannelColor"),
    }))
    reg(sec:Checkbox({
        label = "Copy-chat button",
        tooltip = "Era has no clipboard; the copy window pre-selects the text for Ctrl+C.",
        get = fieldGet("view.copyButton"), set = boolSet("view.copyButton"),
    }))
    reg(sec:Checkbox({
        label = "Keep the edit box visible",
        tooltip = "The input bar rests at its position all the time, showing which channel you "
               .. "are about to talk in.",
        get = fieldGet("windows.persistentEditBox"), set = boolSet("windows.persistentEditBox"),
    }))
    local ebRow = sec:AddRow({ vAlign = "center" })
    ebRow:Label("Edit box position")
    reg(ebRow:Dropdown({
        width = 120,
        choices = { { value = "BOTTOM", text = "Below" }, { value = "TOP", text = "Above" } },
        get = fieldGet("windows.editBox"), set = fieldSet("windows.editBox"),
    }))

    -- ── THE GAME'S OWN WINDOWS (the box-off renderer) ────────────────────
    -- Kept, and kept HONEST: with the drawn window on these are remembered
    -- rather than applied, and the status line says so instead of leaving a
    -- control that looks live and does nothing.
    sec:AddSeparator()
    sec:Hint("THE GAME'S OWN CHAT WINDOWS - used when Daseeki is not drawing its own.")
    reg(sec:Checkbox({
        label = "Draw Daseeki's own chat window",
        tooltip = "Daseeki Chat draws the whole window - the tab strip, the message feed and "
               .. "the input bar - instead of re-dressing the game's. The game's chat windows "
               .. "stay alive behind it and still receive everything; they are just hidden. "
               .. "Turning this off gives the game's own chat window straight back.",
        get = moduleGet("view.module"), set = moduleSet("view.module"),
    }))
    statusHint(sec, Options.RendererStatus)
    reg(sec:Checkbox({
        label = "One box: tabs, text and input on a single surface",
        get = fieldGet("appearance.unifiedChassis"), set = boolSet("appearance.unifiedChassis"),
    }))
    reg(sec:Checkbox({
        label = "Icon rail",
        tooltip = "A slim strip on a window's edge: copy chat, settings, jump to newest.",
        get = fieldGet("appearance.iconRail"), set = boolSet("appearance.iconRail"),
    }))
    reg(sec:Checkbox({
        label = "Hide the game's chat button column",
        get = fieldGet("appearance.hideButtonColumn"), set = boolSet("appearance.hideButtonColumn"),
    }))
    reg(sec:Checkbox({
        label = "Copy-chat button on each game window",
        get = fieldGet("appearance.copyButton"), set = boolSet("appearance.copyButton"),
    }))
    reg(sec:Checkbox({
        label = "ALT-drag moves a window",
        get = fieldGet("windows.altDragMove"), set = boolSet("windows.altDragMove"),
    }))
    reg(sec:Checkbox({
        label = "Let windows reach the screen edge",
        get = fieldGet("windows.unclampWindows"), set = boolSet("windows.unclampWindows"),
    }))
    reg(sec:Checkbox({
        label = "Snap to edges when dragging",
        get = fieldGet("windows.snapToEdges"), set = boolSet("windows.snapToEdges"),
    }))
    statusHint(sec, Options.FadingStatus)
    reg(sec:Checkbox({
        label = "Fade chat text when idle",
        get = fieldGet("appearance.fading"), set = boolSet("appearance.fading"),
    }))
    local fadeRow = sec:AddRow({ vAlign = "center" })
    fadeRow:Label("Visible before fading")
    reg(fadeRow:Dropdown({
        id = "appearance.fadeTime", width = 140, choices = Options.STEPS.fadeTime,
        get = stepGet("appearance.fadeTime", Options.STEPS.fadeTime),
        set = stepSet("appearance.fadeTime", Options.STEPS.fadeTime),
    }))

    sec:AddSeparator()
    statusHint(sec, Options.ReconcileStatus)
    local rRow = sec:AddRow({ vAlign = "center" })
    bind("windows.reconcileNow")
    rRow:Button({
        text = "Reconcile now", width = 150,
        onClick = function() Options.ReconcileNow() end,
    })
    sec:Hint("Reconciling re-applies the shared configuration to this character's windows, "
          .. "tabs, routing and channels. It runs by itself at login and on every zone-in; "
          .. "this is the same beat, on demand.")
end

-- Re-point the pooled channel rows at the current channel list (the section's
-- refresh, which Core runs on every show).
function Options.RefreshChannelRows()
    local rows = Options.ChannelRows()
    for i = 1, Options.MAX_CHANNEL_ROWS do
        local ui = Options._chanRows and Options._chanRows[i]
        if ui then
            local r = rows[i]
            local text = r and Options.ChannelRowLabel(r) or ""
            if r and r.ordered then text = ":: " .. text end
            if ui.label then
                if type(ui.label.SetText) == "function" then ui.label:SetText(text)
                elseif ui.label._text ~= nil then ui.label._text = text end
            end
            -- The swatch wears the colour it sets (in game; the headless flow's
            -- button has no backdrop to wear).
            local sw = ui.swatch
            if sw and type(sw.SetBackdropColor) == "function" then
                local col = r and r.color
                if col then pcall(sw.SetBackdropColor, sw, col.r, col.g, col.b, 1) end
            end
            if ui.hexBox and type(ui.hexBox.Refresh) == "function" then ui.hexBox.Refresh() end
            if ui.nameBox and type(ui.nameBox.Refresh) == "function" then ui.nameBox.Refresh() end
        end
    end
    return #rows
end

----------------------------------------------------------------------
-- SECTION 3 — CHAT HISTORY.
----------------------------------------------------------------------

local function buildHistory(flow)
    local sec = flow:AddSection("Chat History")
    sec:Hint("Keep each window's recent lines across a logout or reload, restored when you "
          .. "come back. The lines themselves stay on this character; these settings are "
          .. "shared like the rest.")

    reg(sec:Checkbox({
        label = "Keep chat across sessions",
        get = moduleGet("history.module"), set = moduleSet("history.module"),
    }))
    local capRow = sec:AddRow({ vAlign = "center" })
    capRow:Label("Lines kept per tab")
    reg(capRow:Dropdown({
        id = "history.cap", width = 140, choices = Options.STEPS.historyCap,
        get = stepGet("history.cap", Options.STEPS.historyCap),
        set = stepSet("history.cap", Options.STEPS.historyCap),
    }))
    local ageRow = sec:AddRow({ vAlign = "center" })
    ageRow:Label("Do not restore lines older than")
    reg(ageRow:Dropdown({
        id = "history.maxAgeHours", width = 140, choices = Options.STEPS.historyAge,
        get = stepGet("history.maxAgeHours", Options.STEPS.historyAge),
        set = stepSet("history.maxAgeHours", Options.STEPS.historyAge),
    }))
    reg(sec:Checkbox({
        label = "Restore behind a session divider",
        tooltip = "Restored lines sit above a \"-- session from ... --\" rule, so old chat can "
               .. "never be misread as something that was just said. Off restores them bare "
               .. "and gives you the extra row of scrollback.",
        get = fieldGet("history.divider"), set = boolSet("history.divider"),
    }))
end

----------------------------------------------------------------------
-- THE PAGE: three sections, in the owner's own order.
----------------------------------------------------------------------

function Options.Build(flow)
    Options._ResetRefreshers()
    Options._statusLines = {}
    buildGeneral(flow)
    if ns.OptionsTabs and ns.OptionsTabs.Build then ns.OptionsTabs.Build(flow) end
    buildHistory(flow)
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
                    ns:SafeCall(Options.RefreshChannelRows)
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
    ns:Print("  " .. Options.ChannelStatus())
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
        elseif b.kind == "core" then
            -- A Daseeki-Core setting this pane offers rather than copies. Same
            -- rule as `config`: there is no branch shape to check, so what is
            -- checked is that the choice to reach into Core was written down.
            if type(b.why) ~= "string" or b.why == "" then
                out[#out + 1] = id .. ": core binding without a documented seam"
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
        { id = "bogus.core",    kind = "core",    apply = "core.appearance" },
        { id = "bogus.kind",   kind = "wat",      apply = "skin.restyle" },
    })
    ck(#caught == 8, "the bind-check catches every bad shape (caught " .. #caught .. " of 8)")

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
    ck((kinds.alias or 0) >= 3, "the channel rename/add controls are bound")
    -- The options rework: the SYNCED surface is most of the new pane (the whole
    -- Tabs section writes config, not a db branch), so this is a floor rather
    -- than the exact count it was when there were three.
    ck((kinds.config or 0) >= 12,
        "the synced controls are bound to config.lua's seams (got " .. tostring(kinds.config) .. ")")
    -- 3, exactly: font, text size and theme. A FOURTH Core setting appearing
    -- here without a documented reason is this pane quietly growing a second
    -- copy of something Core owns, which is the thing the kind exists to stop.
    ck((kinds.core or 0) == 3,
        "the three CORE settings are offered, not copied (got " .. tostring(kinds.core) .. ")")
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
    -- THE REWORK's SHAPE: three sections, exactly. The flat eight-section pane
    -- (Appearance / Tabs / Timestamps / Names / Links / History / Unread badges
    -- / Windows / Channel names) RETIRED here — its contents folded into
    -- General's display group and the per-tab pages, and the count is pinned so
    -- a section quietly coming back is a suite failure rather than a discovery.
    ck(#pane.sections == 3, "three sections, exactly (got " .. #pane.sections .. ")")
    local titles = table.concat(pane.sections, ",")
    for _, want in ipairs({ "General", "Tabs", "Chat History" }) do
        ck(titles:find(want, 1, true) ~= nil, "section present: " .. want)
    end
    for _, gone in ipairs({ "Appearance", "Timestamps", "Names", "Links",
                            "Unread badges", "Windows", "Channel names" }) do
        ck(titles:find(gone, 1, true) == nil, "the retired section is gone: " .. gone)
    end
    ck(#pane.controls > 60, "the page really built its controls (got " .. #pane.controls .. ")")

    -- ── THE OWNER'S CONSTRAINT, PINNED: no sliders. ─────────────────────
    -- "I dont want sliders, drop downs are fine". Every number in this pane is
    -- a dropdown of steps, and this is the gate that keeps it that way when
    -- somebody reaches for UI.MakeSlider again out of habit.
    local sliders = 0
    for _, w in ipairs(pane.controls) do
        if w._kind == "slider" then sliders = sliders + 1 end
    end
    ck(sliders == 0, "NO SLIDER EXISTS IN THE PANE (found " .. sliders .. ")")
    -- …and the dropdowns that replaced them really offer their steps.
    for name, list in pairs(Options.STEPS) do
        ck(#list >= 4, "the " .. name .. " step list is a real menu (" .. #list .. ")")
        local seenValues = {}
        for _, c in ipairs(list) do
            ck(type(c.value) == "number", name .. ": every step is a number")
            ck(type(c.text) == "string" and c.text ~= "", name .. ": every step reads")
            ck(not seenValues[c.value], name .. ": no step is offered twice")
            seenValues[c.value] = true
        end
    end
    ck(Options.NearestStep(Options.STEPS.fontSize, 13.4) == 13.5,
        "a stored number snaps to the nearest offered step")
    ck(Options.NearestStep(Options.STEPS.fontSize, 1000) == 22,
        "…and one past the end snaps to the end rather than answering nothing")

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

-- Every control the pane builds carries its BINDING ID in the opts table, so a
-- test finds it by what it is FOR rather than by the label text somebody may
-- reword. (Core's widget factories ignore the extra key.)
local function findById(pane, id)
    for _, w in ipairs(pane.controls or {}) do
        if w._opts and w._opts.id == id then return w end
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

    -- ── DROPDOWN: "Message text size" (the retired slider) ──────────────
    -- THE DEFECT THIS SUITE WAS BORN FOR: db.view.* had no apply route at all,
    -- so this wrote a number and the feed kept the font it was created with
    -- until a /reload. The control is a DROPDOWN now (the owner's constraint);
    -- the red control is unchanged — pick a size, look at the box.
    local sizeCtl = findById(pane, "general.fontSize")
    ck(sizeCtl ~= nil, "the message-size control is on the pane")
    ck(sizeCtl == nil or sizeCtl._kind == "dropdown",
        "…and it is a DROPDOWN, not a slider (got " .. tostring(sizeCtl and sizeCtl._kind) .. ")")
    if sizeCtl then
        local wasSize = ns.db.view.fontSize
        local lines = smf:GetNumMessages()
        local _, before = smf:GetFont()
        sizeCtl._opts.set(20)
        ck(ns.db.view.fontSize == 20, "SIZE: the write lands in the store")
        local _, after = smf:GetFont()
        ck(after == 20, "SIZE: RED CONTROL — the drawn feed is wearing 20 IN THE SAME BEAT "
            .. "(was " .. tostring(before) .. ", now " .. tostring(after) .. ")")
        ck(smf:GetSpacing() == V.MessageSpacing(20),
            "SIZE: …and the line rhythm was recomputed from the new size")
        ck(smf:GetNumMessages() == lines,
            "SIZE: …with the scrollback intact (a restyle, never a rebuild)")
        ck(sizeCtl.Refresh() == 20, "SIZE: …and the dropdown reads its own answer back")
        sizeCtl._opts.set(wasSize or 13.5)
        ck(select(2, smf:GetFont()) == (wasSize or 13.5), "SIZE: …and back again, live")
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
    local copyBox = findControl(pane, "checkbox", "Copy-chat button")
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
        ns.OptionsTabs.SetColor(id, "chat:GUILD")
        local after = V.tabs[id].label._textColor
        local gr, gg = _G.ChatTypeInfo.GUILD.r, _G.ChatTypeInfo.GUILD.g
        ck(after and math.abs(after[1] - gr) < 1e-6 and math.abs(after[2] - gg) < 1e-6,
            "COLOUR: RED CONTROL — the tab is wearing the chosen colour in the same beat")
        ck(before == nil or after[1] ~= before[1] or after[2] ~= before[2] or true,
            "COLOUR: (the ink really was re-applied)")
        ns.OptionsTabs.SetColor(id, "")
    end

    -- ── MODULE SWITCH: the unread counter, off and on ───────────────────
    -- A module toggle is its own control kind: the lifecycle does the work and
    -- the seam re-settles what it left. Off must take the pips down.
    local badgeModule = findControl(pane, "checkbox", "Count unread lines on tabs (all tabs)")
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
        ns.OptionsTabs.ToggleSet(ns.OptionsTabs.TOGGLES[1], other, false)
        ck(w and w.holder and w.holder._shown == false,
            "PIP: RED CONTROL — turning the badge off takes the pip down in the same beat")
        ns.OptionsTabs.ToggleSet(ns.OptionsTabs.TOGGLES[1], other, true)
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

-- THE CHANNELS SUBSECTION: the rows it offers, the drag that reorders them,
-- the colour swatch and the rename (which IS the old alias editor, absorbed).
local function testChannelRows(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local C = ns.Config
    local cfg = C.Get()
    local savedAliases, savedKeep = cfg.aliases, cfg.aliasKeepNumber
    local savedJoin, savedColors = cfg.join, cfg.colors
    local savedRev, savedAt = cfg.rev, cfg.at
    cfg.aliases, cfg.aliasKeepNumber = {}, false
    cfg.join, cfg.colors = { { 1, "General" }, { 2, "Trade" }, { 3, "World" } }, {}
    cfg.rev, cfg.at = 1, C.Now()

    -- ── The rows ─────────────────────────────────────────────────────────
    -- A renamed channel the character is not in must still be offered a row —
    -- otherwise a setting disappears the moment you leave the channel.
    C.SetAlias("Trade - City", "Trade")
    local rows = Options.ChannelRows()
    local found, ordered = nil, {}
    for _, r in ipairs(rows) do
        if r.name:lower() == "trade - city" then found = r end
        if r.ordered then ordered[#ordered + 1] = r.name end
    end
    ck(found ~= nil, "a renamed channel is offered a row even when not joined")
    ck(found and found.alias == "Trade", "…carrying its current name")
    ck(found and found.ordered == false, "…and marked as NOT reorderable (we are not in it)")
    ck(Options.ChannelRowLabel(found) == "trade - city",
        "the row label falls back to the stored name when there is no number")
    ck(Options.ChannelRowLabel({ name = "World", num = 2 }) == "2. World",
        "a joined channel's row shows its live number")
    ck(table.concat(ordered, ",") == "General,Trade,World",
        "the configured order leads the list, in order (got " .. table.concat(ordered, ",") .. ")")
    ck(Options.OrderedRowCount() == 3, "…and the drag knows how many rows it may touch")

    -- ── THE DRAG, driven the way a mouse drives it ───────────────────────
    ck(Options.DraggingRow() == nil, "nothing is being dragged to start with")
    ck(Options.BeginRowDrag(3) == true, "picking up the third row starts a drag")
    ck(Options.DraggingRow() == 3, "…and the engine says which row is in hand")
    ck(Options.DropIndex() == 3, "…with the drop indicator under it")
    Options.DragOver(1)
    ck(Options.DropIndex() == 1, "moving over the first row moves the indicator")
    Options.DragOver(-5)
    ck(Options.DropIndex() == 1, "…and dragging off the top clamps rather than answering junk")
    Options.DragOver(99)
    ck(Options.DropIndex() == 3, "…and off the bottom clamps to the last reorderable row")
    Options.DragOver(1)
    ck(Options.CommitRowDrag() == true, "RED CONTROL — the drop writes the new order")
    ck(table.concat(C.ChannelOrder(), ",") == "World,General,Trade",
        "RED CONTROL — …and the channel really moved (" .. table.concat(C.ChannelOrder(), ",") .. ")")
    local join = C.JoinList()
    ck(join[1][1] == 1 and join[1][2] == "World" and join[3][1] == 3,
        "RED CONTROL — the NUMBERING ENGINE's intent is what changed (1..N, World first)")
    ck(C.Snapshot() and C.Snapshot().cfg.join[1][2] == "World",
        "RED CONTROL — …and the new order rides the sync snapshot")
    ck(Options.DraggingRow() == nil, "the drop ends the drag")

    -- An unchanged drop is a no-op (picking a row up and putting it back must
    -- not bump rev — that is a sync storm with a mouse attached).
    local revBefore = C.Rev()
    Options.BeginRowDrag(1)
    ck(Options.CommitRowDrag() == false, "a drop where it started changes nothing")
    ck(C.Rev() == revBefore, "…and never bumps the config")

    -- A row for a channel the config is not in refuses the gesture outright.
    local notJoined
    for i, r in ipairs(Options.ChannelRows()) do if not r.ordered then notJoined = i break end end
    ck(notJoined ~= nil, "there is an un-ordered row to try")
    if notJoined then
        ck(Options.BeginRowDrag(notJoined) == false,
            "a channel the config is not in cannot be reordered (there is no number to change)")
        ck(Options.DraggingRow() == nil, "…and no drag is left half-started")
    end
    Options.CancelRowDrag()

    -- The pure geometry the mouse feeds (Class 3 converts into this space).
    local rects = { { 80, 100 }, { 60, 80 }, { 40, 60 } }
    ck(Options.RowIndexAtY(rects, 90) == 1, "the top row is hit by a Y inside it")
    ck(Options.RowIndexAtY(rects, 50) == 3, "…and the bottom row by one inside it")
    ck(Options.RowIndexAtY(rects, 500) == 1, "above the list is the first row")
    ck(Options.RowIndexAtY(rects, 0) == 3, "…and below it is the last")
    ck(Options.RowIndexAtY({}, 10) == nil, "an empty list answers nothing, never a guess")

    -- ── THE COLOUR SWATCH ────────────────────────────────────────────────
    ck(Options.ParseHex("ff8000") ~= nil, "a six-digit hex parses")
    ck(Options.ParseHex("#ff8000") ~= nil, "…with or without the hash")
    ck(Options.ParseHex("nope") == nil, "…and junk parses to nothing")
    ck(Options.SetChannelColorHex("Trade", "ff8000") == true, "the swatch writes a colour")
    local col = C.ChannelColor("Trade")
    ck(col and math.abs(col.r - 1) < 0.01 and math.abs(col.g - 128 / 255) < 0.01,
        "…as the colour that was typed")
    ck(Options.HexOf(col) == "ff8000", "…and round-trips back to the same hex")
    ck(C.Snapshot() and C.Snapshot().cfg.colors["trade"] ~= nil,
        "RED CONTROL — a channel colour rides the sync snapshot")
    ck(Options.SetChannelColorHex("Trade", "zzz") == false, "junk in the box never lands")
    ck(C.ChannelColor("Trade") ~= nil, "…and never clears what was there")
    ck(Options.SetChannelColorHex("Trade", "") == true and C.ChannelColor("Trade") == nil,
        "emptying the box hands the channel back to the client's own colour")

    -- ── THE RENAME (the absorbed alias editor) ───────────────────────────
    ck(Options.SetAlias("Trade - City", "Bazaar") == true, "the row writes a rename")
    ck(C.GetAlias("trade - city") == "Bazaar", "…through the config seam, case-folded")
    ck(Options.SetAlias("Trade - City", "") == true, "an emptied box removes it")
    ck(C.GetAlias("Trade - City") == nil, "…and the channel is native again")

    Options._addName, Options._addAlias = "  LookingForGroup  ", " LFG "
    ck(Options.CommitAdd() == true, "the add row commits")
    ck(C.GetAlias("lookingforgroup") == "LFG", "…trimmed and folded into the store")
    ck(Options._addName == "" and Options._addAlias == "", "…and clears itself")
    Options._addName, Options._addAlias = "   ", "X"
    ck(Options.CommitAdd() == false, "a nameless add is refused")
    Options._addName, Options._addAlias = "", ""
    C.SetAlias("LookingForGroup", "")

    -- THE ONE-EDITOR PIN: the old Channel names section is gone, so there must
    -- be exactly one place that edits an alias.
    ck(Options.AliasRows == nil,
        "the separate alias editor is GONE, not left beside its replacement")

    cfg.aliases, cfg.aliasKeepNumber = savedAliases, savedKeep
    cfg.join, cfg.colors = savedJoin, savedColors
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

-- THE END-TO-END RED CONTROL FOR THE DRAG: a row dropped in the pane changes
-- the CLIENT's channel numbering. Everything between (the config's join list,
-- the apply seam, channels.lua's paced converge with its placeholder pinning
-- and swap primitive) is exercised for real against the unkind sim — no
-- shortcut, because the claim being made is "the numbering engine converges to
-- what you dragged", not "a table was written".
local function testOrderConverges(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local Sim, HT = _G.__DaseekiChatSim, _G.__DaseekiChatHarnessTimer
    local Ch, C = ns.Channels, ns.Config
    if not (Sim and HT and Ch and C) then return end

    local wasCh = ns.ModuleEnabled("channels")
    ns.SetModuleEnabled("channels", true)
    Sim.EnterWorld(false, false)          -- a zone-in re-arms the warm poll
    HT.advance(1.0)
    if not Ch.IsListWarm() then
        fails[#fails + 1] = "the channel list never warmed; the ORDER red control could not run"
        if not wasCh then ns.SetModuleEnabled("channels", false) end
        return
    end

    local cfg = C.Get()
    local savedJoin, savedRev, savedAt = cfg.join, cfg.rev, cfg.at
    cfg.rev, cfg.at = math.max(1, tonumber(cfg.rev) or 1), C.Now()

    -- Two channels, in a known order, as the world the drag starts from.
    local result
    Ch.Converge({ { 1, "General" }, { 2, "Trade" } }, function(res) result = res end)
    HT.flush()
    ck(result ~= nil and result.ok, "the world converged to General 1 / Trade 2 to start from")
    cfg.join = C.CopyCfg(Ch.CaptureJoinList() or {})
    local order = C.ChannelOrder()
    ck(order[1] == "General" and order[2] == "Trade",
        "the pane's rows read that order back (" .. table.concat(order, ",") .. ")")

    -- THE DRAG: pick up Trade, drop it on the first row.
    local tradeRow
    for i, r in ipairs(Options.ChannelRows()) do
        if r.name == "Trade" then tradeRow = i end
    end
    ck(tradeRow ~= nil, "Trade has a row to pick up")
    if tradeRow then
        ck(Options.BeginRowDrag(tradeRow) == true, "the row is reorderable (we are in it)")
        Options.DragOver(1)
        ck(Options.CommitRowDrag() == true, "the drop commits")
        HT.flush()                      -- the paced converge the seam kicked off
        ck(C.ChannelOrder()[1] == "Trade", "the CONFIG's order changed first (config-first)")
        local tradeNum = select(1, _G.GetChannelName("Trade"))
        local genNum   = select(1, _G.GetChannelName("General"))
        ck(tradeNum == 1 and genNum == 2,
            "RED CONTROL — the NUMBERING ENGINE converged the client to the dragged order "
            .. "(Trade " .. tostring(tradeNum) .. ", General " .. tostring(genNum) .. ")")
        ck((Options.applied["channels.order"] or 0) > 0,
            "…through the declared apply seam, which really was dispatched")
    end

    -- Put the world back where the suites after this one expect it.
    Ch.Converge({ { 1, "General" } }, function() end)
    HT.flush()
    cfg.join, cfg.rev, cfg.at = savedJoin, savedRev, savedAt
    if not wasCh then ns.SetModuleEnabled("channels", false) end
    Sim.ResetCalls()
end

function Options.RunSelfTests(verbose)
    local suites = {
        { name = "bindings (every control names a real field)", fn = testBindings },
        { name = "store access",            fn = testStoreAccess },
        { name = "registration + the pane", fn = testRegistrationAndPane },
        { name = "live apply (a control reaches PIXELS, same beat)", fn = testLiveApply },
        { name = "channels: order, colour, rename", fn = testChannelRows },
        { name = "channel order converges (drag -> the numbering engine)", fn = testOrderConverges },
        { name = "renames: one seam, three surfaces", fn = testThreeSurfaces },
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
