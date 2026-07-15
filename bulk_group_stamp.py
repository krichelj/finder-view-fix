#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["ds-store"]
# ///
"""
bulk_group_stamp.py — enable Finder 'Group by Kind' for thousands of folders at once.

DISCOVERY (macOS 26): Finder stores a folder's grouping setting in the PARENT
folder's .DS_Store, as an entry keyed by the child folder's name with code
'GRP0' (value: 'Kind', 'None', 'Name', ...). No window automation needed.

Usage:
    # Quit Finder first, then:
    uv run bulk_group_stamp.py /tmp/fv_targets.txt
    # then relaunch Finder.

Backups of every modified .DS_Store go to /tmp/dsstore_backups/.
Dependencies are declared inline (PEP 723) — uv handles them automatically.
"""
import os, sys, shutil, hashlib
from collections import defaultdict
from ds_store import DSStore

GROUP_VALUE = "Kind"

def main(list_path):
    with open(list_path, encoding="utf-8") as f:
        targets = [l.rstrip("\n") for l in f if l.strip()]

    home = os.path.expanduser("~")
    by_parent = defaultdict(list)
    skipped = []
    for t in targets:
        parent = os.path.dirname(t.rstrip("/"))
        name = os.path.basename(t.rstrip("/"))
        if not name or not os.path.isdir(t):
            skipped.append((t, "missing"))
            continue
        if not os.access(parent, os.W_OK):
            skipped.append((t, "parent not writable"))
            continue
        by_parent[parent].append(name)

    bdir = "/tmp/dsstore_backups"
    os.makedirs(bdir, exist_ok=True)

    written = failed = stores = 0
    fails = []
    for parent, names in sorted(by_parent.items()):
        ds_path = os.path.join(parent, ".DS_Store")
        try:
            exists = os.path.exists(ds_path)
            if exists:
                h = hashlib.md5(parent.encode()).hexdigest()[:12]
                shutil.copy2(ds_path, os.path.join(bdir, f"{h}.DS_Store"))
            mode = "r+" if exists else "w+"
            with DSStore.open(ds_path, mode) as d:
                for n in names:
                    d[n]["GRP0"] = ("ustr", GROUP_VALUE)
                    d[n]["vSrn"] = ("long", 1)
                    written += 1
            stores += 1
        except Exception as ex:
            # Existing .DS_Store unparseable (Finder block layouts the lib
            # can't handle). Original is already backed up — recreate fresh.
            try:
                if os.path.exists(ds_path):
                    os.remove(ds_path)
                with DSStore.open(ds_path, "w+") as d:
                    for n in names:
                        d[n]["GRP0"] = ("ustr", GROUP_VALUE)
                        d[n]["vSrn"] = ("long", 1)
                        written += 1
                stores += 1
                fails.append(f"{parent}: recreated fresh ({ex})")
            except Exception as ex2:
                failed += len(names)
                fails.append(f"{parent}: {ex2}")

    print(f"stamped {written} folders across {stores} .DS_Store files; "
          f"failed {failed}; skipped {len(skipped)}")
    for s in fails[:10]:
        print("  FAIL:", s)
    for t, why in skipped[:10]:
        print("  SKIP:", why, "->", t)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fv_targets.txt")
