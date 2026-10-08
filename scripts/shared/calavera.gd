## MarigoldCalavera.gd - shared calavera (skeleton celebrant) troupe system.
## v0.5.0: one builder + one beat-synced choreography driver used by the
## Ofrenda Viva night sequence (ch1) and El Gran Baile: Espejo.
## Dancers are the real Kenney skeleton model (CC0) dressed with glowing
## marigold eyes, a garland and an accent sash. The model has no rig, so
## choreography is whole-body: beat-quantized hops, sway, spins, bows.
extends RefCounted
class_name MarigoldCalavera


## Build a dressed skeleton dancer. Returns {"root": Node3D, "body": Node3D}.
static func make_dancer(accent: Color, dancer_scale: float = 1.0) -> Dictionary:
	var root := Node3D.new()
	root.name = "Calavera"
	var skel: Node3D = MarigoldModels.instance(MarigoldModels.GRAVEYARD, "character-skeleton")
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	if skel != null:
		MarigoldModels.recolor(skel, Color(0.93, 0.87, 0.74), 0.0, 0.55)
		body.add_child(skel)
		var eye_m := MarigoldFX.glow(Color(1.0, 0.60, 0.12), 2.6)
		for sx in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.022
			em.height = 0.04
			eye.mesh = em
			eye.material_override = eye_m
			eye.position = Vector3(0.055 * sx, 0.615, 0.105)
			skel.add_child(eye)
		for gi in 8:
			var ga := TAU * float(gi) / 8.0
			var bead := MeshInstance3D.new()
			var gm := SphereMesh.new()
			gm.radius = 0.020
			gm.height = 0.035
			bead.mesh = gm
			bead.material_override = MarigoldFX.glow(Color(1.0, 0.60, 0.10), 2.0) \
				if gi % 2 == 0 else MarigoldFX.pbr(accent, 0.1, 0.5)
			bead.position = Vector3(cos(ga) * 0.115, 0.50, sin(ga) * 0.115)
			skel.add_child(bead)
		var sash := MeshInstance3D.new()
		var sm := TorusMesh.new()
		sm.inner_radius = 0.13
		sm.outer_radius = 0.16
		sm.rings = 20
		sm.ring_segments = 8
		sash.mesh = sm
		sash.material_override = MarigoldFX.glow(accent, 1.4)
		sash.position = Vector3(0, 0.38, 0)
		sash.rotation_degrees.x = 12.0
		skel.add_child(sash)
	body.scale = Vector3.ONE * 2.64 # 0.72 m model -> dancer height
	root.scale = Vector3.ONE * dancer_scale
	return {"root": root, "body": body}


## Beat-synced dance step. Call every frame per dancer.
## d: {"root","body","phase","style","base_y","base_rot"} (+ "energy", "spin_dir")
## beat_phase: 0..1 from MarigoldMusic.get_beat_phase() (-1 = idle sway).
## style: 0 bounce, 1 sway, 2 spin.
static func dance_update(d: Dictionary, beat_phase: float, t: float, delta: float) -> void:
	var root: Node3D = d["root"]
	if root == null or not is_instance_valid(root):
		return
	var style: int = int(d.get("style", 0))
	var energy: float = float(d.get("energy", 1.0))
	var ph: float = float(d.get("phase", 0.0))
	var base_y: float = float(d.get("base_y", 0.0))
	var base_rot: float = float(d.get("base_rot", 0.0))
	var tt := t * 2.0 + ph
	# Beat pulse: sharp hop right on the beat, decaying through the bar.
	var pulse := 0.0
	if beat_phase >= 0.0:
		pulse = pow(1.0 - beat_phase, 2.0)
	else:
		pulse = 0.5 + 0.5 * sin(tt * 2.2) # idle: gentle groove
	match style:
		0: # bounce: hop on the beat
			root.position.y = base_y + pulse * 0.16 * energy + absf(sin(tt)) * 0.03
			root.rotation.z = sin(tt * 0.5) * 0.07
			root.rotation.y = base_rot + sin(tt * 0.25) * 0.12
		1: # sway: hips swing, counter-phase lean
			root.position.y = base_y + pulse * 0.07 * energy
			root.rotation.z = sin(tt) * 0.20 * energy
			root.rotation.x = sin(tt * 0.5 + 1.2) * 0.06
			root.rotation.y = base_rot + sin(tt * 0.5) * 0.35
		_: # spin: slow turn with beat hops
			root.rotation.y += delta * 1.4 * float(d.get("spin_dir", 1.0)) * energy
			root.position.y = base_y + pulse * 0.10 * energy
			root.rotation.z = sin(tt * 2.0) * 0.10


## Face the dancer toward a world position (the player).
static func face_player(root: Node3D, target: Vector3) -> void:
	if root == null or not is_instance_valid(root):
		return
	var look := target - root.global_position
	look.y = 0.0
	if look.length_squared() < 0.001:
		return
	root.rotation.y = atan2(-look.x, -look.z)


## Bow depth 0..1: leans the body forward. Animate 0 -> 1 -> hold -> 0.
static func set_bow(d: Dictionary, amount: float) -> void:
	var body: Node3D = d.get("body")
	if body == null or not is_instance_valid(body):
		return
	body.rotation.x = clampf(amount, 0.0, 1.0) * 0.65


## Sink-and-fade exit: drops the dancer into the ground with a petal burst.
static func begin_exit(d: Dictionary, parent: Node) -> void:
	var root: Node3D = d.get("root")
	if root == null or not is_instance_valid(root):
		return
	d["exiting"] = true
	d["exit_t"] = 0.0
	MarigoldFX.scatter_petals(parent, root.global_position + Vector3(0, 0.9, 0), 18)


## Advance an exiting dancer; returns true when fully gone.
static func update_exit(d: Dictionary, delta: float) -> bool:
	var root: Node3D = d.get("root")
	if root == null or not is_instance_valid(root):
		return true
	var t: float = float(d.get("exit_t", 0.0)) + delta
	d["exit_t"] = t
	var k := clampf(t / 1.6, 0.0, 1.0)
	root.position.y = float(d.get("base_y", 0.0)) - k * 1.9
	var s := 1.0 - k * 0.25
	root.scale = Vector3.ONE * s * float(d.get("dancer_scale", 1.0))
	if k >= 1.0:
		root.queue_free()
		return true
	return false
