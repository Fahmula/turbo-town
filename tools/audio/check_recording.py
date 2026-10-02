#!/usr/bin/env python3
"""Checks a recording from the game's --audio test for problems a listener
would notice:

    python3 tools/audio/check_recording.py <dir>     (session.wav + events.txt)

* clicks/pops: short, isolated bursts of high-frequency energy (> 6 kHz) far
  above their surroundings and their own neighbours (onsets that stay loud
  aren't clicks), outside the deliberate one-shots listed in events.txt
  (crashes, knocks, the horn starting...);
* dropouts: the level falling by more than 15 dB for under 120 ms and
  coming straight back (a gap in a loop or a crossfade);
* clipping: samples at full scale;
and prints the level of each phase so the mix can be balanced.
Exit code 1 if anything is found.
"""
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dsp  # noqa: E402


def load(path):
    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        ch = w.getnchannels()
        width = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dt = {2: "<i2", 4: "<i4"}[width]
    x = np.frombuffer(raw, dtype=dt).astype(np.float64) / (2 ** (8 * width - 1))
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, rate


def main(d):
    d = Path(d)
    x, rate = load(d / "session.wav")
    events = []
    phases = []
    for ln in (d / "events.txt").read_text().splitlines():
        if not ln.strip():
            continue
        t, what = ln.split(" ", 1)
        events.append((float(t), what))
        if what.startswith("phase "):
            phases.append((float(t), what[6:]))
    problems = []
    # Clipping.
    clipped = int(np.sum(np.abs(x) >= 0.999))
    if clipped:
        problems.append("%d clipped samples" % clipped)
    # Clicks: high-passed peaks per 2.9 ms block against the median around.
    hp = dsp.highpass(x.astype(np.float32), 6000, 4, rate)
    blk = 128
    nb = len(hp) // blk
    peaks = np.abs(hp[:nb * blk]).reshape(nb, blk).max(axis=1)
    win = int(0.15 * rate / blk)
    # Loops starting/stopping ("voice") must be click-free: not excused.
    shot_times = [t for t, w in events if not w.startswith("phase") and not w.startswith("voice")]
    clicks = []
    for i in range(win, nb - win):
        local = np.median(peaks[i - win:i + win])
        # A click is a short, isolated spike: far above the surroundings and
        # well above its own neighbours a few ms either side (an onset, like
        # the throttle opening or a gravel crunch, stays loud afterwards).
        around = max(peaks[i - 4:i - 1].max(), peaks[i + 2:i + 5].max())
        if peaks[i] > 10 * max(local, 1e-5) and peaks[i] > 4 * around and peaks[i] > 10 ** (-42 / 20):
            t = i * blk / rate
            # Event times come from the game clock, which runs up to ~0.25 s
            # behind the recording.
            if any(-0.3 <= t - s <= 0.6 for s in shot_times):
                continue
            if clicks and t - clicks[-1] < 0.05:
                continue
            clicks.append(t)
    if clicks:
        problems.append("%d possible clicks at %s" % (len(clicks), ", ".join("%.2f s" % t for t in clicks[:12])))
    # Dropouts: 20 ms RMS blocks.
    b2 = int(0.02 * rate)
    n2 = len(x) // b2
    r = np.sqrt(np.mean(x[:n2 * b2].reshape(n2, b2) ** 2, axis=1) + 1e-12)
    rdb = 20 * np.log10(r)
    drops = []
    for i in range(5, n2 - 6):
        before = rdb[i - 5:i].mean()
        after = rdb[i + 1:i + 6].mean()
        if before > -50 and after > -50 and rdb[i] < min(before, after) - 15:
            t = i * b2 / rate
            if any(abs(t - s) < 0.5 for s, w in events if "teleport" in w):
                continue
            drops.append(t)
    if drops:
        problems.append("%d dropouts at %s" % (len(drops), ", ".join("%.2f s" % t for t in drops[:12])))
    # Levels per phase.
    print("recording %.1f s, peak %.1f dBFS, rms %.1f dBFS" % (len(x) / rate, dsp.db(np.max(np.abs(x))), dsp.db(dsp.rms(x))))
    bounds = phases + [(len(x) / rate, "end")]
    for (t0, name), (t1, _) in zip(bounds, bounds[1:]):
        seg = x[int(t0 * rate):int(t1 * rate)]
        if len(seg) > rate * 0.1:
            print("  %-18s %5.1f-%5.1f s  rms %6.1f dBFS  peak %6.1f" % (name, t0, t1, dsp.db(dsp.rms(seg)), dsp.db(np.max(np.abs(seg)))))
    for p in problems:
        print("PROBLEM", p)
    if not problems:
        print("no clicks, dropouts or clipping found")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
