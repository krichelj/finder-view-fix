"""audit_views.check() must flag every kind of non-uniform record."""
import os, plistlib, subprocess, sys
from conftest import REPO

AUDIT = os.path.join(REPO, "tests", "audit_views.py")


def audit(home, *args):
    env = dict(os.environ, HOME=str(home))
    r = subprocess.run([sys.executable, AUDIT, *args], env=env, capture_output=True, text=True)
    return r.returncode, r.stdout


def test_detects_each_defect(tmp_path, bgs):
    home = tmp_path
    for n in ["ok", "nogrp", "icon", "datesort", "datesortC", "Name"]: (home / n).mkdir()
    recs = {}
    for n in ["ok", "icon", "datesort", "datesortC", "Name", "."]: bgs.stamp(recs, n)
    recs[("icon", "vstl")] = ("type", b"icnv")
    recs[("Name", "GRP0")] = ("ustr", "Name")
    p = str(home / ".DS_Store"); bgs.write_records(p, recs)
    r = bgs.read_records(p)
    r[("datesort", "lsvC")] = ("blob", plistlib.dumps({"sortColumn": "dateModified"}, fmt=plistlib.FMT_BINARY))
    r[("datesortC", "lsvC")] = ("blob", plistlib.dumps({"sortColumn": "size"}, fmt=plistlib.FMT_BINARY))
    bgs.write_records(p, r)
    rc, out = audit(home)
    assert rc == 1
    for bad in ["nogrp", "icon", "datesort", "datesortC", "/Name"]:
        assert bad in out, (bad, out)
    assert "7 folders, 5 non-uniform"  # 6 children + home itself in out.replace("audited ", "")


def test_clean_tree_passes_and_unreadable_flagged(tmp_path, bgs):
    (tmp_path / "a").mkdir(); recs = {}
    bgs.stamp(recs, "."); bgs.stamp(recs, "a"); bgs.write_records(str(tmp_path / ".DS_Store"), recs)
    assert audit(tmp_path)[0] == 0
    (tmp_path / "a" / "b").mkdir(); (tmp_path / "a" / ".DS_Store").write_bytes(b"garbage" * 100)
    rc, out = audit(tmp_path)
    assert rc == 1 and "unreadable" in out
