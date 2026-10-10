extends Block
class_name PenroseTile
## PenroseTile — one rhombus of the Penrose wall (the "penrose" and
## "comp" game modes). The damage model is untouched Block behavior — five
## color stages, punch, sparks, armed pulse, single destroyed emission —
## only the body differs: a P3 rhombus lifted verbatim from the arena's own
## backdrop tiling, so the breakable field continues the vista seamlessly
## and a destroyed tile reveals its dim ghost in the backdrop beneath.

## Rhombus corners around this body's origin (its centroid).
var points := PackedVector2Array()
## True (default): any contact bursts the tile — the field is large, so
## Penrose runs stay brisk. False (hardened): the full five-hit ladder.
var one_shot := true
## Fresh-tile color; the player picks one per prototile family in OPTIONS.
## Hardened tiles jump onto the standard damage ladder from the first hit.
var base_color := Color("0fb8ad")


func _init(corners := PackedVector2Array(), shot := true,
		col := Color("0fb8ad")) -> void:
	points = corners
	one_shot = shot
	base_color = col


## Replaces Block._ready wholesale: polygon collision + polygon visual.
func _ready() -> void:
	_shape = CollisionShape2D.new()
	var poly := ConvexPolygonShape2D.new()
	poly.set_point_cloud(points)   # convex hull → winding-proof
	_shape.shape = poly
	add_child(_shape)

	_body = Node2D.new()
	var visual := TileVisual.new()
	visual.points = points
	_body.add_child(visual)
	add_child(_body)
	_apply_color(base_color, false)


## One-shot tiles burst on any contact (main.gd reacts with the mini light
## pop instead of the full kill spectacle); hardened tiles are Blocks.
func take_hit() -> bool:
	if one_shot:
		if _dead:
			return false
		_die()
		return true
	return super.take_hit()


func _burst_color() -> Color:
	return base_color


## Inner drawn visual (mirrors Block.BlockVisual): white shapes so the
## parent's modulate supplies the stage color; dark seams keep neighboring
## tiles readable as separate facets when the whole field is one color.
class TileVisual:
	extends Node2D

	var points := PackedVector2Array()

	func _draw() -> void:
		# soft under-glow pad, slightly inflated
		var pad := PackedVector2Array()
		for p: Vector2 in points:
			pad.append(p * 1.1)
		draw_colored_polygon(pad, Color(1, 1, 1, 0.14))
		# body
		draw_colored_polygon(points, Color(1, 1, 1, 1))
		# facet seam (black survives the modulate tint, unlike white)
		var rim := points.duplicate()
		rim.append(points[0])
		draw_polyline(rim, Color(0, 0, 0, 0.26), 2.0, true)
