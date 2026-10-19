#!/usr/bin/env python3
"""Synthesises the promo soundtrack: a soft music bed plus UI sound effects timed to app/promo/Promo.tsx.

Everything is generated from scratch (sines, filtered noise), so there's nothing to license.
Usage: python3 scripts/promo_audio.py out.wav
"""
import sys
import wave

import numpy as np

SR = 48_000
DURATION = 25.0
N = int(SR * DURATION)
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def place(track, sound, at, gain=1.0):
    """Mixes `sound` (mono or stereo) into `track` starting at `at` seconds."""
    start = int(at * SR)
    end = min(len(track), start + len(sound))
    if end > start:
        track[start:end] += sound[: end - start] * gain


def env(n, attack=0.005, release=0.1):
    """Exponential-ish attack/decay envelope over n samples."""
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-t / release)


def lowpass(x, cutoff):
    """One-pole low-pass, enough to soften noise and harsh partials."""
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def note(freq):
    return 440.0 * 2 ** ((freq - 69) / 12)  # MIDI → Hz


# ---------------------------------------------------------------- music bed

def pad_chord(midis, seconds):
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for m in midis:
        f = note(m)
        for detune in (-0.12, 0.12):
            out += np.sin(2 * np.pi * f * (1 + detune / 100) * t) * 0.5
            out += np.sin(2 * np.pi * 2 * f * t) * 0.06
    fade = np.minimum(1, np.minimum(t / 0.6, (seconds - t) / 0.6))
    return out / len(midis) * fade


def pluck(midi, seconds=0.9):
    t = t_axis(seconds)
    f = note(midi)
    tone = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 4 * f * t)
    return tone * env(len(t), 0.003, 0.28)


def kick(seconds=0.35):
    t = t_axis(seconds)
    f = 50 + 70 * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * env(len(t), 0.002, 0.12)


def music():
    track = np.zeros(N)
    bpm = 96
    beat = 60 / bpm
    bar = beat * 4
    # Cmaj9 – Am7 – Fmaj7 – G6sus, warm and unhurried.
    chords = [[48, 55, 59, 62, 64], [45, 52, 55, 60, 64], [41, 48, 52, 57, 60], [43, 50, 55, 57, 62]]
    arps = [[72, 76, 79, 83], [69, 72, 76, 79], [65, 69, 72, 76], [67, 71, 74, 76]]
    t = 0.0
    i = 0
    while t < DURATION:
        place(track, pad_chord(chords[i % 4], bar + 0.3), t, 0.30)
        for k in range(8):  # eighth-note arpeggio
            if 1.0 < t + k * beat / 2 < DURATION - 2:
                place(track, pluck(arps[i % 4][k % 4] + (12 if k == 7 else 0)), t + k * beat / 2, 0.11)
        for k in range(4):  # soft four-on-the-floor once the demo starts
            if 4.8 <= t + k * beat < 20.2:
                place(track, kick(), t + k * beat, 0.32)
        t += bar
        i += 1
    tt = np.arange(N) / SR
    track *= np.clip(tt / 1.2, 0, 1) * np.clip((DURATION - tt) / 2.5, 0, 1)  # fade in/out
    return track


# ---------------------------------------------------------------- sound effects

def bloop(f0=320, f1=880, seconds=0.16):
    t = t_axis(seconds)
    f = f0 + (f1 - f0) * (1 - np.exp(-t / 0.05))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.003, 0.07)


def whoosh(seconds=0.45):
    """Soft air: band-limited noise (≈250 Hz–1.5 kHz, two poles each side) swelling in and out."""
    n = int(SR * seconds)
    noise = rng.standard_normal(n)
    low = lowpass(lowpass(noise, 1500), 1500)
    band = low - lowpass(lowpass(low, 250), 250)
    shape = np.sin(np.linspace(0, np.pi, n)) ** 3
    return band * shape * 0.9


def click():
    n = int(SR * 0.03)
    burst = lowpass(rng.standard_normal(n), 6000) * env(n, 0.0005, 0.006)
    tick = np.sin(2 * np.pi * 2200 * t_axis(0.03)) * env(n, 0.0005, 0.008)
    return burst * 0.6 + tick * 0.5


def key_thock():
    n = int(SR * 0.08)
    body = np.sin(2 * np.pi * 180 * t_axis(0.08)) * env(n, 0.001, 0.02)
    clack = lowpass(rng.standard_normal(n), 3500) * env(n, 0.0005, 0.01)
    return body * 0.8 + clack * 0.5


def wheel_pop():
    base = bloop(520, 780, 0.14)
    shimmer = sum(np.sin(2 * np.pi * f * t_axis(0.5)) * env(int(SR * 0.5), 0.01, 0.15) for f in (1568, 2093, 2637)) / 3
    out = np.zeros(int(SR * 0.5))
    out[: len(base)] += base
    return out + shimmer * 0.25


def hover_tick():
    n = int(SR * 0.025)
    return np.sin(2 * np.pi * 1800 * t_axis(0.025)) * env(n, 0.0005, 0.006)


def bell(midi, seconds=1.2):
    t = t_axis(seconds)
    f = note(midi)
    tone = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / 0.15)
    return tone * env(len(t), 0.002, 0.35)


def drop_success():
    thud_n = int(SR * 0.12)
    thud = np.sin(2 * np.pi * 140 * t_axis(0.12)) * env(thud_n, 0.001, 0.035)
    out = np.zeros(int(SR * 1.5))
    out[:thud_n] += thud * 0.9
    chime_a, chime_b = bell(88), bell(95)  # E6 then B6
    place(out, chime_a, 0.08, 0.45)
    place(out, chime_b, 0.18, 0.4)
    return out


def sfx():
    track = np.zeros(N)
    # 1. Logo
    place(track, bloop(), 0.18, 0.7)
    place(track, whoosh(0.4), 0.55, 0.16)
    # 2. Headline lines
    place(track, whoosh(0.35), 2.6, 0.18)
    place(track, whoosh(0.35), 2.95, 0.18)
    # 3–5. Desktop window, then three drag → key → wheel → hover → drop beats (times match Promo.tsx BEATS)
    place(track, whoosh(0.5), 4.75, 0.18)
    for grab, wheel_in, hover_at, drop in [(6.05, 6.9, 7.85, 8.6), (10.95, 11.7, 12.55, 13.1), (14.75, 15.35, 15.95, 16.4)]:
        place(track, click(), grab, 0.6)
        place(track, key_thock(), wheel_in - 0.06, 0.7)
        place(track, wheel_pop(), wheel_in, 0.55)
        place(track, hover_tick(), hover_at, 0.5)
        place(track, drop_success(), drop, 0.6)
    place(track, whoosh(0.5), 17.25, 0.18)
    # 6. Stats: a pop per number and ticks while 351 counts up
    for at in (18.0, 18.25, 18.5):
        place(track, bloop(400, 700, 0.12), at, 0.45)
    for k, at in enumerate(np.arange(18.05, 19.1, 0.07)):
        place(track, np.sin(2 * np.pi * (900 + k * 60) * t_axis(0.02)) * env(int(SR * 0.02), 0.0005, 0.005), at, 0.25)
    # 7. End card: logo pop, a warm resolving chord, chime as the link appears
    place(track, bloop(300, 900, 0.18), 20.7, 0.7)
    for m in (72, 76, 79, 84):
        place(track, bell(m, 2.6), 20.75, 0.18)
    place(track, bell(91, 1.5), 21.75, 0.35)
    return track


def main(out_path):
    bed, effects = music() * 1.0, sfx() * 0.7
    # Gentle stereo width: the music's right channel lags by 8 ms; effects stay centred.
    lag = int(SR * 0.008)
    left = bed + effects
    right = np.concatenate([np.zeros(lag), bed[:-lag]]) + effects
    stereo = np.stack([left, right], axis=1)
    stereo /= max(1e-9, np.max(np.abs(stereo))) / 0.89  # peak at about −1 dBFS
    pcm = (stereo * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main(sys.argv[1])
