# Changelog

## Unreleased — first release

Daseeki Chat replaces Prat on this account: a skin-over treatment of the game's
own ten chat windows, drawn in the shared Daseeki look, with one account-spanning
chat configuration that every character — including a brand-new one — reconciles
to automatically at login.

This entry accumulates until 1.0.0 ships. Foundation so far:

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
