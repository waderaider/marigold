# MARIGOLD v0.8.0 changelog

wade's order: a REAL PC mode — play the chapters on desktop with mouse +
keyboard, alongside VR mode. VR path untouched.

## Ship-blockers

### PC mode (desktop mouse + keyboard play)
- Boot chooser (Windows): "Play on PC" / "Play in VR — Quest via Virtual
  Desktop", screen-space 2D overlay before any camera/XR decision. Quest
  APK always boots straight to VR. Choice persists in
  `user://marigold_settings.cfg` (`display/mode`); `--pc` / `--vr` CLI
  flags override. Persisted VR + no headset → chooser returns with
  "No headset found" (never hangs, never boot-loops).
- LaunchMode enum in MarigoldState is the source of truth (PC/VR);
  `get_viewport().use_xr` is derived plumbing. XR initializes ONLY in VR
  mode (fixes SteamVR/VD claiming the runtime on wade's PC with no
  headset worn).
- Desktop FPS rig: captured-mouse look (yaw/pitch) + WASD/arrows at fixed
  eye height, Shift = sprint. Esc releases the mouse for menus; pause
  open/close releases/re-captures automatically. Glowing marigold
  dot+ring crosshair at screen center.
- Verb split: LMB = interact everywhere; RMB = teleport-confirm when the
  petal-ring marker is valid. No more click-a-candle-AND-teleport
  double-fire. VR trigger/pinch paths byte-for-byte unchanged.
- project.godot `[input]`: `interact` (LMB), `teleport_confirm` (RMB),
  `move_forward/back/left/right` (WASD + arrows), `sprint` (Shift).
- Input preference gains "Ratón · Mouse" (default stays Auto — existing
  installs unaffected).
- First-run PC onboarding: one screen — "WASD move · Mouse look · Click
  interact · Right-click teleport · Esc pause". Shown once, dismissable.
- PC defaults to Ultra graphics on first boot (RTX 5070 Ti); saved
  quality is never overridden.

### Menus reframed for PC (3D quads kept, no risky refactor)
- Menu panel scales up 1.35x and smooth-follows the desktop camera;
  VR-only rows stripped on desktop (Room setup, input diagnostics,
  Test connection); PC hint line replaces the laser hint.
- Espejo honest gating: row/card reads "needs a headset", dimmed — no
  fake body tracking. Switch Mode to VR in Settings (restart required).

### Chapter playability on mouse
- ch3 Plaza de los Alebrijes: click-on-guide orb spawning (the old
  1.25 m proximity gate could never fire from a 1.6 m cursor) + RMB-
  clickable teleport pads. XR paths unchanged.
- ch1 The Ofrenda: mirror face-paint swatches clickable via mouse ray
  (the old work-plane proximity test was unreachable by construction).
- mano_magica, pinta, ch5: desktop pointer is now the mouse-ray point
  (was camera-fixed) — pinch/grab/paint/sculpt stations work with the
  cursor. ch2/ch4/galeria/guitarra/ofrenda_finale already mouse-driven.
- Captions/dialogue mirror to a screen-space bottom-third strip in PC
  mode (world-anchored panel stays VR-only).

### Settings additions (all real, no placebos)
- Mouse sensitivity (0.5–2.0 steps), invert-Y, fullscreen (DisplayServer),
  resolution (native/720p/900p/1080p/1440p/4K), Mode switch PC/VR
  (persists; takes effect on restart — said in the UI).
- Gaze dwell gated to XR in menu + pause (latent desktop auto-click bug).

### Export
- Windows preset renamed "MARIGOLD (Windows PC VR)" → "MARIGOLD
  (Windows PC)" — one exe, runtime mode selection. CI unchanged
  otherwise.

## Known limitations (unchanged from v0.7.0)
- NOT Quest-tested, NOT PC-tested — wade runs both builds on his
  hardware. ch5 sway moves 4/5 need camera-yaw detection on PC (auto-
  passes, chapter completable). Espejo is VR-only.

## Files
- `Marigold-v0.8.0.apk` — Quest 3 standalone (always VR).
- `Marigold-v0.8.0-windows.zip` — one Windows exe; choose PC or VR at boot.
- See `PC_MODE_SETUP.md` for controls + troubleshooting.
