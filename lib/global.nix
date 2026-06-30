# Global graph analysis — operations requiring full graph knowledge.
#
# cycles: standard cycle detection (a node is in a cycle iff reachable from
#   itself). Uses genericClosure per-node for C-level BFS.
# dependents/dependentsOf: Arntzenius 2016 (Datafun reverse reachability).
#   dependents uses full transitive closure (amortized for multi-target).
#   dependentsOf uses reverse traversal (O(reachable) for single-target).
# transpose: Mokhov 2017 §4.3 (algebraic graph transpose operation).
{ prelude }:
let
  edgeMaps = import ./edge-maps.nix { inherit prelude; };
  fp = import ./fixpoint.nix { inherit prelude; };
  traverse = import ./traverse.nix;

  # Shared reverse-edge index: id -> [ids with an edge to id].
  # Extracted from dependentsOf so dependentsFrontier reuses it.
  # O(E) via groupBy instead of O(E²) via foldl'+//.
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
  # O(E) via groupBy instead of O(E²) via foldl'+//.
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
  # reachable from itself. Standard cycle detection.
  # Uses genericClosure per-node (C-level BFS) — no full closure materialization.
  # O(n × reachable) with C-level inner loop.
  cycles =
    { edges, nodes, ... }:
    builtins.sort builtins.lessThan (builtins.filter (traverse.selfReachable { inherit edges; }) nodes);

  # Reverse reachability: who can reach targetId?
  # Uses full transitive closure + transpose. O(n²) setup, O(1) lookup.
  # Amortized: if querying multiple targets, compute once and reuse.
  # For single-target queries, prefer `dependentsOf`.
  dependents =
    { edges, nodes, ... }:
    targetId:
    let
      closure = fp.transitiveClosure { inherit edges nodes; };
      reversed = _transposeMat closure;
    in
    builtins.sort builtins.lessThan (
      builtins.filter (id: id != targetId) (reversed.${targetId} or [ ])
    );

  # Single-target reverse reachability via reverse traversal (Arntzenius 2016).
  # O(n) to build reverse index + O(reachable in reverse) C-level BFS.
  # Much faster than `dependents` for single-target queries on large graphs.
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

  # Reverse all edge directions, return new accessor set (Mokhov 2017 §4.3).
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

  # Co-SCC predicate: are u and v in the same strongly connected component?
  # canReach-backed, single-pair (no full closure). The u == v case handles an
  # acyclic node, which cannot reach itself.
  coScc =
    { edges, ... }:
    u: v:
    (u == v) || (traverse.canReach { inherit edges; } u v && traverse.canReach { inherit edges; } v u);

  # SCC partition + condensation (quotient) graph, closure-based O(n²): u and v are
  # co-SCC iff each reaches the other via transitiveClosure. Not Tarjan's linear
  # O(V+E) single-DFS — its mutable stack/lowlink is out-of-substrate for pure Nix.
  # `bottomUp` lists each SCC after every SCC it points to (a reverse-topological
  # order over the condensation DAG); `reps == bottomUp`, `sccs == map members reps`.
  # (Tarjan 1972 / Kosaraju for SCCs; Mokhov 2017 §4 for the quotient-graph idiom.)
  condensation =
    { edges, nodes, ... }:
    let
      closure = fp.transitiveClosure { inherit edges nodes; };
      # O(1) membership (mirrors transitiveReduction's closureSets) → O(n²), not O(n³).
      closSets = prelude.mapAttrs (_: ts: prelude.genAttrs ts (_: true)) closure;
      reaches = u: v: (closSets.${u} or { }) ? ${v};
      # A cyclic node's closure includes itself; an acyclic node's does not, so the
      # u == v case is required to make every node co-SCC with itself.
      coSccPair = u: v: (u == v) || (reaches u v && reaches v u);
      repOf = prelude.genAttrs nodes (
        n: builtins.head (builtins.sort builtins.lessThan (builtins.filter (m: coSccPair n m) nodes))
      );
      # reps0: the unordered set of SCC tags — input to the bottom-up sort below,
      # not the output order. The output order is `bottomUp`, and `reps = bottomUp`.
      reps0 = prelude.unique (map (n: repOf.${n}) nodes);
      membersOf = prelude.mapAttrs (_: ns: builtins.sort builtins.lessThan (map (e: e.n) ns)) (
        builtins.groupBy (e: e.r) (
          map (n: {
            r = repOf.${n};
            n = n;
          }) nodes
        )
      );
      condEdgesOf =
        r:
        prelude.unique (
          builtins.filter (rb: rb != r) (
            map (t: repOf.${t}) (prelude.concatMap (m: edges m) (membersOf.${r} or [ ]))
          )
        );
      # Bottom-up: a second closure, over the condensation, sorted by closure
      # cardinality ascending (a node that points to fewer SCCs has a smaller
      # closure, so it sorts earlier), with a name tie-break. No hand-rolled DFS.
      condMat = prelude.genAttrs reps0 (r: condEdgesOf r);
      condClosure = fp.transitiveClosure {
        edges = id: condMat.${id} or [ ];
        nodes = reps0;
      };
      depthOf = r: builtins.length (condClosure.${r} or [ ]);
      bottomUp = builtins.sort (
        ra: rb:
        let
          da = depthOf ra;
          db = depthOf rb;
        in
        if da == db then ra < rb else da < db
      ) reps0;
      reps = bottomUp;
      members = tag: membersOf.${tag} or [ ];
    in
    {
      inherit reps bottomUp members;
      sccs = map (r: members r) reps;
      sccOf = id: repOf.${id} or id;
      condEdges = condEdgesOf;
    };

  # Impact analysis alias (uses efficient single-target path).
  impactOf = dependentsOf;

  # Cone-local producers-first rank: depth id = 1 + max(depth of in-cone producers).
  # O(|cone| + edges_in_cone) via prelude.fix memoization; NOT whole-graph condensation.
  # RTD 1983 topological enumeration restricted to a dependent cone.
  # Precondition: `cone` is acyclic (a data-change dependent cone is). A cyclic cone
  # makes the prelude.fix recurrence self-referential → uncatchable infinite recursion.
  coneRank =
    accessor: cone:
    let
      coneSet = prelude.genAttrs cone (_: true);
      inConeProducers = id: builtins.filter (d: coneSet ? ${d}) (accessor.edges id);
      # prelude.fix binds `depth` once, so each node's depth is forced at most once
      # (a plain recursive `let` would re-expand shared producers, blowing up to
      # exponential) — this is what delivers the O(|cone| + edges_in_cone) bound.
      depth = prelude.fix (
        d:
        prelude.genAttrs cone (
          id:
          let
            ps = inConeProducers id;
          in
          if ps == [ ] then 0 else 1 + prelude.foldl' (m: p: prelude.max m d.${p}) 0 ps
        )
      );
      order = builtins.sort (
        a: b: if depth.${a} == depth.${b} then a < b else depth.${a} < depth.${b}
      ) cone;
    in
    {
      inherit order depth;
    };

  # DIRECT reverse-adjacency (full map) — the public face of _reverseIndex.
  # DIRECT (immediate dependents), in contrast to dependentsOf's TRANSITIVE closure.
  directDependents = { edges, nodes, ... }: _reverseIndex { inherit edges nodes; };
  directDependentsOf = accessor: id: (directDependents accessor).${id} or [ ];
in
{
  inherit
    cycles
    dependents
    dependentsOf
    dependentsFrontier
    transpose
    impactOf
    condensation
    coScc
    coneRank
    directDependents
    directDependentsOf
    ;
}
