"""Local structural checks. These do not compile Swift or replace native/device tests."""
from pathlib import Path
import json
import sys
from audio_audit import library_files

ROOT = Path(__file__).resolve().parents[1]
PARSER = Path(r"C:\Users\User\Documents\Codex\2026-09-03\referenced-chatgpt-conversation-this-is-an\work\swift-parser")
if PARSER.exists():
    sys.path.insert(0, str(PARSER))
from tree_sitter import Language, Parser
import tree_sitter_swift
import yaml
from PIL import Image

def validate():
    failures = []
    parser = Parser(Language(tree_sitter_swift.language()))
    sources = list((ROOT / "Apple").rglob("*.swift"))
    for path in sources:
        source = path.read_bytes()
        tree = parser.parse(source)
        def walk(node):
            if node.type == "ERROR" or node.is_missing:
                failures.append(f"{path.relative_to(ROOT)}:{node.start_point.row + 1}: {node.type}: {source[node.start_byte:node.end_byte][:100]!r}")
            for child in node.children:
                walk(child)
        walk(tree.root_node)
    project = yaml.safe_load((ROOT / "Apple/project.yml").read_text())
    release = json.loads((ROOT / "Apple/release.json").read_bytes())
    assert project["settings"]["base"]["CURRENT_PROJECT_VERSION"] == release["build"]
    assert project["settings"]["base"]["MARKETING_VERSION"] == release["version"]
    assert project["targets"]["PawBoss"]["settings"]["base"]["TARGETED_DEVICE_FAMILY"] == "1"
    assert project["targets"]["PawBossWatch"]["settings"]["base"]["TARGETED_DEVICE_FAMILY"] == "4"
    assert "ipad" not in json.dumps(project).lower().replace("supports_mac_designed_for_iphone_ipad", "")
    watch = project["targets"]["PawBoss"]["dependencies"][1]
    assert watch["copy"]["subpath"].endswith("/Watch")
    assert not project["targets"]["PawBossWatch"]["info"]["properties"]["WKRunsIndependentlyOfCompanionApp"]
    catalog = json.loads((ROOT / "Apple/Sources/PawBossCore/Resources/catalog.json").read_text())
    assert len(catalog["items"]) == len({item["id"] for item in catalog["items"]})
    assert catalog["economy"]["initialCash"] > 0
    assert catalog["economy"]["minimumHourlyPay"] >= 1271
    for item in catalog["items"]:
        assert item["price"] >= 0 and item["lifespanDays"] > 0
        assert item["layer"] in {"ground", "boundary", "building", "furniture"}
    for platform in ["Assets.xcassets", "WatchAssets.xcassets"]:
        root = ROOT / "Apple/App" / platform
        with Image.open(root / "AppIcon.appiconset/image.png") as icon:
            assert icon.size == (1024, 1024) and icon.mode == "RGB"
        for manifest in root.rglob("Contents.json"):
            content = json.loads(manifest.read_text())
            for entry in content.get("images", []):
                assert (manifest.parent / entry["filename"]).is_file()
            for entry in content.get("colors", []):
                assert entry["color"]["color-space"] == "srgb"
                assert all(0 <= float(value) <= 1 for value in entry["color"]["components"].values())
    audio = library_files()
    if failures:
        print("\n".join(failures)); return 1
    print(f"LOCAL_STRUCTURAL_CHECKS_PASS: {len(sources)} Swift files parsed; iPhone-only/Watch configuration, catalog, opaque 1024px icons and {len(audio)-1} licensed audio assets checked.")
    print("Swift type checking, XCTest, SwiftUI rendering, device accessibility and Watch delivery are NOT proven by this check.")
    return 0

if __name__ == "__main__":
    raise SystemExit(validate())
