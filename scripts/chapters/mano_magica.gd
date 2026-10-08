## mano_magica.gd - MARIGOLD experience: Mano Magica (v0.5.0).
## A guided hand-tracking tour through six gestures: pinch a marigold bud
## until it blooms, grab a light orb and carry it to the stone bowl, throw
## petals at the paper target, sculpt clay by pinching and moving, conduct
## chimes with hand sweeps, and pet an alebrije spirit guide.
## Each station lasts ~10-16 s and advances early on success.
## Input: real hand pinch, controller trigger, or desktop mouse
## (MarigoldHands fallbacks) - fully playable offline, headless-safe.
## No class_name (experience contract). Signal + setup/apply_mode contract.
extends Node3D

signal chapter_complete

enum St { WELCOME, PINCH, GRAB, THROW, SCULPT, CONDUCT, PET, FINALE }

const PHASES := [
	{"st": St.WELCOME, "title": "Mano Magica", "hint": "A tour of your own hands - follow the light", "dur": 5.0},
	{"st": St.PINCH, "title": "1 · Pellizca - Pinch", "hint": "PINCH near the bud to make the marigold bloom", "dur": 14.0},
	{"st": St.GRAB, "title": "2 · Agarra - Grab", "hint": "PINCH and HOLD the light orb, carry it to the stone bowl", "dur": 14.0},
	{"st": St.THROW, "title": "3 · Lanza - Throw", "hint": "Grab a petal and THROW it at the paper ring (2 hits!)", "dur": 16.0},
	{"st": St.SCULPT, "title": "4 · Esculpe - Sculpt", "hint": "PINCH-HOLD near the clay and MOVE to shape it", "dur": 16.0},
	{"st": St.CONDUCT, "title": "5 · Dirige - Conduct", "hint": "Sweep your hand - up for high bells, down for low", "dur": 14.0},
	{"st": St.PET, "title": "6 · Acaricia - Pet", "hint": "Gently stroke the alebrije (slow hands!)", "dur": 14.0},
	{"st": St.FINALE, "title": "¡Bravo!", "hint": "Your hands are magic", "dur": 5.0},
]

const C_ORANGE := Color(1.0, 0.62, 0.12)
const C_GOLD := Color(1.0, 0.80, 0.30)
const C_CREAM := Color(1.0, 0.93, 0.82)
const C_PINK := Color(1.0, 0.42, 0.62)

var _ar_mode := false
var _t := 0.0
var _stage: Node3D
var _backdrop: Node3D
var _phase := -1
var _phase_t := 0.0
var _advance_at := -1.0
var _done := false
var _title_label: Label3D
var _hint_label: Label3D
var _prog_label: Label3D
var _plaque: Node3D

# Station props.
var _bud_root: Node3D
var _bud_mat: StandardMaterial3D
var _bloom := 0.0
var _orb: MeshInstance3D
var _orb_home := Vector3(0.55, 1.25, -1.6)
var _bowl_pos := Vector3(-0.55, 1.05, -1.6)
var _orb_held := false
var _orb_done := false
var _petals: Array = [] # {"node": Node3D, "flying": bool, "vel": Vector3}
var _petal_home := Vector3(0, 1.15, -1.7)
var _held_petal := -1
var _target_pos := Vector3(0, 1.7, -2.6)
var _target_ring: MeshInstance3D
var _hits := 0
var _clay: MeshInstance3D
var _clay_home := Vector3(0, 1.05, -1.5)
var _clay_base := Vector3(0.22, 0.18, 0.22)
var _sculpt_acc := 0.0
var _tick_cd := 0.0
var _conduct_count := 0
var _cond_prev_y := 0.0
var _cond_armed := true
var _sweep_cd := 0.0
var _alebrije: Node3D
var _alebrije_home := Vector3(0, 0.55, -1.9)
var _pet_acc := 0.0
var _purr_cd := 0.0
var _stage_home := Vector3(0, 0, -0.2)


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	if MarigoldSky.instance != null:
		MarigoldSky.instance.set_gentle_mode(true)
	_start_phase(0)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _backdrop != null:
		_backdrop.visible = not on
	if _stage == null:
		return
	if on:
		var key := "marigold_mano_magica"
		if not MarigoldHands.apply_anchor(_stage, key):
			MarigoldHands.place_on_table(_stage)
			MarigoldHands.save_anchor(key, _stage.global_transform)
	else:
		_stage.position = _stage_home
		_stage.rotation = Vector3.ZERO


func _music():
	if not is_inside_tree():
		return null
	var st := get_tree().root.get_node_or_null("MarigoldState")
	if st == null:
		return null
	return st.get("music")


func _process(delta: float) -> void:
	_t += delta
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)
	if _done:
		return
	_phase_t += delta
	_update_hand_glow(delta)
	match _phase:
		St.WELCOME, St.FINALE:
			pass
		St.PINCH:
			_update_pinch(delta)
		St.GRAB:
			_update_grab(delta)
		St.THROW:
			_update_throw(delta)
		St.SCULPT:
			_update_sculpt(delta)
		St.CONDUCT:
			_update_conduct(delta)
		St.PET:
			_update_pet(delta)
	_update_phase_flow(delta)


## ---------------- phase flow ----------------

func _start_phase(idx: int) -> void:
	_phase = idx
	_phase_t = 0.0
	_advance_at = -1.0
	var p: Dictionary = PHASES[idx]
	_title_label.text = String(p["title"])
	_hint_label.text = String(p["hint"])
	_prog_label.text = ""
	_show_station(idx)
	MarigoldHaptics.click()


func _succeed(msg: String) -> void:
	_prog_label.text = msg + "  ¡Muy bien!"
	MarigoldHaptics.fanfare()
	var m = _music()
	if m != null and m.has_method("chime"):
		m.call("chime", 84, 0.7)
	_advance_at = _t + 1.6


func _update_phase_flow(delta: float) -> void:
	if _phase < 0:
		return
	if _advance_at > 0.0 and _t >= _advance_at:
		_next_phase()
		return
	var dur: float = float(PHASES[_phase]["dur"])
	if _phase_t >= dur:
		_next_phase()


func _next_phase() -> void:
	MarigoldFX.scatter_petals(self, _stage_home + Vector3(0, 1.6, -1.4), 20)
	if _phase + 1 >= PHASES.size():
		_finish()
		return
	_hide_station(_phase)
	_start_phase(_phase + 1)


func _finish() -> void:
	if _done:
		return
	_done = true
	MarigoldFX.petal_ceiling_fall(self, _stage_home + Vector3(0, 0, -1.4), 2.5, 120, 20.0, 3.2)
	MarigoldFX.spawn_confetti(self, _stage_home + Vector3(0, 2.0, -1.4), 80)
	MarigoldHaptics.fanfare()
	await get_tree().create_timer(3.6).timeout
	chapter_complete.emit()

## ---------------- world ----------------

func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.position = _stage_home
	add_child(_stage)
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.position = _stage_home
	add_child(_backdrop)
	# Warm stage light (single omni - light budget is safe for this scene).
	MarigoldFX.make_point_light(_stage, Vector3(0, 2.4, -1.4), Color(1.0, 0.72, 0.35), 1.1, 7.0)
	# Ground disc + flower ring backdrop.
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
	MarigoldModels.make_flower_field(_backdrop, 120, 3.0, 4242).position = Vector3(0, 0, -1.4)
	MarigoldFX.spawn_ambient_motes(_backdrop, Vector3(0, 1.6, -1.4), 3.0, 50)
	MarigoldAmbient.add_butterflies(_backdrop, Vector3(0, 1.7, -1.4), 6, 3.0)
	# Instruction labels.
	_title_label = MarigoldFX.make_label("", 84, C_ORANGE)
	_title_label.position = Vector3(0, 2.75, -2.2)
	_stage.add_child(_title_label)
	_hint_label = MarigoldFX.make_label("", 48, C_CREAM)
	_hint_label.position = Vector3(0, 2.35, -2.2)
	_stage.add_child(_hint_label)
	_prog_label = MarigoldFX.make_label("", 52, C_GOLD)
	_prog_label.position = Vector3(0, 2.0, -2.2)
	_stage.add_child(_prog_label)
	_plaque = MarigoldPlaques.place_plaque(self,
		"Mano Magica",
		"A guided tour of your own hands: pinch a bud until it blooms, carry a light orb, throw petals, sculpt clay, conduct bells, and pet an alebrije spirit. Pinch, trigger, or mouse - every gesture works.",
		Vector3(-1.9, 1.5, -1.0), 1.9)
	_build_stations()


func _build_stations() -> void:
	# -- PINCH: marigold bud on a small stem.
	_bud_root = Node3D.new()
	_bud_root.position = Vector3(0, 1.25, -1.6)
	_stage.add_child(_bud_root)
	var stem := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.012
	sm.bottom_radius = 0.016
	sm.height = 0.35
	stem.mesh = sm
	stem.material_override = MarigoldFX.pbr(Color(0.15, 0.35, 0.12), 0.0, 0.7)
	stem.position = Vector3(0, -0.20, 0)
	_bud_root.add_child(stem)
	_bud_mat = MarigoldFX.glow(Color(0.35, 0.55, 0.12), 1.2)
	var bud := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.075
	bm.height = 0.15
	bud.mesh = bm
	bud.material_override = _bud_mat
	_bud_root.add_child(bud)
	# -- GRAB: light orb + stone bowl.
	_orb = MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.075
	om.height = 0.15
	om.radial_segments = 16
	om.rings = 8
	_orb.mesh = om
	_orb.material_override = MarigoldFX.glow(C_GOLD, 2.6)
	_orb.position = _orb_home
	_stage.add_child(_orb)
	var bowl := MeshInstance3D.new()
	var bwm := CylinderMesh.new()
	bwm.top_radius = 0.16
	bwm.bottom_radius = 0.10
	bwm.height = 0.12
	bowl.mesh = bwm
	bowl.material_override = MarigoldFX.pbr(Color(0.45, 0.42, 0.48), 0.0, 0.7)
	bowl.position = _bowl_pos
	_stage.add_child(bowl)
	var bowl_glow := MeshInstance3D.new()
	var bgm := TorusMesh.new()
	bgm.inner_radius = 0.13
	bgm.outer_radius = 0.17
	bgm.rings = 20
	bgm.ring_segments = 8
	bowl_glow.mesh = bgm
	bowl_glow.material_override = MarigoldFX.glow(C_GOLD, 1.8)
	bowl_glow.position = _bowl_pos + Vector3(0, 0.07, 0)
	bowl_glow.rotation_degrees.x = 90.0
	_stage.add_child(bowl_glow)
	# -- THROW: petal pool + paper target ring.
	for i in 6:
		var petal := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.045
		pm.height = 0.03
		petal.mesh = pm
		petal.material_override = MarigoldFX.glow(C_ORANGE, 1.6)
		petal.position = _petal_home + Vector3((i % 3) * 0.09 - 0.09, (i / 3) * 0.05, 0)
		_stage.add_child(petal)
		_petals.append({"node": petal, "flying": false, "vel": Vector3.ZERO})
	_target_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.20
	tm.outer_radius = 0.27
	tm.rings = 24
	tm.ring_segments = 10
	_target_ring.mesh = tm
	_target_ring.material_override = MarigoldFX.glow(C_PINK, 2.0)
	_target_ring.position = _target_pos
	_stage.add_child(_target_ring)
	# -- SCULPT: clay blob on a pedestal.
	var ped := MeshInstance3D.new()
	var pdm := CylinderMesh.new()
	pdm.top_radius = 0.20
	pdm.bottom_radius = 0.24
	pdm.height = 0.85
	ped.mesh = pdm
	ped.material_override = MarigoldFX.pbr(Color(0.38, 0.24, 0.16), 0.0, 0.8)
	ped.position = _clay_home + Vector3(0, -0.55, 0)
	_stage.add_child(ped)
	_clay = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.20
	cm.height = 0.40
	cm.radial_segments = 24
	cm.rings = 12
	_clay.mesh = cm
	_clay.material_override = MarigoldFX.pbr(Color(0.72, 0.42, 0.26), 0.0, 0.55)
	_clay.position = _clay_home
	_stage.add_child(_clay)
	# -- PET: alebrije spirit guide (in-house Blender original).
	_alebrije = MarigoldModels.blender_model(MarigoldModels.ALEBRIJES, "alebrije_deer")
	if _alebrije == null:
		# Fallback: glowing spirit orb creature.
		_alebrije = Node3D.new()
		var fb := MeshInstance3D.new()
		var fbm := SphereMesh.new()
		fbm.radius = 0.22
		fbm.height = 0.44
		fb.mesh = fbm
		fb.material_override = MarigoldFX.glow(Color(0.3, 0.9, 0.7), 1.8)
		_alebrije.add_child(fb)
	_alebrije.position = _alebrije_home
	_stage.add_child(_alebrije)
	_hide_all_stations()


func _station_nodes(st: int) -> Array:
	match st:
		St.PINCH:
			return [_bud_root]
		St.GRAB:
			return [_orb]
		St.THROW:
			var arr: Array = [_target_ring]
			for p in _petals:
				arr.append(p["node"])
			return arr
		St.SCULPT:
			return [_clay]
		St.PET:
			return [_alebrije]
	return []


func _hide_all_stations() -> void:
	for st in [St.PINCH, St.GRAB, St.THROW, St.SCULPT, St.PET]:
		for n in _station_nodes(st):
			(n as Node3D).visible = false
	_target_ring.visible = false


func _show_station(idx: int) -> void:
	var st: int = int(PHASES[idx]["st"])
	for n in _station_nodes(st):
		(n as Node3D).visible = true
	# Reset per-station state.
	match st:
		St.PINCH:
			_bloom = 0.0
			_bud_mat.albedo_color = Color(0.35, 0.55, 0.12)
			_bud_root.scale = Vector3.ONE
		St.GRAB:
			_orb.position = _orb_home
			_orb_held = false
			_orb_done = false
		St.THROW:
			_hits = 0
			_held_petal = -1
			for i in _petals.size():
				var p: Dictionary = _petals[i]
				p["flying"] = false
				p["vel"] = Vector3.ZERO
				(p["node"] as Node3D).position = _petal_home + Vector3((i % 3) * 0.09 - 0.09, (i / 3) * 0.05, 0)
				(p["node"] as Node3D).visible = true
		St.SCULPT:
			_sculpt_acc = 0.0
			_clay.scale = Vector3(_clay_base.x / 0.2, _clay_base.y / 0.2, _clay_base.z / 0.2)
		St.CONDUCT:
			_conduct_count = 0
			_cond_armed = true
		St.PET:
			_pet_acc = 0.0


func _hide_station(idx: int) -> void:
	var st: int = int(PHASES[idx]["st"])
	for n in _station_nodes(st):
		(n as Node3D).visible = false

## ---------------- gestures ----------------

func _pointer(hand: int = MarigoldHands.HAND_RIGHT) -> Vector3:
	return MarigoldHands.pointer_position(self, hand)


func _either_pinch() -> bool:
	return MarigoldHands.pinch_active(self, MarigoldHands.HAND_RIGHT) \
		or MarigoldHands.pinch_active(self, MarigoldHands.HAND_LEFT)


func _update_hand_glow(delta: float) -> void:
	# Bud pulses to invite the pinch; the active target always breathes.
	var beat := sin(_t * 3.0) * 0.5 + 0.5
	if _phase == St.PINCH and _bloom < 1.0:
		_bud_root.scale = Vector3.ONE * (1.0 + beat * 0.12)
	if is_instance_valid(_target_ring) and _target_ring.visible:
		_target_ring.rotation.z += delta * 0.8
		var m := _target_ring.material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = 1.6 + beat * 1.2


## 1. PINCH: pinch near the bud -> it blooms.
func _update_pinch(_delta: float) -> void:
	if _bloom >= 1.0:
		return
	var bud_pos: Vector3 = _bud_root.global_position
	var near := false
	for hand in [MarigoldHands.HAND_RIGHT, MarigoldHands.HAND_LEFT]:
		if MarigoldHands.pinch_active(self, hand) \
				and _pointer(hand).distance_to(bud_pos) < 0.30:
			near = true
			break
	if near:
		var was := _bloom
		_bloom = minf(1.0, _bloom + _delta / 2.2)
		_bud_mat.albedo_color = Color(0.35, 0.55, 0.12).lerp(C_ORANGE, _bloom)
		_bud_mat.emission_energy_multiplier = 1.2 + _bloom * 1.6
		_bud_root.scale = Vector3.ONE * (1.0 + _bloom * 0.7)
		if int(was * 5.0) != int(_bloom * 5.0):
			MarigoldHaptics.click()
			var m = _music()
			if m != null and m.has_method("pluck"):
				m.call("pluck", 72 + int(_bloom * 12.0), 0.5)
		if _bloom >= 1.0:
			MarigoldFX.spawn_sparks(_stage, bud_pos, C_ORANGE, 26)
			_succeed("The marigold blooms!")


## 2. GRAB: pinch-hold the orb, carry it to the bowl.
func _update_grab(_delta: float) -> void:
	if _orb_done:
		return
	var gs := MarigoldHands.grab_state(self, MarigoldHands.HAND_RIGHT)
	if not _orb_held and bool(gs["active"]) \
			and (gs["grab_point"] as Vector3).distance_to(_orb.global_position) < 0.25:
		_orb_held = true
		MarigoldHaptics.thump()
	if _orb_held:
		if bool(gs["active"]):
			_orb.global_position = gs["grab_point"] as Vector3
			_orb.position.y = maxf(_orb.position.y, 0.25)
		else:
			_orb_held = false
			if _orb.global_position.distance_to(_stage.to_global(_bowl_pos)) < 0.35:
				_orb_done = true
				MarigoldFX.spawn_sparks(_stage, _stage.to_global(_bowl_pos), C_GOLD, 30)
				_succeed("Light delivered!")
			else:
				MarigoldHaptics.deny()


## 3. THROW: grab petals, fling them at the paper ring.
func _update_throw(delta: float) -> void:
	# Pick up a petal.
	if _held_petal < 0 and MarigoldHands.pinch_just_pressed(self, MarigoldHands.HAND_RIGHT):
		var pp := _pointer()
		for i in _petals.size():
			var p: Dictionary = _petals[i]
			if bool(p["flying"]):
				continue
			if ((p["node"] as Node3D).global_position.distance_to(pp) < 0.25):
				_held_petal = i
				MarigoldHaptics.click()
				break
	# Carry the held petal.
	if _held_petal >= 0:
		var p: Dictionary = _petals[_held_petal]
		if MarigoldHands.pinch_active(self, MarigoldHands.HAND_RIGHT):
			(p["node"] as Node3D).global_position = _pointer()
		else:
			# Release: fling with the hand's velocity.
			p["flying"] = true
			var v: Vector3 = MarigoldHands.throw_release_velocity(self, MarigoldHands.HAND_RIGHT)
			p["vel"] = v * 1.4 + Vector3(0, 1.2, 0)
			_held_petal = -1
			MarigoldHaptics.impact(clampf(v.length() / 3.0, 0.2, 1.0))
	# Integrate flying petals; ring hit test.
	for i in _petals.size():
		var p: Dictionary = _petals[i]
		if not bool(p["flying"]):
			continue
		var n: Node3D = p["node"]
		var v: Vector3 = p["vel"]
		v.y -= 4.5 * delta
		p["vel"] = v
		n.global_position += v * delta
		if n.global_position.distance_to(_target_pos) < 0.30:
			p["flying"] = false
			n.visible = false
			_hits += 1
			MarigoldFX.spawn_sparks(_stage, _target_pos, C_PINK, 24)
			MarigoldHaptics.thump()
			var m = _music()
			if m != null and m.has_method("chime"):
				m.call("chime", 76 + _hits * 4, 0.6)
			_prog_label.text = "%d / 2 hits" % _hits
			if _hits >= 2:
				_succeed("Bullseye!")
				return
		elif n.global_position.y < 0.02 or n.global_position.distance_to(_stage_home) > 8.0:
			# Missed: respawn at the basket.
			p["flying"] = false
			n.position = _petal_home + Vector3((i % 3) * 0.09 - 0.09, (i / 3) * 0.05, 0)


## 4. SCULPT: pinch-hold near the clay and move to shape it.
func _update_sculpt(delta: float) -> void:
	var gs := MarigoldHands.grab_state(self, MarigoldHands.HAND_RIGHT)
	var near := false
	if bool(gs["active"]):
		var gp: Vector3 = gs["grab_point"]
		near = gp.distance_to(_clay.global_position) < 0.40
	if near:
		_sculpt_acc += delta
		var local: Vector3 = _clay.to_local(gs["grab_point"] as Vector3)
		# Squash the clay along the push direction; bulge the others.
		var target := Vector3(
			clampf(1.0 - local.x * 1.4, 0.55, 1.5),
			clampf(1.0 - local.y * 1.4, 0.55, 1.5),
			clampf(1.0 - local.z * 1.4, 0.55, 1.5))
		_clay.scale = _clay.scale.lerp(target, clampf(6.0 * delta, 0.0, 1.0))
		_clay.rotation.y += delta * MarigoldHands.grab_speed(self, MarigoldHands.HAND_RIGHT) * 0.4
		_tick_cd -= delta
		var spd := MarigoldHands.grab_speed(self, MarigoldHands.HAND_RIGHT)
		if spd > 0.25 and _tick_cd <= 0.0:
			_tick_cd = 0.18
			MarigoldHaptics.texture_tick()
			var m = _music()
			if m != null and m.has_method("pluck"):
				m.call("pluck", 52 + int(spd * 8.0), 0.35, 0.5)
		_prog_label.text = "Shaping... %d%%" % int(clampf(_sculpt_acc / 6.0, 0.0, 1.0) * 100.0)
		if _sculpt_acc >= 6.0:
			MarigoldFX.spawn_sparks(_stage, _clay.global_position, Color(0.72, 0.42, 0.26), 26)
			_succeed("A fine vessel!")


## 5. CONDUCT: hand sweeps play bells - height sets the pitch.
func _update_conduct(_delta: float) -> void:
	var hp := _pointer()
	var pinching := _either_pinch()
	_sweep_cd -= _delta
	if pinching:
		var dy := hp.y - _cond_prev_y
		if _cond_armed and dy > 0.09:
			# Upward flick: bell, pitch from hand height.
			_cond_armed = false
			_conduct_count += 1
			var note := 60 + int(clampf((hp.y - 0.8) / 1.6, 0.0, 1.0) * 24.0)
			var m = _music()
			if m != null and m.has_method("chime"):
				m.call("chime", note, 0.65)
			MarigoldHaptics.click()
			MarigoldFX.spawn_sparks(_stage, hp, Color(1.0, 0.85, 0.45), 8)
			_prog_label.text = "%d bells" % _conduct_count
			if _conduct_count >= 5:
				_succeed("The bells sing!")
				return
		elif dy < -0.02:
			_cond_armed = true
		# Fast horizontal sweep: flourish.
		var spd := MarigoldHands.grab_speed(self, MarigoldHands.HAND_RIGHT)
		if spd > 2.2 and _sweep_cd <= 0.0:
			_sweep_cd = 1.2
			MarigoldFX.spawn_confetti(_stage, hp, 24)
			MarigoldHaptics.pulse(0.7, 0.25)
	_cond_prev_y = hp.y


## 6. PET: slow gentle strokes on the alebrije.
func _update_pet(delta: float) -> void:
	var center: Vector3 = _alebrije.global_position + Vector3(0, 0.25, 0)
	var touched := false
	for hand in [MarigoldHands.HAND_RIGHT, MarigoldHands.HAND_LEFT]:
		var pp := _pointer(hand)
		if pp.distance_to(center) < 0.38:
			touched = true
			break
	if touched:
		var spd: float = maxf(
			MarigoldHands.grab_speed(self, MarigoldHands.HAND_RIGHT),
			MarigoldHands.grab_speed(self, MarigoldHands.HAND_LEFT))
		if spd < 0.9:
			_pet_acc += delta
			# Happy wiggle.
			_alebrije.rotation.z = sin(_t * 10.0) * 0.06
			_alebrije.position.y = _alebrije_home.y + absf(sin(_t * 5.0)) * 0.04
			_purr_cd -= delta
			if _purr_cd <= 0.0:
				_purr_cd = 1.6
				var m = _music()
				if m != null and m.has_method("pluck"):
					m.call("pluck", 45, 0.45, 1.6, 0.998)
				MarigoldHaptics.pulse(0.35, 0.3)
				MarigoldFX.spawn_sparks(_stage, center, C_PINK, 6)
			_prog_label.text = "Purring... %d%%" % int(clampf(_pet_acc / 5.0, 0.0, 1.0) * 100.0)
			if _pet_acc >= 5.0:
				MarigoldFX.spawn_confetti(_stage, center, 30)
				_succeed("New spirit friend!")
	else:
		_alebrije.rotation.z = lerpf(_alebrije.rotation.z, 0.0, clampf(4.0 * delta, 0.0, 1.0))
