## ch1_ofrenda.gd - MARIGOLD Chapter 1: The Ofrenda.
## The player builds a 3-tiered ofrenda: places 6 marigold petal puffs,
## sets 3 photo frames on the tiers, and lights 5 candles.
## Completing all 14 tasks triggers a celebration, then chapter_complete.
## No class_name (chapter contract). Headless-safe: no XR hardware required.
extends Node3D

signal chapter_complete

const TOTAL_PETALS := 6
const TOTAL_FRAMES := 3
const TOTAL_CANDLES := 5
const TOTAL_TASKS := TOTAL_PETALS + TOTAL_FRAMES + TOTAL_CANDLES
const GRAB_RADIUS := 0.30
const MAX_GRAB_DIST := 3.0

var _ar_mode := false
var _stage: Node3D
var _ofrenda: Node3D
var _side_table: Node3D
var _backdrop: Node3D
var _petal_slots: Array[Vector3] = []
var _petal_used: Array[bool] = []
var _frame_slots: Array[Vector3] = []
var _frame_used: Array[bool] = []
var _frames: Array[Node3D] = []
var _frame_home_local: Array[Transform3D] = []
var _candles: Array[Node3D] = []
var _candle_lit: Array[bool] = []
var _flame_mats: Array[StandardMaterial3D] = []
var _flame_nodes: Array[Node3D] = []
var _basket: Node3D
var _basket_puffs: Array[Node3D] = []
var _held: Node3D = null
var _held_kind := ""
var _held_frame_idx := -1
var _petals_placed := 0
var _frames_placed := 0
var _candles_lit_count := 0
var _lights_used := 0
var _progress_label: Label3D
var _toast_label: Label3D
var _toast_time := 0.0
var _plaque: Node3D
var _finished := false
var _party := false
var _pinch_prev := false
var _ember_mats: Array[StandardMaterial3D] = []
var _t := 0.0
var _stage_home := Vector3(0, 0, -1.8)


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	_update_progress()
	_toast("Build the ofrenda: 6 petals · 3 photos · 5 candles", 7.0)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _backdrop:
		_backdrop.visible = not on
	if _stage == null:
		return
	if on:
		var key := _anchor_key()
		if not MarigoldHands.apply_anchor(_stage, key):
			MarigoldHands.place_on_table(_stage)
			MarigoldHands.save_anchor(key, _stage.global_transform)
	else:
		_stage.position = _stage_home
		_stage.rotation = Vector3.ZERO


## Autoload-safe anchor key (avoids a static MarigoldState reference so
## --check-only verification passes; resolves fine at runtime).
func _anchor_key() -> String:
	if is_inside_tree():
		var st := get_tree().root.get_node_or_null("MarigoldState")
		if st != null and st.has_method("anchor_name"):
			return String(st.call("anchor_name", "ch1_ofrenda"))
	return "marigold_ch1_ofrenda"


func _process(delta: float) -> void:
	_t += delta
	if _plaque:
		MarigoldPlaques.face_player(_plaque)
	# Toast fade.
	if _toast_time > 0.0 and _toast_label:
		_toast_time -= delta
		var c := _toast_label.modulate
		c.a = clampf(_toast_time, 0.0, 1.0)
		_toast_label.modulate = c
	# Flame + ember flicker (brighter during the celebration).
	var base := 3.2 if _party else 2.2
	for i in _flame_mats.size():
		MarigoldFX.pulse_glow(_flame_mats[i], base, 1.1, _t + float(i) * 1.7, 9.0)
	for i in _ember_mats.size():
		MarigoldFX.pulse_glow(_ember_mats[i], 2.0, 0.8, _t * 1.3 + float(i) * 2.1, 5.0)
	# Held item follows the pointer with a gentle bob.
	if _held and is_instance_valid(_held):
		var p: Vector3 = _pointer_pos()
		p.y += 0.05 * sin(_t * 4.0)
		_held.global_position = p
	# Pinch interaction: local edge detector (avoids the missing
	# "trigger_click" action in the shared helper's fallback chain).
	if _pinch_edge():
		_on_pinch()


## Pinch edge detection: mouse click = right-hand pinch, plus any
## project XR pinch actions when they exist.
func _pinch_edge() -> bool:
	var now := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if InputMap.has_action("pinch_right") and Input.is_action_pressed("pinch_right"):
		now = true
	var edge := now and not _pinch_prev
	_pinch_prev = now
	return edge


## Transient feedback toast.
func _toast(text: String, dur: float = 2.5) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_time = dur


## Short musical feedback via the shared music player (autoload-safe).
func _sfx(note: int, vol: float = 0.7, dur: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var st := get_tree().root.get_node_or_null("MarigoldState")
	if st == null:
		return
	var m = st.get("music")
	if m != null and m.has_method("pluck"):
		m.call("pluck", note, vol, dur)


## ---------------- build ----------------

func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.position = _stage_home
	add_child(_stage)

	_build_ofrenda()
	_build_side_table()
	_build_backdrop()

	_progress_label = MarigoldFX.make_label("Ofrenda: 0/14", 72, Color(1.0, 0.82, 0.45))
	_progress_label.position = Vector3(0, 2.45, 0.4)
	_stage.add_child(_progress_label)

	_toast_label = MarigoldFX.make_label("", 52, Color(1.0, 0.95, 0.80))
	_toast_label.position = Vector3(0, 2.02, 0.4)
	_stage.add_child(_toast_label)

	_plaque = MarigoldPlaques.place_plaque(
		_stage,
		"The Ofrenda",
		"An ofrenda is a welcoming offering for the spirits of departed loved ones. Families place photographs to honor them, candles to light their path home, marigolds whose scent guides them, and the foods and drinks they loved in life. Building one together is an act of love and remembrance.",
		Vector3(2.1, 1.5, 0.3),
		1.7
	)


## ---------------- build ----------------

func _build_ofrenda() -> void:
	_ofrenda = Node3D.new()
	_ofrenda.name = "Ofrenda"
	_stage.add_child(_ofrenda)

	var wood := MarigoldFX.pbr(Color(0.42, 0.24, 0.12), 0.0, 0.7)
	var cloth_a := MarigoldFX.pbr(Color(0.55, 0.10, 0.45), 0.0, 0.95)
	var cloth_b := MarigoldFX.pbr(Color(0.75, 0.35, 0.08), 0.0, 0.95)
	var trim := MarigoldFX.glow(Color(1.0, 0.60, 0.10), 1.6)

	var tiers := [
		{"size": Vector3(2.2, 0.5, 1.1), "top": 0.5},
		{"size": Vector3(1.7, 0.4, 0.9), "top": 0.9},
		{"size": Vector3(1.2, 0.4, 0.7), "top": 1.3},
	]
	for i in tiers.size():
		var size: Vector3 = tiers[i]["size"]
		var top: float = tiers[i]["top"]
		var tier_box := BoxMesh.new()
		tier_box.size = size
		var tier_mi := MeshInstance3D.new()
		tier_mi.mesh = tier_box
		tier_mi.material_override = wood
		tier_mi.position = Vector3(0, top - size.y * 0.5, 0)
		_ofrenda.add_child(tier_mi)
		# Cloth drape on top.
		var cloth_box := BoxMesh.new()
		cloth_box.size = Vector3(size.x + 0.08, 0.045, size.z + 0.08)
		var cloth_mi := MeshInstance3D.new()
		cloth_mi.mesh = cloth_box
		cloth_mi.material_override = cloth_a if i % 2 == 0 else cloth_b
		cloth_mi.position = Vector3(0, top + 0.022, 0)
		_ofrenda.add_child(cloth_mi)
		# Marigold trim along the front edge.
		var trim_box := BoxMesh.new()
		trim_box.size = Vector3(size.x + 0.08, 0.05, 0.05)
		var trim_mi := MeshInstance3D.new()
		trim_mi.mesh = trim_box
		trim_mi.material_override = trim
		trim_mi.position = Vector3(0, top - 0.04, size.z * 0.5 + 0.03)
		_ofrenda.add_child(trim_mi)

	# Petal slots: two per tier.
	_petal_slots = [
		Vector3(-0.70, 0.52, 0.15), Vector3(0.70, 0.52, 0.15),
		Vector3(-0.50, 0.92, 0.10), Vector3(0.50, 0.92, 0.10),
		Vector3(-0.28, 1.32, 0.05), Vector3(0.28, 1.32, 0.05),
	]
	_petal_used = [false, false, false, false, false, false]

	# Frame slots: one centered per tier, toward the back.
	_frame_slots = [
		Vector3(0, 0.52, -0.24),
		Vector3(0, 0.92, -0.22),
		Vector3(0, 1.32, -0.20),
	]
	_frame_used = [false, false, false]

	# Candles (start unlit) arranged on the tiers.
	var candle_slots := [
		Vector3(-0.95, 0.52, -0.32), Vector3(0.95, 0.52, -0.32),
		Vector3(-0.70, 0.92, -0.28), Vector3(0.70, 0.92, -0.28),
		Vector3(0.42, 1.32, -0.20),
	]
	for s in candle_slots:
		_candles.append(_make_candle(s))
		_candle_lit.append(false)

	# Decorative food offerings (non-interactive): bread + cups on tier 1.
	var bread_mat := MarigoldFX.pbr(Color(0.85, 0.62, 0.35), 0.0, 0.85)
	for bx in [-0.35, 0.35]:
		var bread := SphereMesh.new()
		bread.radius = 0.07
		bread.height = 0.09
		var bmi := MeshInstance3D.new()
		bmi.mesh = bread
		bmi.material_override = bread_mat
		bmi.position = Vector3(bx, 0.57, 0.34)
		_ofrenda.add_child(bmi)
	var cup_mat := MarigoldFX.pbr(Color(0.90, 0.85, 0.70), 0.0, 0.6)
	for cx in [-0.15, 0.15]:
		var cup := CylinderMesh.new()
		cup.top_radius = 0.045
		cup.bottom_radius = 0.035
		cup.height = 0.10
		var cmi := MeshInstance3D.new()
		cmi.mesh = cup
		cmi.material_override = cup_mat
		cmi.position = Vector3(cx, 0.57, 0.36)
		_ofrenda.add_child(cmi)

	# Abundant offerings: the full spread of a real ofrenda.
	_build_offerings()
	_build_marigold_arch()
	_build_garlands()
	_scatter_floor_petals()


## ---------------- abundant offerings ----------------

## Pan de muerto, sugar skulls, copal incense, water, salt, food plates.
func _build_offerings() -> void:
	# Pan de muerto loaves.
	for pos in [Vector3(-0.18, 0.56, -0.08), Vector3(0.22, 0.56, -0.12), Vector3(-0.32, 0.96, 0.22)]:
		var loaf := _make_pan_de_muerto()
		loaf.position = pos
		_ofrenda.add_child(loaf)
	# Sugar skulls with glowing eyes.
	var skull_accents := [Color(1.0, 0.30, 0.60), Color(0.40, 0.85, 1.0), Color(1.0, 0.75, 0.20)]
	var skull_pos := [Vector3(0.38, 0.96, -0.02), Vector3(-0.38, 1.36, -0.02), Vector3(0.88, 0.56, 0.28)]
	for i in 3:
		var skull := _make_sugar_skull(skull_accents[i])
		skull.position = skull_pos[i]
		skull.rotation.y = randf() * TAU
		_ofrenda.add_child(skull)
	# Copal incense burner with rising smoke.
	var copal := _make_copal()
	copal.position = Vector3(0.55, 0.52, -0.38)
	_ofrenda.add_child(copal)
	# Glass of water for the thirsty traveler.
	var glass := _make_water_glass()
	glass.position = Vector3(-0.55, 0.52, -0.36)
	_ofrenda.add_child(glass)
	# Dish of salt for purification.
	var salt := _make_salt_dish()
	salt.position = Vector3(-0.88, 0.52, 0.30)
	_ofrenda.add_child(salt)
	# Plates of food.
	for pos in [Vector3(0.48, 0.52, 0.34), Vector3(-0.05, 0.92, 0.30)]:
		var plate := _make_food_plate()
		plate.position = pos
		_ofrenda.add_child(plate)
	# Two small decorative framed photos already watching over tier 2.
	for i in 2:
		var mini := _make_photo_frame(i + 1)
		mini.scale = Vector3(0.55, 0.55, 0.55)
		mini.position = Vector3(0.82 if i == 0 else -0.82, 0.92, 0.02)
		mini.rotation_degrees = Vector3(-6.0, -18.0 if i == 0 else 18.0, 0)
		_ofrenda.add_child(mini)


func _make_pan_de_muerto() -> Node3D:
	var root := Node3D.new()
	root.name = "PanDeMuerto"
	var bread_mat := MarigoldFX.pbr(Color(0.80, 0.55, 0.28), 0.0, 0.85)
	var bone_mat := MarigoldFX.pbr(Color(0.90, 0.70, 0.42), 0.0, 0.85)
	var loaf := SphereMesh.new()
	loaf.radius = 0.085
	loaf.height = 0.13
	var lmi := MeshInstance3D.new()
	lmi.mesh = loaf
	lmi.material_override = bread_mat
	lmi.scale = Vector3(1.0, 0.72, 1.0)
	lmi.position.y = 0.045
	root.add_child(lmi)
	for r in [35.0, -35.0]:
		var bone := CylinderMesh.new()
		bone.top_radius = 0.014
		bone.bottom_radius = 0.014
		bone.height = 0.15
		var bmi := MeshInstance3D.new()
		bmi.mesh = bone
		bmi.material_override = bone_mat
		bmi.rotation_degrees = Vector3(0, 0, r)
		bmi.position.y = 0.10
		root.add_child(bmi)
	var knob := SphereMesh.new()
	knob.radius = 0.028
	knob.height = 0.05
	var kmi := MeshInstance3D.new()
	kmi.mesh = knob
	kmi.material_override = bone_mat
	kmi.position.y = 0.125
	root.add_child(kmi)
	return root


func _make_sugar_skull(accent: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SugarSkull"
	var skull := SphereMesh.new()
	skull.radius = 0.062
	skull.height = 0.13
	var smi := MeshInstance3D.new()
	smi.mesh = skull
	smi.material_override = MarigoldFX.pbr(Color(0.94, 0.92, 0.88), 0.0, 0.7)
	smi.position.y = 0.06
	root.add_child(smi)
	var eye_mat := MarigoldFX.glow(accent, 2.2)
	for ex in [-0.026, 0.026]:
		var eye := SphereMesh.new()
		eye.radius = 0.016
		eye.height = 0.03
		var emi := MeshInstance3D.new()
		emi.mesh = eye
		emi.material_override = eye_mat
		emi.position = Vector3(ex, 0.075, 0.048)
		root.add_child(emi)
	var flower := SphereMesh.new()
	flower.radius = 0.014
	flower.height = 0.025
	var fmi := MeshInstance3D.new()
	fmi.mesh = flower
	fmi.material_override = MarigoldFX.glow(Color(1.0, 0.60, 0.10), 2.0)
	fmi.position = Vector3(0, 0.115, 0.038)
	root.add_child(fmi)
	return root


func _make_copal() -> Node3D:
	var root := Node3D.new()
	root.name = "CopalBurner"
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.075
	bowl.bottom_radius = 0.05
	bowl.height = 0.06
	var bmi := MeshInstance3D.new()
	bmi.mesh = bowl
	bmi.material_override = MarigoldFX.pbr(Color(0.25, 0.12, 0.08), 0.0, 0.8)
	bmi.position.y = 0.03
	root.add_child(bmi)
	var ember_mat := MarigoldFX.glow(Color(1.0, 0.45, 0.10), 2.5)
	var ember := SphereMesh.new()
	ember.radius = 0.030
	ember.height = 0.04
	var emi := MeshInstance3D.new()
	emi.mesh = ember
	emi.material_override = ember_mat
	emi.position.y = 0.065
	root.add_child(emi)
	_ember_mats.append(ember_mat)
	# Looping smoke wisps.
	var smoke := GPUParticles3D.new()
	smoke.amount = 18
	smoke.lifetime = 3.2
	smoke.preprocess = 3.2
	smoke.position.y = 0.09
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.04
	pm.scale_max = 0.09
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.75, 0.80, 0.45))
	grad.set_color(1, Color(0.75, 0.75, 0.80, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	smoke.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(0.85, 0.85, 0.90, 1.0)
	quad.material = qm
	smoke.draw_pass_1 = quad
	root.add_child(smoke)
	smoke.emitting = true
	return root


func _make_water_glass() -> Node3D:
	var root := Node3D.new()
	root.name = "WaterGlass"
	var glass := CylinderMesh.new()
	glass.top_radius = 0.045
	glass.bottom_radius = 0.038
	glass.height = 0.13
	var gmi := MeshInstance3D.new()
	gmi.mesh = glass
	gmi.material_override = MarigoldFX.pbr_preset(Color(0.70, 0.85, 1.0), "glass")
	gmi.position.y = 0.065
	root.add_child(gmi)
	var water := CylinderMesh.new()
	water.top_radius = 0.038
	water.bottom_radius = 0.033
	water.height = 0.085
	var wmi := MeshInstance3D.new()
	wmi.mesh = water
	var wmat := MarigoldFX.pbr(Color(0.35, 0.65, 1.0), 0.1, 0.2)
	wmat.emission_enabled = true
	wmat.emission = Color(0.30, 0.60, 1.0)
	wmat.emission_energy_multiplier = 0.35
	wmi.material_override = wmat
	wmi.position.y = 0.048
	root.add_child(wmi)
	return root


func _make_salt_dish() -> Node3D:
	var root := Node3D.new()
	root.name = "SaltDish"
	var dish := CylinderMesh.new()
	dish.top_radius = 0.062
	dish.bottom_radius = 0.045
	dish.height = 0.022
	var dmi := MeshInstance3D.new()
	dmi.mesh = dish
	dmi.material_override = MarigoldFX.pbr(Color(0.90, 0.88, 0.82), 0.0, 0.5)
	dmi.position.y = 0.011
	root.add_child(dmi)
	var salt := SphereMesh.new()
	salt.radius = 0.045
	salt.height = 0.05
	var smi := MeshInstance3D.new()
	smi.mesh = salt
	smi.material_override = MarigoldFX.pbr(Color(0.98, 0.98, 0.96), 0.0, 0.95)
	smi.scale = Vector3(1.0, 0.45, 1.0)
	smi.position.y = 0.025
	root.add_child(smi)
	return root


func _make_food_plate() -> Node3D:
	var root := Node3D.new()
	root.name = "FoodPlate"
	var plate := CylinderMesh.new()
	plate.top_radius = 0.115
	plate.bottom_radius = 0.085
	plate.height = 0.028
	var pmi := MeshInstance3D.new()
	pmi.mesh = plate
	pmi.material_override = MarigoldFX.pbr(Color(0.92, 0.88, 0.78), 0.0, 0.45)
	pmi.position.y = 0.014
	root.add_child(pmi)
	var mole := SphereMesh.new()
	mole.radius = 0.068
	mole.height = 0.09
	var mmi := MeshInstance3D.new()
	mmi.mesh = mole
	mmi.material_override = MarigoldFX.pbr(Color(0.32, 0.16, 0.07), 0.0, 0.8)
	mmi.scale = Vector3(1.0, 0.55, 1.0)
	mmi.position.y = 0.045
	root.add_child(mmi)
	var tamal_mat := MarigoldFX.pbr(Color(0.88, 0.72, 0.45), 0.0, 0.85)
	for i in 3:
		var tamal := SphereMesh.new()
		tamal.radius = 0.022
		tamal.height = 0.06
		var tmi := MeshInstance3D.new()
		tmi.mesh = tamal
		tmi.material_override = tamal_mat
		tmi.scale = Vector3(1.0, 1.0, 1.6)
		var a := float(i) / 3.0 * TAU
		tmi.position = Vector3(cos(a) * 0.055, 0.085, sin(a) * 0.055)
		root.add_child(tmi)
	return root


## Marigold arch rising behind the tiers.
func _build_marigold_arch() -> void:
	var arch := Node3D.new()
	arch.name = "MarigoldArch"
	arch.position = Vector3(0, 0, -0.78)
	_ofrenda.add_child(arch)
	var wood := MarigoldFX.pbr(Color(0.35, 0.20, 0.10), 0.0, 0.8)
	for px in [-1.35, 1.35]:
		var post := CylinderMesh.new()
		post.top_radius = 0.045
		post.bottom_radius = 0.058
		post.height = 2.3
		var pmi := MeshInstance3D.new()
		pmi.mesh = post
		pmi.material_override = wood
		pmi.position = Vector3(px, 1.15, 0)
		arch.add_child(pmi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var flower_kinds := ["flower_redA", "flower_redB", "flower_yellowA", "flower_yellowB"]
	var leaf := MarigoldFX.pbr(Color(0.12, 0.35, 0.12), 0.0, 0.9)
	for i in 26:
		var t := float(i) / 25.0
		var pos := Vector3(cos(PI * t) * 1.35, 2.3 + sin(PI * t) * 1.05, 0)
		# Real marigold flower model (Kenney CC0), glowing orange.
		var blossom := MarigoldModels.instance(MarigoldModels.NATURE, flower_kinds[i % flower_kinds.size()])
		if blossom != null:
			MarigoldModels.recolor_glow(blossom, Color(1.0, 0.55, 0.10), Color(1.0, 0.50, 0.08), 1.9)
			blossom.position = pos + Vector3(
				rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.05, 0.05))
			var bs := rng.randf_range(1.6, 2.4)
			blossom.scale = Vector3.ONE * bs
			blossom.rotation.y = rng.randf() * TAU
			arch.add_child(blossom)
		if i % 3 == 0:
			var lf := SphereMesh.new()
			lf.radius = 0.05
			lf.height = 0.03
			var lmi := MeshInstance3D.new()
			lmi.mesh = lf
			lmi.material_override = leaf
			lmi.position = pos + Vector3(0, -0.10, 0.02)
			arch.add_child(lmi)
	# Stone altar dressing flanking the arch (Kenney CC0).
	for sx in [-1.0, 1.0]:
		var altar := MarigoldModels.place(arch, MarigoldModels.GRAVEYARD, "altar-stone", Vector3(sx * 1.85, 0, 0.35), sx * 18.0, 0.9)
		if altar != null:
			MarigoldModels.recolor(altar, Color(0.52, 0.48, 0.55), 0.05, 0.85)


## Marigold garlands swagged across each tier's front edge.
func _build_garlands() -> void:
	var tiers := [
		{"w": 2.28, "top": 0.50, "z": 0.61},
		{"w": 1.78, "top": 0.90, "z": 0.51},
		{"w": 1.28, "top": 1.30, "z": 0.41},
	]
	var flower_kinds := ["flower_redA", "flower_yellowA", "flower_redB", "flower_yellowB"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for tier in tiers:
		var w: float = tier["w"]
		var top: float = tier["top"]
		var z: float = tier["z"]
		for i in 13:
			var t := float(i) / 12.0
			# Real marigold flower model (Kenney CC0) swagged along the edge.
			var blossom := MarigoldModels.instance(MarigoldModels.NATURE, flower_kinds[i % flower_kinds.size()])
			if blossom == null:
				continue
			MarigoldModels.recolor_glow(blossom, Color(1.0, 0.60, 0.10), Color(1.0, 0.55, 0.08), 2.0)
			blossom.position = Vector3(lerpf(-w * 0.5, w * 0.5, t), top + 0.03 - sin(t * PI) * 0.085, z)
			blossom.rotation.y = rng.randf() * TAU
			var bs := rng.randf_range(0.9, 1.3)
			blossom.scale = Vector3.ONE * bs
			_ofrenda.add_child(blossom)


## Scattered fallen petals around the ofrenda base.
func _scatter_floor_petals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var mat := MarigoldFX.glow(Color(1.0, 0.62, 0.10), 1.5)
	for i in 44:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.5, 2.9)
		var petal := SphereMesh.new()
		petal.radius = 0.030
		petal.height = 0.025
		var pmi := MeshInstance3D.new()
		pmi.mesh = petal
		pmi.material_override = mat
		pmi.scale = Vector3(1.0, 0.5, 1.4)
		pmi.position = Vector3(cos(a) * r, 0.015, sin(a) * r * 0.8)
		pmi.rotation.y = rng.randf() * TAU
		_stage.add_child(pmi)


func _build_side_table() -> void:
	_side_table = Node3D.new()
	_side_table.name = "SideTable"
	_side_table.position = Vector3(-2.1, 0, 0.35)
	_stage.add_child(_side_table)

	var wood := MarigoldFX.pbr(Color(0.36, 0.20, 0.10), 0.0, 0.75)
	var top := BoxMesh.new()
	top.size = Vector3(1.15, 0.08, 0.75)
	var top_mi := MeshInstance3D.new()
	top_mi.mesh = top
	top_mi.material_override = wood
	top_mi.position = Vector3(0, 0.72, 0)
	_side_table.add_child(top_mi)
	for lx in [-0.5, 0.5]:
		for lz in [-0.3, 0.3]:
			var leg := BoxMesh.new()
			leg.size = Vector3(0.07, 0.68, 0.07)
			var lmi := MeshInstance3D.new()
			lmi.mesh = leg
			lmi.material_override = wood
			lmi.position = Vector3(lx, 0.34, lz)
			_side_table.add_child(lmi)

	# 3 photo frames standing on the table (grabbable).
	for i in 3:
		var frame := _make_photo_frame(i)
		frame.position = Vector3(-0.34 + float(i) * 0.34, 0.76, 0.12)
		frame.rotation_degrees.x = -6.0
		_side_table.add_child(frame)
		_frames.append(frame)
		_frame_home_local.append(frame.transform)

	# Petal basket with 6 visible puffs (supply indicator).
	_basket = Node3D.new()
	_basket.name = "PetalBasket"
	_basket.position = Vector3(0.30, 0.76, -0.18)
	_side_table.add_child(_basket)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.20
	bowl.bottom_radius = 0.14
	bowl.height = 0.14
	var bowl_mi := MeshInstance3D.new()
	bowl_mi.mesh = bowl
	bowl_mi.material_override = MarigoldFX.pbr(Color(0.55, 0.34, 0.16), 0.0, 0.8)
	bowl_mi.position.y = 0.07
	_basket.add_child(bowl_mi)
	for i in TOTAL_PETALS:
		var puff := _make_petal_puff(0.55)
		var a := float(i) / float(TOTAL_PETALS) * TAU
		puff.position = Vector3(cos(a) * 0.08, 0.15, sin(a) * 0.08)
		_basket.add_child(puff)
		_basket_puffs.append(puff)

	var hint := MarigoldFX.make_label("Pinch the basket for petals,\nframes to move them,\ncandles to light them", 44, Color(1.0, 0.9, 0.7))
	hint.position = Vector3(0, 1.45, 0)
	_side_table.add_child(hint)


func _build_backdrop() -> void:
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.position = _stage_home
	add_child(_backdrop)
	MarigoldModels.make_flower_field(_backdrop, 200, 8.0, 314)
	MarigoldFX.make_god_ray(_backdrop, Vector3(0, 0, 0), 8.0)
	MarigoldFX.make_god_ray(_backdrop, Vector3(-3.5, 0, -1.5), 8.0, Color(1.0, 0.5, 0.7))
	var b1 := MarigoldFX.make_papel_banner(_backdrop, 4.0, 1.1, Color(1.0, 0.35, 0.55))
	b1.position = Vector3(-2.0, 2.6, -3.2)
	var b2 := MarigoldFX.make_papel_banner(_backdrop, 4.0, 1.1, Color(0.35, 0.7, 1.0))
	b2.position = Vector3(2.2, 2.8, -3.6)
	_build_papel_strings()
	MarigoldFX.spawn_ambient_motes(_backdrop, Vector3(0, 1.6, 0), 4.5, 80)
	# Graveyard fence dressing (Kenney CC0) framing the scene.
	for fx in [-3.2, 3.2]:
		var fence := MarigoldModels.place(_backdrop, MarigoldModels.GRAVEYARD, "fence", Vector3(fx, 0, -2.2), 90.0 if fx < 0 else -90.0, 1.4)
		if fence != null:
			MarigoldModels.recolor(fence, Color(0.30, 0.26, 0.32), 0.1, 0.8)


## Strings of small papel picado banners strung above the ofrenda.
func _build_papel_strings() -> void:
	var colors := [
		Color(1.0, 0.35, 0.55), Color(0.35, 0.70, 1.0), Color(1.0, 0.60, 0.10),
		Color(0.50, 0.90, 0.40), Color(0.75, 0.40, 1.0),
	]
	for s in 3:
		var z := -2.4 - float(s) * 1.0
		var y := 3.1 - float(s) * 0.3
		var x0 := -3.6 + float(s) * 0.4
		var x1 := 3.6 - float(s) * 0.4
		var line := BoxMesh.new()
		line.size = Vector3(x1 - x0, 0.015, 0.015)
		var lmi := MeshInstance3D.new()
		lmi.mesh = line
		lmi.material_override = MarigoldFX.pbr(Color(0.10, 0.08, 0.06), 0.0, 0.9)
		lmi.position = Vector3((x0 + x1) * 0.5, y, z)
		_backdrop.add_child(lmi)
		for i in 6:
			var t := float(i) / 5.0
			var b := MarigoldFX.make_papel_banner(
				_backdrop, 0.62, 0.45, colors[(i + s * 2) % colors.size()])
			b.position = Vector3(lerpf(x0, x1, t), y - sin(t * PI) * 0.22 - 0.25, z)


## ---------------- props ----------------

## A puff of glowing marigold petals (grabbed from the basket).
func _make_petal_puff(s: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "PetalPuff"
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var mat := MarigoldFX.glow(Color(1.0, 0.62, 0.10), 1.8)
	for i in 5:
		var petal := SphereMesh.new()
		petal.radius = 0.045 * s
		petal.height = 0.05 * s
		var pmi := MeshInstance3D.new()
		pmi.mesh = petal
		pmi.material_override = mat
		pmi.position = Vector3(
			rng.randf_range(-0.06, 0.06) * s,
			rng.randf_range(0.0, 0.06) * s,
			rng.randf_range(-0.06, 0.06) * s
		)
		pmi.scale = Vector3(1.0, 0.6, 1.4)
		root.add_child(pmi)
	return root


## Photo frame with a glowing abstract portrait silhouette (not a real person).
func _make_photo_frame(variant: int) -> Node3D:
	var root := Node3D.new()
	root.name = "PhotoFrame"
	var wood := MarigoldFX.pbr_preset(Color(0.30, 0.16, 0.07), "plastic")
	var back := BoxMesh.new()
	back.size = Vector3(0.36, 0.46, 0.035)
	var back_mi := MeshInstance3D.new()
	back_mi.mesh = back
	back_mi.material_override = wood
	back_mi.position.y = 0.23
	root.add_child(back_mi)
	# Glowing frame edge.
	var edge := BoxMesh.new()
	edge.size = Vector3(0.38, 0.03, 0.04)
	var edge_mi := MeshInstance3D.new()
	edge_mi.mesh = edge
	edge_mi.material_override = MarigoldFX.glow(Color(1.0, 0.60, 0.12), 1.3)
	edge_mi.position.y = 0.475
	root.add_child(edge_mi)
	# Abstract portrait: head-and-shoulders silhouette shader, tinted per frame.
	var tints := [Color(1.0, 0.55, 0.15), Color(1.0, 0.35, 0.55), Color(0.45, 0.70, 1.0)]
	var photo := PlaneMesh.new()
	photo.size = Vector2(0.30, 0.40)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 bg : source_color = vec4(0.07, 0.04, 0.12, 1.0);
uniform vec4 glow_col : source_color = vec4(1.0, 0.6, 0.15, 1.0);
uniform float seed = 0.0;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.66);
	float head = length(p * vec2(1.0 + seed * 0.15, 1.25)) - (0.13 + seed * 0.02);
	vec2 s = UV - vec2(0.5, 0.16);
	float shoulders = length(s * vec2(1.55, 1.0)) - 0.24;
	float halo = length(UV - vec2(0.5, 0.5)) - 0.34;
	float d = min(head, shoulders);
	float sil = smoothstep(0.015, -0.015, d);
	float ring = smoothstep(0.03, 0.0, abs(halo)) * 0.8;
	vec3 col = mix(bg.rgb, glow_col.rgb, sil);
	col += glow_col.rgb * ring;
	ALBEDO = col;
	EMISSION = glow_col.rgb * (sil * 0.7 + ring * 0.9);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("glow_col", tints[variant % tints.size()])
	sm.set_shader_parameter("seed", float(variant) * 0.5)
	photo.material = sm
	var photo_mi := MeshInstance3D.new()
	photo_mi.mesh = photo
	photo_mi.position = Vector3(0, 0.23, 0.020)
	root.add_child(photo_mi)
	return root


## Unlit candle. Lighting is added by _light_candle (budget: 3 real lights).
func _make_candle(slot: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Candle"
	root.position = slot
	_ofrenda.add_child(root)
	var wax := CylinderMesh.new()
	wax.top_radius = 0.035
	wax.bottom_radius = 0.042
	wax.height = 0.22
	var wax_mi := MeshInstance3D.new()
	wax_mi.mesh = wax
	wax_mi.material_override = MarigoldFX.pbr(Color(0.95, 0.88, 0.75), 0.0, 0.6)
	wax_mi.position.y = 0.11
	root.add_child(wax_mi)
	var wick := CylinderMesh.new()
	wick.top_radius = 0.006
	wick.bottom_radius = 0.006
	wick.height = 0.03
	var wick_mi := MeshInstance3D.new()
	wick_mi.mesh = wick
	wick_mi.material_override = MarigoldFX.pbr(Color(0.08, 0.06, 0.05), 0.0, 0.9)
	wick_mi.position.y = 0.235
	root.add_child(wick_mi)
	# Flame kit, hidden until lit.
	var kit := Node3D.new()
	kit.name = "FlameKit"
	kit.visible = false
	root.add_child(kit)
	var flame_mat := MarigoldFX.glow(Color(1.0, 0.65, 0.15), 3.0)
	var flame := SphereMesh.new()
	flame.radius = 0.026
	flame.height = 0.075
	var flame_mi := MeshInstance3D.new()
	flame_mi.mesh = flame
	flame_mi.material_override = flame_mat
	flame_mi.position.y = 0.28
	kit.add_child(flame_mi)
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.5
	p.position.y = 0.28
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.008
	pm.scale_max = 0.02
	pm.color = Color(1.0, 0.6, 0.15, 0.9)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = MarigoldFX.glow(Color(1.0, 0.6, 0.15), 2.5)
	p.draw_pass_1 = quad
	kit.add_child(p)
	_flame_nodes.append(kit)
	_flame_mats.append(flame_mat)
	return root


func _light_candle(idx: int) -> void:
	if _candle_lit[idx]:
		return
	_candle_lit[idx] = true
	_candles_lit_count += 1
	var kit: Node3D = _flame_nodes[idx]
	kit.visible = true
	for c in kit.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).emitting = true
	# Light budget: only 3 real lights; the rest are emissive-only.
	if _lights_used < 3:
		MarigoldFX.make_point_light(_candles[idx], Vector3(0, 0.38, 0), Color(1.0, 0.62, 0.25), 0.9, 3.5)
		_lights_used += 1
	MarigoldFX.spawn_sparks(self, _candles[idx].global_position + Vector3(0, 0.3, 0), Color(1.0, 0.7, 0.2), 12)
	MarigoldHaptics.thump()
	_sfx(48, 0.8, 1.6)
	_sfx(55, 0.5, 1.2)
	_toast("Candle lit — %d of 5" % _candles_lit_count)
	_update_progress()


## ---------------- interaction ----------------

## Pointer helpers with a viewport guard (headless/test-safe fallbacks).
## Desktop (non-XR): aim with the mouse cursor ray, and drop held items
## onto the y=1.0 work plane so the fixed desktop camera can still play.
## XR: use the shared hand-pointer fallback.
func _pointer_pos() -> Vector3:
	var ray := _pointer_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	if not MarigoldHands.is_xr_active() and absf(dir.y) > 0.001:
		var t := (1.0 - origin.y) / dir.y
		if t > 0.0 and t < 6.0:
			return origin + dir * t
	return origin + dir * 1.0


func _pointer_ray() -> Array:
	if get_viewport() == null:
		var o := global_position + Vector3(0, 1.2, -1.0)
		return [o, Vector3(0, 0, -1)]
	if not MarigoldHands.is_xr_active():
		var vp := get_viewport()
		var cam := vp.get_camera_3d()
		if cam != null:
			var mp := vp.get_mouse_position()
			return [cam.project_ray_origin(mp), cam.project_ray_normal(mp).normalized()]
	return MarigoldHands.pointer_ray(self, MarigoldHands.HAND_RIGHT)


func _on_pinch() -> void:
	if _finished:
		return
	if _held != null:
		_release_held()
		return
	var ray: Array = _pointer_ray()
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	# 1) Unlit candles light on pinch.
	for i in _candles.size():
		if _candle_lit[i]:
			continue
		var target: Vector3 = _candles[i].global_position + Vector3(0, 0.15, 0)
		if _ray_hit(origin, dir, target):
			_light_candle(i)
			return
	# 2) Frames on the side table can be grabbed.
	for i in _frames.size():
		var f := _frames[i]
		if not is_instance_valid(f) or f.get_parent() != _side_table:
			continue
		if _ray_hit(origin, dir, f.global_position + Vector3(0, 0.23, 0)):
			_grab_frame(i)
			return
	# 3) Basket gives a petal puff.
	if _petals_placed + (1 if _held_kind == "petal" else 0) < TOTAL_PETALS:
		if _ray_hit(origin, dir, _basket.global_position + Vector3(0, 0.15, 0)):
			_grab_petal()
			return


func _ray_hit(origin: Vector3, dir: Vector3, target: Vector3) -> bool:
	var to: Vector3 = target - origin
	var along: float = to.dot(dir)
	if along < 0.05 or along > MAX_GRAB_DIST:
		return false
	var closest: Vector3 = origin + dir * along
	return closest.distance_to(target) < GRAB_RADIUS


func _grab_petal() -> void:
	var puff := _make_petal_puff(1.0)
	add_child(puff)
	puff.global_position = _basket.global_position + Vector3(0, 0.25, 0)
	_held = puff
	_held_kind = "petal"
	_sfx(76, 0.35, 0.4)
	_update_basket_puffs()


func _grab_frame(idx: int) -> void:
	var f := _frames[idx]
	f.reparent(self)
	_held = f
	_held_kind = "frame"
	_held_frame_idx = idx
	_sfx(69, 0.35, 0.4)


func _release_held() -> void:
	var pointer: Vector3 = _pointer_pos()
	var local: Vector3 = _ofrenda.to_local(pointer)
	var over_ofrenda := absf(local.x) < 1.2 and local.y > 0.4 and local.y < 1.7 and absf(local.z) < 0.65
	if _held_kind == "petal":
		if over_ofrenda and _petals_placed < TOTAL_PETALS:
			_place_petal(local)
		else:
			_held.queue_free()
		_held = null
		_held_kind = ""
		_update_basket_puffs()
	elif _held_kind == "frame":
		var idx := _held_frame_idx
		if over_ofrenda and _frames_placed < TOTAL_FRAMES:
			_place_frame(idx)
		else:
			# Return to its home on the side table.
			_held.reparent(_side_table)
			_held.transform = _frame_home_local[idx]
		_held = null
		_held_kind = ""
		_held_frame_idx = -1
	_update_progress()


func _place_petal(local: Vector3) -> void:
	var slot := -1
	for i in _petal_used.size():
		if not _petal_used[i]:
			slot = i
			break
	if slot < 0:
		_held.queue_free()
		return
	_petal_used[slot] = true
	_petals_placed += 1
	_held.reparent(_ofrenda)
	_held.position = _petal_slots[slot]
	_held.rotation.y = randf() * TAU
	MarigoldFX.spawn_sparks(self, _ofrenda.to_global(_petal_slots[slot]), Color(1.0, 0.7, 0.2), 10)
	MarigoldHaptics.click()
	var petal_notes := [60, 62, 64, 67, 69, 72]
	_sfx(petal_notes[_petals_placed - 1], 0.7, 1.0)
	_toast("Petal placed — %d of 6" % _petals_placed)


func _place_frame(idx: int) -> void:
	var slot := -1
	for i in _frame_used.size():
		if not _frame_used[i]:
			slot = i
			break
	if slot < 0:
		_held.reparent(_side_table)
		_held.transform = _frame_home_local[idx]
		return
	_frame_used[slot] = true
	_frames_placed += 1
	_held.reparent(_ofrenda)
	_held.position = _frame_slots[slot]
	_held.rotation = Vector3(deg_to_rad(-6.0), 0, 0)
	MarigoldFX.spawn_sparks(self, _ofrenda.to_global(_frame_slots[slot] + Vector3(0, 0.3, 0)), Color(1.0, 0.8, 0.4), 10)
	MarigoldHaptics.thump()
	var frame_notes := [65, 69, 72]
	_sfx(frame_notes[_frames_placed - 1], 0.7, 1.2)
	_toast("Photo placed — %d of 3" % _frames_placed)


func _update_basket_puffs() -> void:
	var holding_petal := 1 if _held_kind == "petal" else 0
	var shown := TOTAL_PETALS - _petals_placed - holding_petal
	for i in _basket_puffs.size():
		_basket_puffs[i].visible = i < shown


func _update_progress() -> void:
	var total := _petals_placed + _frames_placed + _candles_lit_count
	if _progress_label:
		_progress_label.text = "Ofrenda: %d/%d" % [total, TOTAL_TASKS]
	if total >= TOTAL_TASKS and not _finished:
		_celebrate()


func _celebrate() -> void:
	_finished = true
	_party = true
	_progress_label.text = "¡La ofrenda está completa!"
	_toast("The spirits are welcomed home", 4.0)
	# Musical arpeggio, staggered.
	var notes := [60, 64, 67, 72, 76]
	for n in notes:
		_sfx(n, 0.8, 1.4)
		await get_tree().create_timer(0.14).timeout
	for top_y in [0.55, 0.95, 1.35]:
		MarigoldFX.scatter_petals(self, _ofrenda.to_global(Vector3(0, top_y, 0)), 40)
	MarigoldFX.spawn_confetti(self, _ofrenda.to_global(Vector3(0, 1.8, 0)), 70)
	MarigoldHaptics.fanfare()
	# Second beat: spirit butterflies rise from the arch as the flames surge.
	await get_tree().create_timer(1.0).timeout
	MarigoldFX.scatter_petals(self, _ofrenda.to_global(Vector3(0, 3.3, -0.78)), 50)
	MarigoldFX.spawn_sparks(self, _ofrenda.to_global(Vector3(0, 2.4, -0.78)), Color(1.0, 0.85, 0.4), 30)
	await get_tree().create_timer(2.0).timeout
	chapter_complete.emit()
