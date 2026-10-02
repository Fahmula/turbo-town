"""Small offline DSP toolkit for build_audio.py (NumPy only; ffmpeg decodes).

Everything works on mono float32 arrays at RATE. Filters are done in the
frequency domain (zero phase). On a loop that's circular, so a seamless loop
stays seamless after filtering.
"""
import subprocess
import wave

import numpy as np

RATE = 44100


def decode(path, start=0.0, duration=None, rate=RATE):
    """Any audio file -> mono float32 at `rate` (ffmpeg)."""
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", str(path)]
    if duration is not None:
        cmd += ["-t", str(duration)]
    cmd += ["-ac", "1", "-ar", str(rate), "-f", "f32le", "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def save_wav(path, x, rate=RATE):
    """16-bit mono PCM. Clips at full scale (callers normalise first)."""
    x = np.clip(np.asarray(x, dtype=np.float64), -1.0, 1.0)
    data = (x * 32767.0).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data)


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)) + 1e-20))


def db(v):
    return 20.0 * np.log10(max(v, 1e-12))


def normalize_rms(x, target_db):
    return x * (10 ** (target_db / 20.0) / rms(x))


def normalize_peak(x, target_db=-1.0):
    return x * (10 ** (target_db / 20.0) / (np.max(np.abs(x)) + 1e-12))


def spectral(x, gain_fn, rate=RATE):
    """Zero-phase (circular) filter: multiply the spectrum by gain_fn(freqs)."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / rate)
    return np.fft.irfft(spec * gain_fn(f), n).astype(np.float32)


def butter_mag(f, fc, order, high=False):
    r = np.maximum(f, 1e-6) / fc
    if high:
        r = 1.0 / r
    return 1.0 / np.sqrt(1.0 + r ** (2 * order))


def lowpass(x, fc, order=2, rate=RATE):
    return spectral(x, lambda f: butter_mag(f, fc, order), rate)


def highpass(x, fc, order=2, rate=RATE):
    return spectral(x, lambda f: butter_mag(f, fc, order, high=True), rate)


def bandpass(x, lo, hi, order=2, rate=RATE):
    return spectral(x, lambda f: butter_mag(f, hi, order) * butter_mag(f, lo, order, high=True), rate)


def peaks(x, bands, rate=RATE):
    """Sum of resonant bumps: bands = [(freq, q, gain)]."""
    def g(f):
        out = np.zeros_like(f)
        for fc, q, gain in bands:
            bw = fc / q
            out += gain * np.exp(-0.5 * ((f - fc) / (bw * 0.5)) ** 2)
        return out
    return spectral(x, g, rate)


def tilt(x, db_per_octave, ref=1000.0, rate=RATE):
    """Brighter (+) or darker (-) by a slope in dB per octave around `ref`."""
    return spectral(x, lambda f: (np.maximum(f, 20.0) / ref) ** (db_per_octave / 6.0206), rate)


def noise(n, seed, color="white"):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal(n).astype(np.float32)
    if color == "white":
        return w
    exp = {"pink": 0.5, "brown": 1.0}[color]
    return spectral(w, lambda f: 1.0 / np.maximum(f, 20.0) ** exp)


def resample_loop(x, new_rate, rate=RATE):
    """Resamples a loop to `new_rate` in the frequency domain: band-limited
    and circular, so it stays seamless."""
    m = int(round(len(x) * new_rate / rate))
    spec = np.fft.rfft(x)
    keep = m // 2 + 1
    out = np.zeros(keep, dtype=complex)
    k = min(keep, len(spec))
    out[:k] = spec[:k]
    return (np.fft.irfft(out, m) * (m / len(x))).astype(np.float32)


def resample_shot(x, new_rate, rate=RATE):
    """Resamples a one-shot (padded so the FFT's wrap-around stays silent)."""
    pad = int(0.05 * rate)
    y = resample_loop(np.concatenate([x, np.zeros(pad, dtype=np.float32)]), new_rate, rate)
    return y[:int(round(len(x) * new_rate / rate))]


def resample(x, ratio):
    """Plays `x` `ratio` times faster (pitch up), linear interpolation on an
    oversampled copy (fine for offline variants)."""
    n_out = int(len(x) / ratio)
    t = np.arange(n_out) * ratio
    return np.interp(t, np.arange(len(x)), x).astype(np.float32)


def fade(x, fade_in=0.005, fade_out=0.02, rate=RATE):
    x = x.copy()
    a = int(fade_in * rate)
    b = int(fade_out * rate)
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a) ** 2
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b) ** 2
    return x


def make_loop(x, length, xfade, start=0):
    """A seamless loop of `length` samples cut from x[start:]: the `xfade`
    samples after the loop are blended (equal power) into its beginning, so
    the end flows into the start."""
    seg = x[start:start + length + xfade].astype(np.float64)
    if len(seg) < length + xfade:
        raise ValueError("source too short for the loop")
    out = seg[:length].copy()
    t = np.linspace(0.0, 1.0, xfade)
    out[:xfade] = seg[:xfade] * np.sin(t * np.pi / 2) + seg[length:length + xfade] * np.cos(t * np.pi / 2)
    return out.astype(np.float32)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def envelope(n, points, rate=RATE):
    """Piecewise-linear envelope from (time s, level) points."""
    t = np.arange(n) / rate
    ts = [p[0] for p in points]
    vs = [p[1] for p in points]
    return np.interp(t, ts, vs).astype(np.float32)


def pitch_track(x, fmin, fmax, rate=RATE, win=0.06, hop=0.02):
    """Fundamental frequency over time by autocorrelation (for picking steady
    stretches out of engine recordings). Returns (times, freqs, clarity)."""
    w = int(win * rate)
    h = int(hop * rate)
    lag_min = int(rate / fmax)
    lag_max = int(rate / fmin)
    times, freqs, clar = [], [], []
    for i in range(0, len(x) - w - lag_max, h):
        seg = x[i:i + w + lag_max].astype(np.float64)
        seg = seg - seg.mean()
        a = seg[:w]
        best, best_lag = -1.0, lag_min
        e0 = np.dot(a, a) + 1e-12
        for lag in range(lag_min, lag_max):
            b = seg[lag:lag + w]
            c = np.dot(a, b) / np.sqrt(e0 * (np.dot(b, b) + 1e-12))
            if c > best:
                best, best_lag = c, lag
        times.append((i + w / 2) / rate)
        freqs.append(rate / best_lag)
        clar.append(best)
    return np.array(times), np.array(freqs), np.array(clar)


def stats(x, rate=RATE):
    """Peak / RMS / crest and the zero-crossing count, for the build log."""
    return "peak %.1f dB, rms %.1f dB, %.2f s" % (db(np.max(np.abs(x))), db(rms(x)), len(x) / rate)
