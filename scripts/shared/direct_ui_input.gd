extends Node3D
class_name DirectUIInput
## Belt-and-suspenders input fallback for the MARIGOLD 2D panel (v0.6.2).
##
## The primary path (XRUIPointer per-source nodes + xr_moved/xr_clicked
## signals) can fail silently on-device (stale controller discovery, a gate
## that never opens, invisible lasers). This node runs every frame
## INDEPENDENT of that path: it discovers XRController3D nodes itself,
## raycasts from each live controller's raw tracker pose against the panel
## quad, and drives the SAME deduped click funnel as the primary path.
##
## Both paths always run. Clicks are deduped centrally (120 ms / 8 px) so a
## working primary plus this fallback can never double-fire.
##
## It also draws its own bright-yellow beams — if the primary lasers die,
## wade still sees exactly where he is pointing.

const BEAM_COLOR := Color(1.0, 0.85, 0.1)
const BEAM_RADIUS := 0.010
const BEAM_ENERGY := 5.0
const DOT_RADIUS := 0.024
const DOT_ENERGY := 5.0
const MAX_SOURCES := 4 # 2 controllers + 2 hands

var _viewport: SubViewport = null
var _quad: MeshInstance3D = null
var _origin: Node3D = null
var _click_cb := Callable()
var _motion_cb := Callable()
var _enabled := true
## Mirrors XRUIPointer.xr_mode: set from the owner's use_xr each frame. When
## false (desktop/headless) the fallback stays fully inert — the desktop
## mouse path owns input there.
var xr_mode := false

# key -> {"laser": MeshInstance3D, "dot": MeshInstance3D,
#          "ctl": XRController3D or null, "hand_side": int}
var _beams := {}
var _press_state := {} # key -> bool (rising-edge detection)
# Init far negative: "no beam yet" must read as no-beam, not "beam at t=0".
var _last_beam_msec := -100000
var _beam_mat: StandardMaterial3D = null
var _beam_mesh: CylinderMesh = null
var _dot_mat: StandardMaterial3D = null
var _dot_mesh: SphereMesh = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shared_visuals()


## Hook up (or re-target) the panel this node drives. Both paths funnel
## clicks/motions through the owner's inject funnel (deduped there).
func setup(viewport: SubViewport, quad: MeshInstance3D, origin: Node3D,
		click_cb: Callable, motion_cb: Callable) -> void:
	_viewport = viewport
	_quad = quad
	_origin = origin
	_click_cb = click_cb
	_motion_cb = motion_cb


## Switch to a different panel (pause overlay <-> floating exit button).
func set_target(viewport: SubViewport, quad: MeshInstance3D) -> void:
	_viewport = viewport
	_quad = quad
	_hide_all_beams()


func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		_hide_all_beams()


## True when any fallback beam was drawn in the last `window_ms` ms.
## Drives the gaze-reticle arbitration ("no beam drawn") alongside the
## primary path's is_beam_visible().
func beam_visible_recently(window_ms: float = 250.0) -> bool:
	return Time.get_ticks_msec() - _last_beam_msec <= int(window_ms)


func _process(_delta: float) -> void:
	if not xr_mode or not _enabled or _viewport == null or _quad == null \
			or not is_visible_in_tree():
		_hide_all_beams()
		return
	if _origin == null or not is_instance_valid(_origin):
		_origin = get_tree().root.find_child("XROrigin3D", true, false) as Node3D
		if _origin == null:
			_hide_all_beams()
			return
	var seen := {}
	# Controllers: name-agnostic discovery (kills the stale-name failure).
	for ctl in _origin.find_children("*", "XRController3D", true, false):
		var c := ctl as XRController3D
		if c == null or not is_instance_valid(c):
			continue
		if c.get_tracker() == null:
			continue # not live on device
		var key := "ctl_%d" % c.get_instance_id()
		seen[key] = true
		var gt := c.global_transform
		_handle_source(key, gt.origin, -gt.basis.z.normalized(),
				XRUIPointer.trigger_pressed(c), c, 0)
	# Hands: raw tracker pose -> pinch rising edge.
	for side in [XRPositionalTracker.TRACKER_HAND_LEFT,
			XRPositionalTracker.TRACKER_HAND_RIGHT]:
		var key := "hand_%d" % side
		var hr := XRUIPointer.hand_ray(side, _origin)
		if not bool(hr["active"]):
			_hide_beam(key)
			_press_state[key] = false
			continue
		seen[key] = true
		_handle_source(key, hr["origin"], hr["dir"], bool(hr["pinch"]),
				null, side)
	# Hide beams whose source went away.
	for key in _beams.keys():
		if not seen.has(key):
			_hide_beam(key)
			_press_state[key] = false


func _handle_source(key: String, origin: Vector3, dir: Vector3,
		pressed: bool, ctl: XRController3D, hand_side: int) -> void:
	var hit := XRUIPointer.ray_to_viewport(origin, dir, _quad,
			Vector2(_viewport.size))
	var hit_ok := bool(hit["hit"])
	var end_point: Vector3 = hit["world"]
	var kind := "controllers" if ctl != null else "hands"
	if hit_ok and _motion_cb.is_valid():
		_motion_cb.call(hit["pos"], kind)
	# Rising edge -> click through the SAME deduped funnel as the primary.
	var was: bool = bool(_press_state.get(key, false))
	if pressed and not was and hit_ok and _click_cb.is_valid():
		_click_cb.call(hit["pos"], kind)
	_press_state[key] = pressed and hit_ok
	_draw_beam(key, origin, end_point, hit_ok)


func _build_shared_visuals() -> void:
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.albedo_color = BEAM_COLOR
	_beam_mat.emission_enabled = true
	_beam_mat.emission = BEAM_COLOR
	_beam_mat.emission_energy_multiplier = BEAM_ENERGY
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = BEAM_RADIUS
	_beam_mesh.bottom_radius = BEAM_RADIUS
	_beam_mesh.height = 1.0
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = BEAM_COLOR
	_dot_mat.emission_enabled = true
	_dot_mat.emission = BEAM_COLOR
	_dot_mat.emission_energy_multiplier = DOT_ENERGY
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = DOT_RADIUS
	_dot_mesh.height = DOT_RADIUS * 2.0


func _get_beam(key: String) -> Dictionary:
	if _beams.has(key):
		return _beams[key]
	if _beams.size() >= MAX_SOURCES:
		return {}
	var laser := MeshInstance3D.new()
	laser.name = "FallbackLaser"
	laser.mesh = _beam_mesh
	laser.material_override = _beam_mat
	laser.visible = false
	add_child(laser)
	var dot := MeshInstance3D.new()
	dot.name = "FallbackDot"
	dot.mesh = _dot_mesh
	dot.material_override = _dot_mat
	dot.visible = false
	add_child(dot)
	var b := {"laser": laser, "dot": dot}
	_beams[key] = b
	return b


func _draw_beam(key: String, from: Vector3, to: Vector3, show_dot: bool) -> void:
	var b := _get_beam(key)
	if b.is_empty():
		return
	var laser: MeshInstance3D = b["laser"]
	var dot: MeshInstance3D = b["dot"]
	var length := from.distance_to(to)
	if length < 0.001:
		laser.visible = false
		dot.visible = show_dot
		return
	var d := (to - from) / length
	# Orthonormal basis with local +Y along the beam (same math as
	# XRUIPointer._update_visuals).
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var y := d
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	var mid := (from + to) * 0.5
	laser.global_transform = Transform3D(Basis(x, y, z).scaled(
			Vector3(1.0, length, 1.0)), mid)
	laser.visible = true
	dot.global_position = to
	dot.visible = show_dot
	_last_beam_msec = Time.get_ticks_msec()


func _hide_beam(key: String) -> void:
	if not _beams.has(key):
		return
	(_beams[key]["laser"] as MeshInstance3D).visible = false
	(_beams[key]["dot"] as MeshInstance3D).visible = false


func _hide_all_beams() -> void:
	for key in _beams.keys():
		_hide_beam(key)
