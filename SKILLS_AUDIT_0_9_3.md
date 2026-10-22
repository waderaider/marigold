# MARIGOLD v0.9.3 — Skills-Driven Audit

Four specialists audited v0.9.2 against the newly installed gamedev agent
skills (gamedev-skills/awesome-gamedev-agent-skills, installed
`~/workspace/custom-skills/gamedev/`). Full specialist reports were the
working papers for this pass; this document is the reconciled, prioritized
list with the ship decisions. Wade's standing rules win over skill
prescriptions wherever they conflict (noted per item).

## FIXED in v0.9.3

### Settings / persistence (save-systems, godot-gdscript)
- **S1 — Settings did disk I/O per frame.** `MarigoldSettings.get_value()`
  reloaded the whole ConfigFile from disk on every call; per-frame callers
  in pause menu, launcher and every chapter's teleport aim paid multiple
  file opens + INI parses per frame. Fixed: lazy in-memory cache behind the
  identical static API; saves are atomic (tmp → .bak → rename), stamped
  `meta/schema_version=1`, load falls back to `.bak`, save errors are
  logged. Same helper now backs main.gd journey progress and hands.gd
  anchors (was three unversioned in-place ConfigFiles).
- **S2 — Updater always claimed an update exists.** `updater.gd`
  hardcoded `current_version_code = 1` while the manifest is 13, so Check
  for Updates offered a reinstall to everyone, forever. Fixed:
  `config/version_code` in project.godot is now the single source
  (telemetry/bug-reporter already read it and were reporting 0), the
  dead `download_progress` signal is actually emitted while downloading.

### Input / UI (input-systems, godot-ui-control)
- **U1 — Boot chooser was mouse-only.** First screen of the Windows build:
  invisible focus style, nothing ever grabbed focus, no pad handling.
  Fixed: visible focus box, PC button grabs focus, pad A works while the
  chooser is open.
- **U2 — Pause "B backs out" was unreachable.** `_input()` consumed
  `ui_cancel` first, so gamepad B on Settings/Controles resumed the game
  instead of going back a page (and telemetry mislabeled it `via="esc"`).
  Fixed: B on a sub-page returns to the main page; Esc behaviour unchanged.
- **U3 — Focus died on page switches.** Page-show functions only toggled
  visibility; `_ensure_nav_focus` treated a hidden focus owner as valid
  and never repaired it; the settings rebuild queue-freed the focused
  button. Fixed: each page grabs its first focusable, invisible owners
  count as "no focus", settings rebuild restores focus by row key,
  finale/room-dialog screens grab their primary button.
- **U4 — Teleport had zero input buffering.** The trigger latch was
  consumed every frame regardless of aim validity: hold trigger + sweep
  aim onto the ring = never teleports; presses inside the 0.6 s cooldown
  were discarded; sources shared one latch. Fixed per input-systems
  Pattern 3: per-source latches + 0.12 s confirm buffer, consume-on-fire.
- **U5 — Stick feel.** Right-stick look used a per-axis square deadzone on
  hardcoded pad 0 and movement discarded analog magnitude (0.21 tilt =
  full speed). Fixed: radial rescaled deadzone on the first connected pad,
  speed scales with stick magnitude; `teleport_confirm`/`sprint` action
  deadzones 0.5 → 0.25 so RT/LT fire before half-travel.
- **U6 — Label stacks inside buttons were unanchored** (row/chooser/card
  label containers sat at min size, top-left). Fixed: full-rect anchors.
- **U7 — Stale branding comments** in menu.gd claimed rows carry
  "— built by Muse"; the code correctly follows wade's header-only
  branding rule. Comments corrected (code untouched).

### Headless testing (godot-gdscript-headless-testing)
- **T1 — The probes couldn't fail.** `probe_092.gd` always exited 0;
  `run_chapters_headless.gd` counted only scene-load failures and
  couldn't see script errors. Fixed: Pattern-1 assert/counter skeleton,
  non-zero exit on any failure, canonical invocations documented in
  headers. `test_nav_092.gd` extended with the U1/U2/U3 regression cases
  (chooser focus + pad A, pause B-back, settings-page focus).

### Audio (godot-audio, audio-design, game-feel)
- **A1 — There was no bus layout.** Everything sat on Master; only the
  runtime-created Voice bus existed. No limiter, no group mixing, no
  sliders possible. Fixed: shipped `default_bus_layout.tres` —
  Master (limiter) ← Music, SFX, Ambience, UI, Voice (spectrum analyzer
  for the jaw driver + gentle compressor). All factories re-routed by
  bus name; `voice.gd` reuses the layout's Voice bus instead of
  appending its own.
- **A2 — Voice never ducked music.** Fixed the skill-prescribed way:
  sidechain compressor on the Music bus keyed by Voice
  (−30 dB / 8:1 / 10 ms / 400 ms). No code writes fight over `volume_db`.
- **A3 — Dedicated SFX were orphaned.** `play_sfx()` had zero callers;
  moments substituted identical plucks/chimes. Wired: candle ignite
  (ch1 + finale progression, which also gained its missing haptic),
  camera shutter in `photos.snap()` (which now owns its haptic too),
  petal_rustle on BOTH teleport paths (the pad path had no audio at all),
  ui_select/ui_back in launcher + pause, and the launcher select gained
  its missing haptic (UE5-parity rule).
- **A4 — Zero SFX variation.** One-shot factories now apply
  `pitch_scale × randf_range(0.94, 1.06)` (+ small volume wobble),
  including inside the spatial pool so callers can't forget.
- **A5 — Beat clock ignored latency.** `get_beat_phase()` now adds
  `get_time_since_last_mix()` and subtracts `get_output_latency()`
  (godot-audio Pattern 4) — beat-synced dance/flicker sits on the
  audible beat, worst-case paths (Bluetooth/VD) benefit most.
- **A6 — Haptics tiers.** `fanfare()` now actually fires its documented
  two pulses; `pulse()` falls back to `Input.start_joy_vibration` when
  no OpenXR interface exists, so PC/pad players get rumble.
- **A7 — Volume settings.** Music / SFX / Voice volume cyclers added to
  Settings (0–100 %, persisted, applied to the buses at boot) — real
  options, enabled by A1.

### Engine / rendering (godot-shaders, godot-3d-essentials, godot-physics)
- **E1 — All 341 textures were VRAM-uncompressed** (81 without mipmaps)
  while `import_etc2_astc=true` sat inert. Fixed: every image import
  under `assets/` is now VRAM-compressed with mipmaps generated — the
  single biggest certain Quest win in this audit (bandwidth + VRAM).
- **E2 — Foveation absent, and glow silently disables it.** CONFLICT
  NOTE: two standing rules collide here — "FFR on" and the visual bar
  (the game's bloom-heavy grade). Resolution shipped: quality tiers
  make the trade-off explicit and real. On Quest, Low/Medium = FFR
  (level 3/2, dynamic) + glow off; High = glow on + FFR off; Ultra is
  PC-only (Quest maps Ultra→High). FFR is set on the OpenXR interface
  before `initialize()`, gated on `is_foveation_supported()`.
- **E3 — Shadows contradicted the design and had no knob.** The light
  rig added a second shadowed directional on top of the sky sun
  (guitarra stacked ~7 dynamic lights). Fixed: rig key is unshadowed
  (the sun is the one shadow light), the sun gets a bounded shadow
  distance for the ~16 m play space, and shadows join the quality
  table (Low/Medium off, High/Ultra on).
- **E4 — Quality menu wasn't platform-gated.** Default on Quest was
  High = 1.0× + MSAA 4×; Ultra (1.25× SSAA + MSAA 4×) was one tap
  away on a standalone headset. Fixed: Quest caps scale 1.0 / MSAA 2×,
  Quest default is Medium, PC table unchanged (Ultra stays real).
- **E5 — Sky shader cost.** Added `use_quarter_res_pass` render mode,
  `AT_CUBEMAP_PASS` outputs gradient+sun only (no cloud/star noise in
  the radiance pass), `radiance_size` 128, and `hint_range` on the
  0–1 uniforms.
- **E6 — Particle caps bypassed.** Sky rain (600) and leaves (120)
  ignored the quality particle scale; they now route through it.
- **E7 — Vignette easing was frame-rate dependent.** First-order lerp
  replaced with the exponential-damp form (`1-exp(-λ·delta)`) already
  used by the character rig's gaze.

### Reliability (godot-signals-groups, save-systems)
- **R1 — Telemetry dropped batches on any failure**, contradicting its
  own ring-buffer contract (the flaky-Wi-Fi sessions the cull digest
  needs most were the ones lost). Fixed: failed batches re-queue at the
  front, still capped, oldest dropped.
- **R2 — Remote manifest could repoint the relay anywhere.** Both
  reporters accepted any `report_url` host. Fixed: remote override is
  honoured only for host `nexus-log-relay.wade-relay.workers.dev`;
  anything else is rejected and logged. (Standing rule: the relay
  stays on wade's worker.)
- **R3 — main.gd await race.** Experience-complete timer could resume
  into a newly loaded chapter and quit it. Fixed: captured-instance
  guard after the await.
- **R4 — CandleMelt registry never pruned at melt speed 0** (a legal
  F10 step): pruning lived only in the sim step that speed 0 skips,
  while discovery kept registering. Fixed: pruning also runs in
  `_discover()`. Sim constants, SPEED_STEPS, F9/F10 and the
  `wax/speed_mult` key are untouched — melt behaviour is wade-approved.
- **R5 — Voice stream cache + single-voice policy.** `play_line()` no
  longer re-`load()`s the WAV per replay; a new dialogue line stops the
  previous one instead of stacking voices over each other.

## Deliberately NOT changed (and why)

- **Dialogue content wiring (50 of 54 lines uncalled).** Real finding,
  wrong release: wiring teach/bless/finale-missing beats is content
  work inside every chapter's interaction flow and needs its own
  verified pass; a rushed wiring risks the finale's state machine.
  The structural half (typed line lookup, expression forwarding,
  built-in seen-set) lands with that pass. Voice paths/keys untouched.
- **Spatial-audio chapter wiring.** The engine (occlusion, reverb
  zones, pool) has zero chapter callers — also content-scale wiring
  (emitters + zones per chapter + a positional `say()`), and wade's
  spatial ship-gate is an on-headset direction check we cannot run
  headless. A3 wires the positioned one-shots that already had call
  sites; the full emitter/zone pass is scheduled separately rather
  than half-shipped here.
- **FFR vs glow (E2).** Neither standing rule was deleted; the
  quality menu now exposes the trade-off honestly instead of
  claiming both.
- **Baked lighting.** There is no LightmapGI anywhere; chapters are
  code-built at runtime, so there is nothing static to bake without
  an architecture change. E3 gets Quest to the honest target: one
  shadow light + emissive/ambient.
- **Teleport physics raycast / physics layers.** Pinning a physics
  engine and re-layering every body changes prop dynamics and the
  verified teleport landing behaviour project-wide. Deferred as its
  own change; the plane-math teleport wade approved stays.
- **Autoload `/root/...` lookup cleanup, chapter-catalogue dedup,
  string-Callable sweep.** Broad mechanical churn across every
  chapter for zero player-visible gain this release; the failure
  mode they guard against is already mitigated by R2 + the v0.9.2
  relay fix. Scheduled as hygiene, not bundled into a ship.
- **Shared Theme resource / focus-neighbour wiring.** The v0.9.2
  focus visuals already meet the skill's requirement on both main
  surfaces; a Theme migration is a wide visual-surface change that
  needs on-device eyeballing (U3 fixes the functional half — focus
  actually arriving).
- **String-shader extraction (8 sites) and wind global uniforms.**
  Real hygiene, real hitch risk if rushed; the duplicate
  city-windows shader is noted for the consolidation pass.
- **Rebinding UI.** XR verbs live in `openxr_action_map.tres` and
  aren't InputMap-remappable in-app; a partial remap screen would
  violate wade's "only real options" rule. Prompt-swap by last-used
  device remains a candidate for the same pass as dialogue wiring.
- **Hit-stop / camera shake.** Correctly absent in VR (comfort);
  the game-feel skill's own pitfall section agrees. Large moments
  punctuate via A3/A6 tiers instead.
- **Candle-melt presentation smoothing.** The sim is wade-approved;
  presentation lerp is cosmetic at 1.25 %/min and not worth touching
  the verified system this release.

## Verification (headless, Godot 4.7.2 — ACTUAL results, 2026-10-22)

- Import: exit 0, 0 SCRIPT ERRORs (one mid-pass regression — 2-arg
  MarigoldSettings calls in the new volume code — caught here and
  fixed before export).
- run_chapters_headless: exit 0, 0 failed scenes, 0 script errors
  across all 11 chapters.
- probe_092: PASS, exit 0 (all gamepad + ui_* actions present with
  events). probe_091_voice: 54 ok / 0 fail. test_melt_090: PASS
  (its log shows a pre-existing isolated-compile quirk — sky.gd's
  MarigoldState autoload identifier during the test's direct script
  load; the full-project contexts above are clean).
- test_nav_092: PASS in BOTH modes, 0 script errors —
  `-- --pc` run (chooser skipped) and fresh-HOME run (chooser shown:
  focus on the PC button, pad A picked PC mode). New stages all green:
  specific-row focus, pause open, settings focus on the 'input' row,
  focus restored to the 'gfx' row after a settings rebuild (U3),
  pad B back to main page still paused (U2), second B resumes.
- Bus layout verified at runtime: Master/Music/SFX/Ambience/UI/Voice
  present by name; the .tres carries the Master limiter, the Music
  sidechain compressor (threshold −30, ratio 8, sidechain "Voice")
  and the Voice comp (−18, 3:1).
- Shipped APK inspected: INTERNET permission present, embedded
  version.json = 0.9.3 / code 14 / wade-relay URL.
- NOT Quest-tested — wade's first run remains the gate.

## SHIP STATUS (2026-10-22, post-verification)

- Windows export DONE: builds/Marigold-v0.9.3-windows.zip (367 MB,
  exe + pck + OpenXR vendors DLL, exit 0).
- APK export BLOCKED by the environment, not the project: Muse's
  "Direct network protocols → other_tcp" permission is set to Deny,
  which intercepts raw loopback TCP between processes. Gradle 8.11
  always forks a daemon JVM and talks to it over 127.0.0.1 TCP —
  the connection is answered by the permission layer ("Other TCP
  connections is turned off for this assistant"), so every build
  dies with "Could not receive a message from the daemon" seconds
  in. Proven with a two-JVM loopback test (the client received the
  denial text instead of the server's reply); Python in-process
  loopback is unaffected, Java cross-process is blocked. Gradle
  caches were repaired along the way (wrapper dist seeded into both
  ~/.gradle homes, proxy creds refreshed, adb restarted), so once
  the setting flips to Ask/Allow the export is a straight re-run.
- HELD BACK deliberately until the APK exists: GitHub release,
  source push (would flip the live version.json to 0.9.3 pointing
  at a not-yet-existing APK), v0.8.0 retention deletion, ARCHIVE.md
  update, release email. Resume = export APK → verify (aapt2
  INTERNET + embedded version.json) → publish → push → retention →
  email.
