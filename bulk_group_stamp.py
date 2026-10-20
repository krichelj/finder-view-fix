#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["ds-store"]
# ///
"""
bulk_group_stamp.py - enable Finder 'Group by Kind' for thousands of folders at once.

DISCOVERY (macOS 26): Finder stores a folder's grouping setting in the PARENT
folder's .DS_Store, as an entry keyed by the child folder's name with code
'GRP0' (value: 'Kind', 'None', 'Name', ...). No window automation needed.

Usage:
    # Quit Finder first, then:
    uv run bulk_group_stamp.py /tmp/fv_targets.txt
    # then relaunch Finder.

Backups of every modified .DS_Store go to /tmp/dsstore_backups/.
Dependencies are declared inline (PEP 723) - uv handles them automatically.
"""
import os, sys, shutil, hashlib, plistlib
from collections import defaultdict
from ds_store import DSStore
from ds_store.store import DSStoreEntry

GROUP_VALUE = "Kind"


def _name_sorted(v):
    """lsvp/lsvC value with sortColumn forced to 'name' (keeps encoding)."""
    raw = isinstance(v, (bytes, bytearray))
    try:
        pl = plistlib.loads(bytes(v)) if raw else dict(v)
    except Exception:
        return None
    pl["sortColumn"] = "name"
    return plistlib.dumps(pl, fmt=plistlib.FMT_BINARY) if raw else pl


def stamp(recs, n):
    """recs: {(filename, code): (type, value)}. Per-folder overrides beat the
    global defaults, so make them uniform: group=Kind, view=list, sort=name."""
    recs[(n, "GRP0")] = ("ustr", GROUP_VALUE)
    recs[(n, "vstl")] = ("type", b"Nlsv")
    recs[(n, "vSrn")] = ("long", 1)
    if (n, "lsvC") not in recs:
        # Without a saved lsvC Finder seeds one from its own per-folder default
        # (e.g. Downloads -> Date Added) the first time the folder opens, which
        # beats the global sort. Pre-seed it with sort = name.
        recs[(n, "lsvC")] = ("blob", plistlib.dumps(
            {"sortColumn": "name", "viewOptionsVersion": 1}, fmt=plistlib.FMT_BINARY))
    for k in ("lsvp", "lsvC"):
        if (n, k) in recs:
            t, v = recs[(n, k)]
            nv = _name_sorted(v)
            if nv is not None:
                recs[(n, k)] = (t, nv)


def read_records(ds_path):
    recs = {}
    if os.path.exists(ds_path):
        with DSStore.open(ds_path, "r") as d:
            for e in d:
                recs[(e.filename, e.code.decode())] = (e.type, e.value)
    return recs


def _pack(items, children, page):
    """Greedy-pack sorted entries into B-tree nodes of <= `page` bytes.
    Returns (nodes, separators): node i holds items[a:b] (+ child ptrs when
    `children` is given) and separators[i] sits between node i and i+1."""
    ptr = 4 if children is not None else 0
    nodes, seps, cur, size, i = [], [], [], 8, 0
    while i < len(items):
        need = ptr + items[i].byte_length()
        if cur and size + need > page and i < len(items) - 1:
            nodes.append(cur); seps.append(i); cur, size = [], 8
            i += 1  # items[i] becomes the separator
            continue
        cur.append(i); size += need; i += 1
    nodes.append(cur)
    return nodes, seps


def write_records(ds_path, recs):
    """Rebuild the file in one shot with a bottom-up B-tree build.
    ds_store 1.3.x cannot be trusted to write: incremental inserts corrupt the
    tree on node split (DSStore._split -> IndexError 'list index out of range',
    _insert_inner -> BuddyError), and its initial_entries bulk builder also
    raises IndexError for multi-level trees. Those failures left ~13k folders
    unstamped. Only its buddy allocator and entry serialiser are used here."""
    ents = sorted(DSStoreEntry(f, c.encode(), t, v) for (f, c), (t, v) in recs.items())
    tmp = ds_path + ".fvtmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    with DSStore.open(tmp, "w+") as d:
        page = d._page_size
        items, children, levels, nnodes = ents, None, 0, 0
        while True:
            nodes, seps = _pack(items, children, page)
            ptrs = []
            for k, idx in enumerate(nodes):
                blk = d._rootnode if (len(nodes) == 1) else d._store.allocate(page)
                with d._get_block(blk) as b:
                    b.seek(0)
                    if children is None:
                        b.write(b">II", 0, len(idx))
                        for j in idx:
                            items[j].write(b)
                    else:
                        right = seps[k] if k < len(seps) else len(items)
                        b.write(b">II", children[right], len(idx))
                        for j in idx:
                            b.write(b">I", children[j])
                            items[j].write(b)
                    b.zero_fill()
                ptrs.append(blk)
            nnodes += len(nodes)
            if len(nodes) == 1:
                break
            items, children = [items[j] for j in seps], ptrs
            levels += 1
        d._levels, d._records, d._nodes, d._dirty = levels, len(ents), nnodes, True
    os.replace(tmp, ds_path)


def main(list_path):
    with open(list_path, encoding="utf-8") as f:
        targets = [l.rstrip("\n") for l in f if l.strip()]

    home = os.path.expanduser("~")
    by_parent = defaultdict(list)
    skipped = []
    for t in targets:
        parent = os.path.dirname(t.rstrip("/"))
        name = os.path.basename(t.rstrip("/"))
        if t.rstrip("/") == home:
            parent, name = home, "."
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
        if os.path.exists(ds_path):
            h = hashlib.md5(parent.encode()).hexdigest()[:12]
            shutil.copy2(ds_path, os.path.join(bdir, f"{h}.DS_Store"))
        try:
            recs = read_records(ds_path)
        except Exception as ex:
            # Unparseable existing store (already backed up): start fresh.
            recs = {}
            fails.append(f"{parent}: unreadable, recreated fresh ({ex})")
        try:
            for n in names:
                stamp(recs, n)
            write_records(ds_path, recs)
            written += len(names); stores += 1
        except Exception as ex:
            failed += len(names)
            fails.append(f"{parent}: {ex}")

    print(f"stamped {written} folders across {stores} .DS_Store files; "
          f"failed {failed}; skipped {len(skipped)}")
    for s in fails[:10]:
        print("  FAIL:", s)
    for t, why in skipped[:10]:
        print("  SKIP:", why, "->", t)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fv_targets.txt")
