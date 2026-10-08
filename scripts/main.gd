## main.gd - MARIGOLD bootstrap: XR init, title screen, chapter flow,
## immersive/AR mode toggle, and Check for Updates UI.
extends Node3D

const CHAPTERS := [
	{"key": "ch1", "name": "The Ofrenda", "scene": "res://scenes/chapters/ch1_ofrenda.tscn", "mood": "tender",
		"desc": "Build the offering of petals, photos and candles", "keyart": "res://assets/keyart/ch1_ofrenda.png"},
	{"key": "ch2", "name": "The Marigold Bridge", "scene": "res://scenes/chapters/ch2_bridge.tscn", "mood": "wondrous",
		"desc": "Cross the glowing bridge over luminous water", "keyart": "res://assets/keyart/ch2_bridge.png"},
	{"key": "ch3", "name": "Plaza de los Alebrijes", "scene": "res://scenes/chapters/ch3_alebrijes.tscn", "mood": "wondrous",
		"desc": "Meet the glowing spirit-animal guides", "keyart": "res://assets/keyart/ch3_alebrijes.png"},
	{"key": "ch4", "name": "Papel Picado Canopy", "scene": "res://scenes/chapters/ch4_papel.tscn", "mood": "festive",
		"desc": "Wave your hands through cut-paper banners", "keyart": "res://assets/keyart/ch4_papel.png"},
	{"key": "ch5", "name": "El Gran Baile", "scene": "res://scenes/chapters/ch5_baile.tscn", "mood": "finale",
		"desc": "Follow the leader in the grand dance finale", "keyart": "res://assets/keyart/ch5_baile.png"},
]

const EXPERIENCES := {
	"guitarra": {"name": "Guitarra Mexicana", "scene": "res://scenes/chapters/guitarra.tscn", "mood": "festive",
		"desc": "Rhythm-strum folk guitar - two original songs", "keyart": "res://assets/keyart/guitarra.png"},
	"mano_magica": {"name": "Mano Magica", "scene": "res://scenes/chapters/mano_magica.tscn", "mood": "wondrous",
		"desc": "A guided hand-tracking tour: pinch, grab, throw, sculpt", "keyart": "res://assets/keyart/mano_magica.png"},
	"espejo": {"name": "Gran Baile: Espejo", "scene": "res://scenes/chapters/espejo.tscn", "mood": "finale",
		"desc": "Mirror dance - your real moves, body tracked", "keyart": "res://assets/keyart/espejo.png"},
}

const PROGRESS_FILE := "user://marigold_progress.cfg"

var _sky: MarigoldSky
var _title_root: Node3D
var _chapter_root: Node3D
var _chapter_index := -1
var _current_chapter: Node3D = null
var _updater: MarigoldUpdater
var _menu: MarigoldMenu
var _pending_apk := ""
var _xr: OpenXRInterface = null
var _t := 0.0
var _current_kind := "" # "chapter" | "exp" - for pause restart
var _current_exp_key := ""


func _ready() -> void:
	MarigoldState.reset()
	# Living sky: day/night cycle, weather, wind. Replaces the old static night sky.
	_sky = MarigoldSky.new()
	_sky.name = "MarigoldSky"
	add_child(_sky)
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
		_sky.world_env.environment.background_mode = Environment.BG_COLOR
		_sky.world_env.environment.background_color = Color(0, 0, 0, 0)
		_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	else:
		get_viewport().transparent_bg = false
		_sky.world_env.environment.background_mode = Environment.BG_SKY
		_xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	_sky.set_ar_mode(on)
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
	_menu.set_experiences([
		{"key": "guitarra", "name": "Guitarra Mexicana",
			"desc": "Rhythm-strum folk guitar - two original songs",
			"keyart": "res://assets/keyart/guitarra.png"},
		{"key": "mano_magica", "name": "Mano Magica",
			"desc": "A guided hand-tracking tour: pinch, grab, throw, sculpt",
			"keyart": "res://assets/keyart/mano_magica.png"},
		{"key": "espejo", "name": "Gran Baile: Espejo",
			"desc": "Mirror dance - your real moves, body tracked",
			"keyart": "res://assets/keyart/espejo.png"},
	])
	var prog := _load_progress()
	_menu.set_progress(int(prog.get("current", 0)), prog.get("completed", []))
	var ver: String = ProjectSettings.get_setting("application/config/version", "0.3.0")
	_menu.set_version("v" + ver)
	_menu.set_mode(MarigoldState.ar_mode)
	_menu.chapter_chosen.connect(_on_menu_chapter)
	_menu.experience_chosen.connect(_on_menu_experience)
	_menu.mode_toggled.connect(_on_toggle_mode)
	_menu.updates_requested.connect(_on_check_updates)
	_menu.download_requested.connect(_on_download_update)
	_menu.install_requested.connect(_on_install_update)
	_menu.time_mode_chosen.connect(_on_time_mode)


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
	_current_kind = "exp"
	_current_exp_key = key
	_wire_pause_and_skins(key, String(info["name"]))


func _on_experience_complete() -> void:
	# Experiences return to the menu instead of advancing the journey.
	await get_tree().create_timer(0.8).timeout
	_quit_to_menu()


## ---- Pause / restart / quit (shared pause overlay, v0.5.0) ----

## Wire the pause overlay + controller skins + start legend for a chapter.
func _wire_pause_and_skins(key: String, display_name: String) -> void:
	MarigoldPause.attach(Callable(self, "_restart_current"), Callable(self, "_quit_to_menu"), key)
	MarigoldControllerSkins.apply($XROrigin3D, key)
	MarigoldControllerSkins.show_legend(_chapter_root, key, display_name)


func _restart_current() -> void:
	if _current_kind == "exp" and _current_exp_key != "":
		_load_experience(_current_exp_key)
	elif _current_kind == "chapter":
		_load_chapter(_chapter_index)


func _quit_to_menu() -> void:
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	_current_kind = ""
	_current_exp_key = ""
	MarigoldState.music.stop()
	MarigoldState.reset()
	if _sky:
		_sky.set_gentle_mode(false) # experiences may have requested gentle weather
	MarigoldPause.detach()
	_menu.show_menu()


func _on_toggle_mode() -> void:
	set_ar_mode(not MarigoldState.ar_mode)


func _on_time_mode(mode: String) -> void:
	if _sky:
		_sky.set_time_mode(mode)


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

## Petal-fall transition: a curtain of petals falls in front of the player
## (no hard cuts between chapters, v0.5.0).
func _petal_transition() -> void:
	var cam := get_viewport().get_camera_3d()
	var center := Vector3(0, 0, -2.0)
	if cam != null:
		center = cam.global_position + (-cam.global_transform.basis.z) * 1.6
		center.y = 0.0
	MarigoldFX.petal_ceiling_fall(self, center, 2.2, 90, 2.2, 2.6)
	await get_tree().create_timer(1.1).timeout


func _load_chapter(idx: int) -> void:
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	if idx < 0 or idx >= CHAPTERS.size():
		_show_finale_card()
		return
	_chapter_index = idx
	MarigoldState.chapter_index = idx
	_save_progress(idx)
	var info: Dictionary = CHAPTERS[idx]
	var scene: PackedScene = load(info["scene"])
	_current_chapter = scene.instantiate()
	_chapter_root.add_child(_current_chapter)
	if _current_chapter.has_method("setup"):
		_current_chapter.setup(MarigoldState.ar_mode)
	if _current_chapter.has_signal("chapter_complete"):
		_current_chapter.chapter_complete.connect(_on_chapter_complete)
	MarigoldState.music.play_mood(info["mood"])
	_current_kind = "chapter"
	_wire_pause_and_skins(String(info["key"]), String(info["name"]))
	MarigoldFX.scatter_petals(_chapter_root, Vector3(0, 1.5, -2), 40)


func _on_chapter_complete() -> void:
	# Mark the finished chapter, then a petal-fall beat before the next.
	_mark_completed(_chapter_index)
	await _petal_transition()
	_load_chapter(_chapter_index + 1)


## ---- Journey progress (Continue Journey, v0.5.0) ----

func _load_progress() -> Dictionary:
	var cfg := ConfigFile.new()
	var res := {"current": 0, "completed": []}
	if cfg.load(PROGRESS_FILE) != OK:
		return res
	res["current"] = int(cfg.get_value("journey", "current", 0))
	var done: Array = []
	for x in cfg.get_value("journey", "completed", []):
		done.append(int(x))
	res["completed"] = done
	return res


func _save_progress(idx: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_FILE) # keep completed list
	cfg.set_value("journey", "current", idx)
	cfg.save(PROGRESS_FILE)
	_refresh_menu_progress()


func _mark_completed(idx: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_FILE)
	var done: Array = []
	for x in cfg.get_value("journey", "completed", []):
		done.append(int(x))
	if not done.has(idx):
		done.append(idx)
	cfg.set_value("journey", "completed", done)
	cfg.set_value("journey", "current", mini(idx + 1, CHAPTERS.size() - 1))
	cfg.save(PROGRESS_FILE)
	_refresh_menu_progress()


func _refresh_menu_progress() -> void:
	if _menu == null:
		return
	var prog := _load_progress()
	_menu.set_progress(int(prog.get("current", 0)), prog.get("completed", []))


func _show_finale_card() -> void:
	MarigoldState.music.stop()
	if _sky:
		_sky.set_gentle_mode(false)
	MarigoldPause.detach()
	_menu.show_finale()
	MarigoldFX.scatter_petals(_title_root, Vector3(0, 1.5, 0), 80)
