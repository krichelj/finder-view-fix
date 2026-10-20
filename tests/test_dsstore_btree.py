#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["ds-store"]
# ///
"""Property test for the .DS_Store writer: random insertion orders and
sizes forcing multi-level splits, then round-trip read via an UNPATCHED
reader in a fresh subprocess and compare against a Python dict oracle:
every key present exactly once, no extras, values correct."""
import os, sys, random, subprocess, tempfile, json, importlib.util
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bgs", os.path.join(here, "..", "bulk_group_stamp.py"))
bgs = importlib.util.module_from_spec(spec); spec.loader.exec_module(bgs)
from ds_store import DSStore
from ds_store.store import PlistCodec

READER = r'''
import sys, json
from ds_store import DSStore
out = {}
with DSStore.open(sys.argv[1], "r") as d:
    keys = [(e.filename, e.code.decode()) for e in d]
    for e in d: out.setdefault(e.filename, {})[e.code.decode()] = e.value.decode("latin_1") if isinstance(e.value, bytes) else str(e.value)
    # B-tree SEARCH path (what Finder does per folder), not just iteration
    lookup_fail = sum(1 for n in out if d[n]["GRP0"][1] != "Kind")
print(json.dumps({"order": keys, "data": out, "lookup_fail": lookup_fail}))
'''
fails = 0
for seed in range(40):
    rng = random.Random(seed)
    n = rng.choice([1, 7, 60, 300, 1500, 4000])
    names = ["".join(rng.choice("abcXYZ_ 0123456789חד") for _ in range(rng.randint(1, 40))) for _ in range(n)]
    names = list(dict.fromkeys(names))
    order = {0: sorted(names), 1: sorted(names, reverse=True)}.get(seed % 3, names[:])
    if seed % 3 == 2: rng.shuffle(order)
    p = tempfile.mktemp(suffix=".DS_Store"); oracle = {}
    recs = {}
    for nm in order:
        bgs.stamp(recs, nm); oracle[nm] = 1
    # pre-existing foreign record with a dateModified sort that must be rewritten
    recs[(order[0], "lsvp")] = (PlistCodec, {"sortColumn": "dateModified", "iconSize": 16.0})
    bgs.write_records(p, recs)
    # second pass: read back with the tool's reader, re-stamp a subset, rewrite
    recs2 = bgs.read_records(p)
    for nm in rng.sample(order, min(50, len(order))): bgs.stamp(recs2, nm)
    bgs.stamp(recs2, order[0])
    bgs.write_records(p, recs2)
    r = subprocess.run([sys.executable, "-c", READER, p], capture_output=True, text=True)
    if r.returncode: print("FAIL read", seed, r.stderr[-300:]); fails += 1; continue
    got = json.loads(r.stdout)
    keys = [tuple(k) for k in got["order"]]
    data = got["data"]
    bad = [nm for nm in oracle if data.get(nm, {}).get("GRP0") != "Kind" or data[nm].get("vstl") != "Nlsv"
           or "sortColumn" not in data[nm].get("lsvC", "") or "name" not in data[nm].get("lsvC", "")]
    dup = len(keys) != len(set(keys))
    if got["lookup_fail"]:
        bad.append(("lookup_fail", got["lookup_fail"]))
    lsvp = data.get(order[0], {}).get("lsvp", "")
    if "'sortColumn': 'name'" not in lsvp or "iconSize" not in lsvp:
        bad.append(("lsvp", lsvp[:80]))
    extra = set(data) - set(oracle)
    if bad or dup or extra:
        print(f"FAIL seed={seed} n={len(order)} missing={len(bad)} dup={dup} extra={len(extra)}"); fails += 1
    else:
        print(f"ok   seed={seed} n={len(order)} entries={len(keys)}")
    os.remove(p)
print("RESULT:", "FAIL" if fails else "PASS", fails)
sys.exit(1 if fails else 0)
