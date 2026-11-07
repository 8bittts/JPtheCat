#!/usr/bin/env python3
"""Synthesize JP the Cat's interactive UI sounds.

Four short, warm, tasteful cues that match JP's cozy cream-paper brand — soft
sine-based blips with gentle raised-cosine envelopes (no harsh transients):

  ui-toggle-on    a light two-note rise   (settling ON)
  ui-toggle-off   a light two-note fall   (settling OFF)
  ui-click-top    a crisp, higher tick    (top chrome buttons)
  ui-click-bottom a softer, lower thock    (bottom footer buttons)

Writes .wav next to this script, then muxes each to AAC .m4a with ffmpeg into
both the app Resources and the web/public folder so the app and homepage share
one voice. Re-run whenever the sound design changes.

NORMALIZATION: every cue is scaled to ONE shared perceptual level before encode
(see `normalize`). The target is a matched loudest-window RMS — not a matched
peak — because a short click at equal peak sounds quieter than a sustained
toggle (the ear integrates energy over ~a syllable, not over one sample). This
keeps the four cues at a coherent volume while PRESERVING each one's timbre and
shape: `ui-click-top` stays the crisp higher tick, `ui-click-bottom` the softer
lower thock — only their overall level is matched to the toggles. The captured
mascot `jp-meow.m4a`/`meow.m4a` is a separate one-time asset (no generator); it
is loudness-normalized to ~-23 LUFS by hand so it sits coherently just under the
cues (a gentle mascot flourish, not a punchy functional cue). Keep both copies
of every file byte-identical (guarded by web/tests/ui-sound-assets.test.ts).
"""
import math
import os
import struct
import subprocess
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
APP_RES = os.path.join(HERE, "..", "Sources", "JPtheCatApp", "Resources")
WEB_PUB = os.path.join(HERE, "..", "..", "web", "public")

# --- Loudness normalization targets (one shared level for all four cues) ---
# Loudest-window RMS target in dBFS. -15 matches the toggles' natural level and
# lifts the quieter clicks up to meet them.
TARGET_WIN_RMS_DBFS = -15.0
# Integration window for the "loudest-window RMS" measurement. 0.070 s fits
# inside the shortest cue (the 70 ms click-top) and approximates the ear's
# short-term loudness window.
CUE_WINDOW_S = 0.070
# Non-binding safety ceiling; post-normalize peaks land well under this, so the
# limiter branch almost never fires — it only guards against a future louder cue.
PEAK_CEILING_DBFS = -1.0


def env(n, total, attack=0.006, release=None):
    """Raised-cosine attack + exponential-ish release; smooth, click-free."""
    release = release if release is not None else total * 0.7
    a = int(attack * SR)
    r = int(release * SR)
    if n < a:
        return 0.5 - 0.5 * math.cos(math.pi * n / max(a, 1))
    tail = total * SR - n
    if tail < r:
        return math.exp(-3.0 * (1 - tail / max(r, 1)))
    return 1.0


def tone(freq, dur, amp, attack, release, t0=0.0, detune=0.0, harmonic=0.18):
    """A soft sine + a quiet octave harmonic for a little wooden body."""
    samples = []
    total = dur
    for n in range(int(dur * SR)):
        t = n / SR
        e = env(n, total, attack=attack, release=release)
        s = math.sin(2 * math.pi * freq * t)
        s += harmonic * math.sin(2 * math.pi * (freq * 2 + detune) * t)
        samples.append((t0, amp * e * s))
    return samples


def mix(*layers, length):
    buf = [0.0] * length
    for layer in layers:
        for i, (_, v) in enumerate(layer):
            if i < length:
                buf[i] += v
    # soft-clip guard
    return [max(-0.98, min(0.98, x)) for x in buf]


def _dbfs_to_lin(db):
    return 10.0 ** (db / 20.0)


def normalize(buf):
    """Scale a cue so its loudest CUE_WINDOW_S window hits TARGET_WIN_RMS_DBFS,
    then hold a peak ceiling. A single scalar gain — the cue's shape and timbre
    are untouched; only its overall level is matched to the other cues."""
    n = len(buf)
    if n == 0:
        return buf
    w = min(int(CUE_WINDOW_S * SR), n)
    # Loudest sliding-window mean-square via a prefix-sum over x^2 (O(n)).
    pref = [0.0] * (n + 1)
    for i in range(n):
        pref[i + 1] = pref[i] + buf[i] * buf[i]
    best_ms = 0.0
    for start in range(0, n - w + 1):
        ms = (pref[start + w] - pref[start]) / w
        if ms > best_ms:
            best_ms = ms
    cur_rms = math.sqrt(best_ms)
    if cur_rms <= 0.0:
        return buf
    gain = _dbfs_to_lin(TARGET_WIN_RMS_DBFS) / cur_rms
    out = [x * gain for x in buf]
    peak = max((abs(x) for x in out), default=0.0)
    ceil = _dbfs_to_lin(PEAK_CEILING_DBFS)
    if peak > ceil:
        trim = ceil / peak
        out = [x * trim for x in out]
    return out


def note_at(freq, dur, amp, attack, release, offset):
    """A tone whose samples start at `offset` seconds within the clip."""
    start = int(offset * SR)
    raw = tone(freq, dur, amp, attack, release)
    return [(0, 0.0)] * start + raw


def write_wav(path, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", int(round(max(-1.0, min(1.0, s)) * 32767))) for s in samples
        )
        w.writeframes(frames)


def build():
    specs = {}

    # toggle ON — a gentle rise, E5 -> A5, soft and reassuring
    length = int(0.16 * SR)
    specs["ui-toggle-on"] = mix(
        note_at(659.25, 0.09, 0.30, 0.006, 0.07, 0.0),
        note_at(880.00, 0.11, 0.32, 0.006, 0.085, 0.045),
        length=length,
    )

    # toggle OFF — a gentle fall, A5 -> E5, softer/darker
    specs["ui-toggle-off"] = mix(
        note_at(880.00, 0.09, 0.28, 0.006, 0.07, 0.0),
        note_at(659.25, 0.11, 0.30, 0.006, 0.09, 0.045),
        length=length,
    )

    # click TOP — crisp light tick, higher, quick decay
    length = int(0.07 * SR)
    specs["ui-click-top"] = mix(
        note_at(1180.0, 0.055, 0.26, 0.003, 0.045, 0.0),
        length=length,
    )

    # click BOTTOM — softer, lower thock, a touch longer
    length = int(0.085 * SR)
    specs["ui-click-bottom"] = mix(
        note_at(720.0, 0.07, 0.26, 0.004, 0.06, 0.0),
        length=length,
    )

    os.makedirs(APP_RES, exist_ok=True)
    for name, samples in specs.items():
        # Match every cue to one shared perceptual level (preserves timbre/shape).
        samples = normalize(samples)
        wav = os.path.join(HERE, name + ".wav")
        write_wav(wav, samples)
        for dest_dir in (APP_RES, WEB_PUB):
            m4a = os.path.join(dest_dir, name + ".m4a")
            subprocess.run(
                ["ffmpeg", "-y", "-i", wav, "-c:a", "aac", "-b:a", "128k", m4a],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print("wrote", os.path.relpath(m4a, os.path.join(HERE, "..", "..")))
        os.remove(wav)


if __name__ == "__main__":
    build()
