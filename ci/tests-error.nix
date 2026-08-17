# THE SECOND TEST OUTPUT — cells whose subject is an ERROR, and the runner that reads them.
#
# `coneRank` refuses a cyclic cone by name and NAMES THE CYCLE. That it refuses is a boolean
# and `tryEval` can assert it; WHICH cycle it named is a claim about the message, and the
# only assertion available for that is nix-unit's `expectedError`.
#
# ★ WHY A SECOND OUTPUT RATHER THAN A SECOND SUITE. `gen.lib.mkCi` builds `checks.default`
# from a homegrown asserter that evaluates `t.expr == t.expected` UNCONDITIONALLY, and it
# quantifies over `config.flake.tests` and nothing else. A cell with no `expected` and a
# throwing `expr` therefore CRASHES that batch gate rather than failing it — measured: with
# these cells inside `flake.tests`, `nix flake check ./ci` died with this file's own refusal
# message. Hosting them on `flake.testsError` puts them out of the asserter's quantifier
# while keeping them live on the nix-unit path, which is exactly what the spec's
# "nix-unit-path-only" clause asks for, expressed structurally instead of as a known break.
#
# ★ AND THE SPLIT IS STRUCTURAL, NOT CONVENTIONAL. This file is NOT under `./tests`, which is
# the whole of `testModules`, so nothing about which cells land in which output depends on a
# filter predicate or on an ignore convention that a dependency bump could redefine. It
# reaches the flake through `mkCi`'s `extraModules`.
#
# BOTH OUTPUTS NEED RUNNING, so both get a hook. `gen/ci/flakeModule.nix`'s `ci` hook
# hard-codes `./ci#tests`; the `ci-error` hook below is its counterpart and is declared
# through the same `pre-commit.settings.hooks` surface.
#
#   nix-unit --flake ./ci#tests        # the suite
#   nix-unit --flake ./ci#testsError   # these cells
#
# The consultation-order discriminator that says WHY the refusal works — one construction, a
# single switch on whether the driver's verdict is read before the memo map is entered —
# cannot live in either runner: the wrong order produces an uncatchable `infinite recursion`
# that kills the runner rather than failing a cell. It is an exit-code sweep,
# `ci/bench/cone-consultation.sh`.
{
  lib,
  genGraph,
  genInputs,
  ...
}:
let
  inherit (genGraph) mkGraph coneRank;

  # a -> b -> c -> a, read as dependencies: a cone with no producers-first rank at all.
  cyclic = mkGraph {
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
        to = "a";
      }
    ];
  };
  # `den-hoag-ges2` F1's own fixture: a 2-cycle at the HEAD of a chain, which is the shape
  # that shows the abort it replaces arrives at depth 2 rather than at any bound.
  cycshort = mkGraph {
    edges = [
      {
        from = "a";
        to = "b";
      }
      {
        from = "b";
        to = "a";
      }
      {
        from = "c";
        to = "b";
      }
      {
        from = "d";
        to = "c";
      }
    ];
  };
  acyclic = mkGraph {
    edges = [
      {
        from = "q";
        to = "p";
      }
    ];
  };

  # ── THE CLOSURE CLASS'S FIXTURE ──
  # A 25-node chain PLUS the fork n000000 → n000002. The chain supplies the DEPTH (the
  # closure needs 23 rounds), and the fork supplies the out-degree: `transitiveReduction`
  # shares one closure binding behind a `mid != to` guard, so on a graph whose every node has
  # out-degree ≤ 1 that binding is never forced and the surface would not reach the ceiling
  # at all. One node with two successors puts all four members on the same path — measured:
  # under the squared schedule all four have the same cap boundary on this fixture.
  #
  # ★★ ITS DIAMETER IS 23, NOT 24, AND THE FORK EDGE IS WHY. `n000000 → n000002` is a
  # SHORTCUT: it skips `n000001`, so the longest shortest path is one hop shorter than the
  # bare chain's. Measured by BFS — this fixture 23, the same chain WITHOUT the fork edge 24,
  # a 50-node bare chain 49 as the control that the instrument reads a chain correctly. The
  # "23 rounds" above is therefore right, and the naive schedule's own boundary confirms it
  # from the other side: it returns iff the cap ≥ the diameter, and on this fixture that is
  # cap ≥ 23 rather than 24. Worth stating because the fork reads like added depth and is
  # subtracted depth, and a reader who counts chain links gets 24.
  pad =
    i:
    let
      s = toString i;
    in
    builtins.substring 0 (6 - builtins.stringLength s) "000000" + s;
  key = i: "n" + pad i;
  chainLen = 25;
  fork = mkGraph {
    edges =
      map (i: {
        from = key i;
        to = key (i + 1);
      }) (builtins.genList (i: i) (chainLen - 1))
      ++ [
        {
          from = key 0;
          to = key 2;
        }
      ];
  };
  # A closure-class surface forwards a `maxIter` set on its own argument record. Lowering it
  # is what makes the ceiling reachable in a cell at all: under repeated squaring the shipped
  # cap of 1,000 stands for a diameter of 2^999, and no fixture reaches that.
  # ★ ONE BINDING, because the cap and the bound the cells assert must move together. The
  # refusal pattern derives its bound from this number; a second copy is a copy to keep in step.
  #
  # ★★ THE MARGIN IS FOUR ROUNDS, AND IT IS STATED HERE BECAUSE IT USED TO BE ONE. These cells
  # assert a THROW, so they go vacuously green the moment the cap reaches the boundary at which
  # the closure converges — and the squared schedule moved that boundary from 23 rounds to 6.
  # At the previous cap of 5 the margin was a SINGLE round: one fixture or cap edit from a cell
  # that passes by converging rather than by refusing, with nothing in the file saying so. The
  # cap is 2 and the measured boundary on this fixture is 6, on all four surfaces, so the
  # margin is four rounds. Lowering the cap is the right lever rather than deepening the
  # fixture, because the shipped-cap controls below are themselves a cell about the SCHEDULE
  # and a deeper fixture would move their answers for an unrelated reason.
  cappedIter = 2;
  capped = fork // {
    maxIter = cappedIter;
  };
  # One round below the measured boundary of 6: the tightest cap at which this fixture must
  # still refuse. It is the margin's tripwire, and it is derived from the boundary rather than
  # written beside it so that moving one moves the other.
  boundaryIter = 6;
  marginProbeIter = boundaryIter - 1;
  marginProbe = fork // {
    maxIter = marginProbeIter;
  };

  # ONE DRIVER PER CLASS MEMBER, keyed by the name its refusal must carry. The cells below
  # are GENERATED from `genGraph.closureClass`, so a fifth closure caller cannot join that
  # enumeration without a driver and a cell arriving with it — which is the failure a count
  # of four cannot see. Each driver forces the shared closure and returns something small.
  drive = {
    transitiveClosure =
      g: builtins.sort builtins.lessThan ((genGraph.transitiveClosure g)."n000022" or [ ]);
    dependents = g: genGraph.dependents g "n000001";
    condensationClosure = g: builtins.length (genGraph.condensationClosure g).sccs;
    transitiveReduction = g: (genGraph.transitiveReduction g)."n000000" or [ ];
  };
  # What each driver answers at the SHIPPED cap on the SAME fixture — the live control that
  # the refusals above pin the CAP and not the fixture.
  shipped = {
    transitiveClosure = [
      "n000023"
      "n000024"
    ];
    dependents = [ "n000000" ];
    condensationClosure = 25;
    transitiveReduction = [ "n000001" ];
  };

  # The refusal text, raised once at the closure binding and inherited by the four. Anchored
  # at both ends: an unanchored pattern would go green on a message that had grown a cause it
  # cannot support, and the whole point of the split is which causes may be named where.
  # ★ The bound is DERIVED FROM THE CONVERSION rather than written down beside the cap. Under
  # repeated squaring round r holds every path of length ≤ 2^r, so exhausting a cap of c means
  # the diameter exceeds 2^(c−1); this expression re-derives that the moment the cap moves,
  # where a literal would go on asserting a bound the library no longer states.
  closureRefusal =
    surface: cap:
    "^gen-graph: ${surface}: the graph's reachability diameter exceeds 2\\^${toString (cap - 1)}, the depth reached by the closure fixpoint's iteration cap of ${toString cap} under repeated squaring\\. The closure step is monotone on the subset order by construction, so an unconverged closure at the cap is depth and nothing else\\.$";

  # `den-hoag-73uq`'s mode: removes one edge and adds another, so `countEdges` is constant and the
  # cardinality guard never fires. Non-convergence surfaces `maxIter` rounds later.
  antitoneStep = cur: if (cur.a or [ ]) == [ "x" ] then { a = [ "y" ]; } else { a = [ "x" ]; };
in
{
  # Same type as `flake.tests` (`gen/ci/flakeModule.nix`), because it is the same kind of
  # thing read by the same runner — only the assertion the cells carry differs.
  options.flake.testsError = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites whose cells assert an ERROR: { suite.test = { expr; expectedError; }; }. Read by `nix-unit --flake ./ci#testsError`; deliberately outside `flake.tests`, which the batch asserter quantifies over.";
  };

  config = {
    flake.testsError.cone-refusal = {
      # The message NAMES THE CYCLE. A refusal that only said "cyclic" would leave the caller
      # to re-derive which cycle, on a graph the library has already decomposed.
      test-conerank-cyclic-refuses-naming-the-cycle = {
        expr = (coneRank cyclic cyclic.nodes).order;
        expectedError = {
          type = "ThrownError";
          msg = ".*cyclic cone.*\\[\\[\"a\",\"b\",\"c\"\\]\\].*";
        };
      };
      # The 2-cycle at the head of a chain: the component is named, and the acyclic tail is
      # not — the report is the cycle, not the cone.
      test-conerank-cycshort-refuses-naming-the-component = {
        expr = (coneRank cycshort cycshort.nodes).depth;
        expectedError = {
          type = "ThrownError";
          msg = ".*cyclic cone.*\\[\\[\"a\",\"b\"\\]\\].*";
        };
      };
      # ── THE ILL-TYPED CLASSES, NAMED ──
      # That these refuse AT ALL is a boolean, and it is asserted beside the arm's own
      # halves in `ci/tests/arms.nix`, which is where the door-against-arm parity claim
      # belongs. What only this output can assert is that the refusal NAMES the class and
      # the type it found: the two sites abort identically, so a caller handed a cone built
      # from keys it did not check cannot tell them apart from the failure alone and is
      # sent back to bisect its own fixture. Anchored at both ends for the reason the
      # closure refusals are — an unanchored pattern goes green on a message that has grown
      # a cause it cannot support.
      test-conerank-non-string-cone-id-names-the-class-and-the-type = {
        expr = (coneRank { edges = _: [ ]; } [ 42 ]).order;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-graph\\.coneRank: cone entry is a non-string key \\(type int\\); cone ids must be strings$";
        };
      };
      # The other site. It names the NODE the target hangs off, which is the only locator
      # the door has: the cone is a list the caller supplied and the edges come out of a
      # function, so there is no index to give and the producing node is what there is.
      test-conerank-non-string-edge-target-names-the-class-and-the-node = {
        expr = (coneRank { edges = _: [ 42 ]; } [ "a" ]).order;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-graph\\.coneRank: edge target of type int on node \"a\" is not a string; cone membership needs a string target$";
        };
      };
      # The type is READ OFF THE VALUE rather than a fixed word: the same site with a list
      # target says `list`. Without this the two cells above are consistent with a message
      # that hard-codes `int`, which is the shape a copied refusal takes.
      test-conerank-non-string-edge-target-reports-the-type-it-found = {
        expr = (coneRank { edges = _: [ [ "x" ] ]; } [ "a" ]).depth;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-graph\\.coneRank: edge target of type list on node \"a\" is not a string; cone membership needs a string target$";
        };
      };
      # LIVE CONTROL, same run: an acyclic cone through the same accessor does not refuse.
      # Without it, the cells above are consistent with a surface that refuses everything.
      # It is an `expected` cell in an `expectedError` output on purpose — the control has to
      # run in the same invocation as the thing it controls, or it controls nothing.
      test-conerank-acyclic-control = {
        expr = (coneRank acyclic acyclic.nodes).order;
        expected = [
          "p"
          "q"
        ];
      };
    };

    # ── THE CLOSURE CLASS REFUSES BY NAME, AND ONLY IT MAY ──
    #
    # The closure's step is fixed and monotone on the subset order, so a cap it did not reach
    # convergence within IS the graph's diameter and the refusal says so. The exported generic
    # `fixpoint` takes the caller's step, where two unrelated causes — a monotone chain longer
    # than the cap, and an oscillation the cardinality guard cannot see — produce the same
    # state; there the message names no cause. The discriminator cells below are what keep the
    # two apart: without them the suite is green for a construction that tells every caller
    # with an oscillating step that their graph is deep.
    flake.testsError.closure-refusal =
      builtins.listToAttrs (
        map (surface: {
          # (a) + (b) + (d): the refusal names the diameter it could not reach and the surface
          # the caller called, at every member of the enumeration.
          name = "test-closure-${surface}-refuses-naming-diameter-and-surface";
          value = {
            expr = drive.${surface} capped;
            expectedError = {
              type = "ThrownError";
              msg = closureRefusal surface cappedIter;
            };
          };
        }) genGraph.closureClass
        # ★ THE MARGIN, ASSERTED RATHER THAN LEFT FOR A READER TO COMPUTE. The cells above pass
        # by REFUSING, so they go vacuously green the moment the closure starts converging
        # inside the cap. `marginProbe` is one round BELOW the measured boundary: it must still
        # throw. If a cheaper schedule ever moves the boundary down onto the cap, this cell goes
        # red first and says so, where the cells above would simply stop testing anything.
        ++ map (surface: {
          name = "test-closure-${surface}-still-refuses-one-round-below-the-boundary";
          value = {
            expr = drive.${surface} marginProbe;
            expectedError = {
              type = "ThrownError";
              msg = closureRefusal surface marginProbeIter;
            };
          };
        }) genGraph.closureClass
        ++ map (surface: {
          # (c) LIVE CONTROL, same run, same fixture, shipped cap: it returns. Without this
          # the four cells above are consistent with a fixture that cannot be closed at all.
          name = "test-closure-${surface}-shipped-cap-control";
          value = {
            expr = drive.${surface} fork;
            expected = shipped.${surface};
          };
        }) genGraph.closureClass
      )
      // {
        # The enumeration is the checked artefact. A member with no driver takes this cell red
        # before it can reach a refusal cell that would report the wrong message.
        test-closure-class-drivers-cover-the-enumeration = {
          expr = builtins.attrNames drive;
          expected = builtins.sort builtins.lessThan genGraph.closureClass;
        };

        # ★ THE DISCRIMINATOR. An antitone caller-supplied step through the exported
        # `fixpoint` gets the CAUSE-FREE message; the anchors are what make this an assertion
        # that the diameter text is ABSENT rather than an assertion that some text is present.
        test-generic-fixpoint-antitone-step-names-no-cause = {
          expr = genGraph.fixpoint {
            seed = {
              a = [ "x" ];
            };
            step = antitoneStep;
            maxIter = 7;
          };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph: fixpoint exceeded 7 iterations: the step neither converged nor shrank\\. `step` is the caller's, so this binding reports what it observed and names no cause\\.$";
          };
        };
        # The other cause, same binding, same message form: a MONOTONE step under its cap —
        # the closure's own construction, driven through the generic surface where the binding
        # cannot know that is what it is holding. The pair is the reason (ii) may not name a
        # cause, and it is asserted rather than argued.
        test-generic-fixpoint-monotone-under-cap-names-no-cause = {
          expr = genGraph.fixpoint {
            seed = genGraph.materialize fork;
            step = cur: genGraph.unionEdges cur (genGraph.compose cur (genGraph.materialize fork));
            maxIter = 5;
          };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph: fixpoint exceeded 5 iterations: the step neither converged nor shrank\\. `step` is the caller's, so this binding reports what it observed and names no cause\\.$";
          };
        };
        # LIVE CONTROL on the claim the cause-free message makes: the step "never shrank" is an
        # observation, not a tautology — a step that DOES shrink is refused by the size guard,
        # by its own name, before the cap is reached.
        test-generic-fixpoint-shrinking-step-still-hits-the-size-guard = {
          expr = genGraph.fixpoint {
            seed = {
              a = [
                "x"
                "y"
              ];
            };
            step = _: { a = [ "x" ]; };
            maxIter = 7;
          };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph: fixpoint step is not monotonic \\(2 → 1\\)$";
          };
        };
        # LIVE CONTROL, same run: the generic binding converges and returns. Without it the
        # three cells above are consistent with a `fixpoint` that refuses everything.
        test-generic-fixpoint-converging-control = {
          expr = genGraph.fixpoint {
            seed = {
              a = [ "x" ];
            };
            step = cur: cur;
            maxIter = 7;
          };
          expected = {
            a = [ "x" ];
          };
        };
      };

    # THE SECOND HOOK. A second output that nothing runs is a second output that rots, and
    # the wrapper `gen/ci/flakeModule.nix` builds bakes `./ci#tests` into its own text, so it
    # cannot be pointed at this one. This is its counterpart, built the same way, under a
    # distinct hook id so the two merge rather than collide.
    perSystem =
      { pkgs, system, ... }:
      {
        pre-commit.settings.hooks.ci-error = {
          enable = true;
          name = "ci-error";
          description = "Run nix-unit error-assertion tests";
          entry = "${
            pkgs.writeShellApplication {
              name = "gen-graph-ci-nix-unit-error";
              runtimeInputs = [ genInputs.nix-unit.packages.${system}.default ];
              text = ''
                exec nix-unit --flake ./ci#testsError "$@"
              '';
            }
          }/bin/gen-graph-ci-nix-unit-error";
          files = "\\.nix$";
          pass_filenames = false;
        };
      };
  };
}
