extends CanvasLayer
class_name TouchControls
## TouchControls — mobile input, the studio's way: NO mouse emulation
## (project setting off — a simulated mouse would teleport the paddle via
## the mouse-follow path and ghost-click menus). Gameplay gets vector-drawn
## multitouch buttons that synthesize the same input actions the keyboard
## uses (◀ ▶ hold → move_left/move_right, ⚡ → launch/boost, ⏸ → pause),
## so the paddle and ball logic run unchanged — and the rest of the screen
## is a steering pad: a finger anywhere off the buttons drags the paddle to
## its x (like the mouse), and a quick tap launches a parked ball. Menus and
## overlays get wire_taps(): raw-touch activation for every Button /
## CheckBox / LineEdit, because Godot buttons ignore ScreenTouch while
## mouse emulation is off (verified end-to-end by the --touchtest hook).
## The overlay appears only when a touchscreen is present (or --touchui).

const COL := Color(0.1, 0.9, 0.82)
## Visual press feedback lingers this long after an edge-button tap.
const FLASH_S := 0.18
## A steering touch counts as a TAP (→ launch a parked ball) when it lifts
## this soon and never strays farther than this from where it landed.
const TAP_MAX_S := 0.3
const TAP_MAX_PX := 28.0

## The arena (main.gd); buttons hide once the run is won.
var main: Node2D
## Steering targets, set by main alongside `main`.
var paddle: Paddle
var ball: Ball

var _face: Node2D
var _held := {}      # touch index → action ("move_left"/"move_right")
var _held_count := {}  # action → fingers holding it (two thumbs on ◀ = 2)
var _flash := {}     # button kind → seconds of press-flash left
var _steer := -1             # touch index steering the paddle, −1 = none
var _steer_t0 := 0           # msec the steering touch landed
var _steer_from := Vector2.ZERO
var _steer_travel := 0.0     # farthest the steering touch strayed, px


static func wanted() -> bool:
	if OS.get_cmdline_user_args().has("--touchui"):
		return true
	# A handheld with real controls (the Steam Deck launcher) keeps its
	# screen clear: menus still take taps, the gameplay buttons stay away.
	if Game.is_handheld():
		return false
	return DisplayServer.is_touchscreen_available()


## Make every tappable widget under root respond to raw screen touches.
## The GUI system never routes ScreenTouch to controls while mouse
## emulation is off (verified: neither BaseButton nor gui_input see the
## events), so a TapCatcher hit-tests the widgets from _unhandled_input —
## the studio's tap_at pattern — and activates them directly: Buttons
## emit pressed, CheckBoxes toggle with their signal, LineEdits focus
## (which raises the virtual keyboard on device).
static func wire_taps(root: Node) -> void:
	var catcher := TapCatcher.new()
	catcher.root = root
	root.add_child(catcher)


class TapCatcher extends Node:
	## A touch is a TAP when it lifts within this many px of where it
	## landed; anything that travels farther was a scroll (v1.14: taps used
	## to fire on touch-DOWN, so every attempt to drag-scroll OPTIONS
	## toggled the row the finger started on — twice on Reset = wiped).
	const TAP_SLOP_PX := 14.0

	var root: Node
	var _down := {}          # touch index → [Control, landing position]
	var _scroll_rest := 0.0  # sub-pixel scroll carried between drag events

	func _ready() -> void:
		# Overlay widgets must stay tappable under a paused tree.
		process_mode = Node.PROCESS_MODE_ALWAYS

	## Drags are taken in _input, BEFORE the GUI: Godot routes a screen drag
	## to the widget under the finger and swallows it, so started on any
	## OPTIONS row it never reached _unhandled_input — the panel could only
	## scroll from the gaps between rows (found by the v1.14 --touchtest).
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenDrag:
			var drag := event as InputEventScreenDrag
			# A finger that strays past the slop is scrolling, not tapping.
			if _down.has(drag.index) and drag.position.distance_to(
					_down[drag.index][1]) > TAP_SLOP_PX:
				_down.erase(drag.index)
			# Finger drags scroll any visible ScrollContainer under them
			# (the GUI's own touch panning never fires with mouse emulation
			# off). Fractions carry over, so slow drags on a scaled phone
			# screen still move it.
			for n: Node in root.find_children("*", "ScrollContainer", true, false):
				var sc := n as ScrollContainer
				if _tappable(sc) and sc.get_global_rect().has_point(drag.position):
					_scroll_rest += drag.relative.y
					var step := int(_scroll_rest)
					_scroll_rest -= step
					sc.scroll_vertical -= step
					get_viewport().set_input_as_handled()
					return

	func _unhandled_input(event: InputEvent) -> void:
		if not (event is InputEventScreenTouch):
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var hit := _hit(touch.position)
			if hit != null:
				_down[touch.index] = [hit, touch.position]
				get_viewport().set_input_as_handled()
			return
		# Released: activate only a clean tap that still sits on its widget.
		if not _down.has(touch.index):
			return
		var entry: Array = _down[touch.index]
		_down.erase(touch.index)
		var target: Control = entry[0]
		if not is_instance_valid(target) or _hit(touch.position) != target:
			return
		get_viewport().set_input_as_handled()
		target.grab_focus()
		if target is LineEdit:
			return   # focus is the action; typing comes from the keyboard
		var btn := target as BaseButton
		if btn.disabled:
			return
		if btn.toggle_mode:
			# The setter emits `toggled` itself (emitting again ran every
			# toggle handler twice).
			btn.button_pressed = not btn.button_pressed
		else:
			btn.pressed.emit()

	## The topmost tappable widget under a point (later tree order draws on
	## top, so the last hit wins), or null.
	func _hit(pos: Vector2) -> Control:
		var hit: Control = null
		for n: Node in root.find_children("*", "BaseButton", true, false) \
				+ root.find_children("*", "LineEdit", true, false):
			var c := n as Control
			if _tappable(c) and c.get_global_rect().has_point(pos) \
					and _inside_scroll_view(c, pos):
				hit = c
		return hit

	## is_visible_in_tree() IGNORES CanvasLayer visibility, so buttons on a
	## hidden overlay layer would still swallow taps (e.g. the pause menu's
	## widgets mid-game). Check every CanvasLayer ancestor explicitly.
	func _tappable(c: Control) -> bool:
		if not c.is_visible_in_tree():
			return false
		var n: Node = c.get_parent()
		while n != null:
			if n is CanvasLayer and not (n as CanvasLayer).visible:
				return false
			n = n.get_parent()
		return true

	## A widget scrolled out of its ScrollContainer still has a screen rect
	## (above or below the panel) — only the visible window counts.
	func _inside_scroll_view(c: Control, pos: Vector2) -> bool:
		var n: Node = c.get_parent()
		while n != null:
			if n is ScrollContainer \
					and not (n as ScrollContainer).get_global_rect().has_point(pos):
				return false
			n = n.get_parent()
		return true


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_face = Node2D.new()
	add_child(_face)
	_face.draw.connect(_draw_face)


func _process(delta: float) -> void:
	for k: String in _flash.keys():
		_flash[k] = _flash[k] - delta
		if _flash[k] <= 0.0:
			_flash.erase(k)
	_face.queue_redraw()


## The live button set. Move buttons yield to tilt steering when it is on
## and a gravity sensor actually answers; everything hides while paused
## (the pause overlay's own wired buttons take over) and after the win.
func _buttons() -> Array:
	if not _live():
		return []
	var btns: Array = [
		{"kind": "pause", "c": Vector2(1246.0, 26.0), "r": 22.0,
			"action": "pause", "hold": false},
		{"kind": "boost", "c": Vector2(1185.0, 470.0), "r": 48.0,
			"action": "launch", "hold": false},
	]
	var tilting: bool = Game.tilt_control \
		and Input.get_gravity().length_squared() > 4.0
	if not tilting:
		btns.append({"kind": "left", "c": Vector2(95.0, 628.0), "r": 58.0,
			"action": "move_left", "hold": true})
		btns.append({"kind": "right", "c": Vector2(1185.0, 628.0), "r": 58.0,
			"action": "move_right", "hold": true})
	return btns


## Gameplay input is live: arena running, not paused, not won.
func _live() -> bool:
	return main != null and not get_tree().paused and not main.get("_won")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position, event.index)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _steer:
			_steer_travel = maxf(_steer_travel,
				event.position.distance_to(_steer_from))
			if _live():
				paddle.steer_touch(event.position.x)
		elif _held.has(event.index):
			# Finger slid off its hold button → let go of the action.
			var still := false
			for b: Dictionary in _buttons():
				if b.hold and b.action == _held[event.index] \
						and event.position.distance_to(b.c) <= b.r + 24.0:
					still = true
					break
			if not still:
				_release(event.index)


func _press(pos: Vector2, index: int) -> void:
	for b: Dictionary in _buttons():
		if pos.distance_to(b.c) > b.r + 6.0:
			continue
		if b.hold:
			_held[index] = b.action
			_held_count[b.action] = int(_held_count.get(b.action, 0)) + 1
			Input.action_press(b.action)
		else:
			_fire(b.action)
			_flash[b.kind] = FLASH_S
		return
	# Off the buttons: this finger steers (one at a time).
	if _steer < 0 and _live() and paddle != null:
		_steer = index
		_steer_t0 = Time.get_ticks_msec()
		_steer_from = pos
		_steer_travel = 0.0
		paddle.steer_touch(pos.x)


func _release(index: int) -> void:
	if index == _steer:
		_steer = -1
		if paddle != null:
			paddle.release_touch()
		var quick := Time.get_ticks_msec() - _steer_t0 <= int(TAP_MAX_S * 1000.0)
		if quick and _steer_travel <= TAP_MAX_PX and _live() \
				and ball != null and not ball.is_flying():
			_fire("launch")
		return
	if not _held.has(index):
		return
	var action: String = _held[index]
	_held.erase(index)
	_held_count[action] = int(_held_count.get(action, 1)) - 1
	if _held_count[action] <= 0:
		_held_count.erase(action)
		Input.action_release(action)


## A thumb still on ◀ when the arena reloads or closes (AGAIN, RESTART,
## MAIN MENU tapped with the other hand) never lifts on this instance —
## release everything so the next run doesn't start sliding.
func _exit_tree() -> void:
	for action: String in _held_count:
		Input.action_release(action)
	_held.clear()
	_held_count.clear()
	if _steer >= 0 and paddle != null and is_instance_valid(paddle):
		paddle.release_touch()


## One-shot action tap (press + release), as if a key were struck.
func _fire(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)


func _is_down(b: Dictionary) -> bool:
	if _flash.has(b.kind):
		return true
	return b.hold and _held.values().has(b.action)


func _draw_face() -> void:
	for b: Dictionary in _buttons():
		var down := _is_down(b)
		var c: Vector2 = b.c
		var r: float = b.r
		_face.draw_circle(c, r, Color(COL.r, COL.g, COL.b,
			0.2 if down else 0.09))
		_face.draw_arc(c, r, 0.0, TAU, 48, Color(COL.r, COL.g, COL.b,
			0.85 if down else 0.38), 2.0, true)
		var g := Color(0.85, 1.0, 0.97, 0.95 if down else 0.6)
		match b.kind:
			"left":
				_face.draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.42, 0), c + Vector2(r * 0.24, -r * 0.36),
					c + Vector2(r * 0.24, r * 0.36)]), g)
			"right":
				_face.draw_colored_polygon(PackedVector2Array([
					c + Vector2(r * 0.42, 0), c + Vector2(-r * 0.24, -r * 0.36),
					c + Vector2(-r * 0.24, r * 0.36)]), g)
			"boost":
				# lightning bolt
				_face.draw_colored_polygon(PackedVector2Array([
					c + Vector2(6, -r * 0.52), c + Vector2(-10, r * 0.1),
					c + Vector2(-1, r * 0.1), c + Vector2(-6, r * 0.52),
					c + Vector2(10, -r * 0.1), c + Vector2(1, -r * 0.1)]), g)
			"pause":
				_face.draw_rect(Rect2(c + Vector2(-7, -8), Vector2(5, 16)), g)
				_face.draw_rect(Rect2(c + Vector2(2, -8), Vector2(5, 16)), g)
