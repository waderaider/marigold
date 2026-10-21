## MarigoldBanda.gd - ambient skeleton street musicians (v0.6.0).
## Small calavera bands under market umbrellas (ch3/ch5 plaza edges).
## Each musician: make_dancer body + sombrero + folk instrument, driven by
## MarigoldCharacterRig (blink, look-at, expressions) + beat-synced
## instrument bobbing. Approaching (< 2.5 m) triggers a wave (lean + nod +
## JOY) and one short ORIGINAL musical phrase (KS plucks, not a song).
## Hard cap: 6 musicians total. LOD: beyond 4 m the rig skips gaze
## (featured system); instruments are 2-3 primitives each.
extends RefCounted
class_name MarigoldBanda

const INSTRUMENTS := ["guitarron", "trumpet", "violin"]


## Build one musician. Returns {"root","body","rig","instrument","phrase",
## "wave_t","greeted"}. Accent + instrument cycle by index.
static func make_musician(accent: Color, idx: int, seed: int = 0, opts: Dictionary = {}) -> Dictionary:
	var dancer_opts := {"ring": true, "pupils": true, "jaw": true, "seed": seed}
	for k in opts.keys():
		dancer_opts[k] = opts[k]
	var d := MarigoldCalavera.make_dancer(accent, 0.95, dancer_opts)
	var root: Node3D = d["root"]
	var body: Node3D = d["body"]
	var rig: MarigoldCharacterRig = d["rig"]
	if rig != null:
		# v0.7.0 P0: band pupils (shared meshes, ~6 transform writes each).
		# Musicians are the most-watched faces in the market scenes — lock
		# them featured so the crowd rule never hides their pupils.
		rig.featured_lock = true
	# Sombrero (wide brim + low crown). NOTE: body is scaled 2.64x, so these
	# are model-space coordinates (x2.64 in world).
	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.15
	bm.bottom_radius = 0.16
	bm.height = 0.015
	bm.radial_segments = 24
	brim.mesh = bm
	brim.material_override = MarigoldFX.pbr(Color(0.55, 0.32, 0.14), 0.0, 0.7)
	brim.position = Vector3(0, 0.70, 0)
	body.add_child(brim)
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.06
	cm.height = 0.09
	crown.mesh = cm
	crown.material_override = MarigoldFX.pbr(accent, 0.1, 0.5)
	crown.position = Vector3(0, 0.75, 0)
	body.add_child(crown)
	# Instrument (parented to root = world-ish space, 2-3 primitives each).
	var kind: String = INSTRUMENTS[idx % INSTRUMENTS.size()]
	var inst := _build_instrument(kind, accent)
	inst.position = Vector3(0.28, 1.02, 0.30)
	inst.rotation.z = -0.5
	root.add_child(inst)
	# Market umbrella: pole + canopy (shared by the chapter per band).
	return {"root": root, "body": body, "rig": rig, "instrument": inst,
		"kind": kind, "phrase": _phrase_for(kind), "wave_t": 0.0,
		"greet_cd": 0.0, "phase": float(idx) * 2.1, "energy": 0.0,
		"resp_cd": 0.0}


## v0.9.0: hero mariachi — rigged artist GLBs (UE5 ContentStaging wave)
## with baked "Play"/"Sway" clips, looped with a per-player phase offset.
## Kinds: guitar, maracas, trumpet, violin. Returns the model root or null.
static func make_mariachi(kind: String, phase: float = 0.0) -> Node3D:
	var model := MarigoldModels.artist_model("skeleton_mariachi_" + kind)
	if model == null:
		return null
	model.name = "Mariachi_" + kind
	for ap_node in model.find_children("", "AnimationPlayer", true, false):
		var ap := ap_node as AnimationPlayer
		for anim_name in ["Play", "Sway"]:
			if ap.has_animation(anim_name):
				ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		if ap.has_animation("Play"):
			ap.play("Play")
			ap.seek(fmod(phase, 4.0), true)
			ap.speed_scale = 0.95 + fmod(absf(phase) * 0.37, 0.1)
	return model


static func _build_instrument(kind: String, accent: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Instrument_" + kind
	var wood := MarigoldFX.pbr(Color(0.50, 0.26, 0.10), 0.1, 0.5)
	var brass := MarigoldFX.pbr(Color(0.85, 0.62, 0.25), 0.8, 0.35)
	match kind:
		"guitarron":
			var b := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.16
			bm.bottom_radius = 0.20
			bm.height = 0.10
			bm.radial_segments = 16
			b.mesh = bm
			b.material_override = wood
			b.rotation_degrees.x = 90.0
			root.add_child(b)
			var nk := MeshInstance3D.new()
			var nm := BoxMesh.new()
			nm.size = Vector3(0.05, 0.45, 0.05)
			nk.mesh = nm
			nk.material_override = wood
			nk.position = Vector3(0, 0.28, 0)
			root.add_child(nk)
		"trumpet":
			var bell := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.09
			cm.bottom_radius = 0.03
			cm.height = 0.22
			cm.radial_segments = 12
			bell.mesh = cm
			bell.material_override = brass
			bell.rotation_degrees.z = 90.0
			bell.position = Vector3(0.14, 0.30, 0)
			root.add_child(bell)
			var tube := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.025
			tm.bottom_radius = 0.025
			tm.height = 0.30
			tm.radial_segments = 10
			tube.mesh = tm
			tube.material_override = brass
			tube.rotation_degrees.z = 90.0
			root.add_child(tube)
		_: # violin
			var vb := MeshInstance3D.new()
			var vm := BoxMesh.new()
			vm.size = Vector3(0.16, 0.28, 0.07)
			vb.mesh = vm
			vb.material_override = wood
			root.add_child(vb)
			var vn := MeshInstance3D.new()
			var nm2 := BoxMesh.new()
			nm2.size = Vector3(0.04, 0.35, 0.04)
			vn.mesh = nm2
			vn.material_override = wood
			vn.position = Vector3(0, 0.30, 0)
			root.add_child(vn)
	return root


## Short ORIGINAL phrase per instrument (MIDI notes, folk-flavored).
static func _phrase_for(kind: String) -> Array:
	match kind:
		"guitarron":
			return [45, 52, 57, 52] # A2 E3 A3 E3
		"trumpet":
			return [69, 72, 76, 72] # A4 C5 E5 C5
		_:
			return [64, 67, 69, 67] # E4 G4 A4 G4
	return [60]


## Market umbrella over a band (one per band, not per musician).
static func make_umbrella(accent: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Umbrella"
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.03
	pm.height = 2.6
	pm.radial_segments = 10
	pole.mesh = pm
	pole.material_override = MarigoldFX.pbr(Color(0.35, 0.20, 0.10), 0.0, 0.7)
	pole.position = Vector3(0, 1.3, 0)
	root.add_child(pole)
	var can := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.35
	cm.height = 0.45
	cm.radial_segments = 16
	can.mesh = cm
	can.material_override = MarigoldFX.glow(accent, 0.7)
	can.position = Vector3(0, 2.75, 0)
	root.add_child(can)
	return root


## Play one musician's phrase (call-and-response / conducting / greeting).
## volume scales with the player's dance energy (louder when they move).
static func play_phrase(d: Dictionary, music: Object, volume: float = 0.55) -> void:
	var root: Node3D = d["root"]
	if root == null or not is_instance_valid(root):
		return
	if music == null or not (music as Object).has_method("pluck"):
		return
	var tree := root.get_tree()
	var phrase: Array = d["phrase"]
	for i in phrase.size():
		var note := int(phrase[i])
		var dl := float(i) * 0.22
		if tree != null:
			tree.create_timer(dl).timeout.connect(
				func() -> void:
					if music != null and is_instance_valid(root):
						(music as Object).call("pluck", note, volume, 0.9))
	var rig: MarigoldCharacterRig = d["rig"]
	if rig != null:
		rig.set_expression("JOY", 0.4)
		rig.set_speaking(true) # syllable fallback = musical mouthing
		if tree != null:
			tree.create_timer(0.22 * float(phrase.size()) + 0.3).timeout.connect(
				func() -> void:
					if rig != null:
						rig.set_speaking(false)
						rig.clear_expression())


## Per-frame: beat-synced bob + approach wave + greeting phrase +
## v0.7.0 tempo-follow (the band locks to YOUR energy) + call-and-response.
## ctx: default_ctx + "beat_phase". music: MarigoldMusic (for phrases).
static func update_musician(d: Dictionary, delta: float, ctx: Dictionary, music: Object) -> void:
	var root: Node3D = d["root"]
	if root == null or not is_instance_valid(root):
		return
	var rig: MarigoldCharacterRig = d["rig"]
	var t: float = float(ctx.get("t", 0.0))
	var beat: float = float(ctx.get("beat_phase", -1.0))
	var pulse := 0.5 + 0.5 * sin(t * 2.2 + float(d.get("phase", 0.0)))
	if beat >= 0.0:
		pulse = pow(1.0 - beat, 2.0)
	# v0.7.0 tempo-follow: player hand speed = dance/strum energy. The
	# band's groove amplitude follows it (bigger moves, bigger band).
	var energy := 0.0
	for h in [MarigoldHands.HAND_RIGHT, MarigoldHands.HAND_LEFT]:
		energy = maxf(energy, MarigoldHands.grab_speed(root, h))
	energy = clampf(energy / 3.0, 0.0, 1.0)
	d["energy"] = lerpf(float(d.get("energy", 0.0)), energy,
		clampf(3.0 * delta, 0.0, 1.0))
	var groove := 0.7 + 0.6 * float(d["energy"])
	# Beat-synced instrument bob (amplitude rides the player's energy).
	var inst: Node3D = d["instrument"]
	if inst != null and is_instance_valid(inst):
		inst.rotation.x = sin(t * 4.4 + float(d.get("phase", 0.0))) * 0.12 * (0.4 + pulse) * groove
		inst.position.y = 1.02 + pulse * 0.05 * groove
	root.position.y = float(d.get("base_y", 0.0)) + pulse * 0.04 * groove
	# Call-and-response: when the player really moves (energy spike), the
	# band answers with its phrase — louder with dance energy (6 s cd).
	d["resp_cd"] = maxf(0.0, float(d.get("resp_cd", 0.0)) - delta)
	if energy > 0.62 and float(d.get("resp_cd", 0.0)) <= 0.0:
		d["resp_cd"] = 6.0
		play_phrase(d, music, 0.55 + 0.35 * energy)
		MarigoldPhotos.note_moment("band_response")
	# Approach: wave + greeting phrase (cooldown 20 s).
	d["greet_cd"] = maxf(0.0, float(d.get("greet_cd", 0.0)) - delta)
	var pp: Variant = ctx.get("player_pos", null)
	if pp is Vector3 and float(d.get("greet_cd", 0.0)) <= 0.0:
		if root.global_position.distance_to(pp) < 2.5:
			d["greet_cd"] = 20.0
			d["wave_t"] = 1.6
			play_phrase(d, music, 0.55)
			MarigoldPhotos.note_moment("band_phrase")
	# Wave: lean + nod while wave_t runs, then settle.
	var wt: float = float(d.get("wave_t", 0.0))
	if wt > 0.0:
		d["wave_t"] = wt - delta
		var wk := sin(minf(1.0, (1.6 - wt) / 1.6) * PI)
		root.rotation.z = wk * 0.18
		if rig != null and wt - delta <= 0.0:
			rig.set_speaking(false)
			rig.clear_expression()
