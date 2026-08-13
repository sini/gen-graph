{ prelude }:
let
  edgeMaps = import ./edge-maps.nix { inherit prelude; };

  countEdges =
    m: builtins.foldl' (acc: from: acc + builtins.length (m.${from} or [ ])) 0 (builtins.attrNames m);

  # ── THE REFUSAL A CAP-EXHAUSTED FIXPOINT RAISES, AND WHY THERE ARE TWO OF THEM ──
  #
  # Stopping at the cap, this binding has observed exactly two things: the cap was reached,
  # and the step never shrank the accumulator. WHAT THAT MEANS IS NOT OBSERVABLE HERE, because
  # `step` is the caller's. Two unrelated constructions land in this state — a monotone step
  # whose ascending chain is longer than the cap, and a step that oscillates without changing
  # cardinality, which the size guard below cannot see because cardinality is not the subset
  # order. So the generic message states the observation and names neither cause; a message
  # that picked one would tell every caller with an oscillating step that their graph is deep.
  #
  # A caller whose `step` is FIXED can read the cap for what it means and passes that reading
  # as `refusal`. `closureOf` is the one such caller here.
  capReached =
    maxIter:
    "gen-graph: fixpoint exceeded ${toString maxIter} iterations: the step neither converged nor shrank. `step` is the caller's, so this binding reports what it observed and names no cause.";

  fixpoint =
    {
      seed,
      step,
      maxIter ? 1000,
      refusal ? capReached,
    }:
    let
      go =
        iter: current:
        if iter >= maxIter then
          throw (refusal maxIter)
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

  # ── THE CLOSURE CLASS, ENUMERATED ──
  #
  # `transitiveClosure`, `dependents`, `condensationClosure` and `transitiveReduction` each
  # make one closure call, so they share one cost curve, one ceiling and one refusal, and a
  # remedy applied to one of them leaves three surfaces refusing the old way. The ENUMERATION
  # is the artefact rather than its size: a fifth closure caller is the failure a count of
  # four cannot see. `closureOf` refuses a surface that is not on this list, so a refusal can
  # never name a surface the library does not have.
  closureClass = [
    "transitiveClosure"
    "dependents"
    "condensationClosure"
    "transitiveReduction"
  ];

  # THE CLOSURE'S REFUSAL NAMES ITS CAUSE, AND THIS IS THE ONLY BINDING THAT MAY.
  #
  # `step` below is not the caller's: it is built from `unionEdges`, which is
  # `genAttrs allKeys (k: unique ((a.k or [ ]) ++ (b.k or [ ])))` (`edge-maps.nix`), so
  # `current ⊆ step current` per key and the key set only grows. The step is monotone on the
  # SUBSET order, not merely on cardinality, so the oscillating mode the generic message must
  # stay silent about cannot arise here. A monotone map on a finite lattice reaches the cap
  # only along an ascending chain that has not converged, and for reachability the height of
  # that chain IS the graph's diameter — leaving depth as the only remaining cause, which is
  # what makes naming it admissible. (Tarski 1955 for the least fixed point of a monotone map
  # on a complete lattice; the ascending-chain construction that reaches it is Kleene's.)
  #
  # ★ The READING is this binding's and the CAP is `fixpoint`'s. `refusal` receives the cap
  # that was exhausted and converts it to a diameter here, so a cheaper iteration schedule —
  # repeated squaring reaches diameter 2^rounds rather than rounds — changes the conversion at
  # this one site and at no caller. Same discipline as the shared finisher in `partition.nix`:
  # agreement by construction rather than four copies kept in step.
  closureOf =
    surface:
    assert builtins.elem surface closureClass;
    args@{ edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
    in
    fixpoint (
      # `maxIter` rides on the caller's own record when they set one; absent, `fixpoint`'s
      # default applies. The cap is `fixpoint`'s and is deliberately not re-declared here —
      # a closure surface holding its own copy of the constant is a copy to keep in step.
      builtins.intersectAttrs { maxIter = null; } args
      // {
        seed = mat;
        step = current: edgeMaps.unionEdges current (compose current mat);
        refusal =
          cap:
          "gen-graph: ${surface}: the graph's reachability diameter exceeds ${toString cap}, the closure fixpoint's iteration cap. The closure step is monotone on the subset order by construction, so an unconverged closure at the cap is depth and nothing else.";
      }
    );

  transitiveClosure = closureOf "transitiveClosure";

  transitiveReduction =
    args@{ edges, nodes, ... }:
    let
      mat = edgeMaps.materialize { inherit edges nodes; };
      closure = closureOf "transitiveReduction" args;
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
    closureClass
    closureOf
    transitiveClosure
    transitiveReduction
    ;
}
