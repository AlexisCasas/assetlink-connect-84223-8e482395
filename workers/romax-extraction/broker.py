"""4E.2 CI-only broker and Docker isolation spike; no live adapters or credentials."""
from dataclasses import dataclass
import hashlib
import json
import os
import re
import selectors
import subprocess
import time
import uuid

MAX_FILE = 10 * 1024 * 1024
MAX_OUTPUT = 2 * 1024 * 1024
BUCKET = "romax-request-attachments"
PARSER = "synthetic-probe-v1"
CONFIG = hashlib.sha256(b"romax:synthetic-probe-v1:256m:32pids:60s").hexdigest()
FIXTURES = frozenset(b"ROMAX-QA:" + k for k in (b"ok", b"partial", b"timeout", b"overflow", b"malformed", b"crash"))
IMAGE = re.compile(r"sha256:[a-f0-9]{64}")
HASH = re.compile(r"[a-f0-9]{64}")

class Failure(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)

def canonical_uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value
    except (ValueError, TypeError, AttributeError):
        return False

@dataclass(frozen=True)
class Scope:
    org: str
    opportunity: str
    document: str
    job: str

    def __post_init__(self):
        if not all(canonical_uuid(v) for v in (self.org, self.opportunity, self.document, self.job)):
            raise Failure("source_changed")

def validate_claim(scope, claim):
    if not isinstance(claim, dict) or claim.get("status") != "running" or claim.get("job_id") != scope.job:
        raise Failure("source_changed")
    if not canonical_uuid(claim.get("lease")) or claim.get("parser") != PARSER or claim.get("config") != CONFIG:
        raise Failure("source_changed")
    s = claim.get("source")
    if not isinstance(s, dict) or not canonical_uuid(s.get("attempt")):
        raise Failure("source_changed")
    expected = "/".join(("quarantine", scope.org, scope.opportunity, scope.document, s["attempt"]))
    if s.get("path") != expected or s.get("mime") != "application/pdf":
        raise Failure("source_changed")
    if not isinstance(s.get("hash"), str) or not HASH.fullmatch(s["hash"]):
        raise Failure("source_changed")
    if type(s.get("size")) is not int or not 1 <= s["size"] <= MAX_FILE:
        raise Failure("source_changed")
    return s

def read_bounded(chunks, expected_size, expected_hash, deadline):
    result = bytearray()
    digest = hashlib.sha256()
    for chunk in chunks:
        if time.monotonic() >= deadline:
            raise Failure("timeout")
        if not isinstance(chunk, bytes) or len(result) + len(chunk) > expected_size:
            raise Failure("source_changed")
        result.extend(chunk)
        digest.update(chunk)
    if time.monotonic() >= deadline:
        raise Failure("timeout")
    if len(result) != expected_size or digest.hexdigest() != expected_hash:
        raise Failure("source_changed")
    return bytes(result)

def docker_command(image, name):
    if not isinstance(image, str) or not IMAGE.fullmatch(image):
        raise Failure("worker_error")
    return ["docker", "create", "--pull=never", "--name", name, "-i",
            "--network=none", "--ipc=none", "--read-only", "--user=65532:65532",
            "--cap-drop=ALL", "--security-opt=no-new-privileges=true",
            "--memory=256m", "--memory-swap=256m", "--cpus=1", "--pids-limit=32",
            "--ulimit=nofile=64:64", "--ulimit=core=0:0", "--log-driver=none",
            "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=16m,mode=1777", image]

def _remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise Failure("timeout")
    return seconds

def run_sandbox(image, data, timeout=60):
    if data not in FIXTURES:
        raise Failure("unsupported_format")
    return _run_container(image, data, timeout)

def _run_container(image, data, timeout):
    if not isinstance(data, bytes) or len(data)>MAX_FILE:
        raise Failure("limit")
    if type(timeout) not in (float, int) or not 0 < timeout <= 60:
        raise Failure("worker_error")
    deadline = time.monotonic() + timeout
    name = "romax-qa-" + uuid.uuid4().hex
    cmd = docker_command(image, name)
    proc = None
    created = False
    output = bytearray()
    try:
        # CLI operations are local only; fixed args, no shell, no user-selected image/command.
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=_remaining(deadline))
        created = True
        proc = subprocess.Popen(["docker", "start", "-ai", name], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        # Full-duplex nonblocking IO: large synthetic XLSX inputs cannot deadlock stdout or timeout.
        os.set_blocking(proc.stdin.fileno(), False)
        os.set_blocking(proc.stdout.fileno(), False)
        sent = 0
        with selectors.DefaultSelector() as sel:
            sel.register(proc.stdout, selectors.EVENT_READ)
            sel.register(proc.stdin, selectors.EVENT_WRITE)
            while sel.get_map():
                events = sel.select(_remaining(deadline))
                if not events:
                    raise Failure("timeout")
                for key, event in events:
                    if key.fileobj is proc.stdin:
                        try:
                            sent += os.write(proc.stdin.fileno(), data[sent:sent+65536])
                        except BlockingIOError:
                            continue
                        except BrokenPipeError:
                            raise Failure("worker_error") from None
                        if sent == len(data):
                            sel.unregister(proc.stdin)
                            proc.stdin.close()
                    else:
                        try:
                            chunk = os.read(proc.stdout.fileno(), 65536)
                        except BlockingIOError:
                            continue
                        if not chunk:
                            sel.unregister(proc.stdout)
                        else:
                            if len(output) + len(chunk) > MAX_OUTPUT:
                                raise Failure("limit")
                            output.extend(chunk)
        if proc.wait(timeout=_remaining(deadline)) != 0:
            raise Failure("worker_error")
        return bytes(output)
    except subprocess.TimeoutExpired:
        raise Failure("timeout") from None
    except (OSError, subprocess.CalledProcessError):
        raise Failure("worker_error") from None
    finally:
        # Remove only our random container. Never issue broad prune/kill commands.
        # Even a failed create may have succeeded server-side before its response was lost.
        try:
            cleanup = subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, timeout=8)
            if created and cleanup.returncode != 0:
                raise Failure("worker_error")
        except (OSError, subprocess.TimeoutExpired):
            raise Failure("worker_error") from None
        finally:
            if proc is not None:
                if proc.poll() is None:
                    proc.kill()
                proc.wait(timeout=5)
                proc.stdout.close()
                if not proc.stdin.closed:
                    proc.stdin.close()

def parse_result(raw):
    if not isinstance(raw, bytes) or len(raw) > MAX_OUTPUT:
        raise Failure("limit")
    def unique(pairs):
        result = {}
        for k, v in pairs:
            if k in result:
                raise ValueError("duplicate")
            result[k] = v
        return result
    try:
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=unique,
                            parse_constant=lambda _: (_ for _ in ()).throw(ValueError("constant")))
        if not isinstance(result, dict) or set(result) != {"status", "reason", "evidence", "candidates"}:
            raise ValueError("shape")
        status, reason, evidence, candidates = (result[k] for k in ("status", "reason", "evidence", "candidates"))
        if not isinstance(status, str) or not isinstance(evidence, list) or not isinstance(candidates, list):
            raise ValueError("shape")
        # The spike deliberately accepts only fixed synthetic result schema.
        if status not in ("succeeded", "partial", "unsupported"):
            raise ValueError("status")
        if status == "unsupported":
            if reason != "unsupported_format" or evidence or candidates:
                raise ValueError("unsupported")
        elif ((status == "succeeded" and reason is not None) or (status == "partial" and reason != "limit")
              or evidence != [{"location": {"page": 1, "block": 1}, "excerpt": "Synthetic fixture only"}]
              or candidates != [{"kind": "item", "evidence_ordinal": 1, "proposal": {"description": "Synthetic item", "quantity": "12", "unit_raw": "und", "flags": []}}]):
            raise ValueError("synthetic shape")
        return result
    except (UnicodeError, ValueError, TypeError, RecursionError):
        raise Failure("worker_error") from None

class SyntheticBroker:
    """No production switch exists. Ports are provided only by the synthetic test harness."""
    def __init__(self, control, storage, runner):
        self.control, self.storage, self.runner = control, storage, runner

    def execute(self, scope, *, enabled=False):
        if enabled is not True:
            raise Failure("worker_error")
        claim = self.control.claim(scope)
        if isinstance(claim, dict) and claim.get("status") == "failed":
            return {"status": "failed"}
        # If claim is malformed, never trust its lease or call finish for an unrelated job.
        source = validate_claim(scope, claim)
        deadline = time.monotonic() + 60
        try:
            data = read_bounded(self.storage.chunks(BUCKET, source["path"], deadline),
                                source["size"], source["hash"], deadline)
            if data not in FIXTURES:
                raise Failure("unsupported_format")
            output = parse_result(self.runner(data, _remaining(deadline)))
        except Failure as exc:
            outcome = "retry" if exc.code in ("timeout", "worker_error") else "unsupported" if exc.code == "unsupported_format" else "failed"
            # SQL contract allows limit as a terminal reason; do not invent partial evidence.
            output = {"status": outcome, "reason": exc.code, "evidence": [], "candidates": []}
        except Exception:
            output = {"status": "retry", "reason": "worker_error", "evidence": [], "candidates": []}
        # No retry of uncertain writes; original fencing token remains authoritative.
        # Control returns safe receipt or raises, not raw file contents.
        return self.control.finish(scope, claim["lease"], source["hash"], output)
