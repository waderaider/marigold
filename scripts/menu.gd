extends Node3D
class_name MarigoldMenu
## MARIGOLD 2D launch menu: a Control UI rendered on a SubViewport quad
## floating ~2m in front of the user, with Dia de Muertos styling.
##
## Input (ported from the proven NEXUS ARCADE v0.7.0 launcher):
## - Quest controllers: visible marigold-orange laser from each controller,
##   trigger press = click. Lasers stay visible whenever the tracker is live.
## - Hand tracking: ray from the index finger, thumb+index pinch = click.
## - Desktop: real mouse forwarded into the panel (only while no XR pointer
##   is live, so there is no double input on device).

signal chapter_chosen(idx: int)
signal experience_chosen(key: String)
signal mode_toggled
signal updates_requested
signal download_requested
signal install_requested

const VP_SIZE := Vector2(1280, 1440)
const QUAD_SIZE := Vector2(1.9, 2.14)
const QUAD_POS := Vector3(0, 1.6, -2.0)

const C_MARIGOLD := Color(1.0, 0.68, 0.18)
const C_CREAM := Color(1.0, 0.93, 0.82)
const C_PLUM := Color(0.16, 0.05, 0.14, 0.96)
const C_PLUM_LIGHT := Color(0.28, 0.10, 0.22, 0.96)
const C_PINK := Color(1.0, 0.35, 0.55)

var _panel_root: Node3D
var _viewport: SubViewport
var _quad: MeshInstance3D
var _pointers: Array[XRUIPointer] = []
var _controllers: Array[XRController3D] = []
var _xr_origin: Node3D = null

var _menu_panel: Control
var _finale_center: Control
var _mode_button: Button
var _status_label: Label
var _version_label: Label
var _download_button: Button
var _install_button: Button
var _chapter_names: Array = []
var _experiences: Array = []


func _ready() -> void:
	_build_panel()
	_build_ui()
	_build_pointers()


func _process(_delta: float) -> void:
	var xr := get_viewport().use_xr
	for p in _pointers:
		if is_instance_valid(p):
			p.xr_mode = xr


func _input(event: InputEvent) -> void:
	if _panel_root == null or not _panel_root.visible:
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
	_build_chapter_buttons()


func set_experiences(exps: Array) -> void:
	_experiences = exps
	_build_experience_buttons()


func show_menu() -> void:
	_panel_root.visible = true
	_menu_panel.visible = true
	_finale_center.visible = false


func hide_menu() -> void:
	_panel_root.visible = false
	_finale_center.visible = false
	_menu_panel.visible = true


func show_finale() -> void:
	_panel_root.visible = true
	_menu_panel.visible = false
	_finale_center.visible = true


func set_status(text: String) -> void:
	_status_label.text = text


func set_mode(ar: bool) -> void:
	_mode_button.text = "Mode: AR Living Room" if ar else "Mode: Immersive World"


func set_version(text: String) -> void:
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


## ---- panel ----

func _build_panel() -> void:
	_panel_root = Node3D.new()
	_panel_root.name = "PanelRoot"
	add_child(_panel_root)

	_viewport = SubViewport.new()
	_viewport.name = "MenuViewport"
	_viewport.size = Vector2i(int(VP_SIZE.x), int(VP_SIZE.y))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = true
	_panel_root.add_child(_viewport)

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
	_quad.position = QUAD_POS
	_panel_root.add_child(_quad)

	# Backdrop glow frame behind the quad (warm marigold rim).
	var frame := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = QUAD_SIZE + Vector2(0.08, 0.08)
	frame.mesh = fq
	frame.material_override = MarigoldFX.glow(C_MARIGOLD, 0.8)
	frame.position = QUAD_POS + Vector3(0, 0, -0.01)
	_panel_root.add_child(frame)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(root)

	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = C_PLUM
	bg_style.border_color = C_MARIGOLD
	bg_style.set_border_width_all(6)
	bg_style.set_corner_radius_all(28)
	bg.add_theme_stylebox_override("panel", bg_style)
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 70)
	margin.add_theme_constant_override("margin_right", 70)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	bg.add_child(margin)

	_menu_panel = VBoxContainer.new()
	_menu_panel.add_theme_constant_override("separation", 18)
	_menu_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_menu_panel)

	_add_label(_menu_panel, "MARIGOLD", 120, C_MARIGOLD)
	_add_label(_menu_panel, "A Dia de Muertos Journey", 46, C_CREAM)
	_add_separator(_menu_panel)
	_add_label(_menu_panel, "A 10-minute guided journey in 5 chapters.\nSelect a chapter to begin.", 36, Color(0.85, 0.78, 0.88))

	var chapters_box := VBoxContainer.new()
	chapters_box.name = "ChaptersBox"
	chapters_box.add_theme_constant_override("separation", 12)
	_menu_panel.add_child(chapters_box)

	_add_label(_menu_panel, "Experiences", 40, C_PINK)
	var exp_box := VBoxContainer.new()
	exp_box.name = "ExperiencesBox"
	exp_box.add_theme_constant_override("separation", 12)
	_menu_panel.add_child(exp_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_panel.add_child(row)

	var begin := _make_button("Begin Journey", 44)
	begin.pressed.connect(func() -> void: chapter_chosen.emit(0))
	row.add_child(begin)

	_mode_button = _make_button("Mode: Immersive World", 40)
	_mode_button.pressed.connect(func() -> void: mode_toggled.emit())
	row.add_child(_mode_button)

	_add_separator(_menu_panel)

	var upd := _make_button("Check for Updates", 40)
	upd.pressed.connect(func() -> void: updates_requested.emit())
	_menu_panel.add_child(upd)

	_download_button = _make_button("Download", 40)
	_download_button.visible = false
	_download_button.pressed.connect(func() -> void: download_requested.emit())
	_menu_panel.add_child(_download_button)

	_install_button = _make_button("Install Update", 40)
	_install_button.visible = false
	_install_button.pressed.connect(func() -> void: install_requested.emit())
	_menu_panel.add_child(_install_button)

	_status_label = _add_label(_menu_panel, "", 34, Color(0.8, 0.8, 0.85))
	_version_label = _add_label(_menu_panel, "", 32, Color(0.6, 0.6, 0.7))
	_add_label(_menu_panel, "Point the laser and pull the trigger (or pinch) to select", 32, Color(0.7, 0.62, 0.72))

	_build_finale(root)


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
	_add_label(box, "Gracias por celebrar", 96, C_MARIGOLD)
	_add_label(box, "Dia de Muertos honra a quienes amamos.\nHasta el proximo ano.", 44, C_CREAM)
	var again := _make_button("Journey Again", 48)
	again.pressed.connect(func() -> void: chapter_chosen.emit(0))
	box.add_child(again)


func _build_chapter_buttons() -> void:
	var box := _menu_panel.get_node_or_null("ChaptersBox") as VBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	for i in range(_chapter_names.size()):
		var info: Dictionary = _chapter_names[i]
		var b := _make_button("%d. %s" % [i + 1, String(info.get("name", "Chapter"))], 44)
		var idx := i
		b.pressed.connect(func() -> void: chapter_chosen.emit(idx))
		box.add_child(b)


func _build_experience_buttons() -> void:
	var box := _menu_panel.get_node_or_null("ExperiencesBox") as VBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	for exp in _experiences:
		var info: Dictionary = exp
		var b := _make_button(String(info.get("name", "Experience")), 44)
		var key := String(info.get("key", ""))
		b.pressed.connect(func() -> void: experience_chosen.emit(key))
		box.add_child(b)


## ---- widget helpers ----

func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _add_separator(parent: Control) -> void:
	var s := HSeparator.new()
	s.add_theme_stylebox_override("separator", _sep_style())
	parent.add_child(s)


func _sep_style() -> StyleBoxLine:
	var st := StyleBoxLine.new()
	st.color = C_MARIGOLD
	st.thickness = 3
	return st


func _make_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", C_MARIGOLD)
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PLUM_LIGHT
	normal.border_color = C_MARIGOLD
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.42, 0.16, 0.30, 0.98)
	hover.border_color = C_PINK
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = C_MARIGOLD
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## ---- input ----

func _build_pointers() -> void:
	_xr_origin = get_parent().get_node_or_null("XROrigin3D") as Node3D
	if _xr_origin != null:
		for side in ["LeftController", "RightController"]:
			var ctl := _xr_origin.get_node_or_null(side) as XRController3D
			if ctl != null:
				_controllers.append(ctl)
				var p := XRUIPointer.new()
				p.name = "Pointer" + side
				p.controller = ctl
				p.setup(_viewport, _quad, _xr_origin)
				p.xr_clicked.connect(_on_pointer_clicked)
				p.xr_moved.connect(_on_pointer_moved)
				_panel_root.add_child(p)
				_pointers.append(p)
	# Hand pointers discover their XRHandTracker lazily.
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT, XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var hp := XRUIPointer.new()
		hp.name = "PointerHand%d" % side
		hp.hand_side = side
		hp.setup(_viewport, _quad, _xr_origin)
		hp.xr_clicked.connect(_on_pointer_clicked)
		hp.xr_moved.connect(_on_pointer_moved)
		_panel_root.add_child(hp)
		_pointers.append(hp)


func _on_pointer_moved(viewport_pos: Vector2) -> void:
	if _viewport == null:
		return
	var ev := InputEventMouseMotion.new()
	ev.position = viewport_pos
	_viewport.push_input(ev)


func _on_pointer_clicked(viewport_pos: Vector2) -> void:
	if _viewport == null:
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = viewport_pos
	_viewport.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = viewport_pos
	_viewport.push_input(release)


func _xr_pointer_live() -> bool:
	if not get_viewport().use_xr:
		return false
	for p in _pointers:
		if is_instance_valid(p) and p.is_source_live():
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
