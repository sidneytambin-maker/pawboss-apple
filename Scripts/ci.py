"""Native Apple validation. Run on macOS with Xcode and XcodeGen, never claim a skipped stage passed."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APPLE = ROOT / "Apple"
ARTIFACTS = ROOT / "Artifacts"
ARCHIVE = ARTIFACTS / "PawBoss.xcarchive"
PHONE = "com.sidneytambin.pawboss"
WATCH = PHONE + ".watchkitapp"

def run(args, name, cwd=APPLE):
    ARTIFACTS.mkdir(exist_ok=True)
    with (ARTIFACTS / (name + ".log")).open("w", encoding="utf-8") as log:
        result = subprocess.run([str(a) for a in args], cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
    print(name + (": passed" if result.returncode == 0 else ": FAILED"), flush=True)
    if result.returncode:
        print((ARTIFACTS / (name + ".log")).read_text(errors="replace")[-18000:])
        raise RuntimeError(name + " failed; see retained log")

def select_xcode():
    candidates = []
    for path in Path("/Applications").glob("Xcode*.app"):
        if "beta" in path.name.lower():
            continue
        with (path / "Contents/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        version = tuple(int(part) for part in info["CFBundleShortVersionString"].split("."))
        if version >= (26,):
            candidates.append((version, path))
    if not candidates:
        raise RuntimeError("Stable Xcode 26 or newer is required")
    version, path = max(candidates)
    os.environ["DEVELOPER_DIR"] = str(path / "Contents/Developer")
    print("Using " + str(path), flush=True)
    run(["xcodebuild", "-version"], "xcode-version")

def simulator(platform):
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    candidates = []
    for runtime, devices in data["devices"].items():
        if (".iOS-" if platform == "iOS" else ".watchOS-") not in runtime:
            continue
        version = tuple(int(part) for part in re.findall(r"\d+", runtime))
        for device in devices:
            if device.get("isAvailable") and (device["name"].startswith("iPhone") if platform == "iOS" else "Apple Watch" in device["name"]):
                preferred = ("Pro Max" in device["name"]) if platform == "iOS" else ("Ultra" in device["name"])
                candidates.append((version, preferred, device["name"], device["udid"], device["state"]))
    if not candidates:
        raise RuntimeError("No available " + platform + " simulator")
    *_, identifier, state = max(candidates)
    if state != "Booted":
        run(["xcrun", "simctl", "boot", identifier], platform + "-boot")
    run(["xcrun", "simctl", "bootstatus", identifier, "-b"], platform + "-bootstatus")
    return identifier

def ui_tests(platform):
    scheme = "PawBoss" if platform == "iOS" else "PawBossWatch"
    result = ARTIFACTS / (platform + ".xcresult")
    if result.exists():
        raise RuntimeError("A result bundle already exists; preserve it and use a fresh artifacts directory")
    device = simulator(platform)
    try:
        run(["xcodebuild", "-project", "PawBoss.xcodeproj", "-scheme", scheme,
             "-destination", "id=" + device, "-parallel-testing-enabled", "NO",
             "-resultBundlePath", result, "CODE_SIGNING_ALLOWED=NO", "test"], platform + "-ui-tests")
    finally:
        if result.exists():
            summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)], capture_output=True, text=True)
            (ARTIFACTS / (platform + "-test-summary.json")).write_text(summary.stdout, encoding="utf-8")
            subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result), "--output-path", str(ARTIFACTS / (platform + "-screenshots"))], check=False)
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)

def inspect_archive(archive):
    phone = archive / "Products/Applications/PawBoss.app"
    watch = phone / "Watch/PawBossWatch.app"
    manifest = {}
    for label, app, identifier, family in [("iPhone", phone, PHONE, [1]), ("Watch", watch, WATCH, [4])]:
        assert app.is_dir(), label + " app missing from archive"
        with (app / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        assert info["CFBundleIdentifier"] == identifier
        assert info["CFBundleDisplayName"] == "PawBoss"
        assert info["UIDeviceFamily"] == family, "Unexpected device family; iPad is excluded"
        assert info["CFBundleShortVersionString"] == "0.1.0"
        assert info["CFBundleVersion"] == "1"
        assert (app / info["CFBundleExecutable"]).is_file()
        assert (app / "Assets.car").is_file(), "Compiled icon and image catalogue missing"
        assert (app / "PrivacyInfo.xcprivacy").is_file()
        catalog = list(app.glob("*.bundle/catalog.json"))
        assert len(catalog) == 1, "Shared gameplay catalog missing"
        for audio in (APPLE / "App/Audio").glob("*.wav"):
            assert (app / audio.name).is_file(), label + " audio missing: " + audio.name
        if label == "Watch":
            assert info["WKCompanionAppBundleIdentifier"] == PHONE
            assert info["WKApplication"] is True
            assert info["WKRunsIndependentlyOfCompanionApp"] is False
        manifest[label] = {"bundle": identifier, "family": family, "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"], "watchDirectory": str(watch.relative_to(phone))}
    assert not list((phone / "PlugIns").glob("*Watch*.app"))
    (ARTIFACTS / "archive-verification.json").write_text(json.dumps(manifest, indent=2))
    return manifest

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=["all", "tests", "archive", "inspect"], default="all")
    args = parser.parse_args()
    if args.stage == "inspect":
        inspect_archive(ARCHIVE)
        return
    if sys.platform != "darwin":
        raise RuntimeError("Native iOS/watchOS builds require macOS and Xcode")
    select_xcode()
    run(["xcodegen", "generate", "--spec", "project.yml"], "generate-project")
    if args.stage in ["all", "tests"]:
        failures = []
        for label, stage in [("Core", lambda: run(["swift", "test", "--parallel"], "core-tests")),
                             ("iPhone", lambda: ui_tests("iOS")), ("Watch", lambda: ui_tests("watchOS"))]:
            try:
                stage()
            except Exception as error:
                failures.append(label + ": " + str(error))
        if failures:
            raise RuntimeError("Native validation failed; no release archive created. " + "; ".join(failures))
    if args.stage in ["all", "archive"]:
        run(["xcodebuild", "-project", "PawBoss.xcodeproj", "-scheme", "PawBoss", "-configuration", "Release", "-destination", "generic/platform=iOS", "-archivePath", ARCHIVE, "CODE_SIGNING_ALLOWED=NO", "archive"], "release-archive")
        inspect_archive(ARCHIVE)
        target = ARTIFACTS / "PawBoss-unsigned-archive.zip"
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zipped:
            for path in ARCHIVE.rglob("*"):
                if path.is_file():
                    zipped.write(path, path.relative_to(ARTIFACTS))
        (ARTIFACTS / "archive-sha256.txt").write_text(hashlib.sha256(target.read_bytes()).hexdigest() + "  " + target.name + "\n")
        print("Unsigned archive verified. This is not a signed IPA or TestFlight upload.")

if __name__ == "__main__":
    main()
