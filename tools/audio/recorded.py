"""Third-party recordings for build_audio.py: where each comes from (URL +
SHA-256, licence in ASSET_MANIFEST.md) and how it's turned into game files.

Engines: Stunt Rally 3's engine loops (CryHam, CC BY 4.0, rendered in Engine
Simulator at steady rpm). Each becomes an on-load loop; an off-load
(coasting) twin is derived by filtering. Every vehicle's start-up is built
from its own engine set: a synthesised starter crank, then that engine's idle
flaring up and settling.
"""
import numpy as np

import dsp
import synth

R = dsp.RATE

SR3_COMMIT = "0fc4ac9ada5009be68df379940842ce80e31d493"
SR3 = "https://raw.githubusercontent.com/stuntrally/stuntrally3/%s/data/sounds/" % SR3_COMMIT

# file (under data/sounds/) -> SHA-256 of the downloaded file.
SR3_FILES = {
    "crash/01.wav": "5af4b02582b6e45e4eddbc1df30aa80f23dcd9b3f002dde2c55abaa6c29781ba",
    "crash/02.wav": "02a9ee84d115cf063a1a1ad7ccad4c263c45571dd22be7255574d776f97f9d95",
    "crash/03.wav": "8572fccd38a6e85d9496bea6b3801ffdc2dcd1200130510224ab3d7a6f920bb1",
    "crash/04.wav": "b402a2ec8754e0e4388b41266228c5fd4ca2547c00ec936d95528869c8b0bd3a",
    "crash/05.wav": "45fff4b41dace9a8c98a9d8419aea51b825d12d5a2f523da289e446f61175bdf",
    "crash/06.wav": "996efedf4e995cdca08377d558884796c82eca4832dcdf40f0433381e6ca9997",
    "crash/07.wav": "0bdbe9441d4c63736969f3e63abf4ed835deec6297990db37f7177b0547020cc",
    "crash/08.wav": "4cf450d279460b640afe000248a9ffbc16e2e91edf3ebb9b89fb22d750fef409",
    "crash/09.wav": "dfdef4a6bfbb9421ea94f9e598d934b60f5a41f1f902fa94a1c110143d1b9061",
    "crash/10.wav": "5755b9ea9a8a4f453fd6a636dd03f9e1da52c87fe2e9c787eadf30f220abd29b",
    "crash/11.wav": "744435fde1abd478f4c04e9b71f9ea85d4e09e7c9b0b413019aa623c263e155b",
    "crash/12.wav": "02da93a27b2cf86a0648ad4b4b3a30bfe8bd070ecd7609345c178dbc2454fef9",
    "crash/scrap.wav": "f3f370856b26faadc918f9ef0ef30604a8f7cf6ad898ccf1fe67cad413fcf767",
    "crash/screech.wav": "20dcd5cf1ebd82c54df641336f7082ff5199ee26a44b9af4003526ca696d7cf9",
    "engines/b-i6r-1.wav": "9c6d3067e802fddb69144c6eb903ebdfb34d70a6ac968083fce8007df904c0b8",
    "engines/b-i6r-2.wav": "fb1a6627e85ff12a93d13712d8f3a1f1718f4a3bda3fee70e447c4f3504a9d7f",
    "engines/b-i6r-3.wav": "08e0656aa89416ac00eb14b19bdba809130443a551b7a5e902336753cc532f68",
    "engines/b-i6r-4.wav": "d7b7c688f6be3b7dfc8e0b7650c91a7b200acf4a056373648ccb5671878fbc86",
    "engines/b-i6r-5.wav": "4c992f785c097f95a70d7cfd7ee0c3dc7c6b857cbc15f495710c638d04697219",
    "engines/b-i6r-6.wav": "f22a768b26cecf2666c9cda6e13acb03a211a934e6ec4777cf26a31718f3338d",
    "engines/b-i6r-7.wav": "764ba8f3d451ee1132dea7ad2002df1be6106150b21ee47446186ace38f39411",
    "engines/b-i6r-8.wav": "16afeea952054b725b36294a3513da8e286707e63e74a63456f275834c3d4e0c",
    "engines/ds8-0.wav": "1929185d064c2887b37115e35f89a6cab0f4736ddfdba41686c14fa7a0af2f86",
    "engines/ds8-1.wav": "aeacd3a6e9777268667c4e6774aaf407fbba570a9b5f121be9efc8f5028b4f30",
    "engines/ds8-2.wav": "54f932afb9443d0658f79982bfd91e7d9b27b9c79ca408a3d63eff84d55c8c79",
    "engines/ds8-3.wav": "eb628083df65f5f1e353d7921f12f1dcdb17f6c71d2e6e591f6bcc3ce990c094",
    "engines/ds8-4.wav": "15a2970e3cdef56ff6f4db14c86842d7a9207c6846bfc699aa86c01ddceba3a3",
    "engines/ds8-5.wav": "41e7448043369c3c6797de54893b132804b04641e432d7921fefe095109e79db",
    "engines/exh-1.wav": "51e56019fd6587092d1a3d75e80cb2a0dd040d32fdb47f34995e379886bcd8db",
    "engines/exh-2.wav": "da150e74108d0901e5b449caf8c2c1ec698320248709a756b726f86b9c95ed13",
    "engines/exh-3.wav": "dca018afcdb7d6759ecbdf6d8cbb315839e339326ae555f3edfdd860a0478966",
    "engines/exh-4.wav": "0590798da3ba8ef1128fa2433d418eed6c63050a74b1361ce6fd3a026c19b82b",
    "engines/exh-5.wav": "0260367e56f824136cadbdd489aea61c1ca77a8567ef6e5af67a834916842da3",
    "engines/exh-6.wav": "c6ddf1faf8d7d0dfd83ca82474c19387e528f55c2ef62f28048f8b2cd3e8a5a4",
    "engines/gv8-1.wav": "779fd640f80bf0e27b371854f0fe0cce7c619a67dac8066e27f11a637d0c9c9c",
    "engines/gv8-2.wav": "382fb3cca845a1af536949b619ebb9ec8f1cdcfc3d5ad041fbd9cdd43971d1a5",
    "engines/gv8-3.wav": "29b4bb94db722026a213ac0c4da01f846dc9b63352d624b3c4cada14896b1206",
    "engines/gv8-4.wav": "300a0f65e06495655106fab9ab48b7756d47bedda583d965973d42317ab8134e",
    "engines/gv8-5.wav": "2a68671ac4a03a407893e9397acdb4c1e5bcbf243e51191f303f1915673c606d",
    "engines/gv8-6.wav": "3de70b3d2392558f1029759ea70c1bf37c37276c583cf35afa0826d9789098c7",
    "engines/su-low-1.wav": "e32b6de83b46b7c8e2c6590a37a4e84938ffcb86bf182882fd8d3f44277dbfd2",
    "engines/su-low-2.wav": "15dc50c2b2343f610f953ce5cc88d3bd21120874dcdad707bd84e837d42dd3d2",
    "engines/su-low-3.wav": "c6a3e7c78517b9d416c7657bbde3de530c6d48124282f187d320d8add8df7ec7",
    "engines/su-low-4.wav": "2e5d824263188c9b434d084688325d9d08df3050c437ab972dedd6e7e189c3c1",
    "engines/su-low-5.wav": "da48163ae460991b9befdc4b2800a104f4e64ff2412e4a8f007ccbfefe31219e",
    "engines/su-low-6.wav": "3a3434b9a2ed204ba08cd3f3790ede5ade0b137a20a8cf5a913e53de66ec6ce7",
    "engines/su-low-7.wav": "de69c481b9a85013f41b801acaa7e67ea01645aade9697afe6725ed08b3bcb40",
    "engines/su-sz-1.wav": "8835cf1dfd6160a831cd4bf45fd4abb701f3969dc4879c03a918ce320821cfd0",
    "engines/su-sz-2.wav": "88f2188faf29adc644279d93d0674878498f578b0388189e59f93a93b5b49d5d",
    "engines/su-sz-3.wav": "aaff1f73956de616fc0e31d1d02ec9bdecfa6fece68b50ec40844937afe44a48",
    "engines/su-sz-5.wav": "3bcc8cedbeb4b24b626fe2bef9460f978cd8ac64fa9a8fa54bebe0a98545177a",
    "engines/su-sz-6.wav": "cfe1f389735747f388c2b8ed1d5fa957980a86a46c55d737fcc0e922f2a103da",
    "engines/su-sz-7.wav": "b3a8a24496b6eb582fbcf1c874472023e1045f17c731528e7dd31105e7c169a5",
    "engines/su-sz-8.wav": "e13b8d11d004fb7bb82fe341735a729b6509683a98a360da8927d36776a9d5ea",
    "engines/tsu-1.wav": "ed92f7b3b5af4794f3df3c349b3d5d2f6b12522f019e3248e3e041a608169d51",
    "engines/tsu-2.wav": "50b58d9096e22d0e8dba76aac18f528a8504c0e8d93fb6194b72e71d7ba0d7cd",
    "engines/tsu-3.wav": "5c4b14de92e4b0cb2e0484cddd39497f2f3152dc05de8fb307896c70fd105f96",
    "engines/tsu-4.wav": "cc4517c7ac9efeadd023159ff02c6d6352481dd7596fa6e422f9fa3dac022de0",
    "engines/tsu-5.wav": "6cbbf31dfc3fbd9c58a6975f5961888508b0462b4e95d52300016d7c74d7f716",
    "engines/tsu-6.wav": "644d506062f5ecf6dc6105f47efd31bda33823fa995c8294bb2d34bd1eb47ed6",
    "engines/tsu-7.wav": "3e9dbe7c10cf393aa928f1c24cbabe4f6f893be42bf0268183178a5c55ded9e5",
}

# Engine sets: name -> [(source file, recorded rpm)]. Sources that clip
# badly are left out (the neighbours cover their rpm).
ENGINE_SETS = {
    "i6": [("engines/b-i6r-%d.wav" % k, k * 1000) for k in range(1, 9)],
    "four": [("engines/su-low-%d.wav" % k, k * 1000) for k in range(1, 8)],
    "suv4": [("engines/tsu-%d.wav" % k, k * 1000) for k in range(1, 8)],
    "diesel": [("engines/ds8-%d.wav" % k, r) for k, r in enumerate((300, 630, 1000, 1500, 2000, 2350))],
    "v8_truck": [("engines/gv8-%d.wav" % k, k * 1000) for k in range(1, 7)],
    "flat4": [("engines/su-sz-%d.wav" % k, k * 1000) for k in (1, 2, 3, 5, 6, 7, 8)],
    "v8_big": [("engines/exh-%d.wav" % k, k * 1000) for k in range(1, 7)],
}
# Diesels crank longer and clatter; petrol engines catch quickly.
STARTUP = {"diesel": dict(crank=1.0, flare=1.35, diesel=True)}

LOOP_SECONDS = 1.6
XFADE = 0.08

CRASH_SETS = {
    "impact/thud": ["crash/01.wav", "crash/02.wav", "crash/03.wav"],
    "impact/crunch": ["crash/04.wav", "crash/05.wav", "crash/09.wav"],
    "impact/crash": ["crash/06.wav", "crash/07.wav", "crash/08.wav", "crash/10.wav", "crash/11.wav", "crash/12.wav"],
}


def _sr3(fetch, rel):
    return fetch({"url": SR3 + rel, "file": "sr3_" + rel.replace("/", "_"), "sha256": SR3_FILES.get(rel)})


def _clean(x):
    x = x - np.mean(x)
    return dsp.highpass(x, 25, 2)


def engine_loop(x):
    """A seamless on-load loop from a steady recording, from its middle."""
    xf = int(XFADE * R)
    n = min(int(LOOP_SECONDS * R), len(x) - xf - 1)   # a few sources are short
    start = max(0, (len(x) - n - xf) // 2)
    return dsp.normalize_rms(dsp.make_loop(_clean(x), n, xf, start), -18.0)


def off_load(on):
    """Coasting: the same engine with the throttle shut, much less combustion
    roar (the top end and the low-mid boom drop away), a bit hollower."""
    soft = dsp.lowpass(on, 900, 2)
    x = 0.28 * on + 0.72 * soft
    x = dsp.highpass(x, 70, 2)
    return dsp.normalize_rms(x, -18.0)


def _varispeed(x, rate_env):
    """Plays x with a time-varying speed (1 = normal), looping the source."""
    pos = np.cumsum(rate_env)
    idx = np.mod(pos, len(x) - 1)
    i0 = idx.astype(int)
    frac = idx - i0
    return (x[i0] * (1 - frac) + x[i0 + 1] * frac).astype(np.float32)


def startup(idle_loop, low_loop, crank=0.7, flare=1.6, diesel=False, seed=7):
    """Starter crank, then the engine catches: revs flare up and settle to
    idle, and the sample fades out at catch + 0.8 s while VehicleAudio fades
    its loops in (STARTUP_HANDOVER after the start: the profile's
    startup_catch)."""
    nc = int(crank * R)
    t = np.arange(nc) / R
    # Starter: a geared electric whine, each compression stroke slowing it.
    comp = 5.5 if not diesel else 4.2
    wobble = 1.0 - 0.18 * (0.5 + 0.5 * np.sin(2 * np.pi * comp * t))
    f = 290 * wobble * np.clip(t / 0.12, 0.3, 1.0)
    ph = 2 * np.pi * np.cumsum(f) / R
    motor = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)
    motor = dsp.bandpass(motor.astype(np.float32), 150, 4000) * (0.6 + 0.4 * wobble)
    chug = dsp.lowpass(dsp.noise(nc, seed, "pink"), 500, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * comp * t)) ** 4
    crank_sig = dsp.normalize_rms(motor, -22) + dsp.normalize_rms(chug, -20)
    crank_sig = dsp.fade(crank_sig, 0.03, 0.08)
    # Catch: the low loop sped up, settling to idle, then fading out.
    dur = 1.3
    nk = int(dur * R)
    tk = np.arange(nk) / R
    speed = 1.0 + (flare - 1.0) * np.clip(tk / 0.18, 0, 1) * np.exp(-np.maximum(tk - 0.18, 0) * 3.2)
    catch_sig = _varispeed(low_loop, speed) * (1.0 + 0.6 * np.exp(-tk * 2.5))
    tail = _varispeed(idle_loop, np.ones(nk))
    blend = np.clip((tk - 0.5) / 0.3, 0, 1)
    catch_sig = catch_sig * (1 - blend) + tail * blend
    catch_sig *= np.clip(tk / 0.06, 0, 1) * np.clip((1.15 - tk) / 0.35, 0, 1)
    start = nc - int(0.08 * R)
    out = np.zeros(start + nk, dtype=np.float32)
    out[:nc] += crank_sig
    out[start:] += catch_sig
    return dsp.normalize_peak(out, -2.0)


# When the loops take over from the start-up sample (s after crank start).
def handover(name):
    return STARTUP.get(name, {}).get("crank", 0.7) - 0.08 + 0.8


def build(write, fetch):
    print("recorded (Stunt Rally 3, CC BY 4.0):")
    for name, files in ENGINE_SETS.items():
        ons = []
        for rel, rpm in files:
            on = engine_loop(dsp.decode(_sr3(fetch, rel)))
            ons.append((rpm, on))
            write("engine/%s/on_%d.wav" % (name, rpm), on, loop=True, rate=32000)
            write("engine/%s/off_%d.wav" % (name, rpm), off_load(on), loop=True, rate=22050)
        st = STARTUP.get(name, {})
        idle = off_load(ons[0][1]) if name != "diesel" else off_load(ons[1][1])
        low = ons[0][1] if name != "diesel" else ons[1][1]
        write("engine/%s/startup.wav" % name, startup(idle, low, **st))
    for set_name, rels in CRASH_SETS.items():
        for k, rel in enumerate(rels):
            x = _clean(dsp.decode(_sr3(fetch, rel)))
            if set_name == "impact/crash":
                # Car crashes have weight the metal recordings lack.
                n = len(x)
                t = np.arange(n) / R
                thump = np.sin(2 * np.pi * 52 * t * (1 - 0.3 * t)) * np.exp(-t * 9.0)
                x = dsp.normalize_peak(x, -2.0) + dsp.normalize_peak(thump.astype(np.float32), -4.0)
            write("%s_%d.wav" % (set_name, k + 1), dsp.fade(dsp.normalize_peak(x, -1.0), 0.0005, 0.03))
    # Bodywork scraping along the road or a wall: Halleck's metal screech.
    x = _clean(dsp.decode(_sr3(fetch, "crash/screech.wav")))
    n = int(2.6 * R)
    write("body/scrape.wav", dsp.normalize_rms(dsp.make_loop(x, n, int(0.15 * R), int(0.3 * R)), -18.0), loop=True)
    # Heavy metal hits (roll cage), cut into separate impacts at their onsets.
    x = _clean(dsp.decode(_sr3(fetch, "crash/scrap.wav")))
    for k, seg in enumerate(_onsets(x, 5)):
        write("impact/metal_%d.wav" % (k + 1), dsp.fade(dsp.normalize_peak(seg, -1.0), 0.0005, 0.04))


def _onsets(x, count, length=0.55):
    """The `count` loudest separate hits in x, each `length` s long."""
    env = np.abs(x)
    blk = int(0.01 * R)
    nb = len(env) // blk
    e = env[:nb * blk].reshape(nb, blk).max(axis=1)
    picks = []
    order = np.argsort(e)[::-1]
    for i in order:
        if all(abs(i - j) > int(length / 0.01) for j in picks):
            picks.append(i)
        if len(picks) >= count:
            break
    out = []
    for i in sorted(picks):
        s = max(0, i * blk - int(0.01 * R))
        seg = x[s:s + int(length * R)]
        if len(seg) > length * R * 0.6:
            out.append(seg)
    return out
