## shot_pc_menu.gd - visual verification of the v0.9.3 PC 2D menu.
## Renders REAL frames (run under Xvfb, NOT --headless) and captures:
##   pc_menu_1920x1080.png     the new full-screen 2D launcher
##   pc_menu_1280x720.png      same menu at 720p
##   pc_settings_1920x1080.png the menu's Settings page
##   pc_chapter_1920x1080.png  ch1 running: ❚❚ pause button + crosshair
##   pc_pause_1920x1080.png    pause panel open in PC mode
## Run:
##   xvfb-run -a -s "-screen 0 1920x1080x24" \
##     ~/godot/Godot_v4.7.2-stable_linux.x86_64 --path . \
##     --resolution 1920x1080 --script res://tools/shot_pc_menu.gd -- --pc
extends SceneTree

var _frame := 0
var _main: Node = null
var _menu: Node = null
var _stage := 0
var _stage_frame := 0
var _menu_only := false
var _menus_only := false


func _initialize() -> void:
	MarigoldGfx.set_pc_onboarded() # no first-run overlay in the shots
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("res://tools/shots"))
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	_menu_only = args.has("--menu720")
	_menus_only = args.has("--menus")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)


func _goto(s: int) -> void:
	_stage = s
	_stage_frame = _frame


func _snap(file_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "res://tools/shots/" + file_name
	var err := img.save_png(path)
	print("[shots] ", file_name, " ", img.get_size(), " err=", err)


func _first_button(n: Node) -> Button:
	if n is Button:
		return n as Button
	for c in n.get_children():
		var hit := _first_button(c)
		if hit != null:
			return hit
	return null


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > 9000:
		print("[shots] TIMEOUT at stage ", _stage)
		quit(1)
		return true
	match _stage:
		0: # menu up?
			_menu = _main.get_node_or_null("MenuRoot")
			if _menu != null and bool(_menu.get("_pc_built")):
				_goto(1)
		1: # settle, capture the menu at the launch resolution
			if _frame - _stage_frame > 40:
				if _menu_only:
					_snap("pc_menu_1280x720.png")
					print("[shots] DONE (menu720)")
					quit(0)
				else:
					_snap("pc_menu_1920x1080.png")
					_goto(3)
		3: # settings page
			if _frame - _stage_frame > 30:
				_menu.call("_pc_show_page", "settings")
				_goto(4)
		4:
			if _frame - _stage_frame > 25:
				_snap("pc_settings_1920x1080.png")
				if _menus_only:
					print("[shots] DONE (menus)")
					quit(0)
				_menu.call("_pc_show_page", "main")
				var list: Control = _menu.get("_pc_list_vbox")
				var row := _first_button(list)
				if row != null:
					row.pressed.emit()
				_goto(5)
		5: # chapter running (pause button + crosshair visible)
			var cur: Variant = _main.get("_current_chapter")
			if cur != null and _frame - _stage_frame > 150:
				_snap("pc_chapter_1920x1080.png")
				var pause := root.get_node_or_null("MarigoldPause")
				pause.call("_toggle_pause", "exit_button")
				# The tree is now PAUSED: this script's _process stops
				# being called, so the pause capture rides the render
				# signal instead (frames keep drawing while paused).
				RenderingServer.frame_post_draw.connect(_on_pause_frame)
				_goto(6)
		6: # handled by _on_pause_frame
			pass
	return false


var _pause_frames := 0


func _on_pause_frame() -> void:
	_pause_frames += 1
	if _pause_frames >= 30:
		RenderingServer.frame_post_draw.disconnect(_on_pause_frame)
		_snap("pc_pause_1920x1080.png")
		print("[shots] DONE")
		quit(0)
