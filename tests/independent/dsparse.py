"""Independent .DS_Store reader written from the published format notes
(Mentovai / Lewis "Bud1" buddy-allocator description), sharing no code with
the ds-store library or the tool. Besides decoding records it validates the
B-tree structure Finder relies on and raises AssertionError on any defect."""
import struct


def _block(buf, addrs, n):
    a = addrs[n]
    off, size = (a & ~0x1F) + 4, 1 << (a & 0x1F)
    assert off + size <= len(buf) + 4096, f"block {n} past EOF"
    return buf[off:off + size]


def _record(b, p):
    (nlen,) = struct.unpack_from(">I", b, p); p += 4
    name = b[p:p + 2 * nlen].decode("utf-16be"); p += 2 * nlen
    code, typ = b[p:p + 4].decode("latin1"), b[p + 4:p + 8]; p += 8
    if typ == b"bool": val, p = b[p] != 0, p + 1
    elif typ in (b"long", b"shor"): val, p = struct.unpack_from(">I", b, p)[0], p + 4
    elif typ == b"type": val, p = b[p:p + 4], p + 4
    elif typ in (b"comp", b"dutc"): val, p = struct.unpack_from(">Q", b, p)[0], p + 8
    elif typ == b"blob":
        (ln,) = struct.unpack_from(">I", b, p); val, p = b[p + 4:p + 4 + ln], p + 4 + ln
    elif typ == b"ustr":
        (ln,) = struct.unpack_from(">I", b, p); val, p = b[p + 4:p + 4 + 2 * ln].decode("utf-16be"), p + 4 + 2 * ln
    else:
        raise AssertionError(f"unknown type {typ!r}")
    return (name, code, typ.decode("latin1"), val), p


def parse(path):
    """Return list of (filename, code, type, value) in on-disk B-tree order."""
    buf = open(path, "rb").read()
    assert buf[:8] == b"\x00\x00\x00\x01Bud1", "bad magic"
    root_off, root_size, root_off2 = struct.unpack_from(">III", buf, 8)
    assert root_off == root_off2, "header offset copies differ"
    r = buf[root_off + 4:root_off + 4 + root_size]
    (count,) = struct.unpack_from(">I", r, 0)
    addrs = list(struct.unpack_from(f">{count}I", r, 8))
    p = 8 + 4 * ((count + 255) // 256 * 256)
    (ntoc,) = struct.unpack_from(">I", r, p); p += 4
    toc = {}
    for _ in range(ntoc):
        ln = r[p]; key = r[p + 1:p + 1 + ln]; (val,) = struct.unpack_from(">I", r, p + 1 + ln)
        toc[key] = val; p += 1 + ln + 4
    assert b"DSDB" in toc, "no DSDB"
    root, levels, nrec, nnodes, page = struct.unpack_from(">IIIII", _block(buf, addrs, toc[b"DSDB"]), 0)
    out, depths, seen = [], set(), [0]

    def walk(node, depth):
        seen[0] += 1
        b = _block(buf, addrs, node)
        nxt, cnt = struct.unpack_from(">II", b, 0); p = 8
        for _ in range(cnt):
            if nxt:
                (child,) = struct.unpack_from(">I", b, p); p += 4
                walk(child, depth + 1)
            rec, p = _record(b, p)
            out.append(rec)
        assert p <= page, f"node {node} overflows page ({p} > {page})"
        if nxt: walk(nxt, depth + 1)
        else: depths.add(depth)

    walk(root, 0)
    assert len(depths) <= 1, f"leaves at different depths {depths}"
    assert not depths or depths == {levels}, f"levels {levels} != leaf depth {depths}"
    assert len(out) == nrec, f"superblock records {nrec} != {len(out)}"
    assert seen[0] == nnodes, f"superblock nodes {nnodes} != {seen[0]}"
    return out


def finder_key(rec):
    """Finder orders records case-insensitively by name, then by code; names
    differing only in case (impossible on case-insensitive APFS, possible on
    case-sensitive volumes) are tie-broken by exact name."""
    return (rec[0].lower(), rec[0], rec[1])


def as_dict(recs):
    return {(n, c): v for n, c, _, v in recs}
