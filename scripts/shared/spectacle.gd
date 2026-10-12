## MarigoldSpectacle.gd — MARIGOLD spectacle kit (v0.7.0, VFX Artist pass).
##
## One static call per "holy crap" moment: the ofrenda-reveal cascade,
## flight-transition choreography, and petal-teleport departure/arrival.
## Pure spectacle craft (timing, color, scale) — distinct from the
## Tech-Demo Engineer's flight/offrenda beats in CYCLE_V0110_BUILDER_NOTES.md.
##
## Quest 3 rules: GPU-light GPUParticles3D only, counts scaled by the
## graphics-quality multiplier (MarigoldGfx.particle_scale: Bajo 0.5 …
## Ultra 1.25); emissive sprites over sims; real OmniLight3D only for
## flickers, always time-boxed <1 s. Fire-and-forget, self-freeing.
## No audio (MarigoldMusic is the caller's job); haptics where physical.
## Headless-safe: node/tween/timer building only.
##
## Builder API:
##   MarigoldSpectacle.reveal_cascade(parent, anchors, gold)
##   MarigoldSpectacle.flight_slipstream(parent) -> GPUParticles3D
##   MarigoldSpectacle.flight_depart(parent, pos)
##   MarigoldSpectacle.flight_arrival(parent, pos)
##   MarigoldSpectacle.bell_flash(parent, pos)
##   MarigoldSpectacle.depart_implode(parent, pos)
##   MarigoldSpectacle.candle_ignite(parent, pos)
extends RefCounted
class_name MarigoldSpectacle

const GOLD := Color(1.0, 0.78, 0.30)
const PETAL := Color(1.0, 0.62, 0.12)


static func _pcount(amount: int) -> int:
	return maxi(1, int(round(float(amount) * MarigoldGfx.particle_scale())))


## OFRENDA FINALE reveal cascade: staggered petal fountains from each
## memory object (0.4 s apart), each igniting a beam of marigold light,
## then a converging flash sphere at the altar. `anchors`: Array[Vector3]
## local to `parent` (the four memory-object positions).
## Cost: 4 petal systems (~160), 4 beams, 1 flash sphere, ~2.6 s.
static func reveal_cascade(parent: Node, anchors: Array, gold: Color = GOLD) -> void:
	for i in anchors.size():
		var a: Vector3 = anchors[i]
		var d := 0.4 * float(i)
		_later(parent, d, func() -> void:
			MarigoldFX.scatter_petals(parent, a + Vector3(0, 0.3, 0), 40)
			candle_ignite(parent, a + Vector3(0, 0.2, 0))
			_light_beam(parent, a, gold)
		)
	_later(parent, 0.4 * float(anchors.size()) + 0.5, func() -> void:
		_flash_sphere(parent, _centroid(anchors) + Vector3(0, 0.8, 0), gold, 1.6)
	)
	MarigoldHaptics.fanfare()


## Flight slipstream: looping streak particles streaming past the camera
## during the glide. NOT one-shot — the caller stops it at arrival
## (emitting=false, then queue_free after 1 s). Cost: 1 system (60).
static func flight_slipstream(parent: Node) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = _pcount(60)
	p.lifetime = 0.55
	p.preprocess = 0.55
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(7.0, 2.5, 7.0)
	mat.direction = Vector3(0, 0, 1)
	mat.spread = 8.0
	mat.initial_velocity_min = 9.0
	mat.initial_velocity_max = 14.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.015
	mat.scale_max = 0.035
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.55, 0.0))
	grad.add_point(0.35, Color(1.0, 0.85, 0.55, 0.85))
	grad.set_color(1, Color(1.0, 0.85, 0.55, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.55) # long thin streaks
	quad.material = MarigoldFX.glow(Color(1.0, 0.85, 0.55), 1.6)
	p.draw_pass_1 = quad
	p.position = Vector3(0, 1.5, -6)
	parent.add_child(p)
	p.emitting = true
	return p


## Flight departure: updraft petal swirl + expanding ring at liftoff.
## Cost: 1 particle system (40), 1 ring, 1.4 s.
static func flight_depart(parent: Node, pos: Vector3) -> void:
	MarigoldFX.scatter_petals(parent, pos, 40)
	_ring(parent, pos, PETAL, 2.0, 0.8)


## Flight arrival: petal shower from above + warm ring pulse at the
## landing point + soft gold wash. Cost: 1 system (36), 1 ring, ~4 s.
static func flight_arrival(parent: Node, pos: Vector3) -> void:
	MarigoldFX.petal_ceiling_fall(parent, pos + Vector3(0, -1.0, 0), 1.8, 36, 4.0, 2.6)
	_ring(parent, pos, GOLD, 2.4, 1.0)
	_later(parent, 0.15, func() -> void: _ring(parent, pos, GOLD, 3.4, 1.0))


## Church-flyby landmark beat: god-ray flash on the steeple + expanding
## gold ring + sparkle burst, timed with the bell toll.
## Cost: 1 particle system (16), 2 meshes, 1.0 s.
static func bell_flash(parent: Node, pos: Vector3) -> void:
	_light_beam(parent, pos, GOLD, 2.2, 1.0)
	_ring(parent, pos + Vector3(0, -6.0, 0), GOLD, 3.0, 0.9)
	MarigoldFX.eye_sparkle(parent, pos, GOLD)


## Teleport departure implosion: petals converge and vanish where the
## player stood, leaving a fading ring. The arrival bloom already exists;
## this balances the choreography. Cost: 1 system (20), 1 ring, 1.0 s.
static func depart_implode(parent: Node, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = _pcount(20)
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.1
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.8
	mat.gravity = Vector3.ZERO
	mat.damping_min = 3.0
	mat.damping_max = 4.5
	mat.scale_min = 0.03
	mat.scale_max = 0.07
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.62, 0.10, 0.95))
	grad.set_color(1, Color(1.0, 0.62, 0.10, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.035)
	quad.material = MarigoldFX.glow(PETAL, 1.8)
	p.draw_pass_1 = quad
	p.top_level = true
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(parent, p, 1.4)
	_ring_top(parent, pos, PETAL, 1.8, 0.7)


## Candle ignition: warm spark burst + glow-quad flash where a flame
## catches. Wired to the finale's progressive candle lighting.
## Cost: 1 particle system (10), 1 quad, 0.8 s.
static func candle_ignite(parent: Node, pos: Vector3) -> void:
	MarigoldFX.spawn_sparks(parent, pos, Color(1.0, 0.65, 0.20), 10)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.35, 0.35)
	q.mesh = qm
	var m := MarigoldFX.glow(Color(1.0, 0.60, 0.18), 2.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.8
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material_override = m
	parent.add_child(q)
	q.position = pos
	var tw := q.create_tween()
	tw.set_parallel(true)
	tw.tween_property(q, "scale", Vector3.ONE * 1.8, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(q.queue_free)


# -------------------------------------------------------------- helpers ---

## Rising beam of light (unshaded cone, fades out). height in meters.
static func _light_beam(parent: Node, pos: Vector3, color: Color, height: float = 1.4, dur: float = 2.0) -> void:
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.10
	cm.bottom_radius = 0.30
	cm.height = height
	cm.radial_segments = 16
	cone.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.55)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.8
	cone.material_override = m
	parent.add_child(cone)
	cone.position = pos + Vector3(0, height * 0.5, 0)
	var tw := cone.create_tween()
	tw.set_parallel(true)
	tw.tween_property(cone, "scale", Vector3(1.5, 1.0, 1.5), dur * 0.6)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(cone.queue_free)


## Expanding flat ring (torus), parented normally.
static func _ring(parent: Node, pos: Vector3, color: Color, max_r: float, dur: float) -> void:
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.28
	rm.outer_radius = 0.36
	rm.rings = 28
	rm.ring_segments = 8
	ring.mesh = rm
	ring.material_override = MarigoldFX.glow(color, 2.4)
	ring.rotation_degrees.x = 90.0
	parent.add_child(ring)
	ring.position = pos + Vector3(0, 0.06, 0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * max_r, dur)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "transparency", 1.0, dur)
	tw.chain().tween_callback(ring.queue_free)


## Same ring but top-level (stays in world space when the world shifts).
static func _ring_top(parent: Node, global_pos: Vector3, color: Color, max_r: float, dur: float) -> void:
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.28
	rm.outer_radius = 0.36
	rm.rings = 28
	rm.ring_segments = 8
	ring.mesh = rm
	ring.material_override = MarigoldFX.glow(color, 2.4)
	ring.rotation_degrees.x = 90.0
	ring.top_level = true
	parent.add_child(ring)
	ring.global_position = global_pos + Vector3(0, 0.06, 0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * max_r, dur)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "transparency", 1.0, dur)
	tw.chain().tween_callback(ring.queue_free)


## Expanding flash sphere (unshaded, additive feel via high emission).
static func _flash_sphere(parent: Node, pos: Vector3, color: Color, max_r: float) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 16
	sm.rings = 8
	s.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 0.7)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.5
	s.material_override = m
	parent.add_child(s)
	s.position = pos
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector3.ONE * max_r, 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(s.queue_free)


static func _centroid(pts: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += (p as Vector3)
	return c / maxf(float(pts.size()), 1.0)


static func _later(parent: Node, delay: float, fn: Callable) -> void:
	var tree := parent.get_tree()
	if tree == null:
		return
	if delay <= 0.0:
		fn.call()
		return
	tree.create_timer(delay).timeout.connect(fn)


static func _free_later(parent: Node, n: Node, delay: float) -> void:
	_later(parent, delay, func() -> void:
		if is_instance_valid(n):
			n.queue_free()
	)
