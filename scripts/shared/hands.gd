## MarigoldHands.gd - AR and hand-tracking helpers for MARIGOLD.
## Room-aware placement, spatial anchor persistence, hand-tracking pinch
## detection with mouse fallback, and passthrough-friendly object setup.
## Everything is headless-safe: XR calls are guarded, and every helper has
## a sensible non-XR fallback so scripts parse and run without hardware.
extends RefCounted
class_name MarigoldHands

## Hand identifiers for pinch helpers.
const HAND_LEFT := 0
const HAND_RIGHT := 1

## Where anchor transforms persist.
const ANCHOR_FILE := "user://marigold_anchors.cfg"

## Default room bounds used when no scene mesh is available (meters).
const DEFAULT_ROOM := Rect2(-1.75, -1.75, 3.5, 3.5) # x,z centered play area
const DEFAULT_FLOOR_Y := 0.0
const DEFAULT_TABLE_Y := 0.75


## True when an XR session with a valid primary interface is running.
static func is_xr_active() -> bool:
	var xr := XRServer.primary_interface
	return xr != null and xr.is_initialized()


## v0.8.0: shared PC-mode probe for the static helpers below. Resolves the
## MarigoldState autoload at runtime (never at parse time, so headless
## --check-only stays clean).
static func _pc_mode_via(node: Node) -> bool:
	if node == null:
		return false
	var st: Node = node.get_node_or_null("/root/MarigoldState")
	return st != null and st.has_method("is_pc_mode") \
			and bool(st.call("is_pc_mode"))


## Pinch detection.
## XR path: measures thumb-tip to index-tip distance via the hand tracker when
## the project exposes hand-tracking actions; falls back to mouse/trigger.
## `hand` is HAND_LEFT or HAND_RIGHT. `node` is used to find tracker nodes.
## v0.8.0 verb split (wade's order): on PC, LMB = interact (right-hand
## pinch) and RMB = teleport-confirm (owned by MarigoldTeleport) — so the
## RMB->left-pinch mouse mapping is disabled in PC mode. Two-hand XR paths
## are untouched.
static func pinch_active(node: Node, hand: int = HAND_RIGHT) -> bool:
	# Mouse fallback: left button = right-hand pinch (interact).
	if hand == HAND_RIGHT and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	# Right button = left-hand pinch everywhere EXCEPT PC mode, where RMB
	# is the teleport-confirm verb.
	if hand == HAND_LEFT and not _pc_mode_via(node) \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	# XR action fallback (projects that map pinch to an action).
	var action := "pinch_right" if hand == HAND_RIGHT else "pinch_left"
	if InputMap.has_action(action) and Input.is_action_pressed(action):
		return true
	# Trigger fallback for controllers.
	if InputMap.has_action("trigger_click") and Input.is_action_pressed("trigger_click"):
		return true
	return false


## Pinch just pressed this frame (edge detection helper; games should cache).
static func pinch_just_pressed(node: Node, hand: int = HAND_RIGHT) -> bool:
	var key := "__pinch_prev_%d" % hand
	var prev: bool = node.get_meta(key) if node.has_meta(key) else false
	var now: bool = pinch_active(node, hand)
	node.set_meta(key, now)
	return now and not prev


## Hand/pointer world position.
## XR path: point fixed to the camera (head-locked hand proxy), kept
## byte-for-byte. Desktop path (v0.8.0): the mouse ray at 1.6 m — the same
## model ch1/ch3/ch4/guitarra already use, so mano_magica, pinta and ch5
## get a working cursor-hand for free.
static func pointer_position(node: Node3D, hand: int = HAND_RIGHT, reach: float = 1.2) -> Vector3:
	if is_xr_active():
		var camx := node.get_viewport().get_camera_3d()
		if camx == null:
			return node.global_position + Vector3(0, 1.2, -reach)
		var xoff := Vector3(0.18 if hand == HAND_RIGHT else -0.18, -0.12, 0.0)
		return camx.global_transform * (Vector3(0, 0, -reach) + xoff)
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return node.global_position + Vector3(0, 1.2, -reach)
	var mp := node.get_viewport().get_mouse_position()
	return cam.project_ray_origin(mp) + cam.project_ray_normal(mp) * 1.6


## Ray from the pointer for selection (origin, direction).
## XR: camera-forward (unchanged). Desktop (v0.8.0): camera ray through the
## mouse cursor — the unified aim model (UI Specialist).
static func pointer_ray(node: Node3D, hand: int = HAND_RIGHT) -> Array:
	if is_xr_active():
		var camx := node.get_viewport().get_camera_3d()
		var originx := pointer_position(node, hand)
		var dirx := Vector3(0, 0, -1)
		if camx != null:
			dirx = -camx.global_transform.basis.z
		return [originx, dirx.normalized()]
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return [node.global_position + Vector3(0, 1.2, -1.6), Vector3(0, 0, -1)]
	var mp := node.get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp).normalized()
	return [origin, dir]


## Save an object's transform as a named spatial anchor (persists in user://).
static func save_anchor(anchor_name: String, t: Transform3D) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ANCHOR_FILE) # ignore errors; missing file is fine
	cfg.set_value("anchors", anchor_name + "_pos", t.origin)
	cfg.set_value("anchors", anchor_name + "_basis_x", t.basis.x)
	cfg.set_value("anchors", anchor_name + "_basis_y", t.basis.y)
	cfg.set_value("anchors", anchor_name + "_basis_z", t.basis.z)
	cfg.save(ANCHOR_FILE)


## Load a saved anchor transform. Returns null when none was saved.
static func load_anchor(anchor_name: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(ANCHOR_FILE) != OK:
		return null
	if not cfg.has_section_key("anchors", anchor_name + "_pos"):
		return null
	var t := Transform3D()
	t.origin = cfg.get_value("anchors", anchor_name + "_pos", Vector3.ZERO)
	t.basis.x = cfg.get_value("anchors", anchor_name + "_basis_x", Vector3.RIGHT)
	t.basis.y = cfg.get_value("anchors", anchor_name + "_basis_y", Vector3.UP)
	t.basis.z = cfg.get_value("anchors", anchor_name + "_basis_z", Vector3.BACK)
	return t


## Apply a saved anchor to a node. Returns true when an anchor was found.
static func apply_anchor(node: Node3D, anchor_name: String) -> bool:
	var t: Variant = load_anchor(anchor_name)
	if t == null:
		return false
	node.global_transform = t
	return true


## Drop a node onto the floor plane (y = floor_y), keeping x/z.
static func snap_to_floor(node: Node3D, floor_y: float = DEFAULT_FLOOR_Y) -> void:
	var p := node.position
	p.y = floor_y
	node.position = p


## Place a node on a table-height surface in front of the player.
static func place_on_table(node: Node3D, distance: float = 1.0, height: float = DEFAULT_TABLE_Y) -> void:
	var cam := node.get_viewport().get_camera_3d()
	var fwd := Vector3(0, 0, -1)
	if cam != null:
		fwd = -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var base := cam.global_position if cam != null else Vector3.ZERO
	node.position = Vector3(base.x + fwd.x * distance, height, base.z + fwd.z * distance)


## Clamp a position inside room bounds (x/z), with a margin.
static func clamp_to_room(pos: Vector3, margin: float = 0.3) -> Vector3:
	var r := DEFAULT_ROOM
	pos.x = clampf(pos.x, r.position.x + margin, r.position.x + r.size.x - margin)
	pos.z = clampf(pos.z, r.position.y + margin, r.position.y + r.size.y - margin)
	return pos


## Make an object passthrough-friendly: unshaded parts stay readable over the
## real world; returns the node for chaining.
static func passthrough_friendly(mat: StandardMaterial3D) -> StandardMaterial3D:
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## ---- Grab / throw vocabulary (v0.5.0, for Mano Magica) ----
## Built on pinch_active + pointer_position so it works on device (pinch),
## controllers (trigger) and desktop (mouse) with zero extra actions.

## Grab state for one hand. Tracks pinch-hold with a position history so
## throw_release_velocity() can recover the release fling.
## Returns {"active": bool, "grab_point": Vector3, "held_time": float}.
## `node` must be a Node3D in the tree (state is kept in its metadata).
static func grab_state(node: Node3D, hand: int = HAND_RIGHT) -> Dictionary:
	var res := {"active": false, "grab_point": Vector3.ZERO, "held_time": 0.0}
	if node == null or not node.is_inside_tree():
		return res
	var key := "__grab_%d" % hand
	var st: Dictionary = node.get_meta(key) if node.has_meta(key) else {}
	var pinching: bool = pinch_active(node, hand)
	var pos := pointer_position(node, hand)
	var now_msec := Time.get_ticks_msec() / 1000.0
	if pinching:
		if not bool(st.get("active", false)):
			st = {"active": true, "start": pos, "start_t": now_msec,
				"hist": [[now_msec, pos]]}
		else:
			var hist: Array = st.get("hist", [])
			hist.append([now_msec, pos])
			while hist.size() > 10:
				hist.pop_front()
			st["hist"] = hist
		res["active"] = true
		res["grab_point"] = pos
		res["held_time"] = now_msec - float(st.get("start_t", now_msec))
		node.set_meta(key, st)
	else:
		# Latch the release velocity for one frame so the caller can fling.
		if bool(st.get("active", false)):
			var v := _hist_velocity(st.get("hist", []))
			node.set_meta("__throw_%d" % hand, {"vel": v, "t": now_msec})
		node.set_meta(key, {})
	return res


## Release velocity of the last grab for a hand (m/s, world space).
## Valid for ~0.5 s after release, then decays to Vector3.ZERO.
static func throw_release_velocity(node: Node3D, hand: int = HAND_RIGHT) -> Vector3:
	if node == null or not node.is_inside_tree():
		return Vector3.ZERO
	var key := "__throw_%d" % hand
	if not node.has_meta(key):
		return Vector3.ZERO
	var st: Dictionary = node.get_meta(key)
	var age := Time.get_ticks_msec() / 1000.0 - float(st.get("t", 0.0))
	if age > 0.5:
		node.set_meta(key, {})
		return Vector3.ZERO
	return st.get("vel", Vector3.ZERO)


## Hand travel speed while grabbing (m/s) - for texture ticks / sculpt audio.
static func grab_speed(node: Node3D, hand: int = HAND_RIGHT) -> float:
	if node == null or not node.is_inside_tree():
		return 0.0
	var key := "__grab_%d" % hand
	if not node.has_meta(key):
		return 0.0
	var st: Dictionary = node.get_meta(key)
	if not bool(st.get("active", false)):
		return 0.0
	return _hist_velocity(st.get("hist", [])).length()


static func _hist_velocity(hist: Array) -> Vector3:
	if hist.size() < 2:
		return Vector3.ZERO
	var t0: float = hist[0][0]
	var p0: Vector3 = hist[0][1]
	var t1: float = hist[hist.size() - 1][0]
	var p1: Vector3 = hist[hist.size() - 1][1]
	var dt := t1 - t0
	if dt < 0.016:
		return Vector3.ZERO
	return (p1 - p0) / dt
