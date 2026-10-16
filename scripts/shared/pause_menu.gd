## MarigoldPause.gd - shared pause/exit overlay (autoload, v0.5.0).
## SHIP-BLOCKER: every chapter + experience gets pause/exit through:
##   1. the controller menu button (OpenXR "menu_button" action / Esc),
##   2. a small floating on-screen exit button (opens the overlay, never
##      quits directly).
## v0.7.0 rework (wade's order): flat 2D GRID of cards (3 cols, 11 cards,
## no scroll) + Settings page one tap away. Static placement contract.
## v0.6.2: simplified 2D list (superseded) — Continuar (Resume, green) / Controles
## (Controls, blue) / Reiniciar (Restart, orange) / Prev/Next nav row (NEW) /
## SALIR AL INICIO (EXIT) (red, full-width, bottom, unmissable). The pause
## title shows the current chapter/experience name so Restart's target is
## obvious. Belt-and-suspenders input: XRUIPointer primary path + DirectUIInput
## fallback (own yellow beams), one deduped click funnel; gaze dwell fires
## only when NO beam is drawn by either path.
## Pause freezes gameplay via get_tree().paused; this node runs
## PROCESS_MODE_ALWAYS so the overlay stays alive. Ambience audio is ducked.
## Chapters need ZERO changes: main.gd calls attach()/detach().
extends Node3D

## v0.8.0: emitted when the pause overlay opens/closes (main.gd uses it to
## release/re-capture the mouse in PC mode).
signal pause_toggled(open: bool)

const EXIT_VP := Vector2i(160, 160)
const EXIT_SIZE := Vector2(0.17, 0.17)
## v0.7.0 grid spec (UI_SPECIALIST_V0110 §1.3): 900x1000 viewport, 3-col
## grid, 11 cards, no scroll. Panel placed ONCE per open, then STATIC.
const PANEL_VP := Vector2(900, 1000)
const PANEL_SIZE := Vector2(1.32, 1.47)
const PANEL_DISTANCE := 1.8
const DWELL_TIME := 1.2
const CLICK_DEDUPE_MS := 120
const CLICK_DEDUPE_PX := 8.0

const C_MARIGOLD := Color(1.0, 0.68, 0.18)
const C_CREAM := Color(1.0, 0.93, 0.82)
const C_PLUM := Color(0.16, 0.05, 0.14, 0.96)
const C_PLUM_LIGHT := Color(0.28, 0.10, 0.22, 0.96)
const C_PINK := Color(1.0, 0.35, 0.55)
const C_GREEN := Color(0.25, 0.75, 0.35)
const C_BLUE := Color(0.30, 0.55, 1.0)
const C_ORANGE := Color(1.0, 0.60, 0.15)
const C_RED := Color(0.95, 0.20, 0.15)
const C_STEEL := Color(0.45, 0.55, 0.75)

## The 11 pause-grid cards: 5 chapters + 6 experiences (same order as the
## launcher menu; main.gd MENU_ORDER). The grid IS the chapter picker.
const MENU_ITEMS := [
	{"key": "ch1", "name": "The Ofrenda", "mood": "tender"},
	{"key": "ch2", "name": "The Marigold Bridge", "mood": "wondrous"},
	{"key": "ch3", "name": "Plaza de los Alebrijes", "mood": "wondrous"},
	{"key": "ch4", "name": "Papel Picado Canopy", "mood": "festive"},
	{"key": "ch5", "name": "El Gran Baile", "mood": "finale"},
	{"key": "mano_magica", "name": "Mano Magica", "mood": "wondrous"},
	{"key": "guitarra", "name": "Guitarra Mexicana", "mood": "festive"},
	{"key": "pinta", "name": "Pinta Alebrijes", "mood": "festive"},
	{"key": "espejo", "name": "Gran Baile: Espejo", "mood": "finale"},
	{"key": "galeria", "name": "Galeria de Recuerdos", "mood": "wondrous"},
	{"key": "ofrenda_finale", "name": "Tu Ofrenda", "mood": "finale"},
]
## Chip color per chapter mood (UI_SPECIALIST_V0110 §1.3). No new assets.
const MOOD_COLOR := {
	"tender": Color(1.0, 0.80, 0.30), # warm gold
	"wondrous": Color(1.0, 0.62, 0.11), # marigold orange
	"festive": Color(1.0, 0.35, 0.55), # pink
	"finale": Color(0.85, 0.16, 0.12), # deep red
}

var _attached := false
var _pause_open := false
var _restart_cb := Callable()
var _quit_cb := Callable()
var _legend_key := ""
var _title_text := ""
var _menu_was_pressed := false
var _cooldown := 0.0
const MENU_HOLD_MSEC := 450  # v0.7.0: universal 0.45s hold-to-pause (QA §1.3)
var _menu_hold_start := 0  # msec when the current menu press began
var _menu_holding := false  # true while a hold is in progress (owns _dwell_ring)

var _xr_origin: Node3D = null
var _controllers: Array[XRController3D] = []

var _exit_root: Node3D
var _exit_viewport: SubViewport
var _exit_quad: MeshInstance3D
var _exit_pointers: Array[XRUIPointer] = []

var _panel_root: Node3D
var _panel_viewport: SubViewport
var _panel_quad: MeshInstance3D
var _panel_pointers: Array[XRUIPointer] = []
var _panel_stack: Control # main page
var _legend_page: Control # controls legend page
var _legend_lines: Label
var _title_label: Label
var _nav_row: HBoxContainer
var _nav_prev: Button
var _nav_next: Button
var _nav_cb := Callable()
var _jump_cb := Callable()
var _current_key := ""
var _cards := {}
var _page_settings: Control
var _setting_value_btns := {}
var _direct: DirectUIInput = null
# v0.8.0: mode-switch note (restart required — shown under the rows).
var _mode_note: Label = null
var _mode_note_text := ""

var _dwell_t := 0.0
var _dwell_pos := Vector2.ZERO
var _dwell_ring: MeshInstance3D

var _last_click_msec := 0
var _last_click_pos := Vector2(-9999, -9999)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_exit_button()
	_build_panel()
	_build_direct_input()
	_panel_root.visible = false
	_exit_root.visible = false


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	var xr := false
	var vp := get_viewport()
	if vp != null:
		xr = vp.use_xr
	var hide_hands := MarigoldGfx.controllers_only() or MarigoldGfx.mouse_only()
	var hide_ctl := MarigoldGfx.hands_only() or MarigoldGfx.mouse_only()
	for p in _exit_pointers + _panel_pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
			# v0.7.0 Settings: input-method preference is real — the
			# non-preferred path's beams stay hidden.
			var is_hand := p.hand_side != 0
			p.enabled = not ((hide_hands and is_hand) or (hide_ctl and not is_hand))
	if _direct != null and is_instance_valid(_direct):
		_direct.input_filter = MarigoldGfx.input_pref()
	if _direct != null and is_instance_valid(_direct):
		_direct.xr_mode = xr
	_update_menu_button()
	if not _attached:
		return
	if _pause_open:
		_update_gaze(delta, _panel_viewport, _panel_quad)
	else:
		_update_exit_follow()
		_update_gaze(delta, _exit_viewport, _exit_quad)


func _input(event: InputEvent) -> void:
	# Desktop: Esc toggles pause.
	if event.is_action_pressed("ui_cancel"):
		if _attached and _cooldown <= 0.0:
			_cooldown = 0.4
			_toggle_pause("esc")
		return
	if not _attached:
		return
	# Desktop mouse fallback into whichever UI is visible (XR pointers quiet).
	if _any_pointer_live():
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			# Real desktop mouse click -> mouse input method.
			_note_input_method("mouse")
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		if _pause_open and _panel_quad != null:
			_forward_mouse(event as InputEventMouse, cam, _panel_quad, _panel_viewport, PANEL_VP)
		elif not _pause_open and _exit_quad != null and _exit_root.visible:
			_forward_mouse(event as InputEventMouse, cam, _exit_quad, _exit_viewport, Vector2(EXIT_VP))


## ---- public API (called by main.gd) ----

func attach(restart: Callable, quit: Callable, legend_key: String = "",
		title: String = "") -> void:
	_restart_cb = restart
	_quit_cb = quit
	_legend_key = legend_key
	_title_text = title
	_attached = true
	_pause_open = false
	clear_nav() # fresh attach = fresh nav state (main re-sets it after)
	_jump_cb = Callable()
	_current_key = legend_key
	_panel_root.visible = false
	_exit_root.visible = true
	if _title_label != null:
		_title_label.text = "Pausa — " + (title if title != "" else "La Plaza")
	_mark_current_card()
	_refresh_all_settings()
	if _direct != null:
		_direct.set_target(_exit_viewport, _exit_quad)
	# The main scene exists now (autoloads ready before it): wire controllers.
	_ensure_origin()
	_add_controller_pointers(_exit_pointers, _exit_viewport, _exit_quad)
	_add_controller_pointers(_panel_pointers, _panel_viewport, _panel_quad)


func detach() -> void:
	_attached = false
	if _pause_open:
		_resume()
	_exit_root.visible = false
	_panel_root.visible = false


func is_pause_open() -> bool:
	return _pause_open


## Pause-menu Next/Prev row (v0.6.2, PAUSE_MENU_UX §1): walks the same 11-item
## list order as the launcher menu, wrapping around.
func set_nav(prev_label: String, next_label: String, nav_cb: Callable) -> void:
	_nav_cb = nav_cb
	_nav_prev.text = prev_label
	_nav_next.text = next_label
	_nav_row.visible = true


func clear_nav() -> void:
	_nav_cb = Callable()
	_jump_cb = Callable()
	_nav_row.visible = false


## ---- pause state ----

## via: "menu_hold" | "exit_button" | "esc" (QA_PLAN_V0110 §1.3:
## the next telemetry digest must tell accidental taps from real opens).
func _toggle_pause(via: String = "menu_hold") -> void:
	if _pause_open:
		_resume()
	else:
		_open(via)


func _open(via: String = "menu_hold") -> void:
	if not _attached or _pause_open:
		return
	_pause_open = true
	get_tree().paused = true
	_duck_audio(true)
	_exit_root.visible = false
	_place_panel()
	_panel_root.visible = true
	_show_main_page()
	_dwell_t = 0.0
	if _direct != null:
		_direct.set_target(_panel_viewport, _panel_quad)
	MarigoldHaptics.confirm()
	# v0.6.1: gameplay telemetry — pause opens feed "where do players pause".
	# v0.7.0: "via" attributes the source (menu_hold/exit_button/esc).
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event("pause_open", {"chapter": gt.current_chapter(), "via": via})
	# v0.8.0 honest gating: dim the Espejo card in PC mode (needs a
	# headset). Applied at open — launch mode isn't known at _ready time.
	if _cards.has("espejo"):
		var ec := _cards["espejo"] as Button
		if ec != null:
			ec.modulate = Color(1, 1, 1, 0.45) \
					if MarigoldState.is_pc_mode() else Color.WHITE
	pause_toggled.emit(true)


func _resume() -> void:
	if not _pause_open:
		return
	_pause_open = false
	get_tree().paused = false
	_duck_audio(false)
	_panel_root.visible = false
	if _direct != null:
		_direct.set_target(_exit_viewport, _exit_quad)
	if _attached:
		_exit_root.visible = true
	MarigoldHaptics.confirm()
	pause_toggled.emit(false)


func _on_restart() -> void:
	_resume()
	if _restart_cb.is_valid():
		_restart_cb.call()


func _on_quit() -> void:
	_resume()
	if _quit_cb.is_valid():
		_quit_cb.call()


func _on_nav(dir: int) -> void:
	if _nav_cb.is_valid():
		_resume()
		_nav_cb.call(dir)


func _duck_audio(on: bool) -> void:
	var st := get_tree().root.get_node_or_null("MarigoldState")
	if st == null:
		return
	var m = st.get("music")
	if m != null and m.has_method("set_ducked"):
		m.call("set_ducked", on)


## Controller menu button (OpenXR "menu_button" action) with a 0.45s HOLD
## to open pause; sub-threshold taps are ignored (QA_PLAN_V0110 §1.3,
## NO-SHIP §3.1.8 - the Neon Duel pause-spam fix, universal across both
## apps). Unpausing via the menu button stays a rising edge (closing is
## always snappy); Esc stays instant (via="esc"). While holding, the dwell
## ring shows fill progress at the ❚❚ button.
func _update_menu_button() -> void:
	if not _attached:
		_menu_was_pressed = false
		_menu_holding = false
		return
	var pressed := false
	if InputMap.has_action("menu_button") and Input.is_action_pressed("menu_button"):
		pressed = true
	if not pressed:
		_ensure_origin()
		for ctl in _controllers:
			if is_instance_valid(ctl) and ctl.is_button_pressed("menu_button"):
				pressed = true
				break
	if not _pause_open and _cooldown <= 0.0:
		# Closed: hold 0.45s to open. Taps are ignored.
		if pressed and not _menu_was_pressed:
			_menu_hold_start = Time.get_ticks_msec()
			_menu_holding = true
		elif pressed and _menu_was_pressed and _menu_holding:
			var held := int(Time.get_ticks_msec()) - _menu_hold_start
			_show_menu_hold_ring(clampf(float(held) / float(MENU_HOLD_MSEC), 0.0, 1.0))
			if held >= MENU_HOLD_MSEC:
				_menu_holding = false
				_hide_menu_hold_ring()
				_toggle_pause("menu_hold")
		elif not pressed and _menu_was_pressed:
			# Released early: tap ignored (the pause-spam fix).
			_menu_holding = false
			_hide_menu_hold_ring()
	elif pressed and not _menu_was_pressed and _cooldown <= 0.0:
		# Pause already open: menu button unpauses on a rising edge.
		_cooldown = 0.4
		_toggle_pause("menu_hold")
	_menu_was_pressed = pressed


## Hold-progress ring: reuses _dwell_ring, parked at the ❚❚ exit quad
## while the menu button is held (mirrors NEXUS pause_exit's fill ring).
func _show_menu_hold_ring(prog: float) -> void:
	if _exit_root != null and is_instance_valid(_exit_root):
		_exit_root.visible = true
	if _dwell_ring != null and is_instance_valid(_dwell_ring) \
			and _exit_quad != null and is_instance_valid(_exit_quad):
		_dwell_ring.global_position = _exit_quad.global_position \
				+ _exit_quad.global_transform.basis.z * 0.005
		_dwell_ring.scale = Vector3.ONE * (0.4 + prog * 1.6)
		_dwell_ring.visible = true


func _hide_menu_hold_ring() -> void:
	if _dwell_ring != null and is_instance_valid(_dwell_ring):
		_dwell_ring.visible = false


func _ensure_origin() -> void:
	if _xr_origin != null and is_instance_valid(_xr_origin):
		return
	_xr_origin = get_tree().root.get_node_or_null("Main/XROrigin3D") as Node3D
	_controllers.clear()
	if _xr_origin != null:
		for side in ["LeftController", "RightController"]:
			var ctl := _xr_origin.get_node_or_null(side) as XRController3D
			if ctl != null:
				_controllers.append(ctl)


## Add one controller laser pointer per tracked controller (idempotent).
func _add_controller_pointers(arr: Array[XRUIPointer], viewport: SubViewport,
		quad: MeshInstance3D) -> void:
	for ctl in _controllers:
		var has := false
		for p in arr:
			if is_instance_valid(p) and p.controller == ctl:
				has = true
				break
		if has:
			continue
		var p := XRUIPointer.new()
		p.controller = ctl
		p.setup(viewport, quad, _xr_origin)
		p.xr_clicked.connect(_on_pointer_clicked.bind(p))
		p.xr_moved.connect(_on_pointer_moved.bind(p))
		add_child(p)
		arr.append(p)


## ---- exit button (floating, opens pause - never quits directly) ----

func _build_exit_button() -> void:
	_exit_root = Node3D.new()
	_exit_root.name = "ExitButton"
	add_child(_exit_root)

	_exit_viewport = SubViewport.new()
	_exit_viewport.size = EXIT_VP
	_exit_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_exit_viewport.transparent_bg = true
	_exit_root.add_child(_exit_viewport)

	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_exit_viewport.add_child(holder)
	var b := Button.new()
	b.text = "II"
	b.custom_minimum_size = Vector2(132, 132)
	b.add_theme_font_size_override("font_size", 72)
	b.add_theme_color_override("font_color", C_MARIGOLD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.05, 0.14, 0.78)
	sb.border_color = C_MARIGOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(66)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.42, 0.16, 0.30, 0.9)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_open.bind("exit_button"))
	holder.add_child(b)

	_exit_quad = _make_quad(_exit_root, EXIT_SIZE, _exit_viewport)
	_make_pointers(_exit_pointers, _exit_viewport, _exit_quad)


func _update_exit_follow() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var basis := cam.global_transform.basis
	var pos: Vector3 = cam.global_position + basis * Vector3(-0.52, -0.36, -1.15)
	_exit_root.global_position = pos
	# Face the camera.
	var look := cam.global_position - pos
	if look.length_squared() > 0.0001:
		_exit_root.rotation.y = atan2(-look.x, -look.z)
		_exit_root.rotation.x = 0.0


## ---- pause panel ----

func _build_panel() -> void:
	# v0.7.0 flat grid of cards (wade's 2026-10-12 order, ship-blocker):
	# plain flat 2D, no 3D clutter. Title / action row / picker header /
	# 3-col grid (11 cards, no scroll) / big red SALIR AL INICIO.
	# Static placement contract: _panel_root is top_level and is placed
	# ONCE per _open() — see _place_panel(). No tick, no follower.
	_panel_root = Node3D.new()
	_panel_root.name = "PausePanel"
	_panel_root.top_level = true
	add_child(_panel_root)

	_panel_viewport = SubViewport.new()
	_panel_viewport.size = Vector2i(int(PANEL_VP.x), int(PANEL_VP.y))
	_panel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_panel_viewport.transparent_bg = true
	_panel_root.add_child(_panel_viewport)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_viewport.add_child(root)

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = C_PLUM
	bg_style.border_color = C_MARIGOLD
	bg_style.set_border_width_all(5)
	bg_style.set_corner_radius_all(24)
	bg.add_theme_stylebox_override("panel", bg_style)
	root.add_child(bg)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	bg.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	# 1. Title: "Pausa — {ChapterName}", 52px marigold accent, centered.
	_title_label = Label.new()
	_title_label.text = "Pausa"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 52)
	_title_label.add_theme_color_override("font_color", C_MARIGOLD)
	vb.add_child(_title_label)

	# Main page: action row + picker header + grid + exit.
	_panel_stack = VBoxContainer.new()
	_panel_stack.add_theme_constant_override("separation", 12)
	vb.add_child(_panel_stack)

	# 2. Action row: Continuar / Controles / Ajustes / Reiniciar.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_panel_stack.add_child(actions)
	_add_action_button(actions, "Continuar", C_GREEN, _resume)
	_add_action_button(actions, "Controles", C_BLUE, _show_legend_page)
	_add_action_button(actions, "Ajustes", C_PINK, _show_settings_page)
	_add_action_button(actions, "Reiniciar", C_ORANGE, _on_restart)

	# 3. Picker header: Prev / "11 CAPÍTULOS" / Next.
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 12)
	_panel_stack.add_child(picker)
	_nav_prev = Button.new()
	_nav_prev.text = "◀ Prev"
	_nav_prev.custom_minimum_size = Vector2(180, 64)
	_nav_prev.add_theme_font_size_override("font_size", 30)
	_style_grid_button(_nav_prev, C_STEEL)
	_nav_prev.pressed.connect(Callable(self, "_on_nav").bind(-1))
	picker.add_child(_nav_prev)
	var plab := Label.new()
	plab.text = "11 CAPÍTULOS"
	plab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plab.add_theme_font_size_override("font_size", 28)
	plab.add_theme_color_override("font_color", C_CREAM)
	plab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_child(plab)
	_nav_next = Button.new()
	_nav_next.text = "Next ▶"
	_nav_next.custom_minimum_size = Vector2(180, 64)
	_nav_next.add_theme_font_size_override("font_size", 30)
	_style_grid_button(_nav_next, C_STEEL)
	_nav_next.pressed.connect(Callable(self, "_on_nav").bind(1))
	picker.add_child(_nav_next)
	# The nav row visibility is driven by set_nav/clear_nav as before; the
	# picker header itself is permanent in the grid layout.
	_nav_row = picker
	_nav_row.visible = false

	# 4. Grid: 3 columns, 11 cards, no scroll.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_panel_stack.add_child(grid)
	for item in MENU_ITEMS:
		_add_card(grid, String(item["key"]), String(item["name"]),
				String(item["mood"]))

	# 5. Big red SALIR AL INICIO (bilingual per prior cycle).
	var exit := _add_action_button(_panel_stack, "SALIR AL INICIO  (EXIT)",
			C_RED, _on_quit)
	exit.custom_minimum_size = Vector2(0, 104)
	exit.add_theme_font_size_override("font_size", 44)

	# Controls-legend page.
	_legend_page = VBoxContainer.new()
	_legend_page.add_theme_constant_override("separation", 14)
	_legend_page.visible = false
	vb.add_child(_legend_page)
	_legend_lines = Label.new()
	_legend_lines.add_theme_font_size_override("font_size", 34)
	_legend_lines.add_theme_color_override("font_color", C_CREAM)
	_legend_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend_page.add_child(_legend_lines)
	_add_panel_button(_legend_page, "Atras  (Back)", C_BLUE, _show_main_page)

	# Settings page (v0.7.0, wade's order): one tap away from the pause
	# menu. Simple flat 2D rows matching the grid language.
	_build_settings_page(vb)

	_panel_quad = _make_quad(_panel_root, PANEL_SIZE, _panel_viewport)
	_make_pointers(_panel_pointers, _panel_viewport, _panel_quad)

	# Gaze dwell ring (shown while dwelling).
	var ring := TorusMesh.new()
	ring.inner_radius = 0.018
	ring.outer_radius = 0.026
	ring.rings = 24
	ring.ring_segments = 8
	_dwell_ring = MeshInstance3D.new()
	_dwell_ring.mesh = ring
	_dwell_ring.material_override = MarigoldFX.glow(Color(1.0, 0.85, 0.4), 2.5)
	_dwell_ring.visible = false
	add_child(_dwell_ring) # on the pause root: shared by exit + panel quads


## One grid card: 260x124 Button, 14px radius, 52x52 mood color chip +
## 28px name label (max 2 lines). Current chapter gets a 4px accent
## border; pressing it = resume (least surprise).
func _add_card(parent: Control, key: String, card_name: String, mood: String) -> void:
	var b := Button.new()
	# v0.7.0: 256px so 3 cols + seps + 48px margins + 5px border = exactly
	# the 900px panel viewport (was 260 -> 910px min width, 10px squeeze).
	b.custom_minimum_size = Vector2(256, 124)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.1))
	_style_card(b, false)
	b.pressed.connect(Callable(self, "_on_card").bind(key))
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	b.add_child(hb)
	var chip := ColorRect.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(52, 52)
	chip.color = MOOD_COLOR.get(mood, C_MARIGOLD)
	hb.add_child(chip)
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.text = card_name
	lab.add_theme_font_size_override("font_size", 28)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.max_lines_visible = 2
	lab.custom_minimum_size = Vector2(150, 0)
	hb.add_child(lab)
	parent.add_child(b)
	_cards[key] = b


func _style_card(b: Button, current: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PLUM_LIGHT
	normal.border_color = C_MARIGOLD if current else C_PLUM_LIGHT.lightened(0.15)
	normal.set_border_width_all(4 if current else 2)
	normal.set_corner_radius_all(14)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_MARIGOLD
	hover.border_color = C_MARIGOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_MARIGOLD.lightened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 4px accent border on the current chapter's card (re-marked on attach).
func _mark_current_card() -> void:
	for key in _cards.keys():
		_style_card(_cards[key] as Button, key == _current_key)


## v0.8.0: flash a one-line note in the pause title (used for the Espejo
## headset gate — the card stays, dimmed, with an explanation).
var _note_tw: Tween = null


func _flash_card_note(_key: String, msg: String) -> void:
	if _title_label == null:
		return
	_title_label.text = msg
	if _note_tw != null and _note_tw.is_valid():
		_note_tw.kill()
	_note_tw = create_tween()
	_note_tw.tween_interval(2.5)
	_note_tw.tween_callback(func() -> void:
		if _title_label != null:
			_title_label.text = "Pausa — " \
					+ (_title_text if _title_text != "" else "La Plaza"))
func _on_card(key: String) -> void:
	## Card press: current chapter = resume; anything else = direct jump
	## through the same load path as the launcher (autowiring, music,
	## telemetry run identically — main._on_pause_jump).
	# v0.8.0 honest gating: Espejo needs a headset (body tracking). The
	# card stays visible but dimmed — no fake tracking, no silent launch.
	if MarigoldState.is_pc_mode() and key == "espejo":
		_flash_card_note(key, "Espejo needs a headset — switch Mode to VR in Settings, then restart.")
		return
	if key == _current_key:
		_resume()
		return
	_resume()
	if _jump_cb.is_valid():
		_jump_cb.call(key)


## Direct-jump callback (main.gd). Re-set on every attach.
func set_jump(jump_cb: Callable) -> void:
	_jump_cb = jump_cb


## Action-row button: expand-fill x 88, 36px font, flat, 14px radius.
func _add_action_button(parent: Control, text: String, accent: Color,
		cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.1))
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_grid_button(b, accent)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _style_grid_button(b: Button, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PLUM_LIGHT
	normal.border_color = accent
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(14)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.lightened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## ---- settings page (v0.7.0, wade's order) ----

func _build_settings_page(vb: VBoxContainer) -> void:
	_page_settings = VBoxContainer.new()
	_page_settings.add_theme_constant_override("separation", 12)
	_page_settings.visible = false
	vb.add_child(_page_settings)
	var title := Label.new()
	title.text = "Ajustes  (Settings)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", C_MARIGOLD)
	_page_settings.add_child(title)
	_add_setting_row("input", "Entrada · Input method",
			Callable(MarigoldGfx, "input_pref_label"),
			Callable(self, "_cycle_setting_input"))
	_add_setting_row("hand", "Mano dominante · Dominant hand",
			Callable(MarigoldGfx, "hand_label"),
			Callable(self, "_cycle_setting_hand"))
	_add_setting_row("tips", "Consejos · Tool tips",
			Callable(self, "_tips_label"),
			Callable(self, "_cycle_setting_tips"))
	_add_setting_row("gfx", "Calidad gráfica · Graphics",
			Callable(MarigoldGfx, "quality_label"),
			Callable(self, "_cycle_setting_gfx"))
	# v0.7.0 Comfort rows (COMFORT_V0110.md §3).
	_add_setting_row("textsize", "Tamaño de texto · Text size",
			Callable(self, "_textsize_label"),
			Callable(self, "_cycle_setting_textsize"))
	_add_setting_row("seated", "Modo sentado · Seated mode",
			Callable(self, "_seated_label"),
			Callable(self, "_cycle_setting_seated"))
	_add_setting_row("vignette", "Viñeta · Vignette",
			Callable(self, "_vignette_label"),
			Callable(self, "_cycle_setting_vignette"))
	_add_setting_row("flight", "Vuelos · Flight transitions",
			Callable(self, "_flight_label"),
			Callable(self, "_cycle_setting_flight"))
	_add_setting_row("subtitles", "Subtítulos · Subtitles",
			Callable(self, "_subtitles_label"),
			Callable(self, "_cycle_setting_subtitles"))
	_add_setting_row("dance", "Baile una mano · One-hand dance",
			Callable(self, "_dance_label"),
			Callable(self, "_cycle_setting_dance"))
	# v0.8.0 PC mode rows (wade's order — all real, no placebos).
	_add_setting_row("sens", "Sensibilidad · Mouse sensitivity",
			Callable(self, "_sens_label"),
			Callable(self, "_cycle_setting_sens"))
	_add_setting_row("inverty", "Invertir Y · Invert mouse Y",
			Callable(self, "_inverty_label"),
			Callable(self, "_cycle_setting_inverty"))
	_add_setting_row("fullscreen", "Pantalla completa · Fullscreen",
			Callable(self, "_fullscreen_label"),
			Callable(self, "_cycle_setting_fullscreen"))
	_add_setting_row("resolution", "Resolución · Resolution",
			Callable(self, "_resolution_label"),
			Callable(self, "_cycle_setting_resolution"))
	_add_setting_row("mode", "Modo · Mode (PC / VR)",
			Callable(self, "_mode_label"),
			Callable(self, "_cycle_setting_mode"))
	_mode_note = Label.new()
	_mode_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_note.add_theme_font_size_override("font_size", 26)
	_mode_note.add_theme_color_override("font_color", C_MARIGOLD)
	_mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_note.text = _mode_note_text
	_page_settings.add_child(_mode_note)
	var note := Label.new()
	note.text = "Se aplica al instante · Applies instantly"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 26)
	note.add_theme_color_override("font_color", C_CREAM.darkened(0.25))
	_page_settings.add_child(note)
	_add_panel_button(_page_settings, "Atras  (Back)", C_BLUE, _show_main_page)


## v0.7.0 Comfort setting labels + cyclers.
func _textsize_label() -> String:
	return "Grande" if MarigoldGfx.text_scale() > 1.0 else "Normal"

func _cycle_setting_textsize() -> void:
	MarigoldGfx.cycle_text_size()
	_refresh_settings_labels()

func _seated_label() -> String:
	return "Sí" if MarigoldGfx.seated_mode() else "No"

func _cycle_setting_seated() -> void:
	MarigoldGfx.set_seated_mode(not MarigoldGfx.seated_mode())
	_refresh_settings_labels()

func _vignette_label() -> String:
	match MarigoldGfx.vignette():
		"soft":
			return "Suave"
		"strong":
			return "Fuerte"
	return "No"

func _cycle_setting_vignette() -> void:
	MarigoldGfx.cycle_vignette()
	_refresh_settings_labels()

func _flight_label() -> String:
	match MarigoldGfx.flight_mode():
		"short":
			return "Corto"
		"skip":
			return "Omitir"
	return "Completo"

func _cycle_setting_flight() -> void:
	MarigoldGfx.cycle_flight_mode()
	_refresh_settings_labels()

func _subtitles_label() -> String:
	return "Sí" if MarigoldGfx.subtitles_on() else "No"

func _cycle_setting_subtitles() -> void:
	MarigoldGfx.set_subtitles(not MarigoldGfx.subtitles_on())
	_refresh_settings_labels()

func _dance_label() -> String:
	return "Sí" if MarigoldGfx.dance_assist() else "No"

func _cycle_setting_dance() -> void:
	MarigoldGfx.set_dance_assist(not MarigoldGfx.dance_assist())
	_refresh_settings_labels()


## v0.8.0 PC rows (all real, no placebos).
func _sens_label() -> String:
	return "%.2f" % MarigoldGfx.mouse_sensitivity()


func _cycle_setting_sens() -> void:
	MarigoldGfx.cycle_mouse_sensitivity()
	_refresh_settings_labels()


func _inverty_label() -> String:
	return "Sí" if MarigoldGfx.mouse_invert_y() else "No"


func _cycle_setting_inverty() -> void:
	MarigoldGfx.set_mouse_invert_y(not MarigoldGfx.mouse_invert_y())
	_refresh_settings_labels()


func _fullscreen_label() -> String:
	return "Sí" if MarigoldGfx.fullscreen() else "No"


func _cycle_setting_fullscreen() -> void:
	MarigoldGfx.set_fullscreen(not MarigoldGfx.fullscreen())
	_refresh_settings_labels()


func _resolution_label() -> String:
	return MarigoldGfx.resolution()


func _cycle_setting_resolution() -> void:
	MarigoldGfx.cycle_resolution()
	_refresh_settings_labels()


## Mode switch: persists the choice; takes effect on restart (XR can't
## cleanly shut down mid-run, and PC->VR needs a fresh XR init — saying so
## in the UI instead of pretending it's instant).
func _mode_label() -> String:
	var saved := MarigoldGfx.saved_launch_mode()
	var cur := "pc" if MarigoldState.is_pc_mode() else "vr"
	if saved != "" and saved != cur:
		return "%s → %s (restart)" % [cur.to_upper(), saved.to_upper()]
	return cur.to_upper()


func _cycle_setting_mode() -> void:
	var to := "vr" if MarigoldState.is_pc_mode() else "pc"
	MarigoldGfx.save_launch_mode(to)
	_mode_note_text = "Mode set to %s — restart the app to switch." \
			% to.to_upper()
	_refresh_settings_labels()

func _refresh_settings_labels() -> void:
	# Rebuild the settings page to refresh labels (simple, robust).
	if _page_settings != null:
		for c in _page_settings.get_children():
			c.queue_free()
		# Rebuild via deferred to avoid modifying during iteration.
		call_deferred("_rebuild_settings_deferred")

func _rebuild_settings_deferred() -> void:
	# Find the parent VBox and rebuild.
	var vb := _page_settings.get_parent() as VBoxContainer
	if vb != null:
		_page_settings.queue_free()
		_build_settings_page(vb)
		_show_settings_page()

func _add_setting_row(key: String, label_text: String, get_label: Callable,
		cycle: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_page_settings.add_child(hb)
	var lab := Label.new()
	lab.text = label_text
	lab.add_theme_font_size_override("font_size", 30)
	lab.add_theme_color_override("font_color", C_CREAM)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(lab)
	var b := Button.new()
	b.custom_minimum_size = Vector2(240, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	_style_grid_button(b, C_STEEL)
	b.pressed.connect(func() -> void:
		cycle.call()
		_refresh_setting_row(key))
	hb.add_child(b)
	_setting_value_btns[key] = {"btn": b, "get": get_label}


func _refresh_setting_row(key: String) -> void:
	var d: Dictionary = _setting_value_btns.get(key, {})
	if d.is_empty():
		return
	(d["btn"] as Button).text = str((d["get"] as Callable).call())


func _refresh_all_settings() -> void:
	for key in _setting_value_btns.keys():
		_refresh_setting_row(key)


func _cycle_setting_input() -> void:
	MarigoldGfx.cycle_input_pref()


func _cycle_setting_hand() -> void:
	MarigoldGfx.cycle_dominant_hand()


func _tips_label() -> String:
	return "Sí" if MarigoldGfx.tooltips_on() else "No"


func _cycle_setting_tips() -> void:
	MarigoldGfx.set_tooltips(not MarigoldGfx.tooltips_on())


func _cycle_setting_gfx() -> void:
	MarigoldGfx.cycle_quality()


func _add_panel_button(parent: Control, text: String, accent: Color,
		cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 44)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.1))
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PLUM_LIGHT
	normal.border_color = accent
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(16)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.lightened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _show_main_page() -> void:
	_panel_stack.visible = true
	_legend_page.visible = false
	_page_settings.visible = false


func _show_settings_page() -> void:
	_panel_stack.visible = false
	_legend_page.visible = false
	_page_settings.visible = true
	_refresh_all_settings()


func _show_legend_page() -> void:
	_panel_stack.visible = false
	_legend_page.visible = true
	_page_settings.visible = false
	_legend_lines.text = MarigoldControllerSkins.legend_text(_legend_key)


## STATIC PLACEMENT CONTRACT (wade's 2026-10-12 order, SHIP-BLOCKER):
## the panel is placed ONCE per _open(), centered in front of the CURRENT
## head direction at PANEL_DISTANCE, then it is 100% STATIC in world space.
## No timer, no _process repositioning, no off-axis check touches
## _panel_root. Ever. (The v0.9.3 0.5s recenter tick is dead by design —
## do NOT "fix" this back into a follower.)
func _place_panel() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_panel_root.position = Vector3(0, 1.5, -PANEL_DISTANCE)
		_panel_root.rotation = Vector3.ZERO
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0, 0, -1)
	else:
		fwd = fwd.normalized()
	var target := cam.global_position + fwd * PANEL_DISTANCE
	target.y = clampf(cam.global_position.y, 1.1, 1.75)
	_panel_root.global_position = target
	var to_user := cam.global_position - target
	_panel_root.rotation = Vector3(0, atan2(to_user.x, to_user.z), 0)


## ---- shared quad + pointer rig ----

func _make_quad(parent: Node3D, size: Vector2, viewport: SubViewport) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var vpt := ViewportTexture.new()
	vpt.viewport_path = viewport.get_path()
	mat.albedo_texture = vpt
	var quad := MeshInstance3D.new()
	quad.mesh = qm
	quad.material_override = mat
	parent.add_child(quad)
	return quad


func _make_pointers(arr: Array[XRUIPointer], viewport: SubViewport, quad: MeshInstance3D) -> void:
	# Hand pointers discover their XRHandTracker lazily; controller pointers
	# are added in attach() once the main scene (and its controllers) exist.
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.hand_side = side
		hp.setup(viewport, quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked.bind(hp))
		hp.xr_moved.connect(_on_pointer_moved.bind(hp))
		add_child(hp)
		arr.append(hp)


## v0.6.2: belt-and-suspenders fallback. Starts on the exit quad; _open() and
## _resume() re-target it between the exit button and the pause panel.
func _build_direct_input() -> void:
	_direct = DirectUIInput.new()
	_direct.name = "DirectUIInput"
	_direct.setup(_exit_viewport, _exit_quad, _xr_origin,
			Callable(self, "_on_fallback_clicked"),
			Callable(self, "_on_fallback_moved"))
	add_child(_direct)


## ---- centralized click funnel (both paths, deduped) ----

func _active_viewport() -> SubViewport:
	return _panel_viewport if _pause_open else _exit_viewport


func _inject_click(pos: Vector2) -> void:
	var vp := _active_viewport()
	if vp == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_click_msec < CLICK_DEDUPE_MS \
			and pos.distance_to(_last_click_pos) < CLICK_DEDUPE_PX:
		return
	_last_click_msec = now
	_last_click_pos = pos
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	vp.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	vp.push_input(release)


func _inject_motion(pos: Vector2) -> void:
	var vp := _active_viewport()
	if vp == null:
		return
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	vp.push_input(mv)


## v0.6.2 FIX: the old handler only noted the input method and never pushed
## the click into the viewport — laser clicks in the pause menu did nothing.
func _on_pointer_clicked(viewport_pos: Vector2, p: XRUIPointer) -> void:
	if is_instance_valid(p):
		_note_input_from_pointer(p)
	_inject_click(viewport_pos)


func _on_pointer_moved(viewport_pos: Vector2, _p: XRUIPointer) -> void:
	_inject_motion(viewport_pos)


func _on_fallback_clicked(viewport_pos: Vector2, kind: String) -> void:
	_note_input_method(kind)
	_inject_click(viewport_pos)


func _on_fallback_moved(viewport_pos: Vector2, _kind: String) -> void:
	_inject_motion(viewport_pos)


func _any_pointer_live() -> bool:
	if not get_viewport().use_xr:
		return false
	for p in _exit_pointers + _panel_pointers:
		if is_instance_valid(p) and p.is_source_live():
			return true
	return false


## Pixels, not tracker registration: true while EITHER path draws a beam.
func _any_beam_drawn() -> bool:
	for p in _exit_pointers + _panel_pointers:
		if is_instance_valid(p) and p.is_beam_visible():
			return true
	if _direct != null and is_instance_valid(_direct) \
			and _direct.beam_visible_recently(250.0):
		return true
	return false


## Gaze dwell fallback: when no beam is drawn by either path, a 1.2 s look
## = click. (Old rule used tracker registration — a live-but-useless
## tracker hid the reticle AND the lasers were invisible: zero input.)
## v0.8.0: gated to XR — desktop never auto-clicks (see menu.gd).
func _update_gaze(delta: float, viewport: SubViewport, quad: MeshInstance3D) -> void:
	if not MarigoldHands.is_xr_active():
		_dwell_t = 0.0
		_dwell_ring.visible = false
		return
	if _menu_holding:
		return  # the menu-hold ring owns _dwell_ring while the button is held
	if _any_beam_drawn():
		_dwell_t = 0.0
		_dwell_ring.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or quad == null:
		return
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit := XRUIPointer.ray_to_viewport(origin, dir.normalized(), quad,
		Vector2(viewport.size))
	if not bool(hit["hit"]):
		_dwell_t = 0.0
		_dwell_ring.visible = false
		return
	var pos: Vector2 = hit["pos"]
	# Forward hover so buttons highlight.
	_inject_motion(pos)
	if _dwell_t <= 0.0 or _dwell_pos.distance_to(pos) > 28.0:
		_dwell_pos = pos
		_dwell_t = 0.0001
	_dwell_t += delta
	# Dwell ring on the quad at the gaze point.
	var world: Vector3 = hit["world"]
	_dwell_ring.global_position = world + quad.global_transform.basis.z * 0.005
	var k := clampf(_dwell_t / DWELL_TIME, 0.05, 1.0)
	_dwell_ring.scale = Vector3.ONE * (0.4 + k * 1.6)
	_dwell_ring.visible = true
	if _dwell_t >= DWELL_TIME:
		_dwell_t = 0.0
		_dwell_ring.visible = false
		_note_input_method("gaze")
		_inject_click(pos)


## v0.6.1: first click in a chapter session records the input method for
## telemetry (controllers vs hands vs gaze vs mouse). First method wins per
## session (GameplayTelemetry.note_input_method). Source identification
## mirrors XRUIPointer: controller pointers carry a live XRController3D,
## hand pointers carry hand_side != 0.
func _note_input_from_pointer(p: XRUIPointer) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt == null:
		return
	if p.controller != null:
		gt.note_input_method("controllers")
	elif p.hand_side != 0:
		gt.note_input_method("hands")


func _note_input_method(method: String) -> void:
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.note_input_method(method)


func _forward_mouse(event: InputEventMouse, cam: Camera3D, quad: MeshInstance3D,
		viewport: SubViewport, vp_size: Vector2) -> void:
	var hit := XRUIPointer.ray_to_viewport(
		cam.project_ray_origin(event.position),
		cam.project_ray_normal(event.position),
		quad, vp_size)
	if not bool(hit["hit"]):
		return
	var ev2 := event.duplicate() as InputEventMouse
	ev2.position = hit["pos"]
	viewport.push_input(ev2)
