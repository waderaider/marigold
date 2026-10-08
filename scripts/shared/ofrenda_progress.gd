## MarigoldOfrenda.gd - ofrenda-building progression (v0.6.0).
## Four memory objects collected across chapters, arranged on the player's
## OWN ofrenda in the plaza; the finale reveals the completed altar in a
## candle-lit room. Persists in MarigoldSettings.
##
## Items (all original designs, no licensed content):
## - "foto": a photo - earned at ch1's photo ignition (Ofrenda Viva)
## - "pan": a pan de muerto roll - earned crossing the ch2 bridge
## - "marigold": a marigold bloom - earned feeding all four ch3 guides
## - "pick": a guitar pick - earned finishing a Guitarra song
extends RefCounted
class_name MarigoldOfrenda

const ITEMS := {
	"foto": "Abuela's Photo",
	"pan": "Pan de Muerto",
	"marigold": "Marigold Bloom",
	"pick": "Guitar Pick",
}

const ITEM_ORDER := ["foto", "pan", "marigold", "pick"]


static func collect(id: String) -> bool:
	if not ITEMS.has(id):
		return false
	var have: Array = MarigoldSettings.get_value("ofrenda", "items", [])
	if have.has(id):
		return false
	have.append(id)
	MarigoldSettings.set_value("ofrenda", "items", have)
	return true


static func has(id: String) -> bool:
	var have: Array = MarigoldSettings.get_value("ofrenda", "items", [])
	return have.has(id)


static func collected() -> Array:
	return MarigoldSettings.get_value("ofrenda", "items", [])


static func count() -> int:
	return collected().size()


static func is_complete() -> bool:
	return count() >= ITEM_ORDER.size()


static func missing() -> Array:
	var have := collected()
	var out: Array = []
	for id in ITEM_ORDER:
		if not have.has(id):
			out.append(id)
	return out


## Build one memory-object prop for the ofrenda shelf. Original designs.
static func make_item_prop(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "OfrendaItem_" + id
	match id:
		"foto":
			var fr := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.16, 0.20, 0.015)
			fr.mesh = fm
			fr.material_override = MarigoldFX.pbr(Color(0.55, 0.32, 0.14), 0.0, 0.6)
			root.add_child(fr)
			var ph := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.12, 0.15, 0.018)
			ph.mesh = pm
			ph.material_override = MarigoldFX.glow(Color(1.0, 0.85, 0.6), 0.8)
			root.add_child(ph)
		"pan":
			var bread := MeshInstance3D.new()
			var bm := SphereMesh.new()
			bm.radius = 0.07
			bm.height = 0.09
			bread.mesh = bm
			bread.material_override = MarigoldFX.pbr(Color(0.80, 0.55, 0.28), 0.0, 0.85)
			bread.scale = Vector3(1.2, 0.75, 1.0)
			root.add_child(bread)
			for k in 4: # scored cross bones on top
				var bone := MeshInstance3D.new()
				var om := BoxMesh.new()
				om.size = Vector3(0.10, 0.015, 0.02)
				bone.mesh = om
				bone.material_override = MarigoldFX.pbr(Color(0.88, 0.65, 0.35), 0.0, 0.85)
				bone.position = Vector3(0, 0.055, 0)
				bone.rotation.y = float(k) * PI / 4.0
				root.add_child(bone)
		"marigold":
			var f := MarigoldModels.instance(MarigoldModels.NATURE, "flower_yellowA")
			if f != null:
				MarigoldModels.recolor_glow(f, Color(1.0, 0.52, 0.08), Color(1.0, 0.52, 0.08), 1.8)
				f.scale = Vector3.ONE * 1.6
				root.add_child(f)
			else:
				var fb := MeshInstance3D.new()
				var fm2 := SphereMesh.new()
				fm2.radius = 0.06
				fm2.height = 0.10
				fb.mesh = fm2
				fb.material_override = MarigoldFX.glow(Color(1.0, 0.55, 0.1), 1.8)
				root.add_child(fb)
		"pick":
			var pk := MeshInstance3D.new()
			var pm3 := BoxMesh.new()
			pm3.size = Vector3(0.035, 0.045, 0.008)
			pk.mesh = pm3
			pk.material_override = MarigoldFX.pbr(Color(0.90, 0.75, 0.40), 0.6, 0.3)
			pk.rotation.z = 0.5
			root.add_child(pk)
	return root


## Small ofrenda shelf: 4 slots in a row; collected items appear.
## Returns the root; call refresh_shelf(root) after collecting.
static func make_shelf() -> Node3D:
	var root := Node3D.new()
	root.name = "OfrendaShelf"
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.3, 0.08, 0.45)
	table.mesh = tm
	table.material_override = MarigoldFX.pbr(Color(0.42, 0.24, 0.12), 0.0, 0.7)
	table.position = Vector3(0, 0.75, 0)
	root.add_child(table)
	for lx in [-0.5, 0.5]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.07, 0.75, 0.35)
		leg.mesh = lm
		leg.material_override = MarigoldFX.pbr(Color(0.35, 0.20, 0.10), 0.0, 0.7)
		leg.position = Vector3(lx, 0.37, 0)
		root.add_child(leg)
	# Slot markers (empty = dim outline, filled = item prop).
	for i in ITEM_ORDER.size():
		var slot := Node3D.new()
		slot.name = "Slot_" + ITEM_ORDER[i]
		slot.position = Vector3(-0.45 + float(i) * 0.30, 0.86, 0)
		root.add_child(slot)
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 0.07
		rm.outer_radius = 0.10
		rm.rings = 16
		rm.ring_segments = 6
		ring.mesh = rm
		ring.material_override = MarigoldFX.glow(Color(1.0, 0.7, 0.25), 0.9)
		ring.rotation_degrees.x = 90.0
		slot.add_child(ring)
		slot.set_meta("ring", ring)
	# Label.
	var lab := MarigoldFX.make_label("Tu Ofrenda", 44, Color(1.0, 0.85, 0.5))
	lab.position = Vector3(0, 1.35, 0)
	root.add_child(lab)
	refresh_shelf(root)
	return root


## Show collected items on the shelf; dim rings for missing ones.
static func refresh_shelf(root: Node3D) -> void:
	if root == null or not is_instance_valid(root):
		return
	for id in ITEM_ORDER:
		var slot := root.get_node_or_null("Slot_" + id) as Node3D
		if slot == null:
			continue
		for c in slot.get_children():
			if (c as Node3D) != slot.get_meta("ring"):
				c.queue_free()
		var ring := slot.get_meta("ring") as MeshInstance3D
		if has(id):
			var prop := make_item_prop(id)
			prop.position.y = 0.06
			slot.add_child(prop)
			if ring != null and is_instance_valid(ring):
				var m := ring.material_override as StandardMaterial3D
				if m != null:
					m.emission_energy_multiplier = 2.2
		else:
			if ring != null and is_instance_valid(ring):
				var m2 := ring.material_override as StandardMaterial3D
				if m2 != null:
					m2.emission_energy_multiplier = 0.5
