## MarigoldPlaques.gd - floating educational info plaques.
## Warm, respectful explanations of real Dia de Muertos traditions.
## Passthrough-readable: billboarded, outlined text, soft glowing frame.
extends RefCounted
class_name MarigoldPlaques


## Build a plaque: title + wrapped body text on a glowing frame.
static func make_plaque(title: String, body: String, width: float = 1.6) -> Node3D:
	var root := Node3D.new()
	root.name = "InfoPlaque"

	var frame := BoxMesh.new()
	frame.size = Vector3(width, width * 0.62, 0.03)
	var frame_mi := MeshInstance3D.new()
	frame_mi.mesh = frame
	var fm := MarigoldFX.pbr(Color(0.10, 0.05, 0.16), 0.2, 0.5)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.55, 0.15)
	fm.emission_energy_multiplier = 0.25
	frame.material = fm
	root.add_child(frame_mi)

	# Marigold trim along the top edge.
	var trim := BoxMesh.new()
	trim.size = Vector3(width, 0.05, 0.035)
	var trim_mi := MeshInstance3D.new()
	trim_mi.mesh = trim
	trim.material = MarigoldFX.glow(Color(1.0, 0.6, 0.1), 1.4)
	trim_mi.position = Vector3(0, width * 0.31 - 0.025, 0)
	root.add_child(trim_mi)

	var title_l := MarigoldFX.make_label(title, 72, Color(1.0, 0.82, 0.45))
	title_l.position = Vector3(0, width * 0.31 - 0.16, 0.03)
	title_l.pixel_size = 0.0035
	root.add_child(title_l)

	var body_l := MarigoldFX.make_label(body, 44, Color(0.98, 0.94, 0.88))
	body_l.position = Vector3(0, 0.02, 0.03)
	body_l.pixel_size = 0.0035
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.width = width / 0.0035 * 0.88
	root.add_child(body_l)

	return root


## Convenience: plaque + placement in one call.
static func place_plaque(parent: Node3D, title: String, body: String, pos: Vector3, width: float = 1.6) -> Node3D:
	var p := make_plaque(title, body, width)
	p.position = pos
	parent.add_child(p)
	# Gentle face-the-player behavior is handled by chapters calling face_player().
	return p


## Rotate a plaque to face the camera (call in _process for active plaques).
static func face_player(plaque: Node3D) -> void:
	var cam := plaque.get_viewport().get_camera_3d()
	if cam == null:
		return
	var look := cam.global_position - plaque.global_position
	look.y = 0.0
	if look.length_squared() < 0.001:
		return
	plaque.rotation.y = atan2(-look.x, -look.z)
