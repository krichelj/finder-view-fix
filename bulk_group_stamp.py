#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["ds-store"]
# ///
"""
bulk_group_stamp.py - make Finder group folders by Kind, in bulk.

Finder has no global default for grouping (macOS 26-27). It stores grouping per
folder, as record GRP0 in the PARENT folder's .DS_Store keyed by the child's
name (or in the folder's own "." record when the parent is unwritable).
List view and sort by Name are global defaults (see setup.sh), so this tool
only writes GRP0=Kind; besides that it corrects a per-folder view or sort that
Finder already saved as something else (vstl != Nlsv, sortColumn != name).
Stores that already comply are not rewritten.

Finder caches .DS_Store contents and writes them back, so run this with Finder
stopped (maintain.sh does that).

Usage: uv run bulk_group_stamp.py [--check] <folder-list-file>
  --check  count folders that need a change, write nothing (exit 1 if any)
"""
import os, sys, shutil, hashlib, plistlib, tempfile
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
    if pl.get("sortColumn", "name") == "name":
        return v  # already name (or unset, which means name): leave the bytes alone
    pl["sortColumn"] = "name"
    return plistlib.dumps(pl, fmt=plistlib.FMT_BINARY) if raw else pl


def stamp(recs, n):
    """recs: {(filename, code): (type, value)}. Make folder n grouped by Kind and
    fix a saved non-list view or non-name sort. Returns True if recs changed."""
    changed = False
    if recs.get((n, "GRP0"), (None, None))[1] != GROUP_VALUE:
        recs[(n, "GRP0")] = ("ustr", GROUP_VALUE); changed = True
    if (n, "vstl") in recs and bytes(recs[(n, "vstl")][1]) != b"Nlsv":
        recs[(n, "vstl")] = ("type", b"Nlsv"); changed = True
    for k in ("lsvp", "lsvC"):
        if (n, k) in recs:
            t, v = recs[(n, k)]
            nv = _name_sorted(v)
            if nv is not None and nv != v:
                recs[(n, k)] = (t, nv); changed = True
    return changed


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
        if cur and size + need > page:
            if i < len(items) - 1:
                nodes.append(cur); seps.append(i); cur, size = [], 8
                i += 1  # items[i] becomes the separator
                continue
            # Last item does not fit and cannot be a separator (no right node
            # would follow): promote the current node's last item instead and
            # put the final item alone in a new right node.
            assert len(cur) > 1
            seps.append(cur.pop()); nodes.append(cur); cur, size = [], 8
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
    # Explicit total order (case-insensitive name, then code), as Finder
    # searches. DSStoreEntry.__lt__ is not a strict weak order for names that
    # differ only in case ("A" vs "a"), so sorted() on it can interleave them.
    ents = sorted((DSStoreEntry(f, c.encode(), t, v) for (f, c), (t, v) in recs.items()),
                  key=lambda e: (e.filename.lower(), e.filename, e.code))
    # Unique temp file in the same directory: concurrent runs must not share
    # one temp path, and os.replace keeps readers from seeing a partial file.
    fd, tmp = tempfile.mkstemp(prefix=".DS_Store.", suffix=".fvtmp", dir=os.path.dirname(ds_path) or ".")
    os.close(fd)
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


def _in_cloud_storage(path):
    cs = os.path.join(os.path.expanduser("~"), "Library", "CloudStorage") + os.sep
    return (path.rstrip("/") + os.sep).startswith(cs)


def main(list_path, check=False):
    """Returns the number of folders that needed (or, with check, need) a change."""
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
            # Finder keeps a folder's view in its OWN .DS_Store under the "."
            # record when the parent is unwritable (e.g. /Applications), but
            # not for the top folders of a cloud drive (read-only FileProvider
            # account folder): Finder has nowhere to save those, so skip them.
            if name != "." and os.access(t, os.W_OK) and not _in_cloud_storage(parent):
                parent, name = t.rstrip("/"), "."
            else:
                skipped.append((t, "parent not writable"))
                continue
        by_parent[parent].append(name)

    bdir = os.path.join(home, "Library", "Application Support", "finder-view-fix", "unreadable-backups")
    changed = stores = failed = 0
    fails = []
    for parent, names in sorted(by_parent.items()):
        ds_path = os.path.join(parent, ".DS_Store")
        try:
            recs = read_records(ds_path)
        except Exception as ex:
            # Unparseable store: keep a copy (outside /tmp, never overwritten)
            # and start fresh.
            recs = None
            if not check:
                os.makedirs(bdir, exist_ok=True)
                h = hashlib.md5(parent.encode()).hexdigest()[:12]
                shutil.copy2(ds_path, os.path.join(bdir, f"{h}-{int(os.path.getmtime(ds_path))}.DS_Store"))
            fails.append(f"{parent}: unreadable, recreated fresh ({ex})")
        n_changed = 0
        recs = recs if recs is not None else {}
        for n in names:
            n_changed += stamp(recs, n)
        if n_changed == 0:
            continue
        changed += n_changed
        if check:
            continue
        try:
            write_records(ds_path, recs)
            stores += 1
        except Exception as ex:
            failed += n_changed
            fails.append(f"{parent}: {ex}")

    verb = "need a change" if check else "changed"
    print(f"{len(targets)} folders; {changed} {verb} across {stores if not check else '-'} .DS_Store files written; "
          f"failed {failed}; skipped {len(skipped)}")
    for s_ in fails[:10]:
        print("  FAIL:", s_)
    for t, why in skipped[:10]:
        print("  SKIP:", why, "->", t)
    return changed


if __name__ == "__main__":
    args = sys.argv[1:]
    chk = "--check" in args
    args = [a for a in args if a != "--check"]
    n = main(args[0] if args else "/tmp/fv_targets.txt", check=chk)
    sys.exit(1 if chk and n else 0)
