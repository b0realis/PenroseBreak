extends StaticBody2D
class_name Block
## Block — one brick of the bottom wall. Five hits: turquoise → three lighter
## turquoise stages → light blue → white flash + destroyed. All visuals are
## vector: the body is drawn (rounded rect + top highlight), hit feedback is
## a white flash + scale punch + spark burst, destruction adds a shard burst
## and an expanding glow ring (built by main.gd so it can outlive the block).
##
## main.gd connects [signal destroyed] to count the wall down and owns every
## camera/background/audio reaction; the block only knows its own body.

## Emitted once, right before the node frees itself.
signal destroyed(block: Block)

## Display colors per stage (hits taken so far 0..4). A clearly readable
## ladder — turquoise, green, yellow, blue, then WHITE: the armed state,
## breathing softly. The next impact bursts it.
const STAGE_COLORS: Array[Color] = [
	Color("0fb8ad"),  # vivid turquoise — fresh
	Color("3ddc55"),  # green
	Color("ffd744"),  # yellow
	Color("4aa8ff"),  # blue
	Color("ffffff"),  # white — armed, bursts on the next hit
]
const FLASH_WHITE := Color("ffffff")
## Hits to destroy = STAGE_COLORS.size() (the final hit bursts the white block).
const PUNCH_SCALE := Vector2(1.18, 1.32)
const PUNCH_S := 0.14

var size := Vector2(112.0, 30.0)

var _hits := 0
var _dead := false          # guards re-entry between _die() and queue_free
var _body: Node2D           # scaled/tinted visual (collision shape stays put)
var _shape: CollisionShape2D
var _tween: Tween
var _pulse_tween: Tween


func _init(block_size := Vector2(112.0, 30.0)) -> void:
	size = block_size


func _ready() -> void:
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	add_child(_shape)

	_body = Node2D.new()
	var visual := BlockVisual.new()
	visual.size = size
	_body.add_child(visual)
	add_child(_body)
	_apply_color(STAGE_COLORS[0], false)


## Returns true when this hit destroyed the block. A corpse waiting for its
## deferred free (the ball can graze it twice in one physics tick) absorbs
## the hit silently — destroyed must only ever fire once.
func take_hit() -> bool:
	if _dead:
		return false
	_hits += 1
	if _hits >= STAGE_COLORS.size():
		_die()
		return true
	_apply_color(STAGE_COLORS[_hits], true)
	_punch()
	_sparks(STAGE_COLORS[_hits], 6, 90.0)
	if _hits == STAGE_COLORS.size() - 1:
		_arm_pulse()
	return false


## Progress 0..1 toward destruction (drives hit sound pitch in main.gd).
func damage_ratio() -> float:
	return float(_hits) / float(STAGE_COLORS.size())


func _apply_color(col: Color, flash: bool) -> void:
	if not flash:
		_body.modulate = col
		return
	# The impact flash is white — except when the NEW stage is itself white,
	# where a turquoise blink keeps the hit readable.
	_body.modulate = Color("7ffff2") if col.is_equal_approx(FLASH_WHITE) \
		else FLASH_WHITE
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_body, "modulate", col, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_body, "scale", Vector2.ONE, PUNCH_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _punch() -> void:
	_body.scale = PUNCH_SCALE


## The white armed stage breathes gently — a quiet fuse — until the burst.
## Starts after the impact flash has settled so the two tweens never fight.
func _arm_pulse() -> void:
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_interval(0.25)
	_pulse_tween.tween_property(_body, "modulate",
		Color(0.78, 1.0, 0.96), 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_body, "modulate", FLASH_WHITE, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Small spark burst in the block color; frees itself when done.
func _sparks(col: Color, count: int, speed: float) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0.0, 260.0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 1.6
	p.scale_amount_max = 3.4
	p.color = col.lightened(0.25)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.finished.connect(p.queue_free)
	# Parent to our parent so the burst survives if the block dies mid-flight.
	get_parent().add_child(p)
	p.global_position = global_position


func _die() -> void:
	# White flash + shard burst; the block itself vanishes now, main.gd adds
	# the ring/shake/hit-stop spectacle.
	_dead = true
	_shape.set_deferred("disabled", true)
	_sparks(FLASH_WHITE, 14, 240.0)
	_sparks(_burst_color(), 10, 160.0)
	destroyed.emit(self)
	queue_free()


## Tint of the colored half of the death burst; PenroseTile returns its own
## picked color.
func _burst_color() -> Color:
	return STAGE_COLORS[0]


## Inner drawn visual, kept separate so Block can scale/tint it freely while
## the collision shape stays fixed. Drawn in white; the parent's modulate
## supplies the stage color.
class BlockVisual:
	extends Node2D

	var size := Vector2(112.0, 30.0)

	func _draw() -> void:
		var r := Rect2(-size * 0.5, size)
		var corner := 5.0
		# soft under-glow pad
		draw_rect(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)),
			Color(1, 1, 1, 0.14))
		# body
		_draw_round_rect(r, corner, Color(1, 1, 1, 1))
		# top highlight strip (reads as beveled glass)
		var strip := Rect2(r.position + Vector2(5, 4), Vector2(r.size.x - 10, 5))
		draw_rect(strip, Color(1, 1, 1, 0.45))
		# bottom shade line
		draw_rect(Rect2(r.position + Vector2(5, r.size.y - 7),
			Vector2(r.size.x - 10, 3)), Color(0, 0, 0, 0.18))

	func _draw_round_rect(r: Rect2, corner: float, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(corner))
		draw_style_box(sb, r)
