## main.gd - MARIGOLD bootstrap: XR init, title screen, chapter flow,
## immersive/AR mode, and Check for Updates UI.
## v0.6.2: staged boot — XR init first, then the menu panel (frame 1 fast);
## MarigoldSky, music streams, and the updater build AFTER first frame or on
## chapter load. The menu uses a flat backdrop; the sky builds on chapter
## load. Mode toggle and time-of-day selector removed from the menu (default
## immersive; flagged in release notes).
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
	"pinta": {"name": "Pinta Alebrijes", "scene": "res://scenes/chapters/pinta.tscn", "mood": "festive",
		"desc": "Paint your own spirit animal - it comes alive", "keyart": "res://assets/keyart/pinta.png"},
	"galeria": {"name": "Galeria de Recuerdos", "scene": "res://scenes/chapters/galeria.tscn", "mood": "wondrous",
		"desc": "Your festival moments, framed in papel picado", "keyart": "res://assets/keyart/galeria.png"},
	"ofrenda_finale": {"name": "Tu Ofrenda", "scene": "res://scenes/chapters/ofrenda_finale.tscn", "mood": "finale",
		"desc": "Your altar of memories - the candle-lit reveal", "keyart": "res://assets/keyart/ofrenda_finale.png"},
}

## Unified pause-nav + menu list order: 5 chapters in story order, then the
## 6 experiences (finale last). PAUSE_MENU_UX §3 — one order everywhere so
## "down the list = Next".
const MENU_ORDER := ["ch1", "ch2", "ch3", "ch4", "ch5", "mano_magica",
		"guitarra", "pinta", "espejo", "galeria", "ofrenda_finale"]

const PROGRESS_FILE := "user://marigold_progress.cfg"

var _sky: MarigoldSky
var _chapter_root: Node3D
var _chapter_index := -1
var _current_chapter: Node3D = null
var _updater: MarigoldUpdater
var _menu: MarigoldMenu
var _pending_apk := ""
var _xr: OpenXRInterface = null
var _current_kind := "" # "chapter" | "exp" - for pause restart
var _current_exp_key := ""
var _music: MarigoldMusic = null


func _ready() -> void:
	MarigoldState.reset()
	_chapter_root = Node3D.new()
	_chapter_root.name = "ChapterRoot"
	add_child(_chapter_root)

	# XR init FIRST: the compositor needs it, and everything after it is
	# staged so frame 1 stays fast.
	_xr = XRServer.find_interface("OpenXR")
	if _xr and _xr.initialize():
		get_viewport().use_xr = true
		$XROrigin3D/XRCamera3D.current = true
	else:
		_xr = null
		push_warning("[MARIGOLD] OpenXR unavailable - desktop fallback")
		$DesktopCamera.current = true

	_build_menu()
	call_deferred("_stage2")


## Stage 2 (deferred, after first frame): music node (streams lazy-load on
## first play) + the update checker. Sky is NOT built here — it builds on
## chapter load, and the menu uses a flat backdrop.
func _stage2() -> void:
	_ensure_music()
	_updater = MarigoldUpdater.new()
	_updater.name = "Updater"
	add_child(_updater)
	_updater.check_completed.connect(_on_check_completed)
	_updater.download_completed.connect(_on_download_completed)
	_updater.download_failed.connect(_on_download_failed)

## ---- lazy singletons ----

func _ensure_music() -> void:
	if _music != null and is_instance_valid(_music):
		return
	_music = MarigoldMusic.new()
	_music.name = "MarigoldMusic"
	add_child(_music)
	MarigoldState.music = _music


## The sky builds on chapter load (never at menu time). Chapters use
## MarigoldSky.instance null-safely.
func _ensure_sky() -> void:
	if _sky != null and is_instance_valid(_sky):
		return
	_sky = MarigoldSky.new()
	_sky.name = "MarigoldSky"
	add_child(_sky)


## ---- Immersive / AR mode ----

func set_ar_mode(on: bool) -> void:
	MarigoldState.ar_mode = on
	if _xr == null:
		return # desktop: visual change only
	if _sky == null:
		return # sky not built yet (menu stage): immersive default stands
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


## ---- 2D menu ----

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
		{"key": "pinta", "name": "Pinta Alebrijes",
			"desc": "Paint your own spirit animal - it comes alive",
			"keyart": "res://assets/keyart/pinta.png"},
		{"key": "galeria", "name": "Galeria de Recuerdos",
			"desc": "Your festival moments, framed in papel picado",
			"keyart": "res://assets/keyart/galeria.png"},
		{"key": "ofrenda_finale", "name": "Tu Ofrenda",
			"desc": "Your altar of memories - the candle-lit reveal",
			"keyart": "res://assets/keyart/ofrenda_finale.png"},
	])
	var prog := _load_progress()
	_menu.set_progress(int(prog.get("current", 0)), prog.get("completed", []))
	var ver: String = ProjectSettings.get_setting("application/config/version", "0.3.0")
	_menu.set_version("v" + ver)
	_menu.chapter_chosen.connect(_on_menu_chapter)
	_menu.experience_chosen.connect(_on_menu_experience)
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


func _load_experience(key: String, via: String = "menu") -> void:
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	_ensure_sky()
	_ensure_music()
	var info: Dictionary = EXPERIENCES[key]
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_start(String(info["name"]), key, via)
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
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_end("completed")
	await get_tree().create_timer(0.8).timeout
	_quit_to_menu()


## ---- Pause / restart / quit (shared pause overlay, v0.5.0) ----

## Wire the pause overlay + controller skins + start legend for a chapter.
func _wire_pause_and_skins(key: String, display_name: String) -> void:
	MarigoldPause.attach(Callable(self, "_restart_current"),
			Callable(self, "_quit_to_menu"), key, display_name)
	_update_pause_nav()
	MarigoldControllerSkins.apply($XROrigin3D, key)
	MarigoldControllerSkins.show_legend(_chapter_root, key, display_name)


## Unified 11-item list order (same as the menu): prev/next wrap around.
func _update_pause_nav() -> void:
	var cur := _current_menu_key()
	var i := MENU_ORDER.find(cur)
	if i < 0:
		MarigoldPause.clear_nav()
		return
	var prev_key: String = MENU_ORDER[(i - 1 + MENU_ORDER.size()) % MENU_ORDER.size()]
	var next_key: String = MENU_ORDER[(i + 1) % MENU_ORDER.size()]
	MarigoldPause.set_nav("◀ " + _item_name(prev_key),
			_item_name(next_key) + " ▶", Callable(self, "_on_pause_nav"))


func _current_menu_key() -> String:
	if _current_kind == "chapter" and _chapter_index >= 0 \
			and _chapter_index < CHAPTERS.size():
		return String(CHAPTERS[_chapter_index]["key"])
	if _current_kind == "exp":
		return _current_exp_key
	return ""


func _item_name(key: String) -> String:
	for c in CHAPTERS:
		if String(c["key"]) == key:
			return String(c["name"])
	if EXPERIENCES.has(key):
		return String(EXPERIENCES[key]["name"])
	return key


func _load_item(key: String, via: String) -> void:
	for i in range(CHAPTERS.size()):
		if String(CHAPTERS[i]["key"]) == key:
			_load_chapter(i, via)
			return
	if EXPERIENCES.has(key):
		_load_experience(key, via)


## Pause-menu Next/Prev: leave the current item for the adjacent one.
func _on_pause_nav(dir: int) -> void:
	var cur := _current_menu_key()
	var i := MENU_ORDER.find(cur)
	if i < 0:
		return
	var target: String = MENU_ORDER[(i + dir + MENU_ORDER.size()) % MENU_ORDER.size()]
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_end("nav")
	_load_item(target, "nav")


func _restart_current() -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_end("restart")
	if _current_kind == "exp" and _current_exp_key != "":
		_load_experience(_current_exp_key, "restart")
	elif _current_kind == "chapter":
		_load_chapter(_chapter_index, "restart")


func _quit_to_menu() -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_end("quit_to_menu")
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	_current_kind = ""
	_current_exp_key = ""
	if MarigoldState.music != null:
		MarigoldState.music.stop()
	MarigoldState.reset()
	if _sky != null and is_instance_valid(_sky):
		_sky.set_gentle_mode(false) # experiences may have requested gentle weather
	MarigoldPause.detach()
	_menu.show_menu()


## ---- Update checker ----

func _on_check_updates() -> void:
	if _updater == null:
		_menu.set_status("Update checker is still loading — try again in a moment.")
		return
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
	if _updater == null:
		return
	_menu.set_status("Downloading update...")
	_updater.download_update()


func _on_download_completed(apk_path: String) -> void:
	_pending_apk = apk_path
	_menu.set_status("Download complete. Tap Install.")
	_menu.offer_install()


func _on_install_update() -> void:
	if _updater == null:
		return
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


func _load_chapter(idx: int, via: String = "menu") -> void:
	if _current_chapter:
		_current_chapter.queue_free()
		_current_chapter = null
	if idx < 0 or idx >= CHAPTERS.size():
		_show_finale_card()
		return
	_ensure_sky()
	_ensure_music()
	var info: Dictionary = CHAPTERS[idx]
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_start(String(info["name"]), String(info["key"]), via)
	_chapter_index = idx
	MarigoldState.chapter_index = idx
	_save_progress(idx)
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
	# Mark the finished chapter, then the scripted flight over the candle-lit
	# town (v0.6.0: replaces the petal-fall fade-to-black between chapters).
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.chapter_end("completed")
	_mark_completed(_chapter_index)
	var next_idx := _chapter_index + 1
	if next_idx < 0 or next_idx >= CHAPTERS.size():
		_load_chapter(next_idx) # journey end card
		return
	var from_name := String(CHAPTERS[_chapter_index]["name"])
	var to_name := String(CHAPTERS[next_idx]["name"])
	_current_chapter.queue_free()
	_current_chapter = null
	var flight := MarigoldFlight.new()
	flight.finished.connect(_on_flight_done.bind(next_idx))
	flight.begin(self, from_name, to_name, 16.0)


func _on_flight_done(next_idx: int) -> void:
	for c in get_children():
		if c is MarigoldFlight:
			c.queue_free()
	_load_chapter(next_idx, "complete")


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
	if MarigoldState.music != null:
		MarigoldState.music.stop()
	if _sky != null and is_instance_valid(_sky):
		_sky.set_gentle_mode(false)
	MarigoldPause.detach()
	_menu.show_finale()
