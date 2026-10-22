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
var _current_player: AudioStreamPlayer = null
var _stream_cache := {}


func _ready() -> void:
	# v0.9.3: the Voice bus ships in default_bus_layout.tres (with a
	# gentle compressor). Reuse it when present - the old code appended
	# a duplicate bus at whatever index bus_count happened to be, and
	# would have attached the analyzer over the layout's effects.
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_send(_bus_idx, "Master")
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.buffer_length = 0.25
	var slot := AudioServer.get_bus_effect_count(_bus_idx)
	AudioServer.add_bus_effect(_bus_idx, fx)
	_analyzer = AudioServer.get_bus_effect_instance(_bus_idx, slot) as AudioEffectSpectrumAnalyzerInstance


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
## v0.7.0: extended to (stream, speaker, text) per Comfort §4.4 — voice and
## captions can never drift apart. If stream is null (clip not yet generated),
## the caption still shows (subtitle fallback for every line).
func play_dialogue(stream: AudioStream, speaker: String = "", text: String = "", volume_db: float = -4.0) -> void:
	# Captions always (gated by Subtitles toggle inside).
	if speaker != "" or text != "":
		var dur := 0.0
		if stream != null:
			dur = stream.get_length() + 0.8
		MarigoldCaptions.show(speaker, text, dur)
	if stream == null:
		return
	# v0.9.3: single-voice policy - a new line replaces the one still
	# playing instead of stacking voices over each other (the caption
	# model is single-line; the audio now matches it).
	if _current_player != null and is_instance_valid(_current_player):
		_current_player.stop()
		_current_player.queue_free()
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = BUS_NAME
	add_child(p)
	_current_player = p
	p.play()
	p.finished.connect(p.queue_free)


## Convenience: play a narrative line by key. Loads from
## assets/audio/voice/<chapter>/<speaker>_<key>.wav; if missing, caption only.
func play_line(chapter: String, speaker: String, key: String, text: String, volume_db: float = -4.0) -> void:
	var path := "res://assets/audio/voice/%s/%s_%s.wav" % [chapter, speaker.to_lower(), key]
	# v0.9.3: cache loaded streams - replaying a line used to re-read
	# the WAV from disk every time. Path format is unchanged (voice
	# file names, including accented speakers, are load-bearing).
	var stream: AudioStream = _stream_cache.get(path)
	if stream == null and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		if stream != null:
			_stream_cache[path] = stream
	play_dialogue(stream, speaker, text, volume_db)
