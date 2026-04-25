extends Control

const GAME_SCENE := "res://scenes/main.tscn"

@onready var ip_input:    LineEdit = $Center/Panel/VBox/IPInput
@onready var port_label:  Label    = $Center/Panel/VBox/PortLabel
@onready var btn_host:    Button   = $Center/Panel/VBox/BtnHost
@onready var btn_join:    Button   = $Center/Panel/VBox/BtnJoin
@onready var btn_solo:    Button   = $Center/Panel/VBox/BtnSolo
@onready var status_label: Label   = $Center/Panel/VBox/StatusLabel

var _network_manager: Node = null
var _connect_timer: SceneTreeTimer = null

func _ready() -> void:
	# Always release the mouse when the lobby opens — it may have been captured
	# during gameplay (MOUSE_MODE_CAPTURED prevents clicking/typing in UI).
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_network_manager = get_node_or_null("/root/NetworkManager")

	var port: int = int(SettingsManager.data.get("port", 7777))
	port_label.text = _t("Порт: ", "Port: ") + str(port)

	btn_host.pressed.connect(_on_host_pressed)
	btn_join.pressed.connect(_on_join_pressed)
	btn_solo.pressed.connect(_on_solo_pressed)

	if _network_manager:
		_network_manager.session_started.connect(_on_session_started)
		_network_manager.connection_failed.connect(_on_connection_failed)

	_apply_style()

func _on_host_pressed() -> void:
	if _network_manager == null:
		_set_status(_t("NetworkManager недоступен", "NetworkManager unavailable"), true)
		return
	var port: int = int(SettingsManager.data.get("port", 7777))
	var err: Error = _network_manager.host(port)
	if err != OK:
		_set_status(_t("Ошибка хоста: ", "Host error: ") + str(err), true)
		return
	# Scene transition is handled by _on_session_started (connected to NetworkManager.session_started).
	# host() emits session_started synchronously, so do NOT call change_scene_to_file here.

func _on_join_pressed() -> void:
	if _network_manager == null:
		_set_status(_t("NetworkManager недоступен", "NetworkManager unavailable"), true)
		return
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port: int = int(SettingsManager.data.get("port", 7777))
	var err: Error = _network_manager.join(ip, port)
	if err != OK:
		_set_status(_t("Ошибка подключения: ", "Connection error: ") + str(err), true)
		return
	_set_buttons_enabled(false)
	_set_status(_t("Подключение к ", "Connecting to ") + ip + "...", false)

	# Auto-cancel if no response within 10 seconds.
	_connect_timer = get_tree().create_timer(10.0)
	_connect_timer.timeout.connect(_on_connect_timeout)

func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_session_started(_is_host: bool) -> void:
	_connect_timer = null
	_set_status(_t("Подключено. Загрузка...", "Connected. Loading..."), false)
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_connection_failed() -> void:
	_connect_timer = null
	_set_status(_t("Не удалось подключиться", "Connection failed"), true)
	_set_buttons_enabled(true)


func _on_connect_timeout() -> void:
	_connect_timer = null
	if _network_manager:
		_network_manager.leave()
	_set_status(_t(
		"Нет ответа от сервера (проверьте IP, порт и брандмауэр)",
		"No response from server (check IP, port and firewall)"
	), true)
	_set_buttons_enabled(true)

func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.modulate = Color(1, 0.4, 0.4) if is_error else Color(0.7, 1, 0.7)

func _set_buttons_enabled(enabled: bool) -> void:
	btn_host.disabled = not enabled
	btn_join.disabled = not enabled
	btn_solo.disabled = not enabled


func _t(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en

func _apply_style() -> void:
	var ui_theme := Theme.new()

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.07, 0.08, 0.1, 0.96)
	bg_style.border_color = Color(0.15, 0.19, 0.24, 1)
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(14)
	bg_style.set_content_margin_all(28)
	ui_theme.set_stylebox("panel", "PanelContainer", bg_style)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.12, 0.15, 0.2, 1)
	btn_normal.set_corner_radius_all(8)
	btn_normal.content_margin_top = 10
	btn_normal.content_margin_bottom = 10
	btn_normal.content_margin_left = 14
	btn_normal.content_margin_right = 14
	ui_theme.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.17, 0.21, 0.28, 1)
	ui_theme.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.16, 0.35, 0.28, 1)
	ui_theme.set_stylebox("pressed", "Button", btn_pressed)
	ui_theme.set_stylebox("focus", "Button", btn_hover)

	ui_theme.set_color("font_color", "Button", Color(0.92, 0.95, 1))
	ui_theme.set_font_size("font_size", "Button", 15)
	ui_theme.set_font_size("font_size", "Label", 14)
	ui_theme.set_constant("separation", "VBoxContainer", 12)

	self.theme = ui_theme
