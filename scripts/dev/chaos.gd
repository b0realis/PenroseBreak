extends Node
## Chaos (`--chaos [seconds]`, docs/CLI.md) — a seeded input fuzzer that
## lives on the root, so it rides through every scene: menu, OPTIONS, TOP
## SCORES, arena, pause, win. Each tick it may strike a random key, pad
## button or stick, mouse click/move, or (with --touchui) finger tap /
## drag, releasing it a few ticks later. While it plays it checks the
## states nobody should ever reach:
##   * the tree paused with no pause menu on screen (a soft-lock);
##   * Engine.time_scale stuck away from 1 (slow-mo that never recovers);
##   * the ball non-finite, outside the rails or below the floor.
## Script errors surface on stderr (tools/robustness.sh fails on them).
## Pressing QUIT is a legal outcome: the process exits 0 and the harness
## relaunches with the next seed. Pair with `--fixed-fps 60` for speed.
##
## Spawned on the root by Game; PROCESS_MODE_ALWAYS (it must keep typing
## while the game is paused).

const KEYS: Array[Key] = [KEY_SPACE, KEY_ESCAPE, KEY_P, KEY_R, KEY_A, KEY_D,
	KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_TAB, KEY_BACKSPACE,
	KEY_X, KEY_Q, KEY_1]
const BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X,
	JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP,
	JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
const SLOWMO_FRAMES := 150

var _rng := RandomNumberGenerator.new()
var _seconds := 120.0
var _ticks := 0
var _pending: Array = []      # [release tick, InputEvent (the release)]
var _touch := false
var _slowmo := 0
var _paused_bare := 0
var _events := 0
var _failed := false
## Coverage: ticks spent per place, and arena visits / pauses / wins seen.
var _cov := {"menu": 0, "arena": 0, "paused": 0, "won": 0, "arenas": 0}
var _last_scene: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var i := args.find("--chaos")
	if i + 1 < args.size() and args[i + 1].is_valid_float():
		_seconds = float(args[i + 1])
	var si := args.find("--chaos-seed")
	_rng.seed = int(args[si + 1]) if si >= 0 and si + 1 < args.size() \
		else randi()
	_touch = args.has("--touchui")
	print("chaos seed=%d for %.0fs (replay: --chaos-seed %d)" % [
		_rng.seed, _seconds, _rng.seed])


func _exit_tree() -> void:
	if not _failed and _ticks / 60.0 < _seconds:
		print("chaos: game quit at t=%.1fs after %d events; %s" % [
			_ticks / 60.0, _events, _coverage()])


func _coverage() -> String:
	var t := maxf(1.0, float(_ticks))
	return "menu %d%% arena %d%% (paused %d%%, won %d%%), %d arena visits" % [
		roundi(100.0 * _cov.menu / t), roundi(100.0 * _cov.arena / t),
		roundi(100.0 * _cov.paused / t), roundi(100.0 * _cov.won / t),
		_cov.arenas]


func _process(_delta: float) -> void:
	if Engine.time_scale != 1.0 and not get_tree().paused:
		_slowmo += 1
		if _slowmo > SLOWMO_FRAMES:
			_fail("Engine.time_scale stuck at %.2f" % Engine.time_scale)
	else:
		_slowmo = 0


func _physics_process(_delta: float) -> void:
	if _failed:
		return
	_ticks += 1
	if _ticks / 60.0 >= _seconds:
		print("chaos OK: %.0fs, %d events, seed=%d; %s" % [
			_seconds, _events, _rng.seed, _coverage()])
		get_tree().quit(0)
		_failed = true   # stop acting; quit lands at frame end
		return
	# Releases come due.
	for k in range(_pending.size() - 1, -1, -1):
		if _ticks >= int(_pending[k][0]):
			Input.parse_input_event(_pending[k][1])
			_pending.remove_at(k)
	if _rng.randf() < 0.18:
		_strike()
	_watch()


## One random input (press now, release 1–12 ticks later).
func _strike() -> void:
	_events += 1
	var roll := _rng.randf()
	var hold := _rng.randi_range(1, 12)
	if roll < 0.32:
		var down := InputEventKey.new()
		var k: Key = KEYS[_rng.randi_range(0, KEYS.size() - 1)]
		down.keycode = k
		down.physical_keycode = k
		down.pressed = true
		_press(down, hold)
	elif roll < 0.56:
		var b := InputEventJoypadButton.new()
		b.button_index = BUTTONS[_rng.randi_range(0, BUTTONS.size() - 1)]
		b.pressed = true
		_press(b, hold)
	elif roll < 0.66:
		var m := InputEventJoypadMotion.new()
		m.axis = JOY_AXIS_LEFT_X if _rng.randf() < 0.7 else JOY_AXIS_TRIGGER_RIGHT
		m.axis_value = _rng.randf_range(-1.0, 1.0)
		Input.parse_input_event(m)
		var back := InputEventJoypadMotion.new()
		back.axis = m.axis
		back.axis_value = 0.0
		_pending.append([_ticks + hold * 3, back])
	elif roll < 0.86 or not _touch:
		var at := _window(Vector2(_rng.randf_range(0, 1280), _rng.randf_range(0, 720)))
		if _rng.randf() < 0.5:
			var mm := InputEventMouseMotion.new()
			mm.position = at
			mm.relative = Vector2(_rng.randf_range(-40, 40), 0)
			Input.parse_input_event(mm)
		else:
			var c := InputEventMouseButton.new()
			c.button_index = MOUSE_BUTTON_LEFT
			c.position = at
			c.pressed = true
			_press(c, hold)
	else:
		var idx := _rng.randi_range(0, 2)
		var at := _window(Vector2(_rng.randf_range(0, 1280), _rng.randf_range(0, 720)))
		var t := InputEventScreenTouch.new()
		t.index = idx
		t.position = at
		t.pressed = true
		Input.parse_input_event(t)
		if _rng.randf() < 0.5:
			var d := InputEventScreenDrag.new()
			d.index = idx
			d.position = at + Vector2(_rng.randf_range(-300, 300), _rng.randf_range(-60, 60))
			d.relative = d.position - at
			_pending.append([_ticks + 1, d])
		var up := InputEventScreenTouch.new()
		up.index = idx
		up.position = at
		up.pressed = false
		_pending.append([_ticks + hold, up])


func _press(ev: InputEvent, hold: int) -> void:
	Input.parse_input_event(ev)
	var up: InputEvent = ev.duplicate()
	up.set("pressed", false)
	_pending.append([_ticks + hold, up])


func _watch() -> void:
	var cs := get_tree().current_scene
	if cs == null or not cs.scene_file_path.ends_with("/main.tscn"):
		_paused_bare = 0
		_cov.menu += 1
		return
	_cov.arena += 1
	if cs != _last_scene:
		_last_scene = cs
		_cov.arenas += 1
	if get_tree().paused:
		_cov.paused += 1
	if cs.get("_won"):
		_cov.won += 1
	# Paused with no pause menu showing = soft-lock (allow a few ticks for
	# a scene change in flight).
	var pause_layer: CanvasLayer = cs.get("_pause_layer")
	if get_tree().paused and pause_layer != null and not pause_layer.visible:
		_paused_bare += 1
		if _paused_bare > 30:
			_fail("tree paused with the pause menu hidden")
	else:
		_paused_bare = 0
	var ball: Ball = cs.get("_ball")
	if ball == null or not is_instance_valid(ball):
		return
	var p := ball.global_position
	if not (is_finite(p.x) and is_finite(p.y)) or p.x < 28.0 or p.x > 1252.0 \
			or p.y > 712.0:
		_fail("ball out of bounds: %s" % p)


func _window(at: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * at


func _fail(msg: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("chaos FAIL: %s (seed=%d, t=%.1fs)" % [msg, _rng.seed, _ticks / 60.0])
	get_tree().quit(1)
