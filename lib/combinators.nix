# Monotonic query combinators (Arntzenius & Krishnaswami 2016).
{ lib, sets }:
{
  select = nodeSet: pred:
    lib.filterAttrs (_: pred) nodeSet;

  selectEdges = edgeSet: pred:
    let
      filtered = lib.mapAttrs (_from: targets:
        lib.filterAttrs (_to: pred) targets
      ) edgeSet;
    in
    lib.filterAttrs (_: targets: targets != {}) filtered;

  compose = edges1: edges2:
    builtins.foldl' (acc: from:
      let
        targets1 = edges1.${from};
        composed = builtins.foldl' (acc2: mid:
          let midTargets = edges2.${mid} or {};
          in builtins.foldl' (acc3: to:
            let existing = acc3.${from} or {}; in
            acc3 // { ${from} = existing // { ${to} = {
              inherit from to; label = "composed";
            }; }; }
          ) acc2 (builtins.attrNames midTargets)
        ) acc (builtins.attrNames targets1);
      in composed
    ) {} (builtins.attrNames edges1);

  fixpoint = { seed, step, maxIter ? 1000 }:
    let
      go = iter: current:
        let
          next = step current;
          currentKeys = builtins.length (builtins.attrNames current);
          nextKeys = builtins.length (builtins.attrNames next);
        in
        if iter >= maxIter then
          throw "gen-graph: fixpoint exceeded maxIter (${toString maxIter})"
        else if nextKeys < currentKeys then
          throw "gen-graph: fixpoint step is not monotonic — result set shrank from ${toString currentKeys} to ${toString nextKeys} top-level keys"
        else if next == current then
          current
        else
          go (iter + 1) next;
    in go 0 seed;
}
