#!/usr/bin/env python3
"""MARIGOLD v0.7.0 - full SFX + ambience-bed pack.

wade's no-placeholders order: every chapter gets complete SFX. All content
100% synthesized (numpy, filtered noise + Karplus-Strong + formant-ish
vocalise). 22050 Hz 16-bit mono.

One-shots (sfx_*.wav, via MarigoldMusic.play_sfx):
  ui_select, ui_hover, ui_back      - menu UI
  camera_shutter                    - diegetic folk camera (photos.gd)
  candle_ignite                     - progressive candle lighting (ofrenda finale)
  chapter_fanfare                   - chapter-complete celebration
  bell_toll                         - flight landmark church bell
  crowd_cheer                       - dance crowd swell (ch5 energy)
  petal_rustle                      - teleport landing poof
  spirit_greet, spirit_farewell     - original vocalise motifs (bower calavera)

Ambience beds (amb_*.wav, looped via MarigoldMusic.play_ambience):
  amb_night    - ch1: night crickets + distant owl
  amb_water    - ch2: gentle water lapping
  amb_plaza    - ch3: plaza murmur + distant band
  amb_canopy   - ch4: wind + papel flutter
  amb_dance    - ch5: dance crowd bed + feet shuffle
  amb_gallery  - galeria: quiet room tone
Run: python3 tools/make_sfx_v070.py
"""
import os
import wave
import math
import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(20261012)


def write_wav(path, samples):
    samples = np.clip(samples, -1.0, 1.0)
    data = (samples * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote", path, "%.2fs" % (len(samples) / RATE))


def normalize(x, peak_db=-3.0):
    peak = np.max(np.abs(x)) + 1e-9
    return x * (10.0 ** (peak_db / 20.0) / peak)


def seamless(x, fade=2048):
    y = x.copy()
    tail = y[-fade:].copy()
    ramp = np.linspace(0.0, 1.0, fade)
    y[:fade] = y[:fade] * ramp + tail * (1.0 - ramp)
    return y


def one_pole_lp(x, alpha):
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def mtof(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


def ks(freq, dur, damp=0.996, gain=0.5):
    """Karplus-Strong pluck."""
    n = int(dur * RATE)
    N = max(2, int(round(RATE / freq)))
    line = rng.uniform(-1.0, 1.0, N)
    out = np.zeros(n)
    idx = 0
    d = damp * 0.5
    for i in range(n):
        cur = line[idx]
        nxt = line[(idx + 1) % N]
        line[idx] = (cur + nxt) * d
        out[i] = cur
        idx = (idx + 1) % N
    return out * gain


def vocalise(midis, note_dur=0.42, gap=0.06):
    """Original non-verbal 'spirit voice': formant-ish hummed ahh phrases.
    Sum-of-harmonics with slow attack, 5 Hz vibrato, breath noise."""
    total = len(midis) * (note_dur + gap)
    n = int(total * RATE)
    out = np.zeros(n)
    for k, m in enumerate(midis):
        f = mtof(m)
        nn = int(note_dur * RATE)
        t = np.arange(nn) / RATE
        vib = 1.0 + 0.008 * np.sin(2 * np.pi * 5.0 * t)
        ph = np.cumsum(f * vib) / RATE
        # formant-ish: emphasize 800 Hz and 1200 Hz regions
        sig = (np.sin(2 * np.pi * ph) * 0.5
               + np.sin(4 * np.pi * ph) * 0.28
               + np.sin(6 * np.pi * ph) * 0.16
               + np.sin(8 * np.pi * ph) * 0.08)
        env = np.minimum(1.0, t / 0.08) * np.exp(-t * 2.2)
        breath = rng.standard_normal(nn) * 0.03
        seg = (sig * env + breath * env) * 0.5
        s = int(k * (note_dur + gap) * RATE)
        out[s:s + nn] += seg
    return out


# ============================================================ one-shots

def sfx_ui_select():
    # soft wooden click + warm KS pluck
    n = int(0.25 * RATE)
    out = np.zeros(n)
    click = rng.standard_normal(int(0.015 * RATE)) * np.exp(
        -np.arange(int(0.015 * RATE)) / RATE * 120.0) * 0.5
    out[:len(click)] += click
    pl = ks(mtof(72), 0.22, damp=0.994, gain=0.45)
    out[:len(pl)] += pl
    return out


def sfx_ui_hover():
    # feather-soft tick
    n = int(0.07 * RATE)
    t = np.arange(n) / RATE
    return rng.standard_normal(n) * np.exp(-t * 140.0) * 0.22


def sfx_ui_back():
    # descending two-note wooden knock
    n = int(0.30 * RATE)
    out = np.zeros(n)
    for i, m in enumerate([67, 62]):
        pl = ks(mtof(m), 0.2, damp=0.993, gain=0.4)
        s = int(i * 0.09 * RATE)
        out[s:s + len(pl)] += pl
    return out


def sfx_camera_shutter():
    # mechanical two-click shutter
    n = int(0.30 * RATE)
    out = np.zeros(n)
    for i, (f, g) in enumerate([(3200, 0.5), (2400, 0.4)]):
        nn = int(0.025 * RATE)
        t = np.arange(nn) / RATE
        click = (rng.standard_normal(nn) * np.exp(-t * 160.0)
                 + np.sin(2 * np.pi * f * t) * np.exp(-t * 120.0) * 0.5) * g
        s = int(i * 0.09 * RATE)
        out[s:s + nn] += click
    return out


def sfx_candle_ignite():
    # match strike + flame whoosh bloom
    n = int(0.9 * RATE)
    out = np.zeros(n)
    nn = int(0.12 * RATE)
    t = np.arange(nn) / RATE
    strike = one_pole_lp(rng.standard_normal(nn), 0.25) * np.exp(-t * 40.0)
    out[:nn] += strike * 0.7
    fl = int(0.7 * RATE)
    ft = np.arange(fl) / RATE
    flame = one_pole_lp(rng.standard_normal(fl), 0.08)
    flame *= np.minimum(1.0, ft / 0.25) * np.exp(-ft * 2.5)
    s = int(0.10 * RATE)
    out[s:s + fl] += flame * 0.35
    # warm bloom chord (major, soft)
    for k, m in enumerate([60, 64, 67]):
        pl = ks(mtof(m), 0.6, damp=0.998, gain=0.22)
        ss = s + int(k * 0.04 * RATE)
        out[ss:ss + len(pl)] += pl
    return out


def sfx_chapter_fanfare():
    # celebration: mariachi-ish stab + crowd cheer swell + bell
    n = int(2.2 * RATE)
    out = np.zeros(n)
    # brass-ish stab (major chord, summed saws)
    for m in [60, 64, 67, 72]:
        f = mtof(m)
        nn = int(0.9 * RATE)
        t = np.arange(nn) / RATE
        ph = np.cumsum(np.full(nn, f)) / RATE
        saw = sum(np.sin(2 * np.pi * ph * k) / k for k in range(1, 6)) * 0.2
        env = np.minimum(1.0, t / 0.06) * np.exp(-t * 3.0)
        out[:nn] += saw * env * 0.5
    # crowd cheer swell: bandpassed noise, swell then settle
    t = np.arange(n) / RATE
    crowd = one_pole_lp(rng.standard_normal(n), 0.12)
    swell = np.sin(np.pi * np.clip(t / 2.2, 0, 1)) ** 1.5
    out += crowd * swell * 0.30
    # bell accent
    bell = ks(mtof(84), 1.6, damp=0.9992, gain=0.35)
    out[:len(bell)] += bell
    return out


def sfx_bell_toll():
    # low church bell: long decay, slight detune pair
    n = int(3.0 * RATE)
    out = ks(mtof(48), 3.0, damp=0.9995, gain=0.5)
    out += ks(mtof(48) * 1.005, 3.0, damp=0.9995, gain=0.3)[:n]
    return out


def sfx_crowd_cheer():
    # dance crowd swell, 3 s
    n = int(3.0 * RATE)
    t = np.arange(n) / RATE
    crowd = one_pole_lp(rng.standard_normal(n), 0.10)
    swell = np.sin(np.pi * np.clip(t / 3.0, 0, 1)) ** 1.2
    # whistle streaks
    for _ in range(5):
        f0 = rng.uniform(1800, 2600)
        nn = int(rng.uniform(0.2, 0.5) * RATE)
        tt = np.arange(nn) / RATE
        f = f0 + 400 * np.sin(2 * np.pi * 3 * tt)
        ph = np.cumsum(f) / RATE
        seg = np.sin(2 * np.pi * ph) * np.exp(-tt * 4.0) * 0.12
        s = int(rng.uniform(0, 2.2) * RATE)
        e = min(s + nn, n)
        crowd[s:e] += seg[:e - s]
    return crowd * swell * 0.6


def sfx_petal_rustle():
    # soft petal poof: airy filtered noise puff
    n = int(0.45 * RATE)
    t = np.arange(n) / RATE
    nz = one_pole_lp(rng.standard_normal(n), 0.30)
    env = np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2
    chime = ks(mtof(79), 0.4, damp=0.998, gain=0.25)
    out = nz * env * 0.45
    out[:len(chime)] += chime
    return out


# ============================================================ ambience beds

def amb_night():
    # 8 s loop: night crickets + distant owl
    n = RATE * 8
    t = np.arange(n) / RATE
    out = np.zeros(n)
    # cricket chirps: 4.2 kHz pulsed trills
    for _ in range(26):
        f = rng.uniform(4000, 4400)
        nn = int(rng.uniform(0.08, 0.2) * RATE)
        tt = np.arange(nn) / RATE
        pulse = (np.sin(2 * np.pi * 30 * tt) > 0).astype(float)
        seg = np.sin(2 * np.pi * f * tt) * pulse * np.exp(-tt * 8.0) * 0.10
        s = int(rng.uniform(0, 7.5) * RATE)
        e = min(s + nn, n)
        out[s:e] += seg[:e - s]
    # distant owl: two soft hoots
    for hs in (2.0, 5.5):
        for i, f in enumerate([340, 300]):
            nn = int(0.35 * RATE)
            tt = np.arange(nn) / RATE
            hoot = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 6.0) * 0.12
            s = int((hs + i * 0.4) * RATE)
            out[s:s + nn] += hoot
    return seamless(out * 0.8)


def amb_water():
    # 8 s loop: gentle water lapping
    n = RATE * 8
    t = np.arange(n) / RATE
    base = one_pole_lp(rng.standard_normal(n), 0.10)
    lap_lfo = 0.6 + 0.4 * np.sin(2 * np.pi * 0.35 * t + 1.0)
    lap2 = 0.6 + 0.4 * np.sin(2 * np.pi * 0.53 * t)
    return seamless(base * lap_lfo * lap2 * 0.55)


def amb_plaza():
    # 8 s loop: plaza murmur + distant band
    n = RATE * 8
    t = np.arange(n) / RATE
    murmur = one_pole_lp(rng.standard_normal(n), 0.06) * 0.30
    # distant band: faint trumpet-ish phrase, lowpassed
    band = np.zeros(n)
    for k, m in enumerate([72, 76, 79, 76, 74, 72]):
        f = mtof(m)
        nn = int(0.5 * RATE)
        tt = np.arange(nn) / RATE
        seg = (np.sin(2 * np.pi * f * tt) * 0.5
               + np.sin(4 * np.pi * f * tt) * 0.2) * np.exp(-tt * 2.0)
        s = int(k * 0.9 * RATE)
        band[s:s + nn] += seg * 0.06
    return seamless((murmur + band) * 0.9)


def amb_canopy():
    # 8 s loop: wind + papel flutter
    n = RATE * 8
    t = np.arange(n) / RATE
    wind = one_pole_lp(rng.standard_normal(n), 0.05)
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * 0.2 * t)
    # paper flutters: short bright rustle bursts on gusts
    flutter = np.zeros(n)
    for _ in range(18):
        nn = int(rng.uniform(0.1, 0.3) * RATE)
        tt = np.arange(nn) / RATE
        seg = one_pole_lp(rng.standard_normal(nn), 0.5) * np.exp(-tt * 10.0)
        s = int(rng.uniform(0, 7.5) * RATE)
        e = min(s + nn, n)
        flutter[s:e] += seg[:e - s] * 0.25
    return seamless(wind * gust * 0.5 + flutter)


def amb_dance():
    # 8 s loop: dance crowd bed + feet shuffle
    n = RATE * 8
    t = np.arange(n) / RATE
    crowd = one_pole_lp(rng.standard_normal(n), 0.08) * 0.28
    # feet shuffle: periodic soft thuds (dance beat ~120 BPM)
    for k in range(16):
        nn = int(0.12 * RATE)
        tt = np.arange(nn) / RATE
        thud = np.sin(2 * np.pi * 90 * tt) * np.exp(-tt * 30.0) * 0.20
        s = int(k * 0.5 * RATE)
        crowd[s:s + nn] += thud
    return seamless(crowd)


def amb_gallery():
    # 8 s loop: quiet room tone (very soft air + faint distant chime)
    n = RATE * 8
    t = np.arange(n) / RATE
    air = one_pole_lp(rng.standard_normal(n), 0.03) * 0.12
    chime = ks(mtof(88), 3.0, damp=0.9995, gain=0.06)
    s = int(3.0 * RATE)
    air[s:s + len(chime)] += chime
    return seamless(air)


SPECS_ONE = [
    ("sfx_ui_select", sfx_ui_select), ("sfx_ui_hover", sfx_ui_hover),
    ("sfx_ui_back", sfx_ui_back),
    ("sfx_camera_shutter", sfx_camera_shutter),
    ("sfx_candle_ignite", sfx_candle_ignite),
    ("sfx_chapter_fanfare", sfx_chapter_fanfare),
    ("sfx_bell_toll", sfx_bell_toll),
    ("sfx_crowd_cheer", sfx_crowd_cheer),
    ("sfx_petal_rustle", sfx_petal_rustle),
]

SPECS_VOICE = [
    # original vocalise motifs (pentatonic, non-verbal)
    ("sfx_spirit_greet", lambda: vocalise([69, 72, 74, 76, 74, 72])),
    ("sfx_spirit_farewell", lambda: vocalise([76, 74, 72, 69, 67])),
]

SPECS_AMB = [
    ("amb_night", amb_night), ("amb_water", amb_water),
    ("amb_plaza", amb_plaza), ("amb_canopy", amb_canopy),
    ("amb_dance", amb_dance), ("amb_gallery", amb_gallery),
]


def main():
    for stem, fn in SPECS_ONE + SPECS_VOICE:
        write_wav(os.path.join(OUT, stem + ".wav"), normalize(fn()))
    for stem, fn in SPECS_AMB:
        write_wav(os.path.join(OUT, stem + ".wav"), normalize(fn(), -9.0))


if __name__ == "__main__":
    main()
