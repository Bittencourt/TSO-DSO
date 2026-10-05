#!/usr/bin/env python3
"""Check every `setup=[A, B]` name in test/*.jl resolves to a `@testmodule`.

Usage: check_setup_names.py [--tags] [--root DIR]   (exit 1 on unresolved names)
       check_setup_names.py --selftest
--tags additionally lists the distinct tag symbols used.
--root scans DIR/test instead of the repository's test/ (default: the git toplevel of this
script, independent of the current working directory).

Fails closed (exit 2) when no `@testmodule` is found, e.g. wrong root or empty checkout.
"""
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def repo_root():
    return subprocess.check_output(["git", "-C", HERE, "rev-parse", "--show-toplevel"],
                                   text=True).strip()


def scan(root):
    mods = set()
    uses = []
    tags = set()
    for f in sorted(glob.glob(os.path.join(root, "test", "**", "*.jl"), recursive=True)):
        rel = os.path.relpath(f, root)
        with open(f, encoding="utf-8") as fh:
            txt = fh.read().split("\n")
        for n, line in enumerate(txt, 1):
            if line.lstrip().startswith("#"):
                continue
            line = line.split(" #")[0]
            for m in re.finditer(r'@testmodule\s+([A-Za-z_]\w*)', line):
                mods.add(m.group(1))
            for m in re.finditer(r'setup\s*=\s*\[([^\]]*)\]', line):
                for nm in m.group(1).split(","):
                    nm = nm.strip()
                    if nm:
                        uses.append((rel, n, nm))
            for m in re.finditer(r'tags\s*=\s*\[([^\]]*)\]', line):
                tags |= {t.strip() for t in m.group(1).split(",") if t.strip()}
    return mods, uses, tags


def main(argv):
    root = None
    if "--root" in argv:
        i = argv.index("--root")
        if i + 1 >= len(argv):
            print("ERROR: --root needs a directory", file=sys.stderr)
            return 2
        root = argv[i + 1]
    root = root or repo_root()
    mods, uses, tags = scan(root)
    if not mods:
        print(f"ERROR: no @testmodule found under {os.path.join(root, 'test')} (fail-closed)",
              file=sys.stderr)
        return 2
    bad = [(f, n, nm) for f, n, nm in uses if nm not in mods]
    for f, n, nm in bad:
        print(f"UNRESOLVED setup {nm} at {f}:{n}")
    if "--tags" in argv:
        print("tags:", " ".join(sorted(tags)))
    print(f"{len(mods)} testmodules, {len(uses)} setup uses, {len(bad)} unresolved")
    return 1 if bad else 0


def selftest():
    import contextlib
    import io

    def run(files):
        with tempfile.TemporaryDirectory() as d:
            for name, content in files.items():
                p = os.path.join(d, name)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w") as fh:
                    fh.write(content)
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return main(["--root", d])

    mod = "@testmodule Fx begin\nend\n"
    cases = [
        ("empty tree exits 2", run({}), 2),
        ("no testmodule exits 2", run({"test/a.jl": '@testitem "x" setup=[Fx] begin end\n'}), 2),
        ("resolved setup exits 0", run({"test/f.jl": mod, "test/a.jl": '@testitem "x" setup=[Fx] begin end\n'}), 0),
        ("unresolved setup exits 1", run({"test/f.jl": mod, "test/a.jl": '@testitem "x" setup=[Gone] begin end\n'}), 1),
    ]
    ok = True
    for name, got, want in cases:
        if got != want:
            print(f"SELFTEST FAIL: {name}: got {got}, want {want}")
            ok = False
    if ok:
        print(f"selftest OK: {len(cases)} case(s)")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
