# Hark Blender asset drop (branch hark/blender-assets, 2026-10-23)

Wade asked for these on GitHub directly. Per MERGE_PROTOCOL this is a branch, not main: Brio audits and copies what he wants into the UE5 ContentStaging pack.

- `ue5/ContentStaging/` mirrors the ContentStaging layout: unzip/copy over ContentStaging (original filenames, additive).
  - 12 NEW `w6_*.glb`, 45 reworked heroes (same filenames, incl. rebuilt `w3_flora_jacaranda.glb`), new calm 2K `w3_stucco_wall_*` texture set.
- `ue5/_HarkNotes/`: REPORT_BLENDER_rework.md, REPORT_BLENDER_new.md, BRIEF_BLENDER.md, contact sheets, integration_patch.cpp.txt (w6 placements + `IsAutoDressDenied` add `w6_`; NOT applied, uncompiled).
- `ue5/.gdignore` keeps Godot from importing these if the branch is ever merged into the Godot line.
- Same contents as Drive zip `ContentStaging-hark-blender-v0.9-addon.zip`. No third-party tja_ files. Not imported into Unreal yet.
