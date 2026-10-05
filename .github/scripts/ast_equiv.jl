# AST-equivalence checker (strings, comments and line numbers ignored).
# Usage: julia --startup-file=no .github/scripts/ast_equiv.jl [--literals|--strings] REF path...
#   default    : EQUAL/DIFF per .jl file; exit 1 on any DIFF
#   --strings  : informational list of added/removed non-docstring String literals
#   --literals : compare sorted multiset of numeric literals (Number leaves)

function norm(x)
    x isa String && return ""
    x isa LineNumberNode && return nothing
    x isa Expr || return x
    return Expr(x.head, (norm(a) for a in x.args if !(a isa LineNumberNode))...)
end

isdoc(x) = x isa Expr && x.head === :macrocall && !isempty(x.args) &&
           x.args[1] isa GlobalRef && x.args[1].name === Symbol("@doc")

function collect_strings!(acc, x)
    if x isa String
        push!(acc, x)
    elseif x isa Expr
        for (i, a) in enumerate(x.args)
            # docstring position of @doc macrocall: args = [@doc, line, doc, expr]
            isdoc(x) && i == 3 && a isa String && continue
            collect_strings!(acc, a)
        end
    end
    return acc
end

function collect_numbers!(acc, x)
    if x isa Number
        push!(acc, repr(x))
    elseif x isa Expr
        foreach(a -> collect_numbers!(acc, a), x.args)
    end
    return acc
end

function gitshow(ref, path)
    io = IOBuffer()
    p = run(pipeline(ignorestatus(`git show $ref:$path`); stdout = io, stderr = devnull))
    return success(p) ? String(take!(io)) : nothing
end

function counts(v)
    d = Dict{String,Int}()
    for s in v
        d[s] = get(d, s, 0) + 1
    end
    return d
end

function main(args)
    mode = :ast
    rest = String[]
    for a in args
        a == "--literals" ? (mode = :lit) : a == "--strings" ? (mode = :str) : push!(rest, a)
    end
    length(rest) >= 2 || (println("usage: ast_equiv.jl [--literals|--strings] REF path..."); return 2)
    ref, paths = rest[1], rest[2:end]
    root = readchomp(`git rev-parse --show-toplevel`)
    bad = false
    for p in paths
        if !endswith(p, ".jl")
            println("NOTE ignoring non-jl $p")
            continue
        end
        old = gitshow(ref, p)
        file = joinpath(root, p)
        if old === nothing
            println("NEW $p")
            continue
        end
        isfile(file) || (println("MISSING $p (absent in working tree)"); bad = true; continue)
        new = read(file, String)
        eo, en = Meta.parseall(old), Meta.parseall(new)
        if mode === :ast
            if hash(norm(eo)) == hash(norm(en))
                println("EQUAL $p")
            else
                println("DIFF $p")
                bad = true
            end
        elseif mode === :lit
            so, sn = sort!(collect_numbers!(String[], eo)), sort!(collect_numbers!(String[], en))
            if so == sn
                println("EQUAL $p (numeric literals)")
            else
                println("DIFF $p (numeric literals)")
                bad = true
            end
        else
            co = counts(collect_strings!(String[], eo))
            cn = counts(collect_strings!(String[], en))
            n = 0
            for k in sort!(collect(union(keys(co), keys(cn))))
                d = get(cn, k, 0) - get(co, k, 0)
                d == 0 && continue
                for _ in 1:abs(d)
                    println("STR $p: ", d < 0 ? "-" : "+", repr(k))
                    n += 1
                end
            end
            println("STRINGS $p $n")
        end
    end
    return bad ? 1 : 0
end

exit(main(ARGS))
