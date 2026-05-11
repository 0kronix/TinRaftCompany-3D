extends Node
## Прогулочные замеры: раз в N секунд печатает min/avg/p95/max по TIME_PROCESS и физике.
## Включение: [frame_debug] walk_perf_log=true
## Секции (микрорсчёт в коде): walk_perf_sections=true → record_section() + sections_enabled()

const SETTING_LOG := "frame_debug/walk_perf_log"
const SETTING_INTERVAL := "frame_debug/walk_perf_interval_sec"
const SETTING_CAP := "frame_debug/walk_perf_sample_cap"
const SETTING_SECTIONS := "frame_debug/walk_perf_sections"


var _proc_ms: Array[float] = []
var _phys_ms: Array[float] = []
var _cap: int = 600
var _sec_usec: Dictionary = {}
var _sec_n: Dictionary = {}


func _ready() -> void:
	if not ProjectSettings.get_setting(SETTING_LOG, false):
		return

	_cap = maxi(32, int(ProjectSettings.get_setting(SETTING_CAP, 600)))
	get_tree().process_frame.connect(_on_process_frame)

	var timer := Timer.new()
	timer.wait_time = maxf(0.25, float(ProjectSettings.get_setting(SETTING_INTERVAL, 2.0)))
	timer.timeout.connect(_on_flush_timer)
	timer.autostart = true
	add_child(timer)


func _on_process_frame() -> void:
	var p: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var h: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_append_sample(_proc_ms, p)
	_append_sample(_phys_ms, h)


func _append_sample(buf: Array[float], v: float) -> void:
	buf.append(v)
	while buf.size() > _cap:
		buf.pop_front()


static func sections_enabled() -> bool:
	return (
		ProjectSettings.get_setting(SETTING_LOG, false)
		and ProjectSettings.get_setting(SETTING_SECTIONS, false)
	)


func record_section(id: StringName, delta_usec: int) -> void:
	if not sections_enabled():
		return
	_sec_usec[id] = int(_sec_usec.get(id, 0)) + delta_usec
	_sec_n[id] = int(_sec_n.get(id, 0)) + 1


func _on_flush_timer() -> void:
	if _proc_ms.is_empty():
		return

	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var fps1s: float = Performance.get_monitor(Performance.TIME_FPS)

	var sp: Dictionary = _stats(_proc_ms)
	var sh: Dictionary = _stats(_phys_ms)

	print_rich(
		(
			"[color=cyan][WalkPerf][/color] n=%d  proc_ms  min=%.2f avg=%.2f p95=%.2f max=%.2f | phys_ms min=%.2f avg=%.2f max=%.2f | FPS(1s)=%.1f draws=%d prim=%d objs=%d"
			% [
				_proc_ms.size(),
				sp["min"],
				sp["avg"],
				sp["p95"],
				sp["max"],
				sh["min"],
				sh["avg"],
				sh["max"],
				fps1s,
				draws,
				prim,
				objs,
			]
		)
	)

	if sections_enabled() and not _sec_usec.is_empty():
		for id: StringName in _sec_usec.keys():
			var total_usec: int = int(_sec_usec[id])
			var cnt: int = int(_sec_n.get(id, 1))
			print(
				"    section ",
				id,
				": total_ms=",
				snappedf(total_usec / 1000.0, 0.001),
				" n=",
				cnt,
				" avg_ms=",
				snappedf((total_usec / float(cnt)) / 1000.0, 0.001),
			)
		_sec_usec.clear()
		_sec_n.clear()


func _stats(buf: Array[float]) -> Dictionary:
	if buf.is_empty():
		return {"min": 0.0, "max": 0.0, "avg": 0.0, "p95": 0.0}
	var tmp: Array[float] = buf.duplicate()
	tmp.sort()
	var n: int = tmp.size()
	var sum: float = 0.0
	for x: float in tmp:
		sum += x
	var i95: int = clampi(int((n - 1) * 0.95), 0, n - 1)
	return {
		"min": tmp[0],
		"max": tmp[n - 1],
		"avg": sum / float(n),
		"p95": tmp[i95],
	}
