# THE ACCESSOR HOIST, AS A CONTRACT GATE.
#
# `traverse.hoistEdges` changes how an operator READS `edges`: instead of wrapping a node's
# successors into `genericClosure`'s item shape at every visit, the caller wraps them once and
# every traversal reads that. It is an amortization and it is meant to change cost and nothing
# else — but the surfaces it was applied to emit ORDERED values that shipped consumers depend on.
# `fbNode`'s tag is the component's SMALLEST member, and two consumers group their output by that
# tag; `condensationOf`'s `reps`, `bottomUp` and `sccs` are ordered outputs; `cycles` returns a
# sorted list and `cyclePaths` an ordered walk. So "the answer is the same" is a CONTRACT claim
# here, not a sanity check, and the cells below are what makes it one.
#
# ELEMENT-WISE, WHOLE VALUES, NEVER A SUMMARY. `{ first, last, len }` agreement is not agreement
# and neither is a digest: both are satisfied by values that differ where the contract lives.
# Every cell compares the whole value with `==`.
#
# ── AND EVERY AGREEMENT CELL IS ARMED ──
# An equality cell proves nothing on its own: it reads `true` for a comparison that cannot fail,
# and two arms that both answer `[ ]` agree perfectly while saying nothing. So each agreement
# cell is paired with two controls in the same run:
#
#   · the REVERSAL control — the same reference answer with every list reversed at every depth —
#     which must compare UNEQUAL at every cell. If it compared equal, the agreement cell would
#     agree with anything;
#   · the REVERSAL-IS-LIVE control, which asserts the reversal actually CHANGED the reference
#     value. Without it a reversal control passes vacuously on any answer holding no list of two
#     or more elements, and reports a dead predicate as a firing one.
#
# ★ THE SECOND CONTROL IS WHY THE CYCLIC SHAPES BELOW EXIST. `cycles` and `cyclePaths` answer
# `[ ]` on `chain` and `fleet`, so on those shapes both arms agree, the reversal cannot differ,
# and the cell is vacuous however it is spelled. `chainRing` and `fleetRings` are the same
# skeletons closed into cycles, and they are what carries the discrimination for that family.
#
# The reference arms are the PRE-HOIST constructions reproduced verbatim at `2962e22`, the same
# way `ci/bench/cost-classes.nix` reproduces them: a reference cited rather than built is a
# reference nobody can run. The shapes are the bench's, verbatim, so a figure measured there and
# a verdict asserted here are about the same graphs.
{ genGraph, genPrelude, ... }:
let
  inherit (genGraph)
    cycles
    cyclePaths
    condensationOf
    dependentsOf
    directDependents
    fbNode
    fbWork
    hoistEdges
    pathsBetween
    reachableFrom
    reachableVia
    selfReachable
    transpose
    ;
  prelude = genPrelude;

  ix = m: builtins.genList (i: i) m;
  key = p: i: p + builtins.substring 0 (6 - builtins.stringLength (toString i)) "000000" + toString i;
  pad =
    i:
    let
      s = toString i;
      z = builtins.substring 0 (5 - builtins.stringLength s) "00000";
    in
    "n" + z + s;
  fromPairs = ns: pairs: {
    nodes = ns;
    edges =
      let
        m = builtins.listToAttrs pairs;
      in
      k: m.${k} or [ ];
  };

  # ── the bench's shapes ──
  complete = n: {
    nodes = builtins.genList pad n;
    edges = id: builtins.filter (x: x != id) (builtins.genList pad n);
  };
  cycle =
    n:
    let
      ringNodes = builtins.genList pad n;
      idxOf = builtins.listToAttrs (
        builtins.genList (i: {
          name = pad i;
          value = i;
        }) n
      );
    in
    {
      nodes = ringNodes;
      edges =
        id:
        let
          i = idxOf.${id};
        in
        [ (pad (if i + 1 < n then i + 1 else 0)) ];
    };
  chain =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
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

  # ── the same skeletons, closed ──
  # `chain` and `fleet` are acyclic, so the cycle-reporting surfaces answer `[ ]` on them and
  # every comparison over that answer is vacuous. These close each leg back on its root: the
  # node set, the key order and the out-degree are unchanged, and exactly one edge per leg is
  # added, so what they add to the family is a non-empty answer and nothing else.
  chainRing =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ (key "n" (n - 1)) ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
  fleetRings =
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
            value = if d == 0 then [ (k i 9) ] else [ (k i (d - 1)) ];
          }) (ix 10)
        ) (ix c)
      )
    );

  # Small enough that the reference arms — which are the constructions the hoist replaced, and
  # so carry the cost it removed — run inside a suite; large enough that two arms could diverge
  # in tens of components rather than in a handful. Agreement belongs here; scale belongs to
  # `ci/bench/cost-classes.nix`.
  small = 40;

  # The four shapes the oracle names, for the surfaces that answer on all of them.
  shapes = {
    cycle = cycle small;
    complete = complete small;
    chain = chain small;
    fleet = fleet small;
  };
  # For the cycle-reporting surfaces, with the acyclic two replaced by their closed forms.
  cyclicShapes = {
    cycle = cycle small;
    complete = complete small;
    chainRing = chainRing small;
    fleetRings = fleetRings small;
  };
  # `cyclePaths`' reconstruction branch runs `pathsBetween`, which enumerates every simple path
  # between two nodes and is worst-case exponential — a separate, filed defect on a separate
  # branch. On one SCC of 40 mutually-adjacent nodes that enumeration does not terminate in any
  # useful time, so `complete` is EXCLUDED here rather than reduced to a size that would hide
  # why. Nothing below asserts anything about `cyclePaths` on a dense component.
  cyclePathsShapes = builtins.removeAttrs cyclicShapes [ "complete" ];

  # ── THE PRE-HOIST REFERENCE ARMS, VERBATIM AT `2962e22` ──
  cyclesUnhoisted =
    { edges, nodes, ... }:
    builtins.sort builtins.lessThan (builtins.filter (selfReachable { inherit edges; }) nodes);

  tagOfSmallest = members: builtins.head (builtins.sort builtins.lessThan members);

  nodeTagsUnhoisted =
    accessor@{ edges, nodes, ... }:
    let
      rev = transpose accessor;
      forward = prelude.genAttrs nodes (v: reachableFrom { inherit edges; } v);
      backward = prelude.genAttrs nodes (
        v: prelude.genAttrs (reachableFrom { inherit (rev) edges; } v) (_: true)
      );
    in
    prelude.genAttrs nodes (
      v: tagOfSmallest ([ v ] ++ builtins.filter (u: backward.${v} ? ${u}) forward.${v})
    );
  fbNodeUnhoisted = accessor: condensationOf accessor (nodeTagsUnhoisted accessor);

  cyclePathsUnhoisted =
    { edges, nodes, ... }:
    let
      cyclic = cyclesUnhoisted { inherit edges nodes; };
    in
    if cyclic == [ ] then
      [ ]
    else
      let
        inherit ((fbNodeUnhoisted { inherit edges nodes; })) sccOf;
        repCycle =
          members:
          let
            u = tagOfSmallest members;
            back = builtins.filter (p: p != [ ]) (
              map (
                v:
                let
                  ps = pathsBetween { inherit edges; } v u;
                in
                if ps == [ ] then [ ] else builtins.head ps
              ) (builtins.filter (v: sccOf.${v} == sccOf.${u}) (edges u))
            );
          in
          [ u ] ++ (if back == [ ] then [ ] else prelude.init (builtins.head back));
      in
      map repCycle (prelude.mapAttrsToList (_: c: c) (builtins.groupBy (k: sccOf.${k}) cyclic));

  # ── THE TWO ARMS THE LIBRARY DECLINED, kept because a scope is a measurement ──
  # Both are REJECTED ON COST, not on correctness: `dependentsOf` makes one closure and `fbWork`
  # restricts its accessor every round, so hoisting either is a pessimization
  # (`ci/bench/cost-classes.nix`). The cells below assert they would nonetheless have ANSWERED
  # the same — which is what makes the rejection a cost judgement rather than a bug report.
  dependentsOfHoisted =
    accessor: targetId:
    let
      reverseIndex = directDependents accessor;
      succ = hoistEdges {
        edges = id: reverseIndex.${id} or [ ];
        inherit (accessor) nodes;
      };
    in
    builtins.sort builtins.lessThan (reachableVia succ targetId);

  workTagsHoisted =
    accessor@{ nodes, ... }:
    let
      rev = transpose accessor;
      succFwd = hoistEdges accessor;
      succBwd = hoistEdges rev;
      step =
        acc: v:
        if acc.tags ? ${v} then
          acc
        else
          let
            live = id: !(acc.tags ? ${id});
            forward = prelude.genAttrs (reachableVia (id: builtins.filter (w: live w.key) (succFwd id)) v) (
              _: true
            );
            component = [
              v
            ]
            ++ builtins.filter (u: forward ? ${u}) (
              reachableVia (id: builtins.filter (w: live w.key) (succBwd id)) v
            );
            tag = tagOfSmallest component;
          in
          {
            tags = acc.tags // prelude.genAttrs component (_: tag);
          };
    in
    (builtins.foldl' step { tags = { }; } nodes).tags;
  fbWorkHoisted = accessor: condensationOf accessor (workTagsHoisted accessor);

  # ── the armed control ──
  # Reverses every list at every depth. The outer list alone is not enough: on a one-component
  # partition `sccs` holds a single member list, so reversing only the outside is the IDENTITY
  # and the control would report agreement on exactly the shapes where a component's membership
  # order is the thing at risk.
  reverseList =
    xs: builtins.genList (i: builtins.elemAt xs (builtins.length xs - 1 - i)) (builtins.length xs);
  revDeep =
    v:
    if builtins.isList v then
      reverseList (map revDeep v)
    else if builtins.isAttrs v then
      builtins.mapAttrs (_: revDeep) v
    else
      v;

  # `expr`-side helpers, so a cell reads as one line per shape.
  agrees = arms: fx: (arms.hoisted fx) == (arms.reference fx);
  disagreesReversed = arms: fx: (arms.hoisted fx) == revDeep (arms.reference fx);
  reversalIsLive = arms: fx: revDeep (arms.reference fx) != arms.reference fx;

  over = fixtures: f: builtins.mapAttrs (_: fx: f fx) fixtures;
  allTrue = fixtures: builtins.mapAttrs (_: _: true) fixtures;
  allFalse = fixtures: builtins.mapAttrs (_: _: false) fixtures;

  cyclesArms = {
    hoisted = cycles;
    reference = cyclesUnhoisted;
  };
  fbNodeArms = {
    hoisted = fbNode;
    reference = fbNodeUnhoisted;
  };
  cyclePathsArms = {
    hoisted = cyclePaths;
    reference = cyclePathsUnhoisted;
  };
  # The declined arms are compared the other way round — the SHIPPED construction is the
  # reference and the hoisted candidate is what must reproduce it.
  fbWorkArms = {
    hoisted = fbWorkHoisted;
    reference = fbWork;
  };
  dependentsOfArms = {
    hoisted = fx: dependentsOfHoisted fx (builtins.head fx.nodes);
    reference = fx: dependentsOf fx (builtins.head fx.nodes);
  };
in
{
  flake.tests.hoist = {
    # ── cycles: the hoisted front door against the construction it replaced ──
    test-cycles-agrees-element-wise = {
      expr = over cyclicShapes (agrees cyclesArms);
      expected = allTrue cyclicShapes;
    };
    test-cycles-reversal-control-fails = {
      expr = over cyclicShapes (disagreesReversed cyclesArms);
      expected = allFalse cyclicShapes;
    };
    test-cycles-reversal-control-is-live = {
      expr = over cyclicShapes (reversalIsLive cyclesArms);
      expected = allTrue cyclicShapes;
    };
    # THE VACUITY THE CLOSED SHAPES EXIST FOR, stated rather than implied: on the acyclic
    # skeletons both arms answer `[ ]`, so agreement there is free and the reversal cannot fire.
    # A future reader adding `chain` to the fixture set above will find this cell says why not.
    test-cycles-acyclic-agreement-is-vacuous = {
      expr = {
        chainBothEmpty = cycles (chain small) == [ ] && cyclesUnhoisted (chain small) == [ ];
        fleetBothEmpty = cycles (fleet small) == [ ] && cyclesUnhoisted (fleet small) == [ ];
        chainReversalDead = revDeep (cyclesUnhoisted (chain small)) == cyclesUnhoisted (chain small);
        chainRingReversalLive =
          revDeep (cyclesUnhoisted (chainRing small)) != cyclesUnhoisted (chainRing small);
      };
      expected = {
        chainBothEmpty = true;
        fleetBothEmpty = true;
        chainReversalDead = true;
        chainRingReversalLive = true;
      };
    };

    # ── fbNode: the whole published record, on the four shapes the oracle names ──
    test-fbnode-agrees-whole-record = {
      expr = over shapes (agrees fbNodeArms);
      expected = allTrue shapes;
    };
    # And the tag map ALONE, value for value. The record cell above could in principle pass on
    # fields that agree while the naming does not; this is the field two shipped consumers group
    # their output by, so it is asserted on its own.
    test-fbnode-agrees-on-the-tag-value-for-value = {
      expr = over shapes (fx: (fbNode fx).sccOf == (fbNodeUnhoisted fx).sccOf);
      expected = allTrue shapes;
    };
    # The ordered fields on their own, for the same reason.
    test-fbnode-agrees-on-ordered-fields = {
      expr = over shapes (fx: {
        reps = (fbNode fx).reps == (fbNodeUnhoisted fx).reps;
        bottomUp = (fbNode fx).bottomUp == (fbNodeUnhoisted fx).bottomUp;
        sccs = (fbNode fx).sccs == (fbNodeUnhoisted fx).sccs;
      });
      expected = builtins.mapAttrs (_: _: {
        reps = true;
        bottomUp = true;
        sccs = true;
      }) shapes;
    };
    test-fbnode-reversal-control-fails = {
      expr = over shapes (disagreesReversed fbNodeArms);
      expected = allFalse shapes;
    };
    test-fbnode-reversal-control-is-live = {
      expr = over shapes (reversalIsLive fbNodeArms);
      expected = allTrue shapes;
    };

    # ── cyclePaths: inherits the hoist through `cycles` and the per-node arm ──
    # COST ONLY is what the hoist claims here — this surface builds no closure of its own — so
    # these cells say the inherited change did not move the walk, and say nothing about the
    # reconstruction branch's own behaviour.
    test-cyclepaths-agrees-element-wise = {
      expr = over cyclePathsShapes (agrees cyclePathsArms);
      expected = allTrue cyclePathsShapes;
    };
    test-cyclepaths-reversal-control-fails = {
      expr = over cyclePathsShapes (disagreesReversed cyclePathsArms);
      expected = allFalse cyclePathsShapes;
    };
    test-cyclepaths-reversal-control-is-live = {
      expr = over cyclePathsShapes (reversalIsLive cyclePathsArms);
      expected = allTrue cyclePathsShapes;
    };

    # ── the two declined arms: rejected on COST, and these say so ──
    test-fbwork-hoisted-candidate-would-have-agreed = {
      expr = over shapes (agrees fbWorkArms);
      expected = allTrue shapes;
    };
    test-fbwork-hoisted-candidate-reversal-control-fails = {
      expr = over shapes (disagreesReversed fbWorkArms);
      expected = allFalse shapes;
    };
    test-fbwork-hoisted-candidate-reversal-control-is-live = {
      expr = over shapes (reversalIsLive fbWorkArms);
      expected = allTrue shapes;
    };
    test-dependentsof-hoisted-candidate-would-have-agreed = {
      expr = over shapes (agrees dependentsOfArms);
      expected = allTrue shapes;
    };
    test-dependentsof-hoisted-candidate-reversal-control-fails = {
      expr = over shapes (disagreesReversed dependentsOfArms);
      expected = allFalse shapes;
    };
    test-dependentsof-hoisted-candidate-reversal-control-is-live = {
      expr = over shapes (reversalIsLive dependentsOfArms);
      expected = allTrue shapes;
    };

    # ── THE HOISTED OPERATORS AGAINST THE ONES THEY MIRROR, DIRECTLY ──
    # Above, the hoist is read through four consumers. Here it is read at the binding itself, on
    # every node of every shape, so a divergence cannot be one a consumer happens to wash out.
    test-reachableVia-equals-reachableFrom-at-every-node = {
      expr = over shapes (
        fx:
        let
          succ = hoistEdges fx;
        in
        builtins.all (v: reachableVia succ v == reachableFrom { inherit (fx) edges; } v) fx.nodes
      );
      expected = allTrue shapes;
    };
    test-selfReachableVia-equals-selfReachable-at-every-node = {
      expr = over cyclicShapes (
        fx:
        let
          succ = hoistEdges fx;
        in
        builtins.all (
          v: genGraph.selfReachableVia succ v == selfReachable { inherit (fx) edges; } v
        ) fx.nodes
      );
      expected = allTrue cyclicShapes;
    };
    # ARMED: the predicate the cell above rests on must be capable of BOTH answers in the same
    # run, or "they agree" could be "they both say false everywhere".
    test-selfReachable-predicate-answers-both-ways = {
      expr = {
        ring = builtins.all (v: selfReachable { edges = (cycle small).edges; } v) (cycle small).nodes;
        chain = builtins.any (v: selfReachable { edges = (chain small).edges; } v) (chain small).nodes;
      };
      expected = {
        ring = true;
        chain = false;
      };
    };

    # ── THE WRAP MUST NOT NARROW THE WALK ──
    # `hoistEdges` reads the accessor over `nodes`, but a traversal may leave that set: an
    # accessor whose `edges` answers for an id the caller did not enumerate is legal, and the
    # unhoisted operators follow it. The fallback in `hoistEdges` is what keeps that true.
    #
    # ★ THE UNENUMERATED NODE MUST ITSELF HAVE AN OUT-EDGE, and this cell was WRONG before it
    # did. With `c` a leaf, a wrap without the fallback answers `[ ]` for `c` and the accessor
    # answers `[ ]` too, so the two arms agree and the cell passes with the fallback deleted —
    # a predicate that could not have matched. `c -> d` is what makes the difference observable:
    # dropping the fallback loses `d`.
    test-hoist-follows-edges-outside-the-enumerated-node-set = {
      expr =
        let
          dangling = {
            nodes = [
              "a"
              "b"
            ];
            edges =
              id:
              {
                a = [ "b" ];
                b = [ "c" ];
                c = [ "d" ];
                d = [ ];
              }
              .${id} or [ ];
          };
        in
        {
          hoisted = reachableVia (hoistEdges dangling) "a";
          shipped = reachableFrom { inherit (dangling) edges; } "a";
        };
      expected = {
        hoisted = [
          "b"
          "c"
          "d"
        ];
        shipped = [
          "b"
          "c"
          "d"
        ];
      };
    };
  };
}
