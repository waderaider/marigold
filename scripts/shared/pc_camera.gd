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
extends Node3D
class_name MarigoldPCCamera

const EYE_HEIGHT := 1.6
const WALK_SPEED := 3.0
const SPRINT_SPEED := 6.0
const PLAY_RADIUS := 16.0 # matches the laser-teleport clamp

var active := false
var _cam: Camera3D = null
var _pitch := 0.0
var _crosshair: Control = null


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
	var iv := Input.get_vector("move_left", "move_right",
			"move_forward", "move_back")
	if iv.length_squared() > 0.0001:
		var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") \
				else WALK_SPEED
		var dir3 := (global_transform.basis * Vector3(iv.x, 0.0, iv.y))
		dir3.y = 0.0
		if dir3.length_squared() > 0.0001:
			position += dir3.normalized() * speed * delta
			position.x = clampf(position.x, -PLAY_RADIUS, PLAY_RADIUS)
			position.z = clampf(position.z, -PLAY_RADIUS, PLAY_RADIUS)
	if _crosshair != null:
		_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Look direction (for chapters that need an explicit forward).
func look_dir() -> Vector3:
	if _cam == null:
		return -global_transform.basis.z
	return -_cam.global_transform.basis.z


class _CrosshairDot extends Control:
	func _draw() -> void:
		var c := size * 0.5
		# Soft ring.
		draw_arc(c, 14.0, 0.0, TAU, 32, Color(1.0, 0.72, 0.25, 0.75), 2.0)
		# Glowing dot.
		draw_circle(c, 5.0, Color(1.0, 0.80, 0.35, 0.35))
		draw_circle(c, 2.5, Color(1.0, 0.85, 0.45, 1.0))
