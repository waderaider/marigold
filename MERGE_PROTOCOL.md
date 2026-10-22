# MERGE_PROTOCOL.md

External-collaborator rules for the marigold repo. You build; Brio owns the merge.
Nothing you produce ships until Brio audits it against this file. Two previous
external drops each silently reverted approved fixes — this document exists so it
never happens a third time.

## How collaboration works

1. **Work in your own lane.** Before touching files, ask Brio what's in flight
   (wiring, compile fixes, model swaps) so pushes don't collide.
2. **Never push directly to main or any release.** Deliver work as a branch,
   a clearly-named zip, or a Drive link — with a file list, what each change
   fixes, and how you verified it.
3. **Brio audits every drop** against the standing-fix checklist below, then
   merges, re-verifies, and ships under a version number. Audit is not optional.

## Standing fixes — your merge MUST preserve all of these

These were broken by previous external drops. Verify each one survives:

- **Relay URL:** all log/telemetry endpoints point to
  `https://nexus-log-relay.wade-relay.workers.dev`. The old `brio-00c` worker
  is dead for new reports — a zip with stale URLs sends logs nowhere.
- **No forced ray-tracing config:** MarigoldRTX must NOT force-enable
  `r.RayTracing` on D3D12. That was the crash config.
- **Force-feedback compile fix:** present and compiling. This one was reverted
  twice by outside drops — check it explicitly.
- **Candle melt** (MarigoldFX) intact and wired.
- **Voice lines intact:** count and content unchanged (UE5 set: 55; Godot set: 54).
- **Updater pinned to the live release.** Never point scripts at old tags.

## File-encoding rules (silent killers)

- **`.ps1` files: UTF-8 WITH BOM.** PowerShell 5.1 reads BOM-less scripts as
  ANSI; UTF-8 punctuation (em-dashes) decodes as quote characters and breaks
  parsing with no useful error.
- **`.bat` files: CRLF line endings.** LF-only batch files flash and exit.
- After writing either, verify with `file <path>` before committing.

## Build honesty rules

- **wade's PC is the compile gate for UE5.** No "verified" claim without a real
  compile. Code tested only against stubs is reported as stub-tested, never as
  built.
- Unreal Header Tool rejects data structures declared inside classes
  (USTRUCT/UFUNCTION scoping). Enums and structs that travel with them move to
  global scope.
- Verify API names against the actual engine version in use (UE 5.7), not
  vendor docs or memory. A guessed name cost us a full build round.
- **Godot 4.7.2 rejects meshopt- and Draco-compressed GLBs.** Compress with
  `gltfpack -noq` instead. Parse-check scripts with
  `godot --headless --check-only --script <path>` (positional path without
  `--script` runs the file as a scene).
- Blender: never trust `Image.save()` output without a round-trip pixel check —
  route image encoding through system PIL.

## Product rules

- **MARIGOLD and NEXUS ARCADE stay fully separate.** No merging, no launcher
  entries, no cross-promotion links in either direction.
- **'built by Muse'** appears ONLY on the main launcher app header — never on
  individual game rows.
- Both launchers: simple 2D scrollable list, laser pointer + trigger. Every
  game/chapter needs a working Exit-to-launcher (menu button AND on-screen
  control). No placeholders — if it's not done, it doesn't ship.
- Content pack staging is **additive under original filenames** so scenes pick
  replacements up with no code changes; bump the version marker so the updater
  re-pulls the pack exactly once.

## What to hand Brio with every drop

1. File list of what changed, and why.
2. What it fixes or adds, in plain terms.
3. How you verified it (real compile? headless gate? stub-tested? — be honest).
4. Anything you knowingly left stubbed, unverified, or as a guess.
