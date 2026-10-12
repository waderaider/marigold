## MarigoldState.gd - autoload holding global journey state.
## ar_mode: false = full immersive world, true = passthrough AR living-room mode.
extends Node

var ar_mode: bool = false
var chapter_index: int = 0
var music: MarigoldMusic = null
var journey_started: bool = false

const ANCHOR_PREFIX := "marigold_"


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
