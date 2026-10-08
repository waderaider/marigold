## MarigoldPhotos.gd - diegetic camera + festival-moment collection (v0.6.0).
## The controller becomes a folk-art camera when picked up; trigger/pinch
## snaps a small thumbnail (320x180 PNG) into user://photos/. Twelve
## festival moments auto-detect via note_moment(id) called from chapter
## beats. Collection persists in MarigoldSettings; the Galeria experience
## shows the prints on a papel-framed wall.
extends RefCounted
class_name MarigoldPhotos

const PHOTO_DIR := "user://photos/"
const THUMB_W := 320
const THUMB_H := 180

## The 12 collectible festival moments (id -> display name).
const MOMENTS := {
	"mirror_self": "Your Reflection",
	"ofrenda_reveal": "The Ofrenda Awakens",
	"viva_night": "Night Falls",
	"the_bow": "The Bow",
	"bridge_cross": "The Marigold Bridge",
	"guide_greet": "Spirit Guide Greeting",
	"all_fed": "All Guides Fed",
	"pet_bliss": "Spirit Friend",
	"paint_alive": "Painted Alebrije",
	"band_phrase": "Street Band",
	"baile_finale": "El Gran Baile",
	"ofrenda_done": "Your Ofrenda",
}


## Build the hand-held folk-art camera prop. Returns the root Node3D.
## Call take_camera(root) with the grabbed node to arm it.
static func make_camera_prop() -> Node3D:
	var root := Node3D.new()
	root.name = "FolkCamera"
	var wood := MarigoldFX.pbr(Color(0.45, 0.22, 0.10), 0.1, 0.5)
	var brass := MarigoldFX.pbr(Color(0.85, 0.62, 0.25), 0.8, 0.35)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.12, 0.10)
	body.mesh = bm
	body.material_override = wood
	root.add_child(body)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.035
	lm.bottom_radius = 0.045
	lm.height = 0.06
	lm.radial_segments = 16
	lens.mesh = lm
	lens.material_override = brass
	lens.rotation_degrees.x = 90.0
	lens.position = Vector3(0, 0, -0.08)
	root.add_child(lens)
	var glass := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.028
	gm.height = 0.02
	glass.mesh = gm
	glass.material_override = MarigoldFX.glow(Color(0.5, 0.8, 1.0), 1.2)
	glass.position = Vector3(0, 0, -0.115)
	root.add_child(glass)
	# Painted marigold dot on top (folk-art mark).
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.02
	dm.height = 0.04
	dot.mesh = dm
	dot.material_override = MarigoldFX.glow(Color(1.0, 0.6, 0.1), 1.8)
	dot.position = Vector3(0, 0.07, 0)
	root.add_child(dot)
	root.set_meta("is_camera", true)
	return root


## Snap a thumbnail from the current viewport. Returns the saved path or "".
static func snap(node: Node, moment_id: String = "") -> String:
	var vp := node.get_viewport()
	if vp == null:
		return ""
	var tex := vp.get_texture()
	if tex == null:
		return ""
	var img := tex.get_image()
	if img == null or img.is_empty():
		return ""
	img.resize(THUMB_W, THUMB_H, Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var id := moment_id if moment_id != "" else "snap"
	var path := "%smarigold_%s_%d.png" % [PHOTO_DIR, id, Time.get_ticks_msec() % 100000]
	if img.save_png(path) != OK:
		return ""
	_register_photo(id, path)
	return path


## Record a festival moment. Returns true if it was new (toast-worthy).
static func note_moment(id: String) -> bool:
	if not MOMENTS.has(id):
		return false
	var seen: Array = MarigoldSettings.get_value("photos", "moments", [])
	if seen.has(id):
		return false
	seen.append(id)
	MarigoldSettings.set_value("photos", "moments", seen)
	return true


## Auto-capture: note the moment AND snap a thumbnail (best-effort).
## Returns the moment display name when newly captured, "" otherwise.
static func capture_moment(node: Node, id: String) -> String:
	if not note_moment(id):
		return ""
	snap(node, id)
	return String(MOMENTS.get(id, id))


static func moments_seen() -> Array:
	return MarigoldSettings.get_value("photos", "moments", [])


static func moment_count() -> int:
	return moments_seen().size()


static func _register_photo(id: String, path: String) -> void:
	var shots: Array = MarigoldSettings.get_value("photos", "shots", [])
	shots.append({"id": id, "path": path})
	# Cap at 48 stored shots (thumbnails are ~40 KB each).
	while shots.size() > 48:
		var old: Dictionary = shots.pop_front()
		var p := String(old.get("path", ""))
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	MarigoldSettings.set_value("photos", "shots", shots)


static func list_shots() -> Array:
	return MarigoldSettings.get_value("photos", "shots", [])


## Moment display helper for toasts: "The Bow (4/12)".
static func progress_text() -> String:
	return "(%d/12)" % moment_count()


static func moment_ids() -> Array:
	return MOMENTS.keys()


static func moment_name(id: String) -> String:
	return String(MOMENTS.get(id, id))


## Gallery data: {"captured": [moment ids], "thumbs": {id: png path}}.
static func read_all() -> Dictionary:
	var thumbs := {}
	for s in list_shots():
		var d: Dictionary = s
		thumbs[String(d.get("id", ""))] = String(d.get("path", ""))
	return {"captured": moments_seen(), "thumbs": thumbs}


## Load the saved thumbnail for a moment, or null when none was snapped.
static func load_thumb(id: String) -> Texture2D:
	var data := read_all()
	var path := String((data["thumbs"] as Dictionary).get(id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D
