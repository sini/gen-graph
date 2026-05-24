{ lib, graphLib, engine, ... }:
let
  nodes = engine.buildNodes {
    parentGraph = engine.edges [
      { from = "a"; to = "root"; }
      { from = "b"; to = "root"; }
      { from = "c"; to = "root"; }
    ];
    importGraph = engine.edges [
      { from = "a"; to = "b"; }
      { from = "b"; to = "c"; }
    ];
    types = { root = "container"; a = "service"; b = "service"; c = "database"; };
  };
  nodeSet = graphLib.fromNodes nodes;
  edgeSet = graphLib.fromEdges nodes;
in
{
  combinators.test-select-by-type = {
    expr = builtins.attrNames (graphLib.select nodeSet (n: n.type == "service"));
    expected = [ "a" "b" ];
  };

  combinators.test-select-empty-result = {
    expr = graphLib.sizeNodes (graphLib.select nodeSet (n: n.type == "nonexistent"));
    expected = 0;
  };

  combinators.test-compose-transitive = {
    expr =
      let
        importEdges = lib.filterAttrs (from: targets:
          builtins.any (to: (targets.${to}).label == "I") (builtins.attrNames targets)
        ) edgeSet;
        iEdges = lib.mapAttrs (_: targets:
          lib.filterAttrs (_: e: e.label == "I") targets
        ) importEdges;
        composed = graphLib.compose iEdges iEdges;
      in
      composed ? a && composed.a ? c;
    expected = true;
  };
}
