{ lib, genGraph, ... }:
let
  inherit (genGraph)
    fixtures
    mkGraph
    fromRegistry
    field
    fields
    ;
in
{
  flake.tests.registry = {
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

    # fromRegistry tests
    test-from-registry-basic = {
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
          g = fromRegistry {
            registry = nm;
            edges = field "imports";
            parent = _id: entry: entry.parent or null;
          };
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
          imports = [ "host:b" ];
          parent = null;
          role = "server";
        };
      };
    };

    # field tests
    test-field-extracts = {
      expr = (field "imports") "x" {
        imports = [
          "a"
          "b"
        ];
      };
      expected = [
        "a"
        "b"
      ];
    };
    test-field-missing = {
      expr = (field "imports") "x" { };
      expected = [ ];
    };

    # fields tests
    test-fields-concat = {
      expr =
        (fields [
          "imports"
          "deps"
        ])
          "x"
          {
            imports = [ "a" ];
            deps = [ "b" ];
          };
      expected = [
        "a"
        "b"
      ];
    };
    test-fields-partial = {
      expr =
        (fields [
          "imports"
          "deps"
        ])
          "x"
          { imports = [ "a" ]; };
      expected = [ "a" ];
    };

    # fromRegistry with missing entry
    test-from-registry-missing-node = {
      expr =
        let
          g = fromRegistry {
            registry = {
              a = {
                deps = [ "b" ];
              };
            };
            edges = field "deps";
          };
        in
        {
          edges = g.edges "nonexistent";
          data = g.nodeData "nonexistent";
        };
      expected = {
        edges = [ ];
        data = { };
      };
    };
  };
}
