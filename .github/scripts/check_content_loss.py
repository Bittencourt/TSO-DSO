#!/usr/bin/env python3
"""Compare working-tree .jl files under src/ext/test/docs against a git ref,
ignoring whitespace and commas. Reports any file whose actual CONTENT changed.

Usage: python3 check_content_loss.py <git-ref>
Exit 0 = no content loss. Exit 1 = content loss found.
"""
import re, os, subprocess, sys

ref = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
R = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()

def norm(t):
    return re.sub(r'[\s,]+', '', t)

bad, checked = [], 0
for d in ("src", "ext", "test", "docs"):
    for root, _, files in os.walk(os.path.join(R, d)):
        for f in files:
            if not f.endswith(".jl"):
                continue
            rel = os.path.relpath(os.path.join(root, f), R)
            try:
                before = subprocess.check_output(
                    ["git", "show", f"{ref}:{rel}"], text=True, stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                continue  # new file, nothing to compare
            after = open(os.path.join(R, rel)).read()
            checked += 1
            if norm(before) != norm(after):
                bad.append((rel, len(norm(before)), len(norm(after))))

print(f"checked {checked} tracked .jl files against {ref}")
if bad:
    print(f"CONTENT LOSS in {len(bad)} file(s):")
    for rel, a, b in bad:
        print(f"   chars {b-a:+6d}  {rel}")
    sys.exit(1)
print("OK: no content change (whitespace/commas only)")
