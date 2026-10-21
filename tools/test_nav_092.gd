## test_nav_092.gd - v0.9.2 gamepad-navigation end-to-end test.
## Boots the real main scene in PC mode (-- --pc), waits for the launcher
## list, then drives MarigoldMenu._forward_nav_event with synthetic
## joypad events: D-pad Down must land focus on a row button inside the
## panel SubViewport, and the A button must activate the focused row,
## which main.gd turns into a chapter load.
## Run: godot --headless --script tools/test_nav_092.gd -- --pc
extends SceneTree

var _frame := 0
var _main: Node = null
var _menu: Node = null
var _stage := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _joy_button(idx: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = idx
	ev.pressed = true
	return ev


func _process(_delta: float) -> bool:
	_frame += 1
	match _stage:
		0:
			# Wait for Main + menu stage 1 (list built).
			_menu = _main.get_node_or_null("MenuRoot")
			if _menu != null and _frame > 10:
				var vp: SubViewport = _menu.get("_viewport")
				if vp != null and vp.gui_get_focus_owner() == null:
					_stage = 1
			if _frame > 600:
				_failures.append("menu never became ready")
				_finish()
		1:
			# D-pad Down: focus must land on a control in the viewport.
			_menu.call("_forward_nav_event", _joy_button(JOY_BUTTON_DPAD_DOWN))
			_stage = 2
		2:
			var vp2: SubViewport = _menu.get("_viewport")
			var owner := vp2.gui_get_focus_owner()
			if owner == null:
				_failures.append("no focus owner after D-pad down")
			elif not (owner is Button):
				_failures.append("focus owner is not a Button: %s" % owner)
			else:
				print("[nav092] focus after D-pad: ", owner)
			# A button: activates the focused row -> chapter load.
			_menu.call("_forward_nav_event", _joy_button(JOY_BUTTON_A))
			_stage = 3
		3:
			if _frame > 30:
				var cur: Variant = _main.get("_current_chapter")
				if cur == null:
					_failures.append("A button did not start a chapter")
				else:
					print("[nav092] chapter started via gamepad A: ", cur)
				_finish()
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("[nav092] PASS")
	else:
		for f in _failures:
			print("[nav092] FAIL: ", f)
	quit(0 if _failures.is_empty() else 1)
