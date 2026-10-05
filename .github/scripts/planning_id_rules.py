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
    'plan':     r'(?i)\bplans?\s+\d{1,2}-\d{2}\b',
    'bare_nn':  r'(?<![\w.:/\-])(?:0\d|[12]\d|3\d)-(?:0\d|1\d|20)(?![\d\w.:/\-])',
    'dec':      r'\b[Dd]-\d{1,2}\b',
    'reqid':    r'\b' + PFX + r'-\d{1,3}[a-z]?\b',
    'wave':     r'(?i)\bwaves?(?:[\s-]?\d)?\b',
    'task':     r'\bTask\s+\d\b',
    'tid':      r'\bT-\d{2}-\d{2}\b',
    'quick':    r'\b26\d{4}-[0-9a-z]{3}\b',
    'fixnn':    r'_FIX\d+',
    'byteid':   r'(?i)byte-?identical',
    'pitfall':  r'\bPitfall\s+[A-Z]?\d+',
    'artifact': (r'\bRESEARCH(?:\.md)?\b|CONTEXT\.md|-SUMMARY|-REVIEW\.md|\.planning/'
                 r'|USER DECISION|[Cc]ode[- ]review|quick task|\bspike\s+\d{3}'),
    'fxfile':   r'Phase\d+Fixtures|fixtures_phase\d+|:phase\d+',
}
RULES = {k: re.compile(v) for k, v in _RAW.items()}

# Strict thesis-equation pattern: lines matching it AND a rule are flagged MIXED.
THESIS_MIXED = re.compile(r'\(3\.\d{2}\)|(?i:thesis\s+3\.\d)|(?i:\beqs?\.? ?3\.\d)')

SCOPE_ROOTS = ["src", "ext", "test", "scripts", "docs/literate", "docs/make.jl",
               "docs/src", "README.md", ".github/workflows"]
SCOPE_EXTS = {".jl", ".py", ".sh", ".md", ".yml", ".toml"}
EXCLUDE_PREFIXES = [".planning/"]


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
        if paths:
            ps = [p.rstrip("/") for p in paths]
            if not any(f == p or f.startswith(p + "/") for p in ps):
                continue
        res.append(f)
    return res
