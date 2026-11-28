"""Synthetic-only sandbox probe. Never parses customer documents."""
import errno
import json
import os
import socket
import sys
import time

def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":"), ensure_ascii=True))
    sys.stdout.flush()

def verify():
    status = dict(line.split(":", 1) for line in open("/proc/self/status") if ":" in line)
    assert os.getuid() == 65532 and os.getgid() == 65532
    assert int(status["CapEff"].strip(), 16) == 0
    assert status["NoNewPrivs"].strip() == "1" and status["Seccomp"].strip() == "2"
    assert not any("SECRET" in k or "SUPABASE" in k or "GITHUB" in k or "GMAIL" in k for k in os.environ)
    assert not os.path.exists("/var/run/docker.sock")
    assert set(os.listdir("/sys/class/net")) == {"lo"}
    try:
        with socket.create_connection(("192.0.2.1", 9), timeout=0.25):
            raise AssertionError("network reachable")
    except OSError as e:
        assert e.errno in (errno.ENETUNREACH, errno.EHOSTUNREACH, errno.EACCES, errno.EPERM)
    try:
        with open("/app/probe-write", "wb") as f:
            f.write(b"synthetic")
        raise AssertionError("rootfs writable")
    except OSError as e:
        assert e.errno in (errno.EROFS, errno.EACCES)
    with open("/tmp/probe", "wb") as f:
        f.write(b"synthetic")
    assert open("/tmp/probe", "rb").read() == b"synthetic"
    os.unlink("/tmp/probe")
    # Verify actual cgroup v2 caps, not just requested CLI flags.
    assert int(open("/sys/fs/cgroup/memory.max").read()) == 268435456
    assert int(open("/sys/fs/cgroup/pids.max").read()) == 32
    quota, period = open("/sys/fs/cgroup/cpu.max").read().split()
    assert int(quota) == int(period)

def main():
    data = sys.stdin.buffer.read(129)
    if data not in {b"ROMAX-QA:ok", b"ROMAX-QA:timeout", b"ROMAX-QA:overflow", b"ROMAX-QA:malformed", b"ROMAX-QA:crash", b"ROMAX-QA:partial"}:
        emit({"status": "unsupported", "reason": "unsupported_format", "evidence": [], "candidates": []})
        return
    verify()
    if data == b"ROMAX-QA:timeout":
        time.sleep(120)
    if data == b"ROMAX-QA:overflow":
        sys.stdout.buffer.write(b"x" * (3 * 1024 * 1024))
        return
    if data == b"ROMAX-QA:malformed":
        sys.stdout.write("{not-json")
        return
    if data == b"ROMAX-QA:crash":
        sys.exit(17)
    partial = data == b"ROMAX-QA:partial"
    emit({"status": "partial" if partial else "succeeded", "reason": "limit" if partial else None,
          "evidence": [{"location": {"page": 1, "block": 1}, "excerpt": "Synthetic fixture only"}],
          "candidates": [{"kind": "item", "evidence_ordinal": 1, "proposal": {"description": "Synthetic item", "quantity": "12", "unit_raw": "und", "flags": []}}]})

if __name__ == "__main__":
    main()
