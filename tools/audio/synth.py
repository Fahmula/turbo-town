"""Synthesised vehicle sounds for build_audio.py: the ones that are naturally
electronic or noise-like, where synthesis is as good as a recording (reverse
beeper, wind, road roar, air brakes, brake squeal, turbo whine and blow-off,
exhaust pops, suspension knocks, splashes, shift clunks), plus fallbacks.

Every function is deterministic (fixed seeds) and returns mono float32 at
dsp.RATE. Loops have an exact length, and their periodic parts complete a
whole number of cycles, so they loop without a seam.
"""
import numpy as np

import dsp

R = dsp.RATE


def _t(seconds):
    return np.arange(int(seconds * R)) / R


def _loop_sine(freq, seconds, phase=0.0):
    """A sine with a whole number of cycles in `seconds` (rounds `freq`)."""
    cycles = max(1, round(freq * seconds))
    return np.sin(2 * np.pi * cycles * _t(seconds) / seconds + phase)


def _lfo(seconds, cycles, phase=0.0):
    """Slow modulation that completes `cycles` whole cycles over the loop."""
    return np.sin(2 * np.pi * cycles * _t(seconds) / seconds + phase)


# ------------------------------------------------------------------ loops --

def reverse_beeper():
    """Truck / bus reversing beeper: 1.1 kHz piezo, 0.5 s on, 0.5 s off."""
    s = 1.0
    t = _t(s)
    tone = _loop_sine(1100, s) + 0.18 * _loop_sine(2200, s) + 0.08 * _loop_sine(3300, s)
    gate = np.where(t < 0.5, 1.0, 0.0)
    ramp = int(0.006 * R)
    on = np.convolve(gate, np.ones(ramp) / ramp, mode="same")
    return dsp.normalize_peak(tone * on, -3.0)


def wind(seconds=6.0):
    """Air rush at speed: low roar with slow gusts and a faint mirror whistle."""
    n = int(seconds * R)
    roar = dsp.noise(n, 11, "brown") * 0.7 + dsp.noise(n, 12, "pink") * 0.5
    roar = dsp.peaks(dsp.lowpass(roar, 1100, 2), [(280, 1.2, 1.0), (700, 1.5, 0.5), (60, 2.0, 0.3)])
    gust = 1.0 + 0.25 * _lfo(seconds, 2, 0.3) + 0.15 * _lfo(seconds, 5, 1.1) + 0.08 * _lfo(seconds, 11, 2.0)
    whistle = dsp.peaks(dsp.noise(n, 13), [(2300, 18.0, 1.0), (3400, 22.0, 0.5)])
    whistle *= 0.5 + 0.5 * _lfo(seconds, 3, 0.7)
    x = roar * gust + dsp.normalize_rms(whistle, dsp.db(dsp.rms(roar)) - 24)
    return dsp.normalize_rms(x, -20.0)


def road_roar(seconds=4.0):
    """Tyre roll on asphalt: broadband roar peaking near 900 Hz (tread
    pattern noise) over a low rumble, with coarse-surface grain."""
    n = int(seconds * R)
    base = dsp.noise(n, 21, "pink")
    roar = dsp.peaks(base, [(900, 1.3, 1.0), (450, 1.5, 0.6), (1800, 2.0, 0.35)])
    rumble = dsp.lowpass(dsp.noise(n, 22, "brown"), 160, 2)
    # Coarse-surface grain: dense and soft (sparse grains read as ticks).
    grain = dsp.bandpass(dsp.noise(n, 23), 600, 4000)
    grain *= 0.6 + 0.4 * dsp.lowpass(dsp.noise(n, 24), 60, 2) * 8
    x = dsp.normalize_rms(roar, -22) + dsp.normalize_rms(rumble, -26) + dsp.normalize_rms(grain, -31)
    x *= 1.0 + 0.06 * _lfo(seconds, 7, 0.4)
    return dsp.normalize_rms(x, -20.0)


def gravel_roll(seconds=4.0, seed=31):
    """Fallback gravel crunch: dense random stone clicks over a dusty roar."""
    n = int(seconds * R)
    rng = np.random.default_rng(seed)
    clicks = np.zeros(n, dtype=np.float32)
    count = int(seconds * 2600)
    idx = rng.integers(0, n, count)
    clicks[idx] = rng.standard_normal(count) * rng.random(count) ** 2.5
    clicks = dsp.peaks(clicks, [(1800, 0.9, 1.0), (4200, 1.2, 0.6), (650, 1.0, 0.4)])
    roar = dsp.lowpass(dsp.noise(n, seed + 1, "pink"), 900, 2)
    x = dsp.normalize_rms(clicks, -22) + dsp.normalize_rms(roar, -26)
    return dsp.normalize_rms(x, -20.0)


def tyre_squeal(seconds=3.0, seed=41):
    """Fallback squeal: several strained partials (rubber stick-slip at a few
    contact patches) whose pitch and level wobble independently, over a
    rubbery hiss; whole thing seamlessly looped."""
    n = int(seconds * R)
    rng = np.random.default_rng(seed)
    x = np.zeros(n)
    for k, (f0, amp) in enumerate(((1050, 1.0), (1290, 0.7), (1760, 0.45), (2380, 0.3), (880, 0.35))):
        wob = dsp.lowpass(rng.standard_normal(n).astype(np.float32), 7 + 3 * k, 2)
        wob = wob / (np.max(np.abs(wob)) + 1e-9)
        f = f0 * (1.0 + 0.03 * wob)
        ph = 2 * np.pi * np.cumsum(f) / R + rng.uniform(0, 6.28)
        am = dsp.lowpass(rng.standard_normal(n).astype(np.float32), 18, 2)
        am = np.clip(0.6 + 2.5 * am / (np.max(np.abs(am)) + 1e-9), 0.05, 1.5)
        x += amp * am * (np.sin(ph) + 0.35 * np.sin(2 * ph + 0.5) + 0.12 * np.sin(3 * ph + 1.3))
    hiss = dsp.peaks(dsp.noise(n, seed + 2), [(2400, 1.5, 1.0), (5200, 2.0, 0.5)])
    x = dsp.normalize_rms(x.astype(np.float32), -20) + dsp.normalize_rms(hiss, -28)
    xf = int(0.15 * R)
    x = dsp.make_loop(np.concatenate([x, x[:xf]]), n - xf, xf)
    return dsp.normalize_rms(x, -18.0)


def metal_scrape(seconds=3.0, seed=51):
    """Fallback bodywork grinding: rough grit through inharmonic metal-panel
    resonances, with uneven pressure."""
    n = int(seconds * R)
    rng = np.random.default_rng(seed)
    grit = rng.standard_normal(n).astype(np.float32) * (rng.random(n) ** 4).astype(np.float32)
    modes = [(820, 14, 0.6), (1370, 16, 1.0), (2210, 18, 0.8), (3150, 20, 0.7), (4480, 22, 0.5), (6010, 25, 0.35)]
    ring = dsp.peaks(grit, modes)
    rumble = dsp.lowpass(dsp.noise(n, seed + 1, "brown"), 250, 2)
    press = 0.7 + 0.3 * _lfo(seconds, 3, 0.2) + 0.15 * _lfo(seconds, 13, 1.3)
    x = (dsp.normalize_rms(ring, -20) + dsp.normalize_rms(rumble, -27)) * press
    return dsp.normalize_rms(x, -18.0)


def whine(freq, seconds=1.0, harmonics=((2, 0.25), (3, 0.08)), noise_db=-26.0, seed=61):
    """Turbo / supercharger whine: a pure tone with a few harmonics and a
    narrow band of air noise around it."""
    n = int(seconds * R)
    x = _loop_sine(freq, seconds)
    for k, a in harmonics:
        x = x + a * _loop_sine(freq * k, seconds, 0.4 * k)
    air = dsp.peaks(dsp.noise(n, seed), [(freq, 8.0, 1.0), (freq * 2, 10.0, 0.3)])
    x = dsp.normalize_rms(x, -20) + dsp.normalize_rms(air, -20 + noise_db + 20)
    return dsp.normalize_rms(x, -18.0)


def horn(freqs, seconds=1.0, formants=((1600, 2.0, 1.0), (3100, 3.0, 0.6)), brass=0.0, seed=71):
    """Horn loop: buzzy (sawtooth-like, band-limited) tones through the
    diaphragm/trumpet formants. Electric car horns are two tones a third or
    so apart; air horns are a deeper chord with some breath. `freqs` are
    rounded to whole cycles per loop."""
    n = int(seconds * R)
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        cycles = round(f * seconds)
        for k in range(1, 40):
            fk = cycles * k / seconds
            if fk > 9000:
                break
            amp = 1.0 / k ** (1.1 - 0.3 * brass)
            x += amp * np.sin(2 * np.pi * cycles * k * _t(seconds) / seconds + 0.7 * k + i)
    x = dsp.peaks(x.astype(np.float32), list(formants) + [(freqs[0] * 2, 3.0, 0.5)])
    x = x + 0.6 * dsp.highpass(x, 300)
    if brass > 0:
        air = dsp.peaks(dsp.noise(n, seed), [(freqs[0] * 3, 4.0, 1.0)])
        x = x + dsp.normalize_rms(air, dsp.db(dsp.rms(x)) - 26)
    x = dsp.soft_clip(dsp.normalize_peak(x, -2.0), 1.6)
    return dsp.normalize_rms(x, -14.0)


# -------------------------------------------------------------- one-shots --

def air_brake(seed=81):
    """Air-brake release: a valve chuff, then a bright hiss that dies away."""
    n = int(1.3 * R)
    t = _t(1.3)
    hiss = dsp.bandpass(dsp.noise(n, seed), 1600, 9500, 2)
    hiss *= np.exp(-t * 2.6) * np.clip(t / 0.012, 0, 1)
    hiss *= 1.0 + 0.15 * np.sin(2 * np.pi * 31 * t)
    chuff = dsp.lowpass(dsp.noise(n, seed + 1), 900, 2) * np.exp(-t * 40.0)
    x = dsp.normalize_rms(hiss, -16) + dsp.normalize_rms(chuff, -24)
    return dsp.fade(dsp.normalize_peak(x, -1.0), 0.002, 0.15)


def brake_squeal(freq, seed):
    """Disc brake squeal as a car stops: a thin tone with vibrato."""
    dur = 0.9 + 0.2 * (seed % 3)
    n = int(dur * R)
    t = _t(dur)
    f = freq * (1.0 + 0.004 * np.sin(2 * np.pi * 7.3 * t) + 0.01 * t)
    ph = 2 * np.pi * np.cumsum(f) / R
    x = np.sin(ph) + 0.3 * np.sin(2 * ph)
    env = dsp.envelope(n, [(0, 0), (0.06, 1.0), (dur * 0.7, 0.8), (dur, 0.0)])
    x = x * env + dsp.normalize_rms(dsp.bandpass(dsp.noise(n, seed), 2000, 7000), -40) * env
    return dsp.normalize_peak(x, -3.0)


def blowoff(seed=91):
    """Turbo blow-off valve: a fluttering 'pssh' falling in pitch."""
    dur = 0.55
    n = int(dur * R)
    t = _t(dur)
    src = dsp.noise(n, seed)
    lo = dsp.bandpass(src, 1200, 3000)
    hi = dsp.bandpass(src, 3000, 8000)
    sweep = np.clip(t / dur, 0, 1)
    x = hi * (1 - sweep) + lo * sweep
    flutter = 0.65 + 0.35 * np.sign(np.sin(2 * np.pi * 22 * t)) * np.exp(-t * 3)
    env = np.clip(t / 0.01, 0, 1) * np.exp(-t * 5.5)
    return dsp.fade(dsp.normalize_peak(x * flutter * env, -2.0), 0.001, 0.08)


def exhaust_pop(seed):
    """An exhaust pop/crackle: a sharp crack over a short low 'bap'."""
    rng = np.random.default_rng(seed)
    dur = 0.18
    n = int(dur * R)
    t = _t(dur)
    crack = dsp.bandpass(dsp.noise(n, seed), 1500, 7000) * np.exp(-t * rng.uniform(90, 160))
    body_f = rng.uniform(85, 150)
    body = np.sin(2 * np.pi * body_f * t * (1 - 0.6 * t)) * np.exp(-t * rng.uniform(28, 45))
    rumble = dsp.lowpass(dsp.noise(n, seed + 7), 400, 2) * np.exp(-t * 30)
    x = dsp.normalize_peak(crack, -6) * rng.uniform(0.5, 1.0) + dsp.normalize_peak(body, -3) + dsp.normalize_peak(rumble, -8)
    return dsp.fade(dsp.normalize_peak(dsp.soft_clip(x, 1.5), -1.0), 0.0005, 0.03)


def knock(seed, heavy=False):
    """Suspension knock over a bump (heavy = a landing): a low thump, a
    rubbery clunk and a light metallic rattle."""
    rng = np.random.default_rng(seed)
    dur = 0.45 if heavy else 0.22
    n = int(dur * R)
    t = _t(dur)
    f0 = rng.uniform(55, 70) if heavy else rng.uniform(80, 110)
    thump = np.sin(2 * np.pi * f0 * t * (1 - 0.35 * t / dur)) * np.exp(-t * (14 if heavy else 26))
    clunk = dsp.bandpass(dsp.noise(n, seed), 250, 1400) * np.exp(-t * (45 if heavy else 70))
    rattle = dsp.peaks(dsp.noise(n, seed + 3) * (rng.random(n) > 0.995), [(2600, 10, 1), (4100, 12, 0.6)])
    rattle *= np.exp(-t * (10 if heavy else 25))
    x = dsp.normalize_peak(thump, -2) + dsp.normalize_peak(clunk, -7 if heavy else -5) + dsp.normalize_peak(rattle, -18)
    return dsp.fade(dsp.normalize_peak(x, -1.0), 0.0005, 0.05)


def splash(seed):
    """Car into water: a heavy whoosh and spray, then bubbles."""
    rng = np.random.default_rng(seed)
    dur = 1.6
    n = int(dur * R)
    t = _t(dur)
    whoosh = dsp.lowpass(dsp.noise(n, seed, "pink"), 2500, 2) * (np.clip(t / 0.02, 0, 1) * np.exp(-t * 3.5))
    spray = dsp.bandpass(dsp.noise(n, seed + 1), 2000, 9000) * np.clip(t / 0.03, 0, 1) * np.exp(-t * 4.0)
    thump = np.sin(2 * np.pi * 45 * t) * np.exp(-t * 9)
    bubbles = np.zeros(n)
    for _ in range(70):
        start = rng.uniform(0.1, 1.3)
        f = rng.uniform(250, 1300)
        d = rng.uniform(0.02, 0.07)
        i0 = int(start * R)
        m = int(d * R)
        if i0 + m >= n:
            continue
        tt = np.arange(m) / R
        bubbles[i0:i0 + m] += np.sin(2 * np.pi * f * tt * (1 + 3 * tt)) * np.exp(-tt * 60) * rng.uniform(0.2, 1.0)
    bubbles *= np.exp(-t * 1.5)
    x = dsp.normalize_peak(whoosh, -3) + dsp.normalize_peak(spray, -8) + dsp.normalize_peak(thump, -6) + dsp.normalize_peak(bubbles, -14)
    return dsp.fade(dsp.normalize_peak(x, -1.0), 0.001, 0.3)


def shift_clunk(seed=101):
    """A gear change: two quick mechanical clicks and a soft thud."""
    dur = 0.16
    n = int(dur * R)
    t = _t(dur)
    x = np.zeros(n)
    for k, (at, f) in enumerate(((0.0, 1900), (0.045, 1400))):
        i0 = int(at * R)
        m = n - i0
        tt = np.arange(m) / R
        x[i0:] += dsp.peaks(dsp.noise(m, seed + k), [(f, 6, 1.0), (f * 2.3, 8, 0.5)]) * np.exp(-tt * 140)
    x += np.sin(2 * np.pi * 95 * t) * np.exp(-t * 40) * 0.6
    return dsp.fade(dsp.normalize_peak(x, -1.0), 0.0005, 0.02)
