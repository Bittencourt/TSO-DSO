#!/usr/bin/env python3
"""CI guard: no planning identifiers in the tracked source tree (fail-closed).

Usage:
  check_planning_ids.py [paths...]       scan tracked in-scope files (or subtrees)
  check_planning_ids.py --root DIR       scan a plain directory tree instead of git
  check_planning_ids.py --allowlist FILE use another allowlist file
  check_planning_ids.py --selftest       run built-in positive/negative/fail-closed cases

Exit codes: 0 clean; 1 hit or stale allowlist entry; 2 internal/IO/allowlist error.

Allowlist format (planning_id_allowlist.txt): `path<TAB>regex-fragment<TAB>reason`,
blank lines and `#` comments ignored. Matched by path plus text fragment, never by
line number. An entry matching nothing is stale and fails the run.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import planning_id_rules as R  # noqa: E402

DEFAULT_ALLOWLIST = os.path.join(HERE, "planning_id_allowlist.txt")
SELF_EXCLUDED = {"check_planning_ids.py", "planning_id_rules.py",
                 "classify_planning_ids.py", "planning_id_allowlist.txt"}


class GuardError(Exception):
    """Fail-closed condition (exit 2)."""


def load_allowlist(path):
    entries = []
    if not os.path.exists(path):
        return entries
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise GuardError(f"cannot read allowlist {path}: {exc}")
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3 or not all(p.strip() for p in parts):
            raise GuardError(f"{path}:{n}: malformed allowlist line (need path<TAB>fragment<TAB>reason)")
        try:
            rx = re.compile(parts[1])
        except re.error as exc:
            raise GuardError(f"{path}:{n}: bad regex fragment: {exc}")
        entries.append({"path": parts[0].strip(), "rx": rx, "used": False, "line": n})
    return entries


def walk_root(root):
    res = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in (".git", ".planning")]
        for fn in fns:
            if os.path.splitext(fn)[1] in R.SCOPE_EXTS and fn not in SELF_EXCLUDED:
                res.append(os.path.relpath(os.path.join(dp, fn), root))
    return sorted(res)


def scan(root, files, entries):
    hits = []
    for rel in files:
        full = os.path.join(root, rel)
        try:
            with open(full, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError) as exc:
            raise GuardError(f"cannot read {rel}: {exc}")
        for n, line in enumerate(text.splitlines(), 1):
            rules = [k for k, rx in R.RULES.items() if rx.search(line)]
            if not rules:
                continue
            allowed = False
            for e in entries:
                if e["path"] == rel and e["rx"].search(line):
                    e["used"] = True
                    allowed = True
            if not allowed:
                hits.append((rel, n, rules, line.strip()))
    return hits


def main(argv):
    root = None
    allow = DEFAULT_ALLOWLIST
    paths = []
    it = iter(argv)
    for a in it:
        if a == "--root":
            root = next(it, None)
        elif a == "--allowlist":
            allow = next(it, None)
        elif a.startswith("--"):
            print(f"unknown option {a}", file=sys.stderr)
            return 2
        else:
            paths.append(a)
    try:
        if root is None:
            root_dir = R.repo_root()
            files = [f for f in R.iter_scope_files(paths or None) if os.path.basename(f) not in SELF_EXCLUDED]
        else:
            root_dir = root
            files = walk_root(root)
            if paths:
                files = [f for f in files if any(f == p or f.startswith(p.rstrip("/") + "/") for p in paths)]
        entries = load_allowlist(allow)
        hits = scan(root_dir, files, entries)
    except (GuardError, subprocess.CalledProcessError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    for rel, n, rules, text in hits:
        print(f"{rel}:{n}: [{','.join(rules)}] {text}")
    stale = [e for e in entries if not e["used"] and (not paths or e["path"] in files)]
    for e in stale:
        print(f"STALE allowlist entry (line {e['line']}): {e['path']}\t{e['rx'].pattern}")
    if hits or stale:
        print(f"FAIL: {len(hits)} hit(s), {len(stale)} stale allowlist entr(y/ies)")
        return 1
    print(f"OK: {len(files)} files scanned, no planning identifiers")
    return 0


def selftest():
    j = "".join
    positives = {
        "phase": j(["Phase ", "36", " cleanup"]),
        "plan": j(["see plan ", "12", "-", "03"]),
        "bare_nn": j(["(", "14", "-", "05", ")"]),
        "dec": j(["D", "-", "07"]),
        "reqid": j(["HY", "G-", "01"]),
        "wave": j(["wa", "ve ", "3"]),
        "task": j(["Ta", "sk ", "4"]),
        "tid": j(["T", "-", "36", "-", "16"]),
        "quick": j(["26", "0410", "-", "abc"]),
        "fixnn": j(["_FI", "X", "08"]),
        "byteid": j(["byte", "-identical"]),
        "pitfall": j(["Pit", "fall ", "7"]),
        "artifact": j(["RESEA", "RCH", ".md"]),
        "fxfile": j(["Phase", "9", "Fixtures"]),
    }
    negatives = ["3-phase", "T-24", "IEEE-8500", "IEEE-123", "2026-10-04", "0.10-0.12",
                 "eq. 3.43", "(3.31)", "Gan-Low 2015"]
    ok = True
    for rule, text in positives.items():
        if not R.RULES[rule].search(text):
            print(f"SELFTEST FAIL: rule {rule} did not match {text!r}")
            ok = False
    for text in negatives:
        hit = [k for k, rx in R.RULES.items() if rx.search(text)]
        if hit:
            print(f"SELFTEST FAIL: negative {text!r} matched {hit}")
            ok = False
    # Fail-closed scenarios on temporary trees.
    def run(files, allowlist=None):
        with tempfile.TemporaryDirectory() as d:
            for name, content in files.items():
                p = os.path.join(d, name)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                mode = "wb" if isinstance(content, bytes) else "w"
                with open(p, mode) as fh:
                    fh.write(content)
            al = os.path.join(d, "allow.tsv")
            with open(al, "w") as fh:
                fh.write(allowlist or "")
            return main(["--root", d, "--allowlist", al])
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        cases = [
            ("clean tree exits 0", run({"a.jl": "x = 1  # fine\n"}), 0),
            ("phase reference exits 1", run({"a.jl": positives["phase"] + "\n"}), 1),
            ("allowlisted hit exits 0",
             run({"a.jl": "# " + positives["phase"] + "\n"}, "a.jl\t" + "Phase" + "\treason\n"), 0),
            ("stale allowlist entry exits 1", run({"a.jl": "x = 1\n"}, "a.jl\tzzz\treason\n"), 1),
            ("malformed allowlist exits 2", run({"a.jl": "x = 1\n"}, "only-one-field\n"), 2),
            ("undecodable file exits 2", run({"a.jl": b"\xff\xfe\xfa bad\n"}), 2),
        ]
    for name, got, want in cases:
        if got != want:
            print(f"SELFTEST FAIL: {name}: got {got}, want {want}")
            ok = False
    if ok:
        print(f"selftest OK: {len(positives)} positive, {len(negatives)} negative, "
              f"{len(cases)} fail-closed case(s)")
        return 0
    return 1


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(main(sys.argv[1:]))
