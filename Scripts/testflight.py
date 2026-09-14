"""PawBoss-only TestFlight configuration, gated by native tests and verified Apple processing."""
import argparse
import json
import re
import urllib.parse
from pathlib import Path

from apple_setup import Apple, BUNDLES, ROOT
from direct_upload import APP_ID, state as upload_state

def query(resource, **filters):
    return resource + "?" + urllib.parse.urlencode({"filter[" + k + "]": v for k, v in filters.items()})

def exact_app(apple):
    app = apple.request("GET", "apps/" + APP_ID)["data"]
    assert app["attributes"]["bundleId"] == BUNDLES["Phone"] and app["attributes"]["name"] == "PawBoss"

def checked_build(apple, number):
    exact_app(apple)
    records = apple.request("GET", query("builds", app=APP_ID, version=str(number)))["data"]
    assert len(records) == 1, "Exact PawBoss build has not appeared yet"
    build = records[0]
    attrs = build["attributes"]
    assert attrs["processingState"] == "VALID" and attrs["expired"] is False
    assert attrs["usesNonExemptEncryption"] is False
    assert apple.request("GET", "builds/" + build["id"] + "/app")["data"]["id"] == APP_ID
    version = apple.request("GET", "builds/" + build["id"] + "/preReleaseVersion")["data"]["attributes"]
    assert version["version"] == "0.1.0" and version["platform"] == "IOS"
    return build["id"]

def groups(apple, metadata):
    all_groups = apple.request("GET", query("betaGroups", app=APP_ID))["data"]
    result = []
    for name, internal in [(metadata["internalGroup"], True), (metadata["externalGroup"], False)]:
        matches = [g for g in all_groups if g["attributes"]["name"] == name]
        assert len(matches) == 1 and matches[0]["attributes"]["isInternalGroup"] is internal
        group = matches[0]
        assert apple.request("GET", "betaGroups/" + group["id"] + "/app")["data"]["id"] == APP_ID
        result.append(group)
    return result

def configure(apple, metadata, contact):
    exact_app(apple)
    assert metadata["name"] == "PawBoss"
    assert contact["contactFirstName"].lower() == "sidney" and contact["contactLastName"].lower() == "tambin"
    assert re.fullmatch(r"\+?[0-9 ()-]{7,30}", contact["contactPhone"])
    assert "@" in contact["contactEmail"]
    for key in ["description", "whatToTest", "reviewNotes"]:
        assert 20 <= len(metadata[key]) <= 4000
    base = "apps/" + APP_ID
    localizations = apple.request("GET", base + "/betaAppLocalizations")["data"]
    attrs = {"description": metadata["description"], "feedbackEmail": contact["contactEmail"]}
    locale = next((l for l in localizations if l["attributes"]["locale"] == metadata["primaryLocale"]), None)
    if locale:
        apple.request("PATCH", "betaAppLocalizations/" + locale["id"], {"data": {"id": locale["id"], "type": "betaAppLocalizations", "attributes": attrs}})
    else:
        apple.request("POST", "betaAppLocalizations", {"data": {"type": "betaAppLocalizations", "attributes": {"locale": metadata["primaryLocale"], **attrs}, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    detail = apple.request("GET", base + "/betaAppReviewDetail")["data"]
    fields = {key: contact[key] for key in ["contactFirstName", "contactLastName", "contactEmail", "contactPhone"]}
    fields.update({"demoAccountRequired": False, "notes": metadata["reviewNotes"]})
    apple.request("PATCH", "betaAppReviewDetails/" + detail["id"], {"data": {"id": detail["id"], "type": "betaAppReviewDetails", "attributes": fields}})
    all_groups = apple.request("GET", query("betaGroups", app=APP_ID))["data"]
    for name, internal in [(metadata["internalGroup"], True), (metadata["externalGroup"], False)]:
        if not any(g["attributes"]["name"] == name for g in all_groups):
            apple.request("POST", "betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": name, "isInternalGroup": internal, "hasAccessToAllBuilds": False, "feedbackEnabled": True, "publicLinkEnabled": False}, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
    saved = apple.request("GET", base + "/betaAppLocalizations")["data"]
    assert any(l["attributes"]["locale"] == metadata["primaryLocale"] and all(l["attributes"].get(k) == v for k, v in attrs.items()) for l in saved)
    saved_review = apple.request("GET", base + "/betaAppReviewDetail")["data"]["attributes"]
    assert all(saved_review.get(k) == v for k, v in fields.items())
    return groups(apple, metadata)

def publish(apple, directory, evidence, openssl, metadata, contact):
    from inspect_local_ipa import inspect
    signing = inspect(directory, evidence, openssl)
    receipt = json.loads((directory / "direct-upload.json").read_bytes())
    upload = upload_state(apple, receipt)
    build = checked_build(apple, receipt["build"])
    assert receipt["app"] == APP_ID and receipt["sha256"] == signing["ipaSHA256"]
    assert receipt["build"] == signing["build"] == upload["build"]
    assert receipt["uploaded"] and receipt["allPartChecksumsVerified"] and signing["signatureInspectionComplete"]
    assert upload["state"]["state"] == "COMPLETE" and not upload["state"].get("errors")
    assert upload["buildResource"] == {"type": "builds", "id": build}
    configured = configure(apple, metadata, contact)
    localizations = apple.request("GET", "builds/" + build + "/betaBuildLocalizations")["data"]
    locale = next((l for l in localizations if l["attributes"]["locale"] == metadata["primaryLocale"]), None)
    if locale:
        apple.request("PATCH", "betaBuildLocalizations/" + locale["id"], {"data": {"id": locale["id"], "type": "betaBuildLocalizations", "attributes": {"whatsNew": metadata["whatToTest"]}}})
    else:
        apple.request("POST", "betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": metadata["primaryLocale"], "whatsNew": metadata["whatToTest"]}, "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
    for group in configured:
        path = "betaGroups/" + group["id"] + "/relationships/builds"
        if not any(b["id"] == build for b in apple.request("GET", path)["data"]):
            apple.request("POST", path, {"data": [{"type": "builds", "id": build}]})
        assert any(b["id"] == build for b in apple.request("GET", path)["data"])
    submissions = apple.request("GET", query("betaAppReviewSubmissions", build=build))["data"]
    if not submissions:
        apple.request("POST", "betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})

def availability(apple, number, metadata):
    build = checked_build(apple, number)
    detail = apple.request("GET", "builds/" + build + "/buildBetaDetail")["data"]["attributes"]
    submissions = apple.request("GET", query("betaAppReviewSubmissions", build=build))["data"]
    result = []
    for group in groups(apple, metadata):
        linked = apple.request("GET", "betaGroups/" + group["id"] + "/relationships/builds")["data"]
        attrs = group["attributes"]
        result.append({"id": group["id"], "name": attrs["name"], "internal": attrs["isInternalGroup"], "containsBuild": any(b["id"] == build for b in linked), "publicLinkEnabled": attrs.get("publicLinkEnabled", False), "publicLink": attrs.get("publicLink")})
    return {"app": APP_ID, "version": "0.1.0", "buildNumber": str(number), "build": build, "processingState": "VALID", "betaDetail": detail, "reviewStates": [s["attributes"]["betaReviewState"] for s in submissions], "groups": result}

def execute(args):
    directory = args.directory.resolve()
    client = Apple(args.key_file.read_bytes(), args.key_id, args.issuer)
    exact_app(client)
    metadata = json.loads((ROOT / "Docs/TestFlight-Metadata.json").read_bytes())
    receipt = json.loads((directory / "direct-upload.json").read_bytes())
    if args.action == "publish":
        assert args.contact_file or args.contact_app, "An existing account-holder review contact is required"
        if args.contact_file:
            contact = json.loads(args.contact_file.read_bytes())
        else:
            assert re.fullmatch(r"[0-9]+", args.contact_app)
            contact = client.request("GET", "apps/" + args.contact_app + "/betaAppReviewDetail")["data"]["attributes"]
        publish(client, directory, args.evidence.resolve(), args.openssl, metadata, contact)
    result = availability(client, receipt["build"], metadata)
    if args.action == "enable-link":
        assert result["reviewStates"] == ["APPROVED"] and result["betaDetail"]["externalBuildState"] == "IN_BETA_TESTING"
        group = next(g for g in result["groups"] if not g["internal"])
        assert group["containsBuild"]
        client.request("PATCH", "betaGroups/" + group["id"], {"data": {"id": group["id"], "type": "betaGroups", "attributes": {"publicLinkEnabled": True, "publicLinkLimitEnabled": True, "publicLinkLimit": 100}}})
        result = availability(client, receipt["build"], metadata)
    (directory / "beta-availability.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["publish", "status", "enable-link"])
    for name in ["directory", "evidence", "openssl", "key-file"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--contact-file", type=Path)
    parser.add_argument("--contact-app", help="Read the account holder's existing Apple review contact without storing it in source control")
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    execute(parser.parse_args())
