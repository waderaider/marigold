# REPORT_BLENDER_rework — v0.9 Blender pass over existing heroes (2026-10-22)

Offline Blender work only. **No UE import or compile was done** — everything below is verified in Blender/Cycles renders and by parsing the exported glbs, not in-engine.

## TL;DR
| priority | asset(s) | result |
|---|---|---|
| 1 | `w3_flora_jacaranda.glb` | **Full rebuild in Blender.** Real recursive branch skeleton (283 tapered, UV'd limbs + root flare + surface roots), lush umbrella crown of ~1,500 bloom clumps (alpha-masked crossed cards using a 2K atlas baked in Blender from real 3D trumpet-flower panicles) + ~2,800 low-poly 3D trumpets on the crown shell, fallen-blossom carpet, re-strung warm lights. **199,054 → 141,396 tris**, bbox within 0.6 %. |
| 1 | `w3_stucco_wall_*` (Textures/artist-made) | **Replaced** with a calm hand-trowelled lime plaster, 2048² seamless: color / normal (GL) / normaldx / roughness / ao, same filenames. No peeling, chips, crack networks or rain streaks; low-contrast limewash cloudiness, soft trowel undulation, fine sand grain, rare hairline crazing. |
| 2–3 | other w3_* and older artist-made heroes | Automated Blender refinement pass (weld, angle-limited bevel where the budget allows, weighted normals, curvature wear + crevice grime + ground-contact dirt baked into COLOR_0, ≤200k tri budget via decimate). Textures/materials untouched. Per-asset table below. |
| — | `skeleton_mariachi_*` (4) | **Not touched** — skinned + animated rigs; a Blender glTF round-trip risks the skin/anim data and they're in budget (≈57–59k). |

Previews: `previews/blender/<stem>_before_after.png` (same camera per pair, framed on the BEFORE bbox; studio key + low warm "candle" point + warm rim), `previews/blender/w3_stucco_wall_before_after.png`, contact sheet `previews/blender/contact_rework.png`.
Backups of every original: `content/content-staging/_backup_pre_blender/Models/artist-made/` (49 glbs) and `.../_backup_pre_blender/Textures/artist-made/w3_stucco_wall_*` (5 pngs).


## 1. w3_flora_jacaranda — full rebuild (priority 1)
- **Why:** the v0.8 crown still read as thin and gappy (two blue-ish blobs, bare limbs, sparse litter).
- **Branches:** recursive skeleton built in Blender (`work/bl/jac_build.py`): trunk (r 0.17 m, root flare) → 3 leaders → 5 more levels down to 1 cm twigs, 283 limbs plus 6 surface roots. Leaders rise and spread, outer twigs level out, so you get the umbrella shape. Every limb is a tapered tube with parallel-transport frames and a real UV (u wraps the circumference at about a 0.32 m texel repeat, v runs along the length), plus tip caps. Bark is a new **1K seamless** set with vertical fissures, small plates and faint lichen: color + GL normal + ORM.
- **Crown:** about 1,500 "bloom clumps", each 3 crossed cards plus 1 outward-facing card. They are hung on the level-4/5 twig tips and mid-twigs, plus a top-shell fill that only goes where a twig is within 0.45 m (so nothing floats). Cards use a **2K 2×2 atlas baked in Blender** (`jac_atlas.py`) from real 3D panicles: about 1,000 five-lobed trumpet flowers per cell, dark violet tube → lavender mouth, pale throat stripe, 6 tint variants. The bake has albedo (alpha mask, colour dilated into empty texels), a camera-space→tangent **GL normal**, and AO packed into ORM. Custom normals are bent 55% toward the crown ellipsoid so the crown shades like soft cushions. Vertex colour adds depth darkening (lighter, warmer tops; darker interior) and per-clump hue drift (rose ↔ blue-violet).
- **3D flowers:** about 2,800 low-poly trumpets on the outer crown shell give a true silhouette up close, plus about 700 fallen trumpets on the ground.
- **Ground litter:** 1,100 small alpha cards in a carpet out to r = 2.9 m (this pins the original bbox).
- **Lights:** a warm emissive string-light helix on the trunk and the 3 leaders, plus draped strands between level-2 limbs. They use the same `M_StringBulbGlow` (emissive ×14) and `M_LightWire` as before.
- **Materials (5):** `M_JacarandaBark`, `M_JacarandaBloom` (**alphaMode MASK**, cutoff 0.5, double-sided, COLOR_0), `M_JacarandaFlower` (vertex colour, double-sided), `M_LightWire`, `M_StringBulbGlow`. ORM is written as occlusion + metallicRoughness (post-export JSON patch, `glb_patch.py`). Single mesh node, origin at the trunk base, +Y up, metres.
- **Numbers:** 199,054 → **141,396 tris**. bbox (−2.92,−0.03,−2.92)→(2.92,4.80,2.95) became (−2.95,−0.06,−2.91)→(2.92,4.80,2.92), worst axis Δ 0.57% of extent. The glb is 20.4 MB (three 2K atlas PNGs + 1K bark), up from about 14 MB.
- **Changed for UE:** the canopy is now **alpha-masked cards**. In UE 5.7 that means a masked material (Nanite masked works but costs more; foliage LOD/WPO not set up). The leaf material `M_JacarandaLeaf` is gone (jacarandas bloom almost leafless) and `M_JacarandaBloom` is new. If the builder ever looked materials up by those names it needs a look; I found no name lookups (it only spawns `w3_flora_jacaranda` at (−330,1720) / (330,1720)).

## 2. w3_stucco_wall — calm lime plaster (priority 1)
- New generator: `work/bl/stucco_calm.py` (numpy, all FFT-periodic, so it tiles exactly; the seam diff equals the interior diff). It writes the **same 5 filenames** into `Textures/artist-made/`: `_color` (sRGB), `_normal` (GL), `_normaldx` (verified as the exact G-inverse of GL), `_roughness`, `_ao`, all 2048².
- Look: a warm ochre-rose limewash (mean kept close to the old set so the material tint still matches the scene), albedo std about 3% (was much higher), soft broad trowel undulation with slightly horizontal sweeps, fine sand grain and sparse pores. Hairline crazing appears on only about 5% of the tile. Roughness is 0.85–0.89 matte, slightly burnished on trowel highs. AO is very gentle.
- Removed: peeling paint, the turquoise under-coat, the adobe reveal, chips, vertical rain streaks, crack networks.
- Every PNG round-trip was pixel-checked after saving. The builder already maps `w3_stucco_wall_color / _normaldx / _roughness` (MarigoldMaterialBuilder.cpp ~L840), so nothing in code needs to change. The UE textures still have to be re-imported, which I did not do.
- Preview: `previews/blender/w3_stucco_wall_before_after.png` (4 × 2.6 m wall, 2.5 m repeat, warm raking light + cool fill, map thumbnails underneath).

## 3. Batch refinement pass (priorities 2–3) — what it does, and what it does NOT do
Script: `work/bl/rework.py` (driver `batch.sh`). For each glb, starting from the backup:
1. **hard** assets (architecture, furniture, ceramics, metal): weld duplicate verts (0.2 mm) → **bevel** 1 segment, angle-limited at 50°, width ≈ 0.35% of the asset diagonal (1.5–12 mm), harden normals, clamp overlap. It only runs if the result stays ≤ 200k and ≤ 3× the source tris; otherwise it is skipped and the table says so. Then shade-smooth-by-angle 35° plus a **Weighted Normal** modifier (face area, keep sharp).
2. **organic / light** assets: geometry is left alone, apart from the budget step.
3. **Tri budget:** anything still over 200k gets a collapse **decimate** to about 194k, delimited by UV seams and materials.
4. **Wear (all assets):** a relative-curvature pass. Convex edges are lifted slightly (worn highlight), concave crevices are darkened up to 25% (grime), and there is a ground-contact dirt band at the bottom 4–15 cm. This is multiplied into **COLOR_0**; if the asset had none, a white base is created first.
5. Exported uncompressed glb (no Draco/meshopt), same materials and textures (pixel-identical round-trip verified), same single node, same origin/scale.

**Not done in the batch:** no re-unwrap, no new baked 2K/1K PBR texture sets, no LOD1/LOD2 nodes. There wasn't time to do those properly on about 45 assets with 2 CPUs. A glb with extra overlapping _LOD nodes would also double-render if the builder imports the whole file as one mesh. Existing textures are kept as-is (mostly 256–512 px, procedural UVs). This is the main gap against the checklist.


## 4. Per-asset results (all installed under their original filenames in `content/content-staging/Models/artist-made/`)
"bbox Δ" is the worst min/max shift on any axis, as a % of that axis' extent (limit ±5%). Every asset passed. Texture sizes are the images embedded after the pass. For everything except the jacaranda they are the **original** images, pixel-identical after the round-trip (checked by decoding both glbs). Materials, alpha modes, double-sided flags, emissive + `KHR_materials_emissive_strength`, occlusion slots, node name and transforms were all compared before/after: unchanged apart from float-precision noise.

| asset | pass | tris before | tris after | textures (after) | bbox Δ (worst axis, % of extent) | installed | what changed |
|---|---|---|---|---|---|---|---|
| `w3_flora_jacaranda` | rebuild | 199,054 | 141,396 | 1024x1024, 2048x2048 | 0.57% | yes | full Blender rebuild (see §1) |
| `w3_altar_archmarigold` | organic | 449,344 | 193,999 | 512x512 | 0.04% | yes | decimated 449344 -> 193999 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_crossmarigold` | organic | 302,976 | 194,000 | 512x512 | 0.09% | yes | decimated 302976 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_marigoldpile` | organic | 337,852 | 194,000 | 512x512 | 0.18% | yes | decimated 337852 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_papelstrip_a` | light | 36,072 | 36,072 | 1024x1024, 1x1, 256x256, 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_papelstrip_b` | light | 36,072 | 36,072 | 1024x1024, 1x1, 256x256, 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_papelstrip_c` | light | 36,072 | 36,072 | 1024x1024, 1x1, 256x256, 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_petalpath` | organic | 151,824 | 151,824 | 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `w3_altar_tiers` | hard | 299,212 | 194,000 | 1024x1024, 1600x1141, 512x512 | 0.00% | yes | weld: 38079 verts dup verts; bevel skipped (would give 313390 tris); decimated 299204 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_casa_a` | hard | 55,508 | 118,917 | 1024x1024, 2048x2048, 512x512 | 0.00% | yes | weld: 9192 verts dup verts; bevel 12.0 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_casa_b` | hard | 70,242 | 161,342 | 1024x1024, 2048x2048, 512x512 | 0.00% | yes | weld: 8453 verts dup verts; bevel 12.0 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_casa_c` | hard | 55,528 | 125,308 | 1024x1024, 2048x2048, 512x512 | 0.00% | yes | weld: 11552 verts dup verts; bevel 12.0 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_cementerio_set` | hard | 93,716 | 183,751 | 1024x1024, 512x512 | 0.00% | yes | weld: 15827 verts dup verts; bevel 12.0 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_iglesia` | hard | 154,120 | 147,872 | 1024x1024, 2048x2048, 512x512 | 0.00% | yes | weld: 34895 verts dup verts; bevel skipped (would give 208406 tris); COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_kiosko` | hard | 89,860 | 155,038 | 1024x1024, 2048x2048, 512x512 | 0.06% | yes | weld: 18354 verts dup verts; bevel 12.0 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_bg_mausoleo` | hard | 33,658 | 59,202 | 2048x2048, 512x512 | 0.00% | yes | weld: 6716 verts dup verts; bevel 12.0 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_arch_post` | hard | 380,472 | 193,999 | 1024x1024, 512x512 | 0.00% | yes | weld: 8649 verts dup verts; bevel skipped (would give 496065 tris); decimated 371113 -> 193999 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_bench` | hard | 60,012 | 61,116 | 1024x1024, 512x512 | 0.10% | yes | weld: 4772 verts dup verts; bevel 6.9 mm x1 seg @50deg, harden normals; curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_cantera_column` | hard | 241,760 | 194,000 | 1024x1024 | 0.00% | yes | weld: 6473 verts dup verts; bevel skipped (would give 270077 tris); decimated 238402 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_clay_olla` | hard | 63,976 | 65,938 | 1024x1024 | 0.03% | yes | weld: 628 verts dup verts; bevel 2.8 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_gatepost` | hard | 363,056 | 193,999 | 1024x1024, 512x512 | 0.00% | yes | weld: 7515 verts dup verts; bevel skipped (would give 396918 tris); decimated 350150 -> 193999 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_serape_rug` | organic | 129,194 | 129,194 | 2048x1024, 256x256 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_table` | hard | 128,392 | 129,262 | 1024x1024, 1024x512, 128x128 | 0.00% | yes | weld: 2198 verts dup verts; bevel 6.7 mm x1 seg @50deg, harden normals; curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_talavera_round` | hard | 96,800 | 99,845 | 1024x1024, 512x512 | 0.00% | yes | weld: 1059 verts dup verts; bevel 3.2 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_court_talavera_tall` | hard | 300,976 | 193,999 | 1024x1024, 256x256, 512x512 | 0.00% | yes | weld: 3958 verts dup verts; bevel skipped (would give 378609 tris); decimated 298165 -> 193999 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_flora_bougainvillea_pot` | organic | 332,668 | 193,999 | 1024x1024, 512x512 | 0.00% | yes | decimated 332668 -> 193999 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_flora_cempasuchil_bed` | organic | 558,144 | 194,000 | 1024x1024, 512x512 | 0.52% | yes | decimated 558144 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_flora_cempasuchil_bush` | organic | 390,612 | 194,000 | 512x512 | 0.56% | yes | decimated 390612 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_flora_cresta` | organic | 93,216 | 93,216 | 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `w3_flora_farol_post` | hard | 47,712 | 56,893 | 512x512 | 0.00% | yes | weld: 4248 verts dup verts; bevel 11.5 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `w3_flora_festoon` | light | 34,752 | 34,752 | 256x256 | 0.00% | yes | COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `alebrije_jaguar_alado_hero` | organic | 297,252 | 194,000 | 1024x1024, 2048x2048, 512x512 | 1.31% | yes | decimated 297252 -> 194000 (collapse, UV/material delimit); COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `alebrije_serpiente_hero` | organic | 223,376 | 194,000 | 1024x1024, 2048x2048, 512x512 | 1.37% | yes | decimated 223376 -> 194000 (collapse, UV/material delimit); COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `alebrije_venado_hero` | organic | 273,592 | 194,000 | 1024x1024, 2048x2048, 512x512 | 0.49% | yes | decimated 273592 -> 194000 (collapse, UV/material delimit); COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `bowl_mole_hero` | hard | 128,576 | 137,668 | 1024x1024, 512x512 | 0.00% | yes | weld: 11403 verts dup verts; bevel 1.5 mm x1 seg @50deg, harden normals; COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `chandelier_hero` | hard | 329,728 | 194,000 | 1024x1024, 512x512 | 0.00% | yes | weld: 14936 verts dup verts; bevel skipped (would give 350935 tris); decimated 320750 -> 194000 (collapse, UV/material delimit); COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `flower_petal_quaternius` | light | 1,388 | 1,388 | none | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `guitar` | hard | 221,010 | 193,999 | 1024x1024 | 0.00% | yes | weld: 5804 verts dup verts; bevel skipped (would give 232407 tris); decimated 219263 -> 193999 (collapse, UV/material delimit); COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |
| `sahumador` | hard | 348,240 | 194,000 | 1024x1024, 1x1, 2048x1024, 512x512 | 0.00% | yes | weld: 49891 verts dup verts; bevel skipped (would give 384039 tris); decimated 311588 -> 194000 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `salt_dish` | hard | 103,140 | 100,060 | 1024x1024, 512x512 | 0.00% | yes | weld: 153864 verts dup verts; bevel skipped (would give 265624 tris); curvature wear/grime + contact dirt in COLOR_0 |
| `sugar_skull_hero` | organic | 267,392 | 193,999 | 1024x1024, 512x512 | 0.00% | yes | decimated 267392 -> 193999 (collapse, UV/material delimit); curvature wear/grime + contact dirt in COLOR_0 |
| `sugar_skull_mini` | organic | 124,774 | 124,774 | 256x256, 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `tamal_a` | organic | 74,568 | 74,568 | 1024x1024 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `tamal_b` | organic | 138,136 | 138,136 | 1024x1024 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `tamal_c` | organic | 96,813 | 96,813 | 1024x1024, 512x512 | 0.00% | yes | curvature wear/grime + contact dirt in COLOR_0 |
| `water_glass` | light | 71,232 | 71,232 | 1024x1024 | 0.00% | yes | COLOR_0 created (white base); curvature wear/grime + contact dirt in COLOR_0 |


Not processed: `skeleton_mariachi_guitar/maracas/trumpet/violin` (skinned + 2 animations each, left byte-identical, backups exist anyway). w4_/w5_ were skipped as instructed. No tja_ file was touched.

## 5. Unverified / caveats (read before integrating)
1. **No UE import.** Nanite build, masked-material cost, Interchange's handling of COLOR_0 and the jacaranda's custom normals are all untested in-engine.
2. **The wear lives in COLOR_0.** glTF says COLOR_0 multiplies base colour, and the earlier artist-made glbs already relied on vertex colour. 18 assets that had **no** COLOR_0 now get one (white × wear): the casas, iglesia, kiosko, mausoleo, cementerio and others with "COLOR_0 created" in the table. If the UE material ignores vertex colour, the wear is simply invisible. It will not break anything. If a material *does* multiply VC, these assets get slightly darker in crevices, which is the intent.
3. **Decimation** (18 assets went from 221k–558k down to about 194k for the hero ≤200k budget) looks clean in the 448 px previews (see the contact sheet). **Extreme close-ups are unverified**: thin petals and filigree are where collapse decimation degrades first. The originals are in `_backup_pre_blender/` if any hero needs its full density back for Nanite.
4. **Bevels** ran only where the result fit the budget: kiosko, mausoleo, casa_a/b/c, cementerio, bench, table, talavera_round, clay_olla, farol_post, bowl. They were skipped (too many tris after weld) on tiers, iglesia, arch_post, column, gatepost, talavera_tall, chandelier, sahumador, guitar, salt_dish.
5. **Mixed Blender versions:** the system Blender 4.3.2 disappeared mid-run when the sandbox restarted (the `/usr` install wasn't persistent). The jacaranda, the stucco renders and 6 batch assets (tiers, iglesia, kiosko, mausoleo, arch_post, cantera_column) were exported with **4.3.2**. Everything else was exported with the portable **Blender 5.1.0** at `/workspace/tools/blender/current`. Both exporters wrote equivalent, validated glbs. The old headless 4.3 MCP bridge on :9876 is gone; the 5.1 toolchain has its own (`/workspace/tools/blender/bmcp-start`).
6. **Jacaranda:** canopy cards rely on alpha MASK. Previews are Cycles with 96 transparent bounces; in UE, check overdraw/perf with 2 trees at the courtyard entrance. The bulbs are emissive only, so add 1–3 warm point lights if you want real spill. The glb grew to 20.4 MB.
7. **Stucco:** only the staged PNGs changed. The UE assets (`w3_stucco_wall_*` in Content) need a re-import for the scene to show it.
8. Checklist items **not met in this pass**: re-unwrap + baked 2K/1K PBR per asset (only the jacaranda and stucco got new baked texture sets), LOD1/LOD2 nodes, and DX/GL normal choice for the embedded batch normals (unchanged from the source: GL).

## 6. Files
- Report: `marigold/REPORT_BLENDER_rework.md` (this file)
- Previews: `marigold/previews/blender/*_before_after.png` (46 meshes + `w3_stucco_wall_before_after.png`), `marigold/previews/blender/contact_rework.png`
- Changed assets: 46 glbs in `content/content-staging/Models/artist-made/`, 5 PNGs `content/content-staging/Textures/artist-made/w3_stucco_wall_{color,normal,normaldx,roughness,ao}.png`
- Backups: `content/content-staging/_backup_pre_blender/` (Models/artist-made: 49 glbs, including the untouched skeletons; Textures/artist-made: 5 stucco PNGs)
- Scripts (re-runnable): `marigold/work/bl/` — `jac_atlas.py` (bloom atlas bake), `atlas_final.py`, `bark_tex.py`, `jac_build.py` (tree), `stucco_calm.py`, `stucco_ba.py`, `rework.py` + `batch.sh` (batch pass), `before_after.py` + `compose.py` (previews), `contact.py`, `validate.py` (`--install` copies passing glbs), `glb_patch.py` (MASK/ORM JSON patch), `blc.py` (shared helpers), `validate.json` (all numbers above), `out/*.json` (per-asset logs).
