## sky.gd - MarigoldSky: dynamic atmosphere for MARIGOLD v0.4.0.
## Day/night cycle, procedural sky shader, seeded weather simulation, rain with
## wet-look ground, lightning + thunder, global wind system, exponential fog,
## windblown marigold leaves, AR passthrough mode, and gentle mode.
## Headless-safe: builds nodes/materials only, never assumes XR hardware.
## Quest-3-perf: capped particles, cheap sky shader, no SSAO/volumetrics.
class_name MarigoldSky
extends Node

static var instance: MarigoldSky = null

## Public handle to the environment this module drives.
var world_env: WorldEnvironment = null
## Full day/night cycle length in minutes when time_mode == "auto".
var cycle_minutes := 8.0

const TIME_PRESETS := {"dawn": 6.3, "day": 12.0, "sunset": 18.4, "night": 0.0}
const TIME_MODES := ["dawn", "day", "sunset", "night", "auto"]
const WEATHER_STATES := ["clear", "partly", "overcast", "rain", "storm", "fog", "windy"]
const GENTLE_STATES := ["clear", "partly"]

# Numeric weather params: [cloud_cover, fog_density, rain_amount, wind_base, dim]
const WEATHER_NUM := {
	"clear": [0.08, 0.018, 0.0, 0.15, 1.00],
	"partly": [0.38, 0.022, 0.0, 0.28, 0.95],
	"overcast": [0.85, 0.032, 0.0, 0.38, 0.70],
	"rain": [0.95, 0.050, 0.70, 0.55, 0.55],
	"storm": [1.00, 0.065, 1.00, 0.90, 0.42],
	"fog": [0.55, 0.160, 0.0, 0.10, 0.60],
	"windy": [0.30, 0.020, 0.0, 1.00, 0.90],
}
const WEATHER_LIGHTNING := {
	"clear": false, "partly": false, "overcast": false, "rain": false,
	"storm": true, "fog": false, "windy": false,
}
const WEATHER_WEIGHTS := {
	"clear": 3.0, "partly": 3.0, "overcast": 2.0, "rain": 1.5,
	"storm": 0.8, "fog": 1.0, "windy": 1.5,
}
const P_CLOUD := 0
const P_FOG := 1
const P_RAIN := 2
const P_WIND := 3
const P_DIM := 4

# Day keyframes: [hour, top, horizon, sun_color, ambient_energy, fog_color].
const DAY_KEYS := [
	[0.0, Color(0.02, 0.01, 0.08), Color(0.30, 0.07, 0.22), Color(0.45, 0.55, 0.95), 0.18, Color(0.30, 0.07, 0.22)],
	[5.0, Color(0.05, 0.03, 0.14), Color(0.45, 0.16, 0.32), Color(0.85, 0.50, 0.55), 0.28, Color(0.42, 0.15, 0.30)],
	[6.3, Color(0.16, 0.26, 0.58), Color(1.05, 0.55, 0.24), Color(1.00, 0.62, 0.30), 0.45, Color(0.90, 0.48, 0.28)],
	[8.5, Color(0.24, 0.48, 0.94), Color(0.68, 0.78, 0.94), Color(1.00, 0.90, 0.75), 0.62, Color(0.58, 0.68, 0.84)],
	[12.0, Color(0.20, 0.44, 0.95), Color(0.62, 0.76, 0.94), Color(1.00, 0.96, 0.86), 0.70, Color(0.58, 0.68, 0.84)],
	[16.0, Color(0.24, 0.44, 0.90), Color(0.74, 0.70, 0.78), Color(1.00, 0.85, 0.60), 0.62, Color(0.64, 0.60, 0.68)],
	[18.4, Color(0.26, 0.12, 0.46), Color(1.05, 0.44, 0.14), Color(1.00, 0.48, 0.18), 0.40, Color(0.86, 0.34, 0.18)],
	[19.8, Color(0.07, 0.05, 0.24), Color(0.58, 0.20, 0.30), Color(0.85, 0.40, 0.42), 0.30, Color(0.48, 0.17, 0.27)],
	[21.5, Color(0.03, 0.02, 0.11), Color(0.34, 0.08, 0.23), Color(0.45, 0.55, 0.95), 0.22, Color(0.30, 0.08, 0.22)],
	[24.0, Color(0.02, 0.01, 0.08), Color(0.30, 0.07, 0.22), Color(0.45, 0.55, 0.95), 0.18, Color(0.30, 0.07, 0.22)],
]

const SWAY_CODE := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform float wind_strength = 0.2;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway_amount = 1.0;
void vertex() {
	float phase = TIME * 2.5 + VERTEX.x * 1.7 + VERTEX.z * 2.3 + VERTEX.y * 3.1;
	float sway = (sin(phase) * 0.6 + sin(phase * 2.7) * 0.4) * wind_strength * sway_amount;
	float bend = 0.3 + clamp(UV.y, 0.0, 1.0);
	VERTEX.x += wind_dir.x * sway * bend;
	VERTEX.z += wind_dir.y * sway * bend;
}
void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
"""

var _time_mode := "sunset"
var _time_of_day := 18.4
var _weather := "clear"
var _weather_auto := true
var _weather_auto_before_ar := true
var _gentle := false
var _ar_mode := false

var _cur: Array = [0.08, 0.018, 0.0, 0.15, 1.0]
var _target: Array = [0.08, 0.018, 0.0, 0.15, 1.0]
var _lightning_now := false
var _lightning_target := false
var _blend := 1.0
var _state_time := 0.0
var _state_duration := 90.0
var _rng := RandomNumberGenerator.new()

var _t := 0.0
var _wind_angle := 0.6
var _wind_speed := 0.15
var _cloud_drift := 0.0

var _sky_mat: ShaderMaterial = null
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _rain: GPUParticles3D = null
var _rain_pm: ParticleProcessMaterial = null
var _leaves: GPUParticles3D = null
var _leaves_pm: ParticleProcessMaterial = null

var _flash_t := -1.0
var _next_strike := 7.0
var _thunder_at := -1.0
var _thunder_intensity := 1.0

var _ground: Dictionary = {}
var _amb_active := {}
var _amb_volume_set := false

static var _sway_shader: Shader = null
static var _sway_mats: Array = []


func _ready() -> void:
	instance = self
	_rng.randomize()
	_build_environment()
	_build_sun()
	_build_rain()
	_build_leaves()
	set_time_mode("sunset")
	_begin_transition("clear")
	_state_duration = _rng.randf_range(60.0, 150.0)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_t += delta
	# Time advance (paused in AR mode).
	if _time_mode == "auto" and not _ar_mode:
		_time_of_day = fmod(_time_of_day + delta * 24.0 / (cycle_minutes * 60.0), 24.0)
	# Weather auto-transitions.
	if _weather_auto and not _ar_mode:
		_state_time += delta
		if _state_time >= _state_duration:
			_pick_next_weather()
	# Cross-fade params over ~10s.
	_blend = minf(1.0, _blend + delta / 10.0)
	var k := 1.0 - exp(-0.45 * delta)
	for i in _cur.size():
		_cur[i] = lerpf(float(_cur[i]), float(_target[i]), k)
	_lightning_now = _lightning_target and _blend > 0.5
	_update_wind(delta)
	_apply_sky()
	_apply_rain(delta)
	_apply_leaves()
	_apply_wet_look(delta)
	_update_lightning(delta)
	_update_ambience()
	_update_sway_mats(_wind_speed, Vector2(cos(_wind_angle), sin(_wind_angle)))


# ---- Time API ----

func set_time_mode(mode: String) -> void:
	if not TIME_MODES.has(mode):
		push_warning("[MarigoldSky] unknown time mode: " + mode)
		return
	_time_mode = mode
	if TIME_PRESETS.has(mode):
		_time_of_day = float(TIME_PRESETS[mode])


func set_time_of_day(hours: float) -> void:
	_time_of_day = clampf(hours, 0.0, 24.0)


func get_time_of_day() -> float:
	return _time_of_day


# ---- Weather API ----

func set_weather(state: String) -> void:
	if not WEATHER_STATES.has(state):
		push_warning("[MarigoldSky] unknown weather: " + state)
		return
	if _gentle and not GENTLE_STATES.has(state):
		push_warning("[MarigoldSky] gentle mode rejects weather: " + state)
		return
	_begin_transition(state)


func get_weather() -> String:
	return _weather


func set_weather_auto(enabled: bool) -> void:
	_weather_auto = enabled


func set_gentle_mode(on: bool) -> void:
	_gentle = on
	if on:
		if not GENTLE_STATES.has(_weather):
			_begin_transition("clear")
	else:
		# Restore full auto range; next transition uses the full pool.
		if _weather_auto and not _ar_mode:
			_state_time = minf(_state_time, _state_duration - 1.0)


func set_ar_mode(on: bool) -> void:
	if on == _ar_mode:
		return
	_ar_mode = on
	if on:
		# Passthrough: calm clear visuals, pause the clock, keep wind/physics.
		_weather_auto_before_ar = _weather_auto
		_weather_auto = false
		_begin_transition("clear")
		# Force calm immediately so no rain/lightning over passthrough.
		_cur = _target.duplicate()
		_blend = 1.0
		_lightning_now = false
		_flash_t = -1.0
		_thunder_at = -1.0
	else:
		_weather_auto = _weather_auto_before_ar
		_pick_next_weather()


# ---- Wind API ----

func get_wind_at(pos: Vector3) -> Vector3:
	var dir := Vector2(cos(_wind_angle), sin(_wind_angle))
	var local_gust := 0.6 + 0.4 * (0.5 + 0.5 * sin(_t * 1.3 + pos.x * 0.15 + pos.z * 0.11))
	var speed: float = _wind_speed * local_gust
	return Vector3(dir.x, 0.0, dir.y) * speed


func get_wind_strength() -> float:
	return clampf(_wind_speed, 0.0, 1.0)


## Weather numeric params for gameplay hooks (v0.5.0).
## dim: 1.0 = full brightness, lower = darker (storm 0.42). Use to dim
## chapter lighting when storms roll in.
func get_dim() -> float:
	return _cur[P_DIM]


## Current rain amount 0..1 (rain 0.70, storm 1.0). Drives rain ripples on
## water surfaces.
func get_rain_amount() -> float:
	return _cur[P_RAIN]


# ---- Wet-look registration ----

func register_ground_material(mat: Material) -> void:
	var sm := mat as StandardMaterial3D
	if sm == null:
		push_warning("[MarigoldSky] register_ground_material needs StandardMaterial3D")
		return
	if _ground.has(sm):
		return
	_ground[sm] = [sm.albedo_color, sm.roughness]


## Shared wind-sway shader: materials share one Shader; per-frame uniforms are
## pushed to every live instance by MarigoldSky._process.
static func wind_sway_material(albedo: Color, sway_amount: float = 1.0) -> ShaderMaterial:
	if _sway_shader == null:
		_sway_shader = Shader.new()
		_sway_shader.code = SWAY_CODE
	var sm := ShaderMaterial.new()
	sm.shader = _sway_shader
	sm.set_shader_parameter("albedo", albedo)
	sm.set_shader_parameter("sway_amount", sway_amount)
	sm.set_shader_parameter("wind_strength", 0.2)
	sm.set_shader_parameter("wind_dir", Vector2(1.0, 0.0))
	_sway_mats.append(sm)
	return sm


static func _update_sway_mats(strength: float, dir: Vector2) -> void:
	for i in range(_sway_mats.size() - 1, -1, -1):
		var m: ShaderMaterial = _sway_mats[i]
		if not is_instance_valid(m):
			_sway_mats.remove_at(i)
			continue
		m.set_shader_parameter("wind_strength", strength)
		m.set_shader_parameter("wind_dir", dir)


## Wrap a Node3D in a RigidBody3D with an auto-fitted collision shape.
## shape: "box" | "sphere" | "capsule". Keeps the node's global transform.
static func make_dynamic(node: Node3D, shape: String, mass: float) -> RigidBody3D:
	var parent := node.get_parent()
	var gt := node.global_transform
	var body := RigidBody3D.new()
	body.name = node.name + "_Body"
	body.mass = maxf(mass, 0.01)
	if parent != null:
		parent.remove_child(node)
		parent.add_child(body)
	body.global_transform = gt
	body.add_child(node)
	node.transform = Transform3D.IDENTITY
	var col := CollisionShape3D.new()
	col.shape = _shape_for(node, shape)
	body.add_child(col)
	return body


static func _shape_for(node: Node3D, shape: String) -> Shape3D:
	var box := AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
	var found := false
	var to_local := Transform3D.IDENTITY
	if node.is_inside_tree():
		to_local = node.global_transform.affine_inverse()
	for mi in node.find_children("", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var mab: AABB = to_local * m.global_transform * m.get_aabb()
		if not found:
			box = mab
			found = true
		else:
			box = box.merge(mab)
	var size := box.size
	match shape:
		"sphere":
			var s := SphereShape3D.new()
			s.radius = maxf(maxf(size.x, size.y), size.z) * 0.5
			return s
		"capsule":
			var c := CapsuleShape3D.new()
			c.radius = maxf(size.x, size.z) * 0.5
			c.height = maxf(size.y, 0.1)
			return c
		_:
			var b := BoxShape3D.new()
			b.size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
			return b


# ---- Internals ----

func _music() -> MarigoldMusic:
	return MarigoldState.music


func _begin_transition(state: String) -> void:
	_weather = state
	_target = (WEATHER_NUM[state] as Array).duplicate()
	_lightning_target = bool(WEATHER_LIGHTNING[state])
	_blend = 0.0
	_state_time = 0.0
	_state_duration = _rng.randf_range(60.0, 150.0)


func _pick_next_weather() -> void:
	var pool: Array = GENTLE_STATES if _gentle else WEATHER_STATES
	var total := 0.0
	for s in pool:
		if s != _weather:
			total += float(WEATHER_WEIGHTS[s])
	if total <= 0.0:
		return
	var r := _rng.randf() * total
	var pick: String = pool[0]
	for s in pool:
		if s == _weather:
			continue
		r -= float(WEATHER_WEIGHTS[s])
		if r <= 0.0:
			pick = s
			break
	_begin_transition(pick)


func _sample_day() -> Array:
	# Returns [top, horizon, sun_color, ambient, fog_color] lerped between keys.
	var t := _time_of_day
	var prev: Array = DAY_KEYS[DAY_KEYS.size() - 1]
	var next: Array = DAY_KEYS[0]
	for i in DAY_KEYS.size():
		var key: Array = DAY_KEYS[i]
		if float(key[0]) <= t:
			prev = key
		if float(key[0]) > t:
			next = key
			break
	var t0 := float(prev[0])
	var t1 := float(next[0])
	var f := 0.0
	if t1 > t0:
		f = (t - t0) / (t1 - t0)
	f = clampf(f, 0.0, 1.0)
	return [
		(prev[1] as Color).lerp(next[1] as Color, f),
		(prev[2] as Color).lerp(next[2] as Color, f),
		(prev[3] as Color).lerp(next[3] as Color, f),
		lerpf(float(prev[4]), float(next[4]), f),
		(prev[5] as Color).lerp(next[5] as Color, f),
	]


func _is_day() -> bool:
	return _time_of_day >= 6.0 and _time_of_day <= 18.0


func _sun_direction() -> Vector3:
	var dt := (_time_of_day - 6.0) / 12.0
	var el := maxf(sin(dt * PI), 0.02)
	return Vector3(lerpf(-0.9, 0.9, dt), el, -0.35).normalized()


func _moon_direction() -> Vector3:
	var nt := fmod(_time_of_day - 18.0 + 24.0, 24.0) / 12.0
	var el := sin(nt * PI) * 0.85 + 0.12
	return Vector3(lerpf(0.8, -0.8, nt), maxf(el, 0.05), 0.4).normalized()


func _apply_sky() -> void:
	var day := _sample_day()
	var top: Color = day[0]
	var horizon: Color = day[1]
	var sun_col: Color = day[2]
	var ambient: float = day[3]
	var fog_col: Color = day[4]
	var dim: float = _cur[P_DIM]
	var is_day := _is_day()

	var elev_sin := 0.0
	var light_dir := Vector3(0, -1, 0)
	var energy := 0.06
	var light_col := Color(0.55, 0.65, 1.0)
	var night_factor := 1.0
	if is_day:
		var dt := (_time_of_day - 6.0) / 12.0
		elev_sin = sin(dt * PI)
		var sun_dir := _sun_direction()
		light_dir = -sun_dir
		energy = (0.3 + 1.15 * elev_sin) * dim
		light_col = sun_col
		night_factor = clampf(1.0 - elev_sin * 2.5, 0.0, 1.0)
		_sky_mat.set_shader_parameter("sun_dir", sun_dir)
		_sky_mat.set_shader_parameter("moon_dir", Vector3(0, -1, 0))
	else:
		var moon_dir := _moon_direction()
		light_dir = -moon_dir
		energy = 0.06
		_sky_mat.set_shader_parameter("moon_dir", moon_dir)
		_sky_mat.set_shader_parameter("sun_dir", Vector3(0, -1, 0))

	# Lightning double-blink spike.
	var flash_mult := 1.0
	if _flash_t >= 0.0:
		if _flash_t < 0.12:
			flash_mult = 5.0
		elif _flash_t < 0.20:
			flash_mult = 1.0
		elif _flash_t < 0.32:
			flash_mult = 4.0
	energy *= flash_mult

	var up := Vector3.UP
	if absf(light_dir.dot(up)) > 0.98:
		up = Vector3.RIGHT
	_sun.global_transform = Transform3D(Basis.looking_at(light_dir, up), Vector3.ZERO)
	_sun.light_energy = energy
	_sun.light_color = light_col

	_sky_mat.set_shader_parameter("sky_top_color", top)
	_sky_mat.set_shader_parameter("sky_horizon_color", horizon)
	_sky_mat.set_shader_parameter("ground_horizon_color", horizon * 0.45)
	_sky_mat.set_shader_parameter("sun_color", sun_col)
	_sky_mat.set_shader_parameter("night_factor", night_factor)
	_sky_mat.set_shader_parameter("cloud_cover", float(_cur[P_CLOUD]))
	_sky_mat.set_shader_parameter("cloud_drift", _cloud_drift)
	_sky_mat.set_shader_parameter("dim_factor", dim)

	_env.ambient_light_energy = ambient * (0.35 + 0.65 * dim)
	_env.fog_density = float(_cur[P_FOG])
	_env.fog_light_color = fog_col * (0.3 + 0.7 * dim)


func _update_wind(delta: float) -> void:
	_wind_angle += delta * 0.05 * (0.5 + 0.5 * sin(_t * 0.13))
	var gust := 0.8 + 0.2 * sin(_t * 0.9) + 0.08 * sin(_t * 2.3 + 1.7)
	var speed: float = float(_cur[P_WIND]) * gust
	if _gentle:
		speed = minf(speed, 0.35)
	_wind_speed = clampf(speed, 0.0, 1.0)
	_cloud_drift += delta * (0.01 + _wind_speed * 0.05)


func _apply_rain(delta: float) -> void:
	var rain_amt: float = _cur[P_RAIN]
	_rain.visible = rain_amt > 0.02
	_rain.amount_ratio = clampf(rain_amt, 0.0, 1.0)
	if _rain.visible:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var p := cam.global_position
			_rain.global_position = Vector3(p.x, 2.0, p.z)


func _apply_leaves() -> void:
	var ws := get_wind_strength()
	_leaves.visible = ws > 0.05
	_leaves.amount_ratio = clampf(ws * 1.2, 0.0, 1.0)
	if _leaves.visible:
		var w := Vector3(cos(_wind_angle), -0.25, sin(_wind_angle)).normalized()
		_leaves_pm.direction = w
		_leaves_pm.initial_velocity_min = 1.0 + ws * 3.0
		_leaves_pm.initial_velocity_max = 2.0 + ws * 5.0
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var p := cam.global_position
			_leaves.global_position = Vector3(p.x, 1.5, p.z)


func _apply_wet_look(delta: float) -> void:
	var wet: bool = float(_cur[P_RAIN]) > 0.05
	var k := minf(1.0, delta * 2.0)
	for mat in _ground.keys():
		if not is_instance_valid(mat):
			_ground.erase(mat)
			continue
		var sm := mat as StandardMaterial3D
		if sm == null:
			continue
		var orig: Array = _ground[sm]
		var target_a: Color = (orig[0] as Color) * 0.55 if wet else (orig[0] as Color)
		var target_r: float = minf(float(orig[1]), 0.22) if wet else float(orig[1])
		sm.albedo_color = sm.albedo_color.lerp(target_a, k)
		sm.roughness = lerpf(sm.roughness, target_r, k)


func _update_lightning(delta: float) -> void:
	var can_flash := _lightning_now and not _gentle and not _ar_mode
	if not can_flash:
		_flash_t = -1.0
		_thunder_at = -1.0
		return
	if _flash_t < 0.0:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_flash_t = 0.0
			_next_strike = _rng.randf_range(4.0, 11.0)
			_thunder_at = _t + _rng.randf_range(0.4, 2.8)
			_thunder_intensity = _rng.randf_range(0.6, 1.0)
	else:
		_flash_t += delta
		if _flash_t > 0.34:
			_flash_t = -1.0
	if _thunder_at > 0.0 and _t >= _thunder_at:
		_thunder_at = -1.0
		var m := _music()
		if m != null:
			m.play_thunder(_thunder_intensity)


func _update_ambience() -> void:
	var m := _music()
	if m == null:
		return
	var want := {}
	if float(_cur[P_RAIN]) > 0.08:
		want["rain"] = true
	if _wind_speed > 0.45:
		want["wind"] = true
	if want != _amb_active:
		m.stop_ambience()
		if not want.is_empty():
			if not _amb_volume_set:
				m.set_ambience_volume(-14.0)
				_amb_volume_set = true
			for kind in want:
				m.play_ambience(kind)
		_amb_active = want


func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "MarigoldSkyEnv"
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	var sh: Shader = load("res://shaders/sky.gdshader")
	_sky_mat.shader = sh
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.4
	# Vivid "HDR" look for Quest 3 (no true HDR panel), matching MarigoldFX.
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.15
	_env.tonemap_white = 1.2
	_env.glow_enabled = true
	_env.glow_intensity = 1.1
	_env.glow_strength = 1.45
	_env.glow_bloom = 0.35
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_density = 0.018
	_env.fog_light_color = Color(0.86, 0.34, 0.18)
	_env.fog_sky_affect = 0.35
	world_env.environment = _env
	add_child(world_env)


func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "MarigoldSun"
	_sun.shadow_enabled = true
	add_child(_sun)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "MarigoldRain"
	_rain.amount = 600
	_rain.lifetime = 1.1
	_rain.preprocess = 1.1
	_rain.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	_rain_pm = ParticleProcessMaterial.new()
	_rain_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_pm.emission_box_extents = Vector3(7, 7, 7)
	_rain_pm.direction = Vector3(0, -1, 0)
	_rain_pm.spread = 4.0
	_rain_pm.initial_velocity_min = 9.0
	_rain_pm.initial_velocity_max = 13.0
	_rain_pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = _rain_pm
	var streak := BoxMesh.new()
	streak.size = Vector3(0.02, 0.45, 0.02)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.6, 0.75, 0.95, 0.35)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = sm
	_rain.draw_pass_1 = streak
	_rain.amount_ratio = 0.0
	_rain.visible = false
	add_child(_rain)


func _build_leaves() -> void:
	_leaves = GPUParticles3D.new()
	_leaves.name = "MarigoldLeaves"
	_leaves.amount = 120
	_leaves.lifetime = 6.0
	_leaves.preprocess = 6.0
	_leaves.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 20, 60))
	_leaves_pm = ParticleProcessMaterial.new()
	_leaves_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_leaves_pm.emission_box_extents = Vector3(10, 3, 10)
	_leaves_pm.direction = Vector3(1, -0.25, 0)
	_leaves_pm.spread = 25.0
	_leaves_pm.initial_velocity_min = 1.5
	_leaves_pm.initial_velocity_max = 3.0
	_leaves_pm.gravity = Vector3(0, -0.35, 0)
	_leaves_pm.damping_min = 0.3
	_leaves_pm.damping_max = 0.8
	_leaves_pm.color = Color(1.0, 0.55, 0.15)
	_leaves_pm.hue_variation_min = -0.06
	_leaves_pm.hue_variation_max = 0.06
	_leaves.process_material = _leaves_pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var lm := StandardMaterial3D.new()
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.albedo_color = Color(1, 1, 1)
	quad.material = lm
	_leaves.draw_pass_1 = quad
	_leaves.amount_ratio = 0.0
	_leaves.visible = false
	add_child(_leaves)
