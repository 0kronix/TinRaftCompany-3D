extends CharacterBody3D

const JUMP_VELOCITY = 4.5
const DEFAULT_MOUSE_SENSITIVITY := 0.003

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
	config.add_property(NodePath("Head:rotation"))
	sync.replication_config = config
	sync.replication_interval = 1.0 / 20.0

# --- ДВИЖЕНИЕ ---
var SPEED        = 4.5
var acceleration = 12.0
var friction     = 10.0

# --- ПРЫЖОК И ФИЗИКА ---
var jump_force      = 4.8
var gravity         = 9.8 * 1.5
var fall_multiplier = 1.6

# --- ВОЗДУХ ---
var air_control = 0.3

var current_hovered = null
var inventory_open  := false
var menu_open       := false
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var invert_mouse_y: bool     = false
var _ping_label: Label = null


func _ready() -> void:
	if is_multiplayer_authority():
		_setup_local_player()
	else:
		_setup_puppet()


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
	_setup_ping_display()


## Called for all other players — they are puppets driven by MultiplayerSynchronizer.
func _setup_puppet() -> void:
	remove_from_group("player")
	set_physics_process(false)
	set_process_unhandled_input(false)
	# Show the body so other players are visible.
	var body_mesh := get_node_or_null("BodyMesh")
	if body_mesh:
		body_mesh.visible = true
	# Disable camera so it doesn't fight the local player's camera.
	if camera:
		camera.current = false
	# Remove UI layers — puppets don't need HUD, inventory, menu, or shader overlay.
	for layer_name: String in ["HotbarLayer", "MenuLayer", "ShaiderLayer"]:
		var node := get_node_or_null(layer_name)
		if node:
			node.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
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

	# --- ВРАЩЕНИЕ КАМЕРЫ ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var y_delta: float = event.relative.y if invert_mouse_y else -event.relative.y
		head.rotate_x(y_delta * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)

	# --- ВЗАИМОДЕЙСТВИЕ ---
	if event.is_action_pressed("interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if menu_open:
		return

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back")  - Input.get_action_strength("move_forward")
	).normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# --- ПРЫЖОК ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	# --- ГРАВИТАЦИЯ ---
	if not is_on_floor():
		velocity.y -= gravity * (fall_multiplier if velocity.y < 0 else 1.0) * delta

	# --- ДВИЖЕНИЕ С ИНЕРЦИЕЙ ---
	var ctrl: float = 1.0 if is_on_floor() else air_control
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * SPEED, acceleration * ctrl * delta)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, acceleration * ctrl * delta)
		# Гасим скорость при резком развороте.
		if sign(direction.x) != sign(velocity.x):
			velocity.x *= 0.8
		if sign(direction.z) != sign(velocity.z):
			velocity.z *= 0.8
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)

	move_and_slide()
	_update_hover()


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


func _try_interact() -> void:
	if not ray.is_colliding():
		return
	var obj = ray.get_collider()
	while obj and not obj.has_method("interact"):
		obj = obj.get_parent()
	if obj == null:
		return
	if obj.has_method("build_interaction_command"):
		var command: Dictionary = obj.build_interaction_command()
		var nm := get_node_or_null("/root/NetworkManager")
		if nm:
			nm.request_command(self, command)
	else:
		# Fallback for objects without the command pattern.
		obj.interact(self)


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
	var hud_layer := get_node_or_null("HotbarLayer") as CanvasLayer
	if hud_layer == null:
		return
	_ping_label = Label.new()
	_ping_label.name = "PingLabel"
	_ping_label.anchor_left   = 1.0
	_ping_label.anchor_right  = 1.0
	_ping_label.anchor_top    = 0.0
	_ping_label.anchor_bottom = 0.0
	_ping_label.offset_left   = -110.0
	_ping_label.offset_right  = -10.0
	_ping_label.offset_top    = 10.0
	_ping_label.offset_bottom = 34.0
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping_label.add_theme_font_size_override("font_size", 13)
	_ping_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	_ping_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_ping_label.add_theme_constant_override("shadow_offset_x", 1)
	_ping_label.add_theme_constant_override("shadow_offset_y", 1)
	hud_layer.add_child(_ping_label)
	_update_ping()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_update_ping)
	add_child(timer)


func _update_ping() -> void:
	if _ping_label == null or not is_instance_valid(_ping_label):
		return
	var show_ping: bool = SettingsManager.data.get("show_ping", false)
	if not show_ping:
		_ping_label.visible = false
		return
	_ping_label.visible = true
	var mp_peer := multiplayer.multiplayer_peer
	if mp_peer == null or mp_peer is OfflineMultiplayerPeer:
		_ping_label.text = ""
		return
	if multiplayer.is_server():
		_ping_label.text = "HOST"
		return
	var enet_peer := mp_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return
	var server_conn := enet_peer.get_peer(1)
	if server_conn == null:
		return
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
