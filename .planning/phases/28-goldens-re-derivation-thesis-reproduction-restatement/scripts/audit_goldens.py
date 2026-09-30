#!/usr/bin/env python3
"""
audit_goldens.py - SC-1 cross-phase golden-move audit (Phase 28, FIX-11).

Independently (mechanically, not by re-trusting the hand-written 26-/27-GOLDEN-AUDIT.md
tables) parses `git diff <base>..<head> -- test/` (default base `5939799`, the commit
"docs(26): begin phase execution" -- the last commit before Phase 26's first plan landed;
default head `HEAD`) for numeric-literal "golden moves" and flags any that lack an adjacent
old->new + cause attribution comment.

Stdlib only (re, subprocess, argparse) -- no pip install required.

Design (mirrors 28-RESEARCH.md "Cross-Phase Golden Audit Design"):

1. Run `git diff <base>..<head> -- test/`.
2. Parse the diff into hunks; within each hunk, group consecutive removed ('-') lines and
   the consecutive added ('+') lines that immediately follow them (the classic unified-diff
   "replace" block), then pair QUALIFYING lines (see step 5) position-wise across the two
   groups. Pure comment-only insertions (e.g. the attribution comment itself) are excluded
   from the pairing candidates so they don't get paired against a code line -- they are
   still visible to the attribution-window scan below.
3. A numeric literal is flagged via: a decimal with >=3 digits after the point
   (`-?\\d+\\.\\d{3,}`), OR scientific notation (`-?\\d+\\.?\\d*e[+-]?\\d+`), OR a bare
   integer assigned to a name containing GOLDEN/ATOL/RTOL/TOL/SEED/ITER/MAXITER (case
   insensitive, matching this repo's real style: `seed=1`, `maxiter=200`, `GOLDEN_WELFARE`).
   This threshold was tuned against real diffs in this repo: it catches goldens like
   `1.0436080536`, `-4823.1598620624`, `0.6428101637491034`, `3e-9`, `seed=5` while skipping
   non-goldens like hour indices `1:24`, phase numbers `26`, plan IDs `27-09`, and
   line-number self-citations `test_thesis_repro.jl:89`.
4. For each flagged pair, scan a window of the surrounding hunk lines (+/-5 positions,
   covering both removed and added hunk context) for an attribution signal: the literal
   substrings `OLD` and (`->` or the unicode arrow `->`... i.e. an ASCII "->" or "→") and
   `NEW`, OR a `Plan-`/`Plan `/`FIX-`/`PM-`/`WR-`/`D-` reference, OR the words
   "moved"/"re-derived"/"re-pin".
5. Extraction is restricted to lines that are NOT pure `#`-comment-only lines and that
   contain an assignment (`=`), or a `@test`/`isapprox(`/`atol=`/`rtol=` call-site marker --
   i.e. skip lines where a number appears only inside comment prose describing a ratio, not
   assigned to a `const`/passed to `@test`/`isapprox`/`atol=`/`rtol=`.
6. Extracted numeric strings are compared directly (regex extraction already strips
   surrounding whitespace from the matched literal itself, so JuliaFormatter-driven
   whitespace-only reflow of the REST of the line never produces a spurious pair -- only an
   actual change in the matched digits does).
7. Emits one row per flagged-but-unattributed literal (file:line, old value, new value) to
   stdout as a markdown table; exits 1 if any unattributed row exists, 0 otherwise.

Known false positives (see 28-RESEARCH.md "Known false positives" for the full rationale):
- Tolerance/seed round-trips that net to zero across the whole base->HEAD diff window
  produce NO diff line at all for a straight base->HEAD scan (both endpoints identical) --
  a non-issue here since this script always scans base->HEAD, never per-commit.
- A rewritten comment BLOCK (not a code line) could in principle produce a spurious pair if
  both old and new prose text contain decimal-shaped substrings; restricting extraction to
  non-comment, assignment/test-call-site lines (criterion 5) avoids this.
- Version/line-number self-references (`test_thesis_repro.jl:89`, `Plan 27-05`) are filtered
  by the >=3-decimal-digit / scientific-notation heuristic (criterion 3): they are short
  integers or hyphenated (`27-05`, not `27.05`), so they never match the numeric regexes.
"""

import argparse
import re
import subprocess
import sys

DECIMAL_RE = re.compile(r"-?\d+\.\d{3,}")
SCI_RE = re.compile(r"-?\d+\.?\d*[eE][+-]?\d+")
GOLDEN_NAME_RE = re.compile(
    r"[A-Za-z_]*(?:GOLDEN|ATOL|RTOL|TOL|SEED|ITER|MAXITER)[A-Za-z_]*\s*=\s*(-?\d+)(?!\.\d)\b",
    re.IGNORECASE,
)

CODE_VALUE_SIGNALS = ("=", "@test", "isapprox(", "atol=", "rtol=")

ATTRIBUTION_REF_RE = re.compile(r"(Plan[- ]|FIX-|PM-|WR-|D-)")
ATTRIBUTION_WORD_RE = re.compile(r"\b(moved|re-derived|re-pin\w*)\b", re.IGNORECASE)

WINDOW_RADIUS = 5

# Explicit, documented allowlist for known detector FALSE NEGATIVES -- each entry was
# independently investigated (not merely asserted) and resolved by direct inspection in
# 28-CROSS-PHASE-AUDIT.md; every entry MUST cite the audit section that resolved it. This
# is never used to silence a genuinely new or uninvestigated finding -- adding an entry
# here without a matching audit-doc citation defeats SC-1's own "prove mechanically"
# standard. Keyed by (file, new_lineno) of the paired finding.
ALLOWLIST = {
    ("test/test_admm.jl", 145): (
        "28-CROSS-PHASE-AUDIT.md Section 1: the `maxiter_ieee13 = 700` call-site edit's "
        "OWN multi-paragraph attribution comment (D-26-02, Plan 26-16) sits ~30 lines above "
        "the assignment -- outside this script's own +/-5-line WINDOW_RADIUS -- and is "
        "already fully attributed in 26-GOLDEN-AUDIT.md Section 1. Confirmed via direct "
        "inspection at Plan 28-01 (2026-09-30), re-confirmed at Plan 28-05's closing-gate "
        "re-run: not a genuinely unattributed golden move, a window-radius false negative."
    ),
}


def is_comment_only(stripped_line):
    return stripped_line.startswith("#")


def qualifies_as_code_value_line(stripped_line):
    """Criterion 5: exclude pure-comment prose; require an assignment or test-call marker."""
    if is_comment_only(stripped_line):
        return False
    return any(sig in stripped_line for sig in CODE_VALUE_SIGNALS)


def extract_numbers(line):
    """Criterion 3: flag numeric literals via decimal / scientific / golden-name-integer."""
    nums = set()
    nums.update(DECIMAL_RE.findall(line))
    nums.update(SCI_RE.findall(line))
    for m in GOLDEN_NAME_RE.finditer(line):
        nums.add(m.group(1))
    return nums


def is_attributed(window_text):
    """Criterion 4: OLD...->/→...NEW, or a Plan-/FIX-/PM-/WR-/D- reference, or moved/re-derived/re-pin."""
    has_old_new_arrow = (
        ("OLD" in window_text)
        and (("->" in window_text) or ("→" in window_text))
        and ("NEW" in window_text)
    )
    has_ref = bool(ATTRIBUTION_REF_RE.search(window_text))
    has_word = bool(ATTRIBUTION_WORD_RE.search(window_text))
    return has_old_new_arrow or has_ref or has_word


def evaluate_pair(filename, annotated, old_pos, new_pos):
    """Given two paired annotated-line positions, decide if this is a flagged, (un)attributed move."""
    _, old_text, old_lineno, _ = annotated[old_pos]
    _, new_text, _, new_lineno = annotated[new_pos]

    old_nums = extract_numbers(old_text)
    new_nums = extract_numbers(new_text)
    if not old_nums and not new_nums:
        return None
    if old_nums == new_nums:
        return None  # criterion 6: nothing actually changed in the matched literal(s)

    lo = max(0, min(old_pos, new_pos) - WINDOW_RADIUS)
    hi = min(len(annotated), max(old_pos, new_pos) + WINDOW_RADIUS + 1)
    window_text = "\n".join(annotated[p][1] for p in range(lo, hi))

    return {
        "file": filename or "?",
        "old_lineno": old_lineno,
        "new_lineno": new_lineno,
        "old_value": ", ".join(sorted(old_nums)) if old_nums else "NONE",
        "new_value": ", ".join(sorted(new_nums)) if new_nums else "NONE",
        "attributed": is_attributed(window_text),
    }


def process_hunk(filename, old_start, new_start, hunk_lines):
    """Annotate a hunk's lines with old/new line numbers, then pair replace-blocks and evaluate."""
    findings = []
    old_ln = old_start
    new_ln = new_start
    annotated = []  # list of (kind, text_without_diff_prefix, old_lineno_or_None, new_lineno_or_None)

    for raw in hunk_lines:
        if raw.startswith("-") and not raw.startswith("---"):
            annotated.append(("-", raw[1:], old_ln, None))
            old_ln += 1
        elif raw.startswith("+") and not raw.startswith("+++"):
            annotated.append(("+", raw[1:], None, new_ln))
            new_ln += 1
        elif raw.startswith("\\"):
            # "\ No newline at end of file" marker -- no line-number change.
            annotated.append((" ", raw, None, None))
        else:
            text = raw[1:] if raw.startswith(" ") else raw
            annotated.append((" ", text, old_ln, new_ln))
            old_ln += 1
            new_ln += 1

    n = len(annotated)
    idx = 0
    while idx < n:
        if annotated[idx][0] == "-":
            run_start = idx
            j = idx
            while j < n and annotated[j][0] == "-":
                j += 1
            removed_run = list(range(run_start, j))
            k = j
            while k < n and annotated[k][0] == "+":
                k += 1
            added_run = list(range(j, k))

            qual_removed = [
                p for p in removed_run if qualifies_as_code_value_line(annotated[p][1].strip())
            ]
            qual_added = [
                p for p in added_run if qualifies_as_code_value_line(annotated[p][1].strip())
            ]

            pair_count = min(len(qual_removed), len(qual_added))
            for pnum in range(pair_count):
                finding = evaluate_pair(filename, annotated, qual_removed[pnum], qual_added[pnum])
                if finding is not None:
                    findings.append(finding)
            idx = k
        else:
            idx += 1
    return findings


def parse_diff(diff_text):
    """Parse a `git diff -- test/`-style unified diff into a flat list of flagged pairs."""
    lines = diff_text.splitlines()
    results = []
    current_file = None
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        if line.startswith("diff --git"):
            current_file = None
            i += 1
            continue
        if line.startswith("+++ b/"):
            current_file = line[len("+++ b/") :]
            i += 1
            continue
        if line.startswith("@@"):
            m = re.match(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            old_start = int(m.group(1)) if m else 1
            new_start = int(m.group(2)) if m else 1
            i += 1
            hunk_lines = []
            while i < n and not lines[i].startswith("@@") and not lines[i].startswith("diff --git"):
                hunk_lines.append(lines[i])
                i += 1
            results.extend(process_hunk(current_file, old_start, new_start, hunk_lines))
            continue
        i += 1

    return results


# ---------------------------------------------------------------------------
# Self-test: two embedded synthetic diff-hunk fixtures (Python string literals),
# mirroring test_pricing_fit.jl's real
# "# Phase 26 gap-closure re-pin (PM-06) -- ... OLD <value> -> NEW <value>." idiom.
# ---------------------------------------------------------------------------

FIXTURE_ATTRIBUTED_BODY = [
    "     # context above",
    "-    GOLDEN_WELFARE = -4823.1598620624",
    "+    # Phase 26 gap-closure re-pin (PM-06) -- cause. OLD -4823.1598620624 -> NEW -4823.496124912337.",
    "+    GOLDEN_WELFARE = -4823.496124912337",
    "     # context below",
]

FIXTURE_UNATTRIBUTED_BODY = [
    "     # context above",
    "-    GOLDEN_DADP16 = 1.4024313925",
    "+    GOLDEN_DADP16 = 0.3938281171438668",
    "     # context below",
]


def run_selftest():
    findings_attr = process_hunk("selftest_attributed.jl", 1, 1, FIXTURE_ATTRIBUTED_BODY)
    findings_unattr = process_hunk("selftest_unattributed.jl", 1, 1, FIXTURE_UNATTRIBUTED_BODY)

    ok = True
    reasons = []

    if len(findings_attr) != 1:
        ok = False
        reasons.append(f"expected 1 flagged pair in attributed fixture, got {len(findings_attr)}")
    elif findings_attr[0]["attributed"] is not True:
        ok = False
        reasons.append("attributed fixture's pair was NOT recognized as attributed (false negative)")

    if len(findings_unattr) != 1:
        ok = False
        reasons.append(f"expected 1 flagged pair in unattributed fixture, got {len(findings_unattr)}")
    elif findings_unattr[0]["attributed"] is not False:
        ok = False
        reasons.append("unattributed fixture's pair was WRONGLY recognized as attributed (false positive)")

    if ok:
        print("SELFTEST: PASS")
        return 0
    else:
        print("SELFTEST: FAIL " + "; ".join(reasons))
        return 1


def main():
    parser = argparse.ArgumentParser(
        description="SC-1 cross-phase golden-move audit script (Phase 28, FIX-11)."
    )
    parser.add_argument(
        "--base", default="5939799", help="base commit/ref (default: 5939799, pre-Phase-26)"
    )
    parser.add_argument("--head", default="HEAD", help="head commit/ref (default: HEAD)")
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run the embedded synthetic self-test (no git access) and exit",
    )
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    try:
        proc = subprocess.run(
            ["git", "diff", f"{args.base}..{args.head}", "--", "test/"],
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: git diff failed: {exc.stderr}", file=sys.stderr)
        return 2
    except FileNotFoundError:
        print("ERROR: git not found on PATH", file=sys.stderr)
        return 2

    findings = parse_diff(proc.stdout)
    unattributed_raw = [f for f in findings if not f["attributed"]]

    allowlisted = []
    unattributed = []
    for f in unattributed_raw:
        key = (f["file"], f["new_lineno"])
        if key in ALLOWLIST:
            allowlisted.append(f)
        else:
            unattributed.append(f)

    print(f"# Golden-move audit: {args.base}..{args.head} -- test/")
    print(f"\nTotal flagged numeric-literal moves: {len(findings)}")
    print(
        f"Attributed: {len(findings) - len(unattributed_raw)}  "
        f"Allowlisted (investigated false negatives): {len(allowlisted)}  "
        f"Unattributed: {len(unattributed)}\n"
    )

    if allowlisted:
        print("## Allowlisted (detector false negatives, independently investigated)\n")
        print("| File:Line (old->new) | Old Value | New Value | Citation |")
        print("|---|---|---|---|")
        for f in allowlisted:
            loc = f"{f['file']}:{f['old_lineno']}->{f['new_lineno']}"
            citation = ALLOWLIST[(f["file"], f["new_lineno"])]
            print(f"| {loc} | {f['old_value']} | {f['new_value']} | {citation} |")
        print()

    if unattributed:
        print("| File:Line (old->new) | Old Value | New Value | Attribution |")
        print("|---|---|---|---|")
        for f in unattributed:
            loc = f"{f['file']}:{f['old_lineno']}->{f['new_lineno']}"
            print(f"| {loc} | {f['old_value']} | {f['new_value']} | NONE FOUND |")
        return 1

    print("No unattributed golden-value moves found (allowlisted false negatives shown above, if any).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
