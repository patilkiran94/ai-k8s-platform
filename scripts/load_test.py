#!/usr/bin/env python3
"""Tiny concurrent load tester (stdlib only).
usage: load_test.py URL [total=20] [concurrency=4]"""
import json, statistics, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

url = sys.argv[1].rstrip("/") + "/generate"
total = int(sys.argv[2]) if len(sys.argv) > 2 else 20
conc = int(sys.argv[3]) if len(sys.argv) > 3 else 4
body = json.dumps({"prompt": "Write one sentence about the sea.", "max_tokens": 40}).encode()

def one(_):
    t = time.perf_counter()
    try:
        req = urllib.request.Request(url, body, {"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as r:
            r.read(); code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
    except Exception:
        code = 0
    return code, time.perf_counter() - t

t0 = time.perf_counter()
with ThreadPoolExecutor(conc) as ex:
    results = list(ex.map(one, range(total)))
wall = time.perf_counter() - t0

lat = sorted(l for c, l in results if c == 200)
errs = sum(1 for c, _ in results if c != 200)
print(f"requests={total} concurrency={conc} wall={wall:.1f}s throughput={total/wall:.2f} req/s errors={errs}")
if lat:
    p = lambda q: lat[min(len(lat)-1, int(q*len(lat)))]
    print(f"latency  avg={statistics.mean(lat):.2f}s p50={p(.5):.2f}s p95={p(.95):.2f}s max={lat[-1]:.2f}s")
