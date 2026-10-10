extends Node
## AutoTest (`--autotest`, docs/CLI.md) — the headless smoke / soak bot.
## Launches the ball, aims and dodges like a player, boosts out of stalls,
## verifies Esc end to end, and watches the invariants that matter every
## tick: the ball stays finite, inside the rails and above the floor, never
## lodges inside a tile or the paddle, never exceeds sane speed; the tile
## bookkeeping matches the nodes; slow-mo always recovers; the arena's node
## count stays bounded; the wall gets touched at least once a minute.
##
## Modes (flags after `--`): plain = Penrose field, one-shot, constant deal;
## --autotest-classic / --autotest-comp pin the wall type; --autotest-hardened
## pins the 5-hit ladder on Penrose tiles; --autotest-random deals a fresh
## field per run; --autotest-fast demolishes all but one block to reach the
## win flow; --autotest-winclick clicks AGAIN after the win;
## --autotest-soak <s> keeps playing (reloading after every win / round)
## until s seconds of game time have passed; --autotest-seed <n> replays a
## run exactly (every run prints its seed). Pair soaks with Godot's
## `--fixed-fps 60` to run ~30× faster than real time.
##
## Lives outside main.gd (preloaded there) so the arena script stays about
## the game; pin() is called by main before it builds anything.

const RUN_S := 40.0
## Stall breaker: a ball cruising on a shallow arc can bounce off the flat
## classic wall forever, peaking short of the paddle (gravity and the
## cruise-speed drag conserve the loop). A human hits Space; so does the
## bot, through the real input path, once the ball has gone this long
## without touching the paddle or breaking anything. (A ball rolling
## through one-shot tiles is busy, not stalled.)
const STALL_S := 3.0
## Invariant limits.
const LODGED_TICKS := 10        # ball center inside a body this long = stuck
const SPEED_LIMIT := 1600.0     # Ball.MAX_SPEED is 1400; gravity adds a bit
const SLOWMO_FRAMES := 150      # time_scale ≠ 1 longer than this = stuck
const DROUGHT_S := 60.0         # no wall contact this long = stalled play
const CHILD_HEADROOM := 260     # transient fx nodes allowed above the field
## Aim: no wall contact for this long → aim at a random tile instead of
## the most exposed one (a corner sliver can hog the "best" slot).
const RETARGET_S := 8.0

var main: Node2D
var ball: Ball
var paddle: Paddle

var _args := PackedStringArray()
var _ticks := 0
var _launched := false
var _demolished := false
var _pause_phase := 0
var _win_seen_tick := 0
var _since_progress := 0   # ticks since a paddle contact or a kill
var _since_contact := 0    # ticks since any wall contact
var _boost_release := 0    # tick to release an injected boost press
var _boosts := 0
var _failed := false
var _run_s := RUN_S
var _soak := false
var _lodged_block := 0
var _lodged_paddle := 0
var _slowmo_frames := 0
var _max_speed := 0.0
var _max_children := 0
var _probe := PhysicsShapeQueryParameters2D.new()
var _target: Block = null
var _target_tick := 0
var _demolish_tick := -100000
## --autotest-winclick: true in the instance born from the AGAIN reload —
## only it may declare the round trip good.
var _reloaded_run := false


## Pin the arena's settings for comparable runs — only the local copies in
## main; the player's saved options are never touched. Also seeds the
## shared RNG (printed, replayable) on the first run of a process.
static func pin(m: Node2D, args: PackedStringArray) -> void:
	m._mode = "penrose"
	if args.has("--autotest-classic"):
		m._mode = "classic"
	elif args.has("--autotest-comp"):
		m._mode = "comp"
		m._comp_frame = 30
	m._one_shot = m._mode != "classic" and not args.has("--autotest-hardened")
	m._field_constant = not args.has("--autotest-random")
	if not Game.has_meta("autotest_seed"):
		var i := args.find("--autotest-seed")
		var seed_v := randi()
		if i >= 0 and i + 1 < args.size():
			seed_v = int(args[i + 1])
		Game.rng.seed = seed_v
		Game.set_meta("autotest_seed", seed_v)
		print("autotest seed=%d (replay: --autotest-seed %d)" % [seed_v, seed_v])


func _ready() -> void:
	# Keep ticking while the tree is paused — the pause test needs it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = OS.get_cmdline_user_args()
	_reloaded_run = Game.has_meta("winclick_reloaded")
	var si := _args.find("--autotest-soak")
	if si >= 0:
		_soak = true
		if not Game.has_meta("soak_left"):
			var total := 600.0
			if si + 1 < _args.size() and _args[si + 1].is_valid_float():
				total = float(_args[si + 1])
			Game.set_meta("soak_left", total)
			Game.set_meta("soak_stats", {"runs": 0, "wins": 0, "broken": 0,
				"boosts": 0, "max_speed": 0.0, "max_children": 0})
		_run_s = float(Game.get_meta("soak_left"))
	ball.paddle_bounced.connect(func(_p: float) -> void: _since_progress = 0)
	ball.paddle_tapped.connect(func() -> void: _since_progress = 0)
	ball.block_bounced.connect(func(_b: Block, _at: Vector2) -> void:
		_since_contact = 0)
	ball.boosted.connect(func(_p: float) -> void: _boosts += 1)
	for c: Node in main.get_children():
		if c is Block:
			(c as Block).destroyed.connect(
				func(_b: Block) -> void: _since_progress = 0)
	var circle := CircleShape2D.new()
	circle.radius = Ball.RADIUS * 0.5
	_probe.shape = circle
	_probe.collision_mask = 1
	_probe.exclude = [ball.get_rid()]


func _process(_delta: float) -> void:
	# Real-frame counter (unaffected by time_scale): slow-mo must recover.
	if Engine.time_scale != 1.0 and not get_tree().paused:
		_slowmo_frames += 1
		if _slowmo_frames > SLOWMO_FRAMES:
			_fail("Engine.time_scale stuck at %.2f" % Engine.time_scale)
	else:
		_slowmo_frames = 0


func _physics_process(_delta: float) -> void:
	# quit() only lands at the end of the frame, and a later quit(0) would
	# overwrite the failure's exit code — so stop acting at once.
	if _failed:
		return
	_ticks += 1
	var t := _ticks / 60.0
	if not _launched and t >= 0.5:
		_launched = true
		ball.launch()
	_pause_check()
	if get_tree().paused or _failed:
		return
	if not _demolished and t >= 1.5 and _args.has("--autotest-fast"):
		_demolish()
	if main._won:
		_on_won()
		return
	if _launched:
		_steer()
	_invariants(t)
	if _failed:
		return
	if _ticks % 300 == 0:
		var pos := ball.global_position
		print("autotest t=%3.0fs blocks=%2d ball=(%4.0f,%5.0f) v=%4.0f" % [
			t, main._blocks_left, pos.x, pos.y, ball.velocity.length()])
	if t >= _run_s:
		if not _soak and main._blocks_left >= main._total_blocks:
			_fail("no block was destroyed in %.0fs" % _run_s)
			return
		if _args.has("--autotest-fast"):
			_fail("--autotest-fast never reached the win in %.0fs" % _run_s)
			return
		print("autotest OK [%s]: %d/%d blocks left, timer=%s, boosts=%d" % [
			main._mode, main._blocks_left, main._total_blocks,
			Game.format_time(main._elapsed), _boosts])
		if _soak:
			_soak_account(t, false)
			_soak_summary()
		get_tree().quit(0)


## Esc pause/resume round-trip, verified end-to-end through the real input
## pipeline at t = 2.0 .. 2.4 s (this is what caught the v1.1 bug).
func _pause_check() -> void:
	match _pause_phase:
		0 when _ticks == 120:
			_pause_phase = 1
			_press_escape(true)
		1 when _ticks == 126:
			_press_escape(false)
		1 when _ticks == 132:
			if not get_tree().paused:
				_fail("Esc did not pause the game")
			_pause_phase = 2
			_press_escape(true)
		2 when _ticks == 138:
			_press_escape(false)
		2 when _ticks == 144:
			if get_tree().paused:
				_fail("Esc did not resume the game")
			_pause_phase = 3
			print("autotest: Esc pause/resume OK")


## --autotest-fast: chew through all but one block via the normal damage
## path, so the bot reaches the win/record flow in seconds. The survivor is
## the most exposed target (highest, most central — a Penrose deal can hide
## tiny rhombi in corners); hardened survivors start pre-damaged to yellow
## so the bot still walks the blue and armed stages through real bounces.
func _demolish() -> void:
	_demolished = true
	_demolish_tick = _ticks
	var blocks: Array = []
	for c: Node in main.get_children():
		if c is Block:
			blocks.append(c)
	var keep: Block = null
	for b: Block in blocks:
		if keep == null \
				or b.position.y + absf(b.position.x - 640.0) * 0.08 \
				< keep.position.y + absf(keep.position.x - 640.0) * 0.08:
			keep = b
	for b: Block in blocks:
		if b != keep:
			for j in Block.STAGE_COLORS.size():
				b.take_hit()
	# One-shot tiles die on the first hit — pre-damaging the survivor
	# would end the run before the bot plays it.
	if not main._one_shot:
		for j in 2:
			keep.take_hit()


func _on_won() -> void:
	if _boost_release > 0:
		# never leave an injected boost press held past the win
		_boost_release = 0
		_press_launch(false)
	# --autotest-winclick: click AGAIN with a real mouse event (or a raw
	# touch with --touchui) once the overlay is armed (it fades in for
	# 1.2 s, slowed by the finale's slow-mo); the scene must reload, killing
	# this instance. Only the instance born from that reload declares the
	# round trip good — if this one is still here later, it failed.
	if _args.has("--autotest-winclick") and not _reloaded_run:
		if _win_seen_tick == 0:
			_win_seen_tick = _ticks
		var since := _ticks - _win_seen_tick
		var btn := main._win_layer.find_child("AgainButton", true, false) \
			as Button
		if btn == null:
			_fail("win overlay has no AgainButton")
			return
		if since == 150:
			if btn.disabled:
				_fail("AGAIN still disarmed 2.5 s after the win")
				return
			Game.set_meta("winclick_reloaded", true)
			print("autotest winclick: clicking AGAIN")
			_click(btn.get_global_rect().get_center(), true)
		elif since == 156:
			_click(btn.get_global_rect().get_center(), false)
		elif since > 300:
			_fail("AGAIN click did not restart the run")
		return
	if main._mode == "comp" and main._broken == 0:
		_fail("the competition round ended with no tile broken")
		return
	var rec := ""
	if main._mode == "comp":
		var cb: Array = Game.comp_best(main._comp_frame, main._one_shot)
		rec = "%s tiles by %s" % [cb[0], cb[1]]
	else:
		rec = "%s by %s" % [
			Game.format_time(Game.clear_best_time(main._mode, main._one_shot)),
			Game.clear_best_name(main._mode, main._one_shot)]
	if _reloaded_run:
		print("autotest winclick OK: AGAIN reloaded the arena")
	print("autotest WIN [%s]: time=%s broken=%d best=%s" % [
		main._mode, Game.format_time(main._elapsed), main._broken, rec])
	if _soak:
		var left := _soak_account(_ticks / 60.0, true)
		if left > 0.0:
			main._restart()   # next run; the new bot resumes the soak
			return
		_soak_summary()
	get_tree().quit(0)


func _steer() -> void:
	if ball.global_position.y < paddle.position.y + 20.0:
		# Ball overhead: step aside so it can fall past the paddle (its top
		# face only gives a soft bounce, like for a human).
		var side := 1.0 if ball.global_position.x < 640.0 else -1.0
		paddle.position.x = clampf(
			ball.global_position.x + side * 260.0, 115.0, 1165.0)
	else:
		# Aim: park the paddle off-center so the deflect angle steers the
		# ball toward the target tile.
		var target_x := 640.0
		var tgt := _pick_target()
		if tgt != null:
			target_x = tgt.global_position.x
		var want_dir_x := clampf(
			(target_x - ball.global_position.x) / 800.0, -0.8, 0.8)
		paddle.position.x = clampf(
			ball.global_position.x - want_dir_x / 0.85 * Paddle.WIDTH * 0.55,
			115.0, 1165.0)
	# Stalled? Boost early in the climb (low, rising) so the kick carries
	# the ball up to the paddle. Held for two ticks, then released.
	_since_progress += 1
	if _boost_release > 0 and _ticks >= _boost_release:
		_boost_release = 0
		_press_launch(false)
	elif _boost_release == 0 \
			and _since_progress >= int(STALL_S * 60.0) \
			and ball.velocity.y < 0.0 \
			and ball.global_position.y > 360.0 \
			and ball.boost_charge() >= 1.0:
		_press_launch(true)
		_boost_release = _ticks + 2


## The most exposed live tile (highest up, then nearest the ball) — or,
## after RETARGET_S without any wall contact, a random one for a while, so
## a hard-to-reach sliver can't trap the aim forever.
func _pick_target() -> Block:
	var live: Array = []
	for c: Node in main.get_children():
		if c is Block and not (c as Block)._dead:
			live.append(c)
	if live.is_empty():
		return null
	if _since_contact > int(RETARGET_S * 60.0):
		# Lost: hold a random pick for RETARGET_S, then re-roll.
		if not live.has(_target) or _ticks - _target_tick >= int(RETARGET_S * 60.0):
			_target = live[Game.rng.randi_range(0, live.size() - 1)]
			_target_tick = _ticks
		return _target
	_target = null
	var best: Block = null
	var best_score := INF
	var bx := ball.global_position.x
	for b: Block in live:
		var score := b.position.y + 0.35 * absf(b.position.x - bx)
		if score < best_score:
			best_score = score
			best = b
	return best


func _invariants(t: float) -> void:
	var pos := ball.global_position
	if not (is_finite(pos.x) and is_finite(pos.y)):
		_fail("ball position is not finite: %s" % pos)
		return
	if pos.x < 28.0 or pos.x > 1252.0:
		_fail("ball escaped sideways: %s" % pos)
	if pos.y > 712.0:
		_fail("ball fell through the floor: %s" % pos)
	if pos.y < -3000.0:
		_fail("ball climbed out of the rails: %s" % pos)
	var speed := ball.velocity.length()
	_max_speed = maxf(_max_speed, speed)
	if speed > SPEED_LIMIT or not is_finite(speed):
		_fail("ball speed %.0f exceeds %.0f" % [speed, SPEED_LIMIT])
	if _launched and t > 0.6 and not ball.is_flying():
		_fail("ball stopped flying mid-run")
	# Lodged: the ball's inner core overlapping a live tile or the paddle
	# for several ticks means collision resolution lost it.
	_probe.transform = Transform2D(0.0, pos)
	var in_block := false
	var in_paddle := false
	for hit: Dictionary in main.get_world_2d().direct_space_state \
			.intersect_shape(_probe, 4):
		var col: Object = hit.get("collider")
		if col is Block and not (col as Block)._dead:
			in_block = true
		elif col is Paddle:
			in_paddle = true
	_lodged_block = _lodged_block + 1 if in_block else 0
	_lodged_paddle = _lodged_paddle + 1 if in_paddle else 0
	if _lodged_block > LODGED_TICKS:
		_fail("ball lodged inside a tile at %s" % pos)
	if _lodged_paddle > LODGED_TICKS:
		_fail("ball lodged inside the paddle at %s" % pos)
	# Bookkeeping: the counter must match the live tiles in the tree.
	if _ticks % 30 == 0:
		var live := 0
		for c: Node in main.get_children():
			if c is Block and not (c as Block)._dead:
				live += 1
		if live != main._blocks_left:
			_fail("blocks_left=%d but %d live tiles" % [main._blocks_left, live])
		var kids := main.get_child_count()
		# --autotest-fast's one-tick demolition bursts ~140 tiles' worth of
		# sparks at once; judge growth only after that burst has cleared.
		var settled := _ticks - _demolish_tick > 180
		if settled:
			_max_children = maxi(_max_children, kids)
		if settled and kids > main._total_blocks + CHILD_HEADROOM:
			_fail("arena node count runaway: %d children" % kids)
	if _launched:
		_since_contact += 1
		if _since_contact > int(DROUGHT_S * 60.0) and main._blocks_left > 0:
			var left: Array = []
			for c: Node in main.get_children():
				if c is Block and not (c as Block)._dead and left.size() < 8:
					left.append("(%.0f,%.0f)" % [c.position.x, c.position.y])
			_fail("no wall contact for %.0fs; %d tiles left at %s" % [
				DROUGHT_S, main._blocks_left, ", ".join(left)])


## Soak bookkeeping across reloads (Game meta survives the scene); returns
## the game seconds still to play.
func _soak_account(t: float, won: bool) -> float:
	var st: Dictionary = Game.get_meta("soak_stats")
	st.runs += 1
	st.wins += 1 if won else 0
	st.broken += main._broken
	st.boosts += _boosts
	st.max_speed = maxf(st.max_speed, _max_speed)
	st.max_children = maxi(st.max_children, _max_children)
	var left := float(Game.get_meta("soak_left")) - t
	Game.set_meta("soak_left", left)
	return left


func _soak_summary() -> void:
	var st: Dictionary = Game.get_meta("soak_stats")
	print("autotest SOAK OK [%s%s%s]: runs=%d wins=%d broken=%d boosts=%d max_speed=%.0f max_children=%d seed=%d" % [
		main._mode, "" if main._one_shot or main._mode == "classic" else ",hardened",
		"" if main._field_constant else ",random",
		st.runs, st.wins, st.broken, st.boosts, st.max_speed, st.max_children,
		Game.get_meta("autotest_seed")])


func _press_escape(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = down
	Input.parse_input_event(ev)


func _press_launch(down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = "launch"
	ev.pressed = down
	Input.parse_input_event(ev)


## Injected positions are window coordinates (delivery applies the stretch
## transform), same as the touchtest hook. With --touchui the click becomes
## a raw screen touch, exercising the TapCatcher path a phone would take.
func _click(at: Vector2, down: bool) -> void:
	var window := get_tree().root.get_final_transform() * at
	if _args.has("--touchui"):
		var tv := InputEventScreenTouch.new()
		tv.index = 0
		tv.position = window
		tv.pressed = down
		Input.parse_input_event(tv)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = window
	Input.parse_input_event(ev)


func _fail(msg: String) -> void:
	if _failed:
		return
	_failed = true
	printerr("autotest FAIL: %s (seed=%s)" % [msg, Game.get_meta("autotest_seed", "?")])
	get_tree().quit(1)
