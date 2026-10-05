# AST-equivalence checker (comments and line numbers always ignored).
# Usage: julia --startup-file=no .github/scripts/ast_equiv.jl [MODE] REF path...
#   (default)         : EQUAL/DIFF per .jl file modulo comments, line numbers and DOCSTRINGS
#                       only. Every other string literal (error/@warn/@info messages, Dict/CSV
#                       keys, regex and command bodies, @printf formats) is compared exactly,
#                       so EQUAL proves a docs/comment-only change. Exit 1 on any DIFF.
#   --ignore-strings  : weaker check, EQUAL-MODULO-STRINGS/DIFF modulo ALL string literals
#                       (docstrings and code strings alike). EQUAL here does NOT prove a
#                       comment-only change: user-visible runtime strings may differ. Pair it
#                       with --strings to list them. Exit 1 on any DIFF.
#   --strings         : informational list of added/removed non-docstring string literals
#   --literals        : compare sorted multiset of numeric literals (Number leaves)

# Docstring attachment: `"doc" f` lowers to `Core.@doc "doc" f` (GlobalRef) and an explicit
# `@doc "doc" f` keeps the Symbol; in both the docstring is args[3] (after the LineNumberNode).
isdoc(x) =
    x isa Expr &&
    x.head === :macrocall &&
    length(x.args) >= 4 &&
    (
        (x.args[1] isa GlobalRef && x.args[1].name === Symbol("@doc")) ||
        x.args[1] === Symbol("@doc")
    )

# `strings = :docs` blanks only docstrings (default mode); `strings = :all` blanks every String.
function norm(x; strings::Symbol = :docs)
    x isa String && return strings === :all ? "" : x
    x isa LineNumberNode && return nothing
    x isa Expr || return x
    d = isdoc(x)
    # Index BEFORE dropping LineNumberNodes: the docstring is args[3] of the raw macrocall.
    args = Any[]
    for (i, a) in enumerate(x.args)
        a isa LineNumberNode && continue
        push!(args, d && i == 3 ? "<docstring>" : norm(a; strings))
    end
    return Expr(x.head, args...)
end

function collect_strings!(acc, x)
    if x isa String
        push!(acc, x)
    elseif x isa Expr
        for (i, a) in enumerate(x.args)
            # docstring position of @doc macrocall: args = [@doc, line, doc, expr]
            isdoc(x) && i == 3 && continue
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
    modes = Dict("--literals" => :lit, "--strings" => :str, "--ignore-strings" => :astall)
    for a in args
        if haskey(modes, a)
            mode = modes[a]
        elseif startswith(a, "--")
            println("unknown option $a")
            return 2
        else
            push!(rest, a)
        end
    end
    usage = "usage: ast_equiv.jl [--ignore-strings|--literals|--strings] REF path..."
    length(rest) >= 2 || (println(usage); return 2)
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
        if mode === :ast || mode === :astall
            strings = mode === :ast ? :docs : :all
            if norm(eo; strings) == norm(en; strings)
                println(mode === :ast ? "EQUAL $p" : "EQUAL-MODULO-STRINGS $p")
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
