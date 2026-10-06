## MarigoldFX.gd - shared visual kit for MARIGOLD.
## Static helpers: PBR material factory, emissive glow, light rigs, particle
## juice (sparks/confetti/trails), and styled floating UI labels.
## All helpers are headless-safe: they only build nodes/materials, never
## require XR hardware or a rendering device at parse time.
extends RefCounted
class_name MarigoldFX


## PBR material factory.
static func pbr(color: Color, metallic: float = 0.0, roughness: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = clampf(metallic, 0.0, 1.0)
	m.roughness = clampf(roughness, 0.05, 1.0)
	return m


## Named PBR presets: "plastic", "metal", "glass", "matte", "rubber", "neon".
static func pbr_preset(color: Color, preset: String = "plastic") -> StandardMaterial3D:
	match preset:
		"metal":
			return pbr(color, 0.9, 0.25)
		"glass":
			var m := pbr(color, 0.1, 0.05)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35
			return m
		"matte":
			return pbr(color, 0.0, 0.9)
		"rubber":
			return pbr(color, 0.0, 0.75)
		"neon":
			return glow(color, 1.6)
		_:
			return pbr(color, 0.15, 0.45)


## Emissive glow material (unshaded bright + emission).
static func glow(color: Color, intensity: float = 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = intensity
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Soft pulsing glow: call each frame with a phase to animate emission.
static func pulse_glow(mat: StandardMaterial3D, base: float, amp: float, t: float, speed: float = 2.0) -> void:
	if mat == null:
		return
	mat.emission_energy_multiplier = base + amp * (0.5 + 0.5 * sin(t * speed))


## Three-point light rig: key (shadowed), fill, rim. Returns the key light.
static func make_light_rig(parent: Node3D, key_energy: float = 1.2) -> DirectionalLight3D:
	var key := DirectionalLight3D.new()
	key.name = "PolishKeyLight"
	key.light_energy = key_energy
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	parent.add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "PolishFillLight"
	fill.light_energy = 0.5
	fill.light_color = Color(0.6, 0.75, 1.0)
	fill.position = Vector3(-2.0, 2.0, 2.0)
	fill.omni_range = 8.0
	parent.add_child(fill)

	var rim := SpotLight3D.new()
	rim.name = "PolishRimLight"
	rim.light_energy = 0.8
	rim.light_color = Color(1.0, 0.6, 0.9)
	rim.position = Vector3(2.0, 2.5, -2.0)
	rim.spot_range = 10.0
	parent.add_child(rim)
	return key


## Warm point light for accenting a single object.
static func make_point_light(parent: Node3D, pos: Vector3, color: Color, energy: float = 1.0, light_range: float = 4.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.position = pos
	parent.add_child(l)
	return l


## One-shot spark burst at a position. Frees itself when done.
static func spawn_sparks(parent: Node, pos: Vector3, color: Color = Color(1.0, 0.8, 0.2), amount: int = 24) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.06
	mat.color = color
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var qm := glow(color, 2.0)
	quad.material = qm
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	var t := parent.get_tree().create_timer(1.5)
	t.timeout.connect(p.queue_free)
	return p


## Confetti burst (slower, colorful, low gravity).
static func spawn_confetti(parent: Node, pos: Vector3, amount: int = 60) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.0
	p.one_shot = true
	p.explosiveness = 0.85
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -3.0, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.08
	# Color ramp across the rainbow.
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.2, 0.4))
	grad.add_point(0.5, Color(0.2, 1, 0.5))
	grad.set_color(1, Color(0.3, 0.5, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.04)
	quad.material = glow(Color(1, 1, 1), 1.2)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	var t := parent.get_tree().create_timer(3.0)
	t.timeout.connect(p.queue_free)
	return p


## Ambient floating dust motes around an area (looping, subtle).
static func spawn_ambient_motes(parent: Node3D, center: Vector3, radius: float = 2.0, amount: int = 40) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.position = center
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 20.0
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.25
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.01
	mat.scale_max = 0.03
	mat.color = Color(0.7, 0.85, 1.0, 0.6)
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = glow(Color(0.7, 0.85, 1.0), 1.0)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	return p


## Trail emitter to attach to a moving node (e.g. blades, balls, rackets).
static func make_trail(color: Color = Color(0.4, 0.9, 1.0), width: float = 0.05) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 32
	p.lifetime = 0.45
	p.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3.ZERO
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.1
	mat.gravity = Vector3.ZERO
	mat.scale_min = width * 0.4
	mat.scale_max = width
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.9))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(width, width)
	quad.material = glow(color, 1.8)
	p.draw_pass_1 = quad
	p.emitting = true
	return p


## Styled floating Label3D with outline for readability over passthrough.
static func make_label(text: String, font_size: int = 64, color: Color = Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	return l


## Small helper: ease a node toward a target scale (call in _process).
static func ease_scale(node: Node3D, target: Vector3, speed: float, delta: float) -> void:
	if node == null:
		return
	node.scale = node.scale.lerp(target, clampf(speed * delta, 0.0, 1.0))


## ---------------- MARIGOLD originals ----------------

## Field of instanced glowing marigolds (cempasúchil). Cheap: one MultiMesh.
static func make_marigold_field(parent: Node3D, count: int = 220, radius: float = 9.0) -> MultiMeshInstance3D:
	var blossom := SphereMesh.new()
	blossom.radius = 0.09
	blossom.height = 0.12
	blossom.radial_segments = 8
	blossom.rings = 4
	blossom.material = glow(Color(1.0, 0.55, 0.08), 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blossom
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in count:
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		var s := rng.randf_range(0.7, 1.6)
		var t := Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(cos(a) * r, rng.randf_range(0.02, 0.10), sin(a) * r)
		)
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	# Dark stems: second multimesh of thin cylinders.
	var stem := CylinderMesh.new()
	stem.top_radius = 0.008
	stem.bottom_radius = 0.012
	stem.height = 0.25
	stem.material = pbr(Color(0.15, 0.35, 0.12), 0.0, 0.9)
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.mesh = stem
	sm.instance_count = count
	for i in count:
		var t: Transform3D = mm.get_instance_transform(i)
		t.origin.y = 0.0
		sm.set_instance_transform(i, t)
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = sm
	parent.add_child(smi)
	return mmi


## Volumetric-feeling god ray: layered transparent tapered cones.
static func make_god_ray(parent: Node3D, pos: Vector3, height: float = 7.0, color: Color = Color(1.0, 0.75, 0.35)) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	for layer in 3:
		var cone := CylinderMesh.new()
		var w := 0.5 + layer * 0.45
		cone.top_radius = w * 0.35
		cone.bottom_radius = w
		cone.height = height
		cone.radial_segments = 16
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r, color.g, color.b, 0.10 - layer * 0.025)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.position.y = height * 0.5
		root.add_child(mi)
	return root


## Papel picado banner: waving cut-paper plane with scalloped shader edge.
static func make_papel_banner(parent: Node3D, width: float = 3.0, height: float = 1.2, color: Color = Color(1.0, 0.3, 0.6)) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, height)
	plane.subdivide_width = 24
	plane.subdivide_depth = 8
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.6, 1.0);
uniform float wave_speed = 2.2;
uniform float wave_amp = 0.09;
void vertex() {
	float hang = 1.0 - UV.y;
	VERTEX.z += sin(VERTEX.x * 5.0 + TIME * wave_speed) * wave_amp * hang;
	VERTEX.z += sin(VERTEX.x * 11.0 - TIME * wave_speed * 1.7) * wave_amp * 0.4 * hang;
}
void fragment() {
	float edge = UV.y - 0.10 * abs(sin(UV.x * 36.0));
	float cut = smoothstep(0.02, 0.09, edge);
	float dots = step(0.75, fract(sin(dot(floor(UV * vec2(24.0, 8.0)), vec2(12.9898, 78.233))) * 43758.5453));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA = cut * (1.0 - dots * 0.85);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 0.35;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("tint", color)
	plane.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	# PlaneMesh lies flat; rotate to hang vertically like a banner.
	mi.rotation_degrees.x = 90.0
	parent.add_child(mi)
	return mi


## Candle with flame particles and a warm point light. Budget lights!
static func make_candle(parent: Node3D, pos: Vector3, with_light: bool = true, light_energy: float = 0.9) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var wax := CylinderMesh.new()
	wax.top_radius = 0.035
	wax.bottom_radius = 0.04
	wax.height = 0.22
	wax.material = pbr(Color(0.95, 0.88, 0.75), 0.0, 0.6)
	var wax_mi := MeshInstance3D.new()
	wax_mi.mesh = wax
	wax_mi.position.y = 0.11
	root.add_child(wax_mi)
	var flame := SphereMesh.new()
	flame.radius = 0.025
	flame.height = 0.07
	flame.material = glow(Color(1.0, 0.65, 0.15), 3.0)
	var flame_mi := MeshInstance3D.new()
	flame_mi.mesh = flame
	flame_mi.name = "Flame"
	flame_mi.position.y = 0.26
	root.add_child(flame_mi)
	# Flickering fire particles.
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.5
	p.position.y = 0.26
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.008
	pm.scale_max = 0.02
	pm.color = Color(1.0, 0.6, 0.15, 0.9)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = glow(Color(1.0, 0.6, 0.15), 2.5)
	p.draw_pass_1 = quad
	root.add_child(p)
	p.emitting = true
	if with_light:
		make_point_light(root, Vector3(0, 0.35, 0), Color(1.0, 0.62, 0.25), light_energy, 3.5)
	return root


## Night sky: deep indigo-to-magenta gradient with procedural stars.
static func make_night_sky(parent: Node) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.03, 0.01, 0.10)
	mat.sky_horizon_color = Color(0.35, 0.08, 0.25)
	mat.ground_bottom_color = Color(0.01, 0.0, 0.03)
	mat.ground_horizon_color = Color(0.20, 0.05, 0.18)
	mat.sun_angle_max = 30.0
	sky.sky_material = mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 1.2
	# Vivid "HDR" look for Quest 3 (no true HDR panel): strong bloom on all
	# emissives, boosted intensities, saturated colors.
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_strength = 1.45
	env.glow_bloom = 0.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Depth cueing: subtle exponential fog in marigold orange-teal.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.028
	env.fog_light_color = Color(0.45, 0.18, 0.35)
	env.fog_sky_affect = 0.35
	we.environment = env
	parent.add_child(we)
	return we


## Luminous water plane with slow animated shimmer.
static func make_luminous_water(parent: Node3D, size: float = 30.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform vec4 deep : source_color = vec4(0.02, 0.05, 0.16, 1.0);
uniform vec4 glint : source_color = vec4(1.0, 0.55, 0.15, 1.0);
void vertex() {
	VERTEX.y += sin(VERTEX.x * 1.5 + TIME * 1.2) * 0.03 + cos(VERTEX.z * 1.8 + TIME * 0.9) * 0.03;
}
void fragment() {
	float w = sin(UV.x * 60.0 + TIME * 1.5) * sin(UV.y * 60.0 - TIME * 1.1);
	float sparkle = smoothstep(0.75, 1.0, w);
	ALBEDO = mix(deep.rgb, glint.rgb, sparkle * 0.5);
	EMISSION = glint.rgb * sparkle * 0.8;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	plane.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	parent.add_child(mi)
	return mi


## Burst of glowing marigold petals (celebration / footstep scatter).
static func scatter_petals(parent: Node, pos: Vector3, amount: int = 30) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.75
	p.position = pos
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -2.2, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	mat.scale_min = 0.03
	mat.scale_max = 0.07
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.62, 0.10))
	grad.add_point(0.5, Color(1.0, 0.80, 0.25))
	grad.set_color(1, Color(0.85, 0.35, 0.05))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.035)
	quad.material = glow(Color(1.0, 0.65, 0.12), 1.8)
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	var t := parent.get_tree().create_timer(2.5)
	t.timeout.connect(p.queue_free)
	return p
