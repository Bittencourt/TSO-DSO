#!/usr/bin/env python3
"""Compare thesis/literature token multisets between REF and the working tree.

Usage: thesis_tokens.py REF paths...   (exit 1 on any difference)
"""
import re
import subprocess
import sys
from collections import Counter

PATTERNS = [
    r'\b3\.\d{2}\b',
    r'Table \d+',
    r'Fig(?:ure)?\.? ?\d+',
    r'App\. [A-Z]',
    r'pp?\. ?\d+',
    r'(?i)\bthesis\b',
    r'[A-Z][a-z]+(?: and [A-Z][a-z]+| et al\.?)?,? \(?\d{4}\)?',
]
RX = [re.compile(p) for p in PATTERNS]


def tokens(text):
    c = Counter()
    for rx in RX:
        for m in rx.finditer(text):
            c[m.group(0)] += 1
    return c


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    ref, paths = argv[0], argv[1:]
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    bad = False
    for p in paths:
        r = subprocess.run(["git", "show", f"{ref}:{p}"], cwd=root, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"SKIP {p}: absent at {ref}")
            continue
        try:
            with open(f"{root}/{p}", encoding="utf-8") as fh:
                new = fh.read()
        except FileNotFoundError:
            print(f"SKIP {p}: absent in working tree")
            continue
        a, b = tokens(r.stdout), tokens(new)
        for t in sorted(set(a) | set(b)):
            if a[t] != b[t]:
                bad = True
                print(f"DIFF {p}: {t!r} before={a[t]} after={b[t]}")
    if bad:
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
