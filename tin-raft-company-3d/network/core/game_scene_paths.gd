extends RefCounted
class_name GameScenePaths
## Стабильные сегменты путей main.tscn: спавнер игроков, маркеры шлюза, шаттл EVA.

const INSIDE := "Inside"
const PLAYER_CONTAINER := "EVA/ShipInterior/PlayerContainer"
const EVA_SHUTTLE := INSIDE + "/EVA/Shuttle"
## Маркер на сцене шаттла: откуда/куда направлен выброс из шлюзового ящика (вращайте узел в редакторе).
const EVA_SHUTTLE_CRATE_EJECT := EVA_SHUTTLE + "/CrateEjectPort"
const EVA_SHUTTLE_EVASPAWN := EVA_SHUTTLE + "/EvaSpawn"
## Узел штурвала EVA (команды `open_interactable_ui`; стабильный путь без get_path()).

const SHUTTLE_HELM := INSIDE + "/EVA/ShipInterior/ShuttleHelm"
## Спавнер мира (метеориты/обломки) под `Inside` — для проверки «под деревом ли предмет».
const WORLD_OBJECTS := INSIDE + "/WorldObjects"


static func player_puppet_path_str(peer_id: int) -> String:
	return "%s/%s/Player_%d" % [INSIDE, PLAYER_CONTAINER, peer_id]


static func get_world_objects_node(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null(WORLD_OBJECTS)
