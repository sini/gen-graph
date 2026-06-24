# Global graph analysis — operations requiring full graph knowledge.
#
# cycles: standard cycle detection (a node is in a cycle iff reachable from
#   itself). Uses genericClosure per-node for C-level BFS.
# dependents/dependentsOf: Arntzenius 2016 (Datafun reverse reachability).
#   dependents uses full transitive closure (amortized for multi-target).
#   dependentsOf uses reverse traversal (O(reachable) for single-target).
# transpose: Mokhov 2017 §4.3 (algebraic graph transpose operation).
{ lib }:
let
  edgeMaps = import ./edge-maps.nix { inherit lib; };
  fp = import ./fixpoint.nix { inherit lib; };
  traverse = import ./traverse.nix { inherit lib; };

  # Shared O(E) reverse-edge index (consumer->producer reversed): id -> [ids that read id].
  # Extracted from dependentsOf so dependentsFrontier (S3) reuses it. groupBy, not foldl'+//.
  _reverseIndex =
    { edges, nodes, ... }:
    let
      allEdges = lib.concatMap (
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
      allEdges = lib.concatMap (
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

  # S3: reverse-reachability cone of targetId, walked level-by-level, descending
  # into a node's dependents only when prune node == true. A prune==false node is
  # INCLUDED (reached) but not expanded — the early-cutoff stop. genericClosure
  # cannot include-but-not-expand, so this is a hand-rolled BFS with a visited
  # attrset (cycle guard: each id enters the frontier <= once). Reduces to
  # dependentsOf when prune = _: true. (Spec 2026-06-23-gen-rebuild-v2-design §5.P0.)
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
            neighbours = lib.unique (lib.concatMap revOf expandable);
            fresh = builtins.filter (id: !(visited ? ${id})) neighbours;
          in
          go (visited // lib.genAttrs fresh (_: true)) fresh;
      seed0 = if prune targetId then lib.unique (revOf targetId) else [ ];
      reached = go (lib.genAttrs seed0 (_: true)) seed0;
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

  # coScc: thin co-SCC predicate (canReach-backed, single-pair, no full closure).
  coScc =
    { edges, ... }:
    u: v:
    (u == v) || (traverse.canReach { inherit edges; } u v && traverse.canReach { inherit edges; } v u);

  # condensation: SCC partition + condensation (quotient) graph, closure-based O(n^2)
  # (u,v co-SCC iff each reaches the other via transitiveClosure) — NOT Tarjan's
  # linear O(V+E) single-DFS (mutable stack/lowlink, out-of-substrate for pure Nix).
  # bottomUp is producers-first (consumer->producer reverse-topo): solve a super-node
  # only after every super-node it depends on. reps == bottomUp; sccs == map members reps.
  # (Spec 2026-06-23-gen-rebuild-v2-design §5.P0; Tarjan 1972 / Kosaraju, Mokhov 2017 idiom.)
  condensation =
    { edges, nodes, ... }:
    let
      closure = fp.transitiveClosure { inherit edges nodes; };
      # O(1) membership (mirrors transitiveReduction's closureSets) -> O(n^2), not O(n^3).
      closSets = lib.mapAttrs (_: ts: lib.genAttrs ts (_: true)) closure;
      reaches = u: v: (closSets.${u} or { }) ? ${v};
      # CYCLIC node's closure includes itself; ACYCLIC node's does NOT -> (u == v) mandatory.
      coSccPair = u: v: (u == v) || (reaches u v && reaches v u);
      repOf = lib.genAttrs nodes (
        n: builtins.head (builtins.sort builtins.lessThan (builtins.filter (m: coSccPair n m) nodes))
      );
      # reps0: the UNORDERED set of SCC tags — input to the bottom-up sort below,
      # NOT the output order. The output order is `bottomUp`, and `reps = bottomUp`.
      reps0 = lib.unique (map (n: repOf.${n}) nodes);
      membersOf = lib.mapAttrs (_: ns: builtins.sort builtins.lessThan (map (e: e.n) ns)) (
        builtins.groupBy (e: e.r) (
          map (n: {
            r = repOf.${n};
            n = n;
          }) nodes
        )
      );
      condEdgesOf =
        r:
        lib.unique (
          builtins.filter (rb: rb != r) (
            map (t: repOf.${t}) (lib.concatMap (m: edges m) (membersOf.${r} or [ ]))
          )
        );
      # Bottom-up: a SECOND closure over the condensation, sort by closure-cardinality
      # ASCENDING (producers have smaller closures), name tie-break. No hand-rolled DFS.
      condMat = lib.genAttrs reps0 (r: condEdgesOf r);
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
    ;
}
