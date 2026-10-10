extends CharacterBody2D
class_name Ball
## Ball — vivid glowing turquoise, custom-integrated physics.
##
## The twist ("heavy and juicy"): gravity is GENTLE inside the arena, so a
## cruising ball floats — but paddle deflections SLAM it with a power boost
## that decays back toward cruise speed. Block bounces add a smaller kick.
## Missing the paddle lets the ball sail out above the camera (the side
## rails extend far past the view, so it can never be lost); stronger
## off-screen gravity brings it back within a couple of seconds.
##
## Visuals: additive halo + drawn hot core (vector), a tapering Line2D trail
## in world space, and a continuous soft smoke that dims as it drifts.
## main.gd listens to the signals and owns shake/sound/score reactions.

signal launched
signal paddle_bounced(power: float)          # power 0..1 for pitch/shake
signal paddle_tapped                          # soft top/side touch, no slam
signal block_bounced(block: Block, at: Vector2)
signal wall_bounced(at: Vector2)
signal boosted(power: float)                  # player fired the Space boost
signal left_screen                            # sailed out over the top

## Gentle in-arena gravity (px/s²) — the "slow" force of the game.
const GRAVITY_IN := 130.0
## Strong gravity above the camera so a missed ball returns fast.
const GRAVITY_ABOVE := 850.0
## Upward speed is capped when crossing the top edge (bounds the round trip).
const EXIT_SPEED_CAP := 540.0
const CRUISE_SPEED := 430.0
const MAX_SPEED := 1400.0
const MIN_SPEED := 250.0
## Fraction/s of excess speed bled back toward cruise.
const POWER_DRAG := 0.28
const PADDLE_BOOST_MUL := 1.12
const PADDLE_BOOST_ADD := 150.0
const PADDLE_MIN_EXIT := 560.0
const BLOCK_BOOST_ADD := 26.0
const RADIUS := 9.0
## Velocity may never get flatter than this |vy|/speed after a bounce
## (prevents endless horizontal ping-pong between the rails).
const MIN_VERTICAL_RATIO := 0.16
## The paddle's TOP and sides are passive: the ball bounces off softly with
## this energy fraction — no slam, no boost. Only the bottom face is the cannon.
const TOP_BOUNCE_DAMP := 0.45
## Side faces DO add energy — a shove that inherits the paddle's swing.
const SIDE_BOOST_MUL := 1.08
const SIDE_BOOST_ADD := 90.0
## Space mid-flight: instant extra speed along the travel direction, on a
## cooldown so it can't chain into an unlimited frenzy.
const BOOST_ADD := 460.0
const BOOST_COOLDOWN_S := 2.5
## Glow tints: turquoise cruising, a flash of magenta while a boost burns.
const GLOW_COL := Color(0.0, 1.0, 0.88)
const BOOST_GLOW_COL := Color(1.0, 0.16, 0.92)

## Play area for the ball's center (set by main before _ready): rails,
## floor and the far top of the rails.
var arena := Rect2()

var _flying := false
var _run_over := false
var _boost_cd := 0.0
var _was_above := false
var _paddle: Paddle
var _trail: Line2D
var _smoke: CPUParticles2D
var _glow: Sprite2D
var _core: Node2D
var _pulse: Tween
var _tint_tween: Tween


func _init(paddle: Paddle = null) -> void:
	_paddle = paddle


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	z_index = 10   # above the blocks; the trail/smoke children ride along
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	# Halo: big soft additive radial glow. The texture is WHITE and the color
	# lives in self_modulate, so the boost can tint the whole halo magenta.
	_glow = Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.gradient = Gradient.new()
	tex.gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.5))
	tex.gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	_glow.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.scale = Vector2.ONE * 0.9
	_glow.self_modulate = GLOW_COL
	add_child(_glow)

	_core = BallCore.new()
	add_child(_core)

	# World-space trail: turquoise ribbon tapering to nothing.
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.position = Vector2.ZERO
	_trail.width = 14.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.12))
	curve.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.9, 0.8, 0.0))
	grad.set_color(1, Color(0.35, 1.0, 0.93, 0.55))
	_trail.gradient = grad
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	var tmat := CanvasItemMaterial.new()
	tmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = tmat
	add_child(_trail)

	# Smoke: soft dim puffs shed along the path, drifting up and fading —
	# the "beautiful smoke before dimming".
	_smoke = CPUParticles2D.new()
	_smoke.local_coords = false
	_smoke.amount = 46
	_smoke.lifetime = 0.85
	_smoke.direction = Vector2.UP
	_smoke.spread = 40.0
	_smoke.gravity = Vector2(0.0, -26.0)
	_smoke.initial_velocity_min = 4.0
	_smoke.initial_velocity_max = 16.0
	_smoke.scale_amount_min = 0.28
	_smoke.scale_amount_max = 0.6
	_smoke.scale_amount_curve = _fade_curve()
	_smoke.color = Color(0.1, 0.85, 0.78, 0.32)
	_smoke.color_ramp = _smoke_ramp()
	_smoke.texture = _soft_dot()
	var smat := CanvasItemMaterial.new()
	smat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_smoke.material = smat
	_smoke.emitting = false
	add_child(_smoke)

	reset_to_paddle()


## Park under the paddle, waiting for launch.
func reset_to_paddle() -> void:
	_flying = false
	_was_above = false
	velocity = Vector2.ZERO
	if _paddle != null:
		global_position = _paddle.global_position + Vector2(0.0, 26.0)
	_trail.clear_points()
	_smoke.emitting = false


func launch() -> void:
	if _flying:
		return
	_flying = true
	var tilt := Game.rng.randf_range(-0.25, 0.25)
	velocity = Vector2(tilt, 1.0).normalized() * PADDLE_MIN_EXIT
	_smoke.emitting = true
	launched.emit()


func is_flying() -> bool:
	return _flying


## The run has ended (win / TIME!): the ball keeps flying behind the
## overlay as scenery, but Space / A / click no longer boost it — those
## presses belong to the overlay's buttons now.
func end_run() -> void:
	_run_over = true


## Power 0..1 — how far above cruise speed we are (drives visuals + pitch).
func power() -> float:
	return clampf((velocity.length() - CRUISE_SPEED) / (MAX_SPEED - CRUISE_SPEED),
		0.0, 1.0)


func _physics_process(delta: float) -> void:
	if not _flying:
		# Ride along under the paddle.
		global_position = _paddle.global_position + Vector2(0.0, 26.0)
		if Input.is_action_just_pressed("launch"):
			launch()
		return

	# Boost: Space mid-flight kicks the ball along its current heading.
	_boost_cd = maxf(_boost_cd - delta, 0.0)
	if not _run_over and _boost_cd <= 0.0 \
			and Input.is_action_just_pressed("launch"):
		_do_boost()

	var above := global_position.y < -30.0
	if above and not _was_above:
		left_screen.emit()
	_was_above = above

	# The twist: floaty gravity in view, heavy hand above the roofline.
	velocity.y += (GRAVITY_ABOVE if above else GRAVITY_IN) * delta
	# Bleed excess power back toward cruise so paddle slams matter but fade.
	var speed := velocity.length()
	if speed > CRUISE_SPEED:
		speed = maxf(speed - (speed - CRUISE_SPEED) * POWER_DRAG * delta,
			CRUISE_SPEED)
		velocity = velocity.normalized() * speed
	# Crossing the top edge upward: cap the climb so the trip stays short.
	if global_position.y < 0.0 and velocity.y < -EXIT_SPEED_CAP:
		velocity.y = -EXIT_SPEED_CAP

	_unwedge_at_rail()
	var motion := velocity * delta
	for i in 4:
		var hit := move_and_collide(motion)
		if hit == null:
			break
		var normal := hit.get_normal()
		var collider := hit.get_collider()
		if collider is Paddle:
			if normal.y > 0.5:
				# struck the bottom face from below: the cannon
				_deflect_off_paddle()
			elif absf(normal.x) > 0.5:
				# side face: a real shove — reflect, inherit the paddle's
				# swing, and gain energy (smaller than the cannon's slam).
				velocity = velocity.bounce(normal)
				velocity.x += clampf(_paddle.velocity_x * 0.4, -420.0, 420.0)
				velocity = velocity.normalized() * clampf(
					velocity.length() * SIDE_BOOST_MUL + SIDE_BOOST_ADD,
					MIN_SPEED, MAX_SPEED)
				_enforce_liveliness()
				_paddle.punch()
				_pulse_glow()
				paddle_bounced.emit(power())
			else:
				# top: a soft, dampened bounce — the ball just pops up and
				# gravity brings it home past the paddle.
				velocity = velocity.bounce(normal) * TOP_BOUNCE_DAMP
				velocity.x += clampf(_paddle.velocity_x * 0.15, -160.0, 160.0)
				_enforce_liveliness()
				paddle_tapped.emit()
		else:
			velocity = velocity.bounce(normal)
			_enforce_liveliness()
			if collider is Block:
				velocity = velocity.normalized() \
					* minf(velocity.length() + BLOCK_BOOST_ADD, MAX_SPEED)
				block_bounced.emit(collider as Block, hit.get_position())
			else:
				wall_bounced.emit(hit.get_position())
		motion = velocity.normalized() * hit.get_remainder().length()
	_keep_in_arena()
	_update_visuals(delta)


## The paddle moves kinematically (teleports), so it can land ON the ball.
## Mid-field that's the side swat — physics depenetrates sideways and the
## side face shoves (kept). But with no room between the paddle's end and
## a rail, sideways is INTO the rail: pop the ball out vertically instead,
## on the side its center is on, heading away.
func _unwedge_at_rail() -> void:
	if _paddle == null or arena.size == Vector2.ZERO:
		return
	var d := global_position - _paddle.global_position
	var half := Vector2(Paddle.WIDTH, Paddle.HEIGHT) * 0.5 + Vector2.ONE * RADIUS
	if absf(d.x) >= half.x or absf(d.y) >= half.y:
		return
	var room_left := _paddle.global_position.x - Paddle.WIDTH * 0.5 - arena.position.x
	var room_right := arena.end.x - (_paddle.global_position.x + Paddle.WIDTH * 0.5)
	var squeezed := (d.x < 0.0 and room_left < RADIUS * 2.0 + 1.0) \
		or (d.x >= 0.0 and room_right < RADIUS * 2.0 + 1.0)
	if not squeezed:
		return
	if d.y >= 0.0:
		global_position.y = _paddle.global_position.y + half.y + 0.5
		velocity.y = absf(velocity.y)
	else:
		global_position.y = _paddle.global_position.y - half.y - 0.5
		velocity.y = -absf(velocity.y)


## Last-resort net: whatever the solver does, the ball's center stays
## inside the play area (reflecting off the bound it touched).
func _keep_in_arena() -> void:
	if arena.size == Vector2.ZERO:
		return
	var p := global_position
	if p.x < arena.position.x + RADIUS:
		p.x = arena.position.x + RADIUS
		velocity.x = absf(velocity.x)
	elif p.x > arena.end.x - RADIUS:
		p.x = arena.end.x - RADIUS
		velocity.x = -absf(velocity.x)
	if p.y > arena.end.y - RADIUS:
		p.y = arena.end.y - RADIUS
		velocity.y = -absf(velocity.y)
	global_position = p


## The paddle is a cannon: ANY contact fires the ball back down toward the
## blocks, aimed by where it struck along the face, with the paddle's own
## motion adding english — and a power boost. This is the heavy hit.
func _deflect_off_paddle() -> void:
	var offset := clampf((global_position.x - _paddle.global_position.x)
		/ (Paddle.WIDTH * 0.55), -1.0, 1.0)
	var english := clampf(_paddle.velocity_x / 2400.0, -0.35, 0.35)
	# tiny jitter so a perfectly centered hit can't lock into a vertical rail
	var jitter := Game.rng.randf_range(-0.03, 0.03)
	var dir := Vector2(offset * 0.85 + english + jitter, 1.0).normalized()
	var speed := clampf(velocity.length() * PADDLE_BOOST_MUL + PADDLE_BOOST_ADD,
		PADDLE_MIN_EXIT, MAX_SPEED)
	velocity = dir * speed
	_paddle.punch()
	_pulse_glow()
	paddle_bounced.emit(power())


## Boost charge for the HUD: 0 just used → 1 ready.
func boost_charge() -> float:
	return 1.0 - _boost_cd / BOOST_COOLDOWN_S


func _do_boost() -> void:
	if not _flying or velocity.length() < 0.001:
		return
	_boost_cd = BOOST_COOLDOWN_S
	velocity = velocity.normalized() \
		* minf(velocity.length() + BOOST_ADD, MAX_SPEED)
	_pulse_glow()
	# The afterburner signature: the halo burns magenta, then cools back.
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	_glow.self_modulate = BOOST_GLOW_COL
	_tint_tween = create_tween()
	_tint_tween.tween_property(_glow, "self_modulate", GLOW_COL, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	boosted.emit(power())


## Post-bounce sanity: keep a minimum speed and never leave the velocity so
## flat it ping-pongs between the rails forever.
func _enforce_liveliness() -> void:
	var speed := velocity.length()
	if speed < MIN_SPEED:
		velocity = velocity.normalized() * MIN_SPEED if speed > 0.001 \
			else Vector2(0.2, 1.0).normalized() * MIN_SPEED
		speed = MIN_SPEED
	if absf(velocity.y) < speed * MIN_VERTICAL_RATIO:
		var sign_y := -1.0 if velocity.y < 0.0 else 1.0
		velocity.y = sign_y * speed * MIN_VERTICAL_RATIO
		velocity = velocity.normalized() * speed


func _update_visuals(delta: float) -> void:
	var p := power()
	_glow.scale = Vector2.ONE * (0.9 + p * 1.1)
	_trail.width = 12.0 + p * 14.0
	_smoke.color.a = 0.22 + p * 0.3
	# Trail follows in world space; drop tail points as it dims.
	_trail.add_point(global_position)
	while _trail.get_point_count() > 26:
		_trail.remove_point(0)
	# also shrink the tail when idling so a slow ball keeps a short wisp
	if _trail.get_point_count() > 8 and Engine.get_physics_frames() % 3 == 0 \
			and velocity.length() < CRUISE_SPEED + 1.0:
		_trail.remove_point(0)
	if delta > 0.0 and _core != null:
		_core.rotation += delta * (2.0 + p * 9.0)


func _pulse_glow() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_glow.scale = Vector2.ONE * 2.6
	_pulse = create_tween()
	_pulse.tween_property(_glow, "scale", Vector2.ONE * (0.9 + power() * 1.1),
		0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fade_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.15))
	return c


func _smoke_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 1.0, 0.95, 0.5))
	g.set_color(1, Color(0.02, 0.35, 0.4, 0.0))
	return g


## Soft round dot texture for smoke puffs (engine radial gradient — still
## resolution-independent).
func _soft_dot() -> Texture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = Gradient.new()
	tex.gradient.set_color(0, Color(1, 1, 1, 1))
	tex.gradient.set_color(1, Color(1, 1, 1, 0))
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 48
	tex.height = 48
	return tex


## Drawn core: white-hot heart inside a vivid turquoise disc, with two tiny
## orbit flecks that spin faster as power rises. Pure vector.
class BallCore:
	extends Node2D

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 9.0, Color("00e5cd"), true, -1.0, true)
		draw_circle(Vector2.ZERO, 5.0, Color("bffff6"), true, -1.0, true)
		draw_circle(Vector2.ZERO, 2.6, Color(1, 1, 1), true, -1.0, true)
		draw_circle(Vector2(7.0, 0.0), 1.5, Color(0.7, 1.0, 0.96, 0.8),
			true, -1.0, true)
		draw_circle(Vector2(-7.0, 0.0), 1.5, Color(0.7, 1.0, 0.96, 0.8),
			true, -1.0, true)
