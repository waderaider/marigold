## pinta.gd - MARIGOLD experience: Pinta Alebrijes (v0.6.0, finding 5).
## Creature-painting minigame: floating brushes + glowing paint drawers; the
## player colors an ORIGINAL spirit animal (a moth-jaguar alebrije variant -
## no film references of any kind) by ray-painting color onto body regions.
## When every region is painted it comes alive (MarigoldCharacterRig: blink,
## look-at, JOY) and joins the spirit menagerie (persisted in settings).
## Simple by design: region-level painting, not per-texel.
## No class_name (experience contract). Signal + setup/apply_mode contract.
extends Node3D

signal chapter_complete

const C_CREAM := Color(1.0, 0.93, 0.82)
const C_GOLD := Color(1.0, 0.80, 0.30)

const PAINTS := [
	{"name": "Rojo", "col": Color(1.0, 0.25, 0.20)},
	{"name": "Azul", "col": Color(0.25, 0.55, 1.0)},
	{"name": "Dorado", "col": Color(1.0, 0.75, 0.20)},
	{"name": "Verde", "col": Color(0.30, 0.90, 0.45)},
]

const REGIONS := ["Body", "Wings", "Ears", "Tail", "Spots"]

var _t := 0.0
var _ar_mode := false
var _stage: Node3D
var _backdrop: Node3D
var _creature: Node3D
var _rig: MarigoldCharacterRig = null
var _region_mats := {} # region -> StandardMaterial3D
var _region_nodes := {} # region -> Array[MeshInstance3D]
var _painted := {}
var _sel_paint := 2
var _drawer_nodes: Array = []
var _brushes: Array = []
var _phase := "paint" # "paint" | "alive" | "done"
var _alive_t := 0.0
var _menagerie: Node3D
var _done := false
var _plaque: Node3D
var _stage_home := Vector3(0, 0, -0.2)


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	if MarigoldSky.instance != null:
		MarigoldSky.instance.set_gentle_mode(true)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _backdrop != null:
		_backdrop.visible = not on
	if _stage == null:
		return
	if on:
		if not MarigoldHands.apply_anchor(_stage, "marigold_pinta"):
			MarigoldHands.place_on_table(_stage)
			MarigoldHands.save_anchor("marigold_pinta", _stage.global_transform)
	else:
		_stage.position = _stage_home
		_stage.rotation = Vector3.ZERO


func _process(delta: float) -> void:
	_t += delta
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)
	if _done:
		return
	MarigoldCharacterRig.update_all(delta, MarigoldCharacterRig.default_ctx(self))
	match _phase:
		"paint":
			_update_paint()
			_update_brushes(delta)
		"alive":
			_update_alive(delta)


func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.position = _stage_home
	add_child(_stage)
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.position = _stage_home
	add_child(_backdrop)
	MarigoldFX.make_point_light(_stage, Vector3(0, 2.4, -1.4), Color(1.0, 0.72, 0.35), 1.1, 7.0)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 3.2
	dm.bottom_radius = 3.2
	dm.height = 0.06
	dm.radial_segments = 48
	disc.mesh = dm
	disc.material_override = MarigoldFX.pbr(Color(0.10, 0.05, 0.10), 0.0, 0.9)
	disc.position = Vector3(0, -0.03, -1.4)
	_backdrop.add_child(disc)
	MarigoldModels.make_flower_field(_backdrop, 120, 3.0, 5150).position = Vector3(0, 0, -1.4)
	MarigoldFX.spawn_ambient_motes(_backdrop, Vector3(0, 1.6, -1.4), 3.0, 50)
	var title := MarigoldFX.make_label("Pinta Alebrijes", 84, C_GOLD)
	title.position = Vector3(0, 2.75, -2.2)
	_stage.add_child(title)
	var hint := MarigoldFX.make_label("Pinch a paint, then pinch the creature to color it", 44, C_CREAM)
	hint.position = Vector3(0, 2.35, -2.2)
	_stage.add_child(hint)
	_plaque = MarigoldPlaques.place_plaque(self,
		"Pinta Alebrijes",
		"Paint your own spirit animal - an original moth-jaguar alebrije. Choose colors from the glowing drawers, then touch each part of the creature to paint it. Finish every region and watch it come alive.",
		Vector3(-1.9, 1.5, -1.0), 1.9)
	_build_creature()
	_build_drawers()
	_build_brushes()
	_build_menagerie()


## Original moth-jaguar: round body, big moth wings, jaguar ears, tail,
## painted flank spots. Starts unpainted (soft gray); regions paintable.
func _build_creature() -> void:
	var root := Node3D.new()
	root.name = "Creature"
	root.position = Vector3(0, 1.05, -1.6)
	_stage.add_child(root)
	_creature = root
	var gray := Color(0.55, 0.52, 0.58)
	for r in REGIONS:
		var m := MarigoldFX.pbr(gray, 0.0, 0.6)
		_region_mats[r] = m
		_region_nodes[r] = []
		_painted[r] = false
	# Body.
	var body_mi := _part_sphere(0.28, 0.50, "Body")
	body_mi.scale = Vector3(1.0, 0.9, 1.25)
	root.add_child(body_mi)
	# Head pivot + head.
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.38, -0.32)
	root.add_child(head)
	var head_mi := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.18
	hm.height = 0.34
	head_mi.mesh = hm
	head_mi.material_override = _region_mats["Body"]
	head.add_child(head_mi)
	(_region_nodes["Body"] as Array).append(head_mi)
	# Moth wings on pivots.
	for sx in [-1.0, 1.0]:
		var wp := Node3D.new()
		wp.position = Vector3(sx * 0.20, 0.15, 0.10)
		root.add_child(wp)
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.55, 0.04, 0.40)
		w.mesh = wm
		w.material_override = _region_mats["Wings"]
		w.position = Vector3(sx * 0.32, 0.10, 0)
		w.rotation.z = sx * 0.25
		wp.add_child(w)
		(_region_nodes["Wings"] as Array).append(w)
	# Jaguar ears (cones).
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := CylinderMesh.new()
		em.top_radius = 0.0
		em.bottom_radius = 0.06
		em.height = 0.14
		em.radial_segments = 8
		e.mesh = em
		e.material_override = _region_mats["Ears"]
		e.position = Vector3(sx * 0.11, 0.16, 0.02)
		head.add_child(e)
		(_region_nodes["Ears"] as Array).append(e)
	# Tail.
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.09, 0.09, 0.45)
	tail.mesh = tm
	tail.material_override = _region_mats["Tail"]
	tail.position = Vector3(0, 0.10, 0.42)
	tail.rotation.x = -0.4
	root.add_child(tail)
	(_region_nodes["Tail"] as Array).append(tail)
	# Flank spots (painted as one region).
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for si in 8:
		var sp := MeshInstance3D.new()
		var spm := SphereMesh.new()
		spm.radius = 0.045
		spm.height = 0.06
		sp.mesh = spm
		sp.material_override = _region_mats["Spots"]
		var a := rng.randf() * TAU
		sp.position = Vector3(cos(a) * 0.26, 0.10 + rng.randf() * 0.25, sin(a) * 0.32)
		sp.scale = Vector3(1, 1, 0.5)
		root.add_child(sp)
		(_region_nodes["Spots"] as Array).append(sp)
	# Face kit on the head (eyes glow gray until it awakens).
	_rig = MarigoldCharacterRig.build_face(head, {
		"eye_positions": [Vector3(-0.07, 0.05, -0.14), Vector3(0.07, 0.05, -0.14)],
		"eye_radius": 0.035, "glow": Color(0.6, 0.6, 0.65), "glow_energy": 1.2,
		"face_pos": Vector3(0, 0.03, -0.05), "ring": false, "seed": 77})
	_rig.set_gaze_mode(MarigoldCharacterRig.LOOK_PLAYER)


func _part_sphere(r: float, h: float, region: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	mi.mesh = sm
	mi.material_override = _region_mats[region]
	(_region_nodes[region] as Array).append(mi)
	return mi


func _build_drawers() -> void:
	var stand := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.5, 0.08, 0.35)
	stand.mesh = sm
	stand.material_override = MarigoldFX.pbr(Color(0.40, 0.22, 0.10), 0.0, 0.7)
	stand.position = Vector3(0, 0.95, -0.7)
	_stage.add_child(stand)
	for i in PAINTS.size():
		var orb := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.09
		om.height = 0.16
		orb.mesh = om
		orb.material_override = MarigoldFX.glow((PAINTS[i] as Dictionary)["col"], 2.0)
		orb.position = Vector3(-0.54 + float(i) * 0.36, 1.12, -0.7)
		orb.set_meta("paint_idx", i)
		_stage.add_child(orb)
		_drawer_nodes.append(orb)
	var lab := MarigoldFX.make_label(PAINTS[_sel_paint]["name"], 40, C_GOLD)
	lab.name = "PaintLabel"
	lab.position = Vector3(0, 1.38, -0.7)
	_stage.add_child(lab)


func _build_brushes() -> void:
	# 3 floating brushes that bob beside the creature.
	for i in 3:
		var b := Node3D.new()
		b.name = "Brush%d" % i
		var stick := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.015
		sm.bottom_radius = 0.015
		sm.height = 0.35
		stick.mesh = sm
		stick.material_override = MarigoldFX.pbr(Color(0.55, 0.32, 0.14), 0.0, 0.6)
		b.add_child(stick)
		var tip := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.03
		tm.bottom_radius = 0.012
		tm.height = 0.08
		tip.mesh = tm
		tip.material_override = MarigoldFX.glow((PAINTS[(i + _sel_paint) % PAINTS.size()] as Dictionary)["col"], 1.6)
		tip.position = Vector3(0, -0.21, 0)
		b.add_child(tip)
		b.position = Vector3(0.85, 1.35 + float(i) * 0.18, -1.5)
		b.rotation.z = 0.4
		_stage.add_child(b)
		_brushes.append({"node": b, "tip": tip, "phase": float(i) * 2.1})


func _build_menagerie() -> void:
	# Spirit menagerie shelf: past painted friends return as small orbs.
	_menagerie = Node3D.new()
	_menagerie.name = "Menagerie"
	_menagerie.position = Vector3(0, 0.55, -2.5)
	_stage.add_child(_menagerie)
	var shelf := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(2.2, 0.07, 0.4)
	shelf.mesh = sm
	shelf.material_override = MarigoldFX.pbr(Color(0.42, 0.24, 0.12), 0.0, 0.7)
	_menagerie.add_child(shelf)
	var lab := MarigoldFX.make_label("Spirit Menagerie", 40, C_GOLD)
	lab.position = Vector3(0, 0.55, 0)
	_menagerie.add_child(lab)
	_refresh_menagerie()


func _refresh_menagerie() -> void:
	for c in _menagerie.get_children():
		if (c as Node).name.begins_with("Friend"):
			c.queue_free()
	var friends: Array = MarigoldSettings.get_value("pinta", "menagerie", [])
	for i in mini(friends.size(), 8):
		var f: Dictionary = friends[i]
		var orb := MeshInstance3D.new()
		orb.name = "Friend%d" % i
		var om := SphereMesh.new()
		om.radius = 0.09
		om.height = 0.16
		orb.mesh = om
		orb.material_override = MarigoldFX.glow(Color(f.get("r", 1.0), f.get("g", 0.7), f.get("b", 0.2)), 1.8)
		orb.position = Vector3(-0.9 + float(i) * 0.26, 0.16, 0)
		_menagerie.add_child(orb)


func _hand_point(hand: int) -> Vector3:
	return MarigoldHands.pointer_position(self, hand)


func _update_brushes(delta: float) -> void:
	for b in _brushes:
		var n: Node3D = b["node"]
		if n == null or not is_instance_valid(n):
			continue
		n.position.y += sin(_t * 2.0 + float(b["phase"])) * delta * 0.06
		n.rotation.y += delta * 0.4


func _update_paint() -> void:
	# Pick a paint from the drawers.
	for orb in _drawer_nodes:
		if orb == null or not is_instance_valid(orb):
			continue
		for hand in [MarigoldHands.HAND_RIGHT, MarigoldHands.HAND_LEFT]:
			if MarigoldHands.pinch_active(self, hand) \
					and (orb as Node3D).global_position.distance_to(_hand_point(hand)) < 0.25:
				var idx := int((orb as Node3D).get_meta("paint_idx"))
				if idx != _sel_paint:
					_sel_paint = idx
					MarigoldHaptics.click()
					var lab := _stage.get_node_or_null("PaintLabel") as Label3D
					if lab != null:
						lab.text = String((PAINTS[idx] as Dictionary)["name"])
				break
	# Paint a region by pinching near one of its meshes.
	for hand in [MarigoldHands.HAND_RIGHT, MarigoldHands.HAND_LEFT]:
		if not MarigoldHands.pinch_active(self, hand):
			continue
		var pp := _hand_point(hand)
		for r in REGIONS:
			if bool(_painted[r]):
				continue
			for mi in _region_nodes[r]:
				if (mi as Node3D).global_position.distance_to(pp) < 0.30:
					_paint_region(r)
					break
			if bool(_painted[r]):
				break


func _paint_region(r: String) -> void:
	_painted[r] = true
	var col: Color = (PAINTS[_sel_paint] as Dictionary)["col"]
	var m: StandardMaterial3D = _region_mats[r]
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.9
	MarigoldHaptics.texture_tick()
	MarigoldFX.spawn_sparks(_stage, _creature.global_position + Vector3(0, 0.3, 0), col, 12)
	var left := 0
	for k in REGIONS:
		if not bool(_painted[k]):
			left += 1
	if left == 0:
		_awaken()
	else:
		var hint := _stage.get_node_or_null("PaintLabel") as Label3D
		if hint != null:
			hint.text = "%d regions to go" % left


func _awaken() -> void:
	_phase = "alive"
	_alive_t = 0.0
	# It comes alive: gold eyes, JOY, it looks at you.
	if _rig != null:
		_rig.set_glow_color(C_GOLD)
		_rig.set_expression("JOY", 0.5)
		_rig.set_singing(true)
	MarigoldHaptics.fanfare()
	MarigoldFX.spawn_confetti(_stage, _creature.global_position + Vector3(0, 0.5, 0), 50)
	if MarigoldState.music != null and MarigoldState.music.has_method("play_stinger"):
		MarigoldState.music.play_stinger("greet", -6.0)
	MarigoldPhotos.note_moment("paint_alive")
	# Remember this friend's colors in the menagerie.
	var friends: Array = MarigoldSettings.get_value("pinta", "menagerie", [])
	var cols := []
	for r in REGIONS:
		var c: Color = (_region_mats[r] as StandardMaterial3D).albedo_color
		cols.append(c)
	var avg := Color(0, 0, 0)
	for c in cols:
		avg += c
	avg /= float(maxi(cols.size(), 1))
	friends.append({"r": avg.r, "g": avg.g, "b": avg.b})
	while friends.size() > 8:
		friends.pop_front()
	MarigoldSettings.set_value("pinta", "menagerie", friends)


func _update_alive(delta: float) -> void:
	_alive_t += delta
	# Happy hop, then it flies to the menagerie shelf.
	if _alive_t < 2.5:
		_creature.position.y = 1.05 + absf(sin(_alive_t * 6.0)) * 0.25
		_creature.rotation.y += delta * 3.0
	elif _phase == "alive":
		_phase = "done"
		var target: Vector3 = _menagerie.global_position + Vector3(0, 0.35, 0)
		var tw := create_tween()
		tw.tween_property(_creature, "global_position", target, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(_creature, "scale", Vector3.ONE * 0.35, 1.6)
		tw.tween_callback(_finish_alive)


func _finish_alive() -> void:
	if _done:
		return
	_done = true
	if _rig != null:
		_rig.detach()
	_refresh_menagerie()
	MarigoldHaptics.confirm()
	await get_tree().create_timer(1.2).timeout
	chapter_complete.emit()
