# Global graph analysis — operations requiring full graph knowledge.
#
# cycles: Vogt 1989 (well-definedness requires termination — cycle detection
#   ensures finite expansion). Uses genericClosure per-node for C-level BFS.
# dependents/dependentsOf: Arntzenius 2016 (Datafun reverse reachability).
#   dependents uses full transitive closure (amortized for multi-target).
#   dependentsOf uses reverse traversal (O(reachable) for single-target).
# transpose: Mokhov 2017 §4.3 (algebraic graph transpose operation).
{ lib }:
let
  edgeMaps = import ./edge-maps.nix { inherit lib; };
  fp = import ./fixpoint.nix { inherit lib; };
  traverse = import ./traverse.nix { inherit lib; };

  # Transpose a materialized edge map: reverse all edges.
  # O(E) where E = total edges. Each // creates a new attrset.
  _transposeMat = mat:
    builtins.foldl' (acc: from:
      builtins.foldl' (acc2: to:
        acc2 // { ${to} = (acc2.${to} or []) ++ [from]; }
      ) acc (mat.${from} or [])
    ) {} (builtins.attrNames mat);

  # Nodes in any cycle (self-reachable).
  # Uses genericClosure per-node (C-level BFS) — no full closure materialization.
  # O(n × reachable) with C-level inner loop. Correct per Vogt 1989 Lemma 3.2.
  cycles = { edges, nodes, ... }:
    builtins.sort builtins.lessThan (
      builtins.filter (traverse.selfReachable { inherit edges; }) nodes
    );

  # Reverse reachability: who can reach targetId?
  # Uses full transitive closure + transpose. O(n²) setup, O(1) lookup.
  # Amortized: if querying multiple targets, compute once and reuse.
  # For single-target queries, prefer `dependentsOf`.
  dependents = { edges, nodes, ... }: targetId:
    let
      closure = fp.transitiveClosure { inherit edges nodes; };
      reversed = _transposeMat closure;
    in builtins.sort builtins.lessThan (
      builtins.filter (id: id != targetId) (reversed.${targetId} or [])
    );

  # Single-target reverse reachability via reverse traversal (Arntzenius 2016).
  # O(n) to build reverse index + O(reachable in reverse) C-level BFS.
  # Much faster than `dependents` for single-target queries on large graphs.
  dependentsOf = { edges, nodes, ... }: targetId:
    let
      # Build reverse edge accessor: O(n) — iterates all nodes once
      reverseIndex = builtins.foldl' (acc: from:
        builtins.foldl' (acc2: to:
          acc2 // { ${to} = (acc2.${to} or []) ++ [from]; }
        ) acc (edges from)
      ) {} nodes;
      revEdges = id: reverseIndex.${id} or [];
    in
    # Traverse reversed graph from target — C-level BFS via genericClosure
    builtins.sort builtins.lessThan (traverse.reachableFrom { edges = revEdges; } targetId);

  # Reverse all edge directions, return new accessor set (Mokhov 2017 §4.3).
  transpose = { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
      rev = _transposeMat mat;
    in {
      edges = id: rev.${id} or [];
      inherit nodes;
    };

  # Impact analysis alias (uses efficient single-target path).
  impactOf = dependentsOf;
in
{
  inherit cycles dependents dependentsOf transpose impactOf;
}
