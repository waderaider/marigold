## ofrenda_finale.gd - MARIGOLD experience: Ofrenda Finale (v0.6.0, finding 8).
## The emotional payoff of the ofrenda-building progression: YOUR ofrenda in
## a candle-lit room, built from the memory objects collected across chapters
## (photo / pan de muerto / marigold / guitar pick). Collected items rest on
## the shelves; missing ones show as ghost silhouettes with a hint of where
## to find them. All four collected -> the reveal: candle ring brightens,
## papel glows, music swells, the family name appears in marigold light.
## No class_name (experience contract). Signal + setup/apply_mode contract.
extends Node3D

signal chapter_complete

const C_CREAM := Color(1.0, 0.93, 0.82)
const C_GOLD := Color(1.0, 0.80, 0.30)

var _ar_mode := false
var _t := 0.0
var _stage: Node3D
var _backdrop: Node3D
var _shelf: Node3D
var _candle_mats: Array = []
var _candle_flames: Array = [] # v0.7.0 VFX: flame positions for ignition FX
var _ring_roots: Array = [] # v0.9.0: CandleMelt registration roots
var _last_lit := -1 # v0.7.0 VFX: lit-candle count last frame
var _plaque: Node3D
var _stage_home := Vector3(0, 0, -0.2)
var _revealed := false
var _host: Dictionary = {} # v0.7.0: the bower calavera who acknowledges
var _grade_quads: Array = [] # per-memory-object warm rim glows


var _teleport: Dictionary = {} # v0.7.0 laser locomotion rig
var _vista: Node3D = null # v0.7.0 large-scale world vista
var _finale_dialogue_t := -1.0 # v0.7.0 Narrative: rosa_finale_enter timer
var _said_finale_enter := false


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	if MarigoldSky.instance != null:
		MarigoldSky.instance.set_time_mode("fixed")
		MarigoldSky.instance.set_time_of_day(21.0) # candle-lit night
		MarigoldSky.instance.set_weather("clear")

	# v0.7.0: large-scale world vista (wade's order) — mictlan night horizon.
	if not ar_mode:
		_vista = MarigoldVista.build(self, "mictlan", 55.0)

	# v0.7.0: laser-pointer teleport locomotion (wade's order) —
	# every chapter + experience.
	_teleport = MarigoldTeleport.laser_begin(self, self)

func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _backdrop != null:
		_backdrop.visible = not on
	if _stage == null:
		return
	if on:
		if not MarigoldHands.apply_anchor(_stage, "marigold_ofrenda_finale"):
			MarigoldHands.place_on_table(_stage)
			MarigoldHands.save_anchor("marigold_ofrenda_finale", _stage.global_transform)
	else:
		_stage.position = _stage_home
		_stage.rotation = Vector3.ZERO


func _process(delta: float) -> void:
	# v0.7.0 Narrative: finale entrance line.
	if _finale_dialogue_t > 0.0:
		_finale_dialogue_t -= delta
		if _finale_dialogue_t <= 0.0 and not _said_finale_enter:
			_said_finale_enter = true
			MarigoldDialogue.say("rosa_finale_enter")
	MarigoldTeleport.laser_update(self, _teleport, delta)
	_t += delta
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)
	# v0.7.0: the face-system central driver (the bower calavera host).
	MarigoldCharacterRig.update_all(delta, MarigoldCharacterRig.default_ctx(self))
	_update_candle_progress()
	_update_host(delta)
	# The reveal, once, when the altar is complete.
	if not _revealed and MarigoldOfrenda.is_complete():
		_reveal()


func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.position = _stage_home
	add_child(_stage)
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.position = _stage_home
	add_child(_backdrop)
	# Dark room: floor + back wall (the room reads via candlelight).
	var floor_mi := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(16, 16)
	floor_mi.mesh = fm
	# v0.9.0: ambientCG Tiles144 PBR (UE5 wave) on the finale floor.
	floor_mi.material_override = MarigoldFX.pbr_tex(
		"res://assets/textures/ambientcg/Tiles144/Tiles144_1K-JPG_Color.jpg",
		Color(0.35, 0.22, 0.26), 6.0, 0.9,
		"res://assets/textures/ambientcg/Tiles144/Tiles144_1K-JPG_NormalGL.jpg",
		"res://assets/textures/ambientcg/Tiles144/Tiles144_1K-JPG_Roughness.jpg")
	floor_mi.position = Vector3(0, 0, -2.0)
	_backdrop.add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(14, 5, 0.2)
	wall.mesh = wm
	# v0.9.0: ambientCG Plaster001 PBR on the back wall.
	wall.material_override = MarigoldFX.pbr_tex(
		"res://assets/textures/ambientcg/Plaster001/Plaster001_1K-JPG_Color.jpg",
		Color(0.38, 0.20, 0.28), 4.0, 0.95,
		"res://assets/textures/ambientcg/Plaster001/Plaster001_1K-JPG_NormalGL.jpg",
		"res://assets/textures/ambientcg/Plaster001/Plaster001_1K-JPG_Roughness.jpg")
	wall.position = Vector3(0, 2.5, -4.6)
	_backdrop.add_child(wall)
	# The player's ofrenda, full size, centered.
	_shelf = MarigoldOfrenda.make_shelf()
	_shelf.position = Vector3(0, 0, -3.0)
	_stage.add_child(_shelf)
	_build_candle_ring()
	_build_papel_frame()
	_build_host()
	_build_wave_dressing()
	_grade_memory_objects()
	var title := MarigoldFX.make_label("Tu Ofrenda", 84, C_GOLD)
	title.position = Vector3(0, 3.4, -4.4)
	_stage.add_child(title)
	_plaque = MarigoldPlaques.place_plaque(self,
		"Tu Ofrenda",
		"Your altar of memories. Each object you collected on the journey rests here - a photo, pan de muerto, a marigold bloom, a guitar pick. Gather all four to light the final candle.",
		Vector3(-2.6, 1.5, -1.6), 1.9)
	_update_progress_toast()


func _build_candle_ring() -> void:
	# Ring of candles around the ofrenda (emissive only - zero real lights
	# beyond the chapter's shared budget). v0.9.0: each candle is a root
	# registered with CandleMelt — lit candles visibly melt (UE5 Living Wax
	# port). Light cylinders stay (14 instances of the 161k-tri hero candle
	# would blow the Quest frame budget; the hero stars in ch1 instead).
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	for i in 14:
		var a := TAU * float(i) / 14.0
		var r := 2.0
		var pos := Vector3(cos(a) * r, 0, -3.0 + sin(a) * r * 0.7)
		var hgt := rng.randf_range(0.25, 0.45)
		var root := Node3D.new()
		root.name = "RingCandle_%d" % i
		root.position = pos
		_stage.add_child(root)
		var stick := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.035
		sm.bottom_radius = 0.035
		sm.height = hgt
		stick.mesh = sm
		# v0.9.0: real wax PBR set on the ring candles too.
		stick.material_override = MarigoldFX.pbr_tex(
			"res://assets/textures/in-house/wax/candle_wax_512_albedo.png",
			C_CREAM, 2.0, 0.6,
			"res://assets/textures/in-house/wax/candle_wax_512_normal.png",
			"res://assets/textures/in-house/wax/candle_wax_512_roughness.png")
		stick.position = Vector3(0, hgt * 0.5, 0)
		root.add_child(stick)
		var flame := MeshInstance3D.new()
		var fm2 := SphereMesh.new()
		fm2.radius = 0.035
		fm2.height = 0.09
		flame.mesh = fm2
		var fmat := MarigoldFX.glow(Color(1.0, 0.62, 0.18), 1.6)
		flame.material_override = fmat
		flame.position = Vector3(0, hgt + 0.045, 0)
		root.add_child(flame)
		_candle_mats.append(fmat)
		_candle_flames.append(pos + Vector3(0, hgt + 0.045, 0)) # VFX ignition anchor
		root.add_to_group("marigold_candles")
		root.set_meta("melt_wax", stick)
		root.set_meta("melt_sinks", [flame])
		root.set_meta("melt_lit_mode", "meta")
		root.set_meta("melt_lit", false)
		root.set_meta("melt_top", hgt)
		root.set_meta("melt_radius", 0.035)
		_ring_roots.append(root)


## v0.9.0 UE5-wave dressing: the hero nicho shrine mounted over the altar,
## the artist chandelier, tin lanterns, and a woven carpet (Poly Pizza).
func _build_wave_dressing() -> void:
	MarigoldModels.ground_place(_backdrop,
		MarigoldModels.blender_model(MarigoldModels.OFRENDA, "shrine_nicho_hero"),
		Vector3(0, 0.92, -4.42), 1.32, 0.0)
	var chand := MarigoldModels.artist_model("chandelier_hero")
	if chand != null:
		var cb := MarigoldModels.bounds_of(chand)
		chand.position = Vector3(0, 3.55 - cb.size.y, -3.0)
		_backdrop.add_child(chand)
	for lx in [-1.75, 1.75]:
		MarigoldModels.ground_place(_stage,
			MarigoldModels.artist_model("lantern_hojalata_hero"),
			Vector3(lx, 0, -3.7), 0.47, 0.0)
	MarigoldModels.ground_place(_stage,
		MarigoldModels.polypizza_model("textiles", "wool_carpet_zsky"),
		Vector3(0, 0.012, -1.1), 3.0, 0.0, true)


func _build_papel_frame() -> void:
	# Papel-picado arch framing the altar.
	for i in 5:
		var b := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.5)
		b.mesh = qm
		b.material_override = MarigoldPapelPicado.banner_material(900 + i)
		b.position = Vector3(-1.8 + float(i) * 0.9, 2.9, -4.4)
		_stage.add_child(b)


func _update_progress_toast() -> void:
	var n := MarigoldOfrenda.collected().size()
	var label := _stage.get_node_or_null("ProgressLabel") as Label3D
	if label == null:
		label = MarigoldFX.make_label("", 48, C_GOLD)
		label.name = "ProgressLabel"
		label.position = Vector3(0, 2.75, -4.4)
		_stage.add_child(label)
	if n >= 4:
		label.text = "La ofrenda esta completa"
	else:
		label.text = "%d / 4 recuerdos" % n


## v0.7.0: progressive candle lighting — each collected memory object
## lights its share of the ring (not a binary all-14 reveal). Unlit
## candles sit dim; lit ones breathe.
func _update_candle_progress() -> void:
	var n := MarigoldOfrenda.collected().size()
	var lit := int(round(14.0 * float(n) / 4.0))
	# v0.7.0 VFX: ignition burst on each newly-lit candle.
	if lit > _last_lit:
		for i in range(maxi(_last_lit, 0), lit):
			if i < _candle_flames.size():
				MarigoldSpectacle.candle_ignite(_stage, _candle_flames[i])
		_last_lit = lit
	for i in _candle_mats.size():
		var m: StandardMaterial3D = _candle_mats[i]
		if m == null or not is_instance_valid(m):
			continue
		# v0.9.0: feed the melt system this candle's lit state.
		if i < _ring_roots.size():
			(_ring_roots[i] as Node3D).set_meta("melt_lit", i < lit)
		if i < lit:
			var base := 1.6 if not _revealed else 2.6
			m.emission_energy_multiplier = base + sin(_t * 9.0 + float(i) * 1.7) * 0.5
		else:
			m.emission_energy_multiplier = 0.25


## The bower calavera: a skeleton host beside the altar. Idles with a
## gentle sway; at the reveal it faces the player, bows deep, and holds
## JOY — acknowledging YOUR completed ofrenda.
func _build_host() -> void:
	_host = MarigoldCalavera.make_dancer(Color(1.0, 0.62, 0.18), 1.0,
		{"ring": true, "pupils": true, "jaw": true, "seed": 77})
	var root: Node3D = _host["root"]
	root.position = Vector3(2.3, 0, -2.2)
	root.rotation.y = -0.5
	_stage.add_child(root)
	_host["phase"] = 1.2
	_host["base_y"] = 0.0
	# v0.7.0 Narrative: Rosa's entrance line (4s delay).
	_finale_dialogue_t = 4.0


func _update_host(delta: float) -> void:
	var root: Node3D = _host.get("root")
	if root == null or not is_instance_valid(root):
		return
	if _revealed:
		return # the bow holds through the finale
	var t: float = float(_host.get("phase", 0.0)) + delta
	_host["phase"] = t
	root.position.y = float(_host.get("base_y", 0.0)) + absf(sin(_t * 1.6)) * 0.03
	root.rotation.y = -0.5 + sin(_t * 0.4) * 0.08


## Candle-grade lock on the 4 memory objects (v0.7.0 P1): each collected
## object gets a warm rim-glow quad behind it — the locked warm grade
## (plum shadows + marigold key + candle fill) lands on the objects, not
## just the room.
func _grade_memory_objects() -> void:
	for id in MarigoldOfrenda.ITEM_ORDER:
		var slot := _shelf.get_node_or_null("Slot_" + id) as Node3D
		if slot == null:
			continue
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.34, 0.34)
		quad.mesh = qm
		quad.material_override = MarigoldFX.glow(Color(1.0, 0.55, 0.20), 0.0)
		quad.position = Vector3(0, 0.12, -0.10)
		slot.add_child(quad)
		slot.set_meta("grade_quad", quad)
		_grade_quads.append(quad)
	_update_grade_boost()


func _update_grade_boost() -> void:
	var boost := 1.6 if _revealed else 0.7
	for i in _grade_quads.size():
		var q: MeshInstance3D = _grade_quads[i]
		if q == null or not is_instance_valid(q):
			continue
		var id: String = MarigoldOfrenda.ITEM_ORDER[i]
		var m := q.material_override as StandardMaterial3D
		if m == null:
			continue
		m.emission_energy_multiplier = boost if MarigoldOfrenda.has(id) else 0.0


## v0.7.0 VFX: memory-object world positions (stage-local) for the
## reveal cascade — each object erupts its own petal fountain + light beam.
func _memory_positions() -> Array:
	var pts: Array = []
	for id in MarigoldOfrenda.ITEM_ORDER:
		var slot := _shelf.get_node_or_null("Slot_" + id) as Node3D
		if slot != null:
			pts.append(slot.position + _shelf.position)
	if pts.is_empty():
		pts.append(Vector3(0, 1.0, -3.0))
	return pts


func _reveal() -> void:
	_revealed = true
	_update_progress_toast()
	_update_grade_boost() # full warm grade on the four memory objects
	# v0.7.0 VFX: staggered petal-fountain + light-beam cascade from each
	# memory object, converging in a flash sphere (owns the fanfare haptic).
	MarigoldSpectacle.reveal_cascade(_stage, _memory_positions(), C_GOLD)
	# Music swell at the apex.
	if MarigoldState.music != null and MarigoldState.music.has_method("swell"):
		MarigoldState.music.swell(5.0, 1.5, 5.0)
	# The bower acknowledges: faces the player, bows deep, holds JOY.
	var hroot: Node3D = _host.get("root")
	if hroot != null and is_instance_valid(hroot):
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			MarigoldCalavera.face_player(hroot, cam.global_position)
		MarigoldCalavera.set_bow(_host, 1.0)
		var hrig: MarigoldCharacterRig = _host.get("rig")
		if hrig != null:
			hrig.set_expression("JOY", 1.0)
			hrig.set_jaw_hold(0.5, 2.0) # a bow with a smile
	# Photo-prompt at the apex.
	var prompt := MarigoldFX.make_label(
		"\uD83D\uDCF7  ¡Captura este momento! · Seize this moment",
		56, Color(1.0, 0.88, 0.55))
	prompt.position = Vector3(0, 2.0, -4.35)
	_stage.add_child(prompt)
	var ptw := create_tween()
	ptw.tween_interval(5.0)
	ptw.tween_callback(prompt.queue_free)
	MarigoldFX.spawn_confetti(_stage, Vector3(0, 2.0, -3.0), 60)
	if MarigoldState.music != null and MarigoldState.music.has_method("play_stinger"):
		MarigoldState.music.play_stinger("bow_drum", -4.0)
	var fam := MarigoldFX.make_label("La Familia Williams", 64, Color(1.0, 0.88, 0.55))
	fam.position = Vector3(0, 2.35, -4.35)
	_stage.add_child(fam)
	MarigoldPhotos.note_moment("ofrenda_done")
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func() -> void: chapter_complete.emit())
