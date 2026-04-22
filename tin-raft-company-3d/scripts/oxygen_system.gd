extends Node

# Сигналы
signal oxygen_depleted

# Настройки
@export var max_oxygen: float = 100.0
@export var current_oxygen: float = 100.0

@export var changing_rate: float = 5.0
@export var changing_interval: float = 1.5

# Состояние
var is_consuming: bool = false
var timer: Timer

func _ready():
	_setup_timer()
	current_oxygen = max_oxygen

func _setup_timer():
	timer = Timer.new()
	timer.wait_time = changing_interval
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

func start_consumption(custom_rate: float = -1.0, custom_interval: float = -1.0):
	if custom_rate > 0:
		changing_rate = custom_rate
	if custom_interval > 0:
		changing_interval = custom_interval
		timer.wait_time = changing_interval
	
	is_consuming = true
	timer.start()
	print("Oxygen consumption started (rate: ", changing_rate, ", interval: ", changing_interval, ")")

func stop_consumption():
	is_consuming = false
	timer.stop()
	print("Oxygen consumption stopped")

func _on_timer_timeout():
	if not is_consuming:
		return
	
	# Уменьшаем кислород
	current_oxygen = min(max(0, current_oxygen + changing_rate), max_oxygen)
	
	print("Oxygen: ", current_oxygen, "/", max_oxygen)
	
	# Проверяем на смерть
	if current_oxygen <= 0:
		_on_oxygen_depleted()

func _on_oxygen_depleted():
	is_consuming = false
	timer.stop()
	
	oxygen_depleted.emit()
	
	print("Oxygen depleted!")

# Публичные методы
func change_oxygen(amount: float):
	current_oxygen = min(max_oxygen, current_oxygen + amount)

func reset_oxygen():
	current_oxygen = max_oxygen
