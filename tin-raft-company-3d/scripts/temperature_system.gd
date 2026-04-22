extends Node

# Сигналы
signal death_temperature

# Настройки
@export var normal_temperature: float = 36.0
@export var current_temperature: float = 36.0

@export var changing_rate: float = 1.0
@export var changing_interval: float = 1.0

# Состояние
var is_changing: bool = false
var timer: Timer

func _ready():
	_setup_timer()
	current_temperature = normal_temperature

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
	
	is_changing = true
	timer.start()
	print("Temperature changing started (rate: ", changing_rate, ", interval: ", changing_interval, ")")

func stop_consumption():
	is_changing = false
	timer.stop()
	print("Temperature changing stopped")

func _on_timer_timeout():
	if not is_changing:
		return
	
	# Уменьшаем кислород
	current_temperature = current_temperature + changing_rate
	
	print("Temperature: ", current_temperature)
	
	# Проверяем на смерть
	if current_temperature <= 25 or current_temperature >= 45:
		_on_death_temperature()

func _on_death_temperature():
	is_changing = false
	timer.stop()
	
	death_temperature.emit()
	
	print("Temperature depleted!")

# Публичные методы
func change_temperature(amount: float):
	current_temperature = current_temperature + amount

func reset_temperature():
	current_temperature = normal_temperature
