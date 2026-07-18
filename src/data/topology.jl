# src/data/topology.jl
#
# Radial (tree) validation (DATA-02). A feeder must be a radial tree: for a
# simple connected graph, `edges == nodes - 1` AND connected ⟺ tree (acyclic,
# single component) — so an explicit cycle search is unnecessary. We additionally
# require exactly one designated frontier (root) bus.
#
# Validation runs at `Feeder` construction (see data/Feeder.jl) and a non-tree
# feeder raises a clear `ArgumentError`. No Graphs.jl dependency: connectivity is
# a ~15-line BFS over a hand-built adjacency list (RESEARCH "Don't Hand-Roll").
# The sparse node-branch incidence is returned for reuse by the model layer.
#
# Convention (Phase 1): bus `id` equals its 1-based position in `buses`, matching
# the thesis fixtures; the incidence/adjacency are indexed by that position.

using SparseArrays

"""
    assert_radial(buses, branches, root) -> SparseMatrixCSC

Assert the feeder defined by `buses`, `branches`, and frontier `root` is a radial
tree, throwing a clear `ArgumentError` otherwise. Checks, in order:

  1. `length(branches) == length(buses) - 1` (edge-count theorem);
  2. `root` is a valid bus index;
  3. every bus is reachable from `root` via BFS (connectivity);
  4. exactly one bus has `is_root == true`.

Returns the `N × B` sparse node-branch incidence matrix (`+1` at each branch's
`from` node, `-1` at its `to` node) for reuse by the model layer.
"""
function assert_radial(buses, branches, root)
    N, B = length(buses), length(branches)

    # (1) Edge-count theorem: a tree on N nodes has exactly N-1 edges.
    B == N - 1 || throw(ArgumentError(
        "Non-radial feeder: $N buses require exactly $(N - 1) branches, got $B."))

    # (2) Root must index a real bus (guards the BFS/adjacency access below).
    1 ≤ root ≤ N || throw(ArgumentError(
        "Feeder root $root is out of range 1:$N."))

    # Sparse node-branch incidence: +1 at `from`, -1 at `to`.
    Irow = Int[]
    Jcol = Int[]
    Vval = Int[]
    for (b, br) in enumerate(branches)
        push!(Irow, br.from); push!(Jcol, b); push!(Vval, +1)
        push!(Irow, br.to);   push!(Jcol, b); push!(Vval, -1)
    end
    A = sparse(Irow, Jcol, Vval, N, B)

    # (3) Connectivity: BFS from root over an undirected adjacency list.
    #     connected ∧ (B == N-1) ⟺ tree, so no cycle detection is needed.
    adj = [Int[] for _ in 1:N]
    for br in branches
        push!(adj[br.from], br.to)
        push!(adj[br.to], br.from)
    end
    seen = falses(N)
    seen[root] = true
    reached = 1
    queue = [root]
    while !isempty(queue)
        u = pop!(queue)
        for v in adj[u]
            if !seen[v]
                seen[v] = true
                reached += 1
                push!(queue, v)
            end
        end
    end
    reached == N || throw(ArgumentError(
        "Non-radial feeder: graph is disconnected from root $root " *
        "($reached/$N buses reachable)."))

    # (4) Exactly one designated frontier (root) bus.
    nroots = count(b -> b.is_root, buses)
    nroots == 1 || throw(ArgumentError(
        "Feeder must have exactly one frontier (root) bus, got $nroots."))

    return A
end

export assert_radial
