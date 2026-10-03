"""Shared paths and the download step for the Quaternius Downtown City MegaKit
experiment (branch experiment/quaternius-downtown-city).

Source: https://quaternius.com/packs/downtowncitymegakit.html (itch.io page
https://quaternius.itch.io/downtown-city-megakit), the free "Standard"
version, CC0 1.0. Recorded in ASSET_MANIFEST.md.

The zip (223 MB) is cached in build/asset_sources/downtown_city_megakit/
(gitignored, with a .gdignore so Godot never imports the raw kit) and
checked against the SHA-256 below. Only what the game uses is processed into
assets/ by build_megakit_textures.py (texture arrays) and
build_megakit_modules.gd (the module meshes).
"""
import hashlib
import json
import os
import re
import urllib.parse
import urllib.request
import zipfile
from http.cookiejar import CookieJar

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, "build", "asset_sources", "downtown_city_megakit")
ZIP_NAME = "Downtown_City_MegaKit_Standard.zip"
ZIP_SHA256 = "5b1a945576d54cdbb4ccc9c3d52711e6d530da74c74c586407ecc28b165335da"
EXTRACTED = os.path.join(CACHE, "extracted")
TEXTURES = os.path.join(EXTRACTED, "Textures")
GLTF = os.path.join(EXTRACTED, "Exports", "glTF (Godot)")
ITCH_PAGE = "https://quaternius.itch.io/downtown-city-megakit"
STANDARD_FILE = "Downtown City MegaKit[Standard].zip"


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _download_from_itch(dest):
    """itch.io's free-download flow (the same requests the "No thanks, just
    take me to the downloads" button makes): the page's CSRF token, then a
    signed, short-lived URL for the Standard zip."""
    jar = CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    opener.addheaders = [("User-Agent", "TurboTown-asset-fetch/1.0 (CC0 megakit pipeline)")]
    page = opener.open(ITCH_PAGE, timeout=60).read().decode("utf-8", "replace")
    csrf = re.search(r'name="csrf_token" value="([^"]+)"', page).group(1)
    upload = None
    for m in re.finditer(r'data-upload_id="(\d+)"', page):
        tail = page[m.end():m.end() + 600]
        if "[Standard]" in tail:
            upload = m.group(1)
            break
    if upload is None:
        raise SystemExit("could not find the Standard upload on %s" % ITCH_PAGE)
    data = urllib.parse.urlencode({"csrf_token": csrf}).encode()
    url = "%s/file/%s?source=view_game&as_props=1&after_download_lightbox=true" % (ITCH_PAGE, upload)
    signed = json.loads(opener.open(url, data=data, timeout=60).read())["url"]
    with opener.open(signed, timeout=600) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)


def fetch():
    """Makes sure the kit is downloaded, verified and extracted; returns EXTRACTED."""
    os.makedirs(CACHE, exist_ok=True)
    open(os.path.join(os.path.dirname(CACHE), ".gdignore"), "a").close()
    zpath = os.path.join(CACHE, ZIP_NAME)
    if not os.path.exists(zpath):
        print("downloading the Downtown City MegaKit (Standard, 223 MB) from itch.io ...")
        _download_from_itch(zpath)
    got = _sha256(zpath)
    if got != ZIP_SHA256:
        raise SystemExit("%s: sha256 %s, expected %s (the pack was updated? check the licence, then re-pin)"
                         % (zpath, got, ZIP_SHA256))
    if not os.path.isdir(GLTF):
        with zipfile.ZipFile(zpath) as z:
            z.extractall(EXTRACTED)
    return EXTRACTED


if __name__ == "__main__":
    print(fetch())
