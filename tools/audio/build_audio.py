#!/usr/bin/env python3
"""Builds every vehicle sound in assets/audio/ (ART_BIBLE.md §27 budgets;
sources and licences in ASSET_MANIFEST.md).

Run from the project root:

    python3 tools/audio/build_audio.py            # everything
    python3 tools/audio/build_audio.py synth      # only the synthesised parts

Needs NumPy and ffmpeg. Third-party recordings are downloaded once into
build/audio_sources/ (gitignored) from the URLs in sources.py and checked
against their SHA-256; then they're cut, cleaned up, made into seamless loops
or trimmed one-shots, loudness-matched and written as 16-bit mono WAV at
44.1 kHz. Synthesised sounds come from synth.py with fixed seeds. Re-running
reproduces the same files.

Godot imports the WAVs (loops have loop_mode set in their .import files by
this script's import_settings()).
"""
import hashlib
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
import synth  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"
CACHE = ROOT / "build" / "audio_sources"

# Loudness targets (RMS dBFS) by kind, so VehicleAudio's dB numbers mean the
# same thing for every file.
LOOP_DB = -18.0
SHOT_PEAK_DB = -1.0

LOOPS = set()      # loops written this run (for the log)


def write(rel, x, loop=False, rate=dsp.RATE):
    """Writes OUT/rel; `rate` < 44.1 kHz stores it smaller (resampled
    band-limited; loops stay seamless)."""
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if rate != dsp.RATE:
        x = dsp.resample_loop(x, rate) if loop else dsp.resample_shot(x, rate)
    peak = float(abs(x).max())
    if peak > 0.89:
        x = x * (0.89 / peak)   # never clip: stay under -1 dBFS
    dsp.save_wav(path, x, rate)
    if loop:
        LOOPS.add(rel)
    print("  %-34s %s%s" % (rel, dsp.stats(x), "  (loop)" if loop else ""))


def fetch(src):
    """Downloads a source once (cached), checks its SHA-256, returns its path."""
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / src["file"]
    if not path.exists():
        print("  downloading", src["url"])
        req = urllib.request.Request(src["url"], headers={"User-Agent": "turbo-town-build-audio"})
        with urllib.request.urlopen(req, timeout=60) as r:
            path.write_bytes(r.read())
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if src.get("sha256") and digest != src["sha256"]:
        raise SystemExit("checksum mismatch for %s: %s" % (src["file"], digest))
    return path


# --------------------------------------------------------------- synthesis --

def build_synth():
    print("synthesised:")
    write("body/reverse_beeper.wav", synth.reverse_beeper(), loop=True)
    write("body/wind.wav", synth.wind(), loop=True)
    write("engine/turbo_whine.wav", synth.whine(3000, harmonics=((2, 0.2),), noise_db=-20, seed=61), loop=True)
    write("engine/supercharger_whine.wav", synth.whine(1800, harmonics=((2, 0.4), (3, 0.2), (4, 0.1)), noise_db=-30, seed=62), loop=True)
    write("engine/blowoff.wav", synth.blowoff())
    for k in range(4):
        write("engine/pop_%d.wav" % (k + 1), synth.exhaust_pop(200 + k))
    write("engine/shift.wav", synth.shift_clunk())
    write("brake/air_1.wav", synth.air_brake())
    for k, f in enumerate((3150, 3650, 4300)):
        write("brake/squeal_%d.wav" % (k + 1), synth.brake_squeal(f, 300 + k))
    for k in range(4):
        write("suspension/knock_%d.wav" % (k + 1), synth.knock(400 + k))
    for k in range(3):
        write("suspension/land_%d.wav" % (k + 1), synth.knock(500 + k, heavy=True))
    for k in range(2):
        write("body/splash_%d.wav" % (k + 1), synth.splash(600 + k))
    # Fallbacks, replaced by recordings in recorded.py where we have good ones.
    write("tyre/roll_asphalt.wav", synth.road_roar(), loop=True, rate=32000)
    write("tyre/roll_gravel.wav", synth.gravel_roll(), loop=True, rate=32000)
    write("tyre/skid_gravel.wav", synth.gravel_roll(3.0, seed=37) * 1.2, loop=True, rate=32000)
    write("tyre/squeal.wav", synth.tyre_squeal(), loop=True, rate=32000)
    write("horn/car.wav", synth.horn([415, 520]), loop=True)
    write("horn/air.wav", synth.horn([185, 233, 277], formants=((900, 1.5, 1.0), (2200, 2.5, 0.6)), brass=1.0), loop=True)
    write("horn/small.wav", synth.horn([620], formants=((2000, 2.0, 1.0),)), loop=True)


# --------------------------------------------------------- Godot imports --

# Which files loop (every run marks them, whatever it rebuilt).
LOOP_PATTERNS = ["engine/*/on_*.wav", "engine/*/off_*.wav", "engine/*_whine.wav", "tyre/*.wav", "horn/*.wav",
                 "body/wind.wav", "body/scrape.wav", "body/reverse_beeper.wav"]


def import_settings():
    """Sets loop mode in the looping WAVs' .import files. Godot writes those
    on first import, so after adding new sounds: import once
    (godot --headless --path . --import), run `build_audio.py imports`, and
    import again."""
    loops = sorted({p.relative_to(OUT).as_posix() for pat in LOOP_PATTERNS for p in OUT.glob(pat)})
    missing = [r for r in loops if not (OUT / (r + ".import")).exists()]
    if missing:
        print("  %d loops not imported yet: import, then run `build_audio.py imports`" % len(missing))
    for rel in loops:
        imp = OUT / (rel + ".import")
        if not imp.exists():
            continue
        lines = imp.read_text().splitlines()
        out = []
        for ln in lines:
            if ln.startswith("edit/loop_mode="):
                ln = "edit/loop_mode=2"
            elif ln.startswith("edit/loop_begin="):
                ln = "edit/loop_begin=0"
            elif ln.startswith("edit/loop_end="):
                ln = "edit/loop_end=-1"
            elif ln.startswith("compress/mode="):
                ln = "compress/mode=0"   # PCM: QOA's frame seams can tick at the loop point
            out.append(ln)
        imp.write_text("\n".join(out) + "\n")


def main(args):
    parts = args or ["synth", "recorded"]
    if "synth" in parts:
        build_synth()
    if "recorded" in parts:
        import recorded
        recorded.build(write, fetch)
    if "profiles" in parts or "recorded" in parts:
        import profiles
        import recorded
        sets = {}
        for name, files in recorded.ENGINE_SETS.items():
            rpms = [r for _, r in files]
            sets[name] = {"on": [(r, "engine/%s/on_%d.wav" % (name, r)) for r in rpms],
                          "off": [(r, "engine/%s/off_%d.wav" % (name, r)) for r in rpms]}
        print("profiles:")
        profiles.write_profiles(OUT, sets)
    import_settings()


if __name__ == "__main__":
    main(sys.argv[1:])
