# MARIGOLD v0.9.3 — "The Skills Pass"

Built by auditing the whole project against the newly installed gamedev
agent skills (the Godot 4.7 set + input-systems, game-feel, audio-design,
save-systems, dialogue-systems disciplines) and applying the fixes that
survived review. The full audit — 60 findings across four specialist
passes, with the deliberate deferrals and the standing-rule conflicts —
lives in SKILLS_AUDIT_0_9_3.md.

## INPUT (input-systems + godot-ui-control)
- Boot chooser: a gamepad could navigate it but never confirm (Godot's
  default ui_accept has no joypad binding) — pad A now picks via a
  synthetic ui_accept pair; the chooser opens with visible focus on the
  PC button (accent fill + cream border, was an invisible StyleBoxEmpty).
- Pause menu: pad B backs out of Settings/Controls pages to the main
  page instead of ejecting/resuming; page switches move focus to the
  page being shown; cycling a setting rebuilds the page but restores
  focus to the same row; the launcher's focus helper now treats a
  hidden focus owner as no focus.
- Teleport confirm is input-buffered (120 ms, per-source latches): a
  trigger / RT / pinch press just before the petal ring turns valid
  still fires. teleport_confirm + sprint stick deadzones 0.5 → 0.25.
- PC mode: right-stick look reads the first CONNECTED pad (was hardcoded
  to device 0), radial rescaled deadzone, and stick-walk speed is truly
  analog (was normalized to full speed on any tilt).
- Fixed foveated rendering is now set BEFORE OpenXR initializes (it was
  applied after, where it could be ignored).

## AUDIO (godot-audio + audio-design)
- default_bus_layout.tres ships: Master (limiter) ← Music (sidechain
  compressor keyed to Voice — dialogue ducks the music), SFX,
  Ambience, UI, Voice (gentle comp; the lip-sync analyzer appends after
  it). All players re-routed to their buses; voice.gd looks the Voice
  bus up by name instead of assuming an index.
- Settings: new Music / SFX / Voice volume rows (0/25/50/75/100%, real
  bus gains, persisted, applied at boot).
- Silent moments got sounds: teleport petal_rustle on both the laser
  and pad paths; candle_ignite on every newly-lit finale candle (+
  haptic); the real camera_shutter sample replaces the two-note chime
  stand-in and snap() owns its haptic; ui_select on pause open/resume
  and ui_back on page-back; launcher rows gained the missing haptic
  click beside their chime; MarigoldHaptics.fanfare() actually fires
  its second pulse, and pulse() falls back to gamepad rumble off-XR.
- Dialogue: one voice at a time (a new line stops the previous),
  streams cached per path. One-shots get ±6% pitch / ±1.5 dB variation;
  the beat clock is output-latency compensated.

## GRAPHICS (godot-3d-essentials + godot-shaders)
- Quest tiers are honest: Ultra → High on Quest, render scale ≤ 1.0,
  MSAA ≤ 2X, Quest default Medium. Shadows (sun only, 40 m), glow and
  foveation level now follow the tier via MarigoldGfx queries; the
  shared light rig's key light no longer casts a second shadow map.
- Sky shader: clouds compute only in the quarter-resolution pass
  (render_mode use_quarter_res_pass, alpha-composited), stars skipped
  in the cubemap pass, sky radiance 128. Weather particle counts scale
  with the quality tier's particle factor.

## RELIABILITY (save-systems + code-quality pass)
- Telemetry: a failed send re-queues its batch at the front of the
  queue (capped) instead of dropping it; a request that fails to start
  no longer wedges the flush flag. Header comments now tell the truth.
- Remote config (version.json report_url) is accepted only when its
  host is our own relay — in both the telemetry and crash reporters.
- Updater: current_version_code reads application/config/version_code
  (was hardcoded 1 → every check claimed an update), fail-closed at 0,
  and download_progress is actually emitted now.
- Settings: ConfigFile loads are cached (was a full disk reload per
  read, including per-frame readers), saves are atomic
  (tmp → .bak → rename) with a .bak fallback on load, schema version
  stamped. Progress + controller-anchor saves route through it too.
- CandleMelt: freed-candle pruning also runs on (re)discovery, so the
  registry can't leak at wax speed ×0. The vignette ease is a
  frame-rate-independent exponential damp. A stale chapter-complete
  race (await, then act on a chapter the player already left) is
  guarded.

## TESTS (godot-gdscript-headless-testing)
- probe_092 asserts (missing/eventless actions fail, exit 1);
  run_chapters_headless counts load/instantiate/missing-script
  failures into its exit code; both headers document the canonical
  invocation. test_nav_092 grew stages: boot-chooser focus + pad-A
  pick, specific-row focus assertion, pause open → settings focus →
  rebuild focus-restore → B back (still paused) → B resume.
- Headless results at ship time: import 0 script errors; 11/11
  chapters 0 errors; voice probe 54/54; melt test PASS; probe_092
  PASS; test_nav_092 PASS in both --pc and fresh-profile (chooser)
  modes, 0 script errors.

## PC 2D MENU (wade's order, 2026-10-21 — photo evidence)
- The PC launcher is now a TRUE full-screen 2D menu (root-viewport
  Control UI, papel-picado banner strip, game palette): clickable list
  of all 11 chapters/experiences with hover/press/focus states and
  full names, a FIXED description panel beside it (key art + name +
  wrapping text — the "Recuerdos" overlap/clipping from the photo is
  gone by construction: proper containers, siblings, never stacked),
  and footer buttons for Settings, Check for Updates, Diagnostics and
  Quit. Hovering or focusing a row previews it in the description
  panel; clicking launches. The VR launcher (2D panel in world) is
  unchanged.
- Settings and Diagnostics are pages of the same 2D menu, each with an
  on-screen Back button; Settings exposes the same real MarigoldGfx
  knobs as the pause menu (input, hand, tips, graphics, volumes,
  comfort, mouse, display, mode). The Diagnostics page carries the
  two-line input/relay readout + Test connection.
- Keyboard (arrows/Enter) and gamepad (D-pad/stick + A via the same
  synthetic ui_accept fix as the chooser, B backs out of sub-pages)
  work in the 2D menu; the list auto-scrolls to the focused row and
  also scrolls with the mouse wheel and on-screen ▲/▼ buttons.
- ONE-HANDED MOUSE EVERYWHERE (wade's follow-up order): boot chooser
  clickable (unchanged, re-verified); in chapters — hold Left-click
  walks forward toward the look direction (engages after a 0.35 s
  hold so plain clicks stay pure interact, and a physics veto stops
  it while the crosshair is over a usable object in reach); the
  crosshair brightens/expands over usable objects (hover highlight)
  and turns teal while hold-walking; Right-click teleport remains a
  complete locomotion path; a screen-space ❚❚ pause button (top
  right) opens pause by mouse alone; pause/settings are fully
  click-adjustable and Continuar / SALIR are clickable (verified by
  synthetic mouse events). The scheme is printed in the menu and the
  PC onboarding: "Mouse only: look · hold Left-click = walk ·
  Right-click = teleport · Left-click = use".
- Verified: tools/test_nav_092.gd now asserts the PC menu in the root
  viewport and adds a mouse-only stage chain (❚❚ click → pause opens;
  Continuar click → resumes; hold-LMB walks 1.6 m) — PASS in --pc and
  fresh-profile chooser runs; 11/11 chapters 0 script errors; voice
  probe 54/54. Screenshots: tools/shots/ (menu at 1920x1080 +
  1280x720, settings page, chapter with ❚❚ button, pause open).
- SHIPPING NOTE: this release carries the WINDOWS build only. The
  Quest APK for v0.9.3 follows separately — it is blocked on a local
  build-machine permission (Gradle loopback), NOT on a code issue.

## Deliberately NOT changed (details in SKILLS_AUDIT_0_9_3.md)
- 50 defined-but-uncalled dialogue lines: content wiring is an
  authoring pass, not a refactor — flagged for wade.
- Full spatial-emitter/zone wiring per chapter and the shared Theme /
  focus-neighbor graph: larger than this pass; focus is fully usable
  via the engine's neighbor search + the new page-focus moves.
- Input rebinding UI: rejected — the settings rule is "only real
  options", and rebinding is a feature, not a fix.
- No baked lighting (chapters build at runtime), no hit-stop/shake in
  VR (correctly absent — comfort), melt sim constants untouched.

NOT Quest-tested — wade's first run is the gate.
