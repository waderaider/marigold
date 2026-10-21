# Openverse audio staging — STATUS (2026-10-15)

No files staged yet. The Openverse API (`api.openverse.org`) returns HTTP 403
(Cloudflare bot protection) to automated requests from the build VM, so the
pipeline tool cannot pull audio from here.

The tool is ready at `~/workspace/tools/openverse/ov_audio.py` (see its
README). To fill this directory, run from an unblocked network (wade's PC):

    python3 ov_audio.py pull "church bell" --kind sfx --license cc0,by --limit 5 \
        --out /path/to/content-staging/Audio/openverse
    python3 ov_audio.py pull "mariachi" --kind music --license cc0,by --limit 2 \
        --out /path/to/content-staging/Audio/openverse

Each pull appends to `manifest.json` + `ATTRIBUTION.md` here automatically.
