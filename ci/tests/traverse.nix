{ lib, graphLib, ... }:
let
  inherit (graphLib)
    reachableFrom
    reachableWhere
    canReach
    selfReachable
    ancestorsOf
    pathsBetween
    ;
  inherit (graphLib.mock) fixtures mkGraph;
in
{
  flake.tests.traverse = {
    test-reachable-chain = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.chain "a");
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    test-reachable-diamond = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.diamond "a");
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    test-reachable-from-leaf = {
      expr = reachableFrom fixtures.chain "d";
      expected = [ ];
    };
    test-reachable-cyclic = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.cyclic "a");
      expected = [
        "b"
        "c"
      ];
    };
    test-reachable-nonexistent = {
      expr = reachableFrom fixtures.chain "zzz";
      expected = [ ];
    };
    test-reachable-where-filter = {
      expr = builtins.sort builtins.lessThan (
        reachableWhere fixtures.serviceGraph "web" (id: id != "cache")
      );
      expected = [
        "api"
        "db"
      ];
    };
    test-reachable-where-all = {
      expr = builtins.sort builtins.lessThan (reachableWhere fixtures.serviceGraph "web" (_: true));
      expected = [
        "api"
        "cache"
        "db"
      ];
    };
    test-ancestors-tree = {
      expr = ancestorsOf fixtures.tree "grandchild";
      expected = [
        "child1"
        "root"
      ];
    };
    test-ancestors-root = {
      expr = ancestorsOf fixtures.tree "root";
      expected = [ ];
    };
    test-ancestors-child = {
      expr = ancestorsOf fixtures.tree "child2";
      expected = [ "root" ];
    };
    test-paths-diamond = {
      expr = builtins.length (pathsBetween fixtures.diamond "a" "d");
      expected = 2;
    };
    test-paths-no-path = {
      expr = pathsBetween fixtures.chain "d" "a";
      expected = [ ];
    };
    test-paths-cyclic-terminates = {
      expr = builtins.length (pathsBetween fixtures.cyclic "a" "c");
      expected = 1;
    };
    test-paths-self = {
      expr = pathsBetween fixtures.chain "a" "a";
      expected = [ [ "a" ] ];
    };
    test-ancestors-cyclic-terminates = {
      expr =
        let
          # Create a graph with cyclic parent: a->b->a
          g = mkGraph {
            parents = [
              {
                from = "a";
                to = "b";
              }
              {
                from = "b";
                to = "a";
              }
            ];
          };
        in
        ancestorsOf g "a";
      expected = [ "b" ];
    };
    test-reachable-disconnected = {
      expr = reachableFrom fixtures.disconnected "island";
      expected = [ ];
    };
    test-reachable-disconnected-from-connected = {
      expr = builtins.sort builtins.lessThan (reachableFrom fixtures.disconnected "a");
      expected = [ "b" ];
    };

    # --- canReach ---

    test-canReach-true = {
      expr = canReach fixtures.serviceGraph "web" "db";
      expected = true;
    };
    test-canReach-false = {
      expr = canReach fixtures.serviceGraph "db" "web";
      expected = false;
    };
    test-canReach-direct = {
      expr = canReach fixtures.chain "a" "b";
      expected = true;
    };
    test-canReach-transitive = {
      expr = canReach fixtures.chain "a" "d";
      expected = true;
    };
    test-canReach-self-cyclic = {
      expr = canReach fixtures.cyclic "a" "a";
      expected = true; # a→b→c→a: a can reach itself through the cycle
    };
    test-canReach-nonexistent = {
      expr = canReach fixtures.chain "a" "zzz";
      expected = false;
    };

    # --- selfReachable ---

    test-selfReachable-cyclic = {
      expr = selfReachable fixtures.cyclic "a";
      expected = true;
    };
    test-selfReachable-acyclic = {
      expr = selfReachable fixtures.chain "a";
      expected = false;
    };
    test-selfReachable-leaf = {
      expr = selfReachable fixtures.chain "d";
      expected = false;
    };
    test-selfReachable-self-loop = {
      expr = selfReachable (mkGraph {
        edges = [
          {
            from = "x";
            to = "x";
          }
        ];
      }) "x";
      expected = true;
    };
  };
}
