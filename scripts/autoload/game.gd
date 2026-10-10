extends Node
## Game — run state + records (autoload "Game").
##
## Persistence pattern from the studio toolkit's Settings autoload: every
## write-worthy change goes through _save_and_notify(), the disk write is
## debounced and flushed on quit so nothing is lost. Stored in
## user://penrosebreak.cfg: the last player name, the best (minimum) clear time
## and who set it, plus sfx/screen-shake toggles.
##
## Input actions are registered here in code (studio convention: the
## whole game is built in scripts, project.godot stays minimal) — keyboard,
## mouse and gamepad alike. Game also tracks which control family the
## player is using right now (input_scheme) so prompts can follow it.

## Emitted after any persisted value changes.
signal changed
## Emitted when the player switches control family (keys/mouse ↔ gamepad ↔
## touch); the HUD hint and OPTIONS controls reference follow it.
signal scheme_changed

const SAVE_PATH := "user://penrosebreak.cfg"
## Where an unreadable save is preserved before it gets overwritten.
const SAVE_BAD_PATH := "user://penrosebreak.cfg.bad"
const SECTION := "penrosebreak"
const SAVE_DEBOUNCE_S := 0.5

## Game modes: the rectangle wall, the aperiodic field (the default), and
## the field against a countdown.
const MODES := ["classic", "penrose", "comp"]
## Competition round lengths in seconds.
const COMP_TIMES := [30, 60, 120, 300, 600]
## Default fresh-tile colors for the two P3 prototiles (player-pickable).
const DEF_THIN := Color("0fb8ad")
const DEF_THICK := Color("0a9e94")
## Stick deadzone for the move actions (fraction of full tilt); the ui_*
## actions keep Godot's 0.5 so menu steps stay crisp.
const STICK_DEADZONE := 0.2
## Longest player / record-holder name (the menu field caps typing here).
const NAME_MAX := 16

## Best clear time in seconds; <= 0.0 means "no record yet".
var best_time: float:
	get:
		return _best_time
	set(v):
		if is_equal_approx(v, _best_time):
			return
		_best_time = v
		_save_and_notify()

## Name of the record holder, uppercased at record time.
var best_name: String:
	get:
		return _best_name
	set(v):
		if v == _best_name:
			return
		_best_name = v
		_save_and_notify()

## The name typed in the menu; kept between sessions.
var player_name: String:
	get:
		return _player_name
	set(v):
		if v == _player_name:
			return
		_player_name = v
		_save_and_notify()

var sfx_on: bool:
	get:
		return _sfx_on
	set(v):
		if v == _sfx_on:
			return
		_sfx_on = v
		_save_and_notify()

var screen_shake: bool:
	get:
		return _screen_shake
	set(v):
		if v == _screen_shake:
			return
		_screen_shake = v
		_save_and_notify()

## Fullscreen window mode; applied immediately, no-op under headless.
var fullscreen: bool:
	get:
		return _fullscreen
	set(v):
		if v == _fullscreen:
			return
		_fullscreen = v
		_apply_fullscreen()
		_save_and_notify()

## Selected game mode, one of MODES; "penrose" is the default.
var game_mode: String:
	get:
		return _game_mode
	set(v):
		if not MODES.has(v) or v == _game_mode:
			return
		_game_mode = v
		_save_and_notify()

## Competition round length in seconds, one of COMP_TIMES.
var comp_time_s: int:
	get:
		return _comp_time_s
	set(v):
		if not COMP_TIMES.has(v) or v == _comp_time_s:
			return
		_comp_time_s = v
		_save_and_notify()

## Penrose modes: true (default) deals the same field every run from a
## fixed seed — reproducible speedruns, fair competitions; false re-deals a
## fresh aperiodic patch per run.
var field_constant: bool:
	get:
		return _field_constant
	set(v):
		if v == _field_constant:
			return
		_field_constant = v
		_save_and_notify()

## Penrose tile durability: true (default) = any contact bursts the tile,
## with a mini light pop; false = hardened, the full five-hit Block ladder.
var tile_one_shot: bool:
	get:
		return _tile_one_shot
	set(v):
		if v == _tile_one_shot:
			return
		_tile_one_shot = v
		_save_and_notify()

## Fresh-tile colors for the two P3 prototiles, picked in OPTIONS.
var tile_color_thin: Color:
	get:
		return _tile_color_thin
	set(v):
		if v == _tile_color_thin:
			return
		_tile_color_thin = v
		_save_and_notify()

var tile_color_thick: Color:
	get:
		return _tile_color_thick
	set(v):
		if v == _tile_color_thick:
			return
		_tile_color_thick = v
		_save_and_notify()

## Steer the paddle by tilting the device (mobile; needs a gravity sensor —
## silently inactive without one). Touch move buttons hide while it works.
var tilt_control: bool:
	get:
		return _tilt_control
	set(v):
		if v == _tilt_control:
			return
		_tilt_control = v
		_save_and_notify()

## Gamepad rumble on slams, kills, boosts and the finale (OPTIONS toggle).
var rumble_on: bool:
	get:
		return _rumble_on
	set(v):
		if v == _rumble_on:
			return
		_rumble_on = v
		_save_and_notify()

## Control family in use right now: "keys" (keyboard/mouse), "pad" or
## "touch". Follows the last real input; never persisted.
var input_scheme := "keys"

## One-shot handshake: main.gd sets it before returning to the menu so the
## studio splash is skipped; startup.gd clears it. Never persisted.
var skip_splash_once := false

## Shared gameplay RNG (penrose style pick, shake jitter, particles).
var rng := RandomNumberGenerator.new()

var _best_time := 0.0
var _best_name := ""
var _penrose_best := {}     # "shot"/"hard" → [best time, name]
var _comp_best := {}        # "frame:regime" (e.g. "60:shot") → [tiles, name]
var _game_mode := "penrose"
var _comp_time_s := 60
var _field_constant := true
var _tile_one_shot := true
var _tile_color_thin := DEF_THIN
var _tile_color_thick := DEF_THICK
var _tilt_control := false
var _rumble_on := true
var _last_pad := -1          # device id of the gamepad heard last
var _player_name := ""
var _sfx_on := true
var _screen_shake := true
var _fullscreen := false
var _loading := false
var _save_pending := false


func _ready() -> void:
	# Keep hearing input under a paused tree (the scheme can change while
	# the pause menu is up).
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_register_inputs()
	# Handhelds (v1.15): the Steam Deck launcher sets PENROSEBREAK_HANDHELD,
	# so a fullscreen setting the player has never saved opens on the
	# device's default — full screen. A choice saved in OPTIONS wins.
	if is_handheld():
		_fullscreen = true
	# `--fullscreen` / `-f` on the engine command line wins over a saved
	# "off" (_apply_fullscreen used to undo it at once). The engine consumes
	# those flags — they never reach OS.get_cmdline_args() — but it opens
	# the window full screen, so the mode at boot tells.
	var launched_fullscreen := DisplayServer.get_name() != "headless" \
		and DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
	_load()
	if launched_fullscreen:
		_fullscreen = true
	_apply_fullscreen()
	if TouchControls.wanted():
		input_scheme = "touch"
	elif not Input.get_connected_joypads().is_empty():
		input_scheme = "pad"
	# §cli dev hook: `-- --shot <path> [delay_s]` renders the booted scene for
	# delay_s seconds, saves a PNG of the viewport and quits. Used to eyeball
	# visuals from the command line; harmless in normal runs.
	var args := OS.get_cmdline_user_args()
	# §cli robustness drivers (scripts/dev/, docs/CLI.md): they live on the
	# root so they ride through every scene change.
	if args.has("--chaos"):
		get_tree().root.add_child.call_deferred(
			load("res://scripts/dev/chaos.gd").new())
	if args.has("--cycletest"):
		get_tree().root.add_child.call_deferred(
			load("res://scripts/dev/cycle_test.gd").new())
	var i := args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		var delay := 1.5
		if args.size() > i + 2 and args[i + 2].is_valid_float():
			delay = float(args[i + 2])
		_take_shot(args[i + 1], delay)


func _take_shot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("shot %s: %s" % ["saved" if err == OK else "FAILED", path])
	get_tree().quit()


func _exit_tree() -> void:
	_flush_save()


## Watch every real input (before the GUI sees it, never consuming it) to
## learn which control family the player is holding. Injected actions
## (the touch buttons synthesize them) and mouse drift don't count.
func _input(event: InputEvent) -> void:
	var scheme := ""
	if event is InputEventJoypadButton:
		if event.is_pressed():
			scheme = "pad"
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			scheme = "pad"
	elif event is InputEventScreenTouch:
		scheme = "touch"
	elif event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			scheme = "keys"
	if scheme == "pad":
		_last_pad = event.device
	if scheme != "" and scheme != input_scheme:
		input_scheme = scheme
		scheme_changed.emit()


## Launched by a handheld's launcher (the Steam Deck package's run.sh).
static func is_handheld() -> bool:
	return not OS.get_environment("PENROSEBREAK_HANDHELD").is_empty()


## Gamepad rumble — only while a pad is what the player is holding, and
## only if OPTIONS allows. weak/strong are the two motors, 0..1.
func rumble(weak: float, strong: float, seconds: float) -> void:
	if not _rumble_on or input_scheme != "pad" or _last_pad < 0:
		return
	Input.start_joy_vibration(_last_pad, clampf(weak, 0.0, 1.0),
		clampf(strong, 0.0, 1.0), seconds)


## Flush the debounced save whenever the app may die without a goodbye:
## window close, and on mobile / web the app going to the background
## (a discarded tab never runs _exit_tree).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_flush_save()


## Penrose records live in separate slots per breaking regime — a one-shot
## clear and a hardened clear are different sports.
func _regime(shot: bool) -> String:
	return "shot" if shot else "hard"


## Best clear time for a clear mode; 0 = none. "classic" ignores `shot`.
func clear_best_time(mode: String, shot: bool = true) -> float:
	if mode == "penrose":
		var rec: Array = _penrose_best.get(_regime(shot), [0.0, ""])
		return rec[0]
	return _best_time


func clear_best_name(mode: String, shot: bool = true) -> String:
	if mode == "penrose":
		var rec: Array = _penrose_best.get(_regime(shot), [0.0, ""])
		return rec[1]
	return _best_name


## Competition record for a time frame + regime: [tiles broken, name].
func comp_best(frame: int, shot: bool = true) -> Array:
	return _comp_best.get("%d:%s" % [frame, _regime(shot)], [0, ""])


## Record a clear ("classic" keeps the original save keys). Returns true
## when it is a new best (or the first ever) for that mode + regime.
func submit_time(seconds: float, mode: String = "classic",
		shot: bool = true) -> bool:
	var prev := clear_best_time(mode, shot)
	if prev > 0.0 and seconds >= prev:
		return false
	if mode == "penrose":
		_penrose_best[_regime(shot)] = [seconds, _record_name()]
	else:
		_best_time = seconds
		_best_name = _record_name()
	_save_and_notify()
	return true


## Record a competition round for the given time frame + regime. Ties
## don't beat a standing record; a zero-tile round never records.
func submit_comp(frame: int, tiles: int, shot: bool = true) -> bool:
	var prev: Array = comp_best(frame, shot)
	if tiles <= 0 or tiles <= int(prev[0]):
		return false
	_comp_best["%d:%s" % [frame, _regime(shot)]] = [tiles, _record_name()]
	_save_and_notify()
	return true


## Wipe every record, all modes and regimes (options panel, two-click
## confirmed there).
func reset_best() -> void:
	_best_time = 0.0
	_best_name = ""
	_penrose_best = {}
	_comp_best = {}
	_save_and_notify()


func _record_name() -> String:
	var n := _player_name.strip_edges().to_upper()
	return n if n != "" else "ANON"


## Stopwatch formatting used everywhere: M:SS.mmm.
func format_time(seconds: float) -> String:
	var ms := int(round(seconds * 1000.0))
	@warning_ignore("integer_division")
	return "%d:%02d.%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]


## Short caption for a competition time frame: "30s", "1min", "10min".
func format_frame(frame: int) -> String:
	if frame < 60:
		return "%ds" % frame
	return "%dmin" % int(frame / 60.0)


# ------------------------------------------------------------ inputs --------

## Keyboard, mouse and gamepad actions, added once. Editor restarts re-run
## this; the has_action / action_has_event guards keep it idempotent.
## Gamepad buttons use Godot's Xbox-layout names (every pad maps onto them)
## and match ALL devices, so a second controller works too. Godot's own
## ui_accept / ui_cancel ship without pad buttons — A and B are added so
## the menus and overlays answer a controller.
func _register_inputs() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"launch": [KEY_SPACE],
		"restart": [KEY_R],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action: String in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	_add_event("launch", _lmb())
	var pad := {
		"move_left": [JOY_BUTTON_DPAD_LEFT],
		"move_right": [JOY_BUTTON_DPAD_RIGHT],
		"launch": [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER],
		"restart": [JOY_BUTTON_BACK],
		"pause": [JOY_BUTTON_START],
		"ui_accept": [JOY_BUTTON_A],
		"ui_cancel": [JOY_BUTTON_B],
	}
	for action: String in pad:
		for b: JoyButton in pad[action]:
			var ev := InputEventJoypadButton.new()
			ev.device = -1
			ev.button_index = b
			_add_event(action, ev)
	# Analog: left stick steers (strength scales paddle speed), the right
	# trigger fires like A.
	for pair: Array in [["move_left", -1.0], ["move_right", 1.0],
			["launch", 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.device = -1
		m.axis = JOY_AXIS_TRIGGER_RIGHT if pair[0] == "launch" \
			else JOY_AXIS_LEFT_X
		m.axis_value = pair[1]
		_add_event(pair[0], m)
	InputMap.action_set_deadzone("move_left", STICK_DEADZONE)
	InputMap.action_set_deadzone("move_right", STICK_DEADZONE)


func _add_event(action: String, ev: InputEvent) -> void:
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


func _lmb() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	return ev


# ------------------------------------------------------- persistence --------

## Every read is typed and range-checked: a hand-edited or corrupted save
## must never raise. (A script error mid-_load would abort it with
## _loading stuck true — silently disabling every save for the session —
## and a malformed record would break the HUD build.) Bad values fall back
## to defaults; malformed records are dropped.
func _load() -> void:
	_loading = true
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		# Unreadable (corrupt, or a typo in a hand edit): the next save would
		# overwrite it with defaults and every record would be gone. Keep a
		# copy first so it can be repaired and restored.
		var copied := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(SAVE_BAD_PATH))
		push_warning("Game: %s unreadable (error %d); kept a copy as %s (%s)" % [
			SAVE_PATH, err, SAVE_BAD_PATH,
			"ok" if copied == OK else "copy failed: %d" % copied])
	if err == OK:
		_best_time = _read_num(cfg, "best_time", 0.0)
		_best_name = _read_str(cfg, "best_name", "")
		_penrose_best = {}
		var pb: Variant = cfg.get_value(SECTION, "penrose_best", {})
		if pb is Dictionary:
			for regime: String in ["shot", "hard"]:
				var rec := _clean_record((pb as Dictionary).get(regime), false)
				if not rec.is_empty():
					_penrose_best[regime] = rec
		# Migration: v1.3–v1.6 kept one penrose slot and frame-keyed comp
		# records, all earned in the hardened era → the "hard" slots.
		var old_t := _read_num(cfg, "penrose_best_time", 0.0)
		if old_t > 0.0 and not _penrose_best.has("hard"):
			_penrose_best["hard"] = [old_t,
				_read_str(cfg, "penrose_best_name", "")]
		_comp_best = {}
		var cb: Variant = cfg.get_value(SECTION, "comp_best", {})
		if cb is Dictionary:
			for k: Variant in cb:
				var key := ""
				if k is int and COMP_TIMES.has(k):
					key = "%d:hard" % k
					if (cb as Dictionary).has(key):
						continue   # a current-format entry wins
				elif k is String and _valid_comp_key(k):
					key = k
				else:
					continue
				var rec := _clean_record(cb[k], true)
				if not rec.is_empty():
					_comp_best[key] = rec
		_game_mode = _read_str(cfg, "game_mode", "penrose")
		if not MODES.has(_game_mode):
			_game_mode = "penrose"
		_comp_time_s = int(_read_num(cfg, "comp_time_s", 60.0))
		if not COMP_TIMES.has(_comp_time_s):
			_comp_time_s = 60
		_field_constant = _read_bool(cfg, "field_constant", true)
		_tile_one_shot = _read_bool(cfg, "tile_one_shot", true)
		_tile_color_thin = _read_color(cfg, "tile_color_thin", DEF_THIN)
		_tile_color_thick = _read_color(cfg, "tile_color_thick", DEF_THICK)
		_tilt_control = _read_bool(cfg, "tilt_control", false)
		_rumble_on = _read_bool(cfg, "rumble_on", true)
		_player_name = _read_str(cfg, "player_name", "")
		_sfx_on = _read_bool(cfg, "sfx_on", true)
		_screen_shake = _read_bool(cfg, "screen_shake", true)
		_fullscreen = _read_bool(cfg, "fullscreen", _fullscreen)
	_loading = false


## A finite, non-negative number (int or float in the file), else `def`.
func _read_num(cfg: ConfigFile, key: String, def: float) -> float:
	var v: Variant = cfg.get_value(SECTION, key, def)
	if (v is float or v is int) and is_finite(float(v)) and float(v) >= 0.0:
		return float(v)
	return def


func _read_bool(cfg: ConfigFile, key: String, def: bool) -> bool:
	var v: Variant = cfg.get_value(SECTION, key, def)
	return v if v is bool else def


## Strings are clipped to NAME_MAX — names are the only strings stored
## besides the mode id, and the menu field caps typing at the same length.
func _read_str(cfg: ConfigFile, key: String, def: String) -> String:
	var v: Variant = cfg.get_value(SECTION, key, def)
	return (v as String).left(NAME_MAX) if v is String else def


func _read_color(cfg: ConfigFile, key: String, def: Color) -> Color:
	var v: Variant = cfg.get_value(SECTION, key, def)
	return v if v is Color else def


## A record is [score, name]: a finite positive score (int tiles for
## competition frames, float seconds otherwise) and a string. Returns the
## normalized record, or [] when malformed.
func _clean_record(v: Variant, tiles: bool) -> Array:
	if not (v is Array) or (v as Array).size() < 2:
		return []
	var score: Variant = v[0]
	if not (score is float or score is int) or not is_finite(float(score)) \
			or float(score) <= 0.0 or not (v[1] is String):
		return []
	var who := (v[1] as String).left(NAME_MAX)
	return [int(score), who] if tiles else [float(score), who]


func _valid_comp_key(k: String) -> bool:
	var parts := k.split(":")
	return parts.size() == 2 and parts[0].is_valid_int() \
		and COMP_TIMES.has(int(parts[0])) and parts[1] in ["shot", "hard"]


## No-op under the headless driver (tests, CI).
func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)


func _save_and_notify() -> void:
	if _loading:
		return
	if not _save_pending:
		_save_pending = true
		get_tree().create_timer(SAVE_DEBOUNCE_S).timeout.connect(_flush_save)
	changed.emit()


func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # keep unknown keys from newer versions; ignore errors
	cfg.set_value(SECTION, "best_time", _best_time)
	cfg.set_value(SECTION, "best_name", _best_name)
	cfg.set_value(SECTION, "penrose_best", _penrose_best)
	cfg.set_value(SECTION, "comp_best", _comp_best)
	# drop migrated legacy keys (null erases)
	cfg.set_value(SECTION, "penrose_best_time", null)
	cfg.set_value(SECTION, "penrose_best_name", null)
	cfg.set_value(SECTION, "game_mode", _game_mode)
	cfg.set_value(SECTION, "comp_time_s", _comp_time_s)
	cfg.set_value(SECTION, "field_constant", _field_constant)
	cfg.set_value(SECTION, "tile_one_shot", _tile_one_shot)
	cfg.set_value(SECTION, "tile_color_thin", _tile_color_thin)
	cfg.set_value(SECTION, "tile_color_thick", _tile_color_thick)
	cfg.set_value(SECTION, "tilt_control", _tilt_control)
	cfg.set_value(SECTION, "rumble_on", _rumble_on)
	cfg.set_value(SECTION, "player_name", _player_name)
	cfg.set_value(SECTION, "sfx_on", _sfx_on)
	cfg.set_value(SECTION, "screen_shake", _screen_shake)
	cfg.set_value(SECTION, "fullscreen", _fullscreen)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Game: could not save state (error %d)" % err)
