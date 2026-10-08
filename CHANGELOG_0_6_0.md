# MARIGOLD v0.6.0 — "The Faces Version" (2026-10-08)

The faces version + the 8 "Coco VR lessons" findings (wade's direct order — all ship-blockers).

## Character system (the headline)
- **MarigoldCharacterRig** (`scripts/shared/character_rig.gd`): one procedural face system for every character — blink (2.2–5.5s cadence, 80ms), look-at (clamped, head-leading 2:1), 10 expression states, jaw driver, wink, ear flatten, head-roll echo. Shared static meshes, zero allocations in update(), <15µs/char, central `update_all(delta, ctx)` driver.
- **MarigoldVoice** autoload: dedicated "Voice" audio bus + spectrum analyzer sampled once per frame (200–4000 Hz log-compressed); jaw priority: envelope > 6–10 Hz syllable fallback > beat-synced singing.
- Every dancer, guide, musician, and the pet deer now blinks, tracks you, and moves its mouth. CI gates: 600-frame perf, face draw delta (ch3 +12, ch5 +2, budget +14), blink coverage, gaze sanity, shared-mesh audit — all green.

## The 8 findings (design patterns from Coco VR analysis — all original, never Disney/Pixar copies)
1. **Mirror moment (ch1):** skeleton self-avatar with spirit-glass shimmer reflection; 4 persisted face-paint variants.
2. **Diegetic camera:** folk-art camera prop, 12 collectible festival moments (320×180 PNGs), Galeria de Recuerdos photo wall.
3. **Themed teleport:** marigold-petal arc pads + spirit-bridge arrival bloom (ch3, ch5).
4. **Flight transitions:** 16s scripted glides over the candle-lit town replace fade-to-black loads (town = 4 MultiMeshes, camera never moves).
5. **Pinta Alebrijes:** paint an original moth-jaguar spirit animal; it comes alive (CharacterRig) and joins your persisted menagerie.
6. **Papel-picado UI:** procedural cut-paper generator (alpha-tested); menu + pause reskinned; 3D altar decor around the menu; diegetic-styled settings.
7. **Ambient bandas:** 3 skeleton street musicians in ch3 + 3 in ch5 (hard cap 6) — wave, play original phrases, beat-synced bobbing.
8. **Ofrenda progression:** collect foto (ch1), pan de muerto (ch2), marigold (ch3), guitar pick (guitarra); arrange on your ch5 shelf; **Tu Ofrenda** candle-lit finale room reveal.

## Demo moments
- "The Bow, finished" (ch1): pupil snap → 1.5s eye contact → wink → bow with jaw-open smile → gasp stinger + rumble + petals + photo.
- Espejo wink on energy threshold (stinger + haptic + sparkle); head-tilt echo on all dancers.
- Baile beat-drop lock: leader pupils lock on, CURIOUS tilt, jaw-grin hold, chime, finale moment.
- Guide greetings (JOY + talking + greet stinger); feed-joy jaw laugh; deer pet bliss (eyes close + purr) vs fast-pet startle (SURPRISED + ear flatten + deny); guitar lean-in (sound-hole warms, tips toward you) + perfect-strum fanfare.
- 4 new haptics (gaze_lock, wink_tick, purr, gasp_rumble), 4 new stingers (gasp, wink, greet, bow_drum), pooled eye-sparkle FX.

## Art punch-list (code-side)
- ch1: candle-grade lock + salt glitter + frame glass + emissive bread + 40-blossom arch; ch2: sunset grade lock; ch3: lantern paper-cup shades (1 MultiMesh), fountain ripple rings, matte fruit with calyx; ch4: dust motes in god-rays, backlit papel + 3-depth layering; ch5: marigold stage rim (1 MultiMesh), crowd variety (sombreros, height band).

## Tech fixes
- Restored missing Linux OpenXR vendor .so (local runs); fixed pre-existing `OpenXRMetaPassthroughColorLut.new()` API misuse — real binary uses `create_from_image()`.
- versionCode 6, version 0.6.0. APK: pending CI build.

**Not Quest-tested** — wade's headset pass is the gate, as always.
