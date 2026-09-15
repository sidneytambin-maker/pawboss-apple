"""Reproducible licensed audio import. Source recordings stay in ignored Artifacts."""
from pathlib import Path
import array
import hashlib
import json
import math
import subprocess
import urllib.request
import zipfile
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "Artifacts/AudioSources"
OUTPUT = ROOT / "Apple/App/Audio"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

def pcm(path):
    result = subprocess.run([FFMPEG, "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "22050", "-"], capture_output=True, check=True)
    values = array.array("f"); values.frombytes(result.stdout)
    assert values and all(math.isfinite(v) for v in values)
    return values

def run():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    sources = json.loads((ROOT / "Docs/Audio-Sources.json").read_text())["sources"]
    paths = {}
    for source in sources:
        assert source["license"] in ("CC0", "CC-BY-3.0")
        path = CACHE / (source["id"] + Path(source["url"]).suffix)
        if not path.exists():
            request = urllib.request.Request(source["url"], headers={"User-Agent": "PawBoss licensed-asset import"})
            with urllib.request.urlopen(request, timeout=120) as response:
                data = response.read(80_000_001)
            assert 100 < len(data) <= 80_000_000
            path.write_bytes(data)
        paths[source["id"]] = path
        source["sourceSHA256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    specs = []
    def add(name, title, category, source, member=None, start=0, length=None, kind="effect"):
        specs.append(dict(id=name, title=title, category=category, source=source, member=member, start=start, length=length, kind=kind))
    for source, title in [(s["id"],s["title"]) for s in sources if s["id"].startswith("music-")]:
        add(source,title,"Music",source,kind="music")
    add("office-room","Working office","Office","office-room",kind="ambience")
    add("outdoor-garden","Garden birds","Ambience","outdoor-garden",kind="ambience")
    add("outdoor-rain","Rain in the grounds","Ambience","outdoor-rain",kind="ambience")
    add("arrival","Reception doorbell","Customers","arrival")
    # Select three different energetic excerpts, separated across the real recording.
    dog = pcm(paths["dog-recording"])
    for index in range(3):
        lo, hi = len(dog)*index//3, len(dog)*(index+1)//3
        windows = range(lo, max(lo+1, hi-3*22050), 11025)
        start = max(windows, key=lambda n: sum(v*v for v in dog[n:n+22050])) / 22050
        add("dog-" + str(index+1),"Dog bark " + str(index+1),"Dogs","dog-recording",start=start,length=3)
    for name,title,member in [
        ("success","Decision confirmed","confirmation_002"),("warning","Attention needed","error_004"),
        ("payment","Payment received","glass_006"),("enquiry","New enquiry","question_002"),
        ("inspection","Inspection decision","confirmation_004"),("office","Office message","select_004")]:
        add(name,title,"Gameplay" if name != "office" else "Office","interface","Audio/"+member+".ogg")
    for name,title,member,category in [
        ("construction","Construction completed","impactWood_medium_000","Gameplay"),
        ("gate","Gate latch","impactMetal_light_002","Gameplay"),
        ("footsteps","Customer footsteps","footstep_concrete_001","Customers"),
        ("care-movement","Movement in the care room","footstep_carpet_002","Dogs")]:
        add(name,title,category,"impact","Audio/"+member+".ogg")
    assets = []
    for spec in specs:
        source = paths[spec["source"]]
        if spec["member"]:
            with zipfile.ZipFile(source) as archive:
                source = CACHE / (spec["id"] + ".ogg")
                source.write_bytes(archive.read(spec["member"]))
        samples = pcm(source)
        duration = len(samples)/22050
        start = spec["start"]; length = spec["length"] or duration
        segment = samples[int(start*22050):int((start+length)*22050)]
        rms = math.sqrt(sum(v*v for v in segment)/len(segment))
        peak = max(abs(v) for v in segment)
        assert rms > 0.0001 and peak > 0.001, spec["id"] + " is silent"
        # Consistent mastering applies equally to every user; sliders apply afterwards.
        target = 0.12 if spec["kind"] == "effect" else 0.08
        gain = min(target/rms, 0.88/peak)
        filters = [f"volume={gain:.8f}", "alimiter=limit=0.80:level=false", "afade=t=in:d=0.015", f"afade=t=out:st={max(0,length-0.08):.4f}:d=0.08"]
        target_file = OUTPUT / (spec["id"]+".m4a")
        subprocess.run([FFMPEG,"-v","error","-y","-ss",str(start),"-i",str(source),"-t",str(length),
            "-map_metadata","-1","-af",",".join(filters),"-ac","2","-ar","44100","-c:a","aac","-b:a","128k","-movflags","+faststart",str(target_file)],check=True)
        check = pcm(target_file)
        assert max(abs(v) for v in check) <= 1.0 and sum(v*v for v in check) > 0, spec["id"] + " clips or is silent"
        assets.append({"id":spec["id"],"title":spec["title"],"category":spec["category"],"kind":spec["kind"],
            "file":target_file.name,"duration":round(len(check)/22050,3),"source":spec["source"],
            "sha256":hashlib.sha256(target_file.read_bytes()).hexdigest(),
            "modifications":"AAC conversion, level matching, edge fades" + ("; excerpt" if spec["length"] else "")})
        print(spec["id"],round(length,1),"seconds",flush=True)
    assert len(assets) == 23 and sum(a["duration"] for a in assets if a["kind"]=="music") >= 600
    manifest = {"version":2,"assets":assets,"sources":sources}
    (OUTPUT/"audio-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    for old in OUTPUT.glob("*.wav"):
        assert old.parent.resolve() == OUTPUT.resolve()
        old.unlink()
    print("Licensed audio prepared:",len(assets),"assets")

if __name__ == "__main__":
    run()
