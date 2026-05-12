extends RefCounted
class_name EvaShuttleRopeMesh
## Трубка вдоль полилинии (немного граней — дёшево на кадр).

static func rebuild_tube_mesh(target: ArrayMesh, polyline: PackedVector3Array, radius: float, sides: int = 6) -> void:
	target.clear_surfaces()
	var n: int = polyline.size()
	if n < 2 or radius <= 1e-6:
		return
	sides = clampi(sides, 3, 12)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var prev_u: Vector3 = Vector3.ZERO
	var prev_v: Vector3 = Vector3.ZERO

	for i: int in range(n):
		var t: Vector3
		if i < n - 1:
			t = polyline[i + 1] - polyline[i]
		else:
			t = polyline[i] - polyline[i - 1]
		if t.length_squared() < 1e-10:
			t = Vector3.FORWARD
		t = t.normalized()

		var up: Vector3 = Vector3.UP
		if absf(t.dot(up)) > 0.92:
			up = Vector3.RIGHT
		var u: Vector3 = t.cross(up).normalized()
		var v: Vector3 = t.cross(u).normalized()
		if i > 0:
			# Минимальный поворот к предыдущему кадру — меньше скручивания
			var mid_u: Vector3 = (u + prev_u).normalized()
			var mid_v: Vector3 = (v + prev_v).normalized()
			if mid_u.length_squared() > 1e-6 and mid_v.length_squared() > 1e-6:
				u = mid_u
				v = t.cross(u).normalized()
		prev_u = u
		prev_v = v

		var base: Vector3 = polyline[i]
		for s: int in range(sides):
			var ang: float = TAU * float(s) / float(sides)
			var offset: Vector3 = u * cos(ang) * radius + v * sin(ang) * radius
			st.set_normal(offset.normalized())
			st.add_vertex(base + offset)

	# Индексы: кольца по sides вершин на точку
	for i: int in range(n - 1):
		var r0: int = i * sides
		var r1: int = (i + 1) * sides
		for s: int in range(sides):
			var a0: int = r0 + s
			var a1: int = r0 + ((s + 1) % sides)
			var b0: int = r1 + s
			var b1: int = r1 + ((s + 1) % sides)
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a1)
			st.add_index(a1)
			st.add_index(b0)
			st.add_index(b1)

	st.generate_normals()
	st.commit(target)
