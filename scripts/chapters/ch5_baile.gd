## ch5_baile.gd - MARIGOLD Chapter 5: El Gran Baile (finale).
## A grand night dance plaza: 9 original skeleton celebrants, a dance leader,
## a follow-the-leader dance game (8 moves), then marigold petal fireworks.
## Original characters and choreography; no film references.
extends Node3D

signal chapter_complete

const DEMO_TIME := 3.5
const DO_TIME := 12.0
const HOLD_TIME := 1.5
const CHEER_TIME := 1.6
const FINALE_TIME := 8.0
const VOLLEY_COUNT := 6
const STAGE_CENTER := Vector3(0, 0, -3)
const STAGE_TOP_Y := 0.25

# 8 follow-the-leader moves: label, leader arm targets, body lean target.
const MOVES := [
	{"label": "Raise your left hand!", "al": Vector3(0, 0, -2.4), "ar": Vector3(0, 0, 0.3), "lean": Vector3.ZERO},
	{"label": "Both hands up!", "al": Vector3(0, 0, -2.7), "ar": Vector3(0, 0, 2.7), "lean": Vector3.ZERO},
	{"label": "Wave hello!", "al": Vector3(0, 0, -0.4), "ar": Vector3(-1.7, 0, 0.4), "lean": Vector3.ZERO},
	{"label": "Hands to your heart!", "al": Vector3(-0.8, 0, -1.0), "ar": Vector3(-0.8, 0, 1.0), "lean": Vector3.ZERO},
	{"label": "Sway left!", "al": Vector3(0, 0, -1.5), "ar": Vector3(0, 0, 1.5), "lean": Vector3(0, 0, 0.35)},
	{"label": "Sway right!", "al": Vector3(0, 0, -1.5), "ar": Vector3(0, 0, 1.5), "lean": Vector3(0, 0, -0.35)},
	{"label": "Clap above your head!", "al": Vector3(-0.4, 0, -2.5), "ar": Vector3(-0.4, 0, 2.5), "lean": Vector3.ZERO},
	{"label": "Take a bow!", "al": Vector3(0.6, 0, -0.5), "ar": Vector3(0.6, 0, 0.5), "lean": Vector3(0.7, 0, 0)},
]

const DANCER_COLORS := [
	Color(1.0, 0.30, 0.60), Color(0.20, 0.90, 1.00), Color(0.50, 1.00, 0.20),
	Color(0.70, 0.30, 1.00), Color(1.00, 0.55, 0.10), Color(0.20, 1.00, 0.80),
	Color(1.00, 0.80, 0.20), Color(1.00, 0.25, 0.25), Color(0.35, 0.50, 1.00),
]

const GENTLE_PROMPTS := [
	"Copy the leader's pose!",
	"Hold it steady...",
	"Tu puedes - you've got this!",
	"Dance like everyone is watching!",
]

var _ar_mode := false
var _world: Node3D = null
var _ar_hidden: Array = []
var _t := 0.0
var _built := false

var _dancers: Array = []
var _leader: Node3D = null
var _leader_body: Node3D = null
var _leader_arm_l: Node3D = null
var _leader_arm_r: Node3D = null
var _leader_al_target := Vector3(0, 0, -0.3)
var _leader_ar_target := Vector3(0, 0, 0.3)
var _leader_lean_target := Vector3.ZERO

var _phase := "intro" # intro, demo, do, cheer, finale, done
var _phase_t := 0.0
var _move_idx := -1
var _moves_done := 0
var _hold_t := 0.0
var _cheer_t := 0.0
var _prompt_t := 0.0
var _prompt_idx := 0
var _finale_t := 0.0
var _volley := 0
var _wave_hist: Array = []
var _rng := RandomNumberGenerator.new()

var _label_move: Label3D = null
var _label_hint: Label3D = null
var _label_score: Label3D = null
var _progress_ring: MeshInstance3D = null
var _progress_mat: StandardMaterial3D = null
var _candles: Array = []
var _plaque: Node3D = null


## ---- Chapter contract ----

func setup(ar_mode: bool) -> void:
	if _built:
		apply_mode(ar_mode)
		return
	_built = true
	_rng.seed = 20261006
	_build_world()
	_build_stage()
	_build_crowd()
	_build_leader()
	_build_labels()
	_build_plaque()
	apply_mode(ar_mode)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	for n in _ar_hidden:
		if is_instance_valid(n):
			n.visible = not on
	if _world == null:
		return
	if on:
		# Tabletop diorama: shrink, center the stage on a table point, anchor it.
		_world.scale = Vector3.ONE * 0.4
		var cam := get_viewport().get_camera_3d()
		var fwd := Vector3(0, 0, -1)
		var base := Vector3.ZERO
		if cam != null:
			fwd = -cam.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3(0, 0, -1)
			base = cam.global_position
		_world.rotation.y = atan2(-fwd.x, -fwd.z)
		var anchor: Variant = MarigoldHands.load_anchor(MarigoldState.anchor_name("ch5"))
		if anchor != null:
			_world.global_transform = anchor
		else:
			# Stage local center (0,0,-3) * 0.4 = (0,0,-1.2): shift so it lands on the table point.
			var table_pt := Vector3(base.x, 0.75, base.z) + fwd * 1.0
			_world.position = table_pt - fwd * 1.2
			MarigoldHands.save_anchor(MarigoldState.anchor_name("ch5"), _world.global_transform)
	else:
		_world.scale = Vector3.ONE
		_world.position = Vector3.ZERO
		_world.rotation.y = 0.0


## ---- Build ----

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "Diorama"
	add_child(_world)

	# Marigold field ring around the plaza (hidden in AR).
	var field := MarigoldFX.make_marigold_field(_world, 260, 9.0)
	field.position = STAGE_CENTER
	_ar_hidden.append(field)

	# God rays (hidden in AR).
	for gx in [-2.2, 2.2, 0.0]:
		var ray := MarigoldFX.make_god_ray(_world, Vector3(gx, 0, -3.0), 7.0)
		_ar_hidden.append(ray)

	# Papel picado banners overhead (hidden in AR).
	var banner_defs := [
		[Vector3(0, 4.6, -1.2), 4.0, Color(1.0, 0.30, 0.60), 0.15],
		[Vector3(0, 4.9, -3.4), 5.0, Color(0.20, 0.80, 1.00), -0.12],
		[Vector3(0, 4.6, -5.6), 4.0, Color(1.00, 0.65, 0.10), 0.20],
	]
	for b in banner_defs:
		var banner := MarigoldFX.make_papel_banner(_world, b[1], 1.1, b[2])
		banner.position = b[0]
		banner.rotation.y = b[3]
		_ar_hidden.append(banner)

	# Ambient motes stay in both modes.
	MarigoldFX.spawn_ambient_motes(_world, Vector3(0, 1.8, -3.0), 4.5, 60)


func _build_stage() -> void:
	# Circular stone stage.
	var stage := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.15
	cyl.height = STAGE_TOP_Y
	cyl.radial_segments = 48
	cyl.material = MarigoldFX.pbr(Color(0.32, 0.28, 0.36), 0.05, 0.8)
	stage.mesh = cyl
	stage.position = STAGE_CENTER + Vector3(0, STAGE_TOP_Y * 0.5, 0)
	_world.add_child(stage)

	# Glowing marigold rim.
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.90
	torus.outer_radius = 3.08
	torus.rings = 64
	torus.ring_segments = 12
	torus.material = MarigoldFX.glow(Color(1.0, 0.60, 0.10), 1.6)
	rim.mesh = torus
	rim.position = STAGE_CENTER + Vector3(0, STAGE_TOP_Y + 0.01, 0)
	_world.add_child(rim)

	# Center medallion.
	var med := MeshInstance3D.new()
	var med_mesh := CylinderMesh.new()
	med_mesh.top_radius = 0.8
	med_mesh.bottom_radius = 0.8
	med_mesh.height = 0.02
	med_mesh.material = MarigoldFX.glow(Color(1.0, 0.55, 0.15), 1.2)
	med.mesh = med_mesh
	med.position = STAGE_CENTER + Vector3(0, STAGE_TOP_Y + 0.01, 0)
	_world.add_child(med)

	# Floating candles around the rim: emissive only, except 2 real lights.
	for i in 8:
		var a := TAU * float(i) / 8.0
		var pos := STAGE_CENTER + Vector3(cos(a) * 3.35, 0.55, sin(a) * 3.35)
		var candle := MarigoldFX.make_candle(_world, pos, i == 0 or i == 4, 0.8)
		_candles.append({"node": candle, "base_y": 0.55, "phase": TAU * float(i) / 8.0})

	# One warm wash light over the stage (plus the 2 candle lights = light budget).
	MarigoldFX.make_point_light(_world, STAGE_CENTER + Vector3(0, 3.5, 0), Color(1.0, 0.70, 0.35), 1.1, 9.0)


func _build_crowd() -> void:
	for i in 9:
		var accent: Color = DANCER_COLORS[i % DANCER_COLORS.size()]
		var d := _make_skeleton(accent, _rng.randf_range(0.92, 1.08), false)
		var root: Node3D = d["root"]
		var a := TAU * float(i) / 9.0 + 0.18
		var pos := STAGE_CENTER + Vector3(cos(a) * 1.9, STAGE_TOP_Y, sin(a) * 1.9)
		root.position = pos
		var to_center := STAGE_CENTER - pos
		var base_rot := atan2(to_center.x, to_center.z)
		root.rotation.y = base_rot
		_world.add_child(root)
		_dancers.append({
			"root": root, "body": d["body"],
			"arm_l": d["arm_l"], "arm_r": d["arm_r"],
			"phase": _rng.randf() * TAU, "speed": _rng.randf_range(1.6, 2.4),
			"style": i % 3, "base_y": STAGE_TOP_Y, "base_rot": base_rot,
		})


func _build_leader() -> void:
	# Raised platform behind the crowd, facing the player.
	var plat := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.85
	cyl.bottom_radius = 0.95
	cyl.height = 0.5
	cyl.radial_segments = 32
	cyl.material = MarigoldFX.pbr(Color(0.40, 0.16, 0.22), 0.2, 0.5)
	plat.mesh = cyl
	plat.position = Vector3(0, STAGE_TOP_Y + 0.25, -4.7)
	_world.add_child(plat)
	var plat_trim := MeshInstance3D.new()
	var trim := TorusMesh.new()
	trim.inner_radius = 0.80
	trim.outer_radius = 0.90
	trim.rings = 40
	trim.ring_segments = 10
	trim.material = MarigoldFX.glow(Color(1.0, 0.55, 0.10), 1.5)
	plat_trim.mesh = trim
	plat_trim.position = Vector3(0, STAGE_TOP_Y + 0.5, -4.7)
	_world.add_child(plat_trim)

	var d := _make_skeleton(Color(1.0, 0.25, 0.20), 1.35, true)
	_leader = d["root"]
	_leader_body = d["body"]
	_leader_arm_l = d["arm_l"]
	_leader_arm_r = d["arm_r"]
	_leader.position = Vector3(0, STAGE_TOP_Y + 0.5, -4.7)
	_world.add_child(_leader)


func _build_labels() -> void:
	_label_move = MarigoldFX.make_label("El Gran Baile!", 84, Color(1.0, 0.75, 0.25))
	_label_move.position = Vector3(0, 3.15, -4.55)
	_world.add_child(_label_move)

	_label_hint = MarigoldFX.make_label("Follow the leader - copy the moves!", 48, Color(1, 1, 1))
	_label_hint.position = Vector3(0, 2.62, -4.55)
	_world.add_child(_label_hint)

	_label_score = MarigoldFX.make_label("Moves: 0/8", 56, Color(1.0, 0.85, 0.45))
	_label_score.position = Vector3(-2.7, 2.9, -2.9)
	_world.add_child(_label_score)

	# Progress ring: grows while a pose is held.
	_progress_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.20
	ring.rings = 40
	ring.ring_segments = 10
	_progress_mat = MarigoldFX.glow(Color(0.4, 1.0, 0.5), 2.0)
	ring.material = _progress_mat
	_progress_ring.mesh = ring
	_progress_ring.rotation_degrees.x = 90.0
	_progress_ring.position = Vector3(0, 2.18, -4.55)
	_progress_ring.visible = false
	_world.add_child(_progress_ring)


func _build_plaque() -> void:
	_plaque = MarigoldPlaques.place_plaque(
		_world,
		"El Gran Baile",
		"Dia de Muertos is a celebration of life - families gather with joy, music and dance to honor those they love. Love transcends death.",
		Vector3(3.1, 1.5, -1.4),
		1.8
	)


## ---- Skeleton builder (original festive designs) ----

func _make_skeleton(accent: Color, dancer_scale: float, is_leader: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "Celebrant"
	var bone := MarigoldFX.pbr(Color(0.93, 0.88, 0.76), 0.0, 0.55)
	var accent_m := MarigoldFX.pbr(accent, 0.1, 0.5)
	var eye_m := MarigoldFX.glow(Color(1.0, 0.60, 0.12), 2.4)

	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# Skull (slightly squashed sphere).
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.16
	skull_mesh.height = 0.30
	skull_mesh.material = bone
	skull.mesh = skull_mesh
	skull.scale = Vector3(1.0, 0.88, 0.95)
	skull.position = Vector3(0, 1.62, 0)
	body.add_child(skull)

	# Glowing marigold eyes.
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.035
		em.height = 0.07
		em.material = eye_m
		eye.mesh = em
		eye.position = Vector3(0.062 * sx, 1.64, 0.125)
		body.add_child(eye)

	# Jaw.
	var jaw := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(0.14, 0.07, 0.10)
	jm.material = bone
	jaw.mesh = jm
	jaw.position = Vector3(0, 1.50, 0.045)
	body.add_child(jaw)

	# Festive hat for the leader: wide brim + crown.
	if is_leader:
		var brim := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.36
		bm.bottom_radius = 0.36
		bm.height = 0.035
		bm.radial_segments = 32
		bm.material = accent_m
		brim.mesh = bm
		brim.position = Vector3(0, 1.80, 0)
		body.add_child(brim)
		var crown := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.15
		cm.height = 0.24
		cm.material = accent_m
		crown.mesh = cm
		crown.scale = Vector3(1.0, 0.85, 1.0)
		crown.position = Vector3(0, 1.90, 0)
		body.add_child(crown)

	# Marigold garland around the neck.
	for g in 8:
		var ga := TAU * float(g) / 8.0
		var bead := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.035
		gm.height = 0.07
		gm.material = MarigoldFX.glow(Color(1.0, 0.60, 0.10), 1.8) if g % 2 == 0 else accent_m
		bead.mesh = gm
		bead.position = Vector3(cos(ga) * 0.17, 1.47, sin(ga) * 0.17)
		body.add_child(bead)

	# Spine + ribcage (3 stacked torus ribs).
	var spine := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.045
	sm.bottom_radius = 0.05
	sm.height = 0.55
	sm.material = bone
	spine.mesh = sm
	spine.position = Vector3(0, 1.17, 0)
	body.add_child(spine)
	var rib_y := [1.36, 1.23, 1.10]
	var rib_r := [0.24, 0.21, 0.18]
	for r in 3:
		var rib := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rib_r[r] - 0.028
		tm.outer_radius = rib_r[r] + 0.028
		tm.rings = 24
		tm.ring_segments = 8
		tm.material = bone
		rib.mesh = tm
		rib.position = Vector3(0, rib_y[r], 0)
		body.add_child(rib)

	# Poncho (festive cone over the shoulders).
	var poncho := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.17
	pm.bottom_radius = 0.36
	pm.height = 0.26
	pm.radial_segments = 24
	pm.material = accent_m
	poncho.mesh = pm
	poncho.position = Vector3(0, 1.40, 0)
	body.add_child(poncho)

	# Pelvis.
	var pelvis := MeshInstance3D.new()
	var plm := SphereMesh.new()
	plm.radius = 0.14
	plm.height = 0.22
	plm.material = bone
	pelvis.mesh = plm
	pelvis.scale = Vector3(1.2, 0.7, 0.9)
	pelvis.position = Vector3(0, 0.92, 0)
	body.add_child(pelvis)

	# Arms: shoulder pivots so poses can be animated.
	var arm_l := Node3D.new()
	arm_l.name = "ArmL"
	arm_l.position = Vector3(-0.30, 1.44, 0)
	body.add_child(arm_l)
	var arm_r := Node3D.new()
	arm_r.name = "ArmR"
	arm_r.position = Vector3(0.30, 1.44, 0)
	body.add_child(arm_r)
	for piv in [arm_l, arm_r]:
		var upper := MeshInstance3D.new()
		var um := BoxMesh.new()
		um.size = Vector3(0.09, 0.34, 0.09)
		um.material = bone
		upper.mesh = um
		upper.position = Vector3(0, -0.17, 0)
		piv.add_child(upper)
		var hand := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.06
		hm.height = 0.12
		hm.material = accent_m
		hand.mesh = hm
		hand.position = Vector3(0, -0.38, 0)
		piv.add_child(hand)

	# Legs: hip pivots with feet.
	for sx in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.13 * sx, 0.90, 0)
		body.add_child(hip)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.78, 0.12)
		lm.material = bone
		leg.mesh = lm
		leg.position = Vector3(0, -0.41, 0)
		hip.add_child(leg)
		var foot := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.12, 0.07, 0.22)
		fm.material = accent_m
		foot.mesh = fm
		foot.position = Vector3(0, -0.80, 0.05)
		hip.add_child(foot)

	root.scale = Vector3.ONE * dancer_scale
	return {"root": root, "body": body, "arm_l": arm_l, "arm_r": arm_r}


## ---- Game flow ----

func _process(delta: float) -> void:
	if not _built or _world == null:
		return
	_t += delta
	_phase_t += delta
	if _cheer_t > 0.0:
		_cheer_t -= delta

	_update_dancers(delta)
	_update_leader(delta)
	_update_candles()

	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)

	match _phase:
		"intro":
			if _phase_t >= 4.0:
				_start_move(0)
		"demo":
			if _phase_t >= DEMO_TIME:
				_begin_do()
		"do":
			_update_do(delta)
		"cheer":
			if _phase_t >= CHEER_TIME:
				_advance()
		"finale":
			_update_finale(delta)


func _start_move(i: int) -> void:
	_move_idx = i
	_phase = "demo"
	_phase_t = 0.0
	_hold_t = 0.0
	_prompt_t = 0.0
	_prompt_idx = 0
	_wave_hist.clear()
	var mv: Dictionary = MOVES[i]
	_leader_al_target = mv["al"]
	_leader_ar_target = mv["ar"]
	_leader_lean_target = mv["lean"]
	_label_move.text = mv["label"]
	_label_hint.text = "Watch the leader..."
	_progress_ring.visible = false


func _begin_do() -> void:
	_phase = "do"
	_phase_t = 0.0
	_hold_t = 0.0
	_prompt_t = 0.0
	_prompt_idx = 0
	_wave_hist.clear()
	_label_hint.text = "Your turn - hold the pose!"
	_progress_ring.visible = true


func _update_do(delta: float) -> void:
	_prompt_t += delta
	if _prompt_t >= 3.5:
		_prompt_t = 0.0
		_label_hint.text = GENTLE_PROMPTS[_prompt_idx % GENTLE_PROMPTS.size()]
		_prompt_idx += 1

	if _pose_matches(_move_idx):
		_hold_t += delta
		_label_hint.text = "Hold it..."
	else:
		_hold_t = 0.0

	var prog := clampf(_hold_t / HOLD_TIME, 0.0, 1.0)
	var s := 0.35 + prog * 0.9
	_progress_ring.scale = Vector3(s, s, s)
	MarigoldFX.pulse_glow(_progress_mat, 1.2, 1.2, _t, 6.0)

	# Track right-hand lateral motion for the wave move.
	if _move_idx == 2:
		var pr := MarigoldHands.pointer_position(self, MarigoldHands.HAND_RIGHT)
		_wave_hist.append(pr.x)
		if _wave_hist.size() > 48:
			_wave_hist.pop_front()

	if _hold_t >= HOLD_TIME:
		_move_success()
	elif _phase_t >= DO_TIME:
		_move_gentle_pass()


func _move_success() -> void:
	_moves_done += 1
	_update_score()
	_phase = "cheer"
	_phase_t = 0.0
	_cheer_t = CHEER_TIME
	_progress_ring.visible = false
	_label_move.text = "Increible!"
	_label_hint.text = "Beautiful dancing!"
	MarigoldFX.spawn_sparks(_world, _leader.global_position + Vector3(0, 2.2, 0), Color(1.0, 0.75, 0.2), 36)


func _move_gentle_pass() -> void:
	# No fail state: celebrate the effort and keep the party moving.
	_moves_done += 1
	_update_score()
	_phase = "cheer"
	_phase_t = 0.0
	_cheer_t = CHEER_TIME
	_progress_ring.visible = false
	_label_move.text = "Muy bien!"
	_label_hint.text = "Next move!"
	MarigoldFX.scatter_petals(_world, _leader.global_position + Vector3(0, 1.8, 0), 24)


func _advance() -> void:
	if _move_idx + 1 >= MOVES.size():
		_start_finale()
	else:
		_start_move(_move_idx + 1)


func _update_score() -> void:
	_label_score.text = "Moves: %d/8" % _moves_done


func _start_finale() -> void:
	_phase = "finale"
	_phase_t = 0.0
	_finale_t = 0.0
	_volley = 0
	_progress_ring.visible = false
	_label_move.text = "El Gran Baile!"
	_label_hint.text = "What a celebration!"
	_label_score.text = "Moves: %d/8 - Felicidades!" % _moves_done
	# Everyone spins; the leader takes a bow.
	for d in _dancers:
		d["style"] = 2
		d["speed"] = _rng.randf_range(2.2, 3.0)
	_leader_al_target = Vector3(0.6, 0, -0.5)
	_leader_ar_target = Vector3(0.6, 0, 0.5)
	_leader_lean_target = Vector3(0.65, 0, 0)


func _update_finale(delta: float) -> void:
	_finale_t += delta
	while _volley < VOLLEY_COUNT and _finale_t >= 0.5 + float(_volley) * 1.1:
		_fire_volley(_volley)
		_volley += 1
	if _finale_t >= FINALE_TIME:
		_phase = "done"
		chapter_complete.emit()


func _fire_volley(v: int) -> void:
	for k in 3:
		var pos := Vector3(
			_rng.randf_range(-3.0, 3.0),
			_rng.randf_range(4.5, 6.5),
			-3.0 + _rng.randf_range(-2.5, 2.5)
		)
		MarigoldFX.scatter_petals(_world, pos, 40)
		MarigoldFX.spawn_confetti(_world, pos, 60)
	MarigoldFX.spawn_sparks(_world, _leader.global_position + Vector3(0, 2.4, 0), Color(1.0, 0.6, 0.15), 24)


## ---- Pose detection ----

func _hand_refs() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var cam_y := 1.6
	var cam_pos := Vector3(0, 1.6, 0)
	var fwd := Vector3(0, 0, -1)
	if cam != null:
		cam_y = cam.global_position.y
		cam_pos = cam.global_position
		fwd = -cam.global_transform.basis.z
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var pl := MarigoldHands.pointer_position(self, MarigoldHands.HAND_LEFT)
	var pr := MarigoldHands.pointer_position(self, MarigoldHands.HAND_RIGHT)
	var anchor := cam_pos + fwd * 1.2
	anchor.y = cam_pos.y
	return {
		"ly": pl.y, "ry": pr.y,
		"llat": (pl - anchor).dot(right), "rlat": (pr - anchor).dot(right),
		"dist": pl.distance_to(pr),
		"head": cam_y + 0.10, "chest": cam_y - 0.20, "waist": cam_y - 0.50,
	}


func _wave_range() -> float:
	if _wave_hist.size() < 8:
		return 0.0
	var mn: float = _wave_hist[0]
	var mx: float = _wave_hist[0]
	for x in _wave_hist:
		mn = minf(mn, x)
		mx = maxf(mx, x)
	return mx - mn


func _pose_matches(id: int) -> bool:
	var h := _hand_refs()
	match id:
		0: # Raise your left hand!
			return h["ly"] > h["head"]
		1: # Both hands up!
			return h["ly"] > h["head"] and h["ry"] > h["head"]
		2: # Wave hello!
			return h["ry"] > h["chest"] and _wave_range() > 0.30
		3: # Hands to your heart!
			return h["dist"] < 0.35 and absf((h["ly"] + h["ry"]) * 0.5 - h["chest"]) < 0.25
		4: # Sway left!
			return h["llat"] < -0.25 and h["rlat"] < -0.25
		5: # Sway right!
			return h["llat"] > 0.25 and h["rlat"] > 0.25
		6: # Clap above your head!
			return h["dist"] < 0.30 and h["ly"] > h["head"] and h["ry"] > h["head"]
		7: # Take a bow!
			return h["ly"] < h["waist"] and h["ry"] < h["waist"]
	return false


## ---- Animation ----

func _update_dancers(delta: float) -> void:
	for d in _dancers:
		var root: Node3D = d["root"]
		var t := _t * float(d["speed"]) + float(d["phase"])
		var hop := 0.0
		if _cheer_t > 0.0:
			hop = absf(sin(_t * 9.0)) * 0.18
		var style: int = d["style"]
		match style:
			0: # bounce
				root.position.y = float(d["base_y"]) + absf(sin(t)) * 0.12 + hop
				root.rotation.z = sin(t * 0.5) * 0.08
			1: # sway
				root.position.y = float(d["base_y"]) + absf(sin(t * 0.8)) * 0.06 + hop
				root.rotation.z = sin(t) * 0.18
				root.rotation.y = float(d["base_rot"]) + sin(t * 0.5) * 0.30
			_: # spin
				root.position.y = float(d["base_y"]) + absf(sin(t)) * 0.08 + hop
				root.rotation.y += delta * 1.6
		# Arm groove.
		var al: Node3D = d["arm_l"]
		var ar: Node3D = d["arm_r"]
		al.rotation.z = -0.5 - absf(sin(t)) * 0.5
		ar.rotation.z = 0.5 + absf(sin(t + 1.3)) * 0.5


func _update_leader(delta: float) -> void:
	if _leader == null:
		return
	var k := clampf(6.0 * delta, 0.0, 1.0)
	_leader_arm_l.rotation = _leader_arm_l.rotation.lerp(_leader_al_target, k)
	_leader_arm_r.rotation = _leader_arm_r.rotation.lerp(_leader_ar_target, k)
	_leader_body.rotation = _leader_body.rotation.lerp(_leader_lean_target, k)
	# Gentle bob.
	_leader.position.y = STAGE_TOP_Y + 0.5 + absf(sin(_t * 2.2)) * 0.05
	# Wave oscillation during the "Wave hello!" demo.
	if _move_idx == 2 and (_phase == "demo" or _phase == "do"):
		_leader_arm_r.rotation.z += sin(_t * 8.0) * 0.35


func _update_candles() -> void:
	for c in _candles:
		var n: Node3D = c["node"]
		n.position.y = float(c["base_y"]) + sin(_t * 2.0 + float(c["phase"])) * 0.05
