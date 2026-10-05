#!/usr/bin/env python3
"""Shared rule set and file enumeration for the planning-identifier tooling.

Used by classify_planning_ids.py (report tool) and, later, the CI guard.
Stdlib only. Enumerates tracked files via `git ls-files`.
"""
import re
import subprocess

PFX = (r'(?:FIX|ARCH|CR|WR|IN|PM|BILEV|MESH|SCALE|SEAM|DATA|INFRA|PF|HYG|REACT|EXACT|OVR|MPC'
       r'|STOCH|INT|DEV|OPT|EXP|IMPED|REPRO|PRICE|PLAN|PVAL|RESET|ADMM|NASH|SITE|BLOCKER|GATE|WARNING)')

_RAW = {
    'phase':    r'(?i)\bphases?[\s-]?\d+',
    # `plan 06-02` and the hyphenated `plan-06-02` form.
    'plan':     r'(?i)\bplans?[\s-]+\d{1,2}-\d{2}\b',
    # Any two-digit `NN-NN` (phases >= 40, plans >= 21 included); ascending, unpadded pairs
    # such as line/page/hour ranges (`23-24`, `89-90`, `17-20`) are filtered out below.
    # Sentence/label punctuation after the pair still counts (`36-22.`, `36-22:`, `36-21/22`);
    # decimals (`0.10-0.12`), clock times (`12:30-13:45`) and dates stay excluded.
    'bare_nn':  r'(?<![\w.:/\-])(\d\d)-(\d\d)(?![\d\w\-])(?!/\D)(?!\.\d)(?!:\d)',
    'dec':      r'\b[Dd]-\d{1,2}\b',
    'reqid':    r'\b' + PFX + r'-\d{1,3}[a-z]?\b',
    'wave':     r'(?i)\bwaves?(?:[\s-]?\d)?\b',
    'task':     r'\bTask\s+\d+\b',
    'tid':      r'\bT-\d{2}-\d{2}\b',
    'quick':    r'\b26\d{4}-[0-9a-z]{3}\b',
    'fixnn':    r'_FIX\d+',
    'byteid':   r'(?i)byte-?identical',
    'pitfall':  r'\bPitfall\s+[A-Z]?\d+',
    'artifact': (r'\bRESEARCH(?:\.md)?\b|CONTEXT\.md|-SUMMARY|-REVIEW\.md|\.planning/'
                 r'|USER DECISION|[Cc]ode[- ]review|quick task|\bspike\s+\d{3}'
                 r'|STATE\.md|\bROADMAP|REQUIREMENTS\.md|MEMORY\.md|-PLAN\.md|-VERIFICATION'
                 r'|FINDINGS\.md|(?i:\bmemory\s+(?:file\s+|note\s+)?`)|\[\[[a-z][a-z0-9.]*-[a-z0-9.\-]+\]\]'
                 r'|[Rr]eview[- ]fix|deferred-items|-UAT\b|UAT\.md|VALIDATION\.md|DISCUSSION-LOG'),
    'fxfile':   r'Phase\d+Fixtures|fixtures_phase\d+|:phase\d+',
}


def _is_range(m):
    """`a-b` with a < b and no zero padding reads as a numeric range, not a planning id."""
    a, b = m.group(1), m.group(2)
    return int(a) < int(b) and not a.startswith("0") and not b.startswith("0")


class _Filtered:
    """Compiled regex whose matches are additionally vetoed by a predicate."""

    def __init__(self, pattern, veto):
        self.rx = re.compile(pattern)
        self.pattern = pattern
        self.veto = veto

    def search(self, text):
        for m in self.rx.finditer(text):
            if not self.veto(m):
                return m
        return None


_VETO = {'bare_nn': _is_range}
RULES = {k: (_Filtered(v, _VETO[k]) if k in _VETO else re.compile(v)) for k, v in _RAW.items()}

# Strict thesis-equation pattern: lines matching it AND a rule are flagged MIXED.
THESIS_MIXED = re.compile(r'\(3\.\d{2}\)|(?i:thesis\s+3\.\d)|(?i:\beqs?\.? ?3\.\d)')

SCOPE_ROOTS = ["src", "ext", "test", "scripts", "docs/literate", "docs/make.jl",
               "docs/src", "README.md", ".github/workflows/CI.yml"]
SCOPE_EXTS = {".jl", ".py", ".sh", ".md", ".yml", ".toml"}
EXCLUDE_PREFIXES = [".planning/"]
# Roots restricted to a narrower extension set (docs/src: Markdown pages only).
ROOT_EXTS = {"docs/src": {".md"}}


def repo_root():
    return subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()


def iter_scope_files(paths=None):
    """Tracked in-scope files (relative paths), optionally restricted to path prefixes."""
    root = repo_root()
    out = subprocess.check_output(["git", "ls-files"], cwd=root, text=True).splitlines()
    res = []
    for f in out:
        if any(f.startswith(p) for p in EXCLUDE_PREFIXES):
            continue
        if not any(f == r or f.startswith(r.rstrip("/") + "/") for r in SCOPE_ROOTS):
            continue
        if not any(f.endswith(e) for e in SCOPE_EXTS):
            continue
        narrow = [e for r, e in ROOT_EXTS.items() if f.startswith(r + "/")]
        if narrow and not any(f.endswith(x) for x in narrow[0]):
            continue
        if paths:
            ps = [p.rstrip("/") for p in paths]
            if not any(f == p or f.startswith(p + "/") for p in ps):
                continue
        res.append(f)
    return res
