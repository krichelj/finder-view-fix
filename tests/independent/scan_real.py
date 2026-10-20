"""Validate every .DS_Store under $HOME with the independent parser
(structure, page bounds, record counts, Finder key order). Exit 1 on defects."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import dsparse
home = os.path.expanduser("~"); bad = []; n = 0
for root, dirs, files in os.walk(home):
    dirs[:] = [d for d in dirs if d != "Library" and not d.startswith(".Trash")]
    if ".DS_Store" in files:
        p = os.path.join(root, ".DS_Store"); n += 1
        try:
            recs = dsparse.parse(p)
            ks = [dsparse.finder_key(r) for r in recs]
            assert all(a <= b for a, b in zip(ks, ks[1:])), "order"
        except PermissionError:
            n -= 1
        except Exception as e:
            bad.append((p, repr(e)[:100]))
print(f"scanned {n} .DS_Store files, {len(bad)} invalid")
for b in bad[:10]: print("  ", *b)
sys.exit(1 if bad else 0)
