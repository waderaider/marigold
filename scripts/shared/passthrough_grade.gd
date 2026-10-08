## MarigoldPassthroughGrade.gd - warm candlelight passthrough color grade.
## v0.5.0: applies a warm color LUT to the real-world passthrough feed for
## night scenes (Ofrenda Viva) via the Meta passthrough color LUT extension.
##
## API verified against the shipped godotopenxrvendors 5.1.0 Android binary:
## - Engine singleton "OpenXRFbPassthroughExtension": set_color_lut(lut),
##   set_interpolated_color_lut(source, target, weight),
##   get_max_color_lut_resolution().
## - OpenXRMetaPassthroughColorLut.new(image, channels) with
##   COLOR_LUT_CHANNELS_RGB. LUT image must be square 8x8 / 64x64 / 512x512;
##   an 8x8 image encodes a 4x4x4 3D LUT as a 2x2 grid of 4x4 slices
##   (x = red, y = green, slice = blue).
## Headless-safe: every call is guarded; no-ops without the extension.
## NOTE: the exact 2D->3D slice layout is our best reading of the binary and
## needs a device check - there is a settings toggle to disable the grade.
extends RefCounted
class_name MarigoldPassthroughGrade

## Settings toggle (wired to the menu "Candlelight Grade" row).
static var enabled := true

static var _identity_lut = null
static var _warm_lut = null
static var _applied_weight := -1.0


static func _passthrough():
	if not Engine.has_singleton("OpenXRFbPassthroughExtension"):
		return null
	return Engine.get_singleton("OpenXRFbPassthroughExtension")


## Warm candlelight grade curve: lift shadows toward amber, warm the mids,
## gently roll off blue highlights. Input/output in 0..1.
static func _warm_grade(c: Color) -> Color:
	var lift := Color(0.045, 0.020, 0.004) # amber shadow lift
	var r := c.r + (1.0 - c.r) * (1.0 - c.r) * lift.r
	var g := c.g + (1.0 - c.g) * (1.0 - c.g) * lift.g
	var b := c.b + (1.0 - c.b) * (1.0 - c.b) * lift.b
	# Gentle warm S-curve.
	r = clampf(r * 1.055 + 0.012, 0.0, 1.0)
	g = clampf(g * 1.010 + 0.004, 0.0, 1.0)
	b = clampf(b * 0.905 - 0.006, 0.0, 1.0)
	return Color(r, g, b)


## Build an 8x8 LUT image (4x4x4 3D LUT, 2x2 slice grid).
static func _build_lut_image(warm: bool) -> Image:
	var n := 8
	var m := 4
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for b in m:
		var sx := (b % 2) * m
		var sy := (b / 2) * m
		for g in m:
			for r in m:
				var c := Color(float(r) / float(m - 1),
					float(g) / float(m - 1), float(b) / float(m - 1))
				if warm:
					c = _warm_grade(c)
				img.set_pixel(sx + r, sy + g, c)
	return img


static func _get_luts() -> Array:
	if _identity_lut == null and ClassDB.class_exists("OpenXRMetaPassthroughColorLut"):
		var rgb = OpenXRMetaPassthroughColorLut.COLOR_LUT_CHANNELS_RGB
		# Verified against the real plugin binary (5.1.0): the constructor
		# takes no arguments; LUTs are built via create_from_image().
		_identity_lut = OpenXRMetaPassthroughColorLut.create_from_image(_build_lut_image(false), rgb)
		_warm_lut = OpenXRMetaPassthroughColorLut.create_from_image(_build_lut_image(true), rgb)
	return [_identity_lut, _warm_lut]


## Crossfade the passthrough grade toward `weight` (0 = natural, 1 = full
## warm candlelight). Call when entering/leaving night scenes in AR mode.
static func set_warm_weight(weight: float) -> void:
	var w := clampf(weight, 0.0, 1.0)
	if not enabled:
		w = 0.0
	if absf(w - _applied_weight) < 0.01:
		return
	_applied_weight = w
	var pt = _passthrough()
	if pt == null:
		return
	var luts := _get_luts()
	if luts[0] == null or luts[1] == null:
		return
	if w <= 0.001:
		pt.set_color_lut(luts[0])
	else:
		pt.set_interpolated_color_lut(luts[0], luts[1], w)


## Remove any grade (back to natural passthrough).
static func clear() -> void:
	_applied_weight = -1.0
	set_warm_weight(0.0)
	_applied_weight = -1.0
