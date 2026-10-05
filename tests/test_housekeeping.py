import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch


loader = importlib.machinery.SourceFileLoader("gala_housekeeping", str(Path(__file__).resolve().parents[1] / "bin/gala"))
spec = importlib.util.spec_from_loader(loader.name, loader)
gala = importlib.util.module_from_spec(spec)
loader.exec_module(gala)


class ReaperTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.now = 1800000000
        self.queue = SimpleNamespace(lock=threading.Condition(), current=None, waiting=[], snapshot=lambda: [])
        for target, value in (("sys.platform", "darwin"), ("time.time", self.now)):
            mock = patch.object(gala.sys, "platform", value) if target == "sys.platform" else patch.object(gala.time, "time", return_value=value)
            mock.start()
            self.addCleanup(mock.stop)

    def device(self, index, age):
        return {"udid": f"00000000-0000-0000-0000-{index:012d}", "name": "test device", "state": "Booted",
                "lastBootedAt": gala.dt.datetime.fromtimestamp(self.now - age, gala.dt.timezone.utc).isoformat()}

    def test_mocked_simctl_shuts_down_only_devices_booted_for_12_hours(self):
        old, recent = self.device(1, gala.SIMULATOR_MAX_AGE), self.device(2, gala.SIMULATOR_MAX_AGE - 1)
        listed = SimpleNamespace(stdout=json.dumps({"devices": {"iOS": [old, recent]}}))
        with patch.object(gala, "checked", return_value=listed), \
                patch.object(gala.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as shutdown, \
                patch.object(gala, "process_snapshot", return_value=[]), contextlib.redirect_stdout(io.StringIO()) as log:
            gala.reap_idle_resources(self.root, self.queue)
        shutdown.assert_called_once_with(["xcrun", "simctl", "shutdown", old["udid"]],
                                         capture_output=True, text=True, timeout=30, check=False)
        self.assertIn(old["udid"], log.getvalue())
        self.assertEqual(list(json.loads((self.root / "reaper-state.json").read_text())["simulators"]), [recent["udid"]])

    def test_busy_queue_and_publish_prevent_any_resource_changes(self):
        with patch.object(gala, "reap_resources_locked") as reap:
            self.queue.current = "running-job"
            gala.reap_idle_resources(self.root, self.queue)
            self.queue.current = None
            self.queue.waiting = ["queued-job"]
            gala.reap_idle_resources(self.root, self.queue)
            self.queue.waiting = []
            with gala.PUBLISH_LOCK:
                gala.reap_idle_resources(self.root, self.queue)
            reap.assert_not_called()

    def test_unknown_boot_time_is_recorded_then_expires_after_12_hours(self):
        device = self.device(1, 0)
        del device["lastBootedAt"]
        with patch.object(gala, "booted_simulators", return_value=[device]), \
                patch.object(gala, "process_snapshot", return_value=[]), \
                patch.object(gala.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as shutdown, \
                contextlib.redirect_stdout(io.StringIO()):
            gala.reap_idle_resources(self.root, self.queue)
            shutdown.assert_not_called()
            with patch.object(gala.time, "time", return_value=self.now + gala.SIMULATOR_MAX_AGE):
                gala.reap_idle_resources(self.root, self.queue)
            shutdown.assert_called_once()

    def helper(self, pid, **changes):
        process = {"pid": pid, "ppid": 1, "uid": os.getuid(), "started": self.now - gala.SIMULATOR_MAX_AGE,
                   "cpu": "0:00.01", "state": "S", "command": "/usr/bin/swift-frontend"}
        return {**process, **changes}

    def test_only_old_orphaned_helpers_with_unchanged_cpu_are_terminated(self):
        processes = [self.helper(101), self.helper(102, ppid=42), self.helper(103, started=self.now),
                     self.helper(104), self.helper(105, uid=os.getuid() + 1), self.helper(106),
                     self.helper(107, ppid=106, command="/bin/sleep")]
        gala.write_json_atomic(self.root / "reaper-state.json", {"helpers": {
            f"{p['pid']}:{p['started']}": "0:00.00" if p["pid"] == 104 else p["cpu"] for p in processes}})
        with patch.object(gala, "booted_simulators", return_value=[]), \
                patch.object(gala, "process_snapshot", side_effect=lambda pid=None: processes if pid is None else [processes[0]]), \
                patch.object(gala.os, "kill") as kill, contextlib.redirect_stdout(io.StringIO()) as log:
            gala.reap_idle_resources(self.root, self.queue)
        kill.assert_called_once_with(101, signal.SIGTERM)
        self.assertIn("terminated swift-frontend PID 101", log.getvalue())

    def test_first_observation_does_not_kill_helpers_and_reused_pid_survives(self):
        process = self.helper(101)
        with patch.object(gala, "booted_simulators", return_value=[]), \
                patch.object(gala, "process_snapshot", return_value=[process]), patch.object(gala.os, "kill") as kill:
            gala.reap_idle_resources(self.root, self.queue)
            kill.assert_not_called()
            with patch.object(gala, "process_snapshot", side_effect=[[process], [{**process, "started": self.now}]]):
                gala.reap_idle_resources(self.root, self.queue)
            kill.assert_not_called()

    def test_simulator_app_closes_only_after_last_device_shutdown(self):
        process = self.helper(101, command="/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator")
        with patch.object(gala, "booted_simulators", side_effect=[[self.device(1, gala.SIMULATOR_MAX_AGE)], [], []]), \
                patch.object(gala.subprocess, "run", return_value=SimpleNamespace(returncode=0)), \
                patch.object(gala, "process_snapshot", return_value=[process]), \
                patch.object(gala.os, "kill") as kill, contextlib.redirect_stdout(io.StringIO()):
            gala.reap_idle_resources(self.root, self.queue)
        kill.assert_called_once_with(101, signal.SIGTERM)

    def test_failed_shutdown_keeps_simulator_app_and_device_state(self):
        device = self.device(1, gala.SIMULATOR_MAX_AGE)
        with patch.object(gala, "booted_simulators", return_value=[device]), \
                patch.object(gala.subprocess, "run", return_value=SimpleNamespace(returncode=1, stderr="busy")), \
                patch.object(gala, "process_snapshot", return_value=[]), \
                patch.object(gala.os, "kill") as kill, contextlib.redirect_stdout(io.StringIO()) as log:
            gala.reap_idle_resources(self.root, self.queue)
        kill.assert_not_called()
        self.assertIn("shutdown failed: busy", log.getvalue())
        self.assertIn(device["udid"], json.loads((self.root / "reaper-state.json").read_text())["simulators"])

    def test_process_scan_parses_age_owner_and_executable_with_spaces(self):
        result = subprocess.CompletedProcess([], 0, stdout=" 42 1 501 Sun Oct  4 05:44:30 2026 0:00.01 S /Applications/My Tools/swift-frontend\n")
        with patch.object(gala.subprocess, "run", return_value=result):
            processes = gala.process_snapshot()
        self.assertEqual(processes[0]["pid"], 42)
        self.assertEqual(processes[0]["uid"], 501)
        self.assertEqual(processes[0]["command"], "/Applications/My Tools/swift-frontend")

    def test_simctl_failure_is_logged_without_stopping_housekeeping(self):
        with patch.object(gala, "booted_simulators", side_effect=subprocess.TimeoutExpired("simctl", 30)), \
                contextlib.redirect_stdout(io.StringIO()) as log:
            gala.housekeeping(self.root, self.queue)
        self.assertIn("Resource cleanup failed", log.getvalue())


if __name__ == "__main__":
    unittest.main()
