#!/usr/bin/env python3
"""Report planning-identifier hits: file:line | kind | rules | MIXED? | text.

Usage: classify_planning_ids.py [paths...] [--count] [--hand]
Always exits 0 (report tool).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import planning_id_rules as R  # noqa: E402

STR_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')


def classify(path, root):
    hits = []
    in_doc = False
    with open(os.path.join(root, path), encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            text = line.rstrip("\n")
            fences = text.count('"""') + text.count("'''")
            doc_line = in_doc or fences > 0
            if fences % 2 == 1:
                in_doc = not in_doc
            rules = [k for k, rx in R.RULES.items() if rx.search(text)]
            if not rules:
                continue
            s = text.strip()
            if s.startswith("#"):
                kind = "comment"
            elif doc_line:
                kind = "docstring"
            else:
                kind = "code"
                for m in STR_RE.finditer(text):
                    if any(R.RULES[k].search(m.group(0)) for k in rules):
                        kind = "string"
                        break
            mixed = bool(R.THESIS_MIXED.search(text))
            hits.append((n, kind, rules, mixed, text))
    return hits


def main(argv):
    count = "--count" in argv
    hand = "--hand" in argv
    paths = [a for a in argv if not a.startswith("--")]
    root = R.repo_root()
    per_file = {}
    for f in R.iter_scope_files(paths or None):
        h = classify(f, root)
        if h:
            per_file[f] = h
    total = sum(len(h) for h in per_file.values())
    if count:
        print(f"TOTAL {total}")
        for f, h in sorted(per_file.items()):
            print(f"{f}: {len(h)}")
        return 0
    for f, h in sorted(per_file.items()):
        for n, kind, rules, mixed, text in h:
            if hand and not mixed:
                continue
            print(f"{f}:{n} | {kind} | {','.join(rules)} | {'MIXED' if mixed else '-'} | {text.strip()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
