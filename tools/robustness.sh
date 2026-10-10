#!/usr/bin/env bash
## PenroseBreak test runner — the regression suite and the robustness
## campaign, all headless, in parallel. Every run gets its own throwaway
## XDG_DATA_HOME, so the player's records in
## ~/.local/share/godot/app_userdata/PenroseBreak are NEVER touched (no
## backup/restore dance). A run passes only if it exits 0 AND prints no
## SCRIPT ERROR. Game-time-heavy runs use Godot's --fixed-fps 60, which
## plays ~30× faster than real time headless.
##
##   tools/robustness.sh --quick   # regression suite (~20 s): every hook
##   tools/robustness.sh           # + corrupted saves, 1000-deal field
##                                 #   check, 100 menu↔arena cycles, soak
##                                 #   matrix, frame-rate variants, chaos
##
## Env: GODOT (engine binary), SOAK_S (game seconds per soak run, default
## 1800), CHAOS_S (game seconds per chaos lane, default 600), JOBS
## (parallel runs; default: what MemAvailable affords at ~600 MB per Godot
## process, capped at 8 and at nproc — 22 parallel runs once exhausted a
## 12 GB machine). Logs land in a temp dir printed at the end (kept on
## failure). Exit 0 = everything passed. See docs/CLI.md.
set -uo pipefail
cd "$(dirname "$0")/.."

# Engine: $GODOT, else godot4 / godot on PATH, else a sibling ../godot/.
GODOT="${GODOT:-$(command -v godot4 || command -v godot \
	|| ls "$(dirname "$0")"/../../godot/Godot_v4*_linux.x86_64 2>/dev/null | tail -1 || true)}"
[ -n "$GODOT" ] && [ -x "$GODOT" ] || { echo "Godot 4.7 not found: set GODOT=/path" >&2; exit 1; }
SOAK_S=${SOAK_S:-1800}
CHAOS_S=${CHAOS_S:-600}
mem_jobs=$(awk '/MemAvailable/ { printf "%d", $2 / 1024 / 600 }' /proc/meminfo)
JOBS=${JOBS:-$(( mem_jobs < 1 ? 1 : (mem_jobs > 8 ? 8 : mem_jobs) ))}
[ "$JOBS" -gt "$(nproc)" ] && JOBS=$(nproc)
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

WORK=$(mktemp -d -t penrosebreak-tests.XXXXXX)
LOGS=$WORK/logs
mkdir -p "$LOGS"
RESULTS=$WORK/results
: > "$RESULTS"

"$GODOT" --headless --path . --import > "$LOGS/_import.log" 2>&1

## Parse gate: a script that fails to parse doesn't crash headless Godot —
## the scene just never runs, and every check would sit out its timeout.
## Three short boots load every script (the arena preloads the bot and
## harnesses; Game loads chaos / cycle_test on their flags); any parse or
## compile error aborts the run up front.
for gate in "res://scenes/main.tscn --quit-after 30" \
		"res://scenes/startup.tscn -- --chaos 0.2" \
		"res://scenes/startup.tscn -- --cycletest 0"; do
	# shellcheck disable=SC2086
	XDG_DATA_HOME=$WORK/xdg/_gate timeout 60 "$GODOT" --headless --path . $gate \
		>> "$LOGS/_gate.log" 2>&1
done
if grep -qE "Parse Error|Compile Error|Failed to load script" "$LOGS/_gate.log"; then
	echo "SCRIPTS DON'T COMPILE — fix these first:"
	grep -E "Parse Error|Compile Error|Failed to load script" -A1 "$LOGS/_gate.log" \
		| grep -v "^--$" | sort -u | head -20
	exit 2
fi

## run NAME SCENE [godot/user args...] — one isolated headless run. A run
## with a test hook (anything after `--`) must also print its OK / WIN
## line: a hook that never finishes its script but exits 0 anyway (say a
## stray tap hit QUIT) is a failure, not a pass.
run() {
	local name=$1 scene=$2
	shift 2
	local need_marker=0
	case " $* " in *" -- "*) need_marker=1 ;; esac
	local xdg=$WORK/xdg/$name
	mkdir -p "$xdg"
	XDG_DATA_HOME=$xdg timeout 900 "$GODOT" --headless --path . "$scene" "$@" \
		> "$LOGS/$name.log" 2>&1
	local rc=$?
	local errs
	errs=$(grep -c "SCRIPT ERROR" "$LOGS/$name.log")
	local line
	line=$(grep -hE "(autotest|inputtest|padtest|touchtest|fieldtest|cycletest|uitour|chaos)( SOAK)? (OK|WIN|FAIL)|autotest WIN|FAIL" \
		"$LOGS/$name.log" | tail -1 | cut -c1-150)
	local marked=1
	if [ $need_marker -eq 1 ] && ! grep -qE " (OK|WIN)" <<< "$line"; then
		marked=0
	fi
	if [ $rc -eq 0 ] && [ "$errs" -eq 0 ] && [ $marked -eq 1 ]; then
		echo "PASS $name  $line" >> "$RESULTS"
	elif [ $marked -eq 0 ] && [ $rc -eq 0 ]; then
		echo "FAIL $name (exited 0 without its OK line)  $line" >> "$RESULTS"
	else
		echo "FAIL $name (rc=$rc, script errors=$errs)  $line" >> "$RESULTS"
	fi
}

## chaos_lane NAME BUDGET [args...] — fuzz from the menu for BUDGET game
## seconds, relaunching with the next seed whenever chaos presses QUIT.
chaos_lane() {
	local name=$1 budget=$2
	shift 2
	local spent=0 seed=$((RANDOM * 7 + 1)) launches=0
	while [ "$spent" -lt "$budget" ]; do
		local left=$((budget - spent))
		local slice=$((left < 240 ? left : 240))
		local log=$LOGS/${name}_$launches.log
		local xdg=$WORK/xdg/${name}_$launches
		mkdir -p "$xdg"
		XDG_DATA_HOME=$xdg timeout 600 "$GODOT" --headless --fixed-fps 60 --path . \
			res://scenes/startup.tscn -- --chaos "$slice" --chaos-seed "$seed" "$@" \
			> "$log" 2>&1
		local rc=$?
		local errs
		errs=$(grep -c "SCRIPT ERROR" "$log")
		if [ $rc -ne 0 ] || [ "$errs" -ne 0 ]; then
			echo "FAIL $name (seed=$seed rc=$rc script errors=$errs)  $(grep -h FAIL "$log" | head -1)" >> "$RESULTS"
			return
		fi
		local t
		t=$(grep -ohE "game quit at t=[0-9.]+|chaos OK: [0-9]+" "$log" | grep -oE "[0-9.]+$" | head -1)
		t=${t%.*}
		spent=$((spent + ${t:-1} + 1))
		seed=$((seed + 1))
		launches=$((launches + 1))
	done
	echo "PASS $name  $budget game-s over $launches launches" >> "$RESULTS"
}

## Bounded parallelism.
spawn() {
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
		wait -n
	done
	"$@" &
}

M=res://scenes/main.tscn
ST=res://scenes/startup.tscn
FF=(--fixed-fps 60)

# --- regression suite ------------------------------------------------------
spawn run boot_menu $ST --quit-after 240
spawn run boot_arena $M --quit-after 180
spawn run uitour $ST -- --uitour
spawn run touchtest $ST -- --touchtest
spawn run padtest $ST -- --padtest
spawn run inputtest $M -- --inputtest
spawn run inputtest_touch $M -- --inputtest --touchui
spawn run fast "${FF[@]}" $M -- --autotest --autotest-fast
spawn run fast_classic "${FF[@]}" $M -- --autotest --autotest-fast --autotest-classic
spawn run fast_hardened "${FF[@]}" $M -- --autotest --autotest-fast --autotest-hardened
spawn run winclick "${FF[@]}" $M -- --autotest --autotest-fast --autotest-winclick
spawn run winclick_touch "${FF[@]}" $M -- --autotest --autotest-fast --autotest-winclick --touchui
spawn run penrose "${FF[@]}" $M -- --autotest
spawn run classic "${FF[@]}" $M -- --autotest --autotest-classic
spawn run comp "${FF[@]}" $M -- --autotest --autotest-comp
spawn run penrose_touchui "${FF[@]}" $M -- --autotest --touchui
spawn run fieldtest_quick $M -- --fieldtest 100
spawn run cycletest_quick "${FF[@]}" $ST -- --cycletest 10

if [ $QUICK -eq 0 ]; then
	# --- corrupted / hand-edited save files: menu tour + arena boot -------
	CASES=$WORK/cases
	mkdir -p "$CASES"
	printf '\x00\xff\xfe garbage \x01\x02[penrosebreak\n=== =\n' > "$CASES/garbage.cfg"
	: > "$CASES/empty.cfg"
	cat > "$CASES/types.cfg" <<-'EOF'
	[penrosebreak]
	best_time="fast"
	best_name=42
	penrose_best={"shot": "abc", "hard": [1.0]}
	comp_best={"60:shot": 5, "30:hard": ["x", "y"], 120: [3], "60:hard": [7]}
	game_mode=42
	comp_time_s="x"
	field_constant="yes"
	tile_one_shot=[1, 2]
	tile_color_thin="red"
	tile_color_thick=Vector2(1, 2)
	tilt_control=3.5
	player_name=["a"]
	sfx_on="no"
	screen_shake=null
	fullscreen={}
	rumble_on="?"
	EOF
	{
		echo "[penrosebreak]"
		echo "best_time=inf"
		echo "best_name=\"$(printf 'W%.0s' $(seq 1 3000))\""
		echo 'penrose_best={"shot": [nan, "X"], "hard": [-5.0, "Y"]}'
		echo 'comp_best={"60:shot": [999999999999, "Z"], "30:shot": [-3, "N"]}'
		echo 'game_mode="comp"'
		echo 'comp_time_s=-1'
		echo "player_name=\"$(printf 'N%.0s' $(seq 1 3000))\""
	} > "$CASES/extreme.cfg"
	cat > "$CASES/legacy.cfg" <<-'EOF'
	[penrosebreak]
	best_time=20.5
	best_name="CLASSICER"
	penrose_best_time=12.5
	penrose_best_name="OLD"
	comp_best={60: [10, "OLDC"], 30: [4, "OLDD"]}
	EOF
	cat > "$CASES/comp_bad.cfg" <<-'EOF'
	[penrosebreak]
	game_mode="comp"
	comp_time_s=60
	comp_best={"60:shot": "lots"}
	penrose_best={"shot": {"t": 1}}
	EOF
	for c in "$CASES"/*.cfg; do
		n=$(basename "$c" .cfg)
		for kind in menu arena; do
			d=$WORK/xdg/save_${n}_$kind/godot/app_userdata/PenroseBreak
			mkdir -p "$d"
			cp "$c" "$d/penrosebreak.cfg"
		done
		spawn run save_${n}_menu $ST -- --uitour
		spawn run save_${n}_arena $M --quit-after 120
	done

	# --- tiling + carving, leak cycling --------------------------------------
	spawn run fieldtest $M -- --fieldtest 1000
	spawn run cycletest "${FF[@]}" $ST -- --cycletest 100

	# --- soak matrix (two seeds each) + frame-rate variants ------------------
	SOAKS=("pen|" "pen_hard|--autotest-hardened" "pen_rand|--autotest-random"
		"pen_hard_rand|--autotest-hardened --autotest-random"
		"classic|--autotest-classic" "comp|--autotest-comp"
		"comp_hard_rand|--autotest-comp --autotest-hardened --autotest-random"
		"touch_rand|--touchui --autotest-random")
	for s in "${SOAKS[@]}"; do
		n=${s%%|*}
		read -ra a <<< "${s#*|}"
		spawn run soak_${n}_a "${FF[@]}" $M -- --autotest --autotest-soak "$SOAK_S" "${a[@]}"
		spawn run soak_${n}_b "${FF[@]}" $M -- --autotest --autotest-soak "$SOAK_S" "${a[@]}"
	done
	for fps in 30 240; do
		spawn run soak_pen_fps$fps --fixed-fps $fps $M -- --autotest --autotest-soak "$SOAK_S"
		spawn run soak_classic_fps$fps --fixed-fps $fps $M -- --autotest --autotest-soak "$SOAK_S" --autotest-classic
		spawn run soak_hard_rand_fps$fps --fixed-fps $fps $M -- --autotest --autotest-soak "$SOAK_S" --autotest-hardened --autotest-random
	done

	# --- chaos: random input through every scene ------------------------------
	for lane in 1 2 3; do
		spawn chaos_lane chaos_keys_$lane "$CHAOS_S"
		spawn chaos_lane chaos_touch_$lane "$CHAOS_S" --touchui
	done
fi
wait

sort "$RESULTS"
total=$(wc -l < "$RESULTS")
failed=$(grep -c "^FAIL" "$RESULTS")
echo
if [ "$failed" -eq 0 ]; then
	echo "ALL PASS: $total checks"
	rm -rf "$WORK"
	exit 0
fi
echo "FAILED: $failed of $total checks — logs kept in $LOGS"
exit 1
