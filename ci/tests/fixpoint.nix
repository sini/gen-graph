{ lib, genGraph, ... }:
let
  inherit (genGraph)
    fixpoint
    seededFixpoint
    compose
    closureClass
    closureOf
    transitiveClosure
    transitiveReduction
    materialize
    ;
  inherit (genGraph) fixtures mkGraph;
in
{
  flake.tests.fixpoint-tests = {
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
    # The closure class, pinned as a VALUE and not as a count. The four surfaces share one
    # ceiling and one refusal, and the refusal names the surface it was called through, so
    # the list is what a fifth closure caller has to join before it can refuse by name at
    # all. What each member's refusal SAYS is asserted on `./ci#testsError`, which is the
    # only runner that can read a message.
    test-closure-class-enumeration = {
      expr = closureClass;
      expected = [
        "transitiveClosure"
        "dependents"
        "condensationClosure"
        "transitiveReduction"
      ];
    };
    # A surface off the list cannot be constructed, so no refusal can name a surface the
    # library does not have. Positive control: a member constructs and answers.
    test-closureOf-refuses-a-non-member-surface = {
      expr = (builtins.tryEval (closureOf "notAClosureSurface" fixtures.chain)).success;
      expected = false;
    };
    test-closureOf-member-control = {
      expr = builtins.sort builtins.lessThan ((closureOf "dependents" fixtures.chain)."a" or [ ]);
      expected = [
        "b"
        "c"
        "d"
      ];
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
    # --- seededFixpoint ---
    # Canonical semi-naive transitive-closure instance: dR = dR . R (vs naive R . R).
    test-seeded-closure-equals-transitiveClosure-chain = {
      expr =
        let
          mat = materialize fixtures.chain;
          sn = seededFixpoint {
            seed = mat;
            frontier = mat;
            step = dF: _: compose dF mat;
          };
        in
        builtins.sort builtins.lessThan (sn."a" or [ ]);
      expected = builtins.sort builtins.lessThan ((transitiveClosure fixtures.chain)."a" or [ ]);
    };
    test-seeded-closure-equals-transitiveClosure-diamond = {
      expr =
        let
          mat = materialize fixtures.diamond;
          sn = seededFixpoint {
            seed = mat;
            frontier = mat;
            step = dF: _: compose dF mat;
          };
        in
        builtins.sort builtins.lessThan (sn."a" or [ ]);
      expected = builtins.sort builtins.lessThan ((transitiveClosure fixtures.diamond)."a" or [ ]);
    };
    test-seeded-empty-frontier-returns-seed = {
      expr = seededFixpoint {
        seed = {
          a = [ "b" ];
        };
        frontier = { };
        step = dF: _: compose dF { };
      };
      expected = {
        a = [ "b" ];
      };
    };
    test-seeded-max-iter-throws = {
      # A non-converging step (always produces a fresh fact) must throw at maxIter.
      expr =
        !(builtins.tryEval (seededFixpoint {
          seed = {
            a = [ "n0" ];
          };
          frontier = {
            a = [ "n0" ];
          };
          step = dF: _: lib.mapAttrs (_: ts: map (t: t + "x") ts) dF;
          maxIter = 5;
        })).success;
      expected = true;
    };
    test-seeded-property-equals-naive-over-fixtures = {
      # property: the canonical semi-naive instance == transitiveClosure on every
      # fixture shape (gen-graph has no random-DAG generator; multiple shapes stand
      # in for the "semi-naive == naive over random DAGs" equivalence). Sorted per-node compare.
      expr =
        let
          ok =
            g:
            let
              mat = materialize g;
              sn = seededFixpoint {
                seed = mat;
                frontier = mat;
                step = dF: _: compose dF mat;
              };
              tc = transitiveClosure g;
            in
            builtins.all (
              n:
              builtins.sort builtins.lessThan (sn.${n} or [ ]) == builtins.sort builtins.lessThan (tc.${n} or [ ])
            ) g.nodes;
        in
        builtins.all ok [
          fixtures.chain
          fixtures.diamond
          fixtures.serviceGraph
          fixtures.cyclic
        ];
      expected = true;
    };
  };
}
