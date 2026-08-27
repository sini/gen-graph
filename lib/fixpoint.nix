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
  #
  # ── THE CONVERGENCE CHECK, AND WHY IT IS NOT THE SUBSET GUARD ──
  #
  # This line used to read "No monotonicity guard — union-accumulation cannot shrink the
  # result", published as the reason none was needed. THE SENTENCE IS TRUE ABOUT THE
  # ACCUMULATOR AND SAYS NOTHING ABOUT THE CONTENT. A subset predicate is VACUOUS here —
  # `unionEdges` cannot shrink, so it holds no matter what `step` concluded or why. What
  # union cannot do is RETRACT: a conclusion drawn while a fact was absent stays in the
  # result after that fact arrives, and the run then converges on an accumulation the
  # converged graph does not support. Terminating, well-formed, wrong, with nothing
  # reporting.
  #
  # ★ FINITENESS BUYS NOTHING AGAINST IT. Finite height bounds CHAINS, and a chain is what
  # monotonicity produces; drop monotonicity and the iterates are an arbitrary WALK, which
  # in a finite carrier OSCILLATES rather than diverges. The failure is not non-termination
  # that a cap could catch — it is a clean convergence carrying an unsupported conclusion.
  #
  # THE CHECK: at convergence, every conclusion must be an axiom (`seed ∪ frontier`) or be
  # RE-DERIVED by `step` from the converged accumulator — `acc ⊆ base ∪ step acc acc`. That
  # is ONE-STEP SUPPORT, and it is one full application of the caller's own rules against
  # the final graph. For a `step` monotone in BOTH arguments it cannot fire: every round saw
  # inputs contained in the converged accumulator, so everything it produced is produced
  # again. It fires exactly on a conclusion that the converged graph withdraws.
  #
  # ★★ THE RESIDUAL CLASS, WHICH IS THE SAME DEFECT CLASS ONE LAYER IN. SUPPORT IS STRICTLY
  # WEAKER THAN FOUNDEDNESS, SO PASSING THIS CHECK IS NOT EVIDENCE THAT `step` IS MONOTONE.
  # A conclusion drawn on an absence that later acquires a CIRCULAR re-derivation is
  # supported, and is returned: `p :- not r. p :- p. r :- a` has a measurably non-monotone
  # step (`step {a}` yields `p`, `step {a,r}` does not), is NOT refused, and returns `p` —
  # which the well-founded model makes FALSE. That is the supported-model / founded-model
  # gap. Closing it is ADR-0020's WELL-FOUNDED ENGINE, which that ADR puts in Phase-C den
  # territory — but NOTHING NEED WAIT ON PHASE C: `gen-scope` ships one today
  # (`wellFoundedModel`, its `lib/engine.nix`), so a caller needing foundedness runs it ONE
  # LAYER UP. It is unreachable from HERE by layering rather than by absence — gen-scope's
  # flake takes `gen-graph` as an input, so consuming it would invert the dependency.
  # The ceiling is INSTRUMENTED rather than merely described:
  # `test-seeded-circular-rederivation-is-supported-and-RETURNED` asserts the wrong answer
  # is RETURNED, so the day this starts refusing it, a cell says so.
  #
  # ★ WHICH CRITERION ADR-0020 SUPPLIES, STATED SO THIS IS NOT READ AS IMPLEMENTING IT: its
  # refusal oracle is STABLE-MODEL EXISTENCE, and this check does not implement that oracle.
  # The program above HAS a stable model — `{a,r}` — and is returned as something else. What
  # is implemented here is support, and nothing wider.
  #
  # ★ WHY OBSERVED AND NOT MADE INEXPRESSIBLE, which is this repository's usual arm.
  # ADR-0033 rules that a stratum's in-flight output is not nameable from inside it — but
  # AS AMENDED 2026-08-19 that inexpressibility reaches SUBSTRATE-CONSTRUCTED closure only,
  # and here the knot is tied by `step`, which is the caller's arbitrary function in a host
  # language with no way to restrict what it reads. MEASURED, not assumed:
  # dropping `acc` from the signature does not make the absence read inexpressible, it only
  # moves it onto `dF` — the suite carries that oscillation as a cell. Same reading as the
  # cap refusal above: where `step` is the caller's, this binding OBSERVES.
  #
  # ★ AND SILENCE IS NOT AN OPTION FOR IT. ADR-0020 rules that a negative cycle's contested
  # atoms are UNDEFINED — a named third value, never silence — with stable-model existence
  # as the refusal oracle. An edge map has no third value to write and the well-founded
  # engine is Phase-C den territory by that ADR's own text, so what is available here is the
  # refusal: the criterion is stated, and a result that fails it is refused by name rather
  # than returned as an admitted fact.
  #
  # THE PRICE, MEASURED — AND ITS AXIS IS ROUND COUNT, NOT SIZE. One extra full step per
  # call. On a DEEP instance the loop's per-round unions and differences dilute it to
  # nothing: the canonical closure over a 400-node chain runs ~399 rounds and goes
  # 45,307,630 → 45,637,203 thunks, **+0.73%**, with `cpuTime` over three runs a side
  # (25.3–29.2s against 28.2–30.2s) OVERLAPPING, so the thunk count is the instrument that
  # resolves it and the wall clock is not. ★ THAT FIGURE DOES NOT GENERALIZE. A diameter-2
  # graph converges in 2 rounds and there is nothing to dilute against: **+30% to +37%**,
  # and the ratio holds across a 4× size change (402 and 1,602 nodes), which is what
  # identifies the axis as rounds rather than nodes. Shallow dependency graphs — gen-graph's
  # own consumers — pay the high end.
  #
  # ★ AND `step` IS NOW INVOKED WHERE THE PARENT DID NOT INVOKE IT: an EMPTY frontier used
  # to return the seed without ever applying `step`, and the check applies it once. A `step`
  # that throws on inputs the empty-frontier path never used to reach now throws. Pinned by
  # `test-seeded-empty-frontier-still-applies-the-step`.
  #
  # THE OTHER PRICE: a `step` that itself differences against `acc`
  # (`differenceEdges (compose dF r) acc`) is ANTITONE in its second argument and will be
  # refused — correctly by the stated criterion, though its answer may happen to be right.
  # That subtraction is already the loop's own job below, so the fix is to drop it.
  #
  # THE NAME IS STANDARD DATALOG; THE DATAFUN COORDINATE IT USED TO CARRY IS NOT.
  # This line read "(Arntzenius 2016 §9, semi-naive evaluation.)" and cannot be
  # defended: `semi-naive` occurs exactly ONCE in that paper, in §9 Related Work,
  # about FLIX rather than about Datafun, in a sentence whose reason clause is
  # "because Flix does not extend Datalog to higher order, efficient Datalog
  # implementation strategies (such as semi-naive evaluation) continue to apply".
  # Nothing incremental there is ours to cite either — `delta`, `derivative`,
  # `difference`, `incremental` and `frontier` are each 0 (live controls in the same
  # run: `monotone` 48, `semilattice` 41). Semi-naive evaluation is folklore of the
  # Datalog literature, and the operator keeps the NAME on that basis and no other.
  seededFixpoint =
    {
      seed,
      frontier,
      step,
      maxIter ? 1000,
    }:
    let
      base = edgeMaps.unionEdges seed frontier;

      supported =
        acc:
        let
          unsupported = edgeMaps.differenceEdges acc (edgeMaps.unionEdges base (step acc acc));
          pairs = builtins.concatMap (
            from: map (to: "${from} → ${to}") (builtins.sort builtins.lessThan unsupported.${from})
          ) (builtins.attrNames unsupported);
        in
        if pairs == [ ] then
          acc
        else
          throw "gen-graph: seededFixpoint: the result holds ${toString (builtins.length pairs)} conclusion(s) the converged accumulator does not support: ${builtins.concatStringsSep ", " pairs}. Re-deriving from the converged accumulator does not produce them, so they were drawn while a fact was absent and union-accumulation never retracted them. `step` must be monotone in both arguments.";

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
    supported (go 0 base frontier);

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
  # that was exhausted and converts it to a diameter here, which is what lets the schedule and
  # its conversion move together at one site and at no caller. Same discipline as the shared
  # finisher in `partition.nix`: agreement by construction rather than four copies kept in step.
  #
  # ★★ THE SCHEDULE IS REPEATED SQUARING, AND THE CONVERSION IS ITS OTHER HALF. `step` squares
  # the current relation rather than composing it with the seed, so round r holds every path of
  # length ≤ 2^r instead of ≤ r and the round count falls to log₂ of the diameter. The cap
  # therefore no longer bounds the diameter by itself: reaching it means the diameter exceeds
  # 2^(cap−1), and the refusal says that instead of quoting the cap as if it were a depth.
  # Measured on both fixtures the suites use: returns iff 2^(cap−1) ≥ D, exact at every cell.
  #
  # ★ THE BOUND IS NAMED AS A POWER AND NOT COMPUTED, and that is forced rather than stylistic.
  # Nix integers are 64-bit and overflow THROWS ("integer overflow in multiplying"), so at the
  # default cap of 1000 evaluating 2^999 would replace this refusal with an arithmetic error —
  # the one path where an error must survive to be read. Naming the exponent is exact at every
  # cap, and it keeps one message SHAPE, which is what a caller's anchored pattern can match.
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
        step = current: edgeMaps.unionEdges current (compose current current);
        refusal =
          cap:
          "gen-graph: ${surface}: the graph's reachability diameter exceeds 2^${toString (cap - 1)}, the depth reached by the closure fixpoint's iteration cap of ${toString cap} under repeated squaring. The closure step is monotone on the subset order by construction, so an unconverged closure at the cap is depth and nothing else.";
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
