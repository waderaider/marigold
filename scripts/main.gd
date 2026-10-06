## main.gd - MARIGOLD bootstrap: XR init, title screen, chapter flow,
## immersive/AR mode toggle, and Check for Updates UI.
extends Node3D

const CHAPTERS := [
	{"name": "The Ofrenda", "scene": "res://scenes/chapters/ch1_ofrenda.tscn", "mood": "tender"},
	{"name": "The Marigold Bridge", "scene": "res://scenes/chapters/ch2_bridge.tscn", "mood": "wondrous"},
	{"name": "Plaza de los Alebrijes", "scene": "res://scenes/chapters/ch3_alebrijes.tscn", "mood": "wondrous"},
	{"name": "Papel Picado Canopy", "scene": "res://scenes/chapters/ch4_papel.tscn", "mood": "festive"},
	{"name": "El Gran Baile", "scene": "res://scenes/chapters/ch5_baile.tscn", "mood": "finale"},
]

var _world_env: WorldEnvironment
var _title_root: Node3D
var _chapter_root: Node3D
var _chapter_index := -1
var _current_chapter: Node3D = null
var _updater: MarigoldUpdater
var _status_label: Label3D
var _mode_button_label: Label3D
var _xr: OpenXRInterface = null
var _t := 0.0


func _ready() -> void:
	MarigoldState.reset()
	_world_env = MarigoldFX.make_night_sky(self)
	_chapter_root = Node3D.new()
	_chapter_root.name = "ChapterRoot"
	add_child(_chapter_root)

	var music := MarigoldMusic.new()
	music.name = "MarigoldMusic"
	add_child(music)
	MarigoldState.music = music

	_xr = XRServer.find_interface("OpenXR")
	if _xr and _xr.initialize():
		get_viewport().use_xr = true
		$XROrigin3D/XRCamera3D.current = true
		set_ar_mode(false) # start immersive
	else:
		_xr = null
		push_warning("[MARIGOLD] OpenXR unavailable - desktop fallback")
		$DesktopCamera.current = true

	_build_title()

	_updater = MarigoldUpdater.new()
	_updater.name = "Updater"
	add_child(_updater)
	_updater.check_completed.connect(_on_check_completed)
	_updater.download_completed.connect(_on_download_completed)
	_updater.download_failed.connect(_on_download_failed)


func _process(delta: float) -> void:
	_t += delta
	if _title_root and is_instance_valid(_title_root):
		_title_root.rotation.y = sin(_t * 0.1) * 0.05


## ---- Immersive / AR mode ----

func set_ar_mode(on: bool) -> void:
	MarigoldState.ar_mode = on
	if _mode_button_label:
		_mode_button_label.text = "Mode: AR Living Room" if on else "Mode: Immersive World"
	if _xr == null:
		return # desktop: visual change only
	if on and _xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
		get_viewport().transparent_bg = true
		_world_env.environment.background_mode = Environment.BG_COLOR
		_world_env.environment.background_color = Color(0, 0, 0, 0)
		_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		get_viewport().transparent_bg = false
		_world_env.environment.background_mode = Environment.BG_SKY
		_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	# If a chapter is active, let it re-layout for the new mode.
	if _current_chapter and _current_chapter.has_method("apply_mode"):
		_current_chapter.apply_mode(on)


## ---- Title screen ----

func _build_title() -> void:
	_title_root = Node3D.new()
	_title_root.name = "TitleRoot"
	_title_root.position = Vector3(0, 0, -2.5)
	add_child(_title_root)

	# Marigold field + god rays for the wow backdrop.
	MarigoldFX.make_marigold_field(_title_root, 260, 10.0)
	MarigoldFX.make_god_ray(_title_root, Vector3(0, 0, -3), 9.0)
	MarigoldFX.make_god_ray(_title_root, Vector3(-4, 0, -5), 9.0, Color(1.0, 0.5, 0.7))
	MarigoldFX.spawn_ambient_motes(_title_root, Vector3(0, 1.5, 0), 4.0, 60)
	MarigoldFX.make_luminous_water(_title_root, 40.0).position.y = -0.05

	var title := MarigoldFX.make_label("MARIGOLD", 160, Color(1.0, 0.72, 0.25))
	title.position = Vector3(0, 2.6, 0)
	_title_root.add_child(title)
	var sub := MarigoldFX.make_label("A Dia de Muertos Journey", 72, Color(1.0, 0.9, 0.75))
	sub.position = Vector3(0, 2.05, 0)
	_title_root.add_child(sub)
	var hint := MarigoldFX.make_label("A 10-minute guided journey in 5 chapters", 48, Color(0.85, 0.8, 0.9))
	hint.position = Vector3(0, 1.65, 0)
	_title_root.add_child(hint)

	_make_button("Begin Journey", Vector3(0, 1.0, 0), _on_begin)
	_mode_button_label = _make_button("Mode: Immersive World", Vector3(0, 0.45, 0), _on_toggle_mode)
	_make_button("Check for Updates", Vector3(0, -0.1, 0), _on_check_updates)

	var ver: String = ProjectSettings.get_setting("application/config/version", "0.1.0")
	_status_label = MarigoldFX.make_label("v" + ver, 40, Color(0.7, 0.7, 0.8))
	_status_label.position = Vector3(0, -0.55, 0)
	_title_root.add_child(_status_label)


func _make_button(text: String, pos: Vector3, callback: Callable, parent: Node3D = null) -> Label3D:
	var host: Node3D = parent if parent != null else _title_root
	var root := Node3D.new()
	root.position = pos
	host.add_child(root)
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 0.32, 0.08)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = MarigoldFX.pbr(Color(0.35, 0.12, 0.05), 0.3, 0.4)
	root.add_child(mi)
	# Glowing marigold edge.
	var edge := BoxMesh.new()
	edge.size = Vector3(1.54, 0.05, 0.085)
	var edge_mi := MeshInstance3D.new()
	edge_mi.mesh = edge
	edge_mi.material_override = MarigoldFX.glow(Color(1.0, 0.6, 0.12), 1.2)
	edge_mi.position.y = 0.16
	root.add_child(edge_mi)
	var label := MarigoldFX.make_label(text, 56, Color(1, 1, 1))
	label.position.z = 0.06
	root.add_child(label)
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 0.32, 0.3)
	col.shape = shape
	area.add_child(col)
	root.add_child(area)
	area.input_event.connect(_on_button_input.bind(callback, root))
	return label


func _on_button_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int, callback: Callable, _root: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		callback.call()


func _on_begin() -> void:
	_title_root.queue_free()
	_title_root = null
	MarigoldState.journey_started = true
	_load_chapter(0)


func _on_toggle_mode() -> void:
	set_ar_mode(not MarigoldState.ar_mode)


## ---- Update checker ----

func _on_check_updates() -> void:
	_status_label.text = "Checking for updates..."
	_updater.check_for_updates()


func _on_check_completed(has_update: bool, latest_version: String, changelog: String) -> void:
	var ver: String = ProjectSettings.get_setting("application/config/version", "0.1.0")
	if has_update:
		_status_label.text = "v" + ver + " -> v" + latest_version + " available!\n" + changelog.split("\n")[0]
		_make_button("Download v" + latest_version, Vector3(0, -1.0, 0), _on_download_update)
	else:
		_status_label.text = "v" + ver + " is up to date."


func _on_download_update() -> void:
	_status_label.text = "Downloading update..."
	_updater.download_update()


func _on_download_completed(apk_path: String) -> void:
	_status_label.text = "Download complete. Tap Install."
	_make_button("Install Update", Vector3(0, -1.45, 0), _on_install_update.bind(apk_path))


func _on_install_update(apk_path: String) -> void:
	if _updater.install_update(apk_path):
		_status_label.text = "Opening installer..."
	else:
		_status_label.text = "Install only works on Android."


func _on_download_failed(error: String) -> void:
	_status_label.text = "Download failed: " + error


## ---- Chapter flow ----

func _load_chapter(idx: int) -> void:
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	if idx < 0 or idx >= CHAPTERS.size():
		_show_finale_card()
		return
	_chapter_index = idx
	MarigoldState.chapter_index = idx
	var info: Dictionary = CHAPTERS[idx]
	var scene: PackedScene = load(info["scene"])
	_current_chapter = scene.instantiate()
	_chapter_root.add_child(_current_chapter)
	if _current_chapter.has_method("setup"):
		_current_chapter.setup(MarigoldState.ar_mode)
	if _current_chapter.has_signal("chapter_complete"):
		_current_chapter.chapter_complete.connect(_on_chapter_complete)
	MarigoldState.music.play_mood(info["mood"])
	MarigoldFX.scatter_petals(_chapter_root, Vector3(0, 1.5, -2), 40)


func _on_chapter_complete() -> void:
	# Brief beat, then next chapter.
	await get_tree().create_timer(1.2).timeout
	_load_chapter(_chapter_index + 1)


func _show_finale_card() -> void:
	MarigoldState.music.stop()
	var root := Node3D.new()
	root.position = Vector3(0, 1.6, -2.5)
	add_child(root)
	var t := MarigoldFX.make_label("Gracias por celebrar", 110, Color(1.0, 0.8, 0.4))
	root.add_child(t)
	var s := MarigoldFX.make_label("Dia de Muertos honra a quienes amamos.\nHasta el proximo ano.", 56, Color(1, 0.95, 0.85))
	s.position.y = -0.7
	root.add_child(s)
	MarigoldFX.scatter_petals(root, Vector3.ZERO, 80)
	_make_button("Journey Again", Vector3(0, -1.4, 0), _on_restart, root)


func _on_restart() -> void:
	# Clear the finale card (it is the only child besides managed roots).
	for c in get_children():
		if c is Node3D and c.name != "ChapterRoot" and c.name != "XROrigin3D" and c.name != "DesktopCamera":
			c.queue_free()
	MarigoldState.reset()
	_load_chapter(0)
