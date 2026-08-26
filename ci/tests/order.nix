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
    # SEEDED RED (den-hoag-qbs7): an undeclared `before` name used to be silently
    # DROPPED rather than refused — the asymmetric twin of the `after` case above, and
    # the one the shipped guard missed. Two phases: on the pre-fix code this returns
    # `[ "a" ]` (ghost's non-existent constraint vanishes) instead of throwing.
    test-order-refuses-unknown-phase-before = {
      expr = didThrow (phaseOrder {
        a = entryAnywhere;
        b = entryBefore [ "ghost" ];
      });
      expected = true;
    };
    # Same defect, ONE phase: the bead's own measurement found the silent-drop and the
    # throw selected by phase COUNT, which is the tell that the old guard was
    # positional rather than by-name. A single phase must refuse exactly as two do.
    test-order-refuses-unknown-phase-before-single = {
      expr = didThrow (phaseOrder {
        b = entryBefore [ "ghost" ];
      });
      expected = true;
    };
    # LIVE CONTROL for the `before` refusal: a well-formed `before` set is NOT caught.
    test-order-unknown-phase-before-control = {
      expr = didThrow (phaseOrder {
        a = entryAnywhere;
        b = entryBefore [ "a" ];
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
    # The DOOR against the ARM on this file's own fixtures, each emitted sequence compared
    # element-wise. `topoOrderKahn` is the same algorithm published under its own name (see
    # `lib/order.nix`); while the door delegates to it, no fixture here may read differently
    # through the two. The generated shapes and the armed reversal control are in `arms.nix`.
    test-topo-door-agrees-with-arm =
      let
        fxs = [
          chain
          (totalOrder [
            "c"
            "a"
            "b"
          ])
          (acc [ "7" ] { })
          (acc [ ] { })
        ];
      in
      {
        expr = map (fx: (topoOrder fx).order) fxs;
        expected = map (fx: (genGraph.topoOrderKahn fx).order) fxs;
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
    # The retired gen-edge's Law E2 (ADR-0010 §3) — incomparable nodes emit in FROZEN SORT
    # KEY order, which is what makes an ordering a function of the node SET and made its edge
    # trace a parity oracle. A hardcoded name tie-break could not reproduce this; a
    # caller-supplied key can. The law is cited, not depended on: it names where the
    # requirement on this arm came from, and it outlived the library that stated it.
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

    # ── the ready set's DISCRIMINATING shape ──
    # `discrim` below is built so that greedy min-key and tail-append DISAGREE, and it is
    # the only shape here that can tell them apart. Three nodes `m<i>` are ready at the
    # start; emitting `m<i>` releases `a<i>`, whose key sorts BELOW every unconsumed `m`.
    # Greedy min-key must therefore interleave; anything that appends arrivals to a tail
    # and never revisits them emits every `m` first.
    #
    # A TIE-PRODUCING shape is not automatically a discriminating one, so this is not a
    # substitute for the shapes above: on a chain the ready set never holds two elements;
    # on `wide` all producer keys sort below all consumer keys, so re-sorting and appending
    # agree; on a binary tree the two children arrive already in order. All three admit a
    # wrong ready set. This one does not.
    test-topo-discriminating-interleaves = {
      expr =
        (topoOrder (
          acc
            [
              "m0"
              "m1"
              "m2"
              "a0"
              "a1"
              "a2"
            ]
            {
              a0 = [ "m0" ];
              a1 = [ "m1" ];
              a2 = [ "m2" ];
            }
        )).order;
      expected = [
        "m0"
        "a0"
        "m1"
        "a1"
        "m2"
        "a2"
      ];
    };

    # ★ And this is why the case above asserts the WHOLE list. `first | last | length` is
    # the oracle a reordering passes: on this fixture the tail-append order `m0 m1 m2 a0 a1
    # a2` agrees with the true order on all three. An ordering assertion that reads only
    # the ends certifies nothing about the middle, which is the entire ready-set contract.
    test-topo-discriminating-ends-cannot-discriminate = {
      expr =
        let
          ends =
            xs:
            builtins.head xs
            + "|"
            + builtins.elemAt xs (builtins.length xs - 1)
            + "|"
            + toString (builtins.length xs);
        in
        ends
          (topoOrder (
            acc
              [
                "m0"
                "m1"
                "m2"
                "a0"
                "a1"
                "a2"
              ]
              {
                a0 = [ "m0" ];
                a1 = [ "m1" ];
                a2 = [ "m2" ];
              }
          )).order == ends [
          "m0"
          "m1"
          "m2"
          "a0"
          "a1"
          "a2"
        ];
      expected = true;
    };

    # The comparator reaches the ready set, not just the initial sort: under reverse
    # lexicographic order the same graph drains the `m`s largest-first, and each `a<i>`
    # then sorts ABOVE the remaining `m`s rather than below, so the interleaving inverts
    # into two runs.
    test-topo-discriminating-reversed-comparator = {
      expr =
        (topoOrder {
          nodes = [
            "m0"
            "m1"
            "m2"
            "a0"
            "a1"
            "a2"
          ];
          edges =
            id:
            {
              a0 = [ "m0" ];
              a1 = [ "m1" ];
              a2 = [ "m2" ];
            }
            .${id} or [ ];
          lessThan = a: b: a > b;
        }).order;
      expected = [
        "m2"
        "m1"
        "m0"
        "a2"
        "a1"
        "a0"
      ];
    };

    # ── a ready set that is Θ(n) for the whole run, not two or three elements ──
    # 25 independent producer/consumer pairs: 25 nodes are ready at the start and an
    # arrival fires on 25 consecutive steps, so the container is exercised at a width the
    # cases above never reach.
    #
    # ★ The two cases differ ONLY in the key prefixes, and that alone decides the answer:
    # which of `a`/`b` or `p`/`c` a pair uses determines whether a released consumer sorts
    # above or below the producers still waiting. Neither answer is more correct — both are
    # min-key at every step — but a shape name does not identify a fixture, and a test that
    # named only "25 independent pairs" would be under-determined.
    #
    # Producers sort BELOW consumers ⇒ every producer drains before any consumer.
    test-topo-wide-ready-set-producers-first = {
      expr =
        let
          k = p: i: p + (if i < 10 then "0" else "") + toString i;
        in
        (topoOrder (
          acc (builtins.genList (k "a") 25 ++ builtins.genList (k "b") 25) (
            builtins.listToAttrs (
              builtins.genList (i: {
                name = k "b" i;
                value = [ (k "a" i) ];
              }) 25
            )
          )
        )).order;
      expected =
        let
          k = p: i: p + (if i < 10 then "0" else "") + toString i;
        in
        builtins.genList (k "a") 25 ++ builtins.genList (k "b") 25;
    };

    # Consumers sort BELOW the waiting producers ⇒ each arrival wins the very next pick,
    # and the run interleaves for its whole length.
    test-topo-wide-ready-set-arrival-wins = {
      expr =
        let
          k = p: i: p + (if i < 10 then "0" else "") + toString i;
        in
        (topoOrder (
          acc (builtins.genList (k "p") 25 ++ builtins.genList (k "c") 25) (
            builtins.listToAttrs (
              builtins.genList (i: {
                name = k "c" i;
                value = [ (k "p" i) ];
              }) 25
            )
          )
        )).order;
      expected =
        let
          k = p: i: p + (if i < 10 then "0" else "") + toString i;
        in
        builtins.concatLists (
          builtins.genList (i: [
            (k "p" i)
            (k "c" i)
          ]) 25
        );
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

    # The indegree residue is folded back into its base once carrying it costs about what
    # rebuilding costs, and every fixture whose indegrees are all ONE leaves that branch
    # unreached: the residue is empty at every step, so the trigger never fires. This shape
    # fires it. Eight producers are ready at the start and eight consumers each wait on their
    # own producer AND on the LAST one, so consumers accumulate in the residue while the
    # producers drain — the fold triggers partway through, moving four of them into the base,
    # and the remaining ones are read from the residue. The assertion is the ORDER, because
    # what a fold must not do is change which count a later step reads.
    test-topo-indegree-residue-folds-and-preserves-order = {
      expr =
        let
          ix = builtins.genList (i: i) 8;
          last = "a7";
        in
        (topoOrder (
          acc (map (i: "a${toString i}") ix ++ map (i: "b${toString i}") ix) (
            builtins.listToAttrs (
              map (i: {
                name = "b${toString i}";
                value = [
                  "a${toString i}"
                  last
                ];
              }) ix
            )
          )
        )).order;
      expected = [
        "a0"
        "a1"
        "a2"
        "a3"
        "a4"
        "a5"
        "a6"
        "a7"
        "b0"
        "b1"
        "b2"
        "b3"
        "b4"
        "b5"
        "b6"
        "b7"
      ];
    };
    # ── THE CERTIFICATE-GATED ARM (`lib/order.nix`) ──
    # The door has two arms and the gate decides between them. These cells pin the DECISION,
    # not the cost: every exact order already pinned above is the identity assertion for the
    # shapes it covers, and it is unchanged by the arm — which is the point of the certificate.
    #
    # The total order is the routed class: node i depends on every j > i, so the topological
    # order is FORCED and there is exactly one. Both arms answer it; the gate is what lets the
    # cheap one answer.
    test-topo-certificate-routes-a-forced-order = {
      expr =
        (topoOrder (
          acc
            [
              "a"
              "b"
              "c"
              "d"
            ]
            {
              a = [
                "b"
                "c"
                "d"
              ];
              b = [
                "c"
                "d"
              ];
              c = [ "d" ];
            }
        )).order;
      expected = [
        "d"
        "c"
        "b"
        "a"
      ];
    };
    # ★ THE CELL THAT SAYS THE GATE IS LOAD-BEARING. Here the (out-degree, key)-sorted candidate
    # is a VALID topological order — `[ "m0" "m1" "a0" "a1" ]` — and it is NOT this door's
    # answer, because the two source nodes are incomparable and the candidate stratifies them
    # while the door interleaves by key. The linkage witness refuses (`m0` is not a dependency
    # of `m1`), so the Kahn arm answers and the sequence is unchanged. Delete the witness and
    # this cell is what goes red.
    test-topo-certificate-refuses-a-valid-candidate-that-reorders = {
      expr =
        (topoOrder (
          acc
            [
              "a0"
              "a1"
              "m0"
              "m1"
            ]
            {
              a0 = [ "m0" ];
              a1 = [ "m1" ];
            }
        )).order;
      expected = [
        "m0"
        "a0"
        "m1"
        "a1"
      ];
    };
    # The gate reads the RELATION, not the key order: this chain's keys descend with depth, so
    # the candidate is not even a topological order and the certificate rejects it.
    test-topo-certificate-refuses-on-descending-keys = {
      expr =
        (topoOrder (
          acc
            [
              "n0"
              "n1"
              "n2"
              "n3"
            ]
            {
              n0 = [ "n1" ];
              n1 = [ "n2" ];
              n2 = [ "n3" ];
            }
        )).order;
      expected = [
        "n3"
        "n2"
        "n1"
        "n0"
      ];
    };
    # A cycle can never route: validity over a total position map IS the acyclicity proof, so
    # `candValid` fails and the residual check reports as before.
    test-topo-certificate-never-routes-a-cycle = {
      expr =
        let
          r = topoOrder (
            acc
              [
                "x"
                "y"
              ]
              {
                x = [ "y" ];
                y = [ "x" ];
              }
          );
        in
        {
          inherit (r) ok cycles;
        };
      expected = {
        ok = false;
        cycles = [
          [
            "x"
            "y"
          ]
        ];
      };
    };
    # ★ `lessThan` must be a strict total order and this door cannot afford to check it. The
    # certificate is the one place that precondition is GUARDED rather than documented: the
    # comparator only builds the candidate, while validity is checked against positions, so a
    # comparator this degenerate can cause a REJECTION and not a wrong answer. Both shapes
    # below return correctly under a comparator that is constantly false.
    test-topo-certificate-survives-a-non-total-lessThan = {
      expr = {
        forced =
          (topoOrder {
            nodes = [
              "a"
              "b"
              "c"
              "d"
            ];
            edges =
              id:
              {
                a = [
                  "b"
                  "c"
                  "d"
                ];
                b = [
                  "c"
                  "d"
                ];
                c = [ "d" ];
              }
              .${id} or [ ];
            lessThan = _: _: false;
          }).order;
        chain =
          (topoOrder {
            nodes = [
              "p"
              "q"
              "r"
            ];
            edges =
              id:
              {
                p = [ "q" ];
                q = [ "r" ];
              }
              .${id} or [ ];
            lessThan = _: _: false;
          }).order;
      };
      expected = {
        forced = [
          "d"
          "c"
          "b"
          "a"
        ];
        chain = [
          "r"
          "q"
          "p"
        ];
      };
    };
    # The gate runs on KEYS, so a node value that is not its own identity routes exactly as a
    # string-keyed one does — the arm never touches the node values except to project them back.
    test-topo-certificate-routes-under-keyOf = {
      expr =
        map (n: n.id)
          (topoOrder {
            nodes = [
              { id = "a"; }
              { id = "b"; }
              { id = "c"; }
            ];
            keyOf = n: n.id;
            edges =
              n:
              if n.id == "a" then
                [
                  { id = "b"; }
                  { id = "c"; }
                ]
              else if n.id == "b" then
                [ { id = "c"; } ]
              else
                [ ];
          }).order;
      expected = [
        "c"
        "b"
        "a"
      ];
    };
  };
}
