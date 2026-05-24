{ lib, graphLib, ... }:
let
  nodes = graphLib.mock.mkNodes {
    edges = [
      { from = "a"; to = "b"; }
      { from = "b"; to = "c"; }
      { from = "c"; to = "d"; }
    ];
  };
  edgeSet = graphLib.fromEdges nodes;
  iEdges = lib.mapAttrs (_: targets:
    lib.filterAttrs (_: e: e.label == "I") targets
  ) (lib.filterAttrs (_: targets: targets != {}) edgeSet);
in
{
  fixpoint.test-transitive-closure = {
    expr =
      let
        closure = graphLib.fixpoint {
          seed = iEdges;
          step = current: graphLib.unionEdges current (graphLib.compose current iEdges);
        };
      in
      closure ? a && closure.a ? d;
    expected = true;
  };

  fixpoint.test-fixpoint-terminates = {
    expr =
      let
        closure = graphLib.fixpoint {
          seed = iEdges;
          step = current: graphLib.unionEdges current (graphLib.compose current iEdges);
        };
      in
      graphLib.sizeEdges closure;
    expected = 6;
  };

  fixpoint.test-fixpoint-maxIter = {
    expr = builtins.tryEval (graphLib.fixpoint {
      seed = { x = { y = { from = "x"; to = "y"; label = "test"; }; }; };
      maxIter = 0;
      step = current: graphLib.unionEdges current { z = { w = { from = "z"; to = "w"; label = "test"; }; }; };
    });
    expected = { success = false; value = false; };
  };

  fixpoint.test-identity-step-terminates = {
    expr =
      let
        result = graphLib.fixpoint {
          seed = iEdges;
          step = current: current;
        };
      in
      graphLib.sizeEdges result == graphLib.sizeEdges iEdges;
    expected = true;
  };
}
