# ── `series` MODE ───────────────────────────────────────────────────────────────
# `all` with the answer-set layer deleted. Every arm runs its `all` control on the
# same graph in the same evaluation, because the whole content of the claim is a
# difference from `all` — and `all` keeps its shipped contract, so those controls are
# also the guard that this mode did not quietly redefine it. The two arms recording
# what the deletion does NOT fix run a `queryArrivals` control for the same reason.
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
  # `n` is reached in TWO distinct nullable derivative states: residual ε via `x`,
  # residual z? via `y`.
  twoStates = labeledFrom {
    nodes = [
      "n"
      "s"
    ];
    perLabel = {
      x = id: { s = [ "n" ]; }.${id} or [ ];
      y = id: { s = [ "n" ]; }.${id} or [ ];
    };
  };
  # one node reached by two DISTINCT labels that derivate to the SAME state
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
in
{
  flake.tests.series = {
    # ── THE REORDER GOES ──
    test-series-returns-traversal-order = {
      expr = query {
        graph = fan;
        from = "s";
        follow = r.star (r.lit "e");
        mode = "series";
      };
      expected = [
        "s"
        "z"
        "a"
      ];
    };
    test-series-CONTROL-all-sorts-the-same-query = {
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

    # ── THE STATE COLLAPSE GOES ──
    test-series-keeps-distinct-derivative-states = {
      expr = query {
        graph = twoStates;
        from = "s";
        follow = r.parse "x | y z?";
        mode = "series";
      };
      expected = [
        "n"
        "n"
      ];
    };
    test-series-CONTROL-all-collapses-the-two-states = {
      expr = query {
        graph = twoStates;
        from = "s";
        follow = r.parse "x | y z?";
        mode = "all";
      };
      expected = [ "n" ];
    };

    # ── WHAT THE DELETION DOES NOT FIX, PINNED SO IT IS NOT OVERSOLD ──
    test-series-still-collapses-a-dual-inclusion-pair = {
      # both labels derivate to the same state, so the ⟨node, state⟩ key that fences
      # cycles also merges them — the deletion cannot reach this
      expr = query {
        graph = dual;
        from = "s";
        follow = altAB;
        mode = "series";
      };
      expected = [ "x" ];
    };
    test-series-CONTROL-the-edge-keyed-carrier-keeps-that-pair = {
      expr = map (x: x.via.label) (queryArrivals {
        graph = dual;
        from = "s";
        follow = altAB;
        advance = hop;
      });
      expected = [
        "a"
        "b"
      ];
    };
    test-series-still-collapses-reconvergence = {
      expr = query {
        graph = diamond;
        from = "s";
        follow = r.star (r.lit "e");
        mode = "series";
      };
      expected = [
        "s"
        "l"
        "r"
        "t"
      ];
    };
    test-series-CONTROL-the-edge-keyed-carrier-keeps-both-arrivals = {
      expr = map (x: x.via.from) (
        builtins.filter (x: x.node == "t") (queryArrivals {
          graph = diamond;
          from = "s";
          follow = r.star (r.lit "e");
          advance = hop;
        })
      );
      expected = [
        "l"
        "r"
      ];
    };

    # ── the seen-key still fences cycles, which is why it could not be deleted ──
    test-series-cycle-terminates = {
      expr = query {
        graph = labeledFixtures.cyclic;
        from = "a";
        follow = r.parse "contains* member";
        mode = "series";
      };
      expected = [ "m" ];
    };
    test-series-self-loop-terminates = {
      expr = query {
        graph = labeledFrom {
          nodes = [ "s" ];
          perLabel.hop = id: { s = [ "s" ]; }.${id} or [ ];
        };
        from = "s";
        follow = r.plus (r.lit "hop");
        mode = "series";
      };
      expected = [ "s" ];
    };
    test-series-laziness-poison-unreached = {
      expr = query {
        graph = labeledFixtures.poisoned;
        from = "a";
        follow = r.parse "safe";
        mode = "series";
      };
      expected = [ "b" ];
    };
    test-series-where-filters-answers = {
      expr = query {
        graph = labeledFixtures.world;
        from = "root";
        follow = r.parse "contains*";
        mode = "series";
        where = id: id == "u2";
      };
      expected = [ "u2" ];
    };
  };
}
