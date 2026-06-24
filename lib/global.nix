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
    ;
}
