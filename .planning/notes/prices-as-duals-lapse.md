---
title: The prices-as-duals justification lapses under SOCP inexactness
date: 2026-07-26
context: Thesis/paper claim surfaced during the v3.0 exploration session. Writing artifact, not framework work.
status: claim — needs the v3.0 envelope to bound it
---

# The prices-as-duals justification lapses under SOCP inexactness

## The claim — corrected framing

⚠️ **An earlier draft of this note stated the claim incorrectly.** It said the multipliers "lose
their dual interpretation" and invoked a failure of strong duality. That is wrong for the SOCP and a
referee who knows conic duality would catch it immediately. The corrected version:

**The SOCP is convex. Strong duality holds (under Slater). Its duals are perfectly valid prices.**
What fails is *which problem they price*. At an inexact point `l·v > P²+Q²`, the relaxed optimum is
not implementable on the physical network, so:

> The multipliers are **exact prices for a fictitious network**, and the gap between that network and
> the real one is unpriced.

That is a different and sharper statement than "the duals lose meaning." The distinction matters
because it locates the failure precisely: not in the duality theory, but in the physical fidelity of
the primal being priced.

The **nonconvex-local-optimum** argument does apply — but to the AC oracle's multipliers, not the
SOCP's. Those are KKT multipliers at a local optimum: no global-optimality support, so they cannot
carry a market-clearing interpretation either. So neither solve yields a defensible market price
inside the region, but *for two different reasons*, and conflating them weakens the claim.

Framed honestly, and still stronger than the v2.1 finding as currently written:

> It is not merely that the relaxation is loose in the high-PV reverse-flow region. It is that in that
> region **the SOCP prices a network that is not the physical one, while the AC alternative offers
> only local multipliers** — so there is no defensible market-clearing price on offer. And that region
> is precisely the operating regime that motivates transactive distribution pricing.

## Why this matters for the thesis

- It is a **sharper and more publishable claim than the sign-flip reproduction**, which is
  directional-only and knife-edge fragile (see `.planning/MILESTONES.md`, v2.1).
- It is genuinely ours: found by our own AC oracle on our own fixtures, not inherited from the
  thesis being reproduced.
- It reframes a refusal (`assert_socp_exact!` throws) from an implementation limitation into a
  **result**: the framework declines to price because pricing is not defined there, and we can say
  exactly where "there" is once [[socp-validity-envelope]] is measured.
- Examiners will notice a pricing framework that goes silent when the network gets interesting.
  Better to state it first, bounded, than to be asked.

## What the claim needs before it can be written up

1. **The envelope** — the claim is qualitative until the region is mapped. See
   [[socp-validity-envelope]].
2. **A precise statement of which condition fails** — now tracked as
   [[../research/questions.md — Q2]]. It is *not* strong duality (see corrected framing above). The
   candidates are relaxation exactness, the monotonicity assumption behind the classical sufficient
   conditions, or something specific to this model's concave prosumer utilities and battery/deferrable
   devices — which are **not** the plain loss-minimising objective the classical conditions assume.
   That last possibility is both the most likely to be novel and the most likely to be got wrong by
   analogy.
3. **Literature positioning.** Farivar & Low (2013) and Gan et al. (2015) establish exactness
   conditions; the pricing-interpretation consequence of *violating* them is the part to check for
   prior art before claiming novelty. **Do this check early** — it is cheap, and it determines whether
   this note is a contribution or a rediscovery. Do not invest in the write-up first.
4. **An honest note on what the AC duals still are.** They are not worthless — they are local
   marginal values. The claim should say what they can and cannot support, not dismiss them.

## Deliberately out of scope for this claim

Proposing a *fix* (overvoltage-capable relaxation, AC-dual pricing path). That is the deferred
remediation bet — see [[overvoltage-capable-relaxation]]. This note is the diagnosis only, and the
diagnosis stands on its own whether or not the fix ever lands.
