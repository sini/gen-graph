# The ordering ARM against the ordering DOOR, on the generated shapes.
#
# `topoOrderKahn` is A. B. Kahn 1962 published under its own name; `topoOrder` is the door
# and today delegates to it. The door's default is a separate decision from the arm's
# identity — that separation is the whole point of the name — so the agreement between them
# is a property to be measured at every revision rather than read off today's one-line
# delegation. `coneRank` binds the ARM, so a caller reading the door's order and a caller
# reading the arm's must see the same sequence for as long as the door delegates.
#
# ELEMENT-WISE, never a summary. `{ first, last, len }` agreement is not agreement: two
# valid topological orders over the same graph share all three and differ at index 1 (the
# measurement `den-hoag-nz21` records on `fleet`/`discrim`). Every cell below compares the
# whole emitted list by value.
#
# The shapes are the bench's, verbatim, so a figure measured in `ci/bench/cost-classes.nix`
# and a verdict asserted here are about the same graphs.
#
# ── AND THE DOOR SELECTS, so the agreement has a REASON and not only a delegation ──
# The door is a certificate-gated pair. Where a candidate order can be PROVEN to be the
# UNIQUE topological order of its input the door emits that candidate; everywhere else the
# Kahn arm answers. Uniqueness is what makes a second arm admissible behind one door:
# linkage over a permutation of all keys is a directed Hamiltonian path in the dependency
# relation, and a DAG whose relation contains one has exactly one topological order. So the
# identity cells below assert a theorem's consequence, and a red in them is a defect in the
# gate rather than a re-baseline of a loose order.
#
# The GATE is what buys that, and no green identity cell can say so by itself — if the
# certificate were deleted and the candidate emitted unconditionally, every cell here would
# still pass on the shapes where the two happen to coincide. The gate-defeated arm is
# therefore run beside them, and it FIRES: the ungated candidate is still a VALID
# topological order on every shape and a DIFFERENT one on three of seven.
#
# ── AND `coneRank` BEFORE AGAINST AFTER ──
# `coneRank` now warms its memo map along the arm's order. The claim that makes that a
# REMOVAL rather than a re-implementation is that the answer did not move, so the
# PRE-REMEDIATION construction is reproduced below and both arms run in the same cell. The
# whole `depth` map and the whole `order` are compared; the sizes here stay under the
# shipped arm's own ceilings, because a control that aborts proves nothing about agreement.
# The ceiling itself is not assertable in this suite — a `max-call-depth` abort is caught by
# neither runner — and lives in `ci/bench/cone-ceiling.sh`.
{ genGraph, genPrelude, ... }:
let
  inherit (genGraph)
    topoOrder
    topoOrderKahn
    coneRank
    ;
  prelude = genPrelude;

  # THE PRE-REMEDIATION ARM, verbatim at `f3b520f`: the memoized recurrence and the
  # `(depth, id)` sort, with nothing forcing the map in any particular order. Reproduced
  # rather than referenced because the point of the cell is to run both at once.
  coneRankShipped =
    accessor: cone:
    let
      coneSet = prelude.genAttrs cone (_: true);
      inConeProducers = id: builtins.filter (d: coneSet ? ${d}) (accessor.edges id);
      depth = prelude.fix (
        d:
        prelude.genAttrs cone (
          id:
          let
            ps = inConeProducers id;
          in
          if ps == [ ] then 0 else 1 + prelude.foldl' (m: p: prelude.max m d.${p}) 0 ps
        )
      );
      order = builtins.sort (
        a: b: if depth.${a} == depth.${b} then a < b else depth.${a} < depth.${b}
      ) cone;
    in
    {
      inherit order depth;
    };

  ix = m: builtins.genList (i: i) m;
  key = p: i: p + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000" + toString i;
  fromPairs = ns: pairs: {
    nodes = ns;
    edges =
      let
        m = builtins.listToAttrs pairs;
      in
      k: m.${k} or [ ];
  };

  # node i depends on i-1: one legal order, keys ascending with depth.
  chain =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
  # `chain` with the edge direction flipped and nothing else changed, so the keys now
  # ascend AGAINST the dependency order. The sentinel node moves from the head to the
  # tail — it has to, or the last node would name a dependency outside `nodes`, which is a
  # refusal rather than a shape.
  chainRev =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == n - 1 then [ ] else [ (key "n" (i + 1)) ];
      }) (ix n)
    );
  # n/10 independent 10-chains: the shape a host fleet produces.
  fleet =
    n:
    let
      c = n / 10;
      k =
        i: d:
        "h"
        + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000"
        + toString i
        + "-"
        + toString d;
    in
    fromPairs (builtins.concatLists (map (i: map (k i) (ix 10)) (ix c))) (
      builtins.concatLists (
        map (
          i:
          map (d: {
            name = k i d;
            value = if d == 0 then [ ] else [ (k i (d - 1)) ];
          }) (ix 10)
        ) (ix c)
      )
    );
  # n/2 ready at the start, each releasing one whose key sorts BELOW every node still
  # waiting: the shape on which two different valid topological orders are distinguishable.
  discrim =
    n:
    let
      m = n / 2;
    in
    fromPairs (map (key "m") (ix m) ++ map (key "a") (ix m)) (
      map (i: {
        name = key "a" i;
        value = [ (key "m" i) ];
      }) (ix m)
    );
  # n/2 producers, each releasing exactly one consumer: the widest shape with any edge at
  # all, and the one whose candidate order the ungated arm gets right by coincidence.
  wide =
    n:
    let
      m = n / 2;
    in
    fromPairs (map (key "a") (ix m) ++ map (key "b") (ix m)) (
      map (i: {
        name = key "b" i;
        value = [ (key "a" i) ];
      }) (ix m)
    );
  # The transitive tournament: node i depends on every j > i. E is Θ(n²) and the topological
  # order is UNIQUE, so this is the dense shape the door's certificate can prove.
  total =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = map (j: key "n" (i + 1 + j)) (ix (n - i - 1));
      }) (ix n)
    );
  # `total` up to the order WITHIN each dependency list — same nodes, same edge set, same
  # degrees, same unique order. It is a distinct fixture because the certificate's linkage
  # witness WALKS those lists, and the linking predecessor sits first in `total` and last
  # here.
  totalrev =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = map (j: key "n" (n - 1 - j)) (ix (n - i - 1));
      }) (ix n)
    );
  # one 4000-node chain PLUS (n-4000)/2 independent 2-chains: depth and width additive.
  deepwide =
    n:
    let
      d = 4000;
      m = (n - d) / 2;
    in
    fromPairs (map (key "c") (ix d) ++ map (key "a") (ix m) ++ map (key "b") (ix m)) (
      map (i: {
        name = key "c" i;
        value = if i == 0 then [ ] else [ (key "c" (i - 1)) ];
      }) (ix d)
      ++ map (i: {
        name = key "b" i;
        value = [ (key "a" i) ];
      }) (ix m)
    );

  # Small enough to run in a suite, large enough that the two arms could diverge anywhere
  # in 300 emissions rather than in a handful.
  small = 300;
  shapes = {
    chain = chain small;
    chainRev = chainRev small;
    fleet = fleet small;
    discrim = discrim small;
    deepwide = deepwide 4002;
  };

  # The rank cells run BOTH arms, and the pre-remediation one has ceilings of its own — a
  # whole-map `depth` read on `chainRev` aborts between 1,999 and 2,000 — so these stay
  # small. Agreement is the subject here; scale is `cone-ceiling.sh`'s.
  rankShapes = {
    chain = chain small;
    chainRev = chainRev small;
    fleet = fleet small;
    discrim = discrim small;
  };

  # The bench's ten fixtures less its three cyclic ones. `cycle`, `cyclechord` and
  # `complete` emit no order for an index-wise comparison — the door reports a cycle there,
  # which is the direct-arm cell below — so they are excluded by construction rather than
  # by omission. Four entries are `shapes`' own rather than rebuilt copies, so the two
  # families are the same graphs and not two spellings of them.
  benchShapes = {
    inherit (shapes)
      chain
      fleet
      discrim
      deepwide
      ;
    wide = wide small;
    total = total small;
    totalrev = totalrev small;
  };

  doorOrder = fx: (topoOrder fx).order;
  armOrder = fx: (topoOrderKahn fx).order;
  reversed =
    xs: builtins.genList (i: builtins.elemAt xs (builtins.length xs - 1 - i)) (builtins.length xs);

  # ELEMENT-WISE AS A PER-INDEX FOLD, and the COUNT is the point. `==` over two lists
  # returns the same verdict today; a count of divergent positions says how far apart two
  # orders are, and it is the form that cannot be quietly weakened into the
  # `{ first, last, len }` triple two different valid topological orders share.
  diffPositions =
    xs: ys:
    let
      lx = builtins.length xs;
      ly = builtins.length ys;
      shared = if lx < ly then lx else ly;
    in
    # A length mismatch is divergence at every unshared position, COUNTED rather than
    # thrown: a throw here would crash the batch asserter instead of failing its cell.
    (lx + ly - 2 * shared)
    + builtins.length (builtins.filter (i: builtins.elemAt xs i != builtins.elemAt ys i) (ix shared));

  triple = xs: {
    first = builtins.head xs;
    last = builtins.elemAt xs (builtins.length xs - 1);
    len = builtins.length xs;
  };

  # 0-INDEXED 1 AND 2, NEVER 0 AND 1. The triple above samples positions 0 and n-1, so a
  # transposition touching either makes the WEAK predicate fire — after which the control
  # looks armed while certifying nothing about the blindness it exists to exhibit. Both
  # predicates are read in the same cell so that blindness is visible rather than inferred.
  swap12 =
    xs:
    builtins.genList (
      i:
      builtins.elemAt xs (
        if i == 1 then
          2
        else if i == 2 then
          1
        else
          i
      )
    ) (builtins.length xs);

  # THE CANDIDATE THE DOOR'S CERTIFICATE SCORES, emitted with NO certificate: ascending
  # (out-degree, key), the door's own comparator. `keyOf` is the identity on every fixture
  # here, so the node list is the key list.
  bareCandidate =
    fx:
    let
      deg = builtins.listToAttrs (
        map (k: {
          name = k;
          value = builtins.length (fx.edges k);
        }) fx.nodes
      );
    in
    builtins.sort (
      a: b: if deg.${a} == deg.${b} then builtins.lessThan a b else deg.${a} < deg.${b}
    ) fx.nodes;

  # VALIDITY, kept apart from EQUALITY: both arms emit valid orders, so "is topological"
  # and "is the same list" are different findings and a cell reporting one cannot say which
  # of them failed.
  isTopological =
    fx: order:
    let
      pos = builtins.listToAttrs (
        builtins.genList (i: {
          name = builtins.elemAt order i;
          value = i;
        }) (builtins.length order)
      );
    in
    builtins.all (k: builtins.all (d: pos.${d} < pos.${k}) (fx.edges k)) fx.nodes;

  # The certificate's two predicates re-derived over the FIXTURE: consecutive candidates
  # directly linked, and every edge pointing strictly backwards. This says which shapes the
  # door's gate ADMITS. It is not a witness that the door took that path and there can be
  # no such witness in this language — the proof behind the gate is exactly the statement
  # that the two paths are observationally identical. What it buys is that the identity
  # cell cannot go vacuous: an all-false column would mean those cells are comparing the
  # Kahn arm against itself.
  certifies =
    fx:
    let
      cand = bareCandidate fx;
      cn = builtins.length cand;
    in
    builtins.all (i: builtins.elem (builtins.elemAt cand i) (fx.edges (builtins.elemAt cand (i + 1)))) (
      ix (if cn == 0 then 0 else cn - 1)
    )
    && isTopological fx cand;
in
{
  flake.tests.arms = {
    # ── door ≡ arm, element-wise, one cell per shape ──
    test-arm-door-chain = {
      expr = doorOrder shapes.chain;
      expected = armOrder shapes.chain;
    };
    test-arm-door-chain-rev = {
      expr = doorOrder shapes.chainRev;
      expected = armOrder shapes.chainRev;
    };
    test-arm-door-fleet = {
      expr = doorOrder shapes.fleet;
      expected = armOrder shapes.fleet;
    };
    test-arm-door-discrim = {
      expr = doorOrder shapes.discrim;
      expected = armOrder shapes.discrim;
    };
    test-arm-door-deepwide = {
      expr = doorOrder shapes.deepwide;
      expected = armOrder shapes.deepwide;
    };

    # ARMED CONTROL. If the comparison above could not separate two orders it would agree
    # with anything, including a reversal — which is a valid topological order of NO shape
    # here (each has at least one edge, and reversing puts a consumer before its producer).
    # A `false` on every shape is what makes the agreement cells load-bearing.
    test-arm-door-reversal-control = {
      expr = builtins.mapAttrs (_: fx: doorOrder fx == reversed (armOrder fx)) shapes;
      expected = builtins.mapAttrs (_: _: false) shapes;
    };

    # ── THE DOOR'S TWO ARMS EMIT THE SAME LIST, INDEX BY INDEX, ON THE BENCH'S SHAPES ──
    # `diff` is the per-index fold: on a routed shape the door emits its own candidate and
    # must still agree with the Kahn arm because the certificate proves that order is the
    # only one; on a rejected shape it agrees because it IS the Kahn arm. `routed` is
    # written out per fixture rather than summarised, so a gate that stopped admitting
    # anything reds this cell instead of leaving it comparing the arm with itself — and it
    # records which three of the seven the certificate accepts, one of them the sparse
    # chain and two of them dense.
    # `swapDiff`/`swapTripleSame` are the armed control for the fold itself: transposing
    # the elements at 1 and 2 moves two positions, which the fold sees and the retired
    # triple does not.
    test-arm-door-elementwise-bench-shapes = {
      expr = builtins.mapAttrs (_: fx: {
        diff = diffPositions (doorOrder fx) (armOrder fx);
        routed = certifies fx;
        swapDiff = diffPositions (doorOrder fx) (swap12 (doorOrder fx));
        swapTripleSame = triple (doorOrder fx) == triple (swap12 (doorOrder fx));
      }) benchShapes;
      expected = {
        chain = {
          diff = 0;
          routed = true;
          swapDiff = 2;
          swapTripleSame = true;
        };
        wide = {
          diff = 0;
          routed = false;
          swapDiff = 2;
          swapTripleSame = true;
        };
        fleet = {
          diff = 0;
          routed = false;
          swapDiff = 2;
          swapTripleSame = true;
        };
        discrim = {
          diff = 0;
          routed = false;
          swapDiff = 2;
          swapTripleSame = true;
        };
        total = {
          diff = 0;
          routed = true;
          swapDiff = 2;
          swapTripleSame = true;
        };
        totalrev = {
          diff = 0;
          routed = true;
          swapDiff = 2;
          swapTripleSame = true;
        };
        deepwide = {
          diff = 0;
          routed = false;
          swapDiff = 2;
          swapTripleSame = true;
        };
      };
    };

    # ── THE GATE-DEFEATED CONTROL, AND IT FIRES ──
    # The cell above says "these two agree"; it cannot say "the GATE is what makes them
    # agree". `bareCandidate` is the same candidate with the certificate removed, and the
    # divergence is measured rather than asserted to exist: `fleet` 290 of 300, `discrim`
    # 298 of 300, `deepwide` 2 of 4002 — the counts at these sizes, pinned so a control
    # that stopped firing reds instead of passing quietly.
    # `bareValid` is why the gate has to be a certificate and not a heuristic: the ungated
    # candidate is not WRONG anywhere here, it is a DIFFERENT valid topological order, and
    # only the linkage witness separates the shapes on which there is no other one to emit.
    # `revValid` arms that checker in the same cell — a reversal is topological on none of
    # these, so a checker stuck at `true` is visible beside the `bareValid` column rather
    # than assumed away.
    test-arm-door-bare-candidate-control = {
      expr = builtins.mapAttrs (_: fx: {
        bareDiff = diffPositions (doorOrder fx) (bareCandidate fx);
        bareValid = isTopological fx (bareCandidate fx);
        revValid = isTopological fx (reversed (doorOrder fx));
      }) benchShapes;
      expected = {
        chain = {
          bareDiff = 0;
          bareValid = true;
          revValid = false;
        };
        wide = {
          bareDiff = 0;
          bareValid = true;
          revValid = false;
        };
        fleet = {
          bareDiff = 290;
          bareValid = true;
          revValid = false;
        };
        discrim = {
          bareDiff = 298;
          bareValid = true;
          revValid = false;
        };
        total = {
          bareDiff = 0;
          bareValid = true;
          revValid = false;
        };
        totalrev = {
          bareDiff = 0;
          bareValid = true;
          revValid = false;
        };
        deepwide = {
          bareDiff = 2;
          bareValid = true;
          revValid = false;
        };
      };
    };

    # ── the arm is a live surface, called by name ──
    # Not reached through the door in any of these: a name that only ever runs because
    # something else delegates to it is not published.
    test-arm-direct-order = {
      expr =
        (topoOrderKahn {
          nodes = [
            "a"
            "b"
            "c"
          ];
          edges =
            id:
            {
              a = [ "b" ];
              b = [ "c" ];
            }
            .${id} or [ ];
        }).order;
      expected = [
        "c"
        "b"
        "a"
      ];
    };
    # The cycle report is the arm's too, not a wrapper's.
    test-arm-direct-cycle-report = {
      expr =
        let
          r = topoOrderKahn {
            nodes = [
              "a"
              "b"
            ];
            edges =
              id:
              {
                a = [ "b" ];
                b = [ "a" ];
              }
              .${id} or [ ];
          };
        in
        {
          inherit (r) ok;
          cycles = r.cycles;
        };
      expected = {
        ok = false;
        cycles = [
          [
            "a"
            "b"
          ]
        ];
      };
    };
    # And the refusals: the arm carries them, so binding it by name loses no guard.
    test-arm-direct-refuses-dangling = {
      expr =
        !(builtins.tryEval (
          builtins.deepSeq (topoOrderKahn {
            nodes = [ "a" ];
            edges = _: [ "ghost" ];
          }) true
        )).success;
      expected = true;
    };
    # LIVE CONTROL for the refusal cell above, same run: a well-formed call is not caught.
    test-arm-direct-refusal-control = {
      expr =
        !(builtins.tryEval (
          builtins.deepSeq (topoOrderKahn {
            nodes = [ "a" ];
            edges = _: [ ];
          }) true
        )).success;
      expected = false;
    };

    # ── coneRank: the emitted order and the whole depth map did not move ──
    # One cell per shape, both arms run in it, and the comparison is over the WHOLE map and
    # the WHOLE list. `deepwide` is absent by necessity: its deep leg is 4,000 nodes and the
    # shipped arm cannot return there, which is the ceiling `cone-ceiling.sh` measures.
    test-conerank-pre-post-chain = {
      expr = coneRank rankShapes.chain rankShapes.chain.nodes;
      expected = coneRankShipped rankShapes.chain rankShapes.chain.nodes;
    };
    test-conerank-pre-post-chain-rev = {
      expr = coneRank rankShapes.chainRev rankShapes.chainRev.nodes;
      expected = coneRankShipped rankShapes.chainRev rankShapes.chainRev.nodes;
    };
    test-conerank-pre-post-fleet = {
      expr = coneRank rankShapes.fleet rankShapes.fleet.nodes;
      expected = coneRankShipped rankShapes.fleet rankShapes.fleet.nodes;
    };
    test-conerank-pre-post-discrim = {
      expr = coneRank rankShapes.discrim rankShapes.discrim.nodes;
      expected = coneRankShipped rankShapes.discrim rankShapes.discrim.nodes;
    };

    # ARMED CONTROLS for the four cells above, one per axis they compare.
    # ORDER: a reversal must NOT compare equal on any shape — otherwise the list comparison
    # is agreeing with anything. DEPTH: a map with every rank shifted by one must NOT
    # compare equal either, which is what says the map comparison reads the values and not
    # merely the key set.
    test-conerank-pre-post-armed-controls = {
      expr = builtins.mapAttrs (_: fx: {
        order = (coneRank fx fx.nodes).order == reversed (coneRankShipped fx fx.nodes).order;
        depth =
          (coneRank fx fx.nodes).depth == builtins.mapAttrs (_: v: v + 1) (coneRankShipped fx fx.nodes).depth;
      }) rankShapes;
      expected = builtins.mapAttrs (_: _: {
        order = false;
        depth = false;
      }) rankShapes;
    };
  };
}
