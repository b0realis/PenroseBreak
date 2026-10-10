# Architecture

Everything is built in code, in the Prescription Games house style of the
studio's shared toolkit: the two `.tscn` files are one-node stubs whose
scripts construct the entire scene in `_ready()`. There are no editor-placed
nodes, no `.import`-heavy assets, no scene inheritance.

## File map

```
project.godot                  autoloads, window (1280×720, canvas_items/keep),
                               GL Compatibility renderer
icon.svg                       project icon (block + ball, vector)
export_presets.cfg             Linux x86_64 release preset, embedded pack
assets/svg/ui/caduceus.svg     Prescription Games studio mark (studio toolkit)
assets/svg/ui/logo_bounce.svg  logo art: breadbin-paddle slams CRT-ball
                               (kept as project art; not shown in the menu)
LICENSE                        GPL-3.0-or-later
scenes/startup.tscn            → scripts/ui/startup.gd   (main scene)
scenes/main.tscn               → scripts/main.gd          (the arena)
scripts/autoload/game.gd       "Game"  — state, records, options, input map
scripts/autoload/sfx.gd        "Sfx"   — procedural synth, 10 sounds
scripts/ui/startup.gd          splash → menu (name, START/OPTIONS/QUIT, best)
scripts/main.gd                arena build (3 game modes) + juice + overlays
scripts/ball.gd                custom-integrated ball physics + trail/smoke
scripts/paddle.gd              kinematic paddle, mouse/keys arbitration
scripts/block.gd               5-stage block, dead-guard, armed pulse
scripts/penrose_tile.gd        Block subclass: rhombus body from the tiling
scripts/touch_controls.gd      mobile input: gameplay buttons, finger
                               steering + tap-to-launch, menu taps
                               (no mouse emulation; studio pattern)
scripts/game_camera.gd         trauma screen shake
scripts/penrose_bg.gd          P3 Penrose tiling backdrop (see PENROSE.md)
scripts/dev/autotest.gd        `--autotest` smoke / soak bot (preloaded by
                               main.gd; pin() fixes mode/regime/deal/seed)
scripts/dev/input_test.gd      `--inputtest` harness (preloaded by main.gd)
scripts/dev/field_test.gd      `--fieldtest` tiling/carving validator
scripts/dev/cycle_test.gd      `--cycletest` leak cycler (root, via Game)
scripts/dev/chaos.gd           `--chaos` input fuzzer (root, via Game)
tools/robustness.sh            runs every check, isolated + parallel
```

## Autoloads

**Game** (`game.gd`) — run state and persistence. Properties with setters
that apply side effects immediately (fullscreen) and debounce one disk write
per burst of changes (0.5 s, flushed on quit): `best_time`, `best_name`,
`player_name`, `sfx_on`, `screen_shake`, `fullscreen`. Also: the shared
gameplay RNG, `submit_time(seconds, mode)` / `submit_comp(frame, tiles)`
(both return true on a new record; classic, penrose and each competition
frame hold separate record slots — `clear_best_time/name(mode)` and
`comp_best(frame)` read them), `game_mode` + `comp_time_s` (the OPTIONS
selections, persisted), `format_time()` (M:SS.mmm everywhere),
`format_frame()` ("30s"/"1min"), `reset_best()`, the code-registered
input actions (`move_left`, `move_right`, `launch`, `restart`, `pause` —
keyboard, mouse and gamepad, added in `_ready`, idempotent; Godot's
`ui_accept` / `ui_cancel` gain pad A / B so menus answer a controller),
`input_scheme` ("keys" / "pad" / "touch", learned from the last real
input in `_input` — Game runs PROCESS_MODE_ALWAYS so it hears it under
pause too — and announced via `scheme_changed`, which the HUD hint
follows), `rumble(weak, strong, s)` (gamepad vibration, only while a pad
is in hand, gated on the persisted `rumble_on`), `skip_splash_once` (session-scoped handshake so
returning from the arena skips the studio splash), and the `--shot` dev hook
(CLI.md). Save file: `user://penrosebreak.cfg`, section `[penrosebreak]`.
Loading is defensive: every value is read typed and range-checked (bad
types, inf/nan/negative numbers fall back to defaults; names clip to
`NAME_MAX` = 16; malformed records are dropped), because a script error
mid-`_load` would leave `_loading` stuck and silently disable saving. An
unreadable file (parse error) is copied to `penrosebreak.cfg.bad` before
the next save would overwrite it.

**Sfx** (`sfx.gd`) — synthesizes every sound at startup from a tiny additive
toolkit (swept oscillators + lowpass-swept noise, exponential envelopes)
into 22050 Hz 16-bit mono WAV streams, played through a round-robin pool of
8 players with pitch jitter. `Sfx.play(name, pitch_var, pitch_base)`; gates
on `Game.sfx_on`. Sounds: `ui launch paddle block break wall whoosh boost
win best`. The toolkit (`_tone/_noise_hiss/_mix/_delayed/_to_stream`) is
reused verbatim from the studio toolkit; only the recipes are new.

## Scene flow

```
startup.tscn ──START──▶ main.tscn ──MAIN MENU (skip_splash_once)──▶ startup.tscn
     │  splash (caduceus) unless Game.skip_splash_once
     └─ menu: PenroseBg + wash + TileSnow (sparse falling rhombi in the
        block colors), wordmark left, column bottom-right (name, START,
        OPTIONS, TOP SCORES, QUIT, best line for the selected mode),
        options + top-scores panels (centered overlays, replace the menu
        while open)
```

## Game modes

`main.gd` reads `Game.game_mode` once in `_ready` (autotest flags can pin
it locally without touching the save): **classic** builds the 4×10 block
grid; **penrose** (default) and **comp** call `_build_penrose_field()` —
the backdrop is frozen (`PenroseBg.freeze()`), its triangles are paired
into rhombi (`PenroseBg.rhombi()`, spatial diagonal-midpoint matching),
and every rhombus overlapping the strip below `BREAK_TOP_Y` (540 = bottom
quarter) by ≥ 30% of its area (`carve_field()`, a pure static function the
`--fieldtest` validator also runs) becomes a `PenroseTile` static body — a
continuous band. With `Game.field_constant` (default) the arena backdrop
is re-dealt from `FIELD_SEED` for an identical field every run.
`PenroseTile extends Block`, so the ball collision branch, damage ladder,
signals and reactions are untouched. **comp** additionally runs the
stopwatch as a countdown from `Game.comp_time_s` and ends via
`_finish_comp()` (score = tiles broken) instead of `_win()`.

## The arena (main.gd `_ready` order)

1. `PenroseBg` (fresh random tiling) + a full-screen additive **flash rect**
   on CanvasLayer −1 (the world-wide pulse on hits).
2. **Walls** — one StaticBody2D with three WorldBoundaryShape2D half-planes:
   the side rails (endless upward) and the floor at y = 700. A missed ball
   can only leave the view via the top — and always falls back. Half-planes
   (not thin segments, as before v1.14) mean depenetration always pushes
   inward: a paddle teleporting onto a ball at a rail used to squeeze it
   out of the arena for good. The ball adds two nets: `_unwedge_at_rail()`
   pops it out vertically when the paddle lands on it with no room at a
   rail, and `_keep_in_arena()` clamps its center to `Ball.arena`.
   `RailsVisual` draws the glowing edges.
3. **Paddle** at (640, 90), spanning between the rails.
4. **Ball** (z_index 10, above blocks), parked under the paddle.
5. **Blocks** — 4×10 grid sitting on the floor, evenly spread between the
   rails (block width computed from the span).
6. **HUD** (CanvasLayer 5): stopwatch top-center, boost charge bar + tag
   beneath it, player name top-left, best top-right, launch hint center.
7. **Pause overlay** (CanvasLayer 20, PROCESS_MODE_ALWAYS): RESUME /
   RESTART / MAIN MENU / QUIT GAME, plus the `PauseCatcher` node — an
   always-processing Esc listener that acts (and consumes the event) ONLY
   while the tree is paused; unpaused Esc falls through to main's own
   `_unhandled_input`. This split exists because main is pausable and goes
   silent under `get_tree().paused`.
8. **Win overlay** (CanvasLayer 20): WALL DOWN + final time + best line +
   AGAIN / MAIN MENU.
9. **GameCamera** at screen center.
10. `AutoTest` bot (`scripts/dev/autotest.gd`), only when `--autotest` is on
    the user args (CLI.md). `--inputtest` / `--fieldtest` swap in their own
    harnesses instead.

## Signal wiring (ball → main)

The ball owns motion and collision resolution; main owns every reaction
(sound, shake, flash, rings, hit-stop, score):

| signal | fired on | main's reaction |
| --- | --- | --- |
| `launched` | first Space/click | start stopwatch, fade hint, launch sound |
| `paddle_bounced(power)` | bottom-face slam, side shove | paddle sound pitched by power, shake 3+5·power, flash |
| `paddle_tapped` | soft top bounce | quiet low tap sound only |
| `block_bounced(block, at)` | any block contact | `block.take_hit()`; stage tick pitched by damage, random shake 2.2–4.6, small ring; on kill: break sound |
| (block) `destroyed(block)` | 5th hit | count down, shake 7–10.5, white+turquoise rings, hit-stop 0.12×/0.05 s, flash 0.22; last block → `_win()` |
| `wall_bounced(at)` | rails/floor | soft thud |
| `boosted(power)` | Space mid-flight | boost sound, shake 3.5, magenta ring, flash |
| `left_screen` | crossed the roofline | whoosh |

`_win()` records the time via `Game.submit_time`, plays the fanfare (+
shimmer on a new record), fires the triple-ring slow-motion finale, and
raises the overlay.

## Timing rules

- The stopwatch counts physics ticks in main's `_physics_process` (integer
  `_run_ticks`; physics steps keep the real-time rate under any
  time_scale) — hit-stop and the win slow-mo affect the world, never the
  clock. The competition countdown ends on the exact tick.
- Records are set only on comparable fields (`_ranked`): classic, or the
  constant Penrose deal. Random deals (30–194 tiles) show their result as
  UNRANKED.
- When a run ends, the ball keeps flying as scenery but `end_run()` stops
  its boosts, paddle hits only thud, and the overlay's buttons stay
  disarmed until its 1.2 s fade-in completes.
- Hit-stop uses a real-time SceneTreeTimer (`ignore_time_scale`) to restore
  `Engine.time_scale`. Overlapping stops: the one ending last owns the
  restore (a generation counter), so the last block's short kill freeze
  can't truncate the win slow-mo; a shorter stop arriving mid-way through
  a longer one is skipped.
- Once a run ends (`_won`), block contacts are treated as wall bounces —
  a competition round that ran out of time can't keep scoring behind
  the overlay.
- Pausing pauses main (and thus the stopwatch `_process`) naturally.

## Rendering choices

GL Compatibility renderer everywhere; all "glow" is faked with additive
CanvasItemMaterials over engine radial gradients (GradientTexture2D), so the
look survives on any GPU and there is no HDR/WorldEnvironment dependency.
The ball is layered: additive halo sprite (white texture tinted via
`self_modulate` — turquoise cruising, magenta during boost), drawn vector
core, world-space Line2D trail with width/alpha scaling on power, and a
CPUParticles2D smoke plume.
