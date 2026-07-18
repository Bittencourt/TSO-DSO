# src/devices/Aggregator.jl
#
# SEAM: aggregator roll-up -- the network-facing residual writer (DEV-05).
# OWNER: plan 03-05.
#
# Rolls a bus's member devices into the nodal net active/reactive power injections
# and total utility the network actually sees (thesis eqs. 3.21-3.23). Holds a bus
# id, a load power factor phi, and its member `AbstractDevice`s plus the inelastic-
# demand and PV parameter profiles for its houses. `contribute!(agg, ctx; T)` drives
# each device, sums active contributions into p_ag (3.22), derives reactive q_ag =
# p * tan(arccos phi) for flexible/inelastic loads (3.23; batteries/PV are active-
# only), injects p_ag/q_ag into :Rp/:Rq at its bus, and adds the summed utility to
# the objective. RESOLVED design (RESEARCH Q1): the Aggregator is the SOLE :Rp/:Rq
# writer; devices return their terms and never touch the network. Declares its own
# `export`s when plan 03-05 fills it; comment-only stub until then.
