{ lib, graphLib, ... }:
let
  inherit (graphLib)
    cycles
    dependents
    dependentsOf
    transpose
    impactOf
    ;
  inherit (graphLib.mock) fixtures mkGraph;
in
{
  flake.tests.global = {
    test-cycles-acyclic = {
      expr = cycles fixtures.chain;
      expected = [ ];
    };
    test-cycles-cyclic = {
      expr = cycles fixtures.cyclic;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-cycles-partial = {
      expr = cycles (mkGraph {
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
            to = "b";
          }
        ];
      });
      expected = [
        "b"
        "c"
      ];
    };
    test-cycles-self-loop = {
      expr = cycles (mkGraph {
        edges = [
          {
            from = "a";
            to = "a";
          }
        ];
      });
      expected = [ "a" ];
    };
    test-dependents-db = {
      expr = builtins.sort builtins.lessThan (dependents fixtures.serviceGraph "db");
      expected = [
        "api"
        "web"
        "worker"
      ];
    };
    test-dependents-leaf = {
      expr = dependents fixtures.chain "a";
      expected = [ ];
    };
    test-dependents-equals-impact = {
      expr = impactOf fixtures.serviceGraph "db";
      expected = dependents fixtures.serviceGraph "db";
    };
    test-transpose-chain = {
      expr =
        let
          rev = transpose fixtures.chain;
        in
        builtins.sort builtins.lessThan (rev.edges "d");
      expected = [ "c" ];
    };
    test-transpose-preserves-nodes = {
      expr = builtins.sort builtins.lessThan (transpose fixtures.serviceGraph).nodes;
      expected = builtins.sort builtins.lessThan fixtures.serviceGraph.nodes;
    };
    test-transpose-root-becomes-leaf = {
      expr = (transpose fixtures.chain).edges "a";
      expected = [ ];
    };
    test-transpose-cyclic = {
      expr =
        let
          rev = transpose fixtures.cyclic;
        in
        builtins.sort builtins.lessThan (rev.edges "a");
      expected = [ "c" ];
    };
    test-cycles-self-loop-closure = {
      expr =
        let
          g = mkGraph {
            edges = [
              {
                from = "a";
                to = "a";
              }
            ];
          };
          closure = graphLib.transitiveClosure g;
        in
        closure."a" or [ ];
      expected = [ "a" ];
    };

    # --- dependentsOf (single-target reverse traversal) ---

    test-dependentsOf-db = {
      expr = builtins.sort builtins.lessThan (dependentsOf fixtures.serviceGraph "db");
      expected = [
        "api"
        "web"
        "worker"
      ];
    };
    test-dependentsOf-leaf = {
      expr = dependentsOf fixtures.chain "a";
      expected = [ ];
    };
    test-dependentsOf-matches-dependents = {
      expr = dependentsOf fixtures.serviceGraph "queue";
      expected = dependents fixtures.serviceGraph "queue";
    };
    test-impactOf-uses-dependentsOf = {
      expr = impactOf fixtures.serviceGraph "cache";
      expected = dependentsOf fixtures.serviceGraph "cache";
    };
  };
}
