extends CharacterBody3D

const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var ray = $Head/Camera3D/RayCast3D

# --- ДВИЖЕНИЕ (похоже на человека) ---
var SPEED = 4.5                 # м/с (обычная скорость ходьбы человека ~4–5)
var acceleration = 12.0         # разгон (не мгновенный, но отзывчивый)
var friction = 10.0             # торможение

# --- ПРЫЖОК И ФИЗИКА ---
var jump_force = 4.8            # даёт прыжок примерно на 1–1.2 метра
var gravity = 9.8 * 1.5        # ≈ 24.5 (усиленная гравитация для «игрового» ощущения)
var fall_multiplier = 1.6       # быстрее падаем, чем поднимаемся

# --- ВОЗДУХ ---
var air_control = 0.3           # слабый контроль → ощущение массы

var current_hovered = null
var inventory_open := false


func _ready():
	# Захватить мышь при старте
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event):
	# --- ИНВЕНТАРЬ ---
	if event.is_action_pressed("inventory"):
		toggle_inventory()
		return

	if event.is_action_pressed("ui_close") and inventory_open:
		close_inventory()
		return

	# ❗ если инвентарь открыт — блокируем всё ниже
	if inventory_open:
		return

	# --- ВРАЩЕНИЕ КАМЕРЫ ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)

	# --- ВЗАИМОДЕЙСТВИЕ ---
	if event.is_action_pressed("interact"):
		_try_interact()



func _physics_process(delta):
	# --- ВВОД (WASD / стрелки) ---
	var input_dir = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)

	input_dir = input_dir.normalized()
	# Нормализация чтобы по диагонали не было быстрее

	# --- ПРЕОБРАЗУЕМ В НАПРАВЛЕНИЕ В МИРЕ ---
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Это делает движение относительно поворота персонажа

	# --- ПРЫЖОК ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force
		# Прыжок только если стоим на земле

	# --- ГРАВИТАЦИЯ ---
	if not is_on_floor():  # Если в воздухе
		if velocity.y < 0:
			# Падаем → ускоряем падение
			velocity.y -= gravity * fall_multiplier * delta
		else:
			# Поднимаемся
			velocity.y -= gravity * delta

	# --- ДВИЖЕНИЕ С ИНЕРЦИЕЙ ---
	if direction != Vector3.ZERO:
		if is_on_floor():
			# На земле полный контроль
			velocity.x = move_toward(velocity.x, direction.x * SPEED, acceleration * delta)
			velocity.z = move_toward(velocity.z, direction.z * SPEED, acceleration * delta)
		else:
			# В воздухе хуже управляется
			velocity.x = move_toward(velocity.x, direction.x * SPEED, acceleration * air_control * delta)
			velocity.z = move_toward(velocity.z, direction.z * SPEED, acceleration * air_control * delta)
	else:
		# Нет ввода → торможение
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)

	# --- ПОТЕРЯ СКОРОСТИ ПРИ РАЗВОРОТЕ ---
	if direction != Vector3.ZERO:
		if sign(direction.x) != sign(velocity.x):
			velocity.x *= 0.8  # Гасим скорость по X при резком развороте
		if sign(direction.z) != sign(velocity.z):
			velocity.z *= 0.8  # Гасим скорость по Z
	
	# --- ПРИМЕНЯЕМ ДВИЖЕНИЕ ---
	move_and_slide()
	_update_hover()


func _update_hover():
	if ray.is_colliding():
		var obj = ray.get_collider()
		
		# Навели на новый объект
		if obj != current_hovered:
			# Скрыть у предыдущего
			if current_hovered and current_hovered.has_method("hide_hint"):
				current_hovered.hide_hint()
			
			# Показать у нового
			if obj.has_method("show_hint"):
				obj.show_hint()
				current_hovered = obj
			else:
				current_hovered = null
	else:
		# Рейкаст ни во что не упирается
		if current_hovered and current_hovered.has_method("hide_hint"):
			current_hovered.hide_hint()
		current_hovered = null


func _try_interact():
	if ray.is_colliding():
		var obj = ray.get_collider()
		
		while obj and not obj.has_method("interact"):
			obj = obj.get_parent()
		
		if obj:
			obj.interact(self)

func toggle_inventory():
	inventory_open = !inventory_open
	
	if inventory_open:
		open_inventory()
	else:
		close_inventory()


func open_inventory():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var ui = get_node_or_null("CanvasLayer/InventoryUI")
	if ui:
		ui.visible = true


func close_inventory():
	inventory_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var ui = get_node_or_null("CanvasLayer/InventoryUI")
	if ui:
		ui.visible = false
