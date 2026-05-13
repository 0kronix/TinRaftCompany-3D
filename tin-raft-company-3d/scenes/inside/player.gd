extends CharacterBody3D

signal vitals_changed(snapshot: Dictionary)

const JUMP_VELOCITY = 4.5
const DEFAULT_MOUSE_SENSITIVITY := 0.003
const LOBBY_SCENE := "res://scenes/network/lobby.tscn"
const DEAD_BODY_PUSH_RADIUS := 0.95
const DEAD_BODY_PUSH_ACCEL := 7.5
const REVIVE_COMMAND_TYPE := "revive_player"
const VITAL_MIN_VALUE := 0.0
const VITAL_DEFAULT_MAX := 100.0
const PLAYER_OXYGEN_CONSUMPTION_PER_SECOND := 0.1
const PLAYER_OXYGEN_RESTORE_PER_SECOND := 0.1
const PLAYER_PRESSURE_LOSS_PER_SECOND := 1
const PLAYER_PRESSURE_RESTORE_PER_SECOND := 1
const SUFFOCATION_DAMAGE_MIN := 9.0
const SUFFOCATION_DAMAGE_MAX := 11.0
const SUFFOCATION_DAMAGE_INTERVAL_MIN := 1.0
const SUFFOCATION_DAMAGE_INTERVAL_MAX := 2.0
const PRESSURE_DAMAGE_MIN := 15.0
const PRESSURE_DAMAGE_MAX := 25.0
const PRESSURE_DAMAGE_INTERVAL_MIN := 0.5
const PRESSURE_DAMAGE_INTERVAL_MAX := 1.0
const SHIP_OXYGEN_REFILL_REQUEST_INTERVAL := 0.25
const LOW_OXYGEN_WARNING_PERCENT := 20.0
const LOW_PRESSURE_WARNING_PERCENT := 20.0

## Open-space EVA: 6DOF — включается телепортом с шлюза (NetworkManager) или в space_eva.
@export var eva_mode: bool = false

@onready var head   = $Head
@onready var camera = $Head/Camera3D
@onready var ray    = $Head/Camera3D/RayCast3D


func _enter_tree() -> void:
	# Name is "Player_X" — extract peer_id and set authority here.
	# Godot 4 requires that multiplayer authority be set during _enter_tree
	# so that MultiplayerSynchronizer can obtain its network ID correctly.
	var peer_id := name.trim_prefix("Player_").to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
		_setup_sync()


func _setup_sync() -> void:
	var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync == null:
		return
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	config.add_property(NodePath(".:is_dead"))
	config.add_property(NodePath(".:current_health"))
	config.add_property(NodePath(".:current_oxygen"))
	config.add_property(NodePath(".:current_pressure"))
	config.add_property(NodePath(".:eva_mode"))
	config.add_property(NodePath(".:eva_jetpack_thrust_strength"))
	config.add_property(NodePath(".:eva_jetpack_thrust_dir"))
	config.add_property(NodePath(".:eva_shuttle_tether_attached"))
	config.add_property(NodePath(".:eva_shuttle_tether_module_path"))
	config.add_property(NodePath(".:tether_rope_visual_radius"))
	# В EVA head остаётся 0, но синхронизируем, чтобы плавно переключать режим у кукол.
	config.add_property(NodePath("Head:rotation"))
	sync.replication_config = config
	# Было 30 Hz — куклы других игроков заметно «ступенчато» на 60 FPS дисплее.
	sync.replication_interval = 1.0 / 60.0

# --- ДВИЖЕНИЕ ---
var SPEED        = 4.5
var acceleration = 12.0
var friction     = 10.0
## Интерьер: накопление для шагов (только authority).
var _footstep_phase: float = 0.0

# --- ПРЫЖОК И ФИЗИКА ---
var jump_force      = 4.8
var gravity         = 9.8 * 1.5
var fall_multiplier = 1.6

# --- ВОЗДУХ ---
var air_control = 0.3

# --- EVA (космос): ньютоновская инерция — тяга накапливает скорость, нет вязкого трения.
const EVA_THRUST: float   = 2.0
## Предел скорости (м/с), снимаем только в крайних случаях; при необходимости увеличь.
const EVA_SPEED_CAP: float = 60.0

var current_hovered = null
var inventory_open  := false
var menu_open       := false
var is_dead: bool = false:
	set(value):
		is_dead = value
		if not is_dead:
			hide_hint()
@export_group("Player vitals")
@export var max_health: float = VITAL_DEFAULT_MAX:
	set(value):
		max_health = maxf(value, 1.0)
		current_health = clampf(current_health, VITAL_MIN_VALUE, max_health)
@export var max_oxygen: float = VITAL_DEFAULT_MAX:
	set(value):
		max_oxygen = maxf(value, 1.0)
		current_oxygen = clampf(current_oxygen, VITAL_MIN_VALUE, max_oxygen)
@export var max_pressure: float = VITAL_DEFAULT_MAX:
	set(value):
		max_pressure = maxf(value, 1.0)
		current_pressure = clampf(current_pressure, VITAL_MIN_VALUE, max_pressure)
var current_health: float = VITAL_DEFAULT_MAX:
	set(value):
		current_health = clampf(value, VITAL_MIN_VALUE, max_health)
		_on_current_health_changed()
var current_oxygen: float = VITAL_DEFAULT_MAX:
	set(value):
		current_oxygen = clampf(value, VITAL_MIN_VALUE, max_oxygen)
		_on_current_oxygen_changed()
var current_pressure: float = VITAL_DEFAULT_MAX:
	set(value):
		current_pressure = clampf(value, VITAL_MIN_VALUE, max_pressure)
		_on_current_pressure_changed()
@export_group("")
var _ship_oxygen_breath_pending: float = 0.0
var _ship_oxygen_refill_pending: float = 0.0
var _ship_oxygen_refill_timer: float = 0.0
var _suffocation_damage_timer: float = 0.0
var _pressure_damage_timer: float = 0.0
var _oxygen_warning_material: ShaderMaterial = null
var _death_overlay: Control = null
## Кратковременно при модальном UI (E на интерактиве) — ввод/физика отключены.
var modal_ui_block: bool = false
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var invert_mouse_y: bool     = false
var _ping_row: HBoxContainer = null
var _ping_label: Label = null
var _ping_tx_dot: Panel = null
var _ping_tx_style: StyleBoxFlat = null
var _ping_radio_label: Label = null
## 0..1, сила ввода джетпака (только в EVA) — для камеры / тряски
var eva_jetpack_thrust_strength: float = 0.0
## Нормализованное направление тяги в локале тела (как `wish`) — для тряски камеры вдоль тяги
var eva_jetpack_thrust_dir: Vector3 = Vector3.ZERO

## Кабель шаттла (EVA): точка на спине в локале капсулы (+Z — «назад», вперёд у wish — −Z).
const EVA_SHUTTLE_TETHER_ATTACH_LOCAL := Vector3(0.0, 0.62, 0.22)
## Слой коллайдеров «трос у тела» — добавляется в маску CharacterBody при цеплении.
const TETHER_PLAYER_COLLISION_LAYER := 20
## Совпадает с `Shuttle.INTERIOR_STATIC_LAYER` — EVA-игрок уже смотрит слой 11.
const TETHER_INTERIOR_LAYER: int = 11
## Только 11 и 20: корпус шаттла (слой 1) не резолвится с цилиндрами троса: корабль «не чувствует» кабель.
## Упирание в обшивку остаётся за счёт Verlet (`rope_collision_mask` включает слой 1).
const TETHER_ROPE_COLLISION_LAYERS: int = (1 << (TETHER_INTERIOR_LAYER - 1)) | (1 << (TETHER_PLAYER_COLLISION_LAYER - 1))
const TETHER_COLLISION_SEG_POOL := 36
## Скорость схождения фактической длины троса к целевой (м/с).
const TETHER_PAYED_CATCHUP_MPS := 3.6
## Скорость изменения целевой длины при удержании клавиши (м/с).
const TETHER_DESIRED_REEL_MPS := 1.25
var eva_shuttle_tether_attached: bool = false
var eva_shuttle_tether_module_path: String = ""
## Радиус троса для отрисовки у других игроков (синхронизатор копирует с владельца).
var tether_rope_visual_radius: float = 0.038
var _tether_anchor: Node3D = null
var _tether_length_min: float = 5.0
var _tether_length_max: float = 34.0
var _tether_length_step: float = 0.75
var _tether_payed_length: float = 5.0
## Целевая выпущенная длина (кнопки); фактическая длина в симе догоняет плавно.
var _tether_payed_length_desired: float = 5.0
var _tether_reel_tick_cd: float = 0.0
var _tether_limit_ping_cd: float = 0.0
var _tether_slack_ratio: float = 0.14
var _tether_spring: float = 90.0
var _tether_damping: float = 7.0
var _tether_cable_radius: float = 0.035
var _tether_mesh_inst: MeshInstance3D = null
var _tether_rope_array_mesh: ArrayMesh = null
var _rope_sim: EvaShuttleRopeSim = null
var _tether_rope_publish_phase: int = 0
var _puppet_tether_pts: PackedVector3Array = PackedVector3Array()
var _tether_collision_holder: Node3D = null
var _tether_collision_seg_bodies: Array[StaticBody3D] = []
## Исключение пары игрок↔сегмент троса (трос остаётся в мире, шаттл цепляется).
var _tether_seg_player_exception: Array[bool] = []

@export var debug_eva_head_bob_sync: bool = false
var _debug_warned_no_cam_method: bool = false


func _ready() -> void:
	## Слой совпадает с `Shuttle.INTERIOR_STATIC_LAYER` — шлюз на шаттле (дочерний StaticBody).
	set_collision_mask_value(11, true)
	if ray:
		ray.set_collision_mask_value(11, true)
	if is_multiplayer_authority():
		_setup_local_player()
	else:
		_setup_puppet()
	_emit_vitals_changed()


## Called for the local player — the one this peer controls.
func _setup_local_player() -> void:
	add_to_group("player")
	# Activate this player's camera explicitly — required when multiple Camera3D
	# nodes exist in the scene (e.g. other players' puppet cameras set to false).
	camera.current = true
	close_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_apply_control_settings()
	# First-person: hide own body mesh.
	var body_mesh := get_node_or_null("BodyMesh")
	if body_mesh:
		body_mesh.visible = false
	if eva_mode:
		head.rotation = Vector3.ZERO
		up_direction  = Vector3.UP
	_setup_oxygen_warning_effect()
	_setup_ping_display()


## Called for all other players — they are puppets driven by MultiplayerSynchronizer.
func _setup_puppet() -> void:
	remove_from_group("player")
	set_physics_process(false)
	set_process(true)
	set_process_unhandled_input(false)
	# Show the body so other players are visible.
	var body_mesh := get_node_or_null("BodyMesh")
	if body_mesh:
		body_mesh.visible = true
	# Disable camera so it doesn't fight the local player's camera.
	if camera:
		camera.current = false
	# Remove UI layers — puppets don't need HUD, inventory, menu, or shader overlay.
	for layer_name: String in ["UILayer", "MenuLayer", "ShaiderLayer"]:
		var node := get_node_or_null(layer_name)
		if node:
			node.queue_free()


func set_modal_ui_block(v: bool) -> void:
	modal_ui_block = v


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if is_dead:
		_process_dead_look_input(event)
		return
	if modal_ui_block:
		return

	if event.is_action_pressed("ui_close") and inventory_open:
		close_inventory()
		return

	if event.is_action_pressed("ui_close"):
		toggle_menu()
		return

	if event.is_action_pressed("inventory"):
		toggle_inventory()
		return

	if inventory_open or menu_open:
		return

	# --- ВРАЩЕНИЕ (интерьер: yaw тело, pitch голова; EVA: 6DOF на теле) ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if eva_mode:
			rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
			var y_delta: float = event.relative.y if invert_mouse_y else -event.relative.y
			rotate_object_local(Vector3.RIGHT, y_delta * mouse_sensitivity)
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			var y_delta2: float = event.relative.y if invert_mouse_y else -event.relative.y
			head.rotate_x(y_delta2 * mouse_sensitivity)
			head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)


func _holding_walkie_talkie() -> bool:
	var hb: Node = get_node_or_null("HotbarComponent")
	if hb is HotbarComponent:
		var it: ItemResource = (hb as HotbarComponent).get_active_item()
		return it != null and it.is_walkie_talkie
	return false


func _update_radio_ptt_voice_manager() -> void:
	var vm := get_node_or_null("/root/VoiceManager")
	if vm == null or not vm.has_method("set_radio_ptt_active"):
		return
	var allow: bool = (
		not is_dead
		and not menu_open
		and not inventory_open
		and not modal_ui_block
		and _holding_walkie_talkie()
		and Input.is_action_pressed("radio_ptt")
	)
	vm.set_radio_ptt_active(allow)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_update_radio_ptt_voice_manager()
		_update_voice_tx_dot()
		if not is_dead:
			_update_player_oxygen(delta)
			_update_player_pressure(delta)
			_update_suffocation_damage(delta)
			_update_pressure_damage(delta)
	if not is_multiplayer_authority():
		return
	if is_dead:
		_physics_process_dead(delta)
		return
	if modal_ui_block:
		velocity = Vector3.ZERO
		eva_jetpack_thrust_strength = 0.0
		eva_jetpack_thrust_dir = Vector3.ZERO
		return
	if not eva_mode:
		eva_jetpack_thrust_strength = 0.0
		eva_jetpack_thrust_dir = Vector3.ZERO
	if eva_mode:
		_physics_process_eva(delta)
	else:
		_physics_process_interior(delta)
	_sync_eva_camera_physics_hints()
	if not menu_open and not inventory_open:
		if Input.is_action_just_pressed("interact"):
			_try_interact()


func _sync_eva_camera_physics_hints() -> void:
	## head_bob: передаём eva/thrust явно каждый физкадр
	if not is_instance_valid(camera):
		if not _debug_warned_no_cam_method:
			push_error("[Player EvaHeadBob] $Head/Camera3D нет (camera=null)")
			_debug_warned_no_cam_method = true
	elif not camera.has_method("set_eva_jetpack_state"):
		if not _debug_warned_no_cam_method:
			push_error("[Player EvaHeadBob] на камере нет set_eva_jetpack_state; path=" + str(camera.get_path()))
			_debug_warned_no_cam_method = true
	else:
		var ph: int = Engine.get_physics_frames()
		camera.set_eva_jetpack_state(eva_mode, eva_jetpack_thrust_strength, eva_jetpack_thrust_dir, velocity)
		if debug_eva_head_bob_sync and eva_mode and (ph % 60 == 0 or ph <= 2):
			print(
				"[Player] sync cam ph=",
				ph,
				" after set_eva (eva, thrust, |v|) = (",
				eva_mode,
				", ",
				snappedf(eva_jetpack_thrust_strength, 0.001),
				", ",
				snappedf(velocity.length(), 0.01),
				")"
			)


func _physics_process_interior(delta: float) -> void:
	if menu_open:
		return

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back")  - Input.get_action_strength("move_forward")
	).normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force
		SoundManager.play_interior_at(self, "jump_interior", -1.0)

	if not is_on_floor():
		velocity.y -= gravity * (fall_multiplier if velocity.y < 0 else 1.0) * delta

	var ctrl: float = 1.0 if is_on_floor() else air_control
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * SPEED, acceleration * ctrl * delta)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, acceleration * ctrl * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)

	move_and_slide()
	_update_interior_footsteps(delta, input_dir)
	_update_hover()


func _update_interior_footsteps(delta: float, input_dir: Vector2) -> void:
	var horiz: float = Vector2(velocity.x, velocity.z).length()
	var wish_move: bool = input_dir.length_squared() > 0.01
	if not is_on_floor() or not wish_move or horiz < 0.25:
		_footstep_phase = 0.0
		return
	_footstep_phase += delta
	var cadence: float = lerpf(0.48, 0.32, clampf(horiz / SPEED, 0.0, 1.0))
	if _footstep_phase >= cadence:
		_footstep_phase = 0.0
		SoundManager.play_interior_at(self, "footstep_interior", -4.0)


func _physics_process_eva(delta: float) -> void:
	if menu_open:
		eva_jetpack_thrust_strength = 0.0
		eva_jetpack_thrust_dir = Vector3.ZERO
		return
	up_direction = global_transform.basis.y

	var wish := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("jump") - Input.get_action_strength("eva_down"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if wish.length() > 1.0:
		wish = wish.normalized()
	eva_jetpack_thrust_strength = 0.0
	eva_jetpack_thrust_dir = Vector3.ZERO
	if wish.length_squared() > 0.0001:
		eva_jetpack_thrust_strength = minf(1.0, wish.length())
		var wn: Vector3 = wish.normalized()
		eva_jetpack_thrust_dir = wn
		velocity += (global_transform.basis * wn) * EVA_THRUST * wish.length() * delta
		var speed: float = velocity.length()
		if speed > EVA_SPEED_CAP:
			velocity = velocity * (EVA_SPEED_CAP / speed)

	if eva_shuttle_tether_attached:
		if _tether_anchor == null or not is_instance_valid(_tether_anchor) or _rope_sim == null:
			shuttle_tether_detach()
		else:
			_update_tether_payed_smooth_and_audio(delta)
			var w3d: World3D = get_world_3d()
			if w3d != null:
				_rope_sim.step(
					_tether_anchor.global_position,
					_shuttle_tether_attach_point_global(),
					delta,
					self,
					w3d.direct_space_state,
					get_rid(),
					_tether_rope_static_exclude_for_sim()
				)

	move_and_slide()

	if eva_shuttle_tether_attached and _rope_sim != null and _tether_anchor != null and is_instance_valid(_tether_anchor):
		_rope_sim.clamp_character_straight_line(_tether_anchor.global_position, self)
		SoundManager.set_tether_stress_loop(self, _rope_sim.get_tether_strain_for_audio())

	_update_shuttle_tether_visual()
	_update_hover()


func _physics_process_dead(delta: float) -> void:
	eva_jetpack_thrust_strength = 0.0
	eva_jetpack_thrust_dir = Vector3.ZERO
	_hide_hover_hint()

	if eva_mode:
		up_direction = global_transform.basis.y
		_apply_dead_body_player_push(delta)
		if eva_shuttle_tether_attached:
			if _tether_anchor == null or not is_instance_valid(_tether_anchor) or _rope_sim == null:
				shuttle_tether_detach()
			else:
				_update_tether_payed_smooth_and_audio(delta)
				var w3d: World3D = get_world_3d()
				if w3d != null:
					_rope_sim.step(
						_tether_anchor.global_position,
						_shuttle_tether_attach_point_global(),
						delta,
						self,
						w3d.direct_space_state,
						get_rid(),
						_tether_rope_static_exclude_for_sim()
					)
		move_and_slide()
		if eva_shuttle_tether_attached and _rope_sim != null and _tether_anchor != null and is_instance_valid(_tether_anchor):
			_rope_sim.clamp_character_straight_line(_tether_anchor.global_position, self)
			SoundManager.set_tether_stress_loop(self, _rope_sim.get_tether_strain_for_audio())
		_update_shuttle_tether_visual()
	else:
		if not is_on_floor():
			velocity.y -= gravity * (fall_multiplier if velocity.y < 0 else 1.0) * delta
		else:
			velocity.x = move_toward(velocity.x, 0.0, friction * 0.15 * delta)
			velocity.z = move_toward(velocity.z, 0.0, friction * 0.15 * delta)
		_apply_dead_body_player_push(delta)
		move_and_slide()

	_sync_eva_camera_physics_hints()


func _apply_dead_body_player_push(delta: float) -> void:
	var player_container := get_parent()
	if player_container == null:
		return
	for node: Node in player_container.get_children():
		if node == self or not (node is Node3D):
			continue
		var offset: Vector3 = global_position - (node as Node3D).global_position
		if not eva_mode:
			offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001 or distance >= DEAD_BODY_PUSH_RADIUS:
			continue
		var push_ratio := 1.0 - (distance / DEAD_BODY_PUSH_RADIUS)
		velocity += offset.normalized() * DEAD_BODY_PUSH_ACCEL * push_ratio * delta


func _process(_delta: float) -> void:
	if is_instance_valid(head):
		if eva_mode:
			SoundManager.set_eva_jetpack_loop(self, eva_jetpack_thrust_strength, eva_jetpack_thrust_dir)
		else:
			SoundManager.set_eva_jetpack_loop(self, 0.0, Vector3.ZERO)
	if is_multiplayer_authority():
		return
	if not eva_mode:
		return
	_update_puppet_shuttle_tether_rope_visual()


func _update_hover() -> void:
	# Clear stale reference if the object was freed (e.g. picked up by another player).
	if current_hovered != null and not is_instance_valid(current_hovered):
		current_hovered = null

	if ray.is_colliding():
		var obj = ray.get_collider()
		if obj != current_hovered:
			if current_hovered and current_hovered.has_method("hide_hint"):
				current_hovered.hide_hint()
			if obj.has_method("show_hint"):
				obj.show_hint()
				current_hovered = obj
			else:
				current_hovered = null
	else:
		if current_hovered and current_hovered.has_method("hide_hint"):
			current_hovered.hide_hint()
		current_hovered = null


func _hide_hover_hint() -> void:
	if current_hovered != null and is_instance_valid(current_hovered) and current_hovered.has_method("hide_hint"):
		current_hovered.hide_hint()
	current_hovered = null


func get_vitals_snapshot() -> Dictionary:
	return {
		"peer_id": _peer_id_from_player_name(),
		"health": current_health,
		"max_health": max_health,
		"oxygen": current_oxygen,
		"max_oxygen": max_oxygen,
		"pressure": current_pressure,
		"max_pressure": max_pressure
	}


func set_player_vitals(health: float, oxygen: float, pressure: float) -> void:
	current_health = health
	current_oxygen = oxygen
	current_pressure = pressure


func change_player_vitals(health_delta: float, oxygen_delta: float, pressure_delta: float) -> void:
	change_health(health_delta)
	change_oxygen(oxygen_delta)
	change_pressure(pressure_delta)


func change_health(amount: float) -> void:
	current_health += amount


func change_oxygen(amount: float) -> void:
	current_oxygen += amount


func change_pressure(amount: float) -> void:
	current_pressure += amount


func reset_player_vitals() -> void:
	current_health = max_health
	current_oxygen = max_oxygen
	current_pressure = max_pressure


func _on_current_health_changed() -> void:
	_emit_vitals_changed()
	if current_health <= VITAL_MIN_VALUE and not is_dead and is_inside_tree() and is_multiplayer_authority():
		_die()


func _on_current_oxygen_changed() -> void:
	_emit_vitals_changed()
	_update_oxygen_warning_effect()


func _on_current_pressure_changed() -> void:
	_emit_vitals_changed()
	_update_pressure_warning_effect()


func _setup_oxygen_warning_effect() -> void:
	var shader_rect := get_node_or_null("ShaiderLayer/ColorRect") as ColorRect
	if shader_rect == null:
		return
	var shader_material := shader_rect.material as ShaderMaterial
	if shader_material == null:
		return
	_oxygen_warning_material = shader_material.duplicate() as ShaderMaterial
	shader_rect.material = _oxygen_warning_material
	_update_oxygen_warning_effect()
	_update_pressure_warning_effect()


func _update_oxygen_warning_effect() -> void:
	if _oxygen_warning_material == null:
		return
	var oxygen_percent := 100.0
	if max_oxygen > VITAL_MIN_VALUE:
		oxygen_percent = current_oxygen / max_oxygen * 100.0
	var warning_strength := 0.0
	if oxygen_percent < LOW_OXYGEN_WARNING_PERCENT:
		warning_strength = clampf((LOW_OXYGEN_WARNING_PERCENT - oxygen_percent) / LOW_OXYGEN_WARNING_PERCENT, 0.0, 1.0)
	_oxygen_warning_material.set_shader_parameter("red_vignette_strength", warning_strength)


func _update_pressure_warning_effect() -> void:
	if _oxygen_warning_material == null:
		return
	var pressure_percent := 100.0
	if max_pressure > VITAL_MIN_VALUE:
		pressure_percent = current_pressure / max_pressure * 100.0
	var warning_strength := 0.0
	if pressure_percent < LOW_PRESSURE_WARNING_PERCENT:
		warning_strength = clampf((LOW_PRESSURE_WARNING_PERCENT - pressure_percent) / LOW_PRESSURE_WARNING_PERCENT, 0.0, 1.0)
	_oxygen_warning_material.set_shader_parameter("pressure_vignette_strength", warning_strength)


func _update_suffocation_damage(delta: float) -> void:
	if current_oxygen > VITAL_MIN_VALUE:
		_suffocation_damage_timer = 0.0
		return
	if _suffocation_damage_timer <= 0.0:
		_suffocation_damage_timer = _next_suffocation_damage_interval()
	_suffocation_damage_timer -= delta
	if _suffocation_damage_timer > 0.0:
		return
	change_health(-randf_range(SUFFOCATION_DAMAGE_MIN, SUFFOCATION_DAMAGE_MAX))
	_suffocation_damage_timer = _next_suffocation_damage_interval()


func _next_suffocation_damage_interval() -> float:
	return randf_range(SUFFOCATION_DAMAGE_INTERVAL_MIN, SUFFOCATION_DAMAGE_INTERVAL_MAX)


func _update_pressure_damage(delta: float) -> void:
	if current_pressure > VITAL_MIN_VALUE:
		_pressure_damage_timer = 0.0
		return
	if _pressure_damage_timer <= 0.0:
		_pressure_damage_timer = _next_pressure_damage_interval()
	_pressure_damage_timer -= delta
	if _pressure_damage_timer > 0.0:
		return
	change_health(-randf_range(PRESSURE_DAMAGE_MIN, PRESSURE_DAMAGE_MAX))
	_pressure_damage_timer = _next_pressure_damage_interval()


func _next_pressure_damage_interval() -> float:
	return randf_range(PRESSURE_DAMAGE_INTERVAL_MIN, PRESSURE_DAMAGE_INTERVAL_MAX)


func apply_oxygen_exchange_from_ship(breath_amount: float, granted_amount: float) -> void:
	var uncovered_breath := maxf(0.0, breath_amount - granted_amount)
	if uncovered_breath > 0.0:
		change_oxygen(-uncovered_breath)
		return
	var refill_amount := maxf(0.0, granted_amount - breath_amount)
	if refill_amount > 0.0:
		change_oxygen(refill_amount)


func _update_player_oxygen(delta: float) -> void:
	var spent := PLAYER_OXYGEN_CONSUMPTION_PER_SECOND * delta
	if spent <= 0.0:
		return
	if _can_refill_oxygen_from_ship():
		_ship_oxygen_breath_pending += spent
		var missing_after_pending := maxf(0.0, max_oxygen - current_oxygen - _ship_oxygen_refill_pending)
		_ship_oxygen_refill_pending += minf(missing_after_pending, PLAYER_OXYGEN_RESTORE_PER_SECOND * delta)
		_ship_oxygen_refill_timer += delta
		if _ship_oxygen_refill_timer >= SHIP_OXYGEN_REFILL_REQUEST_INTERVAL:
			NetworkManager.request_ship_oxygen_refill(self, _ship_oxygen_breath_pending, _ship_oxygen_refill_pending)
			_ship_oxygen_breath_pending = 0.0
			_ship_oxygen_refill_pending = 0.0
			_ship_oxygen_refill_timer = 0.0
	else:
		change_oxygen(-spent)
		_ship_oxygen_breath_pending = 0.0
		_ship_oxygen_refill_pending = 0.0
		_ship_oxygen_refill_timer = 0.0


func _update_player_pressure(delta: float) -> void:
	if _can_refill_pressure_from_ship():
		if current_pressure < max_pressure:
			change_pressure(PLAYER_PRESSURE_RESTORE_PER_SECOND * delta)
		return
	change_pressure(-PLAYER_PRESSURE_LOSS_PER_SECOND * delta)


func _can_refill_oxygen_from_ship() -> bool:
	return not eva_mode or eva_shuttle_tether_attached


func _can_refill_pressure_from_ship() -> bool:
	return not eva_mode or eva_shuttle_tether_attached


func _emit_vitals_changed() -> void:
	vitals_changed.emit(get_vitals_snapshot())


func _try_interact() -> void:
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var obj = ray.get_collider()
	while obj and not obj.has_method("interact"):
		obj = obj.get_parent()
	if obj == null:
		return
	if obj.has_method("build_interaction_command"):
		var command: Dictionary = obj.build_interaction_command()
		if command.is_empty():
			return
		var ctype: String = str(command.get("type", ""))
		if ctype != "pickup_world_item":
			SoundManager.play_interior_at(self, "interact_use", -2.0)
		if NetworkManager.is_session_active() and not multiplayer.is_server():
			NetworkManager.request_command(self, command)
		else:
			var ok: bool = NetworkManager.request_command(self, command)
			if ctype == "pickup_world_item" and ok:
				SoundManager.play_interior_at(self, "item_pickup", -1.0)
	else:
		SoundManager.play_interior_at(self, "interact_use", -2.0)
		# Fallback for objects without the command pattern.
		obj.interact(self)


func interact(_actor: Node3D) -> void:
	if not is_dead:
		return


func build_interaction_command() -> Dictionary:
	if not is_dead:
		return {}
	return {
		"type": REVIVE_COMMAND_TYPE,
		"target_path": get_path()
	}


func server_validate_interaction(_actor: Node3D) -> bool:
	if not is_dead:
		return false
	var target_peer_id := _peer_id_from_player_name()
	return target_peer_id > 0


func server_apply_interaction(_actor: Node3D, command: Dictionary) -> bool:
	if str(command.get("type", "")) != REVIVE_COMMAND_TYPE:
		return false
	if not is_dead:
		return false
	var target_peer_id := _peer_id_from_player_name()
	var initiator_peer_id := int(command.get("initiator_peer_id", 0))
	if target_peer_id <= 0 or initiator_peer_id == target_peer_id:
		return false
	is_dead = false
	NetworkManager.revive_player_peer(target_peer_id, String(get_path()))
	return true


func show_hint() -> void:
	if not is_dead:
		return
	var label := get_node_or_null("Head/HeadMesh/Label3D") as Label3D
	if label == null:
		return
	label.text = "E - воскресить"
	label.modulate = Color(1, 1, 1, 1)
	label.outline_modulate = Color(0, 0, 0, 1)


func hide_hint() -> void:
	var label := get_node_or_null("Head/HeadMesh/Label3D") as Label3D
	if label == null or label.text != "E - воскресить":
		return
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)


func _process_dead_look_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if eva_mode:
			rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
			var y_delta: float = event.relative.y if invert_mouse_y else -event.relative.y
			rotate_object_local(Vector3.RIGHT, y_delta * mouse_sensitivity)
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			var y_delta2: float = event.relative.y if invert_mouse_y else -event.relative.y
			head.rotate_x(y_delta2 * mouse_sensitivity)
			head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	modal_ui_block = false
	_close_player_ui_for_death()
	_hide_hover_hint()
	_show_death_overlay(_is_single_player_match())


func apply_revive_from_server() -> void:
	_revive()


func _revive() -> void:
	if not is_dead and (_death_overlay == null or not is_instance_valid(_death_overlay)):
		return
	is_dead = false
	modal_ui_block = false
	inventory_open = false
	menu_open = false
	if current_health <= VITAL_MIN_VALUE:
		current_health = max_health
	_hide_hover_hint()
	if _death_overlay != null and is_instance_valid(_death_overlay):
		_death_overlay.queue_free()
	_death_overlay = null
	var hotbar := get_node_or_null("UILayer/HotbarUI") as CanvasItem
	if hotbar:
		hotbar.visible = true
	if is_multiplayer_authority():
		var body_mesh := get_node_or_null("BodyMesh") as Node3D
		if body_mesh:
			body_mesh.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _peer_id_from_player_name() -> int:
	return name.trim_prefix("Player_").to_int()


func _close_player_ui_for_death() -> void:
	inventory_open = false
	menu_open = false
	var settings_menu := get_node_or_null("MenuLayer/SettingsMenu")
	if settings_menu and settings_menu.has_method("hide_menu"):
		settings_menu.hide_menu()
	var hotbar := get_node_or_null("UILayer/HotbarUI") as CanvasItem
	if hotbar:
		hotbar.visible = false


func _is_single_player_match() -> bool:
	if not NetworkManager.is_session_active():
		return true
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.get_peers().is_empty()


func _show_death_overlay(can_exit_to_menu: bool) -> void:
	var ui_layer := get_node_or_null("UILayer") as CanvasLayer
	if ui_layer == null:
		return
	if _death_overlay != null and is_instance_valid(_death_overlay):
		_death_overlay.queue_free()

	_death_overlay = Control.new()
	_death_overlay.name = "DeathOverlay"
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if can_exit_to_menu else Control.MOUSE_FILTER_IGNORE

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade_alpha := 0.78 if can_exit_to_menu else 0.42
	shade.color = Color(0.02, 0.0, 0.0, shade_alpha)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.name = "DeathPanel"
	var panel_height := 180.0 if can_exit_to_menu else 96.0
	panel.custom_minimum_size = Vector2(420.0, panel_height)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -210.0
	panel.offset_right = 210.0
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	_death_overlay.add_child(panel)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)

	var title := Label.new()
	title.text = "Ты умер"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36 if can_exit_to_menu else 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.28, 0.24))
	content.add_child(title)

	if can_exit_to_menu:
		var hint := Label.new()
		hint.text = "Тело осталось в мире без управления"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86))
		content.add_child(hint)

		var button := Button.new()
		button.text = "В главное меню"
		button.custom_minimum_size = Vector2(220.0, 42.0)
		button.pressed.connect(_on_death_main_menu_pressed)
		content.add_child(button)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	ui_layer.add_child(_death_overlay)


func _on_death_main_menu_pressed() -> void:
	if NetworkManager.is_session_active():
		NetworkManager.leave()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func toggle_inventory() -> void:
	inventory_open = !inventory_open
	if inventory_open:
		open_inventory()
	else:
		close_inventory()


func open_inventory() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_inventory() -> void:
	inventory_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func toggle_menu() -> void:
	menu_open = !menu_open
	if menu_open:
		open_menu()
	else:
		close_menu()


func open_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var ui := get_node_or_null("MenuLayer/SettingsMenu")
	if ui:
		ui.show_menu()


func close_menu() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var ui := get_node_or_null("MenuLayer/SettingsMenu")
	if ui:
		ui.hide_menu()
	_apply_control_settings()


func _apply_control_settings() -> void:
	if SettingsManager == null:
		return
	mouse_sensitivity = SettingsManager.get_mouse_sensitivity()
	invert_mouse_y    = SettingsManager.is_mouse_inverted_y()


func _setup_ping_display() -> void:
	var hud_layer := get_node_or_null("UILayer") as CanvasLayer
	if hud_layer == null:
		return
	_ping_row = HBoxContainer.new()
	_ping_row.name = "PingRow"
	_ping_row.alignment = BoxContainer.ALIGNMENT_END
	_ping_row.anchor_left = 1.0
	_ping_row.anchor_right = 1.0
	_ping_row.anchor_top = 0.0
	_ping_row.anchor_bottom = 0.0
	_ping_row.offset_left = -150.0
	_ping_row.offset_right = -10.0
	_ping_row.offset_top = 8.0
	_ping_row.offset_bottom = 36.0
	_ping_row.add_theme_constant_override("separation", 8)
	_ping_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_ping_label = Label.new()
	_ping_label.name = "PingLabel"
	_ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ping_label.add_theme_font_size_override("font_size", 13)
	_ping_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_ping_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_ping_label.add_theme_constant_override("shadow_offset_x", 1)
	_ping_label.add_theme_constant_override("shadow_offset_y", 1)
	_ping_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_ping_tx_dot = Panel.new()
	_ping_tx_dot.name = "VoiceTxDot"
	_ping_tx_dot.custom_minimum_size = Vector2(10, 10)
	_ping_tx_style = StyleBoxFlat.new()
	_ping_tx_style.bg_color = Color(0.22, 0.22, 0.26)
	_ping_tx_style.set_corner_radius_all(5)
	_ping_tx_dot.add_theme_stylebox_override("panel", _ping_tx_style)
	_ping_tx_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_ping_row.add_child(_ping_label)
	_ping_row.add_child(_ping_tx_dot)
	_ping_radio_label = Label.new()
	_ping_radio_label.name = "RadioTxLabel"
	_ping_radio_label.text = ""
	_ping_radio_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ping_radio_label.add_theme_font_size_override("font_size", 12)
	_ping_radio_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.18))
	_ping_radio_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_ping_radio_label.add_theme_constant_override("shadow_offset_x", 1)
	_ping_radio_label.add_theme_constant_override("shadow_offset_y", 1)
	_ping_radio_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ping_row.add_child(_ping_radio_label)
	hud_layer.add_child(_ping_row)
	_update_ping()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_update_ping)
	add_child(timer)


func _update_ping() -> void:
	if _ping_row == null or not is_instance_valid(_ping_row):
		return
	var show_ping: bool = bool(SettingsManager.data.get("show_ping", true))
	if not show_ping:
		_ping_row.visible = false
		return
	_ping_row.visible = true
	if not MultiplayerRuntime.has_active_session_for(self):
		_ping_label.text = ""
		return
	if multiplayer.is_server():
		_ping_label.text = "HOST"
		return
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return
	var server_conn := enet_peer.get_peer(1)
	if server_conn == null:
		return
	# ENet PEER_ROUND_TRIP_TIME — не ICMP: сглаженный RTT по служебным пакетам. Растёт от очереди reliable,
	# загрузки главного потока и задержек рендера (GPU ~100% → кадры длиннее → обработка сети позже).
	var rtt: int = roundi(server_conn.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	var color: Color
	if rtt < 60:
		color = Color(0.4, 1.0, 0.4)
	elif rtt < 120:
		color = Color(1.0, 1.0, 0.3)
	else:
		color = Color(1.0, 0.3, 0.3)
	_ping_label.add_theme_color_override("font_color", color)
	_ping_label.text = "%d ms" % rtt


func _update_voice_tx_dot() -> void:
	if _ping_tx_style == null or _ping_tx_dot == null or not is_instance_valid(_ping_tx_dot):
		return
	if _ping_row != null and is_instance_valid(_ping_row) and not _ping_row.visible:
		return
	var vm := get_node_or_null("/root/VoiceManager")
	var active: bool = false
	var radio_tx: bool = false
	if vm != null:
		if vm.has_method("is_local_voice_transmitting"):
			active = vm.is_local_voice_transmitting()
		if vm.has_method("is_local_radio_transmitting"):
			radio_tx = vm.is_local_radio_transmitting()
	if radio_tx:
		_ping_tx_style.bg_color = Color(1.0, 0.48, 0.08)
		if _ping_radio_label != null and is_instance_valid(_ping_radio_label):
			_ping_radio_label.text = "РАЦИЯ TX"
	elif active:
		_ping_tx_style.bg_color = Color(0.35, 0.92, 0.45)
		if _ping_radio_label != null and is_instance_valid(_ping_radio_label):
			_ping_radio_label.text = ""
	else:
		_ping_tx_style.bg_color = Color(0.22, 0.22, 0.26)
		if _ping_radio_label != null and is_instance_valid(_ping_radio_label):
			_ping_radio_label.text = ""


## Сброс скорости и «верха» после телепорта шлюзом (NetworkManager).
func align_after_airlock_teleport(to_eva: bool) -> void:
	if not to_eva:
		shuttle_tether_detach()
	velocity  = Vector3.ZERO
	rotation  = Vector3.ZERO
	if head:
		head.rotation = Vector3.ZERO
	if to_eva:
		up_direction = global_transform.basis.y
	else:
		up_direction = Vector3.UP


func toggle_shuttle_tether_at_module(module: Node) -> void:
	if module == null or not is_instance_valid(module):
		return
	var path_s := str(module.get_path())
	if eva_shuttle_tether_attached and eva_shuttle_tether_module_path == path_s:
		shuttle_tether_detach()
	else:
		shuttle_tether_attach(module)


func shuttle_tether_detach() -> void:
	var was_attached: bool = eva_shuttle_tether_attached
	SoundManager.set_tether_stress_loop(self, 0.0)
	_tether_reel_tick_cd = 0.0
	_tether_limit_ping_cd = 0.0
	eva_shuttle_tether_attached = false
	eva_shuttle_tether_module_path = ""
	_tether_anchor = null
	_rope_sim = null
	_tether_rope_publish_phase = 0
	_puppet_tether_pts.clear()
	if _tether_mesh_inst != null and is_instance_valid(_tether_mesh_inst):
		_tether_mesh_inst.visible = false
	if is_multiplayer_authority():
		set_collision_mask_value(TETHER_PLAYER_COLLISION_LAYER, false)
		_free_tether_rope_collision_holder()
	if was_attached and is_multiplayer_authority() and NetworkManager.is_session_active():
		NetworkManager.publish_shuttle_tether_rope_polyline(get_multiplayer_authority(), PackedVector3Array())


func shuttle_tether_attach(module: Node) -> void:
	if not eva_mode:
		return
	shuttle_tether_detach()
	var anchor := module.get_node_or_null("CableAnchor") as Node3D
	if anchor == null:
		return
	if module.has_method("get_tether_parameters"):
		var d: Dictionary = module.get_tether_parameters()
		_tether_length_min = float(d.get("length_min", 5.0))
		_tether_length_max = float(d.get("length_max", d.get("max_length", 34.0)))
		if _tether_length_max < _tether_length_min:
			var t: float = _tether_length_min
			_tether_length_min = _tether_length_max
			_tether_length_max = t
		_tether_length_step = maxf(0.05, float(d.get("length_step", 0.75)))
		_tether_payed_length = clampf(_tether_length_min, _tether_length_min, _tether_length_max)
		_tether_slack_ratio = clampf(float(d.get("slack_ratio", 0.14)), 0.0, 0.45)
		_tether_spring = float(d.get("spring", 90.0))
		_tether_damping = float(d.get("damping", 7.0))
		_tether_cable_radius = float(d.get("cable_radius", 0.035))
		tether_rope_visual_radius = _tether_cable_radius
		var rseg: int = int(d.get("rope_segments", 18))
		var rcol: float = float(d.get("rope_collision_radius", 0.065))
		var rmask: int = int(d.get("rope_collision_mask", 1025))
		_rope_sim = EvaShuttleRopeSim.new()
		_rope_sim.configure(
			rseg,
			_tether_length_min,
			_tether_length_max,
			_tether_payed_length,
			_tether_slack_ratio,
			_tether_spring,
			_tether_damping,
			rcol,
			rmask,
			EVA_SHUTTLE_TETHER_ATTACH_LOCAL
		)
	else:
		tether_rope_visual_radius = 0.035
		_tether_cable_radius = 0.035
		_tether_length_min = 5.0
		_tether_length_max = 34.0
		_tether_length_step = 0.75
		_tether_payed_length = _tether_length_min
		_tether_slack_ratio = 0.14
		_tether_spring = 90.0
		_tether_damping = 7.0
		_rope_sim = EvaShuttleRopeSim.new()
		_rope_sim.configure(
			18,
			_tether_length_min,
			_tether_length_max,
			_tether_payed_length,
			_tether_slack_ratio,
			_tether_spring,
			_tether_damping,
			0.065,
			1025,
			EVA_SHUTTLE_TETHER_ATTACH_LOCAL
		)
	_rope_sim.reset_straight(anchor.global_position, _shuttle_tether_attach_point_global())
	print(
		"[Tether] подключение, выпущенная длина: ",
		snappedf(_tether_payed_length, 0.01),
		" м (диапазон ",
		snappedf(_tether_length_min, 0.1),
		" … ",
		snappedf(_tether_length_max, 0.1),
		"); X — длиннее, Z — короче"
	)
	_tether_payed_length_desired = _tether_payed_length
	_tether_reel_tick_cd = 0.0
	_tether_limit_ping_cd = 0.0
	_tether_anchor = anchor
	eva_shuttle_tether_attached = true
	eva_shuttle_tether_module_path = str(module.get_path())
	_ensure_shuttle_tether_visual()
	if is_multiplayer_authority():
		set_collision_mask_value(TETHER_PLAYER_COLLISION_LAYER, true)
		_ensure_tether_rope_collision_holder()


func _update_tether_payed_smooth_and_audio(delta: float) -> void:
	if _rope_sim == null:
		return
	if Input.is_action_pressed("tether_length_increase"):
		if Input.is_action_just_pressed("tether_length_increase"):
			_tether_payed_length_desired = minf(_tether_payed_length_desired + _tether_length_step, _tether_length_max)
		else:
			_tether_payed_length_desired = minf(_tether_payed_length_desired + TETHER_DESIRED_REEL_MPS * delta, _tether_length_max)
	if Input.is_action_pressed("tether_length_decrease"):
		if Input.is_action_just_pressed("tether_length_decrease"):
			_tether_payed_length_desired = maxf(_tether_payed_length_desired - _tether_length_step, _tether_length_min)
		else:
			_tether_payed_length_desired = maxf(_tether_payed_length_desired - TETHER_DESIRED_REEL_MPS * delta, _tether_length_min)
	_tether_payed_length_desired = clampf(_tether_payed_length_desired, _tether_length_min, _tether_length_max)

	var cur_p: float = _rope_sim.get_payed_length()
	var new_p: float = move_toward(cur_p, _tether_payed_length_desired, TETHER_PAYED_CATCHUP_MPS * delta)
	var delta_p: float = new_p - cur_p
	_tether_reel_tick_cd -= delta
	if absf(delta_p) > 0.004 and _tether_reel_tick_cd <= 0.0:
		_tether_reel_tick_cd = clampf(0.28 - absf(delta_p) * 3.2, 0.1, 0.34)
		var vol: float = lerpf(-13.0, -5.0, clampf(absf(delta_p) / maxf(delta * TETHER_PAYED_CATCHUP_MPS, 1e-4), 0.0, 1.0))
		SoundManager.play_tether_reel_tick(self, delta_p > 0.0, vol)
	if absf(new_p - cur_p) > 1e-6:
		_rope_sim.set_payed_length(new_p)
	_tether_payed_length = _rope_sim.get_payed_length()

	_tether_limit_ping_cd -= delta
	if Input.is_action_pressed("tether_length_increase") and _tether_payed_length_desired >= _tether_length_max - 0.02 and _tether_payed_length >= _tether_length_max - 0.06:
		if _tether_limit_ping_cd <= 0.0:
			_tether_limit_ping_cd = 0.34
			SoundManager.play_interior_at(self, "tether_limit_ping", -9.0)
	if Input.is_action_pressed("tether_length_decrease") and _tether_payed_length_desired <= _tether_length_min + 0.02 and _tether_payed_length <= _tether_length_min + 0.06:
		if _tether_limit_ping_cd <= 0.0:
			_tether_limit_ping_cd = 0.34
			SoundManager.play_interior_at(self, "tether_limit_ping", -11.0)


func apply_shuttle_tether_rope_visual(points_world: PackedVector3Array) -> void:
	if is_multiplayer_authority():
		return
	_puppet_tether_pts = points_world.duplicate()


func _ensure_shuttle_tether_visual() -> void:
	if _tether_mesh_inst != null and is_instance_valid(_tether_mesh_inst):
		_tether_mesh_inst.visible = true
		return
	var mi := MeshInstance3D.new()
	mi.name = "ShuttleTetherCable"
	_tether_rope_array_mesh = ArrayMesh.new()
	mi.mesh = _tether_rope_array_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.48)
	mat.metallic = 0.35
	mat.roughness = 0.55
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_tether_mesh_inst = mi


func _shuttle_tether_attach_point_global() -> Vector3:
	return global_position + global_transform.basis * EVA_SHUTTLE_TETHER_ATTACH_LOCAL


func _shuttle_tether_polyline_world_to_mesh_local(poly_world: PackedVector3Array) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var n: int = poly_world.size()
	out.resize(n)
	var inv: Transform3D = global_transform.affine_inverse()
	for i: int in range(n):
		out[i] = inv * poly_world[i]
	return out


func _update_shuttle_tether_visual() -> void:
	if not is_multiplayer_authority():
		return
	if _tether_mesh_inst == null or not is_instance_valid(_tether_mesh_inst):
		return
	if not eva_shuttle_tether_attached or _rope_sim == null or _tether_anchor == null or not is_instance_valid(_tether_anchor):
		_tether_mesh_inst.visible = false
		_disable_all_tether_rope_collision_segments()
		return
	var poly: PackedVector3Array = _rope_sim.get_polyline_with_attach(_shuttle_tether_attach_point_global())
	if poly.size() < 2:
		_tether_mesh_inst.visible = false
		_disable_all_tether_rope_collision_segments()
		return
	if _tether_rope_array_mesh == null:
		_tether_rope_array_mesh = _tether_mesh_inst.mesh as ArrayMesh
		if _tether_rope_array_mesh == null:
			_tether_rope_array_mesh = ArrayMesh.new()
			_tether_mesh_inst.mesh = _tether_rope_array_mesh
	var poly_local: PackedVector3Array = _shuttle_tether_polyline_world_to_mesh_local(poly)
	EvaShuttleRopeMesh.rebuild_tube_mesh(_tether_rope_array_mesh, poly_local, _tether_cable_radius, 6)
	_tether_mesh_inst.visible = true
	_update_tether_rope_collision_segments(poly)

	if NetworkManager.is_session_active():
		_tether_rope_publish_phase += 1
		if _tether_rope_publish_phase % 2 == 0:
			NetworkManager.publish_shuttle_tether_rope_polyline(get_multiplayer_authority(), poly)


func _update_puppet_shuttle_tether_rope_visual() -> void:
	if not eva_shuttle_tether_attached or _puppet_tether_pts.size() < 2:
		if _tether_mesh_inst != null and is_instance_valid(_tether_mesh_inst):
			_tether_mesh_inst.visible = false
		return
	_ensure_shuttle_tether_visual()
	if _tether_rope_array_mesh == null:
		_tether_rope_array_mesh = _tether_mesh_inst.mesh as ArrayMesh
		if _tether_rope_array_mesh == null:
			_tether_rope_array_mesh = ArrayMesh.new()
			_tether_mesh_inst.mesh = _tether_rope_array_mesh
	var poly_local: PackedVector3Array = _shuttle_tether_polyline_world_to_mesh_local(_puppet_tether_pts)
	EvaShuttleRopeMesh.rebuild_tube_mesh(_tether_rope_array_mesh, poly_local, tether_rope_visual_radius, 6)
	_tether_mesh_inst.visible = true


## Расстояние отрезка троса до оси капсулы мало — не выключаем слои (шаттл/мир),
## а только `add_collision_exception_with`, иначе трос «пропадает» для всех.
func _tether_rope_segment_too_close_to_player_capsule(
	ra: Vector3,
	rb: Vector3,
	rope_r: float,
	cap_ax_a: Vector3,
	cap_ax_b: Vector3,
	cap_rad: float
) -> bool:
	var clearance: float = cap_rad + rope_r + 0.1
	var axis: Vector3 = cap_ax_b - cap_ax_a
	var Lax: float = axis.length_squared()
	if Lax < 1e-10:
		return ra.distance_squared_to(cap_ax_a) < clearance * clearance
	var invL: float = 1.0 / Lax
	for si: int in range(9):
		var p: Vector3 = ra.lerp(rb, float(si) / 8.0)
		var u: float = clampf((p - cap_ax_a).dot(axis) * invL, 0.0, 1.0)
		var q: Vector3 = cap_ax_a + axis * u
		if p.distance_to(q) < clearance:
			return true
	return false


func _tether_seg_basis_y(y_unit: Vector3) -> Basis:
	var y: Vector3 = y_unit
	var refx: Vector3 = Vector3.RIGHT
	if absf(y.dot(refx)) > 0.9:
		refx = Vector3.FORWARD
	var x: Vector3 = refx.cross(y).normalized()
	var z: Vector3 = y.cross(x)
	return Basis(x, y, z)


func _ensure_tether_rope_collision_holder() -> void:
	if _tether_collision_holder != null and is_instance_valid(_tether_collision_holder):
		return
	var par: Node = get_parent()
	if par == null:
		return
	var h := Node3D.new()
	h.name = "ShuttleTetherColliders_%d" % get_multiplayer_authority()
	par.add_child(h)
	_tether_collision_holder = h
	_tether_collision_seg_bodies.clear()
	for i: int in range(TETHER_COLLISION_SEG_POOL):
		var sb := StaticBody3D.new()
		sb.name = "TetherSeg_%d" % i
		sb.collision_layer = 0
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(0.045, _tether_cable_radius * 2.0)
		cyl.height = 0.12
		cs.shape = cyl
		sb.add_child(cs)
		h.add_child(sb)
		_tether_collision_seg_bodies.append(sb)
	_tether_seg_player_exception.clear()
	_tether_seg_player_exception.resize(TETHER_COLLISION_SEG_POOL)
	for j: int in range(TETHER_COLLISION_SEG_POOL):
		_tether_seg_player_exception[j] = false


func _free_tether_rope_collision_holder() -> void:
	_disable_all_tether_rope_collision_segments()
	if _tether_collision_holder != null and is_instance_valid(_tether_collision_holder):
		_tether_collision_holder.queue_free()
	_tether_collision_holder = null
	_tether_collision_seg_bodies.clear()
	_tether_seg_player_exception.clear()


func _tether_rope_static_exclude_for_sim() -> Array:
	if _tether_collision_seg_bodies.is_empty():
		return []
	var out: Array = []
	for sb: StaticBody3D in _tether_collision_seg_bodies:
		if sb != null and is_instance_valid(sb):
			var rid: RID = sb.get_rid()
			if rid.is_valid():
				out.append(rid)
	return out


func _tether_rope_collision_set_player_exception_for_seg(i: int, sb: StaticBody3D, want_exc: bool) -> void:
	if i < 0 or i >= _tether_seg_player_exception.size():
		return
	var had: bool = _tether_seg_player_exception[i]
	if want_exc == had:
		return
	if want_exc:
		add_collision_exception_with(sb)
	else:
		remove_collision_exception_with(sb)
	_tether_seg_player_exception[i] = want_exc


func _disable_all_tether_rope_collision_segments() -> void:
	for i: int in range(_tether_collision_seg_bodies.size()):
		var sb: StaticBody3D = _tether_collision_seg_bodies[i]
		if sb != null and is_instance_valid(sb):
			_tether_rope_collision_set_player_exception_for_seg(i, sb, false)
			sb.collision_layer = 0


func _update_tether_rope_collision_segments(poly_world: PackedVector3Array) -> void:
	if _tether_collision_holder == null or not is_instance_valid(_tether_collision_holder):
		return
	var nseg: int = poly_world.size() - 1
	var last_edge_i: int = nseg - 1
	var pool: int = _tether_collision_seg_bodies.size()
	var r: float = maxf(0.045, _tether_cable_radius * 2.0)
	var cap_ax_a: Vector3
	var cap_ax_b: Vector3
	var cap_rad: float = 0.4
	var cs_body: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs_body != null and cs_body.shape is CapsuleShape3D:
		var capsh: CapsuleShape3D = cs_body.shape as CapsuleShape3D
		cap_rad = capsh.radius
		var half_ax: float = capsh.height * 0.5
		var txf: Transform3D = cs_body.global_transform
		cap_ax_a = txf * Vector3(0, -half_ax, 0)
		cap_ax_b = txf * Vector3(0, half_ax, 0)
	else:
		var upv: Vector3 = global_transform.basis.y.normalized()
		cap_ax_a = global_position + upv * -0.9
		cap_ax_b = global_position + upv * 0.9
	for i: int in range(pool):
		var sb: StaticBody3D = _tether_collision_seg_bodies[i]
		if sb == null or not is_instance_valid(sb):
			continue
		if i >= nseg or nseg < 1:
			_tether_rope_collision_set_player_exception_for_seg(i, sb, false)
			sb.collision_layer = 0
			continue
		var a: Vector3 = poly_world[i]
		var b: Vector3 = poly_world[i + 1]
		var seg: Vector3 = b - a
		var L: float = seg.length()
		if L < 0.025:
			_tether_rope_collision_set_player_exception_for_seg(i, sb, false)
			sb.collision_layer = 0
			continue
		var yax: Vector3 = seg / L
		var mid: Vector3 = (a + b) * 0.5
		sb.global_transform = Transform3D(_tether_seg_basis_y(yax), mid)
		var cs: Node = sb.get_child(0)
		if cs is CollisionShape3D:
			var sh: Shape3D = (cs as CollisionShape3D).shape
			if sh is CylinderShape3D:
				var cyl: CylinderShape3D = sh as CylinderShape3D
				cyl.height = L
				cyl.radius = r
		sb.collision_layer = TETHER_ROPE_COLLISION_LAYERS
		var want_player_exc: bool = (i == last_edge_i) or _tether_rope_segment_too_close_to_player_capsule(
			a, b, r, cap_ax_a, cap_ax_b, cap_rad
		)
		_tether_rope_collision_set_player_exception_for_seg(i, sb, want_player_exc)
