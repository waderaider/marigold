# MARIGOLD v0.9.2 — Launcher & Input Audit

Audit date: 2026-10-21 · Scope: launcher, pause, locomotion, all input
methods (Quest 3 headset build + PC mode). Method: full code read of
main.gd / menu.gd / pause_menu.gd / direct_ui_input.gd / xr_ui_pointer.gd /
hands.gd / teleport.gd / pc_camera.gd / gfx.gd / telemetry + export
presets, verified headless (Godot 4.7.2): project import clean, main
scene boot clean, all 11 chapter scenes 0 script errors, gamepad-nav
end-to-end test PASS (tools/test_nav_092.gd). NOT tested on a real
headset — wade's Quest 3 run remains the gate.

## ROOT CAUSE #1 — zero telemetry / dead update checks (CONFIRMED in config)

`export_presets.cfg` (Quest preset) had **`permissions/internet=false`**.
The exported APK therefore has no INTERNET permission and every
HTTPRequest fails on-device: GameplayTelemetry POSTs, BugReporter POSTs,
the version.json config fetch, Check for Updates, and the launcher's
Test Connection ping. This single flag fully explains "zero relay
reports ever from the headset" across v0.6.1–v0.9.0 — the v0.6.2/v0.7.0
telemetry code fixes never had a chance to work. **Fixed: internet=true.**

Compounding it: the Godot project still pointed at the retired relay
(`nexus-log-relay.brio-00c.workers.dev`) in bug_reporter.gd,
gameplay_telemetry.gd, menu.gd (ping URL) and version.json — the UE5
project was migrated to `nexus-log-relay.wade-relay.workers.dev` on
2026-10-19/20, the Godot project was missed. **All four now use the new
worker.** NOTE: both reporters let the remote `version.json` (fetched
from GitHub main) override the compiled fallback, so the version.json
on `main` must carry the new report_url when this ships — it does in
this branch.

## ROOT CAUSE #2 — real hand pinch never registered outside the UI pointers

The launcher UI pinch path (XRUIPointer / DirectUIInput) measures raw
joint distance and is sound. But every CHAPTER-level pinch interaction
goes through `MarigoldHands.pinch_active()`, which checked the actions
`pinch_left` / `pinch_right` — **those actions do not exist** in
openxr_action_map.tres. The action map binds the real pinch
(`/input/pinch_ext/value`, both hands) to **`select_button`**, which
pinch_active never checked. Result on device: pinch interactions in
chapters and the teleport pinch fallback were dead; only controller
trigger (trigger_click) and mouse worked. **Fixed: pinch_active now
checks select_button** (both-hands aggregate, same imprecision the
existing trigger_click fallback already accepted).

## ROOT CAUSE #3 — hand-aim teleport aimed with your head

teleport.gd's hand fallback used `MarigoldHands.pointer_ray`, whose XR
path is a head-locked hand proxy: the petal ring followed your gaze,
not your hand. **Fixed: the fallback now uses the real joint ray
(`XRUIPointer.hand_ray`, same math as the UI lasers)**, falling back to
the old proxy ray only when no hand tracking data exists.

## GAP #4 — Xbox gamepad: zero support (now implemented)

There was not one joypad event or handler in the project. Now:

- **project.godot [input]** (format verified by probe — no comments in
  the section, `]` on its own line): `interact` += A; `teleport_confirm`
  += RT axis; `move_*` += left stick (deadzone 0.5→0.2); `sprint` +=
  L3 + LT; NEW `pause_menu` = Start/Menu button.
- **Launcher + pause navigation**: joypad/keyboard events are forwarded
  into the panel SubViewports (`push_input`) — a bare SubViewport never
  receives root-viewport input on its own, which is why a pad could not
  drive these menus at all. Godot's default ui_* actions cover D-pad +
  left stick nav, but the probe (tools/probe_092.gd) proved **the
  default ui_accept has NO joypad binding** — so A presses also push a
  synthetic ui_accept pair. B backs out of pause pages / resumes.
- **Visible focus**: every menu row/button, pause card and settings
  button had `focus = StyleBoxEmpty` — navigation was blind. All now
  get an accent-fill + cream-border focus box; the launcher list uses
  `ScrollContainer.follow_focus`; first nav event grabs the first row
  (launcher) / Continuar (pause).
- **PC rig**: right-stick look added to pc_camera.gd (left stick drives
  `Input.get_vector` movement automatically via the new bindings).
- **Teleport**: the XR confirm branch also accepts `teleport_confirm`,
  so RT confirms in-headset (Bluetooth pad) and while streaming via
  Virtual Desktop.
- **Pause forwarding is open-state only** — while a chapter runs, pad A
  means "interact" and is never routed at the floating exit button.

## Smaller fixes

- **Pause hand pointers had a null XR origin**: MarigoldPause readies
  before Main exists, so its hand pointers were setup() with
  `_xr_origin = null` and their joint rays ran in raw tracking space.
  attach() now hands every pointer the real origin.
- **Diagnostics upgrade** (launcher spec): the diag line is now two
  lines — line 1 unchanged (headset / controllers / hands / gaze /
  panel / boot), line 2 adds: connected gamepad name, **last input
  event heard (source + seconds ago)** — every click path now labels
  itself (Laser L/R, Pinch L/R, spare path, gaze dwell, mouse, gamepad,
  keyboard) — and **relay health** (`Relay <host> · last send OK/FAILED
  <time>`) from a new `GameplayTelemetry.relay_status_text()`.

## Verified already-correct (no change)

- Launcher shape per the 2026-10-09 spec: one scrollable 2D list, no
  tabs/hero/search; version badge, Check for Updates, Room setup kept.
- Pause panel is placed once per open and 100% static (v0.7.0
  contract); menu panel guard behaviour unchanged.
- Laser teleport is wired in all 11 chapters/experiences
  (laser_begin + laser_update in every chapter script).
- Settings (input method / dominant hand / tooltips / graphics
  Low–Ultra / comfort / PC rows) are real, ConfigFile-persisted, and
  applied at boot (MarigoldGfx) — audit found no placebo toggles.
- Menu button opens pause via 0.45 s hold (controllers), Esc (PC),
  floating II button, controller skins + legend present.
- Gaze dwell (1.2 s) fires only when no beam is drawn by either path.

## Ship-time checklist (v0.9.2)

1. Rebase/merge onto the v0.9.1 (voice) tree — this branch is based on
   v0.9.0 (0223f86) and deliberately does not touch assets/audio/ or
   dialogue scripts.
2. Bump: project.godot config/version=0.9.2, export_presets
   version/name=0.9.2 + version/code=13, version.json
   version/version_code/apk_url + changelog (KEEP report_url =
   wade-relay — see Root Cause #1).
3. Export APK + Windows, publish release v0.9.2, push source to main.
4. Retention: Godot line becomes 5 releases → delete v0.7.0 and move
   it to ARCHIVE.md's archived table (already documented there).
