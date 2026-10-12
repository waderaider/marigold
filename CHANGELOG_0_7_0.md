# MARIGOLD v0.7.0 changelog

Three wade-ordered ship-blockers + the specialist punch-list.

## Ship-blockers

### Pause menu = flat 2D grid of cards (wade's order)
- 900×1000 viewport, 3 columns, 11 cards (5 chapters + 6 experiences), no
  scroll. Mood color chips (tender = warm gold, wondrous = marigold orange,
  festive = pink, finale = deep red). 4px accent border on the current
  chapter; pressing it resumes.
- The grid IS the chapter picker: direct jump through the same load path as
  the launcher (autowiring, music, BugReporter session, telemetry).
- Big red SALIR AL INICIO (EXIT) kept, full-width × 104.
- Static placement contract: panel placed ONCE per open, 100% STATIC in
  world space. The 0.5s recenter tick is dead by design.
- `pause_open` telemetry now carries `via` (menu_hold/exit_button/esc).

### Settings menu, one tap from pause (wade's order)
- Ajustes page: input method (Auto/Controles/Manos — really gates the laser
  paths), dominant hand (teleport aim hand), tool-tips on/off (intro legend
  card), graphics quality Bajo/Medio/Alto/Ultra.
- Graphics measurably changes rendering (verified against the Godot 4.7.2
  binary): viewport scale 0.70/0.85/1.00/1.25, MSAA off/2x/4x/4x, FSR upscale
  on Low, particle density 0.5/0.75/1.0/1.25. No placebo knobs shipped
  (anisotropy setting, shadow-atlas API, and foveation singletons don't
  exist in this build; shadows are baked/disabled by design).
- Persisted in `user://marigold_settings.cfg`; applied at boot before first
  frame (MarigoldState autoload).

### Laser-pointer teleport in every chapter (wade's order)
- Aim the controller laser at the ground → marigold-petal ring landing
  marker → trigger teleports (roomscale world-shift + fade blink).
- Reads raw controller tracker poses directly (live even when the UI pointer
  path fails); hand-aim + pinch fallback; desktop camera-ray fallback.
- Audit result: v0.6.0 shipped pinch-activated teleport PADS in ch3/ch5
  only — fixed-destination, no laser, absent everywhere else. Pads stay; this
  is the universal locomotion layer (11/11 chapters + experiences).

## Telemetry (Headset Specialist)
- `menu_open` boot event (version + input inventory) with immediate flush —
  menu-only sessions now generate events (the zero-phone-home root cause).
- `BugReporter` ported from NEXUS: crash parity — session logs, clean-exit
  flags, pending-crash auto-send on menu boot.
- `_report_url` handling untouched (verified correct).

## Platform (AI/API Guru)
- `XR_META_headset_id` enabled: real headset model in every relay report,
  on-screen diagnostics, and the Test-connection ping.
- `environment_depth` enabled for passthrough folk scenes (matches NEXUS).

## Character animation (Design Director P0s)
- 150ms anticipation poses (crouch/lean-back + overshoot) before every
  personality action: ch3 guides, pet deer, ch5 leader hello move.
- Dead expressions wired: SORROW→WONDER arc on the Viva return, SHY on deer
  first-touch, SLEEPY on chapter-end fades.
- Banda pupils on (shared meshes, ~6 transform writes each), locked featured
  so the 13-rig crowd never hides them.

## Coco-lessons deepening (Tech-Demo)
- Flight: speed curve, velocity-tied wind audio/haptics, church-bell
  landmark toll, real arrival beat (settle, landing thump, music crossfade).
- Ofrenda finale: progressive candle lighting per memory object, bower
  calavera bows to the completed ofrenda, photo-prompt at the apex, music
  swell. Candle-grade lock (warm rim glows) on the 4 memory objects.
- Bandas: tempo-follow player strumming/dancing, call-and-response phrases,
  louder with dance energy.
- Mano Magica finale: 10s conducting of the ch5 band (replaces the 5s
  "¡Bravo!" card).
- Viva: dancers process through the room (weaving orbit), not a camera ring.

## Polish (P1/P2)
- Salt-dish glitter sparkle (7 emissive quads).
- Ch5 crowd: two-tone sashes, re-posed guitars on 2 dancers (height band
  already 0.85–1.18).
- Ch4 banners: unshaded + emissive 0.7 (no directional light added).

## PC VR — Windows build (wade's order, alongside the Quest APK)
- NEW deliverable: `Marigold-v0.7.0-windows.zip` on the same v0.7.0 release —
  64-bit Windows .exe (Forward+ renderer: SDFGI global illumination,
  screen-space reflections, volumetrics on Ultra) for wade's RTX 5070 Ti,
  streamed to Quest 3 via Virtual Desktop. See VIRTUAL_DESKTOP_SETUP.md.
- The Quest standalone APK remains the primary build; PC is additive.
- PC telemetry reports carry a distinct platform/device value so the digest
  splits Quest vs PC sessions.
- HONEST LIMITS: Godot 4 has NO DLSS and NO hardware ray tracing — the PC
  build is Forward+ software GI, not RTX. wade DECIDED 2026-10-12: a UE5
  one-chapter RTX demo (Ch1 Ofrenda night scene, 4-6 weeks) runs as a
  separate workstream, judged on its own merits before any full-port talk.
  Full 5-chapter port (6-9 months) NOT approved. Proposal:
  ~/workspace/design/UE5_RTX_PROPOSAL.md.

## Ship-pass fixes (QA gate, 2026-10-12)
- Universal 0.45s menu-button HOLD to open pause (was bare rising edge —
  QA §3.1.8 NO-SHIP); sub-threshold taps ignored; fill-ring feedback on the
  ❚❚ button; unpausing stays a rising edge; Esc stays instant.
- `via` renamed menu_button → menu_hold (QA §1.3 prescribed values).
- Pause cards 260→256px so the 3-column grid fits the 900px viewport
  exactly (was 910px min width).
- Export preset flips: body_tracking=1, render_model=1 (espejo + controller
  skins use both; was 0 since v0.6.2).

## Spatial 3D audio (wade's permanent rule — fast-follow, NOT this build)
- Audio Director's spatial pass is DONE and verified: Godot 4.7.2's built-in
  3D audio server is the honest path (Meta XR Audio is NOT exposed by the
  vendor plugin — verified via strings on both .so files). 18/18 headless
  checks green. New `SpatialAudio` helper (scripts/shared/spatial_audio.gd)
  in both projects: one line per sound, auto occlusion raycast + reverb
  zones (7 presets). Full spec: ~/workspace/design/SPATIAL_AUDIO_V0110.md.
- The per-title wiring (a `SpatialAudio` node per game/chapter + the spec's
  call sites) ships as a FAST-FOLLOW — it landed after this build's CI run
  started and spans 90+ titles. Always called "spatial 3D audio", never
  Dolby/Atmos/HRTF.
- QA ship-gate additions for the follow-up: eyes-closed direction check,
  wall-muffle occlusion check, reverb zone-transition check, no-2D-regression
  (UI/stingers/music stay 2D).

## Known limitations (next cycle)
- Ch1 mirror bust is NOT wired to body joints (espejo is; ch1 is the gap).
- Dialogue: 41/45 lines have triggers defined, only 4 wired.
- NO voice WAVs exist — captions (MarigoldCaptions) are the dialogue
  fallback and are verified working.
- Ch5 dance-assist setting exists but the scoring predicate is unmodified.
- Seated hip-baseline calibration not implemented.
- Environmental plaques ARE placed in all 11 chapters (builder gap closed).

## Notes
- NOT Quest-tested (standing rule). Headless: all scripts parse-clean,
  120-frame runs zero errors.
- New files: `scripts/shared/gfx.gd` (graphics/control preferences),
  `scripts/shared/bug_reporter.gd` (crash reporter port).
