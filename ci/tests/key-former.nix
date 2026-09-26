# THE KEY FORMER REFUSES A NON-STRING BY THE DOOR'S NAME (den-hoag-2m5iy, ADR-0025 item 1). A
# non-string where a door KEYS an attribute set used to meet Nix's own type error, which escapes
# `builtins.tryEval`; `attrKey`, `keyedAttrs` and the two inline formers now refuse it by name. The
# message cells live on `testsError` (`key-former-refusal`). This file holds the two things an error
# cell cannot say: that each refusal is a throw `tryEval` observes, and that a string answers as
# before.
{ genGraph, ... }:
let
  G = genGraph;
  caught = v: builtins.tryEval (builtins.deepSeq v true);

  # The accessor-result instance: b's edges name the integer 1.
  intTarget = {
    nodes = [
      "a"
      "b"
      "c"
    ];
    edges =
      id:
      if id == "a" then
        [ "b" ]
      else if id == "b" then
        [ 1 ]
      else
        [ ];
  };
  # Its control: the same graph with a string where the integer was.
  strTarget = intTarget // {
    edges =
      id:
      if id == "a" then
        [ "b" ]
      else if id == "b" then
        [
          "a"
          "c"
        ]
      else
        [ ];
  };
  hoisted = G.hoistEdges {
    nodes = [ "a" ];
    edges = _: [ ];
  };
in
{
  flake.tests.key-former = {
    test-a-non-string-edge-target-is-refused-catchably = {
      expr = caught (G.directDependents intTarget);
      expected = {
        success = false;
        value = false;
      };
    };
    test-a-string-edge-target-still-answers = {
      expr = G.directDependents strTarget;
      expected = {
        a = [ "b" ];
        b = [ "a" ];
        c = [ "b" ];
      };
    };
    # The inline former in `hoistEdges`'s returned lookup: `reachableVia` admits an integer start
    # through `nodeKey`, and the lookup is where it keys.
    test-a-hoisted-lookup-of-a-non-string-is-refused-catchably = {
      expr = [
        (caught (hoisted 1))
        (caught (G.reachableVia hoisted 1))
      ];
      expected = [
        {
          success = false;
          value = false;
        }
        {
          success = false;
          value = false;
        }
      ];
    };
    test-a-hoisted-lookup-of-a-string-still-answers = {
      expr = hoisted "a";
      expected = [ ];
    };
    # `{ ${null} = …; }` DROPS the binding rather than aborting, so a null label used to vanish and
    # the ranks after it renumbered. It is refused now; `rankOf`'s null aborted, and is refused too.
    test-a-null-label-is-refused-catchably = {
      expr = [
        (caught (
          G.ranksOf {
            labels = [
              "x"
              null
              "y"
            ];
          }
        ))
        (caught (G.rankOf { labels = [ "x" ]; } null))
      ];
      expected = [
        {
          success = false;
          value = false;
        }
        {
          success = false;
          value = false;
        }
      ];
    };
    test-string-labels-still-rank = {
      expr = G.ranksOf {
        labels = [
          "x"
          "y"
        ];
      };
      expected = {
        x = 0;
        y = 1;
      };
    };
  };
}
