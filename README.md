# PENROSE BREAK

A Prescription Games block breaker with a twist, built with **Godot 4.7**
and named for its backdrop — every run is played over a genuine Penrose
tiling. *Aperiodic tiling countdown.*
The paddle hangs at the **top** of the screen, the wall of blocks waits at
the **bottom**, and gravity is the referee between them. Clear the wall as
fast as you can — the stopwatch is the only score.

## The game

Three modes, picked in OPTIONS (Penrose is the default):

- **Penrose** — the backdrop tiling itself is the wall. Rhombi in the
  bottom quarter of the screen are breakable tiles (a continuous, gap-free
  band); the vista above is scenery. Clear the field as fast as you can.
  The field is dealt from a fixed seed by default — same wall every run,
  for reproducible times — or set it to random in OPTIONS for a fresh
  aperiodic patch per run.
- **Block Classic** — the original 4×10 rectangle wall, against the clock.
- **Penrose Competition** — the Penrose field against a countdown
  (30s–10min, your pick): break as many tiles as time allows.

Best results per mode — and per competition round length, and separately
for one-shot vs hardened tile breaking — live under **TOP SCORES** in the
menu.

- **Inverted arena** — the paddle is a cannon on the top line; any contact
  with its bottom face slams the ball *downward* into the block wall. Its
  side faces shove with real energy too; only its top gives a soft, dampened
  bounce, so a ball that falls back from overhead pops up gently and gravity
  walks it home past the paddle.
- **Gravity twist** — inside the arena gravity is gentle, so a cruising ball
  floats; paddle deflections **slam power** into it (extra speed that slowly
  bleeds back toward cruise), and block bounces add a smaller kick. Miss the
  paddle and the ball sails out above the camera — the side rails extend far
  beyond the view, so it always comes home, pulled back by a heavier
  off-screen gravity.
- **Boost** — Space mid-flight kicks the ball along its current heading, on
  a 2.5 s cooldown (charge bar under the stopwatch). While it burns, the
  ball's glow flashes **magenta**.
- **The wall** — rectangle blocks (5 hits, climbing a readable color
  ladder: **turquoise → green → yellow → blue → white**; the white stage
  is *armed*, breathing until the next impact bursts it, each stage
  singing a higher pitch) or Penrose rhombi. Tiles default to **one-shot**
  — any contact bursts them with a mini light pop — or go **hardened** in
  OPTIONS for the full block ladder. The two prototiles (thin and thick
  rhombi) are colorable with pickers in OPTIONS; a destroyed tile reveals
  its dim ghost in the backdrop beneath.
- **The clock** — a digital stopwatch starts at launch and stops the moment
  the last block dies. Hit-stop slows the world but never the clock (it
  counts real physics ticks). Records need a comparable field: classic,
  or the constant Penrose deal — random deals are shown as unranked. The
  minimum time is the record, shown in the menu and HUD with the name that
  set it.
- **The feel** — randomized trauma-model screen shake on every block
  contact, hit-stop on kills, expanding shockwave rings, spark bursts, a
  world-wide turquoise flash pulse, a tapering light trail plus soft smoke
  that dims behind the ball, and a fully procedural synth soundscape.
- **The backdrop** — a genuine **P3 Penrose tiling** (Robinson-triangle
  deflation, numerically verified rule), regenerated every run with a random
  seed configuration, depth, rotation, offset and one of three turquoise
  render styles. Aperiodicity guarantees no two runs look the same.

Everything on screen is vector: SVG, drawn primitives, or engine gradients.
Every sound is synthesized at boot — no audio files shipped.

## Controls

| Action  | Keys | Controller | Touch |
| ------- | ---- | ---------- | ----- |
| Move    | mouse, or A / D, ← / → | left stick (analog) or d-pad | drag anywhere, hold ◀ ▶ — or tilt the phone (OPTIONS) |
| Launch  | Space or left click | A, RB or RT | tap anywhere, or ⚡ button |
| Boost   | Space mid-flight (2.5 s cooldown) | A mid-flight | ⚡ button mid-flight |
| Restart | R | Back / View | pause → RESTART |
| Pause   | Esc or P — resume / restart / main menu / quit | Start (B resumes) | ⏸ button |

Menus answer a controller too: d-pad / stick to move, A to choose, B to
back out. Rumble on slams, kills, boosts and the finale (OPTIONS toggle).
The in-arena hint follows whichever device you last touched.

On touch hardware the game switches to real touch input (no mouse
emulation): drag a finger anywhere to steer and tap to launch, plus
on-screen multitouch buttons (◀ ▶ ⚡ ⏸), direct taps in the menus,
virtual keyboard for the name field. **Tilt steering** (gravity
sensor) is an OPTIONS toggle — the move buttons step aside while it works.

OPTIONS in the main menu holds the sound / screen-shake / fullscreen /
rumble toggles, the controls reference, and a two-click reset of the
record.

## Download

Ready-to-play packages are on the
[Releases page](https://github.com/b0realis/PenroseBreak/releases):

| package | for |
| --- | --- |
| `…-linux64.zip` | Linux x86-64 — run `./run.sh`; `./shortcut.sh` adds a menu entry |
| `…-steam-deck.zip` | Steam Deck / SteamOS — add `run.sh` as a non-Steam game; starts full screen, plays on the built-in controls |
| `…-raspberry-pi5-arm64.zip` | Raspberry Pi 5 / 64-bit ARM Linux — `./run.sh` (OpenGL ES 3) |
| `…-windows-x86_64.zip` | Windows 10 / 11 — `PenroseBreak.exe` (unsigned: More info → Run anyway) |
| `…-macos-universal.zip` | macOS, Intel + Apple Silicon — unsigned: right-click → Open the first time |
| `…-web.zip` | any browser, phones included — serve the folder, open `index.html` |

Each carries a `README.txt` with the controls, the `LICENSE`, and the Godot
Engine's notices. `SHA256SUMS` lists the checksums.

## Running from source

```sh
godot --path .                  # Godot 4.7; or open the folder in the editor
tools/robustness.sh --quick     # the regression suite (docs/CLI.md)
dist/package_release.sh         # every release package → build/release-<version>/
```

Records and options persist in `user://penrosebreak.cfg`
(`~/.local/share/godot/app_userdata/PenroseBreak/` on Linux).

## Documentation

| Doc | What's in it |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | scene flow, autoloads, node structure, signal wiring |
| [docs/TUNING.md](docs/TUNING.md) | every gameplay constant: what it does, where it lives |
| [docs/PENROSE.md](docs/PENROSE.md) | the tiling math, the verified deflation rule, render styles |
| [docs/CLI.md](docs/CLI.md) | dev hooks: `--autotest`, `--autotest-fast`, `--inputtest`, `--padtest`, `--shot` |
| [docs/CREDITS.md](docs/CREDITS.md) | what came from the studio's shared toolkit, what is original |
| [CHANGELOG.md](CHANGELOG.md) | version history |

## Licence

PENROSE BREAK is free software: code and project-created assets are
licensed under the **[GNU General Public License v3.0 or later](LICENSE)**
(GPL-3.0-or-later). You may redistribute and/or modify it under the terms
of the GPL as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version. It is distributed
in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.

All art is hand-written SVG in this repository and every sound is
synthesized at runtime — there are no third-party assets. The Godot
Engine keeps its own MIT licence (its notices ship with every release
package as `THIRD_PARTY_NOTICES.txt`).

A Prescription Games production.
