"""Offline regressions for release boundaries. No Apple/GitHub requests are made."""
import hashlib
import unittest
from unittest.mock import Mock, patch
from testflight import owner_invitation
from direct_upload import APP_ID, checked_operations, chunk_matches, commit_payload, file_payload, upload_payload
from local_sign import BUNDLES, distribution_entitlements, signing_command, validated_run

class ReleaseTests(unittest.TestCase):
    def test_windows_entitlements_are_not_interpreted_as_path_scopes(self):
        from types import SimpleNamespace
        args = SimpleNamespace(rcodesign=r"C:\tools\rcodesign.exe", certificate_file=r"C:\private\certificate.p12", password_file=r"C:\private\password.txt")
        for label in BUNDLES:
            command = signing_command(args, label, r"C:\release\PawBoss.app")
            value = command[command.index("--entitlements-xml-file") + 1]
            self.assertEqual(value, label + ".plist")
            self.assertNotIn(":", value)
            self.assertIn("--shallow", command)

    def operation(self, offset=0, length=4, url="https://upload.apple.com/part"):
        return {"method": "PUT", "offset": offset, "length": length, "url": url, "requestHeaders": []}

    def test_upload_is_for_pawboss_only(self):
        self.assertEqual(upload_payload(APP_ID, 1)["data"]["relationships"]["app"]["data"]["id"], APP_ID)
        with self.assertRaises(AssertionError): upload_payload("another-app", 1)

    def test_no_zero_byte_file(self):
        with self.assertRaises(AssertionError): file_payload("test", 0)
        self.assertEqual(file_payload("test", 4)["data"]["attributes"]["fileName"], "PawBoss.ipa")

    def test_chunks_cover_file_exactly(self):
        self.assertEqual(len(checked_operations([self.operation(4), self.operation()], 8)), 2)
        for operations in [[self.operation(), self.operation(3)], [self.operation(), self.operation(5)], []]:
            with self.assertRaises(AssertionError): checked_operations(operations, 8)

    def test_delivery_hosts_and_headers_are_restricted(self):
        for url in ["http://upload.apple.com/part", "https://apple.com.attacker.example/part", "https://user:pass@upload.apple.com/part", "https://upload.apple.com:8080/part"]:
            with self.assertRaises(AssertionError): checked_operations([self.operation(url=url)], 4)
        operation = self.operation(); operation["requestHeaders"] = [{"name": "Cookie", "value": "private"}]
        with self.assertRaises(AssertionError): checked_operations([operation], 4)

    def test_chunk_etag_is_exact_received_part(self):
        payload = b"abcdefgh"
        operation = self.operation(4)
        operation["entityTag"] = '"' + hashlib.md5(payload[4:], usedforsecurity=False).hexdigest() + '"'
        self.assertTrue(chunk_matches(operation, payload))
        self.assertFalse(chunk_matches(operation, b"abcdefgi"))

    def test_commit_uses_apple_uploaded_flag_not_invented_checksum(self):
        self.assertEqual(commit_payload("file")["data"]["attributes"], {"uploaded": True})

    def test_distribution_is_never_debug_or_another_bundle(self):
        for bundle in BUNDLES.values():
            entitlements = distribution_entitlements(bundle)
            self.assertFalse(entitlements["get-task-allow"])
            self.assertTrue(entitlements["beta-reports-active"])
            self.assertTrue(entitlements["application-identifier"].endswith("." + bundle))
        with self.assertRaises(AssertionError): distribution_entitlements("unrelated.app")

    def test_failed_or_unfinished_native_build_cannot_be_signed(self):
        import json
        for conclusion in [None, "failure", "cancelled", "skipped"]:
            with patch("local_sign.gh", return_value=json.dumps({"head_branch": "main", "path": ".github/workflows/apple.yml", "conclusion": conclusion})):
                with self.assertRaises(AssertionError): validated_run("123", None)

    def test_other_branch_cannot_be_signed(self):
        with patch("local_sign.gh", return_value='{"head_branch":"untrusted","path":".github/workflows/apple.yml","conclusion":"success"}'):
            with self.assertRaises(AssertionError): validated_run("123", None)

    def test_owner_testing_rejects_a_group_for_another_app(self):
        apple = Mock()
        apple.request.return_value = {"data": {"id": "another-app"}}
        group = {"id": "internal", "attributes": {"isInternalGroup": True}}
        with self.assertRaises(AssertionError): owner_invitation(apple, [group], {})
        apple.request.assert_called_once_with("GET", "betaGroups/internal/app")

    def test_owner_testing_requires_verified_account_holder(self):
        apple = Mock()
        apple.request.side_effect = [{"data": {"id": APP_ID}}, {"data": []}]
        group = {"id": "internal", "attributes": {"isInternalGroup": True}}
        with self.assertRaises(AssertionError): owner_invitation(apple, [group], {})
        self.assertEqual(apple.request.call_count, 2)

    def test_owner_testing_is_app_scoped_and_does_not_repeat_invites(self):
        import urllib.parse
        apple = Mock()
        group = {"id": "internal", "attributes": {"isInternalGroup": True}}
        user = {"firstName": "Test", "lastName": "Owner", "roles": ["ACCOUNT_HOLDER"], "username": "owner@example.com"}
        tester = {"id": "tester", "attributes": {"email": user["username"]}}
        member = {"data": [{"id": "tester"}]}
        apple.request.side_effect = [{"data": {"id": APP_ID}}, {"data": [{"attributes": user}]},
            {"data": [tester]}, member, member, {"data": [{"id": APP_ID}]}]
        result = owner_invitation(apple, [group], {"contactFirstName": "Test", "contactLastName": "Owner"})
        self.assertTrue(result["accountHolderAccessVerified"])
        self.assertTrue(all(call.args[0] == "GET" for call in apple.request.call_args_list))
        filters = urllib.parse.parse_qs(apple.request.call_args_list[2].args[1].split("?", 1)[1])
        self.assertEqual(filters["filter[apps]"], [APP_ID])
        self.assertEqual(filters["filter[email]"], [user["username"]])

if __name__ == "__main__":
    unittest.main()
