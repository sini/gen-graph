# Guard tests for the cone-local rank (coneRank) + direct reverse-adjacency
# (directDependents / directDependentsOf).
#
# Edge convention (consumer -> producer): `accessor.edges id = [ids id depends on]`.
# So a sound `coneRank.order` has every PRODUCER before its CONSUMER, i.e. for every
# edge { from = consumer; to = producer; } the producer precedes the consumer.
#
# coneRank is LOAD-BEARING for gen-rebuild's propagateEager (V-push): the worklist
# drains in producers-first rank order, byte-identical to a full build ONLY IF every
# dependency is ranked before its dependent. directDependents must be DIRECT (the
# immediate reverse neighbours) and NOT the transitive closure (dependentsOf) — the
# distinction is the whole point of the primitive (transitive would re-materialise
# O(|cone|) per move and silently defeat the minimality cutoff).
{
  lib,
  genGraph,
  ...
}:
let
  inherit (genGraph)
    mkGraph
    coneRank
    directDependents
    directDependentsOf
    dependentsOf
    condensation
    ;

  # --- A -> B -> X chain (edges: B deps A, X deps B). Producer A first. ---------
  chain = mkGraph {
    edges = [
      {
        from = "B";
        to = "A";
      }
      {
        from = "X";
        to = "B";
      }
    ];
  };

  # --- diamond: D deps {B,C}, B deps A, C deps A. Producer A first, D last. ------
  diamond = mkGraph {
    edges = [
      {
        from = "B";
        to = "A";
      }
      {
        from = "C";
        to = "A";
      }
      {
        from = "D";
        to = "B";
      }
      {
        from = "D";
        to = "C";
      }
    ];
  };
  diamondEdges = [
    {
      from = "B";
      to = "A";
    }
    {
      from = "C";
      to = "A";
    }
    {
      from = "D";
      to = "B";
    }
    {
      from = "D";
      to = "C";
    }
  ];

  # --- wide fan: c0..c3 each depend on a single producer p. p first. ------------
  wideFan = mkGraph {
    edges =
      map
        (c: {
          from = c;
          to = "p";
        })
        [
          "c0"
          "c1"
          "c2"
          "c3"
        ];
  };
  wideFanEdges =
    map
      (c: {
        from = c;
        to = "p";
      })
      [
        "c0"
        "c1"
        "c2"
        "c3"
      ];

  # index of x in a list (linear scan; fixtures are tiny).
  indexOf =
    xs: x:
    let
      go =
        i: rest:
        if rest == [ ] then
          -1
        else if builtins.head rest == x then
          i
        else
          go (i + 1) (builtins.tail rest);
    in
    go 0 xs;
  precedes =
    order: a: b:
    indexOf order a < indexOf order b;
  # every edge { from = consumer; to = producer; } has producer before consumer.
  producersFirst = order: edgeList: builtins.all (e: precedes order e.to e.from) edgeList;
in
{
  flake.tests.topo = {
    # --- coneRank: producers-first order ---------------------------------------

    # 3-chain A->B->X: producers-first order is exactly [A B X], depths 0,1,2.
    test-conerank-chain-order = {
      expr = (coneRank chain chain.nodes).order;
      expected = [
        "A"
        "B"
        "X"
      ];
    };
    test-conerank-chain-depth = {
      expr = (coneRank chain chain.nodes).depth;
      expected = {
        A = 0;
        B = 1;
        X = 2;
      };
    };

    # diamond: every edge has its producer before its consumer in `order`.
    test-conerank-diamond-deps-first = {
      expr = producersFirst (coneRank diamond diamond.nodes).order diamondEdges;
      expected = true;
    };
    # diamond depths: A=0, B=C=1, D=2 (1 + max(depth B, depth C)).
    test-conerank-diamond-depth = {
      expr = (coneRank diamond diamond.nodes).depth;
      expected = {
        A = 0;
        B = 1;
        C = 1;
        D = 2;
      };
    };

    # wide fan: every consumer's single producer p precedes it in `order`.
    test-conerank-widefan-deps-first = {
      expr = producersFirst (coneRank wideFan wideFan.nodes).order wideFanEdges;
      expected = true;
    };
    # the producer p ranks first (depth 0); every consumer depth 1.
    test-conerank-widefan-producer-first = {
      expr = builtins.head (coneRank wideFan wideFan.nodes).order;
      expected = "p";
    };

    # cone-local: ranking a SUB-cone {B,X} (A excluded) makes B a depth-0 root —
    # the in-cone producer set of B is empty once A is out of the cone.
    test-conerank-subcone-local = {
      expr =
        (coneRank chain [
          "B"
          "X"
        ]).depth;
      expected = {
        B = 0;
        X = 1;
      };
    };

    # topological consistency: coneRank.order agrees with the whole-graph reference
    # condensation.bottomUp — for every edge the producer precedes the consumer in
    # BOTH (robust to tie-break differences).
    test-conerank-agrees-condensation = {
      expr = {
        coneRank = producersFirst (coneRank diamond diamond.nodes).order diamondEdges;
        cond = producersFirst (condensation diamond).bottomUp diamondEdges;
      };
      expected = {
        coneRank = true;
        cond = true;
      };
    };

    # --- directDependents / directDependentsOf: DIRECT, not transitive ----------

    # On A->B->X: A's DIRECT dependent is just B; the TRANSITIVE dependents are B,X.
    test-direct-not-transitive = {
      expr = {
        direct = directDependentsOf chain "A";
        transitive = dependentsOf chain "A";
      };
      expected = {
        direct = [ "B" ];
        transitive = [
          "B"
          "X"
        ];
      };
    };

    # B's direct dependent is X (the next link).
    test-direct-mid-chain = {
      expr = directDependentsOf chain "B";
      expected = [ "X" ];
    };

    # X is a sink: no consumer reads it, so directDependentsOf returns [].
    test-direct-sink-empty = {
      expr = directDependentsOf chain "X";
      expected = [ ];
    };

    # the full reverse-adjacency map keys only producers that have a dependent.
    test-direct-full-map = {
      expr = directDependents chain;
      expected = {
        A = [ "B" ];
        B = [ "X" ];
      };
    };

    # diamond: A's direct dependents are B and C (both immediate consumers of A).
    test-direct-diamond-fan = {
      expr = builtins.sort builtins.lessThan (directDependentsOf diamond "A");
      expected = [
        "B"
        "C"
      ];
    };
  };
}
