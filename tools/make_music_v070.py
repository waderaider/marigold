#!/usr/bin/env python3
"""
MARIGOLD v0.7.0 - second score pack: 10 NEW original themed mood loops.

wade's no-placeholders order: every chapter + the menu gets its OWN themed
music. v0.6.2 had 4 moods shared across 12 destinations. This adds:

  menu      - "La Bienvenida": warm 3/4 guitar waltz, the menu's own theme
  puente    - ch2 Marigold Bridge: flowing 6/8 water theme, high KS + low bells
  alebrijes - ch3 Plaza: playful bouncy 2/4, trumpet stabs + slap percussion
  papel     - ch4 Canopy: airy wind-blown plucks, sparse harmonics + shaker
  baile     - ch5 El Gran Baile: driving 6/8 banda, trumpet lead, the big dance
  magia     - Mano Magica: mysterious-warm hand tour, minor color, chimes
  cancion   - Guitarra: strummed-guitar feature (player is the lead), no trumpet
  espejo    - Espejo mirror dance: hypnotic ostinato, deep pulse
  recuerdos - Galeria: music-box high KS, tender-variant memory theme
  ofrenda   - Tu Ofrenda finale: builds solo->full, swell-ready held ending

ALL MUSIC IS 100% ORIGINAL - progressions and melodies composed for this
script. Reuses the tested voices from make_music.py (KS pluck, trumpet-ish
lead, hand drum, shaker). 22050 Hz 16-bit mono, seamless loops, -3 dB peak.
Run: python3 tools/make_music_v070.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_music as mm

SR = mm.SR


# Extra chord voicings (MIDI), original folk-inspired choices.
A7 = [45, 52, 57, 60, 67]    # A2 E3 A3 C4 G4
D7 = [38, 45, 50, 53, 60]    # D2 A2 D3 F3 C4
E7 = [40, 47, 52, 55, 62]    # E2 B2 E3 G3 D4
Bm = [47, 54, 59, 62, 66]    # B2 F#3 B3 D4 F#4
FshDim = [42, 48, 54, 57]    # F#2 C3 F#3 A3
G6 = [43, 50, 55, 59, 64]    # G2 D3 G3 B3 E4
Csus = [48, 53, 55, 60]      # C3 F3 G3 C4
Am7 = [45, 52, 55, 60, 64]   # A2 E3 G3 C4 E4
EmAdd = [40, 47, 52, 57, 64] # E2 B2 E3 A3 E4


def make_menu():
    """La Bienvenida - ~36 s. Warm 3/4 waltz for the menu: strummed KS
    guitar (oom-pah-pah), soft trumpet melody. 90 BPM, beat = 0.667 s."""
    bpm = 90.0
    beat = 60.0 / bpm
    bar = 3.0 * beat            # 2.0 s
    bars = 18                  # 36 s
    mix = mm.Mix(bars * bar)
    prog = [mm.C4, mm.F, mm.G4, mm.C4,
            mm.AM, mm.F, mm.D4, mm.G4,
            mm.C4, mm.F, mm.G4, mm.C4,
            mm.EM4, mm.AM, mm.D4, mm.G4,
            mm.C4, mm.G4]
    # original waltz melody (trumpet), one note per beat
    mel = [[72, 76, 79], [77, 81, 77], [79, 83, 81], [79, 76, 72],
           [76, 79, 81], [77, 81, 84], [74, 77, 81], [79, 83, 79],
           [81, 79, 76], [81, 84, 81], [79, 83, 79], [72, None, None],
           [76, 79, 76], [74, 76, 79], [77, 81, 79], [83, 81, 79],
           [84, 79, 76], [72, None, None]]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # oom-pah-pah: bass on 1, chord strums on 2 and 3
        mix.add(mm.ks(mm.mtof(chord[0]), 1.0, damp=0.995), t, 0.38)
        mm.strum(mix, chord[1:], t + beat, dur=0.7, damp=0.9945, gain=0.42)
        mm.strum(mix, chord[1:], t + 2 * beat, dur=0.7, damp=0.9945, gain=0.38)
        # trumpet melody
        for k, m in enumerate(mel[b]):
            if m is not None:
                mix.add(mm.trumpet(mm.mtof(m), beat * 0.9, gain=0.38),
                        t + k * beat)
    mm.finalize(mix, bars * bar, "menu")


def make_puente():
    """ch2 bridge - ~40 s. Flowing 6/8 water theme: bright KS arps,
    low bell tolls on bar starts, shaker like lapping water."""
    eighth = 0.30
    bar = 6 * eighth           # 1.8 s
    bars = 22                  # 39.6 s
    mix = mm.Mix(bars * bar)
    prog = ([mm.C, mm.G, mm.AM, mm.F] * 3
            + [mm.DM, mm.G, mm.C, mm.G,
               mm.AM, mm.F, mm.G, mm.C,
               mm.F, mm.C])
    arp_idx = [4, 3, 2, 1, 2, 3]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # low bell on the downbeat (long KS decay)
        mix.add(mm.ks(mm.mtof(chord[0] - 12), 2.6, damp=0.9992), t, 0.30)
        # bright flowing arps on the six eighths
        for k, ci in enumerate(arp_idx):
            mix.add(mm.ks(mm.mtof(chord[ci]), 0.9, damp=0.9975),
                    t + k * eighth, 0.24)
        # shaker lapping on eighths 1, 3, 5
        for e in (1, 3, 5):
            mix.add(mm.tick(), t + e * eighth, 0.16)
    mm.finalize(mix, bars * bar, "puente")


def make_alebrijes():
    """ch3 plaza - ~36 s. Playful 2/4: bouncy strummed guitar, trumpet
    stabs (short), slap + shaker. Bright major, creature-parade feel."""
    bpm = 100.0
    beat = 60.0 / bpm          # 0.6 s
    bar = 2.0 * beat           # 1.2 s
    bars = 30                  # 36 s
    mix = mm.Mix(bars * bar)
    prog = ([mm.G4, mm.C4, mm.G4, mm.D4] * 4
            + [mm.EM4, mm.C4, mm.D4, mm.G4,
               mm.C4, mm.G4, mm.D4, mm.G4,
               mm.C4, mm.G4, mm.C4, mm.G4,
               mm.G4, mm.C4])
    # original cheeky trumpet riff: stabs on the off-beats
    riff = [79, None, 81, None, 83, None, 81, 79,
            84, None, 83, 81, 79, None, 77, None,
            79, 81, 83, 81, 79, 77, 76, None,
            79, None, 81, None, 83, None]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # bouncy strum on both beats
        mm.strum(mix, chord, t, dur=0.5, damp=0.9935, gain=0.46)
        mm.strum(mix, chord, t + beat, dur=0.5, damp=0.9935, gain=0.40)
        # membrane + slap: thump on 1, slap on the "and"
        mix.add(mm.membrane(160, 60, 0.25), t, 0.85)
        mix.add(mm.slap(), t + beat * 0.5, 0.38)
        mix.add(mm.slap(), t + beat * 1.5, 0.34)
        mix.add(mm.tick(), t + beat * 0.5, 0.22)
        # trumpet stab riff (short notes)
        r = riff[b]
        if r is not None:
            mix.add(mm.trumpet(mm.mtof(r), 0.28, gain=0.42), t + beat * 0.5)
    mm.finalize(mix, bars * bar, "alebrijes")


def make_papel():
    """ch4 canopy - ~40 s. Airy and wind-blown: sparse KS harmonics,
    high shimmer plucks, shaker swells. Slow, banners in the breeze."""
    bpm = 60.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    bars = 10                  # 40 s
    mix = mm.Mix(bars * bar)
    prog = [mm.AM, mm.F, mm.C, mm.G,
            mm.EM, mm.F, mm.DM, mm.G,
            mm.AM, mm.G]
    # original sparse shimmer melody (two notes per bar, high register)
    pairs = [(88, 84), (86, 83), (84, 81), (83, 79),
             (81, 79), (84, 81), (83, 81), (86, 84),
             (88, 86), (83, None)]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # one soft harmonic-ish pluck per beat (very bright damp)
        for k in range(4):
            ci = (k * 2 + 1) % len(chord)
            mix.add(mm.ks(mm.mtof(chord[ci] + 12), 2.2, damp=0.9985),
                    t + k * beat, 0.15)
        m1, m2 = pairs[b]
        mix.add(mm.ks(mm.mtof(m1), 2.4, damp=0.9988), t + beat * 0.5, 0.16)
        if m2 is not None:
            mix.add(mm.ks(mm.mtof(m2), 2.4, damp=0.9988),
                    t + beat * 2.5, 0.14)
        # shaker swell across the bar (wind gust)
        for e in range(8):
            env = mm.math.sin(mm.math.pi * e / 8.0) ** 2
            mix.add(mm.tick(), t + e * beat * 0.5, 0.10 + 0.14 * env)
    mm.finalize(mix, bars * bar, "papel")


def make_baile():
    """ch5 El Gran Baile - ~40 s. The big dance: driving 6/8 banda,
    trumpet lead with an ORIGINAL celebratory melody, full drums."""
    eighth = 60.0 / 132.0 / 2.0   # 132 BPM quarter
    bar = 6 * eighth              # 1.36 s
    bars = 29                     # 39.5 s
    mix = mm.Mix(bars * bar)
    prog = ([mm.G4, mm.C4, mm.D4, mm.G4] * 4
            + [mm.EM4, mm.C4, mm.D4, mm.G4,
               mm.C4, mm.G4, mm.D4, mm.G4,
               mm.C4, mm.D4, mm.G4, mm.C4,
               mm.G4])
    # original dance trumpet melody: 6 eighth-notes per bar
    lead = [
        [79, 81, 83, 81, 79, 76], [77, 79, 81, 79, 77, 74],
        [79, 81, 83, 86, 83, 81], [79, 77, 76, 77, 79, 81],
        [83, 81, 79, 81, 83, 86], [84, 83, 81, 79, 81, 83],
        [79, 81, 83, 81, 79, 77], [76, 77, 79, 77, 76, 74],
        [79, 81, 79, 76, 74, 76], [77, 81, 79, 77, 74, 77],
        [79, 83, 81, 79, 76, 79], [81, 83, 86, 83, 81, 79],
        [84, 81, 79, 81, 84, 86], [88, 86, 84, 83, 81, 83],
        [79, 81, 83, 81, 83, 86], [84, 83, 81, 83, 81, 79],
        [77, 79, 81, 83, 81, 79], [76, 77, 79, 81, 79, 77],
        [74, 76, 77, 79, 77, 76], [74, 76, 79, 76, 74, 71],
        [72, 74, 76, 79, 76, 74], [77, 79, 81, 79, 77, 76],
        [74, 76, 77, 79, 81, 83], [81, 79, 77, 76, 74, 76],
        [77, 79, 81, 83, 86, 84], [83, 81, 79, 81, 83, 81],
        [79, 76, 74, 76, 79, 76], [74, 76, 79, 81, 79, 76],
        [72, None, None, None, None, None],
    ]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # driving strums on eighths 0 and 3
        mm.strum(mix, chord, t, dur=0.8, damp=0.994, gain=0.50)
        mm.strum(mix, chord, t + 3 * eighth, dur=0.7, damp=0.994, gain=0.42)
        # bass root on 0
        mix.add(mm.ks(mm.mtof(chord[0]), 1.0, damp=0.995), t, 0.34)
        # drums: membrane on 0 & 3, slaps on 2 & 5, shaker all
        mix.add(mm.membrane(155, 58, 0.30), t, 0.95)
        mix.add(mm.membrane(140, 55, 0.28), t + 3 * eighth, 0.80)
        mix.add(mm.slap(), t + 2 * eighth, 0.40)
        mix.add(mm.slap(), t + 5 * eighth, 0.36)
        for e in range(6):
            g = 0.28 if e in (0, 3) else 0.20
            mix.add(mm.tick(), t + e * eighth, g)
        # trumpet lead
        notes = lead[b]
        if b == bars - 1:
            mix.add(mm.trumpet(mm.mtof(notes[0]), 1.6, gain=0.5), t)
        else:
            for k, m in enumerate(notes):
                if m is None:
                    continue
                mix.add(mm.trumpet(mm.mtof(m), eighth * 0.9, gain=0.44),
                        t + k * eighth)
    mm.finalize(mix, bars * bar, "baile")


def make_magia():
    """Mano Magica - ~44 s. Mysterious-warm hand tour: Em-C-D-G colors,
    low membrane heartbeat, chime accents, trumpet only whispers."""
    bpm = 80.0
    beat = 60.0 / bpm          # 0.75 s
    bar = 4.0 * beat           # 3.0 s
    bars = 15                  # 45 s (trimmed by finalize length)
    mix = mm.Mix(bars * bar)
    prog = ([EmAdd, mm.C, mm.D4, mm.G4] * 2
            + [mm.AM, mm.C, mm.D4, E7,
               mm.AM, mm.D4, mm.G4])
    # original whisper melody (soft trumpet, sparse)
    mel = [[64, None, 67, None], [65, None, 64, None],
           [62, None, 64, None], [59, None, None, None],
           [64, None, 67, None], [69, None, 67, 65],
           [64, None, 62, None], [59, None, None, None],
           [60, None, 64, None], [67, None, 65, 64],
           [62, None, 64, 67], [71, None, 69, None],
           [67, None, 64, None], [62, None, None, None],
           [64, None, None, None]]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # low membrane heartbeat on 1 and 3
        mix.add(mm.membrane(120, 50, 0.40), t, 0.85)
        mix.add(mm.membrane(110, 48, 0.35), t + 2 * beat, 0.65)
        # soft arps
        arp_idx = [0, 2, 3, 1, 3, 2]
        for k, ci in enumerate(arp_idx[:4]):
            c = chord[ci % len(chord)]
            mix.add(mm.ks(mm.mtof(c), 1.4, damp=0.9968),
                    t + k * beat, 0.24)
        # chime accent on beat 4 (high bell)
        mix.add(mm.ks(mm.mtof(chord[-1] + 12), 2.0, damp=0.9992),
                t + 3 * beat, 0.20)
        # whisper trumpet melody
        for k, m in enumerate(mel[b]):
            if m is not None:
                mix.add(mm.trumpet(mm.mtof(m), beat * 0.85, gain=0.30),
                        t + k * beat)
    mm.finalize(mix, bars * bar, "magia")


def make_cancion():
    """Guitarra - ~36 s. Strummed-guitar feature: the STATION is the lead,
    so no trumpet lead here - just rich guitar + light percussion bed."""
    bpm = 110.0
    beat = 60.0 / bpm
    bar = 4.0 * beat           # 2.18 s
    bars = 17                  # 37 s
    mix = mm.Mix(bars * bar)
    prog = ([mm.G4, mm.EM4, mm.C4, mm.D4] * 3
            + [mm.C4, mm.G4, mm.D4, mm.G4,
               mm.G4])
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # featured strumming: down on 1, up-accent on 2&, down on 3, flourish 4
        mm.strum(mix, chord, t, dur=1.6, damp=0.9945, gain=0.55)
        mm.strum(mix, list(reversed(chord)), t + beat * 1.5,
                 dur=1.0, damp=0.994, gain=0.34)
        mm.strum(mix, chord, t + 2 * beat, dur=1.4, damp=0.9945, gain=0.48)
        mm.strum(mix, chord, t + 3 * beat, dur=0.9, damp=0.9935, gain=0.36)
        # bass root on 1 and 3
        mix.add(mm.ks(mm.mtof(chord[0]), 1.2, damp=0.995), t, 0.36)
        mix.add(mm.ks(mm.mtof(chord[0]), 1.0, damp=0.995), t + 2 * beat, 0.30)
        # light percussion: membrane 1&3, shaker 8ths
        mix.add(mm.membrane(150, 55, 0.30), t, 0.80)
        mix.add(mm.membrane(135, 52, 0.28), t + 2 * beat, 0.65)
        for e in range(8):
            mix.add(mm.tick(), t + e * beat * 0.5,
                    0.24 if e % 2 == 0 else 0.16)
    mm.finalize(mix, bars * bar, "cancion")


def make_espejo():
    """Espejo - ~44 s. Hypnotic mirror dance: repeating 2-bar ostinato,
    deep pulse, trumpet answers every 4 bars. Trance-folk."""
    bpm = 96.0
    beat = 60.0 / bpm          # 0.625 s
    bar = 4.0 * beat           # 2.5 s
    bars = 18                  # 45 s
    mix = mm.Mix(bars * bar)
    prog = [mm.AM, mm.G4, mm.AM, mm.G4,
            mm.F, mm.G4, mm.AM, mm.AM,
            mm.AM, mm.G4, mm.F, mm.G4,
            mm.AM, mm.F, mm.G4, mm.AM,
            mm.AM, mm.G4]
    ost = [57, 60, 64, 67, 64, 60]  # A3 C4 E4 G4 E4 C4, MIDI
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # deep pulse on every beat (heartbeat of the mirror)
        for k in range(4):
            mix.add(mm.membrane(100, 45, 0.30), t + k * beat, 0.75)
        # ostinato plucks on 8ths
        for k in range(8):
            m = ost[k % len(ost)]
            mix.add(mm.ks(mm.mtof(m), 0.55, damp=0.9962),
                    t + k * beat * 0.5, 0.26)
        # trumpet answer every 4th bar (bars 3, 7, 11, 15)
        if b % 4 == 3:
            ans = [76, 79, 81, 79]
            for k, m in enumerate(ans):
                mix.add(mm.trumpet(mm.mtof(m), beat * 0.9, gain=0.36),
                        t + k * beat)
    mm.finalize(mix, bars * bar, "espejo")


def make_recuerdos():
    """Galeria - ~40 s. Memory music-box: high-octave KS, tender-variant
    progression, no drums - just shaker breath and soft bass."""
    bpm = 60.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    bars = 10                  # 40 s
    mix = mm.Mix(bars * bar)
    prog = [mm.AM, mm.F, mm.C, mm.G,
            mm.AM, mm.EM, mm.F, mm.G,
            mm.AM, mm.C]
    # original music-box melody (high, gentle)
    mel = [[76, 79, 84, 79], [77, 81, 77, 74],
           [76, 79, 76, 72], [74, 76, 79, 76],
           [81, 79, 76, 79], [76, 74, 71, 74],
           [77, 81, 84, 81], [79, 83, 79, 76],
           [84, 81, 79, 76], [72, None, None, None]]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # soft bass root
        mix.add(mm.ks(mm.mtof(chord[0]), 2.0, damp=0.996), t, 0.26)
        # music-box melody (bright, long decay)
        for k, m in enumerate(mel[b]):
            if m is not None:
                mix.add(mm.ks(mm.mtof(m), 2.6, damp=0.9982),
                        t + k * beat, 0.22)
        # shaker breath
        for e in range(8):
            mix.add(mm.tick(), t + e * beat * 0.5, 0.10)
    mm.finalize(mix, bars * bar, "recuerdos")


def make_ofrenda():
    """Tu Ofrenda finale - ~44 s. Builds solo guitar -> full band;
    final bar holds a swell-ready tonic chord (the reveal moment)."""
    bpm = 100.0
    beat = 60.0 / bpm          # 0.6 s
    bar = 4.0 * beat           # 2.4 s
    bars = 18                  # 43.2 s
    mix = mm.Mix(bars * bar)
    prog = ([mm.AM, mm.F, mm.C, mm.G] * 2
            + [mm.F, mm.EM, mm.DM, mm.G]
            + [mm.AM, mm.F, mm.C, mm.G,
               mm.AM, mm.CL])
    # original rising melody (trumpet joins at bar 6)
    mel = [
        [64, None, 67, None], [65, None, 69, None],
        [67, None, 64, None], [62, None, None, None],
        [64, None, 67, None], [69, 72, 74, 72],
        [76, 74, 72, 74], [76, 79, 76, 74],
        [72, 76, 79, 76], [77, 81, 79, 77],
        [76, 79, 81, 79], [76, 74, 72, 74],
        [76, 79, 81, 84], [83, 81, 79, 76],
        [77, 81, 83, 81], [79, 76, 74, 76],
        [72, 76, 79, 84], [72, None, None, None],
    ]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        full = b >= 6            # band joins at bar 6
        # guitar throughout, fuller after bar 6
        mm.strum(mix, chord, t, dur=1.8, damp=0.9945,
                 gain=0.50 if full else 0.40)
        mm.strum(mix, chord, t + 2 * beat, dur=1.4, damp=0.9945,
                 gain=0.40 if full else 0.30)
        mix.add(mm.ks(mm.mtof(chord[0]), 1.4, damp=0.995), t, 0.34)
        # drums join at bar 6
        if full:
            mix.add(mm.membrane(150, 55, 0.35), t, 0.90)
            mix.add(mm.membrane(135, 52, 0.30), t + 2 * beat, 0.75)
            mix.add(mm.slap(), t + beat, 0.38)
            mix.add(mm.slap(), t + 3 * beat, 0.34)
            for e in range(8):
                mix.add(mm.tick(), t + e * beat * 0.5,
                        0.26 if e % 2 == 0 else 0.18)
        # melody: soft KS for bars 0-5, trumpet from bar 6
        for k, m in enumerate(mel[b]):
            if m is None:
                continue
            if full:
                mix.add(mm.trumpet(mm.mtof(m), beat * 0.9, gain=0.46),
                        t + k * beat)
            else:
                mix.add(mm.ks(mm.mtof(m), 1.8, damp=0.997), t + k * beat,
                        0.20)
        # final bar: held tonic chord (swell-ready reveal)
        if b == bars - 1:
            mm.strum(mix, mm.CL, t, dur=2.2, damp=0.996, gain=0.55)
            mix.add(mm.trumpet(mm.mtof(72), 2.0, gain=0.40), t)
    mm.finalize(mix, bars * bar, "ofrenda")


if __name__ == "__main__":
    import time
    t0 = time.time()
    for name, fn in [
        ("menu", make_menu), ("puente", make_puente),
        ("alebrijes", make_alebrijes), ("papel", make_papel),
        ("baile", make_baile), ("magia", make_magia),
        ("cancion", make_cancion), ("espejo", make_espejo),
        ("recuerdos", make_recuerdos), ("ofrenda", make_ofrenda),
    ]:
        t1 = time.time()
        fn()
        print("  %s rendered in %.1fs" % (name, time.time() - t1))
    print("done in %.1fs total" % (time.time() - t0))
