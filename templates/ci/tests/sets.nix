{ lib, graphLib, engine, ... }:
let
  nodes = engine.buildNodes {
    parentGraph = engine.edges [
      { from = "a"; to = "root"; }
      { from = "b"; to = "root"; }
    ];
    importGraph = engine.edge "a" "b";
    types = { root = "container"; a = "service"; b = "service"; };
  };
in
{
  sets.test-fromNodes-preserves = {
    expr = builtins.attrNames (graphLib.fromNodes nodes);
    expected = builtins.attrNames nodes;
  };

  sets.test-fromEdges-has-import = {
    expr = let edges = graphLib.fromEdges nodes; in edges ? a && edges.a ? b;
    expected = true;
  };

  sets.test-fromEdges-has-parent = {
    expr = let edges = graphLib.fromEdges nodes; in edges ? a && edges.a ? root;
    expected = true;
  };

  sets.test-empty-graph = {
    expr = graphLib.sizeNodes (graphLib.fromNodes {});
    expected = 0;
  };

  sets.test-empty-edges = {
    expr = graphLib.sizeEdges (graphLib.fromEdges {});
    expected = 0;
  };

  sets.test-unionNodes = {
    expr = builtins.attrNames (graphLib.unionNodes { a = {}; } { b = {}; });
    expected = [ "a" "b" ];
  };

  sets.test-intersectNodes = {
    expr = builtins.attrNames (graphLib.intersectNodes { a = {}; b = {}; } { b = {}; c = {}; });
    expected = [ "b" ];
  };

  sets.test-sizeNodes = {
    expr = graphLib.sizeNodes nodes;
    expected = 3;
  };

  sets.test-sizeEdges = {
    expr = graphLib.sizeEdges (graphLib.fromEdges nodes);
    expected = 3;
  };

  sets.test-memberNode = {
    expr = graphLib.memberNode nodes "a";
    expected = true;
  };

  sets.test-memberNode-absent = {
    expr = graphLib.memberNode nodes "z";
    expected = false;
  };
}
