extends SceneTree
## Generator for res://default_bus_layout.tres (v0.9.3, audio-design
## skill pass). Re-run after any bus change:
##   godot --headless --path . --script res://tools/make_bus_layout.gd
## Builds the graph on the AudioServer, then captures it with
## AudioServer.generate_bus_layout() (AudioBusLayout.bus_count is not
## script-assignable). Work happens in _process so the tool exits even
## if a line errors.
## Master (limiter) <- Music (sidechain comp keyed by Voice), SFX,
## Ambience, UI, Voice (gentle comp; voice.gd appends its analyzer).

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	# Probe the compressor's real property names once (they differ
	# across versions: threshold vs threshold_db).
	var probe := AudioEffectCompressor.new()
	var props := {}
	for p in probe.get_property_list():
		props[p["name"]] = true
	print("COMP PROPS: threshold=", props.has("threshold"),
			" threshold_db=", props.has("threshold_db"),
			" sidechain=", props.has("sidechain"),
			" attack_us=", props.has("attack_us"),
			" release_ms=", props.has("release_ms"))

	# NOTE: autoloads run even under --script, so MarigoldVoice has
	# already appended its runtime Voice bus - strip everything back
	# to Master so the captured layout is exactly the six buses below.
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	# Same for Master's effect chain: a previous capture left a limiter
	# behind once (autoload-era state) - strip so exactly one remains.
	while AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	AudioServer.set_bus_name(0, "Master")
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)

	var music := _add_bus("Music")
	var comp := AudioEffectCompressor.new()
	if props.has("threshold_db"):
		comp.set("threshold_db", -30.0)
	else:
		comp.set("threshold", -30.0)
	comp.ratio = 8.0
	comp.attack_us = 10000.0
	comp.release_ms = 400.0
	comp.gain = 0.0
	if props.has("sidechain"):
		comp.set("sidechain", "Voice")
	AudioServer.add_bus_effect(music, comp)

	_add_bus("SFX")
	_add_bus("Ambience")
	_add_bus("UI")

	var voice := _add_bus("Voice")
	var vcomp := AudioEffectCompressor.new()
	if props.has("threshold_db"):
		vcomp.set("threshold_db", -18.0)
	else:
		vcomp.set("threshold", -18.0)
	vcomp.ratio = 3.0
	vcomp.attack_us = 5000.0
	vcomp.release_ms = 200.0
	vcomp.gain = 0.0
	AudioServer.add_bus_effect(voice, vcomp)

	var layout := AudioServer.generate_bus_layout()
	var err := ResourceSaver.save(layout, "res://default_bus_layout.tres")
	print("BUS LAYOUT SAVE: ", err, " server_buses=", AudioServer.bus_count)
	return true


func _add_bus(bus_name: String) -> int:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx
