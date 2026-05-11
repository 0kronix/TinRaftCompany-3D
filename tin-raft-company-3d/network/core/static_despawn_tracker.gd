extends RefCounted
class_name StaticDespawnTracker
## Серверный учёт путей статических узлов, уничтоженных за сессию (late join в world_manager).

var _paths: PackedStringArray = []


func try_record(path_str: String) -> bool:
	if _paths.has(path_str):
		return false
	_paths.append(path_str)
	return true


func get_paths_copy() -> PackedStringArray:
	return _paths.duplicate()


func clear() -> void:
	_paths.clear()
