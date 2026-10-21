# Guanajuato night ambience — source list (2026-10-15)

**Status:** No audio files staged yet. The Openverse API (`api.openverse.org`)
returns HTTP 403 (Cloudflare bot protection) to automated requests from the
build VM, so `ov_audio.py` cannot pull from here. Every track below was
hand-verified (page live, license badge confirmed in page HTML) — grab them
from a normal browser.

**How to download:** Freesound requires a free account (no payment) to
download. Log in at https://freesound.org, open each URL, hit Download.
Alternatively run from an unblocked network (wade's PC):

    python3 ~/workspace/tools/openverse/ov_audio.py pull "<query>" \
        --kind <sfx|music> --license cc0,by --limit 5 \
        --out <this folder>

Each pull appends to `manifest.json` + `ATTRIBUTION.md` automatically.

---

## 1. Mariachi / street musicians (festive Mexican ensemble)

### Pick A — "Mexican Mariachis playing 'las mañanitas' on the square Garibaldi in Mexico City"
- Creator: felix.blume | License: **CC0** (verified: page badge links
  `creativecommons.org/publicdomain/zero/1.0`)
- 5:00, stereo WAV, 48 kHz / 24-bit, 82.4 MB
- Real mariachis on Plaza Garibaldi (Mexico City's mariachi square), playing
  "Las Mañanitas" with a second band bleeding in — authentic street feel.
- URL: https://freesound.org/people/felix.blume/sounds/219317/
- Openverse query fallback: `mariachi Garibaldi`

### Pick B — "Jarabe Tapatío / Mariachi"
- Creator: Lenguaverde | License: **CC0** (verified: page badge links
  `creativecommons.org/publicdomain/zero/1.0`)
- 2:30, stereo MP3 320 kbps, 5.7 MB
- The traditional Jarabe Tapatío (Mexican Hat Dance), street-recorded; final
  segment is the classic "Diana" fanfare.
- URL: https://freesound.org/people/Lenguaverde/sounds/177304/
- Openverse query fallback: `jarabe tapatio mariachi`

## 2. Church bells — evening

### Pick — "Church bells.wav"
- Creator: anand.username.taken | License: **CC0** (page states
  "Creative Commons 0")
- 1:18, stereo WAV, 96 kHz / 24-bit, 43.1 MB
- Evening church bells in a main shopping/entertainment district — right
  mood for the Basílica bell tower at nightfall.
- URL: https://freesound.org/people/anand.username.taken/sounds/501411/
- Openverse query fallback: `church bells evening`
- Backup (CC0, 2:38, mono MP3): https://freesound.org/people/m_marek/sounds/530431/

## 3. Plaza crowd ambience — night celebration

### Pick A — "crowd"
- Creator: ondrosik | License: **CC0** (page states "Creative Commons 0")
- 4:47, stereo FLAC, 48 kHz / 16-bit, 27.5 MB
- Crowd murmur with laughter, voices — long bed for the Jardín plaza loop.
- URL: https://freesound.org/people/ondrosik/sounds/728642/
- Openverse query fallback: `crowd ambience night`

### Pick B — "ambience mexico city juarez street night small crowd talking"
- Creator: jerry.berumen | License: **CC-BY 4.0** — attribution required
  (see below)
- 3:27, stereo WAV, 96 kHz / 24-bit, 114.5 MB
- Mexico City street at night, small crowd talking — best thematic fit for
  Guanajuato; recordist is a Mexico City sound editor.
- URL: https://freesound.org/people/jerry.berumen/sounds/762322/
- Openverse query fallback: `mexico city street night ambience`

## 4. Fireworks — distant bursts / crackle

### Pick A — "Fireworks"
- Creator: MrAuralization | License: **CC0** (page states
  "Creative Commons 0")
- 0:29, stereo WAV, 44.1 kHz / 16-bit, 5.0 MB
- Distant fireworks — clean burst bed for the violet-sky firework moments.
- URL: https://freesound.org/people/MrAuralization/sounds/213240/
- Openverse query fallback: `fireworks distant`

### Pick B — "Fireworks - explode and fizz.wav"
- Creator: soundmary | License: **CC0** (page states "Creative Commons 0")
- 1:11, stereo WAV, 44.1 kHz / 16-bit, 12.0 MB
- Fireworks exploding and fizzing at medium distance **with distant crowd
  sounds baked in** — doubles as celebration bed.
- URL: https://freesound.org/people/soundmary/sounds/117615/
- Openverse query fallback: `fireworks crowd`

---

## Attribution (only the CC-BY track needs it)

- "ambience mexico city juarez street night small crowd talking" by
  jerry.berumen (https://freesound.org/people/jerry.berumen/) — CC BY 4.0.
  Credit in the demo's credits/about panel.
- All other tracks above are CC0 — no attribution required (a credit line is
  still good practice).

## Suggested layering (UE5 / MarigoldFX weather + ambience)

1. `amb_plaza` bed: Pick 3A (CC0 crowd) looped low under everything.
2. Mariachi source: Pick 1A near the Jardín stage position (3D positional);
   Pick 1B as the baile/finale music stinger.
3. Bells: Pick 2 triggered at nightfall transition + faint hourly.
4. Fireworks: Pick 4A/4B synced to the sky-burst VFX timer.
5. Optional flavor: layer Pick 3B (Mexico City night) very low for authentic
   street texture — remember its CC-BY credit.
