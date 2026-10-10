extends Camera2D
class_name GameCamera
## GameCamera — fixed framing + trauma screen shake (model reused from the
## Prescription Games shared toolkit). add_shake() adds trauma; trauma decays
## linearly and the applied offset is trauma² × noise, so small hits whisper
## and big ones slam. Respects Game.screen_shake.

## Hard cap on shake displacement, px.
const SHAKE_MAX_PX := 26.0
## Trauma units drained per second.
const SHAKE_DECAY := 1.9
## Shake wobble frequency, Hz-ish.
const SHAKE_FREQ := 15.0
## add_shake(strength) divides by this to become trauma; strength ~14 = max.
const SHAKE_STRENGTH_TO_TRAUMA := 14.0

var _trauma := 0.0
var _t := 0.0
var _base_pos := Vector2.ZERO


func _ready() -> void:
	_base_pos = position
	# Camera2D ignores its own rotation by default, which silently dropped
	# the shake's small rotational component — opt in (v1.14).
	ignore_rotation = false
	make_current()


## strength ~2 = tick, ~6 = solid hit, ~14 = full slam.
func add_shake(strength := 6.0) -> void:
	if not Game.screen_shake:
		return
	_trauma = clampf(_trauma + strength / SHAKE_STRENGTH_TO_TRAUMA, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
			rotation = 0.0
		return
	_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
	_t += delta * SHAKE_FREQ
	var amt := _trauma * _trauma
	# Two incommensurate sines per axis fake smooth noise well enough here,
	# with the per-hit random phase Game.rng gives via add_shake timing.
	offset = Vector2(
		sin(_t * TAU * 1.13 + 1.7) + 0.6 * sin(_t * TAU * 2.71),
		cos(_t * TAU * 0.97) + 0.6 * sin(_t * TAU * 2.23 + 0.5)
	) * SHAKE_MAX_PX * amt * 0.625
	rotation = 0.012 * amt * sin(_t * TAU * 0.83 + 2.4)
