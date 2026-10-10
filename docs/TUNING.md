# Tuning

Every gameplay-feel number, what it does, and where it lives. Change one
thing at a time; the constants are named at the top of each script.

## Ball physics — `scripts/ball.gd`

| constant | value | meaning |
| --- | --- | --- |
| `GRAVITY_IN` | 130 | px/s² inside the arena — deliberately gentle; the "slow" force of the game |
| `GRAVITY_ABOVE` | 850 | px/s² above the roofline (y < −30) so a missed ball returns in ~2 s |
| `EXIT_SPEED_CAP` | 540 | upward speed is clamped to this when crossing the top edge — bounds the round trip |
| `CRUISE_SPEED` | 430 | the resting speed excess power decays toward |
| `MAX_SPEED` | 1400 | hard speed ceiling |
| `MIN_SPEED` | 250 | floor enforced after bounces so the ball never dies |
| `POWER_DRAG` | 0.28 | fraction/s of speed-above-cruise bled off — how fast a slam fades |
| `PADDLE_BOOST_MUL` / `_ADD` | 1.12 / 150 | the cannon: speed ← speed×mul + add on a bottom-face slam |
| `PADDLE_MIN_EXIT` | 560 | slams never leave slower than this (also the launch speed) |
| `SIDE_BOOST_MUL` / `_ADD` | 1.08 / 90 | the side shove — smaller than the cannon |
| `TOP_BOUNCE_DAMP` | 0.45 | energy kept on a paddle-top bounce (soft, no slam) |
| `BLOCK_BOOST_ADD` | 26 | flat speed added per block bounce |
| `BOOST_ADD` | 460 | Space boost: flat speed added along the heading |
| `BOOST_COOLDOWN_S` | 2.5 | boost recharge (drives the HUD bar) |
| `RADIUS` | 9 | collision radius |
| `MIN_VERTICAL_RATIO` | 0.16 | \|vy\|/speed floor after bounces — kills endless horizontal ping-pong |
| `GLOW_COL` / `BOOST_GLOW_COL` | turquoise / magenta | halo tint cruising vs. while a boost burns (0.55 s cool-down tween) |

Paddle deflect aiming (in `_deflect_off_paddle`): hit offset over
`Paddle.WIDTH × 0.55` sets the angle (×0.85), paddle swing adds english
(`velocity_x / 2400`, clamped ±0.35), plus ±0.03 random jitter so a
perfectly centered hit can't lock into a vertical rail. Side shoves inherit
`velocity_x × 0.4` (clamped ±420).

## Paddle — `scripts/paddle.gd`

| constant | value | meaning |
| --- | --- | --- |
| `WIDTH` / `HEIGHT` | 150 / 22 | slab size (rails clamp accounts for half width) |
| `KEY_SPEED` | 1150 | px/s with A/D or arrows |
| `RECOIL_PX` | 7 | upward recoil on a slam, springs back in 0.22 s |

Mouse and keyboard arbitrate: keys take over the moment they're pressed;
the mouse takes over again once it actually moves (first sighting only
records position so it can't hijack a keyboard run). Touch move buttons
ride the key path (`Input.action_press`). A gamepad's left stick is on the
key path too, analog: `Input.get_axis` returns the tilt past the deadzone
renormalized to 0..1, so speed = tilt × `KEY_SPEED`
(`Game.STICK_DEADZONE` = 0.2 on the move actions; ui_* keep Godot's 0.5).
A steering finger (TouchControls) drags the paddle to its x like the mouse.
Priority: keys / pad / move buttons > finger > tilt > mouse.

| constant (touch_controls.gd) | value | meaning |
| --- | --- | --- |
| `TAP_MAX_S` | 0.3 | a steering touch lifted this soon… |
| `TAP_MAX_PX` | 28 | …that never strayed farther than this is a TAP → launch a parked ball |

Rumble (`Game.rumble(weak, strong, s)`, main.gd): paddle slam
`0.25 + 0.35·power / 0.3·power, 0.08 s`; boost `0.45 / 0.2, 0.12 s`;
one-shot pop `0.2 / 0.12, 0.06 s`; hardened kill `0.3 / 0.55, 0.16 s`;
win `0.6 / 1.0, 0.5 s` (competition end 0.45 s).

Tilt steering (mobile, opt-in):

| constant | value | meaning |
| --- | --- | --- |
| `TILT_FULL_MS2` | 3.2 | m/s² of gravity along screen x for full speed (~19° lean) |
| `TILT_DEADZONE` | 0.08 | axis fraction ignored so a resting phone stays still |
| `TILT_SIGN` | −1.0 | flip if a device family steers inverted |

## Blocks — `scripts/block.gd`

| constant | value | meaning |
| --- | --- | --- |
| `STAGE_COLORS` | turquoise `#0fb8ad`, green `#3ddc55`, yellow `#ffd744`, blue `#4aa8ff`, white | the damage ladder; hits-to-kill = size = 5 |
| `PUNCH_SCALE` / `PUNCH_S` | (1.18, 1.32) / 0.14 s | scale punch on every hit |

The white stage is *armed*: it blinks turquoise on the arming hit (a white
flash would be invisible on a white block) and then breathes on a loop
(0.25 s delay, 0.4 s per half-cycle) until the killing impact. A dead-guard
plus deferred shape-disable make `destroyed` fire exactly once even if the
ball grazes a dying block twice in one physics tick.

Penrose tiles (`penrose_tile.gd`): `one_shot` (OPTIONS, default on) makes
any contact burst the tile — main reacts with the mini light pop (shake
3.0–5.5, flash 0.08, glow bloom + 46 px ring, NO hit-stop) instead of the
full kill spectacle. Hardened tiles run the exact Block ladder above.
Fresh-tile colors come from `Game.tile_color_thin/thick` (OPTIONS
pickers); bursts and light pops follow the picked color.

## Arena & reactions — `scripts/main.gd`

| constant | value | meaning |
| --- | --- | --- |
| `ROWS` × `COLS` | 4 × 10 | the classic wall (200 hits total at 5 per block) |
| `BLOCK_H` / `BLOCK_GAP` | 30 / 8 | classic brick size; width computed from the rail span |
| `BREAK_TOP_Y` | 540 | Penrose modes: rhombi with ≥ 30% area below this line (bottom quarter) become breakable tiles — a gap-free band; the constant field deals 141, random deals vary (~50–200) |
| `FIELD_SEED` | 2654435769 | the constant-field deal: ⌊2³²/φ⌋ (141 tiles) |
| `ARENA_LEFT/RIGHT` | 40 / 1240 | rails |
| `WALL_TOP` | −3200 | top of the ball's play-area bound (`Ball.arena`); the rails themselves are endless half-planes since v1.14 |
| `FLOOR_Y` / `PADDLE_Y` | 700 / 90 | the wall sits on the floor; the paddle holds the top line |

Reaction strengths: paddle slam shake `3 + 5·power`; block tick shake
random 2.2–4.6 (the mandated random shake per contact); kill shake random
7–10.5 + hit-stop (time_scale 0.12 for 0.05 real s) + flash 0.22; win shake
14 + slow-mo (0.22 for 0.45 real s) + triple ring + flash 0.55. The flash
rect caps at alpha 0.7 and decays in 0.3 s.

Block-hit sound pitch: `0.9 + damage_ratio × 0.7` — the audible ladder.

## Camera shake — `scripts/game_camera.gd`

Trauma model: `add_shake(strength)` adds `strength / 14` trauma (capped 1),
trauma drains at 1.9/s, displacement = trauma² × 26 px max with two
incommensurate sines per axis plus a ±0.012 rad roll. Honors
`Game.screen_shake`.

## Timer honesty

The stopwatch counts physics ticks (`_run_ticks / physics_ticks_per_second`,
an integer count, so no float drift): physics steps run at the real-time
rate whatever `Engine.time_scale` is — only their delta shrinks — so
juice never buys or costs time. (Before v1.14 it summed
`delta / Engine.time_scale` in `_process`, which overcounted ~0.1 s per
hardened kill: a hit-stop that starts during physics changes time_scale
after that frame's process delta was already scaled.) The clock
starts on launch (aiming before launch is free) and stops at the last
block's death, before the win spectacle. Competition rounds run the same
honest clock as a countdown from `Game.comp_time_s` (30/60/120/300/600 s);
the round ends at zero — or early if the whole field falls.

## Backdrop

See [PENROSE.md](PENROSE.md) — styles, depths and seed geometry are all
randomized per run from `Game.rng`.
