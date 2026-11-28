"""Only built into the synthetic QA image; no live adapter."""
import sys
sys.path.insert(0,"/app")
from probe import verify, emit
from xlsx_reader import extract, result, MAX_FILE

def main():
    verify()
    data=sys.stdin.buffer.read(MAX_FILE+1)
    output=extract(data)
    # Bound serialized output, never silently truncate.
    import json
    if len(json.dumps(output,ensure_ascii=True).encode("ascii"))>2*1024*1024:
        output=result("unsupported","limit")
    emit(output)

if __name__=="__main__":
    main()
