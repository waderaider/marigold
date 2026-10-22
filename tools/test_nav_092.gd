## test_nav_092.gd - gamepad-navigation end-to-end test (v0.9.2, ext. v0.9.3).
## Boots the real main scene and drives it with synthetic joypad events:
##   A. boot chooser (when shown): focus starts on the PC button and a
##      pad A press picks it (v0.9.3 U1 synthetic ui_accept path).
##   B. launcher: D-pad Down lands focus on a chapter ROW (a specific
##      button inside the list, not just any Button), A starts it.
##   C. pause (v0.9.3 T1): open -> settings page (focus on the first
##      settings row) -> settings rebuild restores focus to the same
##      row (U3) -> pad B backs out to the main page, still paused ->
##      pad B again resumes (U2).
##   D. PC 2D menu (v0.9.3, wade's order): in --pc runs the launcher is
##      the full-screen root-viewport menu — stages B assert focus in
##      the ROOT viewport inside _pc_list_vbox instead of the panel
##      SubViewport (VR assertions unchanged).
##   E. mouse-only path (v0.9.3, PC runs): synthetic mouse events ONLY —
##      click the on-screen ❚❚ pause button -> pause opens; click
##      Continuar on the pause panel -> resumes; hold LMB -> the PC
##      rig walks forward (hold-to-move), release stops.
## Canonical runs (once per checkout: --import first):
##   godot --headless --path . --script res://tools/test_nav_092.gd -- --pc
##   HOME=/tmp/mg-fresh godot --headless --path . \
##       --script res://tools/test_nav_092.gd      # fresh profile: chooser
extends SceneTree

var _frame := 0
var _main: Node = null
var _menu: Node = null
var _pause: Node = null
var _stage := 0
var _stage_frame := 0
var _failures: Array[String] = []
var _pc := false
var _hold_start_msec := 0
var _rig_pos0 := Vector3.ZERO


## Synthetic mouse click (press + release) at a root-viewport position.
func _mouse_click(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(press)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = pos
	Input.parse_input_event(rel)


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _joy_button(idx: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = idx
	ev.pressed = true
	return ev


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[nav092] FAIL: ", msg)


func _goto(stage: int) -> void:
	_stage = stage
	_stage_frame = _frame


func _node_text(n: Node) -> String:
	# Buttons in this project carry their captions in child Labels.
	var t := ""
	if n is Button:
		t += (n as Button).text
	if n is Label:
		t += (n as Label).text
	for c in n.get_children():
		t += " " + _node_text(c)
	return t


func _find_button_with_text(n: Node, needle: String) -> Button:
	if n is Button and _node_text(n).contains(needle):
		return n as Button
	for c in n.get_children():
		var hit := _find_button_with_text(c, needle)
		if hit != null:
			return hit
	return null


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		# Headless windows default to 64x64 while the stretch canvas is
		# 1280x720 — synthetic mouse positions (canvas coords) would be
		# transformed off-screen. Pin the window (a boot-time set is
		# overwritten; frame 5 sticks) so coords line up 1:1, exactly as
		# on a real 1280x720 desktop window.
		root.size = Vector2i(1280, 720)
	match _stage:
		0: # boot: chooser or straight to menu?
			var chooser: Variant = _main.get("_chooser")
			if chooser != null:
				print("[nav092] boot chooser shown")
				_goto(10)
			elif _frame > 30:
				print("[nav092] no chooser (mode pre-resolved) - skipping A")
				_goto(1)
			if _frame > 600:
				_fail("boot never resolved")
				_finish()
		10: # chooser: focus must start on the PC button
			var chooser2: CanvasLayer = _main.get("_chooser")
			var pc_btn := _find_button_with_text(chooser2, "PC")
			if pc_btn == null:
				_fail("chooser has no PC button")
				_goto(1)
			elif root.gui_get_focus_owner() != pc_btn:
				_fail("chooser focus is not on the PC button: %s"
						% root.gui_get_focus_owner())
				_goto(1)
			else:
				print("[nav092] chooser focus OK: ", pc_btn.text)
				Input.parse_input_event(_joy_button(JOY_BUTTON_A))
				_goto(11)
		11: # chooser: pad A must pick PC and dismiss the chooser
			if _main.get("_chooser") == null:
				var st := root.get_node_or_null("MarigoldState")
				if st != null and bool(st.call("is_pc_mode")):
					print("[nav092] chooser pad-A picked PC mode")
				else:
					_fail("chooser dismissed but PC mode not active")
				_goto(1)
			elif _frame - _stage_frame > 180:
				_fail("pad A did not dismiss the chooser")
				_goto(1)
		1: # wait for the launcher list
			_menu = _main.get_node_or_null("MenuRoot")
			if _menu != null and _frame - _stage_frame > 10:
				var st1 := root.get_node_or_null("MarigoldState")
				_pc = st1 != null and bool(st1.call("is_pc_mode"))
				if _pc:
					# PC 2D menu: built in the root viewport. (It
					# pre-focuses the first row, so readiness is
					# "layer up + list built", not "no focus".)
					var layer: CanvasLayer = _menu.get("_pc_layer")
					var pc_list: Control = _menu.get("_pc_list_vbox")
					if layer != null and layer.visible and pc_list != null \
							and _menu.get("_pc_first_row") != null:
						print("[nav092] PC 2D menu ready")
						_goto(2)
				else:
					var vp: SubViewport = _menu.get("_viewport")
					if vp != null and vp.gui_get_focus_owner() == null:
						_goto(2)
			if _frame - _stage_frame > 600:
				_fail("menu never became ready")
				_finish()
		2: # D-pad Down into the list
			if _pc:
				Input.parse_input_event(_joy_button(JOY_BUTTON_DPAD_DOWN))
			else:
				_menu.call("_forward_nav_event", _joy_button(JOY_BUTTON_DPAD_DOWN))
			_goto(3)
		3: # focus must be a specific chapter row inside the list vbox
			if _pc:
				var pc_owner := root.gui_get_focus_owner()
				var pc_list2: Control = _menu.get("_pc_list_vbox")
				if pc_owner == null:
					_fail("PC menu: no focus owner after D-pad down")
				elif not (pc_owner is Button):
					_fail("PC menu: focus owner is not a Button: %s" % pc_owner)
				elif pc_list2 == null or not pc_list2.is_ancestor_of(pc_owner):
					_fail("PC menu: focus is not on a chapter row: %s" % pc_owner)
				else:
					print("[nav092] PC menu focus on row: ",
							_node_text(pc_owner))
				Input.parse_input_event(_joy_button(JOY_BUTTON_A))
				_goto(4)
				return false
			var vp2: SubViewport = _menu.get("_viewport")
			var owner := vp2.gui_get_focus_owner()
			var list_vbox: Control = _menu.get("_list_vbox")
			if owner == null:
				_fail("no focus owner after D-pad down")
			elif not (owner is Button):
				_fail("focus owner is not a Button: %s" % owner)
			elif list_vbox == null or not list_vbox.is_ancestor_of(owner):
				_fail("focus is not on a chapter row: %s" % owner)
			else:
				print("[nav092] focus on row: ", (owner as Button).text)
			_menu.call("_forward_nav_event", _joy_button(JOY_BUTTON_A))
			_goto(4)
		4: # A must start the chapter
			if _frame - _stage_frame > 30:
				var cur: Variant = _main.get("_current_chapter")
				if cur == null:
					_fail("A button did not start a chapter")
					_finish()
				else:
					print("[nav092] chapter started via gamepad A: ", cur)
					_goto(5)
		5: # settle, then open the pause menu
			if _frame - _stage_frame > 30:
				_pause = root.get_node_or_null("MarigoldPause")
				if _pause == null:
					_fail("MarigoldPause autoload not found")
					_finish()
				else:
					_pause.call("_toggle_pause", "gamepad")
					_goto(6)
		6: # pause open? then dive into settings
			if _frame - _stage_frame > 5:
				if not paused:
					_fail("tree not paused after _toggle_pause")
				elif not bool(_pause.get("_pause_open")):
					_fail("pause did not open (attached?)")
				else:
					print("[nav092] pause opened via gamepad path")
					_pause.call("_show_settings_page")
				_goto(7)
		7: # settings page visible, focus on the first row's button
			if _frame - _stage_frame > 5:
				var page: Control = _pause.get("_page_settings")
				if page == null or not page.visible:
					_fail("settings page not visible")
				else:
					var btns: Dictionary = _pause.get("_setting_value_btns")
					var input_btn: Button = (btns.get("input", {}) as Dictionary).get("btn")
					var pvp: SubViewport = _pause.get("_panel_viewport")
					if input_btn == null:
						_fail("settings has no 'input' row button")
					elif pvp.gui_get_focus_owner() != input_btn:
						_fail("settings focus not on first row: %s"
								% pvp.gui_get_focus_owner())
					else:
						print("[nav092] settings focus OK on 'input' row")
						# U3: focus the gfx row, force a rebuild, and
						# expect focus restored to the NEW gfx button.
						var gfx_btn: Button = (btns.get("gfx", {}) as Dictionary).get("btn")
						if gfx_btn != null:
							gfx_btn.grab_focus()
						_pause.call("_refresh_settings_labels")
				_goto(8)
		8: # after the deferred rebuild, focus = new gfx row button
			if _frame - _stage_frame > 8:
				var btns2: Dictionary = _pause.get("_setting_value_btns")
				var gfx_btn2: Button = (btns2.get("gfx", {}) as Dictionary).get("btn")
				var pvp2: SubViewport = _pause.get("_panel_viewport")
				if gfx_btn2 == null:
					_fail("gfx row missing after rebuild")
				elif pvp2.gui_get_focus_owner() != gfx_btn2:
					_fail("focus NOT restored after settings rebuild: %s"
							% pvp2.gui_get_focus_owner())
				else:
					print("[nav092] settings rebuild restored focus to 'gfx' row")
				_pause.call("_input", _joy_button(JOY_BUTTON_B))
				_goto(9)
		9: # B: back to main page, STILL paused
			if _frame - _stage_frame > 5:
				var page2: Control = _pause.get("_page_settings")
				var stack: Control = _pause.get("_panel_stack")
				if page2 != null and page2.visible:
					_fail("B did not leave the settings page")
				elif stack == null or not stack.visible:
					_fail("main pause page not visible after B")
				elif not paused:
					_fail("B on settings page resumed the game (wrong layer)")
				else:
					print("[nav092] B backed out to main page, still paused")
					_pause.call("_input", _joy_button(JOY_BUTTON_B))
				_goto(100)
		100: # B on main page: resume
			if _frame - _stage_frame > 5:
				if paused:
					_fail("second B did not resume")
					_finish()
				elif bool(_pause.get("_pause_open")):
					_fail("pause still flagged open after resume")
					_finish()
				else:
					print("[nav092] second B resumed the game")
					if _pc:
						_goto(200) # mouse-only path (PC runs)
					else:
						_finish()
		200: # mouse-only: the on-screen ❚❚ pause button must be up
			if _frame - _stage_frame > 10:
				var btn: Button = _pause.get("_pc_pause_btn")
				if btn == null:
					_fail("no screen-space pause button")
					_finish()
				elif not btn.visible:
					_fail("screen-space pause button not visible in chapter")
					_finish()
				else:
					print("[nav092] ❚❚ pause button visible; clicking it")
					_mouse_click(btn.get_global_rect().get_center())
					_goto(201)
		201: # pause must be open from the mouse click alone
			if _frame - _stage_frame > 10:
				if not paused or not bool(_pause.get("_pause_open")):
					_fail("mouse click on ❚❚ did not open pause")
					_finish()
				else:
					print("[nav092] pause opened by mouse click alone")
					# Click "Continuar": project its spot on the pause
					# quad (action row, first button) to screen space.
					var panel_root: Node3D = _pause.get("_panel_root")
					var cam := root.get_camera_3d()
					if panel_root == null or cam == null:
						_fail("cannot compute Continuar click point")
						_finish()
					else:
						var world := panel_root.global_transform \
								* Vector3(-0.449, 0.509, 0.0)
						_mouse_click(cam.unproject_position(world))
						_goto(202)
		202: # the Continuar click must resume
			if _frame - _stage_frame > 10:
				if paused or bool(_pause.get("_pause_open")):
					_fail("mouse click on Continuar did not resume")
					_finish()
				else:
					print("[nav092] resumed by mouse click on Continuar")
					_goto(203)
		203: # hold-to-move: press LMB (synthetic) and keep it held
			if _frame - _stage_frame > 10:
				var rig: Node3D = _main.get("_pc_rig")
				if rig == null:
					_fail("no PC rig for hold-to-move")
					_finish()
				else:
					_rig_pos0 = rig.position
					var press := InputEventMouseButton.new()
					press.button_index = MOUSE_BUTTON_LEFT
					press.pressed = true
					press.position = root.size * 0.5
					press.button_mask = MOUSE_BUTTON_MASK_LEFT
					Input.parse_input_event(press)
					_hold_start_msec = Time.get_ticks_msec()
					_goto(204)
		204: # after ~0.9 s held, the rig must have walked forward
			if Time.get_ticks_msec() - _hold_start_msec > 900:
				var rel := InputEventMouseButton.new()
				rel.button_index = MOUSE_BUTTON_LEFT
				rel.pressed = false
				rel.position = root.size * 0.5
				Input.parse_input_event(rel)
				var rig2: Node3D = _main.get("_pc_rig")
				var moved := Vector2(rig2.position.x - _rig_pos0.x,
						rig2.position.z - _rig_pos0.z).length()
				if moved < 0.25:
					_fail("hold-LMB did not walk (moved %.2f m)" % moved)
				else:
					print("[nav092] hold-to-move walked %.2f m" % moved)
				_finish()
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("[nav092] PASS")
	else:
		for f in _failures:
			print("[nav092] FAIL: ", f)
	quit(0 if _failures.is_empty() else 1)
