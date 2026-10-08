## flight.gd - MARIGOLD chapter-transition flight (v0.6.0, finding 4).
## Replaces fade-to-black chapter loads with a short scripted gliding sequence
## over the candle-lit town (~15-20 s). The player is passive: the CAMERA
## never moves (XR tracking stays put); the town slides past beneath it and
## layered dark "fog" planes give the distance cueing. Aggressive LODs by
## construction: the whole town is 4 MultiMeshes + ground + church (7 draw
## calls total), windows as one emissive MultiMesh, no real lights.
## Usage: MarigoldFlight.new().begin(parent, from_name, to_name) -> signal finished.
class_name MarigoldFlight
extends Node3D

signal finished

const SPEED := 6.0 # m/s of town travel

var _t := 0.0
var _dur := 16.0
var _town: Node3D
var _label: Label3D
var _sub: Label3D
var _done := false


func begin(parent: Node, from_name: String, to_name: String, duration: float = 16.0) -> void:
	parent.add_child(self)
	_dur = duration
	_build(from_name, to_name)
	if MarigoldSky.instance != null:
		MarigoldSky.instance.set_time_mode("fixed")
		MarigoldSky.instance.set_time_of_day(21.5) # deep night over the town
		MarigoldSky.instance.set_weather("clear")


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _town != null:
		_town.position.z += SPEED * delta
	if _label != null:
		var a_in := clampf(_t / 2.0, 0.0, 1.0)
		var a_out := clampf((_dur - _t) / 2.5, 0.0, 1.0)
		_label.modulate.a = minf(a_in, a_out)
		_sub.modulate.a = minf(a_in, a_out) * 0.85
	if _t >= _dur:
		_done = true
		if MarigoldSky.instance != null:
			MarigoldSky.instance.set_time_mode("auto")
		finished.emit()


func _build(from_name: String, to_name: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	_town = Node3D.new()
	_town.name = "Town"
	add_child(_town)
	# Ground: one dark plane.
	var gnd := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(160, 220)
	gnd.mesh = gm
	gnd.material_override = MarigoldFX.pbr(Color(0.05, 0.03, 0.07), 0.0, 1.0)
	gnd.position = Vector3(0, -0.5, -60)
	_town.add_child(gnd)
	# Houses: one MultiMesh of dark boxes.
	var house_mesh := BoxMesh.new()
	house_mesh.size = Vector3(1, 1, 1)
	house_mesh.material = MarigoldFX.pbr(Color(0.10, 0.06, 0.10), 0.0, 0.95)
	var houses := MultiMesh.new()
	houses.transform_format = MultiMesh.TRANSFORM_3D
	houses.mesh = house_mesh
	var hn := 46
	houses.instance_count = hn
	# Windows: one MultiMesh of warm emissive quads on the camera side.
	var win_mesh := QuadMesh.new()
	win_mesh.size = Vector2(0.5, 0.65)
	win_mesh.material = MarigoldFX.glow(Color(1.0, 0.68, 0.25), 2.0)
	var wins := MultiMesh.new()
	wins.transform_format = MultiMesh.TRANSFORM_3D
	wins.mesh = win_mesh
	var win_xforms: Array = []
	for i in hn:
		var z := rng.randf_range(-125.0, 8.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := side * rng.randf_range(10.0, 42.0)
		var w := rng.randf_range(5.0, 10.0)
		var h := rng.randf_range(3.5, 9.0)
		var dpt := rng.randf_range(5.0, 9.0)
		houses.set_instance_transform(i, Transform3D(
			Basis.from_scale(Vector3(w, h, dpt)), Vector3(x, -0.5 + h * 0.5, z)))
		# 4-8 lit windows on the town-facing side.
		var nw := 4 + i % 5
		for k in nw:
			var wx := x - side * (w * 0.5 + 0.02) * signf(x)
			win_xforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5 * signf(-x)),
				Vector3(wx, rng.randf_range(0.5, h - 0.5), z - dpt * 0.5 + (float(k) + 0.5) * dpt / float(nw))))
	wins.instance_count = win_xforms.size()
	for i in win_xforms.size():
		wins.set_instance_transform(i, win_xforms[i])
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = houses
	_town.add_child(hmi)
	var wmi := MultiMeshInstance3D.new()
	wmi.multimesh = wins
	_town.add_child(wmi)
	# Street lamps: one MultiMesh of emissive orbs along the avenue.
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.22
	lamp_mesh.height = 0.44
	lamp_mesh.material = MarigoldFX.glow(Color(1.0, 0.80, 0.40), 2.6)
	var lamps := MultiMesh.new()
	lamps.transform_format = MultiMesh.TRANSFORM_3D
	lamps.mesh = lamp_mesh
	var ln := 22
	lamps.instance_count = ln
	for i in ln:
		var lz := 6.0 - float(i) * 6.0
		var lx := 4.5 if i % 2 == 0 else -4.5
		lamps.set_instance_transform(i, Transform3D(Basis(), Vector3(lx, 1.6, lz)))
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lamps
	_town.add_child(lmi)
	# Distant church silhouette at the end of the ride.
	var church := Node3D.new()
	church.position = Vector3(6, 0, -118)
	_town.add_child(church)
	var nave := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(10, 7, 16)
	nave.mesh = nm
	nave.material_override = MarigoldFX.pbr(Color(0.09, 0.05, 0.10), 0.0, 0.95)
	nave.position = Vector3(0, 3.0, 0)
	church.add_child(nave)
	var dome := MeshInstance3D.new()
	var dom := SphereMesh.new()
	dom.radius = 3.0
	dom.height = 5.0
	dome.mesh = dom
	dome.material_override = MarigoldFX.pbr(Color(0.12, 0.07, 0.12), 0.0, 0.95)
	dome.position = Vector3(0, 7.5, -3)
	church.add_child(dome)
	var tower := MeshInstance3D.new()
	var tm2 := BoxMesh.new()
	tm2.size = Vector3(3, 14, 3)
	tower.mesh = tm2
	tower.material_override = MarigoldFX.pbr(Color(0.09, 0.05, 0.10), 0.0, 0.95)
	tower.position = Vector3(-6, 6.5, 4)
	church.add_child(tower)
	# Drifting petals in the slipstream.
	MarigoldFX.spawn_ambient_motes(self, Vector3(0, 1.5, -8), 6.0, 40)
	# Layered fog planes (fixed to the camera, town slides behind them).
	for fi in 3:
		var fog := MeshInstance3D.new()
		var fm := QuadMesh.new()
		fm.size = Vector2(120, 30)
		fog.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.albedo_color = Color(0.03, 0.02, 0.06, 0.30 + float(fi) * 0.25)
		fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		fog.material_override = fmat
		fog.position = Vector3(0, 6, -28.0 - float(fi) * 32.0)
		add_child(fog)
	# Title cards.
	_label = MarigoldFX.make_label("Volando a %s" % to_name, 72, Color(1.0, 0.85, 0.45))
	_label.position = Vector3(0, 2.0, -6)
	_label.modulate.a = 0.0
	add_child(_label)
	_sub = MarigoldFX.make_label("desde %s" % from_name, 44, Color(0.95, 0.90, 0.85))
	_sub.position = Vector3(0, 1.45, -6)
	_sub.modulate.a = 0.0
	add_child(_sub)
	if MarigoldState.music != null and MarigoldState.music.has_method("chime"):
		MarigoldState.music.chime(72, 0.5)
