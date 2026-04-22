extends Node

# Сигналы
signal health_depleted

# Настройки
@export var max_health: float = 100.0
@export var current_health: float = 100.0

@export var changing_rate: float = 5.0
@export var changing_interval: float = 1.5

# Состояние
var is_changing: bool = false
var timer: Timer

func _ready():
	_setup_timer()
	current_health = max_health

func _setup_timer():
	timer = Timer.new()
	timer.wait_time = changing_interval
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

func start_changing(custom_rate: float = -1.0, custom_interval: float = -1.0):
	if custom_rate > 0:
		changing_rate = custom_rate
	if custom_interval > 0:
		changing_interval = custom_interval
		timer.wait_time = changing_interval
	
	is_changing = true
	timer.start()
	print("Health changing started (rate: ", changing_rate, ", interval: ", changing_interval, ")")

func stop_changing():
	is_changing = false
	timer.stop()
	print("Health changing stopped")

func _on_timer_timeout():
	if not is_changing:
		return
	
	# Уменьшаем кислород
	current_health = min(max(0, current_health + changing_rate), max_health)
	
	print("Health: ", current_health, "/", max_health)
	
	# Проверяем на смерть
	if current_health <= 0:
		_on_health_depleted()

func _on_health_depleted():
	is_changing = false
	timer.stop()
	
	health_depleted.emit()
	
	print("Health depleted!")

# Публичные методы
func change_health(amount: float):
	current_health = min(max_health, current_health + amount)

func reset_health():
	current_health = max_health
