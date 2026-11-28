import hashlib
import os
import subprocess
import time
import unittest
import uuid

from broker import (BUCKET, CONFIG, PARSER, Failure, Scope, SyntheticBroker,
                    docker_command, parse_result, read_bounded, run_sandbox)

def uid():
    return str(uuid.uuid4())

def fixture(data=b"ROMAX-QA:ok"):
    scope = Scope(uid(), uid(), uid(), uid())
    attempt = uid()
    claim = {"status": "running", "job_id": scope.job, "lease": uid(), "parser": PARSER, "config": CONFIG,
             "source": {"attempt": attempt, "path": "/".join(("quarantine", scope.org, scope.opportunity, scope.document, attempt)),
                        "hash": hashlib.sha256(data).hexdigest(), "size": len(data), "mime": "application/pdf"}}
    class Control:
        calls = []
        def claim(self, value):
            assert value == scope
            self.calls.append("claim")
            return claim
        def finish(self, value, lease, digest, result):
            assert value == scope and lease == claim["lease"] and digest == claim["source"]["hash"]
            self.calls.append(result)
            return {"status": result["status"]}
    class Storage:
        calls = []
        def chunks(self, bucket, path, deadline):
            assert bucket == BUCKET and path == claim["source"]["path"]
            self.calls.append(path)
            yield data
    return scope, claim, Control(), Storage()

class BrokerTests(unittest.TestCase):
    def test_disabled_default(self):
        scope, claim, control, storage = fixture()
        with self.assertRaises(Failure):
            SyntheticBroker(control, storage, lambda *_: self.fail("ran")).execute(scope)
        self.assertEqual(control.calls, [])

    def test_wrong_path_job_or_parser_never_reads(self):
        for key, value in (("path", "quarantine/foreign"), ("size", 10485761), ("mime", "application/zip")):
            scope, claim, control, storage = fixture()
            claim["source"][key] = value
            with self.assertRaises(Failure):
                SyntheticBroker(control, storage, lambda *_: self.fail("ran")).execute(scope, enabled=True)
            self.assertEqual(storage.calls, [])
        for key in ("job_id", "lease", "parser", "config"):
            scope, claim, control, storage = fixture()
            claim[key] = "invalid"
            with self.assertRaises(Failure):
                SyntheticBroker(control, storage, lambda *_: self.fail("ran")).execute(scope, enabled=True)
            self.assertEqual(storage.calls, [])

    def test_hash_mismatch_never_runs(self):
        scope, claim, control, storage = fixture()
        claim["source"]["hash"] = "0" * 64
        result = SyntheticBroker(control, storage, lambda *_: self.fail("ran")).execute(scope, enabled=True)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(control.calls[-1]["reason"], "source_changed")

    def test_nonfixture_never_runs(self):
        scope, _, control, storage = fixture(b"not a synthetic fixture")
        result = SyntheticBroker(control, storage, lambda *_: self.fail("ran")).execute(scope, enabled=True)
        self.assertEqual(result["status"], "unsupported")

    def test_bounded_source(self):
        digest = hashlib.sha256(b"abc").hexdigest()
        for chunks in ([b"abcd"], [b"ab"], [b"abd"]):
            with self.assertRaises(Failure):
                read_bounded(chunks, 3, digest, time.monotonic()+5)
        self.assertEqual(read_bounded([b"a", b"bc"], 3, digest, time.monotonic()+5), b"abc")
        with self.assertRaises(Failure):
            read_bounded([b"abc"], 3, digest, time.monotonic()-1)

    def test_parser_output_rejects_invalid(self):
        for raw in (b"{}", b'{"status":"x","status":"y"}', b"["*2000, b"{} trailing", b"x"*(2*1024*1024+1)):
            with self.assertRaises(Failure):
                parse_result(raw)

    def test_image_must_be_immutable(self):
        with self.assertRaises(Failure):
            docker_command("python:latest", "test")
        cmd = docker_command("sha256:"+"a"*64, "test")
        for flag in ("--network=none", "--read-only", "--cap-drop=ALL", "--user=65532:65532", "--memory=256m", "--pids-limit=32", "--pull=never"):
            self.assertIn(flag, cmd)
        self.assertNotIn("--privileged", cmd)

    def test_uncertain_finish_not_replayed(self):
        scope, _, control, storage = fixture()
        def finish(*args):
            control.calls.append("uncertain")
            raise RuntimeError("synthetic")
        control.finish = finish
        def run(*_):
            raise Failure("timeout")
        with self.assertRaises(RuntimeError):
            SyntheticBroker(control, storage, run).execute(scope, enabled=True)
        self.assertEqual(control.calls, ["claim", "uncertain"])

class RealSandboxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image = os.environ["ROMAX_QA_IMAGE_ID"]

    def test_sandbox_success_and_partial(self):
        for fixture_name, expected in ((b"ROMAX-QA:ok", "succeeded"), (b"ROMAX-QA:partial", "partial")):
            scope, _, control, storage = fixture(fixture_name)
            result = SyntheticBroker(control, storage, lambda data, seconds: run_sandbox(self.image, data, seconds)).execute(scope, enabled=True)
            self.assertEqual(result["status"], expected)
            self.assertEqual(len(control.calls[-1]["evidence"]), 1)

    def test_timeout_and_cleanup(self):
        with self.assertRaises(Failure) as error:
            run_sandbox(self.image, b"ROMAX-QA:timeout", timeout=5)
        self.assertEqual(error.exception.code, "timeout")

    def test_output_overflow_and_crash(self):
        for name, code in ((b"ROMAX-QA:overflow", "limit"), (b"ROMAX-QA:crash", "worker_error")):
            with self.assertRaises(Failure) as error:
                run_sandbox(self.image, name)
            self.assertEqual(error.exception.code, code)

    def test_malformed_output(self):
        with self.assertRaises(Failure):
            parse_result(run_sandbox(self.image, b"ROMAX-QA:malformed"))

    def test_no_orphan(self):
        result = subprocess.check_output(["docker", "ps", "-aq", "--filter", "name=romax-qa-"], text=True)
        self.assertEqual(result.strip(), "")

if __name__ == "__main__":
    unittest.main(verbosity=2)
