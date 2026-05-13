extends Node
## Центральная точка для лупов и одноразовых SFX: пути к стримам в одном словаре, шины из настроек.
## Лупы — дочерние `AudioStreamPlayer3D` у узла (EVA: корень игрока + смещение по вводу; шаттл: корень).

const SOUND_PATHS: Dictionary = {
	"eva_jetpack": "res://audio/sfx/eva_jetpack_loop.ogg",
	"shuttle_engines": "res://audio/sfx/shuttle_engines_loop.ogg",
	"footstep_interior": "res://audio/sfx/footstep_interior.ogg",
	"jump_interior": "res://audio/sfx/jump_interior.ogg",
	"interact_use": "res://audio/sfx/interact_use.ogg",
	"item_pickup": "res://audio/sfx/item_pickup.ogg",
	"tether_reel_out": "res://audio/sfx/tether_reel_out.ogg",
	"tether_reel_in": "res://audio/sfx/tether_reel_in.ogg",
	"tether_stress": "res://audio/sfx/tether_stress_loop.ogg",
	"tether_limit_ping": "res://audio/sfx/tether_limit_ping.ogg",
}

const LOOP_BUS_EVA := "EVA_Jetpack"
const LOOP_BUS_SHUTTLE := "ShuttleEngines"
const INTERIOR_SFX_BUS := "SFX"

var _stream_cache: Dictionary = {} ## String -> AudioStream
var _oneshot_stream_cache: Dictionary = {} ## String -> AudioStream (без loop)
var _loops: Dictionary = {} ## StringName -> AudioStreamPlayer3D


func _get_stream(sound_id: String) -> AudioStream:
	if _stream_cache.has(sound_id):
		return _stream_cache[sound_id] as AudioStream
	var path: String = str(SOUND_PATHS.get(sound_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var st: Resource = load(path)
	if st is AudioStream:
		var audio: AudioStream = st as AudioStream
		_prepare_loop_stream(audio)
		_stream_cache[sound_id] = audio
		return audio
	return null


func _get_oneshot_stream(sound_id: String) -> AudioStream:
	if _oneshot_stream_cache.has(sound_id):
		return _oneshot_stream_cache[sound_id] as AudioStream
	var path: String = str(SOUND_PATHS.get(sound_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var st: Resource = load(path)
	if st is AudioStream:
		var audio: AudioStream = (st as AudioStream).duplicate() as AudioStream
		if audio is AudioStreamOggVorbis:
			(audio as AudioStreamOggVorbis).loop = false
		elif audio is AudioStreamWAV:
			(audio as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		_oneshot_stream_cache[sound_id] = audio
		return audio
	return null


## Одноразовый SFX в мире (ноги/корпус игрока). Удаляется после окончания.
func play_interior_at(parent: Node3D, sound_id: String, volume_db_offset: float = 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var base := _get_oneshot_stream(sound_id)
	if base == null:
		return
	var ap := AudioStreamPlayer3D.new()
	ap.name = "SfxOne_" + sound_id
	ap.stream = base.duplicate()
	ap.bus = INTERIOR_SFX_BUS
	ap.max_distance = 24.0
	ap.unit_size = 2.0
	ap.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	ap.emission_angle_enabled = false
	ap.position = Vector3(0, 0.08, 0)
	ap.volume_db = volume_db_offset
	parent.add_child(ap)
	ap.finished.connect(ap.queue_free)
	ap.play()


func _prepare_loop_stream(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _ensure_loop_player(slot: StringName, sound_id: String, parent: Node3D, bus_name: String) -> AudioStreamPlayer3D:
	if _loops.has(slot):
		var existing: AudioStreamPlayer3D = _loops[slot] as AudioStreamPlayer3D
		if is_instance_valid(existing) and existing.get_parent() == parent:
			return existing
		_loops.erase(slot)
	var stream := _get_stream(sound_id)
	if stream == null:
		return null
	var ap := AudioStreamPlayer3D.new()
	ap.name = "SfxLoop_" + str(sound_id)
	ap.stream = stream
	ap.bus = bus_name
	ap.max_distance = 140.0
	ap.unit_size = 18.0
	ap.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	# Конус только 0…90° (см. AudioStreamPlayer3D); для лупов EVA/шаттла — омни.
	ap.emission_angle_enabled = false
	parent.add_child(ap)
	_loops[slot] = ap
	return ap


## Громкость 0..1 от силы тяги EVA; позиция источника в локале тела по направлению **ввода** (кнопки), не скорости.
func set_eva_jetpack_loop(parent_player: Node3D, thrust_01: float, thrust_dir_body: Vector3 = Vector3.ZERO) -> void:
	if parent_player == null:
		return
	var slot: StringName = StringName("eva_jet_" + parent_player.name)
	var ap := _ensure_loop_player(slot, "eva_jetpack", parent_player, LOOP_BUS_EVA)
	if ap == null:
		return
	var t: float = clampf(thrust_01, 0.0, 1.0)
	if t >= 0.03 and thrust_dir_body.length_squared() > 1e-8:
		var dn: Vector3 = thrust_dir_body.normalized()
		# «Сопла» сзади относительно вектора тяги в локале капсулы (как WASD в EVA).
		ap.position = -dn * 0.42 + Vector3(0.0, 0.06, 0.0)
	else:
		ap.position = Vector3(0.0, 0.1, 0.0)
	_apply_loop_intensity(ap, thrust_01, -8.0, 2.0)


## Один луп на шаттл по имени узла; intensity 0..1 от основного + РСУ.
func set_shuttle_engines_loop(shuttle: Node3D, intensity_01: float) -> void:
	if shuttle == null:
		return
	var slot: StringName = StringName("shuttle_eng_" + shuttle.name)
	var ap := _ensure_loop_player(slot, "shuttle_engines", shuttle, LOOP_BUS_SHUTTLE)
	if ap == null:
		return
	_apply_loop_intensity(ap, intensity_01, -10.0, 3.0)


## Трос на пределе длины (0..1) — лёгкий луп на SFX.
func set_tether_stress_loop(parent: Node3D, strain_01: float) -> void:
	if parent == null:
		return
	var slot: StringName = StringName("tether_str_" + parent.name)
	var ap := _ensure_loop_player(slot, "tether_stress", parent, INTERIOR_SFX_BUS)
	if ap == null:
		return
	ap.position = Vector3(0.0, 0.22, 0.05)
	var t: float = clampf(strain_01, 0.0, 1.0)
	if t < 0.008:
		if ap.playing:
			ap.stop()
		ap.volume_db = -80.0
		return
	if not ap.playing:
		ap.play()
	ap.volume_db = lerpf(-12.0, -1.0, t)


func play_tether_reel_tick(parent: Node3D, extending: bool, volume_db_offset: float = -7.0) -> void:
	play_interior_at(parent, "tether_reel_out" if extending else "tether_reel_in", volume_db_offset)


func _apply_loop_intensity(ap: AudioStreamPlayer3D, thrust_01: float, db_quiet: float, db_loud: float) -> void:
	if ap == null:
		return
	var t: float = clampf(thrust_01, 0.0, 1.0)
	if t < 0.03:
		if ap.playing:
			ap.stop()
		ap.volume_db = -80.0
		return
	if not ap.playing:
		ap.play()
	ap.volume_db = lerpf(db_quiet, db_loud, t)
