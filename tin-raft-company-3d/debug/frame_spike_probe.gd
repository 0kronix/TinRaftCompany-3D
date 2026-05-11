extends Node
## При длинном кадре печатает в Output сводку Performance + draw calls (без разбора по функциям —
## встроенный профайлер часто не даёт дерево по «Process»).
##
## Включение: в project.godot:
##   [frame_debug]
##   log_spikes=true
## Опционально: spike_threshold_ms, spike_cooldown_ms

const SETTING_LOG := "frame_debug/log_spikes"
const SETTING_THRESHOLD_MS := "frame_debug/spike_threshold_ms"
const SETTING_COOLDOWN_MS := "frame_debug/spike_cooldown_ms"


var _cooldown_until_usec: int = 0


func _ready() -> void:
	if not ProjectSettings.get_setting(SETTING_LOG, false):
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	# Конец idle-фазы кадра: мониторы уже отражают только что завершившийся кадр.
	get_tree().process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	var now_usec: int = Time.get_ticks_usec()
	if now_usec < _cooldown_until_usec:
		return

	var threshold_ms: float = float(ProjectSettings.get_setting(SETTING_THRESHOLD_MS, 32.0))
	var cooldown_ms: float = float(ProjectSettings.get_setting(SETTING_COOLDOWN_MS, 400.0))

	# Godot 4.x: TIME_PROCESS / TIME_PHYSICS_PROCESS в секундах (не мкс).
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	if proc_ms <= threshold_ms and phys_ms <= threshold_ms:
		return

	_cooldown_until_usec = now_usec + int(cooldown_ms * 1000.0)

	var fps1s: float = Performance.get_monitor(Performance.TIME_FPS)
	var nav_ms: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var obj: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	print_rich(
		"[color=yellow][FrameSpike][/color] ph=%d  [b]TIME_PROCESS[/b]=%.2f ms  [b]TIME_PHYSICS_PROCESS[/b]=%.2f ms  [b]NAV[/b]=%.2f ms  FPS(1s)=%.1f  objs=%d orphan=%d  mem=%.1f MiB  draw_calls=%d  prim=%d"
		% [
			Engine.get_process_frames(),
			proc_ms,
			phys_ms,
			nav_ms,
			fps1s,
			obj,
			orphan,
			mem_mb,
			draws,
			prim,
		]
	)
