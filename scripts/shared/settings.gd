## MarigoldSettings.gd - persistent player settings (MARIGOLD v0.6.0).
## One ConfigFile (user://marigold_settings.cfg) backing: face-paint choice,
## photo collection, ofrenda progression, painted menagerie. Static API,
## headless-safe (file IO only, guarded).
##
## v0.9.3 (save-systems skill pass):
## - The ConfigFile is cached in memory: get_value() no longer reloads the
##   file from disk on every call (it was being hit per-frame from the
##   pause menu, launcher and every chapter's teleport aim).
## - Saves are atomic: write .tmp -> rotate current to .bak -> rename.
##   A crash mid-save can no longer truncate the only copy.
## - Files carry meta/schema_version so future key migrations are possible;
##   load falls back to the .bak copy before giving up to defaults.
## - load_cfg()/save_cfg() are the shared persistence discipline for the
##   other ConfigFiles in the project (journey progress, hand anchors).
extends RefCounted
class_name MarigoldSettings

const FILE := "user://marigold_settings.cfg"
const SCHEMA_VERSION := 1

static var _cache: ConfigFile = null
static var _cache_loaded := false


static func _load() -> ConfigFile:
	if _cache_loaded and _cache != null:
		return _cache
	_cache = load_cfg(FILE)
	_cache_loaded = true
	return _cache


## Load a ConfigFile defensively: main file, then .bak, then empty.
static func load_cfg(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		return cfg
	var bak := ConfigFile.new()
	if bak.load(path + ".bak") == OK:
		push_warning("[MarigoldSettings] %s unreadable - recovered from .bak" % path)
		return bak
	return cfg


## Save a ConfigFile atomically (tmp -> bak -> rename). Returns the Error.
static func save_cfg(cfg: ConfigFile, path: String) -> Error:
	cfg.set_value("meta", "schema_version", SCHEMA_VERSION)
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		push_warning("[MarigoldSettings] save to %s failed: %s" % tmp, err)
		return err
	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_bak := abs_path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(abs_bak)
		DirAccess.rename_absolute(abs_path, abs_bak)
	err = DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		push_warning("[MarigoldSettings] rename %s -> %s failed: %s" % [tmp, path, err])
	return err


static func get_value(section: String, key: String, default: Variant) -> Variant:
	var cfg := _load()
	return cfg.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var cfg := _load()
	cfg.set_value(section, key, value)
	save_cfg(cfg, FILE)


## Face-paint variant index (0..3), chosen at the mirror.
static func get_paint() -> int:
	return int(get_value("avatar", "paint", 0))


static func set_paint(idx: int) -> void:
	set_value("avatar", "paint", clampi(idx, 0, 3))
