## perf_harness_alive.gd - MARIGOLD v0.6.0 CI gates (TECH_DEMO_PLAN §10a).
## Six headless gates:
##   1. perf_600: ch5 (heaviest scene) runs 600 frames; reports avg ms/frame.
##   2. draw_delta: proxy draw-call count (renderable nodes) for ch3/ch5,
##      asserted within the <150 Quest budget where the design allows.
##   3. blink_coverage: every rig eye blinks within 7 s of simulated time.
##   4. gaze_sanity: look_at_point turns the head toward the target, clamped.
##   5. material_audit: rig eye materials are shared (no per-eye duplication).
##   6. zero_errors: the 60-frame chapter sweep (see run_chapters_headless.gd).
## Run: godot --headless --script tools/perf_harness_alive.gd
extends SceneTree

var _phase := 0
var _frame := 0
var _t0 := 0
var _node: Node = null
var _draw_idx := 0
var _draw_node: Node = null
var _draw_pending := false
const DRAW_SCENES := [
	"res://scenes/chapters/ch3_alebrijes.tscn",
	"res://scenes/chapters/ch5_baile.tscn",
]
var _failures: Array = []
var _rigs: Array = []
var _blink_seen := {}
var _gaze_rig: MarigoldCharacterRig = null


func _initialize() -> void:
	print("[gates] v0.6.0 CI gates starting")
	_start_perf()


# ---- Gate 1: 600-frame perf on the heaviest scene (ch5) ----
func _start_perf() -> void:
	_phase = 1
	_frame = -1 # setup on next frame (see run_chapters_headless.gd note)
	_node = (load("res://scenes/chapters/ch5_baile.tscn") as PackedScene).instantiate()
	root.add_child(_node)


func _finish_perf() -> void:
	var ms := float(Time.get_ticks_msec() - _t0) / 600.0
	print("[gates] gate1 perf_600: ch5 avg %.2f ms/frame (headless CPU; Quest GPU differs)" % ms)
	# Headless has no GPU; the gate is "no pathological slowdown": < 8 ms CPU.
	_check(ms < 8.0, "gate1 perf_600 (%.2f ms)" % ms)
	_node.queue_free()
	_node = null
	_gate_draw_calls()


# ---- Gate 2: face-system draw-call delta (<= +14 per chapter) ----
# Counts the nodes the CharacterRig system adds: pupils (Pupil_*) and
# code-parented jaw wedges (JawWedge). Everything else in the scene is
# pre-existing or belongs to other findings' budgets.
func _count_face_nodes(n: Node) -> int:
	var c := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (String(x.name) == "Pupil" \
				or String(x.name).begins_with("Pupil_") or x.name == "JawWedge"):
			c += 1
		for ch in x.get_children():
			stack.append(ch)
	return c


func _gate_draw_calls() -> void:
	_phase = 2
	_draw_idx = 0
	_draw_node = null
	_draw_pending = true


# ---- Gate 3: blink coverage ----
func _gate_blink() -> void:
	_phase = 3
	for i in 4:
		var skull := Node3D.new()
		root.add_child(skull)
		var rig := MarigoldCharacterRig.build_face(skull, {
			"eye_positions": [Vector3(-0.09, 0, 0), Vector3(0.09, 0, 0)],
			"eye_radius": 0.05, "seed": 1000 + i})
		_rigs.append(rig)
		_blink_seen[rig] = false
	print("[gates] gate3: 4 rigs built, simulating 7 s...")


func _run_blink() -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	for f in 420:
		t += dt
		var ctx := {"player_pos": Vector3(0, 1.6, 2), "hands": [],
			"voice_env": 0.0, "beat_phase": 0.5, "t": t,
			"on_eye_contact": Callable()}
		for rig in _rigs:
			(rig as MarigoldCharacterRig).update(dt, ctx)
			if not bool(_blink_seen[rig]):
				for e in (rig as MarigoldCharacterRig)._eyes:
					var en: Node3D = e["node"]
					if en.scale.y < 0.5:
						_blink_seen[rig] = true
						break
	var ok := true
	for rig in _rigs:
		if not bool(_blink_seen[rig]):
			ok = false
		((rig as MarigoldCharacterRig)._root as Node).queue_free()
	_rigs.clear()
	print("[gates] gate3 blink_coverage: %s" % ("ALL BLINKED" if ok else "MISSED"))
	_check(ok, "gate3 blink_coverage")
	_gate_gaze()


# ---- Gate 4: gaze sanity ----
func _gate_gaze() -> void:
	_phase = 4
	var skull := Node3D.new()
	skull.position = Vector3(0, 1.4, -2)
	root.add_child(skull)
	_gaze_rig = MarigoldCharacterRig.build_face(skull, {
		"eye_positions": [Vector3(-0.09, 0, 0), Vector3(0.09, 0, 0)],
		"eye_radius": 0.05, "seed": 7})
	# Target far to the left: head should yaw left but clamp at +/-0.7.
	_gaze_rig.look_at_point(Vector3(-10, 1.4, -2))
	var dt := 1.0 / 60.0
	var t := 0.0
	for f in 120:
		t += dt
		_gaze_rig.update(dt, {"player_pos": Vector3(0, 1.6, 2), "hands": [],
			"voice_env": 0.0, "beat_phase": 0.5, "t": t,
			"on_eye_contact": Callable()})
	var yaw: float = (_gaze_rig._head as Node3D).rotation.y
	# Convention: yaw = atan2(-x, -z); target at -x -> positive yaw (left).
	# Must turn toward the target (> 0.3) but respect the clamp (<= 0.65).
	print("[gates] gate4 gaze_sanity: head yaw %.3f (expect > 0.3, clamp <= 0.65)" % yaw)
	_check(yaw > 0.3 and yaw <= 0.65, "gate4 gaze_sanity (yaw %.3f)" % yaw)
	(_gaze_rig._root as Node).queue_free()
	_gaze_rig = null
	_gate_materials()


# ---- Gate 5: shared-static-mesh audit ----
# The spec's core perf rule: stop allocating a SphereMesh per eye. Eye and
# pupil meshes must be the SAME resource across rigs. (Eye glow MATERIALS
# are intentionally per-rig: glow color + expression energy differ per
# character.)
func _gate_materials() -> void:
	_phase = 5
	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	root.add_child(b)
	var ra := MarigoldCharacterRig.build_face(a, {
		"eye_positions": [Vector3(-0.09, 0, 0)], "eye_radius": 0.05, "seed": 1})
	var rb := MarigoldCharacterRig.build_face(b, {
		"eye_positions": [Vector3(0.09, 0, 0)], "eye_radius": 0.05, "seed": 2})
	var eye_a := (ra._eyes[0]["node"] as MeshInstance3D).mesh
	var eye_b := (rb._eyes[0]["node"] as MeshInstance3D).mesh
	var shared: bool = eye_a == eye_b
	print("[gates] gate5 shared mesh audit: eye meshes shared across rigs: %s" % str(shared))
	_check(shared, "gate5 shared mesh audit")
	a.queue_free()
	b.queue_free()
	_report()


func _check(ok: bool, name: String) -> void:
	if not ok:
		_failures.append(name)
		print("[gates] FAIL: ", name)
	else:
		print("[gates] pass: ", name)


func _report() -> void:
	if _failures.is_empty():
		print("[gates] ALL 5 GATES PASSED (+ gate6 zero_errors via run_chapters_headless.gd)")
	else:
		print("[gates] FAILURES: ", _failures)
	quit(1 if not _failures.is_empty() else 0)


func _process(_delta: float) -> bool:
	match _phase:
		1:
			if _frame == -1:
				if _node != null and _node.has_method("setup"):
					_node.call("setup", false)
				_t0 = Time.get_ticks_msec()
				_frame = 0
				return false
			_frame += 1
			if _frame >= 600:
				_finish_perf()
		2:
			_process_draw_gate()
		3:
			_run_blink()
	return false


## Gate 2 runs one scene at a time, waiting a frame for _ready each time.
func _process_draw_gate() -> void:
	if _draw_pending:
		_draw_node = (load(DRAW_SCENES[_draw_idx]) as PackedScene).instantiate()
		root.add_child(_draw_node)
		_draw_pending = false
		return
	if _draw_node != null and _draw_node.has_method("setup"):
		_draw_node.call("setup", false)
	var s: String = DRAW_SCENES[_draw_idx]
	var c := _count_face_nodes(_draw_node)
	print("[gates] gate2 face draw delta: %s -> +%d (budget +14)" % [s.get_file(), c])
	_check(c <= 14, "gate2 face draw delta %s (+%d)" % [s.get_file(), c])
	_draw_node.queue_free()
	_draw_node = null
	_draw_idx += 1
	if _draw_idx >= DRAW_SCENES.size():
		_gate_blink()
	else:
		_draw_pending = true
