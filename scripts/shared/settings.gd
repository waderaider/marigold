## MarigoldSettings.gd - persistent player settings (MARIGOLD v0.6.0).
## One ConfigFile (user://marigold_settings.cfg) backing: face-paint choice,
## photo collection, ofrenda progression, painted menagerie. Static API,
## headless-safe (file IO only, guarded).
extends RefCounted
class_name MarigoldSettings

const FILE := "user://marigold_settings.cfg"


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(FILE) # missing file is fine - defaults apply
	return cfg


static func get_value(section: String, key: String, default: Variant) -> Variant:
	var cfg := _load()
	return cfg.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var cfg := _load()
	cfg.set_value(section, key, value)
	cfg.save(FILE)


## Face-paint variant index (0..3), chosen at the mirror.
static func get_paint() -> int:
	return int(get_value("avatar", "paint", 0))


static func set_paint(idx: int) -> void:
	set_value("avatar", "paint", clampi(idx, 0, 3))
