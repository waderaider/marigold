# BRIEF_BLENDER — v0.9 Blender pass (2026-10-22)

Wade asked: "Update existing assets and new ones using the Blender MCP." Bar: movie-trailer look, original designs (Coco-inspired, never Disney copies). UE 5.7 target (Nanite-friendly hero meshes, but also LOD-able).

## Tooling
- Blender 4.3.2 installed system-wide (`blender`, aarch64 Debian). Headless MCP bridge: `blender -b --factory-startup --python /workspace/work/blender/headless_mcp.py` listens on localhost:9876 (BLENDER_PORT env to change). It may already be running (check `ss -ltnp | grep 9876` / `pgrep -f headless_mcp`); start it with setsid nohup if not.
- MCP server registered as `blender` (stdio `uvx blender-mcp`): `mcpcall tools blender`, `mcpcall call blender execute_blender_code '{"code":"..."}'`, `get_scene_info`, viewport screenshots may NOT work headless — render with Cycles/EEVEE to file instead.
- For heavy batch work, running `blender -b --python script.py` directly is fine and faster; use the MCP for interactive inspection. Only 2 CPUs / 7 GB RAM: keep renders small (Cycles 32–64 spp, 768–1024 px, denoise), one Blender job at a time per agent.
- Existing numpy kit: content/content-staging/_tools/assets3d (meshkit.py, glbload.py) for stats.

## Rules (from MERGE_PROTOCOL.md + project)
- Additive staging under ORIGINAL filenames for reworked assets; back up originals to content/content-staging/_backup_pre_blender/ first.
- New assets: stems `w6_*` in Models/artist-made/; avoid builder keywords (pan, candle, garland, frame, shrine, post, pillar, column, lantern) in new stems.
- Export glTF binary (.glb), +Y up default exporter, no Draco/meshopt compression, embedded PNG textures (encode images via system PIL and round-trip pixel-check; never trust Image.save alone). Keep pivots/scale (meters) and object origin conventions of the original so the scene builder's placements still work — compare bounding boxes before/after (±5%).
- Never touch tja_ files.
- Honest reporting: offline renders only, no UE import/compile.

## Quality checklist per asset
Bevel/weighted normals on hard edges, real UV unwrap (no stretched procedural UVs), PBR textures baked from Blender procedural shaders (basecolor, normal DX/OpenGL note, ORM) at 2K for heroes / 1K for props, wear/edge grime/AO, micro-variation, correct scale, tri budget (hero ≤ 200k, prop ≤ 30k), LOD1/LOD2 via Decimate as separate _LOD1/_LOD2 mesh nodes if feasible. Before/after render (same camera, studio + warm candle light) for every asset into previews/blender/.
