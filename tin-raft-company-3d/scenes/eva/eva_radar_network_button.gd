extends StaticBody3D

enum Op { MODE_TOGGLE, PEER_CYCLE }
@export var op: Op = Op.MODE_TOGGLE


func show_hint() -> void:
	pass


func hide_hint() -> void:
	pass


func build_interaction_command() -> Dictionary:
	match op:
		Op.MODE_TOGGLE:
			return {
				"type": "radar_set_mode",
				"target_path": GameScenePaths.EVA_RADAR_CLUSTER,
			}
		Op.PEER_CYCLE:
			return {
				"type": "radar_cycle_peer",
				"target_path": GameScenePaths.EVA_RADAR_CLUSTER,
			}
		_:
			return {}


func interact(_caller: Node3D) -> void:
	pass
