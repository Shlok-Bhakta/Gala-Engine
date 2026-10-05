import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile


CLI = Path(__file__).resolve().parents[1] / "bin/gala"
loader = importlib.machinery.SourceFileLoader("gala_publish", str(CLI))
spec = importlib.util.spec_from_loader(loader.name, loader)
gala = importlib.util.module_from_spec(spec)
loader.exec_module(gala)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name).resolve()
        self.previous = Path.cwd()
        os.chdir(self.root)
        self.options = SimpleNamespace(host="local", root=gala.DEFAULT_ROOT, name=None, ipa=None)

    def tearDown(self):
        os.chdir(self.previous)
        self.directory.cleanup()

    def make_ipa(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Example.app/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": "com.example.app", "CFBundleVersion": "1",
            }))
        return path

    def test_external_ipa_needs_no_recipe_or_source_sync(self):
        ipa = self.make_ipa(self.root / "external output" / "Example.IPA")
        self.options.ipa = str(ipa)
        self.options.name = "external-app"
        summary = {"timings": {}}
        with patch.object(gala, "prepare") as prepare, \
                patch.object(gala, "rsync_command") as upload, \
                patch.object(gala, "client_publish_job") as publish, \
                patch.object(gala, "sync") as sync, patch.object(gala, "client_job") as job:
            gala.client_publish(self.options, summary)
        self.assertEqual(summary["source"], str(self.root))
        prepare.assert_called_once_with(self.options, "projects/external-app")
        upload.assert_called_once_with(self.options, "-a", str(ipa),
                                       gala.daemon_url("projects/external-app/incoming/current.ipa"))
        publish.assert_called_once_with(self.options, self.root, "projects/external-app", "incoming", summary)
        sync.assert_not_called()
        job.assert_not_called()
        self.assertEqual(set(summary["timings"]), {"prepare", "upload", "publish"})
        self.assertTrue(ipa.is_file())

    def test_explicit_ipa_keeps_existing_project_identity(self):
        (self.root / "ios-build.sh").write_text("exit 1\n")
        expected = gala.project_paths(self.options)
        child = self.root / "subdirectory"
        child.mkdir()
        os.chdir(child)
        self.options.ipa = "/elsewhere/app.ipa"
        self.assertEqual(gala.project_paths(self.options, require_recipe=False), expected)

    def test_implicit_ipa_still_selects_latest_gala_build(self):
        (self.root / "ios-build.sh").write_text("exit 1\n")
        self.make_ipa(self.root / ".gala/runs/20260101/old.ipa")
        latest = self.make_ipa(self.root / ".gala/runs/20260102/nested/latest.ipa")
        with patch.object(gala, "prepare"), patch.object(gala, "rsync_command") as upload, \
                patch.object(gala, "client_publish_job"):
            gala.client_publish(self.options, {"timings": {}})
        self.assertEqual(upload.call_args.args[2], str(latest))

    def test_invalid_input_fails_before_contacting_mac(self):
        invalid = self.root / "invalid.ipa"
        with zipfile.ZipFile(invalid, "w") as archive:
            archive.writestr("readme.txt", "No app here")
        for path in (invalid, self.root / "missing.ipa"):
            self.options.ipa = str(path)
            with self.subTest(path=path), patch.object(gala, "prepare") as prepare:
                with self.assertRaises(RuntimeError):
                    gala.client_publish(self.options, {"timings": {}})
                prepare.assert_not_called()

    def test_push_and_publish_return_json_on_failure_without_recipe(self):
        for action in ("push", "publish"):
            with self.subTest(action=action):
                result = subprocess.run([sys.executable, str(CLI), action, "missing.ipa",
                                         "--host", "local", "--json"], capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                summary = json.loads(result.stdout)
                self.assertFalse(summary["ok"])
                self.assertEqual(summary["action"], action)
                self.assertIn("IPA not found", summary["error"])
                self.assertIn("total", summary["timings"])
                self.assertEqual(json.loads((self.root / ".gala/last-result.json").read_text()), summary)

    def test_no_argument_requires_recipe_for_latest_build_lookup(self):
        with self.assertRaisesRegex(RuntimeError, "No ios-build.sh"):
            gala.client_publish(self.options, {"timings": {}})


if __name__ == "__main__":
    unittest.main()
