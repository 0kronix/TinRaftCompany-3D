# voice_manager.gd (автозагрузка)
extends Node

const BUS_NAME := "VoiceChat"

# Ссылка на эффект кодирования Opus
var opus_encoder: AudioEffectOpusChunked

func _ready() -> void:
	# Создаём новую аудиошину для микрофона
	var bus_idx := AudioServer.bus_count
	AudioServer.add_bus(bus_idx)
	AudioServer.set_bus_name(bus_idx, BUS_NAME)
	AudioServer.set_bus_mute(bus_idx, true)  # чтобы не было эха

	# Добавляем эффект кодирования Opus (он идёт из плагина)
	opus_encoder = AudioEffectOpusChunked.new()
	AudioServer.add_bus_effect(bus_idx, opus_encoder, 0)

	# Создаём AudioStreamPlayer, захватывающий микрофон
	var mic_player := AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = BUS_NAME
	mic_player.autoplay = true
	add_child(mic_player)
