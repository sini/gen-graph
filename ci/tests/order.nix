{ genGraph, ... }:
let
  inherit (genGraph)
    entryAnywhere
    entryAfter
    entryBefore
    entryBetween
    phaseOrder
    topoOrder
    ;

  # An accessor from an explicit adjacency map. Library direction: `edges u ∋ v` means
  # "u depends on v", so an ordering puts every v before the u that names it.
  acc = nodes: m: {
    inherit nodes;
    edges = id: m.${id} or [ ];
  };

  # The chain a→b→c→d read as dependencies: d is the only producer.
  chain =
    acc
      [
        "a"
        "b"
        "c"
        "d"
      ]
      {
        a = [ "b" ];
        b = [ "c" ];
        c = [ "d" ];
      };

  # A total order over strings — every pair comparable, so exactly one valid ordering.
  # This is the shape gen-prelude's retired `asc` comparator cases asserted.
  totalOrder =
    ns:
    acc ns (
      builtins.listToAttrs (
        map (x: {
          name = x;
          value = builtins.filter (y: y < x) ns;
        }) ns
      )
    );

  didThrow = v: !(builtins.tryEval (builtins.deepSeq v true)).success;
in
{
  flake.tests.order = {
    # ── entry* shapes (data-free: dispatch reads only the phase NAME) ──
    test-entry-anywhere-shape = {
      expr = entryAnywhere;
      expected = {
        before = [ ];
        after = [ ];
      };
    };
    test-entry-after-shape = {
      expr = entryAfter [ "a" ];
      expected = {
        before = [ ];
        after = [ "a" ];
      };
    };
    test-entry-before-shape = {
      expr = entryBefore [ "b" ];
      expected = {
        before = [ "b" ];
        after = [ ];
      };
    };
    test-entry-between-shape = {
      expr = entryBetween [ "c" ] [ "a" ];
      expected = {
        before = [ "c" ];
        after = [ "a" ];
      };
    };

    # ── phaseOrder: forward producers-first over the condensation ──
    test-order-linear = {
      expr = phaseOrder {
        a = entryAnywhere;
        b = entryAfter [ "a" ];
        c = entryAfter [ "b" ];
      };
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-order-before = {
      expr = phaseOrder {
        a = entryAnywhere;
        b = entryBefore [ "a" ];
      };
      expected = [
        "b"
        "a"
      ];
    };
    test-order-single-phase = {
      expr = phaseOrder { default = entryAnywhere; };
      expected = [ "default" ];
    };
    # diamond (matches the spike's ordering-delegation.nix fixture)
    test-order-diamond = {
      expr = phaseOrder {
        validate = entryAnywhere;
        resolve = entryAfter [ "validate" ];
        emit = entryAfter [ "resolve" ];
        report = entryAfter [
          "resolve"
          "emit"
        ];
      };
      expected = [
        "validate"
        "resolve"
        "emit"
        "report"
      ];
    };

    # ── independent phases: phaseOrder returns A valid topological order, not a
    # specific tie-break permutation. Assert both present (length-2 permutation);
    # any valid order is dispatch-output-equivalent because a phase's effect is
    # threaded into context only AFTER the phase. ──
    test-order-independent-permutation = {
      expr = builtins.sort builtins.lessThan (phaseOrder {
        p = entryAnywhere;
        q = entryAnywhere;
      });
      expected = [
        "p"
        "q"
      ];
    };

    # ── cycle => throw (preserves gen-dispatch dag.nix's throw-on-cycle contract) ──
    test-order-cycle-throws = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq (phaseOrder {
            a = entryAfter [ "b" ];
            b = entryAfter [ "a" ];
          }) true
        )).success;
      expected = false;
    };
    test-order-self-loop-throws = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq (phaseOrder {
            a = entryAfter [ "a" ];
          }) true
        )).success;
      expected = false;
    };

    # ── the direction contract: every ordering surface reads ONE accessor the same way ──
    # coneRank and phaseOrder were once recorded as disagreeing. They never disagreed about
    # output — that measurement handed the same accessor to surfaces that read it
    # oppositely. With phaseOrder built in the library direction, entries denoting the SAME
    # graph as `chain` produce the SAME order as the accessor surfaces.
    test-order-direction-surfaces-agree = {
      expr = {
        topo = (topoOrder chain).order;
        cone =
          (genGraph.coneRank chain [
            "a"
            "b"
            "c"
            "d"
          ]).order;
        bottomUp = (genGraph.condensation chain).bottomUp;
      };
      expected =
        let
          producersFirst = [
            "d"
            "c"
            "b"
            "a"
          ];
        in
        {
          topo = producersFirst;
          cone = producersFirst;
          bottomUp = producersFirst;
        };
    };
    test-order-phase-matches-accessor-direction = {
      expr = phaseOrder {
        a = entryAfter [ "b" ];
        b = entryAfter [ "c" ];
        c = entryAfter [ "d" ];
        d = entryAnywhere;
      };
      expected = [
        "d"
        "c"
        "b"
        "a"
      ];
    };
    # An `after`/`before` naming a phase outside `entries` is a REFUSAL, and used to be
    # accepted with the constraint silently dropped — a confidently wrong order rather
    # than no order.
    test-order-refuses-unknown-phase = {
      expr = didThrow (phaseOrder {
        a = entryAfter [ "ghost" ];
        b = entryAnywhere;
      });
      expected = true;
    };
    # LIVE CONTROL for the refusal above: a well-formed entry set in the same run is NOT
    # caught, so `didThrow` here discriminates rather than always firing.
    test-order-unknown-phase-control = {
      expr = didThrow (phaseOrder {
        a = entryAnywhere;
        b = entryAfter [ "a" ];
      });
      expected = false;
    };
    # `before` must denote the same graph as the equivalent `after`.
    test-order-before-matches-after = {
      expr =
        phaseOrder {
          a = entryAnywhere;
          b = entryBefore [ "a" ];
          c = entryBefore [ "b" ];
          d = entryBefore [ "c" ];
        } == phaseOrder {
          a = entryAfter [ "b" ];
          b = entryAfter [ "c" ];
          c = entryAfter [ "d" ];
          d = entryAnywhere;
        };
      expected = true;
    };
  };

  # ── the ordering front door ──
  # Seven cases here REPLACE gen-prelude's seven retired `toposort` cases. They are
  # replacements and not absorptions: five of the seven asserted byte-equality with
  # nixpkgs `lib.toposort`, which no longer exists to assert against, and six ran on
  # integers, which these re-express over string keys. What carries forward is the
  # ORDERING and CYCLE-REPORTING behaviour, not the two deleted guarantees.
  flake.tests.order-front-door = {
    # ← test-toposort-result: a total order sorts ascending.
    test-topo-total-order = {
      expr =
        (topoOrder (totalOrder [
          "c"
          "a"
          "b"
        ])).order;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    # ← test-toposort-chain (byte-equality retired; the ordering property kept).
    test-topo-chain = {
      expr = (topoOrder chain).order;
      expected = [
        "d"
        "c"
        "b"
        "a"
      ];
    };
    # ← test-toposort-dag: the [5 2 8 1 3] shape, string-keyed.
    test-topo-dag = {
      expr =
        (topoOrder (totalOrder [
          "5"
          "2"
          "8"
          "1"
          "3"
        ])).order;
      expected = [
        "1"
        "2"
        "3"
        "5"
        "8"
      ];
    };
    # ← test-toposort-single.
    test-topo-single = {
      expr = (topoOrder (acc [ "7" ] { })).order;
      expected = [ "7" ];
    };
    # ← test-toposort-empty: the one retired case that was already type-agnostic, so it
    # re-expresses untouched. It retires on the byte-equality ground alone.
    test-topo-empty = {
      expr = (topoOrder (acc [ ] { })).order;
      expected = [ ];
    };
    # ← test-toposort-cycle-detected: the discriminant. A cycle is `ok = false`, not a
    # missing `result` attr.
    test-topo-cycle-discriminated = {
      expr =
        (topoOrder (
          acc
            [
              "1"
              "2"
            ]
            {
              "1" = [ "2" ];
              "2" = [ "1" ];
            }
        )).ok;
      expected = false;
    };
    # ← test-toposort-cycle: the mutual 1↔2 cycle, now reporting its members.
    test-topo-cycle-members = {
      expr =
        (topoOrder (
          acc
            [
              "1"
              "2"
            ]
            {
              "1" = [ "2" ];
              "2" = [ "1" ];
            }
        )).cycles;
      expected = [
        [
          "1"
          "2"
        ]
      ];
    };
    # LIVE CONTROL for every cycle case above: the acyclic accessor in the same suite
    # reports success and carries no `cycles` at all. An absence claim about cycles
    # without a control that CAN report one is not a check.
    test-topo-acyclic-control = {
      expr = {
        inherit ((topoOrder chain)) ok;
        hasCycles = (topoOrder chain) ? cycles;
      };
      expected = {
        ok = true;
        hasCycles = false;
      };
    };

    # ── cycle reporting is SCC membership: sorted, and EVERY component ──
    # nixpkgs' DFS reported only the first cycle found; a caller fixed one, re-ran, and
    # met the next. Two disjoint cycles are both named in one pass.
    test-topo-cycles-all-components = {
      expr =
        (topoOrder (
          acc
            [
              "a"
              "b"
              "x"
              "y"
              "ok1"
              "ok2"
            ]
            {
              a = [ "b" ];
              b = [ "a" ];
              x = [ "y" ];
              y = [ "x" ];
              ok1 = [ "ok2" ];
            }
        )).cycles;
      expected = [
        [
          "a"
          "b"
        ]
        [
          "x"
          "y"
        ]
      ];
    };
    # A self-loop is a singleton component. `condensation` alone cannot tell it from an
    # acyclic node, so the report is grounded in `cycles` (self-reachability).
    test-topo-self-loop = {
      expr =
        let
          r = topoOrder (
            acc [
              "a"
              "b"
            ] { a = [ "a" ]; }
          );
        in
        {
          inherit (r) ok cycles;
        };
      expected = {
        ok = false;
        cycles = [ [ "a" ] ];
      };
    };

    # ── the front door does not throw on a cycle ──
    # Both migrating consumers render their own diagnostic from the member sets, so the
    # cycle result must be an ordinary value. `phaseOrder` is the throwing layer.
    test-topo-cycle-does-not-throw = {
      expr = didThrow (
        topoOrder (
          acc
            [
              "a"
              "b"
            ]
            {
              a = [ "b" ];
              b = [ "a" ];
            }
        )
      );
      expected = false;
    };

    # ── tie-break: caller-supplied, ascending key by default ──
    test-topo-tiebreak-default-ascending = {
      expr =
        (topoOrder (
          acc [
            "q"
            "p"
            "r"
          ] { }
        )).order;
      expected = [
        "p"
        "q"
        "r"
      ];
    };
    # gen-edge's Law E2 — incomparable nodes emit in FROZEN SORT KEY order, which is what
    # makes an ordering a function of the node SET and its edge trace a parity oracle.
    # A hardcoded name tie-break could not reproduce this; a caller-supplied key can.
    test-topo-tiebreak-canonical-key = {
      expr =
        (topoOrder {
          nodes = [
            "sink"
            "s1"
            "s2"
            "s3"
          ];
          edges =
            id:
            if id == "sink" then
              [
                "s1"
                "s2"
                "s3"
              ]
            else
              [ ];
          keyOf =
            id:
            {
              s1 = "3:s1";
              s2 = "2:s2";
              s3 = "1:s3";
              sink = "9:sink";
            }
            .${id};
        }).order;
      expected = [
        "s3"
        "s2"
        "s1"
        "sink"
      ];
    };
    # The pick is the smallest ready key GLOBALLY, not the smallest within a level: once
    # `a` is emitted, `b` becomes ready and beats the still-unemitted `z`.
    test-topo-pick-is-global-min-ready = {
      expr =
        (topoOrder (
          acc [
            "z"
            "a"
            "b"
          ] { b = [ "a" ]; }
        )).order;
      expected = [
        "a"
        "b"
        "z"
      ];
    };
    test-topo-tiebreak-lessThan = {
      expr =
        (topoOrder {
          nodes = [
            "p"
            "q"
            "r"
          ];
          edges = _: [ ];
          lessThan = a: b: a > b;
        }).order;
      expected = [
        "r"
        "q"
        "p"
      ];
    };

    # ── the type domain: `keyOf` admits nodes that are not strings ──
    # gen-prelude's retired `toposort` was polymorphic; the accessor model is string-keyed.
    # The projection is what keeps integer and record nodes expressible.
    test-topo-integer-nodes = {
      expr =
        (topoOrder {
          nodes = [
            3
            1
            2
          ];
          edges = _: [ ];
          keyOf = toString;
        }).order;
      expected = [
        1
        2
        3
      ];
    };
    test-topo-record-nodes = {
      expr =
        map (r: r.name)
          (topoOrder {
            nodes = [
              {
                name = "y";
                deps = [ "x" ];
              }
              {
                name = "x";
                deps = [ ];
              }
            ];
            edges =
              r:
              map (d: {
                name = d;
                deps = [ ];
              }) r.deps;
            keyOf = r: r.name;
          }).order;
      expected = [
        "x"
        "y"
      ];
    };

    # ── refusals are BY NAME and catchable ──
    # Letting a non-string reach `genAttrs` raises a type error that `tryEval` cannot
    # catch, so the caller loses the diagnostic entirely. Each of these three is a
    # `throw` naming the offence.
    test-topo-refuses-non-string-key = {
      expr = didThrow (topoOrder {
        nodes = [
          1
          2
        ];
        edges = _: [ ];
      });
      expected = true;
    };
    test-topo-refuses-key-collision = {
      expr = didThrow (topoOrder {
        nodes = [
          "a"
          "b"
        ];
        edges = _: [ ];
        keyOf = _: "same";
      });
      expected = true;
    };
    test-topo-refuses-dangling-edge = {
      expr = didThrow (topoOrder {
        nodes = [ "a" ];
        edges = _: [ "ghost" ];
      });
      expected = true;
    };
    # LIVE CONTROL for the refusal arm: a well-formed call in the same run is NOT caught,
    # so `didThrow` is discriminating and not merely always-true.
    test-topo-refusal-control = {
      expr = didThrow (topoOrder chain);
      expected = false;
    };

    # The loop's frame cost is constant in n, so no node count caps an ordering. A chain is
    # the shape that would cap it: a self-applying loop spends one frame per node and aborts
    # here, uncatchably, at the interpreter's call depth. 12000 is past that depth; the
    # accessors are checked separately because each forces a different amount (`.ok` forces
    # the branch condition only, `length` the spine, `head` one element).
    # The bands past what a suite can afford, and the negative control that a stack overflow
    # aborts rather than throwing, are SHELL arms: no in-language assertion observes an
    # abort, so a red arm cannot be a case here.
    test-topo-long-chain-has-no-frame-ceiling = {
      expr =
        let
          n = 12000;
          pad = i: "n${toString i}";
          idxOf = builtins.listToAttrs (
            builtins.genList (i: {
              name = pad i;
              value = i;
            }) n
          );
          r = topoOrder {
            nodes = builtins.genList pad n;
            edges =
              id:
              let
                i = idxOf.${id};
              in
              if i + 1 < n then [ (pad (i + 1)) ] else [ ];
          };
        in
        {
          inherit (r) ok;
          len = builtins.length r.order;
          first = builtins.head r.order;
          last = builtins.elemAt r.order (n - 1);
        };
      expected = {
        ok = true;
        len = 12000;
        first = "n11999";
        last = "n0";
      };
    };

    # A repeated dependency is one arc: the indegree must not count what the decrement
    # pays only once.
    test-topo-duplicate-edge-counted-once = {
      expr =
        (topoOrder (
          acc
            [
              "a"
              "b"
            ]
            {
              a = [
                "b"
                "b"
              ];
            }
        )).order;
      expected = [
        "b"
        "a"
      ];
    };
  };
}
