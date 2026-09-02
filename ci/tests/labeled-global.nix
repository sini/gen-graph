# The labeled↔global composition: the total labeled contract, the one published
# projection, and the query that needs both halves at once.
#
# The two halves of this library were built to different contracts — a labeled query is
# SEEDED and never needed a node set, every global surface is NODE-SET-TOTAL and cannot work
# without one — and nothing bridged them. `labeledFrom` now takes `nodes` as a required
# formal and `forgetLabels` is the single sanctioned bridge, so the global half is reachable
# from a labeled graph, by one definition, rather than unreachable behind an arity abort
# that `tryEval` cannot catch.
#
# ★ THE REMOVED DEFECT LEAVES NO NEGATIVE CELL, and that is stated rather than papered over.
# With `nodes` required at the only constructor, the abort is UNREACHABLE — not caught — so
# there is nothing to assert about it here. What is assertable is the positive composition
# and the totality of the bridge, which is what this file does.
{ genGraph, ... }:
let
  inherit (genGraph)
    labeledFrom
    forgetLabels
    cyclicEdgesWhere
    condensation
    cycles
    dependentsOf
    directDependents
    topoOrder
    coneRank
    ;

  # A labeled graph from per-label adjacency maps. The node set is written out at every
  # fixture because the contract requires it, not because these cases need a wide domain.
  lf =
    nodes: pairs:
    labeledFrom {
      inherit nodes;
      perLabel = builtins.mapAttrs (
        _: m: id:
        m.${id} or [ ]
      ) pairs;
    };

  # The negativity of a label is the CALLER's — the library is label-agnostic, so the
  # predicate arrives from here and the word "neg" is this file's, not gen-graph's.
  isNeg = l: l == "neg";

  ab = [
    "a"
    "b"
  ];

  # F1 · a −neg→ b −pos→ a. The negative edge is on a cycle: the claim.
  f1 = lf ab {
    neg = {
      a = [ "b" ];
    };
    pos = {
      b = [ "a" ];
    };
  };
  # F2 · the SAME shape with both edges positive. ARMED CONTROL: the cycle is still there,
  # so a query that ignored the predicate answers F1's answer here.
  f2 = lf ab {
    pos = {
      a = [ "b" ];
      b = [ "a" ];
    };
  };
  # F3 · a negative edge that is on no cycle. ARMED CONTROL: the label still satisfies the
  # predicate, so a query that ignored the cycle test answers F1's answer here.
  f3 = lf ab {
    neg = {
      a = [ "b" ];
    };
  };
  # F4 · a negative edge inside a 3-cycle (c→a) PLUS an off-cycle negative edge (a→d).
  # DISCRIMINATION: both satisfy the predicate and only one is on a cycle.
  f4 =
    lf
      [
        "a"
        "b"
        "c"
        "d"
      ]
      {
        pos = {
          a = [ "b" ];
          b = [ "c" ];
        };
        neg = {
          c = [ "a" ];
          a = [ "d" ];
        };
      };

  pq = [
    "p"
    "q"
  ];
  # F5 · a BOTH-SIGNED edge inside a cycle. Apt, Blair & Walker 1988 Definition 4 says in
  # consecutive sentences that "for any pair of relation symbols p, q there is at most one
  # edge (p,q) in the dependency graph" and that "an edge may be both positive and
  # negative" — so a sign is a PAIR OF PREDICATES on one edge, never a label, and the
  # labeled contract renders `{+,−}` as two parallel labeled edges over the one pair.
  # Three ordinary clauses produce it: `p ← q`, `p ← ¬q`, `q ← p`.
  #
  # WHY THE FIXTURE HAD TO BE ADDED. F1–F4 are every one of them SINGLE-SIGNED, so a
  # caller that kept one sign per pair answers identically on all four: the cells above
  # cannot tell the two encodings apart, and a suite holding only them is green over an
  # encoding that reads this cycle as admissible while Lemma 1 forbids it. F5 is the input
  # they disagree on.
  f5 = lf pq {
    pos = {
      p = [ "q" ];
      q = [ "p" ];
    };
    neg = {
      p = [ "q" ];
    };
  };
  # F5-ONE · the SAME three clauses under a one-sign-per-edge encoding, where recording
  # `p ← q` leaves nowhere to put `p ← ¬q`. Its cell below is the control.
  f5one = lf pq {
    pos = {
      p = [ "q" ];
      q = [ "p" ];
    };
  };

  u1 = [ "u" ];
  # F6 · BOTH SIGNS ON A SELF-PAIR — the two hazards at once, from the two clauses `p ← p`
  # and `p ← ¬p`. The cycle is a SELF-LOOP, so u's component is a singleton and a reading
  # that asks whether a component has two members loses the cycle; and the pair is
  # BOTH-SIGNED, so a reading that keeps one sign per pair loses the negative half. F5 is the
  # second hazard on a two-node cycle and the self-loop cell is the first hazard
  # single-signed. Neither of them is their intersection, and a reading that fails EITHER one
  # answers `[ ]` on this fixture — reading as admissible a cycle Lemma 1 forbids.
  f6 = lf u1 {
    neg = {
      u = [ "u" ];
    };
    pos = {
      u = [ "u" ];
    };
  };
  # F6-ONE · the SAME two clauses one-sign-per-edge. Its cell below is the control.
  f6one = lf u1 {
    pos = {
      u = [ "u" ];
    };
  };
in
{
  flake.tests.labeled-global = {
    # ── the bridge ──
    # `forgetLabels` produces EXACTLY the plain accessor contract — the pair every
    # node-set-total surface takes — and nothing else.
    test-forget-labels-is-the-plain-contract = {
      expr = {
        shape = builtins.attrNames (forgetLabels f1);
        nodes = (forgetLabels f4).nodes;
        edges = map (id: (forgetLabels f4).edges id) (forgetLabels f4).nodes;
      };
      expected = {
        shape = [
          "edges"
          "nodes"
        ];
        nodes = [
          "a"
          "b"
          "c"
          "d"
        ];
        edges = [
          [
            "d"
            "b"
          ]
          [ "c" ]
          [ "a" ]
          [ ]
        ];
      };
    };
    # Parallel edges differing only in label collapse: multiplicity is a labeled-layer fact
    # and the plain accessor is a set of targets (`mkGraph` states it the same way).
    test-forget-labels-collapses-parallel-labels = {
      expr =
        let
          pg =
            lf
              [
                "u"
                "v"
              ]
              {
                neg = {
                  u = [ "v" ];
                };
                pos = {
                  u = [ "v" ];
                };
              };
        in
        {
          labeled = builtins.length (pg.labeledEdges "u");
          plain = (forgetLabels pg).edges "u";
        };
      expected = {
        labeled = 2;
        plain = [ "v" ];
      };
    };

    # ── totality: the global half, reached from a labeled graph through the bridge ──
    # Six LIVE DEFINITIONS in one run, each a node-set-total surface that was unreachable
    # from a labeled graph before. A token sweep of `lib/` would prove none of this.
    test-global-surfaces-compose-through-the-bridge = {
      expr =
        let
          plain4 = forgetLabels f4;
          plain3 = forgetLabels f3;
        in
        {
          cycles = cycles plain4;
          sccs = (condensation plain4).sccs;
          dependentsOfA = dependentsOf plain4 "a";
          direct = directDependents plain4;
          orderCyclic = topoOrder plain4;
          orderAcyclic = (topoOrder plain3).order;
          rank = coneRank plain3 plain3.nodes;
        };
      expected = {
        cycles = [
          "a"
          "b"
          "c"
        ];
        sccs = [
          [ "d" ]
          [
            "a"
            "b"
            "c"
          ]
        ];
        dependentsOfA = [
          "b"
          "c"
        ];
        direct = {
          a = [ "c" ];
          b = [ "a" ];
          c = [ "b" ];
          d = [ "a" ];
        };
        orderCyclic = {
          ok = false;
          cycles = [
            [
              "a"
              "b"
              "c"
            ]
          ];
        };
        orderAcyclic = [
          "b"
          "a"
        ];
        rank = {
          order = [
            "b"
            "a"
          ];
          depth = {
            a = 1;
            b = 0;
          };
        };
      };
    };
    # The partition is BLIND TO SIGNS, and this cell claims no more than that: F1 and F2
    # differ only in a label, and `condensation` of the projection returns the same
    # partition for both. The credit for telling them apart belongs to the query below.
    test-projection-partition-is-sign-blind = {
      expr = {
        f1 = (condensation (forgetLabels f1)).sccs;
        f2 = (condensation (forgetLabels f2)).sccs;
      };
      expected = {
        f1 = [ ab ];
        f2 = [ ab ];
      };
    };

    # ── the query ──
    # WITNESS EDGES, never a boolean: F4 is why. A boolean answer is `true` for F4 whether
    # the query found the edge on the cycle or the one off it, so a boolean cell passes
    # without discriminating.
    test-cyclic-edges-where-f1-names-the-edge = {
      expr = cyclicEdgesWhere f1 isNeg;
      expected = [
        {
          from = "a";
          label = "neg";
          to = "b";
        }
      ];
    };
    # ARMED CONTROL 1 — same cycle, no matching label. A run in which this and the next
    # cell do not BOTH come back empty says nothing about the cell above it.
    test-cyclic-edges-where-f2-control-no-matching-label = {
      expr = cyclicEdgesWhere f2 isNeg;
      expected = [ ];
    };
    # ARMED CONTROL 2 — matching label, no cycle.
    test-cyclic-edges-where-f3-control-no-cycle = {
      expr = cyclicEdgesWhere f3 isNeg;
      expected = [ ];
    };
    # DISCRIMINATION — two edges satisfy the predicate; exactly the one on the cycle is
    # named, and the off-cycle one (a→d) is absent.
    test-cyclic-edges-where-f4-discriminates = {
      expr = cyclicEdgesWhere f4 isNeg;
      expected = [
        {
          from = "c";
          label = "neg";
          to = "a";
        }
      ];
    };
    # A self-loop IS a cycle, and a singleton component is where a partition-only reading
    # would lose it: the edge's endpoints share a component of size one.
    test-cyclic-edges-where-self-loop = {
      expr = cyclicEdgesWhere (lf [ "u" ] {
        neg = {
          u = [ "u" ];
        };
      }) isNeg;
      expected = [
        {
          from = "u";
          label = "neg";
          to = "u";
        }
      ];
    };
    # BOTH SIGNS ON ONE PAIR, AND THAT PAIR ON A CYCLE. The parallel positive edge does not
    # hide the negative one: `forgetLabels` collapses the pair for the partition, and the
    # JOIN BACK is onto the retained labelled list, so the negative half is still on the
    # cycle and is named. This is the case ABW Definition 4's second sentence exists for,
    # and the only cell in this file whose answer changes when a sign stops being a set.
    test-cyclic-edges-where-both-signed-edge-in-cycle = {
      expr = cyclicEdgesWhere f5 isNeg;
      expected = [
        {
          from = "p";
          label = "neg";
          to = "q";
        }
      ];
    };
    # ARMED CONTROL 3 — the same three clauses ONE-SIGN-PER-EDGE: no edge under the
    # predicate, so the cycle reads ADMISSIBLE where Lemma 1 refuses it. The unsoundness is
    # the CALLER's — this library never sees clauses and cannot make the choice — and the
    # cell records what a caller gets for making it, which is what makes the cell above a
    # measurement of the encoding rather than a restatement of F1.
    test-control-cyclic-edges-where-one-sign-encoding-admits = {
      expr = cyclicEdgesWhere f5one isNeg;
      expected = [ ];
    };
    # THE TWO HAZARDS AT ONCE, which is the one shape neither cell above holds. The join has
    # to read the component TAGS rather than a component SIZE — u's component is a singleton
    # — AND it has to keep the negative half of a both-signed pair, with the parallel
    # positive edge standing right beside it on the same self-pair. Each hazard alone has a
    # cell; a reading that fails either one answers `[ ]` here.
    test-cyclic-edges-where-both-signed-self-loop = {
      expr = cyclicEdgesWhere f6 isNeg;
      expected = [
        {
          from = "u";
          label = "neg";
          to = "u";
        }
      ];
    };
    # ARMED CONTROL 4 — the same two clauses ONE-SIGN-PER-EDGE. Recording `p ← p` leaves
    # nowhere to put `p ← ¬p`, so the self-loop reads ADMISSIBLE: the caller-side unsoundness
    # ARMED CONTROL 3 records, on the singleton-component regime instead of the two-node one.
    test-control-cyclic-edges-where-one-sign-self-loop-admits = {
      expr = cyclicEdgesWhere f6one isNeg;
      expected = [ ];
    };
    # BOTH SIGNS NAMED, NOT ONE PER PAIR. Every other cell in this file filters down to a
    # single record per ordered pair, so a join that deduplicated its output by (from, to)
    # — the same "a sign is a label" reading, one stage after the cycle test — would answer
    # every one of them correctly. These two are where that shows: `{+,−}` on one pair is TWO
    # witnesses, because a caller refusing a graph has to name the negative edge AND the
    # positive one it travels with. The single-sign arm of each fixture is the control, and
    # those are the two cells directly above.
    #
    # THE ORDER IS ASSERTED because the contract states it: (from, label, to) ascending, so
    # the answer is a function of the graph rather than of accessor enumeration.
    test-cyclic-edges-where-both-signs-are-named-on-a-cycle = {
      expr = cyclicEdgesWhere f5 (_: true);
      expected = [
        {
          from = "p";
          label = "neg";
          to = "q";
        }
        {
          from = "p";
          label = "pos";
          to = "q";
        }
        {
          from = "q";
          label = "pos";
          to = "p";
        }
      ];
    };
    # The same claim on the SINGLETON-COMPONENT regime, and a separate cell rather than a
    # second half of the one above: a singleton component behaving like any other is the
    # assumption this file keeps finding false.
    test-cyclic-edges-where-both-signs-are-named-on-a-self-loop = {
      expr = cyclicEdgesWhere f6 (_: true);
      expected = [
        {
          from = "u";
          label = "neg";
          to = "u";
        }
        {
          from = "u";
          label = "pos";
          to = "u";
        }
      ];
    };
    # The predicate is the caller's and the library is label-agnostic: the same graph
    # answers about whichever labels the caller asks about, including all of them.
    test-cyclic-edges-where-predicate-is-the-callers = {
      expr = {
        anyLabel = cyclicEdgesWhere f4 (_: true);
        noLabel = cyclicEdgesWhere f4 (_: false);
      };
      expected = {
        anyLabel = [
          {
            from = "a";
            label = "pos";
            to = "b";
          }
          {
            from = "b";
            label = "pos";
            to = "c";
          }
          {
            from = "c";
            label = "neg";
            to = "a";
          }
        ];
        noLabel = [ ];
      };
    };
  };
}
