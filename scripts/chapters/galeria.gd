## galeria.gd - MARIGOLD experience: Galeria de Recuerdos (v0.6.0, finding 2).
## The in-world photo gallery: papel-picado-framed prints on a wall showing
## the 12 festival moments MarigoldPhotos collected across chapters.
## Uncaptured moments show as framed silhouettes ("memory not yet made").
## No class_name (experience contract). Signal + setup/apply_mode contract.
extends Node3D

signal chapter_complete

const C_CREAM := Color(1.0, 0.93, 0.82)
const C_GOLD := Color(1.0, 0.80, 0.30)

var _ar_mode := false
var _stage: Node3D
var _backdrop: Node3D
var _plaque: Node3D
var _stage_home := Vector3(0, 0, -0.2)


func setup(ar_mode: bool) -> void:
	_build()
	apply_mode(ar_mode)


func apply_mode(on: bool) -> void:
	_ar_mode = on
	if _backdrop != null:
		_backdrop.visible = not on
	if _stage == null:
		return
	if on:
		if not MarigoldHands.apply_anchor(_stage, "marigold_galeria"):
			MarigoldHands.place_on_table(_stage)
			MarigoldHands.save_anchor("marigold_galeria", _stage.global_transform)
	else:
		_stage.position = _stage_home
		_stage.rotation = Vector3.ZERO


func _process(_delta: float) -> void:
	# The gallery is a stroll, not a task: it completes only when the
	# player exits via the pause menu. Keep the plaque readable.
	if _plaque and is_instance_valid(_plaque):
		MarigoldPlaques.face_player(_plaque)


func _build() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	_stage.position = _stage_home
	add_child(_stage)
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	_backdrop.position = _stage_home
	add_child(_backdrop)
	MarigoldFX.make_point_light(_stage, Vector3(0, 2.2, -1.2), Color(1.0, 0.80, 0.45), 1.0, 8.0)
	# The gallery wall.
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(7.2, 3.0, 0.12)
	wall.mesh = wm
	wall.material_override = MarigoldFX.pbr(Color(0.16, 0.08, 0.10), 0.0, 0.9)
	wall.position = Vector3(0, 1.5, -2.6)
	_backdrop.add_child(wall)
	var trim := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(7.4, 0.14, 0.18)
	trim.mesh = tm
	trim.material_override = MarigoldFX.pbr(Color(0.55, 0.20, 0.35), 0.0, 0.6)
	trim.position = Vector3(0, 3.05, -2.6)
	_backdrop.add_child(trim)
	MarigoldModels.make_flower_field(_backdrop, 60, 3.0, 5151).position = Vector3(0, 0, -2.0)
	var title := MarigoldFX.make_label("Galeria de Recuerdos", 84, C_GOLD)
	title.position = Vector3(0, 3.35, -2.5)
	_stage.add_child(title)
	_plaque = MarigoldPlaques.place_plaque(self,
		"Galeria de Recuerdos",
		"Your festival memories, framed in papel picado. Every moment you photographed lives here - the ones still silhouettes are waiting for you in the chapters.",
		Vector3(-2.6, 1.5, -1.2), 1.9)
	_build_frames()


## 12 frames in a 4x3 grid: captured moments show their thumbnail texture,
## missing ones show a silhouette with the moment name.
func _build_frames() -> void:
	var snaps := MarigoldPhotos.read_all()
	var got: Array = snaps.get("captured", [])
	var ids := MarigoldPhotos.moment_ids()
	var cols := 4
	for i in 12:
		var mid := String(ids[i])
		var mname := MarigoldPhotos.moment_name(mid)
		var col_i := i % cols
		var row_i := i / cols
		var x := -2.7 + float(col_i) * 1.8
		var y := 2.35 - float(row_i) * 0.95
		var frame := Node3D.new()
		frame.position = Vector3(x, y, -2.5)
		_stage.add_child(frame)
		# Papel-picado frame: festive border (scaled procedural banner).
		var border := MeshInstance3D.new()
		var bm := QuadMesh.new()
		bm.size = Vector2(1.5, 0.78)
		border.mesh = bm
		border.material_override = MarigoldPapelPicado.banner_material(700 + i)
		border.position = Vector3(0, 0, 0.01)
		frame.add_child(border)
		var is_got := false
		for gmid in got:
			if String(gmid) == mid:
				is_got = true
				break
		if is_got:
			var tex := MarigoldPhotos.load_thumb(mid)
			var print := MeshInstance3D.new()
			var pm := QuadMesh.new()
			pm.size = Vector2(1.28, 0.60)
			print.mesh = pm
			if tex != null:
				var pm2 := StandardMaterial3D.new()
				pm2.albedo_texture = tex
				pm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				print.material_override = pm2
			else:
				print.material_override = MarigoldFX.pbr(Color(0.25, 0.15, 0.30), 0.0, 0.8)
			print.position = Vector3(0, 0, 0.02)
			frame.add_child(print)
		else:
			var sil := MeshInstance3D.new()
			var sm := QuadMesh.new()
			sm.size = Vector2(1.28, 0.60)
			sil.mesh = sm
			sil.material_override = MarigoldFX.pbr(Color(0.10, 0.06, 0.12), 0.0, 1.0)
			sil.position = Vector3(0, 0, 0.02)
			frame.add_child(sil)
			var q := MeshInstance3D.new()
			var qm := SphereMesh.new()
			qm.radius = 0.08
			qm.height = 0.16
			q.mesh = qm
			q.material_override = MarigoldFX.glow(C_GOLD, 1.2)
			q.position = Vector3(0, 0.05, 0.03)
			frame.add_child(q)
		var lab := MarigoldFX.make_label(mname, 34, C_GOLD if is_got else Color(0.5, 0.45, 0.5))
		lab.position = Vector3(0, -0.52, 0.02)
		frame.add_child(lab)
	var snaps2 := MarigoldPhotos.read_all()
	var count := (snaps2.get("captured", []) as Array).size()
	var tally := MarigoldFX.make_label("%d / 12 momentos" % count, 56, C_GOLD)
	tally.position = Vector3(0, 0.45, -2.5)
	_stage.add_child(tally)
