{ lib, graphLib, ... }:
let
  inherit (graphLib)
    roots
    leaves
    select
    fixtures
    mkGraph
    ;
in
{
  flake.tests.enumerate = {
    test-roots-service = {
      expr = roots fixtures.serviceGraph;
      expected = [
        "web"
        "worker"
      ];
    };
    test-roots-chain = {
      expr = roots fixtures.chain;
      expected = [ "a" ];
    };
    test-roots-empty = {
      expr = roots (mkGraph { });
      expected = [ ];
    };
    test-leaves-service = {
      expr = leaves fixtures.serviceGraph;
      expected = [
        "cache"
        "db"
        "queue"
      ];
    };
    test-leaves-chain = {
      expr = leaves fixtures.chain;
      expected = [ "d" ];
    };
    test-leaves-empty = {
      expr = leaves (mkGraph { });
      expected = [ ];
    };
    test-select-by-type = {
      expr = builtins.sort builtins.lessThan (
        select { inherit (fixtures.serviceGraph) nodes nodeData; } (d: (d.type or null) == "backend")
      );
      expected = [
        "api"
        "worker"
      ];
    };
    test-select-datastores = {
      expr = builtins.sort builtins.lessThan (
        select { inherit (fixtures.serviceGraph) nodes nodeData; } (d: (d.type or null) == "datastore")
      );
      expected = [
        "cache"
        "db"
        "queue"
      ];
    };
    test-select-none = {
      expr = select { inherit (fixtures.serviceGraph) nodes nodeData; } (
        d: (d.type or null) == "nonexistent"
      );
      expected = [ ];
    };
  };
}
