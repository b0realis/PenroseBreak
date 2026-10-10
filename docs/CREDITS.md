# Credits

## PENROSE BREAK

A Prescription Games production. Shipped as THE BLOCK until v1.2, renamed
for the tiling it plays on. Free software under the GNU General Public
License v3.0 or later (see LICENSE).

## From the studio's shared toolkit (Prescription Games)

The studio keeps a set of reusables shared between its games. Carried
over here:

| what | into |
| --- | --- |
| studio caduceus mark | `assets/svg/ui/caduceus.svg` (verbatim), splash |
| splash choreography (fade/hold/scale-in, any-key skip, `skip_splash_once` handshake) | `scripts/ui/startup.gd` |
| procedural SFX synth toolkit (`_tone`, `_noise_hiss`, `_mix`, `_delayed`, `_to_stream`, player pool) | `scripts/autoload/sfx.gd` (new recipes) |
| debounced ConfigFile persistence pattern (setters apply + notify, one write per burst, flush on quit) | `scripts/autoload/game.gd` |
| trauma screen-shake camera model | `scripts/game_camera.gd` |
| code-built UI house style (buttons, labels, overlay panels, focus loops) | `startup.gd`, `main.gd` |
| `--bot`-style CLI hooks pattern | `--autotest` / `--shot` |
| touch input doctrine: NO mouse emulation, buttons synthesize the keyboard's inputs, menus take direct taps, `--touchui` test flag | `scripts/touch_controls.gd` |

## Original to this project

- PENROSE BREAK logo (`assets/svg/ui/logo_bounce.svg`): the breadbin home
  computer as the paddle, its CRT television as the glowing ball — with the
  game replaying on the TV screen.
- The P3 Penrose backdrop generator with the numerically verified deflation
  rule (docs/PENROSE.md).
- All gameplay code, the SFX recipes, the icon, the test harnesses.

## Engine

Godot Engine 4.7 (GL Compatibility renderer) — godotengine.org, MIT
licence. Release packages carry its licence and third-party notices in
`THIRD_PARTY_NOTICES.txt`.

## Fonts & audio

No font or audio assets are shipped: text uses the engine fallback font
(plus system monospace for the stopwatch), and every sound is synthesized
at boot.
