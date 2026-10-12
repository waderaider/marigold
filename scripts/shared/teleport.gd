## MarigoldTeleport.gd - marigold-petal themed teleport (v0.6.0).
## Roomscale world-shift teleport: a trail of glowing marigold petals arcs
## to the destination, then a bloom (petal burst + glow pulse) lands the
## arrival. Reuses the petal/particle kit - no new textures.
## Usage: pads call MarigoldTeleport.begin(self, world_node, target_pos)
## once per pinch; the helper animates and shifts the world.
extends RefCounted
class_name MarigoldTeleport

static var _active: Dictionary = {} # node -> {t, from, to, world, arc: Array}


## Begin a teleport: arc preview 0.8 s, then world-shift + bloom.
## world: the chapter's world/stage node to shift. target: world-space dest.
static func begin(node: Node, world: Node3D, target: Vector3) -> bool:
	if _active.has(node):
		return false
	var cam := node.get_viewport().get_camera_3d()
	var from := Vector3(0, 1.2, 0)
	if cam != null:
		from = cam.global_position
	var arc_root := Node3D.new()
	arc_root.name = "TeleportArc"
	node.add_child(arc_root)
	var dots: Array = []
	var petal_mat := MarigoldFX.glow(Color(1.0, 0.62, 0.12), 2.2)
	for i in 14:
		var d := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.03
		pm.height = 0.02
		pm.radial_segments = 8
		pm.rings = 4
		d.mesh = pm
		d.material_override = petal_mat
		var k := float(i) / 13.0
		d.position = _arc_point(from, target, k)
		d.scale = Vector3.ONE * (0.6 + 0.8 * k)
		arc_root.add_child(d)
		dots.append(d)
	_active[node] = {"t": 0.0, "from": from, "to": target, "world": world, "arc": arc_root, "dots": dots}
	return true


static func _arc_point(a: Vector3, b: Vector3, k: float) -> Vector3:
	var p := a.lerp(b, k)
	p.y += sin(k * PI) * 0.9
	return p


## Tick from the chapter's _process. Returns true while a teleport is active.
static func update(node: Node, delta: float) -> bool:
	if not _active.has(node):
		return false
	var st: Dictionary = _active[node]
	st["t"] = float(st["t"]) + delta
	var t: float = st["t"]
	var dots: Array = st["dots"]
	# Petals shimmer along the arc while aiming.
	for i in dots.size():
		var d: MeshInstance3D = dots[i]
		if is_instance_valid(d):
			var s := 0.6 + 0.8 * (float(i) / 13.0)
			d.scale = Vector3.ONE * s * (1.0 + 0.25 * sin(t * 10.0 + float(i)))
	if t >= 0.8:
		var world: Node3D = st["world"]
		var to: Vector3 = st["to"]
		var cam := node.get_viewport().get_camera_3d()
		if world != null and is_instance_valid(world) and cam != null:
			# World-shift: move the world so the target lands under the player.
			var pp := cam.global_position
			var flat_to := Vector3(to.x, 0, to.z)
			var flat_pp := Vector3(pp.x, 0, pp.z)
			world.position += flat_pp - flat_to
			# Arrival bloom: petal burst + spirit-bridge glow ring.
			MarigoldFX.scatter_petals(world.get_parent(), to + Vector3(0, 0.4, 0), 26)
			var ring := MeshInstance3D.new()
			var rm := TorusMesh.new()
			rm.inner_radius = 0.28
			rm.outer_radius = 0.36
			rm.rings = 24
			rm.ring_segments = 8
			ring.mesh = rm
			ring.material_override = MarigoldFX.glow(Color(1.0, 0.72, 0.25), 2.4)
			ring.rotation_degrees.x = 90.0
			ring.position = to + Vector3(0, 0.06, 0)
			world.get_parent().add_child(ring)
			var tw := world.get_parent().create_tween()
			tw.tween_property(ring, "scale", Vector3.ONE * 2.2, 0.7)
			tw.parallel().tween_property(ring, "transparency", 1.0, 0.7)
			tw.tween_callback(ring.queue_free)
			MarigoldHaptics.confirm()
		var arc: Node3D = st["arc"]
		if arc != null and is_instance_valid(arc):
			arc.queue_free()
		_active.erase(node)
		return false
	return true


## A teleport pad marker (pinch to travel). Returns the pad root.
static func make_pad(label_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "TeleportPad"
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.22
	dm.bottom_radius = 0.26
	dm.height = 0.04
	dm.radial_segments = 24
	disc.mesh = dm
	disc.material_override = MarigoldFX.glow(Color(1.0, 0.62, 0.12), 1.4)
	disc.position.y = 0.02
	root.add_child(disc)
	var lab := MarigoldFX.make_label(label_text, 40, Color(1.0, 0.9, 0.6))
	lab.position = Vector3(0, 0.55, 0)
	root.add_child(lab)
	root.set_meta("teleport_pad", true)
	return root


## Pad pulse (call per frame for visible pads).
static func pulse_pad(pad: Node3D, t: float) -> void:
	if pad == null or not is_instance_valid(pad):
		return
	var s := 1.0 + 0.08 * sin(t * 3.0)
	pad.scale = Vector3(s, 1.0, s)


## ------------------------------------------------------------------
## Laser-pointer locomotion (v0.7.0 — wade's ship-blocker).
##
## Standard VR pattern in EVERY chapter + experience: aim the controller
## laser at the ground -> a marigold-petal ring marks the landing point ->
## trigger teleports (roomscale world-shift + quick fade blink).
##
## AUDIT (why v0.6.0 "didn't reach him"): v0.6.0 shipped teleport PADS —
## fixed-destination discs you pinch, wired into ch3 + ch5 ONLY. No
## laser aiming, no free locomotion, absent from ch1/ch2/ch4 and all six
## experiences. This replaces that with universal laser locomotion (the
## pads stay where they are — they ride to fixed POIs).
##
## Input stack: reads controller tracker poses DIRECTLY (XRController3D
## under Main/XROrigin3D), NOT via XRUIPointer — so it stays live when
## the primary UI pointer path fails (the DirectUIInput lesson). Hand
## aim + pinch is the fallback when no controller is live; desktop uses
## the camera ray through the mouse.
##
## Usage (2 lines per chapter):
##   _teleport = MarigoldTeleport.laser_begin(self, world_node)  # setup()
##   MarigoldTeleport.laser_update(self, _teleport, delta)       # _process()
## world_node: the chapter's world/stage node that shifts (ch5=_world,
## ch1/espejo/galeria/mano_magica/ofrenda_finale/pinta=_stage,
## ch2/ch3/ch4/guitarra=self).
## Pass floor_y when the walkable ground is not at the world's origin
## height (default = world.global_position.y).

static var _lasers: Dictionary = {} # node -> rig dict

const LASER_MIN_DIST := 0.8
const LASER_MAX_DIST := 10.0
const LASER_MIN_DOWN := 0.18 # aim must point down this much to count
const LASER_COOLDOWN := 0.6


static func is_arc_active(node: Node) -> bool:
	return _active.has(node)


static func laser_begin(node: Node, world: Node3D, floor_y: float = 1e9) -> Dictionary:
	laser_free(node)
	if world == null or not is_instance_valid(world):
		return {}
	var gy := floor_y
	if gy > 1e8:
		gy = world.global_position.y
	# Landing marker: marigold-petal ring (motif matches the arrival bloom).
	var marker := Node3D.new()
	marker.name = "TeleportMarker"
	marker.top_level = true
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.26
	rm.outer_radius = 0.34
	rm.rings = 28
	rm.ring_segments = 8
	ring.mesh = rm
	ring.material_override = MarigoldFX.glow(Color(1.0, 0.66, 0.16), 2.4)
	ring.rotation_degrees.x = 90.0
	marker.add_child(ring)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.10
	dm.bottom_radius = 0.10
	dm.height = 0.015
	dm.radial_segments = 20
	disc.mesh = dm
	disc.material_override = MarigoldFX.glow(Color(1.0, 0.80, 0.35), 1.6)
	disc.position.y = 0.008
	marker.add_child(disc)
	# Petal dots around the ring (the marigold motif).
	for i in 8:
		var a := TAU * float(i) / 8.0
		var pet := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.035
		pm.height = 0.02
		pm.radial_segments = 6
		pm.rings = 4
		pet.mesh = pm
		pet.material_override = MarigoldFX.glow(Color(1.0, 0.55, 0.10), 2.0)
		pet.position = Vector3(cos(a) * 0.44, 0.01, sin(a) * 0.44)
		marker.add_child(pet)
	marker.visible = false
	node.add_child(marker)
	# Aim beam: thin straight cylinder, controller -> hit point.
	var beam := MeshInstance3D.new()
	beam.name = "TeleportBeam"
	beam.top_level = true
	var bm := CylinderMesh.new()
	bm.top_radius = 0.006
	bm.bottom_radius = 0.006
	bm.height = 1.0
	bm.radial_segments = 6
	beam.mesh = bm
	beam.material_override = MarigoldFX.glow(Color(1.0, 0.70, 0.25), 1.2)
	beam.visible = false
	node.add_child(beam)
	var rig := {"world": world, "floor_y": gy, "marker": marker,
		"beam": beam, "trig_was": false, "pinch_was": false,
		"cool": 0.0, "t": 0.0, "hit": Vector3.ZERO, "valid": false,
		"fade": null, "aim_origin": Vector3.ZERO, "aim_dir": Vector3(0, 0, -1)}
	_lasers[node] = rig
	return rig


static func laser_free(node: Node) -> void:
	if not _lasers.has(node):
		return
	var rig: Dictionary = _lasers[node]
	for k in ["marker", "beam", "fade"]:
		var n: Node = rig.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_lasers.erase(node)


## Per-frame: aim -> marker -> trigger edge -> world-shift + fade blink.
static func laser_update(node: Node, rig: Dictionary, delta: float) -> void:
	if rig.is_empty():
		return
	var world: Node3D = rig.get("world")
	if world == null or not is_instance_valid(world):
		return
	# Never fight the pause menu or a pad-arc teleport.
	var mp := node.get_node_or_null("/root/MarigoldPause")
	if mp != null and mp.has_method("is_pause_open") and bool(mp.call("is_pause_open")):
		_set_laser_visible(rig, false)
		return
	if is_arc_active(node):
		_set_laser_visible(rig, false)
		return
	rig["t"] = float(rig["t"]) + delta
	rig["cool"] = maxf(0.0, float(rig["cool"]) - delta)
	var aim := _laser_aim(node)
	var origin: Vector3 = aim[0]
	var dir: Vector3 = aim[1]
	var have_aim: bool = aim[2]
	rig["aim_origin"] = origin
	rig["aim_dir"] = dir
	var valid := false
	var hit := Vector3.ZERO
	if have_aim and dir.y < -LASER_MIN_DOWN:
		var gy: float = rig["floor_y"]
		var t := (gy - origin.y) / dir.y
		if t >= LASER_MIN_DIST and t <= LASER_MAX_DIST:
			hit = origin + dir * t
			# Keep teleports inside a sane play area.
			if absf(hit.x) < 16.0 and absf(hit.z) < 16.0:
				valid = true
	rig["hit"] = hit
	rig["valid"] = valid
	_update_laser_visuals(rig, origin, dir, hit, valid, have_aim)
	# Trigger edge (primary) / pinch edge (fallback when no controller live).
	var trig := false
	if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
		trig = true
	var trig_edge := trig and not bool(rig["trig_was"])
	rig["trig_was"] = trig
	var pinched := false
	if not have_aim or not _any_controller_live(node):
		for h in [MarigoldHands.HAND_RIGHT, MarigoldHands.HAND_LEFT]:
			if MarigoldHands.pinch_active(node, h):
				pinched = true
				break
	var pinch_edge := pinched and not bool(rig["pinch_was"])
	rig["pinch_was"] = pinched
	if valid and float(rig["cool"]) <= 0.0 and (trig_edge or pinch_edge):
		_do_laser_teleport(node, rig, hit)


static func _set_laser_visible(rig: Dictionary, v: bool) -> void:
	var marker: Node3D = rig.get("marker")
	var beam: Node3D = rig.get("beam")
	if marker != null and is_instance_valid(marker):
		marker.visible = v
	if beam != null and is_instance_valid(beam):
		beam.visible = v


## Aim source priority: dominant-hand controller -> other controller ->
## hand -> desktop camera ray. Honors the input-method preference
## (controllers-only / hands-only) from Settings.
static func _laser_aim(node: Node) -> Array:
	var pref := MarigoldGfx.input_pref()
	# Controllers (raw tracker poses — independent of XRUIPointer).
	if pref != "hands":
		var ctl := _live_controller(node, MarigoldGfx.dominant_hand_idx())
		if ctl == null:
			ctl = _live_controller(node, MarigoldHands.HAND_LEFT)
		if ctl == null:
			ctl = _live_controller(node, MarigoldHands.HAND_RIGHT)
		if ctl != null:
			var o: Vector3 = ctl.global_position
			var d: Vector3 = -ctl.global_transform.basis.z.normalized()
			return [o, d, true]
	# Hands fallback (camera-anchored pointer ray).
	if pref != "controllers" and MarigoldHands.is_xr_active():
		var r: Array = MarigoldHands.pointer_ray(node, MarigoldGfx.dominant_hand_idx())
		return [r[0], (r[1] as Vector3).normalized(), true]
	# Desktop: camera ray through the mouse.
	var cam := node.get_viewport().get_camera_3d()
	if cam != null and not node.get_viewport().use_xr:
		var mpv := node.get_viewport().get_mouse_position()
		return [cam.project_ray_origin(mpv),
			cam.project_ray_normal(mpv).normalized(), true]
	return [Vector3.ZERO, Vector3(0, 0, -1), false]


static func _live_controller(node: Node, hand: int) -> XRController3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	var origin := tree.root.get_node_or_null("Main/XROrigin3D") as Node3D
	if origin == null:
		return null
	var want := "left" if hand == MarigoldHands.HAND_LEFT else "right"
	for c in origin.find_children("*", "XRController3D", true, false):
		var ctl := c as XRController3D
		if ctl == null:
			continue
		# Liveness = the XR server actually holds this tracker.
		# (get_tracker() returns the configured NAME even with no runtime —
		# not a liveness signal.)
		if XRServer.get_tracker(ctl.tracker) == null:
			continue
		if String(ctl.name).to_lower().find(want) >= 0:
			return ctl
	return null


static func _any_controller_live(node: Node) -> bool:
	return _live_controller(node, MarigoldHands.HAND_LEFT) != null \
		or _live_controller(node, MarigoldHands.HAND_RIGHT) != null


static func _update_laser_visuals(rig: Dictionary, origin: Vector3, dir: Vector3,
		hit: Vector3, valid: bool, have_aim: bool) -> void:
	var marker: Node3D = rig.get("marker")
	var beam: MeshInstance3D = rig.get("beam")
	var t: float = rig["t"]
	if marker != null and is_instance_valid(marker):
		marker.visible = valid
		if valid:
			marker.global_position = hit + Vector3(0, 0.02, 0)
			var s := 1.0 + 0.10 * sin(t * 6.0)
			marker.scale = Vector3(s, 1.0, s)
	if beam != null and is_instance_valid(beam):
		beam.visible = have_aim
		if have_aim:
			var end := hit if valid else origin + dir * 3.0
			var mid := (origin + end) * 0.5
			var length: float = origin.distance_to(end)
			beam.global_position = mid
			beam.scale = Vector3(1.0, maxf(length, 0.01), 1.0)
			beam.global_rotation = (Quaternion(Vector3.UP, dir) \
				* Quaternion.IDENTITY).get_euler() \
				if dir.length_squared() > 0.001 else Vector3.ZERO
			var m := beam.material_override as StandardMaterial3D
			if m != null:
				var e := 1.2 if valid else 0.45
				m.emission_energy_multiplier = e


## World-shift + quick fade blink + arrival bloom (petal motif).
static func _do_laser_teleport(node: Node, rig: Dictionary, hit: Vector3) -> void:
	var world: Node3D = rig["world"]
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return
	rig["cool"] = LASER_COOLDOWN
	_blink_fade(node, rig, cam)
	var pp := cam.global_position
	# v0.7.0 VFX: petal implosion where the player stood (balances the
	# arrival bloom; top-level so it survives the world shift).
	var gy: float = rig["floor_y"]
	var anchor: Node = world.get_parent() if world.get_parent() != null else node
	MarigoldSpectacle.depart_implode(anchor, Vector3(pp.x, gy, pp.z))
	var shift := Vector3(pp.x, 0, pp.z) - Vector3(hit.x, 0, hit.z)
	world.global_position = world.global_position + shift
	# Arrival bloom: reuse the pad-teleport's petal-burst language.
	MarigoldFX.scatter_petals(world.get_parent(), hit + Vector3(0, 0.4, 0), 26)
	# v0.7.0 full-featured bar: soft arrival chime (rising two-note).
	var st := node.get_node_or_null("/root/MarigoldState")
	if st != null and st.music != null:
		st.music.chime(67, 0.35)
		st.music.chime(72, 0.30)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.28
	rm.outer_radius = 0.36
	rm.rings = 24
	rm.ring_segments = 8
	ring.mesh = rm
	ring.material_override = MarigoldFX.glow(Color(1.0, 0.72, 0.25), 2.4)
	ring.rotation_degrees.x = 90.0
	ring.top_level = true
	ring.global_position = hit + Vector3(0, 0.06, 0)
	world.get_parent().add_child(ring)
	var tw := world.get_parent().create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 2.2, 0.7)
	tw.parallel().tween_property(ring, "transparency", 1.0, 0.7)
	tw.tween_callback(ring.queue_free)
	MarigoldHaptics.confirm()
	var gt := node.get_node_or_null("/root/GameplayTelemetry")
	if gt != null:
		gt.event("teleport", {"via": "laser", "dist": snappedf(shift.length(), 0.1)})


## Quick fade blink: black quad 0.35 m in front of the camera, 0→0.9→0.
static func _blink_fade(node: Node, rig: Dictionary, cam: Camera3D) -> void:
	var old: Node = rig.get("fade")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6)
	q.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0)
	q.material_override = mat
	q.position = Vector3(0, 0, -0.35)
	cam.add_child(q)
	rig["fade"] = q
	var tw := node.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.9, 0.07)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(q.queue_free)
