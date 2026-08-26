#!/usr/bin/env python3
"""Heuristic scan for the Julia soft-scope trap inside @testitem/@testmodule bodies.

Pattern: a bare `name = ...` at the block's TOP level (a module global under @testitem),
where `name` is ALSO assigned inside a nested for/while/try in the same block. Those inner
assignments create dead locals and never reach the outer binding.

LIMITATIONS (measured on this repo, quick task 260826-0y4): a full-suite scan reported
15 candidates, most of them false positives (e.g. an outer `name = ...` and an unrelated
inner reassignment that were never actually the same soft-scope hazard). Worse, it MISSED
the one real instance that existed at the time this was measured
(`test_planning_certification_integer.jl:335`, `caught = e` inside a `catch`), because its
`OPENER` regex only treats `for`/`while`/`try` as depth-increasing while every bare `end`
decrements depth regardless of which block opened it -- it desynchronises on `if`/`let`/
`function`/`begin` blocks interleaved with the tracked openers, and can both over- and
under-report as a result. This script is a cheap, OPTIONAL pre-commit hint only -- it is
NEVER authoritative and must never be read as a defect list. The authoritative detector is
Julia's own lowering-time "Assignment to X in soft scope is ambiguous" warning; see
`test/runtests.jl`'s header for the full writeup and the established fix idiom.
"""
import re, os, sys

R = sys.argv[1] if len(sys.argv) > 1 else "test"
ASSIGN = re.compile(r'^(\s*)([A-Za-z_][A-Za-z0-9_!]*)\s*=(?!=)')
OPENER = re.compile(r'^\s*(for|while|try)\b')
hits = []
for root, _, files in os.walk(R):
    for f in sorted(files):
        if not f.endswith(".jl"):
            continue
        path = os.path.join(root, f)
        lines = open(path, errors="replace").read().split("\n")
        top, inner, depth, in_item = {}, {}, 0, False
        for i, l in enumerate(lines, 1):
            st = l.strip()
            if st.startswith("@testitem") or st.startswith("@testmodule"):
                top, inner, depth, in_item = {}, {}, 0, True
                continue
            if not in_item or st.startswith("#"):
                continue
            if OPENER.match(l):
                depth += 1
            elif re.match(r'^\s*end\b', l) and depth > 0:
                depth -= 1
            m = ASSIGN.match(l)
            if m:
                name = m.group(2)
                if name in ("function", "end", "if", "for", "while", "return"):
                    continue
                if depth == 0:
                    top.setdefault(name, i)
                else:
                    inner.setdefault(name, i)
            if re.match(r'^end\b', l) and in_item:
                for n in set(top) & set(inner):
                    hits.append((path, n, top[n], inner[n]))
                top, inner, in_item = {}, {}, False
print(f"candidate soft-scope sites: {len(hits)}")
for p, n, t, j in hits:
    print(f"  {p}:{t} top-level `{n} = ...`  ->  reassigned inside nested block at :{j}")
