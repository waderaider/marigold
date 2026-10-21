# MARIGOLD v0.9.2 — "Every Input Works"

**Release date:** 2026-10-21 · **11 experiences** ·
NOT Quest-tested yet — wade's first run is the gate.
Full audit: INPUT_LAUNCHER_AUDIT_0_9_2.md

## FIXED: the headset could never phone home

- The Quest export preset had the INTERNET permission OFF — telemetry,
  crash reports, Check for Updates and the launcher's Test Connection
  could never work on the headset. Zero relay reports explained; on now.
- All relay addresses moved to the current worker
  (nexus-log-relay.wade-relay.workers.dev); the Godot project still
  pointed at the retired one in four places.

## FIXED: hand-tracking pinch in chapters

- Chapter pinch interactions and the teleport pinch fallback read two
  OpenXR actions that don't exist; the real pinch arrives as
  "select_button" and was never checked. Pinch now registers.
- Hand-aim teleport now aims where your hand points (real joint ray)
  instead of where your head looks.

## NEW: Xbox gamepad support (was: none at all)

- Launcher + pause: D-pad / left stick navigate, A selects, B backs
  out, Start opens pause — with a visible focus highlight and
  auto-scrolling list.
- In chapters: A = interact, RT = teleport confirm, works on a
  Bluetooth pad in-headset and while streaming via Virtual Desktop.
- PC mode: left stick moves, right stick looks, L3/LT sprint.

## Launcher diagnostics (read-it-back debugging)

- New second diag line: gamepad name, the last input the menu actually
  heard (source + seconds ago — Laser/Pinch/Gaze/Mouse/Gamepad/
  Keyboard), and relay health (host + last send OK/FAILED + time).

## Also

- Pause overlay's hand pointers now use the real XR origin (their rays
  were computed in raw tracking space).
- Keyboard navigation (arrows/Tab/Enter) works in launcher + pause on
  PC, alongside the mouse.
