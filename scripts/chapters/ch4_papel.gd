## ch4_papel.gd - MARIGOLD Chapter 4: Papel Picado Canopy.
## A walkway corridor under rows of giant cut-paper banners. Waving a hand near
## a banner ripples it (wave shader boost + confetti). Rippling any banner in
## each of the 3 gates awakens it; all gates awakened opens the golden arch walk.
extends Node3D

signal chapter_complete

const WAVE_SPEED_THRESHOLD := 2.0 # m/s of hand motion to ripple a banner
const RIPPLE_RADIUS := 1.25
const BASE_WAVE_AMP := 0.09

const BANNER_COLORS := [
	Color(1.0, 0.15, 0.55), # magenta
	Color(0.10, 0.85, 1.0), # cyan
	Color(1.0, 0.50, 0.10), # orange
	Color(0.60, 0.25, 1.0), # purple
	Color(0.10, 0.90, 0.70), # teal
]

# Pentatonic plucks for wave feedback (A C D E G A C E).
const PENTA := [57, 60, 62, 64, 65, 69, 72, 76]

# Row layout: (z, is_gate). 7 rows x 2 banners = 14 banners.
const ROWS := [
	[0.5, false], [-2.5, true], [-4.5, false], [-6.5, true],
	[-8.5, false], [-10.5, true], [-12.0, false],
]
const GATE_NAMES := ["First Gate", "Second Gate", "Third Gate"]

var _t := 0.0
var _ar_mode := false
var _banners: Array = [] # {"mi","mat","boost","gate","base_tint","awakened","phase","home_pos","home_yaw"}
var _posts: Array = []
var _lantern_spans: Array = []
var _wall_anchors: Array = []
var _gates := [false, false, false]
var _gate_labels: Array = []
var _gate_centers_home: Array = []
var _arch: Node3D
var _arch_home := Vector3.ZERO
var _arch_glow_mat: StandardMaterial3D
var _path_blossoms: Array = [] # {"mi","t","side"}
var _path_start := Vector3(0, 0, 2.5)
var _path_end := Vector3(0, 0, -12.5)
var _fireflies: GPUParticles3D
var _plaque: Node3D
var _count_label: Label3D
var _status_label: Label3D
var _prev_pos := {} # hand -> Vector3
var _awakened_count := 0
var _final_phase := false
var _final_timer := 0.0
var _arch_greeted := false
var _complete_sent := false
var _rng := RandomNumberGenerator.new()


## Null-safe wind strength (headless tests may lack the sky singleton).
func _wind_strength() -> float:
	if MarigoldSky.instance != null:
		return MarigoldSky.instance.get_wind_strength()
	return 0.0


func _ready() -> void:
	_rng.seed = 4242
	_build_corridor()
	_build_gates_and_arch()
	_build_path()
	_build_ui()
	MarigoldFX.spawn_ambient_motes(self, Vector3(0, 1.6, -5), 6.0, 80)
	# Drifting petals riding a gentle breeze down the corridor (looping).
	var drift := GPUParticles3D.new()
	drift.amount = 70
	drift.lifetime = 9.0
	drift.preprocess = 9.0
	drift.position = Vector3(0, 1.3, -5)
	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dpm.emission_box_extents = Vector3(2.2, 1.0, 8.0)
	dpm.direction = Vector3(0, 0, -1)
	dpm.spread = 12.0
	dpm.initial_velocity_min = 0.3
	dpm.initial_velocity_max = 0.8
	dpm.gravity = Vector3.ZERO
	dpm.scale_min = 0.03
	dpm.scale_max = 0.06
	var dgrad := Gradient.new()
	dgrad.set_color(0, Color(1.0, 0.62, 0.10))
	dgrad.add_point(0.5, Color(1.0, 0.80, 0.25))
	dgrad.set_color(1, Color(0.85, 0.35, 0.05))
	var dramp := GradientTexture1D.new()
	dramp.gradient = dgrad
	dpm.color_ramp = dramp
	drift.process_material = dpm
	var dquad := QuadMesh.new()
	dquad.size = Vector2(0.05, 0.035)
	dquad.material = MarigoldFX.glow(Color(1.0, 0.65, 0.12), 1.8)
	drift.draw_pass_1 = dquad
	add_child(drift)
	drift.emitting = true
	# Warm light shafts cutting through the canopy.
	for gz in [0.0, -4.0, -8.0, -12.0]:
		MarigoldFX.make_god_ray(self, Vector3(0.8, 0, gz), 8.0, Color(1.0, 0.72, 0.35))
	MarigoldFX.make_light_rig(self, 0.9)


func setup(ar_mode: bool) -> void:
	_ar_mode = ar_mode
	apply_mode(ar_mode)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	for p in _posts:
		(p as Node3D).visible = not on
	for sp in _lantern_spans:
		(sp as Node3D).visible = not on
	for w in _wall_anchors:
		(w as Node3D).visible = on
	if on:
		# String banners across the room at ~2m height (5-column grid).
		var ai := 0
		for i in _banners.size():
			var b: Dictionary = _banners[i]
			if bool(b["fixed"]):
				continue
			var mi: MeshInstance3D = b["mi"]
			mi.position = Vector3(-1.4 + (ai % 5) * 0.7, 2.0, 1.0 - (ai / 5) * 0.6)
			mi.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
			ai += 1
		_arch.position = Vector3(0, 0, -2.5)
		_path_start = Vector3(0, 0, 1.8)
		_path_end = Vector3(0, 0, -2.3)
	else:
		for b in _banners:
			var mi2: MeshInstance3D = b["mi"]
			mi2.position = b["home_pos"]
			mi2.rotation = Vector3(deg_to_rad(90.0), float(b["home_yaw"]), 0.0)
		_arch.position = _arch_home
		_path_start = Vector3(0, 0, 2.5)
		_path_end = Vector3(0, 0, -12.5)
	_layout_path()
	_update_gate_labels()
	if on:
		_plaque.position = Vector3(1.3, 1.5, -0.6)
		_count_label.position = Vector3(0, 2.5, 0.6)
		_status_label.position = Vector3(0, 2.2, 0.6)
	else:
		_plaque.position = Vector3(1.9, 1.6, 1.8)
		_count_label.position = Vector3(0, 3.4, 1.8)
		_status_label.position = Vector3(0, 3.05, 1.8)


func _process(delta: float) -> void:
	_t += delta
	_update_hand_waves(delta)
	_update_banners(delta)
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)
	if _final_phase and not _complete_sent:
		_check_finale(delta)
	if _arch_glow_mat != null and _final_phase:
		MarigoldFX.pulse_glow(_arch_glow_mat, 1.8, 1.2, _t, 3.0)


# ---------------------------------------------------------------- corridor build

func _build_corridor() -> void:
	var post_mat := MarigoldFX.pbr(Color(0.30, 0.16, 0.08), 0.1, 0.6)
	var gate_idx := 0
	for r in ROWS.size():
		var z: float = ROWS[r][0]
		var is_gate: bool = ROWS[r][1]
		# Posts flanking the row: real carved wooden pillars (Kenney CC0).
		for sx in [-1.0, 1.0]:
			var post := Node3D.new()
			post.position = Vector3(sx * 2.35, 0, z)
			add_child(post)
			var km := MarigoldModels.instance(MarigoldModels.FANTASY, "pillar-wood")
			if km != null:
				MarigoldModels.recolor(km, Color(0.38, 0.22, 0.12), 0.1, 0.65)
				km.scale = Vector3(1.3, 2.4, 1.3)
				post.add_child(km)
			else:
				var pole := CylinderMesh.new()
				pole.top_radius = 0.06
				pole.bottom_radius = 0.08
				pole.height = 3.4
				var pole_mi := MeshInstance3D.new()
				pole_mi.mesh = pole
				pole_mi.material_override = post_mat
				pole_mi.position.y = 1.7
				post.add_child(pole_mi)
			var topper := SphereMesh.new()
			topper.radius = 0.10
			topper.height = 0.20
			var top_mi := MeshInstance3D.new()
			top_mi.mesh = topper
			top_mi.material_override = MarigoldFX.glow(BANNER_COLORS[r % BANNER_COLORS.size()], 2.4)
			top_mi.position.y = 3.45
			post.add_child(top_mi)
			_posts.append(post)
		# Two main banners spanning the walkway, rows at varying heights.
		var by := 2.50 + float(r % 3) * 0.35
		for bi in 2:
			var bx := -1.15 + float(bi) * 2.30
			var col: Color = BANNER_COLORS[(r * 2 + bi) % BANNER_COLORS.size()]
			_add_banner(self, 2.2, 1.1, col, Vector3(bx, by, z),
				gate_idx if is_gate else -1)
		# Upper layer: smaller banners floating above, offset between the mains.
		for bi in 2:
			var ux := -0.58 + float(bi) * 1.16
			var ucol: Color = BANNER_COLORS[(r * 2 + bi + 3) % BANNER_COLORS.size()]
			_add_banner(self, 1.5, 0.8, ucol, Vector3(ux, by + 0.95, z), -1)
		if is_gate:
			gate_idx += 1
	# Lantern strings sagging between consecutive post rows.
	for r in ROWS.size() - 1:
		var z0: float = ROWS[r][0]
		var z1: float = ROWS[r + 1][0]
		for sx in [-1.0, 1.0]:
			var span := Node3D.new()
			span.name = "LanternSpan_%d_%d" % [r, int(sx)]
			add_child(span)
			_lantern_spans.append(span)
			for li in 6:
				var t := float(li) / 5.0
				var lpos := Vector3(sx * 2.35, 3.20 - sin(t * PI) * 0.50, lerpf(z0, z1, t))
				# Real paper lantern model (Kenney CC0).
				var lkm := MarigoldModels.instance(MarigoldModels.FANTASY, "lantern")
				var lcol := Color(1.0, 0.62, 0.28) if li % 2 == 0 else Color(1.0, 0.42, 0.55)
				if lkm != null:
					MarigoldModels.recolor_glow(lkm, lcol, lcol, 2.2)
					lkm.position = lpos
					span.add_child(lkm)
				else:
					var lantern := SphereMesh.new()
					lantern.radius = 0.11
					lantern.height = 0.20
					var lmi := MeshInstance3D.new()
					lmi.mesh = lantern
					lmi.scale = Vector3(1.0, 0.85, 1.0)
					lmi.material_override = MarigoldFX.glow(lcol, 2.0)
					lmi.position = lpos
					span.add_child(lmi)


	# Wall-anchored points for AR mode (replace posts).
	for corner in [Vector3(-1.55, 2.0, 1.55), Vector3(1.55, 2.0, 1.55),
			Vector3(-1.55, 2.0, -1.55), Vector3(1.55, 2.0, -1.55)]:
		var anchor := SphereMesh.new()
		anchor.radius = 0.07
		anchor.height = 0.14
		var ami := MeshInstance3D.new()
		ami.mesh = anchor
		ami.material_override = MarigoldFX.glow(Color(1.0, 0.65, 0.20), 2.0)
		ami.position = corner
		ami.visible = false
		add_child(ami)
		_wall_anchors.append(ami)

	# Gate label anchors (repositioned by layout).
	for gi in 3:
		var center := Vector3.ZERO
		var n := 0
		for b in _banners:
			if int(b["gate"]) == gi:
				center += (b["mi"] as Node3D).position
				n += 1
		if n > 0:
			center /= float(n)
		_gate_centers_home.append(center)
		var gl := MarigoldFX.make_label("", 44, Color(1.0, 0.85, 0.50))
		gl.position = center + Vector3(0, 0.95, 0)
		add_child(gl)
		_gate_labels.append(gl)


func _add_banner(parent: Node3D, width: float, height: float, col: Color, pos: Vector3, gate: int) -> void:
	var b := MarigoldFX.make_papel_banner(parent, width, height, col)
	b.position = pos
	b.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	var pm := b.mesh as PrimitiveMesh
	var smat := pm.material as ShaderMaterial
	_banners.append({
		"mi": b, "mat": smat, "boost": 0.0,
		"gate": gate,
		"base_tint": col, "awakened": false,
		"phase": _rng.randf() * TAU,
		"home_pos": pos, "home_yaw": 0.0,
		"fixed": false,
	})


func _build_gates_and_arch() -> void:
	_arch = Node3D.new()
	_arch.name = "FinalArch"
	_arch_home = Vector3(0, 0, -13.5)
	_arch.position = _arch_home
	add_child(_arch)
	var post_mat := MarigoldFX.pbr(Color(0.30, 0.16, 0.08), 0.1, 0.6)
	for sx in [-1.0, 1.0]:
		var pole := CylinderMesh.new()
		pole.top_radius = 0.07
		pole.bottom_radius = 0.09
		pole.height = 3.8
		var pmi := MeshInstance3D.new()
		pmi.mesh = pole
		pmi.material_override = post_mat
		pmi.position = Vector3(sx * 1.5, 1.9, 0)
		_arch.add_child(pmi)
	# Golden ring the player walks through.
	_arch_glow_mat = MarigoldFX.glow(Color(1.0, 0.75, 0.25), 1.8)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.10
	ring.outer_radius = 1.25
	ring.rings = 24
	ring.ring_segments = 48
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = _arch_glow_mat
	ring_mi.position = Vector3(0, 2.1, 0)
	_arch.add_child(ring_mi)
	# Banner draped across the top.
	var top := MarigoldFX.make_papel_banner(_arch, 3.2, 1.0, Color(1.0, 0.45, 0.10))
	top.position = Vector3(0, 3.6, 0)
	var pm := top.mesh as PrimitiveMesh
	_banners.append({
		"mi": top, "mat": pm.material as ShaderMaterial, "boost": 0.0,
		"gate": -1, "base_tint": Color(1.0, 0.45, 0.10), "awakened": false,
		"phase": _rng.randf() * TAU,
		"home_pos": top.position, "home_yaw": 0.0,
		"fixed": true,
	})
	var arch_label := MarigoldFX.make_label("El Arco Final", 52, Color(1.0, 0.85, 0.45))
	arch_label.position = Vector3(0, 4.4, 0)
	_arch.add_child(arch_label)


func _build_path() -> void:
	# Marigold blossoms lining both sides of the walkway.
	var blossom_mat := MarigoldFX.glow(Color(1.0, 0.55, 0.08), 1.6)
	var steps := 26
	for s in steps:
		var t := float(s) / float(steps - 1)
		for side in [-1.0, 1.0]:
			var bm := SphereMesh.new()
			bm.radius = 0.07
			bm.height = 0.10
			var bmi := MeshInstance3D.new()
			bmi.mesh = bm
			bmi.material_override = blossom_mat
			add_child(bmi)
			_path_blossoms.append({"mi": bmi, "t": t, "side": side})
	_layout_path()


func _layout_path() -> void:
	for pb in _path_blossoms:
		var t: float = pb["t"]
		var side: float = pb["side"]
		var p: Vector3 = _path_start.lerp(_path_end, t)
		(pb["mi"] as Node3D).position = Vector3(p.x + side * 1.1, 0.06, p.z)


func _build_ui() -> void:
	_plaque = MarigoldPlaques.place_plaque(
		self, "Papel Picado",
		"The craft of cut tissue-paper banners. Their delicate beauty represents the fragility of life - and the wind that carries prayers to those we honor.",
		Vector3(1.9, 1.6, 1.8), 1.9)
	_count_label = MarigoldFX.make_label("Gates awakened: 0 / 3", 52, Color(1.0, 0.85, 0.45))
	_count_label.position = Vector3(0, 3.4, 1.8)
	add_child(_count_label)
	_status_label = MarigoldFX.make_label("Wave your hands to ripple the banners", 44, Color(0.9, 0.95, 1.0))
	_status_label.position = Vector3(0, 3.05, 1.8)
	add_child(_status_label)
	_update_gate_labels()


func _update_gate_labels() -> void:
	for gi in 3:
		var gl: Label3D = _gate_labels[gi]
		var center := Vector3.ZERO
		var n := 0
		for b in _banners:
			if int(b["gate"]) == gi:
				center += (b["mi"] as Node3D).global_position
				n += 1
		if n > 0:
			center /= float(n)
			gl.global_position = center + Vector3(0, 0.95, 0)
		if _gates[gi]:
			gl.text = "✦ %s — awakened" % GATE_NAMES[gi]
		else:
			gl.text = "%s — ripple its banners" % GATE_NAMES[gi]


# ---------------------------------------------------------------- hand waving

func _hand_point(hand: int) -> Vector3:
	if MarigoldHands.is_xr_active():
		return MarigoldHands.pointer_position(self, hand)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + Vector3(0, 1.4, -1.6)
	var mp := get_viewport().get_mouse_position()
	return cam.project_ray_origin(mp) + cam.project_ray_normal(mp) * 1.6


func _update_hand_waves(delta: float) -> void:
	for h in [MarigoldHands.HAND_LEFT, MarigoldHands.HAND_RIGHT]:
		var ppos: Vector3 = _hand_point(h)
		if _prev_pos.has(h) and delta > 0.0001:
			var prev: Vector3 = _prev_pos[h]
			var speed := prev.distance_to(ppos) / delta
			if speed > WAVE_SPEED_THRESHOLD:
				_ripple(ppos)
		_prev_pos[h] = ppos


func _ripple(ppos: Vector3) -> void:
	for i in _banners.size():
		var b: Dictionary = _banners[i]
		var mi: Node3D = b["mi"]
		if mi.global_position.distance_to(ppos) < RIPPLE_RADIUS:
			b["boost"] = 1.0
			if _rng.randf() < 0.12:
				MarigoldFX.spawn_confetti(self, mi.global_position, 24)
			if MarigoldState.music != null:
				MarigoldState.music.pluck(int(PENTA[i % PENTA.size()]), 0.35, 0.9)
			var gi: int = int(b["gate"])
			if gi >= 0 and not _gates[gi]:
				_awaken_gate(gi)


func _update_banners(delta: float) -> void:
	# The banner chapter goes furthest: the wind itself drives the cloth
	# ripple (calm = gentle sway, storm = wild snap), and hand-wave boosts
	# still stack on top of the wind-driven base.
	var wind := _wind_strength()
	var gust := 1.2 + wind * 4.0
	var speed := 2.2 * (0.9 + wind * 1.8)
	for b in _banners:
		var mat: ShaderMaterial = b["mat"]
		var boost: float = float(b["boost"])
		if boost > 0.0:
			boost = maxf(0.0, boost - delta * 0.7)
			b["boost"] = boost
		mat.set_shader_parameter("wave_amp", (BASE_WAVE_AMP + boost * 0.55) * gust)
		mat.set_shader_parameter("wave_speed", speed)
		if bool(b["awakened"]):
			var base: Color = b["base_tint"]
			var k := 0.5 + 0.5 * sin(_t * 3.0 + float(b["phase"]))
			mat.set_shader_parameter("tint", base.lerp(Color(1, 1, 1), 0.35 * k))


func _awaken_gate(gi: int) -> void:
	_gates[gi] = true
	_awakened_count += 1
	for b in _banners:
		if int(b["gate"]) == gi:
			b["awakened"] = true
			b["boost"] = 1.0
			MarigoldFX.spawn_sparks(self, (b["mi"] as Node3D).global_position, Color(1.0, 0.80, 0.30), 24)
	_count_label.text = "Gates awakened: %d / 3" % _awakened_count
	_update_gate_labels()
	# The arch brightens with every awakened gate: visible progression.
	_arch_glow_mat.emission_energy_multiplier = 1.4 + float(_awakened_count) * 0.9
	_status_label.text = "%s awakened! (%d/3) - keep waving" % [GATE_NAMES[gi], _awakened_count]
	MarigoldHaptics.fanfare()
	if MarigoldState.music != null:
		MarigoldState.music.pluck(72, 0.7, 1.0)
		MarigoldState.music.pluck(76, 0.7, 1.2)
	if _awakened_count >= 3 and not _final_phase:
		_begin_finale()


func _begin_finale() -> void:
	_final_phase = true
	_final_timer = 0.0
	_status_label.text = "Walk through the golden arch!"
	MarigoldFX.scatter_petals(self, _arch.global_position + Vector3(0, 1.5, 0), 40)
	# Grand ripple: every banner surges at once.
	for b in _banners:
		b["boost"] = 1.0


func _check_finale(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var arch_pos: Vector3 = _arch.global_position + Vector3(0, 1.5, 0)
	if cam != null:
		var d: float = cam.global_position.distance_to(arch_pos)
		# Greeting beat as the player approaches the arch.
		if d < 3.0 and not _arch_greeted:
			_arch_greeted = true
			MarigoldFX.scatter_petals(self, arch_pos, 30)
			if MarigoldState.music != null:
				MarigoldState.music.pluck(79, 0.6, 1.4)
		if d < 1.3:
			_finish()
	else:
		# Headless / no camera: complete shortly after the gates open.
		_final_timer += delta
		if _final_timer > 3.0:
			_finish()


func _finish() -> void:
	if _complete_sent:
		return
	_complete_sent = true
	MarigoldFX.scatter_petals(self, _arch.global_position + Vector3(0, 1.5, 0), 80)
	MarigoldFX.spawn_confetti(self, _arch.global_position + Vector3(0, 2.0, 0), 80)
	_status_label.text = "¡Gracias!"
	chapter_complete.emit()
