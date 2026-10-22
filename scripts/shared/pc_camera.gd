## pc_camera.gd - MarigoldPCCamera: desktop FPS rig for MARIGOLD PC mode
## (v0.8.0, wade's order — real PC play with mouse + keyboard).
##
## Active ONLY in PC mode (never in XR). Owns the DesktopCamera: captured-
## mouse look (yaw on the rig, pitch on the camera) + WASD/arrow movement at
## a fixed eye height. Chapters keep working because they all read the
## viewport camera and the mouse ray through the cursor.
##
## Mouse capture contract: the rig captures the mouse while a chapter is
## running; main.gd releases it for menus/pause/chooser and re-captures on
## resume. Sensitivity + invert-Y are real settings (MarigoldGfx).
##
## v0.9.3: the whole PC experience is one-handed mouse-only — look with
## the mouse, HOLD Left-click to walk, Right-click teleports, Left-click
## uses (chapters), and MarigoldPause shows a clickable ❚❚ button.
extends Node3D
class_name MarigoldPCCamera

const EYE_HEIGHT := 1.6
const WALK_SPEED := 3.0
const SPRINT_SPEED := 6.0
const PLAY_RADIUS := 16.0 # matches the laser-teleport clamp
# v0.9.3 one-handed mouse: hold-LMB-to-walk tuning. A plain click must
# stay the interact verb (chapters fire on the press), so walking only
# engages after this delay, and never while the crosshair is over a
# usable object in reach.
const HOLD_WALK_DELAY := 0.35
const HOVER_RANGE := 1.7 # pointer reach (desktop pointer sits at 1.6 m)

var active := false
var _cam: Camera3D = null
var _pitch := 0.0
var _crosshair: Control = null
var _lmb_hold := 0.0
var _hover_acc := 0.0
var _hover_usable := false
var _hold_walking := false


## Attach to an existing Camera3D (the main scene's DesktopCamera).
## The camera is reparented under the rig, keeping its world position.
func attach(cam: Camera3D) -> void:
	_cam = cam
	var gp := cam.global_position
	position = Vector3(gp.x, 0.0, gp.z)
	rotation = Vector3.ZERO
	cam.reparent(self)
	cam.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	cam.rotation = Vector3.ZERO
	_pitch = 0.0
	_build_crosshair()


func _build_crosshair() -> void:
	# Glowing marigold dot + soft ring at screen center (plan §7 / design
	# doc 1E): the PC cursor-hand visual. Drawn in screen space so it never
	# clips into geometry.
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.name = "PCCrosshairLayer"
	add_child(layer)
	var dot := _CrosshairDot.new()
	dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dot)
	_crosshair = dot


func _input(event: InputEvent) -> void:
	if not active or _cam == null:
		return
	# Esc is handled by the pause menu (ui_cancel) — it releases the mouse.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens := MarigoldGfx.mouse_sensitivity()
		var inv := -1.0 if MarigoldGfx.mouse_invert_y() else 1.0
		rotation.y -= mm.relative.x * sens * 0.0025
		_pitch = clampf(_pitch - mm.relative.y * sens * 0.0025 * inv,
				deg_to_rad(-85.0), deg_to_rad(85.0))
		_cam.rotation.x = _pitch


func _process(delta: float) -> void:
	if not active or _cam == null:
		return
	if get_tree().paused:
		return
	# v0.9.2: Xbox right stick look (UE5 mapping: right stick = look).
	# Mouse look stays primary; the stick polls alongside it.
	# v0.9.3 (input-systems Pattern 2): RADIAL deadzone with rescaling on
	# the first connected pad - the old per-axis square gate clipped
	# diagonals, snapped look from 0 to 0.2x, and hardcoded pad 0.
	var pad := 0
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		pad = int(pads[0])
	var stick := _apply_deadzone(Vector2(
			Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)), 0.2)
	if stick != Vector2.ZERO:
		var sens := MarigoldGfx.mouse_sensitivity()
		var inv := -1.0 if MarigoldGfx.mouse_invert_y() else 1.0
		rotation.y -= stick.x * sens * 2.2 * delta
		_pitch = clampf(_pitch - stick.y * sens * 2.2 * delta * inv,
				deg_to_rad(-85.0), deg_to_rad(85.0))
		_cam.rotation.x = _pitch
	# v0.9.3 one-handed mouse (wade's order): HOLD Left-click = walk
	# forward toward the look direction; release stops. Gated three
	# ways so it can never eat an interaction: (1) the press must be
	# HELD past HOLD_WALK_DELAY — chapter clicks fire on the press;
	# (2) the crosshair must not be over a usable object in reach
	# (physics veto, refreshed at 12 Hz — also drives the crosshair's
	# hover highlight); (3) the rig is only active during chapters
	# (main.gd deactivates it whenever a menu/pause has the mouse).
	_hover_acc += delta
	if _hover_acc >= 0.08:
		_hover_acc = 0.0
		_hover_usable = _ray_hits_usable()
	_hold_walking = false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not _hover_usable:
		_lmb_hold += delta
		_hold_walking = _lmb_hold >= HOLD_WALK_DELAY
	else:
		_lmb_hold = 0.0
	if _hold_walking:
		var wfwd := -global_transform.basis.z
		wfwd.y = 0.0
		if wfwd.length_squared() > 0.0001:
			position += wfwd.normalized() * WALK_SPEED * delta
			position.x = clampf(position.x, -PLAY_RADIUS, PLAY_RADIUS)
			position.z = clampf(position.z, -PLAY_RADIUS, PLAY_RADIUS)
	var iv := Input.get_vector("move_left", "move_right",
			"move_forward", "move_back")
	if iv.length_squared() > 0.0001:
		var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") \
				else WALK_SPEED
		var dir3 := (global_transform.basis * Vector3(iv.x, 0.0, iv.y))
		dir3.y = 0.0
		if dir3.length_squared() > 0.0001:
			# v0.9.3: analog magnitude scales speed - a gentle tilt walks
			# gently (was: dir3.normalized(), any tilt = full speed).
			position += dir3.normalized() \
					* clampf(iv.length(), 0.0, 1.0) * speed * delta
			position.x = clampf(position.x, -PLAY_RADIUS, PLAY_RADIUS)
			position.z = clampf(position.z, -PLAY_RADIUS, PLAY_RADIUS)
	if _crosshair != null:
		_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if _crosshair is _CrosshairDot:
			var dot := _crosshair as _CrosshairDot
			if dot.usable != _hover_usable or dot.walking != _hold_walking:
				dot.usable = _hover_usable
				dot.walking = _hold_walking
				dot.queue_redraw()


## Center-ray "is something usable in front of me" query for the
## hold-to-walk veto + crosshair hover highlight. Any collider within
## pointer reach counts, EXCEPT flat-up surfaces (floor, tabletops):
## aiming at the ground ahead must never block walking toward it.
func _ray_hits_usable() -> bool:
	if _cam == null or not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := _cam.global_position
	var dir := -_cam.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(
			from, from + dir * HOVER_RANGE)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	return normal.y < 0.75


## Radial deadzone with magnitude rescaling (input-systems Pattern 2):
## below `dead` -> zero; above -> (mag - dead) / (1 - dead) along the
## stick's own direction, so diagonals survive and centre is smooth.
static func _apply_deadzone(stick: Vector2, dead: float) -> Vector2:
	var mag := stick.length()
	if mag <= dead:
		return Vector2.ZERO
	var scaled := (mag - dead) / (1.0 - dead)
	return stick / mag * minf(scaled, 1.0)


## Look direction (for chapters that need an explicit forward).
func look_dir() -> Vector3:
	if _cam == null:
		return -global_transform.basis.z
	return -_cam.global_transform.basis.z


class _CrosshairDot extends Control:
	## v0.9.3: hover state — bright expanded ring over a usable object
	## in reach (one-handed discoverability), teal ring while
	## hold-to-walk is engaged.
	var usable := false
	var walking := false

	func _draw() -> void:
		var c := size * 0.5
		if walking:
			draw_arc(c, 18.0, 0.0, TAU, 32, Color(0.18, 0.77, 0.71, 0.9), 2.5)
			draw_circle(c, 2.5, Color(1.0, 0.85, 0.45, 1.0))
			return
		if usable:
			draw_arc(c, 18.0, 0.0, TAU, 32, Color(1.0, 0.72, 0.25, 1.0), 3.0)
			draw_circle(c, 5.0, Color(1.0, 0.80, 0.35, 0.5))
			draw_circle(c, 3.5, Color(1.0, 0.85, 0.45, 1.0))
			return
		# Soft ring.
		draw_arc(c, 14.0, 0.0, TAU, 32, Color(1.0, 0.72, 0.25, 0.75), 2.0)
		# Glowing dot.
		draw_circle(c, 5.0, Color(1.0, 0.80, 0.35, 0.35))
		draw_circle(c, 2.5, Color(1.0, 0.85, 0.45, 1.0))
