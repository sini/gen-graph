# Global graph analysis — operations requiring full graph knowledge.
#
# cycles: standard cycle detection (a node is in a cycle iff reachable from
#   itself). Uses genericClosure per-node for C-level BFS.
# cyclePaths: one representative simple cycle per cyclic component, ORDERED, so
#   consecutive pairs are real edges. SCC partition is Tarjan 1972 / Kosaraju;
#   full simple-cycle enumeration (Johnson 1975) is deliberately not provided.
# dependents/dependentsOf: Arntzenius 2016 (Datafun reverse reachability).
#   dependents uses full transitive closure (amortized for multi-target).
#   dependentsOf uses reverse traversal — Θ( Σ_{u ∈ reach⁻ t} (1 + indeg u) ) for single-target,
#   i.e. O(reachable) only where IN-degree is bounded, since the reversed operator re-reads the
#   index at every visit.
# transpose: Mokhov 2017 §5.2 Graph Transpose — the law is that transpose flips
#   the arguments of `connect` and leaves `overlay` unchanged, so direction is
#   REVERSED, not erased.
{ prelude }:
let
  edgeMaps = import ./edge-maps.nix { inherit prelude; };
  fp = import ./fixpoint.nix { inherit prelude; };
  traverse = import ./traverse.nix;
  partition = import ./partition.nix { inherit prelude; };

  # Shared reverse-edge index: id -> [ids with an edge to id].
  # Extracted from dependentsOf so dependentsFrontier reuses it.
  # Θ(n + E) via groupBy instead of O(E²) via foldl'+// — the concatMap below visits every
  # node to read its out-edges, so a node with no out-edges still costs its visit.
  _reverseIndex =
    { edges, nodes, ... }:
    let
      allEdges = prelude.concatMap (
        from:
        map (to: {
          name = to;
          value = from;
        }) (edges from)
      ) nodes;
      grouped = builtins.groupBy (e: e.name) allEdges;
    in
    builtins.mapAttrs (_: es: map (e: e.value) es) grouped;

  # Transpose a materialized edge map: reverse all edges.
  # Θ(|mat| + E) via groupBy instead of O(E²) via foldl'+// — the concatMap below visits every
  # key of `mat`, so a key with no targets still costs its visit.
  _transposeMat =
    mat:
    let
      allEdges = prelude.concatMap (
        from:
        map (to: {
          name = to;
          value = from;
        }) (mat.${from} or [ ])
      ) (builtins.attrNames mat);
      grouped = builtins.groupBy (e: e.name) allEdges;
    in
    builtins.mapAttrs (_: es: map (e: e.value) es) grouped;

  # Nodes in any cycle (self-reachable): a node is in a cycle iff it is
  # reachable from itself. Standard cycle detection. genericClosure per-node (C-level BFS)
  # materializes each node's closure in full; only the whole-graph transitive closure is avoided.
  #
  # ONE CLOSURE PER NODE OVER ONE ACCESSOR, so the accessor is read ONCE and not at every visit
  # of every closure (`traverse.hoistEdges`). The unhoisted reading costs
  #   Θ( Σ_v Σ_{u ∈ reach v} (1 + outdeg u) )
  # because the operator re-reads `edges` at each visit, which is Θ(n³) on a complete DAG. The
  # hoist pays the out-degree factor ONCE, as Θ(n + E) for the wrap, leaving
  #   Θ( n + E + Σ_v |reach v| )
  # attrsets — still O(n × reachable) at bounded out-degree, where the wrap is Θ(n) and the two
  # readings agree to a constant, and Θ(n²) rather than Θ(n³) on a complete DAG. The n closures
  # are what makes the wrap worth its price here; a caller making one does not hoist.
  cycles =
    accessor@{ edges, nodes, ... }:
    let
      succ = traverse.hoistEdges accessor;
    in
    builtins.sort builtins.lessThan (builtins.filter (traverse.selfReachableVia succ) nodes);

  # Reverse reachability: who can reach targetId?
  # Uses full transitive closure + transpose, so it carries the CLOSURE-CLASS cost
  # shared with `condensationClosure` (super-quadratic on every shape measured;
  # `ci/bench/cost-classes.nix`) — NOT with `condensation`, which is the partition front
  # door and is an UNCONDITIONAL ALIAS for `fbNode` (`partition.nix`), an arm that reaches
  # no closure at all — then O(1) lookup.
  # `transitiveReduction` makes the same
  # closure call but does not always FORCE it, so it is not super-quadratic on every
  # shape: see README's closure-class note for the graph-global carve-out.
  # Amortized: if querying multiple targets, compute once and reuse.
  # For single-target queries, prefer `dependentsOf`.
  dependents =
    args@{ edges, nodes, ... }:
    targetId:
    let
      # The closure class by name, so the ceiling refuses under THIS surface's name rather
      # than under the one it borrows the construction from (`fixpoint.nix`, `closureOf`).
      closure = fp.closureOf "dependents" args;
      reversed = _transposeMat closure;
    in
    builtins.sort builtins.lessThan (
      builtins.filter (id: id != targetId) (reversed.${targetId} or [ ])
    );

  # Single-target reverse reachability via reverse traversal (Arntzenius 2016).
  # Θ(n + E) to build the reverse index — it reads every node's out-edges — then a C-level BFS
  # over that index costing
  #   Θ( Σ_{u ∈ reach⁻ targetId} (1 + indeg u) )
  # because `traverse.reachableFrom`'s operator re-reads the index at every visit, and in the
  # reversed graph a node's out-degree IS its forward in-degree. So this is O(reachable) only
  # where in-degree is bounded, and Θ(n²) on a complete DAG.
  # Much faster than `dependents` for single-target queries on large graphs.
  #
  # ★ AND IT DELIBERATELY DOES NOT HOIST THE ACCESSOR, which is the same decision `cycles` and
  # the partition arms make in the other direction. Hoisting (`traverse.hoistEdges`) builds a Θ(n)
  # SPINE over the whole node set up front; this surface makes exactly ONE closure, so there is no
  # second traversal to spread that spine over. It is not the unreached EDGES that are paid for —
  # the spine's values are unforced thunks, so a node the walk never reaches never has its edges
  # read — it is the spine itself, one entry per node whether or not the node is visited.
  # Measured as a required negative cell in `ci/bench/cost-classes.nix` (`dependentsOf` against
  # `dependentsOfHoisted`): the margin is 3n + 1 attrsets on `chain` and `fleet`, 3n on `cycle` and
  # 2n + 2 on `complete`, exact at every n measured — 2 to 3 allocations per node, FLAT IN n on
  # every shape and independent of E, which is what says it is the spine. `complete` is the
  # discriminator: nothing there is outside the cone, so an unreached-edges account predicts no
  # margin at all, and the margin is still 2n + 2.
  dependentsOf =
    { edges, nodes, ... }:
    targetId:
    let
      reverseIndex = _reverseIndex { inherit edges nodes; };
      revEdges = id: reverseIndex.${id} or [ ];
    in
    builtins.sort builtins.lessThan (traverse.reachableFrom { edges = revEdges; } targetId);

  # Reverse-reachability cone of targetId, walked level-by-level, descending into
  # a node's dependents only when `prune node` is true. A pruned node is still
  # included (reached) but not expanded — the early-cutoff stop. genericClosure
  # cannot include-but-not-expand, so this is a hand-rolled BFS with a visited
  # attrset (cycle guard: each id enters the frontier at most once).
  # Reduces to `dependentsOf` when `prune = _: true`.
  # It does NOT inherit the operator's cost law, even in that limit:
  # Θ(n + E) for the index, then a per-visit Θ( Σ_{u ∈ expanded} (1 + indeg u) ) over what
  # `prune` admits — a pruned node is reached without paying its in-degree — PLUS an
  # accumulator term `genericClosure` does not have. The `visited // genAttrs fresh` below
  # copies the whole visited set once per level, so the walk is Θ(levels × |visited|):
  # quadratic on a deep cone (a chain, in-degree 1, is the witness) however bounded the
  # in-degree, where `genericClosure` accumulates natively and stays flat.
  dependentsFrontier =
    { edges, nodes, ... }:
    targetId: prune:
    let
      reverseIndex = _reverseIndex { inherit edges nodes; };
      revOf = id: reverseIndex.${id} or [ ];
      go =
        visited: frontier:
        if frontier == [ ] then
          visited
        else
          let
            expandable = builtins.filter prune frontier;
            neighbours = prelude.unique (prelude.concatMap revOf expandable);
            fresh = builtins.filter (id: !(visited ? ${id})) neighbours;
          in
          go (visited // prelude.genAttrs fresh (_: true)) fresh;
      seed0 = if prune targetId then prelude.unique (revOf targetId) else [ ];
      reached = go (prelude.genAttrs seed0 (_: true)) seed0;
    in
    builtins.sort builtins.lessThan (builtins.filter (id: id != targetId) (builtins.attrNames reached));

  # Reverse all edge directions, return new accessor set. Mokhov 2017 §5.2 Graph
  # Transpose: transpose flips the arguments of `connect` and leaves `overlay`
  # unchanged — direction is reversed, not erased.
  transpose =
    { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
      rev = _transposeMat mat;
    in
    {
      edges = id: rev.${id} or [ ];
      inherit nodes;
    };

  # Co-SCC predicate: are u and v in the same strongly connected component? canReach-backed
  # and single-pair, but each probe materializes its start's closure in full; only the
  # whole-graph closure is avoided. u == v handles an acyclic node, which cannot reach itself.
  coScc =
    { edges, ... }:
    u: v:
    (u == v) || (traverse.canReach { inherit edges; } u v && traverse.canReach { inherit edges; } v u);

  # ── PARTITION ARM: THE CLOSURE CONSTRUCTION, PUBLISHED BY NAME ──
  # An arm of the partition front door (`condensation`, `lib/partition.nix`), not the door:
  # u and v are co-SCC iff each reaches the other, decided here by materializing the whole
  # transitive closure and asking it. The door is an unconditional alias for the
  # forward–backward arm (`condensation = fbNode`, `lib/partition.nix`) instead;
  # a caller whose correctness depends on THIS construction answering binds this name.
  # Not Tarjan's linear O(V+E) single-DFS — its mutable stack/lowlink is out-of-substrate
  # for pure Nix.
  #
  # COST is the CLOSURE-CLASS cost shared with `dependents`/`transitiveReduction` —
  # SUPER-QUADRATIC and shape-dependent, not O(n²). The closure callers measure as ONE
  # curve on `list.elements`, so do not quote a figure here that the siblings do not carry:
  # `ci/bench/cost-classes.nix`. `transitiveReduction` leaves that curve on graphs whose
  # every node has out-degree <= 1, where its shared closure is never forced (README's
  # note); the closure below is always forced, so no such carve-out applies here.
  #
  # ★ AND IT HAS A REAL CEILING THE OTHER ARMS DO NOT: the closure is a CAPPED fixpoint, so
  # it returns iff the fixpoint's iteration cap is at least the graph's diameter and throws
  # otherwise. The throw names THIS surface and the diameter it could not reach, which it may
  # because the closure's step is monotone on the subset order by construction and so has no
  # other way to reach the cap (`fixpoint.nix`, `closureOf`). The ceiling itself is unchanged
  # and is the standing difference between this arm and the forward–backward pair, which is
  # why the door does not default here.
  #
  # ★ THIS ARM COMPUTES A TAG MAP AND NOTHING ELSE. Everything past it — the member lists,
  # the quotient's edges, `bottomUp` and `depth` — is the SHARED FINISHER's, called here by
  # name (`partition.condensationOf`). That is what makes "every arm returns the same record"
  # a property of the CONSTRUCTION rather than of the cells that check it: an arm that
  # finished its own record would agree with its siblings only for as long as someone kept
  # three copies in step. The closure this arm is named for is spent on the PARTITION; a
  # second closure over the quotient is not needed to order it, and it would put the capped
  # fixpoint's ceiling on the result of every arm rather than on this one.
  # (Tarjan 1972 / Kosaraju for SCCs; Mokhov 2017 §4.6 Preorders and Equivalence Relations
  # for the quotient-graph idiom — a condensation is the quotient by the co-SCC equivalence.)
  condensationClosure =
    args@{ edges, nodes, ... }:
    let
      # The closure class by name (`fixpoint.nix`, `closureOf`): the ceiling below is this
      # arm's, and its refusal says so.
      closure = fp.closureOf "condensationClosure" args;
      # O(1) membership (mirrors transitiveReduction's closureSets) → O(n²), not O(n³).
      closSets = prelude.mapAttrs (_: ts: prelude.genAttrs ts (_: true)) closure;
      reaches = u: v: (closSets.${u} or { }) ? ${v};
      # A cyclic node's closure includes itself; an acyclic node's does not, so the
      # u == v case is required to make every node co-SCC with itself.
      coSccPair = u: v: (u == v) || (reaches u v && reaches v u);
      repOf = prelude.genAttrs nodes (
        n: builtins.head (builtins.sort builtins.lessThan (builtins.filter (m: coSccPair n m) nodes))
      );
    in
    partition.condensationOf { inherit edges nodes; } repOf;

  # One representative simple cycle per cyclic component, as an ORDERED node list rotated to
  # begin at the component's smallest key. Acyclic input => [ ].
  #
  # `cycles` above answers WHICH nodes lie on a cycle; it is a membership set, and a caller that
  # renders it as a traversal states edges the graph does not contain. `cyclePaths` answers the
  # ordered question: it returns a walk in which every consecutive pair IS an edge, closing back
  # on its head.
  #
  # ONE per component, not all: the strongly connected component is the canonical object (Tarjan
  # 1972 / Kosaraju — the partition `condensation` above already anchors), while the cycle through
  # it is existential. Enumerating every simple cycle is Johnson 1975, whose output is itself
  # exponential in the graph; it is deliberately not provided here.
  #
  # COST: `cycles` short-circuits an acyclic graph before any path work, so the ordinary case pays
  # the self-reachability pass and nothing more — but that pass IS `cycles`, so it carries `cycles`'
  # shape dependence: Θ(n + E) to read the accessor once, then O(n × reachable) where out-degree is
  # bounded and Θ(n²) on a complete DAG. This surface builds no closure of its own, so the accessor
  # hoist reaches it only through `cycles` and the partition arm; it neither makes that decision nor
  # can it observe one they did not make.
  # Reconstruction — the per-node forward–backward partition arm plus `pathsBetween`, which
  # enumerates simple paths and is worst-case exponential — runs only once the graph is
  # KNOWN cyclic, i.e. only on the branch a caller refuses on. Same discipline `order.nix` states
  # for its own cycle report: the expensive analysis is on the way out.
  cyclePaths =
    { edges, nodes, ... }:
    let
      cyclic = cycles { inherit edges nodes; };
    in
    if cyclic == [ ] then
      [ ]
    else
      let
        # The partition ARM by name, never the door: this consumer needs the tag map and
        # nothing else, and binding a door would make its answer depend on a default it has
        # no stake in.
        inherit ((partition.fbNode { inherit edges nodes; })) sccOf;
        # The component's smallest key is the ENTRY POINT, so the head of the returned walk is
        # order-independent. The REST of the walk is not: it follows the order of `edges u` and
        # of `pathsBetween`'s enumeration, so a component holding several simple cycles can yield
        # a different representative under a permuted successor list over the SAME edge set.
        # Deterministic for a given accessor, but not a function of the node set alone — a caller
        # wanting a witness stable across accessor permutations cannot pin this walk.
        repCycle =
          members:
          let
            u = builtins.head (builtins.sort builtins.lessThan members);
            # u is self-reachable, so at least one in-component successor has a path home.
            back = builtins.filter (p: p != [ ]) (
              map (
                v:
                let
                  ps = traverse.pathsBetween { inherit edges; } v u;
                in
                if ps == [ ] then [ ] else builtins.head ps
              ) (builtins.filter (v: sccOf.${v} == sccOf.${u}) (edges u))
            );
          in
          # `back`'s paths end AT u; dropping that last element closes the walk without
          # repeating the head. A self-loop leaves [ u ].
          [ u ] ++ (if back == [ ] then [ ] else prelude.init (builtins.head back));
      in
      map repCycle (prelude.mapAttrsToList (_: g: g) (builtins.groupBy (k: sccOf.${k}) cyclic));

  # Impact analysis alias (uses efficient single-target path).
  impactOf = dependentsOf;

  # `coneRank` used to live here. It is an ORDERING surface — it emits an order, and it now
  # takes its warming order from the ordering arm by name — so it lives with the ordering
  # family in `lib/order.nix`. The export set is unchanged: `lib/default.nix` merges both.

  # DIRECT reverse-adjacency (full map) — the public face of _reverseIndex.
  # DIRECT (immediate dependents), in contrast to dependentsOf's TRANSITIVE closure.
  directDependents = { edges, nodes, ... }: _reverseIndex { inherit edges nodes; };
  directDependentsOf = accessor: id: (directDependents accessor).${id} or [ ];
in
{
  inherit
    cycles
    cyclePaths
    dependents
    dependentsOf
    dependentsFrontier
    transpose
    impactOf
    condensationClosure
    coScc
    directDependents
    directDependentsOf
    ;
}
