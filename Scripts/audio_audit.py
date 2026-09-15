"""Validate the licensed library and every bundled file without requiring an audio encoder."""
from pathlib import Path
import hashlib
import json
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]

def library_files():
    root = ROOT / "Apple/App/Audio"
    manifest = root / "audio-manifest.json"
    library = json.loads(manifest.read_bytes())
    assets, sources = library["assets"], library["sources"]
    assert library["version"] == 2 and len(assets) >= 23
    assert len({a["id"] for a in assets}) == len(assets)
    assert len({a["sha256"] for a in assets}) == len(assets)
    assert len({s["id"] for s in sources}) == len(sources)
    assert not list(root.glob("*.wav")), "Obsolete generated sounds must not be bundled"
    music = [a for a in assets if a["kind"] == "music"]
    assert len(music) >= 6 and sum(a["duration"] for a in music) >= 600
    assert all(a["duration"] > 0 and a["category"] in ["Music","Ambience","Dogs","Customers","Office","Gameplay"] for a in assets)
    for source in sources:
        assert source["license"] in ["CC0","CC-BY-3.0"]
        assert source["author"] and len(source["sourceSHA256"]) == 64
        for field in ["page","url","licenseURL"]:
            parsed = urllib.parse.urlparse(source[field])
            assert parsed.scheme == "https" and parsed.hostname and not parsed.username
    files = [manifest]
    for asset in assets:
        assert asset["source"] in {s["id"] for s in sources}
        assert Path(asset["file"]).name == asset["file"] and asset["file"].endswith(".m4a")
        path = root / asset["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"], asset["id"]
        files.append(path)
    assert {p.name for p in root.glob("*.m4a")} == {a["file"] for a in assets}
    return files

def verify_bundle(app):
    for source in library_files():
        assert (app / source.name).read_bytes() == source.read_bytes(), "Bundled audio differs: " + source.name
