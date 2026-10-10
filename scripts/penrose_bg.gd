extends Node2D
class_name PenroseBg
## PenroseBg — the playfield backdrop: a genuine P3 Penrose tiling (rhombi via
## Robinson-triangle deflation), generated fresh each run with a random
## mathematic style: sun-wheel or thick-rhombus seed, random deflation depth,
## rotation, center, and one of three turquoise render styles. A barely
## visible spin keeps it alive (transform only — the tiles are drawn once).
##
## The deflation rule was verified numerically (area exact, only 36-72-72
## and 36-36-108 Robinson triangles, AND 100% of interior triangles pair
## with a mirror twin across their b-c base — the finite-depth tiling
## decomposes fully into rhombi, which the breakable field depends on):
##   acute (a,b,c):  p = a+(b-a)/φ           → obtuse(p,c,a), acute(c,p,b)
##   obtuse (a,b,c): q = b+(a-b)/φ, r = b+(c-b)/φ
##                                           → obtuse(q,r,b), acute(r,q,a),
##                                             obtuse(r,c,a)
## Vertex convention: acute carries 36° at a; obtuse carries 108° at a and
## 36° at b and c. In BOTH families the side b-c is the rhombus diagonal
## shared with the mirror triangle, so stroking only a-b and a-c outlines
## true Penrose rhombi. The base orderings (which endpoint is b) are NOT
## cosmetic: earlier orderings conserved shape but flipped mirror
## orientation, leaving ~55% of triangles twinless — rhombus pairing
## silently broke while the outlines still looked right.

const PHI := 1.618033988749895

enum Style { GLASS, EDGES, DUAL }

var _tris: Array = []          # [family:int, a:Vector2, b:Vector2, c:Vector2]
var _style := Style.GLASS
## Slow drift of the whole tiling, radians/s.
var _spin := 0.0


func _ready() -> void:
	generate(get_viewport_rect().size)


func _process(delta: float) -> void:
	rotation += _spin * delta


## Random style, random geometry, covering a rect of the given size. Pass a
## seeded RNG for a reproducible deal (the constant-field setting); defaults
## to the shared session RNG.
func generate(view: Vector2, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = Game.rng
	_style = rng.randi_range(0, Style.size() - 1) as Style
	# The pivot wanders around mid-screen; every window into a Penrose tiling
	# is unique (aperiodicity), so this alone re-deals the pattern.
	var pivot := view * 0.5 + Vector2(rng.randf_range(-220.0, 220.0),
		rng.randf_range(-160.0, 160.0))
	# Cover the farthest screen corner from the pivot, with margin.
	var radius := (view * 0.5 + (pivot - view * 0.5).abs()).length() * 1.15
	position = pivot
	rotation = rng.randf_range(0.0, TAU)
	_spin = rng.randf_range(-0.01, 0.01) * (1.0 if rng.randf() < 0.5 else -1.0)

	_tris.clear()
	var depth: int
	if rng.randf() < 0.5:
		# Sun wheel: 10 acute triangles around the pivot.
		depth = rng.randi_range(5, 6)
		for i in 10:
			var b := Vector2.from_angle((2 * i - 1) * PI / 10.0) * radius
			var c := Vector2.from_angle((2 * i + 1) * PI / 10.0) * radius
			if i % 2 == 0:
				var t := b
				b = c
				c = t
			_tris.append([0, Vector2.ZERO, b, c])
	else:
		# Thick-rhombus seed: two mirrored obtuse triangles big enough to
		# cover the view (rhombus inradius = s·sin72°/2 ≥ radius).
		depth = rng.randi_range(7, 8)
		var s := radius / (sin(deg_to_rad(72.0)) * 0.5)
		var half_diag := PHI * s * 0.5
		var h := s * sin(deg_to_rad(36.0))
		var b := Vector2(-half_diag, 0.0)
		var c := Vector2(half_diag, 0.0)
		# Same b,c order for BOTH halves — the twin seed's mirror
		# orientation must agree with the deflation rule or the seam
		# between the two seed triangles never pairs into rhombi.
		_tris.append([1, Vector2(0.0, -h), b, c])
		_tris.append([1, Vector2(0.0, h), b, c])
	for i in depth:
		_tris = _subdivide(_tris)
	queue_redraw()


## Stop the barely-there drift. The arena calls this in the Penrose game
## modes: breakable tiles are carved out of this exact tiling as static
## bodies, so the vista underneath must stay aligned with them forever.
func freeze() -> void:
	_spin = 0.0


## Edge length of the rhombi at the generated depth — both prototiles share
## it. The menu snow sizes its flakes to this.
func tile_side() -> float:
	if _tris.is_empty():
		return 40.0
	var t: Array = _tris[0]
	return (t[1] as Vector2).distance_to(t[2])


## Pair the mirror triangles across their shared b-c diagonal into full P3
## rhombi: one [family, corners] pair per rhombus — family 0 = thin (from
## acute halves), 1 = thick (obtuse); corners are a PackedVector2Array
## (apex, b, twin apex, c) in GLOBAL coordinates, ready to become breakable
## tiles. Matching is spatial — same family, diagonal midpoints within
## 0.3 px — so float noise between different subdivision paths can never
## split a pair the way exact key equality could. Boundary triangles
## without a twin are dropped (they only exist at the rim of the covered
## disc, outside the view).
func rhombi() -> Array:
	var grid := {}          # Vector2i cell → Array of unpaired triangles
	var out: Array = []
	for t: Array in _tris:
		var mid: Vector2 = (t[2] + t[3]) * 0.5
		var cell := Vector2i(int(floor(mid.x)), int(floor(mid.y)))
		var mate: Array = []
		var mate_cell := Vector2i.ZERO
		for dx in 3:
			for dy in 3:
				if not mate.is_empty():
					break
				var c := cell + Vector2i(dx - 1, dy - 1)
				if not grid.has(c):
					continue
				for u: Array in grid[c]:
					if u[0] == t[0] \
							and ((u[2] + u[3]) * 0.5).distance_to(mid) < 0.3:
						mate = u
						mate_cell = c
						break
		if mate.is_empty():
			if not grid.has(cell):
				grid[cell] = []
			(grid[cell] as Array).append(t)
			continue
		(grid[mate_cell] as Array).erase(mate)
		out.append([t[0], PackedVector2Array([to_global(mate[1]),
			to_global(t[2]), to_global(t[1]), to_global(t[3])])])
	return out


func _subdivide(tris: Array) -> Array:
	var out: Array = []
	for t: Array in tris:
		var a: Vector2 = t[1]
		var b: Vector2 = t[2]
		var c: Vector2 = t[3]
		if t[0] == 0:
			var p := a + (b - a) / PHI
			out.append([1, p, c, a])
			out.append([0, c, p, b])
		else:
			var q := b + (a - b) / PHI
			var r := b + (c - b) / PHI
			out.append([1, q, r, b])
			out.append([0, r, q, a])
			out.append([1, r, c, a])
	return out


func _draw() -> void:
	# Two Robinson families → two tones of the deep-sea turquoise palette.
	var col_a: Color   # acute halves → thin rhombi
	var col_b: Color   # obtuse halves → thick rhombi
	var edge: Color
	match _style:
		Style.GLASS:
			col_a = Color(0.055, 0.19, 0.21)
			col_b = Color(0.03, 0.125, 0.15)
			edge = Color(0.1, 0.5, 0.48, 0.15)
		Style.EDGES:
			col_a = Color(0.03, 0.1, 0.12)
			col_b = Color(0.035, 0.115, 0.135)
			edge = Color(0.06, 0.62, 0.58, 0.24)
		_:
			col_a = Color(0.02, 0.16, 0.19)
			col_b = Color(0.09, 0.08, 0.19)
			edge = Color(0.5, 0.95, 0.9, 0.09)
	for t: Array in _tris:
		draw_colored_polygon(PackedVector2Array([t[1], t[2], t[3]]),
			col_a if t[0] == 0 else col_b)
		draw_line(t[2], t[1], edge, 1.2, true)
		draw_line(t[1], t[3], edge, 1.2, true)
