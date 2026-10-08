## papel_picado.gd - MARIGOLD shared papel-picado cut-paper system (v0.6.0, finding 6).
## Procedural papel-picado (cut-paper) banners: festive base colors with
## punched cut-out patterns, used as alpha-TESTED textures (not alpha blend -
## cheaper on mobile, crisp edges). One generator serves both 2D UI (menu /
## pause banners as ImageTexture) and 3D (framed prints, altar arches as
## StandardMaterial3D with ALPHA_SCISSOR).
## All patterns are original geometric folk motifs - no copied artwork.
class_name MarigoldPapelPicado

static var _tex_cache := {}


## Festive palette (original colorways, not sampled from any film).
static func _palette() -> Array:
	return [
		Color(0.95, 0.20, 0.35), # rosa mexicano
		Color(1.00, 0.55, 0.10), # marigold
		Color(0.15, 0.55, 0.95), # azul
		Color(0.25, 0.75, 0.40), # verde
		Color(0.65, 0.30, 0.85), # morado
	]


## The 2D cut-paper texture. w/h in pixels; the punched holes are transparent.
static func banner_texture_2d(seed: int, w: int = 256, h: int = 96) -> ImageTexture:
	var key := "%d_%d_%d" % [seed, w, h]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pal := _palette()
	var base: Color = pal[rng.randi() % pal.size()]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(base)
	# White trim inset.
	var trim := Color(1, 1, 1, 0.92)
	var inset := 4
	for x in range(inset, w - inset):
		for yy in [inset, inset + 1, h - inset - 2, h - inset - 1]:
			img.set_pixel(x, yy, trim)
	for y in range(inset, h - inset):
		for xx in [inset, inset + 1, w - inset - 2, w - inset - 1]:
			img.set_pixel(xx, y, trim)
	# Punched cut-outs (transparent).
	var clear := Color(0, 0, 0, 0)
	# Central flower: ring of petal holes around a center hole.
	var cx := w / 2.0
	var cy := h / 2.0
	_punch(img, cx, cy, 7, clear)
	for p in 8:
		var a := TAU * float(p) / 8.0
		_punch(img, cx + cos(a) * 22.0, cy + sin(a) * 13.0, 5, clear)
	# Corner diamonds + side dots.
	for sx in [0.16, 0.84]:
		_punch_diamond(img, w * sx, cy, 9, clear)
		_punch(img, w * sx, cy - 20.0, 3, clear)
		_punch(img, w * sx, cy + 20.0, 3, clear)
	# Scalloped bottom edge: semicircular bites.
	var n := int(w / 24.0)
	for i in n:
		_punch(img, 12.0 + float(i) * 24.0, float(h) + 2.0, 9, clear)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func _punch(img: Image, cx: float, cy: float, r: int, clear: Color) -> void:
	for y in range(maxi(0, int(cy) - r), mini(img.get_height(), int(cy) + r + 1)):
		for x in range(maxi(0, int(cx) - r), mini(img.get_width(), int(cx) + r + 1)):
			var dx := float(x) - cx
			var dy := float(y) - cy
			if dx * dx + dy * dy <= float(r * r):
				img.set_pixel(x, y, clear)


static func _punch_diamond(img: Image, cx: float, cy: float, r: int, clear: Color) -> void:
	for y in range(maxi(0, int(cy) - r), mini(img.get_height(), int(cy) + r + 1)):
		for x in range(maxi(0, int(cx) - r), mini(img.get_width(), int(cx) + r + 1)):
			if absf(float(x) - cx) + absf(float(y) - cy) <= float(r):
				img.set_pixel(x, y, clear)


## The 3D banner material: alpha-tested cut paper, unshaded, slight emission
## so it glows warm under candlelight.
static func banner_material(seed: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = banner_texture_2d(seed)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission_texture = banner_texture_2d(seed)
	m.emission_energy_multiplier = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
