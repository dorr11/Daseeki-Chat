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
  bar all share it, separated by thin lines and nothing else. There is no second
  background anywhere in it: the input bar's own panel is gone, the tab strip has
  none of its own, and a docked group of windows wears *one* box rather than one
  per tab. Text fading is off inside the box, because a box that is always there
  with text that comes and goes is the worst of both; your fading setting is
  remembered rather than rewritten, and the settings page says so out loud.
  Turning the option off gives the previous look back exactly, fading included.
- **Choose where your tabs sit: top, left or right.** Top is a strip along the
  box's upper edge, and the tab you are reading merges into the message surface —
  the dividing line stops at its edges and picks up again on the other side — with
  a colored underline beneath it. Left and right put the tabs on a slim vertical
  rail inside that edge, which reads far better once you have several of them and
  leaves the full width for message text; the tab you are reading is marked by a
  colored bar on the rail's inner edge. The tabs are the game's own tab buttons,
  moved rather than replaced, so clicking, dragging a window out of the dock and
  right-clicking a tab all behave exactly as they always did. Unread counts move
  with the tabs: a small pip beside a top tab, a right-aligned number inside a
  rail row. The icon rail, if you use it, takes the opposite edge automatically.
  Placement is part of your shared chat configuration — set it once on any
  character and every character on every account lands there.
- **A color per tab.** Any window's tab can be given a color of your own instead
  of the one it derives: a suite theme color, or one of the game's own chat
  colors. It is stored as *which* color, never as a fixed value, so a theme
  change or a chat-color change still moves it. Leave it on Automatic and nothing
  changes — the tab keeps deriving its channel's color as before. Tab colors ride
  the shared configuration alongside that window's routing, and survive dragging
  or resizing the window.
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
  and call counting throughout.
