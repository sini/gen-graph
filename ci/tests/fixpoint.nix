{ lib, graphLib, ... }:
let
  inherit (graphLib)
    fixpoint
    compose
    transitiveClosure
    transitiveReduction
    materialize
    ;
  inherit (graphLib.mock) fixtures mkGraph;
in
{
  fixpoint-tests = {
    test-closure-chain = {
      expr =
        let
          closure = transitiveClosure fixtures.chain;
        in
        builtins.sort builtins.lessThan (closure."a" or [ ]);
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    test-closure-diamond = {
      expr =
        let
          closure = transitiveClosure fixtures.diamond;
        in
        builtins.sort builtins.lessThan (closure."a" or [ ]);
      expected = [
        "b"
        "c"
        "d"
      ];
    };
    test-closure-leaf-empty = {
      expr =
        let
          closure = transitiveClosure fixtures.chain;
        in
        closure."d" or [ ];
      expected = [ ];
    };
    test-reduction-chain-unchanged = {
      expr =
        let
          red = transitiveReduction fixtures.chain;
        in
        builtins.sort builtins.lessThan (red."a" or [ ]);
      expected = [ "b" ];
    };
    test-reduction-removes-redundant = {
      expr =
        let
          g = mkGraph {
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
                from = "a";
                to = "c";
              }
            ];
          };
          red = transitiveReduction g;
        in
        builtins.sort builtins.lessThan (red."a" or [ ]);
      expected = [ "b" ];
    };
    test-compose-basic = {
      expr =
        let
          mat = materialize fixtures.chain;
          comp = compose mat mat;
        in
        builtins.sort builtins.lessThan (comp."a" or [ ]);
      expected = [ "c" ];
    };
    test-compose-leaf = {
      expr =
        let
          mat = materialize fixtures.chain;
          comp = compose mat mat;
        in
        comp."d" or [ ];
      expected = [ ];
    };
    test-fixpoint-converges = {
      expr =
        let
          result = fixpoint {
            seed = {
              a = [ ];
            };
            step =
              current:
              if builtins.length (current.a or [ ]) < 3 then
                current // { a = (current.a or [ ]) ++ [ "x" ]; }
              else
                current;
          };
        in
        builtins.length (result.a or [ ]);
      expected = 3;
    };
    test-fixpoint-monotonicity-violation = {
      expr =
        !(builtins.tryEval (fixpoint {
          seed = {
            a = [
              "x"
              "y"
            ];
          };
          step = _: { a = [ "x" ]; };
        })).success;
      expected = true;
    };
    test-fixpoint-max-iter = {
      expr =
        !(builtins.tryEval (fixpoint {
          seed = {
            a = [ ];
          };
          step = current: current // { a = current.a ++ [ "x" ]; };
          maxIter = 5;
        })).success;
      expected = true;
    };
    test-compose-empty = {
      expr = compose { } { };
      expected = { };
    };
    test-compose-with-empty = {
      expr = compose { a = [ "b" ]; } { };
      expected = {
        a = [ ];
      };
    };
    test-fixpoint-already-converged = {
      expr = fixpoint {
        seed = {
          a = [ "b" ];
          b = [ ];
        };
        step = current: current;
      };
      expected = {
        a = [ "b" ];
        b = [ ];
      };
    };
    test-closure-self-loop = {
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
          closure = transitiveClosure g;
        in
        closure."a" or [ ];
      expected = [ "a" ];
    };
  };
}
