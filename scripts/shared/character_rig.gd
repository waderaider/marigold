## MarigoldCharacterRig.gd - shared procedural face system for MARIGOLD v0.6.0.
## One RefCounted per character; all rigs tick from the static update_all()
## central driver (called once per frame from the active chapter's _process).
##
## Two construction paths (match the MarigoldCalavera static-builder pattern):
## - build_face(skull, opts): code-built face kit on a Node3D (calavera troupe,
##   leader, pets). Uses SHARED static meshes - never allocates per eye.
## - attach_face(root, slots): binds existing named parts on Blender/GLB heroes
##   via MarigoldModels.find_part(). Missing slots are null-safe.
##
## Per-frame cost: ~10 transform writes + ~20 float ops -> < 15 us/char.
## Zero allocations and zero find_node/get_node in update(). Headless-safe:
## null player -> face forward; timers use delta, never wall clock.
## Blinks are SILENT (no haptics on blink - taste rule).
extends RefCounted
class_name MarigoldCharacterRig

## Gaze modes.
const LOOK_PLAYER := 0
const LOOK_AWAY := 1
const LOOK_FIXED := 2

## Expression parameter sets: {brow_raise, brow_tilt, eye_squint, eye_widen,
## jaw_bias, head_tilt, head_pitch, glow_mult, ear_raise}. Material-driven,
## no morphs (Quest-safe). Transitions ease over blend_time (default 0.12 s).
const EXPRESSIONS := {
	"NEUTRAL": {"brow_raise": 0.0, "brow_tilt": 0.0, "eye_squint": 0.0, "eye_widen": 0.0,
		"jaw_bias": 0.0, "head_tilt": 0.0, "head_pitch": 0.0, "glow_mult": 1.0, "ear_raise": 0.0},
	"JOY": {"brow_raise": 0.4, "brow_tilt": 0.0, "eye_squint": 0.15, "eye_widen": 0.0,
		"jaw_bias": 0.35, "head_tilt": 0.10, "head_pitch": -0.08, "glow_mult": 1.6, "ear_raise": 0.4},
	"HAPPY": {"brow_raise": 0.5, "brow_tilt": 0.0, "eye_squint": 0.05, "eye_widen": 0.15,
		"jaw_bias": 0.35, "head_tilt": 0.10, "head_pitch": -0.06, "glow_mult": 1.6, "ear_raise": 0.6},
	"WONDER": {"brow_raise": 1.0, "brow_tilt": 0.0, "eye_squint": 0.0, "eye_widen": 0.35,
		"jaw_bias": 0.25, "head_tilt": 0.0, "head_pitch": -0.05, "glow_mult": 1.3, "ear_raise": 1.0},
	"SORROW": {"brow_raise": 0.0, "brow_tilt": 0.5, "eye_squint": 0.2, "eye_widen": 0.0,
		"jaw_bias": 0.0, "head_tilt": -0.06, "head_pitch": 0.15, "glow_mult": 0.8, "ear_raise": 0.0},
	"CURIOUS": {"brow_raise": 0.3, "brow_tilt": 0.0, "eye_squint": 0.0, "eye_widen": 0.15,
		"jaw_bias": 0.15, "head_tilt": 0.20, "head_pitch": 0.0, "glow_mult": 1.2, "ear_raise": 1.0},
	"SURPRISED": {"brow_raise": 1.0, "brow_tilt": 0.0, "eye_squint": 0.0, "eye_widen": 0.35,
		"jaw_bias": 0.8, "head_tilt": 0.0, "head_pitch": -0.05, "glow_mult": 1.8, "ear_raise": 1.0},
	"SHY": {"brow_raise": 0.0, "brow_tilt": 0.2, "eye_squint": 0.1, "eye_widen": 0.0,
		"jaw_bias": 0.0, "head_tilt": -0.10, "head_pitch": 0.12, "glow_mult": 0.9, "ear_raise": 0.0},
	"MISCHIEVOUS": {"brow_raise": 0.2, "brow_tilt": 0.3, "eye_squint": 0.1, "eye_widen": 0.05,
		"jaw_bias": 0.25, "head_tilt": 0.18, "head_pitch": 0.0, "glow_mult": 1.3, "ear_raise": 0.5},
	"SLEEPY": {"brow_raise": 0.0, "brow_tilt": 0.0, "eye_squint": 0.6, "eye_widen": 0.0,
		"jaw_bias": 0.1, "head_tilt": 0.0, "head_pitch": 0.10, "glow_mult": 0.7, "ear_raise": 0.0},
}

## ---- shared static meshes/materials (built once, reused by every face) ----
static var _eye_mesh: SphereMesh = null
static var _pupil_mesh: SphereMesh = null
static var _ring_mesh: TorusMesh = null
static var _brow_mesh: BoxMesh = null
static var _jaw_mesh: BoxMesh = null
static var _pupil_mat: StandardMaterial3D = null

## ---- registry ----
static var _rigs: Array = []
static var _featured_t := 0.0


static func _shared() -> void:
	if _eye_mesh != null:
		return
	_eye_mesh = SphereMesh.new()
	_eye_mesh.radius = 1.0
	_eye_mesh.height = 2.0
	_eye_mesh.radial_segments = 12
	_eye_mesh.rings = 6
	_pupil_mesh = SphereMesh.new()
	_pupil_mesh.radius = 1.0
	_pupil_mesh.height = 2.0
	_pupil_mesh.radial_segments = 8
	_pupil_mesh.rings = 4
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.78
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 16
	_ring_mesh.ring_segments = 6
	_brow_mesh = BoxMesh.new()
	_brow_mesh.size = Vector3(1.0, 0.18, 0.18)
	_jaw_mesh = BoxMesh.new()
	_jaw_mesh.size = Vector3(1.0, 0.5, 0.8)
	_pupil_mat = StandardMaterial3D.new()
	_pupil_mat.albedo_color = Color(0.05, 0.02, 0.08)
	_pupil_mat.roughness = 0.35


## Register / unregister.
static func _register(rig: MarigoldCharacterRig) -> void:
	if not _rigs.has(rig):
		_rigs.append(rig)


static func clear_registry() -> void:
	_rigs.clear()


## Central per-frame driver. Call ONCE per frame from the active chapter.
## ctx keys (all optional): player_pos (Vector3), hands (Array[Vector3]),
## voice_env (0..1), beat_phase (-1 idle), t (scene time),
## on_eye_contact (Callable(rig)).
static func update_all(delta: float, ctx: Dictionary = {}) -> void:
	# Purge dead rigs (their character was freed) and refresh the
	# featured set (nearest 6 get gaze + pupils) at 4 Hz.
	_featured_t -= delta
	var refresh := _featured_t <= 0.0
	if refresh:
		_featured_t = 0.25
	var i := _rigs.size() - 1
	while i >= 0:
		var r: MarigoldCharacterRig = _rigs[i]
		if r._root == null or not is_instance_valid(r._root):
			_rigs.remove_at(i)
		i -= 1
	if refresh:
		_update_featured(ctx)
	for r in _rigs:
		r.update(delta, ctx)


## Crowd rule: in scenes with >6 characters, only the 6 nearest get
## pupils + gaze; everyone else gets blink + fixed gaze.
static func _update_featured(ctx: Dictionary) -> void:
	if _rigs.size() <= 6:
		for r in _rigs:
			(r as MarigoldCharacterRig).featured = true
		return
	var pp: Variant = ctx.get("player_pos", null)
	var order: Array = []
	for r in _rigs:
		var rr: MarigoldCharacterRig = r
		var d := 1e9
		if pp is Vector3 and rr._root != null and is_instance_valid(rr._root):
			d = (rr._root.global_position - (pp as Vector3)).length_squared()
		order.append({"r": rr, "d": d})
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for k in order.size():
		(order[k]["r"] as MarigoldCharacterRig).featured = k < 6


## One-line context builder for chapters. All lookups are null-safe and
## headless-safe (missing camera/voice/music -> neutral defaults).
static func default_ctx(node: Node) -> Dictionary:
	var ctx := {"t": Time.get_ticks_msec() / 1000.0, "beat_phase": -1.0,
		"voice_env": 0.0, "player_pos": null, "hands": []}
	if node != null and node.is_inside_tree():
		var cam := node.get_viewport().get_camera_3d()
		if cam != null:
			ctx["player_pos"] = cam.global_position
	var voice_node: Node = null
	if Engine.has_singleton("MarigoldVoice"):
		voice_node = Engine.get_singleton("MarigoldVoice")
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			voice_node = tree.root.get_node_or_null("MarigoldVoice")
	if voice_node != null and voice_node.has_method("get_envelope"):
		ctx["voice_env"] = clampf(float(voice_node.call("get_envelope")), 0.0, 1.0)
	var st: Node = null
	var tree2 := Engine.get_main_loop() as SceneTree
	if tree2 != null and tree2.root != null:
		st = tree2.root.get_node_or_null("MarigoldState")
	if st != null:
		var music: Object = st.get("music")
		if music != null and (music as Object).has_method("get_beat_phase"):
			ctx["beat_phase"] = float((music as Object).call("get_beat_phase"))
	return ctx


## ---- construction ----

## Build a canonical face kit on a code-built character.
## skull: Node3D to parent the kit to (e.g. the Kenney skeleton node).
## opts: eye_positions (Array[Vector3], REQUIRED), eye_radius (0.035),
##   glow (Color), ring (true = sugar-skull eye rings), pupils (true),
##   jaw (true = lower-jaw plate), jaw_pos (Vector3), jaw_size (Vector3),
##   brow (false), glow_energy (2.6), seed (0 = random).
static func build_face(skull: Node3D, opts: Dictionary) -> MarigoldCharacterRig:
	_shared()
	var rig := MarigoldCharacterRig.new()
	rig._root = skull
	var positions: Array = opts.get("eye_positions", [])
	var radius: float = float(opts.get("eye_radius", 0.035))
	var glow_col: Color = opts.get("glow", Color(1.0, 0.6, 0.12))
	var glow_e: float = float(opts.get("glow_energy", 2.6))
	rig._rng = RandomNumberGenerator.new()
	var seed: int = int(opts.get("seed", 0))
	if seed != 0:
		rig._rng.seed = seed
	else:
		rig._rng.randomize()
	# Face pivot: the look-at target. On single-mesh skulls the face features
	# turn inside the skull; pupils + head-lead sell the gaze.
	var fp := Node3D.new()
	fp.name = "FacePivot"
	fp.position = opts.get("face_pos", Vector3(0, 0.60, 0.06))
	skull.add_child(fp)
	rig._head = fp
	rig._head_rest = Vector3.ZERO
	rig._eye_mat = MarigoldFX.glow(glow_col, glow_e)
	rig._glow_base = glow_e
	var do_ring: bool = bool(opts.get("ring", true))
	var do_pupils: bool = bool(opts.get("pupils", true))
	var side := 0
	for pos in positions:
		var p: Vector3 = pos
		var eye := MeshInstance3D.new()
		eye.name = "Eye_%d" % side
		eye.mesh = _eye_mesh
		eye.material_override = rig._eye_mat
		eye.position = p - fp.position
		eye.scale = Vector3.ONE * radius
		fp.add_child(eye)
		var pupil: MeshInstance3D = null
		var pupil_base := Vector3(0, 0, 0.78)
		if do_pupils:
			pupil = MeshInstance3D.new()
			pupil.name = "Pupil_%d" % side
			pupil.mesh = _pupil_mesh
			pupil.material_override = _pupil_mat
			pupil.position = pupil_base
			pupil.scale = Vector3.ONE * 0.38
			eye.add_child(pupil)
		if do_ring:
			var ring := MeshInstance3D.new()
			ring.name = "Ring_%d" % side
			ring.mesh = _ring_mesh
			ring.material_override = rig._eye_mat
			ring.position = p - fp.position + Vector3(0, 0, -0.15 * radius)
			ring.rotation_degrees.x = 90.0
			ring.scale = Vector3.ONE * radius * 1.55
			fp.add_child(ring)
		rig._eyes.append({"node": eye, "pupil": pupil,
			"pupil_base": pupil_base, "base_r": radius,
			"delay": float(side) * 0.02, "gaze": Vector2.ZERO,
			"sacc": Vector2.ZERO, "side": -1.0 if side == 0 else 1.0})
		side += 1
	if bool(opts.get("jaw", true)):
		var jp := Node3D.new()
		jp.name = "JawPivot"
		jp.position = opts.get("jaw_pos", Vector3(0, 0.545, 0.03)) - fp.position
		fp.add_child(jp)
		var jm := MeshInstance3D.new()
		jm.name = "JawPlate"
		jm.mesh = _jaw_mesh
		jm.material_override = opts.get("jaw_mat", MarigoldFX.pbr(Color(0.93, 0.87, 0.74), 0.0, 0.55))
		var js: Vector3 = opts.get("jaw_size", Vector3(0.09, 0.05, 0.08))
		jm.scale = js
		jm.position = Vector3(0, -js.y * 0.4, js.z * 0.35)
		jp.add_child(jm)
		rig._jaw = jp
		rig._jaw_rest = Vector3.ZERO
	if bool(opts.get("brow", false)):
		for bs in [-1.0, 1.0]:
			var bp := Node3D.new()
			bp.name = "Brow_%d" % int(bs)
			bp.position = Vector3(bs * radius * 1.6, radius * 1.9, 0)
			fp.add_child(bp)
			var bm := MeshInstance3D.new()
			bm.mesh = _brow_mesh
			bm.material_override = rig._eye_mat
			bm.scale = Vector3(radius * 1.4, radius * 1.4, radius * 1.4)
			bp.add_child(bm)
			rig._brows.append({"node": bp, "rest": bp.position})
	rig._reset_timers()
	_register(rig)
	return rig


## Bind to existing named parts (Blender GLB heroes, leader face, pets).
## slots: eyes (Array of fragments or Node3D), head (fragment|Node3D),
##   jaw (fragment|Node3D), ears (Array), opts: pupils (true), glow (Color),
##   glow_energy (2.2), seed. Eye glow pulses are owned by the rig after this
##   (the chapter should stop pulsing the eye material itself).
static func attach_face(root: Node3D, slots: Dictionary) -> MarigoldCharacterRig:
	_shared()
	var rig := MarigoldCharacterRig.new()
	rig._root = root
	rig._rng = RandomNumberGenerator.new()
	var seed: int = int(slots.get("seed", 0))
	if seed != 0:
		rig._rng.seed = seed
	else:
		rig._rng.randomize()
	var glow_col: Color = slots.get("glow", Color(1.0, 0.6, 0.12))
	var glow_e: float = float(slots.get("glow_energy", 2.2))
	rig._eye_mat = MarigoldFX.glow(glow_col, glow_e)
	rig._glow_base = glow_e
	var head_n := _resolve(root, slots.get("head", null))
	if head_n != null:
		rig._head = head_n
		rig._head_rest = head_n.rotation
	rig._jaw = _resolve(root, slots.get("jaw", null))
	if rig._jaw != null:
		rig._jaw_rest = rig._jaw.rotation
	for e in slots.get("ears", []):
		var en := _resolve(root, e)
		if en != null:
			rig._ears.append({"node": en, "rest": en.rotation})
	var do_pupils: bool = bool(slots.get("pupils", true))
	var pupil_set: Array = slots.get("pupil_eyes", [])
	var side := 0
	for e in slots.get("eyes", []):
		var en := _resolve(root, e)
		if en == null:
			continue
		# The rig owns the eye glow from here: re-point the eye at the rig's
		# shared material so expression/emotion energy actually lands.
		var emi := en as MeshInstance3D
		if emi != null:
			emi.material_override = rig._eye_mat
		var want_pupil := do_pupils and (pupil_set.is_empty() or pupil_set.has(e))
		var pupil: MeshInstance3D = null
		var pupil_base := Vector3.ZERO
		if want_pupil:
			var pr := _attach_pupil(en)
			pupil = pr["node"]
			pupil_base = pr["base"]
		rig._eyes.append({"node": en, "pupil": pupil,
			"pupil_base": pupil_base, "base_r": 1.0,
			"delay": float(side) * 0.02, "gaze": Vector2.ZERO,
			"sacc": Vector2.ZERO, "side": -1.0 if side % 2 == 0 else 1.0,
			"base_scale": (en as Node3D).scale})
		side += 1
	rig._reset_timers()
	_register(rig)
	return rig


## Resolve a slot: Node3D passes through, String is a find_part fragment.
static func _resolve(root: Node3D, slot: Variant) -> Node3D:
	if slot is Node3D:
		return slot
	if slot is String and not (slot as String).is_empty():
		return MarigoldModels.find_part(root, slot)
	return null


## Add a dark pupil to a GLB eye mesh, placed proud of its front surface.
## Returns {"node": pupil, "base": pupil_base_pos}. Front = -Z (models face -Z).
static func _attach_pupil(eye: Node3D) -> Dictionary:
	var mi := eye as MeshInstance3D
	var center := Vector3.ZERO
	var half_z := 0.03
	var rad := 0.02
	if mi != null and mi.mesh != null:
		var aabb := mi.mesh.get_aabb()
		center = aabb.get_center()
		half_z = aabb.size.z * 0.5
		rad = minf(aabb.size.x, aabb.size.y) * 0.22
	var pupil := MeshInstance3D.new()
	pupil.name = "Pupil"
	pupil.mesh = _pupil_mesh
	pupil.material_override = _pupil_mat
	pupil.position = center + Vector3(0, 0, -half_z * 0.85)
	pupil.scale = Vector3.ONE * rad
	eye.add_child(pupil)
	return {"node": pupil, "base": pupil.position, "r": rad}


## ---- instance state ----

var _root: Node3D = null
var _head: Node3D = null
var _head_rest := Vector3.ZERO
var _jaw: Node3D = null
var _jaw_rest := Vector3.ZERO
var _eyes: Array = [] # {node, pupil, pupil_base, base_r, delay, gaze, sacc, side, base_scale?}
var _brows: Array = [] # {node, rest}
var _ears: Array = [] # {node, rest}
var _eye_mat: Material = null
var _glow_base := 2.0
var _rng: RandomNumberGenerator = null

var featured := true
var _gaze_mode := LOOK_PLAYER
var _look_point := Vector3.ZERO
var _has_look := false

var _blink_t := 3.0
var _blink_phase := -1.0
var _double_pending := false
var _sacc_t := 0.5
var _sacc_target := Vector2.ZERO

var _expr_cur := {}
var _expr_from := {}
var _expr_to := {}
var _expr_t := 1.0
var _expr_dur := 0.12

var _speaking := false
var _singing := false
var _syll_t := 0.0
var _syll_open := 0.0
var _jaw_hold := 0.0
var _jaw_hold_t := 0.0

var _wink_t := 0.0
var _wink_side := 1.0
var _head_roll_extra := 0.0
var _relax := 0.0 # 0 open .. 1 eyes eased shut (pet bliss)
var _ear_flat := 0.0
var _contact_cd := 0.0


func _reset_timers() -> void:
	_blink_t = _rng.randf_range(2.2, 5.5)
	_blink_phase = -1.0
	_sacc_t = _rng.randf_range(0.4, 1.2)
	_expr_cur = (EXPRESSIONS["NEUTRAL"] as Dictionary).duplicate()
	_expr_from = _expr_cur.duplicate()
	_expr_to = _expr_cur.duplicate()
	_expr_t = 1.0


## ---- public control API (called from chapters) ----

func set_expression(name: String, blend_time: float = 0.12) -> void:
	var e: Dictionary = EXPRESSIONS.get(name.to_upper(), EXPRESSIONS["NEUTRAL"])
	_expr_from = _sample_expr()
	_expr_to = (e as Dictionary).duplicate()
	_expr_t = 0.0
	_expr_dur = maxf(0.01, blend_time)
	if name.to_upper() == "SURPRISED":
		_double_pending = true
		_blink_phase = 0.0 # immediate double-blink on surprise


func clear_expression() -> void:
	set_expression("NEUTRAL", 0.3)


func set_speaking(on: bool) -> void:
	_speaking = on


func set_singing(on: bool) -> void:
	_singing = on


func set_gaze_mode(mode: int) -> void:
	_gaze_mode = mode


func look_at_point(p: Vector3) -> void:
	_look_point = p
	_has_look = true


func release_look() -> void:
	_has_look = false


## Instantly snap gaze to a point (the bow moment's pupil snap).
func snap_look(p: Vector3) -> void:
	look_at_point(p)
	var yaw_pitch := _yaw_pitch_to(p)
	if _head != null and is_instance_valid(_head):
		_head.rotation.y = _head_rest.y + float(yaw_pitch["yaw"])
		_head.rotation.x = _head_rest.x - float(yaw_pitch["pitch"])
	for e in _eyes:
		e["gaze"] = Vector2(signf(float(yaw_pitch["yaw"])) * 0.45, clampf(float(yaw_pitch["pitch"]) * 2.0, -0.45, 0.45))


## One-eye blink + head roll. Event-only (never on a timer).
func wink(side: float = 1.0) -> void:
	_wink_t = 0.45
	_wink_side = signf(side)


## Extra head roll in radians (espejo echoes the player's head tilt).
func set_head_roll_extra(roll: float) -> void:
	_head_roll_extra = clampf(roll, -0.35, 0.35)


## Eyes ease shut 0..1 (pet bliss). 0 = normal.
func set_relax(v: float) -> void:
	_relax = clampf(v, 0.0, 1.0)


## Ears flatten 0..1 (fast approach startle).
func set_ear_flat(v: float) -> void:
	_ear_flat = clampf(v, 0.0, 1.0)


## Hold the jaw open at v for dur seconds (feed-joy laugh).
func set_jaw_hold(v: float, dur: float) -> void:
	_jaw_hold = clampf(v, 0.0, 1.0)
	_jaw_hold_t = dur


## Remove from the registry (call when the character is freed early).
func detach() -> void:
	_rigs.erase(self)


## World position of the face (head pivot, or root + 1.6 m fallback).
func face_world_pos() -> Vector3:
	if _head != null and is_instance_valid(_head):
		return _head.global_position
	if _root != null and is_instance_valid(_root):
		return _root.global_position + Vector3(0, 1.6, 0)
	return Vector3(0, 1.6, 0)


## Recolor the shared eye-glow material (face-paint variants).
func set_glow_color(c: Color) -> void:
	var m := _eye_mat as StandardMaterial3D
	if m == null:
		return
	m.albedo_color = c
	m.emission = c


## ---- per-frame update (the hot path: no allocations, no node lookups) ----

func update(delta: float, ctx: Dictionary) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var t: float = float(ctx.get("t", 0.0))
	var env: float = clampf(float(ctx.get("voice_env", 0.0)), 0.0, 1.0)
	var beat: float = float(ctx.get("beat_phase", -1.0))
	var pp: Variant = ctx.get("player_pos", null)
	var hands: Array = ctx.get("hands", [])
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_update_expression(delta)
	_update_blink(delta)
	_update_gaze(delta, t, pp, hands, ctx)
	_update_jaw(delta, t, env, beat)
	_update_face_parts(delta, t)


func _sample_expr() -> Dictionary:
	var e := _expr_to if _expr_t >= 1.0 else _expr_cur
	return (e as Dictionary).duplicate()


func _update_expression(delta: float) -> void:
	if _expr_t < 1.0:
		_expr_t = minf(1.0, _expr_t + delta / _expr_dur)
		var k := _expr_t * _expr_t * (3.0 - 2.0 * _expr_t) # smoothstep
		for key in _expr_to:
			_expr_cur[key] = lerpf(float(_expr_from.get(key, 0.0)), float(_expr_to[key]), k)


## Blink: 2.2-5.5 s timers, 80 ms-class close, 15% double-blink. SILENT.
func _update_blink(delta: float) -> void:
	if _blink_phase < 0.0:
		_blink_t -= delta
		if _blink_t <= 0.0:
			_blink_phase = 0.0
			if _rng.randf() < 0.15:
				_double_pending = true
	else:
		_blink_phase += delta / 0.19
		if _blink_phase >= 1.0:
			_blink_phase = -1.0
			_blink_t = _rng.randf_range(2.2, 5.5)
			if _double_pending:
				_double_pending = false
				_blink_t = 0.22
	var squint: float = float(_expr_cur.get("eye_squint", 0.0))
	var widen: float = float(_expr_cur.get("eye_widen", 0.0))
	var open_k := (1.0 - 0.15 * squint + 0.35 * widen) * (1.0 - 0.85 * _relax)
	if _wink_t > 0.0:
		_wink_t -= delta
	for e in _eyes:
		var n: Node3D = e["node"]
		if n == null or not is_instance_valid(n):
			continue
		var k := open_k
		if _blink_phase >= 0.0:
			var pd: float = clampf((_blink_phase * 0.19 - float(e["delay"])) / 0.19, 0.0, 1.0)
			if pd > 0.0 and pd < 1.0:
				k *= 1.0 - 0.92 * sin(pd * PI)
		if _wink_t > 0.0 and signf(float(e["side"])) == _wink_side:
			k *= 0.08
		var bs: Vector3 = e.get("base_scale", Vector3.ONE * float(e.get("base_r", 0.035)))
		n.scale = Vector3(bs.x, bs.y * k, bs.z)


## Gaze: head look-at (critically damped ~8/s, clamped) + pupil micro-saccades.
func _update_gaze(delta: float, t: float, pp: Variant, hands: Array, ctx: Dictionary) -> void:
	# Eye-contact event: gaze locked, player within 2.5 m, rate-limited 1/10 s.
	if featured and _gaze_mode == LOOK_PLAYER and pp is Vector3 and _contact_cd <= 0.0:
		var d: float = (_root.global_position - (pp as Vector3)).length()
		if d < 2.5:
			_contact_cd = 10.0
			var cb: Variant = ctx.get("on_eye_contact", null)
			if cb is Callable:
				(cb as Callable).call(self)
	# Resolve the look target: override > nearest hand (2.5 m) > player.
	var target := Vector3.ZERO
	var have := false
	if _has_look:
		target = _look_point
		have = true
	elif _gaze_mode == LOOK_PLAYER:
		var best := 2.5
		for h in hands:
			if h is Vector3:
				var dd: float = _root.global_position.distance_to(h)
				if dd < best:
					best = dd
					target = h
					have = true
		if not have and pp is Vector3:
			target = pp
			have = true
	elif _gaze_mode == LOOK_AWAY and pp is Vector3:
		target = _root.global_position * 2.0 - (pp as Vector3)
		have = true
	# Head look-at.
	if _head != null and is_instance_valid(_head):
		var yaw := 0.0
		var pitch := 0.0
		if have and _gaze_mode != LOOK_FIXED:
			var yp := _yaw_pitch_to(target)
			yaw = float(yp["yaw"])
			pitch = float(yp["pitch"])
		var k := 1.0 - exp(-8.0 * delta)
		var tilt: float = float(_expr_cur.get("head_tilt", 0.0))
		var hpitch: float = float(_expr_cur.get("head_pitch", 0.0))
		var roll := _head_roll_extra
		if _wink_t > 0.0:
			roll += _wink_side * 0.14
		_head.rotation.y = lerpf(_head.rotation.y, _head_rest.y + yaw + tilt, k)
		_head.rotation.x = lerpf(_head.rotation.x, _head_rest.x - pitch + hpitch, k)
		_head.rotation.z = lerpf(_head.rotation.z, _head_rest.z + roll, k)
	# Pupils: saccades + gaze offset (featured only; hidden otherwise).
	_sacc_t -= delta
	if _sacc_t <= 0.0:
		_sacc_t = _rng.randf_range(0.4, 1.2)
		_sacc_target = Vector2(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.12, 0.12))
	var sk := 1.0 - exp(-12.0 * delta)
	for e in _eyes:
		var pup: MeshInstance3D = e["pupil"]
		if pup == null or not is_instance_valid(pup):
			continue
		pup.visible = featured
		if not featured:
			continue
		e["sacc"] = (e["sacc"] as Vector2).lerp(_sacc_target, sk)
		var goff := Vector2.ZERO
		if have and _gaze_mode != LOOK_FIXED and _head != null and is_instance_valid(_head):
			var dir: Vector3 = (target - _head.global_position).normalized()
			var ldir: Vector3 = _head.global_transform.basis.inverse() * dir
			goff = Vector2(clampf(ldir.x, -1.0, 1.0), clampf(ldir.y, -1.0, 1.0)) * 0.45
		e["gaze"] = (e["gaze"] as Vector2).lerp(goff, sk)
		var off: Vector2 = (e["gaze"] as Vector2) + (e["sacc"] as Vector2)
		pup.position = (e["pupil_base"] as Vector3) + Vector3(off.x, off.y, 0.0)


## Yaw (clamped +-0.6) and pitch (clamped +-0.35) from head-parent space.
func _yaw_pitch_to(target: Vector3) -> Dictionary:
	if _head == null or not is_instance_valid(_head):
		return {"yaw": 0.0, "pitch": 0.0}
	var parent := _head.get_parent() as Node3D
	var local := target
	if parent != null:
		local = parent.global_transform.affine_inverse() * target
	var yaw := clampf(atan2(-local.x, -local.z), -0.6, 0.6)
	var flat := Vector2(local.x, local.z).length()
	var pitch := clampf(atan2(local.y, maxf(flat, 0.001)), -0.35, 0.35)
	return {"yaw": yaw, "pitch": pitch}


## Jaw: envelope > syllable fallback > beat-synced singing. Plus expression
## bias and a tiny vowel wobble. rotation.x = -open * 0.55.
func _update_jaw(delta: float, t: float, env: float, beat: float) -> void:
	if _jaw == null or not is_instance_valid(_jaw):
		return
	var open := 0.0
	if _speaking:
		open = maxf(open, env * 1.4)
		if env < 0.05:
			_syll_t -= delta
			if _syll_t <= 0.0:
				_syll_t = _rng.randf_range(0.10, 0.17) # 6-10 Hz syllables
				_syll_open = _rng.randf_range(0.2, 0.7)
			open = maxf(open, _syll_open)
	if _singing and beat >= 0.0:
		open = maxf(open, pow(1.0 - beat, 2.0) * 0.7)
	if _jaw_hold_t > 0.0:
		_jaw_hold_t -= delta
		open = maxf(open, _jaw_hold)
	open = clampf(open + float(_expr_cur.get("jaw_bias", 0.0)), 0.0, 1.0)
	var wobble := sin(t * 13.0 + float(_eyes.size())) * 0.03 * open
	_jaw.rotation.x = _jaw_rest.x - open * 0.55 + wobble


## Brows, ears, eye glow (shared material per character: mutate energy only,
## never duplicate per node - the material rule).
func _update_face_parts(delta: float, t: float) -> void:
	var k := 1.0 - exp(-6.0 * delta)
	var brow_raise: float = float(_expr_cur.get("brow_raise", 0.0))
	var brow_tilt: float = float(_expr_cur.get("brow_tilt", 0.0))
	for b in _brows:
		var n: Node3D = b["node"]
		if n == null or not is_instance_valid(n):
			continue
		n.rotation.z = lerpf(n.rotation.z, brow_tilt * 0.4, k)
		var rest: Vector3 = b["rest"]
		n.position.y = lerpf(n.position.y, rest.y + brow_raise * 0.012, k)
	var ear_raise: float = float(_expr_cur.get("ear_raise", 0.0))
	for e in _ears:
		var n2: Node3D = e["node"]
		if n2 == null or not is_instance_valid(n2):
			continue
		var rest2: Vector3 = e["rest"]
		n2.rotation.z = lerpf(n2.rotation.z, rest2.z + ear_raise * 0.30 - _ear_flat * 0.55, k)
		n2.rotation.x = lerpf(n2.rotation.x, rest2.x - _ear_flat * 0.35, k)
	if _eye_mat != null:
		var glow_mult: float = float(_expr_cur.get("glow_mult", 1.0))
		var pulse := 1.0 + 0.12 * sin(t * 2.5 + float(_eyes.size()) * 1.7)
		var m := _eye_mat as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = _glow_base * glow_mult * pulse
