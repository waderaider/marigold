## guitarra.gd - MARIGOLD experience: Guitarra Mexicana.
## A rhythm-strum + free-play Mexican folk-style guitar game.
## Plaza setting, lantern light, papel picado. ALL music is an original
## folk-inspired waltz composed for this game (see SONG below) - no
## copyrighted or traditional songs are used anywhere.
## Chapter contract: setup(ar_mode), apply_mode(on), signal chapter_complete.
## No class_name (experience contract). Headless-safe.
extends Node3D

signal chapter_complete

# Original 3/4 waltz in A major, 100 BPM (beat = 0.6s), 16 bars.
# Composed for Guitarra Mexicana - original melody, mariachi-flavored changes.
const BEAT := 0.6
const BAR := 1.8
const LEAD_TIME := 2.2 # seconds a note is visible before its hit time
const PERFECT_WINDOW := 0.12
const GOOD_WINDOW := 0.25
const STRUM_Y := 1.15
const NOTE_TOP_Y := 3.3

# Per bar: bass root + chord tones (backing) + 3-beat original melody.
# Chords: A . A . D . D | A . A . E7 . E7 | A . A . D . Bm | A . E7 . A(hold) . A
const BARS := [
	{"root": 45, "chord": [57, 61, 64], "melody": [76, 73, 69]},
	{"root": 45, "chord": [57, 61, 64], "melody": [71, 73, 74]},
	{"root": 50, "chord": [57, 62, 66], "melody": [76, 78, 76]},
	{"root": 50, "chord": [57, 62, 66], "melody": [74, 73, 71]},
	{"root": 45, "chord": [57, 61, 64], "melody": [69, 71, 73]},
	{"root": 45, "chord": [57, 61, 64], "melody": [74, 76, 78]},
	{"root": 40, "chord": [56, 59, 64], "melody": [80, 78, 76]},
	{"root": 40, "chord": [56, 59, 64], "melody": [76, 74, 71]},
	{"root": 45, "chord": [57, 61, 64], "melody": [69, 73, 76]},
	{"root": 45, "chord": [57, 61, 64], "melody": [78, 76, 74]},
	{"root": 50, "chord": [57, 62, 66], "melody": [76, 74, 73]},
	{"root": 47, "chord": [59, 62, 66], "melody": [74, 73, 71]},
	{"root": 45, "chord": [57, 61, 64], "melody": [73, 71, 69]},
	{"root": 40, "chord": [56, 59, 64], "melody": [71, 68, 64]},
	{"root": 45, "chord": [57, 61, 64], "melody": [69, -1, -1]},
	{"root": 45, "chord": [57, 61, 64], "melody": [69, -1, -1]},
]

const STRING_MIDIS := [40, 45, 50, 55, 59, 64] # E2 A2 D3 G3 B3 E4
const STRING_NAMES := ["E", "A", "D", "G", "B", "E"]

enum Phase { SELECT, COUNTDOWN, PLAYING, RESULTS, FREE }

var _phase: int = Phase.SELECT
var _ar_mode := false
var _t := 0.0

var _ground_group: Node3D
var _dressing: Node3D
var _guitar: Node3D
var _string_x: Array = []
var _strum_bar: MeshInstance3D

var _score_label: Label3D
var _judge_label: Label3D
var _hint_label: Label3D
var _judge_t := 0.0

var _mode_orbs: Array = [] # {node, mode, label}
var _exit_arch: Node3D
var _exit_hold := 0.0

var _notes: Array = [] # {time, midi, node, hit, missed}
var _backing: Array = [] # {time, midi, vol, played}
var _song_time := 0.0
var _song_len := 0.0
var _countdown := 0.0
var _score := 0
var _combo := 0
var _max_combo := 0
var _hits := 0
var _perfects := 0

var _prev_swipe_x := 0.0
var _has_prev_swipe := false


func _ready() -> void:
	_build_plaza()
	_build_guitar()
	_build_mode_select()
	_build_ui()
	MarigoldPlaques.place_plaque(
		self, "Guitarra Mexicana",
		"An original folk-style waltz for nylon-string guitar, composed for this plaza. Strum in time with the falling marigold notes - or pick Free Play and make your own melody.",
		Vector3(-2.2, 1.5, 0.6), 1.9)


func setup(ar_mode: bool) -> void:
	_ar_mode = ar_mode
	apply_mode(ar_mode)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _ground_group:
		_ground_group.visible = not on
	if _dressing:
		_dressing.visible = not on


func _process(delta: float) -> void:
	_t += delta
	if _judge_t > 0.0:
		_judge_t -= delta
		if _judge_t <= 0.0 and _judge_label:
			_judge_label.visible = false
	match _phase:
		Phase.SELECT:
			_update_mode_select()
		Phase.COUNTDOWN:
			_update_countdown(delta)
		Phase.PLAYING:
			_update_playing(delta)
		Phase.RESULTS:
			_update_mode_select() # reuse orb-pinch logic for Play Again / Menu
		Phase.FREE:
			_update_free(delta)


## ---- plaza ----

func _build_plaza() -> void:
	_ground_group = Node3D.new()
	_ground_group.name = "PlazaGround"
	add_child(_ground_group)

	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.4
	disc.height = 0.12
	disc.radial_segments = 40
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = disc
	disc_mi.material_override = MarigoldFX.pbr(Color(0.30, 0.16, 0.10), 0.0, 0.8)
	disc_mi.position = Vector3(0, -0.06, -1.0)
	_ground_group.add_child(disc_mi)

	MarigoldModels.make_flower_field(_ground_group, 160, 8.5, 4242)
	MarigoldFX.spawn_ambient_motes(self, Vector3(0, 1.8, -1.0), 4.5, 50)

	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)

	# Papel picado canopy overhead.
	var cols := [Color(1.0, 0.30, 0.55), Color(1.0, 0.62, 0.12), Color(0.35, 0.75, 1.0), Color(0.65, 0.35, 1.0)]
	for i in 4:
		var b := MarigoldFX.make_papel_banner(_dressing, 3.2, 1.1, cols[i % cols.size()])
		b.position = Vector3(-2.4 + i * 1.6, 3.6, -1.6 - (i % 2) * 0.8)
		b.rotation.y = 0.15 if i % 2 == 0 else -0.15

	# Lantern posts with warm light.
	for i in 4:
		var a := i * PI / 2.0 + PI / 4.0
		var px := cos(a) * 3.4
		var pz := -1.0 + sin(a) * 3.4
		var post := MarigoldFX.make_candle(_dressing, Vector3(px, 0.0, pz), true, 1.1)
		post.scale = Vector3(1.6, 2.2, 1.6)
		MarigoldFX.make_point_light(_dressing, Vector3(px, 2.4, pz), Color(1.0, 0.62, 0.25), 1.2, 6.0)

	MarigoldFX.make_point_light(self, Vector3(0, 2.2, -0.6), Color(1.0, 0.72, 0.38), 1.0, 5.0)
	MarigoldFX.make_light_rig(self, 0.7)


## ---- guitar ----

func _build_guitar() -> void:
	var root := Node3D.new()
	root.name = "Guitar"
	root.position = Vector3(0, 0, -1.9)
	add_child(root)

	var wood := MarigoldFX.pbr(Color(0.48, 0.22, 0.09), 0.1, 0.45)
	var wood_light := MarigoldFX.pbr(Color(0.74, 0.47, 0.22), 0.1, 0.5)

	var body := CylinderMesh.new()
	body.top_radius = 0.44
	body.bottom_radius = 0.48
	body.height = 0.18
	body.radial_segments = 28
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body
	body_mi.material_override = wood
	body_mi.rotation_degrees.x = 90.0
	body_mi.position = Vector3(0, 0.72, 0)
	root.add_child(body_mi)

	var hole := CylinderMesh.new()
	hole.top_radius = 0.12
	hole.bottom_radius = 0.12
	hole.height = 0.02
	var hole_mi := MeshInstance3D.new()
	hole_mi.mesh = hole
	hole_mi.material_override = MarigoldFX.pbr(Color(0.02, 0.01, 0.01), 0.0, 1.0)
	hole_mi.rotation_degrees.x = 90.0
	hole_mi.position = Vector3(0, 0.72, 0.10)
	root.add_child(hole_mi)

	# Rosette ring around the sound hole.
	var ros := TorusMesh.new()
	ros.inner_radius = 0.13
	ros.outer_radius = 0.17
	var ros_mi := MeshInstance3D.new()
	ros_mi.mesh = ros
	ros_mi.material_override = MarigoldFX.glow(Color(1.0, 0.62, 0.15), 1.4)
	ros_mi.position = Vector3(0, 0.72, 0.10)
	root.add_child(ros_mi)

	var neck := BoxMesh.new()
	neck.size = Vector3(0.14, 1.7, 0.08)
	var neck_mi := MeshInstance3D.new()
	neck_mi.mesh = neck
	neck_mi.material_override = wood_light
	neck_mi.position = Vector3(0, 1.85, 0)
	root.add_child(neck_mi)

	var head := BoxMesh.new()
	head.size = Vector3(0.18, 0.34, 0.07)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.material_override = wood
	head_mi.position = Vector3(0, 2.85, 0)
	root.add_child(head_mi)

	for f in 6:
		var fret := BoxMesh.new()
		fret.size = Vector3(0.15, 0.012, 0.085)
		var fmi := MeshInstance3D.new()
		fmi.mesh = fret
		fmi.material_override = MarigoldFX.glow(Color(0.9, 0.75, 0.45), 0.8)
		fmi.position = Vector3(0, 1.25 + f * 0.22, 0)
		root.add_child(fmi)

	var string_mat := MarigoldFX.glow(Color(1.0, 0.90, 0.60), 1.8)
	_string_x.clear()
	for i in 6:
		var sx := -0.075 + i * 0.03
		_string_x.append(sx)
		var s := CylinderMesh.new()
		s.top_radius = 0.005
		s.bottom_radius = 0.005
		s.height = 2.3
		s.radial_segments = 6
		var smi := MeshInstance3D.new()
		smi.mesh = s
		smi.material_override = string_mat
		smi.position = Vector3(sx, 1.62, 0.11)
		root.add_child(smi)

	# Strum bar: the timing line notes fall onto.
	var bar := BoxMesh.new()
	bar.size = Vector3(0.55, 0.05, 0.06)
	_strum_bar = MeshInstance3D.new()
	_strum_bar.mesh = bar
	_strum_bar.material_override = MarigoldFX.glow(Color(1.0, 0.45, 0.10), 2.2)
	_strum_bar.position = Vector3(0, STRUM_Y, 0.11)
	root.add_child(_strum_bar)

	var title := MarigoldFX.make_label("Guitarra Mexicana", 64, Color(1.0, 0.80, 0.40))
	title.position = Vector3(0, 3.35, 0)
	root.add_child(title)

	_guitar = root


## ---- mode select / results orbs ----

func _clear_orbs() -> void:
	for o in _mode_orbs:
		var n: Node = o["node"]
		if is_instance_valid(n):
			n.queue_free()
	_mode_orbs.clear()


func _add_orb(pos: Vector3, color: Color, label_text: String, mode: String) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	orb.mesh = sm
	orb.material_override = MarigoldFX.glow(color, 2.0)
	orb.position = pos
	add_child(orb)
	var lab := MarigoldFX.make_label(label_text, 44, Color(1, 1, 1))
	lab.position = pos + Vector3(0, 0.42, 0)
	add_child(lab)
	orb.set_meta("label_node", lab)
	_mode_orbs.append({"node": orb, "mode": mode, "label": lab})


func _build_mode_select() -> void:
	_clear_orbs()
	_add_orb(Vector3(-1.3, 1.5, -1.1), Color(1.0, 0.55, 0.12), "Rhythm", "rhythm")
	_add_orb(Vector3(1.3, 1.5, -1.1), Color(0.35, 0.75, 1.0), "Free Play", "free")
	if _hint_label == null:
		_hint_label = MarigoldFX.make_label("Pinch an orb to choose", 44, Color(0.95, 0.90, 0.80))
		_hint_label.position = Vector3(0, 2.35, -0.9)
		add_child(_hint_label)
	else:
		_hint_label.text = "Pinch an orb to choose"
		_hint_label.visible = true


func _show_results_orbs() -> void:
	_clear_orbs()
	_add_orb(Vector3(-1.3, 1.5, -1.1), Color(1.0, 0.55, 0.12), "Play Again", "rhythm")
	_add_orb(Vector3(1.3, 1.5, -1.1), Color(0.75, 0.45, 1.0), "Back to Menu", "exit")
	_hint_label.text = "Pinch an orb"
	_hint_label.visible = true


func _update_mode_select() -> void:
	for hand in [MarigoldHands.HAND_LEFT, MarigoldHands.HAND_RIGHT]:
		if not MarigoldHands.pinch_just_pressed(self, hand):
			continue
		var hp := _hand_point(hand)
		for o in _mode_orbs:
			var n: Node3D = o["node"]
			if is_instance_valid(n) and hp.distance_to(n.global_position) < 0.45:
				_on_orb_chosen(String(o["mode"]))
				return


func _on_orb_chosen(mode: String) -> void:
	_clear_orbs()
	if _hint_label:
		_hint_label.visible = false
	match mode:
		"rhythm":
			_start_rhythm()
		"free":
			_start_free()
		"exit":
			chapter_complete.emit()


## ---- rhythm mode ----

func _start_rhythm() -> void:
	_notes.clear()
	_backing.clear()
	for bi in BARS.size():
		var bar: Dictionary = BARS[bi]
		var t0 := bi * BAR
		for j in 3:
			var mel: Array = bar["melody"]
			var midi: int = mel[j]
			if midi > 0:
				_notes.append({"time": t0 + j * BEAT, "midi": midi, "node": null, "hit": false, "missed": false, "spawned": false})
		_backing.append({"time": t0, "midi": int(bar["root"]), "vol": 0.35, "played": false})
		var chord: Array = bar["chord"]
		for j in [1, 2]:
			for cm in chord:
				_backing.append({"time": t0 + j * BEAT, "midi": int(cm), "vol": 0.20, "played": false})
	_song_len = BARS.size() * BAR + 1.5
	_song_time = 0.0
	_score = 0
	_combo = 0
	_max_combo = 0
	_hits = 0
	_perfects = 0
	_countdown = 2.4
	_phase = Phase.COUNTDOWN
	_set_judge("Get ready...", Color(1.0, 0.85, 0.5))


func _update_countdown(delta: float) -> void:
	_countdown -= delta
	var n := int(ceil(_countdown / 0.8))
	if _countdown > 0.0:
		_set_judge(str(n), Color(1.0, 0.75, 0.3))
	else:
		_phase = Phase.PLAYING
		_set_judge("Strum!", Color(0.5, 1.0, 0.5))


func _update_playing(delta: float) -> void:
	_song_time += delta
	# Backing track.
	for b in _backing:
		if not b["played"] and _song_time >= b["time"]:
			b["played"] = true
			if MarigoldState.music:
				MarigoldState.music.pluck(int(b["midi"]), float(b["vol"]), 1.6)
	# Spawn + move notes.
	for nt in _notes:
		if not nt["spawned"] and _song_time >= nt["time"] - LEAD_TIME:
			nt["spawned"] = true
			nt["node"] = _spawn_note()
		if nt["spawned"] and not nt["hit"] and not nt["missed"]:
			var n3d: Node3D = nt["node"]
			if is_instance_valid(n3d):
				var remain: float = nt["time"] - _song_time
				var y := STRUM_Y + (NOTE_TOP_Y - STRUM_Y) * clampf(remain / LEAD_TIME, 0.0, 1.0)
				n3d.position = Vector3(0, y, -1.79)
				if remain < -GOOD_WINDOW:
					nt["missed"] = true
					_combo = 0
					_set_judge("Miss", Color(1.0, 0.35, 0.35))
					n3d.queue_free()
					# Keep the music going: ghost-play the missed note softly.
					if MarigoldState.music:
						MarigoldState.music.pluck(int(nt["midi"]), 0.22, 1.2)
	# Strum input: swipe or pinch.
	if _detect_swipe() or MarigoldHands.pinch_just_pressed(self, MarigoldHands.HAND_RIGHT) \
			or MarigoldHands.pinch_just_pressed(self, MarigoldHands.HAND_LEFT):
		_on_strum()
	# Song end.
	if _song_time >= _song_len and _all_notes_judged():
		_finish_rhythm()


func _spawn_note() -> Node3D:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	n.mesh = sm
	n.material_override = MarigoldFX.glow(Color(1.0, 0.62, 0.12), 2.4)
	n.position = Vector3(0, NOTE_TOP_Y, -1.79)
	add_child(n)
	return n


func _on_strum() -> void:
	# Hit the nearest unjudged note inside the timing window.
	var best: Dictionary = {}
	var best_dt := GOOD_WINDOW + 0.001
	for nt in _notes:
		if nt["hit"] or nt["missed"]:
			continue
		var dt: float = absf(_song_time - float(nt["time"]))
		if dt < best_dt:
			best_dt = dt
			best = nt
	if best.is_empty():
		return # empty strum: forgiving, no penalty
	best["hit"] = true
	_hits += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	var node: Node3D = best["node"]
	if is_instance_valid(node):
		node.queue_free()
	if MarigoldState.music:
		MarigoldState.music.pluck(int(best["midi"]), 0.9, 1.4)
	MarigoldFX.spawn_sparks(self, Vector3(0, STRUM_Y, -1.7), Color(1.0, 0.80, 0.30), 14)
	if best_dt <= PERFECT_WINDOW:
		_perfects += 1
		_score += 300
		_set_judge("Perfect!", Color(1.0, 0.85, 0.30))
	else:
		_score += 100
		_set_judge("Good", Color(0.55, 0.95, 0.55))
	_update_score_label()


func _all_notes_judged() -> bool:
	for nt in _notes:
		if not nt["hit"] and not nt["missed"]:
			return false
	return true


func _finish_rhythm() -> void:
	_phase = Phase.RESULTS
	var total := _notes.size()
	var acc := 100.0 * _hits / maxf(1.0, float(total))
	_score_label.text = "Score %d\nAccuracy %d%%\nBest combo %d" % [_score, int(acc), _max_combo]
	_set_judge("Bravo!", Color(1.0, 0.80, 0.35))
	MarigoldFX.spawn_confetti(self, Vector3(0, 2.2, -1.4), 60)
	_show_results_orbs()


## ---- free play ----

func _start_free() -> void:
	_phase = Phase.FREE
	_exit_hold = 0.0
	_build_exit_arch()
	_set_judge("Strum the strings - pinch the arch to leave", Color(0.95, 0.90, 0.80))


func _build_exit_arch() -> void:
	_exit_arch = Node3D.new()
	_exit_arch.name = "ExitArch"
	_exit_arch.position = Vector3(2.1, 0, -0.4)
	add_child(_exit_arch)
	for sx in [-0.35, 0.35]:
		var post := CylinderMesh.new()
		post.top_radius = 0.05
		post.bottom_radius = 0.05
		post.height = 2.2
		var pmi := MeshInstance3D.new()
		pmi.mesh = post
		pmi.material_override = MarigoldFX.glow(Color(0.75, 0.45, 1.0), 1.6)
		pmi.position = Vector3(sx, 1.1, 0)
		_exit_arch.add_child(pmi)
	var lab := MarigoldFX.make_label("Salir", 52, Color(0.95, 0.85, 1.0))
	lab.position = Vector3(0, 2.5, 0)
	_exit_arch.add_child(lab)


func _update_free(delta: float) -> void:
	_update_strum_strings()
	# Pinch-and-hold inside the arch to leave.
	var inside := false
	for hand in [MarigoldHands.HAND_LEFT, MarigoldHands.HAND_RIGHT]:
		if MarigoldHands.pinch_active(self, hand):
			var hp := _hand_point(hand)
			if is_instance_valid(_exit_arch) and hp.distance_to(_exit_arch.global_position + Vector3(0, 1.3, 0)) < 0.6:
				inside = true
	if inside:
		_exit_hold += delta
		if _exit_hold > 0.6:
			chapter_complete.emit()
	else:
		_exit_hold = 0.0


func _update_strum_strings() -> void:
	if _guitar == null:
		return
	var ppos := _hand_point(MarigoldHands.HAND_RIGHT)
	var local: Vector3 = _guitar.to_local(ppos)
	if not _has_prev_swipe:
		_prev_swipe_x = local.x
		_has_prev_swipe = true
		return
	var in_zone := local.y > 0.40 and local.y < 2.60 and absf(local.z) < 0.55
	if in_zone:
		for i in 6:
			var sx: float = _string_x[i]
			var crossed := (_prev_swipe_x < sx) != (local.x < sx)
			if crossed:
				_pluck_string(i, local)
	_prev_swipe_x = local.x


func _pluck_string(i: int, local: Vector3) -> void:
	if MarigoldState.music != null:
		MarigoldState.music.pluck(int(STRING_MIDIS[i]), 0.85, 1.6)
	var hit: Vector3 = _guitar.to_global(Vector3(float(_string_x[i]), clampf(local.y, 0.5, 2.5), 0.15))
	MarigoldFX.spawn_sparks(self, hit, Color(1.0, 0.85, 0.40), 8)
	_set_judge(STRING_NAMES[i], Color(1.0, 0.90, 0.60))


## ---- rhythm-mode swipe detection ----

func _detect_swipe() -> bool:
	if _guitar == null:
		return false
	var ppos := _hand_point(MarigoldHands.HAND_RIGHT)
	var local: Vector3 = _guitar.to_local(ppos)
	if not _has_prev_swipe:
		_prev_swipe_x = local.x
		_has_prev_swipe = true
		return false
	var in_zone := local.y > 0.55 and local.y < 1.85 and absf(local.z) < 0.60
	var swiped := false
	if in_zone:
		# A decisive horizontal sweep across the strings counts as one strum.
		if absf(local.x - _prev_swipe_x) > 0.12:
			swiped = true
	_prev_swipe_x = local.x
	return swiped


## ---- UI helpers ----

func _build_ui() -> void:
	_score_label = MarigoldFX.make_label("", 52, Color(1.0, 0.88, 0.55))
	_score_label.position = Vector3(0, 3.0, -1.2)
	add_child(_score_label)
	_judge_label = MarigoldFX.make_label("", 60, Color(1, 1, 1))
	_judge_label.position = Vector3(0, 2.55, -1.2)
	_judge_label.visible = false
	add_child(_judge_label)
	_update_score_label()


func _update_score_label() -> void:
	if _phase == Phase.PLAYING or _phase == Phase.COUNTDOWN:
		_score_label.text = "Score %d   Combo %d" % [_score, _combo]


func _set_judge(text: String, color: Color) -> void:
	_judge_label.text = text
	_judge_label.modulate = color
	_judge_label.visible = true
	_judge_t = 1.4


func _hand_point(hand: int) -> Vector3:
	if MarigoldHands.is_xr_active():
		return MarigoldHands.pointer_position(self, hand)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + Vector3(0, 1.2, -1.6)
	var mp := get_viewport().get_mouse_position()
	return cam.project_ray_origin(mp) + cam.project_ray_normal(mp) * 1.6
