extends RefCounted
class_name EvaShuttleRopeSim
## Verlet + PBD по длине сегментов; столкновения узлов со статикой (intersect_shape).
## Точки: p[0] якорь, p[1..seg-1] свободные, к p[seg-1] крепится игрок (attach).

const MAX_SEGMENTS := 32
const MIN_SEGMENTS := 4
## Одна итерация — не полное закрытие ошибки, иначе цепочка «дрожит» и разгоняет тело.
const PBD_PASS_GAIN: float = 0.38

var _seg: int = 16
var _rest: float = 2.0
## Выпущенная длина троса (сумма звеньев); меняется только через set_payed_length.
var _payed_length: float = 10.0
var _length_min: float = 4.0
var _length_max: float = 40.0
var _slack_ratio: float = 0.14
var _compliance: float = 1.0
var _verlet_damping: float = 0.994
var _collision_r: float = 0.055
var _collision_mask: int = 1025
var _constraint_passes: int = 12
var _collision_resolve_steps: int = 6
## 0..1: перетяжка по прямой якорь–разъём (для SFX «на пределе»).
var _strain_audio: float = 0.0

var _sphere: SphereShape3D
var _shape_q: PhysicsShapeQueryParameters3D
var _pos: PackedVector3Array = PackedVector3Array()
var _old: PackedVector3Array = PackedVector3Array()
## Локаль точки разъёма на CharacterBody (должна совпадать с игроком).
var _attach_local: Vector3 = Vector3(0.0, 0.82, 0.12)


func _init() -> void:
	_sphere = SphereShape3D.new()
	_shape_q = PhysicsShapeQueryParameters3D.new()
	_shape_q.shape = _sphere
	_shape_q.collide_with_bodies = true
	_shape_q.collide_with_areas = false


func configure(
	segments: int,
	length_min: float,
	length_max: float,
	initial_payed_length: float,
	slack_ratio: float,
	_spring: float,
	_damping: float,
	collision_radius: float,
	collision_mask: int,
	attach_local: Vector3 = Vector3(0.0, 0.82, 0.12)
) -> void:
	_seg = clampi(segments, MIN_SEGMENTS, MAX_SEGMENTS)
	_attach_local = attach_local
	var lo: float = minf(length_min, length_max)
	var hi: float = maxf(length_min, length_max)
	_length_min = maxf(0.5, lo)
	_length_max = maxf(_length_min + 0.1, hi)
	_slack_ratio = clampf(slack_ratio, 0.0, 0.48)
	_payed_length = clampf(initial_payed_length, _length_min, _length_max)
	_strain_audio = 0.0
	_rest = maxf(0.04, _payed_length / float(_seg))
	_compliance = clampf(1.0 - slack_ratio * 0.85, 0.08, 1.0)
	_verlet_damping = clampf(1.0 - _damping * 0.0012, 0.88, 0.9995)
	_collision_r = maxf(0.02, collision_radius * 1.35)
	_collision_mask = collision_mask
	_sphere.radius = _collision_r
	_constraint_passes = mini(10, 5 + int(_seg / 3.0))


## Смена выпущенной длины только с кнопок; _rest пересчитывается, сама длина иначе не «ползёт».
func set_payed_length(value: float) -> bool:
	var v: float = clampf(value, _length_min, _length_max)
	if absf(v - _payed_length) < 1e-5:
		return false
	_payed_length = v
	_rest = maxf(0.04, _payed_length / float(_seg))
	return true


func get_payed_length() -> float:
	return _payed_length


func get_tether_strain_for_audio() -> float:
	return _strain_audio


func reset_straight(anchor: Vector3, attach: Vector3) -> void:
	_pos.resize(_seg)
	_old.resize(_seg)
	for i: int in range(_seg):
		var t: float = float(i) / float(_seg - 1) if _seg > 1 else 0.0
		var pt: Vector3 = anchor.lerp(attach, t)
		_pos[i] = pt
		_old[i] = pt


func get_polyline_with_attach(attach_global: Vector3) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(_seg + 1)
	for i: int in range(_seg):
		out[i] = _pos[i]
	out[_seg] = attach_global
	return out


func step(
	anchor_global: Vector3,
	attach_global: Vector3,
	delta: float,
	character: CharacterBody3D,
	space: PhysicsDirectSpaceState3D,
	exclude_rid: RID,
	rope_collision_exclude_rids: Array = []
) -> void:
	if _seg < MIN_SEGMENTS or character == null or space == null:
		return
	var dt: float = clampf(delta, 0.0, 0.05)
	_strain_audio = move_toward(_strain_audio, 0.0, dt * 1.5)

	_pos[0] = anchor_global
	_old[0] = anchor_global

	for i: int in range(1, _seg):
		var vel: Vector3 = (_pos[i] - _old[i]) * _verlet_damping
		_old[i] = _pos[i]
		_pos[i] = _pos[i] + vel

	_pos[0] = anchor_global

	for _p: int in range(_constraint_passes):
		_pos[0] = anchor_global
		_solve_edge_anchor_to_first()
		for i: int in range(1, _seg - 1):
			_solve_edge_between(i, i + 1)
		_solve_edge_last_to_attach(attach_global, anchor_global)

	_collide_points(space, exclude_rid, rope_collision_exclude_rids, dt)

	_apply_body_tether_residual(anchor_global, attach_global, character, dt)

	_clamp_straight_span_to_payed(anchor_global, character)


func _attach_global_on(character: CharacterBody3D) -> Vector3:
	return character.global_position + character.global_transform.basis * _attach_local


func _clamp_straight_span_to_payed(anchor_global: Vector3, character: CharacterBody3D) -> void:
	var attach_g: Vector3 = _attach_global_on(character)
	var d: float = anchor_global.distance_to(attach_g)
	if d <= _payed_length + 0.015:
		return
	var dir: Vector3 = (attach_g - anchor_global) / maxf(d, 1e-6)
	var over: float = d - _payed_length
	_strain_audio = minf(1.0, maxf(_strain_audio, clampf(over / 0.22, 0.0, 1.0)))
	character.global_position -= dir * over
	var vn: float = character.velocity.dot(dir)
	if vn > 0.0:
		character.velocity -= dir * vn


## После `move_and_slide` у игрока — снова ограничить прямую «якорь — разъём».
func clamp_character_straight_line(anchor_global: Vector3, character: CharacterBody3D) -> void:
	_clamp_straight_span_to_payed(anchor_global, character)


func _solve_edge_anchor_to_first() -> void:
	var pa: Vector3 = _pos[0]
	var pb: Vector3 = _pos[1]
	var diff: Vector3 = pb - pa
	var dist: float = diff.length()
	if dist < 1e-7:
		return
	var err: float = dist - _rest
	if err <= 0.0:
		return
	var n: Vector3 = diff / dist
	var corr: float = err * _compliance * PBD_PASS_GAIN
	_pos[1] -= n * corr


func _solve_edge_between(ia: int, ib: int) -> void:
	var pa: Vector3 = _pos[ia]
	var pb: Vector3 = _pos[ib]
	var diff: Vector3 = pb - pa
	var dist: float = diff.length()
	if dist < 1e-7:
		return
	var err: float = dist - _rest
	if err <= 0.0:
		return
	var n: Vector3 = diff / dist
	var corr: float = err * 0.5 * _compliance * PBD_PASS_GAIN
	_pos[ia] += n * corr
	_pos[ib] -= n * corr


func _solve_edge_last_to_attach(attach: Vector3, anchor_global: Vector3) -> void:
	var ia: int = _seg - 2
	var ib: int = _seg - 1
	var pa: Vector3 = _pos[ia]
	var pb: Vector3 = _pos[ib]
	var diff1: Vector3 = pb - pa
	var d1: float = diff1.length()
	if d1 > 1e-7:
		var e1: float = d1 - _rest
		if e1 > 0.0:
			var n1: Vector3 = diff1 / d1
			var c1: float = e1 * 0.5 * _compliance * PBD_PASS_GAIN
			_pos[ia] += n1 * c1
			_pos[ib] -= n1 * c1

	pb = _pos[ib]
	var diff2: Vector3 = attach - pb
	var d2: float = diff2.length()
	if d2 < 1e-7:
		return
	var e2: float = d2 - _rest
	if e2 <= 0.0:
		return
	var n2: Vector3 = diff2 / d2
	var c2: float = e2 * _compliance * PBD_PASS_GAIN
	# Пока по прямой до якоря есть запас — не перетягивать последний узел к разъёму
	# (иначе при поворотах «ломается» последний сегмент и мешает джетпаку).
	var straight: float = anchor_global.distance_to(attach)
	var slack_frac: float = maxf(_slack_ratio, 0.05)
	var slack_end: float = _payed_length * (1.0 - slack_frac)
	if straight < slack_end + 0.15:
		c2 *= 0.22
	_pos[ib] += n2 * c2


func _apply_body_tether_residual(
	anchor_global: Vector3,
	attach: Vector3,
	character: CharacterBody3D,
	delta: float
) -> void:
	var straight: float = anchor_global.distance_to(attach)
	var slack_frac: float = maxf(_slack_ratio, 0.05)
	var slack_end: float = _payed_length * (1.0 - slack_frac)
	var ramp_end: float = mini(
		_payed_length * 0.993,
		maxf(slack_end + _payed_length * 0.05, _payed_length * 0.88)
	)
	if ramp_end <= slack_end + 1e-3:
		ramp_end = slack_end + _payed_length * 0.06
	var tension: float = _smoothstep01(straight, slack_end, ramp_end)
	if tension > 0.0005:
		var audio_boost: float = sqrt(tension)
		_strain_audio = minf(1.0, maxf(_strain_audio, audio_boost))
	if tension < 0.02:
		return

	var ib: int = _seg - 1
	var diff: Vector3 = attach - _pos[ib]
	var d: float = diff.length()
	if d < 1e-6:
		return
	var err: float = d - _rest
	if err < 0.12:
		return
	var n: Vector3 = diff / d
	var to_node: float = minf(err * 0.82 * tension, 0.28)
	_pos[ib] += n * to_node
	diff = attach - _pos[ib]
	d = diff.length()
	if d < 1e-6:
		return
	err = d - _rest
	if err < 0.1:
		return
	n = diff / d
	# Сдвиг тела по n здесь давал «ползучее» удлинение прямой дальше выпущенной длины — только узлы + демпф.
	var vn: float = character.velocity.dot(n)
	if vn > 0.0:
		var damp: float = (3.5 * err * delta + vn * 0.28) * tension * tension
		character.velocity -= n * minf(vn, damp)


func _smoothstep01(x: float, edge0: float, edge1: float) -> float:
	if x <= edge0:
		return 0.0
	if x >= edge1:
		return 1.0
	var t: float = (x - edge0) / maxf(1e-4, edge1 - edge0)
	return t * t * (3.0 - 2.0 * t)


func _collide_points(
	space: PhysicsDirectSpaceState3D,
	exclude_rid: RID,
	rope_collision_exclude_rids: Array,
	_delta: float
) -> void:
	_shape_q.collision_mask = _collision_mask
	var ex: Array = []
	if exclude_rid.is_valid():
		ex.append(exclude_rid)
	for item: Variant in rope_collision_exclude_rids:
		if item is RID:
			var rid: RID = item as RID
			if rid.is_valid():
				ex.append(rid)
	_shape_q.exclude = ex

	for _iter: int in range(_collision_resolve_steps):
		var moved: bool = false
		for i: int in range(1, _seg):
			_shape_q.transform = Transform3D(Basis(), _pos[i])
			var hits: Array = space.intersect_shape(_shape_q, 12)
			if hits.is_empty():
				continue
			var push: Vector3 = Vector3.ZERO
			for h: Variant in hits:
				var dict: Dictionary = h as Dictionary
				var ph_v: Variant = dict.get("position", null)
				var nv_v: Variant = dict.get("normal", null)
				var nrm: Vector3 = Vector3.ZERO
				if nv_v is Vector3 and (nv_v as Vector3).length_squared() > 1e-10:
					nrm = (nv_v as Vector3).normalized()
					if ph_v is Vector3:
						var to_node: Vector3 = _pos[i] - (ph_v as Vector3)
						if to_node.length_squared() > 1e-10 and nrm.dot(to_node) < 0.0:
							nrm = -nrm
				elif ph_v is Vector3:
					nrm = _pos[i] - (ph_v as Vector3)
				if nrm.length_squared() < 1e-10:
					var col: Variant = dict.get("collider", null)
					if col is Node3D:
						nrm = _pos[i] - (col as Node3D).global_position
				if nrm.length_squared() < 1e-10:
					continue
				nrm = nrm.normalized()
				push += nrm * minf(_collision_r * 1.5, 0.24)
			if push.length_squared() > 1e-12:
				if push.length() > 0.5:
					push = push.normalized() * 0.5
				_pos[i] += push
				moved = true
		if not moved:
			break
