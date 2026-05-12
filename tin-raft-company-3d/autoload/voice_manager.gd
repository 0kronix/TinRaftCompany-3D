extends Node

signal voice_player_added(peer_id: int)
signal voice_player_removed(peer_id: int)

const VOICE_MAGIC := 0xA7
const VOICE_HEADER_SIZE := 5

const OPUS_SAMPLE_RATE := 48000
const OPUS_CHANNELS := 1
## 20 ms кадр @ 48 kHz (как twovoip) — меньше срывов декодера, чем 10 ms при том же битрейте.
const OPUS_CHUNK_SIZE := 960
const OPUS_BITRATE := 64000
const OPUS_COMPLEXITY := 5

## Канал сырых байт (канал 2 у части пиров не приходит в peer_packet).
const VOICE_NET_CHANNEL := 1
## Только FIFO-лимит: «срез до N кадров» давал потери → PLC Opus → шипение и «залипание» по времени.
const VOICE_QUEUE_MAX_FRAMES := 24
var opus_encoder: TwovoipOpusEncoder

var cached_mode := 0
var cached_threshold := 20.0
var cached_voice_volume := 80.0
var cached_denoise := true
var current_mic_level := 0.0

var muted := false
var is_transmitting := false
var ptt_active := false

var vox_timer := 0.0
const VOX_HOLD_TIME := 0.3

var _last_input_mix_rate := 0.0
var _audio_input_frame_count := 480

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
	set_physics_process(true)
	# Раньше остальных узлов: быстрее снимаем очередь после peer_packet (меньше хвост задержки).
	process_priority = -1000


func _is_voice_network_ready() -> bool:
	if network_manager == null or not network_manager.is_session_active():
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	var mp: MultiplayerPeer = multiplayer.multiplayer_peer
	return mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _reinit_opus_chain() -> void:
	if opus_encoder == null:
		return
	var mix: float = AudioServer.get_input_mix_rate()
	if mix <= 0.0:
		mix = float(OPUS_SAMPLE_RATE)
	_last_input_mix_rate = mix
	# Шумодав в create_sampler даёт металлический «шип» на части драйверов; оставляем в process_pre_encoded_chunk.
	opus_encoder.create_sampler(
		mix,
		float(OPUS_SAMPLE_RATE),
		OPUS_CHANNELS,
		false
	)
	opus_encoder.create_opus_encoder(OPUS_BITRATE, OPUS_COMPLEXITY, true)
	_audio_input_frame_count = int(opus_encoder.calc_audio_chunk_size(OPUS_CHUNK_SIZE))


func _apply_input_device_from_settings() -> void:
	if SettingsManager == null:
		return
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	if devices.is_empty():
		return
	var idx: int = clampi(int(SettingsManager.data.get("mic_device", 0)), 0, devices.size() - 1)
	AudioServer.set_input_device(devices[idx])


func _apply_voice_settings() -> void:
	if SettingsManager == null:
		return
	cached_mode = int(SettingsManager.data.get("voice_mode", 0))
	cached_threshold = float(SettingsManager.data.get("mic_threshold", 20.0))
	cached_voice_volume = float(SettingsManager.data.get("voice_volume", 80.0))
	var prev_denoise: bool = cached_denoise
	cached_denoise = bool(SettingsManager.data.get("noise_suppress", true))
	if cached_denoise != prev_denoise:
		_reinit_opus_chain()

	_apply_input_device_from_settings()

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


func _process(_delta: float) -> void:
	_drain_voice_receive_queues()
	if SettingsManager == null:
		return

	if muted:
		current_mic_level = 0.0
		return

	if not _is_voice_network_ready():
		current_mic_level = 0.0
		is_transmitting = false
		return

	var live_mix: float = AudioServer.get_input_mix_rate()
	if live_mix > 0.0 and (_last_input_mix_rate <= 0.0 or abs(live_mix - _last_input_mix_rate) > 1.0):
		_reinit_opus_chain()
	var mix_rate: float = _last_input_mix_rate
	if mix_rate <= 0.0:
		mix_rate = float(OPUS_SAMPLE_RATE)
	var chunk_duration: float = float(OPUS_CHUNK_SIZE) / mix_rate

	var raw_chunk: PackedVector2Array = AudioServer.get_input_frames(_audio_input_frame_count)
	if raw_chunk.size() == 0:
		current_mic_level = 0.0
		return

	var max_amplitude := 0.0
	for v in raw_chunk:
		max_amplitude = maxf(max_amplitude, maxf(absf(v.x), absf(v.y)))
	var vox_instant: float = max_amplitude * 100.0
	current_mic_level = vox_instant

	if cached_mode == 0:
		if not ptt_active:
			return
		opus_encoder.process_pre_encoded_chunk(raw_chunk, OPUS_CHUNK_SIZE, cached_denoise, false)
		var packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 0.95)
		if packet.size() > 0:
			send_voice_packet(packet)
	else:
		if vox_instant >= cached_threshold:
			is_transmitting = true
			vox_timer = VOX_HOLD_TIME

		if is_transmitting:
			opus_encoder.process_pre_encoded_chunk(raw_chunk, OPUS_CHUNK_SIZE, cached_denoise, false)
			var vox_packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 0.95)
			if vox_packet.size() > 0:
				send_voice_packet(vox_packet)
			if vox_instant < cached_threshold:
				vox_timer -= chunk_duration
				if vox_timer <= 0.0:
					is_transmitting = false

	_drain_voice_receive_queues()


func _wrap_voice_packet(opus: PackedByteArray, speaker_id: int) -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(VOICE_HEADER_SIZE)
	header[0] = VOICE_MAGIC
	header.encode_s32(1, speaker_id)
	return header + opus


func send_voice_packet(data: PackedByteArray) -> void:
	if not _is_voice_network_ready():
		return
	var wrapped: PackedByteArray = _wrap_voice_packet(data, multiplayer.get_unique_id())
	if multiplayer.is_server():
		for pid in multiplayer.get_peers():
			if pid == multiplayer.get_unique_id():
				continue
			multiplayer.send_bytes(wrapped, pid, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, VOICE_NET_CHANNEL)
	else:
		multiplayer.send_bytes(wrapped, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, VOICE_NET_CHANNEL)


func _on_player_joined(_peer_id: int) -> void:
	_create_voice_player(_peer_id)


func _on_player_left(peer_id: int) -> void:
	_remove_voice_player(peer_id)


func _on_peer_packet(from_peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() < VOICE_HEADER_SIZE or packet[0] != VOICE_MAGIC:
		return
	var speaker_id: int = packet.decode_s32(1)
	var opus_payload: PackedByteArray = packet.slice(VOICE_HEADER_SIZE)
	if speaker_id == multiplayer.get_unique_id():
		return

	if multiplayer.is_server() and _is_voice_network_ready():
		for pid in multiplayer.get_peers():
			if pid == from_peer_id:
				continue
			multiplayer.send_bytes(packet, pid, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, VOICE_NET_CHANNEL)

	_process_voice_packet(speaker_id, opus_payload)
	_drain_voice_receive_queues()


func _process_voice_packet(speaker_id: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return
	if not peer_voice_players.has(speaker_id):
		_create_voice_player(speaker_id)

	var q: Array = peer_voice_players[speaker_id]["queue"]
	q.append(data)
	while q.size() > VOICE_QUEUE_MAX_FRAMES:
		q.pop_front()


func _drain_voice_receive_queues() -> void:
	for speaker_id: int in peer_voice_players.keys():
		var playback: AudioStreamPlaybackOpus = peer_voice_players[speaker_id]["playback"]
		var q: Array = peer_voice_players[speaker_id]["queue"]
		if playback == null or not is_instance_valid(playback):
			continue
		while q.size() > 0 and playback.available_space_frames() > 0:
			var pkt: PackedByteArray = q.pop_front() as PackedByteArray
			if pkt.is_empty():
				continue
			playback.push_opus_packet(pkt, 0, 0)


func _physics_process(_delta: float) -> void:
	_drain_voice_receive_queues()
	if peer_voice_players.is_empty():
		return
	var tree := get_tree()
	if tree == null:
		return
	for sid: int in peer_voice_players.keys():
		var p3d: AudioStreamPlayer3D = peer_voice_players[sid]["player"]
		var puppet: Node3D = tree.root.get_node_or_null(GameScenePaths.player_puppet_path_str(sid)) as Node3D
		if puppet:
			p3d.global_position = puppet.global_position


func _create_voice_player(peer_id: int) -> void:
	if peer_voice_players.has(peer_id):
		return

	var stream := AudioStreamOpus.new()
	stream.opus_sample_rate = OPUS_SAMPLE_RATE
	stream.opus_channels = OPUS_CHANNELS

	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "Master"
	var vol := cached_voice_volume / 100.0
	player.volume_db = linear_to_db(clampf(vol, 0.0, 1.0))
	add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamPlaybackOpus
	playback.mark_end_opus_stream(true)

	peer_voice_players[peer_id] = {
		"playback": playback,
		"player": player,
		"queue": []
	}
	voice_player_added.emit(peer_id)


## Локальная индикация HUD: PTT зажат или VOX в передаче (мик не в mute, сеть готова).
func is_local_voice_transmitting() -> bool:
	if muted:
		return false
	if not _is_voice_network_ready():
		return false
	if cached_mode == 0:
		return ptt_active
	return is_transmitting


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
