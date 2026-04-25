extends Node

const OPUS_SAMPLE_RATE  := 48000
const OPUS_CHANNELS     := 2
const OPUS_CHUNK_SIZE   := 480
const OPUS_BITRATE      := 128000
const OPUS_COMPLEXITY   := 6

var opus_encoder: TwovoipOpusEncoder
var voice_mode := 0
var mic_threshold := 20.0
var muted := false
var voice_volume := 80.0
var is_transmitting := false
var ptt_active := false
var vox_timer := 0.0
const VOX_HOLD_TIME := 0.3

var mute_pressed_prev := false
var network_manager: NetworkManager
var peer_voice_players := {}

func _ready() -> void:
	opus_encoder = TwovoipOpusEncoder.new()
	opus_encoder.create_sampler(
		OPUS_SAMPLE_RATE,
		OPUS_SAMPLE_RATE,
		OPUS_CHANNELS,
		true
	)
	opus_encoder.create_opus_encoder(OPUS_BITRATE, OPUS_COMPLEXITY, true)
	AudioServer.set_input_device_active(true)

	_apply_voice_settings()
	if SettingsManager:
		SettingsManager.settings_applied.connect(_apply_voice_settings)

	network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_joined.connect(_on_player_joined)
		network_manager.player_left.connect(_on_player_left)

	multiplayer.peer_packet.connect(_on_peer_packet)

func _apply_voice_settings() -> void:
	if SettingsManager == null:
		return
	voice_mode = int(SettingsManager.data.get("voice_mode", 0))
	mic_threshold = float(SettingsManager.data.get("mic_threshold", 20.0))
	voice_volume = float(SettingsManager.data.get("voice_volume", 80.0))
	for peer_id in peer_voice_players:
		var player: AudioStreamPlayer3D = peer_voice_players[peer_id]["player"]
		player.volume_db = linear_to_db(clampf(voice_volume / 100.0, 0.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if SettingsManager == null:
		return

	var ptt_key: Key = SettingsManager.data.get("voice_ptt_key", KEY_V)
	if event is InputEventKey and event.keycode == ptt_key:
		ptt_active = event.is_pressed()

	var mute_key: Key = SettingsManager.data.get("voice_mute_key", KEY_M)
	if event is InputEventKey and event.keycode == mute_key and event.is_pressed():
		muted = !muted
		print("MUTE: ", "ON" if muted else "OFF")

func _process(delta: float) -> void:
	if SettingsManager == null:
		return

	var current_mode := int(SettingsManager.data.get("voice_mode", 0))
	var threshold := float(SettingsManager.data.get("mic_threshold", 0.5))

	if muted:
		return

	if current_mode == 0:   # PTT
		if not ptt_active:
			return
		# Читаем чанк только когда кнопка нажата
		var raw_chunk: PackedVector2Array = AudioServer.get_input_frames(OPUS_CHUNK_SIZE)
		if raw_chunk.size() == 0:
			return
		opus_encoder.process_pre_encoded_chunk(raw_chunk, OPUS_CHUNK_SIZE, false, false)
		var packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 1.0)
		if packet.size() > 0:
			send_voice_packet(packet)
	else:                    # VOX
		# Читаем чанк для проверки уровня
		var raw_chunk: PackedVector2Array = AudioServer.get_input_frames(OPUS_CHUNK_SIZE)
		if raw_chunk.size() == 0:
			return
		var max_amplitude := 0.0
		for v in raw_chunk:
			max_amplitude = max(max_amplitude, abs(v.x))
		var level := max_amplitude * 100.0
		if level >= threshold:
			is_transmitting = true
			vox_timer = VOX_HOLD_TIME
			# Кодируем тот же чанк, который проверили
			opus_encoder.process_pre_encoded_chunk(raw_chunk, OPUS_CHUNK_SIZE, false, false)
			var packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 1.0)
			if packet.size() > 0:
				send_voice_packet(packet)
		elif is_transmitting:
			vox_timer -= delta
			if vox_timer <= 0.0:
				is_transmitting = false

func send_voice_packet(data: PackedByteArray) -> void:
	if not network_manager or not network_manager._peer:
		return
	for id in multiplayer.get_peers():
		if id == multiplayer.get_unique_id():
			continue
		multiplayer.send_bytes(data, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)

func _on_player_joined(_peer_id: int) -> void:
	pass

func _on_player_left(peer_id: int) -> void:
	_remove_voice_player(peer_id)

func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() > 0:
		_process_voice_packet(peer_id, packet)

func _process_voice_packet(peer_id: int, data: PackedByteArray) -> void:
	if not peer_voice_players.has(peer_id):
		_create_voice_player(peer_id)

	var playback: AudioStreamPlaybackOpus = peer_voice_players[peer_id]["playback"]
	if playback and playback.available_space_frames() > 0:
		playback.push_opus_packet(data, 0, 0)

func _create_voice_player(peer_id: int) -> void:
	var stream := AudioStreamOpus.new()
	stream.opus_sample_rate = OPUS_SAMPLE_RATE
	stream.opus_channels    = OPUS_CHANNELS

	var player := AudioStreamPlayer3D.new()
	player.stream   = stream
	player.bus      = "Master"
	var vol := float(SettingsManager.data.get("voice_volume", voice_volume)) / 100.0
	player.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamPlaybackOpus
	playback.mark_end_opus_stream(true)

	peer_voice_players[peer_id] = {
		"playback": playback,
		"player": player
	}
	print("Voice player for peer ", peer_id, " created")

func set_player_volume(peer_id: int, linear_volume: float) -> void:
	if peer_voice_players.has(peer_id):
		var player: AudioStreamPlayer3D = peer_voice_players[peer_id]["player"]
		player.volume_db = linear_to_db(clampf(linear_volume, 0.0, 1.0))

func _remove_voice_player(peer_id: int) -> void:
	if not peer_voice_players.has(peer_id):
		return
	var info = peer_voice_players[peer_id]
	info["player"].queue_free()
	peer_voice_players.erase(peer_id)
	print("Voice player for peer ", peer_id, " removed")
