# ── THE ARRIVAL CARRIER ─────────────────────────────────────────────────────────
# `queryArrivals` is the edge-keyed, order-preserving, distance-carrying walk over the
# same product automaton `queryAll` closes. Every test that claims the carrier keeps
# something runs against a `queryAll` control on the same graph in the same evaluation,
# because the whole content of the claim is a DIFFERENCE from the shipped surface.
{ genGraph, ... }:
let
  inherit (genGraph)
    labeledFrom
    labeledFixtures
    query
    queryArrivals
    regex
    ;
  r = regex;
  hop = s: s.distance + 1;
  vias = map (x: if x.via == null then null else x.via.label);
  nodesOf = map (x: x.node);
  distancesAt = node: xs: map (x: x.distance) (builtins.filter (x: x.node == node) xs);
  minOf = builtins.foldl' (a: b: if b < a then b else a) 999;

  # two DISTINCT labels reaching one node — the dual-inclusion pair
  dual = labeledFrom {
    nodes = [
      "s"
      "x"
    ];
    perLabel = {
      a = id: if id == "s" then [ "x" ] else [ ];
      b = id: if id == "s" then [ "x" ] else [ ];
    };
  };
  altAB = r.alt [
    (r.lit "a")
    (r.lit "b")
  ];

  diamond = labeledFrom {
    nodes = [
      "l"
      "r"
      "s"
      "t"
    ];
    perLabel.e =
      id:
      {
        s = [
          "l"
          "r"
        ];
        l = [ "t" ];
        r = [ "t" ];
      }
      .${id} or [ ];
  };
  fan = labeledFrom {
    nodes = [
      "a"
      "s"
      "z"
    ];
    perLabel.e =
      id:
      if id == "s" then
        [
          "z"
          "a"
        ]
      else
        [ ];
  };
  chain = labeledFrom {
    nodes = [
      "m"
      "s"
      "t"
    ];
    perLabel.p =
      id:
      {
        s = [ "m" ];
        m = [ "t" ];
      }
      .${id} or [ ];
  };

  # ADR-0016's reification: a content-bearing relation is a NODE with labelled
  # incidence, so one relation is spelled as two edges through the binding node.
  # `s` reaches `u` directly and `t` through the binding `b:1`.
  isBinding = id: builtins.substring 0 2 id == "b:";
  bindingRule = s: if isBinding s.from then s.distance else s.distance + 1;
  reified = labeledFrom {
    nodes = [
      "b:1"
      "s"
      "t"
      "u"
    ];
    perLabel.rel =
      id:
      {
        s = [
          "b:1"
          "u"
        ];
        "b:1" = [ "t" ];
      }
      .${id} or [ ];
  };
  reifiedWalk =
    advance:
    map
      (x: {
        inherit (x) node distance;
      })
      (queryArrivals {
        graph = reified;
        from = "s";
        follow = r.plus (r.lit "rel");
        inherit advance;
      });

  # Two routes to `b:3`, which is `v`'s only way in:
  #   A — three direct relations,  three hops, distance 3
  #   B — two reified relations,   four hops,  distance 2
  # They enter `b:3` by DIFFERENT edges, so both survive the edge key; they leave it
  # by the SAME edge, so only the first arrival at `v` survives.
  zeroTrap = labeledFrom {
    nodes = [
      "b:1"
      "b:2"
      "b:3"
      "m"
      "n1"
      "n2"
      "s"
      "v"
    ];
    perLabel.rel =
      id:
      {
        s = [
          "n1"
          "b:1"
        ];
        n1 = [ "n2" ];
        n2 = [ "b:3" ];
        "b:1" = [ "m" ];
        m = [ "b:2" ];
        "b:2" = [ "b:3" ];
        "b:3" = [ "v" ];
      }
      .${id} or [ ];
  };
  zeroTrapWalk =
    advance:
    queryArrivals {
      graph = zeroTrap;
      from = "s";
      follow = r.plus (r.lit "rel");
      inherit advance;
    };
in
{
  flake.tests.arrivals = {
    # ── EDGE KEYING (the dual-inclusion pair) ──
    test-arrivals-keep-both-arms-of-a-dual-inclusion-pair = {
      expr =
        let
          res = queryArrivals {
            graph = dual;
            from = "s";
            follow = altAB;
            advance = hop;
          };
        in
        {
          nodes = nodesOf res;
          labels = vias res;
        };
      expected = {
        nodes = [
          "x"
          "x"
        ];
        labels = [
          "a"
          "b"
        ];
      };
    };
    test-arrivals-CONTROL-all-collapses-the-pair-to-one-answer = {
      # the shipped ⟨node, state⟩ key derivates `a` and `b` to the same state, so the
      # second edge vanishes with nothing in the answer to say it existed
      expr = query {
        graph = dual;
        from = "s";
        follow = altAB;
        mode = "all";
      };
      expected = [ "x" ];
    };
    test-arrivals-keep-reconvergent-multiplicity = {
      expr =
        let
          res = builtins.filter (x: x.node == "t") (queryArrivals {
            graph = diamond;
            from = "s";
            follow = r.star (r.lit "e");
            advance = hop;
          });
        in
        map (x: x.via.from) res;
      expected = [
        "l"
        "r"
      ];
    };
    test-arrivals-CONTROL-all-collapses-the-diamond = {
      expr = query {
        graph = diamond;
        from = "s";
        follow = r.star (r.lit "e");
        mode = "all";
      };
      expected = [
        "l"
        "r"
        "s"
        "t"
      ];
    };
    test-arrivals-distinct-nullable-states-stay-distinct = {
      # `n` reached by `x` (residual ε) and by `y` (residual z?), both nullable
      expr =
        let
          g = labeledFrom {
            nodes = [
              "n"
              "s"
            ];
            perLabel = {
              x = id: { s = [ "n" ]; }.${id} or [ ];
              y = id: { s = [ "n" ]; }.${id} or [ ];
            };
          };
          res = queryArrivals {
            graph = g;
            from = "s";
            follow = r.parse "x | y z?";
            advance = hop;
          };
        in
        {
          labels = vias res;
          admissionsDiffer = (builtins.head res).admission != (builtins.elemAt res 1).admission;
        };
      expected = {
        labels = [
          "x"
          "y"
        ];
        admissionsDiffer = true;
      };
    };

    # ── ORDER (no post-walk sort) ──
    test-arrivals-return-traversal-order = {
      expr = nodesOf (queryArrivals {
        graph = fan;
        from = "s";
        follow = r.star (r.lit "e");
        advance = hop;
      });
      expected = [
        "s"
        "z"
        "a"
      ];
    };
    test-arrivals-CONTROL-all-returns-sorted-order = {
      # same graph, same run: `all` answers `a` first because `attrNames` sorted it
      expr = query {
        graph = fan;
        from = "s";
        follow = r.star (r.lit "e");
        mode = "all";
      };
      expected = [
        "a"
        "s"
        "z"
      ];
    };

    # ── THE ARRIVAL RECORD ──
    test-arrivals-root-arrived-by-no-edge = {
      expr = builtins.head (queryArrivals {
        graph = chain;
        from = "s";
        follow = r.star (r.lit "p");
        advance = hop;
      });
      expected = {
        node = "s";
        distance = 0;
        via = null;
        admission = "'p*";
      };
    };
    test-arrivals-carry-the-delivering-edge = {
      expr = map (x: x.via) (queryArrivals {
        graph = chain;
        from = "s";
        follow = r.plus (r.lit "p");
        advance = hop;
      });
      expected = [
        {
          from = "s";
          label = "p";
        }
        {
          from = "m";
          label = "p";
        }
      ];
    };

    # ── THE DISTANCE RULE ──
    test-arrivals-hop-count-rule = {
      expr =
        map
          (x: {
            inherit (x) node distance;
          })
          (queryArrivals {
            graph = chain;
            from = "s";
            follow = r.plus (r.lit "p");
            advance = hop;
          });
      expected = [
        {
          node = "m";
          distance = 1;
        }
        {
          node = "t";
          distance = 2;
        }
      ];
    };
    test-arrivals-rule-can-collapse-a-reified-incidence-pair = {
      # a rule that does not charge the step OUT of a binding node puts the
      # binding-mediated `t` at the same distance as the direct `u`
      expr = reifiedWalk bindingRule;
      expected = [
        {
          node = "b:1";
          distance = 1;
        }
        {
          node = "u";
          distance = 1;
        }
        {
          node = "t";
          distance = 1;
        }
      ];
    };
    test-arrivals-CONTROL-hop-count-charges-the-reified-pair-twice = {
      # same graph, same run: without the rule the reification moves the answer
      expr = reifiedWalk hop;
      expected = [
        {
          node = "b:1";
          distance = 1;
        }
        {
          node = "u";
          distance = 1;
        }
        {
          node = "t";
          distance = 2;
        }
      ];
    };

    # ── THE BOUND ON `distance`, MEASURED IN BOTH DIRECTIONS ──
    test-arrivals-zero-charging-rule-loses-a-minimum-behind-a-shared-final-edge = {
      # `b:3` is entered by two different edges, so both distances are in the answer
      # and a caller can fold the minimum. `v` is entered only through `b:3 -rel-> v`,
      # so the cheaper arrival shares a key with the dearer first one and is dropped:
      # the minimum is not merely unreported, it is ABSENT from the sequence.
      expr =
        let
          res = zeroTrapWalk bindingRule;
        in
        {
          b3 = distancesAt "b:3" res;
          b3Minimum = minOf (distancesAt "b:3" res);
          v = distancesAt "v" res;
          vMinimumIsAbsent = !(builtins.elem (minOf (distancesAt "b:3" res)) (distancesAt "v" res));
        };
      expected = {
        b3 = [
          3
          2
        ];
        b3Minimum = 2;
        v = [ 3 ];
        vMinimumIsAbsent = true;
      };
    };
    test-arrivals-CONTROL-under-hop-count-the-first-arrival-is-the-minimum = {
      # same graph, same run, a rule nondecreasing in hop count: no minimum is lost
      expr =
        let
          res = zeroTrapWalk hop;
          firstIsMin = node: builtins.head (distancesAt node res) == minOf (distancesAt node res);
        in
        {
          b3 = firstIsMin "b:3";
          v = firstIsMin "v";
        };
      expected = {
        b3 = true;
        v = true;
      };
    };

    # ── TERMINATION AND LAZINESS ──
    test-arrivals-cycle-terminates = {
      expr = nodesOf (queryArrivals {
        graph = labeledFixtures.cyclic;
        from = "a";
        follow = r.parse "contains* member";
        advance = hop;
      });
      expected = [ "m" ];
    };
    test-arrivals-self-loop-terminates = {
      expr = map (x: x.distance) (queryArrivals {
        graph = labeledFrom {
          nodes = [ "s" ];
          perLabel.hop = id: { s = [ "s" ]; }.${id} or [ ];
        };
        from = "s";
        follow = r.plus (r.lit "hop");
        advance = hop;
      });
      expected = [ 1 ];
    };
    test-arrivals-laziness-poison-unreached = {
      expr = nodesOf (queryArrivals {
        graph = labeledFixtures.poisoned;
        from = "a";
        follow = r.parse "safe";
        advance = hop;
      });
      expected = [ "b" ];
    };
    test-arrivals-where-filters-answers-not-the-walk = {
      expr = nodesOf (queryArrivals {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.parse "contains*";
        advance = hop;
        where = id: id == "u2";
      });
      expected = [ "u2" ];
    };
  };
}
