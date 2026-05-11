extends RefCounted
class_name RigidBodyNetworkReplica
## Серверное владение RigidBody (authority по умолчанию 1): клиенты freeze kinematic,
## поза рассылается через NetworkManager, т.к. @rpc на RigidBody недопустим (scene_cache / simplify path).


var sync_hz: float = 45.0
var _accum: float = 0.0


func reset_accumulator() -> void:
	_accum = 0.0


## Офлайн: authority остаётся у локального пира; в сети — владелец `authority_peer` (обычно 1 = сервер).
static func apply_server_physics_authority(rb: RigidBody3D, authority_peer: int = 1) -> void:
	if MultiplayerRuntime.has_active_session_for(rb):
		rb.set_multiplayer_authority(authority_peer)
	if not rb.is_multiplayer_authority():
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		# Дискретные снапшоты с сервера — без сглаживания между тиками RPC/рендера.
		rb.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# Если RigidBody — ребёнок движущейся платформы, родитель каждый физ-тик
		# сдвигает узел; RPC даёт уже мировой transform — без top_level они борются и «мерцают» в двух точках.
		rb.top_level = true


## Один шаг физики: только владелец симуляции шлёт позу с заданной частотой.
func step_authority_pose_broadcast(rb: RigidBody3D, delta: float) -> void:
	# Проверка сессии — один раз в NetworkReplicatedRigidBody._physics_process; здесь тысячи тел × было лишний раз.
	if not rb.is_multiplayer_authority():
		return
	_accum += delta
	if _accum < 1.0 / sync_hz:
		return
	_accum = 0.0
	if NetworkManager.has_method("broadcast_world_rigid_transform"):
		NetworkManager.broadcast_world_rigid_transform(str(rb.get_path()), rb.global_position, rb.global_rotation)
