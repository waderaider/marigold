## MarigoldControllerSkins.gd - styled controller render models + button legend.
## v0.5.0 (permanent feature, mirrors the NEXUS rule): in controller games,
## render a virtual model 1:1 over each real controller, styled per chapter
## with a small accessory, plus a button legend shown at chapter start and
## re-openable from the pause menu's Controls page.
##
## Render model path (verified in the godotopenxrvendors 5.1.0 binary):
## OpenXRFbRenderModel node + set_render_model_type(MODEL_CONTROLLER_LEFT /
## MODEL_CONTROLLER_RIGHT); enable key openxr/extensions/meta/render_model.
## Graceful fallback: a clean stylized primitive controller (<1k tris) when
## the system model is unavailable. Everything is cheap and headless-safe.
extends RefCounted
class_name MarigoldControllerSkins

const ACCENT := Color(1.0, 0.68, 0.18)

## Per-chapter button maps: [button label, what it does].
const BUTTON_MAPS := {
	"global": [
		["Trigger", "Select / pinch"],
		["Menu button", "Pause menu"],
	],
	"ch1": [
		["Pinch / Trigger", "Grab a petal, photo or candle"],
		["Release", "Place it on the ofrenda / light the flame"],
	],
	"ch2": [
		["Walk", "Cross the bridge through each glowing ring"],
		["Pinch / Trigger", "Interact"],
	],
	"ch3": [
		["Pinch / Trigger", "Send a light orb to a spirit guide"],
	],
	"ch4": [
		["Wave hands", "Ripple the papel picado banners"],
	],
	"ch5": [
		["Move hands", "Copy the dance leader's moves"],
	],
	"guitarra": [
		["Swipe hand", "Strum the guitar strings"],
		["Pinch", "Hit the falling note / choose an orb"],
	],
	"mano_magica": [
		["Pinch", "Bloom the marigold / grab the light"],
		["Release", "Throw the petals"],
		["Move while pinching", "Sculpt the clay"],
	],
	"espejo": [
		["Dance", "Your skeleton mirrors your real moves"],
	],
}

## Chapter key -> accessory style on the controllers.
const ACCESSORIES := {
	"guitarra": "pick",
	"mano_magica": "spark",
	"espejo": "ring",
}


## Legend text for the pause menu Controls page.
static func legend_text(chapter_key: String) -> String:
	var lines: Array = []
	for row in BUTTON_MAPS.get("global", []):
		lines.append("%s - %s" % [row[0], row[1]])
	for row in BUTTON_MAPS.get(chapter_key, []):
		lines.append("%s - %s" % [row[0], row[1]])
	return "\n".join(lines)


## Style both controllers for a chapter: system render model when available,
## stylized fallback otherwise, plus the chapter accessory. Idempotent.
static func apply(xr_origin: Node3D, chapter_key: String) -> void:
	if xr_origin == null or not is_instance_valid(xr_origin):
		return
	for side in ["LeftController", "RightController"]:
		var ctl := xr_origin.get_node_or_null(side) as XRController3D
		if ctl == null:
			continue
		_style_controller(ctl, side, chapter_key)


static func _style_controller(ctl: XRController3D, side: String, chapter_key: String) -> void:
	var is_left := side == "LeftController"
	# Re-style: drop a previous skin rig.
	var old := ctl.get_node_or_null("ControllerSkin")
	if old != null:
		old.queue_free()
	var rig := Node3D.new()
	rig.name = "ControllerSkin"
	ctl.add_child(rig)
	var ok := _add_system_model(rig, is_left)
	if not ok:
		rig.add_child(_stylized_controller())
	_add_accessory(rig, String(ACCESSORIES.get(chapter_key, "ring")))


## System render model via the Meta extension. Returns true when the model
## node instanced successfully.
static func _add_system_model(rig: Node3D, is_left: bool) -> bool:
	if not ClassDB.class_exists("OpenXRFbRenderModel"):
		return false
	var rm = ClassDB.instantiate("OpenXRFbRenderModel")
	if rm == null:
		return false
	var type_id := _render_model_type_id(is_left)
	if type_id >= 0:
		rm.set("render_model_type", type_id)
	rig.add_child(rm)
	if rm.has_method("get_render_model_node"):
		return rm.call("get_render_model_node") != null
	return true


## Resolve MODEL_CONTROLLER_LEFT/RIGHT to its int value at runtime.
## Godot 4's ClassDB has no constant-value getter (verified against the 4.7.2
## binary), so derive it from the render_model_type enum property's hint
## string: editor dropdown order == enum value order, and explicit "N:Name"
## entries are honored. Falls back to sequential 0/1 when the hint is missing.
static func _render_model_type_id(is_left: bool) -> int:
	var want := "left" if is_left else "right"
	if ClassDB.class_exists("OpenXRFbRenderModel"):
		for p in ClassDB.class_get_property_list("OpenXRFbRenderModel", true):
			var d: Dictionary = p
			if String(d.get("name", "")) != "render_model_type":
				continue
			var idx := 0
			for part in String(d.get("hint_string", "")).split(","):
				var entry := part.strip_edges()
				var val := idx
				if entry.contains(":"):
					val = int(entry.get_slice(":", 0))
					entry = entry.get_slice(":", 1)
				if entry.to_lower().contains(want):
					return val
				idx += 1
	# Fallback: sequential enum (LEFT=0, RIGHT=1) per declaration order.
	return 0 if is_left else 1


## Clean stylized fallback controller: rounded grip + trigger + thumbstick,
## marigold accent. ~300 tris.
static func _stylized_controller() -> Node3D:
	var root := Node3D.new()
	var dark := MarigoldFX.pbr(Color(0.12, 0.10, 0.14), 0.3, 0.5)
	var grip := MeshInstance3D.new()
	var gm := CapsuleMesh.new()
	gm.radius = 0.021
	gm.height = 0.11
	gm.radial_segments = 12
	gm.material = dark
	grip.mesh = gm
	grip.rotation_degrees.x = 18.0
	root.add_child(grip)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.032
	hm.height = 0.05
	hm.radial_segments = 12
	hm.rings = 6
	hm.material = dark
	head.mesh = hm
	head.position = Vector3(0, 0.055, -0.012)
	root.add_child(head)
	var trig := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.018, 0.035, 0.014)
	tm.material = MarigoldFX.pbr(Color(0.2, 0.18, 0.22), 0.3, 0.5)
	trig.mesh = tm
	trig.position = Vector3(0, 0.035, 0.022)
	trig.rotation_degrees.x = -18.0
	root.add_child(trig)
	var stick := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.011
	sm.bottom_radius = 0.013
	sm.height = 0.014
	sm.radial_segments = 12
	sm.material = dark
	stick.mesh = sm
	stick.position = Vector3(0, 0.082, -0.012)
	root.add_child(stick)
	# Marigold accent ring around the grip.
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.020
	rm.outer_radius = 0.026
	rm.rings = 20
	rm.ring_segments = 8
	rm.material = MarigoldFX.glow(ACCENT, 1.6)
	ring.mesh = rm
	ring.position = Vector3(0, -0.01, 0.008)
	ring.rotation_degrees.x = 18.0
	root.add_child(ring)
	return root


## Small per-chapter accessory: "ring" (marigold band), "pick" (guitar pick
## floating above the controller), "spark" (star sparkle at the tip).
static func _add_accessory(rig: Node3D, kind: String) -> void:
	match kind:
		"pick":
			var pick := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.035, 0.045, 0.008)
			pm.material = MarigoldFX.glow(ACCENT, 2.0)
			pick.mesh = pm
			pick.position = Vector3(0, 0.13, -0.03)
			pick.rotation_degrees = Vector3(20, 0, 15)
			rig.add_child(pick)
		"spark":
			var spark := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.016
			sm.height = 0.032
			sm.material = MarigoldFX.glow(Color(1.0, 0.85, 0.4), 2.5)
			spark.mesh = sm
			spark.position = Vector3(0, 0.12, -0.03)
			rig.add_child(spark)
		_: # "ring"
			var band := MeshInstance3D.new()
			var bm := TorusMesh.new()
			bm.inner_radius = 0.024
			bm.outer_radius = 0.030
			bm.rings = 20
			bm.ring_segments = 8
			bm.material = MarigoldFX.glow(ACCENT, 1.8)
			band.mesh = bm
			band.position = Vector3(0, 0.055, -0.012)
			band.rotation_degrees.x = 90.0
			rig.add_child(band)


## Floating legend card at chapter start: title + button lines, auto-hides
## after 6 s. Display-only (no input needed).
static func show_legend(parent: Node3D, chapter_key: String, chapter_name: String) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "ControlsLegend"
	parent.add_child(root)
	var title := MarigoldFX.make_label("Controles - " + chapter_name, 64, ACCENT)
	title.position = Vector3(0, 0.42, 0)
	root.add_child(title)
	var body := MarigoldFX.make_label(legend_text(chapter_key), 44, Color(1, 1, 1))
	body.position = Vector3(0, 0.02, 0)
	root.add_child(body)
	var hint := MarigoldFX.make_label("Menu button = pause anytime", 36, Color(0.85, 0.78, 0.88))
	hint.position = Vector3(0, -0.34, 0)
	root.add_child(hint)
	var cam := parent.get_viewport().get_camera_3d()
	if cam != null:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3(0, 0, -1)
		root.global_position = cam.global_position + fwd * 1.9 + Vector3(0, 0.15, 0)
		root.rotation.y = atan2(-fwd.x, -fwd.z)
	else:
		root.position = Vector3(0, 1.6, -1.9)
	var tw := root.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(root, "scale", Vector3.ONE * 0.01, 0.4)
	tw.tween_callback(root.queue_free)
