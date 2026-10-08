#!/usr/bin/env python3
"""
MARIGOLD original procedural score synthesizer.

Generates 4 seamless-looping WAV files (22050 Hz, 16-bit mono) into
../assets/audio/ using only the Python standard library.

ALL MUSIC IS 100% ORIGINAL - simple folk-inspired progressions and
melodies composed for this script. No copyrighted material.

Voices:
  - Karplus-Strong plucked string (noise burst -> feedback delay line)
  - Trumpet-ish lead (summed sawtooth harmonics, slow attack, 5.5 Hz
    vibrato, slight breath noise)
  - Hand drum (sine burst with exponential pitch drop = membrane,
    plus filtered-noise slap)
  - Shaker (short bandpassed noise ticks)
"""
import wave
import struct
import math
import random
import os

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "assets", "audio")

random.seed(20261006)


def mtof(midi):
    """Equal-temperament frequency for a MIDI note number."""
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


class Mix:
    def __init__(self, seconds):
        self.buf = [0.0] * int(seconds * SR)

    def add(self, sig, start_sec, gain=1.0):
        b = self.buf
        s = int(start_sec * SR)
        if s >= len(b):
            return
        n = len(sig)
        end = s + n
        if end > len(b):
            end = len(b)
        g = gain
        for i in range(s, end):
            b[i] += sig[i - s] * g


# ---------------------------------------------------------------- voices

def ks(freq, dur, damp=0.996, fade_in=0.003):
    """Karplus-Strong plucked string. damp controls brightness/decay."""
    n = int(dur * SR)
    if n <= 0:
        return []
    N = max(2, int(round(SR / freq)))
    line = [random.uniform(-1.0, 1.0) for _ in range(N)]
    out = [0.0] * n
    idx = 0
    d = damp * 0.5
    for i in range(n):
        cur = line[idx]
        nxt = line[idx + 1] if idx + 1 < N else line[0]
        line[idx] = (cur + nxt) * d
        out[i] = cur
        idx += 1
        if idx >= N:
            idx = 0
    fi = max(1, int(fade_in * SR))
    if fi < n:
        for i in range(fi):
            out[i] *= i / fi
    return out


def trumpet(freq, dur, gain=1.0, vib_rate=5.5, vib_amt=0.006):
    """Trumpet-ish: summed sawtooth harmonics, slow attack, vibrato,
    slight breath noise."""
    n = int(dur * SR)
    if n <= 0:
        return []
    out = [0.0] * n
    phase = 0.0
    vphase = 0.0
    inc = freq / SR
    atk = max(1, int(0.09 * SR))
    rel = max(1, int(0.15 * SR))
    vib_step = 2.0 * math.pi * vib_rate / SR
    twopi = 2.0 * math.pi
    # harmonic amplitudes (1/k) scaled
    h = (1.0, 0.5, 0.33, 0.25, 0.2, 0.16, 0.14, 0.12)
    for i in range(n):
        vphase += vib_step
        phase += inc * (1.0 + vib_amt * math.sin(vphase))
        p = phase * twopi
        s = (math.sin(p) + math.sin(p * 2) * h[1] + math.sin(p * 3) * h[2]
             + math.sin(p * 4) * h[3] + math.sin(p * 5) * h[4]
             + math.sin(p * 6) * h[5] + math.sin(p * 7) * h[6]
             + math.sin(p * 8) * h[7]) * 0.45
        if i < atk:
            e = i / atk
        elif i >= n - rel:
            e = (n - i) / rel
        else:
            e = 1.0
        out[i] = (s + random.uniform(-1.0, 1.0) * 0.015) * e * gain
    return out


def membrane(f0=160.0, f1=55.0, dur=0.35):
    """Hand-drum membrane: sine burst with exponential pitch drop."""
    n = int(dur * SR)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = f1 + (f0 - f1) * math.exp(-t * 22.0)
        ph += f / SR
        out[i] = math.sin(2.0 * math.pi * ph) * math.exp(-t * 11.0)
    return out


def slap(dur=0.12):
    """Hand-drum slap: highpassed noise burst."""
    n = int(dur * SR)
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1.0, 1.0)
        lp += 0.35 * (x - lp)
        out[i] = (x - lp) * math.exp(-t * 45.0)
    return out


def tick(dur=0.05):
    """Shaker tick: short bandpassed-ish noise tick."""
    n = int(dur * SR)
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1.0, 1.0)
        lp += 0.12 * (x - lp)
        out[i] = (x - lp) * math.exp(-t * 90.0)
    return out


def strum(mix, chord, t, dur=0.9, damp=0.9945, gain=0.5):
    """Strummed KS chord: notes staggered by 12 ms."""
    n = len(chord)
    g = gain / math.sqrt(n)
    for k, m in enumerate(chord):
        mix.add(ks(mtof(m), dur, damp), t + k * 0.012, g)


# ---------------------------------------------------------------- output

def finalize(mix, seconds, name):
    """50 ms tail-into-head loop crossfade, normalize to -3 dB, write WAV."""
    b = mix.buf
    total = len(b)
    xf = int(0.05 * SR)
    tail = b[total - xf:]
    for i in range(xf):
        w = i / xf
        b[i] += tail[i] * w * 0.9
        b[total - xf + i] *= (1.0 - w)
    peak = max(max(b), -min(b), 1e-9)
    target = 10.0 ** (-3.0 / 20.0)  # -3 dB
    s = target / peak
    frames = struct.pack("<%dh" % total,
                         *[int(max(-32768, min(32767, v * s * 32767)))
                           for v in b])
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(frames)
    size = os.path.getsize(path)
    print("wrote %s: %.1fs, %d bytes (%.2f MB), peak-normalized to -3 dB"
          % (path, total / SR, size, size / 1048576.0))


# ============================================================ compositions
# All progressions and melodies below are original, composed for MARIGOLD.

# Chord voicings (MIDI), original folk-inspired choices.
AM = [45, 52, 57, 60, 64]   # A2 E3 A3 C4 E4
F  = [41, 48, 53, 57, 60]   # F2 C3 F3 A3 C4
C  = [48, 55, 60, 64, 67]   # C3 G3 C4 E4 G4
G  = [43, 50, 55, 59, 62]   # G2 D3 G3 B3 D4
EM = [40, 47, 52, 55, 59]   # E2 B2 E3 G3 B3
DM = [38, 45, 50, 53, 57]   # D2 A2 D3 F3 A3
D4 = [38, 50, 54, 57]       # D2 D3 F#3 A3
G4 = [43, 50, 55, 59]       # G2 D3 G3 B3
C4 = [48, 55, 60, 64]       # C3 G3 C4 E4
EM4 = [40, 47, 52, 55]      # E2 B2 E3 G3
CL = [36, 48, 55, 60, 64]   # C2 C3 G3 C4 E4 (low C for finale)


def make_tender():
    """~48 s. Slow gentle KS arpeggios, original Am-F-C-G cycle, sparse
    soft melody. Feel: quiet remembrance."""
    bpm = 60.0
    beat = 60.0 / bpm          # 1.0 s
    bar = 4.0 * beat           # 4.0 s
    bars = 12                  # 48 s
    mix = Mix(bars * bar)
    prog = [AM, F, C, G] * 3
    # sparse original melody, one soft note per bar
    melody = [76, 79, 81, 79, 76, 72, 74, 76, 79, 81, 79, 76]
    arp_idx = [0, 1, 2, 3, 4, 3, 2, 1]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        for k, ci in enumerate(arp_idx):
            mix.add(ks(mtof(chord[ci]), 1.6, damp=0.9965),
                    t + k * beat * 0.5, 0.30)
        mix.add(ks(mtof(melody[b]), 3.0, damp=0.997),
                t, 0.16)
    finalize(mix, bars * bar, "tender")


def make_wondrous():
    """~48 s. Brighter KS arpeggios + high shimmer plucks playing an
    original melody. Feel: wonder, first sight of the Land of the Dead."""
    bpm = 70.0
    beat = 60.0 / bpm
    bar = 4.0 * beat           # 24/7 s
    bars = 14                  # 48.0 s
    mix = Mix(bars * bar)
    prog = [C, EM, F, G,
            C, EM, F, G,
            AM, F, DM, G,
            G, C]
    # original shimmer melody: two high notes per bar (beats 1 & 3)
    pairs = [(76, 79), (81, 79), (84, 81), (79, 77),
             (76, 79), (83, 81), (84, 81), (79, 76),
             (81, 84), (81, 77), (81, 79), (83, 79),
             (74, 79), (72, None)]
    arp_idx = [0, 1, 2, 3, 4, 3, 2, 3]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        for k, ci in enumerate(arp_idx):
            mix.add(ks(mtof(chord[ci]), 1.1, damp=0.9972),
                    t + k * beat * 0.5, 0.26)
        m1, m2 = pairs[b]
        mix.add(ks(mtof(m1), 1.6, damp=0.9975), t, 0.20)
        if m2 is not None:
            mix.add(ks(mtof(m2), 1.6, damp=0.9975), t + 2 * beat, 0.17)
    finalize(mix, bars * bar, "wondrous")


def make_festive():
    """~40 s. Lively strummed KS guitar in 6/8 (original rhythm),
    membrane hand drum + slap + shaker. Feel: danceable fiesta."""
    eighth = 0.24
    bar = 6 * eighth           # 1.44 s
    bars = 28                  # 40.32 s
    mix = Mix(bars * bar)
    prog = ([G4, G4, C4, C4, G4, G4, D4, D4] * 2
            + [EM4, EM4, C4, C4, G4, D4, G4, G4]
            + [C4, G4, D4, G4])
    pluck_idx = [1, 2, 3, 2]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # strums on the two main 6/8 beats (eighths 0 and 3)
        strum(mix, chord, t, dur=0.8, damp=0.994, gain=0.50)
        strum(mix, chord, t + 3 * eighth, dur=0.7, damp=0.994, gain=0.40)
        # light inner plucks on eighths 1, 2, 4, 5
        for k, e in enumerate((1, 2, 4, 5)):
            ci = pluck_idx[k]
            mix.add(ks(mtof(chord[ci]), 0.35, damp=0.995),
                    t + e * eighth, 0.18)
        # hand drum: membrane thumps on 0 and 3, slaps on 2 and 5
        mix.add(membrane(150, 55, 0.35), t, 0.90)
        mix.add(membrane(130, 52, 0.30), t + 3 * eighth, 0.75)
        mix.add(slap(), t + 2 * eighth, 0.35)
        mix.add(slap(), t + 5 * eighth, 0.30)
        # shaker on every eighth, accents on the main beats
        for e in range(6):
            g = 0.30 if e in (0, 3) else 0.20
            mix.add(tick(), t + e * eighth, g)
    finalize(mix, bars * bar, "festive")


def make_finale():
    """~52 s. Fullest arrangement: strummed guitar + trumpet-ish lead
    playing an ORIGINAL celebratory melody + drums + shaker.
    Feel: triumphant homecoming."""
    bpm = 120.0
    beat = 60.0 / bpm          # 0.5 s
    bar = 4.0 * beat           # 2.0 s
    bars = 26                  # 52 s
    mix = Mix(bars * bar)
    prog = ([CL, AM, F, G] * 4
            + [F, EM, DM, G] * 2
            + [G, CL])
    # original celebratory trumpet melody: 4 quarter notes per bar
    # (bar 26 = one held tonic)
    lead = [
        [72, 76, 79, 76], [76, 81, 79, 76], [77, 81, 84, 81],
        [79, 83, 81, 79], [84, 79, 76, 79], [81, 76, 74, 76],
        [77, 81, 77, 74], [79, 74, 79, 83], [84, 83, 81, 79],
        [81, 79, 76, 74], [84, 81, 77, 81], [83, 79, 81, 83],
        [84, 79, 84, 79], [81, 79, 81, 76], [77, 81, 79, 77],
        [79, 83, 86, 83], [81, 77, 81, 84], [83, 79, 76, 79],
        [81, 77, 74, 77], [79, 83, 79, 74], [81, 77, 84, 81],
        [79, 76, 79, 83], [81, 79, 77, 74], [79, 83, 86, 83],
        [79, 81, 83, 79], [84, None, None, None],
    ]
    for b in range(bars):
        chord = prog[b]
        t = b * bar
        # strummed guitar on beats 1 and 3
        strum(mix, chord, t, dur=1.6, damp=0.9945, gain=0.50)
        strum(mix, chord, t + 2 * beat, dur=1.2, damp=0.9945, gain=0.38)
        # bass root pluck on beat 1
        mix.add(ks(mtof(chord[0]), 1.2, damp=0.995), t, 0.35)
        # light chord plucks on beats 2 and 4
        mix.add(ks(mtof(chord[2]), 0.4, damp=0.995),
                t + beat, 0.16)
        mix.add(ks(mtof(chord[3]), 0.4, damp=0.995),
                t + 3 * beat, 0.16)
        # drums: membrane on 1 & 3, slap on 2 & 4
        mix.add(membrane(150, 55, 0.35), t, 0.95)
        mix.add(membrane(135, 52, 0.30), t + 2 * beat, 0.80)
        mix.add(slap(), t + beat, 0.40)
        mix.add(slap(), t + 3 * beat, 0.35)
        # shaker on eighth notes, accents on quarters
        for e in range(8):
            g = 0.28 if e % 2 == 0 else 0.20
            mix.add(tick(), t + e * beat * 0.5, g)
        # trumpet lead
        notes = lead[b]
        if b == bars - 1:
            mix.add(trumpet(mtof(notes[0]), 1.9, gain=0.5), t)
        else:
            for k, m in enumerate(notes):
                mix.add(trumpet(mtof(m), beat * 0.92, gain=0.5),
                        t + k * beat)
    finalize(mix, bars * bar, "finale")


# ============================================================ stingers (v0.6.0)
# One-shot SFX for the character face system. All original, <1.2 s each.

def finalize_oneshot(mix, seconds, name):
    """No loop crossfade; 30 ms fade-out tail; normalize to -3 dB."""
    b = mix.buf
    total = len(b)
    fade = int(0.03 * SR)
    for i in range(fade):
        w = 1.0 - i / fade
        b[total - fade + i] *= w
    peak = max(max(b), -min(b), 1e-9)
    target = 10.0 ** (-3.0 / 20.0)
    s = target / peak
    frames = struct.pack("<%dh" % total,
                         *[int(max(-32768, min(32767, v * s * 32767)))
                           for v in b])
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(frames)
    print("wrote %s: %.2fs, %d bytes" % (path, total / SR, os.path.getsize(path)))


def make_stingers():
    # gasp: crowd inhale swell - filtered-noise rise + soft major chord.
    m = Mix(1.1)
    n = int(0.8 * SR)
    lp = 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1.0, 1.0)
        lp += 0.06 * (x - lp)
        env = math.sin(math.pi * min(1.0, t / 0.8)) ** 1.5
        m.buf[i] += (x - lp) * env * 0.5
    for k, midi in enumerate([60, 64, 67]):  # C4 E4 G4, soft major
        m.add(ks(mtof(midi), 0.9, damp=0.9985), 0.10 + k * 0.05, 0.30)
    finalize_oneshot(m, 1.1, "stinger_gasp")

    # wink: high Karplus-Strong pluck pair E6 -> B6.
    m = Mix(0.7)
    m.add(ks(mtof(88), 0.35, damp=0.996), 0.0, 0.6)
    m.add(ks(mtof(95), 0.45, damp=0.996), 0.14, 0.6)
    finalize_oneshot(m, 0.7, "stinger_wink")

    # greet: warm 3-note folk motif, strummed.
    m = Mix(1.2)
    strum(m, [60, 64, 67, 72], 0.05, dur=1.0, damp=0.996, gain=0.7)
    m.add(membrane(140.0, 70.0, 0.3), 0.0, 0.35)
    finalize_oneshot(m, 1.2, "stinger_greet")

    # bow_drum: low hand-drum + bright chime.
    m = Mix(1.0)
    m.add(membrane(110.0, 48.0, 0.5), 0.0, 0.9)
    m.add(slap(0.10), 0.02, 0.4)
    m.add(ks(mtof(84), 0.8, damp=0.9992), 0.12, 0.45)
    finalize_oneshot(m, 1.0, "stinger_bow_drum")


if __name__ == "__main__":
    make_tender()
    make_wondrous()
    make_festive()
    make_finale()
    make_stingers()
    print("done")
