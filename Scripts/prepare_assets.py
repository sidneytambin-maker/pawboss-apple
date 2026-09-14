"""Export platform icon sizes and original, locally synthesised audio. No external audio licensing."""
from pathlib import Path
import argparse
import json
import math
import random
import struct
import wave
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def catalog_image(path, source, size=None):
    path.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGB")
        if size:
            image = image.resize(size, Image.Resampling.LANCZOS)
        image.save(path / "image.png")

def icons(icon, welcome):
    for name, platform in [("Assets.xcassets", "ios"), ("WatchAssets.xcassets", "watchos")]:
        root = ROOT / "Apple" / "App" / name
        dest = root / "AppIcon.appiconset"
        catalog_image(dest, icon, (1024, 1024))
        (dest / "Contents.json").write_text(json.dumps({"images": [{"filename": "image.png", "idiom": "universal", "platform": platform, "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
        for title, source, size in [("Brand", icon, (512, 512)), ("Welcome", welcome, None)]:
            dest = root / f"{title}.imageset"
            catalog_image(dest, source, size)
            (dest / "Contents.json").write_text(json.dumps({"images": [{"filename": "image.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2))

def sound(name, seconds, sample):
    root = ROOT / "Apple" / "App" / "Audio"
    root.mkdir(parents=True, exist_ok=True)
    rate = 22050
    with wave.open(str(root / f"{name}.wav"), "wb") as output:
        output.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        output.writeframes(b"".join(struct.pack("<h", round(max(-.9, min(.9, sample(i / rate))) * 32767)) for i in range(int(seconds * rate))))

def pluck(t, frequency, duration=.7):
    if t < 0 or t > duration:
        return 0
    return math.sin(2 * math.pi * frequency * t) * math.exp(-t * 7) * min(1, t * 120) * .4

def audio():
    random.seed(701)
    patterns = {"success": [523.25, 659.25, 783.99], "warning": [329.63, 261.63], "payment": [783.99, 1046.5], "enquiry": [659.25, 880], "construction": [196, 293.66, 392], "inspection": [392, 493.88, 587.33, 783.99], "arrival": [880, 659.25], "office": [1046.5, 783.99, 659.25]}
    for name, notes in patterns.items():
        sound(name, 1.7, lambda t, notes=notes: sum(pluck(t - i * .16, f) for i, f in enumerate(notes)))
    sound("dog", 1.1, lambda t: sum((math.sin(2 * math.pi * (170 - 35 * (t - start)) * (t - start)) + .3 * random.uniform(-1, 1)) * .3 * math.sin(math.pi * (t - start) / .22) ** 2 if 0 < t - start < .22 else 0 for start in [.08, .52]))
    sound("ambience", 8, lambda t: .025 * random.uniform(-1, 1) * (.5 + .5 * math.sin(math.pi * t / 8) ** 2))
    notes = [261.63, 329.63, 392, 329.63, 293.66, 349.23, 440, 349.23, 261.63, 329.63, 392, 523.25, 293.66, 392, 329.63, 261.63]
    sound("music", 16, lambda t: sum(pluck(t - i, f, 1.0) * .35 + pluck(t - i, f / 2, 1.0) * .2 for i, f in enumerate(notes)))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--icon", type=Path, required=True)
    parser.add_argument("--welcome", type=Path, required=True)
    args = parser.parse_args()
    icons(args.icon, args.welcome)
    audio()
    print("PawBoss iPhone/Watch image assets and 11 original audio files exported.")
