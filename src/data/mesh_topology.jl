# src/data/mesh_topology.jl
#
# Mesh (connected, not-necessarily-radial) validation (MESH-01, plan 23-01). A
# meshed feeder need not be a tree: `nB >= N` is allowed (loops are the whole
# point). This file is `data/topology.jl`'s `assert_radial` MINUS the tree-
# specific edge-count theorem (`B == N - 1`) -- every other check (root range,
# positional convention, branch-endpoint range, BFS connectivity, single-root,
# root/is_root agreement) is kept VERBATIM, since those checks are already
# graph-generic and never assumed acyclicity.
#
# `data/topology.jl`/`assert_radial`/`Feeder` are BYTE-UNCHANGED by this file
# (D-01/D-09 lock): this is a wholly separate validator for a wholly separate
# struct (`MeshedFeeder`, `data/MeshedFeeder.jl`).
#
# No Graphs.jl dependency: connectivity is the same ~15-line BFS over a
# hand-built adjacency list `assert_radial` uses (RESEARCH "Don't Hand-Roll").
# The sparse node-branch incidence is returned as a convenience, mirroring
# `assert_radial`'s own return contract.
#
# Convention (Phase 1, inherited): bus `id` equals its 1-based position in
# `buses`; the incidence/adjacency are indexed by that position.

using SparseArrays

"""
    assert_connected(buses, branches, root) -> SparseMatrixCSC

Assert the meshed feeder defined by `buses`, `branches`, and frontier `root`
is a CONNECTED graph (a mesh, `nB >= N` is allowed -- unlike `assert_radial`,
this function does NOT require a tree), throwing a clear `ArgumentError`
otherwise. Checks, in order (this is `assert_radial` minus its check 1, the
`B == N - 1` edge-count theorem):

 1. `root` is a valid bus index;
 2. every `bus.id` equals its 1-based position (indexing convention);
 3. every branch endpoint is a valid bus index;
 4. every bus is reachable from `root` via BFS (connectivity);
 5. exactly one bus has `is_root == true`;
 6. the `root` index points at that single `is_root`-flagged bus.

Returns the `N × B` sparse node-branch incidence matrix (`+1` at each branch's
`from` node, `-1` at its `to` node).
"""
function assert_connected(buses, branches, root)
    N, B = length(buses), length(branches)

    # (1) Root must index a real bus (guards the BFS/adjacency access below).
    1 ≤ root ≤ N || throw(ArgumentError("Feeder root $root is out of range 1:$N."))

    # (2) Positional convention (WR-03): every `bus.id` MUST equal its 1-based
    #     position. All incidence/adjacency indexing is BY POSITION, and the
    #     framework assumes `bus.id` equals that position -- a mislabeled or
    #     reordered `buses` would index inconsistently with `bus.id` the moment
    #     any later layer indexes by id, with no error (a silent-wrong hazard).
    all(i -> buses[i].id == i, eachindex(buses)) ||
        throw(ArgumentError("Bus ids must equal their 1-based position in `buses`."))

    # Branch endpoints must reference real buses (IN-02). Checked explicitly here
    # so an out-of-range endpoint gives a clear domain message instead of the
    # cryptic "row index out of range" that `SparseArrays.sparse` would raise
    # below (both are ArgumentError, so the exception-type contract is unchanged).
    for (b, br) in enumerate(branches)
        (1 ≤ br.from ≤ N && 1 ≤ br.to ≤ N) || throw(
            ArgumentError("Branch $b endpoints ($(br.from)->$(br.to)) out of range 1:$N."),
        )
    end

    # Sparse node-branch incidence: +1 at `from`, -1 at `to`. Note `nB >= N` is
    # perfectly valid here (unlike `assert_radial`) -- a mesh has extra branches
    # forming loops, so this matrix need not be square-minus-one-column-rank.
    Irow = Int[]
    Jcol = Int[]
    Vval = Int[]
    for (b, br) in enumerate(branches)
        push!(Irow, br.from)
        push!(Jcol, b)
        push!(Vval, +1)
        push!(Irow, br.to)
        push!(Jcol, b)
        push!(Vval, -1)
    end
    A = sparse(Irow, Jcol, Vval, N, B)

    # (3) Connectivity: BFS from root over an undirected adjacency list. This
    #     check is ALREADY graph-generic -- it never assumed a tree, only that
    #     every bus is reachable, so it carries over verbatim to a mesh.
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
    reached == N || throw(
        ArgumentError(
            "Disconnected mesh feeder: graph is disconnected from root $root " *
            "($reached/$N buses reachable).",
        ),
    )

    # (4) Exactly one designated frontier (root) bus.
    nroots = count(b -> b.is_root, buses)
    nroots == 1 || throw(
        ArgumentError("Malformed mesh feeder: must have exactly one frontier (root) bus, got $nroots."),
    )

    # (5) The `root` index and the `is_root` flag must AGREE: the single flagged
    #     bus must be the one at position `root`. Otherwise the stored frontier
    #     index and the frontier flag silently disagree -- a silent-wrong hazard
    #     for any layer that reads `feeder.root` in one place and scans `is_root`
    #     in another (WR-01).
    buses[root].is_root || throw(
        ArgumentError(
            "Malformed mesh feeder: root index $root does not point to the is_root-flagged bus.",
        ),
    )

    return A
end

export assert_connected
