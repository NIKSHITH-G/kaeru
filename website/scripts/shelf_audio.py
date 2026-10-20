#!/usr/bin/env python3
"""Soundtrack for the shelf video (app/shelf-video): the promo's music bed and sound effects, re-timed.

Reuses the synthesis in promo_audio.py, so everything is still generated from scratch.
Usage: python3 scripts/shelf_audio.py out.wav
"""
import importlib.util
import sys
import wave
from pathlib import Path

import numpy as np

spec = importlib.util.spec_from_file_location("promo_audio", Path(__file__).with_name("promo_audio.py"))
pa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pa)

DURATION = 22.0
pa.DURATION = DURATION
pa.N = int(pa.SR * DURATION)
SR, N = pa.SR, pa.N


def shake_swish():
    return pa.whoosh(0.12)


def sfx():
    track = np.zeros(N)
    place = pa.place
    # 1. Hook: a pop for each window, air as "One shelf." lands and the windows gather
    for k in range(3):
        place(track, pa.bloop(420 + k * 120, 760 + k * 120, 0.12), 0.3 + k * 0.25, 0.5)
    place(track, pa.whoosh(0.45), 1.55, 0.2)
    # 2. Title
    place(track, pa.bloop(300, 900, 0.18), 2.5, 0.6)
    for i, m in enumerate((72, 76, 79)):
        place(track, pa.pluck(m, 0.7), 2.65 + i * 0.08, 0.3)
    # 3. Demo window
    place(track, pa.whoosh(0.5), 3.7, 0.18)
    # Grab the invoice, shake, the shelf pops up, drop
    place(track, pa.click(), 4.6, 0.6)
    for at in (5.15, 5.27, 5.39, 5.51, 5.63):
        place(track, shake_swish(), at, 0.12)
    place(track, pa.wheel_pop(), 5.65, 0.6)
    for land in (6.25, 8.65, 10.15):
        place(track, pa.bloop(260, 520, 0.12), land, 0.65)   # the pop of a file landing
        place(track, pa.hover_tick(), land - 0.38, 0.4)        # trackpad tick as it reaches the shelf
    for grab in (7.7, 9.2):
        place(track, pa.click(), grab, 0.6)
    # ✨ → picker → ZIP; the zip arrives with a chime
    place(track, pa.click(), 11.25, 0.6)
    place(track, pa.wheel_pop(), 11.35, 0.55)
    place(track, pa.hover_tick(), 11.95, 0.5)
    place(track, pa.click(), 12.55, 0.5)
    place(track, pa.drop_success(), 12.75, 0.6)
    # Chat slides in; drag the zip over and send
    place(track, pa.whoosh(0.5), 13.55, 0.2)
    place(track, pa.click(), 14.35, 0.6)
    place(track, pa.bloop(500, 1100, 0.14), 15.35, 0.6)
    place(track, pa.bell(91, 0.8), 15.85, 0.25)  # read receipts
    place(track, pa.bloop(700, 980, 0.1), 16.2, 0.4)  # reply arrives
    place(track, pa.whoosh(0.5), 16.95, 0.18)
    # 4. Features: a pop per chip
    for i in range(6):
        place(track, pa.bloop(400 + i * 40, 700 + i * 40, 0.1), 17.6 + i * 0.12, 0.35)
    # 5. End card
    place(track, pa.bloop(300, 900, 0.18), 19.8, 0.7)
    for m in (72, 76, 79, 84):
        place(track, pa.bell(m, 2.2), 19.85, 0.18)
    place(track, pa.bell(91, 1.4), 20.85, 0.35)
    return track


def main(out_path):
    bed, effects = pa.music() * 1.0, sfx() * 0.7
    lag = int(SR * 0.008)
    left = bed + effects
    right = np.concatenate([np.zeros(lag), bed[:-lag]]) + effects
    stereo = np.stack([left, right], axis=1)
    stereo /= max(1e-9, np.max(np.abs(stereo))) / 0.89
    pcm = (stereo * 32767).astype(np.int16)
    with wave.open(out_path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    main(sys.argv[1])
