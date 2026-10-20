#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["ds-store"]
# ///
"""Independent audit: walks every visible folder under $HOME (not the target list)
and reads its effective per-folder view state from the parent .DS_Store.
A folder is uniform iff: GRP0 == Kind, no vstl other than Nlsv, and any
lsvp/lsvC sortColumn is 'name'. Prints counts + offenders; exit 1 if any."""
import os, sys, plistlib
from ds_store import DSStore

SKIP = {"Library", "node_modules", ".Trash"}
BUNDLE = (".app", ".bundle", ".framework", ".photoslibrary", ".pkg", ".xcodeproj", ".lproj", ".xcassets", ".plugin", ".kext")

def folders(home):
    yield home
    for root, dirs, _ in os.walk(home):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP and not d.endswith(BUNDLE)
                   and not os.path.islink(os.path.join(root, d))]
        for d in dirs:
            yield os.path.join(root, d)

def entries(parent, cache={}):
    if parent in cache: return cache[parent]
    e = {}
    ds = os.path.join(parent, ".DS_Store")
    if os.path.exists(ds):
        try:
            with DSStore.open(ds, "r") as d:
                for x in d: e.setdefault(x.filename, {})[x.code.decode()] = x.value
        except Exception as ex:
            e = {"__error__": str(ex)}
    cache[parent] = e
    return e

def sortcol(v):
    if isinstance(v, (bytes, bytearray)):
        try: v = plistlib.loads(bytes(v))
        except Exception: return None
    return v.get("sortColumn") if isinstance(v, dict) else None

def check(path):
    p = path.rstrip("/")
    parent, name = (p, ".") if p == HOME else (os.path.dirname(p), os.path.basename(p))
    e = entries(parent)
    if "__error__" in e: return ["unreadable .DS_Store"]
    r = e.get(name, {})
    bad = []
    if r.get("GRP0") != "Kind": bad.append(f"GRP0={r.get('GRP0')}")
    v = r.get("vstl")
    if v is not None and bytes(v) != b"Nlsv": bad.append(f"vstl={v}")
    for k in ("lsvp", "lsvC"):
        if k in r:
            s = sortcol(r[k])
            if s not in (None, "name"): bad.append(f"{k}.sort={s}")
    return bad

HOME = os.path.expanduser("~")
if __name__ == "__main__":
    if sys.argv[1:2] == ["--only"]:  # audit exactly these folders
        fs = sys.argv[2:]; off = [(f, b) for f in fs if (b := check(f))]
        print(f"audited {len(fs)} folders, {len(off)} non-uniform")
        for f, b in off[:15]: print("  ", f, b)
        sys.exit(1 if off else 0)
    roots = sys.argv[1:] or [HOME]
    tot = 0; off = []
    for root in roots:
        for f in (folders(root) if root == HOME else [root, *[os.path.join(a, d) for a, ds, _ in os.walk(root) for d in ds if not d.startswith('.')]]):
            if not os.access(os.path.dirname(f.rstrip('/')) or "/", os.W_OK): continue
            tot += 1
            b = check(f)
            if b: off.append((f, b))
    print(f"audited {tot} folders, {len(off)} non-uniform")
    for f, b in off[:15]: print("  ", f, b)
    sys.exit(1 if off else 0)
