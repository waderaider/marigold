## model_lib.gd - shared CC0 3D model loader for MARIGOLD v0.2.0.
## All models are Kenney (kenney.nl) CC0 packs - no attribution required.
## Cached PackedScene loading + recolor helpers. Headless-safe.
extends RefCounted
class_name MarigoldModels

const BASE := "res://assets/models/kenney/"

## Pack subdirectories.
const GRAVEYARD := "graveyard/"
const NATURE := "nature/"
const FANTASY := "fantasy/"
const FURNITURE := "furniture/"

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
