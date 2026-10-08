## MarigoldTeleport.gd - marigold-petal themed teleport (v0.6.0).
## Roomscale world-shift teleport: a trail of glowing marigold petals arcs
## to the destination, then a bloom (petal burst + glow pulse) lands the
## arrival. Reuses the petal/particle kit - no new textures.
## Usage: pads call MarigoldTeleport.begin(self, world_node, target_pos)
## once per pinch; the helper animates and shifts the world.
extends RefCounted
class_name MarigoldTeleport

static var _active: Dictionary = {} # node -> {t, from, to, world, arc: Array}


## Begin a teleport: arc preview 0.8 s, then world-shift + bloom.
## world: the chapter's world/stage node to shift. target: world-space dest.
static func begin(node: Node, world: Node3D, target: Vector3) -> bool:
	if _active.has(node):
		return false
	var cam := node.get_viewport().get_camera_3d()
	var from := Vector3(0, 1.2, 0)
	if cam != null:
		from = cam.global_position
	var arc_root := Node3D.new()
	arc_root.name = "TeleportArc"
	node.add_child(arc_root)
	var dots: Array = []
	var petal_mat := MarigoldFX.glow(Color(1.0, 0.62, 0.12), 2.2)
	for i in 14:
		var d := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.03
		pm.height = 0.02
		pm.radial_segments = 8
		pm.rings = 4
		d.mesh = pm
		d.material_override = petal_mat
		var k := float(i) / 13.0
		d.position = _arc_point(from, target, k)
		d.scale = Vector3.ONE * (0.6 + 0.8 * k)
		arc_root.add_child(d)
		dots.append(d)
	_active[node] = {"t": 0.0, "from": from, "to": target, "world": world, "arc": arc_root, "dots": dots}
	return true


static func _arc_point(a: Vector3, b: Vector3, k: float) -> Vector3:
	var p := a.lerp(b, k)
	p.y += sin(k * PI) * 0.9
	return p


## Tick from the chapter's _process. Returns true while a teleport is active.
static func update(node: Node, delta: float) -> bool:
	if not _active.has(node):
		return false
	var st: Dictionary = _active[node]
	st["t"] = float(st["t"]) + delta
	var t: float = st["t"]
	var dots: Array = st["dots"]
	# Petals shimmer along the arc while aiming.
	for i in dots.size():
		var d: MeshInstance3D = dots[i]
		if is_instance_valid(d):
			var s := 0.6 + 0.8 * (float(i) / 13.0)
			d.scale = Vector3.ONE * s * (1.0 + 0.25 * sin(t * 10.0 + float(i)))
	if t >= 0.8:
		var world: Node3D = st["world"]
		var to: Vector3 = st["to"]
		var cam := node.get_viewport().get_camera_3d()
		if world != null and is_instance_valid(world) and cam != null:
			# World-shift: move the world so the target lands under the player.
			var pp := cam.global_position
			var flat_to := Vector3(to.x, 0, to.z)
			var flat_pp := Vector3(pp.x, 0, pp.z)
			world.position += flat_pp - flat_to
			# Arrival bloom: petal burst + spirit-bridge glow ring.
			MarigoldFX.scatter_petals(world.get_parent(), to + Vector3(0, 0.4, 0), 26)
			var ring := MeshInstance3D.new()
			var rm := TorusMesh.new()
			rm.inner_radius = 0.28
			rm.outer_radius = 0.36
			rm.rings = 24
			rm.ring_segments = 8
			ring.mesh = rm
			ring.material_override = MarigoldFX.glow(Color(1.0, 0.72, 0.25), 2.4)
			ring.rotation_degrees.x = 90.0
			ring.position = to + Vector3(0, 0.06, 0)
			world.get_parent().add_child(ring)
			var tw := world.get_parent().create_tween()
			tw.tween_property(ring, "scale", Vector3.ONE * 2.2, 0.7)
			tw.parallel().tween_property(ring, "transparency", 1.0, 0.7)
			tw.tween_callback(ring.queue_free)
			MarigoldHaptics.confirm()
		var arc: Node3D = st["arc"]
		if arc != null and is_instance_valid(arc):
			arc.queue_free()
		_active.erase(node)
		return false
	return true


## A teleport pad marker (pinch to travel). Returns the pad root.
static func make_pad(label_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "TeleportPad"
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.22
	dm.bottom_radius = 0.26
	dm.height = 0.04
	dm.radial_segments = 24
	disc.mesh = dm
	disc.material_override = MarigoldFX.glow(Color(1.0, 0.62, 0.12), 1.4)
	disc.position.y = 0.02
	root.add_child(disc)
	var lab := MarigoldFX.make_label(label_text, 40, Color(1.0, 0.9, 0.6))
	lab.position = Vector3(0, 0.55, 0)
	root.add_child(lab)
	root.set_meta("teleport_pad", true)
	return root


## Pad pulse (call per frame for visible pads).
static func pulse_pad(pad: Node3D, t: float) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	var s := 1.0 + 0.08 * sin(t * 3.0)
	pad.scale = Vector3(s, 1.0, s)
