-- Daseeki Chat — options_tabs.lua  (the options rework's TABS section)
--
-- WHY THIS FILE EXISTS (file map amendment, 2026-08-11): the rework's Tabs
-- section is a pane of its own — one SUB-TAB PER CHAT TAB, with a name, a
-- colour, a message-group tree, channel routing and per-tab notifications
-- behind each one, plus + Add Tab, tab removal, the Combat Log toggle and the
-- addon tab. Carrying it inside options.lua would have taken that file past
-- 3,500 lines and buried the General section it already owns. The cut is the
-- natural one the brief named: options_tabs.lua, immediately after options.lua
-- (it consumes options.lua's binding index and its wiring helpers, so it must
-- load second). `Daseeki-Chat.toc` and the harness's EXPECTED_FILE_MAP gate
-- were amended in the SAME COMMIT, with the design doc — the map stays LAW.
--
-- THE RULE THIS SECTION IS BUILT ON: CONFIG-FIRST, ALWAYS. Nothing here
-- creates, destroys, shows or hides a client chat window. Every control writes
-- the SYNCED config through config.lua's own seam, dispatches the apply route
-- its binding declares, and the reconciler converges this character's client
-- store to what the config now says — the identical path a brand-new character
-- takes at login, which is why an added tab appears on every character without
-- anybody visiting this pane again.
--
-- Bindings are registered through Options.AddBindings so the id index stays in
-- step; controls are built through Options' own published helpers, so the
-- bind-check, the coverage gate and the "every binding is really used" pin
-- cover this file exactly as they cover options.lua.

local ADDON, ns = ...

local Options = ns.Options
if type(Options) ~= "table" then return end        -- options.lua is the owner

local Tabs = {}
ns.OptionsTabs = Tabs

local bind      = Options._bind
local reg       = Options._reg
local fieldGet  = Options._fieldGet
local moduleGet, moduleSet = Options._moduleGet, Options._moduleSet
local statusHint = Options._statusHint

local MAX_CHANNEL_ROUTES = 12        -- pooled per-tab channel checkboxes

-- NO NEW BINDING TABLE HERE ON PURPOSE. Every control this file builds names
-- an id options.lua already declares (Options.AddBindings exists for a section
-- that genuinely owns new ones, and this one does not) — so the bind-check, the
-- "every binding is really used" pin and the coverage gate see one table, and a
-- typo in an id here is recorded in Options._badIds exactly as it would be
-- there.

----------------------------------------------------------------------
-- THE MESSAGE-GROUP TREE.
--
-- The client's own chat-group model (the capability reference the owner named:
-- the game's per-window "Messages" panel). Grouped the way the client groups
-- them so a page reads as a tree rather than as forty checkboxes, and kept to
-- the groups that exist on era — a control for a group the client never emits
-- would be a control that does nothing, forever.
----------------------------------------------------------------------

-- THE CATEGORIES ARE THE CLIENT'S OWN (owner UAT, 2026-08-12: "'which messages
-- come here' should be formatted like the previous screenshots i sent you" —
-- the game's per-window Messages panel, which is five titled boxes, not one
-- forty-item column). Same tokens, same coverage; regrouped and re-titled to
-- the reference, and rendered as five bordered boxes with two columns of
-- checkboxes inside each (Form.Group + Form.Checks).
Tabs.GROUP_TREE = {
    { title = "Player Messages", groups = {
        { "SAY", "Say" }, { "EMOTE", "Emote" }, { "YELL", "Yell" },
        { "WHISPER", "Whisper" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" },
        { "PARTY", "Party" }, { "PARTY_LEADER", "Party leader" },
        { "RAID", "Raid" }, { "RAID_LEADER", "Raid leader" },
        { "RAID_WARNING", "Raid warning" },
    } },
    { title = "Combat", groups = {
        { "COMBAT_XP_GAIN", "Experience" }, { "COMBAT_FACTION_CHANGE", "Reputation" },
        { "COMBAT_MISC_INFO", "Other combat" }, { "SKILL", "Skill ups" },
        { "LOOT", "Loot" }, { "MONEY", "Money" }, { "TRADESKILLS", "Trade skills" },
    } },
    { title = "PvP", groups = {
        { "BATTLEGROUND", "Battleground" },
        { "BATTLEGROUND_LEADER", "Battleground leader" },
        { "COMBAT_HONOR_GAIN", "Honour" },
    } },
    { title = "Creature Messages", groups = {
        { "MONSTER_SAY", "Creature say" }, { "MONSTER_YELL", "Creature yell" },
        { "MONSTER_EMOTE", "Creature emote" }, { "MONSTER_WHISPER", "Creature whisper" },
    } },
    { title = "Other", groups = {
        { "SYSTEM", "System" }, { "ERRORS", "Errors" }, { "IGNORED", "Ignored" },
        { "AFK", "Away" }, { "DND", "Busy" }, { "TARGETICONS", "Target markers" },
    } },
}

-- Every group the tree offers, flat and sorted (Class 8: a listing anything
-- iterates is deterministic).
function Tabs.AllGroups()
    local out = {}
    for _, branch in ipairs(Tabs.GROUP_TREE) do
        for _, g in ipairs(branch.groups) do out[#out + 1] = g[1] end
    end
    table.sort(out)
    return out
end

----------------------------------------------------------------------
-- THE TAB COLOUR PALETTE. Two families, both live in-game: a Core theme token
-- follows the theme, a chat type follows the player's own chat colours.
-- skin.lua owns what a spec MEANS; this is the curated menu of them.
--
-- GROUP AND CHANNEL COLOURS ARE DELIBERATELY NOT HERE (the design's own rule):
-- they live with the group and the channel, in General, because they are
-- global facts. What a TAB carries is its own ink.
----------------------------------------------------------------------

Tabs.COLOR_CHOICES = {
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

----------------------------------------------------------------------
-- THE PER-TAB OPT-OUTS (account-local, per window).
--
-- The four do NOT share a polarity (badges/history store `true` for OFF;
-- stamps stores `false` for OFF, absent for ON), so the shape below names each
-- module's own table AND its own polarity rather than inventing a fifth
-- convention this file would then have to keep in step. Nothing here is a
-- second copy of a module's rule: it is a pointer at it.
----------------------------------------------------------------------

Tabs.TOGGLES = {
    { key = "badges",  binding = "tabs.badge",   branch = "badges",  store = "optOut",
      offValue = true,  onValue = nil, label = "Count unread lines",
      tooltip = "Show a quiet unread counter on this tab." },
    { key = "accent",  binding = "tabs.accent",  branch = "badges",  store = "accentOptOut",
      offValue = true,  onValue = nil, label = "Whisper accent",
      tooltip = "A pile containing a whisper wears the accent colour instead of the muted one." },
    { key = "stamps",  binding = "tabs.stamp",   branch = "stamps",  store = "windows",
      offValue = false, onValue = nil, label = "Timestamps",
      tooltip = "Timestamp the lines in this tab." },
    { key = "history", binding = "tabs.history", branch = "history", store = "optOut",
      offValue = true,  onValue = nil, label = "Keep across sessions",
      tooltip = "Keep this tab's lines across a logout or reload." },
}

function Tabs.ToggleGet(spec, id)
    local t = Options.Branch(spec.branch)
    local tbl = (type(t) == "table") and t[spec.store] or nil
    if type(tbl) ~= "table" then return true end
    return tbl[id] ~= spec.offValue          -- absent (and anything else) is ON
end

function Tabs.ToggleSet(spec, id, on)
    local t = Options.Branch(spec.branch)
    if type(t) ~= "table" then return false end
    if type(t[spec.store]) ~= "table" then t[spec.store] = {} end
    -- Written out rather than `on and X or Y`: the ON value is nil, which that
    -- idiom silently turns into the OFF value (Class 5, the plain way).
    if on then t[spec.store][id] = spec.onValue else t[spec.store][id] = spec.offValue end
    Options.Dispatch(spec.binding)
    return true
end

----------------------------------------------------------------------
-- THE SUB-TAB SET. One page per chat tab, and the pages come from the CONFIG's
-- tab set (not the client's), because the config is the authority and a tab
-- the config declares must be editable on a character that has not converged
-- to it yet.
----------------------------------------------------------------------

Tabs.MAX_PAGES = 10

function Tabs.PageIds()
    local C = ns.Config
    local ids = (C and C.WindowIds and C.WindowIds()) or {}
    if #ids == 0 then
        -- Before the first reconcile there may be no config tab set at all;
        -- the CLIENT's own live windows are then the honest answer.
        local V = ns.View
        if V and type(V.OwnedIds) == "function" then
            local ok, own = pcall(V.OwnedIds)
            if ok and type(own) == "table" then ids = own end
        end
    end
    local out = {}
    for _, id in ipairs(ids) do
        if id ~= (C and C.COMBAT_LOG_ID or 2) then out[#out + 1] = id end
    end
    return out
end

function Tabs.PageLabel(id)
    local C = ns.Config
    local name = (C and C.WindowName and C.WindowName(id)) or ""
    if name == "" then
        local gcwi = _G.GetChatWindowInfo
        if type(gcwi) == "function" then
            local ok, nm = pcall(gcwi, id)
            if ok and type(nm) == "string" then name = nm end
        end
    end
    if name == "" then name = "Chat " .. tostring(id) end
    if C and C.AddonSinkId and C.AddonSinkId() == id then name = name .. " (addon)" end
    return name
end

Tabs.selected = nil

function Tabs.Selected()
    local ids = Tabs.PageIds()
    for _, id in ipairs(ids) do if id == Tabs.selected then return id end end
    Tabs.selected = ids[1]
    return Tabs.selected
end

function Tabs.Select(id)
    for _, live in ipairs(Tabs.PageIds()) do
        if live == id then
            Tabs.selected = id
            Tabs._pendingRemove = nil     -- a page change cancels a pending remove
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- THE WRITES. Every one of them: config seam -> declared apply route.
----------------------------------------------------------------------

function Tabs.SetName(id, name)
    local C = ns.Config
    if not (C and C.SetWindowName) then return false end
    local changed = C.SetWindowName(id, name)
    if changed then Options.Dispatch("tabs.name") end
    return changed
end

function Tabs.SetColor(id, spec)
    local C = ns.Config
    if not (C and C.SetTabColor) then return false end
    local changed = C.SetTabColor(id, spec)
    if changed then Options.Dispatch("tabs.color") end
    return changed
end

function Tabs.SetGroup(id, group, on)
    local C = ns.Config
    if not (C and C.SetWindowGroup) then return false end
    local changed = C.SetWindowGroup(id, group, on)
    if changed then Options.Dispatch("tabs.group") end
    return changed
end

function Tabs.SetChannel(id, name, on)
    local C = ns.Config
    if not (C and C.SetWindowChannel) then return false end
    local changed = C.SetWindowChannel(id, name, on)
    if changed then Options.Dispatch("tabs.channel") end
    return changed
end

-- + ADD TAB. Config-first: a live window entry, then the reconciler creates it
-- on this character and the view picks the new tab up. Returns the new id.
function Tabs.AddTab(name, opts)
    local C = ns.Config
    if not (C and C.AddWindow) then return nil, "no config" end
    opts = type(opts) == "table" and opts or {}
    opts.name = name
    local id, why = C.AddWindow(opts)
    if not id then
        ns:Print("no free chat window left - the game has ten, and they are all in use.")
        return nil, why
    end
    Options.Dispatch(opts.addonSink and "tabs.addonTab" or "tabs.add")
    Tabs.Select(id)
    return id
end

function Tabs.Removable(id)
    local C = ns.Config
    return (C and C.RemovableWindow and C.RemovableWindow(id)) and true or false
end

-- REMOVE, with the confirm affordance: the first press ARMS (the button
-- re-labels itself), the second one commits. Selecting another page, or
-- pressing anything else, disarms — a destructive verb never rides on one
-- click, and never needs a modal to say so.
Tabs._pendingRemove = nil

function Tabs.RemovePending() return Tabs._pendingRemove end

function Tabs.RemoveLabel(id)
    if Tabs._pendingRemove == id then return "Really remove?" end
    return "Remove this tab"
end

function Tabs.PressRemove(id)
    if not Tabs.Removable(id) then return false end
    if Tabs._pendingRemove ~= id then
        Tabs._pendingRemove = id
        return false                      -- armed, not committed
    end
    Tabs._pendingRemove = nil
    local C = ns.Config
    local removed = C.RemoveWindow(id)
    if removed then
        Options.Dispatch("tabs.remove")
        Tabs.selected = nil
        Tabs.Selected()
    end
    return removed
end

-- THE COMBAT LOG TAB.
function Tabs.CombatLog()
    local C = ns.Config
    return (C and C.CombatLogTab and C.CombatLogTab()) and true or false
end

function Tabs.SetCombatLog(on)
    local C = ns.Config
    if not (C and C.SetCombatLogTab) then return false end
    local changed = C.SetCombatLogTab(on and true or false)
    if changed then Options.Dispatch("tabs.combatLog") end
    return changed
end

-- THE ADDON TAB. One verb, both directions: with no sink it CREATES one (the
-- same config-first Add Tab path, flagged addonSink); with one it removes it.
function Tabs.AddonTabId()
    local C = ns.Config
    return (C and C.AddonSinkId and C.AddonSinkId()) or nil
end

function Tabs.SetAddonTab(on)
    local C = ns.Config
    if not C then return false end
    local cur = Tabs.AddonTabId()
    if on and not cur then
        return Tabs.AddTab("Addon", { addonSink = true }) ~= nil
    end
    if not on and cur then
        C.SetAddonSink(cur, false)
        local removed = C.RemoveWindow(cur)
        Options.Dispatch("tabs.addonTab")
        return removed
    end
    return false
end

function Tabs.RouteAddon()
    local C = ns.Config
    return (C and C.RouteAddonLines and C.RouteAddonLines()) and true or false
end

function Tabs.SetRouteAddon(on)
    local C = ns.Config
    if not (C and C.SetRouteAddonLines) then return false end
    local changed = C.SetRouteAddonLines(on and true or false)
    if changed then Options.Dispatch("tabs.routeAddon") end
    return changed
end

----------------------------------------------------------------------
-- STATUS LINES: read-only truth about the tab set and the classifier.
----------------------------------------------------------------------

function Tabs.Status()
    local ids = Tabs.PageIds()
    local C = ns.Config
    local free = (C and C.NewWindowId and C.NewWindowId()) or nil
    return ("%d chat tab(s) in your shared configuration.%s"):format(#ids,
        free and "" or " Every one of the game's ten windows is in use, so no more can be added.")
end

function Tabs.AddonStatus()
    local id = Tabs.AddonTabId()
    if not id then
        return "No addon tab. Every line goes exactly where the game and this configuration "
            .. "put it - nothing is classified at all."
    end
    if not Tabs.RouteAddon() then
        return "The addon tab exists but routing is OFF: lines flow exactly as they would "
            .. "without it. Turn it on to send addon output there."
    end
    local V = ns.View
    if V and type(V.ClassifierArmed) == "function" and not V.ClassifierArmed() then
        return "Routing is on, but nothing is being classified yet - the drawn chat window "
            .. "has to be up (it is where the routing happens)."
    end
    return "Addon output goes to the addon tab. This is a best guess, not a certainty: a line "
        .. "an addon prints while the game is delivering a chat message reads as chat. If "
        .. "something lands in the wrong tab, turn the toggle off and everything goes back to "
        .. "exactly where it was."
end

function Tabs.CombatLogStatus()
    if Tabs.CombatLog() then
        return "The game's own combat log is hosted inside the chat box as a tab. It stays the "
            .. "game's window - it is not timestamped, coloured, counted or kept by Daseeki."
    end
    return "No combat log tab. The game's log window is hidden along with the rest of the "
        .. "game's chat windows, and comes back the moment Daseeki stops drawing its own."
end

----------------------------------------------------------------------
-- THE SECTION.
----------------------------------------------------------------------

Tabs._pages = {}

function Tabs.Build(flow)
    local Form = Options.Form
    local sec = flow:AddSection("Tabs")

    -- ══ THE SUB-TAB NAV (owner UAT: "the selectors in the tab section have
    -- no label" — his screenshot is four EMPTY BOXES) ════════════════════
    --
    -- ROOT CAUSE, and it is the third face of the blank-caption class: the
    -- buttons were built with `text = ""` and re-captioned in Tabs.Refresh with
    -- `btn:SetText(name)`. A real Button HAS SetText — but Core's MakeButton
    -- never calls SetFontString, so that text goes to a fontstring that does
    -- not exist. The call "succeeded", the `elseif btn._label` fallback was
    -- therefore unreachable, and the boxes stayed blank forever.
    --
    -- THE FIX IS STRUCTURAL, not a call swap: every nav button is BORN with a
    -- caption (so the kit really makes the FontString), it is re-captioned only
    -- through Form.SetCaption (which writes the FontString the kit draws and
    -- returns false if there is none), and a button with no tab behind it is
    -- HIDDEN rather than left standing as an empty box.
    local nav = Form.Group(sec, "Chat tabs")
    Form.Note(nav, "One page per chat tab. Names, colours and routing are shared - set them "
        .. "once on any character and every character gets them.")

    local navRow = Form.Row(nav)
    Tabs._nav = {}
    for i = 1, Tabs.MAX_PAGES do
        local btn = navRow:Button({
            text = "Tab " .. i, width = 84, variant = "quiet",
            onClick = function()
                local id = Tabs.PageIds()[i]
                if id then Tabs.Select(id); Options._refresh() end
            end,
        })
        -- The tab-colour chip: a 3-unit bar under the button in that tab's own
        -- ink, so the nav reads as tabs rather than as a row of buttons.
        if type(btn.CreateTexture) == "function" then
            local ok, chip = pcall(btn.CreateTexture, btn, nil, "OVERLAY")
            if ok and type(chip) == "table" then
                pcall(chip.SetHeight, chip, 3)
                pcall(chip.SetPoint, chip, "BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
                pcall(chip.SetPoint, chip, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
                btn._chip = chip
            end
        end
        Tabs._nav[i] = btn
    end

    local actRow = Form.Row(nav)
    bind("tabs.add")
    actRow:Button({
        text = "+ Add Tab", width = 120,
        tooltip = "A new tab is created in your shared configuration and appears on every "
               .. "character at once.",
        onClick = function()
            Tabs.AddTab("New tab")
            Options._refresh()
        end,
    })
    bind("tabs.remove")
    Tabs._removeBtn = actRow:Button({
        text = "Remove this tab", width = 150, variant = "danger",
        tooltip = "Removing asks twice: the first press arms the button.",
        onClick = function()
            Tabs.PressRemove(Tabs.Selected())
            Options._refresh()
        end,
    })
    Form.CloseGroup(nav)

    -- ══ THE SELECTED PAGE ════════════════════════════════════════════════
    local page = Form.Group(sec, "This tab")
    bind("tabs.name")
    bind("tabs.color")
    Form.Pair(page,
        { caption = "Tab name", width = 180, make = function(row)
            return reg(Form.FixWidth(row:EditBox({
                width = 180,
                get = function()
                    local id = Tabs.Selected()
                    return id and (Tabs.PageLabel(id):gsub(" %(addon%)$", "")) or ""
                end,
                set = function(v)
                    local id = Tabs.Selected()
                    if id then Tabs.SetName(id, tostring(v or "")) end
                    Options._refresh()
                end,
            }), 180))
        end },
        { caption = "Tab colour", width = 140, make = function(row)
            return reg(row:Dropdown({
                width = 140, choices = Tabs.COLOR_CHOICES,
                tooltip = "\"Automatic\" gives a tab the colour of the channel it is for, and "
                       .. "the accent colour when it carries more than one. Channel colours "
                       .. "themselves live in General - they belong to the channel, not the tab.",
                get = function()
                    local C, id = ns.Config, Tabs.Selected()
                    return (id and C and C.TabColor and C.TabColor(id)) or ""
                end,
                set = function(v)
                    local id = Tabs.Selected()
                    if id then Tabs.SetColor(id, tostring(v or "")) end
                    Options._refresh()
                end,
            }))
        end })
    Form.CloseGroup(page)

    -- ══ WHICH MESSAGES COME HERE — the client-config layout ══════════════
    -- Five titled boxes, two columns of checkboxes inside each. Colours are
    -- global (they belong to the channel and the group), so a row is a checkbox
    -- and a name and nothing else, exactly as in the reference.
    bind("tabs.group")
    Tabs._groupBoxes = {}
    Tabs._groupGroups = {}
    for _, branch in ipairs(Tabs.GROUP_TREE) do
        local box = Form.Group(sec, branch.title)
        local items = {}
        for _, entry in ipairs(branch.groups) do
            local group, label = entry[1], entry[2]
            items[#items + 1] = {
                label = label,
                get = function()
                    local C, id = ns.Config, Tabs.Selected()
                    return (id and C and C.WindowHasGroup and C.WindowHasGroup(id, group)) or false
                end,
                set = function(v)
                    local id = Tabs.Selected()
                    if id then Tabs.SetGroup(id, group, v and true or false) end
                end,
            }
        end
        local grid = Form.Checks(box, items)
        for n, entry in ipairs(branch.groups) do
            Tabs._groupBoxes[entry[1]] = reg(grid._boxes and grid._boxes[n] or nil)
        end
        Form.CloseGroup(box)
        Tabs._groupGroups[#Tabs._groupGroups + 1] = box
    end

    -- ══ WHICH CHANNELS COME HERE ═════════════════════════════════════════
    -- A pooled row per channel, captioned with the channel's own name through
    -- the one re-caption path, and HIDDEN when there is no channel behind it
    -- (the same ghost-row rule the channel manager now holds to).
    bind("tabs.channel")
    local chans = Form.Group(sec, "Channels")
    Tabs._chanBoxes = {}
    for i = 1, MAX_CHANNEL_ROUTES do
        Tabs._chanBoxes[i] = reg(Form.Check(chans, {
            label = "channel " .. i,
            get = function()
                local C, id = ns.Config, Tabs.Selected()
                local row = Options.ChannelRows()[i]
                if not (id and row and C and C.WindowHasChannel) then return false end
                return C.WindowHasChannel(id, row.name)
            end,
            set = function(v)
                local id, row = Tabs.Selected(), Options.ChannelRows()[i]
                if id and row then Tabs.SetChannel(id, row.name, v and true or false) end
            end,
        }))
    end
    Tabs._chanGroup = chans
    Form.CloseGroup(chans)

    -- ══ ADVANCED: notifications and the two special tabs ═════════════════
    -- The owner: "there are just way too many options in general". Everything
    -- a player sets once and never touches again lives behind one press.
    local adv = Form.Advanced(sec, "Notifications and special tabs")
    Tabs._toggles = {}
    local checks = {
        { label = "Count unread lines on tabs (all tabs)",
          get = moduleGet("badges.module"), set = moduleSet("badges.module") },
    }
    for _, spec in ipairs(Tabs.TOGGLES) do
        bind(spec.binding)
        checks[#checks + 1] = {
            _spec = spec, label = spec.label, tooltip = spec.tooltip,
            get = function()
                local id = Tabs.Selected()
                return id and Tabs.ToggleGet(spec, id) or false
            end,
            set = function(v)
                local id = Tabs.Selected()
                if id then Tabs.ToggleSet(spec, id, v and true or false) end
            end,
        }
    end
    bind("tabs.combatLog")
    checks[#checks + 1] = {
        label = "Combat Log tab",
        tooltip = "Show the game's own combat log as a tab in Daseeki's chat box. The log "
               .. "itself stays the game's window - it is hosted, not rebuilt, not "
               .. "timestamped, coloured, counted or kept.",
        get = function() return Tabs.CombatLog() end,
        set = function(v) Tabs.SetCombatLog(v); Options._refresh() end,
    }
    bind("tabs.addonTab")
    checks[#checks + 1] = {
        label = "Addon tab",
        tooltip = "A tab that collects what OTHER addons print to chat, so your conversation "
               .. "stays your conversation.",
        get = function() return Tabs.AddonTabId() ~= nil end,
        set = function(v) Tabs.SetAddonTab(v and true or false); Options._refresh() end,
    }
    bind("tabs.routeAddon")
    checks[#checks + 1] = {
        label = "Route addon messages there",
        tooltip = "This is a best guess, not a certainty: a line an addon prints while the "
               .. "game is delivering a chat message reads as chat. Off leaves every line "
               .. "exactly where it would have been without the addon tab.",
        get = function() return Tabs.RouteAddon() end,
        set = function(v) Tabs.SetRouteAddon(v); Options._refresh() end,
    }
    local advGrid = Form.Checks(adv, checks)
    for n, c in ipairs(checks) do
        local w = advGrid._boxes and advGrid._boxes[n]
        reg(w)
        if c._spec then Tabs._toggles[c._spec.key] = w end
    end
    local filterBinding = bind("badges.filter")
    Form.Button(adv, {
        text = "Clear unread group filter", width = 220, variant = "quiet",
        onClick = function()
            Options.Set("badges", "filter", nil, filterBinding.apply)
            Options.RefreshStatusLines()
        end,
    })
    Tabs._addonStatus = statusHint(adv.flow, Tabs.AddonStatus)
    Options.Form._spend(adv, Options.Form.HINT_H * 3, "addon status")
    Form.CloseGroup(adv)
end

-- Re-point the pooled sub-tab buttons, the channel-route labels and the remove
-- button at the current world (the section's refresh).
-- THE SINGLE RE-CAPTION PATH, everywhere. Nothing in this function reaches for
-- a widget's own SetText any more: a Core Label is a frame that has none, and a
-- Core Button has one that paints nothing. Form.SetCaption writes the
-- FontString the kit really draws and REFUSES (returns false) when there is
-- none, so a caption that cannot be written is a failure a test can see instead
-- of a blank box a player has to report.
function Tabs.Refresh()
    local Form = Options.Form
    local ids = Tabs.PageIds()
    local sel = Tabs.Selected()
    Tabs._shownNav, Tabs._captionFailures = 0, {}
    local function caption(w, text, what)
        if not Form.SetCaption(w, text) then
            Tabs._captionFailures[#Tabs._captionFailures + 1] = tostring(what)
        end
    end
    for i = 1, Tabs.MAX_PAGES do
        local btn = Tabs._nav and Tabs._nav[i]
        local id = ids[i]
        if btn then
            if id then
                Tabs._shownNav = Tabs._shownNav + 1
                local text = Tabs.PageLabel(id)
                caption(btn, text, "nav " .. i)
                -- The selected page reads as selected without a bracket
                -- convention: its ink is the accent, the rest are muted.
                local UI = _G.DaseekiUI
                if btn._label and UI and UI.Color and type(btn._label.SetTextColor) == "function" then
                    pcall(btn._label.SetTextColor, btn._label,
                        UI.Color(id == sel and "accent" or "muted"))
                end
                Tabs.PaintChip(btn, id, id == sel)
                if type(btn.Show) == "function" then pcall(btn.Show, btn) end
            elseif type(btn.Hide) == "function" then
                -- No tab behind it: not an empty box, no box at all.
                pcall(btn.Hide, btn)
            end
        end
    end
    local rm = Tabs._removeBtn
    if rm then caption(rm, sel and Tabs.RemoveLabel(sel) or "Remove this tab", "remove") end

    local rows = Options.ChannelRows()
    Tabs._shownChanBoxes = 0
    for i = 1, MAX_CHANNEL_ROUTES do
        local box = Tabs._chanBoxes and Tabs._chanBoxes[i]
        local row = rows[i]
        if box then
            if row then
                Tabs._shownChanBoxes = Tabs._shownChanBoxes + 1
                caption(box, Options.ChannelRowLabel(row), "channel route " .. i)
                if type(box.Show) == "function" then pcall(box.Show, box) end
            elseif type(box.Hide) == "function" then
                pcall(box.Hide, box)
            end
            if type(box.Refresh) == "function" then box.Refresh() end
        end
    end
    return #ids
end

-- The nav button's tab-colour chip: the tab's own ink, so a sub-tab looks like
-- the tab it edits. Muted when the tab carries no colour of its own.
function Tabs.PaintChip(btn, id, selected)
    local chip = type(btn) == "table" and btn._chip or nil
    if not (chip and type(chip.SetColorTexture) == "function") then return false end
    local V, UI = ns.View, _G.DaseekiUI
    local r, g, b
    if V and type(V.TabInk) == "function" then
        local ok, rr, gg, bb = pcall(V.TabInk, id)
        if ok and type(rr) == "number" then r, g, b = rr, gg, bb end
    end
    if not r then
        if UI and UI.Color then r, g, b = UI.Color(selected and "accent" or "borderLite")
        else r, g, b = 0.5, 0.5, 0.5 end
    end
    pcall(chip.SetColorTexture, chip, r, g, b, selected and 1 or 0.55)
    return true
end

----------------------------------------------------------------------
-- The debug surface.
----------------------------------------------------------------------

ns.RegisterDebugCommand("tabs", "the tab set: pages, routing, the special tabs", function()
    local ids = Tabs.PageIds()
    ns:Print(("tabs: %d page(s), selected %s"):format(#ids, tostring(Tabs.Selected())))
    local C = ns.Config
    for _, id in ipairs(ids) do
        ns:Print(("  %d. %s  groups=%d channels=%d colour=%s"):format(
            id, Tabs.PageLabel(id),
            #((C and C.WindowGroups and C.WindowGroups(id)) or {}),
            #((C and C.WindowChannels and C.WindowChannels(id)) or {}),
            tostring((C and C.TabColor and C.TabColor(id)) or "auto")))
    end
    ns:Print("  " .. Tabs.CombatLogStatus())
    ns:Print("  " .. Tabs.AddonStatus())
end)

----------------------------------------------------------------------
-- Self-tests (suite "options-tabs").
----------------------------------------------------------------------

-- The pure half: the tree, the palette, the polarity trap, the page set.
local function testPure(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end

    local seen = {}
    for _, branch in ipairs(Tabs.GROUP_TREE) do
        ck(type(branch.title) == "string" and branch.title ~= "", "every tree branch is named")
        for _, g in ipairs(branch.groups) do
            ck(type(g[1]) == "string" and g[1] == g[1]:upper(),
                "a group is the CLIENT's own token: " .. tostring(g[1]))
            ck(type(g[2]) == "string" and g[2] ~= "", "…with a readable label")
            ck(not seen[g[1]], "…and appears exactly once in the tree (" .. tostring(g[1]) .. ")")
            seen[g[1]] = true
        end
    end
    local flat = Tabs.AllGroups()
    ck(#flat > 20, "the tree covers the client's chat-group model (got " .. #flat .. ")")
    local sorted = true
    for i = 2, #flat do if flat[i - 1] > flat[i] then sorted = false end end
    ck(sorted, "the flat group list is sorted (Class 8)")

    local sawAuto, sawToken, sawChat = false, false, false
    for _, choice in ipairs(Tabs.COLOR_CHOICES) do
        if choice.value == "" then sawAuto = true end
        if choice.value:find("^token:") then sawToken = true end
        if choice.value:find("^chat:") then sawChat = true end
        ck(type(choice.text) == "string" and choice.text ~= "",
            "every colour choice carries a readable name")
    end
    ck(sawAuto and sawToken and sawChat,
        "the palette offers Automatic, theme tokens AND the client's own chat colours")

    ck(#Tabs.TOGGLES == 4, "the page carries all four per-tab opt-outs")
end

-- The live half: the write paths, the add/remove convergence and the two
-- special tabs, driven through the PANE's own closures wherever one exists.
local function testLive(fails)
    local function ck(c, m) if not c then fails[#fails + 1] = m end end
    local C = ns.Config
    local UI = _G.DaseekiUI
    if not (C and UI and UI.__BuildPane) then return end

    local cfg = C.Get()
    local savedWindows, savedSkin = cfg.windows, cfg.skin
    local savedRev, savedAt = cfg.rev, cfg.at
    cfg.windows = C.CopyCfg(cfg.windows or {})
    cfg.skin    = C.CopyCfg(cfg.skin or {})

    -- THE WORLD THIS SUITE NEEDS, and it is the whole point of it: the pane up,
    -- the RECONCILER up (Add Tab is config-first, so its red control is "the
    -- reconciler made the client's window live"), and the DRAWN WINDOW up (so
    -- "and the strip grew a tab for it" is a pixel fact rather than a hope).
    -- Enabled here rather than assumed, because a suite that silently skips its
    -- own red controls is the silent-green class this harness exists to catch.
    local wasOpts   = ns.ModuleEnabled("options")
    local wasView   = ns.ModuleEnabled("view")
    local wasSkin   = ns.ModuleEnabled("skin")
    local wasRecon  = ns.ModuleEnabled("reconcile")
    ns.SetModuleEnabled("options", true)
    ns.SetModuleEnabled("skin", true)
    ns.SetModuleEnabled("view", true)
    ns.SetModuleEnabled("reconcile", true)
    local HT = _G.__DaseekiChatHarnessTimer
    if HT then HT.flush() end
    -- THE PANE IS BUILT ONCE (Core builds lazily and this addon's build is
    -- guarded by Options._built), so a second __BuildPane would hand back an
    -- EMPTY recording pane and every assertion below it would be vacuous. Take
    -- the one that was really built, exactly as the options suite does.
    local def = UI.__RegisteredAddon("chat")
    local pane = def and def.sections and def.sections[1] and def.sections[1]._pane
    if not pane then pane = UI.__BuildPane("chat", "settings") end
    ck(type(pane) == "table" and #(pane.controls or {}) > 0,
        "the pane is built, with the Tabs section's controls in it")
    if type(pane) ~= "table" then return end

    -- ── The pages ────────────────────────────────────────────────────────
    local ids = Tabs.PageIds()
    ck(#ids >= 1, "at least one tab page is offered")
    ck(Tabs.Selected() ~= nil, "…and one of them is selected")
    ck(Tabs.PageLabel(ids[1]) ~= "", "…each carrying a readable name")
    for _, id in ipairs(ids) do
        ck(id ~= (C.COMBAT_LOG_ID or 2), "the combat log is never one of the pages")
    end

    -- ── Rename, colour, groups, channels ─────────────────────────────────
    local id = Tabs.Selected()
    ck(Tabs.SetName(id, "Renamed") == true and C.WindowName(id) == "Renamed",
        "the name box writes through the config seam")
    ck(Tabs.SetColor(id, "chat:GUILD") == true and C.TabColor(id) == "chat:GUILD",
        "the colour dropdown writes through the config seam")
    ck(Tabs.SetColor(id, "") == true and C.TabColor(id) == nil, "…and Automatic clears it")
    -- A group the tab does not already carry, so the write is a real change
    -- (an unchanged write is correctly a no-op, and asserting on one would be
    -- asserting the no-op).
    local probeGroup = "MONSTER_WHISPER"
    if C.WindowHasGroup(id, probeGroup) then Tabs.SetGroup(id, probeGroup, false) end
    ck(Tabs.SetGroup(id, probeGroup, true) == true and C.WindowHasGroup(id, probeGroup),
        "a group checkbox writes the routing")
    ck(Tabs.SetGroup(id, probeGroup, true) == false, "…and an unchanged one is a no-op")
    ck(Tabs.SetGroup(id, probeGroup, false) == true and not C.WindowHasGroup(id, probeGroup),
        "…and unchecking removes it")
    ck(Tabs.SetChannel(id, "Trade", true) == true and C.WindowHasChannel(id, "Trade"),
        "a channel checkbox writes the routing")
    ck(Tabs.SetChannel(id, "Trade", false) == true, "…and unchecks it")

    -- ── The four per-tab toggles, and the polarity trap ──────────────────
    for _, spec in ipairs(Tabs.TOGGLES) do
        local branch = Options.Branch(spec.branch)
        ck(type(branch) == "table", spec.key .. ": the module's own branch is reachable")
        ck(Tabs.ToggleGet(spec, 6) == true,
            spec.key .. ": an untouched tab is ON (absent means on, in every one of them)")
        Tabs.ToggleSet(spec, 6, false)
        ck(Tabs.ToggleGet(spec, 6) == false, spec.key .. ": turning it off reads back")
        ck(branch[spec.store][6] == spec.offValue,
            spec.key .. ": …as the value that MODULE's own rule reads ("
            .. tostring(spec.offValue) .. ")")
        Tabs.ToggleSet(spec, 6, true)
        ck(branch[spec.store][6] == spec.onValue and Tabs.ToggleGet(spec, 6) == true,
            spec.key .. ": and turning it back on clears the entry entirely")
    end

    -- ── + ADD TAB, through the pane's own button ─────────────────────────
    local before = #Tabs.PageIds()
    local addBtn
    for _, w in ipairs(pane.controls) do
        if w._kind == "button" and w._opts.text == "+ Add Tab" then addBtn = w end
    end
    ck(addBtn ~= nil, "the + Add Tab button is on the pane")
    if addBtn then
        addBtn._opts.onClick()
        local now = Tabs.PageIds()
        ck(#now == before + 1, "RED CONTROL — + Add Tab adds a tab (" .. #now .. ")")
        local newId = Tabs.Selected()
        ck(C.WindowEntry(newId) and C.WindowEntry(newId).shown == true,
            "…as a LIVE window entry in the shared configuration")
        ck(C.Snapshot() and C.Snapshot().cfg.windows[newId] ~= nil,
            "RED CONTROL — …and the new tab rides the sync snapshot")

        -- THE CONVERGENCE, asserted rather than assumed: the pane wrote CONFIG,
        -- the reconciler wrote the CLIENT, and the drawn window read what the
        -- reconciler left. Three layers, one click.
        local R = ns.Reconcile
        ck(R and R.active == true, "the reconciler is up to converge the add")
        if HT then HT.flush() end
        local gcwi = _G.GetChatWindowInfo
        local ok, name, _, _, _, _, _, shown = pcall(gcwi, newId)
        ck(ok and (shown and shown ~= 0),
            "RED CONTROL — the reconciler made the CLIENT's own window live")
        ck(name == C.WindowName(newId),
            "…carrying the name the config gave it (got " .. tostring(name) .. ")")
        local V = ns.View
        ck(V and V.active == true, "the drawn window is up to show the new tab")
        if V and V.active then
            local drawn = false
            for _, vid in ipairs(V.ids) do if vid == newId then drawn = true end end
            ck(drawn, "RED CONTROL — …and the drawn window grew the tab for it")
            ck(V.frames[newId] ~= nil, "…with a message surface of its own")
            ck(V.wrappedFrames[V.ClientFrame(newId)] == true,
                "…and its engine window's AddMessage wrapped, so lines mirror into it")
        end

        -- ── REMOVE, with the confirm affordance ─────────────────────────
        ck(Tabs.Removable(newId) == true, "a tab the config made is removable")
        ck(Tabs.Removable(1) == false, "…and the primary window never is")
        ck(Tabs.PressRemove(newId) == false, "the first press ARMS the remove")
        ck(Tabs.RemovePending() == newId, "…and says so")
        ck(Tabs.RemoveLabel(newId) == "Really remove?", "…on the button itself")
        Tabs.Select(newId)
        ck(Tabs.RemovePending() == nil, "selecting a page disarms it again")
        Tabs.PressRemove(newId)
        ck(Tabs.PressRemove(newId) == true, "the second press commits")
        if HT then HT.flush() end
        local gone = true
        for _, live in ipairs(Tabs.PageIds()) do if live == newId then gone = false end end
        ck(gone, "RED CONTROL — the tab is gone from the config's tab set")
        ck(Tabs.Selected() ~= newId, "…and the pane moved off its page")
        local okR, _, _, _, _, _, _, shownR = pcall(gcwi, newId)
        ck(okR and not (shownR and shownR ~= 0),
            "RED CONTROL — the reconciler closed the CLIENT's window too")
        if V and V.active then
            local still = false
            for _, vid in ipairs(V.ids) do if vid == newId then still = true end end
            ck(not still, "RED CONTROL — …and the drawn window dropped the tab")
        end
    end

    -- ── THE COMBAT LOG TOGGLE ────────────────────────────────────────────
    local wasLog = Tabs.CombatLog()
    ck(Tabs.SetCombatLog(true) == true and Tabs.CombatLog() == true,
        "the combat log toggle writes the synced config")
    local V = ns.View
    if V and V.active then
        local hasLog = false
        for _, vid in ipairs(V.ids) do if vid == (C.COMBAT_LOG_ID or 2) then hasLog = true end end
        ck(hasLog, "RED CONTROL — …and the tab appears in the drawn strip in the same beat")
        ck(_G.ChatFrame2 and _G.ChatFrame2._parent == V.chassis,
            "RED CONTROL — …hosting the CLIENT's own log frame inside the chassis")
    end
    ck(Tabs.SetCombatLog(false) == true, "turning it off lands")
    if V and V.active then
        local hasLog = false
        for _, vid in ipairs(V.ids) do if vid == (C.COMBAT_LOG_ID or 2) then hasLog = true end end
        ck(not hasLog, "RED CONTROL — …and the tab is gone again")
    end
    Tabs.SetCombatLog(wasLog)

    -- ── THE ADDON TAB ────────────────────────────────────────────────────
    ck(Tabs.AddonTabId() == nil, "no addon tab to start with")
    ck(Tabs.SetAddonTab(true) == true, "the addon tab is created through the Add Tab path")
    local sink = Tabs.AddonTabId()
    ck(type(sink) == "number", "…and is found by its config flag")
    ck(C.WindowEntry(sink) and C.WindowEntry(sink).addonSink == true,
        "…which is what makes it the sink (not its name)")
    ck(#C.WindowGroups(sink) == 0 and #C.WindowChannels(sink) == 0,
        "…and it is routed NOTHING by the client, so only classified lines can reach it")
    ck(Tabs.RouteAddon() == true, "routing defaults ON once the tab exists")
    ck(Tabs.SetRouteAddon(false) == true and Tabs.RouteAddon() == false,
        "…and the toggle turns it off")
    ck(Tabs.AddonStatus():find("exactly as they would", 1, true) ~= nil,
        "…with the status line saying honestly that nothing is classified")
    Tabs.SetRouteAddon(true)
    -- HONEST EITHER WAY, and both ways are pinned: with the drawn window up the
    -- line owns the heuristic out loud; with it down it says why nothing is
    -- being classified rather than implying it is.
    local st = Tabs.AddonStatus()
    ck(st:find("best guess", 1, true) ~= nil or st:find("has to be up", 1, true) ~= nil,
        "the status line is HONEST rather than promising accuracy (got: " .. st:sub(1, 60) .. ")")
    ck(Tabs.SetAddonTab(false) == true and Tabs.AddonTabId() == nil,
        "…and the tab can be taken away again")

    -- The refresh re-points everything without erroring on a pooled row that
    -- has no channel behind it.
    ck(type(Tabs.Refresh()) == "number", "the section refresh re-points its pooled controls")

    -- Put the world back: the config first, then one reconcile so the CLIENT
    -- store follows it, then the strip.
    cfg.windows, cfg.skin = savedWindows, savedSkin
    cfg.rev, cfg.at = savedRev, savedAt
    local R2 = ns.Reconcile
    if R2 and R2.active and R2.Run then R2.Run("options-tabs-cleanup") end
    if HT then HT.flush() end
    local V2 = ns.View
    if V2 and V2.active and V2.RebuildTabs then V2.RebuildTabs("options-tabs-cleanup") end
    ns.SetModuleEnabled("reconcile", wasRecon)
    ns.SetModuleEnabled("view", wasView)
    ns.SetModuleEnabled("skin", wasSkin)
    if not wasOpts then ns.SetModuleEnabled("options", false) end
    if HT then HT.flush() end
end

ns:RegisterSelfTest("options-tabs", function(verbose)
    local suites = {
        { name = "pure (the group tree, the palette, the polarity trap)", fn = testPure },
        { name = "live (rename/routing/add/remove/special tabs)",         fn = testLive },
    }
    local allPass = true
    for _, suite in ipairs(suites) do
        local fails = {}
        local ok, err = pcall(suite.fn, fails)
        if not ok then fails[#fails + 1] = "error: " .. tostring(err) end
        if #fails > 0 then allPass = false end
        if verbose and ns.Print then
            if #fails == 0 then ns:Print("  PASS options-tabs/" .. suite.name)
            else for _, f in ipairs(fails) do
                ns:Print("  FAIL options-tabs/" .. suite.name .. " :: " .. f) end
            end
        end
    end
    return allPass
end)

return Tabs
