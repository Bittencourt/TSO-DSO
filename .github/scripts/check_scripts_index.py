#!/usr/bin/env python3
"""CI guard: scripts/README.md must index every tracked file under scripts/.

Usage:
  check_scripts_index.py              check the tracked tree
  check_scripts_index.py --selftest   run built-in positive/negative cases

Every tracked path under scripts/ (except scripts/README.md) must appear in scripts/README.md
as a whole path token (inside a backticked span) giving its full location: its path relative
to scripts/ (`lib/b.jl`, `archive/c.jl`) or the same path with a `scripts/` prefix. A bare
basename (`a.jl`) names only a file directly under scripts/ (`scripts/a.jl`), never one in a
subdirectory, so a script moved to `archive/` whose index row still says `old.jl` is reported
both as NOT INDEXED (`scripts/archive/old.jl`) and as STALE (`old.jl`). Matching is by whole
token, never by substring, so `pv_boom_report.jl` does not index `archive/pv_boom_report.jl`
or `boom_report.jl`.
Stale check: a path token with a script-like extension that is bare, `scripts/`-prefixed, or
relative to scripts/ (`lib/`, `archive/`, `data/` vendored OpenDSS) and names no tracked file
at exactly that location is reported. Tokens rooted elsewhere (`src/`, `test/`, `results/`,
`.github/`, ...) are ignored.
Mislocation check: in the first column of the `## Scripts` table no entry may be under
`archive/`, and in the first column of the `## Archive` table every entry must be under
`archive/`. Both headings must exist (exactly `## Scripts` and `## Archive`): a renamed or
deleted heading would make the mislocation check a silent no-op, so it is reported as MISSING
SECTION. Exit codes: 0 complete; 1 missing, stale or mislocated entries or a missing section;
2 internal/IO error.
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


def _tok_rel(tok):
    return tok[len("scripts/"):] if tok.startswith("scripts/") else tok


def missing_entries(files, readme_text):
    """Tracked files not named in the readme by their full scripts/-relative path (a bare
    basename counts only for a file directly under scripts/; see module docstring)."""
    tracked = [f for f in files if f.startswith("scripts/") and f != README]
    rel_toks = {_tok_rel(t) for t in readme_tokens(readme_text)}
    return [f for f in tracked if _rel(f) not in rel_toks]


def stale_entries(files, readme_text):
    """Script-like path tokens in the readme that name no tracked scripts/ file."""
    rels = {_rel(f) for f in files if f.startswith("scripts/")}
    stale = []
    for tok in readme_tokens(readme_text):
        if not _STALE_EXT.search(tok) or tok.startswith(_EXTERNAL):
            continue
        rel = _tok_rel(tok)
        # A bare token names scripts/<tok> only; a relative token names exactly that path.
        if rel in rels:
            continue
        # `data/...` is also the repo-root data/ directory; only vendored OpenDSS files
        # are known to live under scripts/data/.
        if rel.startswith("data/") and not re.search(r"\.(?:dss|DSS)$", rel):
            continue
        if tok not in stale:
            stale.append(tok)
    return stale


# Section headings the mislocation check keys on; each must be present verbatim.
REQUIRED_SECTIONS = ("Scripts", "Archive")


def missing_sections(readme_text):
    """Required `## <name>` headings (see REQUIRED_SECTIONS) absent from the readme."""
    present = {line[3:].strip() for line in readme_text.splitlines() if line.startswith("## ")}
    return [s for s in REQUIRED_SECTIONS if s not in present]


def mislocated_entries(readme_text):
    """First-column entries of the `## Scripts` table that point into archive/, and of the
    `## Archive` table that do not. Returns `(token, section)` pairs."""
    out = []
    section = None
    for line in readme_text.splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
            continue
        if section not in ("Scripts", "Archive") or not line.startswith("|"):
            continue
        cells = line.split("|")
        if len(cells) < 3 or re.fullmatch(r"\s*:?-+:?\s*", cells[1]):
            continue
        for span in re.findall(r"`([^`\n]*)`", cells[1]):
            for tok in _TOKEN.findall(span):
                rel = _tok_rel(tok.rstrip("."))
                in_archive = rel.startswith("archive/")
                if (section == "Scripts") == in_archive:
                    out.append((tok, section))
    return out


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
    # Reviewer probe (iteration 2): a script moved to archive/ whose active-table row still
    # names it by its bare basename is both NOT INDEXED and STALE.
    moved = ["scripts/archive/old.jl", README]
    assert missing_entries(moved, "Active: `old.jl` runs X") == ["scripts/archive/old.jl"]
    assert stale_entries(moved, "Active: `old.jl` runs X") == ["old.jl"]
    assert missing_entries(moved, "`archive/old.jl`") == []
    assert stale_entries(moved, "`scripts/archive/old.jl`") == []
    # A bare basename never indexes a subdirectory file, even when it is unique.
    assert missing_entries(["scripts/lib/b.jl", README], "`b.jl`") == ["scripts/lib/b.jl"]
    assert stale_entries(["scripts/lib/b.jl", README], "`b.jl`") == ["b.jl"]
    # Mislocated: archive/ path left in the active table, or an active path in the archive table.
    tables = ("## Scripts\n\n| Script | Purpose |\n|---|---|\n| `a.jl` | x |\n"
              "| `archive/old.jl` | still listed as active |\n\n"
              "## Archive\n\n| Script | Reason |\n|---|---|\n| `archive/c.jl` | gone |\n"
              "| `lib/b.jl` | wrong table |\n")
    assert mislocated_entries(tables) == [("archive/old.jl", "Scripts"),
                                          ("lib/b.jl", "Archive")], mislocated_entries(tables)
    assert mislocated_entries("## Scripts\n| `a.jl` | `archive/x.jl` in purpose |\n") == []
    # Reviewer probe (iteration 3): a renamed heading must not turn the check into a no-op.
    assert missing_sections(tables) == []
    renamed = tables.replace("## Scripts", "## Active scripts")
    assert mislocated_entries(renamed) == [("lib/b.jl", "Archive")]
    assert missing_sections(renamed) == ["Scripts"], missing_sections(renamed)
    assert missing_sections("no headings at all") == ["Scripts", "Archive"]
    assert missing_sections("### Scripts\n## Archive\n") == ["Scripts"]
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
    misloc = mislocated_entries(text)
    nosec = missing_sections(text)
    for f in miss:
        print(f"NOT INDEXED: {f} (add it to {README} by its path relative to scripts/)")
    for t in stale:
        print(f"STALE ENTRY: {t} is named in {README} but no tracked file is at that path")
    for t, sec in misloc:
        print(f"MISLOCATED: {t} is in the '## {sec}' table of {README}, which does not "
              f"match its archive/ status")
    for sec in nosec:
        print(f"MISSING SECTION: {README} has no '## {sec}' heading; the archive-status "
              f"(mislocation) check cannot run without it")
    if miss or stale or misloc or nosec:
        return 1
    print(f"scripts index complete ({len(files)} tracked files checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
