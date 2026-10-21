## probe_091_voice.gd - v0.9.1 voice wiring probe (headless).
## For every line in MarigoldDialogue.LINES, resolves the EXACT path
## MarigoldVoice.play_line() loads:
##   res://assets/audio/voice/<chapter>/<speaker.to_lower()>_<key>.wav
## and verifies ResourceLoader.exists() + a loadable AudioStream with
## length > 0. Run:
##   godot --headless --script tools/probe_091_voice.gd
extends SceneTree


func _init() -> void:
	var ok := 0
	var fail := 0
	for line in MarigoldDialogue.LINES:
		var key: String = line[0]
		var chapter: String = line[1]
		var speaker: String = line[2]
		var path := "res://assets/audio/voice/%s/%s_%s.wav" % [chapter, speaker.to_lower(), key]
		if not ResourceLoader.exists(path):
			print("VOICE MISSING: ", path)
			fail += 1
			continue
		var stream := load(path) as AudioStream
		if stream == null or stream.get_length() <= 0.0:
			print("VOICE BADSTREAM: ", path)
			fail += 1
			continue
		ok += 1
		print("VOICE OK: ", path, " ", snappedf(stream.get_length(), 0.1), "s")
	print("VOICE SUMMARY: ", ok, " ok, ", fail, " fail, ", MarigoldDialogue.LINES.size(), " total")
	quit(1 if fail > 0 else 0)
