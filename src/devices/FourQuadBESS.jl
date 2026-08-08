# src/devices/FourQuadBESS.jl
#
# SEAM: four-quadrant (P,Q) battery + inverter device (MESH-04).
# OWNER: plan 19-02.
#
# WHAT IT WILL BECOME: a standalone 4Q battery device (no PV field, unlike `PVBattery`) whose
# inverter can inject/absorb BOTH active and reactive power within an apparent-power cone
# (|S|^2 = P^2 + Q^2 <= Smax^2), with asymmetric grid-charging caps distinguishing genuine
# 4-quadrant operation from the existing 2Q PVBattery model. This file is intentionally
# comment-only — no `struct`, no `function`, no `export` — until plan 19-02 fills it.
