# src/devices/PVBattery.jl
#
# SEAM: PV + battery (BESS) prosumer device (DEV-04).
# OWNER: plan 03-04.
#
# An `AbstractDevice` implementing a co-located PV generator and battery with
# continuous charge/discharge and SOC dynamics (thesis eqs. 3.6-3.9): SOC
# recursion with round-trip efficiency, charge limited by available PV (3.7),
# discharge/charge power bounds (3.8), SOC band (3.9). Utility is a concave charge
# utility minus a convex discharge cost (eqs. 3.15-3.20). CRITICAL: NO binary and
# NO p_ch*p_dch==0 constraint -- the App. C parametrization (lambda_min <=
# lambda_med <= lambda_max) makes simultaneous charge/discharge strictly dominated,
# so p_ch[t]*p_dch[t] = 0 holds at the optimum; this must be VERIFIED numerically
# post-solve (p_ch*p_dch < tau). Follows the `Interruptible` pattern; network-
# agnostic (bus + parameters only; never a Feeder). Declares its own `export`s when
# plan 03-04 fills it; comment-only stub until then.
