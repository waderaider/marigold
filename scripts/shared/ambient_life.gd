## MarigoldAmbient.gd - ambient life pass (v0.5.0).
## Butterflies (one-draw-call MultiMesh, per-frame matrix animation) and
## distant spirit silhouettes drifting on the horizon. Cheap by design:
## butterflies = 1 draw call, spirits = 1 draw call each (4-6 total).
extends RefCounted
class_name MarigoldAmbient


## A field of butterflies: orange/pink glowing quads that flap (scale-x
## oscillation) and drift on lissajous paths. 1 draw call via MultiMesh.
class ButterflyField extends Node3D:
	var count := 8
	var radius := 4.0
	var center := Vector3(0, 1.6, 0)
	var _mmi: MultiMeshInstance3D
	var _seeds: Array = []
	var _t := 0.0

	func _ready() -> void:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.14, 0.10)
		quad.material = MarigoldFX.glow(Color(1.0, 0.55, 0.25), 1.8)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = count
		var rng := RandomNumberGenerator.new()
		rng.seed = 777
		for i in count:
			_seeds.append({
				"r": radius * sqrt(rng.randf()),
				"a": rng.randf() * TAU,
				"h": rng.randf_range(0.8, 2.6),
				"sp": rng.randf_range(0.25, 0.6),
				"ph": rng.randf() * TAU,
				"flap": rng.randf_range(9.0, 13.0),
				"s": rng.randf_range(0.7, 1.3),
			})
		_mmi = MultiMeshInstance3D.new()
		_mmi.multimesh = mm
		add_child(_mmi)
		_update(0.0)

	func _process(delta: float) -> void:
		_t += delta
		_update(delta)

	func _update(_delta: float) -> void:
		if _mmi == null:
			return
		var mm := _mmi.multimesh
		for i in count:
			var s: Dictionary = _seeds[i]
			var a: float = s["a"] + _t * float(s["sp"])
			var pos := center + Vector3(cos(a) * float(s["r"]),
				float(s["h"]) + sin(_t * 0.9 + float(s["ph"])) * 0.35,
				sin(a) * float(s["r"]))
			var flap := 0.35 + 0.65 * absf(sin(_t * float(s["flap"]) + float(s["ph"])))
			var basis := Basis(Vector3.UP, -a + PI * 0.5).scaled(
				Vector3(float(s["s"]) * flap, float(s["s"]), float(s["s"])))
			mm.set_instance_transform(i, Transform3D(basis, pos))


## Distant spirit silhouettes: soft dark-blue glowing figures drifting far
## away, giving the horizon life. Each is one quad = 1 draw call.
class SpiritHorizon extends Node3D:
	var count := 5
	var distance := 14.0
	var base_y := 2.2
	var _quads: Array = []
	var _seeds: Array = []
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in count:
			var quad := QuadMesh.new()
			quad.size = Vector2(1.1, 2.0)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.45, 0.60, 1.0, 0.16)
			m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			quad.material = m
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			add_child(mi)
			_quads.append(mi)
			_seeds.append({
				"a": TAU * float(i) / float(count) + rng.randf_range(-0.3, 0.3),
				"h": base_y + rng.randf_range(-0.6, 0.8),
				"sp": rng.randf_range(0.05, 0.14),
				"ph": rng.randf() * TAU,
				"s": rng.randf_range(0.8, 1.4),
			})

	func _process(delta: float) -> void:
		_t += delta
		for i in _quads.size():
			var mi: MeshInstance3D = _quads[i]
			var s: Dictionary = _seeds[i]
			var a: float = s["a"] + _t * float(s["sp"])
			mi.position = Vector3(cos(a) * distance,
				float(s["h"]) + sin(_t * 0.5 + float(s["ph"])) * 0.4,
				sin(a) * distance)
			var sc := float(s["s"]) * (1.0 + 0.06 * sin(_t * 1.1 + float(s["ph"])))
			mi.scale = Vector3.ONE * sc


## A field of falling marigold petals: orange/gold quads drifting down with
## sway, 1 draw call via MultiMesh. PC VR scales count x3 via quality setting.
class PetalField extends Node3D:
	var count := 24
	var radius := 6.0
	var center := Vector3(0, 3.0, 0)
	var fall_speed := 0.5
	var drift_dir := Vector3(0.3, 0, 0.1)
	var _mmi: MultiMeshInstance3D
	var _seeds: Array = []
	var _t := 0.0

	func _ready() -> void:
		# PC VR: scale count by quality (Ultra = x3).
		if MarigoldGfx.is_pc_vr() and MarigoldGfx.quality() == "ultra":
			count = count * 3
		var quad := QuadMesh.new()
		quad.size = Vector2(0.09, 0.07)
		quad.material = MarigoldFX.glow(Color(1.0, 0.62, 0.15), 1.4)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = count
		var rng := RandomNumberGenerator.new()
		rng.seed = 999
		for i in count:
			_seeds.append({
				"x": rng.randf_range(-radius, radius),
				"z": rng.randf_range(-radius, radius),
				"y": rng.randf_range(0.0, 4.0),
				"sp": rng.randf_range(0.7, 1.3),
				"ph": rng.randf() * TAU,
				"s": rng.randf_range(0.7, 1.4),
			})
		_mmi = MultiMeshInstance3D.new()
		_mmi.multimesh = mm
		add_child(_mmi)

	func _process(delta: float) -> void:
		_t += delta
		if _mmi == null:
			return
		var mm := _mmi.multimesh
		for i in count:
			var s: Dictionary = _seeds[i]
			# Fall + sway + drift.
			var y: float = fmod(float(s["y"]) - _t * fall_speed * float(s["sp"]), 4.0)
			if y < 0.0:
				y += 4.0
			var sway := sin(_t * 1.5 + float(s["ph"])) * 0.4
			var pos := center + Vector3(
				float(s["x"]) + sway + drift_dir.x * _t * 0.2,
				y,
				float(s["z"]) + cos(_t * 1.2 + float(s["ph"])) * 0.3 + drift_dir.z * _t * 0.2)
			# Wrap drift.
			pos.x = fmod(pos.x - center.x + radius, radius * 2.0) - radius + center.x
			pos.z = fmod(pos.z - center.z + radius, radius * 2.0) - radius + center.z
			var rot := Basis(Vector3.UP, _t * 2.0 + float(s["ph"])).rotated(
				Vector3.RIGHT, sin(_t * 3.0 + float(s["ph"])) * 0.5)
			var basis := rot.scaled(Vector3.ONE * float(s["s"]))
			mm.set_instance_transform(i, Transform3D(basis, pos))


## Dust motes: slow drifting particles for light shafts. 1 GPUParticles3D,
## 36 particles (128 on PC Ultra), additive.
class DustMotes extends Node3D:
	var count := 36
	var volume := Vector3(3.0, 4.0, 3.0)
	var _p: GPUParticles3D

	func _ready() -> void:
		if MarigoldGfx.is_pc_vr() and MarigoldGfx.quality() == "ultra":
			count = 128
		_p = GPUParticles3D.new()
		_p.amount = count
		_p.lifetime = 6.0
		_p.preprocess = 6.0
		_p.explosiveness = 0.0
		_p.randomness = 0.8
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = volume * 0.5
		pm.direction = Vector3(0, -0.2, 0)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.25
		pm.gravity = Vector3(0, -0.02, 0)
		pm.scale_min = 0.02
		pm.scale_max = 0.06
		pm.color = Color(1.0, 0.85, 0.6, 0.5)
		_p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.05, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.9, 0.7, 0.4)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material = m
		_p.draw_pass_1 = quad
		add_child(_p)


## Ember field: rising embers for candle/fire scenes. 1 GPUParticles3D.
class EmberField extends Node3D:
	var count := 24
	var radius := 3.0
	var _p: GPUParticles3D

	func _ready() -> void:
		if MarigoldGfx.is_pc_vr() and MarigoldGfx.quality() == "ultra":
			count = count * 2
		_p = GPUParticles3D.new()
		_p.amount = count
		_p.lifetime = 3.5
		_p.preprocess = 3.5
		_p.explosiveness = 0.0
		_p.randomness = 0.9
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3(0, 1, 0)
		pm.emission_ring_height = 0.2
		pm.emission_ring_radius = radius
		pm.emission_ring_inner_radius = radius * 0.3
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 15.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.0
		pm.gravity = Vector3(0, 0.3, 0)
		pm.scale_min = 0.03
		pm.scale_max = 0.08
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.5, 0.15, 0.9))
		grad.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		_p.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.06)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material = m
		_p.draw_pass_1 = quad
		add_child(_p)


## Convenience: add butterflies to a chapter world.
static func add_butterflies(parent: Node3D, center: Vector3, count: int = 8, radius: float = 4.0) -> Node3D:
	var f := ButterflyField.new()
	f.center = center
	f.count = count
	f.radius = radius
	parent.add_child(f)
	return f


## Convenience: add distant spirits to a chapter world.
static func add_spirits(parent: Node3D, count: int = 5, distance: float = 14.0) -> Node3D:
	var s := SpiritHorizon.new()
	s.count = count
	s.distance = distance
	parent.add_child(s)
	return s


## Convenience: add a petal field (Animator's plan: every chapter gets one).
static func add_petals(parent: Node3D, center: Vector3, count: int = 24, radius: float = 6.0) -> Node3D:
	var f := PetalField.new()
	f.center = center
	f.count = count
	f.radius = radius
	parent.add_child(f)
	return f


## Convenience: add dust motes (Animator's plan: light shafts).
static func add_dust(parent: Node3D, volume: Vector3 = Vector3(3.0, 4.0, 3.0)) -> Node3D:
	var d := DustMotes.new()
	d.volume = volume
	parent.add_child(d)
	return d


## Convenience: add an ember field (Animator's plan: candle/fire scenes).
static func add_embers(parent: Node3D, radius: float = 3.0, count: int = 24) -> Node3D:
	var e := EmberField.new()
	e.radius = radius
	e.count = count
	parent.add_child(e)
	return e
