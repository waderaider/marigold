## MarigoldGfx.gd - graphics quality + control preferences (MARIGOLD v0.7.0).
## wade's order: a settings menu with graphics quality that MEASURABLY
## changes rendering. Audit rule: every knob below was verified against the
## real Godot 4.7.2 binary headless — knobs that don't exist in this build
## (anisotropy ProjectSetting, RenderingServer.directional_shadow_size_set,
## foveation singletons) were NOT shipped. No placebo toggles.
##
## Verified knobs:
## - Viewport.scaling_3d_scale (resolution scale): Low 0.70 / Med 0.85 /
##   High 1.00 / Ultra 1.25 (supersampling).
## - Viewport.msaa_3d: Low DISABLED / Med MSAA_2X / High+ MSAA_4X.
## - Viewport.scaling_3d_mode: FSR on Low (cheap upscale), bilinear above.
## - Particle density: MarigoldGfx.particle_scale() consumed by the MarigoldFX
##   spawn helpers (motes/petals/confetti/sparks): 0.5 / 0.75 / 1.0 / 1.25.
## Shadows (v0.9.3, skills audit): the game owns both shadowed lights
## (MarigoldSky sun + the retired rig key), so shadows ARE a real knob:
## Low/Medium -> sun shadow off; High/Ultra -> on. The light-rig key is
## now always unshadowed (the sun is the one shadow light).
## Foveation (v0.9.3): OpenXRInterface.foveation_level is set in main.gd
## before initialize(). Godot disables foveation while glow post-effects
## run, so on Quest the tiers make that trade-off explicitly:
## Low/Medium -> FFR 3/2 (dynamic) + glow OFF; High -> glow ON + FFR off.
## Ultra is PC-only (Quest maps Ultra -> High) and Quest caps are
## scale <= 1.0, MSAA <= 2X; Quest default quality is Medium.
##
## Persisted in MarigoldSettings (user://marigold_settings.cfg), applied at
## boot BEFORE the first frame from MarigoldState._ready (autoloads run
## before the main scene). Changes from the pause-menu Settings page apply
## live AND persist.
extends RefCounted
class_name MarigoldGfx

const QUALITIES := ["low", "medium", "high", "ultra"]
const QUALITY_LABEL := {"low": "Bajo", "medium": "Medio", "high": "Alto", "ultra": "Ultra"}
const INPUT_PREFS := ["auto", "controllers", "hands", "mouse"]
const INPUT_LABEL := {"auto": "Auto", "controllers": "Controles", "hands": "Manos", "mouse": "Ratón"}
const HANDS := ["right", "left"]
const HAND_LABEL := {"right": "Derecha", "left": "Izquierda"}

static var _particle_scale := 1.0


static func quality() -> String:
	var def := "medium" if OS.has_feature("android") else "high"
	var q := str(MarigoldSettings.get_value("gfx", "quality", def))
	return q if QUALITIES.has(q) else def


## The tier that actually renders: on Quest, Ultra maps to High (1.25x
## supersampling + MSAA 4X is a self-inflicted frame-killer standalone).
static func effective_quality() -> String:
	var q := quality()
	if q == "ultra" and OS.has_feature("android"):
		return "high"
	return q


## Shadow row of the quality table (v0.9.3): High/Ultra cast the sun's
## shadow; Low/Medium do not. Consulted by MarigoldSky at build time and
## re-applied live via MarigoldSky.refresh_quality().
static func shadows_on() -> bool:
	return effective_quality() == "high" or effective_quality() == "ultra"


## Glow row (v0.9.3): on Quest, glow runs only at High — Low/Medium trade
## it away so fixed foveated rendering can engage (glow disables FFR in
## the OpenXR path). PC keeps glow at every tier.
static func glow_on() -> bool:
	if OS.has_feature("android"):
		return effective_quality() == "high"
	return true


## FFR row (v0.9.3): OpenXRInterface.foveation_level for the persisted
## quality. 0 = off. Only meaningful on Quest; set pre-initialize.
static func foveation_level() -> int:
	if not OS.has_feature("android"):
		return 0
	match effective_quality():
		"low":
			return 3
		"medium":
			return 2
	return 0


static func set_quality(q: String) -> void:
	if not QUALITIES.has(q):
		return
	MarigoldSettings.set_value("gfx", "quality", q)
	_apply(q)


static func cycle_quality() -> String:
	var q := quality()
	set_quality(QUALITIES[(QUALITIES.find(q) + 1) % QUALITIES.size()])
	return quality()


static func quality_label() -> String:
	return str(QUALITY_LABEL.get(quality(), quality()))


## Particle-density multiplier for this frame's quality (0.5..1.25).
static func particle_scale() -> float:
	return _particle_scale


static func _scale_for(q: String) -> float:
	match q:
		"low":
			return 0.5
		"medium":
			return 0.75
		"ultra":
			return 1.25
	return 1.0


## Apply at boot (MarigoldState._ready, before first frame) or live from the
## settings page. All API verified against Godot 4.7.2.
static func _apply(_q: String) -> void:
	_particle_scale = _scale_for(effective_quality())
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var vp: Viewport = tree.root
	var on_quest := OS.has_feature("android")
	match effective_quality():
		"low":
			vp.scaling_3d_scale = 0.70
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		"medium":
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		"high":
			vp.scaling_3d_scale = 1.0
			# Quest cap: MSAA 2X in Compatibility stereo (4X is bandwidth-
			# bound on the tiled GPU); PC keeps 4X.
			vp.msaa_3d = Viewport.MSAA_2X if on_quest else Viewport.MSAA_4X
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		_: # ultra (PC only; Quest already mapped to high above)
			vp.scaling_3d_scale = 1.25
			vp.msaa_3d = Viewport.MSAA_4X
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	# Shadow/glow rows apply live to the sky's sun + environment.
	var sky_inst: Variant = MarigoldSky.instance
	if sky_inst != null and is_instance_valid(sky_inst):
		sky_inst.refresh_quality()


# ---- audio volumes (v0.9.3 A7: real bus volumes, persisted) ----

const VOL_STEPS: Array[int] = [0, 25, 50, 75, 100]


static func _bus_volume_pct(key: String) -> int:
	return int(MarigoldSettings.get_value("audio", key, 100))


static func _apply_bus_volume(bus: String, pct: int) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var f := clampf(float(pct) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx,
			-60.0 if f <= 0.001 else linear_to_db(f))


static func _cycle_bus_volume(key: String, bus: String) -> void:
	var cur := _bus_volume_pct(key)
	var idx := VOL_STEPS.find(cur)
	var nxt: int = VOL_STEPS[(idx + 1) % VOL_STEPS.size()] \
			if idx >= 0 else VOL_STEPS[VOL_STEPS.size() - 1]
	MarigoldSettings.set_value("audio", key, nxt)
	_apply_bus_volume(bus, nxt)


static func music_vol_label() -> String:
	return "%d%%" % _bus_volume_pct("music_vol")


static func sfx_vol_label() -> String:
	return "%d%%" % _bus_volume_pct("sfx_vol")


static func voice_vol_label() -> String:
	return "%d%%" % _bus_volume_pct("voice_vol")


static func cycle_music_volume() -> void:
	_cycle_bus_volume("music_vol", "Music")


static func cycle_sfx_volume() -> void:
	_cycle_bus_volume("sfx_vol", "SFX")


static func cycle_voice_volume() -> void:
	_cycle_bus_volume("voice_vol", "Voice")


static func apply_audio_volumes() -> void:
	_apply_bus_volume("Music", _bus_volume_pct("music_vol"))
	_apply_bus_volume("SFX", _bus_volume_pct("sfx_vol"))
	_apply_bus_volume("Voice", _bus_volume_pct("voice_vol"))


static func apply_boot() -> void:
	apply_audio_volumes()
	_apply(quality())


## ---- PC VR (Windows) ultra effects ----
## v0.7.0 PC VR: on Windows with the Forward+ renderer, Ultra quality
## unlocks the full showcase — SDFGI global illumination, screen-space
## reflections, SSAO, volumetric fog, and glow. These are per-Environment
## properties; call apply_pc_effects() on every WorldEnvironment.

## True on desktop Windows (not Android/Quest). PC VR via Virtual Desktop.
static func is_pc_vr() -> bool:
	return OS.has_feature("windows") and not OS.has_feature("android")


## PC effects are active when on Windows + Forward+ + Ultra quality.
static func pc_effects_active() -> bool:
	if not is_pc_vr():
		return false
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return false
	return quality() == "ultra"


## ---- Comfort & Accessibility (COMFORT_V0110.md) ----
## All settings persist in MarigoldSettings, applied at boot. Every option
## does something real (no placebo).

const TEXT_SIZES := ["normal", "large"]
const VIGNETTE_LEVELS := ["off", "soft", "strong"]
const FLIGHT_MODES := ["full", "short", "skip"]

## UI text size multiplier: Normal 1.0x, Large 1.4x (Comfort §3.1-A).
static func text_scale() -> float:
	var s := str(MarigoldSettings.get_value("comfort", "text_size", "normal"))
	return 1.4 if s == "large" else 1.0

static func set_text_size(s: String) -> void:
	if TEXT_SIZES.has(s):
		MarigoldSettings.set_value("comfort", "text_size", s)

static func cycle_text_size() -> String:
	var s := str(MarigoldSettings.get_value("comfort", "text_size", "normal"))
	var n: String = TEXT_SIZES[(TEXT_SIZES.find(s) + 1) % TEXT_SIZES.size()]
	set_text_size(n)
	return n

## Seated mode: panels at 1.15m instead of 1.55m (Comfort §3.1-B).
static func seated_mode() -> bool:
	return bool(MarigoldSettings.get_value("comfort", "seated", false))

static func set_seated_mode(on: bool) -> void:
	MarigoldSettings.set_value("comfort", "seated", on)

## Panel eye height: 1.15m seated, 1.55m standing.
static func panel_height() -> float:
	return 1.15 if seated_mode() else 1.55

## Vignette strength: off/soft/strong (Comfort §3.1-C, default soft).
static func vignette() -> String:
	var v := str(MarigoldSettings.get_value("comfort", "vignette", "soft"))
	return v if VIGNETTE_LEVELS.has(v) else "soft"

static func set_vignette(v: String) -> void:
	if VIGNETTE_LEVELS.has(v):
		MarigoldSettings.set_value("comfort", "vignette", v)

static func cycle_vignette() -> String:
	var v := vignette()
	var n: String = VIGNETTE_LEVELS[(VIGNETTE_LEVELS.find(v) + 1) % VIGNETTE_LEVELS.size()]
	set_vignette(n)
	return n

## Vignette max opacity: off 0.0, soft 0.55, strong 0.85.
static func vignette_max() -> float:
	match vignette():
		"soft":
			return 0.55
		"strong":
			return 0.85
	return 0.0

## Flight transitions: full (16s) / short (4s) / skip (fade) (Comfort §3.3-E).
static func flight_mode() -> String:
	var m := str(MarigoldSettings.get_value("comfort", "flight", "full"))
	return m if FLIGHT_MODES.has(m) else "full"

static func set_flight_mode(m: String) -> void:
	if FLIGHT_MODES.has(m):
		MarigoldSettings.set_value("comfort", "flight", m)

static func cycle_flight_mode() -> String:
	var m := flight_mode()
	var n: String = FLIGHT_MODES[(FLIGHT_MODES.find(m) + 1) % FLIGHT_MODES.size()]
	set_flight_mode(n)
	return n

## Flight duration in seconds: full 16, short 4, skip 0 (fade only).
static func flight_duration() -> float:
	match flight_mode():
		"short":
			return 4.0
		"skip":
			return 0.0
	return 16.0

## Subtitles: on/off, default ON (Comfort §3.3-F).
static func subtitles_on() -> bool:
	return bool(MarigoldSettings.get_value("comfort", "subtitles", true))

static func set_subtitles(on: bool) -> void:
	MarigoldSettings.set_value("comfort", "subtitles", on)

## One-handed dance assist for ch5 (Comfort §3.3-G).
static func dance_assist() -> bool:
	return bool(MarigoldSettings.get_value("comfort", "dance_assist", false))

static func set_dance_assist(on: bool) -> void:
	MarigoldSettings.set_value("comfort", "dance_assist", on)


## Upgrade an Environment with the full Forward+ showcase. Safe to call on
## Quest (no-op unless pc_effects_active). All properties verified in Godot 4.7.
static func apply_pc_effects(env: Environment) -> void:
	if env == null or not pc_effects_active():
		return
	# SDFGI: real-time global illumination (the "Pixar look" bounce light).
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 2 # SDFGI_CASCADES_4 (0-indexed enum)
	env.sdfgi_min_cell_size = 0.2
	# Screen-space reflections (wet marigold petals, water, glass).
	env.ss_reflections_enabled = true
	env.ss_reflections_roughness = 0.15
	# SSAO: contact shadows for depth.
	env.ssao_enabled = true
	env.ssao_light_affect = 0.4
	# Volumetric fog: god-rays through papel picado, candle glow.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_emission = Color(1.0, 0.6, 0.25)
	env.volumetric_fog_emission_energy = 0.3
	# Glow (bloom): candles, marigolds, neon accents pop.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15


## ---- control preferences (all real behavior, no placebo) ----

## Input method preference: gates which laser path draws beams.
## auto = current belt-and-suspenders behavior; controllers = controller
## beams only (hand beams hidden); hands = hand beams only.
static func input_pref() -> String:
	var p := str(MarigoldSettings.get_value("controls", "input", "auto"))
	return p if INPUT_PREFS.has(p) else "auto"


static func set_input_pref(p: String) -> void:
	if INPUT_PREFS.has(p):
		MarigoldSettings.set_value("controls", "input", p)


static func cycle_input_pref() -> String:
	var p := input_pref()
	set_input_pref(INPUT_PREFS[(INPUT_PREFS.find(p) + 1) % INPUT_PREFS.size()])
	return input_pref()


static func input_pref_label() -> String:
	return str(INPUT_LABEL.get(input_pref(), input_pref()))


static func controllers_only() -> bool:
	return input_pref() == "controllers"


static func hands_only() -> bool:
	return input_pref() == "hands"


## v0.8.0: explicit mouse preference (PC mode). Beams from both XR paths
## stay hidden — the cursor/teleport beam are the pointers.
static func mouse_only() -> bool:
	return input_pref() == "mouse"


## ---- PC mode settings (v0.8.0, wade's order — all real, no placebos) ----

## Mouse look sensitivity multiplier: 0.25 .. 3.0 (default 1.0).
static func mouse_sensitivity() -> float:
	return clampf(float(MarigoldSettings.get_value("controls", "mouse_sens", 1.0)),
			0.25, 3.0)


static func set_mouse_sensitivity(s: float) -> void:
	MarigoldSettings.set_value("controls", "mouse_sens", clampf(s, 0.25, 3.0))


static func cycle_mouse_sensitivity() -> float:
	# Steps through 0.5 / 0.75 / 1.0 / 1.5 / 2.0 — lands on the nearest step
	# above the current value.
	var steps := [0.5, 0.75, 1.0, 1.5, 2.0]
	var cur := mouse_sensitivity()
	for s in steps:
		if s > cur + 0.01:
			set_mouse_sensitivity(s)
			return s
	set_mouse_sensitivity(steps[0])
	return steps[0]


## Invert mouse Y for look.
static func mouse_invert_y() -> bool:
	return bool(MarigoldSettings.get_value("controls", "invert_y", false))


static func set_mouse_invert_y(on: bool) -> void:
	MarigoldSettings.set_value("controls", "invert_y", on)


## Fullscreen toggle (real: DisplayServer window mode).
static func fullscreen() -> bool:
	return bool(MarigoldSettings.get_value("display", "fullscreen", false))


static func set_fullscreen(on: bool) -> void:
	MarigoldSettings.set_value("display", "fullscreen", on)
	_apply_window()


## Window resolution for windowed mode (real: DisplayServer window size).
## "native" = leave the OS default.
const RESOLUTIONS := ["native", "1280x720", "1600x900", "1920x1080",
		"2560x1440", "3840x2160"]


static func resolution() -> String:
	var r := str(MarigoldSettings.get_value("display", "resolution", "native"))
	return r if RESOLUTIONS.has(r) else "native"


static func set_resolution(r: String) -> void:
	if not RESOLUTIONS.has(r):
		return
	MarigoldSettings.set_value("display", "resolution", r)
	_apply_window()


static func cycle_resolution() -> String:
	var r := resolution()
	set_resolution(RESOLUTIONS[(RESOLUTIONS.find(r) + 1) % RESOLUTIONS.size()])
	return resolution()


## Apply saved fullscreen + resolution at boot (called from _enter_pc_mode
## and from the setters above).
static func _apply_window() -> void:
	if OS.has_feature("android"):
		return # Quest: the OS owns the window
	if fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var r := resolution()
		if r != "native" and r.contains("x"):
			var parts := r.split("x")
			if parts.size() == 2 and parts[0].is_valid_int() \
					and parts[1].is_valid_int():
				DisplayServer.window_set_size(
						Vector2i(int(parts[0]), int(parts[1])))


static func apply_window_boot() -> void:
	_apply_window()


## Launch-mode persistence (v0.8.0 boot chooser). "pc" | "vr" | "" (unset).
static func saved_launch_mode() -> String:
	var m := str(MarigoldSettings.get_value("display", "mode", ""))
	return m if m == "pc" or m == "vr" else ""


static func save_launch_mode(m: String) -> void:
	if m == "pc" or m == "vr":
		MarigoldSettings.set_value("display", "mode", m)


## PC onboarding dismissed flag (v0.8.0 first-run screen).
static func pc_onboarded() -> bool:
	return bool(MarigoldSettings.get_value("display", "pc_onboarded", false))


static func set_pc_onboarded() -> void:
	MarigoldSettings.set_value("display", "pc_onboarded", true)


## Dominant hand: which controller aims the teleport laser + the default
## hand in Mano Magica's pointer fallbacks.
static func dominant_hand() -> String:
	var h := str(MarigoldSettings.get_value("controls", "hand", "right"))
	return h if HANDS.has(h) else "right"


static func set_dominant_hand(h: String) -> void:
	if HANDS.has(h):
		MarigoldSettings.set_value("controls", "hand", h)


static func cycle_dominant_hand() -> String:
	var h := dominant_hand()
	set_dominant_hand(HANDS[(HANDS.find(h) + 1) % HANDS.size()])
	return dominant_hand()


static func hand_label() -> String:
	return str(HAND_LABEL.get(dominant_hand(), dominant_hand()))


static func dominant_hand_idx() -> int:
	return MarigoldHands.HAND_RIGHT if dominant_hand() == "right" else MarigoldHands.HAND_LEFT


## Tool tips: the intro ControlsLegend card shown at chapter start.
## Off = clean view for experienced players (the pause-menu Controles page
## stays — that's reference, not a tooltip).
static func tooltips_on() -> bool:
	return bool(MarigoldSettings.get_value("controls", "tooltips", true))


static func set_tooltips(on: bool) -> void:
	MarigoldSettings.set_value("controls", "tooltips", on)
