# ── THE VISITATION-ORDER GUARD ──────────────────────────────────────────────────
# `builtins.genericClosure` returns items in an order Nix does not document. Measured
# at the Nix this suite runs against, the doc string exists and is SILENT on
# visitation: over its full text `order`, `bfs`, `breadth`, `depth`, `visit`, `sort`,
# `insertion` and `sequence` all occur zero times, and the prose commits only to
# calling the operator on each item not yet called until no new items are added. Its
# worked example happens to print insertion order; an example is not a contract.
#
# WHAT RESTS ON IT. `queryArrivals` carries a distance payload and keeps the FIRST
# arrival at each key. That first arrival is the minimum only if visitation is
# NONDECREASING IN DEPTH — under a depth-first or LIFO worklist a node first reached
# by a long route would record the long distance, and every downstream comparison
# would be computed against a wrong number with nothing to show for it. So this is
# not a determinism nicety: it is the soundness condition for reading `<` off the
# payload, and pinning a fixed output sequence instead would leave exactly that
# property unguarded.
#
# ★ THE GUARD IS ARMED. A test that only ever asserts `true` on a passing property
# cannot distinguish a live check from a broken one, and this file's own predicate is
# the thing most worth doubting. Two controls run in the same evaluation: a literal
# out-of-order sequence, and — the load-bearing one — the SAME graph walked by
# `expandPreorder`'s DFS, whose depth sequence genuinely violates the property. One
# graph, one predicate, two traversals: the guard fails on the seeded violation in
# the run it passes clean.
{ genGraph, ... }:
let
  inherit (genGraph)
    labeledFrom
    regex
    queryArrivals
    expandPreorder
    ;
  r = regex;
  hop = s: s.distance + 1;

  nondecreasing =
    xs:
    builtins.all (i: builtins.elemAt xs i <= builtins.elemAt xs (i + 1)) (
      builtins.genList (i: i) (if xs == [ ] then 0 else builtins.length xs - 1)
    );

  # A deep branch enumerated BEFORE a shallow sibling: breadth-first visits z at
  # depth 1 before descending, depth-first descends a's whole chain first and comes
  # back to z at depth 1 afterwards.
  skewSucc =
    id:
    {
      s = [
        "a"
        "z"
      ];
      a = [ "a2" ];
      a2 = [ "a3" ];
    }
    .${id} or [ ];
  skew = labeledFrom {
    nodes = [
      "a"
      "a2"
      "a3"
      "s"
      "z"
    ];
    perLabel.e = skewSucc;
  };
  skewClosureDepths = map (x: x.distance) (queryArrivals {
    graph = skew;
    from = "s";
    follow = r.plus (r.lit "e");
    advance = hop;
  });
  # the seeded violation: same graph, same depths, depth-first order
  skewPreorderDepths =
    (expandPreorder {
      roots = [
        {
          id = "s";
          depth = 0;
        }
      ];
      key = f: f.id;
      edges =
        f:
        map (t: {
          id = t;
          depth = f.depth + 1;
        }) (skewSucc f.id);
      emit = f: _: f.depth;
    }).nodes;

  # The trap graphs enumerate the LONG route to `t` first and the short one last, so a
  # LIFO worklist would record the long distance for it.
  trap1 = labeledFrom {
    nodes = [
      "b"
      "c"
      "s"
      "t"
      "x"
    ];
    perLabel.e =
      id:
      {
        s = [
          "b"
          "t"
        ];
        b = [ "c" ];
        c = [ "x" ];
        x = [ "t" ];
      }
      .${id} or [ ];
  };
  trap2 = labeledFrom {
    nodes = [
      "p"
      "p2"
      "q"
      "q2"
      "r"
      "s"
      "t"
    ];
    perLabel.e =
      id:
      {
        s = [
          "p"
          "q"
          "r"
          "t"
        ];
        p = [ "p2" ];
        p2 = [ "t" ];
        q = [ "q2" ];
        q2 = [ "t" ];
        r = [ "t" ];
      }
      .${id} or [ ];
  };
  walk =
    graph:
    queryArrivals {
      inherit graph;
      from = "s";
      follow = r.plus (r.lit "e");
      advance = hop;
    };
  firstDistanceAt =
    graph: node: (builtins.head (builtins.filter (x: x.node == node) (walk graph))).distance;
in
{
  flake.tests.closure-order = {
    # ── the property the carrier's soundness rests on ──
    test-closure-visitation-is-nondecreasing-in-depth = {
      expr = nondecreasing skewClosureDepths;
      expected = true;
    };
    test-closure-visitation-nondecreasing-on-both-traps = {
      expr = {
        trap1 = nondecreasing (map (x: x.distance) (walk trap1));
        trap2 = nondecreasing (map (x: x.distance) (walk trap2));
      };
      expected = {
        trap1 = true;
        trap2 = true;
      };
    };

    # ── THE ARMED CONTROLS: the same predicate must FAIL on a seeded violation ──
    test-nondecreasing-CONTROL-rejects-a-depth-first-walk-of-the-same-graph = {
      # DFS returns to the shallow sibling AFTER descending the deep branch, so its
      # depth sequence falls at the end. If this reported `true` the guard above
      # would be vacuous.
      expr = {
        depths = skewPreorderDepths;
        nondecreasing = nondecreasing skewPreorderDepths;
      };
      expected = {
        depths = [
          0
          1
          2
          3
          1
        ];
        nondecreasing = false;
      };
    };
    test-nondecreasing-CONTROL-rejects-a-literal-out-of-order-sequence = {
      expr = {
        falls = nondecreasing [
          1
          2
          1
        ];
        flat = nondecreasing [
          1
          1
          1
        ];
        empty = nondecreasing [ ];
      };
      expected = {
        falls = false;
        flat = true;
        empty = true;
      };
    };

    # ── what nondecreasing depth BUYS: first arrival is the minimum ──
    test-first-arrival-is-minimal-despite-the-long-route-first = {
      expr = {
        trap1 = firstDistanceAt trap1 "t";
        trap2 = firstDistanceAt trap2 "t";
      };
      expected = {
        trap1 = 1;
        trap2 = 1;
      };
    };
    test-first-arrival-CONTROL-a-genuinely-deep-node-reports-its-depth = {
      # without this the traps above could be passing on an "always 1" artefact
      expr = firstDistanceAt trap1 "x";
      expected = 3;
    };
  };
}
