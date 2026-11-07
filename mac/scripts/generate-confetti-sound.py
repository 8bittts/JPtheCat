#!/usr/bin/env python3
"""Synthesize JP the Cat's celebration confetti "pop" sound.

A single one-shot party-popper flourish for the full-desktop upgrade celebration
(`FullScreenConfetti`): a soft launch "pop" (a warm low thump + a quick filtered
transient), a short upward "pfft" puff as the burst goes off, then a sprinkle of
gentle high sparkle tings for the falling confetti. Tasteful and cozy — the same
cream-paper voice as the UI cues, never a harsh firecracker.

This is a CELEBRATION asset (like the captured `jp-meow.m4a`), NOT one of the four
shared interactive UI cues, so it lives only in the app Resources and is played at
a modest volume gated on the master "Interactive sounds" setting. It is generated
here (pure stdlib + ffmpeg mux) so the design is reproducible; re-run to retune.

  ./generate-confetti-sound.py    # writes confetti-pop.m4a into app Resources
"""
import math
import os
import struct
import subprocess
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
APP_RES = os.path.join(HERE, "..", "Sources", "JPtheCatApp", "Resources")
PEAK_CEILING = 0.89  # leave headroom below full-scale so the encode never clips

# Deterministic pseudo-random (no `random` import needed; keeps output reproducible).
_seed = 0x1337


def rnd():
    global _seed
    _seed = (1103515245 * _seed + 12345) & 0x7FFFFFFF
    return _seed / 0x7FFFFFFF


def raised_cos_env(n, total_n, attack_n, release_n):
    """Click-free raised-cosine attack + cosine release."""
    if n < attack_n:
        return 0.5 - 0.5 * math.cos(math.pi * n / max(attack_n, 1))
    tail = total_n - n
    if tail < release_n:
        return 0.5 - 0.5 * math.cos(math.pi * tail / max(release_n, 1))
    return 1.0


def add(buf, start_s, samples):
    i0 = int(start_s * SR)
    for k, v in enumerate(samples):
        j = i0 + k
        if 0 <= j < len(buf):
            buf[j] += v


DURATION = 1.05
buf = [0.0] * int(DURATION * SR)

# --- 1) The launch "pop": a warm low thump + a fast broadband transient ---------
pop_len = int(0.14 * SR)
pop = []
for n in range(pop_len):
    t = n / SR
    e = raised_cos_env(n, pop_len, int(0.002 * SR), int(0.11 * SR))
    thump = math.sin(2 * math.pi * 150 * t) * math.exp(-t * 24)          # low body
    click = (rnd() * 2 - 1) * math.exp(-t * 90)                          # transient
    pop.append((0.85 * thump + 0.35 * click) * e)
add(buf, 0.0, pop)

# --- 2) The "pfft" puff: a quick upward pitch glide as the burst goes off --------
puff_len = int(0.22 * SR)
puff = []
for n in range(puff_len):
    t = n / SR
    frac = n / puff_len
    freq = 420 + 900 * frac                                             # rise up
    e = raised_cos_env(n, puff_len, int(0.008 * SR), int(0.12 * SR))
    body = math.sin(2 * math.pi * freq * t)
    breath = (rnd() * 2 - 1) * 0.25 * (1 - frac)                        # airy top
    puff.append((0.5 * body + breath) * e * 0.6)
add(buf, 0.02, puff)

# --- 3) Sparkle tings: gentle high glints for the falling confetti ---------------
for s in range(14):
    start = 0.12 + rnd() * 0.62
    freq = 1600 + rnd() * 2200
    ting_len = int((0.10 + rnd() * 0.10) * SR)
    amp = 0.14 + rnd() * 0.10
    ting = []
    for n in range(ting_len):
        t = n / SR
        e = raised_cos_env(n, ting_len, int(0.004 * SR), int(0.08 * SR))
        tone = math.sin(2 * math.pi * freq * t) + 0.4 * math.sin(2 * math.pi * freq * 2 * t)
        ting.append(tone * e * amp * math.exp(-t * 10))
    add(buf, start, ting)

# --- Normalize to the peak ceiling, then write WAV + mux to AAC .m4a -------------
peak = max(1e-9, max(abs(v) for v in buf))
scale = PEAK_CEILING / peak
buf = [v * scale for v in buf]

wav_path = os.path.join(HERE, "confetti-pop.wav")
with wave.open(wav_path, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in buf))

out = os.path.join(APP_RES, "confetti-pop.m4a")
subprocess.run(
    ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
     "-c:a", "aac", "-b:a", "128k", out],
    check=True)
os.remove(wav_path)
print("wrote", out)
