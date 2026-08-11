# The cyclic-cone REFUSAL, and the one cell in this repository that only one runner can host.
#
# `coneRank` refuses a cyclic cone by name and NAMES THE CYCLE. Asserting that it refuses is
# a boolean and `tryEval` can do it; asserting WHICH cycle it named is a claim about the
# message, and the only assertion available for that is nix-unit's `expectedError`.
#
# ★ STATED GATE GAP, not worked around. `gen.lib.mkCi` builds `checks.default` from a
# homegrown asserter that evaluates `t.expr == t.expected` UNCONDITIONALLY, so a cell with
# no `expected` and a throwing `expr` CRASHES that batch gate rather than failing it. This
# file is therefore reachable by `nix-unit --flake ./ci#tests` and is a known break of
# `nix flake check ./ci` until the harness grows an error path. It is kept in a file of its
# own so that the gap is exactly one file wide and its removal is atomic.
#
# The consultation-order discriminator that says WHY the refusal works — one construction,
# a single switch on whether the driver's verdict is read before the memo map is entered —
# cannot live in either runner: the wrong order produces an uncatchable `infinite recursion`
# that kills the runner rather than failing a cell. It is an exit-code sweep,
# `ci/bench/cone-consultation.sh`.
{ genGraph, ... }:
let
  inherit (genGraph) mkGraph coneRank;

  # a -> b -> c -> a, read as dependencies: a cone with no producers-first rank at all.
  cyclic = mkGraph {
    edges = [
      {
        from = "a";
        to = "b";
      }
      {
        from = "b";
        to = "c";
      }
      {
        from = "c";
        to = "a";
      }
    ];
  };
  # `den-hoag-ges2` F1's own fixture: a 2-cycle at the HEAD of a chain, which is the shape
  # that shows the abort it replaces arrives at depth 2 rather than at any bound.
  cycshort = mkGraph {
    edges = [
      {
        from = "a";
        to = "b";
      }
      {
        from = "b";
        to = "a";
      }
      {
        from = "c";
        to = "b";
      }
      {
        from = "d";
        to = "c";
      }
    ];
  };
  acyclic = mkGraph {
    edges = [
      {
        from = "q";
        to = "p";
      }
    ];
  };
in
{
  flake.tests.cone-refusal = {
    # The message NAMES THE CYCLE. A refusal that only said "cyclic" would leave the caller
    # to re-derive which cycle, on a graph the library has already decomposed.
    test-conerank-cyclic-refuses-naming-the-cycle = {
      expr = (coneRank cyclic cyclic.nodes).order;
      expectedError = {
        type = "ThrownError";
        msg = ".*cyclic cone.*\\[\\[\"a\",\"b\",\"c\"\\]\\].*";
      };
    };
    # The 2-cycle at the head of a chain: the component is named, and the acyclic tail is
    # not — the report is the cycle, not the cone.
    test-conerank-cycshort-refuses-naming-the-component = {
      expr = (coneRank cycshort cycshort.nodes).depth;
      expectedError = {
        type = "ThrownError";
        msg = ".*cyclic cone.*\\[\\[\"a\",\"b\"\\]\\].*";
      };
    };
    # LIVE CONTROL, same run: an acyclic cone through the same accessor does not refuse.
    # Without it, the two cells above are consistent with a surface that refuses everything.
    test-conerank-acyclic-control = {
      expr = (coneRank acyclic acyclic.nodes).order;
      expected = [
        "p"
        "q"
      ];
    };
  };
}
