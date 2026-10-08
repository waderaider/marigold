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
