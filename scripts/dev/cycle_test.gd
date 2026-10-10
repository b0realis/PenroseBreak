extends Node
## CycleTest (`--cycletest [n]`, docs/CLI.md) — the menu ↔ arena loop,
## driven by real key events only, n times (default 25): Enter on START →
## arena → Space launches → R restarts → Esc pauses → ↓ ↓ Enter picks MAIN
## MENU → back in the menu. Each return samples the engine's object, node,
## resource and orphan counts; growth across cycles means a leak (nodes
## or resources surviving their scene). Exits 0 / 1 with a table.
##
## Spawned on the root by Game (so it survives every scene change); runs
## PROCESS_MODE_ALWAYS to drive the pause menu.

const SETTLE := 0.45          # seconds to let a scene build / a tween land
## Allowed growth of each counter between the warm-up sample and the last.
const GROW_TOL := 0.03

var _cycles := 25
var _done := 0
var _samples: Array = []      # [objects, nodes, resources, orphans]
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var i := args.find("--cycletest")
	if i + 1 < args.size() and args[i + 1].is_valid_int():
		_cycles = int(args[i + 1])
	_run()


func _run() -> void:
	await _wait(1.2)   # splash skip happens below; menu needs a beat
	_key(KEY_ESCAPE)   # any key skips the studio splash
	await _wait(SETTLE + 0.3)
	while _done < _cycles:
		if not _in("startup"):
			_fail("expected the menu at cycle %d" % _done)
			return
		_sample()
		_key(KEY_ENTER)                     # START holds focus
		await _wait(SETTLE)
		if not _in("main"):
			_fail("Enter on START did not open the arena")
			return
		_key(KEY_SPACE)                     # launch
		await _wait(SETTLE)
		_key(KEY_R)                         # restart (scene reload)
		await _wait(SETTLE)
		if not _in("main"):
			_fail("R did not reload the arena")
			return
		_key(KEY_ESCAPE)                    # pause → RESUME focused
		await _wait(0.2)
		if not get_tree().paused:
			_fail("Esc did not pause")
			return
		_key(KEY_DOWN)
		await _wait(0.1)
		_key(KEY_DOWN)                      # → MAIN MENU
		await _wait(0.1)
		_key(KEY_ENTER)
		await _wait(SETTLE + 0.3)
		_done += 1
	_sample()
	_report()


func _sample() -> void:
	_samples.append([
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	])


## Compare the warm-up sample (after two cycles: caches, synthesized sounds
## and fonts are all in) against the final one.
func _report() -> void:
	var first: Array = _samples[mini(2, _samples.size() - 1)]
	var last: Array = _samples[-1]
	var names := ["objects", "nodes", "resources", "orphans"]
	var parts: Array = []
	var bad: Array = []
	for k in 4:
		parts.append("%s %d→%d" % [names[k], first[k], last[k]])
		var limit := int(ceil(first[k] * (1.0 + GROW_TOL))) + 2
		if last[k] > limit:
			bad.append(names[k])
	if not bad.is_empty():
		_fail("growth over %d cycles in %s (%s)" % [
			_cycles, ", ".join(bad), ", ".join(parts)])
		return
	print("cycletest OK: %d menu↔arena cycles; %s" % [_cycles, ", ".join(parts)])
	get_tree().quit(0)


func _in(scene: String) -> bool:
	var cs := get_tree().current_scene
	return cs != null and cs.scene_file_path.ends_with("/%s.tscn" % scene)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _key(k: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)


func _fail(msg: String) -> void:
	printerr("cycletest FAIL: " + msg)
	get_tree().quit(1)
