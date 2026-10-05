#!/usr/bin/env python3
"""Scan / apply `using TSODSO: names` for names that stop being exported.

Usage: unexport_migrate.py scan|apply --names FILE paths...
  FILE : one name per line.
  scan : print `file:line name` for each bare use plus a files/sites count.
  apply: insert a `using TSODSO: ...` line (never restructures code). Idempotent.
Bare use = `(?<![\\w!.])NAME(?![\\w!])`; `converged` is anchored on `converged(`.
Comments, docstring prose, string literals and locally defined names are skipped.
"""
import re
import sys

STR_RE = re.compile(r'"(?:[^"\\$]|\\.)*"')
IMPORT_RE = re.compile(r'^\s*using\s+TSODSO\s*:\s*(.*)$')


def name_rx(n):
    if n == "converged":
        return re.compile(r'(?<![\w!.:])converged\(')
    return re.compile(r'(?<![\w!.:])' + re.escape(n) + r'(?![\w!])')


def code_lines(lines, md):
    """Yield (idx, text) of code lines, skipping comments / docstrings / prose."""
    in_doc = False
    in_fence = False
    for i, line in enumerate(lines):
        s = line.strip()
        if md:
            if s.startswith("```"):
                in_fence = not in_fence
                continue
            if not in_fence:
                continue
        else:
            fences = line.count('"""')
            if in_doc or fences:
                if fences % 2 == 1:
                    in_doc = not in_doc
                continue
        if s.startswith("#"):
            continue
        t = STR_RE.sub('""', line)
        t = t.split(" #")[0]
        yield i, t


def local_defs(lines, names):
    out = set()
    for n in names:
        rx = re.compile(r'^\s*(?:function|struct|mutable struct|abstract type|const|macro)\s+' + re.escape(n) + r'\b'
                        r'|^\s*' + re.escape(n) + r'\s*(?:\([^)]*\))?\s*=(?!=)')
        if any(rx.search(l) for l in lines):
            out.add(n)
    return out


def blocks(lines):
    """(start,end) line index ranges of @testitem/@testmodule bodies; else whole file."""
    res = []
    i = 0
    while i < len(lines):
        if re.match(r'^@test(item|module)\b', lines[i]):
            j = i
            while j < len(lines) and not lines[j].rstrip().endswith("begin"):
                j += 1
            k = j + 1
            while k < len(lines) and not re.match(r'^end\b', lines[k]):
                k += 1
            res.append((j + 1, k))  # body = [j+1, k)
            i = k
        i += 1
    return res or [(0, len(lines))]


def uses(lines, rng, names, md):
    found = {}
    sub = lines[rng[0]:rng[1]]
    for i, t in code_lines(sub, md):
        for n in names:
            if name_rx(n).search(t):
                found.setdefault(n, []).append(rng[0] + i)
    return found


def imported(lines, rng):
    got = set()
    for l in lines[rng[0]:rng[1]]:
        m = IMPORT_RE.match(l)
        if m:
            got |= {x.strip() for x in m.group(1).split("#")[0].split(",") if x.strip()}
    return got


def selfcheck():
    """Scratch file with `:SOCP`, a string mention and one real use must give 1 site."""
    import os, subprocess, tempfile
    src = 'x = :SOCP\ny = "SOCP in text"\nz = Symbol("SOCP")\nw = SOCP()\n'
    with tempfile.TemporaryDirectory() as d:
        f = os.path.join(d, "a.jl"); n = os.path.join(d, "n.txt")
        open(f, "w").write(src); open(n, "w").write("SOCP\n")
        out = subprocess.run([sys.executable, __file__, "scan", "--names", n, f],
                             capture_output=True, text=True).stdout
    ok = "1 sites in 1 files" in out
    print("selfcheck:", "OK" if ok else "FAIL " + out)
    return 0 if ok else 1


def main(argv):
    if argv[:1] == ["selfcheck"]:
        return selfcheck()
    if len(argv) < 3 or argv[0] not in ("scan", "apply") or "--names" not in argv:
        print(__doc__)
        return 2
    mode = argv[0]
    k = argv.index("--names")
    names = [l.strip() for l in open(argv[k + 1]) if l.strip()]
    paths = [a for i, a in enumerate(argv[1:], 1) if i not in (k, k + 1)]
    nfiles = nsites = 0
    for p in paths:
        if not (p.endswith(".jl") or p.endswith(".md")):
            continue
        md = p.endswith(".md")
        text = open(p, encoding="utf-8").read()
        lines = text.split("\n")
        mine = [n for n in names if n not in local_defs(lines, names)]
        sites = 0
        edits = []  # (insert_after_index or None, body_start, indent, names)
        for rng in blocks(lines):
            f = uses(lines, rng, mine, md)
            if not f:
                continue
            for n, idxs in f.items():
                for i in idxs:
                    if mode == "scan":
                        print(f"{p}:{i+1} {n}")
                    sites += 1
            need = sorted(set(f) - imported(lines, rng))
            if need and mode == "apply" and not md:
                at = None
                for i in range(rng[0], rng[1]):
                    if re.match(r'^\s*using\s+TSODSO\s*$', lines[i]):
                        at = i
                        break
                if at is not None:
                    indent = re.match(r'\s*', lines[at]).group(0)
                    edits.append((at + 1, indent, need))
                else:
                    indent = "    " if rng != (0, len(lines)) else ""
                    edits.append((rng[0], indent, need))
        if sites:
            nfiles += 1
            nsites += sites
        if mode == "apply" and edits:
            for pos, indent, need in sorted(edits, reverse=True):
                lines.insert(pos, f"{indent}using TSODSO: {', '.join(need)}")
            open(p, "w", encoding="utf-8").write("\n".join(lines))
    print(f"{mode}: {nsites} sites in {nfiles} files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
