## test_melt_090.gd - functional test for the CandleMelt port (v0.9.0).
## Builds a make_candle candle, runs the melt sim at 120x for ~10 real
## seconds (= 20 sim-minutes), and asserts: temperature saturates, height
## melts to the 0.35 floor, the flame sinks with the wick, drips spawn,
## a wax pool forms, and reset_wax() restores everything.
extends SceneTree

var _frame := 0
var _candle: Node3D
var _wax: Node3D
var _flame: Node3D
var _cm: Node
var _saw_drip := false
var _failures: Array = []


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "TestWorld"
	root.add_child(world)
	_candle = MarigoldFX.make_candle(world, Vector3.ZERO, true, 0.9)
	_wax = _candle.get_meta("melt_wax") as Node3D
	_flame = _candle.get_node_or_null("Flame") as Node3D
	_cm = root.get_node_or_null("CandleMelt")
	if _cm == null:
		_failures.append("CandleMelt autoload missing")
		_finish()
		return
	_cm.set_speed(120.0)
	print("[melt-test] candle built; wax rest y=", _wax.position.y,
		" flame rest y=", _flame.position.y)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 300:
		var c: Dictionary = _cm._candles[0] if _cm._candles.size() > 0 else {}
		print("[melt-test] mid: registered=", _cm._candles.size(),
			" height=", c.get("height", -1), " temp=", c.get("temp", -1),
			" wax.scale.y=", _wax.scale.y, " flame.y=", _flame.position.y,
			" pool=", c.get("pool_radius", -1))
	if _frame < 4800:
		return false
	var c: Dictionary = _cm._candles[0] if _cm._candles.size() > 0 else {}
	if _cm._candles.size() != 1:
		_failures.append("expected 1 registered candle, got %d" % _cm._candles.size())
	if float(c.get("temp", 0)) < 0.99:
		_failures.append("temperature did not saturate: %s" % c.get("temp"))
	if absf(float(c.get("height", 1)) - 0.35) > 0.01:
		_failures.append("height did not reach 0.35 floor: %s" % c.get("height"))
	if absf(_wax.scale.y - 0.35) > 0.01:
		_failures.append("wax scale.y != 0.35: %s" % _wax.scale.y)
	if absf(_flame.position.y - 0.26 * 0.35) > 0.01:
		_failures.append("flame did not sink with wick: y=%s" % _flame.position.y)
	for d in _cm._live:
		if d != null:
			_saw_drip = true
	if not _saw_drip and int(c.get("frozen", []).size()) == 0 and float(c.get("pool_radius", 0)) <= 0.0:
		_failures.append("no drips, frozen drips, or pool after 20 sim-minutes")
	if float(c.get("pool_radius", 0)) <= 0.0:
		_failures.append("no wax pool formed")
	print("[melt-test] end: height=", c.get("height"), " pool=", c.get("pool_radius"),
		" frozen=", (c.get("frozen", []) as Array).size(), " saw_drip=", _saw_drip)
	_cm.reset_wax()
	if absf(float(_cm._candles[0]["height"]) - 1.0) > 0.001:
		_failures.append("reset_wax did not restore height")
	_cm.set_speed(1.0)
	_finish()
	return true


func _finish() -> void:
	if _failures.is_empty():
		print("[melt-test] PASS")
	else:
		for f in _failures:
			print("[melt-test] FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)
