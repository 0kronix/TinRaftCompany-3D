extends RefCounted
class_name MultiplayerRuntime
## Проверка «мы в сети, не офлайн-заглушка» и безопасный disconnect сигналов.


static func has_active_session_for(node: Node) -> bool:
	if node == null:
		return false
	var p: MultiplayerPeer = node.multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer)


static func disconnect_if_connected(sig: Signal, cb: Callable) -> void:
	if sig.is_connected(cb):
		sig.disconnect(cb)
