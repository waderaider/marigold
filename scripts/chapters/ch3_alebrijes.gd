## ch3_alebrijes.gd - MARIGOLD Chapter 3: Plaza de los Alebrijes.
## A festive plaza with four ORIGINAL spirit-animal guides (jaguar-moth, axolotl-
## hummingbird, coyote-serpent, rabbit-owl). Feed each guide a light orb to make
## it happy; feeding all four completes the chapter. Bonus: a playable guitar
## corner (hand-strummed via pointer tracking + MarigoldState.music.pluck).
## Original folk-art IP only - no film references of any kind.
extends Node3D

signal chapter_complete

const FEED_RANGE := 1.25
const AIM_TOLERANCE := 0.5
const AIM_MAX_DIST := 4.0
const STRING_MIDIS := [40, 45, 50, 55, 59, 64] # E2 A2 D3 G3 B3 E4

const GUIDE_DEFS := [
	{"name": "Xochi", "sub": "jaguar-moth",
		"body": Color(0.95, 0.45, 0.10), "accent": Color(1.0, 0.78, 0.25),
		"glow": Color(1.0, 0.55, 0.15), "feature": "moth_wings"},
	{"name": "Tlanetl", "sub": "axolotl-hummingbird",
		"body": Color(0.95, 0.38, 0.58), "accent": Color(0.35, 0.90, 1.0),
		"glow": Color(1.0, 0.40, 0.70), "feature": "gills"},
	{"name": "Mictli", "sub": "coyote-serpent",
		"body": Color(0.16, 0.72, 0.62), "accent": Color(0.60, 1.0, 0.55),
		"glow": Color(0.30, 1.0, 0.80), "feature": "serpent_tail"},
	{"name": "Papalotl", "sub": "rabbit-owl",
		"body": Color(0.55, 0.35, 0.95), "accent": Color(1.0, 0.85, 0.35),
		"glow": Color(0.70, 0.45, 1.0), "feature": "rabbit_ears"},
]

const BANNER_COLORS := [
	Color(1.0, 0.15, 0.55), Color(0.10, 0.85, 1.0), Color(1.0, 0.50, 0.10),
	Color(0.60, 0.25, 1.0), Color(0.10, 0.90, 0.70),
]

var _t := 0.0
var _ar_mode := false
var _guides: Array = [] # Dictionaries describing each spirit guide.
var _orbs := {} # hand index -> orb Node3D currently held.
var _fed_count := 0
var _celebrating := false
var _complete_sent := false

var _ground_group: Node3D
var _dressing: Node3D
var _fountain_ring: MeshInstance3D
var _banner_strings: Array = []
var _guitar: Node3D
var _guitar_home := Transform3D.IDENTITY
var _string_x: Array = []
var _prev_strum_x := 0.0
var _has_prev_strum := false

var _plaque: Node3D
var _feed_label: Label3D
var _status_label: Label3D
# Wind + physics integration (v0.4.0).
var _banner_mats: Array[ShaderMaterial] = [] # papel banner vertex-shader mats
var _sway_mats := {} # emission hex -> MarigoldSky.wind_sway_material cache
var _wind_flames: Array[StandardMaterial3D] = [] # candle flame materials
var _wind_lights: Array = [] # {"light": OmniLight3D, "base": float, "phase": float}


func _ready() -> void:
	_build_plaza()
	_build_guides()
	_build_guitar()
	_build_ui()


func setup(ar_mode: bool) -> void:
	_ar_mode = ar_mode
	apply_mode(ar_mode)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	_ground_group.visible = not on
	_dressing.visible = not on
	for b in _banner_strings:
		var mi: MeshInstance3D = b["mi"]
		var p: Vector3 = b["home"]
		if on:
			p.y = 2.6
		mi.position = p
	for i in _guides.size():
		var g: Dictionary = _guides[i]
		var node: Node3D = g["node"]
		if on:
			var a := float(i) * PI * 0.5 + PI * 0.25
			var p2 := Vector3(cos(a) * 1.5, 1.0, sin(a) * 1.5)
			p2 = MarigoldHands.clamp_to_room(p2, 0.4)
			node.position = p2
			node.look_at(Vector3(p2.x * 0.15, 1.0, p2.z * 0.15), Vector3.UP)
			g["base_y"] = 1.0
			g["home_yaw"] = node.rotation.y
			MarigoldHands.save_anchor(MarigoldState.anchor_name("ch3_guide_%d" % i), node.global_transform)
		else:
			var home_t: Transform3D = g["home"]
			node.transform = home_t
			g["base_y"] = float(g["home_y"])
			g["home_yaw"] = home_t.basis.get_euler().y
	if on:
		MarigoldHands.place_on_table(_guitar, 1.2)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var gp: Vector3 = _guitar.global_position
			var cp: Vector3 = cam.global_position
			_guitar.look_at(Vector3(cp.x, gp.y, cp.z), Vector3.UP)
	else:
		_guitar.transform = _guitar_home
	# UI placement per mode.
	if on:
		_plaque.position = Vector3(-1.3, 1.5, -1.2)
		_feed_label.position = Vector3(0, 2.3, -1.6)
		_status_label.position = Vector3(0, 2.0, -1.6)
	else:
		_plaque.position = Vector3(-2.4, 1.6, 1.6)
		_feed_label.position = Vector3(0, 2.4, 2.6)
		_status_label.position = Vector3(0, 2.05, 2.6)


func _process(delta: float) -> void:
	_t += delta
	if _fountain_ring and is_instance_valid(_fountain_ring):
		_fountain_ring.rotation.y += delta * 0.6
	_animate_guides(delta)
	_update_feeding()
	_update_strum()
	_update_wind_fx() # banners ripple, stall candle flames dance with gusts
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)


## ---------------- wind + physics (v0.4.0) ----------------

## Null-safe wind strength (headless tests may lack the sky singleton).
func _wind_strength() -> float:
	if MarigoldSky.instance != null:
		return MarigoldSky.instance.get_wind_strength()
	return 0.0


## Remember a papel banner's vertex-shader material for wind driving.
## The banner's own cutout shader is preserved (look untouched).
func _track_banner(b: MeshInstance3D) -> void:
	var pm := b.mesh as PrimitiveMesh
	if pm == null:
		return
	var sm := pm.material as ShaderMaterial
	if sm != null and not _banner_mats.has(sm):
		_banner_mats.append(sm)


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


## Track a make_candle's flame material + point light for wind flicker.
func _track_candle_flames(root: Node3D) -> void:
	var flame := root.get_node_or_null("Flame")
	if flame is MeshInstance3D:
		var m: Material = (flame as MeshInstance3D).get_active_material(0)
		if m is StandardMaterial3D:
			_wind_flames.append(m)
	for c in root.get_children():
		if c is OmniLight3D:
			_wind_lights.append({"light": c, "base": (c as OmniLight3D).light_energy,
				"phase": randf() * TAU})


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


## Per-frame wind response: banners ripple, candle flames + lights dance.
func _update_wind_fx() -> void:
	var wind := _wind_strength()
	var amp := 0.09 * (0.7 + wind * 2.5)
	var speed := 2.2 * (0.85 + wind * 1.6)
	for mat in _banner_mats:
		mat.set_shader_parameter("wave_amp", amp)
		mat.set_shader_parameter("wave_speed", speed)
	if MarigoldSky.instance != null:
		for m in _sway_mats.values():
			(m as ShaderMaterial).set_shader_parameter("wind_strength", wind)
	var flick := 0.5 + wind * 3.0 # calm day = gentle flicker, storm = wild dance
	for i in _wind_flames.size():
		var fm := _wind_flames[i]
		if is_instance_valid(fm):
			MarigoldFX.pulse_glow(fm, 2.6, 1.2 * flick, _t * 1.1 + float(i) * 1.9, 11.0)
	for d in _wind_lights:
		var l: OmniLight3D = d["light"]
		if is_instance_valid(l):
			l.light_energy = float(d["base"]) * (1.0 + (0.10 + wind * 0.45) * sin(_t * 12.0 + float(d["phase"])))


# ---------------------------------------------------------------- plaza build

func _build_plaza() -> void:
	_ground_group = Node3D.new()
	_ground_group.name = "PlazaGround"
	add_child(_ground_group)

	# Dark plaza disc under the marigold field.
	var disc := CylinderMesh.new()
	disc.top_radius = 10.0
	disc.bottom_radius = 10.0
	disc.height = 0.1
	disc.radial_segments = 48
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = disc
	disc_mi.material_override = MarigoldFX.pbr(Color(0.09, 0.04, 0.12), 0.0, 0.9)
	disc_mi.position.y = -0.06
	_ground_group.add_child(disc_mi)

	# Wind: the plaza flower field sways with gusts.
	_apply_field_sway(MarigoldModels.make_flower_field(_ground_group, 200, 9.5, 777))

	# Fountain of glowing water at the plaza center: real carved fountain (Kenney CC0).
	var fountain := Node3D.new()
	fountain.name = "Fountain"
	fountain.position = Vector3(0, 0, -1.0)
	_ground_group.add_child(fountain)
	var fountain_m := MarigoldModels.instance(MarigoldModels.FANTASY, "fountain-center")
	if fountain_m != null:
		MarigoldModels.recolor(fountain_m, Color(0.35, 0.22, 0.38), 0.4, 0.35)
		fountain_m.scale = Vector3.ONE * 1.6
		fountain.add_child(fountain_m)
	else:
		var basin := CylinderMesh.new()
		basin.top_radius = 1.15
		basin.bottom_radius = 0.95
		basin.height = 0.55
		basin.radial_segments = 32
		var basin_mi := MeshInstance3D.new()
		basin_mi.mesh = basin
		basin_mi.material_override = MarigoldFX.pbr(Color(0.25, 0.12, 0.20), 0.4, 0.35)
		basin_mi.position.y = 0.27
		fountain.add_child(basin_mi)
		var column := CylinderMesh.new()
		column.top_radius = 0.09
		column.bottom_radius = 0.14
		column.height = 0.9
		var col_mi := MeshInstance3D.new()
		col_mi.mesh = column
		col_mi.material_override = MarigoldFX.pbr(Color(0.30, 0.15, 0.25), 0.4, 0.35)
		col_mi.position.y = 0.9
		fountain.add_child(col_mi)
	var water := MarigoldFX.make_luminous_water(fountain, 2.0)
	water.position.y = 0.58
	var orb_top := SphereMesh.new()
	orb_top.radius = 0.14
	orb_top.height = 0.28
	var orb_mi := MeshInstance3D.new()
	orb_mi.mesh = orb_top
	orb_mi.material_override = MarigoldFX.glow(Color(0.4, 0.9, 1.0), 2.5)
	orb_mi.position.y = 1.45
	fountain.add_child(orb_mi)
	MarigoldFX.make_point_light(fountain, Vector3(0, 1.6, 0), Color(0.4, 0.85, 1.0), 1.2, 6.0)
	# Looping spray of glowing droplets.
	var spray := GPUParticles3D.new()
	spray.amount = 48
	spray.lifetime = 1.1
	spray.position = Vector3(0, 1.35, 0)
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 18.0
	spm.initial_velocity_min = 1.5
	spm.initial_velocity_max = 2.8
	spm.gravity = Vector3(0, -4.5, 0)
	spm.scale_min = 0.012
	spm.scale_max = 0.030
	spm.color = Color(0.55, 0.90, 1.0, 0.85)
	spray.process_material = spm
	var squint := QuadMesh.new()
	squint.size = Vector2(0.03, 0.03)
	squint.material = MarigoldFX.glow(Color(0.55, 0.90, 1.0), 2.2)
	spray.draw_pass_1 = squint
	fountain.add_child(spray)
	spray.emitting = true
	# Slowly rotating glow ring on the basin rim.
	var rim := TorusMesh.new()
	rim.inner_radius = 0.03
	rim.outer_radius = 1.12
	rim.rings = 12
	rim.ring_segments = 48
	_fountain_ring = MeshInstance3D.new()
	_fountain_ring.mesh = rim
	_fountain_ring.material_override = MarigoldFX.glow(Color(0.45, 0.90, 1.0), 1.6)
	_fountain_ring.position = Vector3(0, 0.56, 0)
	fountain.add_child(_fountain_ring)

	# God rays over the plaza.
	MarigoldFX.make_god_ray(self, Vector3(0, 0, -1), 8.0)
	MarigoldFX.make_god_ray(self, Vector3(-4, 0, -4), 8.0, Color(1.0, 0.5, 0.7))
	MarigoldFX.make_god_ray(self, Vector3(4, 0, -4), 8.0, Color(0.5, 0.8, 1.0))

	# Papel banners strung overhead in three rows (wind-rippled).
	var rows := [-3.5, -1.0, 1.5]
	for r in rows.size():
		var z: float = rows[r]
		for bi in 3:
			var bx := -2.6 + float(bi) * 2.6
			var col: Color = BANNER_COLORS[(r * 3 + bi) % BANNER_COLORS.size()]
			var b := MarigoldFX.make_papel_banner(self, 2.0, 1.0, col)
			b.position = Vector3(bx, 3.4, z)
			_track_banner(b)
			_banner_strings.append({"mi": b, "home": b.position})

	MarigoldFX.spawn_ambient_motes(self, Vector3(0, 1.6, -1), 5.0, 70)
	MarigoldFX.make_light_rig(self, 1.0)

	# Rich dressing: market stalls, string lights, distant buildings (hidden in AR).
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	_build_market()
	_build_string_lights()
	_build_skyline()


# ---------------------------------------------------------------- market stalls

func _build_market() -> void:
	var stall_defs := [
		{"pos": Vector3(-4.6, 0, 2.2), "yaw": 0.6, "label": "Fruta", "goods": "fruit",
			"tint": Color(1.0, 0.45, 0.15)},
		{"pos": Vector3(4.7, 0, -0.6), "yaw": -0.9, "label": "Ceramica", "goods": "pots",
			"tint": Color(0.20, 0.70, 1.0)},
		{"pos": Vector3(-1.6, 0, -5.8), "yaw": 0.15, "label": "Velas", "goods": "candles",
			"tint": Color(1.0, 0.75, 0.30)},
	]
	for sd in stall_defs:
		_build_stall(sd)


func _build_stall(sd: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Stall_%s" % String(sd["label"])
	root.position = sd["pos"]
	root.rotation.y = float(sd["yaw"])
	_dressing.add_child(root)
	var wood := MarigoldFX.pbr(Color(0.32, 0.18, 0.09), 0.0, 0.7)
	# Four posts.
	for px in [-0.9, 0.9]:
		for pz in [-0.6, 0.6]:
			var post := CylinderMesh.new()
			post.top_radius = 0.05
			post.bottom_radius = 0.06
			post.height = 2.4
			var pmi := MeshInstance3D.new()
			pmi.mesh = post
			pmi.material_override = wood
			pmi.position = Vector3(px, 1.2, pz)
			root.add_child(pmi)
	# Canopy with glowing front trim + papel banner.
	var canopy := BoxMesh.new()
	canopy.size = Vector3(2.2, 0.08, 1.6)
	var cmi := MeshInstance3D.new()
	cmi.mesh = canopy
	cmi.material_override = MarigoldFX.pbr(Color(0.55, 0.16, 0.10), 0.0, 0.6)
	cmi.position = Vector3(0, 2.45, 0)
	root.add_child(cmi)
	var trim := BoxMesh.new()
	trim.size = Vector3(2.24, 0.06, 0.06)
	var tmi := MeshInstance3D.new()
	tmi.mesh = trim
	tmi.material_override = MarigoldFX.glow(Color(1.0, 0.62, 0.18), 1.5)
	tmi.position = Vector3(0, 2.40, 0.80)
	root.add_child(tmi)
	var banner := MarigoldFX.make_papel_banner(root, 2.0, 0.5, sd["tint"])
	banner.position = Vector3(0, 2.05, 0.82)
	_track_banner(banner)
	# Counter.
	var counter := BoxMesh.new()
	counter.size = Vector3(1.9, 0.55, 0.9)
	var comi := MeshInstance3D.new()
	comi.mesh = counter
	comi.material_override = wood
	comi.position = Vector3(0, 0.55, 0)
	root.add_child(comi)
	var top := BoxMesh.new()
	top.size = Vector3(2.0, 0.06, 1.0)
	var topmi := MeshInstance3D.new()
	topmi.mesh = top
	topmi.material_override = MarigoldFX.pbr(Color(0.45, 0.26, 0.13), 0.0, 0.6)
	topmi.position = Vector3(0, 0.86, 0)
	root.add_child(topmi)
	# Static collider so counter goods rest on the counter top.
	_static_box(root, Vector3(0, 0.445, 0), Vector3(2.0, 0.89, 1.0))
	# Goods on the counter.
	match String(sd["goods"]):
		"fruit":
			var fruit_cols := [Color(1.0, 0.45, 0.10), Color(0.85, 0.15, 0.20), Color(0.45, 0.85, 0.25)]
			for fi in 9:
				var fm := SphereMesh.new()
				fm.radius = 0.07
				fm.height = 0.13
				var fmi := MeshInstance3D.new()
				fmi.mesh = fm
				fmi.material_override = MarigoldFX.glow(fruit_cols[fi % 3], 1.1)
				fmi.position = Vector3(-0.6 + float(fi % 3) * 0.6, 0.97, -0.18 + float(fi / 3) * 0.36)
				root.add_child(fmi)
				if fi < 3:
					_make_prop_dynamic(fmi, "sphere", 0.15)
		"pots":
			var pot_cols := [Color(0.75, 0.35, 0.15), Color(0.20, 0.55, 0.85), Color(0.25, 0.65, 0.40)]
			for pi in 5:
				var pot := CylinderMesh.new()
				pot.top_radius = 0.06
				pot.bottom_radius = 0.10
				pot.height = 0.24
				var potmi := MeshInstance3D.new()
				potmi.mesh = pot
				potmi.material_override = MarigoldFX.pbr(pot_cols[pi % 3], 0.1, 0.5)
				potmi.position = Vector3(-0.7 + float(pi) * 0.35, 1.01, 0.0)
				root.add_child(potmi)
				_make_prop_dynamic(potmi, "box", 0.40)
		"candles":
			for ci in 3:
				var cm := MarigoldFX.make_candle(root, Vector3(-0.5 + float(ci) * 0.5, 0.89, 0.0), ci == 1)
				_track_candle_flames(cm)
	var sl := MarigoldFX.make_label(String(sd["label"]), 48, Color(1.0, 0.85, 0.55))
	sl.position = Vector3(0, 2.85, 0)
	root.add_child(sl)


# ---------------------------------------------------------------- string lights

func _build_string_lights() -> void:
	var pole_mat := MarigoldFX.pbr(Color(0.22, 0.12, 0.07), 0.0, 0.8)
	var poles: Array = []
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		var p := Vector3(cos(a) * 7.4, 0, -1.0 + sin(a) * 7.4)
		poles.append(p)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.05
		pole.bottom_radius = 0.07
		pole.height = 4.3
		var pmi := MeshInstance3D.new()
		pmi.mesh = pole
		pmi.material_override = pole_mat
		pmi.position = Vector3(p.x, 2.15, p.z)
		_dressing.add_child(pmi)
	var bulb_cols := [Color(1.0, 0.72, 0.30), Color(1.0, 0.45, 0.55), Color(0.65, 0.85, 1.0)]
	for s in 4:
		var a0: Vector3 = poles[s]
		var a1: Vector3 = poles[(s + 1) % 4]
		for bi in 9:
			var t := float(bi) / 8.0
			var pos: Vector3 = a0.lerp(a1, t)
			pos.y = 4.15 - sin(t * PI) * 0.7
			var bulb := SphereMesh.new()
			bulb.radius = 0.05
			bulb.height = 0.10
			var bmi := MeshInstance3D.new()
			bmi.mesh = bulb
			bmi.material_override = MarigoldFX.glow(bulb_cols[bi % 3], 2.2)
			bmi.position = pos
			_dressing.add_child(bmi)


# ---------------------------------------------------------------- distant skyline

func _build_skyline() -> void:
	for i in 10:
		var a := float(i) / 10.0 * TAU + 0.3
		var r := 14.0 + float(i % 3) * 2.5
		var w := 3.0 + float(i % 4)
		var h := 4.5 + fmod(float(i) * 1.7, 5.0)
		var broot := Node3D.new()
		broot.position = Vector3(cos(a) * r, 0, -1.0 + sin(a) * r)
		broot.rotation.y = -a + PI * 0.5
		_dressing.add_child(broot)
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, w * 0.8)
		var bmi := MeshInstance3D.new()
		bmi.mesh = bm
		bmi.material_override = MarigoldFX.pbr(Color(0.07, 0.03, 0.10), 0.0, 0.95)
		bmi.position = Vector3(0, h * 0.5 - 0.1, 0)
		broot.add_child(bmi)
		# Lit windows on the plaza-facing side.
		for wx in [-0.5, 0.5]:
			for wy in [0.35, 0.65]:
				if (i + int(wx * 10.0) + int(wy * 10.0)) % 3 == 0:
					continue
				var win := BoxMesh.new()
				win.size = Vector3(0.22, 0.30, 0.06)
				var wmi := MeshInstance3D.new()
				wmi.mesh = win
				wmi.material_override = MarigoldFX.glow(Color(1.0, 0.70, 0.30), 1.4)
				wmi.position = Vector3(wx * w * 0.5, h * wy, -w * 0.4 - 0.02)
				broot.add_child(wmi)
		# Papel strip along the roofline (wind-rippled).
		var strip := MarigoldFX.make_papel_banner(broot, w * 0.9, 0.6, BANNER_COLORS[i % BANNER_COLORS.size()])
		strip.position = Vector3(0, h - 0.5, -w * 0.4 - 0.05)
		_track_banner(strip)


# ---------------------------------------------------------------- guide build

func _build_guides() -> void:
	for i in GUIDE_DEFS.size():
		var g := _build_guide(GUIDE_DEFS[i], i)
		var a := float(i) * PI * 0.5 + PI * 0.25
		var p := Vector3(cos(a) * 3.2, 0.0, -1.0 + sin(a) * 3.2)
		(g["node"] as Node3D).position = p
		(g["node"] as Node3D).look_at(Vector3(0, 0, -1.0), Vector3.UP)
		g["home"] = (g["node"] as Node3D).transform
		g["home_y"] = 0.0
		g["home_yaw"] = (g["node"] as Node3D).rotation.y
		g["base_y"] = 0.0
		_guides.append(g)


func _build_guide(def: Dictionary, idx: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Guide%d_%s" % [idx, String(def["name"])]
	add_child(root)

	var body_col: Color = def["body"]
	var accent: Color = def["accent"]
	var feature: String = def["feature"]

	var body_mat := MarigoldFX.glow(body_col, 0.9)
	var accent_mat := MarigoldFX.glow(accent, 1.5)
	var eye_mat := MarigoldFX.glow(Color(1, 1, 1), 2.5)
	var dark_mat := MarigoldFX.pbr(Color(0.10, 0.05, 0.03), 0.0, 0.8)

	var g := {
		"node": root, "def": def, "fed": false, "hop_t": -1.0,
		"phase": float(idx) * 1.7, "base_y": 0.0, "home_y": 0.0,
		"home": Transform3D.IDENTITY, "home_yaw": 0.0, "mats": [eye_mat],
		"wing_l": null, "wing_r": null, "tail": null,
		"head": null, "ear_l": null, "ear_r": null,
		"bob_amp": 0.06, "bob_speed": 2.0, "flap_speed": 7.0,
		"personality": "", "personality_t": 3.0 + float(idx) * 1.3,
		"action_t": 0.0, "joy_t": 0.0,
	}

	# Body: rounded, slightly elongated.
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 0.55
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body
	body_mi.material_override = body_mat
	body_mi.scale = Vector3(1.0, 0.85, 1.35)
	body_mi.position = Vector3(0, 0.62, 0)
	root.add_child(body_mi)

	# Head pivot (lets the guide curiously track the player's hand).
	var head_pivot := Node3D.new()
	head_pivot.position = Vector3(0, 1.0, -0.42)
	root.add_child(head_pivot)
	g["head"] = head_pivot
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.40
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.material_override = body_mat
	head_pivot.add_child(head_mi)

	# Glowing eyes.
	for sx in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.045
		eye.height = 0.09
		var eye_mi := MeshInstance3D.new()
		eye_mi.mesh = eye
		eye_mi.material_override = eye_mat
		eye_mi.position = Vector3(sx * 0.09, 0.07, -0.18)
		head_pivot.add_child(eye_mi)

	# Four stubby legs.
	for lx in [-0.18, 0.18]:
		for lz in [-0.25, 0.25]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.05
			leg.bottom_radius = 0.065
			leg.height = 0.45
			var leg_mi := MeshInstance3D.new()
			leg_mi.mesh = leg
			leg_mi.material_override = dark_mat
			leg_mi.position = Vector3(lx, 0.22, lz)
			root.add_child(leg_mi)

	# Generic tail pivot (sways); serpent feature extends it.
	var tail := Node3D.new()
	tail.position = Vector3(0, 0.72, 0.42)
	root.add_child(tail)
	g["tail"] = tail
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.10, 0.10, 0.45)
	var tail_mi := MeshInstance3D.new()
	tail_mi.mesh = tail_mesh
	tail_mi.material_override = accent_mat
	tail_mi.position = Vector3(0, 0.08, 0.25)
	tail_mi.rotation.x = -0.5
	tail.add_child(tail_mi)

	# Alebrije folk-art detailing: glowing dorsal ridge + painted flank spots.
	# (v0.2.0: rich surface detail over the base body.)
	var ridge_mat := MarigoldFX.glow(accent, 2.2)
	for ri in 5:
		var spike := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.008
		sm.bottom_radius = 0.035
		sm.height = 0.14
		sm.radial_segments = 6
		spike.mesh = sm
		spike.material_override = ridge_mat
		var rt := float(ri) / 4.0
		spike.position = Vector3(0, 0.86 + sin(rt * PI) * 0.10, lerpf(0.30, -0.34, rt))
		spike.rotation_degrees.x = lerpf(-28.0, 28.0, rt)
		root.add_child(spike)
	var spot_mat := MarigoldFX.glow(accent, 1.6)
	var spot_rng := RandomNumberGenerator.new()
	spot_rng.seed = 1000 + idx * 77
	for si in 14:
		var spot := MeshInstance3D.new()
		var spm := SphereMesh.new()
		spm.radius = 0.035
		spm.height = 0.05
		spot.mesh = spm
		spot.material_override = spot_mat
		var sa := spot_rng.randf() * TAU
		var sy := spot_rng.randf_range(0.48, 0.82)
		spot.position = Vector3(cos(sa) * 0.30, sy, sin(sa) * 0.40)
		spot.scale = Vector3(1.0, 1.0, 0.45)
		root.add_child(spot)

	match feature:
		"moth_wings":
			_add_moth_wings(root, g, accent_mat, eye_mat, dark_mat)
		"gills":
			_add_axolotl_traits(root, g, accent_mat)
		"serpent_tail":
			_add_serpent_traits(root, g, accent_mat, dark_mat)
		"rabbit_ears":
			_add_owl_rabbit_traits(root, g, body_mat, accent_mat)

	# Name label floating above.
	var nl := MarigoldFX.make_label(String(def["name"]), 56, Color(1.0, 0.9, 0.6))
	nl.position = Vector3(0, 1.75, 0)
	root.add_child(nl)
	var sl := MarigoldFX.make_label(String(def["sub"]), 36, Color(0.9, 0.85, 0.95))
	sl.position = Vector3(0, 1.5, 0)
	root.add_child(sl)

	return g


func _add_moth_wings(root: Node3D, g: Dictionary, accent_mat: Material, eye_mat: Material, dark_mat: Material) -> void:
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.26, 0.88, 0.05)
		root.add_child(pivot)
		if side < 0.0:
			g["wing_l"] = pivot
		else:
			g["wing_r"] = pivot
		var w := BoxMesh.new()
		w.size = Vector3(0.62, 0.05, 0.48)
		var wmi := MeshInstance3D.new()
		wmi.mesh = w
		wmi.material_override = accent_mat
		wmi.position = Vector3(side * 0.34, 0, 0)
		pivot.add_child(wmi)
		# Moth eye-spot on each wing.
		var spot := SphereMesh.new()
		spot.radius = 0.09
		spot.height = 0.05
		var smi := MeshInstance3D.new()
		smi.mesh = spot
		smi.material_override = eye_mat
		smi.position = Vector3(side * 0.34, 0.035, 0)
		pivot.add_child(smi)
	# Jaguar rosettes dotting the body.
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var sp := SphereMesh.new()
		sp.radius = 0.05
		sp.height = 0.07
		var spmi := MeshInstance3D.new()
		spmi.mesh = sp
		spmi.material_override = dark_mat
		spmi.position = Vector3(cos(a) * 0.30, 0.62 + 0.13 * sin(a * 2.0), sin(a) * 0.40)
		root.add_child(spmi)
	# Feathery antennae (ride on the head pivot).
	var hpivot: Node3D = g["head"]
	for side in [-1.0, 1.0]:
		var ant := CylinderMesh.new()
		ant.top_radius = 0.012
		ant.bottom_radius = 0.012
		ant.height = 0.22
		var ami := MeshInstance3D.new()
		ami.mesh = ant
		ami.material_override = accent_mat
		ami.position = Vector3(side * 0.08, 0.28, -0.04)
		ami.rotation.z = -side * 0.35
		hpivot.add_child(ami)
	g["personality"] = "burst"
	g["flap_speed"] = 7.0
	g["bob_amp"] = 0.06
	g["bob_speed"] = 2.0


func _add_axolotl_traits(root: Node3D, g: Dictionary, accent_mat: Material) -> void:
	var hpivot: Node3D = g["head"]
	# External gill fans around the head.
	for side in [-1.0, 1.0]:
		for gi in 3:
			var gill := BoxMesh.new()
			gill.size = Vector3(0.17, 0.03, 0.07)
			var gmi := MeshInstance3D.new()
			gmi.mesh = gill
			gmi.material_override = accent_mat
			gmi.position = Vector3(side * (0.24 + gi * 0.05), 0.04 - gi * 0.045, 0.14 + gi * 0.09)
			gmi.rotation.z = side * 0.55
			hpivot.add_child(gmi)
	# Hummingbird beak.
	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.032
	beak.height = 0.30
	var bmi := MeshInstance3D.new()
	bmi.mesh = beak
	bmi.material_override = accent_mat
	bmi.rotation_degrees.x = -90.0
	bmi.position = Vector3(0, -0.02, -0.32)
	hpivot.add_child(bmi)
	# Tiny blurred-fast wings.
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.28, 0.80, -0.05)
		root.add_child(pivot)
		if side < 0.0:
			g["wing_l"] = pivot
		else:
			g["wing_r"] = pivot
		var w := BoxMesh.new()
		w.size = Vector3(0.30, 0.03, 0.20)
		var wmi := MeshInstance3D.new()
		wmi.mesh = w
		wmi.material_override = accent_mat
		wmi.position = Vector3(side * 0.17, 0, 0)
		pivot.add_child(wmi)
	g["personality"] = "hover"
	g["flap_speed"] = 14.0
	g["bob_amp"] = 0.13
	g["bob_speed"] = 3.4


func _add_serpent_traits(root: Node3D, g: Dictionary, accent_mat: Material, dark_mat: Material) -> void:
	# Long curling serpent tail replacing the stub: chain of segments.
	var tail: Node3D = g["tail"]
	for c in tail.get_children():
		c.queue_free()
	for si in 5:
		var r := 0.085 - si * 0.011
		var seg := SphereMesh.new()
		seg.radius = r
		seg.height = r * 2.0
		var smi := MeshInstance3D.new()
		smi.mesh = seg
		smi.material_override = accent_mat
		smi.position = Vector3(0, 0.10 + si * 0.10, 0.10 + si * 0.13)
		tail.add_child(smi)
	# Rattle tip.
	var tip := SphereMesh.new()
	tip.radius = 0.05
	tip.height = 0.12
	var tmi := MeshInstance3D.new()
	tmi.mesh = tip
	tmi.material_override = MarigoldFX.glow(Color(1.0, 0.85, 0.30), 2.2)
	tmi.position = Vector3(0, 0.62, 0.78)
	tail.add_child(tmi)
	# Coyote ears: two cones (ride on the head pivot).
	var hpivot: Node3D = g["head"]
	for side in [-1.0, 1.0]:
		var ear := CylinderMesh.new()
		ear.top_radius = 0.0
		ear.bottom_radius = 0.06
		ear.height = 0.20
		var emi := MeshInstance3D.new()
		emi.mesh = ear
		emi.material_override = dark_mat
		emi.position = Vector3(side * 0.12, 0.26, 0.02)
		emi.rotation.z = -side * 0.25
		hpivot.add_child(emi)
	# Forked tongue.
	var tongue := BoxMesh.new()
	tongue.size = Vector3(0.03, 0.012, 0.16)
	var tong_mi := MeshInstance3D.new()
	tong_mi.mesh = tongue
	tong_mi.material_override = MarigoldFX.glow(Color(1.0, 0.25, 0.45), 1.6)
	tong_mi.position = Vector3(0, -0.06, -0.28)
	hpivot.add_child(tong_mi)
	g["personality"] = "rattle"
	g["flap_speed"] = 0.0
	g["bob_amp"] = 0.05
	g["bob_speed"] = 1.6


func _add_owl_rabbit_traits(root: Node3D, g: Dictionary, body_mat: Material, accent_mat: Material) -> void:
	var hpivot: Node3D = g["head"]
	# Long rabbit ears with glowing tips (ride on the head pivot; twitchable).
	for side in [-1.0, 1.0]:
		var ear := BoxMesh.new()
		ear.size = Vector3(0.09, 0.42, 0.05)
		var emi := MeshInstance3D.new()
		emi.mesh = ear
		emi.material_override = body_mat
		emi.position = Vector3(side * 0.11, 0.40, 0.02)
		emi.rotation.z = -side * 0.18
		hpivot.add_child(emi)
		if side < 0.0:
			g["ear_l"] = emi
		else:
			g["ear_r"] = emi
		var tip := SphereMesh.new()
		tip.radius = 0.05
		tip.height = 0.10
		var tmi := MeshInstance3D.new()
		tmi.mesh = tip
		tmi.material_override = accent_mat
		tmi.position = Vector3(side * 0.15, 0.63, 0.02)
		hpivot.add_child(tmi)
	# Owl facial disk.
	var disk := CylinderMesh.new()
	disk.top_radius = 0.20
	disk.bottom_radius = 0.20
	disk.height = 0.04
	var dmi := MeshInstance3D.new()
	dmi.mesh = disk
	dmi.material_override = MarigoldFX.pbr(Color(0.98, 0.92, 0.80), 0.0, 0.9)
	dmi.rotation_degrees.x = 90.0
	dmi.position = Vector3(0, 0.03, -0.18)
	hpivot.add_child(dmi)
	g["personality"] = "twitch"
	g["flap_speed"] = 5.0
	g["bob_amp"] = 0.07
	g["bob_speed"] = 2.2
	# Small owl wings.
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.30, 0.70, 0.05)
		root.add_child(pivot)
		if side < 0.0:
			g["wing_l"] = pivot
		else:
			g["wing_r"] = pivot
		var w := BoxMesh.new()
		w.size = Vector3(0.28, 0.05, 0.34)
		var wmi := MeshInstance3D.new()
		wmi.mesh = w
		wmi.material_override = accent_mat
		wmi.position = Vector3(side * 0.16, -0.05, 0.05)
		pivot.add_child(wmi)


# ---------------------------------------------------------------- guitar corner

func _build_guitar() -> void:
	var root := Node3D.new()
	root.name = "GuitarCorner"
	root.position = Vector3(4.1, 0.0, 2.4)
	root.rotation.y = -0.7
	root.rotation.x = -0.10 # gentle lean back
	add_child(root)

	var wood := MarigoldFX.pbr(Color(0.45, 0.20, 0.08), 0.1, 0.5)
	var wood_light := MarigoldFX.pbr(Color(0.72, 0.45, 0.20), 0.1, 0.5)

	# Giant stylized body: flattened cylinder facing the player.
	var body := CylinderMesh.new()
	body.top_radius = 0.42
	body.bottom_radius = 0.46
	body.height = 0.16
	body.radial_segments = 24
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body
	body_mi.material_override = wood
	body_mi.rotation_degrees.x = 90.0
	body_mi.position = Vector3(0, 0.62, 0)
	root.add_child(body_mi)

	# Sound hole.
	var hole := CylinderMesh.new()
	hole.top_radius = 0.11
	hole.bottom_radius = 0.11
	hole.height = 0.02
	var hole_mi := MeshInstance3D.new()
	hole_mi.mesh = hole
	hole_mi.material_override = MarigoldFX.pbr(Color(0.02, 0.01, 0.01), 0.0, 1.0)
	hole_mi.rotation_degrees.x = 90.0
	hole_mi.position = Vector3(0, 0.62, 0.09)
	root.add_child(hole_mi)

	# Neck + headstock.
	var neck := BoxMesh.new()
	neck.size = Vector3(0.13, 1.15, 0.07)
	var neck_mi := MeshInstance3D.new()
	neck_mi.mesh = neck
	neck_mi.material_override = wood_light
	neck_mi.position = Vector3(0, 1.55, 0.0)
	root.add_child(neck_mi)
	var head := BoxMesh.new()
	head.size = Vector3(0.17, 0.30, 0.06)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.material_override = wood
	head_mi.position = Vector3(0, 2.24, 0.0)
	root.add_child(head_mi)

	# Frets.
	for f in 5:
		var fret := BoxMesh.new()
		fret.size = Vector3(0.14, 0.012, 0.075)
		var fmi := MeshInstance3D.new()
		fmi.mesh = fret
		fmi.material_override = MarigoldFX.glow(Color(0.9, 0.75, 0.45), 0.8)
		fmi.position = Vector3(0, 1.18 + f * 0.18, 0.0)
		root.add_child(fmi)

	# Six glowing strings along the neck.
	var string_mat := MarigoldFX.glow(Color(1.0, 0.90, 0.60), 1.8)
	_string_x.clear()
	for i in 6:
		var sx := -0.075 + i * 0.03
		_string_x.append(sx)
		var s := CylinderMesh.new()
		s.top_radius = 0.004
		s.bottom_radius = 0.004
		s.height = 1.75
		s.radial_segments = 6
		var smi := MeshInstance3D.new()
		smi.mesh = s
		smi.material_override = string_mat
		smi.position = Vector3(sx, 1.32, 0.10)
		root.add_child(smi)

	MarigoldFX.make_point_light(root, Vector3(0, 1.4, 0.7), Color(1.0, 0.70, 0.35), 0.9, 3.5)

	var gl := MarigoldFX.make_label("Guitar Corner", 56, Color(1.0, 0.85, 0.50))
	gl.position = Vector3(0, 2.72, 0)
	root.add_child(gl)
	var hint := MarigoldFX.make_label("Strum across the strings", 40, Color(0.95, 0.90, 0.80))
	hint.position = Vector3(0, 2.42, 0)
	root.add_child(hint)

	_guitar = root
	_guitar_home = root.transform


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	_plaque = MarigoldPlaques.place_plaque(
		self, "Alebrijes",
		"Brightly painted Oaxacan folk-art spirit animals. Tradition holds that alebrijes guide and protect souls on their journey - each one carries the colors of its maker's dreams.",
		Vector3(-2.4, 1.6, 1.6), 1.9)
	_feed_label = MarigoldFX.make_label("Spirit guides fed: 0 / 4", 52, Color(1.0, 0.85, 0.45))
	_feed_label.position = Vector3(0, 2.4, 2.6)
	add_child(_feed_label)
	_status_label = MarigoldFX.make_label("", 48, Color(0.9, 0.95, 1.0))
	_status_label.position = Vector3(0, 2.05, 2.6)
	add_child(_status_label)


# ---------------------------------------------------------------- idle animation

func _animate_guides(delta: float) -> void:
	var hand_pts := [_hand_point(MarigoldHands.HAND_LEFT), _hand_point(MarigoldHands.HAND_RIGHT)]
	for g in _guides:
		var node: Node3D = g["node"]
		var ph: float = float(g["phase"])
		var personality: String = String(g["personality"])
		var y: float = float(g["base_y"])
		# Hop (feed reaction).
		var hop: float = float(g["hop_t"])
		if hop >= 0.0:
			hop += delta * 2.2
			if hop >= 1.0:
				g["hop_t"] = -1.0
			else:
				g["hop_t"] = hop
				y += sin(hop * PI) * 0.5
		# Joy spin + squash-and-stretch (the bigger happy reaction).
		var joy: float = float(g["joy_t"])
		if joy > 0.0:
			joy = maxf(0.0, joy - delta)
			g["joy_t"] = joy
			node.rotation.y += delta * TAU / 0.9
			var sq := 1.0 + 0.12 * sin(joy * 14.0)
			node.scale = Vector3(2.0 - sq, sq, 2.0 - sq)
			if joy <= 0.0:
				node.scale = Vector3.ONE
				node.rotation.y = float(g["home_yaw"])
		# Personality action timer: each guide does its signature move.
		var pt: float = float(g["personality_t"]) - delta
		if pt <= 0.0:
			pt = randf_range(4.0, 8.0)
			g["action_t"] = 1.2
		g["personality_t"] = pt
		var action: float = float(g["action_t"])
		if action > 0.0:
			g["action_t"] = maxf(0.0, action - delta)
		# Idle bob (per-guide rhythm).
		node.position.y = y + sin(_t * float(g["bob_speed"]) + ph) * float(g["bob_amp"])
		# Wing flap (moth does periodic big bursts).
		if g["wing_l"] != null:
			var fs: float = float(g["flap_speed"])
			if personality == "burst" and action > 0.0:
				fs *= 3.0
			var flap := sin(_t * fs + ph) * 0.55
			(g["wing_l"] as Node3D).rotation.z = 0.25 + flap
			(g["wing_r"] as Node3D).rotation.z = -0.25 - flap
		# Tail: serpent rattles its tail; others sway.
		if g["tail"] != null:
			if personality == "rattle" and action > 0.0:
				(g["tail"] as Node3D).rotation.y = sin(_t * 30.0) * 0.35
			else:
				(g["tail"] as Node3D).rotation.y = sin(_t * 2.4 + ph) * 0.5
		# Rabbit ear twitch.
		if personality == "twitch" and g["ear_l"] != null:
			var tw := 0.0
			if action > 0.0:
				tw = sin(_t * 25.0) * 0.30
			(g["ear_l"] as Node3D).rotation.z = 0.18 + tw
			(g["ear_r"] as Node3D).rotation.z = -0.18 - tw
		# Curiosity: the head tracks the nearest hand within 2.5 m.
		var head: Node3D = g["head"]
		if head != null:
			var gp: Vector3 = node.global_position
			var best_d := 2.5
			var target_hp := Vector3.ZERO
			for hp in hand_pts:
				var d: float = gp.distance_to(hp)
				if d < best_d:
					best_d = d
					target_hp = hp
			var target_yaw: float
			if best_d < 2.5:
				var inv: Transform3D = head.get_parent().global_transform.affine_inverse()
				var local_t: Vector3 = inv * target_hp
				target_yaw = clampf(atan2(-local_t.x, -local_t.z), -0.7, 0.7)
			else:
				target_yaw = sin(_t * 0.6 + ph) * 0.30
			head.rotation.y = lerpf(head.rotation.y, target_yaw, minf(1.0, delta * 4.0))
		# Eye glow pulse.
		for m in g["mats"]:
			MarigoldFX.pulse_glow(m, 1.6, 0.9, _t + ph, 2.5)


# ---------------------------------------------------------------- feeding interaction

func _hand_point(hand: int) -> Vector3:
	if MarigoldHands.is_xr_active():
		return MarigoldHands.pointer_position(self, hand)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + Vector3(0, 1.2, -1.6)
	var mp := get_viewport().get_mouse_position()
	return cam.project_ray_origin(mp) + cam.project_ray_normal(mp) * 1.6


func _hand_ray(hand: int) -> Array:
	if MarigoldHands.is_xr_active():
		return MarigoldHands.pointer_ray(self, hand)
	var cam := get_viewport().get_camera_3d()
	var mp := get_viewport().get_mouse_position()
	if cam == null:
		return [global_position + Vector3(0, 1.2, -1.6), Vector3(0, 0, -1)]
	return [cam.project_ray_origin(mp), cam.project_ray_normal(mp)]


func _update_feeding() -> void:
	if _celebrating:
		return
	for h in [MarigoldHands.HAND_LEFT, MarigoldHands.HAND_RIGHT]:
		var pinching: bool = MarigoldHands.pinch_active(self, h)
		var ppos: Vector3 = _hand_point(h)
		if pinching and not _orbs.has(h):
			var target: Variant = _nearest_unfed_guide(ppos)
			if target != null:
				var orb := _make_orb()
				orb.global_position = ppos
				add_child(orb)
				_orbs[h] = orb
				if MarigoldState.music != null:
					MarigoldState.music.pluck(76, 0.35, 0.6)
		if _orbs.has(h):
			var orb: Node3D = _orbs[h]
			if pinching:
				orb.global_position = ppos
			else:
				_orbs.erase(h)
				var ray: Array = _hand_ray(h)
				var aimed: Variant = _aimed_guide(ray[0], ray[1])
				if aimed != null:
					_feed_guide(aimed, orb)
				else:
					_fizzle_orb(orb)


func _make_orb() -> Node3D:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	orb.mesh = sm
	orb.material_override = MarigoldFX.glow(Color(1.0, 0.90, 0.55), 2.6)
	var trail := MarigoldFX.make_trail(Color(1.0, 0.85, 0.45), 0.05)
	orb.add_child(trail)
	return orb


func _nearest_unfed_guide(ppos: Vector3) -> Variant:
	var best: Variant = null
	var best_d := FEED_RANGE
	for g in _guides:
		if bool(g["fed"]):
			continue
		var gp: Vector3 = (g["node"] as Node3D).global_position + Vector3(0, 0.7, 0)
		var d := gp.distance_to(ppos)
		if d < best_d:
			best_d = d
			best = g
	return best


func _aimed_guide(origin: Vector3, dir: Vector3) -> Variant:
	var best: Variant = null
	var best_perp := AIM_TOLERANCE
	for g in _guides:
		if bool(g["fed"]):
			continue
		var gp: Vector3 = (g["node"] as Node3D).global_position + Vector3(0, 0.7, 0)
		var to_g := gp - origin
		var proj := to_g.dot(dir)
		if proj < 0.3 or proj > AIM_MAX_DIST:
			continue
		var perp := (to_g - dir * proj).length()
		if perp < best_perp:
			best_perp = perp
			best = g
	return best


func _feed_guide(g: Dictionary, orb: Node3D) -> void:
	g["fed"] = true
	var target: Vector3 = (g["node"] as Node3D).global_position + Vector3(0, 0.7, 0)
	var tw := create_tween()
	tw.tween_property(orb, "global_position", target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_on_orb_arrived.bind(g, orb))


func _on_orb_arrived(g: Dictionary, orb: Node3D) -> void:
	var pos: Vector3 = orb.global_position
	orb.queue_free()
	var col: Color = (g["def"] as Dictionary)["glow"]
	MarigoldFX.spawn_sparks(self, pos, col, 30)
	MarigoldFX.scatter_petals(self, pos, 24)
	MarigoldHaptics.thump()
	g["hop_t"] = 0.0
	g["joy_t"] = 0.9 # spin + squash-and-stretch celebration
	if MarigoldState.music != null:
		MarigoldState.music.pluck(67, 0.7, 1.0)
		MarigoldState.music.pluck(72, 0.7, 1.2)
	_fed_count += 1
	_feed_label.text = "Spirit guides fed: %d / 4" % _fed_count
	_status_label.text = "%s is delighted!" % String((g["def"] as Dictionary)["name"])
	if _fed_count >= 4 and not _celebrating:
		_celebrate()


func _fizzle_orb(orb: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(orb, "scale", Vector3.ZERO, 0.25)
	tw.tween_callback(orb.queue_free)


func _celebrate() -> void:
	_celebrating = true
	_status_label.text = "Todos los guias estan contentos!"
	for g in _guides:
		var n: Node3D = g["node"]
		MarigoldFX.spawn_confetti(self, n.global_position + Vector3(0, 1.2, 0), 40)
		g["hop_t"] = 0.0
		g["joy_t"] = 2.7 # victory dance: ~3 spins
	if MarigoldState.music != null:
		for note in [60, 64, 67, 72, 76]:
			MarigoldState.music.pluck(note, 0.6, 1.5)
	await get_tree().create_timer(3.2).timeout
	for g in _guides:
		var n2: Node3D = g["node"]
		n2.scale = Vector3.ONE
		n2.rotation.y = float(g["home_yaw"])
	if _complete_sent:
		return
	_complete_sent = true
	chapter_complete.emit()


# ---------------------------------------------------------------- guitar strumming

func _update_strum() -> void:
	if _guitar == null:
		return
	var ppos: Vector3 = _hand_point(MarigoldHands.HAND_RIGHT)
	var local: Vector3 = _guitar.to_local(ppos)
	if not _has_prev_strum:
		_prev_strum_x = local.x
		_has_prev_strum = true
		return
	var in_zone := local.y > 0.40 and local.y < 2.20 and absf(local.z) < 0.50
	if in_zone:
		for i in 6:
			var sx: float = _string_x[i]
			var crossed := (_prev_strum_x < sx) != (local.x < sx)
			if crossed:
				_pluck_string(i, local)
	_prev_strum_x = local.x


func _pluck_string(i: int, local: Vector3) -> void:
	if MarigoldState.music != null:
		MarigoldState.music.pluck(int(STRING_MIDIS[i]), 0.85, 1.4)
	var hit: Vector3 = _guitar.to_global(Vector3(float(_string_x[i]), clampf(local.y, 0.5, 2.1), 0.14))
	MarigoldFX.spawn_sparks(self, hit, Color(1.0, 0.85, 0.40), 8)
