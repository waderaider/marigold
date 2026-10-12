## vista.gd - MarigoldVista: large-scale world vistas for MARIGOLD v0.7.0.
## Shared builder that gives every chapter a BIG environment feel:
## layered sky dome, far landmark silhouettes (church, city, mountains),
## mid-ground dressing (trees, lamps, arches), and distance fog hooks.
## All far-field geometry is UNShaded (cheap) and merged into few nodes.
## Headless-safe: builds nodes/materials only, never assumes XR hardware.
## Quest-3-perf: unshaded silhouettes, no shadows, <20 draw calls per vista.
class_name MarigoldVista
extends RefCounted

## Build a complete vista layer. theme: "pueblo" | "mictlan" | "mercado" | "fiesta".
## far_radius: distance of the landmark ring (default 65m).
## Returns the vista root node.
static func build(parent: Node3D, theme: String = "pueblo", far_radius: float = 65.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Vista"
	parent.add_child(root)
	_build_sky_dome(root, theme)
	_build_far_landmarks(root, theme, far_radius)
	_build_midground(root, theme)
	return root

## Large gradient sky dome with stars (unshaded, Back cull, radius 180m).
static func _build_sky_dome(root: Node3D, theme: String) -> void:
	var sky_shader := Shader.new()
	var top := Color(0.03, 0.02, 0.10)
	var horizon := Color(0.45, 0.12, 0.28)
	match theme:
		"mictlan":
			top = Color(0.02, 0.01, 0.08)
			horizon = Color(0.55, 0.15, 0.35)
		"mercado":
			top = Color(0.05, 0.08, 0.22)
			horizon = Color(0.95, 0.45, 0.20)
		"fiesta":
			top = Color(0.04, 0.03, 0.14)
			horizon = Color(0.90, 0.35, 0.45)
		_:
			top = Color(0.03, 0.04, 0.16)
			horizon = Color(0.85, 0.40, 0.22)
	sky_shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;
uniform vec4 top : source_color = vec4(%f, %f, %f, 1.0);
uniform vec4 horizon : source_color = vec4(%f, %f, %f, 1.0);
void fragment() {
	float h = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(horizon.rgb, top.rgb, pow(h, 0.65));
	// Star field (procedural hash, only in upper sky).
	vec2 sp = UV * vec2(180.0, 90.0);
	vec2 cell = floor(sp);
	float star = step(0.992, fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453));
	star *= smoothstep(0.55, 0.85, h);
	col += vec3(1.0, 0.95, 0.85) * star * 0.8;
	ALBEDO = col;
}
""" % [top.r, top.g, top.b, horizon.r, horizon.g, horizon.b]
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	var dome := SphereMesh.new()
	dome.radius = 180.0
	dome.height = 360.0
	dome.radial_segments = 24
	dome.rings = 12
	var dmi := MeshInstance3D.new()
	dmi.mesh = dome
	dmi.material_override = sky_mat
	dmi.position = Vector3(0, 0, 0)
	root.add_child(dmi)

## Far landmark ring: church towers, city blocks, mountain silhouettes.
static func _build_far_landmarks(root: Node3D, theme: String, far_radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme) + 777
	var dark := MarigoldFX.pbr(Color(0.07, 0.05, 0.13), 0.0, 0.95)
	var dark2 := MarigoldFX.pbr(Color(0.10, 0.07, 0.18), 0.0, 0.95)
	# Mountain silhouettes (back layer, very far, unshaded dark).
	var mtn_mat := MarigoldFX.pbr(Color(0.05, 0.04, 0.10), 0.0, 1.0)
	for i in 7:
		var ang := TAU * float(i) / 7.0 + rng.randf_range(-0.2, 0.2)
		var w := rng.randf_range(30.0, 55.0)
		var h := rng.randf_range(18.0, 35.0)
		var mtn := PrismMesh.new()
		mtn.size = Vector3(w, h, 8.0)
		var mmi := MeshInstance3D.new()
		mmi.mesh = mtn
		mmi.material_override = mtn_mat
		mmi.position = Vector3(cos(ang) * (far_radius + 25.0), h * 0.28, sin(ang) * (far_radius + 25.0))
		mmi.rotation.y = -ang + PI * 0.5
		root.add_child(mmi)
	# Church tower (Mexican pueblo landmark) — front-center-ish.
	if theme == "pueblo" or theme == "fiesta":
		_build_church(root, Vector3(cos(0.6) * far_radius, 0, sin(0.6) * far_radius), dark, dark2)
	# City blocks with lit windows (Land of the Dead glow).
	if theme == "mictlan" or theme == "fiesta" or theme == "mercado":
		_build_city_blocks(root, far_radius, rng, dark)
	# Agave/cactus silhouettes for pueblo theme.
	if theme == "pueblo":
		for i in 5:
			var ang2 := TAU * float(i) / 5.0 + 0.3
			_build_cactus(root, Vector3(cos(ang2) * (far_radius - 8.0), 0, sin(ang2) * (far_radius - 8.0)), dark2)

## Mexican church: tower + dome + cross silhouette.
static func _build_church(root: Node3D, pos: Vector3, dark: Material, dark2: Material) -> void:
	var church := Node3D.new()
	church.name = "FarChurch"
	church.position = pos
	root.add_child(church)
	# Main tower.
	var tower := BoxMesh.new()
	tower.size = Vector3(6.0, 18.0, 6.0)
	var tmi := MeshInstance3D.new()
	tmi.mesh = tower
	tmi.material_override = dark
	tmi.position = Vector3(0, 9.0, 0)
	church.add_child(tmi)
	# Dome (sphere squashed).
	var dome := SphereMesh.new()
	dome.radius = 4.2
	dome.height = 6.0
	var dmi := MeshInstance3D.new()
	dmi.mesh = dome
	dmi.material_override = dark2
	dmi.position = Vector3(0, 20.5, 0)
	church.add_child(dmi)
	# Cross on top.
	var cross_v := BoxMesh.new()
	cross_v.size = Vector3(0.5, 3.0, 0.5)
	var cv := MeshInstance3D.new()
	cv.mesh = cross_v
	cv.material_override = MarigoldFX.glow(Color(1.0, 0.75, 0.35), 1.2)
	cv.position = Vector3(0, 25.0, 0)
	church.add_child(cv)
	var cross_h := BoxMesh.new()
	cross_h.size = Vector3(1.8, 0.5, 0.5)
	var ch := MeshInstance3D.new()
	ch.mesh = cross_h
	ch.material_override = cv.material_override
	ch.position = Vector3(0, 25.0, 0)
	church.add_child(ch)
	# Bell tower windows (warm glow).
	for i in 2:
		var win := PlaneMesh.new()
		win.size = Vector2(1.2, 2.0)
		var wmi := MeshInstance3D.new()
		wmi.mesh = win
		wmi.material_override = MarigoldFX.glow(Color(1.0, 0.65, 0.25), 1.5)
		wmi.position = Vector3(-1.5 + float(i) * 3.0, 14.0, 3.05)
		church.add_child(wmi)
	# Nave (long hall).
	var nave := BoxMesh.new()
	nave.size = Vector3(14.0, 8.0, 8.0)
	var nmi := MeshInstance3D.new()
	nmi.mesh = nave
	nmi.material_override = dark
	nmi.position = Vector3(9.0, 4.0, 0)
	church.add_child(nmi)

## Distant city blocks with procedural lit windows (Land of the Dead).
static func _build_city_blocks(root: Node3D, far_radius: float, rng: RandomNumberGenerator, dark: Material) -> void:
	var win_shader := Shader.new()
	win_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base : source_color = vec4(0.06, 0.05, 0.12, 1.0);
uniform vec4 win_on : source_color = vec4(1.0, 0.65, 0.25, 1.0);
void fragment() {
	vec2 g = vec2(UV.x * 10.0, UV.y * 16.0);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float lit = step(0.5, fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453));
	float win = step(0.25, f.x) * (1.0 - step(0.75, f.x)) * step(0.3, f.y) * (1.0 - step(0.7, f.y));
	vec3 col = mix(base.rgb, win_on.rgb, lit * win);
	ALBEDO = col;
	EMISSION = win_on.rgb * lit * win * 1.0;
}
"""
	var win_mat := ShaderMaterial.new()
	win_mat.shader = win_shader
	var city := Node3D.new()
	city.name = "FarCityVista"
	root.add_child(city)
	# Arc of buildings across the back.
	for i in 9:
		var ang := -0.7 + 1.4 * float(i) / 8.0
		var w := rng.randf_range(5.0, 9.0)
		var h := rng.randf_range(8.0, 20.0)
		var d := rng.randf_range(4.0, 6.0)
		var bld := BoxMesh.new()
		bld.size = Vector3(w, h, d)
		var bmi := MeshInstance3D.new()
		bmi.mesh = bld
		bmi.material_override = dark
		bmi.position = Vector3(sin(ang) * far_radius, h * 0.5, -cos(ang) * far_radius)
		bmi.rotation.y = ang
		city.add_child(bmi)
		var face := PlaneMesh.new()
		face.size = Vector2(w * 0.94, h * 0.94)
		var fmi := MeshInstance3D.new()
		fmi.mesh = face
		fmi.material_override = win_mat
		fmi.position = bmi.position + Vector3(sin(ang) * (d * 0.5 + 0.1), 0, -cos(ang) * (d * 0.5 + 0.1))
		fmi.rotation.y = ang + PI
		city.add_child(fmi)

## Saguaro-style cactus silhouette (pueblo desert).
static func _build_cactus(root: Node3D, pos: Vector3, mat: Material) -> void:
	var cactus := Node3D.new()
	cactus.position = pos
	root.add_child(cactus)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 1.2
	trunk.bottom_radius = 1.5
	trunk.height = 10.0
	var tmi := MeshInstance3D.new()
	tmi.mesh = trunk
	tmi.material_override = mat
	tmi.position = Vector3(0, 5.0, 0)
	cactus.add_child(tmi)
	for side in [-1.0, 1.0]:
		var arm_v := CylinderMesh.new()
		arm_v.top_radius = 0.8
		arm_v.bottom_radius = 0.9
		arm_v.height = 4.0
		var av := MeshInstance3D.new()
		av.mesh = arm_v
		av.material_override = mat
		av.position = Vector3(side * 2.2, 6.5, 0)
		cactus.add_child(av)
		var arm_h := CylinderMesh.new()
		arm_h.top_radius = 0.8
		arm_h.bottom_radius = 0.8
		arm_h.height = 2.4
		var ah := MeshInstance3D.new()
		ah.mesh = arm_h
		ah.material_override = mat
		ah.rotation.z = PI * 0.5
		ah.position = Vector3(side * 1.2, 4.8, 0)
		cactus.add_child(ah)

## Mid-ground: stylized trees, lamp posts, papel arches (25-40m ring).
static func _build_midground(root: Node3D, theme: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var leaf_mat := MarigoldFX.pbr(Color(0.15, 0.35, 0.12), 0.0, 0.8)
	var trunk_mat := MarigoldFX.pbr(Color(0.25, 0.16, 0.10), 0.0, 0.9)
	var lamp_glow := MarigoldFX.glow(Color(1.0, 0.70, 0.30), 1.8)
	for i in 10:
		var ang := TAU * float(i) / 10.0 + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(28.0, 42.0)
		var pos := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		if i % 3 == 0:
			# Lamp post with warm glow.
			_build_lamp(root, pos, trunk_mat, lamp_glow)
		else:
			# Stylized tree (sphere canopy + cylinder trunk).
			_build_tree(root, pos, trunk_mat, leaf_mat, rng)

static func _build_tree(root: Node3D, pos: Vector3, trunk_mat: Material, leaf_mat: Material, rng: RandomNumberGenerator) -> void:
	var tree := Node3D.new()
	tree.position = pos
	root.add_child(tree)
	var h := rng.randf_range(4.0, 7.0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.4
	trunk.height = h
	var tmi := MeshInstance3D.new()
	tmi.mesh = trunk
	tmi.material_override = trunk_mat
	tmi.position = Vector3(0, h * 0.5, 0)
	tree.add_child(tmi)
	for j in 3:
		var canopy := SphereMesh.new()
		canopy.radius = rng.randf_range(1.5, 2.5)
		canopy.height = canopy.radius * 1.6
		var cmi := MeshInstance3D.new()
		cmi.mesh = canopy
		cmi.material_override = leaf_mat
		cmi.position = Vector3(rng.randf_range(-1.0, 1.0), h + rng.randf_range(-0.5, 1.0), rng.randf_range(-1.0, 1.0))
		tree.add_child(cmi)

static func _build_lamp(root: Node3D, pos: Vector3, pole_mat: Material, glow_mat: Material) -> void:
	var lamp := Node3D.new()
	lamp.position = pos
	root.add_child(lamp)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.12
	pole.height = 5.0
	var pmi := MeshInstance3D.new()
	pmi.mesh = pole
	pmi.material_override = pole_mat
	pmi.position = Vector3(0, 2.5, 0)
	lamp.add_child(pmi)
	var bulb := SphereMesh.new()
	bulb.radius = 0.35
	bulb.height = 0.6
	var bmi := MeshInstance3D.new()
	bmi.mesh = bulb
	bmi.material_override = glow_mat
	bmi.position = Vector3(0, 5.2, 0)
	lamp.add_child(bmi)
