import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader("gala", str(Path(__file__).resolve().parents[1] / "bin/gala"))
spec = importlib.util.spec_from_loader(loader.name, loader)
gala = importlib.util.module_from_spec(spec)
loader.exec_module(gala)


class PushTests(unittest.TestCase):
    def test_registration_replaces_rotated_token_and_keeps_environments_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            request = {"token": "aabb", "environment": "development", "device": "12345678-1234-1234-1234-123456789abc"}
            gala.register_apns(root, request)
            gala.register_apns(root, {**request, "token": "ccdd"})
            gala.register_apns(root, {**request, "environment": "production"})
            entries = json.loads((root / "apns-subscriptions.json").read_text())
            self.assertEqual([(e["token"], e["environment"]) for e in entries],
                             [("ccdd", "development"), ("aabb", "production")])
            self.assertEqual((root / "apns-subscriptions.json").stat().st_mode & 0o777, 0o600)

    def test_registration_rejects_invalid_tokens_and_environments(self):
        with tempfile.TemporaryDirectory() as directory:
            base = {"token": "aabb", "environment": "development", "device": "12345678-1234-1234-1234-123456789abc"}
            for change in ({"token": "../bad"}, {"token": "abc"}, {"environment": "sandbox"}, {"device": ""}):
                with self.subTest(change=change), self.assertRaises(RuntimeError):
                    gala.register_apns(Path(directory), {**base, **change})

    def test_push_signing_rejects_wildcard_without_push(self):
        profiles = [(Path("wildcard"), {"Entitlements": {"application-identifier": "TEAM.*"}}, "identity")]
        with patch.object(gala, "signing_profiles", return_value=profiles):
            with self.assertRaisesRegex(RuntimeError, "Push Notifications enabled"):
                gala.profile_for_bundle("com.galaengine.app", require_push=True)
        with patch.object(gala, "signing_profiles", return_value=profiles):
            self.assertEqual(gala.profile_for_bundle("com.example.app")[2], "identity")

    def test_expired_token_cleanup_preserves_registration_updated_during_send(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry = {"token": "aabb", "environment": "development", "device": "12345678-1234-1234-1234-123456789abc", "registered_at": 1}
            gala.save_apns_subscriptions(root, [entry])

            def send(*args, **kwargs):
                gala.save_apns_subscriptions(root, [{**entry, "registered_at": 2}])
                return type("Result", (), {"returncode": 0, "stdout": json.dumps({"registered": 1, "sent": 0,
                    "failed": 1, "results": [{**entry, "status": "expired", "reason": "Unregistered"}]})})()

            with patch.object(gala.subprocess, "run", side_effect=send):
                report = gala.notify_apns(root, {"project": "yala"})
            self.assertEqual(report["failed"], 1)
            self.assertEqual(json.loads((root / "apns-subscriptions.json").read_text())[0]["registered_at"], 2)

    def test_48_hour_cleanup_removes_only_expired_delivery_and_preserves_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, age in (("expired", 49 * 3600), ("current", 47 * 3600)):
                project = root / "ota" / name
                project.mkdir(parents=True)
                for filename in ("current.ipa", "current.json", "icon.png"):
                    (project / filename).write_bytes(b"test")
                timestamp = time.time() - age
                os.utime(project / "current.ipa", (timestamp, timestamp))
            cache = root / "projects" / "expired" / "build" / "cache"
            cache.parent.mkdir(parents=True)
            cache.write_text("keep")
            gala.expire_ota(root)
            self.assertFalse((root / "ota" / "expired").exists())
            self.assertTrue((root / "ota" / "current" / "current.ipa").is_file())
            self.assertTrue(cache.is_file())

    def test_corrupt_push_state_reports_failure_without_breaking_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "apns-subscriptions.json").write_text("broken json")
            result = gala.notify_subscribers(root, "yala", {"title": "Yala"})
            self.assertEqual(result["failed"], 1)
            self.assertEqual(result["sent"], 0)


if __name__ == "__main__":
    unittest.main()
