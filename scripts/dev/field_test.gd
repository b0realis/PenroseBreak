extends Node
## FieldTest (`--fieldtest [n]`, docs/CLI.md) — validates the P3 tiling and
## the wall carving over n deals (default 200) plus the constant deal:
##   * every rhombus is a true Penrose rhombus: four equal sides (the
##     generated tile edge), convex, apex angle 36° (thin) or 108° (thick);
##   * the rhombi tile the whole view — the summed clipped areas equal the
##     view area, so no unpaired-triangle gaps and no overlaps (the pairing
##     breaks silently when a deflation vertex order is wrong; PENROSE.md);
##   * the carved wall covers its strip with no holes: complete coverage
##     away from the rails and floor (within one tile diameter of them the
##     rule deliberately leaves sub-30% slivers as scenery — that edge share
##     is reported, not asserted);
##   * the constant deal (FIELD_SEED) still yields exactly CONSTANT_TILES —
##     competition records depend on that field never changing.
## Prints one summary line, exits 0 / 1 with the failing deal's seed.
## main.gd adds it instead of building an arena and hands over its pure
## carving rule, so the test exercises the exact code the game runs.

## Tiles in the constant (FIELD_SEED) field since v1.3 — docs/PENROSE.md.
const CONSTANT_TILES := 141
const VIEW := Vector2(1280.0, 720.0)
const AREA_TOL := 1e-3      # relative tolerance on area sums
const SIDE_TOL := 1e-3      # relative tolerance on rhombus sides
const ANGLE_TOL := 0.5      # degrees

var carve: Callable          # main.gd carve_field(rhombi) -> Array
var area: Callable           # main.gd poly_area(poly) -> float
var strip := Rect2()         # the breakable band
var field_seed := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var n := 200
	var i := args.find("--fieldtest")
	if i + 1 < args.size() and args[i + 1].is_valid_int():
		n = int(args[i + 1])
	var stats := {"tiles_min": 1 << 30, "tiles_max": 0, "rhombi_max": 0,
		"cover_err": 0.0, "inner_err": 0.0, "edge_gap": 0.0, "ms_max": 0}
	var const_tiles := _deal(field_seed, stats)
	if const_tiles < 0:
		return
	if const_tiles != CONSTANT_TILES:
		_fail(field_seed, "constant deal has %d tiles, expected %d" % [
			const_tiles, CONSTANT_TILES])
		return
	for k in n:
		if _deal(1000003 * (k + 1), stats) < 0:
			return
	print("fieldtest OK: %d deals + constant (%d tiles); tiles %d..%d, rhombi ≤ %d, view cover err %.6f, inner wall cover err %.6f, edge slivers ≤ %.1f%% of strip, ≤ %d ms/deal" % [
		n, const_tiles, stats.tiles_min, stats.tiles_max, stats.rhombi_max,
		stats.cover_err, stats.inner_err, stats.edge_gap * 100.0,
		stats.ms_max])
	get_tree().quit(0)


## Generate one deal, validate it; returns its wall tile count, or -1
## after failing.
func _deal(seed_v: int, stats: Dictionary) -> int:
	var t0 := Time.get_ticks_msec()
	var bg := PenroseBg.new()
	add_child(bg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	bg.generate(VIEW, rng)
	bg.freeze()
	var rh := bg.rhombi()
	var field: Array = carve.call(rh)
	stats.ms_max = maxi(stats.ms_max, Time.get_ticks_msec() - t0)
	var side := bg.tile_side()
	var view_poly := _rect_poly(Rect2(Vector2.ZERO, VIEW))
	var cover := 0.0
	for r: Array in rh:
		var q: PackedVector2Array = r[1]
		var why := _bad_rhombus(int(r[0]), q, side)
		if why != "":
			_fail(seed_v, "%s at %s" % [why, q])
			return -1
		cover += _clipped_area(q, view_poly)
	var view_area := VIEW.x * VIEW.y
	var cover_err := absf(cover - view_area) / view_area
	if cover_err > AREA_TOL:
		_fail(seed_v, "rhombi cover %.1f of %.1f px² of the view (%s)" % [
			cover, view_area, "gap" if cover < view_area else "overlap"])
		return -1
	# Inner band: the strip minus one long rhombus diagonal (thin: 2·s·cos18°)
	# off the rails and the floor; the top edge stays (tiles crossing it are
	# always kept).
	var d := 2.0 * side * cos(deg_to_rad(18.0))
	var inner := Rect2(strip.position.x + d, strip.position.y,
		strip.size.x - 2.0 * d, strip.size.y - d)
	var inner_poly := _rect_poly(inner)
	var strip_poly := _rect_poly(strip)
	var inner_cover := 0.0
	var strip_cover := 0.0
	for r: Array in field:
		inner_cover += _clipped_area(r[1], inner_poly)
		strip_cover += _clipped_area(r[1], strip_poly)
	var inner_area := inner.size.x * inner.size.y
	var inner_err := absf(inner_cover - inner_area) / inner_area
	if inner_err > AREA_TOL:
		_fail(seed_v, "wall covers %.1f of %.1f px² of its inner band (%s)" % [
			inner_cover, inner_area,
			"hole" if inner_cover < inner_area else "overlap"])
		return -1
	var strip_area := strip.size.x * strip.size.y
	stats.cover_err = maxf(stats.cover_err, cover_err)
	stats.inner_err = maxf(stats.inner_err, inner_err)
	stats.edge_gap = maxf(stats.edge_gap, 1.0 - strip_cover / strip_area)
	stats.tiles_min = mini(stats.tiles_min, field.size())
	stats.tiles_max = maxi(stats.tiles_max, field.size())
	stats.rhombi_max = maxi(stats.rhombi_max, rh.size())
	bg.queue_free()
	return field.size()


## "" when q (apex, b, twin apex, c) is a proper P3 rhombus of edge `side`.
func _bad_rhombus(family: int, q: PackedVector2Array, side: float) -> String:
	if q.size() != 4:
		return "rhombus with %d corners" % q.size()
	var turn := 0.0
	for k in 4:
		var a := q[k]
		var b := q[(k + 1) % 4]
		var c := q[(k + 2) % 4]
		if absf(a.distance_to(b) - side) > side * SIDE_TOL:
			return "side %.4f ≠ tile edge %.4f" % [a.distance_to(b), side]
		var cross := (b - a).cross(c - b)
		if turn != 0.0 and signf(cross) != signf(turn):
			return "non-convex rhombus"
		turn = cross
	var apex := rad_to_deg((q[1] - q[0]).angle_to(q[3] - q[0]))
	var want := 36.0 if family == 0 else 108.0
	if absf(absf(apex) - want) > ANGLE_TOL:
		return "apex angle %.2f°, expected %.0f°" % [absf(apex), want]
	return ""


func _clipped_area(q: PackedVector2Array, clip: PackedVector2Array) -> float:
	var a := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(q, clip):
		a += area.call(piece)
	return a


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
		r.end, Vector2(r.position.x, r.end.y)])


func _fail(seed_v: int, msg: String) -> void:
	printerr("fieldtest FAIL (deal seed %d): %s" % [seed_v, msg])
	get_tree().quit(1)
