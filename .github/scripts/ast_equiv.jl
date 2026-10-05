# AST-equivalence checker (comments and line numbers always ignored).
# Usage: julia --startup-file=no .github/scripts/ast_equiv.jl [MODE] [--allow-new] REF path...
#        julia --startup-file=no .github/scripts/ast_equiv.jl --selftest
#   (default)         : EQUAL/DIFF per .jl file modulo comments, line numbers and DOCSTRINGS
#                       only. Every other string literal (error/@warn/@info messages, Dict/CSV
#                       keys, regex and command bodies, @printf formats) is compared exactly,
#                       and literals are compared by TYPE and value (`1` vs `1.0`, `true` vs `1`,
#                       `0x01` vs `1` are DIFF), so EQUAL proves a docs/comment-only change.
#                       Exit 1 on any DIFF.
#   --ignore-strings  : weaker check, EQUAL-MODULO-STRINGS/DIFF modulo ALL string literals
#                       (docstrings and code strings alike). EQUAL here does NOT prove a
#                       comment-only change: user-visible runtime strings may differ. Pair it
#                       with --strings to list them. Exit 1 on any DIFF.
#   --strings         : informational list of added/removed non-docstring string literals
#   --literals        : compare sorted multiset of numeric literals (Number leaves)
#   --allow-new       : a path absent at REF prints NEW and is accepted (default: failure)
#
# Fail-closed: an unknown/unresolvable REF, a path outside the repository, or a path absent at
# REF (without --allow-new) is never reported as success. Paths may be absolute or relative to
# the current directory; they are mapped to repository-root-relative paths for `git show`.
# Exit: 0 all EQUAL; 1 any DIFF/MISSING/NEW; 2 usage error, bad REF or path outside the repo.

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

# Type-strict structural equality: `==` on Expr args treats `1 == 1.0`, `true == 1` and
# `0x01 == 1` as equal, which would hide a literal-type (dispatch) change.
function streq(a, b)
    if a isa Expr
        return b isa Expr && a.head === b.head && length(a.args) == length(b.args) &&
               all(streq(x, y) for (x, y) in zip(a.args, b.args))
    elseif a isa QuoteNode
        return b isa QuoteNode && streq(a.value, b.value)
    end
    return typeof(a) === typeof(b) && isequal(a, b)
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

function gitshow(root, ref, path)
    io = IOBuffer()
    p = run(pipeline(ignorestatus(`git -C $root show $ref:$path`); stdout = io, stderr = devnull))
    return success(p) ? String(take!(io)) : nothing
end

valid_ref(root, ref) =
    success(pipeline(ignorestatus(`git -C $root rev-parse --verify --quiet $(ref * "^{commit}")`);
                     stdout = devnull, stderr = devnull))

# Absolute or cwd-relative path -> repository-root-relative path (nothing if outside the repo).
function root_relative(root, p)
    a = abspath(p)
    d = dirname(a)
    isdir(d) && (a = joinpath(realpath(d), basename(a)))   # tolerate symlinked cwd/tmp
    r = relpath(a, realpath(root))
    (r == ".." || startswith(r, "../") || isabspath(r)) && return nothing
    return r
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
    allow_new = false
    modes = Dict("--literals" => :lit, "--strings" => :str, "--ignore-strings" => :astall)
    for a in args
        if haskey(modes, a)
            mode = modes[a]
        elseif a == "--allow-new"
            allow_new = true
        elseif startswith(a, "--")
            println("unknown option $a")
            return 2
        else
            push!(rest, a)
        end
    end
    usage = "usage: ast_equiv.jl [--ignore-strings|--literals|--strings] [--allow-new] REF path..."
    length(rest) >= 2 || (println(usage); return 2)
    ref, paths = rest[1], rest[2:end]
    root = try
        readchomp(pipeline(`git rev-parse --show-toplevel`; stderr = devnull))
    catch
        println("ERROR: not inside a git repository")
        return 2
    end
    valid_ref(root, ref) || (println("ERROR: bad REF $(repr(ref)) (not a commit here; shallow clone?)"); return 2)
    bad = false
    nchecked = 0
    for p0 in paths
        if !endswith(p0, ".jl")
            println("NOTE ignoring non-jl $p0")
            continue
        end
        p = root_relative(root, p0)
        p === nothing && (println("ERROR: $p0 is outside the repository $root"); return 2)
        nchecked += 1
        old = gitshow(root, ref, p)
        file = joinpath(root, p)
        if old === nothing
            println("NEW $p", allow_new ? "" : " (absent at $ref; pass --allow-new to accept)")
            allow_new || (bad = true)
            continue
        end
        isfile(file) || (println("MISSING $p (absent in working tree)"); bad = true; continue)
        new = read(file, String)
        eo, en = Meta.parseall(old), Meta.parseall(new)
        if mode === :ast || mode === :astall
            strings = mode === :ast ? :docs : :all
            if streq(norm(eo; strings), norm(en; strings))
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
    nchecked == 0 && (println("ERROR: no .jl paths given (fail-closed)"); return 2)
    return bad ? 1 : 0
end

function selftest()
    nfail = 0
    check(label, got, want) =
        got == want || (nfail += 1; println("SELFTEST FAIL [$label]: got $got, want $want"))
    eq(a, b) = streq(norm(Meta.parseall(a)), norm(Meta.parseall(b)))
    # literal type strictness
    check("1 vs 1.0", eq("y = x + 1", "y = x + 1.0"), false)
    check("true vs 1", eq("flag = true", "flag = 1"), false)
    check("0x01 vs 1", eq("b = 0x01", "b = 1"), false)
    check("0.0 vs -0.0", eq("z = 0.0", "z = -0.0"), false)
    check(":a vs :b", eq("s = :a", "s = :b"), false)
    check("same literal", eq("y = x + 1.0", "y = x  +  1.0  # c"), true)
    check("docstring only", eq("\"a\"\nf(x) = 1", "\"b\"\nf(x) = 1"), true)
    check("code string", eq("error(\"a\")", "error(\"b\")"), false)
    # fail-closed CLI on a throwaway repository
    mktempdir() do d
        g(args...) = run(pipeline(`git -C $d -c user.name=t -c user.email=t@t $args`; stdout = devnull, stderr = devnull))
        g("init", "-q")
        write(joinpath(d, "a.jl"), "x = 1\n")
        g("add", "a.jl"); g("commit", "-q", "-m", "init")
        q(args...) = redirect_stdout(devnull) do
            cd(() -> main(collect(String, args)), d)
        end
        check("equal file", q("HEAD", "a.jl"), 0)
        check("absolute path", q("HEAD", joinpath(d, "a.jl")), 0)
        check("bad ref", q("no-such-ref", "a.jl"), 2)
        check("outside repo", q("HEAD", joinpath(dirname(d), "zz_not_here.jl")), 2)
        write(joinpath(d, "b.jl"), "y = 2\n")
        check("new file fails", q("HEAD", "b.jl"), 1)
        check("new file allowed", q("--allow-new", "HEAD", "b.jl"), 0)
        check("no jl paths", q("HEAD", "README.md"), 2)
        write(joinpath(d, "a.jl"), "x = 1.0\n")
        check("literal type change", q("HEAD", "a.jl"), 1)
        write(joinpath(d, "a.jl"), "# comment\nx = 1\n")
        check("comment only", q("HEAD", "a.jl"), 0)
    end
    println(nfail == 0 ? "selftest OK" : "selftest: $nfail failure(s)")
    return nfail == 0 ? 0 : 1
end

exit("--selftest" in ARGS ? selftest() : main(ARGS))
