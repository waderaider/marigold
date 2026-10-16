## captions.gd - MarigoldCaptions: world-anchored caption system (MARIGOLD v0.7.0).
## Comfort & Accessibility spec (COMFORT_V0110.md §4.4): every voiced line gets
## a caption; gated by the Subtitles toggle (default ON).
## API: MarigoldCaptions.show(speaker, text, duration).
## Presentation: world-anchored panel 1.6m in front of camera, 1.35m height,
## static placement per caption (never head-locked; repositioned on each line).
## Headless-safe: builds nodes only, never assumes XR hardware.
extends Node

static var instance: MarigoldCaptions = null

var _panel: Node3D = null
var _speaker_label: Label3D = null
var _text_label: Label3D = null
var _backing: MeshInstance3D = null
var _hide_t := 0.0
var _duration := 0.0
# v0.8.0 PC mode: screen-space caption strip (bottom third), mirroring the
# world-anchored panel. In PC mode the strip replaces the world panel.
var _strip_layer: CanvasLayer = null
var _strip_label: RichTextLabel = null


func _ready() -> void:
	instance = self
	_build_panel()
	_build_strip()


## Screen-space caption strip for PC mode: bottom third, centered, marigold
## speaker name + cream text, semi-opaque dark backing.
func _build_strip() -> void:
	_strip_layer = CanvasLayer.new()
	_strip_layer.layer = 5
	_strip_layer.name = "CaptionStrip"
	add_child(_strip_layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_bottom", 90)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_layer.add_child(margin)
	var align := CenterContainer.new()
	align.set_anchors_preset(Control.PRESET_FULL_RECT)
	align.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-third anchor: push the center container down.
	align.anchor_top = 0.66
	align.offset_top = 0.0
	margin.add_child(align)
	_strip_label = RichTextLabel.new()
	_strip_label.bbcode_enabled = true
	_strip_label.fit_content = true
	_strip_label.scroll_active = false
	_strip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_label.add_theme_font_size_override("normal_font_size", 34)
	_strip_label.add_theme_font_size_override("bold_font_size", 34)
	_strip_label.add_theme_color_override("default_color", Color(1.0, 0.96, 0.88))
	_strip_label.custom_minimum_size = Vector2(900, 0)
	align.add_child(_strip_label)
	_strip_layer.visible = false


func _build_panel() -> void:
	_panel = Node3D.new()
	_panel.name = "CaptionPanel"
	_panel.visible = false
	add_child(_panel)
	# Backing plate: papel-picado dark, high contrast.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 0.5)
	_backing = MeshInstance3D.new()
	_backing.mesh = quad
	var bg := StandardMaterial3D.new()
	bg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.albedo_color = Color(0.08, 0.05, 0.12, 0.88)
	_backing.material_override = bg
	_panel.add_child(_backing)
	# Speaker name: marigold accent, 40px.
	_speaker_label = Label3D.new()
	_speaker_label.font_size = 40
	_speaker_label.modulate = Color(1.0, 0.72, 0.25)
	_speaker_label.position = Vector3(-0.62, 0.14, 0.01)
	_speaker_label.pixel_size = 0.0025
	_panel.add_child(_speaker_label)
	# Text: cream, 40px, 2-line wrap.
	_text_label = Label3D.new()
	_text_label.font_size = 40
	_text_label.modulate = Color(1.0, 0.96, 0.88)
	_text_label.position = Vector3(-0.62, -0.02, 0.01)
	_text_label.pixel_size = 0.0025
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.width = 520.0
	_panel.add_child(_text_label)


func _process(delta: float) -> void:
	var st: Node = get_node_or_null("/root/MarigoldState")
	var pc := st != null and st.has_method("is_pc_mode") \
			and bool(st.call("is_pc_mode"))
	if pc:
		# PC mode: the screen-space strip owns the timer.
		if _strip_layer.visible:
			_hide_t += delta
			if _hide_t >= _duration:
				_strip_layer.visible = false
		return
	if not _panel.visible:
		return
	_hide_t += delta
	if _hide_t >= _duration:
		_panel.visible = false


## Show a caption. Gated by the Subtitles toggle (default ON).
## duration: seconds; if 0, auto-computed from word count.
static func show(speaker: String, text: String, duration: float = 0.0) -> void:
	if instance == null:
		return
	# Subtitles toggle (Comfort spec §3.3-F, default ON).
	if not MarigoldGfx.subtitles_on():
		return
	if duration <= 0.0:
		var words := text.split(" ").size()
		duration = maxf(3.0, float(words) * 0.45)
	# Text size multiplier (Comfort spec §3.1-A).
	var ts := MarigoldGfx.text_scale()
	instance._speaker_label.font_size = int(40 * ts)
	instance._text_label.font_size = int(40 * ts)
	instance._speaker_label.text = speaker
	instance._text_label.text = text
	instance._duration = duration
	instance._hide_t = 0.0
	var st: Node = instance.get_node_or_null("/root/MarigoldState")
	var pc := st != null and st.has_method("is_pc_mode") \
			and bool(st.call("is_pc_mode"))
	if pc:
		# PC mode: mirror to the screen-space strip; the world panel stays
		# hidden (it was built for a headset's view frustum).
		instance._panel.visible = false
		var ts2 := MarigoldGfx.text_scale()
		instance._strip_label.add_theme_font_size_override(
				"normal_font_size", int(34 * ts2))
		instance._strip_label.add_theme_font_size_override(
				"bold_font_size", int(34 * ts2))
		var safe_speaker := speaker.replace("[", "(").replace("]", ")")
		var safe_text := text.replace("[", "(").replace("]", ")")
		instance._strip_label.text = "[center][color=#ffb347][b]%s[/b][/color]\n%s[/center]" \
				% [safe_speaker, safe_text]
		instance._strip_layer.visible = true
		return
	# World-anchored: 1.6m in front of camera, 1.35m height, static per caption.
	var cam := instance.get_viewport().get_camera_3d()
	if cam != null:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var pos: Vector3 = cam.global_position + fwd * 1.6
		pos.y = 1.35
		instance._panel.global_position = pos
		# Face the camera.
		var look := cam.global_position - pos
		look.y = 0.0
		if look.length() > 0.01:
			instance._panel.rotation.y = atan2(-look.x, -look.z)
	instance._panel.visible = true


## Hide immediately (e.g. on chapter exit).
static func hide_now() -> void:
	if instance != null:
		instance._panel.visible = false
		instance._strip_layer.visible = false
		instance._hide_t = 0.0
