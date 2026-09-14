"""PawBoss-only Apple identifiers. Credentials are read locally, never printed or uploaded to GitHub."""
import argparse
import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLES = {"Phone": "com.sidneytambin.pawboss", "Watch": "com.sidneytambin.pawboss.watchkitapp"}
TEAM = "HT5X86Q4DD"

def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise RuntimeError("Apple API redirect refused")

class Apple:
    def __init__(self, key, key_id, issuer):
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
        private = serialization.load_pem_private_key(key, password=None)
        now = int(time.time())
        header = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
        claims = b64(json.dumps({"iss": issuer, "iat": now - 10, "exp": now + 1100, "aud": "appstoreconnect-v1"}).encode())
        body = header + b"." + claims
        r, s = decode_dss_signature(private.sign(body, ec.ECDSA(hashes.SHA256())))
        self.token = (body + b"." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method, path, body=None):
        assert not path.startswith(("http", "/")), "API-relative paths only"
        request = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/" + path,
            data=json.dumps(body).encode() if body else None,
            headers={"Authorization": "Bearer " + self.token, "Content-Type": "application/json"}, method=method)
        try:
            with self.opener.open(request, timeout=60) as response:
                data = response.read()
                return json.loads(data) if data else None
        except urllib.error.HTTPError as error:
            details = json.loads(error.read()).get("errors", [])
            raise RuntimeError(json.dumps([{key: item.get(key) for key in ("status", "code", "detail")} for item in details])) from None

def setup(client, create):
    identifiers = {}
    for label, bundle in BUNDLES.items():
        records = client.request("GET", "bundleIds?" + urllib.parse.urlencode({"filter[identifier]": bundle}))["data"]
        records = [record for record in records if record["attributes"]["identifier"] == bundle]
        if not records and create:
            records = [client.request("POST", "bundleIds", {"data": {"type": "bundleIds", "attributes": {"name": "PawBoss " + label, "identifier": bundle, "platform": "IOS"}}})["data"]]
        if records:
            assert len(records) == 1 and records[0]["attributes"]["identifier"] == bundle
            identifiers[label] = {"bundle": bundle, "id": records[0]["id"]}
    apps = client.request("GET", "apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLES["Phone"]}))["data"]
    summary = {"team": TEAM, "identifiers": identifiers, "apps": [{"id": app["id"], "name": app["attributes"]["name"], "bundleId": app["attributes"]["bundleId"]} for app in apps], "checkedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    directory = ROOT / "Artifacts" / "AppleSetup"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "status.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return summary

def provision(client, args):
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.serialization import pkcs12
    private, certificate, chain = pkcs12.load_key_and_certificates(args.certificate_file.read_bytes(), args.password_file.read_bytes().strip())
    assert private is not None and certificate is not None
    assert certificate.subject.get_attributes_for_oid(x509.oid.NameOID.ORGANIZATIONAL_UNIT_NAME)[0].value == TEAM
    assert certificate.not_valid_after_utc.timestamp() > time.time() + 86400
    der = certificate.public_bytes(serialization.Encoding.DER)
    certificates = client.request("GET", "certificates?filter[certificateType]=DISTRIBUTION&limit=200")["data"]
    matches = [c for c in certificates if base64.b64decode(c["attributes"]["certificateContent"]) == der]
    assert len(matches) == 1, "Protected local certificate must match Apple's active certificate"
    cert_id = matches[0]["id"]
    status = setup(client, True)
    summary = {}
    for label, identifier in status["identifiers"].items():
        name = "PawBoss " + label + " App Store"
        records = client.request("GET", "profiles?" + urllib.parse.urlencode({"filter[name]": name, "filter[profileState]": "ACTIVE", "include": "bundleId,certificates", "limit": 200}))["data"]
        records = [p for p in records if p["relationships"]["bundleId"]["data"]["id"] == identifier["id"] and any(c["id"] == cert_id for c in p["relationships"]["certificates"]["data"])]
        if records:
            profile = records[0]
        else:
            profile = client.request("POST", "profiles", {"data": {"type": "profiles", "attributes": {"name": name, "profileType": "IOS_APP_STORE"}, "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": identifier["id"]}}, "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})["data"]
        assert profile["attributes"]["profileState"] == "ACTIVE"
        target = ROOT / "Artifacts/AppleSetup" / (label + ".mobileprovision")
        target.write_bytes(base64.b64decode(profile["attributes"]["profileContent"]))
        summary[label] = {"id": profile["id"], "name": name, "bundle": identifier["bundle"], "expires": profile["attributes"]["expirationDate"]}
    (ROOT / "Artifacts/AppleSetup/profiles.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    print("PawBoss-specific profiles stored locally in ignored Artifacts. No credentials uploaded to GitHub.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["status", "register", "provision"])
    parser.add_argument("--key-file", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--certificate-file", type=Path)
    parser.add_argument("--password-file", type=Path)
    args = parser.parse_args()
    client = Apple(args.key_file.read_bytes(), args.key_id, args.issuer)
    if args.action == "provision":
        assert args.certificate_file and args.password_file
        provision(client, args)
    else:
        setup(client, args.action == "register")
