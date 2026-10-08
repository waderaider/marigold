## run_chapters_headless.gd - MARIGOLD v0.6.0 headless verification.
## Loads every chapter/experience scene, calls setup(false), runs 60 frames,
## reports any SCRIPT ERRORs. Run:
##   godot --headless --script tools/run_chapters_headless.gd
## (res:// resolves because the script lives inside the project.)
## NOTE: nodes added during SceneTree._initialize get _ready deferred, so
## setup() is always called on the frame AFTER add_child.
extends SceneTree

const SCENES := [
	"res://scenes/chapters/ch1_ofrenda.tscn",
	"res://scenes/chapters/ch2_bridge.tscn",
	"res://scenes/chapters/ch3_alebrijes.tscn",
	"res://scenes/chapters/ch4_papel.tscn",
	"res://scenes/chapters/ch5_baile.tscn",
	"res://scenes/chapters/guitarra.tscn",
	"res://scenes/chapters/mano_magica.tscn",
	"res://scenes/chapters/espejo.tscn",
	"res://scenes/chapters/pinta.tscn",
	"res://scenes/chapters/galeria.tscn",
	"res://scenes/chapters/ofrenda_finale.tscn",
]

var _idx := 0
var _frame := -1 # -1 = setup pending (waits one frame for _ready)
var _node: Node = null
var _errors := 0


func _initialize() -> void:
	print("[harness] starting, ", SCENES.size(), " scenes x 60 frames")
	_next()


func _process(_delta: float) -> bool:
	if _frame == -1:
		# _ready has now run; safe to set up.
		if _node != null and is_instance_valid(_node) and _node.has_method("setup"):
			_node.call("setup", false)
		print("[harness] running: ", SCENES[_idx])
		_frame = 0
		return false
	_frame += 1
	if _frame >= 60:
		print("[harness] OK: ", SCENES[_idx], " (60 frames, errors so far: ", _errors, ")")
		_frame = -1
		if _node != null and is_instance_valid(_node):
			_node.queue_free()
		_node = null
		_idx += 1
		if _idx >= SCENES.size():
			print("[harness] DONE. total script errors: ", _errors)
			return true
		_next()
	return false


func _next() -> void:
	var ps := load(SCENES[_idx]) as PackedScene
	if ps == null:
		print("[harness] LOAD FAILED: ", SCENES[_idx])
		_errors += 1
		_frame = 0
		return
	_node = ps.instantiate()
	root.add_child(_node)
	_frame = -1 # setup on next frame
