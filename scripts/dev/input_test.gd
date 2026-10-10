extends Node
## InputTest (`--inputtest`, docs/CLI.md) — drives every gameplay input end
## to end through Input.parse_input_event, exactly as hardware would send
## it: gamepad stick (full and half tilt) and D-pad steering, A launch and
## A boost, Start / B / P pause and resume, a mouse button held on a pause
## button while B resumes (must NOT fire it — v1.13), and — with
## --touchui — finger steering, dragging and tap-to-launch. Each check prints a line; any
## failure exits 1. The finale presses the pad's Back button: the reloaded
## arena prints the pass (main.gd), proving restart works from a pad.
##
## Lives outside main.gd (preloaded there) to keep the arena script lean;
## dev-only, inert unless the flag is on the user args.

var main: Node2D
var paddle: Paddle
var ball: Ball

var _t := 0              # physics ticks
var _next := 30          # tick the next plan step runs
var _plan: Array = []    # [Callable, ticks to wait after it]
var _x0 := 0.0
var _boosts := 0
var _failed := false


func _ready() -> void:
	# Keep ticking under a paused tree — the pause checks need it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# An arena reload mid-plan would start a fresh instance and replay the
	# plan from the top — a silent pass. Only the final Back press may
	# reload (main.gd prints the pass on seeing its meta flag).
	if Game.has_meta("inputtest_started"):
		_fail("the arena reloaded unexpectedly mid-test")
		return
	Game.set_meta("inputtest_started", true)
	ball.boosted.connect(func(_p: float) -> void: _boosts += 1)
	var touch := OS.get_cmdline_user_args().has("--touchui")

	# --- the v1.13 chaos find: a mouse button held down ON a pause button
	# while B / Esc / Start resumes. Hiding the menu made Godot synthesize
	# a release on that button, so it fired (RESTART, MAIN MENU, QUIT
	# GAME…). Resuming must just resume. ---
	_do(func() -> void: _button(JOY_BUTTON_START, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_START, false), 4)
	_do(func() -> void:
		_check(get_tree().paused, "paused for the held-button check")
		_mouse(_pause_button("RESTART"), true), 4)
	_do(func() -> void: _button(JOY_BUTTON_B, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_B, false), 3)
	_do(func() -> void: _mouse(_pause_button("RESTART"), false), 12)
	_do(func() -> void:
		_check(not get_tree().paused and is_inside_tree(),
			"B with RESTART held down resumed without restarting"), 2)

	# --- gamepad steering (ball parked) ---
	_do(func() -> void:
		_x0 = paddle.position.x
		_axis(JOY_AXIS_LEFT_X, -1.0), 20)
	_do(func() -> void:
		_check(paddle.position.x < _x0 - 300.0,
			"stick full left: %.0f → %.0f" % [_x0, paddle.position.x])
		_check(Game.input_scheme == "pad", "scheme follows the pad")
		_axis(JOY_AXIS_LEFT_X, 0.0)
		_x0 = paddle.position.x, 2)
	_do(func() -> void:
		_check(absf(paddle.position.x - _x0) < 0.5, "stick released: paddle stops")
		_x0 = paddle.position.x
		# 0.6 tilt past the 0.2 deadzone → half strength → half speed
		_axis(JOY_AXIS_LEFT_X, 0.6), 20)
	_do(func() -> void:
		var d := paddle.position.x - _x0
		_check(d > 130.0 and d < 260.0, "stick half right is analog: +%.0f px" % d)
		_axis(JOY_AXIS_LEFT_X, 0.0)
		_x0 = paddle.position.x
		_button(JOY_BUTTON_DPAD_RIGHT, true), 10)
	_do(func() -> void:
		_check(paddle.position.x > _x0 + 120.0,
			"d-pad right: %.0f → %.0f" % [_x0, paddle.position.x])
		_button(JOY_BUTTON_DPAD_RIGHT, false), 5)

	# --- launch: a finger (tap) with the touch overlay, else pad A ---
	if touch:
		_do(func() -> void: _touch(Vector2(300.0, 360.0), true), 4)
		_do(func() -> void:
			_check(absf(paddle.position.x - 300.0) < 1.0,
				"finger down steers the paddle to x=%.0f" % paddle.position.x)
			_check(Game.input_scheme == "touch", "scheme follows the finger")
			_drag(Vector2(900.0, 360.0), Vector2(600.0, 0.0)), 4)
		_do(func() -> void:
			_check(absf(paddle.position.x - 900.0) < 1.0,
				"finger drag follows to x=%.0f" % paddle.position.x)
			_touch(Vector2(900.0, 360.0), false), 4)
		_do(func() -> void:
			_check(not ball.is_flying(), "a long drag is not a tap (no launch)")
			_touch(Vector2(640.0, 300.0), true), 3)
		_do(func() -> void: _touch(Vector2(640.0, 300.0), false), 4)
		_do(func() -> void:
			_check(ball.is_flying(), "quick tap launched the ball"), 12)
	else:
		_do(func() -> void: _button(JOY_BUTTON_A, true), 2)
		_do(func() -> void: _button(JOY_BUTTON_A, false), 4)
		_do(func() -> void: _check(ball.is_flying(), "pad A launched the ball"), 12)

	# --- boost: pad A mid-flight ---
	_do(func() -> void: _button(JOY_BUTTON_A, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_A, false), 4)
	_do(func() -> void: _check(_boosts == 1, "pad A mid-flight boosted"), 1)

	# --- v1.14: the paddle pinned on a rail must not crush the ball out of
	# the arena (thin rail segments used to let the solver push it through,
	# and it fell forever). Stick holds the paddle at its left clamp; the
	# ball is dropped into it there. ---
	_do(func() -> void: _axis(JOY_AXIS_LEFT_X, -1.0), 45)
	_do(func() -> void:
		ball.global_position = Vector2(50.0, 90.0)
		ball.velocity = Vector2(-30.0, 60.0), 40)
	_do(func() -> void:
		var p := ball.global_position
		_check(is_finite(p.x) and p.x >= 49.0 and p.x <= 1231.0 and p.y < 691.0,
			"paddle pinned on the rail kept the ball in play (ball at %.0f,%.0f)" % [p.x, p.y])
		_axis(JOY_AXIS_LEFT_X, 0.0), 4)

	# --- pause: Start / B / Start / Start, then keyboard P twice ---
	_do(func() -> void: _button(JOY_BUTTON_START, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_START, false), 4)
	_do(func() -> void:
		_check(get_tree().paused, "Start paused the game")
		_button(JOY_BUTTON_B, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_B, false), 4)
	_do(func() -> void:
		_check(not get_tree().paused, "B resumed from the pause menu")
		_button(JOY_BUTTON_START, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_START, false), 4)
	_do(func() -> void:
		_check(get_tree().paused, "Start paused again")
		_button(JOY_BUTTON_START, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_START, false), 4)
	_do(func() -> void:
		_check(not get_tree().paused, "Start resumed")
		_key(KEY_P, true), 2)
	_do(func() -> void: _key(KEY_P, false), 4)
	_do(func() -> void:
		_check(get_tree().paused, "P paused")
		_key(KEY_P, true), 2)
	_do(func() -> void: _key(KEY_P, false), 4)
	_do(func() -> void: _check(not get_tree().paused, "P resumed"), 2)

	# --- v1.14 (touch): a thumb still on ◀ when the arena reloads must not
	# leave move_left pressed in the next run (main.gd checks after the
	# reload, before printing the pass) ---
	if touch:
		_do(func() -> void: _touch(Vector2(95.0, 628.0), true, 1), 3)
		_do(func() -> void:
			_check(Input.is_action_pressed("move_left"),
				"holding the ◀ button presses move_left"), 1)

	# --- restart: pad Back reloads the arena (pass printed by main.gd) ---
	_do(func() -> void:
		Game.set_meta("inputtest_restart", true)
		_button(JOY_BUTTON_BACK, true), 2)
	_do(func() -> void: _button(JOY_BUTTON_BACK, false), 60)
	_do(func() -> void: _fail("Back did not restart the run"), 0)


func _do(step: Callable, wait_ticks: int) -> void:
	_plan.append([step, wait_ticks])


func _physics_process(_delta: float) -> void:
	if _failed:
		return
	_t += 1
	if _t < _next or _plan.is_empty():
		return
	var entry: Array = _plan.pop_front()
	(entry[0] as Callable).call()
	_next = _t + maxi(int(entry[1]), 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("inputtest: %s — OK" % what)
	else:
		_fail(what)


func _fail(msg: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("inputtest FAIL: " + msg)
	get_tree().quit(1)


func _button(b: JoyButton, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = b
	ev.pressed = down
	Input.parse_input_event(ev)


func _axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)


## Injected positions are window coordinates (delivery applies the stretch
## transform) — pre-map from the 1280×720 content space, like --touchtest.
## Mouse button at a content position. A press first hovers there (a real
## pointer always moves onto a button before clicking it — BaseButton only
## arms a press while hovered).
func _mouse(at: Vector2, down: bool) -> void:
	if down:
		var mv := InputEventMouseMotion.new()
		mv.position = get_tree().root.get_final_transform() * at
		Input.parse_input_event(mv)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = get_tree().root.get_final_transform() * at
	ev.pressed = down
	Input.parse_input_event(ev)


## Center of a pause-menu button, by caption (content coordinates).
func _pause_button(caption: String) -> Vector2:
	for b: Node in main._pause_layer.find_children("*", "Button", true, false):
		if (b as Button).text == caption:
			return (b as Button).get_global_rect().get_center()
	_fail("no %s button in the pause menu" % caption)
	return Vector2.ZERO


func _touch(at: Vector2, down: bool, index := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = get_tree().root.get_final_transform() * at
	ev.pressed = down
	Input.parse_input_event(ev)


func _drag(at: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = get_tree().root.get_final_transform() * at
	ev.relative = relative
	Input.parse_input_event(ev)
