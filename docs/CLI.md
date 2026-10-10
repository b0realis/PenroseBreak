# CLI dev hooks

All hooks live after Godot's `--` user-args separator and are inert in
normal play. `godot` below means a Godot 4.7 binary; the scripts in
`tools/` and `dist/` find it as `$GODOT`, else `godot4` / `godot` on PATH,
else a sibling `../godot/Godot_v4*_linux.x86_64`.

## `tools/robustness.sh` — run everything (start here)

```sh
tools/robustness.sh --quick   # regression suite: 18 checks, ~10 s
tools/robustness.sh           # + robustness campaign, ~2–3 min
```

First a parse gate (three short boots that load every script) aborts the
run if anything fails to compile — headless Godot doesn't exit on a parse
error, it idles, so every check would otherwise sit out its timeout. Then
it runs every hook below headless and in parallel, each with its own
throwaway `XDG_DATA_HOME` — so the player's records in
`~/.local/share/godot/app_userdata/PenroseBreak/` are **never touched**
(no backup/restore needed). A check passes only if it exits 0 and prints
no `SCRIPT ERROR` — and a hook run must print its OK / WIN line (exiting
0 without it, e.g. because a stray input hit QUIT, fails). Game-time-heavy runs use Godot's `--fixed-fps 60`,
which plays ~30× faster than real time headless. The full campaign adds:
corrupted / hand-edited save files (garbage, empty, wrong types,
inf/nan/negative/huge values, legacy keys) booted through `--uitour` and
the arena; `--fieldtest 1000`; `--cycletest 100`; a soak matrix (every
mode × one-shot/hardened × constant/random deal, two seeds each, plus
30 fps and 240 fps variants) of `SOAK_S` game seconds (default 1800);
and six `--chaos` lanes of `CHAOS_S` game seconds (default 600; keys/pad/
mouse and touch). Env: `GODOT`, `SOAK_S`, `CHAOS_S`, `JOBS` (default is memory-aware: ~600 MB per run, max 8). Logs are kept
on failure. Running a single hook by hand: prefix
`XDG_DATA_HOME=$(mktemp -d)` to keep records safe the same way.

## `--autotest` — headless smoke / soak bot

```sh
godot --headless res://scenes/main.tscn -- --autotest
```

Runs a 40 s bot game and exits 0/1 (`scripts/dev/autotest.gd`, preloaded
by `main.gd`; it moved out of `main.gd` in v1.13). The bot pins its setup
locally (the player's saved options are never touched): plain
`--autotest` plays the **Penrose field**, one-shot, constant deal; add
`--autotest-classic` for the rectangle wall, or `--autotest-comp` for a
real 30 s competition round (ends via the countdown, records into the
30 s frame). More pins: `--autotest-hardened` (5-hit Penrose tiles),
`--autotest-random` (fresh deal per run). Every run prints its seed;
`--autotest-seed <n>` replays it exactly (pair with `--fixed-fps 60`
for frame-exact determinism). `--autotest-soak <s>` keeps playing —
reloading the arena after every win / round — until s game seconds have
passed, then prints a `SOAK OK` line (runs, wins, tiles, boosts, max
speed, max node count). The bot:

- launches the ball at t = 0.5 s;
- **aims**: parks the paddle off-center so the deflect angle steers the
  ball toward the most exposed tile (highest up, then nearest); after 8 s
  without any wall contact it aims at a random tile instead, so a
  corner sliver half behind a rail can't trap its aim (a v1.13 soak found
  exactly that);
- **dodges**: when the ball is overhead it steps aside so the ball can fall
  past the paddle, like a human would;
- **boosts out of stalls**: a cruising ball on a shallow arc can bounce off
  the flat classic wall forever, peaking short of the paddle. When the
  ball has neither touched the paddle nor broken anything for 3 s (a ball
  rolling through one-shot tiles is busy, not stalled) and is low
  (y > 360) and rising, the bot taps the `launch` action through the
  input pipeline (the Space boost) once it's charged. The boost count is
  in the final summary;
- **verifies Esc end-to-end** at t = 2.0–2.4 s: injects real Escape key
  events through the input pipeline, asserts the tree pauses, injects
  again, asserts it resumes (this is what caught the event-consumption bug
  in v1.1);
- watches invariants every tick: ball position finite, never outside the
  rails sideways, never below the floor or above the rail tops, speed
  ≤ 1600; the ball's core never lodged inside a live tile or the paddle
  for more than 10 ticks; `_blocks_left` equals the live tiles in the tree;
  the arena's node count bounded (transient fx); `Engine.time_scale` back
  to 1 within 150 frames of any hit-stop; some wall contact at least
  once every 60 s;
- prints a status line every 5 s and a final summary; fails if nothing was
  destroyed in 40 s.

Any failure stops the bot at once and exits 1. (Before v1.11 the "nothing
destroyed" check fell through to `quit(0)` in the same tick and the later
call won: the log said FAIL but the exit code said pass.)

## `--autotest-fast` — win-path test

```sh
godot --headless res://scenes/main.tscn -- --autotest --autotest-fast
```

Same bot, but at t = 1.5 s it chews through all but one block via the
normal damage path (5 × `take_hit()` each — exercising stage colors, the
armed pulse, sparks, destroy counting), then plays for real until the last
block dies. The survivor is the most exposed target (highest, most
central — a Penrose deal can hide tiny rhombi in corners) and starts
pre-damaged to yellow. Verifies the full win flow: stopwatch stop, record
submission + persistence, overlay. Combines with `--autotest-classic`.
Typical result ~4–15 s.

**Note:** wins write real records into `user://penrosebreak.cfg`. Run
through `tools/robustness.sh`, or prefix `XDG_DATA_HOME=$(mktemp -d)`, and
the player's file is never touched.

## `--autotest-winclick` — win overlay round trip

```sh
godot --headless res://scenes/main.tscn -- --autotest --autotest-fast --autotest-winclick
```

After the win, injects a real mouse click on the AGAIN button and requires
the arena to reload (the replayed run's win is the pass signal). Add
`--touchui` to run the same check as a raw screen touch through the
TapCatcher path — the route a phone takes.

## `--touchtest` — raw-touch pipeline check

```sh
godot --headless res://scenes/startup.tscn -- --touchtest
```

Injects real `InputEventScreenTouch` / `ScreenDrag` events (positions
pre-mapped into window space — delivery applies the stretch transform)
with mouse emulation off, exactly as a phone would send them: a tap during
the splash where QUIT will be (must only skip the splash); a tap opening
OPTIONS; a drag that starts on the Sound FX row (must scroll the panel and
leave the toggle alone); a clean tap (flips it once); a tap on BACK while
it is scrolled out of view (must be ignored), then on BACK in view; then
START. Reaching the arena is the pass (exit 0); every step is asserted.
This hook is what proved Godot's GUI never routes raw touches to buttons —
hence the TapCatcher in `touch_controls.gd` (taps on release, drags read in
`_input` because the GUI swallows a drag that starts on a widget).

## `--padtest` — gamepad menu check

```sh
godot --headless res://scenes/startup.tscn -- --padtest
```

Drives the menu with injected gamepad events only: START holds focus on
reveal, d-pad down walks to the mode cycler and then OPTIONS, A opens
OPTIONS, B closes it — with a mouse button held on the Sound FX toggle,
which must not flip (v1.13) — focus back on START, A on START enters the arena —
which prints the pass (exit 0). Each step is asserted (exit 1 on a miss).
Nothing persisted is touched. Exists because Godot 4.7's default
`ui_accept` / `ui_cancel` carry no pad buttons — A / B are added in
`Game._register_inputs`.

## `--inputtest` — every gameplay input, end to end

```sh
godot --headless res://scenes/main.tscn -- --inputtest
godot --headless res://scenes/main.tscn -- --inputtest --touchui
```

`scripts/dev/input_test.gd` injects real events through
`Input.parse_input_event` and asserts each effect: stick full left moves
the paddle; releasing stops it; half tilt is analog (≈ half speed); d-pad
steers; A launches (with `--touchui`: finger down steers to its x, a drag
follows, a long drag doesn't launch, a quick tap does); A mid-flight
boosts; the paddle pinned on a rail keeps the ball in the arena; Start
pauses, B resumes, Start/Start and P/P toggle; a mouse button held on
RESTART while B resumes must not fire it; the input scheme follows pad
and finger; with `--touchui`, a thumb held on ◀ through the restart must
not leave move_left pressed. Finally the pad's Back button restarts — the
reloaded arena prints the pass (and fails if the arena reloaded any
earlier). No records are written.

## `--fieldtest [n]` — tiling + wall-carving validator

```sh
godot --headless res://scenes/main.tscn -- --fieldtest 1000
```

`scripts/dev/field_test.gd` deals n random fields (default 200) plus the
constant one and checks each: every rhombus a true P3 rhombus (four equal
sides, convex, apex 36° thin / 108° thick); the rhombi tile the whole view
(clipped areas sum to the view area — no unpaired-triangle gaps, no
overlaps); the wall covers its band with no holes away from the rails and
floor; the constant deal still has exactly 141 tiles (competition records
depend on it). It runs main.gd's own pure `carve_field()`. ~15 ms/deal.

## `--cycletest [n]` — menu ↔ arena leak check

```sh
godot --headless --fixed-fps 60 res://scenes/startup.tscn -- --cycletest 100
```

`scripts/dev/cycle_test.gd` (spawned on the root by Game, so it survives
scene changes) drives n loops with real keys only: Enter on START → Space
→ R restart → Esc → ↓ ↓ Enter (MAIN MENU). Each menu return samples the
engine's object / node / resource / orphan counts; growth past 3 % between
the warm-up sample and the last fails.

## `--chaos [s]` — input fuzzer

```sh
godot --headless --fixed-fps 60 res://scenes/startup.tscn -- --chaos 120 [--chaos-seed n] [--touchui]
```

`scripts/dev/chaos.gd` (also on the root) strikes random keys, pad
buttons and sticks, mouse moves and clicks, and — with `--touchui` —
finger taps and drags, through every scene, releasing each a few ticks
later. It fails on a soft-lock (tree paused with the pause menu hidden),
slow-mo that never recovers, or the ball leaving the arena; script errors
fail it in the runner. Hitting QUIT is a legal ending (exit 0, with a
coverage line: time in menu / arena / paused / won); the runner relaunches
with the next seed until the lane's budget is spent.

## `--uitour` — open every menu panel

```sh
godot --headless res://scenes/startup.tscn -- --uitour
```

Opens OPTIONS and TOP SCORES (every record reader and caption runs),
closes them, touches one setting there and back (so a save happens), and
quits 0. The runner boots it against corrupted save files.

## `--touchui` — force the touch overlay

Add `--touchui` to any run (including `--autotest`) to show the gameplay
touch buttons without touch hardware, for layout checks and bot runs with
the overlay active.

## `--shot` — viewport screenshot

```sh
godot res://scenes/startup.tscn -- --shot /tmp/menu.png 4.0
```

Renders the booted scene windowed, waits the given seconds (default 1.5),
saves a PNG of the viewport and quits. Handled in the `Game` autoload, so
it works for any scene. Requires a presenting display — it hangs under
remote sessions where the compositor won't map windows (verified: engine
and GL init fine, the main loop blocks idle on first present).

## Headless boot checks

```sh
godot --headless res://scenes/startup.tscn --quit-after 240   # menu builds?
godot --headless res://scenes/main.tscn --quit-after 180      # arena builds?
```

Exit 0 with no stderr output = clean. A "2 ObjectDB instances leaked"
warning appears only when the autotest force-quits mid-tween — cosmetic,
dev-only.

## Release packages — `dist/package_release.sh`

```sh
dist/package_release.sh   # → build/release-<version>/
```

Exports every preset (Linux x86_64, Linux ARM64, Windows x86_64, macOS,
Web) and builds the six player packages plus `SHA256SUMS`:

| package | what's inside |
| --- | --- |
| `PenroseBreak-<v>-linux64.zip` | x86-64 binary, `run.sh`, `shortcut.sh` (menu entry), icon |
| `PenroseBreak-<v>-steam-deck.zip` | same binary; `run.sh` sets `PENROSEBREAK_HANDHELD` (full screen by default, no on-screen touch buttons) at 1280×800 / 60 fps |
| `PenroseBreak-<v>-raspberry-pi5-arm64.zip` | ARM64 binary; `run.sh` forces OpenGL ES 3 at 60 fps |
| `PenroseBreak-<v>-windows-x86_64.zip` | one self-contained `PenroseBreak.exe` (unsigned) |
| `PenroseBreak-<v>-macos-universal.zip` | `PenroseBreak.app`, Intel + Apple Silicon (unsigned: right-click → Open) |
| `PenroseBreak-<v>-web.zip` | `index.html` at the zip root — any static host, or an itch.io HTML project; built without threads, so no cross-origin isolation is needed |

Every package carries `LICENSE` (GPL-3.0-or-later), `README.txt` (start
instructions + controls) and `THIRD_PARTY_NOTICES.txt` — the Godot
Engine's MIT licence and its bundled components, written by
`dist/godot_notices.gd` from the very engine that exported the build. The
script checks each binary's architecture, then smoke-tests the shipped
x86-64 binary (a boot, `--touchtest` and `--padtest`) and the Deck
launcher, all in a throwaway profile. Needs the 4.7.stable export
templates (`~/.local/share/godot/export_templates/4.7.stable/`). Notes:
macOS universal requires `textures/vram_compression/import_etc2_astc=true`
in project.godot (set) and ships unsigned (`codesign=0`); Windows uses
`modify_resources=false` so no rcedit is needed; the script keeps a
`build/.gdignore` so the editor never imports exports back in. Only the
x86-64 binaries can be run on an x86-64 Linux machine.

Single exports by hand work too, e.g.
`godot --headless --export-release "Linux x86_64" build/PenroseBreak.x86_64`.
