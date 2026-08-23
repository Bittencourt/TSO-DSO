# Phase 24: Discrete/Integer Investment Expansion - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-23
**Phase:** 24-discrete-integer-investment-expansion
**Areas discussed:** Investment lattice design, Integer master seam, Certification oracle & tiny instance, Cut policy & Phase 24's certificate

All four offered gray areas were selected for discussion.

---

## Investment Lattice Design

### Q1 — What should the discrete investment levels physically represent?

| Option | Description | Selected |
|--------|-------------|----------|
| Engineering block sizes | `y_inv = B·n`, B a real physical increment; integrality carries engineering meaning | |
| Pure binary expansion of `y_max` | Integrality as a numerical discretization of the same continuous range; K bits give resolution `y_max/2^K` | ✓ |
| Explicit level menu | Non-uniform list of real equipment ratings + choose-at-most-one; not binary expansion, so an INT-01 deviation | |

**User's choice:** Pure binary expansion of `y_max`.
**Notes:** Accepts that the discreteness is physically meaningless, in exchange for the clean
convergence-to-continuous diff. Recorded as D-01 with an explicit instruction not to retro-fit a
physical justification.

### Q2 — Which endpoint convention for the binary expansion?

| Option | Description | Selected |
|--------|-------------|----------|
| Divide by `2^K − 1` | All-ones lands exactly on `y_max`; full closed range representable; untidy step size | |
| Divide by `2^K` | Round step sizes; `y_max` unreachable (`y_max·(1−2^-K)`); diff carries a `2^-K` boundary artifact | ✓ |
| Levels = `2^K`, cap at `y_max` | Both endpoints + round steps, at the cost of a non-unique bit representation | |

**User's choice:** Divide by `2^K`.
**Notes:** Claude raised the unreachable-endpoint artifact BEFORE the choice, then verified it is
harmless on the canonical instance — the continuous golden optimum `N1_Y_HAND = 0.7` is interior to
`[0, 8.0]`, so the artifact never binds here. Documented as a known artifact (D-02) rather than
engineered away.

### Q3 — What default K (bit count) should the fixture use?

| Option | Description | Selected |
|--------|-------------|----------|
| K = 3 (8 levels) | Smallest that still exercises integrality; matches INT-03's "tiny instance" | |
| K = 4 (16 levels) | Finer lattice, less degenerate cut sequence, enumeration still trivial | ✓ |
| K configurable, no pinned default | Maximum flexibility, but nothing to golden-test against | |

**User's choice:** K = 4.
**Notes:** Gives step 0.5 on `y_max = 8.0`. Claude then established the load-bearing consequence
(D-04): `0.7` is NOT on the K=4 lattice, so the canonical instance carries a genuine, non-degenerate
integrality gap — a zero gap would be the suspicious result.

---

## Integer Master Seam

### Q1 — How should the integer master be exposed in code?

| Option | Description | Selected |
|--------|-------------|----------|
| New separate builder | `build_master_integer` alongside an untouched `build_master`; continuous path byte-identical by construction; per-builder PVAL-04 carve-out | ✓ |
| Flag on `build_master` | `integer=false` default; single assembly, no duplication; conditional exemption, easier to get subtly wrong | |
| Flag + distinct return type | One assembly plus static dispatch via `IntegerBendersMaster`; larger blast radius through `benders.jl` | |

**User's choice:** New separate builder.
**Notes:** Claude had already surfaced the binding constraint from code: the PVAL-04 guard carries a
source-scan tripwire requiring the discovered `build_*` set to EQUAL the registry keys, so a new
builder cannot be omitted from the registry to dodge the guard (D-07).

### Q2 — How should `solve_stackelberg!` reach the new integer builder?

| Option | Description | Selected |
|--------|-------------|----------|
| `master` injection kwarg | Mirrors the EXISTING `follower = nothing` seam; default path untouched | ✓ |
| New integer driver | `solve_stackelberg_integer!`; maximum isolation but duplicates the hardened loop | |
| `master_builder` function kwarg | Loop still owns construction, keeping the line-62 invariant literally true | |

**User's choice:** `master` injection kwarg.
**Notes:** Chosen for consistency with an established seam rather than inventing a parallel one.
Claude flagged the consequence: `benders.jl:62`'s no-`build_*`-elsewhere docstring invariant must be
UPDATED to describe the seam, not left silently false.

---

## Certification Oracle & Tiny Instance

### Q1 — What should certify the integer loop for INT-03?

| Option | Description | Selected |
|--------|-------------|----------|
| Enumeration primary, Bilevel confirm | 16-point exhaustive enumeration as primary; BilevelJuMP as independent secondary, non-blocking if incompatible | ✓ |
| Enumeration only | Sufficient for 16 points, no new dependency; loses the independent second channel | |
| Bilevel primary, enumeration confirm | Closer to a formal proof, but stakes correctness on unverified mode compatibility | |

**User's choice:** Enumeration primary, Bilevel confirm.
**Notes:** Claude corrected the inherited research flag first (D-11): the flag concerned a
mixed-integer FOLLOWER, whereas this phase puts integrality in the LEADER with a continuous
follower, so the flagged blocker likely does not apply on its original grounds.

### Q2 — What instance should the certification run on?

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse canonical N=1 toy | Existing reviewed fixtures; direct diff vs the continuous PVAL-02 golden; non-degenerate gap | ✓ |
| New smaller instance | K=2, paper-checkable cut trace; adds a fixture, loses the golden diff | |
| Both | Serves teaching and regression separately; two fixtures, more surface | |

**User's choice:** Reuse canonical N=1 toy.

---

## Cut Policy & Phase 24's Certificate

### Q1 — What terminates the integer Benders loop?

| Option | Description | Selected |
|--------|-------------|----------|
| Lattice-gap exact criterion | Terminate below the minimum objective separation between distinct lattice points — a proof, not a tolerance | ✓ |
| New absolute gap, re-measured | Gap-tolerance shape but a newly measured value pinned with provenance; weaker than the structure permits | |
| Both, gap as a guard | Exact criterion as the argument, loose gap only as a runaway guard reported as failure if it fires first | |

**User's choice:** Lattice-gap exact criterion.
**Notes:** Chosen explicitly to avoid inheriting the continuous loop's `tol = 1e-6`, which the
milestone's "no reused tolerances" bar forbids.

### Q2 — What is Phase 24's own new certificate? (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Per-cut validity assertion | Every LL cut checked against the enumerated optimum; tests the cut, not just the outcome | ✓ |
| No-good-cut usage count = 0 | Strictest reading of INT-02's "never the convergence argument" | |
| Finite-termination bound | Iterations ≤ \|lattice\|; would catch cycling | |
| Continuous-baseline diff | Relaxation bound holds and the integer solution brackets the continuous optimum | ✓ |

**User's choice:** Per-cut validity assertion + continuous-baseline diff.
**Notes:** The two declined options are recorded in CONTEXT.md `<specifics>` as deliberate
non-selections, so a later agent does not reintroduce them as gates.

### Q3 — If a rigorous `δ_min` can't be derived, what should the phase do?

| Option | Description | Selected |
|--------|-------------|----------|
| Fall back, report honestly | Attempt derivation; fall back to a measured gap AND report the failed derivation as a finding | |
| Enumeration-backed criterion | Terminate when the incumbent matches the enumerated optimum — exact by construction, no `δ_min` | ✓ |
| Derive it or block | Hard prerequisite; strongest guarantee, risks stalling the milestone's last phase | |

**User's choice:** Enumeration-backed criterion.
**Notes:** Claude raised the underlying risk unprompted — `δ_min` is not simply `c_y·step`, because
the follower's continuous response can offset the leader-cost separation, so a rigorous derivation
may need Lipschitz behaviour in `y`. Accepted cost: works only where enumeration is tractable, so the
large-lattice production criterion becomes an explicitly deferred open item.

### Q4 — What happens when a no-good cut fires?

| Option | Description | Selected |
|--------|-------------|----------|
| Allowed, counted, surfaced | Stays available; every firing counted and reported; convergence attributed only to LL cuts | ✓ |
| Hard-fail in certified runs | Strictest reading, at the risk of a brittle test | |
| Off by default | Smallest surface; a stall becomes the finding, but no recovery path | |

**User's choice:** Allowed, counted, surfaced.

---

## Claude's Discretion

- Algebraic form of the LL cut, cut management/dedup, and module placement of cut bookkeeping.
- HiGHS MILP attribute tuning (behind `select_optimizer` only).
- Trace/report field naming for the no-good bookkeeping, provided the count and the `converged_via`
  attribution are both present.

## Deferred Ideas

- A production termination criterion for lattices too large to enumerate.
- Integrality in the N>1 Nash / diagonalization path.
- Engineering block sizes / explicit level menus as a later modelling extension.
