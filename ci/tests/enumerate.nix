{ lib, genGraph, ... }:
let
  inherit (genGraph)
    roots
    leaves
    select
    fixtures
    mkGraph
    ;
in
{
  flake.tests.enumerate = {
    test-roots-attributed = {
      expr = roots fixtures.attributed;
      expected = [
        "elm"
        "fir"
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
    test-leaves-attributed = {
      expr = leaves fixtures.attributed;
      expected = [
        "birch"
        "cedar"
        "dogwood"
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
        select { inherit (fixtures.attributed) nodes nodeData; } (d: (d.type or null) == "bough")
      );
      expected = [
        "alder"
        "fir"
      ];
    };
    test-select-datastores = {
      expr = builtins.sort builtins.lessThan (
        select { inherit (fixtures.attributed) nodes nodeData; } (d: (d.type or null) == "burl")
      );
      expected = [
        "birch"
        "cedar"
        "dogwood"
      ];
    };
    test-select-none = {
      expr = select { inherit (fixtures.attributed) nodes nodeData; } (
        d: (d.type or null) == "nonexistent"
      );
      expected = [ ];
    };
  };
}
