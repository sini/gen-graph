{ lib }:
let
  edgeMaps = import ./edge-maps.nix { inherit lib; };

  countEdges = m:
    builtins.foldl' (acc: from:
      acc + builtins.length (m.${from} or [])
    ) 0 (builtins.attrNames m);

  fixpoint = { seed, step, maxIter ? 1000 }:
    let
      go = iter: current:
        if iter >= maxIter then
          throw "gen-graph: fixpoint exceeded ${toString maxIter} iterations"
        else let
          next = step current;
          currentSize = countEdges current;
          nextSize = countEdges next;
        in
        if nextSize < currentSize then
          throw "gen-graph: fixpoint step is not monotonic (${toString currentSize} → ${toString nextSize})"
        else if next == current then current
        else go (iter + 1) next;
    in go 0 seed;

  compose = e1: e2:
    lib.mapAttrs (_from: targets:
      lib.unique (lib.concatMap (mid: e2.${mid} or []) targets)
    ) e1;

  transitiveClosure = { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
    in fixpoint {
      seed = mat;
      step = current: edgeMaps.unionEdges current (compose current mat);
    };

  transitiveReduction = { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
      closure = transitiveClosure { inherit edges nodes; };
      redundant = lib.mapAttrs (_from: targets:
        let
          # Pre-convert closure lists to attrsets for O(1) membership
          closureSets = lib.genAttrs targets (mid:
            builtins.listToAttrs (map (t: { name = t; value = true; }) (closure.${mid} or []))
          );
        in
        builtins.filter (to:
          builtins.any (mid:
            mid != to && (closureSets.${mid} or {}) ? ${to}
          ) targets
        ) targets
      ) mat;
    in edgeMaps.differenceEdges mat redundant;
in
{
  inherit fixpoint compose transitiveClosure transitiveReduction;
}
