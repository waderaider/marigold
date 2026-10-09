## MarigoldPause.gd - shared pause/exit overlay (autoload, v0.5.0).
## SHIP-BLOCKER: every chapter + experience gets pause/exit through:
##   1. the controller menu button (OpenXR "menu_button" action / Esc),
##   2. a small floating on-screen exit button (opens the overlay, never
##      quits directly).
## v0.6.2 rework: simplified 2D list — Continuar (Resume, green) / Controles
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

const EXIT_VP := Vector2i(160, 160)
const EXIT_SIZE := Vector2(0.17, 0.17)
const PANEL_VP := Vector2(680, 780)
const PANEL_SIZE := Vector2(1.0, 1.15)
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

var _attached := false
var _pause_open := false
var _restart_cb := Callable()
var _quit_cb := Callable()
var _legend_key := ""
var _title_text := ""
var _menu_was_pressed := false
var _cooldown := 0.0

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
var _direct: DirectUIInput = null

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
	for p in _exit_pointers + _panel_pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
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
			_toggle_pause()
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
	_panel_root.visible = false
	_exit_root.visible = true
	if _title_label != null:
		_title_label.text = title if title != "" else "Pausa"
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
	_nav_row.visible = false


## ---- pause state ----

func _toggle_pause() -> void:
	if _pause_open:
		_resume()
	else:
		_open()


func _open() -> void:
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
	var gt := get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event("pause_open", {"chapter": gt.current_chapter()})


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


## Controller menu button (OpenXR "menu_button" action) with edge detection.
func _update_menu_button() -> void:
	if not _attached:
		_menu_was_pressed = false
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
	if pressed and not _menu_was_pressed and _cooldown <= 0.0:
		_cooldown = 0.4
		_toggle_pause()
	_menu_was_pressed = pressed


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
	b.pressed.connect(_open)
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
	_panel_root = Node3D.new()
	_panel_root.name = "PausePanel"
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
		margin.add_theme_constant_override(side, 56)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	bg.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vb)

	# v0.6.2: title shows the current chapter/experience name so Restart's
	# target is obvious (PAUSE_MENU_UX §4.5).
	_title_label = Label.new()
	_title_label.text = "Pausa"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 72)
	_title_label.add_theme_color_override("font_color", C_MARIGOLD)
	vb.add_child(_title_label)

	_panel_stack = VBoxContainer.new()
	_panel_stack.add_theme_constant_override("separation", 10)
	vb.add_child(_panel_stack)
	# PAUSE_MENU_UX §1 order: Resume (safest, top) / Controls / Restart /
	# Nav row (leave-this-item zone) / Exit (bottom, red, full-width).
	_add_panel_button(_panel_stack, "Continuar  (Resume)", C_GREEN, _resume)
	_add_panel_button(_panel_stack, "Controles  (Controls)", C_BLUE, _show_legend_page)
	_add_panel_button(_panel_stack, "Reiniciar  (Restart)", C_ORANGE, _on_restart)

	_nav_row = HBoxContainer.new()
	_nav_row.add_theme_constant_override("separation", 12)
	_nav_row.visible = false
	_panel_stack.add_child(_nav_row)
	_nav_prev = _add_panel_button(_nav_row, "◀ Prev", C_STEEL,
			Callable(self, "_on_nav").bind(-1))
	_nav_next = _add_panel_button(_nav_row, "Next ▶", C_STEEL,
			Callable(self, "_on_nav").bind(1))

	var exit := _add_panel_button(_panel_stack, "SALIR AL INICIO  (EXIT)",
			C_RED, _on_quit)
	exit.custom_minimum_size = Vector2(0, 110)
	exit.add_theme_font_size_override("font_size", 46)

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


func _show_legend_page() -> void:
	_panel_stack.visible = false
	_legend_page.visible = true
	_legend_lines.text = MarigoldControllerSkins.legend_text(_legend_key)


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
func _update_gaze(delta: float, viewport: SubViewport, quad: MeshInstance3D) -> void:
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
