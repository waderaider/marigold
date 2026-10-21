## candle_melt.gd - CandleMelt autoload: runtime candle wax simulation.
## GDScript port of the UE5 MarigoldCandleMelt world subsystem (MARIGOLD UE5
## v0.5.0 "Living wax"), adapted to Godot architecture:
##   UE5 world subsystem + actor discovery -> autoload + scene-group scan
##   UE5 ISM/HISM drip batches              -> three MultiMeshInstance3D
##   UE5 console marigold.wax.speed/.reset  -> persisted setting + F9/F10 keys
##   UE5 UMarigoldCandleFlames hooks        -> factory meta contract (below)
##
## Behaviour (UE5 defaults, cm converted to m): a lit candle heats up over
## ~25 s, then loses 1.25% of its height per minute at full temperature,
## never below 35% of its rest height. The wax mesh scales in Y about its
## base while the flame kit and candle light sink with the wick. Hot wax
## drips run down the wall, slow exponentially as they cool, and freeze
## partway; ~25% reach the foot and grow a wax pool. Unlit candles cool
## over ~45 s. Melt state is per-scene (the UE5 original does not persist
## it across sessions either); only the speed multiplier persists.
##
## Factory contract — candle builders (MarigoldFX.make_candle,
## ch1 _make_candle, ofrenda_finale ring) tag each candle root:
##   root.add_to_group("marigold_candles")
##   root.set_meta("melt_wax", wax_node)        Node3D scaled about its base
##   root.set_meta("melt_sinks", [nodes])       Node3Ds whose Y sinks with h
##   root.set_meta("melt_lit_mode", "always" | "anchor" | "meta")
##   root.set_meta("melt_anchor", kit_node)     for "anchor": lit = visible
##   root.set_meta("melt_lit", bool)            for "meta": chapter-driven
##   root.set_meta("melt_top", float)           rest wax-top Y in root space
##   root.set_meta("melt_radius", float)        wax radius in root space
##   root.set_meta("melt_light", omni)          optional, energy breathes
##   root.set_meta("melt_glow_mats", [mats])    optional, emission boost
extends Node

# --- Melt (UE5 defaults) -------------------------------------------------
const MELT_RATE_PER_MINUTE := 0.0125
const MIN_HEIGHT_FRACTION := 0.35
const HEAT_UP_SECONDS := 25.0
const COOL_DOWN_SECONDS := 45.0
const MOLTEN_GLOW_BOOST := 0.9
# --- Drips ---------------------------------------------------------------
const DRIP_INTERVAL_MIN := 4.0
const DRIP_INTERVAL_MAX := 12.0
const DRIP_FLOW_SPEED := 0.015 # m/s (UE5: 1.5 cm/s)
const DRIP_VISCOSITY_STEEPNESS := 5.0
const DRIP_COOL_MIN := 6.0
const DRIP_COOL_MAX := 20.0
const POOL_FEED_CHANCE := 0.25
const POOL_MAX_RADIUS_MULT := 2.0
const POOL_GROWTH_PER_DRIP := 0.0035 # m (UE5: 0.35 cm)
const POOL_THICKNESS := 0.003
const FREEZE_TEMP := 0.12
# --- Performance ---------------------------------------------------------
const ACTIVE_RADIUS := 15.0 # m (UE5: 1500 cm)
const SIM_RATE := 30.0
const MAX_LIVE_DRIPS := 192
const MAX_FROZEN_TOTAL := 1024
const MAX_PER_CANDLE_FROZEN := 32
const MAX_POOLS := 256

const BEAD_PATH := "res://assets/models/artist/wax_drip_bead.glb"
const SPEED_STEPS := [0.0, 1.0, 5.0, 20.0, 60.0]

var speed_mult := 1.0

var _candles: Array = [] # Dictionaries, see _register().
var _by_root := {} # root instance id -> candle dict
var _accum := 0.0
var _discover_t := 0.0
var _rng := RandomNumberGenerator.new()

var _live_mm: MultiMesh
var _live_mmi: MultiMeshInstance3D
var _live: Array = [] # slot -> drip dict or null
var _frozen_mm: MultiMesh
var _frozen_mmi: MultiMeshInstance3D
var _frozen_free: Array = [] # stack of free slot indices
var _pool_mm: MultiMesh
var _pool_mmi: MultiMeshInstance3D
var _bead_size := Vector3(0.008, 0.02, 0.003) # measured GLB bounds
var _hidden_xf := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))


func _ready() -> void:
	_rng.randomize()
	speed_mult = float(MarigoldSettings.get_value("wax", "speed_mult", 1.0))
	_build_batches()
	set_process(true)


## Validity-first casts: a plain `as` cast on a freed object raises a
## script error, so always test the raw Variant before casting.
func _n3(v: Variant) -> Node3D:
	if v == null or not is_instance_valid(v):
		return null
	return v as Node3D


func _omni(v: Variant) -> OmniLight3D:
	if v == null or not is_instance_valid(v):
		return null
	return v as OmniLight3D


## Console equivalents (UE5: marigold.wax.speed / marigold.wax.reset).
func set_speed(mult: float) -> void:
	speed_mult = clampf(mult, 0.0, 500.0)
	MarigoldSettings.set_value("wax", "speed_mult", speed_mult)
	print("[CandleMelt] wax speed x%.1f" % speed_mult)


func reset_wax() -> void:
	for c in _candles:
		c["height"] = 1.0
		c["temp"] = 0.0
		c["pool_radius"] = 0.0
		c["applied"] = -1.0
		_release_candle_frozen(c)
		if int(c["pool_slot"]) >= 0:
			_pool_mm.set_instance_transform(int(c["pool_slot"]), _hidden_xf)
			c["pool_slot"] = -1
	for i in _live.size():
		_live[i] = null
		_live_mm.set_instance_transform(i, _hidden_xf)
	print("[CandleMelt] wax reset (%d candles)." % _candles.size())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_F9:
			reset_wax()
		elif k == KEY_F10:
			var idx := SPEED_STEPS.find(speed_mult)
			set_speed(SPEED_STEPS[(idx + 1) % SPEED_STEPS.size()])


# ---------------------------------------------------------------- batches

func _build_batches() -> void:
	var bead_mesh: Mesh = null
	if ResourceLoader.exists(BEAD_PATH):
		var ps := load(BEAD_PATH) as PackedScene
		if ps != null:
			var probe := ps.instantiate()
			for mi in probe.find_children("", "MeshInstance3D", true, false):
				bead_mesh = (mi as MeshInstance3D).mesh
				break
			probe.free()
	if bead_mesh == null:
		var sm := SphereMesh.new()
		sm.radius = 0.004
		sm.height = 0.02
		bead_mesh = sm
	_live_mm = _make_batch(bead_mesh, MAX_LIVE_DRIPS)
	_live_mmi = _batch_node(_live_mm, "LiveDrips")
	_frozen_mm = _make_batch(bead_mesh, MAX_FROZEN_TOTAL)
	_frozen_mmi = _batch_node(_frozen_mm, "FrozenDrips")
	for i in range(MAX_FROZEN_TOTAL - 1, -1, -1):
		_frozen_free.append(i)
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = 1.0
	pool_mesh.bottom_radius = 1.0
	pool_mesh.height = 1.0
	pool_mesh.radial_segments = 20
	var wax_mat := StandardMaterial3D.new()
	wax_mat.albedo_color = Color(0.93, 0.86, 0.72)
	wax_mat.roughness = 0.35
	pool_mesh.material = wax_mat
	_pool_mm = _make_batch(pool_mesh, MAX_POOLS)
	_pool_mmi = _batch_node(_pool_mm, "WaxPools")
	_live.resize(MAX_LIVE_DRIPS)


func _make_batch(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, _hidden_xf)
	return mm


func _batch_node(mm: MultiMesh, nm: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	# Instances are placed in world space each step.
	mmi.top_level = true
	add_child(mmi)
	return mmi


# -------------------------------------------------------------- discovery

func _discover() -> void:
	for root in get_tree().get_nodes_in_group("marigold_candles"):
		var n := root as Node3D
		if n == null or _by_root.has(n.get_instance_id()):
			continue
		if not n.has_meta("melt_wax"):
			continue
		_register(n)


func _register(root: Node3D) -> void:
	var wax := root.get_meta("melt_wax") as Node3D
	if wax == null:
		return
	var sinks: Array = []
	var sink_rest: Array = []
	for s in (root.get_meta("melt_sinks", []) as Array):
		var sn := s as Node3D
		if sn != null:
			sinks.append(sn)
			sink_rest.append(sn.position.y)
	var glow: Array = []
	var glow_base: Array = []
	for m in (root.get_meta("melt_glow_mats", []) as Array):
		if m is StandardMaterial3D:
			glow.append(m)
			glow_base.append((m as StandardMaterial3D).emission_energy_multiplier)
	var light := root.get_meta("melt_light", null) as OmniLight3D
	var c := {
		"root": root, "root_id": root.get_instance_id(),
		"wax": wax, "wax_rest_y": wax.position.y,
		"sinks": sinks, "sink_rest": sink_rest,
		"lit_mode": String(root.get_meta("melt_lit_mode", "always")),
		"anchor": root.get_meta("melt_anchor", null) as Node3D,
		"top": float(root.get_meta("melt_top", 0.22)),
		"radius": float(root.get_meta("melt_radius", 0.04)),
		"light": light,
		"light_base": light.light_energy if light != null else 0.0,
		"glow": glow, "glow_base": glow_base,
		"height": 1.0, "temp": 0.0, "applied": -1.0,
		"drip_timer": _rng.randf_range(DRIP_INTERVAL_MIN, DRIP_INTERVAL_MAX),
		"pool_radius": 0.0, "pool_slot": -1, "frozen": [],
	}
	_candles.append(c)
	_by_root[root.get_instance_id()] = c


func _is_lit(c: Dictionary) -> bool:
	match String(c["lit_mode"]):
		"always":
			return true
		"anchor":
			var a := _n3(c["anchor"])
			return a != null and a.visible
		"meta":
			var r := _n3(c["root"])
			return r != null and bool(r.get_meta("melt_lit", false))
	return true


# ------------------------------------------------------------------- sim

func _process(delta: float) -> void:
	_discover_t -= delta
	if _discover_t <= 0.0:
		_discover_t = 1.0
		_discover()
	if speed_mult <= 0.0:
		return
	_accum += minf(delta, 0.1) * speed_mult
	var step := 1.0 / SIM_RATE
	var guard := 0
	while _accum >= step and guard < 40:
		_accum -= step
		_step(step)
		guard += 1
	if guard >= 40:
		_accum = 0.0


func _step(dt: float) -> void:
	# Prune freed candles (chapter changes).
	for i in range(_candles.size() - 1, -1, -1):
		if _n3(_candles[i]["root"]) == null:
			_by_root.erase(int(_candles[i].get("root_id", -1)))
			_release_candle_frozen(_candles[i])
			if int(_candles[i].get("pool_slot", -1)) >= 0:
				_pool_mm.set_instance_transform(int(_candles[i]["pool_slot"]), _hidden_xf)
			_candles.remove_at(i)
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	for c in _candles:
		_step_candle(c, dt, cam, cam_pos)
	_step_drips(dt)


func _step_candle(c: Dictionary, dt: float, cam: Camera3D, cam_pos: Vector3) -> void:
	var lit := _is_lit(c)
	if lit:
		c["temp"] = minf(1.0, float(c["temp"]) + dt / HEAT_UP_SECONDS)
	else:
		c["temp"] = maxf(0.0, float(c["temp"]) - dt / COOL_DOWN_SECONDS)
	var temp := float(c["temp"])
	if temp > 0.0 and lit:
		var dh := MELT_RATE_PER_MINUTE / 60.0 * temp * dt
		c["height"] = maxf(MIN_HEIGHT_FRACTION, float(c["height"]) - dh)
	var h := float(c["height"])
	if absf(h - float(c["applied"])) > 0.0005:
		c["applied"] = h
		var wax := _n3(c["wax"])
		if wax != null:
			wax.scale.y = h
			wax.position.y = float(c["wax_rest_y"]) * h
		var sinks: Array = c["sinks"]
		var rests: Array = c["sink_rest"]
		for i in sinks.size():
			var sn := _n3(sinks[i])
			if sn != null:
				sn.position.y = float(rests[i]) * h
		_consume_frozen_above(c)
	# Adopt a light registered late (ch1 adds its candle light on ignite).
	if c["light"] == null:
		var r := _n3(c["root"])
		if r != null and r.has_meta("melt_light"):
			var lt := _omni(r.get_meta("melt_light"))
			if lt != null:
				c["light"] = lt
				c["light_base"] = lt.light_energy
				(c["sinks"] as Array).append(lt)
				(c["sink_rest"] as Array).append(lt.position.y)
				c["applied"] = -1.0 # force a visual re-apply with the light
	# Molten glow: light energy + registered glow materials breathe with heat.
	var light := _omni(c["light"])
	if light != null:
		light.light_energy = float(c["light_base"]) * (1.0 + 0.35 * temp)
	var glow: Array = c["glow"]
	var bases: Array = c["glow_base"]
	for i in glow.size():
		var m := glow[i] as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = float(bases[i]) + MOLTEN_GLOW_BOOST * temp
	# Drip spawning (hot, near the camera or light-bearing like UE5).
	if temp > 0.55:
		c["drip_timer"] = float(c["drip_timer"]) - dt / temp
		if float(c["drip_timer"]) <= 0.0:
			c["drip_timer"] = _rng.randf_range(DRIP_INTERVAL_MIN, DRIP_INTERVAL_MAX)
			var root := _n3(c["root"])
			var near := cam != null and root != null and root.global_position.distance_to(cam_pos) <= ACTIVE_RADIUS
			if near or light != null:
				_spawn_drip(c)


# ------------------------------------------------------------------ drips

func _free_live_slot() -> int:
	for i in _live.size():
		if _live[i] == null:
			return i
	return -1


func _spawn_drip(c: Dictionary) -> void:
	if int(c["frozen"].size()) + _live_count_for(c) >= MAX_PER_CANDLE_FROZEN + 8:
		return
	var slot := _free_live_slot()
	if slot < 0:
		return
	var a := _rng.randf() * TAU
	_live[slot] = {
		"candle": c, "angle": a, "dist": 0.0, "vel": 0.0, "temp": 1.0,
		"tau": _rng.randf_range(DRIP_COOL_MIN, DRIP_COOL_MAX),
		"to_pool": _rng.randf() < POOL_FEED_CHANCE,
		"width": _rng.randf_range(0.006, 0.009),
		"phase": _rng.randf() * TAU,
	}


func _live_count_for(c: Dictionary) -> int:
	var n := 0
	for d in _live:
		if d != null and d["candle"] == c:
			n += 1
	return n


func _step_drips(dt: float) -> void:
	for slot in _live.size():
		var d = _live[slot]
		if d == null:
			continue
		var c: Dictionary = d["candle"]
		var root := _n3(c["root"])
		if root == null:
			_live[slot] = null
			_live_mm.set_instance_transform(slot, _hidden_xf)
			continue
		# Cooling (exponential) and viscous flow down the wall.
		d["temp"] = float(d["temp"]) * exp(-dt / float(d["tau"]))
		if bool(d["to_pool"]):
			d["temp"] = maxf(float(d["temp"]), 0.35)
		var target := DRIP_FLOW_SPEED * exp(-DRIP_VISCOSITY_STEEPNESS * (1.0 - float(d["temp"])))
		d["vel"] = move_toward(float(d["vel"]), target, dt * DRIP_FLOW_SPEED * 2.0)
		d["dist"] = float(d["dist"]) + float(d["vel"]) * dt
		d["angle"] = float(d["angle"]) + sin(Time.get_ticks_msec() * 0.001 + float(d["phase"])) * 0.01 * dt
		var wax_h := float(c["top"]) * float(c["height"])
		if float(d["dist"]) >= wax_h:
			_absorb_drip(slot, c)
		elif float(d["temp"]) < FREEZE_TEMP:
			_freeze_drip(slot, c)
		else:
			_live_mm.set_instance_transform(slot, _drip_transform(c, d))


func _drip_transform(c: Dictionary, d: Dictionary) -> Transform3D:
	var root := _n3(c["root"])
	var r := float(c["radius"])
	var top := float(c["top"]) * float(c["height"])
	var local := Vector3(cos(float(d["angle"])) * r, top - float(d["dist"]), sin(float(d["angle"])) * r)
	var origin := root.global_transform * local
	var stretch := clampf(0.6 + float(d["vel"]) / DRIP_FLOW_SPEED * 0.8, 0.6, 1.6)
	var sc := Vector3(float(d["width"]) / _bead_size.x, stretch, 1.0)
	return Transform3D(Basis.from_scale(sc), origin)


func _freeze_drip(slot: int, c: Dictionary) -> void:
	var d = _live[slot]
	_live[slot] = null
	_live_mm.set_instance_transform(slot, _hidden_xf)
	if _frozen_free.is_empty() or (c["frozen"] as Array).size() >= MAX_PER_CANDLE_FROZEN:
		return
	var fslot: int = _frozen_free.pop_back()
	_frozen_mm.set_instance_transform(fslot, _drip_transform(c, d))
	var top_frac := (float(c["top"]) - float(d["dist"])) / float(c["top"])
	(c["frozen"] as Array).append({"slot": fslot, "top_frac": top_frac})


func _absorb_drip(slot: int, c: Dictionary) -> void:
	_live[slot] = null
	_live_mm.set_instance_transform(slot, _hidden_xf)
	var cap := float(c["radius"]) * POOL_MAX_RADIUS_MULT
	c["pool_radius"] = minf(cap, float(c["pool_radius"]) + POOL_GROWTH_PER_DRIP)
	if float(c["pool_radius"]) <= 0.0:
		return
	if int(c["pool_slot"]) < 0:
		c["pool_slot"] = _alloc_pool_slot()
		if int(c["pool_slot"]) < 0:
			return
	var root := _n3(c["root"])
	if root == null:
		return
	var gt := root.global_transform
	var basis := Basis.from_euler(gt.basis.get_euler()) \
		.scaled(Vector3(float(c["pool_radius"]), POOL_THICKNESS, float(c["pool_radius"])))
	_pool_mm.set_instance_transform(int(c["pool_slot"]),
		Transform3D(basis, gt.origin + Vector3(0, POOL_THICKNESS * 0.5, 0)))


var _pool_cursor := 0


func _alloc_pool_slot() -> int:
	for i in MAX_POOLS:
		_pool_cursor = (_pool_cursor + 1) % MAX_POOLS
		var taken := false
		for c in _candles:
			if int(c["pool_slot"]) == _pool_cursor:
				taken = true
				break
		if not taken:
			return _pool_cursor
	return -1


func _consume_frozen_above(c: Dictionary) -> void:
	var frozen: Array = c["frozen"]
	var h := float(c["height"])
	for i in range(frozen.size() - 1, -1, -1):
		if float(frozen[i]["top_frac"]) > h + 0.01:
			var fslot: int = int(frozen[i]["slot"])
			_frozen_mm.set_instance_transform(fslot, _hidden_xf)
			_frozen_free.append(fslot)
			frozen.remove_at(i)


func _release_candle_frozen(c: Dictionary) -> void:
	for f in (c.get("frozen", []) as Array):
		var fslot: int = int(f["slot"])
		_frozen_mm.set_instance_transform(fslot, _hidden_xf)
		_frozen_free.append(fslot)
	(c["frozen"] as Array).clear()
