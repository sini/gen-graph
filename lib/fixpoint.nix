{ prelude }:
let
  inherit (import ./key.nix)
    attrKey
    badResult
    callable
    callableAt
    keyedAttrs
    ;

  # An edge map is `{ from = [ to … ]; }`: a set whose values are lists. The value test is a primop
  # predicate, so it costs no lambda call; the key is found only on the refusal path.
  edgeMapOr =
    who: subject: m:
    if !builtins.isAttrs m then
      badResult who "step" subject "an edge map { from = [ to … ]; }" m
    else if builtins.all builtins.isList (builtins.attrValues m) then
      m
    else
      let
        k = builtins.head (builtins.filter (k: !builtins.isList m.${k}) (builtins.attrNames m));
      in
      throw "gen-graph.${who}: step ${subject} returned an edge map whose entry ${builtins.toJSON k} is a ${builtins.typeOf m.${k}}, not a list of node ids";
  edgeMaps = import ./edge-maps.nix { inherit prelude; };

  countEdges =
    m: builtins.foldl' (acc: from: acc + builtins.length (m.${from} or [ ])) 0 (builtins.attrNames m);

  # ── THE REFUSAL A CAP-EXHAUSTED FIXPOINT RAISES, AND WHY THERE ARE TWO OF THEM ──
  #
  # Stopping at the cap, this binding has observed exactly two things: the cap was reached,
  # and no step withdrew an edge the accumulator already held — the guard below refuses that at
  # the step it happens, so arriving here means it never happened, and "neither converged nor
  # shrank" is still exactly what was observed. WHAT THAT MEANS IS NOT OBSERVABLE HERE, because
  # `step` is the caller's. Two unrelated constructions land in this state — a step whose ascent
  # (monotone, or merely inflationary) is longer than the cap, and a step that is STATIONARY IN
  # EDGE CONTENT yet never literally equal, which permuting a target list is enough to produce
  # (`{ a = [ "x" "y" ]; }` ↔ `{ a = [ "y" "x" ]; }`): the subset test passes in BOTH directions
  # so the guard never fires, and `next == current` is literal attrset equality so it never
  # converges either. The guard sees neither, correctly — it tests the subset order and neither
  # of them withdraws. So the generic message states the observation and names neither cause: a
  # message that picked one would tell every caller with a permuting step that their graph is
  # deep, and a message saying the step ASCENDED would be false of the permutation, which
  # reaches the cap having ascended nowhere.
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
      st = callableAt "fixpoint" "step" "an edge map" step;
      rf = callableAt "fixpoint" "refusal" "a string" refusal;
      # ── THE TERMINATION GUARD TESTS THE SUBSET ORDER OVER EDGE CONTENT ──
      #
      # The semilattice this fixpoint is computed in orders edge maps by INCLUSION OF
      # (from, to) PAIRS, joined by `unionEdges`; that is the poset Datafun's Lemma 4 takes its
      # ascending chain over, so it is the order the guard must test. `differenceEdges` reads
      # `b.${from} or [ ]` and drops rows that difference to empty, so `differenceEdges current
      # next == { }` IS containment on edge content — not on the literal KEY SET, which
      # `materialize`'s sink rows make shrink on round 0 of every closure over a graph with a
      # sink, and not on CARDINALITY, which a step withdrawing one edge and adding another
      # leaves untouched. Cardinality is SUBSUMED rather than dropped: `current ⊆ next` implies
      # `|current| ≤ |next|`, so this catches every shrink the count caught AND the
      # size-preserving oscillation it could not see, and it names the edge instead of an
      # arithmetic difference.
      #
      # THE PRICE, MEASURED in `sets.elements` — O(E) per round, a full exponent below the
      # computation it guards: over an N-node chain the whole closure reads 2.98 and the guard's
      # own term 2.00, so relative overhead FALLS with size (8.4% at N=50 → 0.6% at N=800).
      # `nrThunks` is BLIND to it (~1.15) because this is primop work allocating Values, not
      # Exprs. On a shallow shape there is nothing to dilute against, and there the invariant is
      # the ABSOLUTE delta — 5,362 elements at 421 nodes and 21,122 at 1,641, identical across
      # three fixtures whose ratios span 29.5% to 41.2%. A cardinality pre-filter would buy some
      # of that back and is UNSOUND: a step removing one edge and adding two grows the count and
      # is still non-ascending.
      #
      # ★ A PRECONDITION THIS ADDS, INSTRUMENTED RATHER THAN CLOSED. `countEdges` was total over
      # attrsets of lists; `differenceEdges` keys an attrset by the target list's ELEMENTS, so
      # the accumulator narrows to attrset of lists of STRINGS, and a non-string target now gets
      # Nix's raw `expected a string but found an integer` where it used to get a named refusal.
      # A door — a per-iteration element-type check — is a second O(E) pass on the happy path
      # for a domain `materialize`, `unionEdges` and `compose` cannot produce, and
      # `builtins.tryEval` does not catch that type error, so the loss is pinned as a cell
      # instead: `test-generic-fixpoint-non-string-edge-target-is-not-refused-by-name`, which
      # says so the day a named refusal returns. Same move as
      # `test-seeded-circular-rederivation-is-supported-and-RETURNED` below.
      go =
        iter: current:
        if iter >= maxIter then
          throw (
            let
              m = rf maxIter;
            in
            if builtins.isString m then
              m
            else
              badResult "fixpoint" "refusal" "on the cap ${toString maxIter}" "a string" m
          )
        else
          let
            next = edgeMapOr "fixpoint" "at iteration ${toString iter}" (st current);
            withdrawn = edgeMaps.differenceEdges current next;
            withdrawnPairs = builtins.concatMap (
              from: map (to: "${from} → ${to}") (builtins.sort builtins.lessThan withdrawn.${from})
            ) (builtins.attrNames withdrawn);
          in
          if withdrawnPairs != [ ] then
            throw "gen-graph: fixpoint step is not ascending: it withdrew ${toString (builtins.length withdrawnPairs)} edge(s) the accumulator already held: ${builtins.concatStringsSep ", " withdrawnPairs}. The iterates of a step that retracts are a walk, not an ascending chain, and a walk in a finite carrier cycles rather than converging. `step` must not withdraw an edge the accumulator holds."
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
  # gap. Closing it is ADR-0020's WELL-FOUNDED ENGINE, which that ADR puts in Phase-C
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
  # engine is Phase-C territory by that ADR's own text, so what is available here is the
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
      st = callableAt "seededFixpoint" "step" "an edge map" step;
      base = edgeMaps.unionEdges seed frontier;

      supported =
        acc:
        let
          unsupported = edgeMaps.differenceEdges acc (
            edgeMaps.unionEdges base (
              edgeMapOr "seededFixpoint" "on the converged accumulator" (
                let
                  h = st acc;
                in
                if builtins.isFunction h || callable h then
                  h acc
                else
                  badResult "seededFixpoint" "step" "on the converged accumulator"
                    "a function from the accumulator to an edge map"
                    h
              )
            )
          );
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
            produced = edgeMapOr "seededFixpoint" "at iteration ${toString iter}" (
              let
                h = st dF;
              in
              if builtins.isFunction h || callable h then
                h acc
              else
                badResult "seededFixpoint" "step" "at iteration ${toString iter}"
                  "a function from the accumulator to an edge map"
                  h
            );
            acc' = edgeMaps.unionEdges acc produced;
            dF' = edgeMaps.differenceEdges produced acc;
          in
          go (iter + 1) acc' dF';
    in
    supported (go 0 base frontier);

  compose =
    e1: e2:
    prelude.mapAttrs (
      _from: targets: prelude.unique (prelude.concatMap (mid: e2.${attrKey mid} or [ ]) targets)
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
  # `step` below is not the caller's: it is built from `unionEdges`, which since
  # `den-hoag-6gqe` item 3 is `filterAttrs (targets != [ ]) (genAttrs allKeys (k: unique
  # ((a.k or [ ]) ++ (b.k or [ ]))))` (`edge-maps.nix`) — RELATION-PURE, dropping a row that
  # unions to empty rather than carrying it as bookkeeping. What is monotone is EDGE CONTENT,
  # not the literal key set: `current.k ⊆ step(current).k` holds for every key under the `.k
  # or [ ]` reading, and once a key is PRESENT its value can only grow — a union with a
  # non-empty set is never empty, so a key present-nonempty never disappears again. The one
  # place the literal key set can shrink is the seed itself: `materialize` still seeds every
  # sink with an explicit `[ ]` row, and that row drops on the first round, once, since
  # nothing ever unions into it — a one-time transition that carries no edge and does not
  # recur. The step is monotone on the SUBSET order of edge content, not merely on
  # cardinality, so a WITHDRAWING step cannot arise here. ★ THE REASON HAS NARROWED: `fixpoint`'s
  # own guard now tests that same subset order, so a withdrawing step cannot arise past it
  # ANYWHERE, and what the generic message must stay silent about is a step stationary in edge
  # content yet never literally equal — likewise absent here, because this one converges.
  # A monotone map on a finite lattice reaches the cap
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
          closureSets = keyedAttrs targets (
            mid:
            builtins.listToAttrs (
              map (t: {
                name = attrKey t;
                value = true;
              }) (closure.${attrKey mid} or [ ])
            )
          );
        in
        builtins.filter (
          to: builtins.any (mid: mid != to && (closureSets.${attrKey mid} or { }) ? ${attrKey to}) targets
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
