"""Independent verification of PawBoss content and signatures, not Apple trust evaluation."""
import argparse
import hashlib
import json
import os
import plistlib
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from local_sign import BUNDLES, TEAM, ROOT, check_profile, decode_profile, distribution_entitlements, validated_run
from macho_seals import check_bundle, signature_blobs, slices

def native_sections(data):
    wide = data[:4] == b"\xcf\xfa\xed\xfe"
    assert wide or data[:4] == b"\xce\xfa\xed\xfe"
    cursor, sections = (32 if wide else 28), []
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, length = struct.unpack_from("<II", data, cursor)
        assert length >= 8 and cursor + length <= len(data)
        if command in (1, 0x19):
            segment_wide = command == 0x19
            count = struct.unpack_from("<I", data, cursor + (64 if segment_wide else 48))[0]
            section = cursor + (72 if segment_wide else 56)
            for _ in range(count):
                name = data[section:section + 32]
                address, size = struct.unpack_from("<QQ" if segment_wide else "<II", data, section + 32)
                offset = struct.unpack_from("<I", data, section + (48 if segment_wide else 40))[0]
                flags = struct.unpack_from("<I", data, section + (64 if segment_wide else 56))[0]
                empty = flags & 0xff in (1, 0xc, 0x12)
                assert empty or offset + size <= len(data)
                digest = None if empty else hashlib.sha256(data[offset:offset + size]).hexdigest()
                sections.append((name, address, size, flags, digest))
                section += 80 if segment_wide else 68
        cursor += length
    assert sections
    return sections

def cms_signature(blobs, certificate, openssl, directory, bundle):
    assert {0, 2, 5, 7, 0x10000} <= set(blobs), "Full CMS, requirements and XML/DER entitlements required"
    cd = blobs[0]
    flags, identifier_offset = struct.unpack_from(">I", cd, 12)[0], struct.unpack_from(">I", cd, 20)[0]
    assert not flags & 2, "Ad-hoc signatures cannot be distributed"
    assert cd[identifier_offset:].split(b"\0", 1)[0].decode() == bundle
    assert struct.unpack_from(">I", cd, 8)[0] >= 0x20200
    team_offset = struct.unpack_from(">I", cd, 48)[0]
    assert cd[team_offset:].split(b"\0", 1)[0].decode() == TEAM
    (directory / "cd.bin").write_bytes(cd)
    (directory / "signature.der").write_bytes(blobs[0x10000][8:])
    result = subprocess.run([str(openssl), "cms", "-verify", "-binary", "-inform", "DER",
        "-in", str(directory / "signature.der"), "-content", str(directory / "cd.bin"),
        "-nointern", "-certfile", str(certificate), "-noverify"], capture_output=True)
    assert result.returncode == 0 and result.stdout == cd, "CMS signer/digest verification failed"

def inspect(directory, evidence, openssl):
    receipt_path = directory / "local-signing.json"
    receipt = json.loads(receipt_path.read_bytes())
    run = validated_run(receipt["validatedRun"], evidence)
    assert receipt["sourceRevision"] == run["head_sha"] and receipt["build"] == "1"
    ipa = directory / "PawBoss.ipa"
    assert hashlib.sha256(ipa.read_bytes()).hexdigest() == receipt["ipaSHA256"]
    certificate = directory / "distribution-certificate.pem"
    cert_der = x509.load_pem_x509_certificate(certificate.read_bytes()).public_bytes(serialization.Encoding.DER)
    source = evidence / "PawBoss.xcarchive/Products/Applications/PawBoss.app"
    if os.name == "nt":
        source = Path("\\\\?\\" + str(source.resolve()))
    expected_catalog = (ROOT / "Apple/Sources/PawBossCore/Resources/catalog.json").read_bytes()
    reports = []
    with zipfile.ZipFile(ipa) as package, tempfile.TemporaryDirectory() as temporary:
        assert package.testzip() is None
        names = package.namelist()
        assert len(names) == len(set(names))
        assert all(n.startswith("Payload/PawBoss.app/") and ".." not in Path(n).parts for n in names)
        assert not any(n.lower().endswith((".p8", ".p12", ".pem")) for n in names)
        for label, relative in [("Phone", ""), ("Watch", "Watch/PawBossWatch.app/")]:
            prefix = "Payload/PawBoss.app/" + relative
            info = plistlib.loads(package.read(prefix + "Info.plist"))
            assert info["CFBundleIdentifier"] == BUNDLES[label] and info["CFBundleDisplayName"] == "PawBoss"
            assert info["CFBundleVersion"] == receipt["build"] and info["CFBundleShortVersionString"] == "0.1.0"
            assert info["UIDeviceFamily"] == ([1] if label == "Phone" else [4])
            if label == "Watch":
                assert info["WKApplication"] and info["WKCompanionAppBundleIdentifier"] == BUNDLES["Phone"]
            assert info == plistlib.loads((source / relative / "Info.plist").read_bytes()), "Tested app metadata changed"
            profile = decode_profile(package.read(prefix + "embedded.mobileprovision"), openssl)
            check_profile(profile, BUNDLES[label], cert_der)
            assert profile["UUID"] == receipt["profiles"][label]["uuid"]
            signed_slices = list(slices(package.read(prefix + info["CFBundleExecutable"])))
            source_slices = list(slices((source / relative / info["CFBundleExecutable"]).read_bytes()))
            assert len(signed_slices) == len(source_slices)
            for signed, unsigned in zip(signed_slices, source_slices):
                assert signed[4:12] == unsigned[4:12], "Native architecture changed"
                assert native_sections(signed) == native_sections(unsigned), "Tested native code/data changed"
                blobs = signature_blobs(signed)
                if label == "Watch":
                    assert blobs[0][37] == 1 and blobs.get(0x1000, b"")[37:38] == b"\x02", "Watch requires its platform SHA1/SHA256 directories"
                assert plistlib.loads(blobs[5][8:]) == distribution_entitlements(BUNDLES[label])
                cms_signature(blobs, certificate, openssl, Path(temporary), BUNDLES[label])
            report = check_bundle(package, prefix)
            assert not report["failures"], "Signed content seal failed"
            own = [n for n in names if n.startswith(prefix) and ".app/" not in n[len(prefix):]]
            catalogs = [n for n in own if n.endswith("catalog.json")]
            assert len(catalogs) == 1 and package.read(catalogs[0]) == expected_catalog
            assert prefix + "Assets.car" in names and prefix + "PrivacyInfo.xcprivacy" in names
            reports.append({**report, "cmsSignerVerified": True, "nativeSectionsUnchanged": True})
        binaries = {"PawBoss", "Watch/PawBossWatch.app/PawBossWatch"}
        for file in source.rglob("*"):
            if file.is_file():
                relative = file.relative_to(source).as_posix()
                if relative not in binaries and "_CodeSignature/" not in relative:
                    assert package.read("Payload/PawBoss.app/" + relative) == file.read_bytes(), relative + " changed"
    receipt["signatureInspectionComplete"] = True
    receipt["signatureChecks"] = reports
    receipt["nativePlatformTrustVerification"] = "Independent content/CMS verification only; Apple processing and beta availability are separate"
    receipt_path.write_text(json.dumps(receipt, indent=2))
    print(json.dumps(receipt))
    return receipt

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ["directory", "evidence", "openssl"]:
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    inspect(args.directory.resolve(), args.evidence.resolve(), args.openssl)
