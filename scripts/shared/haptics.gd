## haptics.gd - shared haptic feedback for MARIGOLD v0.2.0.
## Wraps OpenXR controller vibration via the action map's "haptic" output.
## Gracefully no-ops on hand-tracking-only or desktop (nothing to vibrate).
## Headless-safe: all XR access is guarded.
extends RefCounted
class_name MarigoldHaptics

## Preset strengths.
const SOFT := 0.25
const MEDIUM := 0.55
const STRONG := 0.9


## Pulse one or both controllers. amplitude 0..1, duration in seconds.
static func pulse(amplitude: float = MEDIUM, duration: float = 0.12, hand: int = -1) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null:
		return
	if not xr.has_method("trigger_haptic_pulse"):
		return
	# hand: -1 = both, 0 = left, 1 = right (mirror MarigoldHands constants).
	var trackers: Array[StringName] = []
	if hand < 0 or hand == 0:
		trackers.append(&"/user/hand/left")
	if hand < 0 or hand == 1:
		trackers.append(&"/user/hand/right")
	for tracker in trackers:
		xr.trigger_haptic_pulse(&"haptic", tracker, 1.0, clampf(amplitude, 0.0, 1.0), duration, 0.0)


## Convenience: quick UI click.
static func click() -> void:
	pulse(SOFT, 0.06)


## Convenience: satisfying grab/place thump.
static func thump() -> void:
	pulse(MEDIUM, 0.14)


## Convenience: celebration burst (two pulses).
static func fanfare() -> void:
	pulse(STRONG, 0.10)
	# Second pulse is scheduled by the caller via a timer if desired.
