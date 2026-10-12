## vignette.gd - MarigoldVignette: dynamic comfort vignette (MARIGOLD v0.7.0).
## Comfort spec (COMFORT_V0110.md §3.1-C, §4.2): peripheral vignette during
## smooth camera/world motion. Opacity = strength × motion factor, eased.
## One camera-attached quad, radial-gradient feathered edge. Cheap.
## Headless-safe: builds nodes only, never assumes XR hardware.
extends Node

static var instance: MarigoldVignette = null

var _quad: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _current := 0.0
var _target := 0.0


func _ready() -> void:
	instance = self
	_build()


func _build() -> void:
	# Camera-attached quad: parent to camera in _process (camera may change).
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	_quad = MeshInstance3D.new()
	_quad.mesh = q
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	// Feathered edge: transparent center, dark periphery.
	float v = smoothstep(0.55, 1.05, d);
	ALBEDO = vec3(0.0, 0.0, 0.0);
	ALPHA = v * opacity;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = shader
	_mat = null # using shader material
	_quad.material_override = sm
	_quad.visible = false
	add_child(_quad)


func _process(delta: float) -> void:
	if _quad == null:
		return
	# Ease toward target (0.4s).
	var rate := delta / 0.4
	_current = lerpf(_current, _target, minf(1.0, rate))
	if _current < 0.01:
		_quad.visible = false
		return
	_quad.visible = true
	# Attach to camera.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_quad.global_transform = cam.global_transform * Transform3D(
			Basis(), Vector3(0, 0, -0.5))
		var sm := _quad.material_override as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter("opacity", _current)


## Set the motion factor (0.0 = stationary, 1.0 = max speed).
## Opacity = vignette_max() × motion_factor.
static func set_motion(factor: float) -> void:
	if instance == null:
		return
	var max_op := MarigoldGfx.vignette_max()
	instance._target = max_op * clampf(factor, 0.0, 1.0)


## Convenience: drive from a speed value (e.g. flight velocity).
static func set_speed(speed: float, max_speed: float) -> void:
	if max_speed <= 0.0:
		set_motion(0.0)
	else:
		set_motion(clampf(speed / max_speed, 0.0, 1.0))
