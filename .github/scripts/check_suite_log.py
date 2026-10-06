#!/usr/bin/env python3
"""Validate a detached run started by suite_detached.sh.

Usage: check_suite_log.py LABEL [--mode suite|docs] [--wait SECONDS] [--same-pass-as OTHER]
                          [--broken N] [--skip-canary]
  --broken N      expected Broken count in the totals row (default 5). The expected count is
                  per Julia patch: use the BROKEN_* value recorded for that patch in
                  .planning/phases/37-test-infrastructure-repo-hygiene/37-TIMINGS.md
                  (1.12.5: BROKEN_1.12.5=5; post-gate 1.12.7: BROKEN_1.12.7_EXPECTED_POSTGATE=5).
  --skip-canary   do not require the canary iters/welfare lines (short logs)
Exit 0 ok, 3 still running, 1 failed requirement.
"""
import os
import re
import subprocess
import sys
import time

T = ".planning/tmp/36"


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    label = argv[0]
    mode = argv[argv.index("--mode") + 1] if "--mode" in argv else "suite"
    wait = min(int(argv[argv.index("--wait") + 1]), 540) if "--wait" in argv else 0
    other = argv[argv.index("--same-pass-as") + 1] if "--same-pass-as" in argv else None
    nbroken = int(argv[argv.index("--broken") + 1]) if "--broken" in argv else 5
    skip_canary = "--skip-canary" in argv
    root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    os.chdir(root)
    done, log, start = f"{T}/{label}.done", f"{T}/{label}.log", f"{T}/{label}.start"
    t0 = time.time()
    while not os.path.exists(done):
        print("RUNNING")
        if time.time() - t0 >= wait:
            return 3
        time.sleep(15)
    code = open(done).read().strip()
    if code != "0":
        fail(f"DONE marker is {code!r}, expected '0'")
    commit_t = int(subprocess.check_output(["git", "log", "-1", "--format=%ct"], text=True).strip())
    if not os.path.exists(log) or not os.path.exists(start):
        fail("log or start file missing")
    if os.path.getmtime(log) <= commit_t:
        fail("log mtime is not later than the HEAD commit (stale run)")
    if int(open(start).read().strip()) <= commit_t:
        fail("run started before the HEAD commit (stale run)")
    text = open(log, errors="replace").read()
    if mode == "docs":
        if re.search(r"(?i)missing docstring", text):
            fail("docs log has a missing docstring warning")
        if re.search(r"(?i)error.{0,80}@example|@example.{0,80}error", text):
            fail("docs log has an @example error")
        print("docs OK")
        return 0
    idx = text.rfind("Test Summary:")
    if idx < 0:
        fail("no 'Test Summary' block in log")
    lines = text[idx:].split("\n")
    head = [c for c in lines[0].split("|", 1)[1].split()]
    row = None
    for l in lines[1:]:
        if "|" in l:
            row = l
            break
    if row is None:
        fail("Test Summary block has no totals row")
    vals = row.split("|", 1)[1].split()
    cols = [c for c in head if c != "Time"]
    tot = {c: int(v) for c, v in zip(cols, vals) if v.isdigit()}
    g = lambda k: tot.get(k, 0)
    print("totals:", {k: g(k) for k in ("Pass", "Fail", "Error", "Broken", "Total")})
    if g("Fail") != 0 or g("Error") != 0:
        fail("fail/error is nonzero")
    if g("Broken") != nbroken:
        fail(f"broken is {g('Broken')}, expected {nbroken}")
    if not skip_canary:
        if not re.search(r"iters\s*=\s*56\b", text):
            fail("canary iters = 56 not found")
        if not re.search(r"welfare\s*=\s*-4823\.66604824162\b", text):
            fail("canary welfare = -4823.66604824162 not found")
    with open(f"{T}/{label}.totals", "w") as fh:
        fh.write(" ".join(f"{k}={g(k)}" for k in ("Pass", "Fail", "Error", "Broken", "Total")) + "\n")
    if other:
        m = re.search(r"Pass=(\d+)", open(f"{T}/{other}.totals").read())
        if not m or int(m.group(1)) != g("Pass"):
            fail(f"pass count {g('Pass')} differs from {other}")
    print("suite OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
