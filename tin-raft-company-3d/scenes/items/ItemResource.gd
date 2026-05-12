extends Resource
class_name ItemResource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var model: PackedScene
@export var max_stack: int = 1
@export var mass: float = 1.0          # для ограничения веса
@export var is_usable: bool = false    # можно ли использовать из хотбара
## В активном слоте хотбара: ЛКМ (`radio_ptt`) — передача голоса на большую дистанцию (см. VoiceManager).
@export var is_walkie_talkie: bool = false
