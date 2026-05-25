{ lib }:
let
  edgeMaps = import ./edge-maps.nix { inherit lib; };
  fp = import ./fixpoint.nix { inherit lib; };

  # Transpose a materialized edge map: reverse all edges
  _transposeMat = mat:
    builtins.foldl' (acc: from:
      builtins.foldl' (acc2: to:
        acc2 // { ${to} = (acc2.${to} or []) ++ [from]; }
      ) acc (mat.${from} or [])
    ) {} (builtins.attrNames mat);

  cycles = { edges, nodes, ... }:
    let
      closure = fp.transitiveClosure { inherit edges nodes; };
      # Convert each node's closure targets to attrset for O(1) self-membership check
      closureSets = lib.genAttrs nodes (id:
        builtins.listToAttrs (map (t: { name = t; value = true; }) (closure.${id} or []))
      );
    in builtins.sort builtins.lessThan (
      builtins.filter (id: closureSets.${id} ? ${id}) nodes
    );

  dependents = { edges, nodes, ... }: targetId:
    let
      closure = fp.transitiveClosure { inherit edges nodes; };
      reversed = _transposeMat closure;
    in builtins.sort builtins.lessThan (
      builtins.filter (id: id != targetId) (reversed.${targetId} or [])
    );

  transpose = { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
      rev = _transposeMat mat;
    in {
      edges = id: rev.${id} or [];
      inherit nodes;
    };

  impactOf = dependents;
in
{
  inherit cycles dependents transpose impactOf;
}
