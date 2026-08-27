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

    # ── THE CONVERGENCE CHECK: A CONCLUSION THE CONVERGED GRAPH WITHDRAWS ──
    #
    # A rule that fires on the ABSENCE of a fact and then produces it. Round 0 sees no
    # y-child and spawns one; round 1 sees the y-child and does not; union cannot retract,
    # so the run converges holding a conclusion the converged graph no longer supports.
    # Measured before the check: this RETURNED `root -> [ "a" "y" ]`, converged and
    # well-formed, with nothing reporting. WHICH conclusion the refusal names is asserted
    # on `./ci#testsError`, the only runner that can read a message.
    test-seeded-refuses-a-conclusion-the-converged-graph-withdraws = {
      expr =
        !(builtins.tryEval (seededFixpoint {
          seed = {
            root = [ "a" ];
          };
          frontier = {
            root = [ "a" ];
          };
          step = _dF: acc: if builtins.elem "y" (acc.root or [ ]) then { } else { root = [ "y" ]; };
        })).success;
      expected = true;
    };
    # ★ THE SAME WRONG ANSWER WITH `acc` DISCARDED, which is why the remedy is a check and
    # not a narrower signature. Removing the accumulator argument would not make the
    # absence read inexpressible — it moves it onto the frontier and converges on the same
    # unsupported conclusion. The cell holds that refutation so it cannot be re-argued.
    test-seeded-refuses-the-same-oscillation-read-through-the-frontier-alone = {
      expr =
        !(builtins.tryEval (seededFixpoint {
          seed = {
            root = [ "a" ];
          };
          frontier = {
            root = [ "a" ];
          };
          step = dF: _acc: if builtins.elem "y" (dF.root or [ ]) then { } else { root = [ "y" ]; };
        })).success;
      expected = true;
    };
    # ★★ THE CEILING, INSTRUMENTED — THIS CELL ASSERTS THE WRONG ANSWER IS RETURNED.
    #
    # The check is ONE-STEP SUPPORT, strictly weaker than foundedness, so the absence of a
    # refusal is NOT evidence that a step is monotone. `p :- not r. p :- p. r :- a` draws
    # `p` from the absence of `r`, and the self-loop `p :- p` then supports `p` forever
    # after `r` arrives. Its step is measurably non-monotone — `step {a}` yields `p`,
    # `step {a,r}` does not — and it is RETURNED, `p` included, which the well-founded
    # model makes FALSE. Closing the gap is ADR-0020's well-founded engine, Phase-C den
    # territory, not this binding's.
    #
    # Written against the RETURNED VALUE rather than `tryEval success`, so it pins WHAT
    # comes back and not merely that something does. When the gap closes this goes red.
    test-seeded-circular-rederivation-is-supported-and-RETURNED = {
      expr =
        let
          has = m: x: builtins.elem x (m.root or [ ]);
          answer = seededFixpoint {
            seed = {
              root = [ "a" ];
            };
            frontier = {
              root = [ "a" ];
            };
            step = _dF: acc: {
              root =
                (if !(has acc "r") then [ "p" ] else [ ])
                ++ (if has acc "p" then [ "p" ] else [ ])
                ++ (if has acc "a" then [ "r" ] else [ ]);
            };
          };
        in
        builtins.sort builtins.lessThan (answer.root or [ ]);
      # The well-founded model is [ "a" "r" ]; `p` is unfounded and comes back anyway.
      expected = [
        "a"
        "p"
        "r"
      ];
    };
    # The support check applies `step` once at convergence, INCLUDING on the empty-frontier
    # path, where the loop returns without ever entering a round. A step that throws on
    # inputs that path never used to reach now throws. Behaviour change against the parent
    # rev, pinned rather than left for a caller to discover.
    test-seeded-empty-frontier-still-applies-the-step = {
      expr =
        !(builtins.tryEval (seededFixpoint {
          seed = {
            root = [ "a" ];
          };
          frontier = { };
          step = _dF: _acc: throw "step reached";
        })).success;
      expected = true;
    };
    # LIVE CONTROL on the same predicate in the same run: a MONOTONE step that genuinely
    # derives new facts passes the check and returns them. Without it the cells above are
    # consistent with a seededFixpoint that now refuses everything that derives anything
    # at all.
    test-seeded-monotone-step-deriving-new-facts-is-not-refused = {
      expr =
        let
          mat = materialize fixtures.chain;
        in
        (builtins.tryEval (seededFixpoint {
          seed = mat;
          frontier = mat;
          step = dF: _: compose dF mat;
        })).success;
      expected = true;
    };
  };
}
