## probe_092.gd - v0.9.2 input-map verification probe.
## Prints the parsed events for the gamepad-touched actions and the
## built-in ui_* navigation actions, so the [input] serialization and
## Godot's default joypad GUI-nav bindings are verified, not assumed.
## Run: godot --headless --script tools/probe_092.gd
extends SceneTree


func _describe(action: StringName) -> String:
	if not InputMap.has_action(action):
		return action + ": <missing>"
	var parts: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			parts.append("JoyBtn%d" % (ev as InputEventJoypadButton).button_index)
		elif ev is InputEventJoypadMotion:
			var m := ev as InputEventJoypadMotion
			parts.append("JoyAxis%d/%+.1f" % [m.axis, m.axis_value])
		elif ev is InputEventMouseButton:
			parts.append("Mouse%d" % (ev as InputEventMouseButton).button_index)
		elif ev is InputEventKey:
			parts.append("Key%d" % (ev as InputEventKey).physical_keycode)
		else:
			parts.append(ev.get_class())
	return action + ": " + ", ".join(parts)


func _initialize() -> void:
	for a in ["interact", "teleport_confirm", "move_forward", "move_back",
			"move_left", "move_right", "sprint", "pause_menu"]:
		print("[probe092] ", _describe(a))
	for a in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left",
			"ui_right", "ui_focus_next", "ui_page_up", "ui_page_down"]:
		print("[probe092] ", _describe(a))
	print("[probe092] joypads connected: ", Input.get_connected_joypads())
	quit()
