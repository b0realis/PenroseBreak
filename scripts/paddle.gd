extends StaticBody2D
class_name Paddle
## Paddle — the deflector at the TOP of the screen. Kinematic: follows the
## mouse x directly and/or move_left/move_right at KEY_SPEED (a gamepad
## stick scales that speed by its tilt), clamped to the rails; a steering
## finger (TouchControls) drags it like the mouse; on mobile with
## Game.tilt_control, the device's gravity sensor steers like an analog
## stick. Priority: keys/pad/move buttons > finger > tilt > mouse.
## Velocity is tracked so the ball can inherit "english" on deflect.
## Vector visual: drawn rounded slab + additive glow halo; hit feedback is a
## squash punch + upward recoil.

const WIDTH := 150.0
const HEIGHT := 22.0
const KEY_SPEED := 1150.0
## Ignore mouse until it actually moves (so keyboard play isn't hijacked).
const RECOIL_PX := 7.0
## Sideways tilt (m/s² of gravity along screen x) for full steering speed:
## ~3.2 ≈ a 19° lean. Deadzone keeps a resting phone still.
const TILT_FULL_MS2 := 3.2
const TILT_DEADZONE := 0.08
## Flip if steering is inverted on a particular device family.
const TILT_SIGN := -1.0

var velocity_x := 0.0

var _half_span := 640.0
var _center_x := 640.0
var _home_y := 0.0
var _mouse_x := -1.0
var _mouse_active := false
var _touch_x := 0.0
var _touch_active := false
var _visual: Node2D
var _tween: Tween


func _ready() -> void:
	_home_y = position.y
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(WIDTH, HEIGHT)
	shape.shape = rect
	add_child(shape)

	# Additive halo behind the slab.
	var halo := Sprite2D.new()
	var halo_tex := GradientTexture2D.new()
	halo_tex.gradient = Gradient.new()
	halo_tex.gradient.set_color(0, Color(0.06, 1.0, 0.9, 0.28))
	halo_tex.gradient.set_color(1, Color(0.06, 1.0, 0.9, 0.0))
	halo_tex.fill = GradientTexture2D.FILL_RADIAL
	halo_tex.fill_from = Vector2(0.5, 0.5)
	halo_tex.fill_to = Vector2(0.5, 0.0)
	halo_tex.width = 256
	halo_tex.height = 128
	halo.texture = halo_tex
	halo.scale = Vector2(WIDTH * 1.6 / 256.0, HEIGHT * 5.0 / 128.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = mat
	add_child(halo)

	_visual = PaddleVisual.new()
	add_child(_visual)


## Rails the paddle may travel between (block-grid margins, set by main).
func set_span(center_x: float, half_span: float) -> void:
	_center_x = center_x
	_half_span = half_span - WIDTH * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var x := (event as InputEventMouseMotion).position.x
		if _mouse_x < 0.0:
			_mouse_x = x   # first sighting: record only, don't hijack keys
		elif _mouse_active or absf(x - _mouse_x) > 1.5:
			_mouse_active = true
			_mouse_x = x


## Touch steering (TouchControls): while a finger is down on the play area
## the paddle follows its x, exactly like the mouse path.
func steer_touch(x: float) -> void:
	_touch_x = x
	_touch_active = true
	_mouse_active = false


func release_touch() -> void:
	_touch_active = false


func _physics_process(delta: float) -> void:
	var target := position.x
	var key_dir := Input.get_axis("move_left", "move_right")
	var tilt := _tilt_axis()
	if key_dir != 0.0:
		_mouse_active = false   # keys take over until the mouse moves again
		target = position.x + key_dir * KEY_SPEED * delta
	elif _touch_active:
		target = _touch_x
	elif tilt != 0.0:
		_mouse_active = false
		target = position.x + tilt * KEY_SPEED * delta
	elif _mouse_active:
		target = _mouse_x
	target = clampf(target, _center_x - _half_span, _center_x + _half_span)
	velocity_x = (target - position.x) / maxf(delta, 0.0001)
	position.x = target


## Analog steering from the device's gravity sensor, −1..1. Zero whenever
## tilt control is off or no sensor answers (desktop), so it costs nothing
## there. Device y tracks screen x in landscape; reverse-landscape flips.
func _tilt_axis() -> float:
	if not Game.tilt_control:
		return 0.0
	var g := Input.get_gravity()
	if g.length_squared() < 4.0:
		return 0.0
	var horiz := TILT_SIGN * g.y
	if DisplayServer.screen_get_orientation() \
			== DisplayServer.SCREEN_REVERSE_LANDSCAPE:
		horiz = -horiz
	var axis := clampf(horiz / TILT_FULL_MS2, -1.0, 1.0)
	return 0.0 if absf(axis) < TILT_DEADZONE else axis


## Juice on ball contact: squash punch + a small upward recoil, glow pop.
func punch() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_visual.scale = Vector2(1.22, 0.72)
	position.y = _home_y - RECOIL_PX
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_visual, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:y", _home_y, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Drawn slab: turquoise body, hot core line along the striking (bottom)
## edge, soft top shade. Pure vector. (Inner classes don't see the outer
## scope, so the dimensions are restated here.)
class PaddleVisual:
	extends Node2D

	const WIDTH := 150.0
	const HEIGHT := 22.0

	func _draw() -> void:
		var r := Rect2(Vector2(-WIDTH * 0.5, -HEIGHT * 0.5), Vector2(WIDTH, HEIGHT))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("0fb8ad")
		sb.set_corner_radius_all(int(HEIGHT * 0.45))
		draw_style_box(sb, r)
		var core := StyleBoxFlat.new()
		core.bg_color = Color(0.86, 1.0, 0.98, 0.9)
		core.set_corner_radius_all(3)
		# striking edge: the BOTTOM face (the ball comes from below)
		draw_style_box(core, Rect2(Vector2(-WIDTH * 0.5 + 8.0, HEIGHT * 0.5 - 7.0),
			Vector2(WIDTH - 16.0, 4.0)))
		draw_rect(Rect2(Vector2(-WIDTH * 0.5 + 10.0, -HEIGHT * 0.5 + 3.0),
			Vector2(WIDTH - 20.0, 3.0)), Color(1, 1, 1, 0.25))
