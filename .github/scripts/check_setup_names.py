#!/usr/bin/env python3
"""Check every `setup=[A, B]` name in test/*.jl resolves to a `@testmodule`.

Usage: check_setup_names.py [--tags]   (exit 1 on unresolved names)
--tags additionally lists the distinct tag symbols used.
"""
import glob
import re
import sys

mods = set()
uses = []
tags = set()
for f in sorted(glob.glob("test/**/*.jl", recursive=True)):
    txt = open(f, encoding="utf-8").read().split("\n")
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
                    uses.append((f, n, nm))
        for m in re.finditer(r'tags\s*=\s*\[([^\]]*)\]', line):
            tags |= {t.strip() for t in m.group(1).split(",") if t.strip()}
bad = [(f, n, nm) for f, n, nm in uses if nm not in mods]
for f, n, nm in bad:
    print(f"UNRESOLVED setup {nm} at {f}:{n}")
if "--tags" in sys.argv:
    print("tags:", " ".join(sorted(tags)))
print(f"{len(mods)} testmodules, {len(uses)} setup uses, {len(bad)} unresolved")
sys.exit(1 if bad else 0)
