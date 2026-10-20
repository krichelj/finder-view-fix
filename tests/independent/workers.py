"""Top-level (picklable) worker functions for multiprocessing tests."""
import importlib.util, io, os, contextlib, random, sys
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _bgs():
    spec = importlib.util.spec_from_file_location("bgs", os.environ.get("BGS_PATH", os.path.join(REPO, "bulk_group_stamp.py")))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


def run_main(list_path):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        _bgs().main(list_path)
    return out.getvalue()


def stamp_same_parent(parent, names, rounds):
    m = _bgs(); ds = os.path.join(parent, ".DS_Store")
    for _ in range(rounds):
        recs = m.read_records(ds)
        for n in names: m.stamp(recs, n)
        m.write_records(ds, recs)
    return len(names)


def main_quiet(list_path):
    _bgs().main(list_path)
