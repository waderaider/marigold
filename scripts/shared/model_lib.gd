## model_lib.gd - shared CC0 3D model loader for MARIGOLD v0.2.0.
## All models are Kenney (kenney.nl) CC0 packs - no attribution required.
## Cached PackedScene loading + recolor helpers. Headless-safe.
extends RefCounted
class_name MarigoldModels

const BASE := "res://assets/models/kenney/"
const BLENDER_BASE := "res://assets/models/blender/"

## Pack subdirectories.
const GRAVEYARD := "graveyard/"
const NATURE := "nature/"
const FANTASY := "fantasy/"
const FURNITURE := "furniture/"
## In-house Blender originals (no license encumbrance).
const ALEBRIJES := "alebrijes/"
const GUITAR := "guitar/"
const OFRENDA := "ofrenda/"

static var _cache := {}


## Load (and cache) a model scene by pack + filename (without extension).
## Returns an instantiated Node3D, or null if the model is missing.
static func instance(pack: String, model_name: String) -> Node3D:
	var path := BASE + pack + model_name + ".fbx"
	if _cache.has(path):
		var cached: PackedScene = _cache[path]
		if cached != null and is_instance_valid(cached):
			return cached.instantiate() as Node3D
		_cache.erase(path)
	if not ResourceLoader.exists(path):
		push_warning("[MarigoldModels] missing model: " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("[MarigoldModels] failed to load: " + path)
		return null
	_cache[path] = ps
	return ps.instantiate() as Node3D


## Load an in-house Blender GLB (e.g. alebrijes). Same cache contract.
static func blender_model(subdir: String, model_name: String) -> Node3D:
	var path := BLENDER_BASE + subdir + model_name + ".glb"
	if _cache.has(path):
		var cached: PackedScene = _cache[path]
		if cached != null and is_instance_valid(cached):
			return cached.instantiate() as Node3D
		_cache.erase(path)
	if not ResourceLoader.exists(path):
		push_warning("[MarigoldModels] missing blender model: " + path)
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("[MarigoldModels] failed to load: " + path)
		return null
	_cache[path] = ps
	return ps.instantiate() as Node3D


## Find a descendant node by name fragment (case-insensitive). Used to map
## Blender part names (wings, head, tail...) to animation slots.
static func find_part(root: Node, fragment: String) -> Node3D:
	var frag := fragment.to_lower()
	var stack: Array = [root]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		if n is Node3D and String(n.name).to_lower().contains(frag):
			return n as Node3D
		for c in n.get_children():
			stack.append(c)
	return null


## Enable vertex-color albedo (+ optional emissive) on every mesh material
## under root. For in-house vertex-colored GLBs. Duplicates shared materials
## so per-guide glow pulsing stays independent.
static func enable_vertex_colors(root: Node, emission: Color = Color(0, 0, 0),
		emission_energy: float = 0.0) -> Array:
	var mats: Array = []
	var dup_cache := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var n := stack.pop_back() as Node
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var src: Material = mi.get_active_material(0)
			if src is StandardMaterial3D:
				if not dup_cache.has(src):
					var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					dup.vertex_color_use_as_albedo = true
					if emission_energy > 0.0:
						dup.emission_enabled = true
						dup.emission = emission
						dup.emission_energy_multiplier = emission_energy
					dup_cache[src] = dup
					mats.append(dup)
				mi.material_override = dup_cache[src]
		for c in n.get_children():
			stack.append(c)
	return mats


## Model-space AABB of every mesh under a root (for scale normalization).
static func bounds_of(model: Node) -> AABB:
	var bounds := AABB()
	var first := true
	var stack: Array = [[model, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var t: Transform3D = item[1]
		var lt := t
		if n is Node3D:
			lt = t * (n as Node3D).transform
		if n is MeshInstance3D:
			var mesh := (n as MeshInstance3D).mesh
			if mesh != null:
				var ma: AABB = lt * mesh.get_aabb()
				if first:
					bounds = ma
					first = false
				else:
					bounds = bounds.merge(ma)
		for c in n.get_children():
			stack.append([c, lt])
	return bounds


## Place a model under a parent with transform. Returns the instance (or null).
static func place(parent: Node3D, pack: String, model_name: String, pos: Vector3 = Vector3.ZERO, rot_y_deg: float = 0.0, scl: float = 1.0) -> Node3D:
	var n := instance(pack, model_name)
	if n == null:
		return null
	n.position = pos
	n.rotation.y = deg_to_rad(rot_y_deg)
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	return n


## Recolor every mesh surface in a model instance with a PBR material.
## Use for marigolds (orange), alebrije accents, etc.
static func recolor(root: Node, albedo: Color, metallic: float = 0.0, roughness: float = 0.6, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> void:
	if root == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	_apply_recursive(root, mat)


## Apply a vivid emissive glow recolor (for marigolds, spirit guides).
static func recolor_glow(root: Node, albedo: Color, emission: Color, energy: float = 2.2) -> void:
	recolor(root, albedo, 0.0, 0.5, emission, energy)


static func _apply_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_apply_recursive(c, mat)


## Field of REAL marigold flower models (Kenney nature-kit), instanced.
## Dramatically richer than the v0.1.0 sphere blossoms.
static func make_flower_field(parent: Node3D, count: int = 160, radius: float = 9.0, seed: int = 12345) -> Node3D:
	var root := Node3D.new()
	root.name = "FlowerField"
	parent.add_child(root)
	var variants := ["flower_redA", "flower_redB", "flower_yellowA", "flower_yellowB"]
	var orange := Color(1.0, 0.52, 0.08)
	var deep_orange := Color(0.95, 0.38, 0.05)
	var gold := Color(1.0, 0.72, 0.15)
	var tints := [orange, deep_orange, gold, orange]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var v: String = variants[i % variants.size()]
		var f := instance(NATURE, v)
		if f == null:
			continue
		var tint: Color = tints[i % tints.size()]
		# Petals glow like embers; stems stay dark via per-mesh split is overkill,
		# so glow the whole flower - reads as luminous marigold at distance.
		recolor_glow(f, tint, tint, rng.randf_range(1.4, 2.4))
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		var s := rng.randf_range(0.8, 1.7)
		f.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		f.rotation.y = rng.randf() * TAU
		f.scale = Vector3.ONE * s
		root.add_child(f)
	return root


## Row of real flowers along a line (for bridge rails, arch trim).
static func make_flower_row(parent: Node3D, from: Vector3, to: Vector3, count: int = 12, seed: int = 99) -> Node3D:
	var root := Node3D.new()
	root.name = "FlowerRow"
	parent.add_child(root)
	var variants := ["flower_redA", "flower_yellowA", "flower_redB", "flower_yellowB"]
	var tints := [Color(1.0, 0.55, 0.08), Color(1.0, 0.75, 0.18)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var f := instance(NATURE, variants[i % variants.size()])
		if f == null:
			continue
		var tint: Color = tints[i % tints.size()]
		recolor_glow(f, tint, tint, 2.0)
		f.position = from.lerp(to, t)
		f.rotation.y = rng.randf() * TAU
		var s := rng.randf_range(0.7, 1.1)
		f.scale = Vector3.ONE * s
		root.add_child(f)
	return root
