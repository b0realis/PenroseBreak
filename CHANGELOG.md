# Changelog

## v1.15 — 2026-10-11

Public release:

- **Free software: GPL-3.0-or-later** (was MIT). Source code at
  github.com/b0realis/PenroseBreak.
- **Release packages for six targets:**
  - Linux x86-64
  - Steam Deck / SteamOS
  - Raspberry Pi 5 (64-bit ARM)
  - Windows 10/11
  - macOS (universal, unsigned)
  - Web (phones included)

  Each comes as a ready-to-run folder with a `README.txt` (start steps
  and controls), the `LICENSE` and the Godot Engine's third-party
  notices, plus `SHA256SUMS`. `dist/package_release.sh` builds them all
  and smoke-tests the shipped Linux binary: a boot plus the end-to-end
  touch and gamepad menu checks.
- **Steam Deck:** the launcher starts full screen until you change it in
  OPTIONS, at the Deck's 1280×800 and 60 fps. The on-screen touch buttons
  stay away on a handheld with real controls; menus still take taps.
- **Raspberry Pi 5:** the launcher runs on OpenGL ES 3.
- **`--fullscreen` / `-f` on the command line is honoured** (the saved
  window setting used to undo it at once).

## v1.14 — 2026-10-10

Bug-hunt campaign: two independent code reviews, every finding verified
by repro before fixing:

- **Fixed: the stopwatch ran fast in Block Classic and hardened Penrose.**
  Each 5-hit kill added about 0.1 s of phantom time: the kill's hit-stop
  changed the time scale mid-frame, and the clock divided that frame's
  already-scaled delta by the new value. That's roughly +5 s on a Classic
  clear, and the hardened competition countdown ended early by the same
  amount. The clock now counts physics ticks, which keep real-time pace
  under any slow-mo, and competition rounds end on the exact tick.
  Classic and hardened records set before v1.14 are slower than the runs
  that earned them, so expect to beat them.
- **Fixed: the paddle could crush the ball out of the arena.** Pinning the
  paddle against a rail with the ball beside it (holding a key, or
  flinging the mouse to the edge) could squeeze the ball through the thin
  rail line. It then fell forever, and the run could never finish. Rails
  and floor are now solid half-planes, a ball squeezed at a rail pops out
  vertically, and a final clamp keeps it inside. The side swat elsewhere
  plays exactly as before.
- **Fixed: inputs leaked past the end of a run.** Space / A / click to
  confirm AGAIN also fired a boost (sound, shake, ring, rumble). Paddle
  hits behind the overlay slammed the screen. The AGAIN button was
  clickable while still invisible during the overlay's fade-in, so the
  click meant as a boost when the last block died could restart before
  you saw your time. All three are gone.
- **Touch fixes:**
  - Trying to drag-scroll OPTIONS toggled the row your finger started on,
    because taps fired on touch-down. Two drags starting on Reset wiped
    all records. Taps now fire on release, and only if the finger
    stayed put.
  - Drag-scrolling never worked when the drag started on a row: Godot
    swallowed it.
  - Rows scrolled out of view were still tappable.
  - A tap during the splash hit the invisible menu underneath (QUIT
    included), and touch couldn't skip the splash.
  - A thumb still on ◀ / ▶ when the run restarted kept the paddle sliding
    into the next run.
  - Toggles fired twice per tap (double blip).
  - Slow drags lost their fractional pixels and barely scrolled.
- **Controller: the name field is reachable** (the column used to wrap
  from START straight to QUIT, so pad players were always ANON).
- **Web: no dead QUIT buttons.** A browser tab can't close itself, so
  QUIT only froze the page; it's hidden there now.
- **Saves are flushed when the app goes to the background**, since a
  discarded mobile tab never says goodbye.
- **Random-deal fields are unranked.** They range from 30 to 194 tiles
  (measured over 1000 deals), so their times don't compare with the
  constant 141-tile field. They now show "RANDOM DEAL — UNRANKED" instead
  of landing in the record slots, and OPTIONS says so.
- The screen shake's small rotation now actually applies. Camera2D
  ignores its own rotation by default, which had silently dropped it.
- **Test harness:**
  - `--autotest-winclick` could pass without a real reload (or loop
    forever with touch).
  - Competition and `--autotest-fast` runs now have to prove their
    result.
  - `tools/robustness.sh` gained a parse gate (headless Godot idles on a
    parse error instead of exiting), requires each hook's OK line, and
    picks a memory-aware number of parallel runs (22 at once had
    exhausted the machine).
  - New regression steps cover each fix above.

## v1.13 — 2026-10-10

Robustness campaign:

- **Fixed (found by the chaos fuzzer): a mouse button held on a menu
  button fired it when the menu closed.** Hold the mouse down on QUIT
  GAME, MAIN MENU or RESTART, then resume with Esc / B / Start, and that
  button fired anyway: the game quit or the run ended. Godot synthesizes
  a release on a control that is hidden while a mouse button holds it.
  The same applied to OPTIONS toggles and Reset when the panel was closed
  with Esc / B. Menus now disarm their buttons before hiding.
  `--inputtest` and `--padtest` check both cases.
- **Fixed: a corrupted or hand-edited save could break the game.** One
  wrong-typed value (say `field_constant="yes"`) raised inside the
  loader, aborting it with saving silently disabled for the whole
  session, so new records were lost. A malformed record broke the arena's
  HUD build (no boost bar, script errors every frame). Every value is now
  read typed and range-checked: bad types, inf/nan/negative numbers and
  malformed records fall back to defaults, and names are clipped to 16
  characters.
- **Unreadable saves are preserved.** If the save file can't be parsed
  (a typo in a hand edit, a truncated write), it's copied to
  `penrosebreak.cfg.bad` before the next save overwrites it, so the
  records can be repaired and restored.
- **Test runner, `tools/robustness.sh`.** One command runs every check
  headless and in parallel. Each run gets its own throwaway data
  directory, so tests can never touch your records. `--quick` is the
  18-check regression suite (~10 s); the full campaign takes 2–3 min.
- **New robustness checks** (see docs/CLI.md):
  - long soak runs at ~30× real time (`--autotest-soak`) across every
    mode, tile regime and deal, at 30/60/240 fps, with replayable seeds;
  - stricter bot invariants: ball never lodged in a tile or the paddle,
    bounded speed and node count, tile bookkeeping, slow-mo recovery,
    regular wall contact;
  - `--fieldtest`: tiling and wall-carving validator, 1000 deals;
  - `--cycletest`: menu ↔ arena leak check;
  - `--chaos`: seeded fuzzer of keys, pad, mouse and touch through every
    scene, checking for soft-locks;
  - `--uitour`: opens every panel, run against corrupted saves.
- Smarter test bot: it aims at the most exposed tile and re-targets when
  stuck. A soak found it fixated on a corner sliver half hidden behind a
  rail.

Campaign results: 12+ game-hours of soak per full run, 1000 tiling deals,
200 menu↔arena cycles and thousands of random inputs. No crashes,
soft-locks, lodged balls or leaks across scenes. The constant field is
still exactly 141 tiles.

## v1.12 — 2026-10-10

Controller support + finger steering:

- **Full gamepad support.** Left stick steers the paddle analog (tilt
  scales speed, 0.2 deadzone), the d-pad steers digitally, A / RB / RT
  launch and boost, Start pauses (B or Start resumes), Back / View
  restarts. Any controller works, including a second one.
- **Menus answer a controller.** Godot's built-in accept/cancel carry no
  pad buttons, so a controller could move focus but never press
  anything. A now chooses and B backs out of OPTIONS, TOP SCORES and the
  pause menu.
- **Rumble** on paddle slams, boosts, kills and the finale, scaled like
  the screen shake. Only while a pad is in hand; OPTIONS → "Controller
  rumble" turns it off.
- **Finger steering + tap-to-launch.** On touch hardware the whole
  screen is now a steering pad: drag anywhere off the buttons and the
  paddle follows your finger like a mouse; a quick tap launches a parked
  ball. The ◀ ▶ ⚡ ⏸ buttons stay; ⚡ is still the boost.
- **Prompts follow your device.** The launch hint and the boost tag in
  the arena switch between keyboard, controller and touch wording as soon
  as you pick another device up. OPTIONS → HOW TO PLAY now lists keys and
  controller side by side, with a touch summary.
- **P pauses** too (alongside Esc).
- New dev checks: `--padtest` (the menu driven by a controller alone) and
  `--inputtest` (every gameplay input end to end; add `--touchui` for the
  finger path). See docs/CLI.md.

## v1.11 — 2026-10-10

End-of-round fixes + an honest test bot:

- **Fixed: competition rounds kept scoring after TIME!** The ball flew on
  behind the results overlay, still bursting tiles (with sound and
  shake) while the HUD tile counter climbed past the recorded score.
  Once a round ends, the surviving tiles act as wall: the ball just
  thuds off them and the counter stays frozen at the result.
- **Fixed: the win slow-mo was cut short in Block Classic and hardened
  Penrose.** The last block's own 0.05 s kill freeze restored full speed
  mid-way through the 0.45 s finale. Overlapping hit-stops now let the
  one ending last own the restore.
- **Fixed: a failed smoke test could still exit 0.** The "no block was
  destroyed in 40 s" check fell through to the success exit in the same
  tick, so `--autotest-classic` reported a pass while printing FAIL. Any
  failure now stops the bot immediately and keeps exit code 1.
- **The bot now boosts out of stalls.** A ball cruising on a shallow arc
  can bounce off the flat classic wall forever, peaking short of the
  paddle; about 1 in 4 classic bot runs used to sit in that loop for the
  whole 40 s. Like a human, the bot now taps Space (via the real input
  path) when the ball has neither touched the paddle nor broken anything
  for 3 s and is low and rising. The ball physics are unchanged.
- Version strings synced: `project.godot` and the macOS export preset
  had drifted to 1.9 / 1.6.

## v1.10 — 2026-07-29

Menu polish + a mode quick-switch:

- **Best line centered.** The record line under the menu buttons lived
  inside the right-hugging column and long records (mode · regime ·
  time · name) clipped off the edge. It is now a full-width,
  screen-centered label above the version footer, hidden while the
  OPTIONS / TOP SCORES panels are open.
- **"PLAYER NAME" caption** above the name field, so the first box in
  the menu explains itself before you click it.
- **Mode quick-switch in the main menu**: a `‹ PENROSE ›` cycler button
  right under START flips between Penrose / Block Classic / Penrose
  Competition without a trip into OPTIONS. It is the same cycle as the
  OPTIONS button and the two stay in sync (both funnel through
  `Game.changed`); the best line follows the selected mode instantly.

## v1.9 — 2026-07-28

Win-overlay hardening + a color home button:

- **Fixed: hidden overlay widgets could swallow taps.** Godot's
  `is_visible_in_tree()` ignores CanvasLayer visibility, so on touch
  hardware the INVISIBLE pause menu's buttons counted as tappable
  mid-game and around the win overlay — stealing taps (and playing
  phantom UI blips). The TapCatcher now checks every CanvasLayer ancestor
  explicitly.
- **New regression test `--autotest-winclick`**: after the win, injects a
  real click (or a raw touch with `--touchui`) on the AGAIN button and
  requires the arena to reload — the win overlay's buttons are now
  verified end-to-end on both input paths, forever.
- **"Default turquoise" button** under the tile color rows: one tap
  restores the house look — light turquoise thin tiles over dark thick —
  and syncs the pickers/swatches.

## v1.8 — 2026-07-28

Fair scores, mobile colors:

- **Records split by breaking regime.** A one-shot clear and a hardened
  clear are different sports, so penrose clear times and every
  competition frame now keep separate one-shot / hardened slots. TOP
  SCORES shows both (competition as a two-column table); the menu best
  line and in-arena HUD follow the regime you have selected. Existing
  records migrate to the hardened slots — they were earned in the
  hardened era.
- **Tap-for-random tile colors on mobile.** The color-picker popup wants
  a mouse, so on touch hardware the swatch rolls a fresh random color on
  every tap instead (random hue, tasteful saturation/brightness). Desktop
  keeps the full picker; the choice persists either way.

## v1.7 — 2026-07-28

Tile feel, tile colors, and a menu that fits:

- **One-shot tile breaking** (OPTIONS → PENROSE TILES, the new default):
  in the Penrose modes any contact bursts the tile — with a **mini light
  pop** (an additive glow bloom in the tile's own color, small ring,
  gentle shake, no hit-stop) instead of the full kill spectacle, which
  would exhaust at one-kill-per-hit pace. **Hardened** keeps the classic
  five-hit Block ladder. Autotests pin one-shot for comparable runs.
- **Prototile colors**: two color pickers — thin rhombi and thick rhombi —
  tint the fresh field however you like (defaults: the familiar turquoise
  and a deeper cousin, so the two tile shapes read at a glance). Death
  bursts and light pops follow the picked color; hardened tiles still
  climb the standard damage ladder once hit.
- **Options panel scrolls.** The panel had outgrown the screen and
  clipped; its content now lives in a fixed-size scroll area — mouse
  wheel / focus-follow on desktop, finger drag on touch (TapCatcher
  gained drag-scrolling, since Godot's own GUI touch panning never fires
  with mouse emulation off).

## v1.6 — 2026-07-28

**All-platform builds.** Four release targets, exported from the same
tree: Linux x86_64 (`build/PenroseBreak.x86_64`, embedded pack), Windows
x86_64 (`build/PenroseBreak-windows-x86_64.exe`, embedded pack, no
resource modification so no rcedit needed), macOS universal
(`build/PenroseBreak-macos.zip`, unsigned — right-click → Open on first
launch), and Web (`build/web/`, the mobile build). Presets follow the
studio's export conventions; the macOS bundle is
`com.prescriptiongames.penrosebreak` with the studio copyright line.

## v1.5 — 2026-07-28

**Mobile ready** — touch controls and tilt steering, the studio's way
(NO mouse emulation; `emulate_mouse_from_touch` is off, so a touch can
never teleport the paddle through the mouse path or ghost-click menus):

- **Touch gameplay** (`scripts/touch_controls.gd`, appears only on touch
  hardware or with `--touchui`): vector-drawn multitouch buttons that
  synthesize the same input actions the keyboard uses — ◀ ▶ hold to move,
  ⚡ to launch/boost, ⏸ to pause. Paddle and ball logic run unchanged.
- **Touch menus**: raw-touch tap handling for every Button / CheckBox /
  LineEdit (TapCatcher — Godot's GUI ignores ScreenTouch while mouse
  emulation is off, verified by the new `--touchtest` hook, which taps
  START through the real input pipeline headlessly). Tap the name field
  to raise the virtual keyboard; tap or press anything to skip the splash.
- **Tilt steering** (OPTIONS → "Tilt control (mobile)", persisted): steer
  the paddle by leaning the phone — gravity-sensor analog control, ~19°
  for full speed, deadzone so a resting phone stays still; silently
  inactive without a sensor. The ◀ ▶ buttons hide while tilt is working;
  ⚡ and ⏸ remain.
- **Web export preset** (`build/web/`): the mobile delivery — landscape
  (sensor, both directions), no threads (plain static hosting works),
  experimental virtual keyboard on for name entry.

## v1.4 — 2026-07-28

The tiling, perfected:

- **Fixed: the deflation rule's mirror orientation.** The original child
  orderings conserved area and shape (all verified) but flipped chirality,
  so ~55% of triangles had no twin across their diagonal — outlines drew
  fine, but the tiling couldn't be decomposed into rhombi, and the
  breakable field came out half-empty ("not tiled"). Re-searched the 32
  orderings with a new pairing-completeness check (docs/PENROSE.md): 100%
  of interior triangles now pair, on both seeds (the thick-rhombus seed's
  twin needed the same b,c order too).
- **Gap-free field.** Tiles join the wall by area overlap instead of
  center point: ≥ 30% inside the strip — or ANY overlap for tiles that sit
  fully inside the arena (a tile crossing only the strip's top line is
  completely reachable; dropping it just punched a notch). The wall now
  tiles the bottom quarter wall-to-wall.
- **Constant / random field** (OPTIONS, persisted, default constant): the
  constant setting deals the exact same 141-tile field every run from a
  fixed seed — ⌊2³²/φ⌋, the golden ratio seeding the golden-ratio tiling —
  for reproducible speedruns and fair competitions; switch it off for a
  fresh aperiodic patch per run.
- **Menu snow matches the vista**: the falling rhombi now share the
  backdrop tiling's exact edge length (fewer flakes when the deal is
  chunky) — the vista's own prototiles adrift.

## v1.3 — 2026-07-28

The game grows into its name: **Penrose game modes**.

- **Three game modes** (OPTIONS → GAME MODE, persisted):
  - **Block Classic** — the original 4×10 rectangle wall, clear it fast;
  - **Penrose** — the NEW DEFAULT. The backdrop tiling itself becomes the
    wall: rhombi landing in the bottom quarter of the screen turn into
    breakable tiles with the exact block damage ladder (turquoise → green
    → yellow → blue → armed white → burst); the upper three quarters stay
    scenery. The vista freezes so a destroyed tile forever reveals its
    dim ghost beneath;
  - **Penrose Competition** — the Penrose field against a countdown:
    break as many tiles as the clock allows. Round length cycles through
    30s / 1min / 2min / 5min / 10min (persisted); the HUD counts down and
    tallies broken tiles; ending early by clearing the whole field counts
    as glory ("FIELD CLEARED").
- **Top Scores** menu entry: classic and penrose best times plus the
  competition table (best tiles per round length), all on one overlay.
  Records live in separate slots per mode (and per competition frame);
  the menu's best line follows the selected mode; "Reset best time"
  became "Reset all records".
- **PenroseTile** (`scripts/penrose_tile.gd`): a Block subclass with a
  convex-polygon body lifted verbatim from the backdrop generator — the
  ball, reactions, sparks, armed pulse and scoring all Just Work.
- **Autotest matrix**: plain `--autotest` now exercises the Penrose field;
  `--autotest-classic` pins the rectangle wall, `--autotest-comp` runs a
  real 30 s competition round; `--autotest-fast` picks the most exposed
  survivor so the win path is reachable on any random field.

## v1.2 — 2026-07-28

THE BLOCK is now **PENROSE BREAK** — named for the tiling it plays on.

- **Renamed everything**: project (`config/name`), folder
  (`PROJECTS/PenroseBreak`), export binary (`build/PenroseBreak.x86_64`),
  save file (`user://penrosebreak.cfg`, section `[penrosebreak]`; existing
  records migrate by copying the old file over with the section header
  renamed), docs and logo/icon annotations.
- **New wordmark + tagline.** The menu title reads "PenroseBreak" in the
  same simple style as before; the tagline is now "Aperiodic tiling
  countdown."
- **Menu facelift.** The logo art is gone from above the title (the SVG
  stays in the repo); in its place the whole menu gets **Penrose tile
  snow** — sparse lone rhombi (both P3 prototiles) in the block damage
  colors, drifting down with a lazy sway and spin. Also fixed the menu's
  legibility wash, which sat on CanvasLayer −1 *behind* the tiling and
  never actually showed.
- **MIT license** added (the studio byline shared with its other
  releases). Superseded by GPL-3.0-or-later in v1.15.

## v1.1 — 2026-07-16

Gameplay, from playtest feedback:

- **Paddle faces specialized.** Bottom face = the cannon (unchanged). Side
  faces now shove with real energy (×1.08 + 90, inheriting up to ±420 of
  the paddle's swing). Top face = soft dampened bounce (0.45) — fixes the
  high-frequency ricochet frenzy where any contact re-slammed the ball
  *into* the paddle with full shake each collision.
- **Boost.** Space mid-flight adds +460 speed along the heading, 2.5 s
  cooldown, HUD charge bar under the stopwatch; the ball's halo burns
  **magenta** while it fires (plus magenta shockwave ring). The escape
  hatch for a ball dawdling in the block field.
- **Wall rebalanced.** 4 rows (was 5); damage ladder recolored for
  readability: turquoise → green → yellow → blue → **white** (armed,
  breathing) → burst on the next impact. 5 hits per block.
- **Esc fixed.** The pause overlay's always-on Esc listener consumed every
  press before main could see it — pause could never open. It now only
  acts (and consumes) while actually paused; the autotest injects real Esc
  events to verify the round-trip forever after.
- **Pause menu** gained QUIT GAME (now: resume / restart / main menu /
  quit).
- **Options panel** in the main menu: Sound FX / Screen shake / Fullscreen
  toggles (persisted), full controls reference, two-click record reset.
- **Menu relayout**: logo + wordmark on the left, menu column bottom-right,
  version bottom-left; "a Prescription Games production" footer removed
  (the studio keeps the splash).
- **New logo** (`logo_bounce.svg`): the breadbin computer as the paddle
  slamming its CRT television — the glowing ball — downward; the TV screen
  replays the game itself. Floats on a slow bob in the menu.

## v1.0 — 2026-07-16

Initial release, built on the studio's shared reusables (see docs/CREDITS.md):

- Inverted block breaker: paddle on top, 5×10 turquoise wall on the floor,
  gentle in-arena gravity vs. heavy off-screen gravity, side rails extended
  3200 px above the camera so the ball is never lost.
- Power model: paddle slams boost speed (decaying back toward cruise),
  block bounces add a kick; offset + english + jitter aiming.
- Speedrun stopwatch (starts at launch, honest through hit-stop), best
  time + name persisted and shown in menu/HUD.
- Full juice pass: trauma screen shake (randomized per block contact),
  hit-stop on kills, shockwave rings, spark bursts, world flash, light
  trail + smoke, glow-layered ball, procedural synth SFX (no audio files).
- P3 Penrose tiling backdrop with numerically verified deflation rule;
  random seed/depth/rotation/style per run.
- Prescription Games caduceus splash → menu (player name, START, QUIT,
  best); pause overlay; win overlay with record handling.
- Dev CLI: `--autotest` bot with invariant checks, `--autotest-fast`
  win-path test, `--shot` screenshot hook; Linux x86_64 export preset.
- Fixed during hardening: double-`destroyed` emission when a dying block
  was grazed twice in one physics tick; stopwatch counting scaled time
  during hit-stop.
