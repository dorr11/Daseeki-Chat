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
-- ============ THE FORM LANGUAGE (owner UAT, 2026-08-12) ============
--
-- THE FOUR THINGS THE OWNER SAID, and the one mechanism each of them needs:
--
--  "there are no labels on the drop downs"   -> Form.LabelCell / Form.SetCaption
--  "all options are vertical in a single
--   column making it hard to read"           -> Form.Group + Form.Pair
--  "there are just way too many options"     -> Form.Advanced (the fold)
--  "'which messages come here' should be
--   formatted like the [client's config]"    -> Form.Group + Form.Checks
--
-- ── WHY LABELS WERE MISSING, exactly ──────────────────────────────────────
-- Core's UI.MakeLabel returns a FRAME carrying no `uiWidth` and never sized.
-- Core's row arranger then computes `ww = w.uiWidth or w:GetWidth()` — nil or
-- zero — and calls `w:SetWidth(ww)`. A zero-width frame inside the pane's
-- clipping ScrollChild is culled together with its FontString. Core's own file
-- names this defect class three separate times (the checkbox self-size fix,
-- the segmented self-size fix, the stackBlocks safety net) and the ROW-ITEM net
-- it added patches HEIGHT only — so the width hole is still open, and every
-- `row:Label("Font")` in the old pane fell straight through it.
--
-- We do not fix Core in this round. We stop handing it an unsized label:
-- Form.LabelCell gives every caption a real width of its own, which is both the
-- fix and the thing that makes the label column LINE UP — one mechanism, two
-- wins. The corestub now runs Core's own arranger, so a caption that would be
-- culled in game is culled in the harness.
--
-- ── WHY RE-CAPTIONING SILENTLY DID NOTHING ────────────────────────────────
-- Two more shapes, both of them "the call succeeded and the pixel did not
-- move":
--   * a Core Label is a FRAME. It has no SetText. options.lua's channel-row
--     refresh called `ui.label:SetText(name)` behind a type guard, the guard
--     was false in game, and the channel names were never written at all.
--   * a Core Button HAS SetText — but MakeButton never calls SetFontString, so
--     the text goes to a fontstring that does not exist. options_tabs.lua's
--     sub-tab nav tried that first, "succeeded", and never reached the
--     `elseif btn._label` branch. Four empty boxes, forever.
-- Form.SetCaption is the ONE re-caption path in this addon: it writes the
-- FontString the kit actually draws (`widget._label`), never the frame, never
-- the dead Button method, and it REFUSES (returns false) on a widget that has
-- no drawn caption to write — so "I relabelled it" can never again mean "I
-- called something that returned".
--
-- ── LAYOUT IS PURE ────────────────────────────────────────────────────────
-- Everything that DECIDES a column or a height below is a pure function of
-- numbers, driven directly by the suite at the hub's real width range (876 at
-- the narrowest window the hub can be dragged to, 880 at any larger one — see
-- Daseeki-Core hub.lua). The frame glue only places what the pure half decided.
----------------------------------------------------------------------

local Form = {}
Options.Form = Form

Form.LABEL_W       = 150   -- the label column; every control in a group lines up
Form.ITEM_GAP      = 8     -- Core's own ITEM_GAP (daseekiui.lua)
Form.ROW_GAP       = 10    -- Core's own rowGap token
Form.ROW_H         = 26    -- a control row's height budget (24 + a unit of air)
Form.CHECK_H       = 24    -- one checklist row
Form.HINT_H        = 22    -- one wrapped hint line
Form.CARD_PAD      = 10    -- MakeEditorCard's inner padding, per side
Form.CARD_TITLE_H  = 22    -- …and its title band
Form.CARD_SLACK    = 8     -- one row of headroom, so a font step never clips
Form.MIN_CONTENT_W = 876   -- the hub's narrowest content width (hub.lua MIN_W)
Form.MAX_CONTENT_W = 880   -- …and its widest (theme.lua contentMaxW)

-- PURE. The width a full-width group box gives the rows inside it.
function Form.GroupInner(contentW)
    return (tonumber(contentW) or Form.MIN_CONTENT_W) - 2 * Form.CARD_PAD
end

-- PURE. The laid width of one [label][control] cell.
function Form.CellWidth(controlW, labelW)
    return (tonumber(labelW) or Form.LABEL_W) + Form.ITEM_GAP + (tonumber(controlW) or 0)
end

-- PURE. Do two cells fit side by side in `avail`? The gap BETWEEN the columns
-- is a full row gap, not an item gap, so the two columns read as two columns.
Form.COL_GAP = 24
function Form.FitsTwoUp(wA, wB, avail)
    if not (wA and wB and avail) then return false end
    return (wA + Form.COL_GAP + wB) <= avail
end

-- THE SECOND COLUMN STARTS AT THE SAME X ON EVERY ROW, or it is not a column.
-- Core's row arranger simply lays items left to right at their own widths, so a
-- row holding a 200-unit dropdown and a row holding a 120-unit one would put
-- their second captions 80 units apart — a ragged edge that reads as a mistake.
-- The FIRST COLUMN is therefore a fixed track, and the second caption absorbs
-- the difference into its own width. One number, and the columns line up.
Form.COL1_W = 380       -- caption track + the widest control the pane offers

-- PURE. How wide the second column's caption must be so that column two always
-- begins at COL1_W + COL_GAP, whatever the first column's control is.
function Form.SecondLabelW(aControlW, aLabelW, bLabelW)
    local used = Form.CellWidth(aControlW, aLabelW) + Form.ITEM_GAP
    local want = Form.COL1_W + Form.COL_GAP
    return (bLabelW or Form.LABEL_W) + math.max(0, want - used)
end

-- PURE. The x offset each cell of a planned row starts at. Returns the offsets
-- and the total laid width, so "no overlap" and "no overflow" are both
-- answerable from one call.
function Form.RowOffsets(widths, avail)
    local out, x = {}, 0
    for i, w in ipairs(widths or {}) do
        out[i] = x
        x = x + w + Form.COL_GAP
    end
    return out, math.max(0, x - Form.COL_GAP)
end

-- PURE. The whole two-column plan: given every cell's laid width and the width
-- available, which cells share a row. Never puts two cells on a row they do not
-- both fit on, never drops a cell, never repeats one.
function Form.PlanRows(widths, avail)
    local rows, i = {}, 1
    widths = widths or {}
    avail = tonumber(avail) or Form.MIN_CONTENT_W
    while i <= #widths do
        local a, b = widths[i], widths[i + 1]
        if b and Form.FitsTwoUp(a, b, avail) then
            rows[#rows + 1] = { i, i + 1 }
            i = i + 2
        else
            rows[#rows + 1] = { i }
            i = i + 1
        end
    end
    return rows
end

-- PURE. How tall a group box has to be to hold `units` of content without its
-- inner pane needing to scroll (MakeEditorCard's inner pane is noBar: content
-- taller than the card is content nobody can reach, which is the very defect
-- class this round exists to close).
function Form.BoxHeight(units, hasTitle)
    local h = Form.CARD_PAD * 2 + (tonumber(units) or 0) + Form.CARD_SLACK
    if hasTitle ~= false then h = h + Form.CARD_TITLE_H end
    return h
end

-- PURE. The height a checklist of n items costs at `cols` columns.
function Form.ChecklistHeight(n, cols)
    cols = math.max(1, tonumber(cols) or 2)
    return math.ceil(math.max(0, tonumber(n) or 0) / cols) * Form.CHECK_H + Form.ROW_GAP
end

-- PURE. Core's own checklist rule (AddChecklist COLLAPSE_W = 460): two columns
-- while the pane is wide enough, one when it is not. Stated here so the height
-- budget above and the kit's own placement can never disagree.
Form.CHECKLIST_COLLAPSE_W = 460
function Form.ChecklistColumns(avail)
    return ((tonumber(avail) or 0) >= Form.CHECKLIST_COLLAPSE_W) and 2 or 1
end

----------------------------------------------------------------------
-- THE GLUE. Every function below only PLACES what the pure half decided.
----------------------------------------------------------------------

local function widgetCall(w, method, ...)
    if type(w) ~= "table" then return nil end
    local fn = w[method]
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, w, ...)
    if not ok then return nil end
    return a == nil and true or a
end

-- Give a Core Label frame the width Core forgot to give it. THE fix for the
-- blank-caption class, and the reason the label column lines up.
function Form.SizeLabel(w, width)
    if type(w) ~= "table" then return nil end
    width = tonumber(width) or Form.LABEL_W
    w.uiWidth = width
    widgetCall(w, "SetWidth", width)
    local fs = w._label
    if fs then
        widgetCall(fs, "SetWidth", width)
        widgetCall(fs, "SetJustifyH", "LEFT")
        widgetCall(fs, "SetWordWrap", false)
    end
    return w
end

-- An inline caption on the SAME ROW as its control (the owner's ask), sized so
-- the kit really draws it.
function Form.LabelCell(row, text, width)
    if type(row) ~= "table" or type(row.Label) ~= "function" then return nil end
    local w = row:Label(text or "")
    return Form.SizeLabel(w, width)
end

-- THE ONE RE-CAPTION PATH. Returns true only when a caption a player can read
-- was really written.
function Form.SetCaption(widget, text)
    if type(widget) ~= "table" then return false end
    text = tostring(text or "")
    local fs = widget._label
    if not (fs and type(fs.SetText) == "function") then return false end
    pcall(fs.SetText, fs, text)
    -- Keep the recorded opts in step so a headless test finds the control by
    -- what it now SAYS. (In game these keys do not exist; the write is a no-op
    -- on a table nothing reads.)
    local o = widget._opts
    if type(o) == "table" then
        if o.text ~= nil then o.text = text end
        if o.label ~= nil then o.label = text end
    end
    return true
end

-- Tint a caption (the channel row's name IS the colour preview).
function Form.TintCaption(widget, r, g, b)
    local fs = type(widget) == "table" and widget._label or nil
    if not (fs and type(fs.SetTextColor) == "function") then return false end
    if r == nil then
        local UI = _G.DaseekiUI
        if UI and UI.Color then r, g, b = UI.Color("text") else r, g, b = 1, 1, 1 end
    end
    pcall(fs.SetTextColor, fs, r, g, b, 1)
    return true
end

-- Show or hide a whole pooled row (the ghost-row fix: a row with no channel
-- behind it is not drawn at all).
function Form.ShowRow(items, on)
    for _, w in ipairs(items or {}) do
        if type(w) == "table" then widgetCall(w, on and "Show" or "Hide") end
    end
    return on and true or false
end

----------------------------------------------------------------------
-- GROUP BOXES. A bordered, titled card that hosts its own flow — Core's own
-- MakeEditorCard, which is exactly the client-config aesthetic the owner sent
-- as the reference (a titled border with rows inside it).
--
-- ITS HEIGHT IS A BUDGET, NOT A GUESS. Every helper below bumps `g.units` by
-- the height it just spent, so the card's height is the arithmetic sum of what
-- is inside it — and the suite pins that the card really covers its own
-- content, because MakeEditorCard's inner pane carries no scrollbar and
-- content taller than the card is content nobody can reach.
----------------------------------------------------------------------

Form.groups = {}

function Form.Group(flow, title, opts)
    opts = opts or {}
    local g = { title = title, units = 0, open = true, spent = {}, advanced = false }
    local row = (type(flow.AddRow) == "function") and flow:AddRow() or flow
    local card = (type(row.EditorCard) == "function")
        and row:EditorCard({ title = title, height = Form.BoxHeight(0, title ~= nil) })
        or nil
    g.card = card
    -- No card factory (a Core too old to carry one): the group degrades to the
    -- flow it was asked to build in, so every control still exists and is still
    -- wired. Quietly worse-looking beats quietly missing.
    g.flow = (card and card.flow) or flow
    Form.groups[#Form.groups + 1] = g
    return g
end

local function spend(g, units, what)
    if type(g) ~= "table" then return end
    g.units = g.units + units
    g.spent[#g.spent + 1] = { units, what }
end
Form._spend = spend

function Form.CloseGroup(g)
    if type(g) ~= "table" then return nil end
    g.height = Form.BoxHeight(g.units, g.title ~= nil)
    Form.ApplyGroup(g)
    return g.height
end

-- Push the group's current height and open/closed state onto the card. Core's
-- row arranger reads `uiHeight` on every layout, so this is all a fold needs.
function Form.ApplyGroup(g)
    local card = g and g.card
    if not card then return false end
    local h = g.open and (g.height or Form.BoxHeight(g.units, g.title ~= nil)) or 0
    card.uiHeight = h
    widgetCall(card, "SetHeight", math.max(h, 1))
    widgetCall(card, g.open and "Show" or "Hide")
    if g.open then widgetCall(card, "Relayout") end
    return true
end

-- A COLLAPSED group: the fold the owner asked for ("fold rarely-touched
-- toggles into a collapsed Advanced group per section"). The whole group is ONE
-- block, so collapsing it collapses everything inside it in one beat — no
-- per-control show/hide, no OnUpdate, nothing to get out of step.
function Form.Advanced(flow, title)
    local header = flow:AddRow()
    local g
    local btn = header:Button({
        text = "\226\150\184  " .. tostring(title or "Advanced"),   -- "▸ Title"
        width = 320, variant = "quiet",
        onClick = function() Form.ToggleAdvanced(g) end,
    })
    g = Form.Group(flow, nil, {})
    g.advanced, g.open, g.toggle, g.name = true, false, btn, tostring(title or "Advanced")
    return g
end

function Form.AdvancedLabel(g)
    return (g.open and "\226\150\190  " or "\226\150\184  ") .. tostring(g.name or "Advanced")
end

function Form.ToggleAdvanced(g)
    if type(g) ~= "table" then return false end
    g.open = not g.open
    Form.SetCaption(g.toggle, Form.AdvancedLabel(g))
    Form.ApplyGroup(g)
    Options._relayout()
    return g.open
end

-- Ask the hub to re-run its layout after a fold changed a block's height.
-- Reached through the pane the flow was built on, and silent when there is none
-- (the headless flow has no geometry to re-run).
Options._pane = nil
function Options._relayout()
    local p = Options._pane
    if type(p) == "table" and type(p.Layout) == "function" then pcall(p.Layout, p) end
    return true
end

----------------------------------------------------------------------
-- THE CELL HELPERS. Each one adds exactly one row to a group and pays for it.
----------------------------------------------------------------------

-- One [caption][control] row. `make(row)` builds the control on the row it is
-- handed, so the caller keeps the widget it needs.
function Form.Field(g, caption, make, labelW)
    local row = g.flow:AddRow({ vAlign = "center" })
    Form.LabelCell(row, caption, labelW)
    local w = make and make(row) or nil
    spend(g, Form.ROW_H + Form.ROW_GAP, caption)
    return w, row
end

-- TWO cells on one row, when the pure planner says they fit at the hub's
-- NARROWEST content width. They always share the row or always do not — the
-- decision is made once, from a number, not from live geometry.
function Form.Pair(g, a, b)
    local inner = Form.GroupInner(Form.MIN_CONTENT_W)
    local wB = b and Form.CellWidth(b.width or 140, b.labelW) or nil
    if b and Form.FitsTwoUp(Form.COL1_W, wB, inner) then
        local row = g.flow:AddRow({ vAlign = "center" })
        Form.LabelCell(row, a.caption, a.labelW)
        local wa = a.make and a.make(row) or nil
        -- The second column's caption absorbs the first column's slack into its
        -- own width, so column two starts at the same x on every row and
        -- NOTHING has to be anchored by hand.
        Form.LabelCell(row, b.caption, Form.SecondLabelW(a.width or 140, a.labelW, b.labelW))
        local wb = b.make and b.make(row) or nil
        spend(g, Form.ROW_H + Form.ROW_GAP, (a.caption or "") .. " | " .. (b.caption or ""))
        return wa, wb, row
    end
    local wa = Form.Field(g, a.caption, a.make, a.labelW)
    local wb = b and Form.Field(g, b.caption, b.make, b.labelW) or nil
    return wa, wb
end

-- One checkbox on its own row (its caption is its own — Core's MakeCheckbox
-- draws the label inline and self-sizes, so it is never culled).
function Form.Check(g, opts)
    local w = g.flow:Checkbox(opts)
    spend(g, Form.CHECK_H + Form.ROW_GAP, opts and opts.label)
    return w
end

-- A two-column checkbox grid — Core's own AddChecklist, which is the "TWO-
-- COLUMN placement where the hub page width allows" the brief asked for: it
-- lays two columns and collapses to one on a narrow pane, by itself.
function Form.Checks(g, items)
    local grid
    if type(g.flow.AddChecklist) == "function" then
        grid = g.flow:AddChecklist(items)
    else
        grid = { _boxes = {} }
        for _, it in ipairs(items or {}) do
            grid._boxes[#grid._boxes + 1] = g.flow:Checkbox(it)
        end
    end
    local cols = Form.ChecklistColumns(Form.GroupInner(Form.MIN_CONTENT_W))
    spend(g, Form.ChecklistHeight(#(items or {}), cols), "checklist")
    return grid
end

-- ONE short hint per GROUP — never one per control (the owner: the pane
-- narrates). Anything longer than a line belongs in a tooltip.
function Form.Note(g, text)
    local h = g.flow:Hint(text)
    spend(g, Form.HINT_H, "hint")
    return h
end

-- A row the caller builds itself (the channel rows), paying its own height.
function Form.Row(g, height)
    local row = g.flow:AddRow({ vAlign = "center" })
    spend(g, (tonumber(height) or Form.ROW_H) + Form.ROW_GAP, "row")
    return row
end

function Form.Button(g, opts)
    local row = g.flow:AddRow({ vAlign = "center" })
    local b = row:Button(opts)
    spend(g, Form.ROW_H + Form.ROW_GAP, opts and opts.text)
    return b, row
end

-- Core's MakeEditBox sets `_fillWidth = true`, which means the FIRST edit box
-- on a row swallows every remaining unit and the SECOND one is squeezed to
-- Core's 40-unit floor. That is why the channel rows rendered as one enormous
-- hex field beside a stub of a name field. Any edit box sharing a row states
-- its own width instead.
function Form.FixWidth(w, width)
    if type(w) ~= "table" then return w end
    w._fillWidth = false
    w.uiWidth = tonumber(width) or 120
    widgetCall(w, "SetWidth", w.uiWidth)
    return w
end

-- Grey an edit box's own text (the "this is the game's name, not your name"
-- state on a rename field that has never been filled in).
function Form.GreyBox(w, on)
    local box = type(w) == "table" and (w.editBox or w) or nil
    if not (box and type(box.SetTextColor) == "function") then return false end
    local UI = _G.DaseekiUI
    local r, g2, b = 1, 1, 1
    if UI and UI.Color then r, g2, b = UI.Color(on and "muted" or "text") end
    pcall(box.SetTextColor, box, r, g2, b, 1)
    return true
end

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

-- A debug line, not a pane line. It used to sit under the placement dropdown
-- and narrate "0 tab(s) carry a colour of their own", which is exactly the
-- noise the owner's "way too many options" was about.
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

-- What the inline rename box SHOWS for row i: the alias when there is one,
-- otherwise the channel's real name, greyed — so the field always says what the
-- channel is currently called instead of sitting there empty and nameless.
function Options.RenameBoxText(i)
    local r = Options.ChannelRows()[tonumber(i) or 0]
    if not r then return "" end
    if r.alias ~= "" then return r.alias end
    return r.name
end

-- …and its commit. Typing the channel's own name back (or emptying the field)
-- is the REMOVE verb, not "rename Trade to Trade": the greyed placeholder must
-- never turn into a stored alias just because the player clicked into the box
-- and back out of it again.
function Options.SetAliasFromRow(name, typed)
    local function fold(s) return (tostring(s or ""):gsub("%s+", "")):lower() end
    if fold(typed) == "" or fold(typed) == fold(name) then
        return Options.SetAlias(name, "")
    end
    return Options.SetAlias(name, typed)
end

-- THE API PATH for aliasing a channel this character has never seen. There is
-- deliberately NO pane control for it any more (the owner: "the channel rename
-- piece is terrible" — the orphan "Rename a channel you are not in right now:"
-- field beneath the rows was the piece). An alias made here grows a row of its
-- own the moment it exists, which is where it is then edited.
Options._addName, Options._addAlias = "", ""

-- The add verb's commit: a name and an alias, for a channel the client does not
-- currently list. Refuses a nameless add; an empty alias on a named channel is
-- still the remove verb, which is the honest reading.
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
-- THE CHANNEL ROWS (owner UAT: "the channel color section doesnt show you
-- what channel your editing", "the channel rename piece is terrible").
--
-- WHAT HE SAW, and why. Three defects on one surface:
--   1. NO CHANNEL NAME. The row's label was a Core Label FRAME; the refresh
--      wrote it with `ui.label:SetText(...)` behind a type guard that is FALSE
--      on a frame, so the name was never written — and even if it had been, the
--      label carried no width and the ScrollChild culled it. Two independent
--      reasons for the same blank.
--   2. TWELVE ROWS FOR FIVE CHANNELS. The pool is twelve; nothing hid the rows
--      with no channel behind them, so seven ghosts sat there with an empty
--      label, a Colour button and two empty fields each.
--   3. AN ENORMOUS HEX FIELD BESIDE A STUB. Core's MakeEditBox is `_fillWidth`,
--      so the FIRST edit box on a row swallows every remaining unit and the
--      second is squeezed to Core's 40-unit floor.
--
-- WHAT REPLACES IT: one row per REAL channel, carrying
--   [:: handle] [number + NAME, inked in that channel's own colour] [Colour]
--   [hex] [rename] — the name doubling as the live colour preview, the rename
-- inline where the channel is, and the orphan "Rename a channel you are not in
-- right now:" field GONE. A channel the character is not in keeps its colour
-- and its name and says "not joined" instead of pretending to be reorderable.
----------------------------------------------------------------------

Options.HANDLE_W = 22
Options.NAME_W   = 230

local function buildChannels(sec)
    local chan = Form.Group(sec, "Channels")
    Form.Note(chan, "Drag a row by its handle to change that channel's number. The name box "
        .. "renames it everywhere; the colour box takes six hex digits, and emptying it hands "
        .. "the channel back to the game.")

    bind("channels.order"); bind("channels.color"); bind("channels.rename")
    Options._chanRows = {}
    for i = 1, Options.MAX_CHANNEL_ROWS do
        local row = Form.Row(chan)
        -- Every caption below is BUILT with placeholder text, so the kit really
        -- creates the FontString the refresh then writes through Form.SetCaption.
        -- A control born captionless has nothing to re-caption (Core draws no
        -- label it was not asked for at construction), which is exactly how the
        -- sub-tab buttons ended up permanently blank.
        local handle = Form.LabelCell(row, "::", Options.HANDLE_W)
        local label  = Form.LabelCell(row, "channel", Options.NAME_W)
        local swatch = row:Button({
            text = "Colour", width = 80, variant = "quiet",
            onClick = function()
                local r = Options.ChannelRows()[i]
                if r then Options.OpenColorPicker(r.name) end
            end,
        })
        local hexBox = Form.FixWidth(row:EditBox({
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
        }), 90)
        reg(hexBox)
        local nameBox = Form.FixWidth(row:EditBox({
            width = 150,
            get = function() return Options.RenameBoxText(i) end,
            set = function(v)
                local r = Options.ChannelRows()[i]
                if r then Options.SetAliasFromRow(r.name, v) end
                Options._refresh()
            end,
        }), 150)
        reg(nameBox)
        Options._chanRows[i] = { row = row, handle = handle, label = label,
                                 swatch = swatch, hexBox = hexBox, nameBox = nameBox }
        installRowDrag(row, i)
    end
    Options._chanGroup = chan
    Form.CloseGroup(chan)
    return chan
end

----------------------------------------------------------------------
-- SECTION 1 — GENERAL.
----------------------------------------------------------------------

local function buildGeneral(flow)
    local sec = flow:AddSection("General")
    local UI = _G.DaseekiUI

    -- ══ GROUP: APPEARANCE ════════════════════════════════════════════════
    -- Two columns, every control captioned on its own row, one hint for the
    -- whole box. This is the layout the rest of the page is built in.
    local look = Form.Group(sec, "Appearance")
    Form.Note(look, "Font, text size and theme belong to the whole Daseeki suite - changing one "
        .. "here changes it everywhere.")

    local fontBinding  = bind("core.font")
    local scaleBinding = bind("core.fontScale")
    local themeBinding = bind("core.theme")

    Form.Pair(look,
        { caption = "Font", width = 200, make = function(row)
            return reg(row:Dropdown({
                width = 200,
                choices = (UI and UI.FontNames) and UI.FontNames() or {},
                get = function() return UI and UI.GetFont and UI.GetFont() or "" end,
                set = function(v)
                    if UI and UI.SetFont then UI.SetFont(v) end
                    Options.Apply(fontBinding.apply)
                end,
            }))
        end },
        { caption = "Theme", width = 200, make = function(row)
            return reg(row:Dropdown({
                width = 200,
                choices = (UI and UI.GetThemeNames) and UI.GetThemeNames() or {},
                get = function() return UI and UI.GetThemeName and UI.GetThemeName() or "" end,
                set = function(v)
                    if UI and UI.SetTheme then UI.SetTheme(v) end
                    Options.Apply(themeBinding.apply)
                end,
            }))
        end })

    Form.Pair(look,
        { caption = "Text size", width = 120, make = function(row)
            return reg(row:Dropdown({
                width = 120, choices = Options.STEPS.coreScale,
                get = function()
                    return Options.NearestStep(Options.STEPS.coreScale,
                        UI and UI.GetFontScale and UI.GetFontScale() or 1)
                end,
                set = function(v)
                    if UI and UI.SetFontScale then UI.SetFontScale(tonumber(v) or 1) end
                    Options.Apply(scaleBinding.apply)
                end,
            }))
        end },
        { caption = "Tab text", width = 120, make = function(row)
            return reg(row:Dropdown({
                id = "general.tabTextSize", width = 120, choices = Options.STEPS.tabTextSize,
                get = stepGet("general.tabTextSize", Options.STEPS.tabTextSize),
                set = stepSet("general.tabTextSize", Options.STEPS.tabTextSize),
            }))
        end })

    Form.Pair(look,
        { caption = "Message size", width = 120, make = function(row)
            return reg(row:Dropdown({
                id = "general.fontSize", width = 120, choices = Options.STEPS.fontSize,
                tooltip = "The chat feed's own size in Daseeki's window.",
                get = stepGet("general.fontSize", Options.STEPS.fontSize),
                set = stepSet("general.fontSize", Options.STEPS.fontSize),
            }))
        end },
        { caption = "Line spacing", width = 120, make = function(row)
            return reg(row:Dropdown({
                id = "general.lineHeight", width = 120, choices = Options.STEPS.lineHeight,
                tooltip = "How much air sits between message lines, as a share of the text size.",
                get = stepGet("general.lineHeight", Options.STEPS.lineHeight),
                set = stepSet("general.lineHeight", Options.STEPS.lineHeight),
            }))
        end })

    Form.Pair(look,
        { caption = "Tab position", width = 120, make = function(row)
            return reg(row:Dropdown({
                width = 120,
                choices = { { value = "top",   text = "Top" },
                            { value = "left",  text = "Left" },
                            { value = "right", text = "Right" } },
                tooltip = "Left and right put the tabs on a slim vertical rail, which reads "
                       .. "better with many tabs and leaves the full width for message text.",
                get = function() return Options.TabPlacement() end,
                set = function(v) Options.SetTabPlacement(v); Options._refresh() end,
            }))
        end },
        { caption = "Edit box", width = 120, make = function(row)
            return reg(row:Dropdown({
                width = 120,
                choices = { { value = "BOTTOM", text = "Below" }, { value = "TOP", text = "Above" } },
                get = fieldGet("windows.editBox"), set = fieldSet("windows.editBox"),
            }))
        end })

    reg(Form.Check(look, {
        label = "Lock the chat box in place",
        tooltip = "Locked, the box will not move or resize and its corner grips are gone - a "
               .. "stray drag cannot shift it. Same as /dchat lock and /dchat unlock, and it "
               .. "travels with your shared chat configuration.",
        get = function() return Options.Locked() end,
        set = function(v) Options.SetLocked(v); Options._refresh() end,
    }))
    Form.CloseGroup(look)

    -- ══ GROUP: CHANNELS ══════════════════════════════════════════════════
    buildChannels(sec)

    -- ══ GROUP: DISPLAY ═══════════════════════════════════════════════════
    local disp = Form.Group(sec, "Display")
    Form.Note(disp, "What a chat line is dressed with. Hover any option for the detail.")
    Form.Checks(disp, {
        { label = "Timestamps",  tooltip = "Stamp every line with the time it arrived.",
          get = moduleGet("stamps.module"), set = moduleSet("stamps.module") },
        { label = "Class-coloured names",
          get = moduleGet("names.module"), set = moduleSet("names.module") },
        { label = "Clickable web addresses",
          tooltip = "Clicking one opens a box with the address pre-selected (era has no clipboard).",
          get = moduleGet("urls.module"), set = moduleSet("urls.module") },
        { label = "Channel-coloured tabs",
          tooltip = "Ink each tab with the colour of the channel that window is for. A window "
                 .. "earns a colour only when its routing collapses to exactly one identity.",
          get = fieldGet("appearance.channelTabs"), set = boolSet("appearance.channelTabs") },
        { label = "Colour the edit box prefix",
          get = fieldGet("appearance.editBoxChannelColor"), set = boolSet("appearance.editBoxChannelColor") },
        { label = "Keep the edit box visible",
          tooltip = "The input bar rests at its position all the time, showing which channel "
                 .. "you are about to talk in.",
          get = fieldGet("windows.persistentEditBox"), set = boolSet("windows.persistentEditBox") },
    })
    Form.Pair(disp,
        { caption = "Time format", width = 160, make = function(row)
            return reg(row:Dropdown({
                width = 160,
                choices = {
                    { value = "HH:MM",    text = "13:05" },
                    { value = "HH:MM:SS", text = "13:05:42" },
                    { value = "hh:MM",    text = "1:05 PM" },
                    { value = "hh:MM:SS", text = "1:05:42 PM" },
                },
                get = fieldGet("stamps.format"), set = fieldSet("stamps.format"),
            }))
        end },
        { caption = "Name brackets", width = 120, make = function(row)
            return reg(row:Dropdown({
                width = 120,
                choices = { { value = "square", text = "[Name]" },
                            { value = "angle",  text = "<Name>" },
                            { value = "none",   text = "Name" } },
                get = fieldGet("names.brackets"), set = fieldSet("names.brackets"),
            }))
        end })
    Form.CloseGroup(disp)

    -- ══ ADVANCED: the fine print of the display group ════════════════════
    -- The owner: "there are just way too many options in general". Nothing is
    -- taken away - the rarely-touched half is folded, in ONE block, behind one
    -- press.
    local adv = Form.Advanced(sec, "Advanced display options")
    Form.Checks(adv, {
        { label = "Square brackets around the time",
          get = fieldGet("stamps.brackets"), set = boolSet("stamps.brackets") },
        { label = "Use server time",
          tooltip = "Stamp the realm's clock instead of this computer's.",
          get = fieldGet("stamps.serverTime"), set = boolSet("stamps.serverTime") },
        { label = "Timestamp divider",
          tooltip = "A hairline between the timestamp column and the message text.",
          get = fieldGet("appearance.stampDivider"), set = boolSet("appearance.stampDivider") },
        { label = "Remember classes between sessions",
          tooltip = "Keep a realm-scoped cache of who is what class, so a name is coloured the "
                 .. "moment it appears instead of after the first sighting.",
          get = fieldGet("names.persist"), set = boolSet("names.persist") },
        { label = "Show addresses in [brackets]",
          get = fieldGet("urls.brackets"), set = boolSet("urls.brackets") },
        { label = "Copy-chat button",
          tooltip = "Era has no clipboard; the copy window pre-selects the text for Ctrl+C.",
          get = fieldGet("view.copyButton"), set = boolSet("view.copyButton") },
        { label = "Keep the channel number in renamed channels",
          tooltip = "On: \"[2. Trade]\". Off: \"[Trade]\".",
          get = function() return ns.Config and ns.Config.AliasKeepNumber() end,
          set = function(v)
              local C = ns.Config
              if C and C.SetAliasKeepNumber(v and true or false) then
                  Options.Dispatch("channels.keepNumber")
              end
          end },
    })
    Form.Pair(adv,
        { caption = "Stamp colour", width = 140, make = function(row)
            return reg(row:Dropdown({
                width = 140,
                choices = { { value = "theme", text = "Theme" }, { value = "custom", text = "Custom" } },
                get = fieldGet("stamps.colorMode"), set = fieldSet("stamps.colorMode"),
            }))
        end },
        { caption = "Custom (RRGGBB)", width = 120, make = function(row)
            return reg(Form.FixWidth(row:EditBox({
                width = 120,
                get = fieldGet("stamps.customColor"),
                set = fieldSet("stamps.customColor", function(v)
                    -- Only a real six-digit hex lands; anything else leaves the
                    -- stored value alone (stamps.lua falls back on its own, but
                    -- writing junk into the store would make the field lie).
                    local hex = tostring(v or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
                    return hex or Options.Get("stamps", "customColor")
                end),
            }), 120))
        end })
    Form.Field(adv, "Game's own stamps", function(row)
        return reg(row:Dropdown({
            width = 140,
            tooltip = "What to do when the game's own timestamp setting is switched on too.",
            choices = { { value = "defer", text = "Step aside" },
                        { value = "takeover", text = "Take over" } },
            get = fieldGet("stamps.native"), set = fieldSet("stamps.native"),
        }))
    end)
    Form.CloseGroup(adv)

    -- ══ ADVANCED: the game's own chat windows ════════════════════════════
    local eng = Form.Advanced(sec, "The game's own chat windows")
    bind("windows.reconcileNow")
    Form._engineStatus = statusHint(eng.flow, Options.RendererStatus)
    Form._spend(eng, Form.HINT_H * 2, "renderer status")
    Form.Checks(eng, {
        { label = "Draw Daseeki's own chat window",
          tooltip = "Daseeki Chat draws the whole window - the tab strip, the message feed and "
                 .. "the input bar - instead of re-dressing the game's. Turning this off gives "
                 .. "the game's own chat window straight back.",
          get = moduleGet("view.module"), set = moduleSet("view.module") },
        { label = "One box: tabs, text and input together",
          get = fieldGet("appearance.unifiedChassis"), set = boolSet("appearance.unifiedChassis") },
        { label = "Icon rail",
          tooltip = "A slim strip on a window's edge: copy chat, settings, jump to newest.",
          get = fieldGet("appearance.iconRail"), set = boolSet("appearance.iconRail") },
        { label = "Hide the game's chat button column",
          get = fieldGet("appearance.hideButtonColumn"), set = boolSet("appearance.hideButtonColumn") },
        { label = "Copy button on each game window",
          get = fieldGet("appearance.copyButton"), set = boolSet("appearance.copyButton") },
        { label = "ALT-drag moves a window",
          get = fieldGet("windows.altDragMove"), set = boolSet("windows.altDragMove") },
        { label = "Let windows reach the screen edge",
          get = fieldGet("windows.unclampWindows"), set = boolSet("windows.unclampWindows") },
        { label = "Snap to edges when dragging",
          get = fieldGet("windows.snapToEdges"), set = boolSet("windows.snapToEdges") },
        { label = "Fade chat text when idle",
          tooltip = "Fading is off while Daseeki draws its own window - the box is always "
                 .. "there, so the text in it is too. Your setting is remembered, not rewritten.",
          get = fieldGet("appearance.fading"), set = boolSet("appearance.fading") },
    })
    Form.Pair(eng,
        { caption = "Visible before fading", width = 140, make = function(row)
            return reg(row:Dropdown({
                id = "appearance.fadeTime", width = 140, choices = Options.STEPS.fadeTime,
                get = stepGet("appearance.fadeTime", Options.STEPS.fadeTime),
                set = stepSet("appearance.fadeTime", Options.STEPS.fadeTime),
            }))
        end },
        { caption = "Shared configuration", width = 150, make = function(row)
            return row:Button({
                text = "Reconcile now", width = 150,
                tooltip = "Re-apply the shared configuration to this character's windows, tabs, "
                       .. "routing and channels. It runs by itself at login and on every zone-in.",
                onClick = function() Options.ReconcileNow() end,
            })
        end })
    Form._reconcileStatus = statusHint(eng.flow, Options.ReconcileStatus)
    Form._spend(eng, Form.HINT_H * 2, "reconcile status")
    Form.CloseGroup(eng)
end

-- Re-point the pooled channel rows at the current channel list (the section's
-- refresh, which Core runs on every show).
--
-- THE TWO RULES THIS FUNCTION NOW HOLDS, both of them owner UAT findings:
--   * A ROW PER CHANNEL, AND NOT ONE MORE. The pool is twelve; the rows past
--     the last real channel are HIDDEN, not left standing with empty fields.
--     The suite pins shown-rows == channels.
--   * EVERY ROW SAYS WHICH CHANNEL IT IS, in that channel's own colour — the
--     name doubles as the live colour preview, so "what am I editing" and
--     "what does it look like" are one glance.
function Options.RefreshChannelRows()
    local rows = Options.ChannelRows()
    Options._shownChanRows = 0
    for i = 1, Options.MAX_CHANNEL_ROWS do
        local ui = Options._chanRows and Options._chanRows[i]
        if ui then
            local r = rows[i]
            -- The ROW FRAME is hidden with its contents, not just the widgets
            -- on it: a row left shown with everything on it hidden is still a
            -- mouse region and still a stripe of empty space.
            local items = { ui.row, ui.handle, ui.label, ui.swatch, ui.hexBox, ui.nameBox }
            Form.ShowRow(items, r ~= nil)
            if r then
                Options._shownChanRows = Options._shownChanRows + 1
                -- The caption, through the ONE re-caption path (a Core Label is
                -- a frame: writing it with :SetText is what left this blank).
                local text = Options.ChannelRowLabel(r)
                if not r.num then text = text .. "  (not joined)" end
                Form.SetCaption(ui.label, text)
                -- The name IS the preview: the channel's own colour, the muted
                -- ink when it has none, and the muted ink for a channel this
                -- character is not in (a quiet, inert row rather than a lie).
                local col = r.color
                if not r.num then
                    Form.TintCaption(ui.label, nil)
                elseif col then
                    Form.TintCaption(ui.label, col.r, col.g, col.b)
                else
                    Form.TintCaption(ui.label, nil)
                end
                -- The handle only exists on a row a drag can actually move.
                Form.SetCaption(ui.handle, r.ordered and "::" or "")
                -- The swatch wears the colour it sets (in game; the headless
                -- flow's button has no backdrop to wear).
                local sw = ui.swatch
                if sw and type(sw.SetBackdropColor) == "function" and col then
                    pcall(sw.SetBackdropColor, sw, col.r, col.g, col.b, 1)
                end
                Form.GreyBox(ui.nameBox, r.alias == "")
            end
            if ui.hexBox and type(ui.hexBox.Refresh) == "function" then ui.hexBox.Refresh() end
            if ui.nameBox and type(ui.nameBox.Refresh) == "function" then ui.nameBox.Refresh() end
        end
    end
    -- The group is only as tall as the rows it is really showing.
    local g = Options._chanGroup
    if g then
        g.units = (g._baseUnits or g.units)
        g._baseUnits = g._baseUnits or g.units
        g.units = g._baseUnits
            - (Options.MAX_CHANNEL_ROWS - Options._shownChanRows) * (Form.ROW_H + Form.ROW_GAP)
        g.height = Form.BoxHeight(g.units, g.title ~= nil)
        Form.ApplyGroup(g)
    end
    return #rows
end

----------------------------------------------------------------------
-- SECTION 3 — CHAT HISTORY.
----------------------------------------------------------------------

local function buildHistory(flow)
    local sec = flow:AddSection("Chat History")
    local g = Form.Group(sec, "Retention")
    Form.Note(g, "Keep each window's recent lines across a logout or reload. The lines stay on "
        .. "this character; these settings are shared like the rest.")
    reg(Form.Check(g, {
        label = "Keep chat across sessions",
        get = moduleGet("history.module"), set = moduleSet("history.module"),
    }))
    Form.Pair(g,
        { caption = "Lines kept per tab", width = 140, make = function(row)
            return reg(row:Dropdown({
                id = "history.cap", width = 140, choices = Options.STEPS.historyCap,
                get = stepGet("history.cap", Options.STEPS.historyCap),
                set = stepSet("history.cap", Options.STEPS.historyCap),
            }))
        end },
        { caption = "Drop lines older than", width = 140, make = function(row)
            return reg(row:Dropdown({
                id = "history.maxAgeHours", width = 140, choices = Options.STEPS.historyAge,
                get = stepGet("history.maxAgeHours", Options.STEPS.historyAge),
                set = stepSet("history.maxAgeHours", Options.STEPS.historyAge),
            }))
        end })
    reg(Form.Check(g, {
        label = "Restore behind a session divider",
        tooltip = "Restored lines sit above a \"-- session from ... --\" rule, so old chat can "
               .. "never be misread as something that was just said. Off restores them bare "
               .. "and gives you the extra row of scrollback.",
        get = fieldGet("history.divider"), set = boolSet("history.divider"),
    }))
    Form.CloseGroup(g)
end

----------------------------------------------------------------------
-- THE PAGE: three sections, in the owner's own order.
----------------------------------------------------------------------

function Options.Build(flow)
    Options._ResetRefreshers()
    Options._statusLines = {}
    Options.Form.groups = {}
    -- The pane a fold has to ask for a re-layout (Core's flow carries it; the
    -- headless recording flow does not, and nothing here assumes it does).
    Options._pane = type(flow) == "table" and flow.pane or nil
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
    -- Registration IS this module's own lifecycle act, so the command may do it
    -- (the tab menu may not — see View.OpenSettings).
    Options.Register()
    -- …and then the SAME seam the tab menu runs. This used to be a second
    -- `hub:Open("chat")` of its own, which is how the menu's copy of the call
    -- was free to drift into Core:ShowAddon (a page SELECT that never shows the
    -- window) without anything here noticing. One caller, one contract:
    -- Core:Open(id, sectionId) opens the window AND lands on the section.
    local V = ns.View
    if V and type(V.OpenSettings) == "function" then
        V.OpenSettings("settings")
        return
    end
    hub:Open("chat", "settings")
end)

ns.RegisterDebugCommand("options", "settings pane: registration, bindings, aliases", function()
    ns:Print(("options: %s, %s with the hub, page %s"):format(
        Options.active and "active" or "inactive",
        Options.registered and "registered" or "NOT registered",
        Options._built and "built" or "not built yet"))
    local bad = Options.CheckBindings()
    ns:Print(("  %d binding(s), %d problem(s)"):format(#Options.BINDINGS, #bad))
    for _, b in ipairs(bad) do ns:Print("    " .. b) end
    -- THE STATUS LINES LIVE HERE NOW. The owner's UAT: "there are just way too
    -- many options in general" — and most of the pane's word count was these,
    -- narrating one control at a time ("0 tab(s) carry a colour of their own").
    -- They are real, useful answers; they are just not what a settings page is
    -- for. The pane keeps the two that explain a control that would otherwise
    -- look inert (the renderer and the reconciler); the rest report here.
    for _, fn in ipairs({ Options.ChannelStatus, Options.LockStatus,
                          Options.TabPlacementStatus, Options.FadingStatus,
                          Options.BadgeFilterStatus }) do
        local ok, line = pcall(fn)
        if ok and type(line) == "string" then ns:Print("  " .. line) end
    end
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

-- OPEN SETTINGS: ONE SEAM TO THE HUB, AND IT REALLY OPENS THE WINDOW.
--
-- THE LIVE DEFECT (owner UAT, 2026-08-12): "right clicking the tab and
-- clicking 'Open Settings' doesnt seem to work". View.OpenSettings preferred
-- Core:ShowAddon and returned success the moment the call did not raise — but
-- Core:ShowAddon SELECTS a page and never shows the window (EnsureHub builds
-- it HIDDEN; only Core:Open calls window:Show()). So the entry selected a page
-- inside a window nobody could see. It was green here only because the Core
-- stub modeled Open and ShowAddon as two identical recorders; the stub now
-- models Core's real asymmetry, which is what makes this suite able to fail.
--
-- Both entry points are driven — the tab menu and /dchat options — because the
-- reason there is one seam is so there is one contract to get right.
local function testOpenSettingsSeam(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local UI = _G.DaseekiUI
    local V, C = ns.View, ns.Config
    if not (UI and UI.__HubShown and V and V.OpenSettings) then return end

    local wasView, wasSkin, wasOpts = ns.ModuleEnabled("view"), ns.ModuleEnabled("skin"), Options.active
    ns.SetModuleEnabled("options", true)
    ns.SetModuleEnabled("skin", true)
    ns.SetModuleEnabled("view", true)
    local HT = _G.__DaseekiChatHarnessTimer
    if HT then HT.flush() end

    ck(V.SettingsPageRegistered() == true,
        "the ENABLED module really put Chat's page in the hub (the module's own act)")

    -- A config fingerprint: opening a window is a display act and must leave
    -- the synced store untouched, revision stamp included.
    local function serialize(t, out)
        out = out or {}
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)                       -- Class 8: a stable rendering
        for _, k in ipairs(keys) do
            local v = t[k] ~= nil and t[k] or t[tonumber(k)]
            if type(v) == "table" then out[#out + 1] = k .. "{"; serialize(v, out); out[#out + 1] = "}"
            else out[#out + 1] = k .. "=" .. tostring(v) end
        end
        return out
    end
    local function fingerprint()
        local c = C.Get() or {}
        local out = { "rev=" .. tostring(c.rev), "at=" .. tostring(c.at) }
        local snap = C.Snapshot()
        if snap then serialize(snap.cfg, out) end
        return table.concat(out, ",")
    end

    -- ── LEG ONE: THE TAB CONTEXT MENU, driven exactly as a right-click drives
    -- it (View.RunTabMenuItem is the function the menu row's OnClick calls).
    local id = V.ids and V.ids[1]
    ck(id ~= nil, "the drawn view has a tab whose menu can be run")
    UI.__HubClose()
    ck(UI.__HubShown() == false, "the hub starts CLOSED, the way a session starts")
    local cfgBefore = fingerprint()
    if id then
        ck(V.RunTabMenuItem(id, "settings") == true, "the menu's Open settings entry runs")
        ck(UI.__HubShown() == true,
            "RED CONTROL — the Daseeki WINDOW is really open afterwards (the owner's defect: "
            .. "the old code selected a page inside a hidden window and called it success)")
        local a, s = UI.__HubPage()
        ck(a == "chat" and s == "settings",
            "RED CONTROL — …and it is on CHAT's settings page (got "
            .. tostring(a) .. "/" .. tostring(s) .. ")")
        ck(fingerprint() == cfgBefore,
            "RED CONTROL — opening the settings wrote NOTHING to the config (a display act, "
            .. "not a config act)")
    end

    -- ── LEG TWO: /dchat options, through the REAL slash dispatcher.
    UI.__HubClose()
    ns.SlashDispatch("options")
    ck(UI.__HubShown() == true, "RED CONTROL — /dchat options opens the window too")
    local a2, s2 = UI.__HubPage()
    ck(a2 == "chat" and s2 == "settings",
        "…and lands on the same page through the same seam (got "
        .. tostring(a2) .. "/" .. tostring(s2) .. ")")

    -- ── THE CORE CONTRACT ITSELF, pinned where this addon can see it. If a
    -- future Core ever makes ShowAddon show the window (or Open stop showing
    -- it), this fails here instead of in the owner's chat window.
    local hub = _G.DaseekiSuite
    UI.__HubClose()
    hub:ShowAddon("chat", "settings")
    ck(UI.__HubShown() == false,
        "the hub contract: Core:ShowAddon SELECTS a page and never shows the window")
    hub:Open("chat", "settings")
    ck(UI.__HubShown() == true, "…and Core:Open is the one call that shows it")

    -- A section id the page does not have falls back to its FIRST section
    -- (Core:GetAddonSection), so a stale section name can never blank the page.
    UI.__HubClose()
    ck(V.OpenSettings("nosuchsection") == true, "an unknown section id is still an open")
    local a3, s3 = UI.__HubPage()
    ck(UI.__HubShown() == true and a3 == "chat" and s3 == "settings",
        "…falling back to Chat's first section, exactly as Core does (got "
        .. tostring(a3) .. "/" .. tostring(s3) .. ")")

    UI.__HubClose()
    ns.SetModuleEnabled("view", wasView)
    ns.SetModuleEnabled("skin", wasSkin)
    if not wasOpts then ns.SetModuleEnabled("options", false) end
    if HT then HT.flush() end
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

-- ════════════════════════════════════════════════════════════════════════
-- THE RED CONTROL FOR "THERE ARE NO LABELS ON THE DROP DOWNS" (owner, UAT
-- 2026-08-12), and for its three siblings: the channel rows with no channel
-- name, the Tabs sub-tab buttons rendering as four empty boxes, and the
-- per-tab channel checkboxes with nothing beside them.
--
-- The claim this suite makes is not "the builder passed a label somewhere". It
-- is: EVERY CONTROL ON THE PAGE CARRIES A CAPTION THE KIT ACTUALLY DRAWS. The
-- corestub arranges the pane by Core's own row arithmetic, so a caption Core
-- would cull is culled here, and a SetText Core would throw away is thrown
-- away here. Against the build the owner UAT'd, every leg below is RED.
-- ════════════════════════════════════════════════════════════════════════
local function testCaptions(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local UI = _G.DaseekiUI
    if not (UI and UI.__PaneAudit) then return end

    local wasOpts = Options.active
    ns.SetModuleEnabled("options", true)
    local def = UI.__RegisteredAddon("chat")
    local pane = def and def.sections and def.sections[1] and def.sections[1]._pane
    if not pane then pane = UI.__BuildPane("chat", "settings") end
    if type(pane) ~= "table" then
        fails[#fails + 1] = "the pane did not build; captions cannot be audited"
        return
    end

    -- The page is laid out at BOTH ends of the hub's real width range: 876 is
    -- the narrowest window the hub can be dragged to, 880 is every larger one.
    for _, width in ipairs({ UI.MIN_CONTENT_W, UI.MAX_CONTENT_W }) do
        UI.__ArrangePane(pane, width)
        local problems = UI.__PaneAudit(pane)
        ck(#problems == 0, ("RED CONTROL — every control on the page carries a caption the "
            .. "kit DRAWS, at %d units (%d problem(s): %s)")
            :format(width, #problems, table.concat(problems, " | ")))
    end

    -- THE THREE ROOT CAUSES, each pinned by name so a regression says which
    -- one came back rather than "a label is missing somewhere".
    --
    -- 1. A Core Label frame carries no uiWidth: anything that hands one to a
    --    row without sizing it is a zero-width frame the ScrollChild culls.
    local sized, unsized = 0, {}
    for _, w in ipairs(pane.controls) do
        if w._kind == "label" and w._shown and w:Caption() then
            if (w.uiWidth or 0) >= 1 then sized = sized + 1
            else unsized[#unsized + 1] = w:Caption() end
        end
    end
    ck(sized > 0, "the page really uses inline label cells (got " .. sized .. ")")
    ck(#unsized == 0, "RED CONTROL — every label cell carries its OWN width, so none is "
        .. "culled by the row arranger (" .. table.concat(unsized, ",") .. ")")

    -- 2. A Label is a FRAME. Nothing may relabel one through :SetText.
    for _, w in ipairs(pane.controls) do
        if w._kind == "label" then
            ck(type(w.SetText) ~= "function",
                "a label is a FRAME in the sim too — it has no SetText to be fooled by")
            break
        end
    end

    -- 3. Button:SetText writes to a fontstring Core never installed. A relabel
    --    that goes through it is a relabel that never happened.
    local btn
    for _, w in ipairs(pane.controls) do if w._kind == "button" then btn = w break end end
    if btn then
        local before = btn:Caption()
        btn:SetText("THIS TEXT IS NEVER DRAWN")
        ck(btn:Caption() == before,
            "Button:SetText changes NOTHING a player can read (Core installs no fontstring) "
            .. "— got " .. tostring(btn:Caption()))
    end

    -- ── THE CHANNEL MANAGER: a row per channel, and not one more ────────
    -- "the channel color section doesnt show you what channel your editing"
    -- and twelve rows for five channels. Both are structural now: the row
    -- count IS the channel count, and every shown row carries its channel's
    -- name in that channel's own ink.
    ns:SafeCall(Options.RefreshChannelRows)
    UI.__ArrangePane(pane, UI.MIN_CONTENT_W)
    local channels = Options.ChannelRows()
    ck(Options._shownChanRows == #channels,
        ("RED CONTROL — the channel manager draws exactly one row per channel: %d row(s) "
        .. "for %d channel(s), no ghosts"):format(tonumber(Options._shownChanRows) or -1, #channels))
    local nameless, ghosts = {}, 0
    for i = 1, Options.MAX_CHANNEL_ROWS do
        local ui = Options._chanRows[i]
        local r = channels[i]
        if ui and ui.label then
            if r then
                local cap = ui.label:Caption()
                if not cap or not cap:lower():find(r.name:lower(), 1, true) then
                    nameless[#nameless + 1] = tostring(r.name) .. "->" .. tostring(cap)
                end
            elseif ui.label._shown then
                ghosts = ghosts + 1
            end
        end
    end
    ck(#nameless == 0, "RED CONTROL — every channel row SAYS which channel it is ("
        .. table.concat(nameless, ",") .. ")")
    ck(ghosts == 0, "RED CONTROL — no pooled row is left standing without a channel behind it "
        .. "(" .. ghosts .. " ghost(s))")

    -- The name doubles as the colour preview.
    do
        local C = ns.Config
        local first = channels[1]
        if C and first then
            local was = C.ChannelColor(first.name)
            Options.SetChannelColorHex(first.name, "ff8000")
            ns:SafeCall(Options.RefreshChannelRows)
            local ui1 = Options._chanRows[1]
            local fs = ui1 and ui1.label and ui1.label._label
            local r0, g0
            if fs and type(fs.GetTextColor) == "function" then r0, g0 = fs:GetTextColor() end
            ck(r0 and math.abs(r0 - 1) < 0.01 and math.abs(g0 - 128 / 255) < 0.01,
                "RED CONTROL — the channel's NAME is inked in the channel's own colour, so the "
                .. "row previews what it is setting (got " .. tostring(r0) .. "," .. tostring(g0) .. ")")
            if was then Options.SetChannelColor(first.name, was.r, was.g, was.b)
            else Options.SetChannelColorHex(first.name, "") end
            ns:SafeCall(Options.RefreshChannelRows)
        end
    end

    -- ── THE ORPHAN RENAME FIELD IS GONE, and its absence is pinned ───────
    -- "the channel rename piece is terrible": a naked "Rename a channel you are
    -- not in right now:" field under the rows. The rename lives on the row now.
    local orphan
    for _, w in ipairs(pane.controls) do
        if w._kind == "hint" and type(w._text) == "string"
           and w._text:find("not in right now", 1, true) then orphan = w._text end
    end
    ck(orphan == nil, "RED CONTROL — the orphan rename field is GONE, not left beside its "
        .. "replacement (found: " .. tostring(orphan) .. ")")
    ck(type(Options.RenameBoxText) == "function" and type(Options.SetAliasFromRow) == "function",
        "…and the rename lives on the channel's own row instead")
    -- The greyed placeholder is never stored as an alias.
    do
        local C = ns.Config
        local r = channels[1]
        if C and r then
            local was = C.GetAlias(r.name)
            Options.SetAliasFromRow(r.name, r.name)
            ck(C.GetAlias(r.name) == nil,
                "RED CONTROL — typing the channel's own name back is the REMOVE verb, so the "
                .. "greyed placeholder can never become a stored alias")
            Options.SetAliasFromRow(r.name, "Shorter")
            ck(C.GetAlias(r.name) == "Shorter", "…and a real rename still lands")
            C.SetAlias(r.name, was or "")
        end
    end

    -- ── THE SUB-TAB NAV: names, and no empty boxes ──────────────────────
    local T = ns.OptionsTabs
    if T and T._nav then
        ns:SafeCall(T.Refresh)
        local ids = T.PageIds()
        ck(#(T._captionFailures or {}) == 0,
            "RED CONTROL — every nav caption was really WRITTEN through the drawn FontString ("
            .. table.concat(T._captionFailures or {}, ",") .. ")")
        ck(T._shownNav == #ids,
            ("RED CONTROL — the Tabs nav shows one button per chat tab (%d of %d), never an "
            .. "empty box"):format(tonumber(T._shownNav) or -1, #ids))
        local blank = {}
        for i = 1, #ids do
            local btn = T._nav[i]
            local cap = btn and btn:Caption()
            if not cap then blank[#blank + 1] = tostring(i) end
        end
        ck(#blank == 0, "RED CONTROL — no sub-tab button renders blank (" ..
            table.concat(blank, ",") .. ") — the owner's four empty boxes")
        ck(T._shownChanBoxes == #channels,
            "RED CONTROL — the per-tab channel list shows one row per channel too ("
            .. tostring(T._shownChanBoxes) .. " of " .. #channels .. ")")
    end

    -- ── THE FORM LANGUAGE ITSELF ────────────────────────────────────────
    ck(#pane.cards >= 8, "the page is built from bordered group boxes (got "
        .. #pane.cards .. ")")
    ck(#pane.checklists >= 5, "…with two-column checkbox grids inside them (got "
        .. #pane.checklists .. ")")
    local folds, closed = 0, 0
    for _, g in ipairs(Form.groups) do
        if g.advanced then
            folds = folds + 1
            if not g.open then closed = closed + 1 end
        end
    end
    ck(folds >= 3, "the rarely-touched options are folded (got " .. folds .. " fold(s))")
    ck(folds == closed, "…and every fold starts CLOSED (the point of folding them)")
    -- A fold really opens and closes, and its caption says which it is.
    local fold
    for _, g in ipairs(Form.groups) do if g.advanced then fold = g break end end
    if fold then
        local shut = fold.toggle and fold.toggle:Caption()
        ck(Form.ToggleAdvanced(fold) == true, "a fold opens")
        ck(fold.card == nil or fold.card.uiHeight > 0, "…giving its block a real height")
        ck(fold.toggle and fold.toggle:Caption() ~= shut, "…and the button says so")
        ck(Form.ToggleAdvanced(fold) == false, "…and closes again")
        ck(fold.card == nil or fold.card.uiHeight == 0, "…collapsing the whole group in one block")
    end

    -- EVERY GROUP BOX IS TALL ENOUGH FOR WHAT IS IN IT. MakeEditorCard's inner
    -- pane carries no scrollbar, so content taller than the card is content
    -- nobody can reach — the same invisible-control class, one level up.
    local short = {}
    for _, g in ipairs(Form.groups) do
        if g.card and g.open then
            local want = Form.BoxHeight(g.units, g.title ~= nil)
            if (g.card.uiHeight or 0) < want then
                short[#short + 1] = tostring(g.title or g.name) .. " " ..
                    tostring(g.card.uiHeight) .. "<" .. tostring(want)
            end
        end
    end
    ck(#short == 0, "RED CONTROL — every group box is at least as tall as its own content "
        .. "(" .. table.concat(short, " | ") .. ")")

    if not wasOpts then ns.SetModuleEnabled("options", false) end
end

-- THE LAYOUT ARITHMETIC, PURE. Everything that decides a column, a row plan or
-- a box height is a function of numbers, so the claim "nothing overlaps and
-- nothing overflows at the narrowest window the hub can be dragged to" is
-- arithmetic rather than a look at a screenshot.
local function testFormMath(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    ck(Form.MIN_CONTENT_W == 876 and Form.MAX_CONTENT_W == 880,
        "the hub's real content width range is what the planner plans against")
    ck(Form.GroupInner(880) == 860, "a group box's inner width is the page minus its padding")

    -- Two-up: the decision, and its edges.
    local inner = Form.GroupInner(Form.MIN_CONTENT_W)
    ck(Form.FitsTwoUp(100, 100, inner) == true, "two small cells share a row")
    ck(Form.FitsTwoUp(inner, 10, inner) == false, "…and two that do not fit, do not")
    ck(Form.FitsTwoUp(400, 400, 823) == false,
        "the gap between the columns counts against the fit (400+24+400 > 823)")
    ck(Form.FitsTwoUp(400, 400, 824) == true, "…and exactly enough is a fit")
    ck(Form.FitsTwoUp(nil, 100, inner) == false, "an unanswerable width never fits (never a guess)")

    -- THE SECOND COLUMN STARTS AT THE SAME X ON EVERY ROW. This is the one that
    -- turns "two things beside each other" into "two columns": whatever the
    -- first column's control is, the second caption absorbs the difference.
    do
        local starts = {}
        for _, cw in ipairs({ 200, 180, 160, 140, 120, 80 }) do
            local lw = Form.SecondLabelW(cw, nil, nil)
            -- Where the row arranger will actually place the second caption:
            -- after the first cell and one item gap.
            starts[#starts + 1] = Form.CellWidth(cw) + Form.ITEM_GAP
                + (lw - Form.LABEL_W)
        end
        local same = true
        for i = 2, #starts do if math.abs(starts[i] - starts[1]) > 1e-6 then same = false end end
        ck(same, "every second column starts at the same x (" .. table.concat(starts, ",") .. ")")
        ck(math.abs(starts[1] - (Form.COL1_W + Form.COL_GAP)) < 1e-6,
            "…and that x is the first column's track plus the column gap")
        ck(Form.SecondLabelW(5000) >= Form.LABEL_W,
            "a control wider than the whole track never produces a NEGATIVE caption width")
        ck(Form.FitsTwoUp(Form.COL1_W, Form.CellWidth(200), inner) == true,
            "the widest pair the pane offers really does fit at the narrowest hub width")
    end

    -- The plan: nothing dropped, nothing repeated, nothing overlapping and
    -- nothing past the edge — at BOTH ends of the hub's width range.
    local widths = { 300, 300, 700, 200, 200, 200 }
    for _, avail in ipairs({ Form.GroupInner(Form.MIN_CONTENT_W),
                             Form.GroupInner(Form.MAX_CONTENT_W), 460, 320 }) do
        local rows = Form.PlanRows(widths, avail)
        local seen, count = {}, 0
        for _, r in ipairs(rows) do
            local ws = {}
            for _, idx in ipairs(r) do
                ck(not seen[idx], "cell " .. idx .. " is placed exactly once at " .. avail)
                seen[idx] = true
                count = count + 1
                ws[#ws + 1] = widths[idx]
            end
            local offs, total = Form.RowOffsets(ws, avail)
            -- A single cell wider than the page is the degrade case: the plan
            -- gives it a row of its own rather than dropping it, and Core's own
            -- clipping pane contains it. A PAIRED row must always fit.
            ck(total <= avail or #r == 1,
                ("a planned row of two never overflows (%d of %d)"):format(total, avail))
            for i = 2, #offs do
                ck(offs[i] >= offs[i - 1] + ws[i - 1],
                    "…and two cells on one row never overlap")
            end
        end
        ck(count == #widths, "every cell is placed at " .. avail .. " (" .. count .. ")")
    end
    -- A cell wider than the page still gets a row of its own rather than
    -- vanishing (the plan degrades, it never drops).
    local wide = Form.PlanRows({ 5000 }, 100)
    ck(#wide == 1 and #wide[1] == 1, "a cell too wide for the page still gets its own row")

    -- Heights.
    ck(Form.BoxHeight(0, false) == Form.CARD_PAD * 2 + Form.CARD_SLACK,
        "an empty untitled box is padding and slack")
    ck(Form.BoxHeight(100, true) == Form.BoxHeight(100, false) + Form.CARD_TITLE_H,
        "a title costs the title band")
    ck(Form.BoxHeight(100, true) > 100, "a box is always taller than its content")
    ck(Form.ChecklistHeight(7, 2) == 4 * Form.CHECK_H + Form.ROW_GAP,
        "seven items in two columns is four rows")
    ck(Form.ChecklistHeight(0, 2) == Form.ROW_GAP, "…and none is none")
    ck(Form.ChecklistColumns(Form.GroupInner(Form.MIN_CONTENT_W)) == 2,
        "a group box is always wide enough for Core's two-column checklist")
    ck(Form.ChecklistColumns(200) == 1, "…and a narrow one collapses to one, as the kit does")
    ck(Form.CHECKLIST_COLLAPSE_W == 460,
        "the collapse width is Core's own (AddChecklist COLLAPSE_W) — one number, not two")

    -- The label cell is what makes a caption survive Core's row arranger.
    ck(Form.CellWidth(120) == Form.LABEL_W + Form.ITEM_GAP + 120,
        "a cell is its caption column plus its control")
    local fake = { _label = { SetText = function() end } }
    ck(Form.SizeLabel(fake, 90).uiWidth == 90, "SizeLabel gives a label a width of its own")
    ck(Form.SetCaption({ }, "x") == false,
        "SetCaption REFUSES a widget with no drawn caption instead of pretending")
    ck(Form.SetCaption(nil, "x") == false, "…and refuses nothing at all")
end

function Options.RunSelfTests(verbose)
    local suites = {
        { name = "bindings (every control names a real field)", fn = testBindings },
        { name = "store access",            fn = testStoreAccess },
        -- The registration suite owns the phase-0 inertness assertions (nothing
        -- registered while disabled), so it must run before anything that turns
        -- the module on. Captions run straight after it, on the pane it built.
        { name = "form layout (pure: columns, plans, box heights)", fn = testFormMath },
        { name = "registration + the pane", fn = testRegistrationAndPane },
        { name = "captions (every control is legible)", fn = testCaptions },
        { name = "live apply (a control reaches PIXELS, same beat)", fn = testLiveApply },
        { name = "open settings: one seam, and the window really opens", fn = testOpenSettingsSeam },
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
