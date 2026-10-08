## MarigoldVoice.gd - Voice audio bus + jaw envelope driver (MARIGOLD v0.6.0).
## Autoload singleton. Creates a dedicated "Voice" bus with an
## AudioEffectSpectrumAnalyzer, sampled ONCE per frame and cached for all
## character rigs (never per character). Jaw driver priority: envelope >
## syllable-timer fallback (in the rig) > beat-synced singing.
## Also the integration hook for offline TTS (roadmap #5): play_dialogue()
## plays a clip on the Voice bus; Sherpa-ONNX output will use the same API.
## Headless-safe: the dummy audio driver yields a silent analyzer -> 0.0.
## NOTE: no class_name - the name is provided by the autoload entry in
## project.godot (class_name + autoload with the same name is a parse error).
extends Node

const BUS_NAME := "Voice"

var _bus_idx := -1
var _analyzer: AudioEffectSpectrumAnalyzerInstance = null
var _env := 0.0


func _ready() -> void:
	_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(_bus_idx)
	AudioServer.set_bus_name(_bus_idx, BUS_NAME)
	AudioServer.set_bus_send(_bus_idx, "Master")
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.buffer_length = 0.25
	AudioServer.add_bus_effect(_bus_idx, fx)
	_analyzer = AudioServer.get_bus_effect_instance(_bus_idx, 0) as AudioEffectSpectrumAnalyzerInstance


func _process(_delta: float) -> void:
	if _analyzer == null:
		_env = 0.0
		return
	var mag := _analyzer.get_magnitude_for_frequency_range(200.0, 4000.0)
	var m := maxf(mag.x, mag.y)
	# Log-compressed to 0..1: silence -> 0, conversational voice -> ~0.5+.
	_env = clampf(log(1.0 + m * 40.0) / log(41.0), 0.0, 1.0)


## Current voice-band envelope, 0..1. Sampled once per frame, cached.
func get_envelope() -> float:
	return _env


## Play a one-shot dialogue clip on the Voice bus (auto-freed).
## This cycle ships the bus + hook; clips are optional content.
func play_dialogue(stream: AudioStream, volume_db: float = -4.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = BUS_NAME
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
