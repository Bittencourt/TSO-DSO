#!/usr/bin/env python3
"""CI guard: scripts/README.md must index every tracked file under scripts/.

Usage:
  check_scripts_index.py              check the tracked tree
  check_scripts_index.py --selftest   run built-in positive/negative cases

Every tracked path under scripts/ (except scripts/README.md) must appear in scripts/README.md
as a whole path token (inside a backticked span): either its path relative to scripts/
(`lib/b.jl`), the same path with a `scripts/` prefix, or its bare basename when that basename
is unique among tracked scripts/ files. Matching is by whole token, never by substring, so
`pv_boom_report.jl` does not index `archive/pv_boom_report.jl` or `boom_report.jl`.
Stale check: a path token with a script-like extension that is bare, `scripts/`-prefixed, or
relative to scripts/ (`lib/`, `archive/`, `data/` vendored OpenDSS) and names no tracked file
is reported. Tokens rooted elsewhere (`src/`, `test/`, `results/`, `.github/`, ...) are
ignored. Exit codes: 0 complete; 1 missing or stale entries; 2 internal/IO error.
"""
import re
import subprocess
import sys

README = "scripts/README.md"

# Path-like token: no path characters on either side (so `SCRIPT=scripts/x.jl` yields
# `scripts/x.jl`, and `pv_boom_report.jl` is never found inside `archive/pv_boom_report.jl`).
# A token right after `:` is a filter spec value (`file:test_admm.jl`), not a path.
_TOKEN = re.compile(r"(?<![A-Za-z0-9_./:-])([A-Za-z0-9_.-][A-Za-z0-9_./-]*\.[A-Za-z0-9]+)(?![A-Za-z0-9_/-])")
# Extensions a tracked scripts/ file can have; only these are checked for staleness.
_STALE_EXT = re.compile(r"\.(?:jl|sh|py|toml|txt|dss|DSS)$")
# Roots outside scripts/: tokens starting with one of these are not scripts/ paths.
_EXTERNAL = ("src/", "test/", "results/", "docs/", "ext/", "bench/", ".github/", ".planning/")


def readme_tokens(readme_text):
    """Whole path-like tokens inside fenced code blocks and inline backticked spans, with a
    `./` prefix stripped."""
    fence = re.compile(r"^```[^\n]*\n(.*?)^```", re.S | re.M)
    spans = fence.findall(readme_text)
    spans += re.findall(r"`([^`\n]*)`", fence.sub("", readme_text))
    toks = []
    for span in spans:
        for t in _TOKEN.findall(span):
            t = t.rstrip(".")
            toks.append(t[2:] if t.startswith("./") else t)
    return toks


def _rel(f):
    return f[len("scripts/"):]


def missing_entries(files, readme_text):
    """Tracked files not named in the readme by a whole token (see module docstring)."""
    tracked = [f for f in files if f.startswith("scripts/") and f != README]
    toks = set(readme_tokens(readme_text))
    rel_toks = {t[len("scripts/"):] if t.startswith("scripts/") else t for t in toks}
    base_count = {}
    for f in tracked:
        b = f.rsplit("/", 1)[-1]
        base_count[b] = base_count.get(b, 0) + 1
    out = []
    for f in tracked:
        rel = _rel(f)
        base = rel.rsplit("/", 1)[-1]
        if rel in rel_toks:
            continue
        if base_count[base] == 1 and base in toks:
            continue
        out.append(f)
    return out


def stale_entries(files, readme_text):
    """Script-like path tokens in the readme that name no tracked scripts/ file."""
    rels = {_rel(f) for f in files if f.startswith("scripts/")}
    bases = {r.rsplit("/", 1)[-1] for r in rels}
    stale = []
    for tok in readme_tokens(readme_text):
        if not _STALE_EXT.search(tok) or tok.startswith(_EXTERNAL):
            continue
        rel = tok[len("scripts/"):] if tok.startswith("scripts/") else tok
        if "/" in rel:
            if rel in rels:
                continue
            # `data/...` is also the repo-root data/ directory; only vendored OpenDSS files
            # are known to live under scripts/data/.
            if rel.startswith("data/") and not re.search(r"\.(?:dss|DSS)$", rel):
                continue
        elif rel in bases:
            continue
        if tok not in stale:
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
    # Reviewer probes: overlapping names are not indexed by a substring mention.
    over = ["scripts/boom_report.jl", "scripts/archive/pv_boom_report.jl",
            "scripts/pv_boom_report.jl", README]
    assert missing_entries(over, "`pv_boom_report.jl`") == [
        "scripts/boom_report.jl", "scripts/archive/pv_boom_report.jl"], \
        missing_entries(over, "`pv_boom_report.jl`")
    assert missing_entries(over, "`pv_boom_report.jl` `archive/pv_boom_report.jl` "
                                 "`boom_report.jl`") == []
    # Same basename in two directories: the bare basename indexes neither.
    dup = ["scripts/lib/x.jl", "scripts/archive/x.jl", README]
    assert missing_entries(dup, "`x.jl`") == ["scripts/lib/x.jl", "scripts/archive/x.jl"]
    assert missing_entries(dup, "`lib/x.jl` `scripts/archive/x.jl`") == []
    # Tokens inside a longer backticked command are found as whole tokens.
    assert missing_entries(["scripts/run.sh", "scripts/prof.jl"],
                           "`SCRIPT=scripts/prof.jl scripts/run.sh <label>`") == []
    # Stale: scripts/-prefixed and other script extensions are checked too.
    assert stale_entries(files, "`scripts/gone.jl` `b.toml` `foo.py`") == [
        "scripts/gone.jl", "b.toml", "foo.py"], stale_entries(files, "`scripts/gone.jl` `b.toml` `foo.py`")
    assert stale_entries(files, "`scripts/lib/b.jl` `lib/gone.jl`") == ["lib/gone.jl"]
    assert stale_entries(files, "`data/ieee/Gone.dss` `data/pv/results.jld2` `src/x.jl` "
                                "`.github/scripts/y.py` `test/t.jl`") == ["data/ieee/Gone.dss"]
    # Fenced blocks count; a `file:` filter value is not a path token.
    assert missing_entries(files, "`lib/b.jl` `archive/c.jl`\n```\njulia scripts/a.jl\n```\n") == []
    assert stale_entries(files, "```\nrun.jl file:test_x.jl\n```\n") == ["run.jl"]
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
