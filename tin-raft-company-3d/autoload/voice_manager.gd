extends Node

signal voice_player_added(peer_id: int)
signal voice_player_removed(peer_id: int)

const OPUS_SAMPLE_RATE  := 48000
const OPUS_CHANNELS     := 2
const OPUS_CHUNK_SIZE   := 480
const OPUS_BITRATE      := 64000
const OPUS_COMPLEXITY   := 5
var opus_encoder: TwovoipOpusEncoder

var cached_mode := 0
var cached_threshold := 20.0
var cached_voice_volume := 80.0
var current_mic_level := 0.0

var muted := false
var is_transmitting := false
var ptt_active := false

var vox_timer := 0.0
const VOX_HOLD_TIME := 0.3

var _last_input_mix_rate := 0.0

var mute_pressed_prev := false
var network_manager: NetworkManager
var peer_voice_players := {}

func _ready() -> void:
	opus_encoder = TwovoipOpusEncoder.new()
	_reinit_opus_chain()
	AudioServer.set_input_device_active(true)

	_apply_voice_settings()
	if SettingsManager:
		SettingsManager.settings_applied.connect(_apply_voice_settings)

	network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_joined.connect(_on_player_joined)
		network_manager.player_left.connect(_on_player_left)

	multiplayer.peer_packet.connect(_on_peer_packet)

func _reinit_opus_chain() -> void:
	if opus_encoder == null:
		return
	var mix: float = AudioServer.get_input_mix_rate()
	if mix <= 0.0:
		mix = float(OPUS_SAMPLE_RATE)
	_last_input_mix_rate = mix
	opus_encoder.create_sampler(
		mix,
		float(OPUS_SAMPLE_RATE),
		OPUS_CHANNELS,
		true
	)
	opus_encoder.create_opus_encoder(OPUS_BITRATE, OPUS_COMPLEXITY, true)

func _apply_voice_settings() -> void:
	if SettingsManager == null:
		return
	cached_mode = int(SettingsManager.data.get("voice_mode", 0))
	cached_threshold = float(SettingsManager.data.get("mic_threshold", 20.0))
	cached_voice_volume = float(SettingsManager.data.get("voice_volume", 80.0))
	for peer_id in peer_voice_players:
		var player: AudioStreamPlayer3D = peer_voice_players[peer_id]["player"]
		player.volume_db = linear_to_db(clampf(cached_voice_volume / 100.0, 0.0, 1.0))

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

func _process(_delta: float) -> void:
	if SettingsManager == null:
		return

	if muted:
		current_mic_level = 0.0
		return

	# сравнение в Гц, а не is_equal_approx — иначе на части драйверов вечный reinit
	var live_mix: float = AudioServer.get_input_mix_rate()
	if live_mix > 0.0 and ( _last_input_mix_rate <= 0.0 or abs(live_mix - _last_input_mix_rate) > 1.0):
		_reinit_opus_chain()
	var mix_rate: float = _last_input_mix_rate
	if mix_rate <= 0.0:
		mix_rate = float(OPUS_SAMPLE_RATE)
	var chunk_duration: float = float(OPUS_CHUNK_SIZE) / mix_rate

	var raw_chunk: PackedVector2Array = AudioServer.get_input_frames(OPUS_CHUNK_SIZE)
	if raw_chunk.size() == 0:
		current_mic_level = 0.0
		return

	var max_amplitude := 0.0
	for v in raw_chunk:
		max_amplitude = max(max_amplitude, abs(v.x))
	var vox_instant: float = max_amplitude * 100.0
	current_mic_level = vox_instant

	if cached_mode == 0:   # PTT
		if not ptt_active:
			return
		opus_encoder.process_pre_encoded_chunk(raw_chunk, OPUS_CHUNK_SIZE, false, false)
		var packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 1.0)
		if packet.size() > 0:
			send_voice_packet(packet)
	else:                    # VOX: порог по пику чанка; хвост — таймер после падения ниже порога
		if vox_instant >= cached_threshold:
			is_transmitting = true
			vox_timer = VOX_HOLD_TIME

		if is_transmitting:
			opus_encoder.process_pre_encoded_chunk(raw_chunk, OPUS_CHUNK_SIZE, false, false)
			var vox_packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 1.0)
			if vox_packet.size() > 0:
				send_voice_packet(vox_packet)
			if vox_instant < cached_threshold:
				vox_timer -= chunk_duration
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
	_create_voice_player(_peer_id)   # создаём плеер сразу при подключении

func _on_player_left(peer_id: int) -> void:
	_remove_voice_player(peer_id)

func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() > 0:
		_process_voice_packet(peer_id, packet)

func _process_voice_packet(peer_id: int, data: PackedByteArray) -> void:
	# плеер уже гарантированно создан в _on_player_joined
	if not peer_voice_players.has(peer_id):
		return

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
	var vol := cached_voice_volume / 100.0
	player.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamPlaybackOpus
	playback.mark_end_opus_stream(true)

	peer_voice_players[peer_id] = {
		"playback": playback,
		"player": player
	}
	voice_player_added.emit(peer_id)
	print("Voice player for peer ", peer_id, " created")

func set_player_volume(peer_id: int, linear_volume: float) -> void:
	if peer_voice_players.has(peer_id):
		var player: AudioStreamPlayer3D = peer_voice_players[peer_id]["player"]
		player.volume_db = linear_to_db(clampf(linear_volume, 0.0, 1.0))

func _remove_voice_player(peer_id: int) -> void:
	if not peer_voice_players.has(peer_id):
		return
	var info = peer_voice_players[peer_id]
	voice_player_removed.emit(peer_id)
	info["player"].queue_free()
	peer_voice_players.erase(peer_id)
	print("Voice player for peer ", peer_id, " removed")
