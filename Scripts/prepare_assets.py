"""Export platform icons. Licensed audio is imported by prepare_audio.py."""
from pathlib import Path
import argparse
import json
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

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--icon", type=Path, required=True)
    parser.add_argument("--welcome", type=Path, required=True)
    args = parser.parse_args()
    icons(args.icon, args.welcome)
    print("PawBoss iPhone/Watch images exported. Run prepare_audio.py separately for licensed audio.")
