# REPORT_BLENDER_new — w6_* new hero assets (Blender 4.3.2, then 5.1.0; 2026-10-22)

**Status: offline Blender work only.** The GLBs were exported, opened again in Blender, and rendered with Cycles. Nothing has been imported into UE 5.7. The C++ patch below has **not been compiled**. Nothing was pushed or uploaded. No existing file was modified: every output is a new `w6_*` stem or lives under `work/w6/` or `previews/blender/new/`.

These are original designs, Coco-inspired in spirit only. No Disney/Pixar shapes, characters, names or likenesses. The musician's guitar is a plain classical guitar with a hand-painted marigold-vine border, not the skull-headstock guitar. The portraits are abstract sepia silhouettes, not real people.

## Pipeline (repeatable)
- Scripts are in `marigold/work/w6/`:
  - `w6lib.py`: build helpers plus `finalize()`, which joins parts, applies weighted normals, makes a Smart-UV atlas, runs the Cycles bakes, encodes PNGs with PIL, builds the final PBR material and exports the GLB.
  - `w6mats.py`: procedural shaders (clay, barro negro, wood, tin, painted tin, cantera, bone, sugar, icing, foil, petal, paper, straw, charcoal, resin).
  - `w6shapes.py`: skull, ruffle discs, petals and marigold heads.
  - `a_<name>.py`: one build script per asset.
  - `papel_atlas.py`: PIL-drawn papel picado cut patterns.
  - `verify.py`: GLB parse and pixel round-trip check.
  - `contact.py`, `gen_report.py`.
- How to run:
  - One asset: `/workspace/tools/blender/current/blender -b --factory-startup -noaudio --python work/w6/run.py -- w6_<stem> [all|build|render]`.
  - Several in sequence: `work/w6/queue.sh stem…`.
  - Plain batch runs only. The MCP bridge on :9876 belongs to blender-rework and was never touched.
- Meshes:
  - Built in metres, front = −Y in Blender, which exports as glTF +Z. That is the same convention as the w3 assets, so `MarigoldW3::FacingYaw()` applies unchanged.
  - Origin is at the base centre (min Z = 0).
  - Bevel modifiers are on hard parts. A Weighted Normal modifier (keep sharp) was applied on all assets except the paper and petal ones, where it would flatten the crinkle shading.
- UVs: one Smart-UV atlas per asset, with a 0.004 margin and 10 px bake padding. The papel picado banner keeps its authored per-flag UVs so the cut patterns land 1:1 on the pixel grid.
- Textures:
  - Each asset gets a 2048 px (heroes) or 1024 px (props) set, baked in Cycles from the procedural shaders: basecolor (sRGB), tangent-space normal (**OpenGL / +Y**), and ORM (R = baked AO, G = roughness, B = metal).
  - Basecolor alpha is used for the papel picado cuts and the rebozo fringe (alphaMode MASK).
  - An emissive map is included for the copal embers.
  - Wear, grime and moss come from AO and Bevel nodes inside the bake (edge wear, cavity grime, moss in recesses).
- Embedding check:
  - PNGs are encoded with system PIL, read back and compared pixel by pixel before embedding.
  - After export, `verify.py` pulls each embedded PNG out of the GLB and compares it to the source pixel for pixel. Every texture passed (column "RT ok" below).
  - No Draco or meshopt compression; the `extensionsUsed` list is empty of both.
- LODs: none are stored inside the GLBs. Three stacked LOD mesh nodes would draw on top of each other with the current single-static-mesh import path. Use Nanite (all are closed or near-closed meshes) or UE auto-LOD on import.
- Normal maps are OpenGL (+Y), as the glTF spec requires. I expect UE's glTF/Interchange importer to handle the conversion, but I have not checked that in UE. If the bumps look inverted after import, set *Flip Green Channel* on the normal textures.

## Assets (12 delivered) — `content/content-staging/Models/artist-made/`

| stem | tris | dims W x D x H (m) | GLB MB | alpha | 2-sided | preview |
|---|---|---|---|---|---|---|
| w6_calavera_azucar_trio | 78,532 | 0.35 x 0.17 x 0.11 | 7.35 | OPAQUE | no | previews/blender/new/w6_calavera_azucar_trio.png |
| w6_cantera_fountain_basin | 20,008 | 1.82 x 1.82 x 0.88 | 9.64 | OPAQUE | yes | previews/blender/new/w6_cantera_fountain_basin.png |
| w6_copal_burner_tripod | 5,616 | 0.39 x 0.21 x 0.18 | 2.15 | OPAQUE | no | previews/blender/new/w6_copal_burner_tripod.png |
| w6_hojalata_milagros_box | 12,726 | 0.41 x 0.13 x 0.53 | 6.35 | OPAQUE | yes | previews/blender/new/w6_hojalata_milagros_box.png |
| w6_mezcal_jug_set | 6,142 | 0.54 x 0.40 x 0.32 | 1.91 | OPAQUE | no | previews/blender/new/w6_mezcal_jug_set.png |
| w6_ofrenda_bread_basket | 40,312 | 0.47 x 0.48 x 0.12 | 11.26 | OPAQUE | yes | previews/blender/new/w6_ofrenda_bread_basket.png |
| w6_ofrenda_photo_stand_set | 32,856 | 0.64 x 0.26 x 0.36 | 8.19 | OPAQUE | no | previews/blender/new/w6_ofrenda_photo_stand_set.png |
| w6_papel_picado_banner | 4,300 | 2.50 x 0.11 x 0.53 | 7.91 | MASK | yes | previews/blender/new/w6_papel_picado_banner.png |
| w6_petal_tile_path | 29,444 | 2.00 x 1.00 x 0.06 | 9.28 | OPAQUE | yes | previews/blender/new/w6_petal_tile_path.png |
| w6_rebozo_chair | 21,684 | 0.57 x 0.63 x 1.01 | 10.04 | MASK | yes | previews/blender/new/w6_rebozo_chair.png |
| w6_skeleton_guitarist | 37,106 | 1.03 x 0.84 x 1.35 | 8.05 | OPAQUE | no | previews/blender/new/w6_skeleton_guitarist.png |
| w6_tissue_flower_cluster | 16,728 | 0.50 x 0.40 x 0.65 | 2.65 | OPAQUE | yes | previews/blender/new/w6_tissue_flower_cluster.png |

### w6_calavera_azucar_trio
- **What**: three moulded sugar skulls (2 white, 1 chocolate) with piped royal icing, foil eye/nose inlays
- **Tris** 78,532 · **dims** 0.35 x 0.17 x 0.11 m · **GLB** 7.35 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_calavera_azucar_trio
- **Textures** (embedded PNG): w6_calavera_azucar_trio_normal 2048px (RT ok), w6_calavera_azucar_trio_orm 2048px (RT ok), w6_calavera_azucar_trio_basecolor 2048px (RT ok)
- **Placement**: Altar tier 3 front (0,-578,125), in front of the photo stands. Arm's-length VR close-up hero.

### w6_cantera_fountain_basin
- **What**: octagonal pink cantera fountain basin (1.96 m) with carved rosette panels, moss/water staining, pedestal cup, still water w/ floating marigold petals
- **Tris** 20,008 · **dims** 1.82 x 1.82 x 0.88 m · **GLB** 9.64 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_cantera_fountain_basin
- **Textures** (embedded PNG): w6_cantera_fountain_basin_normal 2048px (RT ok), w6_cantera_fountain_basin_orm 2048px (RT ok), w6_cantera_fountain_basin_basecolor 2048px (RT ok)
- **Placement**: West courtyard (-1150,560,0), mirrors the kiosko at (1250,700); clear of benches/lamps (check in editor).

### w6_copal_burner_tripod
- **What**: footed clay sahumador with handle, glowing charcoal (emissive) + copal resin; SOCKET_smoke node at ember top
- **Tris** 5,616 · **dims** 0.39 x 0.21 x 0.18 m · **GLB** 2.15 MB · material slots: baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_copal_burner_tripod, SOCKET_smoke
- **Textures** (embedded PNG): w6_copal_burner_tripod_emissive 1024px (RT ok), w6_copal_burner_tripod_normal 1024px (RT ok), w6_copal_burner_tripod_orm 1024px (RT ok), w6_copal_burner_tripod_basecolor 1024px (RT ok)
- **Placement**: Floor at the foot of the altar (0,-495,0). Node SOCKET_smoke (17.5 cm up) is where a MarigoldFX/Niagara smoke emitter should attach; patch adds a small unshadowed ember glow.

### w6_hojalata_milagros_box
- **What**: Oaxacan punched-tin (hojalata) wall box with sunburst crest, painted enamel, folk flaming heart, marigolds, 5 hanging milagros
- **Tris** 12,726 · **dims** 0.41 x 0.13 x 0.53 m · **GLB** 6.35 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_hojalata_milagros_box
- **Textures** (embedded PNG): w6_hojalata_milagros_box_normal 2048px (RT ok), w6_hojalata_milagros_box_orm 2048px (RT ok), w6_hojalata_milagros_box_basecolor 2048px (RT ok)
- **Placement**: Same side table, back edge (-420,-650,79); or wall-mount on a courtyard wall at ~150 cm.

### w6_mezcal_jug_set
- **What**: clay cantaro jug + 3 barro negro copitas + orange + sal de gusano on tray
- **Tris** 6,142 · **dims** 0.54 x 0.40 x 0.32 m · **GLB** 1.91 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_mezcal_jug_set
- **Textures** (embedded PNG): w6_mezcal_jug_set_normal 1024px (RT ok), w6_mezcal_jug_set_orm 1024px (RT ok), w6_mezcal_jug_set_basecolor 1024px (RT ok)
- **Placement**: On the ground next to the musician (-820,420,0) — or on the side table / a bench (verify seat height).

### w6_ofrenda_bread_basket
- **What**: three sugar-dusted pan de muerto (huesos + lagrima) on embroidered servilleta in a woven chiquihuite basket
- **Tris** 40,312 · **dims** 0.47 x 0.48 x 0.12 m · **GLB** 11.26 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_ofrenda_bread_basket
- **Textures** (embedded PNG): w6_ofrenda_bread_basket_normal 2048px (RT ok), w6_ofrenda_bread_basket_orm 2048px (RT ok), w6_ofrenda_bread_basket_basecolor 2048px (RT ok)
- **Placement**: Side offering table w3_court_table at (-420,-600): basket at (-420,-560,79).

### w6_ofrenda_photo_stand_set
- **What**: 3 carved mesquite photo stands with gilt relief (worn leaf over red bole), sepia portrait cards (abstract silhouettes, no likeness), easel struts
- **Tris** 32,856 · **dims** 0.64 x 0.26 x 0.36 m · **GLB** 8.19 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_ofrenda_photo_stand_set
- **Textures** (embedded PNG): w6_ofrenda_photo_stand_set_normal 2048px (RT ok), w6_ofrenda_photo_stand_set_orm 2048px (RT ok), w6_ofrenda_photo_stand_set_basecolor 2048px (RT ok)
- **Placement**: Altar tier 3 (z=125 cm), back centre (0,-612,125). Replaces nothing; sits behind the sugar-skull trio. Builder: BuildWave3Environment (W6 block).

### w6_papel_picado_banner
- **What**: 6 hanging tissue flags, 30x40 cm, real cut patterns in alpha (MASK), twine with catenary sag, 2.5 m span
- **Tris** 4,300 · **dims** 2.50 x 0.11 x 0.53 m · **GLB** 7.91 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_papel_picado_banner
- **Textures** (embedded PNG): w6_papel_picado_banner_normal 2048px (RT ok), w6_papel_picado_banner_orm 2048px (RT ok), w6_papel_picado_banner_basecolor 2048px (RT ok)
- **Placement**: Across the altar front above the marigold arch (0,-520,235); extra copies can chain over the petal path at z~380 (2.5 m span each).

### w6_petal_tile_path
- **What**: 2.0 x 1.0 m handmade saltillo tile path section with grout, strewn cempasuchil petal trail + whole heads; tileable along X
- **Tris** 29,444 · **dims** 2.00 x 1.00 x 0.06 m · **GLB** 9.28 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_petal_tile_path
- **Textures** (embedded PNG): w6_petal_tile_path_normal 2048px (RT ok), w6_petal_tile_path_orm 2048px (RT ok), w6_petal_tile_path_basecolor 2048px (RT ok)
- **Placement**: 4 chained 2 m sections from the main petal path west to the fountain: (-160 - i*200, 420, 0.3), i=0..3.

### w6_rebozo_chair
- **What**: painted Michoacan-style chair with tule seat; cloth-simulated ikat rebozo with alpha fringe draped over back & seat
- **Tris** 21,684 · **dims** 0.57 x 0.63 x 1.01 m · **GLB** 10.04 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_rebozo_chair
- **Textures** (embedded PNG): w6_rebozo_chair_normal 2048px (RT ok), w6_rebozo_chair_orm 2048px (RT ok), w6_rebozo_chair_basecolor 2048px (RT ok)
- **Placement**: Visitor's chair facing the altar (330,-390,0), yaw 160 — tells the 'someone just stepped away' story.

### w6_skeleton_guitarist
- **What**: original seated skeleton musician on a crate with painted classical guitar, palm hat, paliacate; static pose prop
- **Tris** 37,106 · **dims** 1.03 x 0.84 x 1.35 m · **GLB** 8.05 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_skeleton_guitarist
- **Textures** (embedded PNG): w6_skeleton_guitarist_normal 2048px (RT ok), w6_skeleton_guitarist_orm 2048px (RT ok), w6_skeleton_guitarist_basecolor 2048px (RT ok)
- **Placement**: Beside the fountain (-880,330,0), yaw -40 so he plays toward the main path / player.

### w6_tissue_flower_cluster
- **What**: 7 fan-folded tissue-paper blooms (papel de china) on wire stems, ribbon tie; double-sided paper
- **Tris** 16,728 · **dims** 0.50 x 0.40 x 0.65 m · **GLB** 2.65 MB · material slots: baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture · nodes: w6_tissue_flower_cluster
- **Textures** (embedded PNG): w6_tissue_flower_cluster_normal 1024px (RT ok), w6_tissue_flower_cluster_orm 1024px (RT ok), w6_tissue_flower_cluster_basecolor 1024px (RT ok)
- **Placement**: Altar tier 1 side wings (+-96,-600,45) at scale 0.7, yaw +-20. Also good in talavera urns.

## Contact sheet
`previews/blender/contact_new.png`. Each asset also has a single still: `previews/blender/new/<stem>.png`.

Render setup:
- Each render reimports the exported GLB, so it shows exactly what UE will receive.
- Lighting is the same for every asset: a dark studio sweep, a soft cool key, a cool rim light and two warm candle-coloured point lights.
- Cycles at 48 spp with the OIDN denoiser (Blender 5.1).
- These are offline renders, not UE screenshots.

## Honest notes / known limitations
- **Tool change mid-run.** The sandbox was reset at about 03:38 UTC. That removed the system Blender 4.3.2 and its Python packages, and killed every background job, including blender-rework's MCP bridge (I did not restart it; it is theirs). I continued with the persistent **Blender 5.1.0** in `/workspace/tools/blender/current`, using the same scripts.
  - The GLBs for `w6_mezcal_jug_set`, `w6_papel_picado_banner` and `w6_skeleton_guitarist` were exported from 4.3. All other GLBs were built or rebuilt in 5.1.
  - Every preview still was rendered in 5.1 with the OIDN denoiser (plus a light PIL pass).
- **Colour.** Basecolor bakes use a gamma 1.6 "palette to linear" step, so the hand-picked colours read correctly. The papel picado bypasses it so its PIL-drawn atlas colours stay exact.
- **Musician** is a static pose prop, a single mesh with no skeleton or rig. The hat brim hides most of the face from eye level, so lower the hat tilt in `a_skeleton_guitarist.py` if you want the skull read more. The guitar's painted marigold border is subtle at 2K.
- **Placement coordinates are suggestions** taken from the scene builder's own layout (altar at (0,-600), tier tops at 45/85/125 cm, court table at (-420,-600), kiosko at (1250,700)). Check them in the editor for overlaps with the w5 plaza dressing, which I could not see placed.
- The petal tile path's tiles line up when sections are chained along X. The scattered petals do not tile seamlessly, so alternate the yaw between 0 and 180 to hide repeats.
- The fountain water is an opaque glossy surface in the GLB. For real water, swap in an M_Water material on that part in UE. It is the flat octagon at 44 cm; a material split was not done because each asset uses one atlas material.
- Not done because of time: LOD1/LOD2 nodes (see the pipeline note), per-asset before/after renders (these are new assets, so there is no "before"), and a second camera angle per asset.

## INTEGRATION PATCH (uncompiled — apply by hand, then build in UE 5.7)

```cpp
// ===== PATCH 1 — MarigoldSceneBuilder.cpp, IsAutoDressDenied() =====
// Add w6_ to the explicit-placement prefixes so keyword auto-dressing never grabs these stems.
	return DenyList.Contains(Stem) || Stem.StartsWith(TEXT("w3_")) || Stem.StartsWith(TEXT("w4_"))
		|| Stem.StartsWith(TEXT("w5_")) || Stem.StartsWith(TEXT("w6_")) || Stem.StartsWith(TEXT("tja_"));

// ===== PATCH 2 — MarigoldSceneBuilder_Wave3.cpp, end of BuildWave3Environment() =====
// Insert just BEFORE the final Owner.Log(...) line (after MarigoldW5Plaza::Build(...)).
// Reuses the existing `Put` lambda (HasW3 guard -> missing asset = silent skip) and `Front`.
// Units cm; altar centre (0,-600), tier tops z = 45 / 85 / 125 (w3_altar_tiers), front = +Y.
// Yaw offsets: 0 = faces south (+Y), 180 = north, -90 = east (+X), 90 = west (-X).
	// ---------------- v0.9 w6_* Blender hero pass (REPORT_BLENDER_new.md) ----------------
	{
		const TCHAR* W6Folder = TEXT("Altar/W6");
		// Tier 3 (z=125, 110x70 cm): carved photo stands at the back, sugar-skull trio in front of them.
		Put(TEXT("w6_ofrenda_photo_stand_set"), FVector(0.0f, -612.0f, 125.0f), 0.0f, W6Folder);
		Put(TEXT("w6_calavera_azucar_trio"),    FVector(0.0f, -578.0f, 125.0f), 0.0f, W6Folder);
		// Tier 1 side wings (x = +-80..110 cm, z=45): tissue-paper bouquets, scaled to the 30 cm wing.
		Put(TEXT("w6_tissue_flower_cluster"), FVector(-96.0f, -600.0f, 45.0f),  20.0f, W6Folder, 0.7f);
		Put(TEXT("w6_tissue_flower_cluster"), FVector( 96.0f, -600.0f, 45.0f), -20.0f, W6Folder, 0.7f);
		// Copal burner on the floor at the foot of the altar (smoke rises from the GLB node SOCKET_smoke, ~17.5 cm up).
		AActor* Copal = Put(TEXT("w6_copal_burner_tripod"), FVector(0.0f, -495.0f, 0.0f), 0.0f, W6Folder);
		// Papel picado across the altar front, above the marigold arch (arch crown ~152 cm).
		Put(TEXT("w6_papel_picado_banner"), FVector(0.0f, -520.0f, 235.0f), 0.0f, W6Folder);
		// Side offering table (w3_court_table at (-420,-600), top ~79 cm): bread basket + tin niche.
		Put(TEXT("w6_ofrenda_bread_basket"),  FVector(-420.0f, -560.0f, 79.0f),  10.0f, W6Folder);
		Put(TEXT("w6_hojalata_milagros_box"), FVector(-420.0f, -650.0f, 79.0f),   0.0f, W6Folder);
		// Visitor's chair facing the altar, rebozo left on it.
		Put(TEXT("w6_rebozo_chair"), FVector(330.0f, -390.0f, 0.0f), 160.0f, TEXT("Courtyard/W6"));
		// West courtyard: cantera fountain mirrors the kiosko (1250,700); musician + mezcal beside it.
		Put(TEXT("w6_cantera_fountain_basin"), FVector(-1150.0f, 560.0f, 0.0f),  22.5f, TEXT("Courtyard/W6"));
		Put(TEXT("w6_skeleton_guitarist"),     FVector(-880.0f, 330.0f, 0.0f),  -40.0f, TEXT("Courtyard/W6"));
		Put(TEXT("w6_mezcal_jug_set"),         FVector(-820.0f, 420.0f, 0.0f),  -25.0f, TEXT("Courtyard/W6"));
		// Saltillo + petal side path: 4 chained 2 m sections from the main path (x=0) west toward the fountain.
		for (int32 i = 0; i < 4; ++i)
		{
			Put(TEXT("w6_petal_tile_path"), FVector(-160.0f - i * 200.0f, 420.0f, 0.3f), 0.0f, TEXT("Courtyard/W6/Path"));
		}
		// Warm unshadowed glow off the copal embers (shadow budget stays with the candles).
		if (Copal)
		{
			UPointLightComponent* PL = NewObject<UPointLightComponent>(Copal, TEXT("W6CopalGlow"));
			PL->SetupAttachment(Copal->GetRootComponent());
			PL->SetRelativeLocation(FVector(0, 0, 17.0f) / FMath::Max(Copal->GetActorScale3D().Z, KINDA_SMALL_NUMBER));
			PL->SetIntensity(120.0f);
			PL->SetAttenuationRadius(140.0f);
			PL->SetLightColor(FLinearColor(1.0f, 0.45f, 0.15f));
			PL->SetCastShadows(false);
			Copal->AddInstanceComponent(PL);
			PL->RegisterComponent();
		}
	}
```
