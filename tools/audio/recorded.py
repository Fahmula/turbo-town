"""Third-party recordings for build_audio.py: where each comes from (URL +
SHA-256, licence in ASSET_MANIFEST.md) and how it's turned into game files.

Engines: Stunt Rally 3's engine loops (CryHam, CC BY 4.0, rendered in Engine
Simulator at steady rpm). Each becomes an on-load loop; an off-load
(coasting) twin is derived by filtering. Every vehicle's start-up is built
from its own engine set: a synthesised starter crank, then that engine's idle
flaring up and settling.
"""
import io
import tempfile
import zipfile
from pathlib import Path

import numpy as np

import dsp

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
STARTUP = {"diesel": dict(crank=0.95, flare=1.35, diesel=True)}

LOOP_SECONDS = 1.6
XFADE = 0.08

KENNEY = {"url": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
          "file": "kenney_impact-sounds.zip",
          "sha256": "029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8"}
# Game set -> Kenney Impact Sounds families (CC0), five takes each.
KENNEY_SETS = {
    "impact/plastic": ["impactGeneric_light", "impactSoft_medium"],
    "impact/wood": ["impactWood_medium", "impactPlank_medium"],
    "impact/metal": ["impactMetal_medium", "impactPlate_heavy"],
    "impact/debris": ["impactPlate_light", "impactTin_medium", "impactGeneric_light"],
}

# Other recordings: key -> source (URL, cache file, SHA-256). Licences and
# credits in ASSET_MANIFEST.md.
OTHER = {
    "squeal": {"url": "https://opengameart.org/sites/default/files/tires_squal_loop.wav",
               "file": "oga_tires_squal_loop.wav",
               "sha256": "2b341cfa20987388fcca9fd91d8be5056cb6c6c54abc2a97846c2be5e5a4f604"},
    "gravel": {"url": "https://svn.code.sf.net/p/trigger-rally/code/data/sounds/gravel.wav",
               "file": "triggerrally_gravel.wav",
               "sha256": "5b9af7c8e674cfcdc36037dfd6592431cd9e2d35ce59759d2aa0520f289407db"},
    "car_horn": {"url": "https://upload.wikimedia.org/wikipedia/commons/8/8c/Car_Horn.wav",
                 "file": "commons_Car_Horn.wav",
                 "sha256": "f44a161267e00c374ea6670292e70491e18f7c49a9448fc3a96960525adcfeb6"},
    "air_horn": {"url": "https://upload.wikimedia.org/wikipedia/commons/8/8a/WABCO_E2.ogg",
                 "file": "commons_WABCO_E2.ogg",
                 "sha256": "126e969ec69be5ce28effe9a599b177d8a5b56d432243e2129fc6fae18dad349"},
    "big_horn": {"url": "https://upload.wikimedia.org/wikipedia/commons/9/9c/Leslie_S-3L.ogg",
                 "file": "commons_Leslie_S-3L.ogg",
                 "sha256": "fa61d95ac7a43ff52d4ef26518bdb306042f025f1fc1df9be4f1aefdf1ce7eb1"},
    "start": {"url": "https://upload.wikimedia.org/wikipedia/commons/3/3d/1997AccordSE_enginestart.ogg",
              "file": "commons_1997AccordSE_enginestart.ogg",
              "sha256": "6f669e2aa51f965467f992a157f4e5809282e0b6d93b02a78aa851944fe7253c"},
    "air_brake": {"url": "https://soundbible.com/grab.php?id=525&type=wav",
                  "file": "soundbible_525.wav",
                  "sha256": "fe336bc56b84aa4ddf237677c1d16339b50c654dfcf4fa4c9cf668f991f98728"},
    "window": {"url": "https://soundbible.com/grab.php?id=392&type=wav",
               "file": "soundbible_392.wav",
               "sha256": "52ebbc883d1ffb8b2427236b7be57f3b0b30c1fdf3cdbaad26c98305d0413051"},
    "glass_tw": {"url": "https://opengameart.org/sites/default/files/glass_breaking.wav",
                 "file": "oga_glass_breaking.wav",
                 "sha256": "37d29069c885afe3f7ca639293fa679fb6511a6a1e54316f0e403e4493f502b3"},
    "breaking": {"url": "https://opengameart.org/sites/default/files/sfx_breaking_and_falling.zip",
                 "file": "oga_sfx_breaking_and_falling.zip",
                 "sha256": "e6ee04d91c5f4d30cfda1260d2c9d1faf96fda36319287215fbd07bcb1a80451"},
    "metal27": {"url": "https://opengameart.org/sites/default/files/27-Metal-Audio-Samples-blacklodgegames.com_.zip",
                "file": "oga_27_metal.zip",
                "sha256": "479e85403898c2ff2d1e2d6a130b8cfb4ae00fbd8cbcaf440917450f996f5232"},
}
# The Accord's starter: four compression strokes before it catches.
CRANK = (0.1, 0.47)

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
    """Plays the loop x with a time-varying speed (1 = normal), wrapping
    round its seam."""
    n = len(x)
    idx = np.mod(np.cumsum(rate_env), n)
    i0 = idx.astype(int) % n
    frac = idx - np.floor(idx)
    return (x[i0] * (1 - frac) + x[(i0 + 1) % n] * frac).astype(np.float32)


def startup(idle_loop, low_loop, crank_rec, crank=0.7, flare=1.6, diesel=False):
    """A real starter crank (`crank_rec`, cranked longer and slower for a
    diesel), then the engine catches: revs flare up and settle to idle, and
    the sample fades out at catch + 0.8 s while VehicleAudio fades its loops
    in (handover(): the profile's startup_catch)."""
    rec = dsp.highpass(crank_rec, 60, 2)
    if diesel:
        # Slower and longer: the slowed crank twice, crossfaded.
        slow = dsp.resample(rec, 0.8)
        xf = int(0.03 * R)
        first = slow[:int(0.42 * R)]
        second = slow.copy()
        t = np.linspace(0, 1, xf)
        joint = first[-xf:] * np.cos(t * np.pi / 2) + second[:xf] * np.sin(t * np.pi / 2)
        rec = np.concatenate([first[:-xf], joint, second[xf:]]).astype(np.float32)
    # The recording sets the crank's length (a decode can be a few ms short).
    rec = dsp.fade(rec, 0.01, 0.08)
    nc = min(int(crank * R), len(rec))
    crank_sig = dsp.normalize_rms(rec[:nc].astype(np.float32), -18)
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
    return STARTUP.get(name, {}).get("crank", CRANK[1] - CRANK[0]) - 0.08 + 0.8


def build(write, fetch):
    crank_rec = _clean(dsp.decode(fetch(OTHER["start"]), CRANK[0], CRANK[1] - CRANK[0]))
    print("recorded (Stunt Rally 3, CC BY 4.0):")
    for name, files in ENGINE_SETS.items():
        ons = []
        for rel, rpm in files:
            on = engine_loop(dsp.decode(_sr3(fetch, rel)))
            ons.append((rpm, on))
            write("engine/%s/on_%d.wav" % (name, rpm), on, loop=True, rate=32000)
            write("engine/%s/off_%d.wav" % (name, rpm), off_load(on), loop=True, rate=22050)
        st = dict(STARTUP.get(name, {"crank": CRANK[1] - CRANK[0]}))
        idle = off_load(ons[0][1]) if name != "diesel" else off_load(ons[1][1])
        low = ons[0][1] if name != "diesel" else ons[1][1]
        write("engine/%s/startup.wav" % name, startup(idle, low, crank_rec, **st))
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
    # Heavy metal hits (roll cage), cut into separate impacts at their onsets:
    # the bodywork deforming under a big crash.
    x = _clean(dsp.decode(_sr3(fetch, "crash/scrap.wav")))
    for k, seg in enumerate(_onsets(x, 5)):
        write("impact/deform_%d.wav" % (k + 1), dsp.fade(dsp.normalize_peak(seg, -1.0), 0.0005, 0.04))
    build_kenney(write, fetch)
    build_other(write, fetch)


def _kenney(zf, name):
    """Decodes one Kenney OGG (from the zip) to mono float32."""
    data = zf.read("Audio/%s.ogg" % name)
    with tempfile.NamedTemporaryFile(suffix=".ogg") as tmp:
        tmp.write(data)
        tmp.flush()
        return _clean(dsp.decode(tmp.name))


def _cascade(hits, seed, heavy, count, spread, decay):
    """A glass shatter from single glass hits: one heavy crack, then a
    shower of smaller pieces at random times, quieter and higher as it goes."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int((spread + 0.6) * R), dtype=np.float32)
    first = dsp.normalize_peak(heavy, -1.0)
    out[:len(first)] += first[:len(out)]
    for k in range(count):
        h = hits[rng.integers(len(hits))]
        h = dsp.resample(h, rng.uniform(0.9, 1.5))
        at = int((spread * rng.random() ** 2.2 + 0.005) * R)
        amp = 10 ** (-(rng.uniform(4, 14) + decay * at / R) / 20)
        end = min(len(out), at + len(h))
        out[at:end] += dsp.normalize_peak(h, 0.0)[:end - at] * amp
    return dsp.fade(dsp.normalize_peak(out, -1.0), 0.0005, 0.12)


def build_kenney(write, fetch):
    print("recorded (Kenney Impact Sounds, CC0):")
    zf = zipfile.ZipFile(io.BytesIO(Path(fetch(KENNEY)).read_bytes()))
    for set_name, families in KENNEY_SETS.items():
        k = 0
        for fam in families:
            for take in range(5):
                k += 1
                x = _kenney(zf, "%s_%03d" % (fam, take))
                write("%s_%d.wav" % (set_name, k), dsp.fade(dsp.normalize_peak(x, -1.0), 0.0005, 0.03))
    glass_heavy = [_kenney(zf, "impactGlass_heavy_%03d" % t) for t in range(5)]
    glass_small = [_kenney(zf, "impactGlass_light_%03d" % t) for t in range(5)] + \
                  [_kenney(zf, "impactGlass_medium_%03d" % t) for t in range(5)]
    # Built shatters, after the recorded ones (glass_1-6, tinkle_1-3, build_other).
    for k in range(2):
        write("impact/glass_%d.wav" % (k + 7), _cascade(glass_small, 700 + k, glass_heavy[k], 42, 0.6, 12.0))
    for k in range(2):
        write("impact/tinkle_%d.wav" % (k + 4), _cascade(glass_small, 800 + k, glass_small[k + 5], 13, 0.35, 18.0))


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


def _period_loop(x, f0, seconds, xfade=0.01):
    """A loop of a steady pitched sound cut to a whole number of periods of
    f0 (so the seam lines up), lightly crossfaded."""
    period = R / f0
    n = int(round(round(seconds * f0) * period))
    return dsp.make_loop(x, n, int(xfade * R))


def build_other(write, fetch):
    print("recorded (other CC0 / CC BY sources):")
    # Tyre squeal: qubodup's loop (CC BY 3.0).
    x = _clean(dsp.decode(fetch(OTHER["squeal"])))
    write("tyre/squeal.wav", dsp.normalize_rms(dsp.make_loop(x, len(x) - int(0.12 * R) - 1, int(0.12 * R)), -18.0),
          loop=True, rate=32000)
    # Gravel under the tyres, rolling and sliding (CC0).
    x = _clean(dsp.decode(fetch(OTHER["gravel"])))
    n = int(3.6 * R)
    roll = dsp.make_loop(x, n, int(0.15 * R), int(0.1 * R))
    write("tyre/roll_gravel.wav", dsp.normalize_rms(roll, -20.0), loop=True, rate=32000)
    slide = dsp.highpass(dsp.make_loop(x, n, int(0.15 * R), int(0.5 * R)), 250, 2)
    slide = dsp.peaks(slide, [(1800, 0.8, 1.0), (3500, 1.0, 0.7)]) + 0.5 * slide
    write("tyre/skid_gravel.wav", dsp.normalize_rms(slide, -18.0), loop=True, rate=32000)
    # Horns: a real car horn (350 Hz pair), a two-chime and a three-chime air
    # horn (CC0). Steady stretches looped on whole periods; the air horns'
    # recordings tick above 10 kHz, so they're low-passed.
    x = _clean(dsp.decode(fetch(OTHER["car_horn"])))
    write("horn/car.wav", dsp.normalize_rms(_period_loop(x[int(1.97 * R):], 350.0, 0.15), -14.0), loop=True)
    x = dsp.lowpass(_clean(dsp.decode(fetch(OTHER["air_horn"]))), 8500, 4)
    write("horn/air.wav", dsp.normalize_rms(_period_loop(x[int(9.0 * R):], R / 293.0, 1.0, 0.03), -14.0), loop=True)
    x = dsp.lowpass(_clean(dsp.decode(fetch(OTHER["big_horn"]))), 8500, 4)
    write("horn/air_big.wav", dsp.normalize_rms(dsp.make_loop(x, int(1.0 * R), int(0.08 * R), int(10.0 * R)), -14.0), loop=True)
    # Air brakes: the release hiss, without the idling engine under it (CC BY 3.0).
    x = _clean(dsp.decode(fetch(OTHER["air_brake"]), 2.65, 1.75))
    write("brake/air_1.wav", dsp.fade(dsp.normalize_peak(dsp.highpass(x, 300, 2), -1.0), 0.005, 0.25))
    # Glass: a car window shattering (CC BY 3.0) and CC0 glass breaks.
    x = _clean(dsp.decode(fetch(OTHER["window"])))
    for k, (a, b) in enumerate(((0.05, 1.6), (1.22, 2.6))):
        write("impact/glass_%d.wav" % (k + 1), dsp.fade(dsp.normalize_peak(x[int(a * R):int(b * R)], -1.0), 0.003, 0.3))
    x = _clean(dsp.decode(fetch(OTHER["glass_tw"])))
    write("impact/glass_3.wav", dsp.fade(dsp.normalize_peak(x, -1.0), 0.002, 0.15))
    zf = zipfile.ZipFile(io.BytesIO(Path(fetch(OTHER["breaking"])).read_bytes()))
    for k in range(6):
        x = _zip_audio(zf, "bfh1_glass_breaking_%02d.ogg" % (k + 1))
        name = "impact/glass_%d.wav" % (k + 4) if k < 3 else "impact/tinkle_%d.wav" % (k - 2)
        write(name, dsp.fade(dsp.normalize_peak(x, -1.0), 0.002, 0.1))
    # More crash variety: blacklodgegames' dull metal collisions (CC0).
    zf = zipfile.ZipFile(io.BytesIO(Path(fetch(OTHER["metal27"])).read_bytes()))
    base = "27-Metal-Audio-Samples-blacklodgegames.com/dull_metal_collision_%02d_44k_32bit_stereo.wav"
    for set_name, start, takes in (("impact/thud", 4, (3, 4, 9)), ("impact/crunch", 4, (1, 5, 6, 13)),
                                    ("impact/deform", 5, (7, 10, 12))):
        for i, take in enumerate(takes):
            x = _zip_audio(zf, base % take)
            write("%s_%d.wav" % (set_name, start + i), dsp.fade(dsp.normalize_peak(x, -1.0), 0.0005, 0.05))


def _zip_audio(zf, name):
    with tempfile.NamedTemporaryFile(suffix=Path(name).suffix) as tmp:
        tmp.write(zf.read(name))
        tmp.flush()
        return _clean(dsp.decode(tmp.name))
