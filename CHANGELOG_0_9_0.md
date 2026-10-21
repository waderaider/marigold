# MARIGOLD v0.9.0 — "The UE5 Wave"

**Release date:** 2026-10-21 · **11 experiences** · NOT Quest-tested yet — wade's first run is the gate.

wade's order: everything the UE5 build got — the ContentStaging asset wave
AND the candle-melting system — comes to the Godot version. 234 files
staged; every hero model is wired into the game as a replacement, not
sitting in a folder.

## NEW: Living Wax — candle melt system (UE5 MarigoldCandleMelt port)
- New `CandleMelt` autoload (GDScript port of the UE5 world subsystem):
  lit candles heat up over ~25s, then melt at 1.25% of height per minute
  (never below 35%), wax scaling about its base while the flame kit and
  candle light sink with the wick. Unlit candles cool over ~45s.
- Wax drips run down the candle wall, slow exponentially as they cool,
  freeze partway (kept as frozen drips), and ~25% reach the foot to grow
  a wax pool — one shared MultiMesh per batch (live / frozen / pools),
  30 Hz fixed-step sim, same caps and rates as the UE5 original.
- Wired into: ch1's five ofrenda candles (lit state = flame kit),
  every `MarigoldFX.make_candle` candle (ch3, ch5, Guitarra), and the
  14-candle finale ring (lit state follows the memory-object progress).
- Controls (UE5 console equivalents): **F9** = `marigold.wax.reset`,
  **F10** = cycle `marigold.wax.speed` (0/1/5/20/60x, persisted in
  settings). Like the UE5 original, melt state is per-scene, not saved.
- Molten glow: candle light energy and flame glow rise with temperature.

## NEW: UE5 hero assets replace the placeholders
- **Hero candle** (161k-tri artist original) replaces the in-house
  candle set in ch1 — tall/mid/short scales, and the stale flame-anchor
  measurements were corrected (flames used to float ~10cm over the wick).
- **4 animated mariachi** (rigged, baked Play/Sway clips): the full
  quartet holds the stage in El Gran Baile; trumpet + maracas join the
  plaza band in ch3.
- **Ofrenda heroes**: pan de muerto, sugar skulls (hero + mini), carved
  frame, marigold garland, mole bowl + tamales, salt dish, water glass,
  copal sahumador — all replace their procedural/in-house equivalents.
- **Hero alebrijes** (venado, winged jaguar, serpent) stand as plaza
  monuments on stone plinths in ch3 — they are single-piece meshes, so
  the interactive guides keep their articulated models (the character
  rig needs the parts). 10 hunt-wave spirit alebrijes + butterflies
  join ch3, Espejo and the Galería.
- **Chandeliers + tin lanterns**: artist chandelier over the ch1 altar
  and in the finale room, hojalata lanterns flanking both altars,
  a Poly Pizza chandelier in the Galería.
- **Shrine nicho hero** mounted over the finale altar; a second shrine,
  bell, rug, lamps and dishware dress ch1; market pots, banners, skyline
  towers, instruments and hats dress ch3/ch5/Guitarra/ch2/ch4 — 36 Poly
  Pizza models placed. A skeleton greeter waves at the bridge's far arch.
- **Painted ancestor portraits** (Rosa, Tomás, Luz) now fill the ch1
  photo frames, under the same ignite-glow shader.

## Textures (PBR sets applied to real surfaces)
- Papel-picado atlas → all `banner_material` banners (menu, pause,
  finale arch, ch4 arch banners) with per-seed sheet regions.
- ambientCG: Tiles144 → finale floor, Plaster001 → finale wall,
  PavingStones046 → flight town ground.
- In-house: wax PBR → procedural + ring candles; talavera strips →
  ofrenda tier fronts; serape runner → ch4 corridor + Guitarra table;
  city windows → flight house facades (emissive); crowd billboards →
  ch5 plaza; petal texture → petal particles; saltillo floor → ch3
  plaza disc; woven textile → market canopies; marigold flower PBR →
  every marigold field blossom.

## Audio: everything re-rendered at 48kHz
- All 38 music/ambience/SFX WAVs replaced with the 48kHz masters from
  the UE5 wave (the old set was 22.05kHz) — same names, same wiring,
  double the fidelity.
- The 55 UE5 voice lines are staged under `assets/audio/voice/ue5/`
  but NOT wired: they belong to the UE5 script's cast (Chon, Lalo,
  Mar), which does not map 1:1 onto this game's 45-line script —
  wiring them would put the wrong words in the wrong mouths.

## Verification
- Headless: all 11 chapter scenes load + run 60 frames, 0 script errors.
- CandleMelt functional test PASS (tools/test_melt_090.gd): temperature
  saturates, height melts to the 0.35 floor, flame sinks with the wick,
  drips freeze + pool caps at 2x radius, reset restores.
- Mariachi Play/Sway animations verified in-engine on all 4 rigs.

## Known limitations
- NOT Quest-tested / NOT PC-tested — first run is the gate, as always.
- ~120 new dressing draw calls across chapters (mid/filler tier models);
  hero models are reserved for hero slots. Perf harness unchanged.
