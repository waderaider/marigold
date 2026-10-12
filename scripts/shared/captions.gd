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


func _ready() -> void:
	instance = self
	_build_panel()


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
		instance._hide_t = 0.0
