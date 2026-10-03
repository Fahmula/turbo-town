"""Shared helpers for the scripts that download CC0 assets and turn them into
game textures (tools/textures/fetch_<family>.py).

Sources (both CC0, no login, no attribution required; we credit anyway):
  * Poly Haven  https://polyhaven.com   (API: api.polyhaven.com)
  * ambientCG   https://ambientcg.com   (API: ambientcg.com/api/v2)

Downloads are cached in build/texture_sources/ (gitignored) and checked
against the md5 Poly Haven publishes (ambientCG publishes none; pass a
sha256 to pin one). Outputs go to assets/textures/<family>/ and are
committed, like the audio pipeline (tools/audio/build_audio.py).

Typical use, from the project root:

    from fetch_common import *
    src = polyhaven("asphalt_02", "2k")            # {"diff": path, "nor_gl": ..., "rough": ..., "ao": ...}
    save_color(src["diff"], out("road", "road_asphalt_albedo.jpg"), 1024)
    save_normal(src["nor_gl"], out("road", "road_asphalt_normal.png"), 1024)
    save_orm(src["ao"], src["rough"], None, out("road", "road_asphalt_orm.png"), 1024)
    credit("road", "Asphalt 02", "Rob Tuytel", "https://polyhaven.com/a/asphalt_02")
    write_sources("road")

Godot imports the results with tools/textures/ conventions (ART_BIBLE.md §8):
colour maps sRGB, normal maps flagged as normal maps (OpenGL / Y+), ORM
linear (R = AO, G = roughness, B = metallic).
"""
import hashlib
import io
import json
import os
import urllib.request
import zipfile

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, "build", "texture_sources")
UA = {"User-Agent": "TurboTown-asset-fetch/1.0 (CC0 texture pipeline)"}

_credits = {}

# Poly Haven map names -> our short keys.
_PH_MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough", "AO": "ao",
            "Displacement": "disp", "arm": "arm", "Metal": "metal", "Translucent": "trans",
            "Opacity": "alpha", "alpha": "alpha"}


def _get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def download(url, md5=None, sha256=None, name=None):
    """Downloads `url` into the cache (once) and returns the local path."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name or url.rsplit("/", 1)[-1].split("?")[-1].replace("file=", ""))
    if not os.path.exists(path):
        data = _get(url)
        if md5 and hashlib.md5(data).hexdigest() != md5:
            raise RuntimeError("md5 mismatch for %s" % url)
        if sha256 and hashlib.sha256(data).hexdigest() != sha256:
            raise RuntimeError("sha256 mismatch for %s" % url)
        with open(path, "wb") as f:
            f.write(data)
    return path


def polyhaven_info(asset):
    return json.loads(_get("https://api.polyhaven.com/info/%s" % asset))


def polyhaven_files(asset):
    return json.loads(_get("https://api.polyhaven.com/files/%s" % asset))


def polyhaven(asset, res="2k", maps=("Diffuse", "nor_gl", "Rough", "AO"), fmt="jpg"):
    """A Poly Haven texture set: {"diff", "nor_gl", "rough", "ao", ...: path}.
    Maps the asset doesn't have are skipped."""
    files = polyhaven_files(asset)
    got = {}
    for m in maps:
        if m not in files or res not in files[m]:
            continue
        entry = files[m][res].get(fmt) or files[m][res].get("png") or files[m][res].get("jpg")
        got[_PH_MAPS.get(m, m)] = download(entry["url"], md5=entry.get("md5"))
    return got


def polyhaven_model(asset, res="1k"):
    """A Poly Haven model: downloads the glTF and every file it includes.
    Returns the local path of the .gltf (textures sit beside it)."""
    files = polyhaven_files(asset)
    g = files["gltf"][res]["gltf"]
    folder = os.path.join(CACHE, "models", asset + "_" + res)
    os.makedirs(folder, exist_ok=True)
    main = os.path.join(folder, g["url"].rsplit("/", 1)[-1])
    if not os.path.exists(main):
        with open(main, "wb") as f:
            f.write(_get(g["url"]))
    for rel, inc in g.get("include", {}).items():
        p = os.path.join(folder, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if not os.path.exists(p):
            with open(p, "wb") as f:
                f.write(_get(inc["url"]))
    return main


def ambientcg(asset, res="2K", sha256=None):
    """An ambientCG material: {"Color", "NormalGL", "Roughness",
    "AmbientOcclusion", "Displacement", "Opacity", ...: path} (as present)."""
    z = download("https://ambientcg.com/get?file=%s_%s-JPG.zip" % (asset, res), sha256=sha256,
                 name="%s_%s-JPG.zip" % (asset, res))
    folder = os.path.join(CACHE, "%s_%s" % (asset, res))
    if not os.path.isdir(folder):
        with zipfile.ZipFile(z) as zf:
            zf.extractall(folder)
    got = {}
    for fn in os.listdir(folder):
        stem = os.path.splitext(fn)[0]
        if "_" in stem and fn.lower().endswith((".jpg", ".png")):
            got[stem.rsplit("_", 1)[-1]] = os.path.join(folder, fn)
    return got


def out(family, filename):
    d = os.path.join(ROOT, "assets", "textures", family)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, filename)


def _fit(img, size):
    if size and img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return img


def save_color(src, dst, size=None, quality=92):
    """Colour map (sRGB). JPG unless `dst` ends in .png."""
    img = _fit(Image.open(src).convert("RGB"), size)
    if dst.lower().endswith(".png"):
        img.save(dst, optimize=True)
    else:
        img.save(dst, quality=quality, optimize=True)
    return dst


def save_normal(src, dst, size=None):
    """Normal map, OpenGL convention (Y+), as PNG."""
    img = _fit(Image.open(src).convert("RGB"), size)
    img.save(dst, optimize=True)
    return dst


def save_gray(src, dst, size=None, quality=92):
    img = _fit(Image.open(src).convert("L"), size)
    if dst.lower().endswith(".png"):
        img.save(dst, optimize=True)
    else:
        img.save(dst, quality=quality, optimize=True)
    return dst


def save_orm(ao, rough, metal, dst, size=None):
    """Packs R = AO (white if None), G = roughness, B = metallic (black if
    None) into one linear PNG."""
    r = _fit(Image.open(rough).convert("L"), size)
    a = _fit(Image.open(ao).convert("L"), size) if ao else Image.new("L", r.size, 255)
    m = _fit(Image.open(metal).convert("L"), size) if metal else Image.new("L", r.size, 0)
    Image.merge("RGB", (a, r, m)).save(dst, optimize=True)
    return dst


def credit(family, title, author, url, licence="CC0 1.0", use=""):
    _credits.setdefault(family, []).append((title, author, url, licence, use))


def write_sources(family):
    """Writes assets/textures/<family>/SOURCES.md from the credit() calls
    (ASSET_MANIFEST.md collects them)."""
    rows = _credits.get(family, [])
    lines = ["# Sources: assets/textures/%s/" % family, "",
             "Made by tools/textures/fetch_%s.py from these CC0 assets." % family, "",
             "| Asset | Author | Source | Licence | Used for |", "|---|---|---|---|---|"]
    for (title, author, url, lic, use) in rows:
        lines.append("| %s | %s | %s | %s | %s |" % (title, author, url, lic, use))
    with open(out(family, "SOURCES.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
