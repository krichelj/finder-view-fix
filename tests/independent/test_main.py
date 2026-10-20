"""End-to-end tests of bulk_group_stamp.main() and make_targets.sh on
synthetic home trees, run serially, in threads and in processes."""
import os, random, stat, subprocess, sys, threading, time
import pytest
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
import dsparse, workers

REPO = workers.REPO


def tree(root, rng, n_dirs=200):
    dirs = [str(root)]
    for _ in range(n_dirs):
        parent = rng.choice(dirs)
        name = rng.choice(["Proj", "data", "Data", "café", "חדש", "a b", "x'y", "日本", "🙂", "-dash", "#h"]) + str(rng.randint(0, 999))
        p = os.path.join(parent, name); os.makedirs(p, exist_ok=True); dirs.append(p)
        if rng.random() < .3: open(os.path.join(p, "f.txt"), "w").close()
    return dirs[1:]


def stamped(path):
    parent, name = os.path.dirname(path), os.path.basename(path)
    ds = os.path.join(parent, ".DS_Store")
    return os.path.exists(ds) and dsparse.as_dict(dsparse.parse(ds)).get((name, "GRP0")) == "Kind"


def write_list(path, items):
    with open(path, "w", encoding="utf-8") as f: f.write("\n".join(items) + "\n")


def test_mixed_bad_inputs(tmp_path):
    good = tmp_path / "good"; good.mkdir()
    afile = tmp_path / "afile"; afile.write_text("x")
    ro = tmp_path / "ro"; (ro / "child").mkdir(parents=True); os.chmod(ro, 0o555)
    corrupt = tmp_path / "c"; (corrupt / "k").mkdir(parents=True)
    (corrupt / ".DS_Store").write_bytes(os.urandom(5000))
    lst = tmp_path / "l"
    write_list(lst, [str(good) + "/", str(tmp_path / "missing"), str(afile), str(ro / "child"),
                     str(corrupt / "k"), "", "   ", str(good)])
    try:
        out = workers.run_main(str(lst))
    finally:
        os.chmod(ro, 0o755)
    assert stamped(str(good)) and stamped(str(corrupt / "k"))
    assert not os.path.exists(ro / ".DS_Store")
    assert "parent not writable" in out and "missing" in out and "recreated fresh" in out
    assert "failed 0" in out


def test_home_target_uses_dot_record(tmp_path, monkeypatch):
    home = tmp_path / "home"; (home / "Docs").mkdir(parents=True)
    lst = tmp_path / "l"; write_list(lst, [str(home), str(home / "Docs")])
    env = dict(os.environ, HOME=str(home))
    subprocess.run([sys.executable, "-c", f"import workers; workers.run_main({str(lst)!r})"],
                   cwd=os.path.dirname(__file__), env=env, check=True)
    d = dsparse.as_dict(dsparse.parse(str(home / ".DS_Store")))
    assert d[(".", "GRP0")] == "Kind" and d[("Docs", "GRP0")] == "Kind"


def test_backup_holds_pre_run_bytes(tmp_path):
    import hashlib
    (tmp_path / "k").mkdir()
    orig = os.urandom(3000); (tmp_path / ".DS_Store").write_bytes(orig)
    lst = tmp_path / "l"; write_list(lst, [str(tmp_path / "k")]); workers.run_main(str(lst))
    h = hashlib.md5(str(tmp_path).encode()).hexdigest()[:12]
    assert open(f"/tmp/dsstore_backups/{h}.DS_Store", "rb").read() == orig


@pytest.mark.parametrize("mode", ["serial", "threads", "processes"])
def test_many_trees_parallel(tmp_path, mode):
    lists, all_dirs = [], []
    for i in range(12):
        root = tmp_path / f"t{i}"; root.mkdir()
        ds = tree(root, random.Random(i), 150); all_dirs += ds
        lists.append(str(tmp_path / f"l{i}")); write_list(lists[-1], ds)
    if mode == "serial": outs = list(map(workers.run_main, lists))
    elif mode == "threads":  # stdout redirection is process-global, so judge by files only
        with ThreadPoolExecutor(12) as ex: list(ex.map(workers.main_quiet, lists))
        outs = ["failed 0"] * len(lists)
    else:
        with ProcessPoolExecutor(min(12, os.cpu_count() or 4)) as ex: outs = list(ex.map(workers.run_main, lists))
    assert all("failed 0" in o for o in outs)
    missing = [d for d in all_dirs if not stamped(d)]
    assert not missing, missing[:5]


def test_concurrent_writers_same_parent_never_corrupt(tmp_path):
    """8 processes hammer ONE .DS_Store while a thread keeps parsing it.
    The file must always be valid (atomic replace) and end up containing
    at least one writer's complete set."""
    parent = str(tmp_path); groups = [[f"g{g}_{i}" for i in range(300)] for g in range(8)]
    for grp in groups:
        for n in grp: os.mkdir(os.path.join(parent, n))
    stop, errors, reads = threading.Event(), [], [0]

    def reader():
        ds = os.path.join(parent, ".DS_Store")
        while not stop.is_set():
            if os.path.exists(ds):
                try: dsparse.parse(ds); reads[0] += 1
                except FileNotFoundError: pass
                except Exception as e: errors.append(repr(e))
    t = threading.Thread(target=reader); t.start()
    try:
        with ProcessPoolExecutor(8) as ex:
            list(ex.map(workers.stamp_same_parent, [parent] * 8, groups, [5] * 8))
    finally:
        stop.set(); t.join()
    assert not errors, errors[:3]
    assert reads[0] > 0
    d = dsparse.as_dict(dsparse.parse(os.path.join(parent, ".DS_Store")))
    assert any(all(d.get((n, "GRP0")) == "Kind" for n in grp) for grp in groups)
    assert not [f for f in os.listdir(parent) if "fvtmp" in f], "temp files leaked"


# ---------- make_targets.sh ----------
def run_make_targets(home):
    env = dict(os.environ, HOME=str(home))
    out = "/tmp/fv_targets.txt"
    backup = open(out, "rb").read() if os.path.exists(out) else None
    try:
        subprocess.run(["bash", os.path.join(REPO, "make_targets.sh")], env=env, check=True, capture_output=True)
        return open(out, encoding="utf-8").read().splitlines()
    finally:
        if backup is not None: open(out, "wb").write(backup)


def test_make_targets_exclusions_and_odd_names(tmp_path):
    home = tmp_path / "h"
    keep = ["Documents/a b/c", "PycharmProjects/p/src", "Dropbox/חדש/日本", "x'y/\"q\"", "-n/-e"]
    skip = ["Library/Caches/x", ".hidden/y", "Documents/Foo.app/Contents", "p/node_modules/m",
            "Pictures/P.photoslibrary/r", "Documents/K.bundle/z", "Documents/.git/obj"]
    for k in keep + skip: (home / k).mkdir(parents=True)
    os.symlink(home / "Documents", home / "link_to_docs")
    got = set(run_make_targets(home))
    assert str(home) in got
    for k in keep:
        p = str(home / k)
        while p != str(home):
            assert p in got, p; p = os.path.dirname(p)
    for s in skip:
        assert not any(g.startswith(str(home / s)) for g in got), s
    assert not any(g.startswith(str(home / "link_to_docs")) for g in got)
    assert len(got) == len(run_make_targets(home)), "duplicates"


def test_make_targets_newline_name_does_not_break_pipeline(tmp_path):
    home = tmp_path / "h"; (home / "ok").mkdir(parents=True); (home / "bad\nname").mkdir()
    lines = run_make_targets(home)
    lst = tmp_path / "l"; write_list(lst, lines)
    out = workers.run_main(str(lst))
    assert "failed 0" in out and stamped(str(home / "ok"))
