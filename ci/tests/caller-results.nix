# ── A CALLER FUNCTION'S RESULT IS REFUSED WHERE IT IS CONSUMED (den-hoag-pqp4z) ───────────────
# `cyclicEdgesWhere`'s `p` is applied by the labeled surfaces and its result read, and the labeled
# record's `labeledEdges` is applied wherever the record is read. Unguarded, a result of the wrong
# type aborted past `tryEval` (`expected a Boolean but found an integer`). These cells assert every
# arm is refused CATCHABLY; the messages are pinned on `testsError` (`ci/tests-error.nix`,
# `caller-results`). The walk surfaces' `where`, `groupBy`, `advance` and `marksOf` retired with the
# calculus (den-hoag-gayc U3); resolution is gen-scope's `resolve`.
{ genGraph, ... }:
let
  inherit (genGraph)
    cyclicEdgesWhere
    forgetLabels
    ;
  # a —x→ b —y→ a: one cycle, carrying an `x` edge and a `y` edge.
  graph = {
    nodes = [
      "a"
      "b"
    ];
    labeledEdges =
      id:
      if id == "a" then
        [
          {
            label = "x";
            target = "b";
          }
        ]
      else
        [
          {
            label = "y";
            target = "a";
          }
        ];
  };
  admitted = v: (builtins.tryEval (builtins.deepSeq v true)).success;

  otherArms = {
    pInt = cyclicEdgesWhere (_: 1) graph;
    pNotFunction = cyclicEdgesWhere 1 graph;
    # a set whose `__functor` is not a function is not callable, at every door incl. `edgesAt`
    labeledEdgesFunctorInt =
      (forgetLabels (
        graph
        // {
          labeledEdges = {
            __functor = 1;
          };
        }
      )).edges
        "a";
  };
  admittedOf = arms: builtins.filter (k: admitted arms.${k}) (builtins.attrNames arms);
in
{
  flake.tests.caller-results = {
    test-every-other-caller-function-result-is-refused-catchably = {
      expr = admittedOf otherArms;
      expected = [ ];
    };
    # CONTROL: the same constructions with lawful functions answer, so the refusals above are the
    # guards and not a broken fixture
    test-the-lawful-arms-answer = {
      expr = {
        p = cyclicEdgesWhere (l: l == "x") graph;
        edges = (forgetLabels graph).edges "a";
      };
      expected = {
        p = [
          {
            from = "a";
            label = "x";
            to = "b";
          }
        ];
        edges = [ "b" ];
      };
    };
  };
}
