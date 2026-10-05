import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch


loader = importlib.machinery.SourceFileLoader("gala_ota", str(Path(__file__).resolve().parents[1] / "bin/gala"))
spec = importlib.util.spec_from_loader(loader.name, loader)
gala = importlib.util.module_from_spec(spec)
loader.exec_module(gala)


class OTATests(unittest.TestCase):
    def test_tailnet_name_is_cached_for_a_minute_then_refreshed(self):
        with patch.dict(gala.TAILNET_CACHE, url=None, until=0), patch.object(gala.time, "monotonic", return_value=1) as clock, \
                patch.object(gala, "checked", return_value=SimpleNamespace(stdout=json.dumps({"Self": {"DNSName": "mac.example."}}))) as status:
            self.assertEqual(gala.tailnet_base_url(), "https://mac.example/gala")
            self.assertEqual(gala.tailnet_base_url(), "https://mac.example/gala")
            status.assert_called_once()
            clock.return_value = 62
            gala.tailnet_base_url()
            self.assertEqual(status.call_count, 2)

    def test_current_delivery_and_dashboard_hide_expired_or_missing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, age, published in (("old-mirror", 10, 1), ("new-mirror", 10, 2), ("expired", gala.OTA_TTL_SECONDS + 1, 3)):
                folder = root / "ota" / name
                folder.mkdir(parents=True)
                ipa = folder / "current.ipa"
                ipa.write_bytes(b"ipa")
                os.utime(ipa, (time.time() - age,) * 2)
                (folder / "current.json").write_text(json.dumps({"bundle_id": "com.example.app", "sha256": "a" * 64,
                    "title": "Example", "version": str(published), "bytes": 3, "published_at": published}))
            self.assertIsNone(gala.current_delivery(root / "ota/expired"))
            self.assertIsNone(gala.current_delivery(root / "ota/missing"))
            self.assertEqual([p["project"] for p in gala.ota_projects(root)], ["new-mirror"])
            gala.expire_ota(root)
            self.assertFalse((root / "ota/expired").exists())
            self.assertTrue((root / "ota/new-mirror/current.ipa").is_file())

    def test_manifest_keeps_build_hash_attempt_and_bundle_identity(self):
        info = {"bundle_id": "com.example.app", "sha256": "a" * 64, "title": "Example", "version": "42"}
        token = "b" * 32
        item = plistlib.loads(gala.ota_manifest("https://mac.example/gala", "example", info, token, True))["items"][0]
        self.assertEqual(item["metadata"]["bundle-identifier"], info["bundle_id"])
        self.assertEqual(item["metadata"]["bundle-version"], "42")
        self.assertIn("sha256=" + info["sha256"] + "&attempt=" + token, item["assets"][0]["url"])
        self.assertIn("example/icon.png", item["assets"][1]["url"])


if __name__ == "__main__":
    unittest.main()
