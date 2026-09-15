"""Sign a fully tested PawBoss archive locally; no private key is sent to GitHub."""
import argparse
import base64
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import zipfile
from pathlib import Path

from apple_setup import Apple, BUNDLES, ROOT, TEAM
from audio_audit import verify_bundle

REPOSITORY = "sidneytambin-maker/pawboss-apple"
RELEASE = json.loads((ROOT / "Apple/release.json").read_bytes())

def gh(*args):
    return subprocess.check_output(["gh", *args], cwd=ROOT, text=True)

def validated_run(run_id, evidence):
    run = json.loads(gh("api", f"repos/{REPOSITORY}/actions/runs/{run_id}"))
    assert run["head_branch"] == "main" and run["path"] == ".github/workflows/apple.yml"
    assert run["conclusion"] == "success", "A failed or unfinished native build cannot be released"
    jobs = json.loads(gh("api", f"repos/{REPOSITORY}/actions/runs/{run_id}/jobs"))["jobs"]
    assert any(j["name"] == "native-validation" and j["conclusion"] == "success" for j in jobs)
    subprocess.run(["git", "merge-base", "--is-ancestor", run["head_sha"], "HEAD"], cwd=ROOT, check=True)
    diff = subprocess.check_output(["git", "diff", run["head_sha"], "--", "Apple", "Scripts/ci.py", ".github/workflows/apple.yml"], cwd=ROOT)
    assert not diff, "Native sources and build configuration must match the tested revision"
    for platform, folder in [("iOS", "UITests"), ("watchOS", "WatchUITests")]:
        summary = json.loads((evidence / (platform + "-test-summary.json")).read_bytes())
        expected = sum(len(re.findall(r"func test\w+\s*\(", p.read_text())) for p in (ROOT / "Apple" / folder).glob("*.swift"))
        assert summary["failedTests"] == 0 and summary["skippedTests"] == 0
        assert summary["passedTests"] == expected and summary["totalTestCount"] == expected, platform + " test count mismatch"
    log = (evidence / "core-tests.log").read_text(errors="replace")
    expected_core = sum(len(re.findall(r"func test\w+\s*\(", p.read_text())) for p in (ROOT / "Apple/Tests").rglob("*.swift"))
    executed = re.findall(r"\[(\d+)/(\d+)\] Testing PawBossCoreTests\.\S+", log)
    assert len(executed) == expected_core and {int(i) for i, _ in executed} == set(range(1, expected_core + 1))
    assert all(int(total) == expected_core for _, total in executed) and "error:" not in log
    verification = json.loads((evidence / "archive-verification.json").read_bytes())
    assert verification["iPhone"]["bundle"] == BUNDLES["Phone"] and verification["Watch"]["bundle"] == BUNDLES["Watch"]
    return run

def decode_profile(data, openssl):
    result = subprocess.run([str(openssl), "cms", "-verify", "-binary", "-inform", "DER", "-noverify"], input=data, capture_output=True)
    assert result.returncode == 0, "Provisioning profile CMS verification failed"
    return plistlib.loads(result.stdout)

def distribution_entitlements(bundle):
    assert bundle in BUNDLES.values()
    return {"application-identifier": TEAM + "." + bundle, "com.apple.developer.team-identifier": TEAM,
            "get-task-allow": False, "beta-reports-active": True}

def check_profile(profile, bundle, certificate):
    assert profile["TeamIdentifier"] == [TEAM]
    assert profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc).timestamp() > time.time() + 86400
    assert not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices")
    assert certificate in profile["DeveloperCertificates"]
    entitlements = profile["Entitlements"]
    for key, value in distribution_entitlements(bundle).items():
        assert entitlements.get(key) == value, "Incorrect distribution entitlement: " + key

def prepare_app(evidence, destination):
    source = evidence / "PawBoss.xcarchive/Products/Applications/PawBoss.app"
    if os.name == "nt":
        source = Path("\\\\?\\" + str(source.resolve()))
    assert source.is_dir() and not destination.exists()
    shutil.copytree(source, destination)
    for label, app, family in [("Phone", destination, [1]), ("Watch", destination / "Watch/PawBossWatch.app", [4])]:
        info = plistlib.loads((app / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == BUNDLES[label] and info["CFBundleDisplayName"] == "PawBoss"
        assert info["CFBundleVersion"] == RELEASE["build"] and info["CFBundleShortVersionString"] == RELEASE["version"]
        assert info["UIDeviceFamily"] == family
        banks = list(app.glob("*.bundle/catalog.json"))
        assert len(banks) == 1 and banks[0].read_bytes() == (ROOT / "Apple/Sources/PawBossCore/Resources/catalog.json").read_bytes()
        verify_bundle(app)
        if label == "Watch":
            assert info["WKCompanionAppBundleIdentifier"] == BUNDLES["Phone"] and info["WKApplication"]
    return source

def make_ipa(app, target):
    executables = set()
    for info_path in app.rglob("Info.plist"):
        info = plistlib.loads(info_path.read_bytes())
        if info.get("CFBundleExecutable"):
            executables.add(info_path.parent / info["CFBundleExecutable"])
    with zipfile.ZipFile(target, "x", zipfile.ZIP_DEFLATED) as package:
        for file in sorted(app.rglob("*")):
            assert not file.is_symlink(), "Unexpected symbolic link in app bundle"
            if not file.is_file():
                continue
            entry = zipfile.ZipInfo("Payload/PawBoss.app/" + file.relative_to(app).as_posix())
            entry.create_system = 3
            entry.external_attr = (0o100755 if file in executables else 0o100644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(entry, file.read_bytes())

def signing_command(args, label, target):
    assert label in BUNDLES
    # A Windows drive colon is interpreted as a signing scope. Resolve this
    # basename from the protected temporary working directory instead.
    return [str(args.rcodesign), "sign", "--shallow", "--p12-file", str(args.certificate_file),
            "--p12-password-file", str(args.password_file), "--team-name", TEAM, "--timestamp-url", "none",
            "--entitlements-xml-file", label + ".plist", str(target)]

def sign(args):
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.serialization import pkcs12
    evidence, output = args.evidence.resolve(), args.output.resolve()
    run = validated_run(args.run, evidence)
    output.mkdir(parents=True, exist_ok=False)
    app = output / "PawBoss.app"
    prepare_app(evidence, app)
    password = args.password_file.read_bytes().strip()
    private, certificate, chain = pkcs12.load_key_and_certificates(args.certificate_file.read_bytes(), password)
    assert private and certificate
    assert certificate.subject.get_attributes_for_oid(x509.oid.NameOID.ORGANIZATIONAL_UNIT_NAME)[0].value == TEAM
    assert certificate.not_valid_after_utc.timestamp() > time.time() + 86400
    der = certificate.public_bytes(serialization.Encoding.DER)
    apple = Apple(args.key_file.read_bytes(), args.key_id, args.issuer)
    certificates = apple.request("GET", "certificates?filter[certificateType]=DISTRIBUTION&limit=200")["data"]
    assert any(base64.b64decode(c["attributes"]["certificateContent"]) == der for c in certificates)
    profiles = {}
    with tempfile.TemporaryDirectory(prefix="pawboss-sign-", dir=args.key_file.parent) as temporary:
        temporary = Path(temporary)
        for label, bundle in BUNDLES.items():
            query = urllib.parse.urlencode({"filter[name]": "PawBoss " + label + " App Store", "filter[profileState]": "ACTIVE"})
            records = apple.request("GET", "profiles?" + query)["data"]
            assert len(records) == 1
            data = base64.b64decode(records[0]["attributes"]["profileContent"])
            profile = decode_profile(data, args.openssl)
            check_profile(profile, bundle, der)
            target = app if label == "Phone" else app / "Watch/PawBossWatch.app"
            (target / "embedded.mobileprovision").write_bytes(data)
            (temporary / (label + ".plist")).write_bytes(plistlib.dumps(distribution_entitlements(bundle)))
            profiles[label] = {"id": records[0]["id"], "uuid": profile["UUID"], "bundle": bundle}
        for label in ["Watch", "Phone"]:
            target = app if label == "Phone" else app / "Watch/PawBossWatch.app"
            command = signing_command(args, label, target)
            result = subprocess.run(command, cwd=temporary, capture_output=True)
            log = (result.stdout + result.stderr).replace(password, b"[REDACTED]")
            (output / (label + "-signing.log")).write_bytes(log)
            assert result.returncode == 0, label + " signing failed; see protected local log"
    (output / "distribution-certificate.pem").write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    ipa = output / "PawBoss.ipa"
    make_ipa(app, ipa)
    receipt = {"validatedRun": str(args.run), "sourceRevision": run["head_sha"], **RELEASE,
               "ipaSHA256": hashlib.sha256(ipa.read_bytes()).hexdigest(), "profiles": profiles, "signedLocally": True,
               "signatureInspectionComplete": False, "uploaded": False}
    (output / "local-signing.json").write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True)
    for name in ["evidence", "output", "key-file", "certificate-file", "password-file", "rcodesign", "openssl"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    sign(parser.parse_args())
