# Run JuliaFormatter 2.10.x (never the global 2.12.x) in a temporary environment.
# Usage: julia --startup-file=no .github/scripts/format210.jl path...
import Pkg
Pkg.activate(; temp = true)
Pkg.add(name = "JuliaFormatter", version = "2.10")
using JuliaFormatter
v = pkgversion(JuliaFormatter)
(v.major == 2 && v.minor == 10) || error("expected JuliaFormatter 2.10.x, got $v")
println("JuliaFormatter version: $v")
isempty(ARGS) && error("usage: format210.jl path...")
root = readchomp(`git rev-parse --show-toplevel`)
cd(root)  # honour the repo .JuliaFormatter.toml
format(ARGS; verbose = true)
println("JuliaFormatter version used: $v")
