#!/usr/bin/env python3
"""make_weather_audio.py - synthesize original weather ambience for MARIGOLD v0.4.0.

All content is 100% synthesized from filtered noise: no samples, no licensed assets.
Outputs 16-bit mono 22050 Hz WAV files into ../assets/audio/:
  rain.wav    - 4s seamless loop, filtered noise patter with droplet modulation
  wind.wav    - 8s seamless loop, lowpassed noise with slow LFO swell
  thunder.wav - 3.5s one-shot, lowpassed noise burst + sub-rumble decay
"""
import os
import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(20261008)


def write_wav(path, samples):
    samples = np.clip(samples, -1.0, 1.0)
    data = (samples * 32767.0).astype("<i2")
    import wave
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote", path, f"{len(samples)/RATE:.2f}s")


def one_pole_lowpass(x, alpha):
    """Simple one-pole lowpass (alpha near 1 = darker)."""
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def seamless(x, fade=2048):
    """Crossfade tail into head so the loop is click-free."""
    y = x.copy()
    tail = y[-fade:].copy()
    ramp = np.linspace(0.0, 1.0, fade)
    y[:fade] = y[:fade] * ramp + tail * (1.0 - ramp)
    return y


# ---- rain: 4s loop ----
def make_rain():
    n = RATE * 4
    noise = rng.standard_normal(n)
    # Bright patter: highpassed-ish noise (differentiate + mild lowpass).
    patter = np.diff(noise, prepend=noise[-1])
    patter = one_pole_lowpass(patter, 0.55)
    # Droplet amplitude modulation: random droplet envelope, periodic over 4s.
    t = np.arange(n) / RATE
    mod = np.ones(n)
    drop_times = rng.uniform(0, 4.0, 220)
    drop_decay = rng.uniform(30.0, 90.0, 220)
    for dt, dd in zip(drop_times, drop_decay):
        mod += 0.9 * np.exp(-((t - dt) % 4.0) * dd)
    # Periodic slow swell (whole cycles in 4s -> seamless).
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * t / 4.0 * 2 + 1.0)
    rain = patter * mod * swell
    rain *= 0.5 / max(1e-6, np.abs(rain).max())
    return seamless(rain)


# ---- wind: 8s loop ----
def make_wind():
    n = RATE * 8
    noise = rng.standard_normal(n)
    # Deep whoosh body: heavy lowpass.
    body = one_pole_lowpass(noise, 0.03)
    # Airy top layer: band-ish (lowpass minus deeper lowpass).
    airy = one_pole_lowpass(noise, 0.12) - body
    t = np.arange(n) / RATE
    # Slow LFO swell, whole cycles in 8s (no whistling: only sub-0.5Hz LFOs).
    lfo = (0.55 + 0.30 * np.sin(2 * np.pi * t / 8.0)
           + 0.15 * np.sin(2 * np.pi * t / 4.0 + 0.7))
    wind = (body * 1.2 + airy * 0.25) * lfo
    wind *= 0.55 / max(1e-6, np.abs(wind).max())
    return seamless(wind)


# ---- thunder: 3.5s one-shot ----
def make_thunder():
    n = int(RATE * 3.5)
    noise = rng.standard_normal(n)
    t = np.arange(n) / RATE
    # Sub-rumble: very dark lowpass of noise with exponential decay.
    rumble = one_pole_lowpass(noise, 0.012)
    decay = np.exp(-t * 2.2)
    # Initial crack: brighter burst decaying fast.
    crack = one_pole_lowpass(noise, 0.25) * np.exp(-t * 14.0)
    # A couple of delayed rolling echoes.
    echo = one_pole_lowpass(noise, 0.02)
    echo *= 0.5 * np.exp(-np.clip(t - 0.9, 0, None) * 3.0) * (t > 0.9)
    thunder = rumble * decay * 1.4 + crack * 0.9 + echo
    # Soft attack ramp to avoid a click at t=0.
    ramp = min(RATE // 20, n)
    thunder[:ramp] *= np.linspace(0.0, 1.0, ramp)
    thunder *= 0.85 / max(1e-6, np.abs(thunder).max())
    return thunder


def main():
    os.makedirs(OUT, exist_ok=True)
    write_wav(os.path.join(OUT, "rain.wav"), make_rain())
    write_wav(os.path.join(OUT, "wind.wav"), make_wind())
    write_wav(os.path.join(OUT, "thunder.wav"), make_thunder())


if __name__ == "__main__":
    main()
