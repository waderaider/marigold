## MarigoldState.gd - autoload holding global journey state.
## ar_mode: false = full immersive world, true = passthrough AR living-room mode.
extends Node

## Launch mode: how the player is experiencing MARIGOLD (v0.8.0, wade's
## order — real PC mode alongside VR).
## This is the SOURCE OF TRUTH for "are we on desktop or in a headset".
## get_viewport().use_xr is plumbing derived from the mode, never the source.
enum LaunchMode { UNSET, PC, VR }

var ar_mode: bool = false
var chapter_index: int = 0
var music: MarigoldMusic = null
var journey_started: bool = false
var launch_mode: int = LaunchMode.UNSET

const ANCHOR_PREFIX := "marigold_"


## True when running the desktop/monitor build (mouse + keyboard).
func is_pc_mode() -> bool:
	return launch_mode == LaunchMode.PC


## True when running in a headset (Quest standalone or PC VR via VD).
func is_vr_mode() -> bool:
	return launch_mode == LaunchMode.VR


## v0.7.0: graphics quality applies at boot, BEFORE the first frame
## (autoloads ready before the main scene). wade's order: the quality
## setting must measurably change rendering — see MarigoldGfx.
func _ready() -> void:
	MarigoldGfx.apply_boot()


func anchor_name(key: String) -> String:
	return ANCHOR_PREFIX + key


func reset() -> void:
	chapter_index = 0
	journey_started = false
