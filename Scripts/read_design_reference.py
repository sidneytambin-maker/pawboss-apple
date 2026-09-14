"""Extract only the user-owned Windows design documents, without modifying them."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from xml.etree import ElementTree

SOURCE = Path(r"C:\Users\User\OneDrive\Documents\games\dog_daycare_business_game_starter")
ROOT = Path(__file__).resolve().parents[1]
NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}


def extract():
    destination = ROOT / "ReferenceReview"
    destination.mkdir(exist_ok=True)
    records = []
    for source in sorted(SOURCE.glob("*.docx")):
        with zipfile.ZipFile(source) as archive:
            document = ElementTree.fromstring(archive.read("word/document.xml"))
        paragraphs = ["".join(p.itertext()) for p in []]
        paragraphs = ["".join(t.text or "" for t in p.findall(".//w:t", NS))
                      for p in document.findall(".//w:p", NS)]
        text = "\n".join(p for p in paragraphs if p.strip())
        (destination / (source.stem + ".txt")).write_text(text, encoding="utf-8")
        records.append({"file": source.name, "words": len(text.split()),
                        "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    (destination / "manifest.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    extract()
