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


def make_project(root, name, test="echo testing", build=None):
    source = root / "projects" / name / "source"
    gala.worker_prepare(root / "projects" / name)
    (source / "ios-test.sh").write_text(test + "\n")
    (source / "ios-build.sh").write_text((build or "exit 1") + "\n")
    return source


def wait_done(queue, job, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        state = queue.status(job)
        if state["state"] == "done":
            return state
        time.sleep(0.05)
    raise AssertionError(f"{job} did not finish")


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        toolchain = patch.object(gala, "toolchain_identity", return_value="Xcode test fixture")
        toolchain.start()
        self.addCleanup(toolchain.stop)

    def tearDown(self):
        self.directory.cleanup()

    def test_jobs_run_one_at_a_time_in_order(self):
        marker = self.root / "order.txt"
        for name in ("alpha", "beta"):
            make_project(self.root, name, f"echo start-{name} >> {marker}; sleep 0.3; echo end-{name} >> {marker}")
        queue = gala.JobQueue(self.root)
        first = queue.submit("alpha", "20260101T000000Z-aaaaaa", ["test"])
        second = queue.submit("beta", "20260101T000000Z-bbbbbb", ["test"])
        self.assertEqual(first["ahead"], 0)
        self.assertEqual(second["ahead"], 1)
        wait_done(queue, "20260101T000000Z-bbbbbb")
        self.assertEqual(marker.read_text().split(), ["start-alpha", "end-alpha", "start-beta", "end-beta"])

    def test_passing_test_is_skipped_until_source_changes(self):
        source = make_project(self.root, "alpha")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-000001", ["test"])
        self.assertEqual(wait_done(queue, "20260101T000000Z-000001")["skipped"], [])
        queue.submit("alpha", "20260101T000000Z-000002", ["test"])
        state = wait_done(queue, "20260101T000000Z-000002")
        self.assertEqual((state["skipped"], state["exit_code"]), (["test"], 0))
        queue.submit("alpha", "20260101T000000Z-000003", ["test"], retest=True)
        self.assertEqual(wait_done(queue, "20260101T000000Z-000003")["skipped"], [])
        (source / "new.swift").write_text("let x = 1\n")
        queue.submit("alpha", "20260101T000000Z-000004", ["test"])
        self.assertEqual(wait_done(queue, "20260101T000000Z-000004")["skipped"], [])

    def test_failed_test_stops_build_and_records_timings(self):
        make_project(self.root, "alpha", "exit 3", "echo should-not-run")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-cccccc", ["test", "build"])
        state = wait_done(queue, "20260101T000000Z-cccccc")
        self.assertEqual(state["exit_code"], 3)
        self.assertEqual(list(state["timings"]), ["test"])
        run = self.root / "projects/alpha/runs/20260101T000000Z-cccccc"
        self.assertNotIn("should-not-run", (run / "output.log").read_text())
        self.assertEqual(json.loads((run / "result.json").read_text())["kind"], "build")

    def test_exec_runs_in_mirror_with_scratch_off_internal_disk(self):
        make_project(self.root, "alpha")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-dddddd", ["exec"],
                     command='pwd > "$GALA_ARTIFACT_DIR/pwd"; echo "$TMPDIR" > "$GALA_ARTIFACT_DIR/tmp"; exit 4')
        state = wait_done(queue, "20260101T000000Z-dddddd")
        run = self.root / "projects/alpha/runs/20260101T000000Z-dddddd"
        self.assertEqual(state["exit_code"], 4)
        self.assertEqual(Path((run / "pwd").read_text().strip()).resolve(),
                         (self.root / "projects/alpha/source").resolve())
        self.assertTrue((run / "tmp").read_text().startswith(str(self.root / "tmp")))
        self.assertFalse((self.root / "tmp" / "20260101T000000Z-dddddd").exists())

    def test_cancel_removes_queued_job_and_stops_running_one(self):
        make_project(self.root, "alpha", "sleep 30")
        make_project(self.root, "beta")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-eeeeee", ["test"])
        queue.submit("beta", "20260101T000000Z-ffffff", ["test"])
        self.assertTrue(queue.cancel("20260101T000000Z-ffffff"))
        self.assertEqual(queue.status("20260101T000000Z-ffffff")["exit_code"], 130)
        deadline = time.time() + 5
        while queue.status("20260101T000000Z-eeeeee")["state"] != "running" and time.time() < deadline:
            time.sleep(0.05)
        started = time.time()
        queue.cancel("20260101T000000Z-eeeeee")
        self.assertEqual(wait_done(queue, "20260101T000000Z-eeeeee")["exit_code"], 130)
        self.assertLess(time.time() - started, 10)

    def test_abandoned_queued_jobs_are_dropped(self):
        make_project(self.root, "alpha", "sleep 1")
        make_project(self.root, "beta")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-111111", ["test"])
        queue.submit("beta", "20260101T000000Z-222222", ["test"])
        with queue.lock:
            queue.jobs["20260101T000000Z-222222"]["seen"] -= gala.QUEUE_STALE_SECONDS + 1
            queue.prune()
        self.assertEqual(queue.jobs["20260101T000000Z-222222"]["state"], "done")
        self.assertFalse((self.root / "projects/beta/runs/20260101T000000Z-222222").exists())
        wait_done(queue, "20260101T000000Z-111111")

    def test_stale_projects_and_old_reports_are_removed(self):
        make_project(self.root, "fresh")
        make_project(self.root, "stale")
        old = time.time() - gala.PROJECT_TTL_SECONDS - 60
        os.utime(self.root / "projects/stale/last-used", (old, old))
        reports = self.root / "reports" / "fresh"
        reports.mkdir(parents=True)
        (reports / "20250101T000000Z-crash.json").write_text("{}")
        limit = gala.REPORT_LIMITS["log"]
        for index in range(limit + 5):
            (reports / f"2026{index:04d}-log.log").write_text("x")
        self.assertEqual(gala.collect_stale_projects(self.root), ["stale"])
        gala.prune_reports(self.root)
        self.assertTrue((self.root / "projects/fresh").is_dir())
        self.assertFalse((self.root / "projects/stale").exists())
        self.assertEqual(len(list(reports.glob("*-log.log"))), limit)
        self.assertFalse((reports / "20260000-log.log").exists())
        # Chatty logs must not push out an older crash report.
        self.assertTrue((reports / "20250101T000000Z-crash.json").exists())

    def test_client_fingerprint_decides_test_skip(self):
        make_project(self.root, "alpha")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-a00001", ["test"], fingerprint="a" * 64)
        wait_done(queue, "20260101T000000Z-a00001")
        # Files a recipe writes into the mirror don't defeat the cache.
        (self.root / "projects/alpha/source/generated.txt").write_text("output")
        queue.submit("alpha", "20260101T000000Z-a00002", ["test"], fingerprint="a" * 64)
        self.assertEqual(wait_done(queue, "20260101T000000Z-a00002")["skipped"], ["test"])
        queue.submit("alpha", "20260101T000000Z-a00003", ["test"], fingerprint="b" * 64)
        self.assertEqual(wait_done(queue, "20260101T000000Z-a00003")["skipped"], [])

    def test_running_job_stops_when_its_client_disappears(self):
        make_project(self.root, "alpha", "sleep 30")
        queue = gala.JobQueue(self.root)
        queue.submit("alpha", "20260101T000000Z-b00001", ["test"])
        deadline = time.time() + 5
        while not queue.jobs["20260101T000000Z-b00001"]["process"] and time.time() < deadline:
            time.sleep(0.05)
        with queue.lock:
            queue.jobs["20260101T000000Z-b00001"]["seen"] -= gala.RUNNING_STALE_SECONDS + 1
            queue.prune()
        deadline = time.time() + 10
        while queue.jobs["20260101T000000Z-b00001"]["state"] != "done" and time.time() < deadline:
            time.sleep(0.05)
        self.assertEqual(queue.jobs["20260101T000000Z-b00001"]["exit_code"], 130)


class BuildNumberTests(unittest.TestCase):
    def test_build_numbers_survive_mirror_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gala.write_json_atomic(root / "build-numbers.json", {"com.example.app": 37})
            numbers = json.loads((root / "build-numbers.json").read_text())
            self.assertEqual(numbers["com.example.app"], 37)
            self.assertEqual(list(root.glob(".build-numbers.json.*")), [])

if __name__ == "__main__":
    unittest.main()
