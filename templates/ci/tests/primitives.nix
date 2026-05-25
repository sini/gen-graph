{ lib, graphLib, ... }:
let
  # Diamond graph: a -> b, a -> c, b -> d, c -> d
  nodes = graphLib.mock.mkNodes {
    edges = [
      { from = "a"; to = "b"; }
      { from = "a"; to = "c"; }
      { from = "b"; to = "d"; }
      { from = "c"; to = "d"; }
    ];
    types = { a = "entry"; b = "mid"; c = "mid"; d = "leaf"; };
  };
in
{
  primitives.test-reachableFrom = {
    expr = builtins.sort builtins.lessThan (graphLib.reachableFrom nodes "a");
    expected = [ "b" "c" "d" ];
  };

  primitives.test-reachableFrom-leaf = {
    expr = graphLib.reachableFrom nodes "d";
    expected = [];
  };

  primitives.test-reachableFrom-nonexistent = {
    expr = graphLib.reachableFrom nodes "nonexistent";
    expected = [];
  };

  primitives.test-dependents = {
    expr = builtins.sort builtins.lessThan (graphLib.dependents nodes "d");
    expected = [ "a" "b" "c" ];
  };

  primitives.test-dependents-root = {
    expr = graphLib.dependents nodes "a";
    expected = [];
  };

  primitives.test-roots = {
    expr = graphLib.roots nodes;
    expected = [ "a" ];
  };

  primitives.test-leaves = {
    expr = graphLib.leaves nodes;
    expected = [ "d" ];
  };

  primitives.test-impactOf = {
    expr = builtins.sort builtins.lessThan (graphLib.impactOf nodes "d");
    expected = [ "a" "b" "c" ];
  };

  primitives.test-cycles = {
    expr =
      let
        cyclicNodes = graphLib.mock.mkNodes {
          edges = [
            { from = "a"; to = "b"; }
            { from = "b"; to = "c"; }
            { from = "c"; to = "a"; }
          ];
        };
      in
      builtins.sort builtins.lessThan (graphLib.cycles cyclicNodes);
    expected = [ "a" "b" "c" ];
  };

  primitives.test-no-cycles = {
    expr = graphLib.cycles nodes;
    expected = [];
  };

  primitives.test-pathsBetween = {
    expr = graphLib.pathsBetween nodes "a" "d";
    expected = [ [ "a" "b" "d" ] [ "a" "c" "d" ] ];
  };

  primitives.test-pathsBetween-no-path = {
    expr = graphLib.pathsBetween nodes "d" "a";
    expected = [];
  };

  primitives.test-pathsBetween-direct = {
    expr = graphLib.pathsBetween nodes "a" "b";
    expected = [ [ "a" "b" ] ];
  };

  primitives.test-reachableWhere-by-type = {
    expr = builtins.sort builtins.lessThan
      (graphLib.reachableWhere (graphLib.mock.fixtures.serviceGraph) "web" (n: n.type == "datastore"));
    expected = [ "cache" "db" ];
  };

  primitives.test-reachableWhere-no-match = {
    expr = graphLib.reachableWhere nodes "a" (n: n.type == "nonexistent");
    expected = [];
  };

  primitives.test-reachableWhere-all-match = {
    expr = builtins.sort builtins.lessThan
      (graphLib.reachableWhere nodes "a" (_: true));
    expected = [ "b" "c" "d" ];
  };

  primitives.test-ancestorsOf-chain = {
    expr = graphLib.ancestorsOf (graphLib.mock.fixtures.tree) "grandchild";
    expected = [ "child1" "root" ];
  };

  primitives.test-ancestorsOf-root = {
    expr = graphLib.ancestorsOf (graphLib.mock.fixtures.tree) "root";
    expected = [];
  };

  primitives.test-ancestorsOf-one-level = {
    expr = graphLib.ancestorsOf (graphLib.mock.fixtures.tree) "child2";
    expected = [ "root" ];
  };

  primitives.test-transitiveReduction-diamond = {
    expr =
      let reduced = graphLib.transitiveReduction (graphLib.mock.fixtures.diamond);
      in graphLib.sizeEdges reduced;
    expected = 4;
  };

  primitives.test-transitiveReduction-chain-unchanged = {
    expr =
      let
        reduced = graphLib.transitiveReduction (graphLib.mock.fixtures.chain);
        iEdges = graphLib.fromEdges (graphLib.mock.fixtures.chain);
        original = lib.mapAttrs (_: targets:
          lib.filterAttrs (_: e: e.label == "I") targets
        ) (lib.filterAttrs (_: t: t != {}) iEdges);
      in
      graphLib.sizeEdges reduced == graphLib.sizeEdges original;
    expected = true;
  };
}
