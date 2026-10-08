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


## ---- Haptic vocabulary (v0.5.0) ----
## Consistent feel language across chapters: UI confirm, error deny,
## physics impact scaled by force, texture ticks for drag/sculpt/strum,
## sub-bass rumble for thunder/finale, heartbeat for tense moments.

## UI accept: short high blip.
static func confirm() -> void:
	pulse(0.35, 0.05)


## Error: double low buzz.
static func deny() -> void:
	pulse(0.5, 0.09)
	var t := Engine.get_main_loop()
	if t != null:
		await t.create_timer(0.09).timeout
		pulse(0.5, 0.09)


## Impact thump scaled by force 0..1 (catches, drum hits, collisions).
static func impact(force01: float) -> void:
	var f := clampf(force01, 0.0, 1.0)
	pulse(0.3 + 0.6 * f, 0.08 + 0.18 * f)


## Texture tick: 30 ms high tick for drag/paint/strum motion.
## Call per distance traveled, not per frame.
static func texture_tick() -> void:
	pulse(0.22, 0.03)


## Low-frequency rumble (thunder, finale, big moments).
static func sub_bass(duration: float = 0.8) -> void:
	pulse(0.95, duration)


## Two-thump heartbeat for tense/spooky beats.
static func heartbeat(times: int = 2) -> void:
	for i in maxi(1, times):
		pulse(0.7, 0.12)
		var t := Engine.get_main_loop()
		if t != null:
			await t.create_timer(0.28).timeout
			pulse(0.55, 0.10)
			await t.create_timer(0.5).timeout


## ---- Character-system haptics (v0.6.0) ----
## Event-driven only: blinks are SILENT (no haptics on blink - taste rule).

## Eye-contact lock: soft single blip on the hand nearest the character.
static func gaze_lock(hand: int = -1) -> void:
	pulse(0.3, 0.06, hand)


## Wink: texture tick routed to the nearest hand.
static func wink_tick(hand: int = -1) -> void:
	pulse(0.22, 0.03, hand)


## Pet bliss: low soft wave (a purr, not a rumble).
static func purr(duration: float = 0.8) -> void:
	pulse(0.25, duration)


## Crowd gasp: sub-bass lite under the bow moment.
static func gasp_rumble() -> void:
	pulse(0.6, 0.5)
