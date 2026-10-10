extends Node2D
## Main — the arena (scenes/main.tscn). Everything is built in code, in the
## Prescription Games house style: Penrose backdrop, side rails that extend
## far above the camera (a missed ball can sail out over the roof but never
## sideways), the paddle at the TOP, the breakable wall at the BOTTOM, the
## glowing ball between them, the stopwatch HUD, and the pause/win overlays.
##
## Three game modes (Game.game_mode):
##   "classic" — the 4×10 rectangle block wall, clear it fast;
##   "penrose" — the DEFAULT: the backdrop tiling itself becomes the wall.
##     Rhombi whose centers land in the bottom quarter of the screen turn
##     into breakable PenroseTiles (same five-stage damage ladder as
##     blocks); the vista above stays scenery, and a destroyed tile reveals
##     its dim ghost in the frozen backdrop beneath;
##   "comp" — the Penrose field against a countdown (Game.comp_time_s):
##     break as many tiles as the clock allows.
##
## Flow: ball parks under the paddle → launch starts the clock → every
## paddle deflect slams power into the ball, every block bounce chips a color
## stage off a block (with shake, sparks and a background flash) → the last
## block's death (or the countdown running dry in "comp") ends the run,
## records the best and raises the overlay. R restarts, Esc pauses (on a
## gamepad: Back restarts, Start pauses — see Game._register_inputs).

const VIEW := Vector2(1280.0, 720.0)
## Playfield rails (block grid + paddle both live between these).
const ARENA_LEFT := 40.0
const ARENA_RIGHT := 1240.0
## Side walls continue this far above the camera — the "artificially
## elongated" sides that keep the ball recoverable.
const WALL_TOP := -3200.0
const FLOOR_Y := 700.0
const PADDLE_Y := 90.0

const ROWS := 4
const COLS := 10
const BLOCK_H := 30.0
const BLOCK_GAP := 8.0
## Penrose modes: backdrop rhombi overlapping the strip below this line
## (the bottom quarter of the 720 px screen) become breakable tiles.
const BREAK_TOP_Y := 540.0
## Fixed deal for the constant-field setting: ⌊2³² / φ⌋ — the golden ratio
## seeding the golden-ratio tiling. Same seed → same field, every run.
const FIELD_SEED := 2654435769

const COL_TEXT := Color("d9fffa")
const COL_DIM := Color("55908f")
const COL_ACCENT := Color("19e3d2")

## Launch hint + boost tag per control family (Game.input_scheme); they
## switch live when the player picks up another device. Plain ASCII: the
## fallback font has no controller glyphs.
const HINTS := {
	"keys": "SPACE or CLICK — launch      A/D or mouse — move      SPACE mid-flight — boost",
	"pad": "A — launch      STICK or D-PAD — move      A mid-flight — boost      START — pause",
	"touch": "TAP — launch      DRAG anywhere — move      BOLT button — boost",
}
const BOOST_TAGS := {
	"keys": "BOOST — SPACE",
	"pad": "BOOST — A",
	"touch": "BOOST — BOLT",
}
const AutoTest := preload("res://scripts/dev/autotest.gd")
const FieldTest := preload("res://scripts/dev/field_test.gd")
const InputTest := preload("res://scripts/dev/input_test.gd")

var _camera: GameCamera
var _bg: PenroseBg
var _flash_rect: ColorRect
var _flash_tween: Tween
var _paddle: Paddle
var _ball: Ball
var _mode := "penrose"
var _one_shot := true
var _field_constant := true   # Penrose modes: same deal every run
## Records are set only on comparable fields: classic, or the constant
## Penrose deal. A random deal (30–194 tiles, measured over 1000 deals by
## --fieldtest) is a different race every time — shown, never recorded.
var _ranked := true
const UNRANKED_TEXT := "RANDOM DEAL — UNRANKED (records use the constant field)"
var _blocks_left := 0
var _total_blocks := 0
var _broken := 0
var _comp_frame := 60      # competition time frame in play (seconds)
var _elapsed := 0.0
var _run_ticks := 0          # physics ticks since launch (the stopwatch)
var _running := false
var _won := false
var _paused := false
var _hit_stop_gen := 0       # bumps per hit-stop; only the latest restores
var _hit_stop_end_ms := 0    # real-time end of the running hit-stop

var _timer_label: Label
var _tiles_label: Label
var _win_title: Label
var _hint_label: Label
var _boost_bar: BoostBar
var _hud_layer: CanvasLayer
var _pause_layer: CanvasLayer
var _win_layer: CanvasLayer
var _win_time_label: Label
var _win_best_label: Label
var _win_column: VBoxContainer
var _boost_tag: Label


func _ready() -> void:
	# §cli: `--fieldtest [n]` validates the tiling + wall carving over n
	# deals (scripts/dev/field_test.gd) instead of building an arena.
	if OS.get_cmdline_user_args().has("--fieldtest"):
		var ft := FieldTest.new()
		ft.carve = carve_field
		ft.area = poly_area
		ft.strip = Rect2(ARENA_LEFT, BREAK_TOP_Y,
			ARENA_RIGHT - ARENA_LEFT, FLOOR_Y - BREAK_TOP_Y)
		ft.field_seed = FIELD_SEED
		add_child(ft)
		set_process(false)
		set_process_unhandled_input(false)
		return
	_mode = Game.game_mode
	_comp_frame = Game.comp_time_s
	_one_shot = _mode != "classic" and Game.tile_one_shot
	_field_constant = Game.field_constant
	var args := OS.get_cmdline_user_args()
	if args.has("--autotest") or args.has("--inputtest"):
		# Test runs pin mode, regime and deal locally (the player's saved
		# options are never touched) so runs stay comparable — see
		# scripts/dev/autotest.gd for the flags.
		AutoTest.pin(self, args)
	_ranked = _mode == "classic" or _field_constant
	_build_backdrop()
	_build_walls()
	_build_paddle_and_ball()
	if _mode == "classic":
		_build_blocks()
	else:
		_build_penrose_field()
	_build_hud()
	_build_pause_overlay()
	_build_win_overlay()
	# Overlay buttons answer raw touches (mouse emulation is off); the
	# gameplay button layer itself only appears on touch hardware.
	TouchControls.wire_taps(_pause_layer)
	TouchControls.wire_taps(_win_layer)
	if TouchControls.wanted():
		var touch := TouchControls.new()
		touch.main = self
		touch.paddle = _paddle
		touch.ball = _ball
		add_child(touch)
	_camera = GameCamera.new()
	_camera.position = VIEW * 0.5
	add_child(_camera)
	# §cli: `--touchtest` (startup.gd) taps START via raw touch; arriving
	# here IS the pass signal.
	if args.has("--touchtest"):
		print("touchtest OK: START activated by raw touch")
		get_tree().quit(0)
		return
	# §cli: `--padtest` (startup.gd) drives the menu with gamepad events and
	# presses START with A; arriving here is the pass signal.
	if args.has("--padtest"):
		print("padtest OK: START activated by gamepad")
		get_tree().quit(0)
		return
	# §cli: `--inputtest` drives every gameplay input end to end (pad, keys,
	# touch with --touchui) and finishes by restarting with the pad's Back
	# button — the reloaded arena is the pass signal.
	if Game.has_meta("inputtest_restart"):
		if Input.is_action_pressed("move_left") \
				or Input.is_action_pressed("move_right"):
			printerr("inputtest FAIL: a held move button stayed pressed into the new run")
			get_tree().quit(1)
			return
		print("inputtest OK: Back restarted the run")
		get_tree().quit(0)
		return
	if args.has("--inputtest"):
		var it := InputTest.new()
		it.main = self
		it.paddle = _paddle
		it.ball = _ball
		add_child(it)
		return
	# §cli: `--autotest` (after the `--` separator) runs the headless smoke /
	# soak bot (scripts/dev/autotest.gd): plays, checks invariants, exits 0/1.
	if args.has("--autotest"):
		var bot := AutoTest.new()
		bot.main = self
		bot.ball = _ball
		bot.paddle = _paddle
		add_child(bot)


## The stopwatch counts physics ticks: they run at the real-time rate
## whatever Engine.time_scale is (only their delta shrinks), so hit-stop
## and the win slow-mo can never skew the clock. (v1.14: dividing the
## process delta by time_scale was wrong whenever a hit-stop began
## mid-frame — that frame's delta had been scaled by the OLD value, adding
## ~0.1 s per hardened kill.) Paused → no physics → no time.
func _physics_process(_delta: float) -> void:
	if not _running:
		return
	# Integer ticks, not a float sum of 1/60s (that drifts a tick late).
	_run_ticks += 1
	_elapsed = float(_run_ticks) / Engine.physics_ticks_per_second
	if _mode == "comp" and _elapsed >= _comp_frame:
		_finish_comp(false)


func _process(_delta: float) -> void:
	if _running:
		_timer_label.text = Game.format_time(
			maxf(_comp_frame - _elapsed, 0.0) if _mode == "comp" else _elapsed)
	_boost_bar.set_state(_ball.boost_charge(), _ball.is_flying() and not _won)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _won:
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and not _paused:
		_restart()


# ------------------------------------------------------------- build --------

func _build_backdrop() -> void:
	_bg = PenroseBg.new()
	add_child(_bg)
	if _mode != "classic" and _field_constant:
		# Reproducible arena: re-deal the vista (and thus the wall carved
		# from it) from the fixed seed instead of the session RNG.
		var fixed := RandomNumberGenerator.new()
		fixed.seed = FIELD_SEED
		_bg.generate(VIEW, fixed)
	# Full-screen additive flash the whole world pulses with on hits.
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.05, 0.9, 0.8)
	_flash_rect.modulate.a = 0.0
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash_rect.material = mat
	layer.add_child(_flash_rect)


## One static body carries both rails and the floor, as half-planes
## (WorldBoundaryShape2D): endless upward, so the ball can only ever leave
## the view via the top and always falls back — and solid all the way out,
## so depenetration always pushes INWARD. (v1.14: they were thin segments;
## a paddle teleporting onto a ball at the rail could squeeze its center
## across the line, the rail then pushed it out, and it fell forever.)
func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	add_child(walls)
	# normal points into the play area; distance = normal · (point on line)
	var planes := [
		[Vector2.RIGHT, ARENA_LEFT],
		[Vector2.LEFT, -ARENA_RIGHT],
		[Vector2.UP, -FLOOR_Y],
	]
	for pl: Array in planes:
		var shape := CollisionShape2D.new()
		var wb := WorldBoundaryShape2D.new()
		wb.normal = pl[0]
		wb.distance = pl[1]
		shape.shape = wb
		walls.add_child(shape)
	add_child(RailsVisual.new())


func _build_paddle_and_ball() -> void:
	_paddle = Paddle.new()
	_paddle.position = Vector2(VIEW.x * 0.5, PADDLE_Y)
	add_child(_paddle)
	_paddle.set_span((ARENA_LEFT + ARENA_RIGHT) * 0.5,
		(ARENA_RIGHT - ARENA_LEFT) * 0.5)

	_ball = Ball.new(_paddle)
	_ball.arena = Rect2(ARENA_LEFT, WALL_TOP,
		ARENA_RIGHT - ARENA_LEFT, FLOOR_Y - WALL_TOP)
	add_child(_ball)
	_ball.launched.connect(_on_launched)
	_ball.paddle_bounced.connect(_on_paddle_bounced)
	_ball.paddle_tapped.connect(func() -> void: Sfx.play("wall", 0.1, 0.72))
	_ball.block_bounced.connect(_on_block_bounced)
	_ball.wall_bounced.connect(_on_wall_bounced)
	_ball.boosted.connect(_on_boosted)
	_ball.left_screen.connect(func() -> void: Sfx.play("whoosh"))


## Classic mode: 4 rows × 10 columns, spread evenly between the rails,
## sitting ON the floor.
func _build_blocks() -> void:
	var span := ARENA_RIGHT - ARENA_LEFT
	var block_w := (span - BLOCK_GAP * (COLS + 1)) / COLS
	_blocks_left = ROWS * COLS
	_total_blocks = _blocks_left
	for row in ROWS:
		for col in COLS:
			var block := Block.new(Vector2(block_w, BLOCK_H))
			block.position = Vector2(
				ARENA_LEFT + BLOCK_GAP + block_w * 0.5
					+ col * (block_w + BLOCK_GAP),
				FLOOR_Y - BLOCK_H * 0.5 - (ROWS - 1 - row) * (BLOCK_H + BLOCK_GAP))
			block.destroyed.connect(_on_block_destroyed)
			add_child(block)


## Penrose modes: the arena backdrop itself is the playfield. Every rhombus
## with a meaningful overlap (≥ 30% of its area) of the bottom-quarter strip
## between the rails becomes a breakable PenroseTile, so the wall tiles the
## strip continuously — no interior gaps — while corner slivers hiding
## behind the rails and floor lines stay scenery. The vista is frozen so
## the dim ghost a destroyed tile reveals stays aligned with the remaining
## bodies forever. With the constant-field setting the deal is fixed
## (FIELD_SEED); otherwise every run is a fresh aperiodic patch.
func _build_penrose_field() -> void:
	_bg.freeze()
	_blocks_left = 0
	for r: Array in carve_field(_bg.rhombi()):
		var quad: PackedVector2Array = r[1]
		var center := (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
		var local := PackedVector2Array()
		for p: Vector2 in quad:
			local.append(p - center)
		var tile := PenroseTile.new(local, _one_shot,
			Game.tile_color_thin if r[0] == 0 else Game.tile_color_thick)
		tile.position = center
		tile.destroyed.connect(_on_block_destroyed)
		add_child(tile)
		_blocks_left += 1
	_total_blocks = _blocks_left


## The wall-carving rule, pure (the `--fieldtest` validator runs it over
## hundreds of deals): from PenroseBg.rhombi() pairs, keep every rhombus
## that overlaps the bottom strip. A tile crossing only the strip's TOP
## line sits fully in the open arena — completely reachable, so any overlap
## keeps it and the field's top edge stays continuous. Only tiles poking
## out past the rails or floor need a meaningful share inside (≥ 30%), or
## near-unreachable slivers would join the wall.
static func carve_field(rhombi: Array) -> Array:
	var strip := PackedVector2Array([
		Vector2(ARENA_LEFT, BREAK_TOP_Y), Vector2(ARENA_RIGHT, BREAK_TOP_Y),
		Vector2(ARENA_RIGHT, FLOOR_Y), Vector2(ARENA_LEFT, FLOOR_Y)])
	var out: Array = []
	for r: Array in rhombi:
		var quad: PackedVector2Array = r[1]
		var overlap := 0.0
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(quad, strip):
			overlap += poly_area(piece)
		if overlap <= 0.0:
			continue
		var inside_arena := true
		for p: Vector2 in quad:
			if p.x < ARENA_LEFT - 0.5 or p.x > ARENA_RIGHT + 0.5 \
					or p.y > FLOOR_Y + 0.5:
				inside_arena = false
				break
		if not inside_arena and overlap < poly_area(quad) * 0.3:
			continue
		out.append(r)
	return out


static func poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	# The digital stopwatch, front and center at the roofline. Competition
	# rounds show the remaining time instead and count down.
	var t0 := Game.format_time(_comp_frame) if _mode == "comp" else "0:00.000"
	_timer_label = _make_label(t0, 38, COL_TEXT, true, 3)
	_timer_label.add_theme_font_override("font", _mono_font(true))
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_top = 8.0
	_timer_label.offset_left = -160.0
	_timer_label.offset_right = 160.0
	_hud_layer.add_child(_timer_label)

	# Player name, dim, top-left.
	var who := Game.player_name.strip_edges()
	var name_label := _make_label(who.to_upper() if who != "" else "ANON",
		15, COL_DIM, false, 2)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	name_label.offset_left = 14.0
	name_label.offset_top = 10.0
	name_label.offset_right = 320.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hud_layer.add_child(name_label)

	# Best line, dim, top-right — the record for the mode being played.
	var best_text := ""
	if not _ranked:
		best_text = "RANDOM DEAL — UNRANKED"
	elif _mode == "comp":
		var cb: Array = Game.comp_best(_comp_frame, _one_shot)
		if int(cb[0]) > 0:
			best_text = "BEST (%s)  %d TILES — %s" % [
				Game.format_frame(_comp_frame), cb[0], cb[1]]
	elif Game.clear_best_time(_mode, _one_shot) > 0.0:
		best_text = "BEST %s — %s" % [
			Game.format_time(Game.clear_best_time(_mode, _one_shot)),
			Game.clear_best_name(_mode, _one_shot)]
	if best_text != "":
		var best := _make_label(best_text, 15, COL_DIM, false, 2)
		best.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		best.offset_left = -420.0
		# leave room for the touch ⏸ button in the corner on mobile
		best.offset_right = -64.0 if TouchControls.wanted() else -14.0
		best.offset_top = 10.0
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hud_layer.add_child(best)

	# Competition rounds get a live broken-tile counter under the boost bar.
	if _mode == "comp":
		_tiles_label = _make_label("TILES  0", 22, COL_ACCENT, true, 3)
		_tiles_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_tiles_label.offset_left = -160.0
		_tiles_label.offset_right = 160.0
		_tiles_label.offset_top = 88.0
		_tiles_label.offset_bottom = 116.0
		_hud_layer.add_child(_tiles_label)

	_hint_label = _make_label("", 16, COL_DIM, false, 2)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint_label.offset_top = -40.0
	_hint_label.offset_bottom = -10.0
	_hint_label.offset_left = -400.0
	_hint_label.offset_right = 400.0
	_hud_layer.add_child(_hint_label)

	# Boost charge bar under the stopwatch: fills over the cooldown, pulses
	# when the Space kick is ready.
	_boost_bar = BoostBar.new()
	_boost_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boost_bar.offset_left = -70.0
	_boost_bar.offset_right = 70.0
	_boost_bar.offset_top = 56.0
	_boost_bar.offset_bottom = 66.0
	_boost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_boost_bar)
	_boost_tag = _make_label("", 11, COL_DIM, false, 2)
	_boost_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boost_tag.offset_left = -100.0
	_boost_tag.offset_right = 100.0
	_boost_tag.offset_top = 68.0
	_boost_tag.offset_bottom = 84.0
	_hud_layer.add_child(_boost_tag)
	_apply_scheme()
	Game.scheme_changed.connect(_apply_scheme)


## Prompts follow the control family in hand (keys / pad / touch).
func _apply_scheme() -> void:
	_hint_label.text = HINTS.get(Game.input_scheme, HINTS["keys"])
	_boost_tag.text = BOOST_TAGS.get(Game.input_scheme, BOOST_TAGS["keys"])


# ------------------------------------------------------------ reactions -----

func _on_launched() -> void:
	Sfx.play("launch")
	_running = true
	var tw := create_tween()
	tw.tween_property(_hint_label, "modulate:a", 0.0, 0.4)


func _on_paddle_bounced(power: float) -> void:
	if _won:
		# Behind the results overlay: just a soft thud, no slam spectacle.
		_on_wall_bounced(Vector2.ZERO)
		return
	Sfx.play("paddle", 0.06, 0.9 + power * 0.5)
	_camera.add_shake(3.0 + power * 5.0)
	_flash(0.05 + power * 0.05)
	Game.rumble(0.25 + power * 0.35, power * 0.3, 0.08)


func _on_boosted(power: float) -> void:
	Sfx.play("boost", 0.06, 0.95 + power * 0.3)
	_camera.add_shake(3.5)
	Game.rumble(0.45, 0.2, 0.12)
	_flash(0.07)
	# magenta, matching the ball's afterburner glow
	_ring(_ball.global_position, Color(1.0, 0.3, 0.95, 0.6), 54.0, 0.3)


func _on_block_bounced(block: Block, at: Vector2) -> void:
	# A competition round that ran out of time leaves the ball flying behind
	# the overlay: the surviving tiles turn to wall, so the score (and the
	# HUD counter) stay frozen at the recorded result.
	if _won:
		_on_wall_bounced(at)
		return
	var was_last_stage := block.take_hit()
	if was_last_stage:
		# destruction reactions live in _on_block_destroyed (signal fired
		# inside take_hit); only the impact sound remains here
		Sfx.play("break", 0.05)
		return
	# The visible pitch ladder: a block sings higher as it whitens.
	Sfx.play("block", 0.03, 0.9 + block.damage_ratio() * 0.7)
	# Random screen shake on every block contact, as ordered.
	_camera.add_shake(Game.rng.randf_range(2.2, 4.6))
	_flash(0.05)
	_ring(at, Color(0.4, 1.0, 0.95, 0.5), 26.0, 0.22)


func _on_block_destroyed(block: Block) -> void:
	_blocks_left -= 1
	_broken += 1
	if _tiles_label != null:
		_tiles_label.text = "TILES  %d" % _broken
	if block is PenroseTile and (block as PenroseTile).one_shot:
		# One-shot pace: every contact is a kill, so the full spectacle
		# (big shake + hit-stop) would exhaust — a mini light pop instead.
		_camera.add_shake(Game.rng.randf_range(3.0, 5.5))
		_flash(0.08)
		Game.rumble(0.2, 0.12, 0.06)
		_light_pop(block.global_position, (block as PenroseTile).base_color)
		_ring(block.global_position, Color(1, 1, 1, 0.7), 46.0, 0.28)
	else:
		_camera.add_shake(Game.rng.randf_range(7.0, 10.5))
		_flash(0.22)
		Game.rumble(0.3, 0.55, 0.16)
		_ring(block.global_position, Color(1, 1, 1, 0.85), 60.0, 0.4)
		_ring(block.global_position, Color(0.1, 1.0, 0.9, 0.6), 110.0, 0.55)
		_hit_stop(0.12, 0.05)
	if _blocks_left <= 0:
		if _mode == "comp":
			_finish_comp(true)
		else:
			_win()


func _on_wall_bounced(_at: Vector2) -> void:
	Sfx.play("wall", 0.12)


# ------------------------------------------------------------- effects ------

## Additive full-screen pulse; strength ~0.05 tick, ~0.6 finale.
func _flash(strength: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.modulate.a = minf(_flash_rect.modulate.a + strength, 0.7)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "modulate", Color(1, 1, 1, 0.0), 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Mini light burst for one-shot tile breaks: an additive radial glow in
## the tile's own color that blooms and fades in a blink.
func _light_pop(at: Vector2, col: Color) -> void:
	var s := Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.9),
		Color(col.r, col.g, col.b, 0.5),
		Color(col.r, col.g, col.b, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96
	s.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.position = at
	s.z_index = 15
	s.scale = Vector2.ONE * 0.35
	add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * 1.5, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)


## Expanding vector ring that fades and frees itself.
func _ring(at: Vector2, col: Color, final_radius: float, dur: float) -> void:
	var ring := RingFx.new()
	ring.color = col
	ring.position = at
	ring.z_index = 20
	add_child(ring)
	ring.scale = Vector2.ONE * 0.15
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE * (final_radius / RingFx.RADIUS),
		dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


## Frame-freeze punch: drop time_scale for a moment of real time. When stops
## overlap, the one ending last owns the restore — the last block's 0.05 s
## kill freeze must not cut the 0.45 s win slow-mo short. The timer calls a
## method (not a lambda), so a reload mid-stop simply drops the connection.
func _hit_stop(scale_to: float, real_seconds: float) -> void:
	var end_ms := Time.get_ticks_msec() + int(real_seconds * 1000.0)
	if end_ms < _hit_stop_end_ms:
		return   # a longer stop is already running; let it finish
	_hit_stop_end_ms = end_ms
	_hit_stop_gen += 1
	Engine.time_scale = scale_to
	get_tree().create_timer(real_seconds, true, false, true).timeout.connect(
		_end_hit_stop.bind(_hit_stop_gen))


func _end_hit_stop(gen: int) -> void:
	if gen == _hit_stop_gen:
		Engine.time_scale = 1.0


# ------------------------------------------------------------ win / end -----

func _win() -> void:
	_running = false
	_won = true
	_ball.end_run()
	var final_time := _elapsed
	var is_best := _ranked and Game.submit_time(final_time, _mode, _one_shot)
	Sfx.play("win")
	if is_best:
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void: Sfx.play("best"))
	# The finale: big slam, slow-motion beat, triple ring at the kill site.
	_camera.add_shake(14.0)
	Game.rumble(0.6, 1.0, 0.5)
	_flash(0.55)
	_hit_stop(0.22, 0.45)
	var center := Vector2((ARENA_LEFT + ARENA_RIGHT) * 0.5, FLOOR_Y - 90.0)
	_ring(center, Color(1, 1, 1, 0.9), 340.0, 0.8)
	_ring(center, Color(0.1, 1.0, 0.9, 0.7), 520.0, 1.1)
	_ring(center, Color(0.6, 1.0, 0.97, 0.5), 720.0, 1.4)

	_win_title.text = "WALL DOWN" if _mode == "classic" else "FIELD DOWN"
	_timer_label.text = Game.format_time(final_time)
	_win_time_label.text = Game.format_time(final_time)
	if not _ranked:
		_win_best_label.text = UNRANKED_TEXT
	elif is_best:
		_win_best_label.text = "NEW BEST — %s" \
			% Game.clear_best_name(_mode, _one_shot)
		_win_best_label.add_theme_color_override("font_color", COL_ACCENT)
	elif Game.clear_best_time(_mode, _one_shot) > 0.0:
		_win_best_label.text = "best  %s — %s" % [
			Game.format_time(Game.clear_best_time(_mode, _one_shot)),
			Game.clear_best_name(_mode, _one_shot)]
	_raise_win_overlay()


## Competition rounds end when the countdown runs dry — or early, in glory,
## when the whole field is down. The score is tiles broken, recorded per
## time frame.
func _finish_comp(cleared: bool) -> void:
	if _won:
		return
	_running = false
	_won = true
	_ball.end_run()
	if not cleared:
		_timer_label.text = Game.format_time(0.0)
	var is_best := _ranked and Game.submit_comp(_comp_frame, _broken, _one_shot)
	Sfx.play("win")
	if is_best:
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void: Sfx.play("best"))
	_camera.add_shake(12.0)
	Game.rumble(0.6, 1.0, 0.45)
	_flash(0.5)
	_hit_stop(0.25, 0.4)
	var center := Vector2((ARENA_LEFT + ARENA_RIGHT) * 0.5, FLOOR_Y - 90.0)
	_ring(center, Color(1, 1, 1, 0.9), 340.0, 0.8)
	_ring(center, Color(0.1, 1.0, 0.9, 0.7), 520.0, 1.1)

	_win_title.text = "FIELD CLEARED" if cleared else "TIME!"
	_win_time_label.text = "%d TILES" % _broken
	var cb: Array = Game.comp_best(_comp_frame, _one_shot)
	if not _ranked:
		_win_best_label.text = UNRANKED_TEXT
	elif is_best:
		_win_best_label.text = "NEW BEST (%s) — %s" % [
			Game.format_frame(_comp_frame), cb[1]]
		_win_best_label.add_theme_color_override("font_color", COL_ACCENT)
	elif int(cb[0]) > 0:
		_win_best_label.text = "best (%s)  %d tiles — %s" % [
			Game.format_frame(_comp_frame), cb[0], cb[1]]
	_raise_win_overlay()


## The buttons stay disarmed while the column fades in: the click / Space
## / A that was meant as a boost when the last block died must not land on
## an invisible AGAIN and restart before the player has seen the time.
func _raise_win_overlay() -> void:
	var buttons := _win_layer.find_children("*", "BaseButton", true, false)
	for b: Node in buttons:
		(b as BaseButton).disabled = true
	_win_layer.visible = true
	_win_column.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_win_column, "modulate:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		for b: Node in buttons:
			(b as BaseButton).disabled = false
		var btn := _win_layer.find_child("AgainButton", true, false) as Button
		if btn != null:
			btn.grab_focus())


func _restart() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Game.skip_splash_once = true
	get_tree().change_scene_to_file("res://scenes/startup.tscn")


# ------------------------------------------------------------ overlays ------

func _set_paused(on: bool) -> void:
	_paused = on
	get_tree().paused = on
	# Hiding a control that holds mouse focus makes Godot synthesize a mouse
	# RELEASE on it: a pause button held down while Esc / B / Start resumes
	# would fire (QUIT GAME, MAIN MENU…). Disarm the buttons before hiding;
	# they re-arm when the menu shows again. (Found by --chaos.)
	for b: Node in _pause_layer.find_children("*", "BaseButton", true, false):
		(b as BaseButton).disabled = not on
	if not on:
		# Don't let a hidden pause button keep keyboard / pad focus into
		# play (Godot drops it on hide today; this keeps it explicit).
		get_viewport().gui_release_focus()
	_pause_layer.visible = on
	Sfx.play("ui")
	if on:
		var btn := _pause_layer.find_child("ResumeButton", true, false) as Button
		if btn != null:
			btn.grab_focus()


func _build_pause_overlay() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 20
	_pause_layer.visible = false
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)
	var column := _center_column(_pause_layer)
	column.add_child(_make_label("PAUSED", 44, COL_TEXT, true, 8))
	column.add_child(_spacer(18))
	var resume := _make_menu_button("RESUME")
	resume.name = "ResumeButton"
	resume.pressed.connect(func() -> void: _set_paused(false))
	var restart := _make_menu_button("RESTART")
	restart.pressed.connect(_restart)
	var menu := _make_menu_button("MAIN MENU")
	menu.pressed.connect(_to_menu)
	var quit := _make_menu_button("QUIT GAME")
	quit.pressed.connect(func() -> void: get_tree().quit())
	quit.visible = not OS.has_feature("web")   # a tab can't close itself
	for b: Button in [resume, restart, menu, quit]:
		var wrap := CenterContainer.new()
		wrap.add_child(b)
		column.add_child(wrap)
	# Main is pausable, so its _unhandled_input goes silent while the tree is
	# paused; this always-processing catcher owns the Esc-to-resume path.
	var catcher := PauseCatcher.new()
	catcher.on_cancel = func() -> void:
		if get_tree().paused and not _won:
			_set_paused(false)
	_pause_layer.add_child(catcher)


func _build_win_overlay() -> void:
	_win_layer = CanvasLayer.new()
	_win_layer.layer = 20
	_win_layer.visible = false
	_win_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_win_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.04, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_layer.add_child(dim)
	_win_column = _center_column(_win_layer)
	_win_title = _make_label("WALL DOWN", 56, COL_TEXT, true, 12)
	_win_column.add_child(_win_title)
	_win_column.add_child(_spacer(6))
	_win_time_label = _make_label("0:00.000", 64, COL_ACCENT, true, 4)
	_win_time_label.add_theme_font_override("font", _mono_font(true))
	_win_column.add_child(_win_time_label)
	_win_best_label = _make_label("", 20, COL_DIM, false, 3)
	_win_column.add_child(_win_best_label)
	_win_column.add_child(_spacer(22))
	var again := _make_menu_button("AGAIN")
	again.name = "AgainButton"
	again.pressed.connect(_restart)
	var menu := _make_menu_button("MAIN MENU")
	menu.pressed.connect(_to_menu)
	for b: Button in [again, menu]:
		var wrap := CenterContainer.new()
		wrap.add_child(b)
		_win_column.add_child(wrap)


# ------------------------------------------------------------- helpers ------

func _center_column(layer: CanvasLayer) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	center.add_child(column)
	return column


## Tabular system monospace for the stopwatch digits (falls back gracefully).
func _mono_font(bold: bool) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono",
		"Liberation Mono", "monospace"])
	if bold:
		var fv := FontVariation.new()
		fv.base_font = f
		fv.variation_embolden = 0.6
		return fv
	return f


func _make_label(text: String, size_px: int, color: Color, bold: bool,
		letter_spacing: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", size_px)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0.1, 0.1, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	if bold or letter_spacing > 0:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		if bold:
			f.variation_embolden = 0.85
		if letter_spacing > 0:
			f.set_spacing(TextServer.SPACING_GLYPH, letter_spacing)
		lbl.add_theme_font_override("font", f)
	return lbl


func _make_menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 46)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	btn.add_theme_color_override("font_focus_color", COL_ACCENT)
	btn.add_theme_color_override("font_pressed_color", COL_ACCENT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.09, 0.1, 0.8)
	normal.border_color = Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.4)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.03, 0.14, 0.15, 0.92)
	focus.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.9)
	focus.set_border_width_all(2)
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.05, 0.2, 0.2, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", focus)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.mouse_entered.connect(func() -> void:
		if btn.focus_mode != Control.FOCUS_NONE:
			btn.grab_focus())
	btn.focus_entered.connect(func() -> void: Sfx.play("ui"))
	return btn


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The glowing arena edges: two side rails and the floor line, with a soft
## additive gradient bleeding inward. Pure vector drawing.
class RailsVisual:
	extends Node2D

	func _draw() -> void:
		var rail := Color(0.1, 0.9, 0.82, 0.7)
		var soft := Color(0.05, 0.6, 0.55, 0.16)
		draw_line(Vector2(40.0, 0.0), Vector2(40.0, 700.0), rail, 3.0, true)
		draw_line(Vector2(1240.0, 0.0), Vector2(1240.0, 700.0), rail, 3.0, true)
		draw_line(Vector2(40.0, 700.0), Vector2(1240.0, 700.0), rail, 3.0, true)
		draw_line(Vector2(46.0, 0.0), Vector2(46.0, 700.0), soft, 9.0, true)
		draw_line(Vector2(1234.0, 0.0), Vector2(1234.0, 700.0), soft, 9.0, true)
		draw_line(Vector2(46.0, 694.0), Vector2(1234.0, 694.0), soft, 9.0, true)


## The boost cooldown lamp: a slim rounded bar that fills as the Space kick
## recharges and breathes once ready. Drawn vector, ~zero cost.
class BoostBar:
	extends Control

	var _charge := 1.0
	var _active := false
	var _t := 0.0

	func set_state(charge: float, active: bool) -> void:
		if is_equal_approx(charge, _charge) and active == _active:
			return
		_charge = charge
		_active = active
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if _active and _charge >= 1.0:
			queue_redraw()   # keep the ready-pulse breathing

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.03, 0.12, 0.13, 0.8)
		bg.set_corner_radius_all(4)
		draw_style_box(bg, r)
		if not _active:
			return
		var fill := StyleBoxFlat.new()
		if _charge >= 1.0:
			var pulse := 0.72 + 0.28 * sin(_t * 5.0)
			fill.bg_color = Color(0.1, 0.89, 0.82, pulse)
		else:
			fill.bg_color = Color(0.08, 0.5, 0.47, 0.85)
		fill.set_corner_radius_all(4)
		draw_style_box(fill, Rect2(Vector2.ZERO,
			Vector2(size.x * clampf(_charge, 0.0, 1.0), size.y)))


## Esc / Start / B listener that stays alive under a paused tree (its
## parent overlay is PROCESS_MODE_ALWAYS); resumes the game via the
## injected callable — "pause" toggles back, "ui_cancel" (Esc, pad B) backs
## out. It must only act — and only CONSUME the event — while the tree is
## actually paused, or it starves main's own handler and the pause menu
## can never open.
class PauseCatcher:
	extends Node

	var on_cancel := Callable()

	func _unhandled_input(event: InputEvent) -> void:
		if (event.is_action_pressed("pause") \
				or event.is_action_pressed("ui_cancel")) \
				and get_tree().paused \
				and on_cancel.is_valid():
			# Consume first: the callback may end this scene, after which
			# the node has no viewport left to mark the event on.
			get_viewport().set_input_as_handled()
			on_cancel.call()


## One expanding stroke circle used by _ring().
class RingFx:
	extends Node2D

	const RADIUS := 40.0
	var color := Color(1, 1, 1, 0.8)

	func _draw() -> void:
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, color, 5.0, true)
