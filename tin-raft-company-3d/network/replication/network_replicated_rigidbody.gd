extends RigidBody3D
class_name NetworkReplicatedRigidBody
## Сервер/host симулируют тело и шлют позу через NetworkManager;
## клиенты — буфер + интерполяция (WorldRigidReplicaSync.relay_snapshot).

@export_group("Network replicate")
@export var net_interp_delay_sec: float = 0.085
## Частота рассылки позы с сервера (выше — плавнее, дороже по трафику). Реф. ~частотаPhysics.
@export_range(20.0, 120.0, 1.0) var net_pose_sync_hz: float = 45.0

var _network_replica: RigidBodyNetworkReplica = RigidBodyNetworkReplica.new()
var _net_interp: NetworkRigidBodyInterpolator


func _ensure_net_interpolator() -> void:
	if _net_interp == null:
		_net_interp = NetworkRigidBodyInterpolator.new(net_interp_delay_sec)


func _enter_tree() -> void:
	RigidBodyNetworkReplica.apply_server_physics_authority(self)
	_network_replica.sync_hz = net_pose_sync_hz
	_ensure_net_interpolator()


func receive_net_physics_snapshot(pos: Vector3, rot_rad: Vector3) -> void:
	_ensure_net_interpolator()
	if is_multiplayer_authority():
		return
	_net_interp.push_snapshot(pos, rot_rad)


func _physics_process(delta: float) -> void:
	var net_active: bool = MultiplayerRuntime.has_active_session_for(self)
	if net_active:
		if not is_multiplayer_authority():
			_ensure_net_interpolator()
			_apply_network_interpolation()
			return

	# Сервер / одиночка: симуляция; рассылка позы только при активной сетевой сессии (иначе лишние проверки на каждом теле).
	if freeze:
		if net_active:
			_network_replica.step_authority_pose_broadcast(self, delta)
		return

	_network_simulate_authority(delta)
	if net_active:
		_network_replica.step_authority_pose_broadcast(self, delta)


## Под класс-модель: двигатель, силы, ввод до `step_authority_pose_broadcast` (вызывается только у authority или в офлайне).
func _network_simulate_authority(_delta: float) -> void:
	pass


func _apply_network_interpolation() -> void:
	var now_sec: float = float(Time.get_ticks_msec()) * 0.001
	var xf_variant: Variant = _net_interp.sample_transform(now_sec)
	if xf_variant == null:
		return
	var xf: Transform3D = xf_variant as Transform3D
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
