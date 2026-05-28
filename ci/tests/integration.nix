{ lib, graphLib, ... }:
let
  inherit (graphLib)
    reachableFrom
    dependents
    materialize
    roots
    leaves
    cycles
    ;
  inherit (graphLib) mkGraph fromRegistry field;

  # Simulate gen-scope: a memoized accessor backed by an attrset
  simulatedScope = {
    "host:igloo" = {
      imports = [ "host:iceberg" ];
    };
    "host:iceberg" = {
      imports = [ "host:glacier" ];
    };
    "host:glacier" = {
      imports = [ ];
    };
  };
  scopeAccessor = {
    edges = id: (simulatedScope.${id} or { imports = [ ]; }).imports;
    nodes = builtins.attrNames simulatedScope;
  };

  # Simulate a build dependency graph
  buildGraph = mkGraph {
    edges = [
      {
        from = "app";
        to = "lib-core";
      }
      {
        from = "app";
        to = "lib-ui";
      }
      {
        from = "lib-ui";
        to = "lib-core";
      }
      {
        from = "lib-core";
        to = "lib-base";
      }
    ];
  };
in
{
  flake.tests.integration = {
    test-scope-accessor-reachable = {
      expr = builtins.sort builtins.lessThan (reachableFrom scopeAccessor "host:igloo");
      expected = [
        "host:glacier"
        "host:iceberg"
      ];
    };
    test-scope-accessor-dependents = {
      expr = builtins.sort builtins.lessThan (dependents scopeAccessor "host:glacier");
      expected = [
        "host:iceberg"
        "host:igloo"
      ];
    };
    test-scope-materialize = {
      expr = (materialize scopeAccessor)."host:igloo";
      expected = [ "host:iceberg" ];
    };
    test-scope-roots = {
      expr = roots scopeAccessor;
      expected = [ "host:igloo" ];
    };
    test-scope-leaves = {
      expr = leaves scopeAccessor;
      expected = [ "host:glacier" ];
    };
    test-scope-acyclic = {
      expr = cycles scopeAccessor;
      expected = [ ];
    };
    test-build-graph-roots = {
      expr = roots buildGraph;
      expected = [ "app" ];
    };
    test-build-graph-leaves = {
      expr = leaves buildGraph;
      expected = [ "lib-base" ];
    };
    test-build-graph-reachable = {
      expr = builtins.sort builtins.lessThan (reachableFrom buildGraph "app");
      expected = [
        "lib-base"
        "lib-core"
        "lib-ui"
      ];
    };
    test-from-node-map-reachable = {
      expr =
        let
          nm = {
            "svc:web" = {
              imports = [ "svc:api" ];
            };
            "svc:api" = {
              imports = [ "svc:db" ];
            };
            "svc:db" = {
              imports = [ ];
            };
          };
          g = fromRegistry {
            registry = nm;
            edges = field "imports";
          };
        in
        builtins.sort builtins.lessThan (reachableFrom g "svc:web");
      expected = [
        "svc:api"
        "svc:db"
      ];
    };
  };
}
