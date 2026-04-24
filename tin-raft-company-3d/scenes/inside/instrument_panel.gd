extends StaticBody3D

@onready var status_label: Label3D = $StatusLabel
@onready var alert_label: Label3D = $AlertLabel

func _ready() -> void:
	var gs := get_node_or_null("/root/GameServices")
	if gs and gs.capsule_state_service:
		gs.capsule_state_service.state_changed.connect(_on_state_changed)
		_update_display(gs.capsule_state_service.get_snapshot())
	else:
		status_label.text = "[ NO SIGNAL ]"

func _on_state_changed(snapshot: Dictionary) -> void:
	_update_display(snapshot)

func _update_display(snapshot: Dictionary) -> void:
	var o2   := snapshot.get("oxygen",      100.0) as float
	var pr   := snapshot.get("pressure",    100.0) as float
	var temp := snapshot.get("temperature",  22.0) as float
	var pw   := snapshot.get("power",       100.0) as float
	var breach := snapshot.get("hull_breach", false) as bool

	# Each line kept <=22 chars to fit within the 0.67m screen mesh.
	status_label.text = (
		"== CAPSULE STATUS ==\n"
		+ "O2  %s %3.0f%%\n" % [_bar(o2), o2]
		+ "P   %s %3.0f%%\n" % [_bar(pr), pr]
		+ "T   %s %3.0fC\n"  % [_bar_temp(temp), temp]
		+ "PWR %s %3.0f%%"   % [_bar(pw), pw]
	)

	var critical := o2 < 30.0 or pr < 30.0 or pw < 15.0
	status_label.modulate = Color(1.0, 0.35, 0.3) if critical else Color(0.35, 1.0, 0.55)

	alert_label.text     = "! HULL BREACH !" if breach else ""
	alert_label.modulate = Color(1.0, 0.3, 0.2)

# ── Helpers ──────────────────────────────────────────────────────────────────

func _bar(value: float, length: int = 8) -> String:
	var filled := clampi(int(round(value / 100.0 * float(length))), 0, length)
	return "▓".repeat(filled) + "░".repeat(length - filled)

func _bar_temp(temp: float) -> String:
	# Map expected range -50 .. +80°C → 0..100 for the bar
	var normalized := clampf((temp + 50.0) / 130.0 * 100.0, 0.0, 100.0)
	return _bar(normalized)
