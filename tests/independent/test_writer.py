"""Writer/stamper edge cases, validated by the independent parser."""
import os, plistlib, random, string
import pytest
from concurrent.futures import ThreadPoolExecutor
from ds_store import DSStore
import dsparse

ALPH = string.ascii_letters + string.digits + " ._-()[]&'#%+,;=@" + "חדשׁéüßøåÆ日本語한국🙂"


def names(rng, n, maxlen=60):
    s = set()
    while len(s) < n:
        s.add("".join(rng.choice(ALPH) for _ in range(rng.randint(1, maxlen))))
    return list(s)


def check(path, expected_names, bgs_extra=None):
    recs = dsparse.parse(path)                       # structure validated here
    keys = [(r[0], r[1]) for r in recs]
    assert len(keys) == len(set(keys)), "duplicate records"
    ks = [dsparse.finder_key(r) for r in recs]
    assert all(a <= b for a, b in zip(ks, ks[1:])), "not in Finder order"
    d = dsparse.as_dict(recs)
    for n in expected_names:
        assert d[(n, "GRP0")] == "Kind"
        assert d[(n, "vstl")] == b"Nlsv"
        assert plistlib.loads(d[(n, "lsvC")])["sortColumn"] == "name"
    with DSStore.open(path, "r") as s:               # stock-library search path
        for n in expected_names:
            assert s[n]["GRP0"][1] == "Kind"
    return d


@pytest.mark.parametrize("n", [0, 1, 2, 3, 15, 16, 17, 100, 500, 2000, 6000])
@pytest.mark.parametrize("order", ["sorted", "reversed", "shuffled"])
def test_sizes_and_orders(bgs, tmp_path, n, order):
    rng = random.Random(n * 7 + len(order))
    ns = names(rng, n)
    ns = {"sorted": sorted(ns), "reversed": sorted(ns, reverse=True)}.get(order, ns)
    if order == "shuffled": rng.shuffle(ns)
    recs = {}
    for x in ns: bgs.stamp(recs, x)
    p = str(tmp_path / ".DS_Store")
    bgs.write_records(p, recs)
    if n == 0:
        assert dsparse.parse(p) == []
    else:
        check(p, ns)


def test_case_only_collisions(bgs, tmp_path):
    ns = ["Foo", "foo", "FOO", "fOo", "a", "A", "Zeta", "zeta"]
    recs = {}
    for x in ns: bgs.stamp(recs, x)
    p = str(tmp_path / ".DS_Store"); bgs.write_records(p, recs)
    check(p, ns)


def test_max_length_names_force_deep_tree(bgs, tmp_path):
    rng = random.Random(1)
    ns = names(rng, 3000, maxlen=255)
    ns = [x[:255] for x in ns]
    recs = {}
    for x in ns: bgs.stamp(recs, x)
    p = str(tmp_path / ".DS_Store"); bgs.write_records(p, recs)
    check(p, ns)


def test_dot_record_for_home(bgs, tmp_path):
    recs = {}
    bgs.stamp(recs, "."); bgs.stamp(recs, ".hidden"); bgs.stamp(recs, "Documents")
    p = str(tmp_path / ".DS_Store"); bgs.write_records(p, recs)
    check(p, [".", ".hidden", "Documents"])


def test_foreign_records_preserved_and_sort_rewritten(bgs, tmp_path):
    p = str(tmp_path / ".DS_Store")
    lsvp = {"sortColumn": "dateModified", "iconSize": 16.0, "columns": {"name": {"width": 300}}}
    lsvc = plistlib.dumps({"sortColumn": "dateAdded", "textSize": 13.0}, fmt=plistlib.FMT_BINARY)
    with DSStore.open(p, "w+") as d:   # stock library writes the "Finder" file
        d["A"]["Iloc"] = (15, 15)
        d["A"]["lsvp"] = lsvp
        d["A"]["lsvC"] = ("blob", lsvc)
        d["B"]["cmmt"] = ("ustr", "a comment")
        d["B"]["GRP0"] = ("ustr", "Name")
    recs = bgs.read_records(p)
    bgs.stamp(recs, "A"); bgs.stamp(recs, "B")
    bgs.write_records(p, recs)
    d = check(p, ["A", "B"])
    assert d[("B", "cmmt")] == "a comment"
    assert ("A", "Iloc") in d
    pl = plistlib.loads(d[("A", "lsvp")])
    assert pl["sortColumn"] == "name" and pl["iconSize"] == 16.0 and pl["columns"]["name"]["width"] == 300
    pc = plistlib.loads(d[("A", "lsvC")])
    assert pc == {"sortColumn": "name", "textSize": 13.0}


def test_malformed_plist_left_untouched(bgs, tmp_path):
    p = str(tmp_path / ".DS_Store")
    recs = {("X", "lsvC"): ("blob", b"not a plist")}
    bgs.stamp(recs, "X"); bgs.write_records(p, recs)
    d = dsparse.as_dict(dsparse.parse(p))
    assert d[("X", "lsvC")] == b"not a plist" and d[("X", "GRP0")] == "Kind"


def test_idempotent_byte_identical(bgs, tmp_path):
    rng = random.Random(5); ns = names(rng, 800)
    p = str(tmp_path / ".DS_Store"); recs = {}
    for x in ns: bgs.stamp(recs, x)
    bgs.write_records(p, recs); first = open(p, "rb").read()
    recs2 = bgs.read_records(p)
    for x in ns: bgs.stamp(recs2, x)
    bgs.write_records(p, recs2)
    assert open(p, "rb").read() == first


def test_no_temp_file_left(bgs, tmp_path):
    recs = {}; bgs.stamp(recs, "a")
    bgs.write_records(str(tmp_path / ".DS_Store"), recs)
    assert sorted(os.listdir(tmp_path)) == [".DS_Store"]


def test_many_stores_in_threads(bgs, tmp_path):
    """64 independent stores written concurrently from 16 threads."""
    def job(i):
        rng = random.Random(i); ns = names(rng, rng.choice([1, 50, 700, 2500]))
        d = tmp_path / f"s{i}"; d.mkdir(); p = str(d / ".DS_Store"); recs = {}
        for x in ns: bgs.stamp(recs, x)
        bgs.write_records(p, recs); check(p, ns); return len(ns)
    with ThreadPoolExecutor(16) as ex:
        assert all(ex.map(job, range(64)))


def fixed_name(i, L):
    """i-th distinct, case-insensitively unique name of exactly L chars."""
    digits = string.ascii_lowercase + string.digits  # 36 symbols
    out = ""
    for _ in range(L):
        out = digits[i % 36] + out; i //= 36
    return out


@pytest.mark.parametrize("namelen", [1, 7, 30, 64, 128, 200, 255])
def test_node_capacity_boundaries(bgs, tmp_path, namelen):
    """Equal-size records so leaf capacity c is exact; n = c+1, 2c+1, ... put
    the overflowing record last, the case that once produced a 4137-byte node."""
    from ds_store.store import DSStoreEntry
    probe = {}; bgs.stamp(probe, "x" * namelen)
    sizes = [DSStoreEntry(f, c.encode(), t, v).byte_length() for (f, c), (t, v) in probe.items()]
    per_name = sum(sizes)
    c = (4096 - 8) // per_name + 1
    for n in sorted({max(1, c - 1), c, c + 1, c + 2, 2 * c, 2 * c + 1, 2 * c + 2, 5 * c + 1}):
        if n > 36 ** namelen: continue
        ns = [fixed_name(i, namelen) for i in range(n)]
        assert len(set(n.lower() for n in ns)) == len(ns)
        recs = {}
        for x in ns: bgs.stamp(recs, x)
        p = str(tmp_path / f"{n}.DS_Store"); bgs.write_records(p, recs)
        check(p, ns)


def _seed_case(seed):
    import importlib, tempfile, workers
    m = workers._bgs(); rng = random.Random(seed)
    ns = names(rng, rng.randint(1, 3000), maxlen=rng.choice([5, 40, 255]))
    recs = {}
    for x in ns: m.stamp(recs, x)
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, ".DS_Store"); m.write_records(p, recs); check(p, ns)
    return seed


def test_300_random_trees_in_process_pool():
    from concurrent.futures import ProcessPoolExecutor
    with ProcessPoolExecutor() as ex:
        assert sorted(ex.map(_seed_case, range(300))) == list(range(300))
