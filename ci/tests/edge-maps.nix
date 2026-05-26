{ lib, graphLib, ... }:
let
  inherit (graphLib)
    materialize
    materializeParents
    unionEdges
    intersectEdges
    differenceEdges
    selectEdges
    ;
  inherit (graphLib.mock) fixtures mkGraph;
in
{
  edge-maps = {
    test-materialize-chain = {
      expr =
        let
          mat = materialize fixtures.chain;
        in
        mat."a";
      expected = [ "b" ];
    };
    test-materialize-leaf = {
      expr =
        let
          mat = materialize fixtures.chain;
        in
        mat."d";
      expected = [ ];
    };
    test-materialize-diamond = {
      expr =
        let
          mat = materialize fixtures.diamond;
        in
        builtins.sort builtins.lessThan mat."a";
      expected = [
        "b"
        "c"
      ];
    };
    test-union-dedup = {
      expr =
        let
          a = {
            x = [
              "a"
              "b"
            ];
          };
          b = {
            x = [
              "b"
              "c"
            ];
          };
          result = unionEdges a b;
        in
        builtins.sort builtins.lessThan result.x;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-union-disjoint = {
      expr =
        let
          a = {
            x = [ "a" ];
          };
          b = {
            y = [ "b" ];
          };
          result = unionEdges a b;
        in
        {
          x = result.x;
          y = result.y;
        };
      expected = {
        x = [ "a" ];
        y = [ "b" ];
      };
    };
    test-intersect = {
      expr =
        let
          a = {
            x = [
              "a"
              "b"
              "c"
            ];
          };
          b = {
            x = [
              "b"
              "c"
              "d"
            ];
          };
        in
        builtins.sort builtins.lessThan (intersectEdges a b).x;
      expected = [
        "b"
        "c"
      ];
    };
    test-intersect-disjoint = {
      expr = intersectEdges { x = [ "a" ]; } { x = [ "b" ]; };
      expected = { };
    };
    test-difference = {
      expr =
        let
          a = {
            x = [
              "a"
              "b"
              "c"
            ];
          };
          b = {
            x = [ "b" ];
          };
        in
        builtins.sort builtins.lessThan (differenceEdges a b).x;
      expected = [
        "a"
        "c"
      ];
    };
    test-difference-empty = {
      expr = differenceEdges { x = [ "a" ]; } { x = [ "a" ]; };
      expected = { };
    };
    test-materialize-parents-tree = {
      expr =
        let
          mp = materializeParents fixtures.tree;
        in
        mp;
      expected = {
        child1 = "root";
        child2 = "root";
        grandchild = "child1";
      };
    };
    test-materialize-parents-no-parents = {
      expr = materializeParents fixtures.chain;
      expected = { };
    };
    test-select-edges-basic = {
      expr =
        let
          mat = materialize fixtures.serviceGraph;
          filtered = selectEdges (from: _to: from == "api") mat;
        in
        builtins.sort builtins.lessThan (filtered."api" or [ ]);
      expected = [
        "cache"
        "db"
      ];
    };
    test-select-edges-by-target = {
      expr =
        let
          mat = materialize fixtures.serviceGraph;
          filtered = selectEdges (_from: to: to == "db") mat;
        in
        builtins.sort builtins.lessThan (builtins.attrNames filtered);
      expected = [
        "api"
        "worker"
      ];
    };
    test-intersect-disjoint-sources = {
      expr = intersectEdges { x = [ "a" ]; } { y = [ "b" ]; };
      expected = { };
    };
    test-difference-b-extra-keys = {
      expr =
        let
          a = {
            x = [
              "a"
              "b"
            ];
          };
          b = {
            x = [ "a" ];
            y = [ "z" ];
          };
        in
        differenceEdges a b;
      expected = {
        x = [ "b" ];
      };
    };
    test-union-disjoint-sources = {
      expr =
        let
          result = unionEdges { x = [ "a" ]; } { y = [ "b" ]; };
        in
        result;
      expected = {
        x = [ "a" ];
        y = [ "b" ];
      };
    };
  };
}
