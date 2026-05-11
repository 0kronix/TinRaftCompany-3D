extends RefCounted
class_name NetworkRigidBodyInterpolator
## Буфер снапшотов + выборка с задержкой; рендер плавнее, чем голый RPC ~30 Гц.
## Время через Time.get_ticks_msec() для сопоставления с входящими пакетами.


const MAX_SNAPSHOTS: int = 32

var _delay_sec: float
var _snapshots: Array[Dictionary] = [] # { "t": float, "xf": Transform3D }


func _init(interpolation_delay_sec: float = 0.085) -> void:
	_delay_sec = maxf(interpolation_delay_sec, 0.0)


func set_delay_sec(sec: float) -> void:
	_delay_sec = maxf(sec, 0.0)


func push_snapshot(pos: Vector3, euler_rot_rad: Vector3) -> void:
	var t_ms: float = float(Time.get_ticks_msec())
	var t_sec := t_ms * 0.001
	var xf := Transform3D(Basis.from_euler(euler_rot_rad), pos)
	while _snapshots.size() >= MAX_SNAPSHOTS:
		_snapshots.pop_front()
	_snapshots.append({"t": t_sec, "xf": xf})


## По ``now_sec`` (тот же масштаб, что из Time.get_ticks_msec()*0.001).
func sample_transform(now_sec: float) -> Variant:
	var target_t := now_sec - _delay_sec
	if _snapshots.is_empty():
		return null
	if _snapshots.size() == 1:
		return _snapshots[0]["xf"]

	var idx := -1
	for i in range(_snapshots.size() - 1):
		var seg_a: float = _snapshots[i]["t"]
		var seg_b: float = _snapshots[i + 1]["t"]
		if seg_a <= target_t and target_t <= seg_b:
			idx = i
			break

	if idx < 0:
		if target_t < _snapshots[0]["t"]:
			return _snapshots[0]["xf"]
		return _snapshots[_snapshots.size() - 1]["xf"]

	var seg_t0 := float(_snapshots[idx]["t"])
	var seg_t1 := float(_snapshots[idx + 1]["t"])
	var xf0: Transform3D = _snapshots[idx]["xf"]
	var xf1: Transform3D = _snapshots[idx + 1]["xf"]
	var denom: float = seg_t1 - seg_t0
	var f := 0.0 if denom <= 1e-8 else clampf((target_t - seg_t0) / denom, 0.0, 1.0)
	return xf0.interpolate_with(xf1, f)


func clear() -> void:
	_snapshots.clear()
