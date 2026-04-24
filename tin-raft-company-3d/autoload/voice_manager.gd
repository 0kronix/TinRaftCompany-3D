extends Node

const BUS_NAME := "VoiceChat"

var opus_encoder: AudioEffectOpusChunked
var is_ptt_pressed := false
var network_manager: NetworkManager
var peer_voice_players := {}

func _ready() -> void:
	var bus_idx := AudioServer.bus_count
	AudioServer.add_bus(bus_idx)
	AudioServer.set_bus_name(bus_idx, BUS_NAME)
	AudioServer.set_bus_mute(bus_idx, true)

	opus_encoder = AudioEffectOpusChunked.new()
	AudioServer.add_bus_effect(bus_idx, opus_encoder, 0)

	var mic_player := AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = BUS_NAME
	mic_player.autoplay = true
	add_child(mic_player)
	
	network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_joined.connect(_on_player_joined)
		network_manager.player_left.connect(_on_player_left)
	
	multiplayer.peer_packet.connect(_on_peer_packet)

func _on_player_joined(_peer_id: int):
	pass

func _on_player_left(peer_id: int):
	_remove_voice_player(peer_id)

func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	if packet.size() > 0 and packet.size() < 200:
		print("RECEIVED: ", packet.size(), " bytes from peer ", peer_id)
		_process_voice_packet(peer_id, packet)

func _process(_delta: float) -> void:
	if is_ptt_pressed:
		while opus_encoder.chunk_available():
			var opus_packet: PackedByteArray = opus_encoder.read_opus_packet(PackedByteArray())
			opus_encoder.drop_chunk()
			send_voice_packet(opus_packet)

func send_voice_packet(data: PackedByteArray) -> void:
	if not network_manager or not network_manager._peer:
		return
	for id in multiplayer.get_peers():
		if id == multiplayer.get_unique_id():
			continue
		multiplayer.send_bytes(data, id, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)
		print("SENT: ", data.size(), " bytes to peer ", id)

func start_talking():
	is_ptt_pressed = true
	print("PTT pressed")

func stop_talking():
	is_ptt_pressed = false
	print("PTT released")

func _process_voice_packet(peer_id: int, data: PackedByteArray) -> void:
	if not peer_voice_players.has(peer_id):
		_create_voice_player(peer_id)
	
	var stream: AudioStreamOpusChunked = peer_voice_players[peer_id]
	
	if stream.chunk_space_available():
		stream.push_opus_packet(data, 0, 0)
	else:
		print("Buffer full for peer ", peer_id)

func _create_voice_player(peer_id: int) -> void:
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamOpusChunked.new()
	stream.mix_rate = 48000
	player.stream = stream
	player.bus = "Master"
	player.volume_db = 0.0
	add_child(player)
	player.play()
	
	peer_voice_players[peer_id] = stream
	
	print("Voice player for peer ", peer_id, " created")

func _remove_voice_player(peer_id: int) -> void:
	if peer_voice_players.has(peer_id):
		for child in get_children():
			if child is AudioStreamPlayer and child.stream == peer_voice_players[peer_id]:
				child.queue_free()
				break
		peer_voice_players.erase(peer_id)
		print("Voice player for peer ", peer_id, " removed")
