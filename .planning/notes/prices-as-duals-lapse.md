---
title: The prices-as-duals justification lapses under SOCP inexactness
date: 2026-07-26
context: Thesis/paper claim surfaced during the v3.0 exploration session. Writing artifact, not framework work.
status: claim — needs the v3.0 envelope to bound it
---

# The prices-as-duals justification lapses under SOCP inexactness

## The claim

The framework's entire transactive-pricing story rests on prices being **duals of a convex
program**. That is what makes a DADP/DLMP a meaningful market signal rather than an arbitrary
multiplier: strong duality on a convex social-welfare problem gives the multiplier its
interpretation as a marginal price supporting a globally optimal allocation.

When the SOC relaxation is **inexact**, the convex program whose duals we read is no longer the
physical problem. The AC oracle still produces multipliers, but they are duals of a *nonconvex local
optimum* — no strong duality, no global-optimality support, so the "prices are duals" justification
does not transfer.

So the honest statement is stronger than the v2.1 finding as currently written:

> It is not merely that the relaxation is loose in the high-PV reverse-flow region. It is that **the
> theoretical basis for the prices themselves lapses there** — and that region is precisely the
> operating regime that motivates transactive distribution pricing.

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
2. **A precise statement of which condition fails.** "Prices lapse" needs to name the step: is it
   strong duality, the exactness of the relaxation, or the monotonicity assumption behind the
   sufficient conditions? These are distinct and should not be blurred.
3. **Literature positioning.** Farivar & Low (2013) and Gan et al. (2015) establish exactness
   conditions; the pricing-interpretation consequence of *violating* them is the part to check for
   prior art before claiming novelty.
4. **An honest note on what the AC duals still are.** They are not worthless — they are local
   marginal values. The claim should say what they can and cannot support, not dismiss them.

## Deliberately out of scope for this claim

Proposing a *fix* (overvoltage-capable relaxation, AC-dual pricing path). That is the deferred
remediation bet — see [[overvoltage-capable-relaxation]]. This note is the diagnosis only, and the
diagnosis stands on its own whether or not the fix ever lands.
