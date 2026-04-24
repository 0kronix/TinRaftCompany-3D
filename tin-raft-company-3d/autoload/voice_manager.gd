extends Node

const OPUS_SAMPLE_RATE  := 48000
const OPUS_CHANNELS     := 1          # моно для голоса
const OPUS_CHUNK_SIZE   := 960        # 20 мс @ 48 kHz
const OPUS_BITRATE      := 32000
const OPUS_COMPLEXITY   := 10

var opus_encoder: TwovoipOpusEncoder
var is_ptt_pressed  := false
var network_manager: NetworkManager
# peer_id -> AudioStreamPlaybackOpus
var peer_voice_players := {}

func _ready() -> void:
	opus_encoder = TwovoipOpusEncoder.new()
	opus_encoder.create_sampler(
		AudioServer.get_input_mix_rate(),
		OPUS_SAMPLE_RATE,
		OPUS_CHANNELS,
		false   # без шумоподавления
	)
	opus_encoder.create_opus_encoder(OPUS_BITRATE, OPUS_COMPLEXITY, true)
	AudioServer.set_input_device_active(true)

	network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_joined.connect(_on_player_joined)
		network_manager.player_left.connect(_on_player_left)

	multiplayer.peer_packet.connect(_on_peer_packet)


func _on_player_joined(_peer_id: int) -> void:
	pass


func _on_player_left(peer_id: int) -> void:
	_remove_voice_player(peer_id)


func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() > 0:
		_process_voice_packet(peer_id, packet)


func _process(_delta: float) -> void:
	if not is_ptt_pressed:
		return

	var audio_chunk_size := opus_encoder.calc_audio_chunk_size(OPUS_CHUNK_SIZE)
	while true:
		var chunk: PackedVector2Array = AudioServer.get_input_frames(audio_chunk_size)
		if chunk.size() == 0:
			break
		opus_encoder.process_pre_encoded_chunk(chunk, OPUS_CHUNK_SIZE, false, false)
		var packet: PackedByteArray = opus_encoder.encode_chunk(PackedByteArray(), 1.0)
		if packet.size() > 0:
			send_voice_packet(packet)


func send_voice_packet(data: PackedByteArray) -> void:
	if not network_manager or not network_manager._peer:
		return
	for id in multiplayer.get_peers():
		if id == multiplayer.get_unique_id():
			continue
		multiplayer.send_bytes(data, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)


func start_talking() -> void:
	is_ptt_pressed = true
	print("PTT pressed")


func stop_talking() -> void:
	is_ptt_pressed = false
	print("PTT released")


func _process_voice_packet(peer_id: int, data: PackedByteArray) -> void:
	if not peer_voice_players.has(peer_id):
		_create_voice_player(peer_id)

	var playback: AudioStreamPlaybackOpus = peer_voice_players[peer_id]
	if playback and playback.available_space_frames() > 0:
		playback.push_opus_packet(data, 0, 0)
	else:
		print("Voice buffer full for peer ", peer_id)


func _create_voice_player(peer_id: int) -> void:
	var stream := AudioStreamOpus.new()
	stream.opus_sample_rate = OPUS_SAMPLE_RATE
	stream.opus_channels    = OPUS_CHANNELS

	var player := AudioStreamPlayer.new()
	player.stream   = stream
	player.bus      = "Master"
	player.volume_db = 0.0
	add_child(player)
	player.play()

	var playback := player.get_stream_playback() as AudioStreamPlaybackOpus
	# Сразу разблокируем воспроизведение (без ожидания буфера)
	playback.mark_end_opus_stream(true)

	peer_voice_players[peer_id] = playback
	print("Voice player for peer ", peer_id, " created")


func _remove_voice_player(peer_id: int) -> void:
	if not peer_voice_players.has(peer_id):
		return
	var target_pb: AudioStreamPlaybackOpus = peer_voice_players[peer_id]
	for child in get_children():
		if child is AudioStreamPlayer:
			var pb = child.get_stream_playback()
			if pb == target_pb:
				child.queue_free()
				break
	peer_voice_players.erase(peer_id)
	print("Voice player for peer ", peer_id, " removed")
