# MARIGOLD v0.9.1 — "Voices"

**Release date:** 2026-10-21 · **11 experiences** · NOT Quest-tested yet — wade's first run is the gate.

wade's order: the Godot version gets its own voice-over — a set that
matches THIS script's cast. The 55 UE5 lines staged in v0.9.0 stay
unwired: that script's cast (Chon, Lalo, Mar…) doesn't exist here, and
playing the wrong lines would be worse than captions. Instead, every
one of this script's 54 lines now has a real voice.

## NEW: full voice-over for the Godot script (54 lines, ~5.3 min)

- All 54 lines in `MarigoldDialogue` (NARRATIVE_V0110 §1.4) now play
  real audio via `MarigoldVoice.play_line()` — no code changes were
  needed: the clips sit at the exact paths the dialogue manager
  already loads (`assets/audio/voice/<chapter>/<speaker>_<key>.wav`,
  mono 48 kHz WAV, same spec as the music masters). Captions still
  show with every line; the caption-only fallback is untouched.
- **Same voices as the UE5 build for the shared cast** — Rosa is
  "Homey Slipper" and Tomás is "Restful Raincloud" in both games,
  so the abuelos sound like themselves on either engine.
- **New voices for the Godot-only cast** (all original TTS voices,
  no imitation of any performer):
  - Luz (tía, 9 lines) — Mirthful Maraca: warm, joyful, a little wicked.
  - The alebrije guides (2 lines each): Xochi — Merry Seesaw (young,
    playful); Tlanetl — Softhearted Dewdrop (slow, tender, shy);
    Mictli — Breezy Marmalade (very deep, slow — the old serpent);
    Papalotl — Flustered Pinwheel (fast, startled — it's a lot).
  - La banda (1 line each): Beto — Tireless Pendulum (energetic,
    Spanish); Chayo — Tickled Button (cheerful); Nena — Fond
    Flowerpot (tender, for the strings).
  - Rafa (4 lines) — Composed Bugle: a craftsman's calm confidence.
  - Nico (5 lines) — Vivacious Loaf: exuberant dance maestro.
  - Moti (1 line) — Giggly Bell: childlike, brand-new to the world.
- Honest tradeoff: the TTS catalog has exactly one Spanish-accented
  female voice (it's UE5 Mar's), so Luz, Chayo and Nena speak in warm
  English/Caribbean-accented voices. The Spanish endearments still
  land — the abuela warmth is in the writing.

## Verified headless (all actually run)

- `tools/probe_091_voice.gd`: 54/54 clips resolve via
  `ResourceLoader.exists()` and load as non-empty AudioStreams at
  the exact paths `play_line()` requests — including the accented
  `tomás_…` filenames in ch2/espejo.
- `tools/run_chapters_headless.gd`: all 11 chapter/experience scenes
  run 60 frames each, **0 script errors**.

## Notes

- The staged UE5 voice files under `assets/audio/voice/ue5/` are
  unchanged — they belong to the UE5 script if it ever ports.
- Debug-signed APK per the project's CI recipe, same as v0.9.0.
