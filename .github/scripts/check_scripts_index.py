#!/usr/bin/env python3
"""CI guard: scripts/README.md must index every tracked file under scripts/.

Usage:
  check_scripts_index.py              check the tracked tree
  check_scripts_index.py --selftest   run built-in positive/negative cases

Every tracked path under scripts/ (except scripts/README.md) must appear, by basename or
by its path relative to scripts/, in scripts/README.md. Exit codes: 0 complete;
1 missing entries; 2 internal/IO error.
"""
import subprocess
import sys

README = "scripts/README.md"


def missing_entries(files, readme_text):
    """Return the files whose basename is not mentioned in the readme text."""
    out = []
    for f in files:
        if f == README:
            continue
        base = f.rsplit("/", 1)[-1]
        if base not in readme_text:
            out.append(f)
    return out


def stale_entries(files, readme_text):
    """Backticked `*.jl|sh|dss|txt` names in the readme that match no tracked file."""
    import re
    bases = {f.rsplit("/", 1)[-1] for f in files}
    rels = {f[len("scripts/"):] for f in files if f.startswith("scripts/")}
    stale = []
    for tok in re.findall(r"`([A-Za-z0-9_./-]+\.(?:jl|sh|dss|DSS|txt))`", readme_text):
        if tok in rels or tok.rsplit("/", 1)[-1] in bases:
            continue
        if tok.startswith(("test/", "src/", "scripts/", "results/", "data/")):
            continue
        stale.append(tok)
    return stale


def selftest():
    files = ["scripts/a.jl", "scripts/lib/b.jl", "scripts/archive/c.jl", README]
    full = "`a.jl` `lib/b.jl` `archive/c.jl`"
    assert missing_entries(files, full) == []
    assert missing_entries(files, "`a.jl` `lib/b.jl`") == ["scripts/archive/c.jl"]
    assert missing_entries(files + ["scripts/new.sh"], full) == ["scripts/new.sh"]
    assert stale_entries(files, full) == []
    assert stale_entries(files, full + " `gone.jl`") == ["gone.jl"]
    print("check_scripts_index selftest: OK")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    try:
        res = subprocess.run(["git", "ls-files", "scripts"], check=True,
                             capture_output=True, text=True)
        with open(README, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"check_scripts_index: cannot read inputs: {exc}", file=sys.stderr)
        return 2
    files = [f for f in res.stdout.splitlines() if f]
    miss = missing_entries(files, text)
    stale = stale_entries(files, text)
    for f in miss:
        print(f"NOT INDEXED: {f} (add it to {README})")
    for t in stale:
        print(f"STALE ENTRY: {t} is named in {README} but is not a tracked file")
    if miss or stale:
        return 1
    print(f"scripts index complete ({len(files)} tracked files checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
