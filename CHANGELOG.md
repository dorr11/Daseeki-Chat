# Changelog

## Unreleased — first release

Daseeki Chat replaces Prat on this account: **its own chat window**, drawn in the
shared Daseeki look, with one account-spanning chat configuration that every
character — including a brand-new one — reconciles to automatically at login.

This entry accumulates until 1.0.0 ships.

### Daseeki draws its own chat window

**This is the headline.** Chat no longer re-dresses the game's chat window — it
draws its own, and the game's ten chat windows become a hidden engine behind it.

The reason is simple: two rounds of careful work still could not hold the design
on screen. The game kept taking its window back. It fades the tabs on beats
nobody asked for, it re-decides where the little button column goes and pushes
the window away from the screen edge while it is at it, it puts its own artwork
back underneath ours, and it re-places the window from its own saved position on
its own schedule. Every single property of the design was a fight, forever, and
"forever" is not a thing software wins. Drawing our own makes the design the
*default state* instead of a position to be defended.

What you get:

- **One box, at the design's own numbers.** The panel, the border, the tab
  strip, the message area and the input bar are all ours, in the exact colours
  the approved design specifies — no approximations, no tones bled through from
  underneath. Your thinner tabs and entry bar, and the removed dead space at the
  left and right of the feed, are the shipped defaults.
- **Tabs that stop fading.** They never fade again, because there is nothing to
  fade them — our tabs are not part of the game's tab machinery at all. An
  unselected tab is *quieter in colour*, which is what the design draws;
  nothing in the window animates its transparency, ever. The selected tab wears
  the message surface's own fill so the two read as one piece, with the accent
  underline above it, and it can sit on the top, left or right exactly as
  before.
- **Your window stays where you put it.** There is no bounce-back to fix any
  more: the game has no machinery pointed at a window it does not own. Drag it
  by the tab strip, or ALT-drag anywhere on it; it snaps to screen edges, screen
  centre lines and the same boundaries as before, and the position still lives
  in the same synced configuration and still shows up in
  `/dchat debug reconcile`.
- **Everything you already configured still applies.** Tab position, per-tab
  colours, channel routing, channel names and aliases, timestamps, class
  colours, link handling, scrollback across sessions and the unread counters all
  work exactly as they did and are still synced across your characters — the
  configuration layer did not change at all. Messages are decorated by the same
  code, in the same order, and arrive in the new window with their colours
  intact.
- **Your typing bar is still the game's.** Slash commands, channel stickiness
  and sending are the game's own machinery, moved into our window rather than
  rewritten — there is no version of "we reimplemented sending" that is safe.
  It is always visible, Escape unfocuses it without hiding it, and switching
  tabs points it at that tab so replies and your sticky channel follow you.
- **Unread counters ride the new tabs**, as the same red chip with white digits,
  and clear when you look at the tab.
- **The combat log is left alone**, native and untouched.
- **Turning it off gives the game's chat straight back.** Uncheck *Draw
  Daseeki's own chat window* under **Appearance** (or `/dchat disable view`) and
  the game's windows come back visible, the typing bar goes home, and nothing
  has been destroyed. New sliders there set the message text size, the line
  height and the tab text size.
- Two things the design asks for that the game genuinely cannot do survive:
  **letter spacing** and **tabular figures** are not available on game text at
  all. Rounded corners and the drop shadow are now *possible* — they need
  bespoke corner art and are queued rather than refused. Everything else in the
  mapping table (now at the top of `view.lua`) reads identical.
- `/dchat debug view` prints the whole thing: the design's numbers, the palette,
  the mirror's counters, how many times the game tried to re-show a window we
  had put away, and the line count per tab.

### Alignment fixes, and the chat box can now be resized

The first live look at the drawn window found three things wrong with how it was
laid out, and one thing missing. All four are fixed.

- **The tabs no longer draw on top of each other.** The row of tabs was placing
  each tab at a distance measured from the *previous tab's width* instead of
  from where the previous tab actually ended, so the first tab landed correctly
  and everything after it piled into the same small band — the garbled
  "Loot FoDMs" in the screenshot. The row now runs properly, with the design's
  2-unit gap between tabs, and there is a test that measures where every tab
  ends up rather than trusting that it is right.
- **The unread counter sits inside its tab again.** The chip was hanging off the
  *tab's* right edge instead of off the end of the tab's *label*, which left it
  floating detached in the gap between two tabs while the tab itself had already
  been made wider to hold it. The label and the chip are now centred inside the
  tab as one piece, exactly as the design draws them, and a tab that gains a
  counter grows to fit it on the very next frame.
- **No more stray game tabs floating over your chat.** A chat window is not one
  frame: hanging off each one are its tab (which lives on the game's dock bar,
  not on the window, so hiding the window never hid it), its typing box, its
  button column, the column's minimize button, the minimized stand-in, the
  resize grip, the scrollbar and a click-catcher overlay. Only three of those
  were being put away, and the game puts its tabs back on beats of its own —
  which is how a stock gold-bordered "Loot" tab ended up sitting in the middle
  of the message feed and clipping the top line. The whole family is now put
  away, held down against every beat the game re-asserts them on, and restored
  exactly as it was found when the window is switched off.
- **You can resize it.** (Superseded below: this shipped as one handle in the
  bottom-right that only appeared on hover, which was too easy to miss — there
  are four, always visible while unlocked, and a lock to turn them off.) It
  will not shrink below a usable box (the tab strip,
  three lines of chat and the typing bar) or grow past your screen, the tab
  strip, feed, typing bar and side rail all reflow as you drag, and the drop
  snaps to screen edges and centre lines just like a move does. **The size is
  synced**, stored the same scale-independent way the position is — as a
  fraction of your screen — so it means the same thing on every account and
  every character, and it is restored at login by the same reconciler that
  restores the position. `/dchat debug reconcile` now reports a resize in the
  same one-line verdict it reports a move in.

### The settings actually change things now

Every control in the settings pane wrote its setting correctly and always had —
what was missing was the other half: **nothing re-read it**, so most of the pane
only took effect after a `/reload`. Moving the message-size slider changed a
number in your configuration and left the window exactly as it was. That is
fixed at the mechanism, not control by control:

- **Every setting now names the thing it re-draws**, and the addon refuses to
  ship a control that names nothing. Move a slider and the chat text restyles
  under your cursor — with your scrollback intact, because it is a restyle and
  not a rebuild. Tick a box and the button, pip or bar appears or disappears in
  the same instant. Pick a tab colour and the tab is wearing it before you let
  go of the menu.
- **A handful of settings genuinely have nothing standing to re-draw** — how
  many lines are kept for next session is read when the session ends, and
  whether a web address is drawn in brackets is decided as each new line
  arrives. Those now say so in writing instead of looking broken, and the tests
  drive the *next* line to prove they really take effect.
- **Settings you change here sync exactly like changes you make in-game.**
  Choosing a tab position or a tab colour in the pane bumps your shared chat
  configuration and travels to your other characters the same way dragging the
  box does.

### Tabs on the left or right no longer break the window

Setting the tab position to Left (or Right) left the window in a mixed state:
one tab still on the top strip while the rest were drawn down the side **over
the message text**, with an unread counter floating loose and the feed never
making room for the side rail.

- **The tab strip and the tabs on it are now decided together, always.** The old
  code could re-run the *row of tabs* on an ordinary beat — a colour change, a
  tab click — while the *strip they sit on* was still in its old shape, so the
  new side rail was drawn straight over the message area. Moving the tabs now
  moves the strip, re-insets the message feed for the rail's width, and
  re-checks the box's minimum size, as one act. This also covers the case where
  *another character* changed the tab position: your box migrates correctly the
  next time anything touches it.
- **The box can no longer be too small for its own tabs.** A side rail of five
  tabs needs a certain height whatever the message feed wants; below that the
  last tabs used to run off the rail and across the typing bar. The minimum size
  now accounts for the tabs themselves, on whichever edge they are on.
- **The unread counters ride the side rail properly**, right-aligned in their
  row with the tab's name trimmed to leave them room, instead of colliding.
- Behind this: the tab layout was two near-identical copies of the same
  arithmetic (one for the top strip, one for the side rail) that had already
  drifted apart once. It is one routine now, and the tests are a **matrix** —
  every tab position, with and without unread counters, with one to five tabs,
  at the smallest, default and largest sizes, and switching between every pair
  of positions in both directions — asserting that no tab overlaps another, no
  tab is left on the wrong surface, and the message feed, tab strip and typing
  bar never overlap. That matrix found the remaining faults; hand-picked cases
  had missed them.

### Lock and unlock, and four resize corners

- **`/dchat lock` and `/dchat unlock`**, plus a *Lock the chat box in place*
  checkbox under **Windows**. Locked, the box is a rock: dragging does nothing
  (ALT-drag included), resizing does nothing, no snap guides appear and the
  corner handles are gone, so a stray drag can never shift your chat again.
  `/dchat` tells you which state you are in along with the command list.
- **The lock travels with your configuration**, beside the position and size it
  governs — lock it once on any character and every character's box is locked.
  It ships **unlocked**, so nothing you have now changes until you say so.
- **All four corners resize now, and you can see them.** The old single handle
  in the bottom-right only appeared while the pointer was on the box, which is
  why it had to be asked about; there are now four, one per corner, quietly
  visible the whole time the box is unlocked and brighter under the pointer.
  Drag any of them and the **opposite corner stays exactly where it is**. All
  the old rules still apply — the minimum and maximum sizes, the reflow while
  you drag, the snap on the drop, and the size still syncs to your other
  characters.

### The settings menu, rebuilt

The old settings page had eight sections and told you almost nothing about what
any of them were for. It has been rebuilt as **three**, around what you actually
set:

**General — how chat looks.** Font, text size and theme (the whole Daseeki
suite's, offered here rather than copied, so changing one changes every Daseeki
window at once), message text size, line spacing, tab text size, tab style
(top / left / right), and the lock. **No sliders anywhere** — every number is a
dropdown of sensible steps, and the test suite now fails the build if a slider
ever comes back. Timestamps, name colouring, web links and the copy button
folded in underneath as one display group, and the game's-own-windows settings
sit last, behind a line that says plainly which renderer they speak to.

**General → Channels — one row per channel, and three things you can do to it:**

- **Drag a row to change that channel's number.** The order you drop them in is
  the order your characters get: it writes the shared configuration's channel
  order, and the join-order engine drives the game's own numbering to match on
  every character. A drag can only ever *renumber* — it can never join or leave
  a channel — and a channel you are not currently in politely refuses to move
  (there is no number to change) while keeping its colour and its name.
- **A colour per channel**, stored by name, so it survives the game shuffling
  channel numbers around between characters and sessions.
- **A short name per channel.** "LookingForGroup" becomes "LFG" in the chat
  line, on the typing bar's channel label, and on any tab that belongs to that
  channel — the same one seam, three places. This replaces the separate
  *Channel names* page; there is now exactly one place to rename a channel.

**Tabs — one page per chat tab.** Its name, its colour, which kinds of message
come to it (the game's own message groups, as a tidy checklist), which channels
come to it, and its notifications (unread counter and whisper accent, per tab).
Channel and message colours deliberately are *not* here: they belong to the
channel, not to the tab, so they live in General and stay consistent everywhere.
Plus three new things:

- **+ Add Tab.** A new tab appears immediately, and on every one of your
  characters — it is written into the shared configuration and the reconciler
  creates the window, exactly the way a brand-new character gets your layout.
  **Removing** a tab asks twice (the button re-labels itself to *Really
  remove?*); your first chat window can never be removed.
- **A Combat Log tab.** Off by default. Turned on, the game's own combat log
  moves *inside* the chat box as a tab — it stays the game's log window, so it
  is not timestamped, coloured, counted or kept by Daseeki; it is just hosted.
  Turned off, it goes back where it was.
- **An Addon tab.** A tab that collects what *other* addons print to chat, so
  your conversation stays your conversation. **The honest part:** a chat line
  carries no flag saying who wrote it, so this is a best guess — a line that
  arrives outside the game's own chat delivery is treated as addon output. An
  addon that prints while the game is delivering a message will read as chat and
  stay where it is. Which is why there is a *Route addon messages here* switch:
  turn it off (or do not make the tab at all) and every line goes exactly where
  it would have gone before, unchanged.

**Chat History** keeps its own page: on or off, how many lines per tab, how old
is too old, and whether restored lines sit behind a session divider (new — turn
it off and you get that row of scrollback back).

Everything above is part of your shared configuration and reaches every
character, the same as the rest: tab order, tab names, colours, routing, the two
special tabs and the channel order, names and colours.

**Moving and resizing, in one paragraph:** while the box is unlocked, drag the
tab strip — anywhere on it, including past the last tab — to move it, or hold
ALT and drag anywhere on it. Drop it near a screen edge, a screen centre line or
another edge and it snaps flush. To resize, drag any of the four corner handles;
the opposite corner stays put. Both gestures save immediately and sync to your
other characters. `/dchat lock` freezes all of it; `/dchat unlock` gives it back.

Foundation, and the work the drawn window is built on top of:

- Repo skeleton, module lifecycle, `/dchat` slash surface with an extensible
  `debug` subcommand registry, additive-and-healing SavedVariables init.
- Suite-themed chat skin: token-driven window backdrops and tab styling, themed
  attached edit box, Core font roles applied to every window, configurable text
  fading, and a per-window copy-chat affordance (era has no clipboard; the copy
  window pre-selects the text for Ctrl+C).
- **Channel-colored tabs.** Each chat tab is inked by the channel that window is
  actually for: a guild window's tab in guild-chat green, a single-channel
  window's tab in that channel's color, the combat log in its own muted
  treatment. Dominance is strict — a window earns a color only when its routing
  (message groups and channels, from the shared config) collapses to exactly one
  identity, so the busy default window keeps the standard treatment. The colors
  are the *game's own* chat colors, read live, so they follow your color settings
  and update the moment you change one. The selected tab wears its color at full
  strength under an accent underline; the rest are dimmed.
- **Timestamp divider.** With timestamps on, a subtle hairline separates the
  stamp column from the message text. It measures the real width of your chosen
  stamp format, and it is absent whenever timestamps are.
- **Colored channel prefix in the edit box.** The attached input's sticky-channel
  label ("Guild:", "2. World:") wears that channel's color and keeps up with a
  color change made while the box is open.
- **Icon rail (off by default).** An optional slim strip on a window's left edge
  with three affordances Chat already has: copy chat, settings, and jump to the
  newest line. Nothing new hides behind them.
- Every one of the four is a separate switch under `/dchat debug skin`; turning
  the tab colors off restores the previous look exactly.
- **Move a window without an edit mode.** Hold ALT and drag anywhere on a chat
  window to move it — no unlocking, no tab-dragging, no mode. A docked window
  moves the whole dock, which is the only move the game keeps. Let go and the
  new position is saved into the shared configuration and synced, so every
  character and account lands there too. Plain clicks are untouched: chat text,
  links and scrolling behave exactly as they always did. If you would rather not
  hold a key, `/dchat unlock` lets a plain drag move the windows for the rest of
  the session and `/dchat lock` puts it back.
- **The edit box can stay put.** On by default: the input bar rests at its
  configured position all the time, showing which channel you are about to talk
  in ("Say:", "Guild:") in that channel's color, quiet until you use it. Click it
  or press Enter to type; Escape stops typing without making the bar disappear.
  Turn it off and the box behaves exactly like the game's own again.
- **Window positions now travel between accounts correctly.** Positions are
  stored as a fraction of the screen rather than as raw offsets, and are applied
  through each account's own UI scale, so one configuration puts the window in
  the same place on every account and every character — even when the accounts
  quietly disagree about scale. Because the addon places windows directly, a
  position saved flush against the screen edge lands flush everywhere, including
  on an account where dragging one there is impossible.
- **Chat windows can be dragged all the way to the screen edge.** The margin the
  game holds windows away from the edge with is loosened on the managed windows
  (they stay on screen, they just stop being fenced off it). On by default,
  re-applied whenever the game re-imposes it, and postponed out of combat when
  the game refuses the change.
- **The little button column beside each chat window is gone.** On by default:
  the game's own chat-menu and scroll-button strip — the small square column
  that sits on the left of your chat window on one account and on the right on
  another, because the game moves it depending on where the window is — is
  hidden and stays hidden. It was also the last thing stopping a window from
  being dragged flush to the screen edge: its width has to fit on screen too,
  so it ate the final stretch even after the edge margin was loosened. Nothing
  is lost: the jump-to-newest button lives on the icon rail, the input bar
  already shows the channel you are about to talk in, and the game's chat menu
  (languages, emotes, whisper targets) is still one click away — on the icon
  rail, or by right-clicking the channel label on the input bar. Turn the
  option off and the game's column comes straight back, side-switching and all.
- **A settings window.** Chat now has a page in the Daseeki settings window
  alongside the rest of the suite (`/dchat options`, or open the Daseeki window
  and pick Chat). Everything that was only reachable as a slash command is a
  control now, in nine groups: Appearance (the one-box layout, channel-colored
  tabs, the timestamp divider, the colored edit-box prefix, the icon rail, the
  game's button column, the copy button, text fading and its delay), Tabs (where
  the tabs sit, and a row per window), Timestamps (on/off, four formats,
  server time, what to do when the game's own timestamps are on, stamp color),
  Names (class coloring, brackets, remembering classes between sessions), Links
  (detection, brackets), History (on/off, lines kept, how old is too old),
  Unread badges (on/off, clearing a group filter), Windows (the persistent edit
  box and where it sits, ALT-drag, reaching the screen edge, the session unlock,
  plus the reconciler's live status and a **Reconcile now** button), and Channel
  names. Every change applies live; nothing needs a reload.
- **Custom channel names.** Give a channel your own short name and chat uses it
  everywhere: `[2. Trade - City]` becomes `[Trade]` in every chat line, on the
  input bar's channel label when you are talking there, and on a tab that
  belongs to that channel. One name, all three places. Channel links keep
  working exactly as before — only the words you see change, and the game's own
  click target is untouched down to the byte. Names are matched however they are
  capitalized and are remembered by NAME rather than by number, because channel
  numbers differ between characters and shift as you join and leave. Aliases are
  account-wide and travel with the rest of your chat configuration to every
  account on the mesh. The editor lists the channels you are in (and any you
  have already named), with a row to add one you are not in right now; clear a
  box to go back to the game's own name. There is one switch for whether the
  number is kept — `[2. Trade]` — and it ships off, so the default is the clean
  short name.
- **The button column is disabled, not just hidden.** With the option on (still
  the default) the game's chat button strip loses its mouse — the column frame
  and every button in it — so there is no invisible hitbox left beside your chat
  window for a stray click to find, and any event registrations those buttons
  held are dropped too. Turning the option off restores the mouse on every one
  of them exactly as the game had it; the dropped event registrations cannot be
  put back (the game gives no way to list what a frame was listening for), so
  the restore says so in one line and names `/reload` as the exact fix rather
  than pretending to be complete.
- **One box: tabs, text and input on a single surface.** On by default. A chat
  window is now drawn as one panel — the tab strip, the messages and the input
  bar all share it. The strip sits on the darker chassis tone and the messages
  and input bar on the lighter one, exactly as the design does; the input bar's
  own panel is gone, the tab strip has none of its own, and a docked group of
  windows wears *one* box rather than one per tab. Text fading is off inside the
  box, because a box that is always there
  with text that comes and goes is the worst of both; your fading setting is
  remembered rather than rewritten, and the settings page says so out loud.
  Turning the option off gives the previous look back exactly, fading included.
- **Choose where your tabs sit: top, left or right.** Top is a strip along the
  box's upper edge, and the tab you are reading merges into the message surface —
  it is painted in the surface's own color, so there is nothing at all between
  them — with a colored underline beneath it. Left and right put the tabs on a slim vertical
  rail inside that edge, which reads far better once you have several of them and
  leaves the full width for message text; the tab you are reading is marked by a
  colored bar on the rail's inner edge. The tabs are the game's own tab buttons,
  moved rather than replaced, so clicking, dragging a window out of the dock and
  right-clicking a tab all behave exactly as they always did. Unread counts move
  with the tabs: a small pip beside a top tab, a right-aligned number inside a
  rail row (the pip is a small red chip on the tab itself). The icon rail, if
  you use it, takes the opposite edge automatically.
  Placement is part of your shared chat configuration — set it once on any
  character and every character on every account lands there.
- **A color per tab.** Any window's tab can be given a color of your own instead
  of the one it derives: a suite theme color, or one of the game's own chat
  colors. It is stored as *which* color, never as a fixed value, so a theme
  change or a chat-color change still moves it. Leave it on Automatic and nothing
  changes — the tab keeps deriving its channel's color as before. Tab colors ride
  the shared configuration alongside that window's routing, and survive dragging
  or resizing the window.
- **The box now matches the mockups.** The first cut of the one box shipped a
  long way from the design that was approved, and this is the honest list of
  what was wrong. The **tab you are reading was a filled block** — the game's
  own chat-tab artwork was never taken down, so every tab kept wearing it; in
  the design the active tab has no fill of its own, it wears the *message
  surface's* color so the two read as one piece, and the inactive tabs are the
  channel's color dimmed with no fill at all. The **whole window was one flat
  tone and read as pure black** — there are two tones in the design, a darker
  chassis behind the tab strip and a lighter one behind the messages and the
  input bar, and the panel was also being drawn slightly see-through. There was
  **no breathing room anywhere**: text sat against the edges, tabs against each
  other, the input bar against the text. Every measurement in the design is now
  applied literally — 14 either side of the message text and 10 above it, tab
  padding, strip padding, a little air between lines, and 8/12 inside the input
  bar. The **timestamp divider never appeared**; see the next entry. The
  **copy button was the loudest thing on the window** and is now a quiet glyph
  at the far end of the tab strip, brightening only when you point at it. The
  **unread count floated in the gap between two tabs** and now rides its own
  tab as a small red chip with white digits, sitting just after the tab's name
  exactly as the design draws it — the tab widens to hold it. Where the game
  simply cannot do what the design shows, it is written down rather than faked:
  rounded corners, letter spacing, tabular figures and the drop shadow all have
  a named reason in the mapping table at the top of `skin.lua`, which lists
  every value in the design beside the value that shipped. Turning the box off
  is still the previous look, exactly.
- **The timestamp divider actually draws now.** Two separate faults kept it
  away. It hung off the window's panel, and in the one box a docked window that
  is not the group's host has *no* panel of its own — so on every tab except the
  first, the hairline was drawn onto something invisible. And nothing ever
  re-asked whether timestamps were on: turning them on from the settings page
  moved the answer and told the skin nothing, so the line stayed away until
  something unrelated happened to redraw. The hairline belongs to the message
  window now, and timestamps ring the skin's bell when they come and go. It is
  also drawn the way the design draws it — a thin line in the soft border color,
  centred in the gap between the time and the message.
- **Timestamps are bare by default.** `17:16`, not `[17:16]`, in the design's
  faint ink, with the hairline doing the separating. If you prefer the brackets
  there is now a switch for them under **Timestamps**.
- **A row per chat window in the settings page.** A new **Tabs** group carries
  the tab position and, under it, one row for each of your ten chat windows:
  its color, and whether that window counts unread lines, gets timestamps, and
  keeps its lines across a logout. Those three per-window switches existed in the
  configuration but had no control anywhere until now.
- **`/dchat debug position`** prints everything that decides where a window
  lands: the scale chain, the screen's size in both units and pixels, the clamp
  state and margins, the game's saved position, the live position, and the saved
  fraction. Run it on two accounts and the diff names whatever differs between
  them.
- **A window you drag to the edge stays at the edge.** Dropping a window flush
  against the screen no longer has it walk back inward a moment later. Two
  separate things were putting it back and both are fixed: the game rewrites the
  margin it fences windows away from the edge with every time it re-decides
  which side the little button column belongs on, and it re-places a window from
  its own saved position on its own beats — a position an ALT-drag had never
  told it about. Now the loosened margin is retaken inside the very same call
  the game rewrites it in (deferred and replayed if you are in combat), and a
  drop is committed through the game's own save so its next tidy-up agrees with
  where you actually put the window.
- **Snap to edges when dragging.** On by default. Drop a chat window near a
  screen edge, a screen centre line or another chat window's edge and it lands
  *on* it exactly — including flush at the very edge, which is what "align it
  with the left of my screen" was always asking for. While you drag, a thin
  accent line shows the boundary it is about to line up with, and it disappears
  the moment you let go. The drag itself is untouched and stays as smooth as the
  game's own; only the landing is corrected. Turn it off in the settings page
  and a near-miss stays a near-miss.
- **Every way of moving a window now reaches the shared configuration.** Moving
  a window by dragging its tab — the game's own way, which Chat deliberately
  never took away — is captured back exactly like an ALT-drag, as is dropping a
  tab onto the dock or tearing one off it. Previously a move the configuration
  never learned about would simply be undone by the next reconcile.
- **`/dchat debug reconcile` now opens with a one-line verdict**: *last position
  change: user move captured @…* or *drift corrected to config @…*. If a window
  ever moves when you did not move it, that line names who did it, and the trace
  below says which window and from where to where.
- **The chat tabs stop fading.** In the one box, the tab strip no longer dims
  when the pointer is elsewhere. Turning message fading off had never covered
  this: the game fades a chat *tab* with a completely separate mechanism from
  the one that fades chat *text*. Chat now neutralises that mechanism and holds
  the last word against it — at no cost when nothing has changed — and hands it
  straight back the moment the box is turned off or the module is disabled.
- **Thinner tabs and input bar, and no more dead margin beside the text.** The
  tab strip and the input row are snug around what they actually contain
  (the strip is 26 units tall instead of 35, the input row 26 instead of 36),
  and the empty panel between the message text and the left and right edges of
  the box is gone. Unread-count pips still sit centred in the thinner tab.
- **The feed breathes.** Messages are set at the design's own size with the
  spacing its line height asks for, computed from whatever size is in force
  rather than frozen at one number, so lines no longer touch. Both are settings;
  putting the size back to 0 hands the game's own right-click *Font size* menu
  the authority again, exactly as before.
- The headless harness with the unkind chat simulator: the 10-window client
  model, async server-gated channel joins, mutable per-frame ring buffers with
  uptime stamps, GUID-carrying era message events, the edit box's sticky-channel
  header beat, real frame geometry with a clamped drag and an unclamped
  programmatic placement, a drivable UI scale, the edit box's own show/hide
  machinery under both chat styles, the per-window button column with the
  game's own side-flipping and its share of the drag footprint, a real pointer
  (including a hit test that answers whether a click reaches through a disabled
  frame to what is behind it), a recording model of the Daseeki settings hub so
  the settings page is really built and every control really driven under test,
  and call counting throughout. It now also models the things that made the two
  live defects above invisible headless: a client that actively fades tabs on
  its own beat, a clamp margin the client rewrites and then enforces on its next
  layout pass, a saved position the client restores from without being asked,
  and a native tab-drop in two postures — one that passes through the obvious
  hookable names and one that does the same work through the client's own
  internal references, so a capture layer that bets on the obvious names fails
  the test instead of the player.
