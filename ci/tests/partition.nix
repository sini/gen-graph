# The SCC PARTITION door against its arms, on the generated shapes.
#
# `fbNode` and `fbWork` are the two forward–backward arms published under their own names;
# `condensationClosure` is the closure construction published under its; `condensation` is the
# door and today defaults to `fbNode`. The door's default is a separate decision from any
# arm's identity — that separation is the whole point of the names — so the agreement between
# them is a property measured at every revision rather than read off today's one-line
# delegation.
#
# THE REFERENCE IS THE CLOSURE ARM. It is the construction every one of these fixtures was
# partitioned by before the arms existed, and it decides co-SCC membership by materializing
# the whole transitive closure and asking it — an independent route to the same partition,
# not a rearrangement of the same walk. Its own ceiling is a fixpoint iteration cap, and
# every fixture here has a diameter far below it, so the reference answers on all of them.
# That is stated rather than assumed: an identity oracle whose reference throws is a red cell
# blamed on the new arm.
#
# ELEMENT-WISE, never a summary, and never a sample of fields. `{ first, last, len }`
# agreement is not agreement, and neither is agreeing on `sccs` while disagreeing on the tag:
# two valid partitions of the same graph can share every class and differ on which member
# names it, and the naming is what two shipped consumers group their OUTPUT by. Every cell
# below compares whole values.
#
# ── AND THE REPRESENTATIVE IS PART OF THE ORACLE, NOT AN IMPLEMENTATION DETAIL ──
# The tag is the component's SMALLEST member. `topoOrderKahn`'s cycle report and `cyclePaths`
# both group by the tag and feed the grouping to an iteration in sorted key order, so an arm
# that agrees on the classes and picks a different member as the tag silently reorders both.
# The cells pin `sccOf` value-for-value, and the armed control is an arm that gets the classes
# right and the tag wrong — it must FAIL, or the comparison is blind to exactly the thing that
# breaks those consumers.
#
# The shapes are the bench's, verbatim, so a figure measured in `ci/bench/cost-classes.nix`
# and a verdict asserted here are about the same graphs.
{ genGraph, genPrelude, ... }:
let
  inherit (genGraph)
    condensation
    condensationClosure
    fbNode
    fbWork
    reachableFrom
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

  # node i depends on i-1: n singleton components in a line, keys ascending with depth.
  chain =
    n:
    fromPairs (map (key "n") (ix n)) (
      map (i: {
        name = key "n" i;
        value = if i == 0 then [ ] else [ (key "n" (i - 1)) ];
      }) (ix n)
    );
  # the simple ring: out-degree 1, ONE component of n members, diameter n. The only shape
  # here whose partition is not all singletons, and therefore the only one on which a
  # representative can be got wrong or a multi-member term dropped.
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
  # n/2 independent 2-chains; every producer key sorts below every consumer key.
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
  # n/2 ready at the start, each releasing one whose key sorts BELOW every node still waiting.
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
  # one hub DEPENDING ON n-1 leaves: closure cardinality n-1, longest path 1.
  fan =
    n:
    fromPairs ([ "hub" ] ++ map (key "l") (ix (n - 1))) [
      {
        name = "hub";
        value = map (key "l") (ix (n - 1));
      }
    ];
  # n-1 dependents on ONE hub: closure cardinality 1, longest path 1. The depth-1
  # discriminator — the mirror of `fan`, and the shape that says a reading is not merely
  # counting nodes.
  star =
    n:
    fromPairs ([ "hub" ] ++ map (key "d") (ix (n - 1))) (
      map (i: {
        name = key "d" i;
        value = [ "hub" ];
      }) (ix (n - 1))
    );
  # src -> n-2 middles -> snk: cardinality n-1, longest path 2. Shallow, but every middle is
  # a distinct path the traversal must actually walk.
  bush =
    n:
    let
      m = n - 2;
    in
    fromPairs ([ "src" ] ++ map (key "m") (ix m) ++ [ "snk" ]) (
      [
        {
          name = "src";
          value = map (key "m") (ix m);
        }
      ]
      ++ map (i: {
        name = key "m" i;
        value = [ "snk" ];
      }) (ix m)
    );
  # A 10-chain c9 -> … -> c0, with c0 ALSO depending on 10 leaves. 20 nodes, 20 components.
  # ★ THE ONLY FIXTURE HERE WHERE BOTH QUANTITIES EXCEED 1 AND DIFFER — cardinality 19,
  # longest path 10 — so it is the one that catches a cardinality/longest-path swap. A suite
  # of chains passes with either wired, because on a chain they are equal.
  # ★★ ONE ENTRY PER NAME. `builtins.listToAttrs` is FIRST-WINS on a duplicate name, silently:
  # a builder emitting `c0` twice keeps the first and drops the fan, leaving a 10-chain plus 10
  # orphans that evaluates fine and returns a plausible number. The edges-present cells below
  # are what catch that, and they are why they exist.
  deepfan =
    let
      leaves = map (i: "d${toString i}") (ix 10);
    in
    fromPairs (map (i: "c${toString i}") (ix 10) ++ leaves) (
      map (i: {
        name = "c${toString i}";
        value = if i == 0 then leaves else [ "c${toString (i - 1)}" ];
      }) (ix 10)
      ++ map (i: {
        name = "d${toString i}";
        value = [ ];
      }) (ix 10)
    );

  # Small enough that the closure reference runs in a suite, large enough that the arms could
  # diverge anywhere in tens of components rather than in a handful. The reference is
  # super-quadratic; scale belongs to `ci/bench/cost-classes.nix`, agreement belongs here.
  small = 60;
  shapes = {
    chain = chain small;
    cycle = cycle small;
    wide = wide small;
    fleet = fleet small;
    discrim = discrim small;
    fan = fan small;
    bush = bush small;
    star = star small;
  };
  shipped = {
    inherit (genGraph.fixtures)
      chain
      cyclic
      diamond
      disconnected
      serviceGraph
      tree
      ;
  };
  allFixtures = shapes // builtins.mapAttrs (n: v: v) shipped;
  # The shapes whose partition has a component with more than one member. A control that
  # varies the REPRESENTATIVE cannot fire on a singleton partition — the smallest member and
  # the largest are the same node — so a control run over the acyclic shapes would report
  # agreement and prove nothing.
  multiMember = {
    inherit (shapes) cycle;
    inherit (shipped) cyclic;
  };
  # The shapes with at least two components, which is what a reversal control needs: reversing
  # a one-element order is the identity, and a control that cannot differ is not a control.
  manyTags = builtins.removeAttrs allFixtures [
    "cycle"
    "cyclic"
  ];

  # THE WRONG-REPRESENTATIVE ARM, as an armed control: the same forward–backward classes with
  # the tag taken as the component's LARGEST member instead of its smallest. It agrees with
  # every arm on the classes and disagrees on every tag of every multi-member component.
  maxTagArm =
    accessor@{ edges, nodes, ... }:
    let
      rev = genGraph.transpose accessor;
      forward = prelude.genAttrs nodes (v: reachableFrom { inherit edges; } v);
      backward = prelude.genAttrs nodes (
        v: prelude.genAttrs (reachableFrom { inherit (rev) edges; } v) (_: true)
      );
    in
    prelude.genAttrs nodes (
      v:
      prelude.last (
        builtins.sort builtins.lessThan ([ v ] ++ builtins.filter (u: backward.${v} ? ${u}) forward.${v})
      )
    );

  reversed =
    xs: builtins.genList (i: builtins.elemAt xs (builtins.length xs - 1 - i)) (builtins.length xs);
  # The classes as a SET-shaped value, so "same partition, different tag" is expressible: the
  # member lists sorted, independent of which member names each one.
  classesOf = c: builtins.sort (a: b: builtins.head a < builtins.head b) c.sccs;

  # ── the derivability check ──
  # Σ_v |reach(v)| over ATOMS, computed two ways. `direct` walks every atom. `derived` reads
  # only the published partition — no atom traversal at all: a member of class C reaches the
  # other |C|-1 members of C plus every member of every class C reaches. `derivedWrong` drops
  # the same-class term, which is zero on a singleton partition and is the whole answer on a
  # ring — so it agrees everywhere except where the property actually lives.
  sumReachDirect =
    g: builtins.foldl' (a: v: a + builtins.length (reachableFrom { inherit (g) edges; } v)) 0 g.nodes;
  sumReachFrom =
    keepSameClass: g:
    let
      c = condensation g;
      size = t: builtins.length c.members.${t};
      out =
        t: builtins.foldl' (a: d: a + size d) 0 (reachableFrom { edges = r: c.condEdges.${r} or [ ]; } t);
    in
    builtins.foldl' (a: t: a + size t * ((if keepSameClass then size t - 1 else 0) + out t)) 0 c.reps;
  sumReachDerived = sumReachFrom true;
  sumReachDerivedWrong = sumReachFrom false;

  # Max closure CARDINALITY over the condensation DAG — the quantity the published `depth` is
  # NOT, kept here only so a cell can show the two separating on the fixture where they do.
  maxCardinality =
    g:
    let
      c = condensation g;
    in
    builtins.foldl' (
      a: t: prelude.max a (builtins.length (reachableFrom { edges = r: c.condEdges.${r} or [ ]; } t))
    ) 0 c.reps;
in
{
  flake.tests.partition = {
    # ── the per-node arm against the closure reference, whole record, every fixture ──
    test-fbnode-equals-closure-reference = {
      expr = builtins.mapAttrs (_: fx: fbNode fx == condensationClosure fx) allFixtures;
      expected = builtins.mapAttrs (_: _: true) allFixtures;
    };
    # And the tag map on its own, VALUE FOR VALUE, so the cell above cannot be passing on a
    # field that happens to agree while the naming does not.
    test-fbnode-tag-map-value-for-value = {
      expr = builtins.mapAttrs (_: fx: (fbNode fx).sccOf == (condensationClosure fx).sccOf) allFixtures;
      expected = builtins.mapAttrs (_: _: true) allFixtures;
    };

    # ── the worklist arm, against the reference AND against the other arm ──
    test-fbwork-equals-closure-reference = {
      expr = builtins.mapAttrs (_: fx: fbWork fx == condensationClosure fx) allFixtures;
      expected = builtins.mapAttrs (_: _: true) allFixtures;
    };
    test-fbwork-equals-fbnode = {
      expr = builtins.mapAttrs (_: fx: fbWork fx == fbNode fx) allFixtures;
      expected = builtins.mapAttrs (_: _: true) allFixtures;
    };
    test-fbwork-tag-map-value-for-value = {
      expr = builtins.mapAttrs (_: fx: (fbWork fx).sccOf == (condensationClosure fx).sccOf) allFixtures;
      expected = builtins.mapAttrs (_: _: true) allFixtures;
    };

    # ── ARMED: the classes right, the representative wrong ──
    # The control arm returns the SAME partition and tags each component with its largest
    # member. The classes must still agree — otherwise the control is a different partition
    # and says nothing about naming — and the tag map must NOT.
    test-wrong-representative-control-same-classes = {
      expr = builtins.mapAttrs (
        _: fx:
        classesOf (fbNode fx) == builtins.sort (a: b: builtins.head a < builtins.head b) (
          map (t: builtins.sort builtins.lessThan t) (
            prelude.mapAttrsToList (_: g: g) (builtins.groupBy (v: (maxTagArm fx).${v}) fx.nodes)
          )
        )
      ) multiMember;
      expected = builtins.mapAttrs (_: _: true) multiMember;
    };
    test-wrong-representative-control-fails = {
      expr = builtins.mapAttrs (_: fx: (fbNode fx).sccOf == maxTagArm fx) multiMember;
      expected = builtins.mapAttrs (_: _: false) multiMember;
    };

    # ── the door against its default arm, and against the other one ──
    test-door-equals-default-arm = {
      expr = builtins.mapAttrs (_: fx: condensation fx == fbNode fx) allFixtures;
      expected = builtins.mapAttrs (_: _: true) allFixtures;
    };
    # The door against the arm it does NOT default to: the ruling requires the partition and
    # the representative to agree. They agree on every published field here, because the
    # order-shaped fields are computed from the partition by one pass both arms share — so the
    # cell asserts the stronger property and says which part the contract requires.
    test-door-and-worklist-arm-agree-on-partition-and-tag = {
      expr = builtins.mapAttrs (_: fx: {
        classes = classesOf (condensation fx) == classesOf (fbWork fx);
        tags = (condensation fx).sccOf == (fbWork fx).sccOf;
        wholeRecord = condensation fx == fbWork fx;
      }) allFixtures;
      expected = builtins.mapAttrs (_: _: {
        classes = true;
        tags = true;
        wholeRecord = true;
      }) allFixtures;
    };
    # ARMED CONTROL for the agreement cells: a reversal must NOT compare equal on any shape
    # with more than one component. If it did, the comparison would agree with anything.
    test-door-arm-reversal-control = {
      expr = builtins.mapAttrs (_: fx: {
        bottomUp = (condensation fx).bottomUp == reversed (fbNode fx).bottomUp;
        sccs = (condensation fx).sccs == reversed (fbNode fx).sccs;
      }) manyTags;
      expected = builtins.mapAttrs (_: _: {
        bottomUp = false;
        sccs = false;
      }) manyTags;
    };

    # ── the published depth field ──
    # Longest path over the condensation DAG. `chain` and `star` are the AGREEING cells —
    # both quantities coincide there, so a broken reading surfaces as disagreement — and
    # `fan`, `bush` and `deepfan` SEPARATE them.
    test-depth-chain-20 = {
      expr = (condensation (chain 20)).depth;
      expected = 19;
    };
    test-depth-star-20 = {
      expr = (condensation (star 20)).depth;
      expected = 1;
    };
    test-depth-fan-20 = {
      expr = (condensation (fan 20)).depth;
      expected = 1;
    };
    test-depth-bush-20 = {
      expr = (condensation (bush 20)).depth;
      expected = 2;
    };
    # THE DISCRIMINATING CELL: both quantities exceed 1 and differ. Read in one expression so
    # a swap cannot pass by agreeing on the other fixture.
    test-depth-deepfan-against-cardinality = {
      expr = {
        depth = (condensation deepfan).depth;
        cardinality = maxCardinality deepfan;
      };
      expected = {
        depth = 10;
        cardinality = 19;
      };
    };
    # The same separation stated as an inequality on every shape: a path out of a class visits
    # distinct classes (the quotient is acyclic, so none repeats) and all of them are in that
    # class's closure, so cardinality >= longest path POINTWISE, hence for the maxima. A
    # reading that swapped the two would break this on `fan`, `bush` and `deepfan`.
    test-cardinality-dominates-depth = {
      expr = builtins.mapAttrs (_: fx: maxCardinality fx >= (condensation fx).depth) (
        allFixtures // { inherit deepfan; }
      );
      expected = builtins.mapAttrs (_: _: true) (allFixtures // { inherit deepfan; });
    };

    # ── EDGES-PRESENT, one cell per depth fixture ──
    # A fixture that silently lost the shape it exists to test still evaluates and still
    # returns a plausible number, so a cell that only reads the output cannot catch its own
    # fixture. These read the fixture itself.
    test-fixtures-edges-present = {
      expr = {
        chain20 = {
          nodes = builtins.length (chain 20).nodes;
          deep = (chain 20).edges (key "n" 19);
          root = (chain 20).edges (key "n" 0);
        };
        fan20 = {
          nodes = builtins.length (fan 20).nodes;
          hubOut = builtins.length ((fan 20).edges "hub");
          leafOut = (fan 20).edges (key "l" 0);
        };
        star20 = {
          nodes = builtins.length (star 20).nodes;
          hubOut = (star 20).edges "hub";
          leafOut = (star 20).edges (key "d" 0);
        };
        bush20 = {
          nodes = builtins.length (bush 20).nodes;
          srcOut = builtins.length ((bush 20).edges "src");
          midOut = (bush 20).edges (key "m" 0);
          snkOut = (bush 20).edges "snk";
        };
        deepfan = {
          nodes = builtins.length deepfan.nodes;
          components = builtins.length (condensation deepfan).sccs;
          c0Out = builtins.length (deepfan.edges "c0");
          c9Out = deepfan.edges "c9";
          leafOut = deepfan.edges "d0";
        };
      };
      expected = {
        chain20 = {
          nodes = 20;
          deep = [ (key "n" 18) ];
          root = [ ];
        };
        fan20 = {
          nodes = 20;
          hubOut = 19;
          leafOut = [ ];
        };
        star20 = {
          nodes = 20;
          hubOut = [ ];
          leafOut = [ "hub" ];
        };
        bush20 = {
          nodes = 20;
          srcOut = 18;
          midOut = [ "snk" ];
          snkOut = [ ];
        };
        deepfan = {
          nodes = 20;
          components = 20;
          c0Out = 10;
          c9Out = [ "c8" ];
          leafOut = [ ];
        };
      };
    };

    # ── every other measure is DERIVABLE from the published partition ──
    # The soundness of publishing the partition and no measure, made checkable: the atom-domain
    # sum computed by walking every atom, and computed from `{ sccs, sccOf, condEdges }` alone.
    test-sum-reach-derivable-from-partition = {
      expr = builtins.mapAttrs (_: fx: sumReachDirect fx == sumReachDerived fx) (
        allFixtures // { inherit deepfan; }
      );
      expected = builtins.mapAttrs (_: _: true) (allFixtures // { inherit deepfan; });
    };
    # The values themselves, on the five shapes at n = 20 — five DIFFERENT numbers, so the
    # agreement above is not a degenerate coincidence.
    test-sum-reach-values-at-20 = {
      expr = {
        chain = sumReachDirect (chain 20);
        fan = sumReachDirect (fan 20);
        bush = sumReachDirect (bush 20);
        deepfan = sumReachDirect deepfan;
        cycle = sumReachDirect (cycle 20);
      };
      expected = {
        chain = 190;
        fan = 19;
        bush = 37;
        deepfan = 145;
        cycle = 380;
      };
    };
    # ARMED: the same derivation with the multi-member term dropped. It agrees on every
    # singleton partition — its dropped term is zero there — and MUST disagree on the ring,
    # the one fixture whose partition has a component with more than one member. That is what
    # says the agreement above is a property of the construction and not of singletons.
    test-sum-reach-armed-control = {
      expr = {
        chain = sumReachDirect (chain 20) == sumReachDerivedWrong (chain 20);
        fan = sumReachDirect (fan 20) == sumReachDerivedWrong (fan 20);
        bush = sumReachDirect (bush 20) == sumReachDerivedWrong (bush 20);
        deepfan = sumReachDirect deepfan == sumReachDerivedWrong deepfan;
        cycle = sumReachDirect (cycle 20) == sumReachDerivedWrong (cycle 20);
        cycleWrongValue = sumReachDerivedWrong (cycle 20);
      };
      expected = {
        chain = true;
        fan = true;
        bush = true;
        deepfan = true;
        cycle = false;
        cycleWrongValue = 0;
      };
    };

    # ── the arms are LIVE SURFACES, called by name ──
    # Not reached through the door in any of these: a name that only ever runs because
    # something else delegates to it is not published.
    test-arms-direct-by-name = {
      expr =
        let
          g = {
            nodes = [
              "a"
              "b"
              "c"
              "d"
            ];
            edges =
              id:
              {
                a = [ "b" ];
                b = [ "c" ];
                c = [ "a" ];
                d = [ "a" ];
              }
              .${id} or [ ];
          };
        in
        {
          node = (fbNode g).sccs;
          work = (fbWork g).sccs;
          closure = (condensationClosure g).sccs;
        };
      expected = {
        node = [
          [
            "a"
            "b"
            "c"
          ]
          [ "d" ]
        ];
        work = [
          [
            "a"
            "b"
            "c"
          ]
          [ "d" ]
        ];
        closure = [
          [
            "a"
            "b"
            "c"
          ]
          [ "d" ]
        ];
      };
    };
  };
}
