extends Node3D
class_name MarigoldMenu
## MARIGOLD 2D launch menu (v0.6.2 rework): one panel, one scrollable list.
##
## LAUNCHER LAW: no tabs, no hero buttons, no key-art cards, no mode toggle
## (defaults to immersive), no time-of-day selector. Two passive headers —
## STORY CHAPTERS (ch1..ch5 in story order) then EXPERIENCES (Mano Magica,
## Guitarra, Pinta, Espejo, Galeria, Tu Ofrenda finale last). Each row:
## "Name — built by Muse" + one-line description.
##
## Panel framing (photo-bug fix): the old build parked the quad at a fixed
## tracking-space offset with NO recenter, so any play-space offset clipped
## the buttons ("Begin Jo…", "Mode: Immer…"). Now: yaw-aligned to the live
## HMD forward on every menu open (+0.75 s re-settle one-shot), 0.96x1.28 m
## quad at 2.0 m, and a 0.5 s guard tick that pushes the panel out when
## closer than 0.8 m and recenters when >30 deg off-axis.
##
## Input (belt and suspenders): XRUIPointer primary path AND a DirectUIInput
## fallback that draws its own bright-yellow beams from raw tracker poses.
## Both funnel through inject_click/inject_motion (clicks deduped 120ms/8px).
## Gaze dwell (1.2 s) fires only when NO beam was drawn by either path in the
## last 0.25 s — never on tracker registration alone (the F3 failure mode).
##
## Staged boot: stage 0 (_ready) = panel + quad + LOADING label only;
## stage 1 (deferred) = list UI, pointers, fallback, recenter;
## stage 2 (deferred, low priority) = altar decor.
##
## Input works with controller laser, hand pinch, gaze dwell (fallback), and
## desktop mouse.

signal chapter_chosen(idx: int)
signal experience_chosen(key: String)
signal updates_requested
signal download_requested
signal install_requested

const VP_SIZE := Vector2(1280, 1700)
const QUAD_SIZE := Vector2(0.96, 1.28)
const PANEL_DISTANCE := 2.0
const MIN_PANEL_DIST := 0.8
const REFRAME_ANGLE_DEG := 30.0
const GUARD_INTERVAL := 0.5
const RESETTLE_DELAY := 0.75
const CLICK_DEDUPE_MS := 120
const CLICK_DEDUPE_PX := 8.0
const DWELL_TIME := 1.2
const SCROLL_STEP := 120.0
const SCROLL_REPEAT := 0.12

## Experience menu order (PAUSE_MENU_UX §3): tutorial first, finale last.
const EXP_ORDER := ["mano_magica", "guitarra", "pinta", "espejo", "galeria",
		"ofrenda_finale"]

const RELAY_PING_URL := "https://nexus-log-relay.brio-00c.workers.dev/report"

# Design Director palette (v0.6.2).
const C_BG := Color(0.106, 0.059, 0.118)       # #1B0F1E
const C_PANEL := Color(0.165, 0.086, 0.149)    # #2A1626
const C_CREAM := Color(1.0, 0.965, 0.910)      # #FFF6E8
const C_ACCENT := Color(1.0, 0.620, 0.106)     # #FF9E1B marigold
const C_TERRA := Color(0.894, 0.341, 0.180)    # #E4572E terracotta
const C_DIM := Color(0.847, 0.749, 0.659)      # #D8BFA8
const C_DARK := Color(0.106, 0.059, 0.118)     # selection text #1B0F1E

var _panel_root: Node3D
var _viewport: SubViewport
var _quad: MeshInstance3D
var _pointers: Array[XRUIPointer] = []
var _controllers: Array[XRController3D] = []
var _xr_origin: Node3D = null
var _direct: DirectUIInput = null

var _menu_panel: Control
var _finale_center: Control
var _list_vbox: VBoxContainer
var _scroll: ScrollContainer
var _status_label: Label
var _version_label: Label
var _diag_label: Label
var _conn_label: Label
var _test_button: Button
var _download_button: Button
var _install_button: Button
var _room_dialog: Control
var _dwell_ring: MeshInstance3D

var _chapter_names: Array = []
var _experiences: Array = []
var _progress_idx := 0
var _completed: Array = []
var _list_built := false
var _pending_version := "" # set_version() may arrive before stage 1 builds

var _boot_msec := 0
var _first_frame_s := -1.0
var _stage1_msec := 0
var _guard_acc := 0.0
var _resettle_t := -1.0

var _last_click_msec := 0
var _last_click_pos := Vector2(-9999, -9999)

var _scroll_dir := 0
var _scroll_acc := 0.0

var _dwell_t := 0.0
var _dwell_pos := Vector2.ZERO
var _no_beam_s := 0.0 # seconds with XR up, menu visible, no beam drawn

var _ping_http: HTTPRequest = null
var _ping_in_flight := false


func _ready() -> void:
	_boot_msec = Time.get_ticks_msec()
	_build_panel_stage0()
	RenderingServer.frame_post_draw.connect(_on_first_frame, CONNECT_ONE_SHOT)
	call_deferred("_stage1")


func _on_first_frame() -> void:
	_first_frame_s = float(Time.get_ticks_msec() - _boot_msec) / 1000.0
	if _diag_label != null:
		_refresh_diag()


func _process(delta: float) -> void:
	var xr := get_viewport().use_xr
	for p in _pointers:
		if is_instance_valid(p):
			p.xr_mode = xr
	if _direct != null and is_instance_valid(_direct):
		_direct.xr_mode = xr
	# Re-settle one-shot: HMD pose is often identity at menu build time.
	if _resettle_t > 0.0:
		_resettle_t -= delta
		if _resettle_t <= 0.0:
			_resettle_t = -1.0
			_recenter_panel()
	# Panel framing guards.
	if _panel_root != null and _panel_root.visible:
		_guard_acc += delta
		if _guard_acc >= GUARD_INTERVAL:
			_guard_acc = 0.0
			_auto_frame_panel()
			_refresh_diag()
		_update_gaze(delta)
		# Self-test (§3.4): XR up + menu visible + no beam drawn for > 3 s
		# => the photo-state, reported on screen for wade to read back.
		if get_viewport().use_xr and not _any_beam_drawn():
			_no_beam_s += delta
		else:
			_no_beam_s = 0.0
	# Scroll hold-to-repeat.
	if _scroll_dir != 0 and _scroll != null:
		_scroll_acc += delta
		while _scroll_acc >= SCROLL_REPEAT:
			_scroll_acc -= SCROLL_REPEAT
			_scroll.scroll_vertical += _scroll_dir * SCROLL_STEP * 3.0


func _input(event: InputEvent) -> void:
	if _panel_root == null or not _panel_root.visible:
		return
	# Room dialog eats input while open.
	if _room_dialog != null and _room_dialog.visible:
		return
	# Desktop fallback: forward the real mouse into the panel viewport, but
	# only while no XR pointer is live (avoids double input on device).
	if _xr_pointer_live():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_forward_desktop_mouse(mb)
	elif event is InputEventMouseMotion:
		_forward_desktop_mouse(event as InputEventMouseMotion)


## ---- public API (called by main.gd) ----

func set_chapters(chapters: Array) -> void:
	_chapter_names = chapters
	_rebuild_list()


func set_experiences(exps: Array) -> void:
	_experiences = exps
	_rebuild_list()


## Journey progress: current chapter index + completed chapter indices.
func set_progress(idx: int, completed: Array) -> void:
	_progress_idx = clampi(idx, 0, maxi(0, _chapter_names.size() - 1))
	_completed = completed.duplicate()
	_rebuild_list()


func show_menu() -> void:
	_panel_root.visible = true
	if _menu_panel == null:
		return # stage 0: still showing the LOADING placeholder
	_menu_panel.visible = true
	_finale_center.visible = false
	_recenter_panel()
	_resettle_t = RESETTLE_DELAY
	_guard_acc = 0.0


func hide_menu() -> void:
	_panel_root.visible = false
	if _menu_panel == null:
		return
	_finale_center.visible = false
	_menu_panel.visible = true
	_resettle_t = -1.0


func show_finale() -> void:
	_panel_root.visible = true
	if _menu_panel == null:
		return
	_menu_panel.visible = false
	_finale_center.visible = true
	_recenter_panel()
	_resettle_t = RESETTLE_DELAY


func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func set_version(text: String) -> void:
	_pending_version = text
	if _version_label != null:
		_version_label.text = text


func offer_download(version: String) -> void:
	_download_button.text = "Download v" + version
	_download_button.visible = true
	_install_button.visible = false


func offer_install() -> void:
	_download_button.visible = false
	_install_button.visible = true


func clear_update_buttons() -> void:
	_download_button.visible = false
	_install_button.visible = false


## ---- stage 0: panel + quad + LOADING label (frame 1) ----

func _build_panel_stage0() -> void:
	_panel_root = Node3D.new()
	_panel_root.name = "PanelRoot"
	add_child(_panel_root)

	_viewport = SubViewport.new()
	_viewport.name = "MenuViewport"
	_viewport.size = Vector2i(int(VP_SIZE.x), int(VP_SIZE.y))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = true
	_panel_root.add_child(_viewport)

	# Stage-0 UI: flat opaque backdrop + one LOADING label. Flat colors,
	# default font, zero assets — frame 1 must never be black.
	var root := Control.new()
	root.name = "Stage0Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var lab := Label.new()
	lab.text = "LOADING…"
	lab.add_theme_font_size_override("font_size", 64)
	lab.add_theme_color_override("font_color", C_CREAM)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(lab)

	var qm := QuadMesh.new()
	qm.size = QUAD_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	var vpt := ViewportTexture.new()
	vpt.viewport_path = _viewport.get_path()
	mat.albedo_texture = vpt
	_quad = MeshInstance3D.new()
	_quad.name = "MenuQuad"
	_quad.mesh = qm
	_quad.material_override = mat
	_panel_root.add_child(_quad)

	# Warm marigold rim frame behind the quad.
	var frame := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = QUAD_SIZE + Vector2(0.06, 0.06)
	frame.mesh = fq
	frame.material_override = MarigoldFX.glow(C_ACCENT, 0.8)
	frame.position = Vector3(0, 0, -0.01)
	_panel_root.add_child(frame)

	# Gaze dwell ring (shown while dwelling).
	var ring := TorusMesh.new()
	ring.inner_radius = 0.014
	ring.outer_radius = 0.02
	ring.rings = 24
	ring.ring_segments = 8
	_dwell_ring = MeshInstance3D.new()
	_dwell_ring.mesh = ring
	_dwell_ring.material_override = MarigoldFX.glow(Color(1.0, 0.85, 0.4), 2.5)
	_dwell_ring.visible = false
	_panel_root.add_child(_dwell_ring)


## ---- stage 1 (deferred): list UI, pointers, fallback, recenter ----

func _stage1() -> void:
	_stage1_msec = Time.get_ticks_msec()
	_build_ui()
	_build_pointers()
	_build_direct_input()
	_recenter_panel()
	_resettle_t = RESETTLE_DELAY
	call_deferred("_stage2")


## ---- stage 2 (deferred, low priority): altar decor ----

func _stage2() -> void:
	_build_altar_decor()


## v0.6.0 (finding 6): the menu sits on a decorated ofrenda - candle cluster,
## marigold garland, and a papel-picado arch. Emissive only, zero new lights.
## Deferred to stage 2 so boot never waits on it.
func _build_altar_decor() -> void:
	var qx := QUAD_SIZE.x * 0.5
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.4, 0.08, 0.5)
	table.mesh = tm
	table.material_override = MarigoldFX.pbr(Color(0.40, 0.22, 0.10), 0.0, 0.7)
	table.position = Vector3(0, -QUAD_SIZE.y * 0.5 - 0.04, 0.15)
	_panel_root.add_child(table)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6006
	for i in 5:
		var cx := -0.8 + float(i) * 0.4
		var stick := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.03
		sm.bottom_radius = 0.03
		sm.height = rng.randf_range(0.18, 0.32)
		stick.mesh = sm
		stick.material_override = MarigoldFX.pbr(Color(1.0, 0.93, 0.82), 0.0, 0.6)
		stick.position = table.position + Vector3(cx, 0.15, 0)
		_panel_root.add_child(stick)
		var flame := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.025
		fm.height = 0.07
		flame.mesh = fm
		flame.material_override = MarigoldFX.glow(Color(1.0, 0.62, 0.18), 2.0)
		flame.position = stick.position + Vector3(0, 0.20, 0)
		_panel_root.add_child(flame)
	var blossom := SphereMesh.new()
	blossom.radius = 0.045
	blossom.height = 0.06
	blossom.radial_segments = 8
	blossom.rings = 4
	blossom.material = MarigoldFX.glow(Color(1.0, 0.55, 0.08), 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blossom
	mm.instance_count = 16
	for i in 16:
		var bx := -1.1 + float(i) * 0.147
		mm.set_instance_transform(i, Transform3D(Basis(),
			table.position + Vector3(bx, 0.06, 0.26)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_panel_root.add_child(mmi)
	for i in 7:
		var b := MeshInstance3D.new()
		var qm2 := QuadMesh.new()
		qm2.size = Vector2(0.42, 0.22)
		b.mesh = qm2
		b.material_override = MarigoldPapelPicado.banner_material(7000 + i)
		var ax := -qx - 0.1 + float(i) * (2.0 * qx + 0.2) / 6.0
		b.position = Vector3(ax, QUAD_SIZE.y * 0.5 + 0.18, 0.05)
		_panel_root.add_child(b)


## ---- the simplified list UI ----

func _build_ui() -> void:
	# Remove the stage-0 placeholder.
	var stage0 := _viewport.get_node_or_null("Stage0Root")
	if stage0 != null:
		stage0.queue_free()

	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = C_BG # opaque
	bg_style.border_color = C_ACCENT
	bg_style.set_border_width_all(6)
	bg_style.set_corner_radius_all(28)
	bg.add_theme_stylebox_override("panel", bg_style)
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	bg.add_child(margin)

	_menu_panel = VBoxContainer.new()
	_menu_panel.add_theme_constant_override("separation", 12)
	margin.add_child(_menu_panel)

	# Header: title + version badge.
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 24)
	_menu_panel.add_child(header)
	var title := Label.new()
	title.text = "MARIGOLD — built by Muse"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", C_ACCENT)
	header.add_child(title)
	_version_label = Label.new()
	_version_label.text = _pending_version
	_version_label.add_theme_font_size_override("font_size", 36)
	_version_label.add_theme_color_override("font_color", C_DIM)
	header.add_child(_version_label)
	_add_label(_menu_panel, "A Dia de Muertos Journey", 40, C_CREAM)

	# The scrollable list.
	var list_frame := PanelContainer.new()
	list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lf_style := StyleBoxFlat.new()
	lf_style.bg_color = C_PANEL # opaque
	lf_style.border_color = C_ACCENT
	lf_style.set_border_width_all(3)
	lf_style.set_corner_radius_all(18)
	lf_style.content_margin_left = 16
	lf_style.content_margin_right = 16
	lf_style.content_margin_top = 16
	lf_style.content_margin_bottom = 16
	list_frame.add_theme_stylebox_override("panel", lf_style)
	_menu_panel.add_child(list_frame)

	var list_hbox := HBoxContainer.new()
	list_hbox.add_theme_constant_override("separation", 12)
	list_frame.add_child(list_hbox)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_hbox.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list_vbox)

	# Explicit scroll buttons (laser-scroll; injected clicks are
	# press+release so drag-scroll is deliberately not relied upon).
	var scroll_col := VBoxContainer.new()
	scroll_col.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll_col.add_theme_constant_override("separation", 16)
	list_hbox.add_child(scroll_col)
	var up := _make_scroll_button("▲", 1)
	var down := _make_scroll_button("▼", -1)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_col.add_child(up)
	scroll_col.add_child(spacer)
	scroll_col.add_child(down)

	# Footer buttons.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	_menu_panel.add_child(btn_row)
	var upd := _make_button("CHECK FOR UPDATES", 34, C_ACCENT)
	upd.custom_minimum_size = Vector2(560, 96)
	upd.pressed.connect(func() -> void: updates_requested.emit())
	btn_row.add_child(upd)
	var room := _make_button("Room setup", 30, C_DIM)
	room.custom_minimum_size = Vector2(0, 96)
	room.pressed.connect(_show_room_dialog)
	btn_row.add_child(room)

	_download_button = _make_button("Download", 34, C_ACCENT)
	_download_button.visible = false
	_download_button.pressed.connect(func() -> void: download_requested.emit())
	_menu_panel.add_child(_download_button)

	_install_button = _make_button("Install Update", 34, C_ACCENT)
	_install_button.visible = false
	_install_button.pressed.connect(func() -> void: install_requested.emit())
	_menu_panel.add_child(_install_button)

	_status_label = _add_label(_menu_panel, "", 30, C_DIM)

	# Diagnostics (ship-blocker): plain-words input state + connection test.
	_diag_label = _add_label(_menu_panel, "", 26, C_DIM)
	var conn_row := HBoxContainer.new()
	conn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	conn_row.add_theme_constant_override("separation", 16)
	_menu_panel.add_child(conn_row)
	_test_button = _make_button("Test connection", 28, C_DIM)
	_test_button.custom_minimum_size = Vector2(0, 72)
	_test_button.pressed.connect(_test_connection)
	conn_row.add_child(_test_button)
	_conn_label = Label.new()
	_conn_label.text = "Connection: not tested"
	_conn_label.add_theme_font_size_override("font_size", 28)
	_conn_label.add_theme_color_override("font_color", C_DIM)
	conn_row.add_child(_conn_label)

	_add_label(_menu_panel, "Point the laser and pull the trigger (or pinch) to select",
			24, C_DIM)

	_ping_http = HTTPRequest.new()
	_ping_http.name = "DiagPingHTTP"
	_ping_http.timeout = 8
	add_child(_ping_http)
	_ping_http.request_completed.connect(_on_ping_completed)

	_build_finale(root)
	_build_room_dialog(root)

	_list_built = true
	_rebuild_list()
	_refresh_diag()


func _rebuild_list() -> void:
	if not _list_built or _list_vbox == null:
		return
	for c in _list_vbox.get_children():
		c.queue_free()
	_add_section_header("STORY CHAPTERS")
	for i in range(_chapter_names.size()):
		var info: Dictionary = _chapter_names[i]
		var name := String(info.get("name", "Chapter"))
		var mark := ""
		if _completed.has(i):
			mark = "✓ "
		elif i == _progress_idx:
			mark = "▶ "
		var row := _make_row("%d. %s%s" % [i + 1, mark, name],
				String(info.get("desc", "")))
		var idx := i
		row.pressed.connect(func() -> void: chapter_chosen.emit(idx))
		_list_vbox.add_child(row)
	_add_section_header("EXPERIENCES")
	for key in EXP_ORDER:
		var info := _find_experience(key)
		if info.is_empty():
			continue
		var row := _make_row(String(info.get("name", "Experience")),
				String(info.get("desc", "")))
		var k := String(info.get("key", key))
		row.pressed.connect(func() -> void: experience_chosen.emit(k))
		_list_vbox.add_child(row)


func _find_experience(key: String) -> Dictionary:
	for exp in _experiences:
		var info: Dictionary = exp
		if String(info.get("key", "")) == key:
			return info
	return {}


func _add_section_header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", C_ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_vbox.add_child(l)


func _make_row(name: String, desc: String) -> Button:
	var b := Button.new()
	# wade's permanent branding directive: "Name — built by Muse".
	b.text = ""
	b.custom_minimum_size = Vector2(0, 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL
	normal.border_color = C_ACCENT
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_ACCENT # instant color-swap selection
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_TERRA
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	b.add_child(vb)
	var nl := Label.new()
	nl.text = name
	nl.add_theme_font_size_override("font_size", 40)
	nl.add_theme_color_override("font_color", C_CREAM)
	nl.add_theme_color_override("font_hover_color", C_DARK)
	nl.add_theme_color_override("font_pressed_color", C_DARK)
	nl.clip_text = true
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nl)
	var dl := Label.new()
	dl.text = desc
	dl.add_theme_font_size_override("font_size", 26)
	dl.add_theme_color_override("font_color", C_DIM)
	dl.add_theme_color_override("font_hover_color", C_DARK)
	dl.add_theme_color_override("font_pressed_color", C_DARK)
	dl.clip_text = true
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(dl)
	return b


func _make_scroll_button(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 120)
	b.add_theme_font_size_override("font_size", 56)
	b.add_theme_color_override("font_color", C_ACCENT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL
	normal.border_color = C_ACCENT
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(20)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = C_ACCENT
	hover.border_color = C_ACCENT
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void:
		if _scroll != null:
			_scroll.scroll_vertical += -dir * SCROLL_STEP)
	b.button_down.connect(func() -> void:
		_scroll_dir = -dir
		_scroll_acc = SCROLL_REPEAT * 0.5) # first repeat comes sooner
	b.button_up.connect(func() -> void:
		if _scroll_dir == -dir:
			_scroll_dir = 0
			_scroll_acc = 0.0)
	return b


func _build_finale(root: Control) -> void:
	_finale_center = CenterContainer.new()
	_finale_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_finale_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finale_center.visible = false
	root.add_child(_finale_center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_finale_center.add_child(box)
	_add_label(box, "Gracias por celebrar", 96, C_ACCENT)
	_add_label(box, "Dia de Muertos honra a quienes amamos.\nHasta el proximo ano.",
			44, C_CREAM)
	var again := _make_button("Journey Again", 48, C_ACCENT)
	again.pressed.connect(func() -> void: chapter_chosen.emit(0))
	box.add_child(again)


func _build_room_dialog(root: Control) -> void:
	_room_dialog = Control.new()
	_room_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_dialog.visible = false
	root.add_child(_room_dialog)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL
	ps.border_color = C_ACCENT
	ps.set_border_width_all(4)
	ps.set_corner_radius_all(20)
	ps.content_margin_left = 48
	ps.content_margin_right = 48
	ps.content_margin_top = 40
	ps.content_margin_bottom = 40
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	_add_label(vb, "Room setup", 56, C_ACCENT)
	var body := Label.new()
	body.text = "Centers the menu panel on where you are looking right now.\n\n" \
		+ "For full room capture (walls and furniture), use the Quest\n" \
		+ "system menu: Settings > Guardian > Room setup."
	body.add_theme_font_size_override("font_size", 30)
	body.add_theme_color_override("font_color", C_CREAM)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)
	var recenter := _make_button("Center panel on me", 34, C_ACCENT)
	recenter.pressed.connect(func() -> void:
		_recenter_panel()
		_room_dialog.visible = false)
	vb.add_child(recenter)
	var close := _make_button("Close", 30, C_DIM)
	close.pressed.connect(func() -> void: _room_dialog.visible = false)
	vb.add_child(close)


func _show_room_dialog() -> void:
	_room_dialog.visible = true


## ---- widget helpers ----

func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_button(text: String, font_size: int, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", C_CREAM)
	b.add_theme_color_override("font_hover_color", C_DARK)
	b.add_theme_color_override("font_pressed_color", C_DARK)
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL
	normal.border_color = accent
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_TERRA
	pressed.border_color = C_TERRA
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## ---- panel placement (the photo bug) ----

## Yaw-align the panel to the live HMD forward on every menu open.
func _recenter_panel() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
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
	# Yaw the quad's +Z to face the user.
	var to_user := cam.global_position - target
	_panel_root.rotation = Vector3(0, atan2(to_user.x, to_user.z), 0)


## 0.5 s guard tick: push away when too close, recenter when off-axis.
func _auto_frame_panel() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(cam):
		return
	var center := _panel_root.global_position
	var to_panel := center - cam.global_position
	var d := to_panel.length()
	if d < MIN_PANEL_DIST:
		# Emergency push: 1.5 m along yaw-projected camera forward.
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.001:
			fwd = Vector3(0, 0, -1)
		else:
			fwd = fwd.normalized()
		var target := cam.global_position + fwd * 1.5
		target.y = clampf(cam.global_position.y, 1.1, 1.75)
		_panel_root.global_position = target
		var to_user := cam.global_position - target
		_panel_root.rotation = Vector3(0, atan2(to_user.x, to_user.z), 0)
		return
	var cam_fwd := -cam.global_transform.basis.z
	if cam_fwd.length_squared() < 0.001 or d < 0.001:
		return
	var ang := rad_to_deg(acos(clampf(cam_fwd.normalized().dot(
			to_panel / d), -1.0, 1.0)))
	if ang > REFRAME_ANGLE_DEG:
		_recenter_panel()


## ---- input: primary + fallback funnel ----

func _build_pointers() -> void:
	_xr_origin = get_parent().get_node_or_null("XROrigin3D") as Node3D
	if _xr_origin != null:
		# Name-agnostic discovery: the old fixed ["LeftController",
		# "RightController"] lookup silently found nothing on some trees.
		for ctl in _xr_origin.find_children("*", "XRController3D", true, false):
			var c := ctl as XRController3D
			if c == null:
				continue
			_controllers.append(c)
			var p := XRUIPointer.new()
			p.name = "Pointer" + c.name
			p.controller = c
			p.setup(_viewport, _quad, _xr_origin)
			p.xr_clicked.connect(_on_pointer_clicked)
			p.xr_moved.connect(_on_pointer_moved)
			_panel_root.add_child(p)
			_pointers.append(p)
	# Hand pointers discover their XRHandTracker lazily.
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT,
			XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.name = "PointerHand%d" % side
		hp.hand_side = side
		hp.setup(_viewport, _quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked)
		hp.xr_moved.connect(_on_pointer_moved)
		_panel_root.add_child(hp)
		_pointers.append(hp)


func _build_direct_input() -> void:
	_direct = DirectUIInput.new()
	_direct.name = "DirectUIInput"
	_direct.setup(_viewport, _quad, _xr_origin,
			Callable(self, "_on_fallback_clicked"),
			Callable(self, "_on_fallback_moved"))
	_panel_root.add_child(_direct)


## Centralized click funnel: the ONLY injection point (both paths call it).
## Dual-path dedupe: 120 ms / 8 px.
func inject_click(pos: Vector2) -> void:
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
	_viewport.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	_viewport.push_input(release)


## Hover is idempotent; no dedupe needed.
func inject_motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	_viewport.push_input(ev)


func _on_pointer_moved(viewport_pos: Vector2) -> void:
	inject_motion(viewport_pos)


func _on_pointer_clicked(viewport_pos: Vector2) -> void:
	inject_click(viewport_pos)


func _on_fallback_moved(viewport_pos: Vector2, _kind: String) -> void:
	inject_motion(viewport_pos)


func _on_fallback_clicked(viewport_pos: Vector2, _kind: String) -> void:
	inject_click(viewport_pos)


func _xr_pointer_live() -> bool:
	if not get_viewport().use_xr:
		return false
	for p in _pointers:
		if is_instance_valid(p) and p.is_source_live():
			return true
	return false


## True when a beam is actually drawn by EITHER path (pixels, not tracker
## registration). Gaze reticle + dwell are keyed on this.
func _any_beam_drawn() -> bool:
	for p in _pointers:
		if is_instance_valid(p) and p.is_beam_visible():
			return true
	if _direct != null and is_instance_valid(_direct) \
			and _direct.beam_visible_recently(250.0):
		return true
	return false


func _forward_desktop_mouse(event: InputEventMouse) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _quad == null:
		return
	var hit := XRUIPointer.ray_to_viewport(
		cam.project_ray_origin(event.position),
		cam.project_ray_normal(event.position),
		_quad, VP_SIZE)
	if not bool(hit["hit"]):
		return
	var ev2 := event.duplicate() as InputEventMouse
	ev2.position = hit["pos"]
	_viewport.push_input(ev2)


## Gaze dwell fallback: runs only when no beam is drawn by either path.
func _update_gaze(delta: float) -> void:
	if _room_dialog != null and _room_dialog.visible:
		_dwell_t = 0.0
		_dwell_ring.visible = false
		return
	if _any_beam_drawn():
		_dwell_t = 0.0
		_dwell_ring.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or _quad == null:
		return
	var hit := XRUIPointer.ray_to_viewport(cam.global_position,
			(-cam.global_transform.basis.z).normalized(), _quad, VP_SIZE)
	if not bool(hit["hit"]):
		_dwell_t = 0.0
		_dwell_ring.visible = false
		return
	var pos: Vector2 = hit["pos"]
	inject_motion(pos) # hover so buttons highlight
	if _dwell_t <= 0.0 or _dwell_pos.distance_to(pos) > 28.0:
		_dwell_pos = pos
		_dwell_t = 0.0001
	_dwell_t += delta
	var world: Vector3 = hit["world"]
	_dwell_ring.global_position = world + _quad.global_transform.basis.z * 0.005
	var k := clampf(_dwell_t / DWELL_TIME, 0.05, 1.0)
	_dwell_ring.scale = Vector3.ONE * (0.4 + k * 1.6)
	_dwell_ring.visible = true
	if _dwell_t >= DWELL_TIME:
		_dwell_t = 0.0
		_dwell_ring.visible = false
		inject_click(pos)


## ---- diagnostics + connection test (ship-blocker) ----

func _refresh_diag() -> void:
	if _diag_label == null:
		return
	var boot := "…"
	if _first_frame_s >= 0.0:
		boot = "%.2fs" % _first_frame_s
	elif _stage1_msec > 0:
		boot = "UI %.2fs" % (float(_stage1_msec - _boot_msec) / 1000.0)
	var ctl := _diag_controllers()
	var hands := _diag_hands()
	var gaze := "ready" if not _any_beam_drawn() else "standby"
	var dist := "?"
	var cam := get_viewport().get_camera_3d()
	if cam != null and _panel_root != null:
		dist = "%.1f m" % cam.global_position.distance_to(
				_panel_root.global_position)
	var warn := ""
	if get_viewport().use_xr and _no_beam_s > 3.0:
		warn = "  ⚠ NO INPUT SOURCE LIVE — look at a button and hold 1.2s"
	_diag_label.text = "Controllers: %s · Hands: %s · Gaze: %s · Panel: %s · Boot: first frame %s%s" \
			% [ctl, hands, gaze, dist, boot, warn]


func _diag_controllers() -> String:
	var l := false
	var r := false
	if _xr_origin == null:
		return "none"
	for ctl in _xr_origin.find_children("*", "XRController3D", true, false):
		var c := ctl as XRController3D
		if c == null or c.get_tracker() == null:
			continue
		var nm := String(c.name).to_lower()
		if nm.find("left") >= 0:
			l = true
		elif nm.find("right") >= 0:
			r = true
		else:
			l = true
			r = true
	if l and r:
		return "L+R live"
	if l:
		return "L live"
	if r:
		return "R live"
	return "none"


func _diag_hands() -> String:
	var l := XRServer.get_tracker(&"left_hand") is XRHandTracker \
			and (XRServer.get_tracker(&"left_hand") as XRHandTracker).has_tracking_data
	var r := XRServer.get_tracker(&"right_hand") is XRHandTracker \
			and (XRServer.get_tracker(&"right_hand") as XRHandTracker).has_tracking_data
	if l and r:
		return "L+R"
	if l:
		return "L"
	if r:
		return "R"
	return "none"


func _test_connection() -> void:
	if _ping_in_flight:
		return
	_ping_in_flight = true
	_test_button.disabled = true
	_conn_label.text = "Connection: testing…"
	_conn_label.add_theme_color_override("font_color", C_DIM)
	var payload := {
		"type": "diag_ping",
		"app": "marigold",
		"version": str(ProjectSettings.get_setting(
				"application/config/version", "0.0.0")),
		"ts": int(Time.get_unix_time_from_system()),
		"input": _diag_label.text if _diag_label != null else "",
	}
	_ping_http.request(RELAY_PING_URL,
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, JSON.stringify(payload))


func _on_ping_completed(result: int, response_code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_ping_in_flight = false
	_test_button.disabled = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 \
			and response_code < 300:
		_conn_label.text = "Connection: SUCCESS"
		_conn_label.add_theme_color_override("font_color",
				Color(0.4, 1.0, 0.5))
	else:
		var why := "timeout" if result == HTTPRequest.RESULT_TIMEOUT else \
				("code %d" % response_code if response_code > 0 else "err")
		_conn_label.text = "Connection: FAILED (%s)" % why
		_conn_label.add_theme_color_override("font_color", C_TERRA)
