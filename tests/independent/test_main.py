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


def test_mixed_bad_inputs(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path / "fakehome"))   # backups land here, not in the real home
    good = tmp_path / "good"; good.mkdir()
    afile = tmp_path / "afile"; afile.write_text("x")
    ro = tmp_path / "ro"; (ro / "child").mkdir(parents=True); os.chmod(ro, 0o555)
    corrupt = tmp_path / "c"; (corrupt / "k").mkdir(parents=True)
    (corrupt / ".DS_Store").write_bytes(os.urandom(5000))
    lst = tmp_path / "l"
    write_list(lst, [str(good) + "/", str(tmp_path / "missing"), str(afile), str(ro / "child"),
                     str(corrupt / "k"), "", "   ", str(good)])
    ro2 = tmp_path / "ro2"; (ro2 / "locked").mkdir(parents=True)
    os.chmod(ro2 / "locked", 0o555); os.chmod(ro2, 0o555)
    write_list(lst, [str(good) + "/", str(tmp_path / "missing"), str(afile), str(ro / "child"),
                     str(corrupt / "k"), "", "   ", str(good), str(ro2 / "locked")])
    try:
        out = workers.run_main(str(lst))
    finally:
        os.chmod(ro, 0o755); os.chmod(ro2, 0o755); os.chmod(ro2 / "locked", 0o755)
    assert stamped(str(good)) and stamped(str(corrupt / "k"))
    # parent unwritable, folder writable: Finder's own "." record in the folder
    assert not os.path.exists(ro / ".DS_Store")
    self_rec = dsparse.as_dict(dsparse.parse(str(ro / "child" / ".DS_Store")))
    assert self_rec[(".", "GRP0")] == "Kind"
    # both unwritable: skipped, nothing written anywhere
    assert not os.path.exists(ro2 / ".DS_Store") and not os.path.exists(ro2 / "locked" / ".DS_Store")
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


def test_unreadable_store_backed_up_outside_tmp(tmp_path):
    """Only an unparseable store is replaced wholesale; its original bytes are
    kept under ~/Library/Application Support (not /tmp, never overwritten)."""
    home = tmp_path / "home"; (home / "p" / "k").mkdir(parents=True)
    orig = os.urandom(3000); (home / "p" / ".DS_Store").write_bytes(orig)
    lst = tmp_path / "l"; write_list(lst, [str(home / "p" / "k")])
    env = dict(os.environ, HOME=str(home))
    subprocess.run([sys.executable, "-c", f"import workers; workers.run_main({str(lst)!r})"],
                   cwd=os.path.dirname(__file__), env=env, check=True)
    bdir = home / "Library" / "Application Support" / "finder-view-fix" / "unreadable-backups"
    kept = [f.read_bytes() for f in bdir.iterdir()]
    assert kept == [orig] and stamped(str(home / "p" / "k"))


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
def run_make_targets(home, extra=""):
    out = str(home) + ".targets"
    env = dict(os.environ, HOME=str(home), FV_TARGETS=out, FV_EXTRA_ROOTS=extra)
    subprocess.run(["bash", os.path.join(REPO, "make_targets.sh")], env=env, check=True, capture_output=True)
    return open(out, encoding="utf-8").read().splitlines()


def test_make_targets_extra_roots(tmp_path):
    home = tmp_path / "h"; (home / "Library" / "CloudStorage" / "GD-x" / "My Drive" / "p q").mkdir(parents=True)
    cloud = home / "Library" / "CloudStorage" / "GD-x"
    (cloud / "My Drive" / ".hidden" / "y").mkdir(parents=True)
    (cloud / "My Drive" / "Thing.app" / "Contents").mkdir(parents=True)
    apps = tmp_path / "Apps"; (apps / "Utilities").mkdir(parents=True)
    got = set(run_make_targets(home, f"{cloud}\n{apps}\n{tmp_path / 'does-not-exist'}"))
    for p in [cloud, cloud / "My Drive", cloud / "My Drive" / "p q", apps, apps / "Utilities"]:
        assert str(p) in got, p
    assert not any(".hidden" in g or "Thing.app" in g for g in got)
    # ~/Library itself stays excluded unless named as a root
    assert not any(g.startswith(str(home / "Library")) and not g.startswith(str(cloud)) for g in got)


def test_default_extra_roots_follow_home(tmp_path):
    """Without FV_EXTRA_ROOTS the script must pick up every ~/Library/CloudStorage/* root and iCloud Drive."""
    home = tmp_path / "h"
    for r in ["Library/CloudStorage/GoogleDrive-a/My Drive/x", "Library/CloudStorage/OneDrive-b/y",
              "Library/Mobile Documents/com~apple~CloudDocs/z"]:
        (home / r).mkdir(parents=True)
    out = str(home) + ".targets"
    env = {k: v for k, v in os.environ.items() if k != "FV_EXTRA_ROOTS"}
    env.update(HOME=str(home), FV_TARGETS=out)
    subprocess.run(["bash", os.path.join(REPO, "make_targets.sh")], env=env, check=True, capture_output=True)
    got = set(open(out, encoding="utf-8").read().splitlines())
    for r in ["Library/CloudStorage/GoogleDrive-a/My Drive/x", "Library/CloudStorage/OneDrive-b/y",
              "Library/Mobile Documents/com~apple~CloudDocs/z"]:
        assert str(home / r) in got, r


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


def test_compliant_stores_not_rewritten_and_check_mode(tmp_path):
    """The hourly job relies on this: a second run writes nothing, and --check
    reports pending work without writing."""
    ds = tree(tmp_path / "t", random.Random(7), 60)
    lst = tmp_path / "l"; write_list(lst, ds)
    run = lambda *a: subprocess.run([sys.executable, os.environ.get("BGS_PATH", os.path.join(REPO, "bulk_group_stamp.py")), *a, str(lst)],
                                    capture_output=True, text=True)
    r = run("--check"); assert r.returncode == 1 and not any(stamped(d) for d in ds)
    assert run().returncode == 0 and all(stamped(d) for d in ds)
    stores = {p: (os.stat(p).st_ino, os.stat(p).st_mtime_ns) for p in
              (os.path.join(os.path.dirname(d), ".DS_Store") for d in ds)}
    time.sleep(0.05)
    assert run().returncode == 0
    assert stores == {p: (os.stat(p).st_ino, os.stat(p).st_mtime_ns) for p in stores}, "compliant store rewritten"
    assert run("--check").returncode == 0
    new = os.path.join(ds[0], "brand new"); os.mkdir(new); write_list(lst, ds + [new])
    assert run("--check").returncode == 1 and run().returncode == 0 and stamped(new)
