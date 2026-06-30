{ prelude }:
let
  edgeMaps = import ./edge-maps.nix { inherit prelude; };

  countEdges =
    m: builtins.foldl' (acc: from: acc + builtins.length (m.${from} or [ ])) 0 (builtins.attrNames m);

  fixpoint =
    {
      seed,
      step,
      maxIter ? 1000,
    }:
    let
      go =
        iter: current:
        if iter >= maxIter then
          throw "gen-graph: fixpoint exceeded ${toString maxIter} iterations"
        else
          let
            next = step current;
            currentSize = countEdges current;
            nextSize = countEdges next;
          in
          if nextSize < currentSize then
            throw "gen-graph: fixpoint step is not monotonic (${toString currentSize} → ${toString nextSize})"
          else if next == current then
            current
          else
            go (iter + 1) next;
    in
    go 0 seed;

  # Semi-naive delta-frontier fixpoint: `step dF acc` sees only the current frontier
  # `dF`, not the whole accumulator (the semi-naive saving over `fixpoint`, which
  # re-steps the whole map each iteration). Converges when the frontier empties.
  # No monotonicity guard — union-accumulation cannot shrink the result.
  # (Arntzenius 2016 §9, semi-naive evaluation.)
  seededFixpoint =
    {
      seed,
      frontier,
      step,
      maxIter ? 1000,
    }:
    let
      go =
        iter: acc: dF:
        if iter >= maxIter then
          throw "gen-graph: seededFixpoint exceeded ${toString maxIter} iterations"
        else if countEdges dF == 0 then
          acc
        else
          let
            produced = step dF acc;
            acc' = edgeMaps.unionEdges acc produced;
            dF' = edgeMaps.differenceEdges produced acc;
          in
          go (iter + 1) acc' dF';
    in
    go 0 (edgeMaps.unionEdges seed frontier) frontier;

  compose =
    e1: e2:
    prelude.mapAttrs (
      _from: targets: prelude.unique (prelude.concatMap (mid: e2.${mid} or [ ]) targets)
    ) e1;

  transitiveClosure =
    { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
    in
    fixpoint {
      seed = mat;
      step = current: edgeMaps.unionEdges current (compose current mat);
    };

  transitiveReduction =
    { edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
      closure = transitiveClosure { inherit edges nodes; };
      redundant = prelude.mapAttrs (
        _from: targets:
        let
          # Pre-convert closure lists to attrsets for O(1) membership
          closureSets = prelude.genAttrs targets (
            mid:
            builtins.listToAttrs (
              map (t: {
                name = t;
                value = true;
              }) (closure.${mid} or [ ])
            )
          );
        in
        builtins.filter (
          to: builtins.any (mid: mid != to && (closureSets.${mid} or { }) ? ${to}) targets
        ) targets
      ) mat;
    in
    edgeMaps.differenceEdges mat redundant;
in
{
  inherit
    fixpoint
    seededFixpoint
    compose
    transitiveClosure
    transitiveReduction
    ;
}
