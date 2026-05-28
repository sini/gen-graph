{ lib, graphLib, ... }:
let
  inherit (graphLib.mock) fixtures mkGraph;
in
{
  flake.tests.mock = {
    test-diamond-nodes = {
      expr = builtins.sort builtins.lessThan fixtures.diamond.nodes;
      expected = [
        "a"
        "b"
        "c"
        "d"
      ];
    };
    test-diamond-edges = {
      expr = builtins.sort builtins.lessThan (fixtures.diamond.edges "a");
      expected = [
        "b"
        "c"
      ];
    };
    test-chain-edges-leaf = {
      expr = fixtures.chain.edges "d";
      expected = [ ];
    };
    test-tree-parent = {
      expr = fixtures.tree.parent "child1";
      expected = "root";
    };
    test-tree-parent-root = {
      expr = fixtures.tree.parent "root";
      expected = null;
    };
    test-service-nodedata = {
      expr = (fixtures.serviceGraph.nodeData "api").type;
      expected = "backend";
    };
    test-service-nodedata-missing = {
      expr = fixtures.serviceGraph.nodeData "nonexistent";
      expected = { };
    };
    test-mkgraph-empty = {
      expr = (mkGraph { }).nodes;
      expected = [ ];
    };
    test-mkgraph-dedup-edges = {
      expr =
        (mkGraph {
          edges = [
            {
              from = "a";
              to = "b";
            }
            {
              from = "a";
              to = "b";
            }
          ];
        }).edges
          "a";
      expected = [ "b" ];
    };
    test-cyclic-nodes = {
      expr = builtins.sort builtins.lessThan fixtures.cyclic.nodes;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-disconnected-nodes = {
      expr = builtins.sort builtins.lessThan fixtures.disconnected.nodes;
      expected = [
        "a"
        "b"
        "island"
      ];
    };
    test-disconnected-island-edges = {
      expr = fixtures.disconnected.edges "island";
      expected = [ ];
    };
    test-from-node-map = {
      expr =
        let
          nm = {
            "host:a" = {
              imports = [ "host:b" ];
              parent = null;
              role = "server";
            };
            "host:b" = {
              imports = [ ];
              parent = "host:a";
              role = "client";
            };
          };
          g = graphLib.mock.fromNodeMap nm;
        in
        {
          edges = g.edges "host:a";
          parent = g.parent "host:b";
          nodes = builtins.sort builtins.lessThan g.nodes;
          data = g.nodeData "host:a";
        };
      expected = {
        edges = [ "host:b" ];
        parent = "host:a";
        nodes = [
          "host:a"
          "host:b"
        ];
        data = {
          role = "server";
        };
      };
    };
  };
}
