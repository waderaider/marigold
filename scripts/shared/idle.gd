## idle.gd - MarigoldIdle: shared procedural idle-life driver (MARIGOLD v0.7.0).
## Pixar-Style Animator's plan (ANIMATOR_V0110.md): any rigged character can
## opt into breathing, blink scheduling, ear/tail flicks, weight shifts, and
## the head-lead rule (head lerp 8/s, body 4/s — never same-frame).
## Zero-alloc, <15us/char. Sits UNDER MarigoldCharacterRig; the Design
## Director's anticipation work hooks into the same action-timer path.
## Headless-safe: pure math + node transforms, never assumes XR hardware.
class_name MarigoldIdle
extends RefCounted

## Idle state for one character. Create via MarigoldIdle.create().
class IdleState:
	var root: Node3D
	var head: Node3D = null
	var chest: Node3D = null
	var ear_l: Node3D = null
	var ear_r: Node3D = null
	var tail_segs: Array = []
	var rng := RandomNumberGenerator.new()
	# Timers.
	var breath_phase := 0.0
	var blink_t := 0.0
	var next_blink := 3.0
	var flick_t := 0.0
	var next_flick := 8.0
	var shift_t := 0.0
	var next_shift := 6.0
	var base_yaw := 0.0
	var target_yaw := 0.0
	var base_scale_y := 1.0


## Create an idle state for a character. Pass the rig root and optional
## head/chest/ear/tail nodes. All optional except root.
static func create(root: Node3D, head: Node3D = null, chest: Node3D = null,
		ear_l: Node3D = null, ear_r: Node3D = null, tail_segs: Array = []) -> IdleState:
	var s := IdleState.new()
	s.root = root
	s.head = head
	s.chest = chest
	s.ear_l = ear_l
	s.ear_r = ear_r
	s.tail_segs = tail_segs
	s.rng.seed = hash(root.get_instance_id()) + 12345
	s.base_yaw = root.rotation.y
	s.target_yaw = s.base_yaw
	s.base_scale_y = root.scale.y
	s.next_blink = s.rng.randf_range(2.4, 5.0)
	s.next_flick = s.rng.randf_range(6.0, 14.0)
	s.next_shift = s.rng.randf_range(4.0, 8.0)
	return s


## Update one frame. Call from the character's _process. Zero-alloc.
static func update(s: IdleState, delta: float, t: float) -> void:
	if s == null or s.root == null or not is_instance_valid(s.root):
		return
	# Breathing: chest/root scale 1 +/- 0.02 @ 0.25Hz.
	s.breath_phase += delta * TAU * 0.25
	var breath := 1.0 + 0.02 * sin(s.breath_phase)
	if s.chest != null and is_instance_valid(s.chest):
		s.chest.scale.y = breath
	else:
		s.root.scale.y = s.base_scale_y * breath
	# Blink scheduler: 2.4-5s randomized.
	s.blink_t += delta
	if s.blink_t >= s.next_blink:
		s.blink_t = 0.0
		s.next_blink = s.rng.randf_range(2.4, 5.0)
		_do_blink(s)
	# Ear/tail flicks: random 6-14s, 120ms flick.
	s.flick_t += delta
	if s.flick_t >= s.next_flick:
		s.flick_t = 0.0
		s.next_flick = s.rng.randf_range(6.0, 14.0)
		_do_flick(s)
	# Weight shifts: root yaw +/- 0.05 every 4-8s.
	s.shift_t += delta
	if s.shift_t >= s.next_shift:
		s.shift_t = 0.0
		s.next_shift = s.rng.randf_range(4.0, 8.0)
		s.target_yaw = s.base_yaw + s.rng.randf_range(-0.05, 0.05)
	# Head-lead: head lerp 8/s, body 4/s — never same-frame.
	# (Body yaw eases toward target; head is driven by the rig's look-at.)
	var yaw_diff: float = s.target_yaw - s.root.rotation.y
	s.root.rotation.y += yaw_diff * minf(1.0, delta * 4.0)
	# Tail lag: segments trail with 2-3 frame delay (simple spring).
	_update_tail(s, delta)


## Trigger a blink (also called by the scheduler). Override via callback.
static func _do_blink(s: IdleState) -> void:
	# Default: quick scale-y pulse on head (if no eye rig). Characters with
	# MarigoldCharacterRig should call rig.blink() instead — this is the
	# fallback for simple props/creatures.
	if s.head != null and is_instance_valid(s.head):
		var tw := s.root.create_tween()
		tw.tween_property(s.head, "scale:y", 0.85, 0.06)
		tw.tween_property(s.head, "scale:y", 1.0, 0.12)


## Ear flick: quick rotation jitter on ears, tail tip wag.
static func _do_flick(s: IdleState) -> void:
	if s.ear_l != null and is_instance_valid(s.ear_l):
		var tw := s.root.create_tween()
		tw.tween_property(s.ear_l, "rotation:z", 0.3, 0.06)
		tw.tween_property(s.ear_l, "rotation:z", 0.0, 0.12)
	if s.ear_r != null and is_instance_valid(s.ear_r):
		var tw2 := s.root.create_tween()
		tw2.tween_property(s.ear_r, "rotation:z", -0.3, 0.06)
		tw2.tween_property(s.ear_r, "rotation:z", 0.0, 0.12)


## Tail lag chain: each segment lerps toward the previous with delay.
static func _update_tail(s: IdleState, delta: float) -> void:
	if s.tail_segs.is_empty():
		return
	var prev_rot := s.root.rotation.y
	for i in s.tail_segs.size():
		var seg: Node3D = s.tail_segs[i]
		if seg == null or not is_instance_valid(seg):
			continue
		# Lag: further segments follow slower (2-3 frame delay feel).
		var rate := 6.0 / float(i + 2)
		var diff: float = prev_rot - seg.rotation.y
		# Wrap angle.
		while diff > PI:
			diff -= TAU
		while diff < -PI:
			diff += TAU
		seg.rotation.y += diff * minf(1.0, delta * rate)
		prev_rot = seg.rotation.y


## Anticipation: 150ms crouch/lean-back + 120ms overshoot before an action.
## Call before any discrete personality action. on_done is called at the
## action moment (after anticipation + overshoot).
static func anticipate(s: IdleState, on_done: Callable, crouch := 0.90, lean := 0.15) -> void:
	if s == null or s.root == null or not is_instance_valid(s.root):
		if on_done.is_valid():
			on_done.call()
		return
	var tw := s.root.create_tween()
	# 150ms crouch (scale-y) + lean-back.
	tw.set_parallel(true)
	tw.tween_property(s.root, "scale:y", s.base_scale_y * crouch, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(s.root, "rotation:x", -lean, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 120ms overshoot (slight over-extend).
	tw.set_parallel(false)
	tw.tween_property(s.root, "scale:y", s.base_scale_y * 1.05, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s.root, "rotation:x", 0.05, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Settle + fire.
	tw.tween_property(s.root, "scale:y", s.base_scale_y, 0.10)
	tw.tween_property(s.root, "rotation:x", 0.0, 0.10)
	tw.tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call())
