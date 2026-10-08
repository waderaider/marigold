## espejo.gd - MARIGOLD experience: Gran Baile - Espejo (v0.5.0).
## Mirror dance: three calavera dancers mirror the PLAYER's real body moves.
## Body tracking: XRBodyTracker via XRServer TRACKER_BODY (the Meta
## body_tracking extension, enabled in project.godot). Joints are read with
## get_joint_transform() and smoothed hard against noise (exp filter +
## deadzone + clamps). Graceful fallbacks: hands-only (hand trackers) ->
## auto-dance (beat-synced, like the Ofrenda Viva troupe).
## The skeleton dancers have no rig, so mirroring is whole-body: lean,
## crouch, sway, turn, plus per-dancer hand-glow orbs that track the
## player's real hands - the visible "that's me" feedback.
## Fully playable offline; headless-safe; no new lights (candle-grade only).
## No class_name (experience contract).
extends Node3D

signal chapter_complete

const DANCE_TIME := 75.0
const INTRO_TIME := 6.0
const FINALE_TIME := 6.0

const J_HEAD := 6
const J_HIPS := 1
const J_HAND_L := 22
const J_HAND_R := 49

const C_ORANGE := Color(1.0, 0.62, 0.12)
const C_GOLD := Color(1.0, 0.80, 0.30)
const C_CREAM := Color(1.0, 0.93, 0.82)
const C_PINK := Color(1.0, 0.42, 0.62)

var _ar_mode := false
var _t := 0.0
var _stage: Node3D
var _backdrop: Node3D
var _dancers: Array = [] # {"root","body","phase","style","base_y","base_rot","orbs":[l,r],"name"...}
var _mode := "auto" # "body" | "hands" | "auto"
var _body: XRBodyTracker = null
var _hand_l: XRPositionalTracker = null
var _hand_r: XRPositionalTracker = null
var _mode_label: Label3D
var _hint_label: Label3D
var _energy_label: Label3D
var _plaque: Node3D
# Smoothed mirror pose.
var _lean := Vector2.ZERO
var _crouch := 0.0
var _turn := 0.0
var _hand_h := 0.0
var _hand_spread := 0.0
var _energy := 0.0
var _prev_hips := Vector3.ZERO
var _have_prev := false
var _confetti_cd := 0.0
var _phase := "intro"
var _phase_t := 0.0
var _done := false
var _recheck_cd := 5.0
var _stage_home := Vector3(0, 0, -0.2)
# v0.6.0: espejo wink + head-tilt echo.
var _wink_cd := 0.0
var _head_roll := 0.0


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	if MarigoldSky.instance != null:
		MarigoldSky.instance.set_gentle_mode(true)
	_find_trackers()


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _backdrop != null:
		_backdrop.visible = not on
	if _stage == null:
		return
	if on:
		var key := "marigold_espejo"
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


func _beat_phase() -> float:
	var m = _music()
	if m != null and m.has_method("get_beat_phase"):
		return float(m.call("get_beat_phase"))
	return -1.0


func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.position = _stage_home
	add_child(_stage)
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.position = _stage_home
	add_child(_backdrop)
	# Warm candle-grade light (single omni - light budget safe).
	MarigoldFX.make_point_light(_stage, Vector3(0, 2.6, -2.2), Color(1.0, 0.62, 0.25), 1.2, 9.0)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 4.2
	dm.bottom_radius = 4.2
	dm.height = 0.06
	dm.radial_segments = 48
	disc.mesh = dm
	disc.material_override = MarigoldFX.pbr(Color(0.12, 0.05, 0.10), 0.0, 0.9)
	disc.position = Vector3(0, -0.03, -2.2)
	_backdrop.add_child(disc)
	MarigoldModels.make_flower_field(_backdrop, 140, 4.0, 777).position = Vector3(0, 0, -2.2)
	MarigoldFX.spawn_ambient_motes(_backdrop, Vector3(0, 1.6, -2.2), 4.0, 60)
	MarigoldAmbient.add_butterflies(_backdrop, Vector3(0, 1.7, -2.2), 6, 4.0)
	# Labels.
	_hint_label = MarigoldFX.make_label("Dance - your skeleton mirrors your real moves", 52, C_CREAM)
	_hint_label.position = Vector3(0, 2.9, -3.4)
	_stage.add_child(_hint_label)
	_mode_label = MarigoldFX.make_label("", 44, C_GOLD)
	_mode_label.position = Vector3(0, 2.55, -3.4)
	_stage.add_child(_mode_label)
	_energy_label = MarigoldFX.make_label("", 48, C_PINK)
	_energy_label.position = Vector3(0, 2.2, -3.4)
	_stage.add_child(_energy_label)
	_plaque = MarigoldPlaques.place_plaque(self,
		"Gran Baile: Espejo",
		"The mirror dance. Three calavera dancers copy YOUR real body - lean, crouch, sway and wave, and they follow. Needs body tracking; without it they dance to the beat and your hands still lead.",
		Vector3(-2.3, 1.5, -1.2), 2.0)
	# Dancer troupe: arc facing the player.
	var names := ["La Catrina", "El Charro", "La Dama"]
	var accents := [C_PINK, C_GOLD, Color(0.4, 0.85, 1.0)]
	for i in 3:
		var d := MarigoldCalavera.make_dancer(accents[i], 1.0)
		var root: Node3D = d["root"]
		var x := (float(i) - 1.0) * 1.5
		root.position = Vector3(x, 0, -2.6 - absf(x) * 0.35)
		_stage.add_child(root)
		d["phase"] = float(i) * 2.1
		d["style"] = i
		d["base_y"] = 0.0
		d["base_rot"] = 0.0
		d["energy"] = 1.0
		d["spin_dir"] = 1.0 if i % 2 == 0 else -1.0
		# Hand-glow orbs: the visible "your hands" mirror.
		var orbs := []
		for side in [-1.0, 1.0]:
			var orb := MeshInstance3D.new()
			var om := SphereMesh.new()
			om.radius = 0.07
			om.height = 0.14
			orb.mesh = om
			orb.material_override = MarigoldFX.glow(accents[i], 2.4)
			_stage.add_child(orb)
			orbs.append(orb)
		d["orbs"] = orbs
		var lab := MarigoldFX.make_label(names[i], 52, accents[i])
		lab.position = root.position + Vector3(0, 2.15, 0)
		_stage.add_child(lab)
		MarigoldCalavera.face_player(root, Vector3(0, 1.5, 0.6))
		_dancers.append(d)


## ---------------- tracker discovery ----------------

func _find_trackers() -> void:
	if not MarigoldHands.is_xr_active():
		_set_mode("auto", "Auto-dance - no headset tracking")
		return
	# Body tracker first.
	var bodies := XRServer.get_trackers(XRServer.TRACKER_BODY)
	for key in bodies:
		var tr: XRPositionalTracker = bodies[key]
		if tr is XRBodyTracker and (tr as XRBodyTracker).has_tracking_data:
			_body = tr as XRBodyTracker
			break
	# Hand trackers for the hands-only fallback.
	var hands := XRServer.get_trackers(XRServer.TRACKER_HAND)
	for key in hands:
		var tr: XRPositionalTracker = hands[key]
		if tr.hand == XRPositionalTracker.TRACKER_HAND_LEFT:
			_hand_l = tr
		elif tr.hand == XRPositionalTracker.TRACKER_HAND_RIGHT:
			_hand_r = tr
	_recheck_mode()


func _recheck_mode() -> void:
	if _body != null and is_instance_valid(_body) and _body.has_tracking_data:
		_set_mode("body", "Body tracked - they mirror you")
	elif _hand_l != null or _hand_r != null:
		_set_mode("hands", "Hands only - wave to lead the dance")
	else:
		_set_mode("auto", "Auto-dance - moving to the beat")


func _set_mode(mode: String, label: String) -> void:
	_mode = mode
	if _mode_label != null and is_instance_valid(_mode_label):
		_mode_label.text = label

## ---------------- per-frame ----------------

func _process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)
	if _done:
		return
	# Trackers can appear late (permissions) - recheck on a cooldown.
	_recheck_cd -= delta
	if _recheck_cd <= 0.0 and _mode == "auto":
		_recheck_cd = 5.0
		_find_trackers()
	_read_pose(delta)
	var beat := _beat_phase()
	match _phase:
		"intro":
			if _phase_t >= INTRO_TIME:
				_phase = "dance"
				_phase_t = 0.0
				_hint_label.text = "¡Baila! Lean, crouch, sway - they follow you"
				MarigoldHaptics.fanfare()
		"dance":
			_update_energy(delta)
			if _phase_t >= DANCE_TIME:
				_phase = "finale"
				_phase_t = 0.0
				_hint_label.text = "¡Bravo! Final bow"
				for d in _dancers:
					MarigoldCalavera.face_player(d["root"], Vector3(0, 1.5, 0.6))
		"finale":
			if _phase_t < 2.0:
				for d in _dancers:
					MarigoldCalavera.set_bow(d, _phase_t / 2.0)
			elif _phase_t >= FINALE_TIME:
				_finish()
	for d in _dancers:
		_update_dancer(d, beat, delta)
	MarigoldCharacterRig.update_all(delta, _rig_ctx()) # v0.6.0: faces


## Read the body tracker (or hands fallback) into the smoothed mirror pose.
## Heavy noise tolerance: exponential smoothing, deadzones, hard clamps.
func _read_pose(delta: float) -> void:
	var k := clampf(10.0 * delta, 0.0, 1.0) # smoothing factor
	if _mode == "body" and _body != null and is_instance_valid(_body):
		if not _body.has_tracking_data:
			_recheck_mode()
			return
		var hips: Vector3 = _body.get_joint_transform(J_HIPS).origin
		var head: Vector3 = _body.get_joint_transform(J_HEAD).origin
		var hl: Vector3 = _body.get_joint_transform(J_HAND_L).origin
		var hr: Vector3 = _body.get_joint_transform(J_HAND_R).origin
		# v0.6.0: echo the player's head tilt on the dancers ("that's me").
		var head_roll_raw: float = clampf(
			_body.get_joint_transform(J_HEAD).basis.get_euler().z, -0.4, 0.4)
		_head_roll = lerpf(_head_roll, head_roll_raw, k)
		if not _have_prev:
			_prev_hips = hips
			_have_prev = true
		# Lean: head offset from hips (x = sideways, z = fwd/back), mirrored.
		var lean := Vector2(head.x - hips.x, head.z - hips.z)
		lean = lean.limit_length(0.45)
		if lean.length() < 0.03:
			lean = Vector2.ZERO # deadzone
		_lean = _lean.lerp(Vector2(-lean.x, lean.y), k) # mirror x
		# Crouch: hips drop below their running baseline.
		var base_y := 0.95
		_crouch = lerpf(_crouch, clampf((base_y - hips.y) * 1.6, 0.0, 0.55), k)
		# Turn: hand depth difference (one hand forward = turn).
		_turn = lerpf(_turn, clampf((hl.z - hr.z) * 2.0, -0.9, 0.9), k)
		# Hands: average height + spread, for the glow orbs.
		_hand_h = lerpf(_hand_h, (hl.y + hr.y) * 0.5, k)
		_hand_spread = lerpf(_hand_spread, clampf(hl.distance_to(hr) * 0.7, 0.1, 1.4), k)
		# Energy: how much the hips move = how hard you're dancing.
		var hv := (hips - _prev_hips).length() / maxf(delta, 0.001)
		_prev_hips = hips
		_energy = lerpf(_energy, clampf(hv * 0.5, 0.0, 1.5), clampf(3.0 * delta, 0.0, 1.0))
	elif _mode == "hands":
		# Hands-only: hand heights drive lean + orbs, beat drives the rest.
		var yl := _hand_pose_y(_hand_l)
		var yr := _hand_pose_y(_hand_r)
		if yl >= 0.0 and yr >= 0.0:
			_hand_h = lerpf(_hand_h, (yl + yr) * 0.5, k)
			_lean = _lean.lerp(Vector2(clampf((yr - yl) * 1.2, -0.4, 0.4), 0.0), k)
			_hand_spread = lerpf(_hand_spread, 0.8, k)
			_energy = lerpf(_energy, 0.8, clampf(2.0 * delta, 0.0, 1.0))
		else:
			_recheck_mode()
	else:
		# Auto-dance: gentle idle so the scene never looks dead.
		_energy = lerpf(_energy, 0.5, clampf(2.0 * delta, 0.0, 1.0))


func _hand_pose_y(tr: XRPositionalTracker) -> float:
	if tr == null or not is_instance_valid(tr):
		return -1.0
	if not tr.has_pose("default"):
		return -1.0
	var pose: XRPose = tr.get_pose("default")
	if pose == null:
		return -1.0
	return pose.transform.origin.y


func _update_energy(delta: float) -> void:
	_confetti_cd -= delta
	_wink_cd -= delta
	if _energy > 0.9 and _confetti_cd <= 0.0:
		_confetti_cd = 2.5
		var c := Vector3(0, 1.8, -2.2)
		MarigoldFX.spawn_confetti(_stage, c, 30)
		MarigoldHaptics.pulse(0.6, 0.2)
	# v0.6.0: the center dancer notices you - locks eyes, winks, tickles
	# your nearest hand. "It noticed me."
	if _energy > 0.9 and _wink_cd <= 0.0 and _dancers.size() >= 2:
		_wink_cd = 12.0
		var d: Dictionary = _dancers[1]
		var rig: MarigoldCharacterRig = d.get("rig")
		if rig != null:
			rig.set_gaze_mode(MarigoldCharacterRig.LOOK_PLAYER)
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				rig.look_at_point(cam.global_position)
			rig.wink(1.0)
			rig.set_expression("MISCHIEVOUS", 0.4)
		var m = _music()
		if m != null and m.has_method("play_stinger"):
			m.call("play_stinger", "wink", -8.0)
		MarigoldHaptics.wink_tick()
		MarigoldFX.eye_sparkle(_stage, (d["root"] as Node3D).global_position + Vector3(0, 1.6, 0))
	_energy_label.text = "Energia " + "●".repeat(int(clampf(_energy * 5.0, 0.0, 5.0)))


func _update_dancer(d: Dictionary, beat: float, delta: float) -> void:
	var root: Node3D = d["root"]
	if root == null or not is_instance_valid(root):
		return
	# Base: beat-synced troupe choreography (shared with Ofrenda Viva).
	MarigoldCalavera.dance_update(d, beat, _t, delta)
	# v0.6.0: the dancers echo your head tilt (J_HEAD roll -> head roll).
	var rig: MarigoldCharacterRig = d.get("rig")
	if rig != null:
		rig.set_head_roll_extra(_head_roll)
	if _phase == "finale":
		return # the bow owns the body now
	# Mirror layer: the player's pose on top of the beat.
	root.rotation.z += _lean.x * 1.4
	root.rotation.x += _lean.y * 0.8
	root.position.y -= _crouch
	root.rotation.y += _turn * 0.6
	var e: float = clampf(0.4 + _energy * 0.6, 0.4, 1.4)
	d["energy"] = e
	# Hand-glow orbs: track the player's mirrored hands in front of each
	# dancer - the visible "that's me" feedback. Mirrored: the dancer's
	# left orb follows the player's right hand height/spread.
	var orbs: Array = d["orbs"]
	var spread := _hand_spread
	var hy := clampf(_hand_h, 0.2, 2.0)
	for i in orbs.size():
		var orb: MeshInstance3D = orbs[i]
		var sx := -1.0 if i == 0 else 1.0 # mirrored
		var lp := Vector3(sx * (0.25 + spread * 0.45), hy - root.position.y, 0.35)
		orb.position = orb.position.lerp(root.position + lp, clampf(10.0 * delta, 0.0, 1.0))
		var om := orb.material_override as StandardMaterial3D
		if om != null:
			om.emission_energy_multiplier = 1.8 + _energy * 1.4


func _finish() -> void:
	if _done:
		return
	_done = true
	for d in _dancers:
		MarigoldCalavera.begin_exit(d, _stage)
	MarigoldFX.petal_ceiling_fall(_stage, Vector3(0, 0, -2.2), 3.0, 120, 20.0, 3.0)
	MarigoldHaptics.fanfare()
	await get_tree().create_timer(2.8).timeout
	chapter_complete.emit()


## ---------------- v0.6.0: face system ----------------

func _rig_ctx() -> Dictionary:
	var ctx := MarigoldCharacterRig.default_ctx(self)
	ctx["hands"] = []
	ctx["on_eye_contact"] = Callable(self, "_on_eye_contact")
	return ctx


func _on_eye_contact(rig: MarigoldCharacterRig) -> void:
	MarigoldHaptics.gaze_lock()
	MarigoldFX.eye_sparkle(_stage, rig.face_world_pos())
