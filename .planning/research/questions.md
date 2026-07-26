# Open Research Questions

Questions that need deeper investigation before or during a milestone. Each records why it matters
and what would answer it — not a guess at the answer.

---

## Q1 — Do cone slackness and AC-disagreement coincide?

**Raised:** 2026-07-26 (exploration session, v3.0 scoping)
**Revised:** 2026-07-26, second pass — the original framing was wrong; see "What this replaces"
**Blocks:** the v3.0 opening question — see [[../notes/socp-validity-envelope]]
**Status:** open — this is the milestone's FIRST measurement, not a mid-flight detail

### The question

There are two distinct exactness notions implemented in the tree, and v2.1's two headline findings
each came from a *different* one:

| | measures | cost | v2.1 finding |
|---|---|---|---|
| `assert_socp_exact!` (`src/models/exactness.jl:8`) | cone slack within one SOCP solve: `gap = \|l·v − (P²+Q²)\|` | **free** | Phase 18-01 sign-flip fragility (this is what threw) |
| `assert_ac_exact!` (`src/models/ac_oracle.jl:148`) | SOCP optimum vs independent AC optimum | ≥1 nonconvex Ipopt solve | EXACT-04 inexactness at `pv_scale = 1.2` |

**Are these the same phenomenon?** Specifically:

1. Do the Phase 18-01 fragile population points coincide exactly with the points where cone
   `maxratio > 1`?
2. Where the cone is slack, is the SOCP optimum measurably wrong against the AC oracle — and by how
   much?
3. Are there points with a slack cone but negligible AC disagreement (a *harmless* relaxation gap),
   or measurable AC disagreement with a tight cone (worse — a gap the free detector cannot see)?

### Why it comes first

The v3.0 brief originally carried "these two findings are probably one finding" as a motivating
premise. It is a hypothesis. If the fragility has a different cause than the exactness boundary, much
of the milestone's rationale weakens — so it gets measured before anything is built on it.

Q1(1) needs **zero AC solves**: sweep recording the free cone gap and compare against the Phase 18-01
fragile set. Only new code required is a non-throwing `socp_gap_report` so a sweep records rather than
aborting at the first inexact point. Spike-sized.

Q1(3) is where the residual risk lives. A slack-cone-but-fine case means the envelope is drawn too
large — merely conservative. A tight-cone-but-wrong case means the free detector **misses** invalid
points, the envelope is drawn too small, results get stamped valid when they are not, and the
pre-registered WIDE/NARROW gate in [[../seeds/overvoltage-capable-relaxation]] reads NARROW for the
wrong reason.

### What would answer it

For Q1(1): the sweep above. Cheap, definitive, do it first.

For Q1(2)-(3): an AC-oracle point set that deliberately includes **tight-cone points** — not only
slack ones. A point set drawn solely from cone-flagged points cannot detect a missed region at all;
that sampling mistake would silently invalidate the envelope.

**Methodology requirement:** budget ≥2 Ipopt starts per point (v2.1 needed a two-start comparison to
rule out a local-optimum artifact on a single point), and carry an explicit **inconclusive** outcome
alongside exact/inexact. Neither earlier draft of the method had a cell for inconclusive; a
precision/recall table that silently drops those points overstates whichever conclusion survives.

### What this replaces

The original Q1 asked whether a *binding-set heuristic* (`v[j,t] ≈ vmax²`, reverse flow) predicts
inexactness, treating it as a cheap proxy for the expensive AC oracle. That framing was wrong
architecture: `src/models/exactness.jl` already measures the relaxation gap **exactly and for free**,
so no proxy detector is needed. The binding-set signature is retained in the brief as the
*interpretive* layer connecting the region to the Farivar & Low (2013) / Gan et al. (2015)
conditions — not as a detector.

---

## Q2 — What is the exact mechanism that makes the relaxation inexact here?

**Raised:** 2026-07-26 (second pass)
**Blocks:** [[../notes/prices-as-duals-lapse]] — the interpretive claim cannot be written without it
**Status:** open — needs a literature source check, not a re-derivation from memory

The v3.0 brief asserts that the Farivar & Low (2013) / Gan et al. (2015) sufficient conditions turn
on (a) upper voltage bounds not binding and (b) objective monotonicity in branch flow. **That
characterization is an unverified recollection** and was written into the brief with more confidence
than it earned.

What actually needs pinning down before any interpretive claim is publishable:

1. The precise form of the sufficient conditions in each paper — they differ, and Farivar & Low's
   no-upper-bound result is not the same statement as Gan et al.'s.
2. The mechanism: *why* does a binding upper voltage bound plus reverse flow make an inflated `l`
   attractive to the optimizer? At an inexact point `l·v > P²+Q²`, i.e. the model carries more
   apparent current than the flows justify. Under what objective/constraint geometry is that
   preferred? This was **not** derived.
3. Which of the three candidate failures is the one that actually occurs here: relaxation exactness,
   the monotonicity assumption, or something specific to this device/utility structure (the concave
   prosumer utilities and battery/deferrable devices are not the plain loss-minimising objective the
   classical conditions assume — that difference may itself be the answer).

Point 3 is the one most likely to be genuinely novel and most likely to be got wrong by analogy.
