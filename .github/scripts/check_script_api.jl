# Static API-surface check for researcher scripts and literate docs (no solver is run).
#
# Usage: julia --project=. --startup-file=no .github/scripts/check_script_api.jl [--selftest] [path...]
#   path... : .jl files or directories (default: scripts docs/literate). Relative paths are
#             resolved against the repo root.
#
# Each file is parsed with `Meta.parseall` (never `include`d) and checked against the LOADED
# TSODSO module:
#   1. parse errors;
#   2. `using/import TSODSO: x` (also `x as y`), `import TSODSO.Sub as S` and dotted chains
#      must resolve: `TSODSO.a.b`, alias chains `T.a`, and unrooted submodule chains such as
#      `ReactiveMode.OFF` (a TSODSO submodule in scope via `using TSODSO` or an import);
#   3. a bare (unqualified, not imported, not locally bound) identifier owned by TSODSO or one
#      of its submodules that `using TSODSO` does NOT bring into scope (unexported / `public`
#      names such as `max_jump`, `SOCP`, `I_base`, `ReactiveMode.OFF` written as `OFF`);
#      a call `f(...)` of such a name is flagged even if the file also binds `f` as a plain
#      variable or NamedTuple key (the `max_jump = max_jump(tr)` pattern);
#   4. removed APIs: `reactive_consensus` typed `::Bool`/`::Symbol` or passed a Bool/Symbol
#      literal; the removed `operational_oracle` keywords (`objective_hook`, `horizon_state`,
#      `z`); `.loss`/`.voltage` on a receiver whose name looks like a DLMP decomposition.
# Exit: 0 clean, 1 findings, 2 usage error / nothing scanned (fail-closed).

using TSODSO

const MOD = TSODSO
const REACTIVE_KW = (:reactive_consensus, :reactive_mode)
const REMOVED_ORACLE_KW = (:objective_hook, :horizon_state, :z)
const DLMP_REMOVED_FIELDS = (:loss, :voltage)

# --------------------------------------------------------------------------- name tables

function owned_by_tsodso(m::Module, s::Symbol)
    isdefined(m, s) || return false
    owner = try
        Base.binding_module(m, s)
    catch
        return false
    end
    while true
        owner === MOD && return true
        p = parentmodule(owner)
        p === owner && return false
        owner = p
    end
end

"""Symbols reachable bare after `using TSODSO` (exports of TSODSO)."""
exported_set() = Set(n for n in names(MOD) if Base.isexported(MOD, n))

"""TSODSO submodules (e.g. `ReactiveMode`), searched for names written bare by mistake."""
function submodules()
    out = Module[]
    for n in names(MOD; all = true)
        isdefined(MOD, n) || continue
        v = getfield(MOD, n)
        v isa Module && v !== MOD && parentmodule(v) === MOD && push!(out, v)
    end
    return out
end

"""Where a bare symbol `s` lives in TSODSO without being exported, or `nothing`."""
function hidden_home(s::Symbol, exported, subs)
    s in exported && return nothing
    (isdefined(Base, s) || isdefined(Core, s)) && return nothing
    startswith(String(s), "@") && return nothing
    if owned_by_tsodso(MOD, s)
        return "TSODSO.$s"
    end
    for m in subs
        if isdefined(m, s) && Base.binding_module(m, s) === m && s !== nameof(m)
            return "$(nameof(m)).$s"   # e.g. bare `OFF` -> ReactiveMode.OFF
        end
    end
    return nothing
end

# --------------------------------------------------------------------------- AST walking

mutable struct FileScan
    path::String
    bound::Set{Symbol}        # names bound anywhere in the file (vars, args, fields, ...)
    fbound::Set{Symbol}       # names bound as functions / types / modules / consts
    imported::Set{Symbol}     # names explicitly imported from TSODSO (or a submodule)
    modalias::Dict{Symbol,Module}  # local names bound to TSODSO / a submodule (`import TSODSO as T`)
    refs::Dict{Symbol,Int}    # value-position references -> first line
    calls::Dict{Symbol,Int}   # call-position references -> first line
    errors::Vector{String}
    line::Int
end
FileScan(p) = FileScan(p, Set{Symbol}(), Set{Symbol}(), Set{Symbol}(), Dict{Symbol,Module}(),
                       Dict{Symbol,Int}(), Dict{Symbol,Int}(), String[], 0)

err!(fs, msg) = push!(fs.errors, "$(fs.path):$(fs.line): $msg")

# Names bound by an assignment LHS / argument / loop variable pattern.
function bind!(fs, x; fn = false)
    if x isa Symbol
        push!(fs.bound, x)
        fn && push!(fs.fbound, x)
    elseif x isa Expr
        h = x.head
        if h in (:tuple, :parameters, :block, :vect)
            foreach(a -> bind!(fs, a), x.args)
        elseif h === :(::)
            length(x.args) == 2 ? (bind!(fs, x.args[1]); ref!(fs, x.args[2])) : ref!(fs, x.args[1])
        elseif h === :kw || h === :(=)
            bind!(fs, x.args[1]); ref!(fs, x.args[2])
        elseif h === :...
            bind!(fs, x.args[1])
        elseif h === :curly || h === :where
            bind!(fs, x.args[1]; fn = fn); foreach(a -> bind!(fs, a), x.args[2:end])
        elseif h === :<: || h === :>:
            bind!(fs, x.args[1]; fn = fn); ref!(fs, x.args[2])
        elseif h === :call
            bind_signature!(fs, x)
        elseif h === :escape
            bind!(fs, x.args[1])
        else
            ref!(fs, x)           # e.g. `a.b = ...`, `a[i] = ...`: those are references
        end
    end
end

# `f(args...; kw...)` signature (possibly wrapped in `where` / `::T`).
function bind_signature!(fs, sig)
    if sig isa Expr && sig.head === :where
        foreach(a -> bind!(fs, a), sig.args[2:end])
        return bind_signature!(fs, sig.args[1])
    elseif sig isa Expr && sig.head === :(::) && length(sig.args) == 2
        ref!(fs, sig.args[2])
        return bind_signature!(fs, sig.args[1])
    elseif sig isa Expr && sig.head === :call
        f = sig.args[1]
        if f isa Symbol
            bind!(fs, f; fn = true)
        elseif f isa Expr && f.head === :(::)     # (::Type)(x) functor
            ref!(fs, f.args[end])
        elseif f isa Expr && f.head === :curly
            bind!(fs, f; fn = true)
        else
            ref!(fs, f)                            # `Base.show(...) = ...`, `TSODSO.f(...)`
        end
        for a in sig.args[2:end]
            check_reactive_decl!(fs, a)
            bind!(fs, a)
        end
    elseif sig isa Expr && sig.head === :tuple   # anonymous `function (x, y)`
        foreach(a -> bind!(fs, a), sig.args)
    else
        bind!(fs, sig)
    end
end

function check_reactive_decl!(fs, a)
    a isa Expr || return
    if a.head === :parameters
        foreach(b -> check_reactive_decl!(fs, b), a.args)
    elseif a.head === :kw
        check_reactive_decl!(fs, a.args[1])
    elseif a.head === :(::) && length(a.args) == 2 && a.args[1] in REACTIVE_KW &&
           a.args[2] in (:Bool, :Symbol)
        err!(fs, "`$(a.args[1])::$(a.args[2])` — the Bool/Symbol reactive forms were removed; " *
                 "annotate `::ReactiveMode.T`")
    end
end

"""Updating assignment heads: `+=`, `-=`, `^=`, `.+=`, `.=`, ... (never plain `=`)."""
function is_update_assign(h::Symbol)
    s = String(h)
    return h !== :(=) && endswith(s, "=") && length(s) >= 2 &&
           s ∉ ("==", "!=", "<=", ">=", "===", "!==", "=>", ":=")
end

callee_name(f) = f isa Symbol ? f :
                 (f isa Expr && f.head === :. && f.args[2] isa QuoteNode) ? f.args[2].value : nothing

# Resolve a `TSODSO.a.b` chain; returns the qualified names list or nothing if not rooted at TSODSO.
function dotted(x)
    parts = Symbol[]
    while x isa Expr && x.head === :. && length(x.args) == 2 && x.args[2] isa QuoteNode
        pushfirst!(parts, x.args[2].value)
        x = x.args[1]
    end
    x isa Symbol || return nothing
    pushfirst!(parts, x)
    return parts
end

"""
Module a dotted chain starting at `s` is rooted at, or `nothing` when `s` is not a TSODSO module
in scope: `TSODSO` itself, a local alias (`import TSODSO as T`, `using TSODSO: ReactiveMode as RM`),
or an exported/imported TSODSO submodule written unrooted (`ReactiveMode.OFF`) and not shadowed
by a local binding.
"""
function chain_root(fs, s::Symbol)
    s === :TSODSO && return MOD
    haskey(fs.modalias, s) && return fs.modalias[s]
    s in fs.bound && return nothing
    isdefined(MOD, s) || return nothing
    v = getfield(MOD, s)
    (v isa Module && v !== MOD && parentmodule(v) === MOD) || return nothing
    (Base.isexported(MOD, s) || s in fs.imported) || return nothing
    return v
end

function check_qualified!(fs, parts)
    m = chain_root(fs, parts[1])
    m === nothing && return
    for i in 2:length(parts)
        m isa Module || return                      # field access on a value: stop
        if !isdefined(m, parts[i])
            err!(fs, "`$(join(parts[1:i], "."))` is not defined (removed or renamed API)")
            return
        end
        m = getfield(m, parts[i])
    end
end

# Resolve a `TSODSO.a.b` module path from a using/import statement (reports a missing link).
function resolve_path!(fs, path)
    m = MOD
    for p in path[2:end]
        if !(m isa Module) || !isdefined(m, p)
            err!(fs, "`$(join(path, "."))` is not defined (removed or renamed API)")
            return nothing
        end
        m = getfield(m, p)
    end
    return m
end

# `x`, `x as y`, `@m` items of a `using A: ...` list -> (imported name, local name).
function import_item(b)
    inner, alias = b isa Expr && b.head === :as ? (b.args[1], b.args[2]) : (b, nothing)
    n = inner isa Expr && inner.head === :. ? inner.args[end] : inner
    n isa Symbol || return nothing
    return n, (alias isa Symbol ? alias : n)
end

function handle_using!(fs, x)
    for a in x.args
        if a isa Expr && a.head === :(:)           # using A.B: x, y as z
            path = a.args[1].args
            items = filter(!isnothing, map(import_item, a.args[2:end]))
            if !isempty(path) && path[1] === :TSODSO
                m = resolve_path!(fs, path)
                for (n, local_name) in items
                    if m isa Module && !isdefined(m, n)
                        err!(fs, "`$(x.head) $(join(path, ".")): $n` — `$n` is not defined " *
                                 "(removed or renamed API)")
                    end
                    push!(fs.imported, local_name)
                    if m isa Module && isdefined(m, n) && getfield(m, n) isa Module
                        fs.modalias[local_name] = getfield(m, n)
                    end
                end
            else
                foreach(it -> push!(fs.bound, it[2]), items)
            end
        elseif a isa Expr && a.head === :as        # import A.B as C
            inner, alias = a.args
            path = inner isa Expr && inner.head === :. ? inner.args : Any[]
            if !isempty(path) && path[1] === :TSODSO
                m = resolve_path!(fs, path)
                m isa Module && (fs.modalias[alias] = m)
                push!(fs.imported, alias)
            else
                push!(fs.bound, alias)
            end
        elseif a isa Expr && a.head === :.
            path = a.args
            if !isempty(path) && path[1] === :TSODSO && length(path) > 1
                m = resolve_path!(fs, path)
                # `using TSODSO.ReactiveMode` brings that submodule's exports (none) + its name
                push!(fs.imported, path[end])
                m isa Module && (fs.modalias[path[end]] = m)
                if m isa Module && x.head === :using
                    for n in names(m)
                        Base.isexported(m, n) && push!(fs.imported, n)
                    end
                end
            elseif !isempty(path)
                push!(fs.bound, path[end])
            end
        end
    end
end

function check_call_kws!(fs, x)
    name = callee_name(x.args[1])
    for a in x.args[2:end]
        kws = a isa Expr && a.head === :parameters ? a.args : (a,)
        for k in kws
            k isa Expr && k.head === :kw || continue
            kn, kv = k.args
            if kn in REACTIVE_KW && (kv isa Bool || kv isa QuoteNode)
                err!(fs, "`$kn = $(repr(kv isa QuoteNode ? kv.value : kv))` — Bool/Symbol reactive " *
                         "forms were removed; pass `ReactiveMode.OFF/CERTIFIED/LIVE`")
            end
            if name === :operational_oracle && kn in REMOVED_ORACLE_KW
                err!(fs, "`operational_oracle(...; $kn = ...)` — keyword `$kn` was removed")
            elseif kn in (:objective_hook, :horizon_state)
                err!(fs, "keyword `$kn` was removed from `operational_oracle`")
            end
        end
    end
end

function ref!(fs, x)
    if x isa Symbol
        haskey(fs.refs, x) || (fs.refs[x] = fs.line)
        return
    elseif x isa LineNumberNode
        fs.line = x.line
        return
    elseif !(x isa Expr)
        return                                      # literals, QuoteNode (`:sym`), GlobalRef
    end
    h, A = x.head, x.args
    if h === :using || h === :import
        handle_using!(fs, x)
    elseif h === :function || h === :macro
        isempty(A) && return
        sig = A[1]
        if h === :macro && sig isa Expr && sig.head === :call
            foreach(a -> bind!(fs, a), sig.args[2:end])
        elseif sig isa Symbol
            bind!(fs, sig; fn = true)               # `function f end`
        else
            bind_signature!(fs, sig)
        end
        length(A) >= 2 && ref!(fs, A[2])
    elseif h === :(=) && (A[1] isa Expr && (A[1].head in (:call, :where) ||
                          (A[1].head === :(::) && A[1].args[1] isa Expr && A[1].args[1].head === :call)))
        bind_signature!(fs, A[1])                    # short-form method definition
        ref!(fs, A[2])
    elseif is_update_assign(h)
        # `s += f(x)`, `s .*= g(y)`, `v[i] -= h(z)`: the LHS is (re)bound, the RHS is a USE.
        # Never route the RHS through `bind!` (a call there would read as a method definition
        # and legitimise the callee for the whole file).
        A[1] isa Symbol ? bind!(fs, A[1]) : ref!(fs, A[1])
        foreach(a -> ref!(fs, a), A[2:end])
    elseif h in (:(=), :const, :local, :global)
        if h === :(=)
            bind!(fs, A[1]; fn = false)
            ref!(fs, A[2])
            if A[1] isa Symbol
                # a top-level const-like binding of a callable keeps call-position uses legal
                A[2] isa Expr && A[2].head in (:->, :function) && push!(fs.fbound, A[1])
            end
        else
            for a in A
                if a isa Expr && a.head === :(=)
                    bind!(fs, a.args[1]; fn = true); ref!(fs, a.args[2])
                else
                    h === :const ? ref!(fs, a) : bind!(fs, a)
                end
            end
        end
    elseif h === :tuple || h === :parameters
        for a in A                                  # NamedTuple keys are not references
            if a isa Expr && (a.head === :(=) || a.head === :kw) && a.args[1] isa Symbol
                ref!(fs, a.args[2])
            else
                ref!(fs, a)
            end
        end
    elseif h === :kw
        ref!(fs, A[2])
    elseif h === :call
        check_call_kws!(fs, x)
        f = A[1]
        if f isa Symbol
            haskey(fs.calls, f) || (fs.calls[f] = fs.line)
            ref!(fs, f)
        else
            ref!(fs, f)
        end
        foreach(a -> ref!(fs, a), A[2:end])
    elseif h === :.
        parts = dotted(x)
        if parts !== nothing
            check_qualified!(fs, parts)
            ref!(fs, parts[1])
            if length(parts) == 2 && parts[2] in DLMP_REMOVED_FIELDS &&
               occursin(r"dec|dlmp"i, String(parts[1]))
                err!(fs, "`$(parts[1]).$(parts[2])` — DlmpDecomposition `.loss`/`.voltage` were " *
                         "removed; use `.cone`/`.drop`")
            end
        else
            ref!(fs, A[1])
            length(A) >= 2 && !(A[2] isa QuoteNode) && ref!(fs, A[2])   # broadcast `f.(x)`
        end
    elseif h === :for || h === :generator || h === :filter || h === :flatten || h === :comprehension
        if h === :for
            spec = A[1]
            specs = spec isa Expr && spec.head === :block ? spec.args : (spec,)
            for s in specs
                s isa Expr && s.head in (:(=), :in) ? (bind!(fs, s.args[1]); ref!(fs, s.args[2])) : ref!(fs, s)
            end
            foreach(a -> ref!(fs, a), A[2:end])
        elseif h === :generator || h === :filter
            for a in A[2:end]
                a isa Expr && a.head in (:(=), :in) ? (bind!(fs, a.args[1]); ref!(fs, a.args[2])) : ref!(fs, a)
            end
            ref!(fs, A[1])
        else
            foreach(a -> ref!(fs, a), A)
        end
    elseif h === :let
        spec = A[1]
        specs = spec isa Expr && spec.head === :block ? spec.args : (spec,)
        for s in specs
            s isa Expr && s.head === :(=) ? (bind!(fs, s.args[1]); ref!(fs, s.args[2])) :
            s isa Symbol ? bind!(fs, s) : ref!(fs, s)
        end
        foreach(a -> ref!(fs, a), A[2:end])
    elseif h === :->
        bind_signature!(fs, A[1] isa Symbol ? A[1] : (A[1] isa Expr && A[1].head === :tuple ? A[1] : A[1]))
        ref!(fs, A[2])
    elseif h === :do
        ref!(fs, A[1]); ref!(fs, A[2])
    elseif h === :try
        ref!(fs, A[1])
        length(A) >= 2 && A[2] isa Symbol && bind!(fs, A[2])
        foreach(a -> ref!(fs, a), A[3:end])
    elseif h === :struct
        bind!(fs, A[2]; fn = true)
        for f in A[3].args
            if f isa Symbol
                push!(fs.bound, f)
            elseif f isa Expr && f.head === :(::)
                bind!(fs, f)
            elseif f isa Expr && f.head === :(=) && f.args[1] isa Expr && f.args[1].head === :(::)
                bind!(fs, f.args[1]); ref!(fs, f.args[2])   # @kwdef default
            else
                ref!(fs, f)
            end
        end
    elseif h === :abstract || h === :primitive
        bind!(fs, A[1]; fn = true)
    elseif h === :module
        bind!(fs, A[2]; fn = true)
        ref!(fs, A[3])
    elseif h === :macrocall
        for a in A[2:end]
            ref!(fs, a)
        end
    elseif h === :quote
        return                                      # quoted code is data
    elseif h === :string
        foreach(a -> ref!(fs, a), A)                # interpolations
    else
        foreach(a -> ref!(fs, a), A)
    end
    return
end

# --------------------------------------------------------------------------- driver

function scan_source(path, src; exported = exported_set(), subs = submodules())
    fs = FileScan(path)
    ex = try
        Meta.parseall(src; filename = path)
    catch e
        err!(fs, "parse error: $(sprint(showerror, e))")
        return fs.errors
    end
    ex isa Expr && ex.head === :toplevel || (err!(fs, "unexpected parse result"); return fs.errors)
    for a in ex.args
        if a isa Expr && a.head === :error || a isa Expr && a.head === :incomplete
            err!(fs, "parse error: $(a)")
        end
        ref!(fs, a)
    end
    for (s, line) in sort!(collect(fs.refs); by = last)
        s in fs.imported && continue
        is_call = haskey(fs.calls, s)
        # Bound as a variable/key only does not legitimise CALLING a hidden TSODSO name.
        local_ok = is_call ? s in fs.fbound : s in fs.bound
        local_ok && continue
        home = hidden_home(s, exported, subs)
        home === nothing && continue
        fs.line = is_call ? fs.calls[s] : line
        err!(fs, "`$s` is not exported by TSODSO (it is `$home`): qualify it or add it to a " *
                 "`using TSODSO: ...` list")
    end
    return fs.errors
end

function collect_files(root, args)
    targets = isempty(args) ? ["scripts", "docs/literate"] : args
    files = String[]
    for t in targets
        p = isabspath(t) ? t : joinpath(root, t)
        if isdir(p)
            for (d, _, fs) in walkdir(p), f in fs
                endswith(f, ".jl") && push!(files, joinpath(d, f))
            end
        elseif isfile(p) && endswith(p, ".jl")
            push!(files, p)
        else
            println(stderr, "ERROR: no such .jl file or directory: $t")
            return nothing
        end
    end
    return sort!(files)
end

function selftest()
    cases = [
        # (source, expected-number-of-findings, label)
        ("using TSODSO\nx = max_jump(tr)", 1, "unexported call"),
        ("using TSODSO\nnt = (max_jump = max_jump(tr),)", 1, "NamedTuple key does not bind"),
        ("using TSODSO: max_jump\nnt = (max_jump = max_jump(tr),)", 0, "explicit import"),
        ("using TSODSO\ny = TSODSO.max_jump(tr)", 0, "qualified"),
        ("using TSODSO\ny = TSODSO.no_such_thing_xyz(1)", 1, "qualified removed name"),
        ("using TSODSO: no_such_thing_xyz", 1, "imported removed name"),
        ("using TSODSO\nf(; reactive_consensus::Bool) = 1", 1, "Bool annotation"),
        ("using TSODSO\nf(; reactive_consensus::ReactiveMode.T) = 1", 0, "enum annotation"),
        ("using TSODSO\nsolve_admm(a, b; reactive_consensus = true)", 1, "Bool literal kw"),
        ("using TSODSO\nsolve_admm(a, b; reactive_consensus = :live)", 1, "Symbol literal kw"),
        ("using TSODSO\nsolve_admm(a, b; reactive_consensus = ReactiveMode.LIVE)", 0, "enum kw"),
        ("using TSODSO\nsolve_admm(a, b; reactive_consensus = OFF)", 1, "bare OFF"),
        ("using TSODSO\nopt = select_optimizer(SOCP())", 1, "bare SOCP"),
        ("using TSODSO\nfunction g(x)\n    SOCP = 1\n    SOCP + x\nend", 0, "local var shadows"),
        ("using TSODSO\noperational_oracle(f, a; z = 1)", 1, "removed oracle kw"),
        ("using TSODSO\nx = dec.loss", 1, "DLMP .loss"),
        ("using TSODSO\nx = df.loss", 0, "non-DLMP .loss"),
        ("using TSODSO\nfor max_jump in 1:3\n    println(max_jump)\nend", 0, "loop var"),
        # `public` (declared via @compat public, every Julia version) is NOT `export`: a bare
        # public name after `using TSODSO` is an UndefVarError at runtime, so it is flagged.
        ("using TSODSO\nb = PerUnitBase(1.0, 4.16)", 1, "bare public-not-exported name"),
        ("using TSODSO\nb = TSODSO.PerUnitBase(1.0, 4.16)", 0, "qualified public name"),
        ("using TSODSO: PerUnitBase\nb = PerUnitBase(1.0, 4.16)", 0, "imported public name"),
        ("x = (", 1, "parse error"),
        # compound assignment: the RHS is a use, never a definition
        ("using TSODSO\ns = 0\ns += max_jump(t)", 1, "compound += RHS call"),
        ("using TSODSO\ntotal = 0\ntotal += max_jump(tr)\ny = max_jump(tr2)", 1,
         "compound += does not legitimise later calls"),
        ("using TSODSO\nv = zeros(3)\nv .-= max_jump.(t)", 1, "broadcast compound .-="),
        ("using TSODSO\ns = 0\ns += 1\nprintln(s)", 0, "compound on a local is fine"),
        # unrooted / aliased submodule chains and renamed imports
        ("using TSODSO\nx = ReactiveMode.ON", 1, "unrooted submodule typo"),
        ("using TSODSO\nsolve_admm(a, b; reactive_consensus = ReactiveMode.Live)", 1,
         "unrooted submodule wrong case"),
        ("using TSODSO\nx = ReactiveMode.CERTIFIED", 0, "unrooted submodule ok"),
        ("using TSODSO\nx = TSODSO.ReactiveMode.ON", 1, "rooted submodule typo"),
        ("using TSODSO: no_such_thing_xyz as q", 1, "renamed import of removed name"),
        ("using TSODSO: max_jump as mj\ny = mj(tr)", 0, "renamed import ok"),
        ("import TSODSO as T\ny = T.no_such_thing_xyz(1)", 1, "module alias chain"),
        ("import TSODSO.ReactiveMode as RM\nx = RM.LIVE\ny = RM.ON", 1, "submodule alias chain"),
        ("using TSODSO\nReactiveMode = (ON = 1,)\nx = ReactiveMode.ON", 0, "local shadows submodule"),
        # value (non-call) uses of a hidden function
        ("using TSODSO\ny = max_jump.(trs)", 1, "broadcast value use"),
        ("using TSODSO\ny = map(max_jump, trs)", 1, "higher-order value use"),
        ("using TSODSO\nf = max_jump", 1, "function-as-value binding"),
    ]
    exported, subs = exported_set(), submodules()
    bad = 0
    for (src, want, label) in cases
        got = length(scan_source("<selftest:$label>", src; exported, subs))
        if got != want
            bad += 1
            println("SELFTEST FAIL [$label]: expected $want finding(s), got $got")
        end
    end
    println(bad == 0 ? "selftest OK ($(length(cases)) cases)" : "selftest: $bad failure(s)")
    return bad == 0 ? 0 : 1
end

function main(args)
    if "--selftest" in args
        return selftest()
    end
    any(a -> startswith(a, "-"), args) && (println(stderr, "usage: check_script_api.jl [--selftest] [path...]"); return 2)
    root = readchomp(`git -C $(@__DIR__) rev-parse --show-toplevel`)
    files = collect_files(root, args)
    files === nothing && return 2
    if isempty(files)
        println(stderr, "ERROR: no .jl files found to check (fail-closed)")
        return 2
    end
    exported, subs = exported_set(), submodules()
    errors = String[]
    for f in files
        append!(errors, scan_source(relpath(f, root), read(f, String); exported, subs))
    end
    foreach(println, errors)
    println(isempty(errors) ? "OK: $(length(files)) files checked against the TSODSO API surface" :
            "FAIL: $(length(errors)) finding(s) in $(length(files)) files")
    return isempty(errors) ? 0 : 1
end

exit(main(ARGS))
