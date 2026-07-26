# API Reference

Full docstring reference for the public `TSODSO` API, grouped by subsystem. Every symbol
below is documented at its definition in `src/`; this page surfaces those docstrings in the
rendered manual (previously they existed in the code but were not included in the docs).

```@meta
CurrentModule = TSODSO
```

## Module

```@docs
TSODSO
```

## Solver Abstraction

```@autodocs
Modules = [TSODSO]
Pages = ["solver/ProblemClass.jl", "solver/problem_class_trait.jl", "solver/factory.jl"]
Order = [:type, :constant, :function]
```

## Core: Model Context & Status

```@autodocs
Modules = [TSODSO]
Pages = ["core/ModelContext.jl", "core/status.jl"]
Order = [:type, :constant, :function]
```

## Units

```@autodocs
Modules = [TSODSO]
Pages = ["units/PerUnit.jl"]
Order = [:type, :constant, :function]
```

## Network Data Model

```@autodocs
Modules = [TSODSO]
Pages = ["data/Feeder.jl", "data/topology.jl", "data/ieee13.jl", "data/ieee123.jl", "data/profiles.jl"]
Order = [:type, :constant, :function]
```

## Prosumer Devices & Aggregator

```@autodocs
Modules = [TSODSO]
Pages = [
    "devices/AbstractDevice.jl",
    "devices/Thermostatic.jl",
    "devices/Deferrable.jl",
    "devices/Interruptible.jl",
    "devices/PVBattery.jl",
    "devices/Aggregator.jl",
]
Order = [:type, :constant, :function]
```

## Power-Flow Formulations

```@autodocs
Modules = [TSODSO]
Pages = ["powerflow/AbstractPowerFlow.jl", "powerflow/DCPowerFlow.jl", "powerflow/LinDistFlow.jl", "powerflow/ConvexBranchFlow.jl", "powerflow/ACPowerFlow.jl"]
Order = [:type, :constant, :function]
```

## Models & Centralized Solve

```@autodocs
Modules = [TSODSO]
Pages = ["models/toy_dc.jl", "models/linear_solve.jl", "models/welfare_solve.jl", "models/oracle.jl", "models/exactness.jl", "models/ac_oracle.jl"]
Order = [:type, :constant, :function]
```

## Pricing & Welfare Accounting

```@autodocs
Modules = [TSODSO]
Pages = ["pricing/dlmp.jl", "pricing/welfare.jl", "pricing/fit.jl", "pricing/checks.jl"]
Order = [:type, :constant, :function]
```

## ADMM Decomposition

```@autodocs
Modules = [TSODSO]
Pages = ["admm/AgrOpt.jl", "admm/DsoOpt.jl", "admm/residuals.jl", "admm/solve_admm.jl"]
Order = [:type, :constant, :function]
```

## Diagnostics

```@autodocs
Modules = [TSODSO]
Pages = ["diagnostics/plots.jl"]
Order = [:type, :constant, :function]
```

## Experiment Harness

```@autodocs
Modules = [TSODSO]
Pages = ["experiments/Scenario.jl", "experiments/materialize.jl", "experiments/run.jl", "experiments/store.jl", "experiments/sweep.jl"]
Order = [:type, :constant, :function]
```

## Planning Layer

```@autodocs
Modules = [TSODSO]
Pages = [
    "planning/retry.jl",
    "planning/checkpoint.jl",
    "planning/trace.jl",
    "planning/subproblem.jl",
    "planning/follower.jl",
    "planning/master.jl",
    "planning/benders.jl",
    "planning/coupling.jl",
    "planning/nash.jl",
]
Order = [:type, :constant, :function]
```
