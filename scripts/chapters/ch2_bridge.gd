## ch2_bridge.gd - MARIGOLD Chapter 2: The Marigold Bridge.
## A glowing bridge of marigold petals spans luminous water between two
## stone arches. The player walks through 5 waypoint rings; each ring
## reveals the next line of the cempasúchil legend. Passing the far arch
## triggers petal fireworks, then chapter_complete.
## No class_name (chapter contract). Headless-safe: no XR hardware required.
extends Node3D

signal chapter_complete

const RING_COUNT := 5
const RING_TRIGGER_DIST := 1.1
const ARCH_TRIGGER_DIST := 1.4
const BRIDGE_LENGTH := 22.0

const LEGEND := [
	"Long ago, the love of two young souls moved the gods, and from their memory bloomed a new flower.",
	"They called it cempasúchil — the flower of twenty petals — blazing orange like the sun at dusk.",
	"Its vivid color and sweet scent guide the spirits of the departed back to the world of the living.",
	"On Día de Muertos, families scatter its petals to lay a glowing path between the worlds.",
	"Walk the bridge of petals. Those we love are never truly gone while we remember them.",
]
const NUMERALS := ["I", "II", "III", "IV", "V"]

var _ar_mode := false
var _bridge: Node3D
var _backdrop: Node3D
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[StandardMaterial3D] = []
var _ring_done: Array[bool] = []
var _rings_reached := 0
var _plaque: Node3D
var _plaque_title: Label3D
var _plaque_body: Label3D
var _far_arch: Node3D
var _finished := false
var _t := 0.0
# Rich dressing.
var _lanterns: Array[Node3D] = []
var _lantern_mats: Array[StandardMaterial3D] = []
var _lantern_phase: Array[float] = []
var _blossoms: Array[MeshInstance3D] = []
var _blossom_base: Array[Vector3] = []
var _blossom_phase: Array[float] = []
var _city: Node3D
var _drift: GPUParticles3D
var _fireflies: Array[GPUParticles3D] = []
var _shocks: Array[Dictionary] = []
var _toast_label: Label3D
var _toast_time := 0.0
# Wind + physics integration (v0.4.0).
var _sway_mats := {} # emission hex -> MarigoldSky.wind_sway_material cache


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	_update_plaque(-1)
	_toast("Cross the bridge — pass through each glowing ring", 7.0)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _bridge == null:
		return
	if on:
		# Shorten the bridge to fit a living room, then clamp waypoints.
		_bridge.scale.z = 0.5
		for r in _rings:
			r.global_position = MarigoldHands.clamp_to_room(r.global_position)
		_far_arch.global_position = MarigoldHands.clamp_to_room(_far_arch.global_position)
		_plaque.global_position = MarigoldHands.clamp_to_room(_plaque.global_position)
	else:
		_bridge.scale.z = 1.0
		_layout_bridge()
		_plaque.position = Vector3(1.9, 1.6, 1.2)
	if _backdrop:
		_backdrop.visible = not on
	# Big set pieces stay in the immersive world.
	if _city:
		_city.visible = not on
	if _drift:
		_drift.emitting = not on
	for f in _fireflies:
		f.emitting = not on


func _process(delta: float) -> void:
	_t += delta
	if _plaque:
		MarigoldPlaques.face_player(_plaque)
	# Toast fade.
	if _toast_time > 0.0 and _toast_label:
		_toast_time -= delta
		var c := _toast_label.modulate
		c.a = clampf(_toast_time, 0.0, 1.0)
		_toast_label.modulate = c
	# Gentle pulse on unreached rings.
	for i in _rings.size():
		if not _ring_done[i]:
			MarigoldFX.pulse_glow(_ring_mats[i], 1.2, 0.6, _t + float(i) * 0.9, 2.5)
	# Lantern sway + breathing glow, driven by the wind (directional swing).
	var wind := _wind_strength()
	for i in _lanterns.size():
		if not is_instance_valid(_lanterns[i]):
			continue
		var wvec := _wind_at(_lanterns[i].global_position)
		var gust := 1.0 + wind * 3.0
		_lanterns[i].rotation.z = sin(_t * 0.8 + _lantern_phase[i]) * 0.07 * gust + wvec.x * 0.35
		_lanterns[i].rotation.x = cos(_t * 0.6 + _lantern_phase[i]) * 0.05 * gust - wvec.z * 0.35
		MarigoldFX.pulse_glow(_lantern_mats[i], 1.6, 0.45 * (0.6 + wind * 3.2), _t + _lantern_phase[i], 1.8)
	_update_sway_wind()
	# Blossoms bobbing on the water.
	for i in _blossoms.size():
		var b := _blossoms[i]
		var bp: Vector3 = _blossom_base[i]
		bp.y += sin(_t * 0.9 + _blossom_phase[i]) * 0.045
		bp.x += sin(_t * 0.35 + _blossom_phase[i] * 1.3) * 0.06
		b.global_position = bp
	# Spirit-gate shockwaves expand and fade.
	for s in _shocks:
		s["t"] = float(s["t"]) + delta * 1.3
		var n: Node3D = s["node"]
		var m: StandardMaterial3D = s["mat"]
		var k: float = float(s["t"])
		n.scale = Vector3.ONE * (1.0 + k * 3.5)
		var mc := m.albedo_color
		mc.a = clampf(1.0 - k, 0.0, 1.0)
		m.albedo_color = mc
	# Remove finished shockwaves.
	for i in range(_shocks.size() - 1, -1, -1):
		if float(_shocks[i]["t"]) >= 1.0:
			(_shocks[i]["node"] as Node).queue_free()
			_shocks.remove_at(i)
	if _finished:
		return
	_check_waypoints()


## Transient feedback toast.
func _toast(text: String, dur: float = 2.5) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_time = dur


## Short musical feedback via the shared music player (autoload-safe).
func _sfx(note: int, vol: float = 0.7, dur: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var st := get_tree().root.get_node_or_null("MarigoldState")
	if st == null:
		return
	var m = st.get("music")
	if m != null and m.has_method("pluck"):
		m.call("pluck", note, vol, dur)


## ---------------- wind + physics (v0.4.0) ----------------

## Null-safe wind reads (headless tests may lack the sky singleton).
func _wind_strength() -> float:
	if MarigoldSky.instance != null:
		return MarigoldSky.instance.get_wind_strength()
	return 0.0


func _wind_at(pos: Vector3) -> Vector3:
	if MarigoldSky.instance != null:
		return MarigoldSky.instance.get_wind_at(pos)
	return Vector3.ZERO


## Give a flower field cloth-like sway via the shared wind shader.
func _apply_field_sway(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var src: Material = mi.get_active_material(0)
			if src is StandardMaterial3D and (src as StandardMaterial3D).emission_enabled:
				var tint: Color = (src as StandardMaterial3D).emission
				var key := tint.to_html()
				if not _sway_mats.has(key):
					_sway_mats[key] = MarigoldSky.wind_sway_material(tint, 0.5)
				mi.material_override = _sway_mats[key] as ShaderMaterial
		for c in n.get_children():
			stack.append(c)


## Push gust strength into our sway materials (the sky does this too when live).
func _update_sway_wind() -> void:
	if MarigoldSky.instance == null:
		return
	var w := MarigoldSky.instance.get_wind_strength()
	for m in _sway_mats.values():
		(m as ShaderMaterial).set_shader_parameter("wind_strength", w)


## Invisible static collider so dynamic props rest on a support surface.
static func _static_box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "SupportCol"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = center
	body.add_child(col)
	parent.add_child(body)


## Convert a decorative prop into a real rigid body; the collision shape is
## recentered on the visual AABB so the prop rests exactly on its support.
static func _make_prop_dynamic(node: Node3D, shape: String, mass: float) -> RigidBody3D:
	var body := MarigoldSky.make_dynamic(node, shape, mass)
	var box := AABB()
	var found := false
	var to_local: Transform3D = node.global_transform.affine_inverse()
	for mi in node.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var mab: AABB = to_local * m.global_transform * m.get_aabb()
		box = mab if not found else box.merge(mab)
		found = true
	if found:
		for c in body.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).position = box.get_center()
				break
	return body


## ---------------- build ----------------

func _build() -> void:
	# Luminous water under everything.
	var water := MarigoldFX.make_luminous_water(self, 44.0)
	water.position.y = -0.5

	_bridge = Node3D.new()
	_bridge.name = "Bridge"
	add_child(_bridge)
	_layout_bridge()

	# Far stone arch (the exit; walking through ends the chapter).
	_far_arch = _make_stone_arch(Vector3(0, 0, -BRIDGE_LENGTH * 0.5 - 0.5), true)
	_bridge.add_child(_far_arch)

	# Legend plaque near the start.
	_plaque = MarigoldPlaques.place_plaque(self, "The Marigold Bridge", "", Vector3(1.9, 1.6, 1.2), 1.7)
	_plaque_title = null
	_plaque_body = null
	var found: Array[Label3D] = []
	for c in _plaque.get_children():
		if c is Label3D:
			found.append(c)
	if found.size() >= 2:
		_plaque_title = found[0]
		_plaque_body = found[1]

	# Backdrop: god rays, marigold banks, motes (hidden in AR).
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	MarigoldFX.make_god_ray(_backdrop, Vector3(0, 0, -BRIDGE_LENGTH * 0.5 - 0.5), 9.0)
	MarigoldFX.make_god_ray(_backdrop, Vector3(0, 0, 2.5), 9.0, Color(1.0, 0.5, 0.7))
	# Marigold banks sway with the wind.
	var bank_l := MarigoldModels.make_flower_field(_backdrop, 110, 5.0, 11)
	bank_l.position = Vector3(-4.5, -0.4, -6.0)
	_apply_field_sway(bank_l)
	var bank_r := MarigoldModels.make_flower_field(_backdrop, 110, 5.0, 22)
	bank_r.position = Vector3(4.5, -0.4, -12.0)
	_apply_field_sway(bank_r)
	MarigoldFX.spawn_ambient_motes(_backdrop, Vector3(0, 2.0, -9.0), 4.0, 50)

	# Layered dressing: fireflies, petal drift, city, blossoms.
	# (Lanterns are built inside _layout_bridge so they rebuild on toggles.)
	_build_fireflies()
	_build_petal_drift()
	_build_city()
	_build_floating_blossoms()

	# Toast label for feedback near the start.
	_toast_label = MarigoldFX.make_label("", 52, Color(1.0, 0.95, 0.80))
	_toast_label.position = Vector3(0, 2.7, 1.6)
	add_child(_toast_label)


## (Re)lays out deck, rings and start arch in bridge-local coordinates.
## Preserves waypoint progress and the far arch across mode toggles.
func _layout_bridge() -> void:
	var saved_done: Array[bool] = _ring_done.duplicate()
	var saved_reached := _rings_reached
	for c in _bridge.get_children():
		if c == _far_arch:
			continue # the exit arch persists; never rebuild it
		c.queue_free()
	_rings.clear()
	_ring_mats.clear()
	_ring_done.clear()
	_lanterns.clear()
	_lantern_mats.clear()
	_lantern_phase.clear()

	# Deck: glowing petal bridge.
	var deck := BoxMesh.new()
	deck.size = Vector3(1.8, 0.15, BRIDGE_LENGTH)
	var deck_mi := MeshInstance3D.new()
	deck_mi.mesh = deck
	var deck_mat := MarigoldFX.pbr(Color(0.30, 0.12, 0.04), 0.1, 0.6)
	deck_mat.emission_enabled = true
	deck_mat.emission = Color(1.0, 0.45, 0.08)
	deck_mat.emission_energy_multiplier = 0.55
	deck.material = deck_mat
	deck_mi.position = Vector3(0, -0.075, -BRIDGE_LENGTH * 0.5 + 2.0)
	_bridge.add_child(deck_mi)
	# Static collider so loose blossoms below rest on the deck.
	_static_box(_bridge, Vector3(0, -0.075, -BRIDGE_LENGTH * 0.5 + 2.0),
		Vector3(1.8, 0.15, BRIDGE_LENGTH))

	# Glowing edge rails.
	var rail_mat := MarigoldFX.glow(Color(1.0, 0.62, 0.12), 1.6)
	for rx in [-0.95, 0.95]:
		var rail := BoxMesh.new()
		rail.size = Vector3(0.08, 0.10, BRIDGE_LENGTH)
		var rail_mi := MeshInstance3D.new()
		rail_mi.mesh = rail
		rail_mi.material_override = rail_mat
		rail_mi.position = Vector3(rx, 0.05, -BRIDGE_LENGTH * 0.5 + 2.0)
		_bridge.add_child(rail_mi)

	# Marigold strip down the center of the deck: real flowers (Kenney CC0).
	# The strip sways with the wind; a few loose center blossoms are real
	# rigid bodies (they rest on the deck collider above).
	var strip := MarigoldModels.make_flower_field(_bridge, 90, 0.85, 33)
	strip.position = Vector3(0, 0.05, -BRIDGE_LENGTH * 0.5 + 2.0)
	_apply_field_sway(strip)
	var dyn_count := 0
	for child in strip.get_children():
		if dyn_count >= 4:
			break
		if child is Node3D:
			var cp: Vector3 = (child as Node3D).position
			if Vector2(cp.x, cp.z).length() < 0.45:
				_make_prop_dynamic(child as Node3D, "sphere", 0.25)
				dyn_count += 1

	# Start arch (decorative) and 5 waypoint rings.
	_bridge.add_child(_make_stone_arch(Vector3(0, 0, 2.5), false))
	for i in RING_COUNT:
		var z := 0.0 - float(i) * 4.5
		var ring := _make_ring(Vector3(0, 1.25, z))
		_bridge.add_child(ring)
		_rings.append(ring)
		# Restore progress across mode toggles.
		var was_done := i < saved_done.size() and saved_done[i]
		_ring_done.append(was_done)
		if was_done:
			_ring_mats[i].emission_energy_multiplier = 3.2
			ring.scale *= 1.12
	_rings_reached = saved_reached
	# Lanterns hang from the bridge and rebuild with it.
	_build_lanterns()


func _make_ring(pos: Vector3) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 0.95
	torus.rings = 24
	torus.ring_segments = 12
	var mat := MarigoldFX.glow(Color(1.0, 0.60, 0.10), 1.2)
	torus.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.rotation_degrees.x = 90.0
	mi.position = pos
	_ring_mats.append(mat)
	return mi


func _make_stone_arch(pos: Vector3, is_exit: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "FarArch" if is_exit else "StartArch"
	root.position = pos
	var stone := MarigoldFX.pbr(Color(0.45, 0.42, 0.48), 0.05, 0.85)
	# Real carved stone pillars (Kenney CC0) instead of boxes.
	for px in [-1.5, 1.5]:
		var pillar_m := MarigoldModels.instance(MarigoldModels.FANTASY, "pillar-stone")
		if pillar_m != null:
			MarigoldModels.recolor(pillar_m, Color(0.48, 0.44, 0.52), 0.05, 0.85)
			pillar_m.position = Vector3(px, 0, 0)
			pillar_m.scale = Vector3(1.6, 2.6, 1.6)
			root.add_child(pillar_m)
		else:
			var pillar := BoxMesh.new()
			pillar.size = Vector3(0.6, 3.4, 0.6)
			var pmi := MeshInstance3D.new()
			pmi.mesh = pillar
			pmi.material_override = stone
			pmi.position = Vector3(px, 1.7, 0)
			root.add_child(pmi)
	var beam := BoxMesh.new()
	beam.size = Vector3(3.8, 0.6, 0.7)
	var bmi := MeshInstance3D.new()
	bmi.mesh = beam
	bmi.material_override = stone
	bmi.position = Vector3(0, 3.6, 0)
	root.add_child(bmi)
	# Marigold trim across the beam: real flowers (Kenney CC0).
	MarigoldModels.make_flower_row(root, Vector3(-1.9, 3.32, 0), Vector3(1.9, 3.32, 0), 10, 7 if is_exit else 8)
	if is_exit:
		# Extra glow marks the exit.
		var halo := _make_ring(Vector3(0, 1.6, 0))
		halo.scale = Vector3(1.35, 1.35, 1.35)
		root.add_child(halo)
	return root


## ---------------- layered dressing ----------------

## Paper lanterns hanging over the bridge, swaying gently.
func _build_lanterns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var glow_colors := [Color(1.0, 0.55, 0.20), Color(1.0, 0.40, 0.45), Color(1.0, 0.70, 0.30)]
	for i in 8:
		var z := 1.5 - float(i) * 2.75
		var x := 1.7 if i % 2 == 0 else -1.7
		var lantern := _make_lantern(glow_colors[i % glow_colors.size()])
		lantern.position = Vector3(x + rng.randf_range(-0.2, 0.2), 4.6, z)
		_bridge.add_child(lantern)
		_lanterns.append(lantern)
		_lantern_phase.append(rng.randf() * TAU)
	# Two grand lanterns flanking the entrance.
	for x in [-2.2, 2.2]:
		var post := CylinderMesh.new()
		post.top_radius = 0.05
		post.bottom_radius = 0.06
		post.height = 3.6
		var pmi := MeshInstance3D.new()
		pmi.mesh = post
		pmi.material_override = MarigoldFX.pbr(Color(0.20, 0.10, 0.08), 0.0, 0.8)
		pmi.position = Vector3(x, 1.8, 2.8)
		_bridge.add_child(pmi)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.9, 0.06, 0.06)
		var ami := MeshInstance3D.new()
		ami.mesh = arm
		ami.material_override = MarigoldFX.pbr(Color(0.20, 0.10, 0.08), 0.0, 0.8)
		ami.position = Vector3(x - 0.4 * signf(x), 3.55, 2.8)
		_bridge.add_child(ami)
		var lantern := _make_lantern(Color(1.0, 0.60, 0.20))
		lantern.position = Vector3(x - 0.8 * signf(x), 3.55, 2.8)
		_bridge.add_child(lantern)
		_lanterns.append(lantern)
		_lantern_phase.append(rng.randf() * TAU)


func _make_lantern(glow_color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Lantern"
	var line := CylinderMesh.new()
	line.top_radius = 0.008
	line.bottom_radius = 0.008
	line.height = 0.55
	var lmi := MeshInstance3D.new()
	lmi.mesh = line
	lmi.material_override = MarigoldFX.pbr(Color(0.08, 0.06, 0.05), 0.0, 0.9)
	lmi.position.y = -0.275
	root.add_child(lmi)
	var mat := MarigoldFX.glow(glow_color, 2.2)
	# Real paper lantern model (Kenney CC0); falls back to the primitive body.
	var km := MarigoldModels.instance(MarigoldModels.FANTASY, "lantern")
	if km != null:
		MarigoldModels.recolor_glow(km, glow_color, glow_color, 2.2)
		km.position.y = -0.75
		km.scale = Vector3.ONE * 1.4
		root.add_child(km)
	else:
		var body := SphereMesh.new()
		body.radius = 0.17
		body.height = 0.38
		var bmi := MeshInstance3D.new()
		bmi.mesh = body
		bmi.material_override = mat
		bmi.scale = Vector3(1.0, 1.12, 1.0)
		bmi.position.y = -0.75
		root.add_child(bmi)
	var cap_mat := MarigoldFX.pbr(Color(0.45, 0.10, 0.08), 0.0, 0.7)
	for cy in [-0.55, -0.95]:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.06
		cap.bottom_radius = 0.06
		cap.height = 0.045
		var cmi := MeshInstance3D.new()
		cmi.mesh = cap
		cmi.material_override = cap_mat
		cmi.position.y = cy
		root.add_child(cmi)
	_lantern_mats.append(mat)
	return root


## Spirit moths / fireflies drifting in looping particle clouds.
func _build_fireflies() -> void:
	var cfgs := [
		{"c": Color(1.0, 0.80, 0.30), "pos": Vector3(0, 1.8, -9.0), "ext": Vector3(2.5, 1.6, 10.0)},
		{"c": Color(0.50, 0.90, 1.00), "pos": Vector3(0, 0.7, -9.0), "ext": Vector3(6.0, 1.0, 12.0)},
	]
	for cfg in cfgs:
		var p := GPUParticles3D.new()
		p.amount = 55
		p.lifetime = 6.0
		p.preprocess = 6.0
		p.position = cfg["pos"]
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = cfg["ext"]
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 180.0
		pm.initial_velocity_min = 0.10
		pm.initial_velocity_max = 0.35
		pm.gravity = Vector3.ZERO
		pm.scale_min = 0.015
		pm.scale_max = 0.04
		pm.color = cfg["c"]
		p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.035, 0.035)
		quad.material = MarigoldFX.glow(cfg["c"], 2.2)
		p.draw_pass_1 = quad
		add_child(p)
		p.emitting = true
		_fireflies.append(p)


## Petals drifting down through the air along the whole bridge.
func _build_petal_drift() -> void:
	_drift = GPUParticles3D.new()
	_drift.amount = 90
	_drift.lifetime = 8.0
	_drift.preprocess = 8.0
	_drift.position = Vector3(0, 2.4, -9.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.0, 2.5, 12.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.10
	pm.initial_velocity_max = 0.30
	pm.gravity = Vector3(0, -0.15, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.030
	pm.scale_max = 0.060
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.62, 0.10))
	grad.add_point(0.5, Color(1.0, 0.80, 0.25))
	grad.set_color(1, Color(0.85, 0.35, 0.05))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	_drift.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.035)
	quad.material = MarigoldFX.glow(Color(1.0, 0.65, 0.12), 1.8)
	_drift.draw_pass_1 = quad
	add_child(_drift)
	_drift.emitting = true


## Distant glowing city silhouette across the water (the Land of the Dead).
func _build_city() -> void:
	_city = Node3D.new()
	_city.name = "FarCity"
	_city.position = Vector3(0, -0.5, -38.0)
	add_child(_city)
	var win_shader := Shader.new()
	win_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base : source_color = vec4(0.05, 0.04, 0.10, 1.0);
uniform vec4 win_on : source_color = vec4(1.0, 0.70, 0.30, 1.0);
uniform vec4 win_off : source_color = vec4(0.10, 0.09, 0.16, 1.0);
void fragment() {
	vec2 g = vec2(UV.x * 14.0, UV.y * 22.0);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float lit = step(0.55, fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453));
	float win = step(0.20, f.x) * (1.0 - step(0.80, f.x)) * step(0.25, f.y) * (1.0 - step(0.75, f.y));
	vec3 col = mix(win_off.rgb, win_on.rgb, lit * win);
	ALBEDO = mix(base.rgb, col, win);
	EMISSION = win_on.rgb * lit * win * 0.9;
}
"""
	var win_mat := ShaderMaterial.new()
	win_mat.shader = win_shader
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var dark := MarigoldFX.pbr(Color(0.06, 0.05, 0.12), 0.0, 0.9)
	var x := -22.0
	while x < 22.0:
		var w := rng.randf_range(2.2, 4.2)
		var h := rng.randf_range(3.0, 9.5)
		var d := rng.randf_range(2.0, 3.2)
		var bld := BoxMesh.new()
		bld.size = Vector3(w, h, d)
		var bmi := MeshInstance3D.new()
		bmi.mesh = bld
		bmi.material_override = dark
		bmi.position = Vector3(x + w * 0.5, h * 0.5, rng.randf_range(-1.5, 1.5))
		_city.add_child(bmi)
		var face := PlaneMesh.new()
		face.size = Vector2(w * 0.96, h * 0.96)
		face.material = win_mat
		var fmi := MeshInstance3D.new()
		fmi.mesh = face
		fmi.position = bmi.position + Vector3(0, 0, d * 0.5 + 0.02)
		_city.add_child(fmi)
		x += w + rng.randf_range(0.8, 2.2)
	# Warm glow strip: the city's lights on the water.
	var strip := BoxMesh.new()
	strip.size = Vector3(46.0, 0.06, 1.4)
	var smi := MeshInstance3D.new()
	smi.mesh = strip
	smi.material_override = MarigoldFX.glow(Color(1.0, 0.60, 0.20), 0.9)
	smi.position = Vector3(0, 0.12, 2.5)
	_city.add_child(smi)
	# A few far celebratory lights in the sky.
	for i in 3:
		var fl := SphereMesh.new()
		fl.radius = 0.35
		fl.height = 0.6
		var fmi2 := MeshInstance3D.new()
		fmi2.mesh = fl
		fmi2.material_override = MarigoldFX.glow(Color(1.0, 0.55, 0.25), 1.6)
		fmi2.position = Vector3(-12.0 + float(i) * 12.0, 8.0 + float(i) * 1.5, -3.0)
		_city.add_child(fmi2)
	# Windmill silhouette (Kenney CC0) on the skyline.
	var mill := MarigoldModels.place(_city, MarigoldModels.FANTASY, "windmill", Vector3(14.0, 0, -2.0), -12.0, 2.2)
	if mill != null:
		MarigoldModels.recolor(mill, Color(0.10, 0.08, 0.16), 0.0, 0.9)


## Marigold blossoms floating on the luminous water.
func _build_floating_blossoms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var orange := MarigoldFX.glow(Color(1.0, 0.60, 0.10), 1.7)
	var yellow := MarigoldFX.glow(Color(1.0, 0.80, 0.20), 1.7)
	for i in 26:
		var bl := SphereMesh.new()
		bl.radius = 0.055
		bl.height = 0.07
		var bmi := MeshInstance3D.new()
		bmi.mesh = bl
		bmi.material_override = orange if i % 2 == 0 else yellow
		var pos := Vector3(rng.randf_range(-9.0, 9.0), -0.40, rng.randf_range(-20.0, 2.0))
		bmi.position = pos
		add_child(bmi)
		_blossoms.append(bmi)
		_blossom_base.append(pos)
		_blossom_phase.append(rng.randf() * TAU)


## ---------------- progression ----------------

func _camera_pos() -> Vector3:
	var vp := get_viewport()
	if vp == null:
		return Vector3(0, 1.6, 1.5)
	var cam := vp.get_camera_3d()
	if cam:
		return cam.global_position
	return Vector3(0, 1.6, 1.5)


func _check_waypoints() -> void:
	var cam := _camera_pos()
	# Waypoint rings.
	var ring_notes := [62, 64, 67, 69, 72]
	for i in _rings.size():
		if _ring_done[i]:
			continue
		if cam.distance_to(_rings[i].global_position) < RING_TRIGGER_DIST:
			_ring_done[i] = true
			_rings_reached += 1
			_ring_mats[i].emission_energy_multiplier = 3.2
			_rings[i].scale *= 1.12
			var feet := Vector3(cam.x, 0.08, cam.z)
			MarigoldFX.scatter_petals(self, feet, 35)
			MarigoldFX.spawn_sparks(self, _rings[i].global_position, Color(1.0, 0.75, 0.25), 16)
			MarigoldHaptics.thump()
			_sfx(ring_notes[i], 0.75, 1.2)
			_toast("Ring %s of V — the legend unfolds" % NUMERALS[i])
			_update_plaque(i)
	# Far arch: walk through to finish.
	if is_instance_valid(_far_arch):
		var arch_center: Vector3 = _far_arch.global_position + Vector3(0, 1.4, 0)
		if cam.distance_to(arch_center) < ARCH_TRIGGER_DIST:
			_finish()


func _update_plaque(ring_idx: int) -> void:
	if _plaque_body == null:
		return
	if ring_idx < 0:
		_plaque_title.text = "The Marigold Bridge"
		_plaque_body.text = "Walk the bridge. Pass through each glowing ring to hear the legend of the cempasúchil."
	else:
		_plaque_title.text = "The Legend — %s of %s" % [NUMERALS[ring_idx], NUMERALS[RING_COUNT - 1]]
		_plaque_body.text = LEGEND[ring_idx]


func _finish() -> void:
	_finished = true
	var cam := _camera_pos()
	MarigoldFX.scatter_petals(self, Vector3(cam.x, 1.2, cam.z), 60)
	MarigoldFX.spawn_confetti(self, Vector3(cam.x, 2.0, cam.z - 1.0), 80)
	MarigoldFX.spawn_sparks(self, _far_arch.global_position + Vector3(0, 2.5, 0), Color(1.0, 0.7, 0.2), 40)
	if _plaque_body:
		_plaque_title.text = "The Crossing"
		_plaque_body.text = "You have crossed the bridge of petals. The celebration continues in the Land of the Dead."
	_toast("The spirit gate opens!", 3.5)
	# Second beat: expanding spirit-gate shockwaves + rising chime arpeggio.
	for k in 3:
		_spawn_shockwave(_far_arch.global_position + Vector3(0, 1.6, 0), float(k) * 0.35)
	var notes := [60, 64, 67, 72, 76, 79]
	for n in notes:
		_sfx(n, 0.8, 1.4)
		await get_tree().create_timer(0.12).timeout
	await get_tree().create_timer(1.6).timeout
	chapter_complete.emit()


## Expanding golden ring for the spirit-gate moment.
func _spawn_shockwave(pos: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 10
	var mat := MarigoldFX.glow(Color(1.0, 0.85, 0.45), 2.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.rotation_degrees.x = 90.0
	add_child(mi)
	mi.global_position = pos
	_shocks.append({"node": mi, "mat": mat, "t": 0.0})
