extends Node

# Сигналы
signal oxygen_depleted

# Настройки
@export var max_oxygen: float = 100.0
@export var current_oxygen: float = 100.0
@export var depletion_rate: float = 5.0
@export var depletion_interval: float = 1.5

# Состояние
var is_consuming: bool = false
var is_dead: bool = false
var timer: Timer

func _ready():
	_setup_timer()
	
	current_oxygen = max_oxygen

func _setup_timer():
	timer = Timer.new()
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

func _input(event):
	if is_dead:
		return
	
	if event.is_action_pressed("oxygen_toggle"):
		toggle_oxygen_consumption()
		return

func toggle_oxygen_consumption():
	if is_dead:
		return
	
	is_consuming = !is_consuming
	
	if is_consuming:
		timer.start()
		print("Oxygen consumption started")
	else:
		timer.stop()
		print("Oxygen consumption stopped")

func _on_timer_timeout():
	if not is_consuming or is_dead:
		return
	
	# Уменьшаем кислород
	current_oxygen = max(0, current_oxygen - depletion_rate)
	
	print("Oxygen: ", current_oxygen, "/", max_oxygen)
	
	# Проверяем на смерть
	if current_oxygen <= 0 and not is_dead:
		_on_oxygen_depleted()

func _on_oxygen_depleted():
	is_dead = true
	is_consuming = false
	timer.stop()
	
	oxygen_depleted.emit()
	
	print("WASTED - Oxygen depleted!")
