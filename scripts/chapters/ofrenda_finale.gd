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
var _plaque: Node3D
var _stage_home := Vector3(0, 0, -0.2)
var _revealed := false


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)
	if MarigoldSky.instance != null:
		MarigoldSky.instance.set_time_mode("fixed")
		MarigoldSky.instance.set_time_of_day(21.0) # candle-lit night
		MarigoldSky.instance.set_weather("clear")


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
	_t += delta
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)
	# Candle flames breathe.
	for i in _candle_mats.size():
		var m: StandardMaterial3D = _candle_mats[i]
		if m != null and is_instance_valid(m):
			var base := 1.6 if not _revealed else 2.6
			m.emission_energy_multiplier = base + sin(_t * 9.0 + float(i) * 1.7) * 0.5
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
	floor_mi.material_override = MarigoldFX.pbr(Color(0.10, 0.06, 0.08), 0.0, 0.9)
	floor_mi.position = Vector3(0, 0, -2.0)
	_backdrop.add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(14, 5, 0.2)
	wall.mesh = wm
	wall.material_override = MarigoldFX.pbr(Color(0.12, 0.06, 0.09), 0.0, 0.95)
	wall.position = Vector3(0, 2.5, -4.6)
	_backdrop.add_child(wall)
	# The player's ofrenda, full size, centered.
	_shelf = MarigoldOfrenda.make_shelf()
	_shelf.position = Vector3(0, 0, -3.0)
	_stage.add_child(_shelf)
	_build_candle_ring()
	_build_papel_frame()
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
	# beyond the chapter's shared budget).
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	for i in 14:
		var a := TAU * float(i) / 14.0
		var r := 2.0
		var pos := Vector3(cos(a) * r, 0, -3.0 + sin(a) * r * 0.7)
		var stick := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.035
		sm.bottom_radius = 0.035
		sm.height = rng.randf_range(0.25, 0.45)
		stick.mesh = sm
		stick.material_override = MarigoldFX.pbr(C_CREAM, 0.0, 0.6)
		stick.position = pos + Vector3(0, 0.15, 0)
		_stage.add_child(stick)
		var flame := MeshInstance3D.new()
		var fm2 := SphereMesh.new()
		fm2.radius = 0.035
		fm2.height = 0.09
		flame.mesh = fm2
		var fmat := MarigoldFX.glow(Color(1.0, 0.62, 0.18), 1.6)
		flame.material_override = fmat
		flame.position = pos + Vector3(0, 0.42, 0)
		_stage.add_child(flame)
		_candle_mats.append(fmat)


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


func _reveal() -> void:
	_revealed = true
	_update_progress_toast()
	MarigoldHaptics.fanfare()
	MarigoldFX.spawn_confetti(_stage, Vector3(0, 2.0, -3.0), 80)
	MarigoldFX.scatter_petals(_stage, Vector3(0, 1.5, -3.0), 60)
	if MarigoldState.music != null and MarigoldState.music.has_method("play_stinger"):
		MarigoldState.music.play_stinger("bow_drum", -4.0)
	var fam := MarigoldFX.make_label("La Familia Williams", 64, Color(1.0, 0.88, 0.55))
	fam.position = Vector3(0, 2.35, -4.35)
	_stage.add_child(fam)
	MarigoldPhotos.note_moment("ofrenda_done")
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func() -> void: chapter_complete.emit())
