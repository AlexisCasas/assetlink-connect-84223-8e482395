"""Synthetic-only XLSX coordinator. No live credentials, network adapters or scheduler."""
import hashlib
import time
from broker import (Failure, Scope, canonical_uuid, HASH, MAX_FILE, BUCKET,
                    read_bounded, _remaining, _run_container)
from xlsx_contract import checked
PARSER="xlsx-restricted-v1"
CONFIG=hashlib.sha256(b"xlsx-restricted-v1:10m:40m:20:50000:500").hexdigest()
MIME="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

class XlsxQABroker:
    def __init__(self,control,storage,image,fixture_hashes):
        self.control,self.storage,self.image=control,storage,image
        self.fixture_hashes=frozenset(fixture_hashes)
    def execute(self,scope,*,enabled=False):
        if enabled is not True or not isinstance(scope,Scope): raise Failure("worker_error")
        claim=self.control.claim(scope)
        if not isinstance(claim,dict) or claim.get("status")!="running" or claim.get("job_id")!=scope.job or not canonical_uuid(claim.get("lease")) or claim.get("parser")!=PARSER or claim.get("config")!=CONFIG:
            raise Failure("source_changed")
        s=claim.get("source")
        if not isinstance(s,dict) or not canonical_uuid(s.get("attempt")) or s.get("path")!="/".join(("quarantine",scope.org,scope.opportunity,scope.document,s["attempt"])) or s.get("mime")!=MIME or not isinstance(s.get("hash"),str) or not HASH.fullmatch(s["hash"]) or type(s.get("size"))!=int or not 1<=s["size"]<=MAX_FILE:
            raise Failure("source_changed")
        # Fixture digest allowlist is built in CI from generated synthetic files.
        if s["hash"] not in self.fixture_hashes: raise Failure("unsupported_format")
        deadline=time.monotonic()+60
        try:
            data=read_bounded(self.storage.chunks(BUCKET,s["path"],deadline),s["size"],s["hash"],deadline)
            result=checked(_run_container(self.image,data,_remaining(deadline)))
        except Failure as exc:
            result={"status":"retry" if exc.code in ("timeout","worker_error") else "failed","reason":exc.code,"evidence":[],"candidates":[]}
        except Exception:
            result={"status":"retry","reason":"worker_error","evidence":[],"candidates":[]}
        return self.control.finish(scope,claim["lease"],s["hash"],result)
