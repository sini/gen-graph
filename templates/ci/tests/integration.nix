{ lib, graphLib, ... }:
let
  # Realistic service dependency graph
  nodes = graphLib.mock.mkNodes {
    edges = [
      { from = "web"; to = "api"; }
      { from = "api"; to = "database"; }
      { from = "api"; to = "cache"; }
      { from = "worker"; to = "database"; }
      { from = "worker"; to = "queue"; }
      { from = "cache"; to = "database"; }
    ];
    types = {
      web = "frontend";
      api = "backend";
      database = "datastore";
      cache = "datastore";
      worker = "backend";
      queue = "datastore";
    };
  };
in
{
  integration.test-what-breaks-if-database-dies = {
    expr = builtins.sort builtins.lessThan (graphLib.dependents nodes "database");
    expected = [ "api" "cache" "web" "worker" ];
  };

  integration.test-web-depends-on = {
    expr = builtins.sort builtins.lessThan (graphLib.reachableFrom nodes "web");
    expected = [ "api" "cache" "database" ];
  };

  integration.test-entry-points = {
    expr = builtins.sort builtins.lessThan (graphLib.roots nodes);
    expected = [ "web" "worker" ];
  };

  integration.test-leaf-services = {
    expr = builtins.sort builtins.lessThan (graphLib.leaves nodes);
    expected = [ "database" "queue" ];
  };

  integration.test-no-cycles = {
    expr = graphLib.cycles nodes;
    expected = [];
  };

  integration.test-select-backends = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (graphLib.select nodes (n: n.type == "backend")));
    expected = [ "api" "worker" ];
  };

  integration.test-select-datastores = {
    expr = builtins.sort builtins.lessThan
      (builtins.attrNames (graphLib.select nodes (n: n.type == "datastore")));
    expected = [ "cache" "database" "queue" ];
  };
}
