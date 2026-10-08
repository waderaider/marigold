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

const EXPERIENCES := {
	"guitarra": {"name": "Guitarra Mexicana", "scene": "res://scenes/chapters/guitarra.tscn", "mood": "festive"},
}

var _world_env: WorldEnvironment
var _title_root: Node3D
var _chapter_root: Node3D
var _chapter_index := -1
var _current_chapter: Node3D = null
var _updater: MarigoldUpdater
var _menu: MarigoldMenu
var _pending_apk := ""
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

	_build_backdrop()
	_build_menu()

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
	if _menu:
		_menu.set_mode(on)
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


## ---- Backdrop + 2D menu ----

func _build_backdrop() -> void:
	# 3D wow-backdrop behind the 2D menu: marigold field, god rays, motes.
	_title_root = Node3D.new()
	_title_root.name = "TitleRoot"
	_title_root.position = Vector3(0, 0, -2.5)
	add_child(_title_root)

	MarigoldModels.make_flower_field(_title_root, 200, 10.0, 2026)
	MarigoldFX.make_god_ray(_title_root, Vector3(0, 0, -3), 9.0)
	MarigoldFX.make_god_ray(_title_root, Vector3(-4, 0, -5), 9.0, Color(1.0, 0.5, 0.7))
	MarigoldFX.spawn_ambient_motes(_title_root, Vector3(0, 1.5, 0), 4.0, 60)
	MarigoldFX.make_luminous_water(_title_root, 40.0).position.y = -0.05


func _build_menu() -> void:
	_menu = MarigoldMenu.new()
	_menu.name = "MenuRoot"
	add_child(_menu)
	_menu.set_chapters(CHAPTERS)
	_menu.set_experiences([{"key": "guitarra", "name": "Guitarra Mexicana"}])
	var ver: String = ProjectSettings.get_setting("application/config/version", "0.3.0")
	_menu.set_version("v" + ver)
	_menu.set_mode(MarigoldState.ar_mode)
	_menu.chapter_chosen.connect(_on_menu_chapter)
	_menu.experience_chosen.connect(_on_menu_experience)
	_menu.mode_toggled.connect(_on_toggle_mode)
	_menu.updates_requested.connect(_on_check_updates)
	_menu.download_requested.connect(_on_download_update)
	_menu.install_requested.connect(_on_install_update)


func _on_menu_chapter(idx: int) -> void:
	# Full select -> load path: reset journey state, hide the menu,
	# then start the chapter. This is the path the bug report broke.
	MarigoldState.reset()
	_menu.hide_menu()
	MarigoldState.journey_started = true
	_load_chapter(idx)


func _on_menu_experience(key: String) -> void:
	if not EXPERIENCES.has(key):
		return
	MarigoldState.reset()
	_menu.hide_menu()
	MarigoldState.journey_started = true
	_load_experience(key)


func _load_experience(key: String) -> void:
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	var info: Dictionary = EXPERIENCES[key]
	var scene: PackedScene = load(info["scene"])
	_current_chapter = scene.instantiate()
	_chapter_root.add_child(_current_chapter)
	if _current_chapter.has_method("setup"):
		_current_chapter.setup(MarigoldState.ar_mode)
	if _current_chapter.has_signal("chapter_complete"):
		_current_chapter.chapter_complete.connect(_on_experience_complete)
	MarigoldState.music.play_mood(info["mood"])


func _on_experience_complete() -> void:
	# Experiences return to the menu instead of advancing the journey.
	await get_tree().create_timer(0.8).timeout
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	MarigoldState.music.stop()
	MarigoldState.reset()
	_menu.show_menu()


func _on_toggle_mode() -> void:
	set_ar_mode(not MarigoldState.ar_mode)


## ---- Update checker ----

func _on_check_updates() -> void:
	_menu.set_status("Checking for updates...")
	_menu.clear_update_buttons()
	_updater.check_for_updates()


func _on_check_completed(has_update: bool, latest_version: String, changelog: String) -> void:
	var ver: String = ProjectSettings.get_setting("application/config/version", "0.3.0")
	if has_update:
		_menu.set_status("v" + ver + " -> v" + latest_version + " available!\n" + changelog.split("\n")[0])
		_menu.offer_download(latest_version)
	else:
		_menu.set_status("v" + ver + " is up to date.")


func _on_download_update() -> void:
	_menu.set_status("Downloading update...")
	_updater.download_update()


func _on_download_completed(apk_path: String) -> void:
	_pending_apk = apk_path
	_menu.set_status("Download complete. Tap Install.")
	_menu.offer_install()


func _on_install_update() -> void:
	if _pending_apk != "" and _updater.install_update(_pending_apk):
		_menu.set_status("Opening installer...")
	else:
		_menu.set_status("Install only works on Android.")


func _on_download_failed(error: String) -> void:
	_menu.set_status("Download failed: " + error)


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
	_menu.show_finale()
	MarigoldFX.scatter_petals(_title_root, Vector3(0, 1.5, 0), 80)
