extends Control

## Круговой 2D-радар: сонар-клин; цели в локальной плоскости XZ опорного кадра.

var _local_xz: PackedVector2Array = PackedVector2Array()
var _sweep_angle: float = 0.0


func set_targets(local_xz: PackedVector2Array, _types: PackedByteArray) -> void:
	_local_xz = local_xz
	queue_redraw()


func _process(delta: float) -> void:
	_sweep_angle = wrapf(_sweep_angle + delta * 1.8, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var rad: float = minf(size.x, size.y) * 0.48
	draw_arc(c, rad, 0.0, TAU, 64, Color(0.02, 0.12, 0.06, 0.95), 3.0, true)
	draw_arc(c, rad * 0.66, 0.0, TAU, 48, Color(0.05, 0.25, 0.12, 0.55), 1.0, true)
	draw_arc(c, rad * 0.33, 0.0, TAU, 32, Color(0.05, 0.25, 0.12, 0.35), 1.0, true)

	var wedge: float = 0.55
	var a0: float = _sweep_angle - wedge * 0.5
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(c)
	var steps: int = 18
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = a0 + wedge * t
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, Color(0.15, 0.85, 0.35, 0.22))

	var blip_col := Color(0.45, 1.0, 0.55, 0.82)
	for i: int in range(_local_xz.size()):
		var p: Vector2 = _local_xz[i]
		var q: Vector2 = c + Vector2(p.x, p.y) * rad
		if q.distance_to(c) > rad - 1.0:
			continue
		draw_circle(q, 3.4, blip_col)

	draw_line(c, c + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * rad, Color(0.45, 1.0, 0.55, 0.75), 2.0)
