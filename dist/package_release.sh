#!/usr/bin/env bash
## Release packages — what a player unpacks and runs:
##   PenroseBreak-<version>-linux64.zip              Linux x86-64
##   PenroseBreak-<version>-steam-deck.zip           SteamOS (same binary, Deck launcher)
##   PenroseBreak-<version>-raspberry-pi5-arm64.zip  Raspberry Pi 5 / 64-bit ARM Linux
##   PenroseBreak-<version>-windows-x86_64.zip       Windows 10/11, 64-bit
##   PenroseBreak-<version>-macos-universal.zip      macOS (Intel + Apple Silicon), unsigned
##   PenroseBreak-<version>-web.zip                  browser build, index.html at the zip root
## plus SHA256SUMS, in build/release-<version>/. Exports every preset with
## Godot 4.7, checks each binary's architecture, smoke-tests the x86-64
## build (a boot, then the --touchtest and --padtest end-to-end menu
## checks), boots the Deck launcher, and writes the engine's own licence +
## third-party notices next to the game (Godot is MIT; this game is
## GPL-3.0-or-later). Every run uses a throwaway profile, so no player
## settings or records are touched.
## Usage: dist/package_release.sh   (override the engine with GODOT=/path)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot4 || command -v godot \
	|| ls "$ROOT"/../godot/Godot_v4*_linux.x86_64 2>/dev/null | tail -1 || true)}"
[ -n "$GODOT" ] && [ -x "$GODOT" ] || { echo "Godot 4.7 not found: set GODOT=/path" >&2; exit 1; }
VERSION="$(sed -n 's/^const VERSION := "v\(.*\)"$/\1/p' "$ROOT/scripts/ui/startup.gd")"
[ -n "$VERSION" ] || { echo "no VERSION in scripts/ui/startup.gd" >&2; exit 1; }
OUT="$ROOT/build/release-$VERSION"
EXP="$OUT/export"
# build/ is git-ignored and must stay invisible to the editor, or Godot
# would import the web export's PNGs and pack them into the next build.
mkdir -p "$ROOT/build"
touch "$ROOT/build/.gdignore"
rm -rf "${OUT:?}"
mkdir -p "$EXP/web"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
sandboxed() { XDG_DATA_HOME="$SANDBOX/data" XDG_CONFIG_HOME="$SANDBOX/config" \
	XDG_CACHE_HOME="$SANDBOX/cache" "$@"; }

echo "== PenroseBreak $VERSION — exporting with $("$GODOT" --version)"
# (Exports run in the normal profile: that is where the export templates
# live. The editor never runs the game's autoloads, so no save is touched.)
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
export_preset() {  # export_preset <preset> <output>
	"$GODOT" --headless --path "$ROOT" --export-release "$1" "$2" \
		>"$OUT/export-$(basename "$2").log" 2>&1
}
export_preset "Linux x86_64" "$EXP/PenroseBreak.x86_64"
export_preset "Linux ARM64" "$EXP/PenroseBreak.arm64"
export_preset "Windows x86_64" "$EXP/PenroseBreak.exe"
export_preset "macOS" "$EXP/PenroseBreak-macos.zip"
export_preset "Web" "$EXP/web/index.html"
file "$EXP/PenroseBreak.x86_64" | grep -q "x86-64" || { echo "x86-64 export missing/wrong" >&2; exit 1; }
file "$EXP/PenroseBreak.arm64" | grep -q "aarch64" || { echo "arm64 export missing/wrong" >&2; exit 1; }
file "$EXP/PenroseBreak.exe" | grep -q "PE32+" || { echo "Windows export missing/wrong" >&2; exit 1; }
unzip -l "$EXP/PenroseBreak-macos.zip" | grep -q "Contents/MacOS/" || { echo "macOS export missing/wrong" >&2; exit 1; }
for w in index.html index.js index.wasm index.pck; do
	[ -s "$EXP/web/$w" ] || { echo "web export lacks $w" >&2; exit 1; }
done
for b in PenroseBreak.x86_64 PenroseBreak.arm64 PenroseBreak.exe; do
	[ "$(stat -c %s "$EXP/$b")" -gt 20000000 ] || { echo "$b too small — PCK not embedded?" >&2; exit 1; }
done

# The engine's licence + every bundled third-party component, from the
# very engine that exported the binaries; and the menu icon.
sandboxed "$GODOT" --headless --path "$ROOT" --script res://dist/godot_notices.gd -- \
	"$EXP/THIRD_PARTY_NOTICES.txt" "$EXP/icon.png" >/dev/null 2>&1
[ -s "$EXP/THIRD_PARTY_NOTICES.txt" ] || { echo "notices not written" >&2; exit 1; }
[ -s "$EXP/icon.png" ] || { echo "icon not rendered" >&2; exit 1; }

# Smoke: the shipped x86-64 binary boots, and its menus answer a raw touch
# and a gamepad end to end (the game's own --touchtest / --padtest hooks).
smoke() {  # smoke <name> <expect: alive|pass> <cmd...>
	local name=$1 expect=$2
	shift 2
	set +e
	sandboxed timeout 30 "$@" >"$OUT/smoke-$name.log" 2>&1
	local rc=$?
	set -e
	if [ "$expect" = alive ]; then
		[ "$rc" = 124 ] || { echo "$name: expected to still run, exit $rc ($OUT/smoke-$name.log)" >&2; exit 1; }
	else
		[ "$rc" = 0 ] || { echo "$name failed (exit $rc), see $OUT/smoke-$name.log" >&2; exit 1; }
	fi
	if grep -qE "SCRIPT ERROR|^ERROR:" "$OUT/smoke-$name.log"; then
		echo "$name logged errors, see $OUT/smoke-$name.log" >&2; exit 1
	fi
}
smoke boot-linux64 alive timeout 8 "$EXP/PenroseBreak.x86_64" --headless
smoke touchtest pass "$EXP/PenroseBreak.x86_64" --headless -- --touchtest
smoke padtest pass "$EXP/PenroseBreak.x86_64" --headless -- --padtest

CONTROLS='CONTROLS
  Keyboard  mouse or A / D or arrows to move, Space or left click to
            launch, Space mid-flight to boost (it recharges), Esc or P
            to pause, R to restart.
  Gamepad   left stick or d-pad to move, A (or RB / RT) to launch and
            boost, START pauses (B resumes), BACK / VIEW restarts.
            Menus: d-pad + A to choose, B to back out.
  Touch     drag anywhere to steer, tap to launch, the bolt button
            boosts, the pause button sits top-right.'

readme() {  # readme <stage> <platform> <start text> <settings path>
	cat >"$1/README.txt" <<README
PENROSE BREAK $VERSION — $2
An inverted block breaker: the paddle hangs at the top, the wall waits
at the bottom, gravity referees, and the stopwatch is the only score.
Every run is played over a genuine Penrose tiling.
Source code: https://github.com/b0realis/PenroseBreak

START
$3

$CONTROLS

  Settings and records: $4

LICENCE
  PENROSE BREAK is free software under the GNU General Public License
  v3.0 or later (LICENSE); its source is at the address above. It runs on
  the Godot Engine (MIT): the engine's licence and its third-party notices
  are in THIRD_PARTY_NOTICES.txt.
README
}

stage() {  # stage <platform> → prints the staging dir, with the legal files
	local dir="$OUT/PenroseBreak-$VERSION-$1"
	mkdir -p "$dir"
	cp "$ROOT/LICENSE" "$dir/LICENSE"
	cp "$EXP/THIRD_PARTY_NOTICES.txt" "$dir/THIRD_PARTY_NOTICES.txt"
	echo "$dir"
}

zip_dir() {  # zip_dir <platform> — zips the folder itself (it unpacks as one)
	local name="PenroseBreak-$VERSION-$1"
	(cd "$OUT" && zip -qr -X "$name.zip" "$name")
	echo "ok: $name.zip ($(du -h "$OUT/$name.zip" | cut -f1))"
}

linux_package() {  # linux_package <platform> <binary> <start text> <run.sh body>
	local dir
	dir="$(stage "$1")"
	cp -p "$EXP/$2" "$dir/$2"
	chmod +x "$dir/$2"
	cp "$EXP/icon.png" "$dir/icon.png"
	printf '%s\n' "$4" >"$dir/run.sh"
	chmod +x "$dir/run.sh"
	cat >"$dir/shortcut.sh" <<'SHORTCUT'
#!/bin/sh
# Put PENROSE BREAK in your application menu, pointing at this folder:
#   ./shortcut.sh            # write ~/.local/share/applications/penrosebreak.desktop
#   ./shortcut.sh --remove   # delete it again
set -eu
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
ENTRY="${XDG_DATA_HOME:-$HOME/.local/share}/applications/penrosebreak.desktop"
if [ "${1:-}" = "--remove" ]; then
	rm -f "$ENTRY"
	echo "removed $ENTRY"
	exit 0
fi
mkdir -p "$(dirname "$ENTRY")"
cat >"$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=PenroseBreak
Comment=An inverted block breaker over a Penrose tiling
Exec="$HERE/run.sh"
Path=$HERE
Icon=$HERE/icon.png
Terminal=false
Categories=Game;ArcadeGame;
StartupWMClass=PenroseBreak
EOF
chmod +x "$ENTRY"
echo "wrote $ENTRY — PenroseBreak is in your menu (./shortcut.sh --remove undoes it)"
SHORTCUT
	chmod +x "$dir/shortcut.sh"
	readme "$dir" "$1" "$3" "~/.local/share/godot/app_userdata/PenroseBreak/"
	zip_dir "$1"
}

linux_package linux64 PenroseBreak.x86_64 \
'  Linux x86-64. Extract the folder anywhere and run ./run.sh (or
  PenroseBreak.x86_64 directly). ./shortcut.sh adds it to your application
  menu. Needs OpenGL 3.3 or OpenGL ES 3.0 graphics drivers.' \
'#!/bin/sh
# PENROSE BREAK launcher (Linux x86-64).
set -eu
cd -- "$(dirname -- "$0")"
exec ./PenroseBreak.x86_64 "$@"'

linux_package steam-deck PenroseBreak.x86_64 \
'  Steam Deck / SteamOS: native Linux x86-64, no Proton needed.
  In Desktop Mode, extract the folder (for example to ~/Games/). In Steam:
  Games > Add a Non-Steam Game > Browse..., pick run.sh, add it. It starts
  full screen (switch it in OPTIONS) at the Deck'"'"'s 1280x800.
  Play with the built-in controls (Gamepad layout in Steam Input): left
  stick / d-pad to move, A to launch and boost, the Menu button (START)
  pauses, the View button (BACK) restarts. Menus take the d-pad + A / B
  (or the touchscreen). Not Steam Deck Verified; tested as a Linux build,
  not yet on a Deck in hand.' \
'#!/bin/sh
# Steam Deck / SteamOS launcher: full screen unless OPTIONS says
# otherwise (PENROSEBREAK_HANDHELD), the Deck'"'"'s 1280x800 panel, 60 fps.
set -eu
cd -- "$(dirname -- "$0")"
export PENROSEBREAK_HANDHELD=steam-deck
exec ./PenroseBreak.x86_64 --resolution 1280x800 --max-fps 60 "$@"'

linux_package raspberry-pi5-arm64 PenroseBreak.arm64 \
'  Raspberry Pi 5 (or newer 64-bit ARM Linux): use a 64-bit desktop OS
  such as Raspberry Pi OS (64-bit) with its standard graphics drivers.
  Extract the folder and run ./run.sh from the desktop session — it runs
  on OpenGL ES 3. If needed: chmod +x run.sh PenroseBreak.arm64
  Not a 32-bit build. Built and checked as an ARM64 export; not yet
  played on a Pi in hand, so performance needs on-device testing.' \
'#!/bin/sh
# Raspberry Pi 5 launcher: OpenGL ES 3 (the Pi 5 offers desktop OpenGL
# 3.1, below the 3.3 Godot asks for first), 60 fps.
set -eu
cd -- "$(dirname -- "$0")"
exec ./PenroseBreak.arm64 --rendering-driver opengl3_es --max-fps 60 "$@"'

# Windows: one self-contained executable.
dir="$(stage windows-x86_64)"
cp "$EXP/PenroseBreak.exe" "$dir/PenroseBreak.exe"
readme "$dir" windows-x86_64 \
'  Windows 10 / 11, 64-bit. Extract the folder anywhere and run
  PenroseBreak.exe. The executable is not code-signed, so SmartScreen may
  ask once: More info > Run anyway.' \
'%APPDATA%\Godot\app_userdata\PenroseBreak\'
zip_dir windows-x86_64

# macOS: the universal .app, repacked beside the legal files.
dir="$(stage macos-universal)"
unzip -qq "$EXP/PenroseBreak-macos.zip" -d "$dir"
readme "$dir" macos-universal \
'  macOS 10.15 or newer, Intel or Apple Silicon (universal). Extract and
  move PenroseBreak.app wherever you like. The app is not signed or
  notarized: the first time, right-click it > Open > Open (or allow it
  under System Settings > Privacy & Security).' \
'~/Library/Application Support/Godot/app_userdata/PenroseBreak/'
zip_dir macos-universal

# Web: index.html at the ZIP ROOT (what itch.io's HTML projects and any
# static host expect). Built without threads: no cross-origin isolation.
dir="$OUT/PenroseBreak-$VERSION-web"
mkdir -p "$dir"
cp "$EXP"/web/* "$dir/"
cp "$ROOT/LICENSE" "$EXP/THIRD_PARTY_NOTICES.txt" "$dir/"
readme "$dir" web \
'  Browser build (also the phone build — touch controls included). Serve
  this folder from any static web host and open index.html — for a quick
  local test: python3 -m http.server, then http://localhost:8000. It needs
  no special headers (built without threads). For itch.io, upload the zip
  as an HTML project.' \
'the browser'"'"'s storage for this page'
(cd "$dir" && zip -qr -X "../PenroseBreak-$VERSION-web.zip" .)
echo "ok: PenroseBreak-$VERSION-web.zip ($(du -h "$OUT/PenroseBreak-$VERSION-web.zip" | cut -f1))"

# The Deck launcher boots too (headless: it only proves run.sh is sound).
smoke boot-steam-deck alive timeout 8 "$OUT/PenroseBreak-$VERSION-steam-deck/run.sh" --headless

(cd "$OUT" && sha256sum PenroseBreak-"$VERSION"-*.zip >SHA256SUMS)
echo "== done: $OUT"
cat "$OUT/SHA256SUMS"
