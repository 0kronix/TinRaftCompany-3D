extends Control
## Системный чат: join/leave (сигналы `NetworkManager.system_chat_*`). Панель всплывает на новое сообщение и гаснет через `message_visible_seconds`.

@export var message_visible_seconds: float = 4.0
@export var panel_fade_in_seconds: float = 0.14
@export var panel_fade_out_seconds: float = 0.32

@onready var _panel: Control = $ChatPanel
@onready var _log: RichTextLabel = $ChatPanel/RichTextLabel

var _hooks: bool = false
var _panel_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _log:
		_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel:
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_try_bind")


func _try_bind() -> void:
	if _hooks:
		return
	if not NetworkManager.is_session_active():
		if _panel:
			_panel.visible = false
		return
	_hooks = true
	if _panel:
		_panel.visible = true
		var c: Color = _panel.modulate
		_panel.modulate = Color(c.r, c.g, c.b, 0.0)
	NetworkManager.system_chat_join.connect(_on_system_join)
	NetworkManager.system_chat_leave.connect(_on_system_leave)


func _exit_tree() -> void:
	if _panel_tween and is_instance_valid(_panel_tween):
		_panel_tween.kill()
	_panel_tween = null
	if not _hooks:
		return
	if NetworkManager.system_chat_join.is_connected(_on_system_join):
		NetworkManager.system_chat_join.disconnect(_on_system_join)
	if NetworkManager.system_chat_leave.is_connected(_on_system_leave):
		NetworkManager.system_chat_leave.disconnect(_on_system_leave)
	_hooks = false


func _on_system_join(peer_id: int) -> void:
	_append_line(_t("Игрок %d присоединился." % peer_id, "Player %d joined." % peer_id))


func _on_system_leave(peer_id: int) -> void:
	_append_line(_t("Игрок %d вышел." % peer_id, "Player %d left." % peer_id))


func _append_line(line: String) -> void:
	if _log == null:
		return
	_log.append_text("[color=#9aa3b5]%s[/color]\n" % line)
	_bump_visibility()


func _bump_visibility() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if _panel_tween and is_instance_valid(_panel_tween):
		_panel_tween.kill()
	_panel.visible = true
	var c: Color = _panel.modulate
	_panel.modulate = Color(c.r, c.g, c.b, minf(c.a, 1.0))
	_panel_tween = create_tween()
	_panel_tween.tween_property(_panel, "modulate:a", 1.0, panel_fade_in_seconds)
	_panel_tween.tween_interval(message_visible_seconds)
	_panel_tween.tween_property(_panel, "modulate:a", 0.0, panel_fade_out_seconds)


func _t(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en
