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
# BOTH OUTPUTS NEED RUNNING, so both get a hook — and `gen-harness`'s shared flake module wires
# both, beside each other, off the same read-roots guard. `ci` hard-codes `./ci#tests` and cannot
# be pointed at this one; `ci-error` is its counterpart and this file supplies only its cells.
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
  genGraph,
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
  # `cycshort` — a 2-cycle at the HEAD of a chain, which is the shape that shows the abort it
  # replaces arrives at depth 2 rather than at any bound. `ci/bench/cone-consultation.nix` builds
  # the same shape under the same name, so its figure and this refusal are about one graph.
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

  # The antitone mode: removes one edge and adds another, so the edge COUNT is constant and a
  # cardinality test is blind to it — which is what made this step worth pinning, and what the
  # carrier grieved: non-convergence used to surface `maxIter` rounds later, under a message that
  # names no cause. The subset guard is not blind to it. It refuses at the FIRST step, naming the
  # edge withdrawn, and the saving is linear in the cap: at the shipped default of 1,000 rounds
  # this fixture goes 9,015 → 38 `nrFunctionCalls`.
  antitoneStep = cur: if (cur.a or [ ]) == [ "x" ] then { a = [ "y" ]; } else { a = [ "x" ]; };

  # ASCENDS FOR THREE ROUNDS AND THEN WITHDRAWS, size-preserving across the withdrawal so a
  # cardinality test is blind to that too. This is the step that discriminates the guard from one
  # refusing too eagerly: naming `e0` proves the three ascending rounds were ADMITTED and only the
  # first non-ascending one was refused. A guard that fired on round 1 would not reach it.
  ascendThenWithdrawStep =
    cur:
    let
      n = builtins.length cur.a;
    in
    if n < 4 then
      { a = cur.a ++ [ "e${toString n}" ]; }
    else
      { a = builtins.filter (x: x != "e0") cur.a ++ [ "e9" ]; };

  # INFLATIONARY BUT NOT MONOTONE: it only ever appends, so the subset guard never fires; it reads
  # the ABSENCE of `b`, so it is not monotone. The second construction that genuinely reaches the
  # cap once the guard lands, and the reason the cap's pair below is still ASSERTED rather than
  # argued — the antitone half is now refused before the cap and can no longer stand in it.
  inflationaryNonMonotoneStep = cur: {
    a = cur.a ++ (if cur ? b then [ ] else [ "n${toString (builtins.length cur.a)}" ]);
  };

  # The WITHDRAWAL refusal, raised once at the generic `fixpoint` binding and inherited by the
  # three cells that assert it. Anchored at both ends, for the same reason `closureRefusal` is:
  # what the split is about is which causes may be named where, so a pattern that could absorb a
  # grown message asserts nothing. ★ The count is DERIVED FROM THE PAIRS rather than written down
  # beside them, so a fixture withdrawing a second edge cannot leave the two disagreeing.
  notAscending =
    pairs:
    "^gen-graph: fixpoint step is not ascending: it withdrew ${toString (builtins.length pairs)} edge\\(s\\) the accumulator already held: ${builtins.concatStringsSep ", " pairs}\\. The iterates of a step that retracts are a walk, not an ascending chain, and a walk in a finite carrier cycles rather than converging\\. `step` must not withdraw an edge the accumulator holds\\.$";
in
{
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
    # `fixpoint` takes the caller's step, where two unrelated causes still produce the same state
    # — an ascent (monotone, or merely inflationary) longer than the cap, and a step stationary in
    # edge content that is never literally equal — and there the message names no cause. The
    # discriminator cells below are what keep the two apart: without them the suite is green for a
    # construction that tells every caller with a non-converging step that their graph is deep.
    # ★ THE THIRD CAUSE IS NO LONGER ONE OF THEM. A step that WITHDRAWS an edge used to arrive
    # here indistinguishable from depth; it is now refused at the step it withdraws, by a binding
    # that has observed the withdrawal and may therefore name it.
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
        test-generic-fixpoint-antitone-step-is-refused-naming-the-withdrawn-edge = {
          expr = genGraph.fixpoint {
            seed = {
              a = [ "x" ];
            };
            step = antitoneStep;
            maxIter = 7;
          };
          expectedError = {
            type = "ThrownError";
            msg = notAscending [ "a → x" ];
          };
        };
        # ★ AND IT FIRES AT THE FIRST NON-ASCENDING STEP, NOT AT THE CAP AND NOT ON EVERY STEP.
        # The cell above admits one withdrawal at round 0, where the guard has nothing to be
        # eager about; this one ascends for three rounds first and is size-preserving across the
        # withdrawal, so the round the guard names is the one piece of evidence that the
        # admitted rounds really were admitted. `maxIter` is the shipped default: reaching the
        # cap here would take 1,000 rounds and a different message.
        test-generic-fixpoint-refuses-at-the-first-non-ascending-step = {
          expr = genGraph.fixpoint {
            seed = {
              a = [ "e0" ];
            };
            step = ascendThenWithdrawStep;
          };
          expectedError = {
            type = "ThrownError";
            msg = notAscending [ "a → e0" ];
          };
        };
        # The other cause, same binding, same message form: a MONOTONE step under its cap —
        # the closure's own construction, driven through the generic surface where the binding
        # cannot know that is what it is holding. The pair is the reason (ii) may not name a
        # cause, and it is asserted rather than argued.
        #
        # ★ THE SECOND HALF OF THE PAIR IS THE CELL BELOW IT, NOT THE ANTITONE ONE ANY MORE.
        # The antitone step is now refused before the cap, so without a second construction that
        # genuinely reaches it this comment would be arguing the pair instead of exhibiting it.
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
        # The pair's second half: INFLATIONARY BUT NOT MONOTONE, so the subset guard passes it
        # (nothing is ever withdrawn) and it reaches the cap on its own account rather than by
        # being a monotone step in disguise. Byte-identical message to the cell above — which is
        # the assertion: two unrelated constructions, one cause-free text.
        test-generic-fixpoint-inflationary-non-monotone-under-cap-names-no-cause = {
          expr = genGraph.fixpoint {
            seed = {
              a = [ "x" ];
            };
            step = inflationaryNonMonotoneStep;
            maxIter = 5;
          };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph: fixpoint exceeded 5 iterations: the step neither converged nor shrank\\. `step` is the caller's, so this binding reports what it observed and names no cause\\.$";
          };
        };
        # ★ THE CEILING THE SUBSET GUARD ADDS, ASSERTED AS A LOSS. `differenceEdges` keys an
        # attrset by the target list's ELEMENTS, so `fixpoint`'s accumulator is now attrset of
        # lists of STRINGS where the cardinality test was total over attrsets of lists. At HEAD
        # this fixture got a NAMED gen-graph refusal; it now gets Nix's own type error, which
        # names neither this library nor `step`. A door was rejected on price (a second O(E) pass
        # on the happy path, for a domain `materialize`/`unionEdges`/`compose` cannot produce),
        # so the loss is instrumented instead — the day `fixpoint` regains a named refusal over
        # this domain, this cell reds and says so. The `msg` is UNANCHORED on purpose: the text
        # is Nix's, not this library's, and anchoring would pin a message gen-graph does not own.
        test-generic-fixpoint-non-string-edge-target-is-not-refused-by-name = {
          expr = genGraph.fixpoint {
            seed = {
              a = [
                1
                2
              ];
            };
            step = cur: { a = cur.a ++ [ 3 ]; };
            maxIter = 5;
          };
          expectedError = {
            type = "TypeError";
            msg = "expected a string but found an integer";
          };
        };
        # LIVE CONTROL on the claim the cause-free message makes: the step "never shrank" is an
        # observation, not a tautology — a step that DOES shrink is refused by the subset guard,
        # by its own name, before the cap is reached. ★ A SHRINK IS SUBSUMED rather than tested
        # separately: `current ⊆ next` implies `|current| ≤ |next|`, so this fixture is caught by
        # the same predicate that catches the size-preserving withdrawal above, and it is caught
        # with a better answer — `a → y` names the edge where `(2 → 1)` named an arithmetic
        # difference the caller then had to locate.
        test-generic-fixpoint-shrinking-step-is-refused-by-the-subset-guard = {
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
            msg = notAscending [ "a → y" ];
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

    # ── THE SEEDED FIXPOINT REFUSES BY NAMING THE CONCLUSIONS, NOT ONLY BY NAMING A CAUSE ──
    #
    # Unlike the cap, this refusal HAS observed its cause — it re-derived from the converged
    # accumulator and the caller's own rules did not produce these facts — so it is entitled
    # to name one, and the shipped message does (`step` must be monotone in both arguments).
    # What these cells assert is the part a cause cannot supply: a refusal that said ONLY
    # "not monotone" would leave the caller to find which of its conclusions the converged
    # graph withdrew, on an accumulation the library already has in hand.
    flake.testsError.seeded-support-refusal = {
      test-seeded-refusal-names-the-unsupported-conclusion = {
        expr = genGraph.seededFixpoint {
          seed = {
            root = [ "a" ];
          };
          frontier = {
            root = [ "a" ];
          };
          step = _dF: acc: if builtins.elem "y" (acc.root or [ ]) then { } else { root = [ "y" ]; };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-graph: seededFixpoint: the result holds 1 conclusion\\(s\\) the converged accumulator does not support: root → y\\. Re-deriving from the converged accumulator does not produce them, so they were drawn while a fact was absent and union-accumulation never retracted them\\. `step` must be monotone in both arguments\\.$";
        };
      };
      # The count and the enumeration are asserted together, on a rule withdrawing TWO
      # conclusions: a message that named one of them, or that ordered them by evaluation
      # accident, fails here and passes the cell above.
      test-seeded-refusal-enumerates-every-unsupported-conclusion = {
        expr = genGraph.seededFixpoint {
          seed = {
            root = [ "a" ];
          };
          frontier = {
            root = [ "a" ];
          };
          step =
            _dF: acc:
            if builtins.elem "y" (acc.root or [ ]) then
              { }
            else
              {
                root = [ "y" ];
                extra = [ "z" ];
              };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-graph: seededFixpoint: the result holds 2 conclusion\\(s\\) the converged accumulator does not support: extra → z, root → y\\..*";
        };
      };
      # LIVE CONTROL, same run, same binding: a monotone step deriving new facts returns
      # them. Without it the two cells above are consistent with a binding that refuses
      # every seeded run.
      test-seeded-support-check-monotone-control = {
        expr =
          let
            mat = genGraph.materialize fork;
            sn = genGraph.seededFixpoint {
              seed = mat;
              frontier = mat;
              step = dF: _: genGraph.compose dF mat;
            };
            tc = genGraph.transitiveClosure fork;
            sorted = m: n: builtins.sort builtins.lessThan (m.${n} or [ ]);
          in
          builtins.all (n: sorted sn n == sorted tc n) fork.nodes;
        expected = true;
      };
    };

    # ── THE DEPTH-CAP REFUSALS NAME THE SURFACE THE CALLER CALLED ──
    #
    # `preorder.nix`'s guard lives in ONE place — the shared `foldPreorder.go` — and
    # `traverse.nix`'s in `pathsBetween`'s own `dfs`. That the guard FIRES, and that it fires
    # catchably where the old construction aborted uncatchably, is a boolean asserted beside
    # each surface's other halves in `ci/tests/{preorder,traverse}.nix`. What only this
    # output can assert is the ADR-0009 amendment's actual demand: that the refusal names a
    # surface BY NAME — and, for the shared core, that it names the caller rather than
    # itself. Three specializations abort identically otherwise, and a caller handed one is
    # sent back to bisect its own fixture.
    #
    # Anchored at the front and through the cap, for the reason the closure refusals are: an
    # unanchored pattern goes green on a message that has grown a cause it cannot support.
    flake.testsError.depth-refusal =
      let
        chain =
          n:
          let
            key = i: "n" + pad i;
            m = builtins.listToAttrs (
              map (i: {
                name = key i;
                value = if i == 0 then [ ] else [ (key (i - 1)) ];
              }) (builtins.genList (i: i) n)
            );
          in
          {
            top = key (n - 1);
            bottom = key 0;
            edges = k: m.${k} or [ ];
          };
        # `c9` is one node past the cap of 8 and refuses; `c8` sits exactly on it and
        # returns. `pathsBetween`'s boundary is one node further out, its terminating check
        # being consulted before the guard, so `c10` is what refuses there.
        c8 = chain 8;
        c9 = chain 9;
        c10 = chain 10;
        c = c9;

        # `ancestorsOf` walks a `parent` accessor, not `edges` — same numbering, reversed
        # into a single-parent function. `ancestorsChain n`'s `top` has `n - 1` ancestors.
        ancestorsChain =
          n:
          let
            key = i: "n" + pad i;
            m = builtins.listToAttrs (
              map (i: {
                name = key i;
                value = if i == 0 then null else key (i - 1);
              }) (builtins.genList (i: i) n)
            );
          in
          {
            top = key (n - 1);
            parent = k: m.${k} or null;
          };
        # 8 ancestors sits exactly on the cap of 8 and returns; 9 (one more node) refuses —
        # unlike `pathsBetween`, `ancestorsOf` has no terminating check exempting one extra
        # frame, so the boundary is `maxDepth` ancestors exactly, not `maxDepth + 1`.
        ac9 = ancestorsChain 9;
        ac10 = ancestorsChain 10;
      in
      {
        test-expandpreorder-refusal-names-the-surface = {
          expr =
            (genGraph.expandPreorder {
              roots = [ c.top ];
              key = f: f;
              inherit (c) edges;
              maxDepth = 8;
            }).nodes;
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.expandPreorder: DFS depth exceeded the stated cap of 8\\..*";
          };
        };
        # The other specialization of the same core. Two surfaces, two names, one guard: this
        # is what a message hard-coding `foldPreorder` at the throw site fails.
        test-foldreach-refusal-names-the-surface = {
          expr =
            (genGraph.foldReach {
              roots = [ c.top ];
              edges = t: c.edges t;
              target = e: e;
              project = e: [ e ];
              itemKey = i: i;
              maxDepth = 8;
            }).nodes;
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.foldReach: DFS depth exceeded the stated cap of 8\\..*";
          };
        };
        # ★ AND THE NAME IS READ OFF THE CALLER, not chosen from a fixed set of three. A
        # specialization written OUTSIDE this library (den-hoag's `forwardExpand` is one) names
        # itself the same way, which is why `surface` carries no membership assertion — the
        # contrast with `fixpoint.closureOf`, whose class really is closed. Without this cell
        # the two above are consistent with a `surface` the core ignores for anything but its
        # own two callers.
        test-foldpreorder-refusal-names-a-caller-outside-this-library = {
          expr = genGraph.foldPreorder {
            roots = [ c.top ];
            key = f: f;
            acc = 0;
            expand = acc: frame: {
              acc = acc + 1;
              children = c.edges frame;
            };
            maxDepth = 8;
            surface = "forwardExpand";
          };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.forwardExpand: DFS depth exceeded the stated cap of 8\\..*";
          };
        };
        # `traverse.nix`'s own core. Same law, same shape, a separate recursion and a separate
        # cap — its frames cost ≈4 per link against `foldPreorder`'s ≈2, so one number could
        # not have served both.
        test-pathsbetween-refusal-names-the-surface = {
          expr = genGraph.pathsBetween {
            inherit (c10) edges;
            maxDepth = 8;
          } c10.top c10.bottom;
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.pathsBetween: path depth exceeded the stated cap of 8\\..*";
          };
        };
        # A fourth self-recursive core, its own recursion (`ancestorsOf.go`), its own cap.
        # ★ Frame cost ≈1 per link — no fork over children, no fold accumulator — so it is
        # the tightest of the four (measured boundary 9,988, against 4,993 for the shared
        # preorder core and 2,497 for `pathsBetween`); one number could not have served all.
        test-ancestorsof-refusal-names-the-surface = {
          expr = genGraph.ancestorsOf {
            inherit (ac10) parent;
            maxDepth = 8;
          } ac10.top;
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.ancestorsOf: ancestor chain depth exceeded the stated cap of 8\\..*";
          };
        };
        # LIVE CONTROL, same run, same accessors: under the cap all three cores return.
        # Without it every cell above is consistent with a guard that refuses at any depth,
        # which is the failure mode a refusal-only output cannot otherwise see.
        test-depth-refusal-under-the-cap-control = {
          expr = {
            preorder =
              builtins.length
                (genGraph.expandPreorder {
                  roots = [ c8.top ];
                  key = f: f;
                  inherit (c8) edges;
                  maxDepth = 8;
                }).nodes;
            paths = builtins.length (
              builtins.head (
                genGraph.pathsBetween {
                  inherit (c9) edges;
                  maxDepth = 8;
                } c9.top c9.bottom
              )
            );
            ancestors = builtins.length (
              genGraph.ancestorsOf {
                inherit (ac9) parent;
                maxDepth = 8;
              } ac9.top
            );
          };
          expected = {
            preorder = 8;
            paths = 9;
            ancestors = 8;
          };
        };
      };
    # den-hoag-u9k7j: the key projection is GUARDED. `unsafeDiscardStringContext` coerces, so an
    # unguarded key would admit a forged `outPath` set as the node "b" silently. It must keep the
    # TypeError it met before the projection existed.
    flake.testsError.context-node-names = {
      test-a-forged-endpoint-is-not-coerced-into-a-node = {
        expr =
          (genGraph.mkGraph {
            edges = [
              {
                from = "a";
                to = {
                  outPath = "b";
                };
              }
            ];
          }).nodes;
        expectedError = {
          type = "TypeError";
          msg = "expected a string but found a set.*";
        };
      };
    };

    # den-hoag-vq94z: a labeled graph's `labeledEdges` result is refused BY NAME where a surface
    # reads it. Where these cells assert a message, the unguarded read met interpreter text
    # (`expected a set but found a string`, `attribute 'label' missing`, …) or no error at all.
    # Catchability across every mode and surface is `ci/tests/labeled-door.nix`; these pin WHICH
    # refusal, anchored, because a refusal naming the wrong surface or field is the defect.
    flake.testsError.labeled-door =
      let
        inherit (genGraph)
          boundedBy
          forgetLabels
          labeledTranspose
          query
          queryArrivals
          regex
          ;
        x = regex.star (regex.lit "x");
        on = es: {
          nodes = [
            "a"
            "b"
          ];
          labeledEdges = id: if id == "a" then es else [ ];
        };
        walk =
          graph:
          query {
            inherit graph;
            from = "a";
            follow = x;
          };
        refusal = surface: tail: "^gen-graph\\.${surface}: labeledEdges \"a\" returned ${tail}$";
        labelTail = "an edge whose label is of type int; a label is a letter of the query alphabet, a string";
        datumTail = "an edge whose target is of type set; a target is a node id, a string";
        datum = on [
          {
            label = "x";
            target = "b";
          }
          {
            label = "r";
            target = {
              x = 1;
            };
          }
        ];
      in
      {
        test-a-result-that-is-not-a-list-is-refused-by-name = {
          expr = walk (on {
            label = "x";
            target = "b";
          });
          expectedError = {
            type = "ThrownError";
            msg = refusal "query" "a set, not a list of \\{ label; target; \\}";
          };
        };
        test-an-element-that-is-not-an-edge-is-refused-by-name = {
          expr = walk (on [ "b" ]);
          expectedError = {
            type = "ThrownError";
            msg = refusal "query" "an element of type string, not an edge \\{ label; target; \\}";
          };
        };
        test-an-edge-with-no-label-is-refused-by-name = {
          expr = walk (on [ { target = "b"; } ]);
          expectedError = {
            type = "ThrownError";
            msg = refusal "query" "an edge with no label";
          };
        };
        test-an-edge-with-no-target-is-refused-by-name = {
          expr = walk (on [ { label = "x"; } ]);
          expectedError = {
            type = "ThrownError";
            msg = refusal "query" "an edge with no target";
          };
        };
        test-a-non-string-label-is-refused-by-name = {
          expr = walk (on [
            {
              label = 1;
              target = "b";
            }
          ]);
          expectedError = {
            type = "ThrownError";
            msg = refusal "query" labelTail;
          };
        };
        test-a-non-string-target-is-refused-by-name-in-queryArrivals = {
          expr = queryArrivals {
            graph = on [
              {
                label = "x";
                target = {
                  n = "b";
                };
              }
            ];
            from = "a";
            follow = x;
            advance = s: s.distance + 1;
          };
          expectedError = {
            type = "ThrownError";
            msg = refusal "queryArrivals" "an edge whose target is of type set; a target is a node id, a string";
          };
        };
        # The refusal names the surface that APPLIED the accessor, not the one that first forced
        # the element: here `query` forces a label `boundedBy` read.
        test-a-bounded-graph-refuses-as-boundedBy = {
          expr = walk (
            boundedBy
              (on [
                {
                  label = 1;
                  target = "b";
                }
              ])
              (_: [
                {
                  name = "m";
                  admits = _: true;
                }
              ])
          );
          expectedError = {
            type = "ThrownError";
            msg = refusal "boundedBy" labelTail;
          };
        };
        # A surface that reads every target at a node refuses the datum a walk leaves unread.
        # At base both aborted uncatchably (`expected a string but found a set`).
        test-labeledTranspose-refuses-a-datum-target-by-name = {
          expr = (labeledTranspose datum).labeledEdges "b";
          expectedError = {
            type = "ThrownError";
            msg = refusal "labeledTranspose" datumTail;
          };
        };
        test-forgetLabels-refuses-a-datum-target-by-name = {
          expr = (forgetLabels datum).edges "a";
          expectedError = {
            type = "ThrownError";
            msg = refusal "forgetLabels" datumTail;
          };
        };
        # A non-string id is rendered by its type: coercing it into the message would abort
        # in the act of refusing.
        test-a-refusal-renders-a-non-string-id-by-type = {
          expr =
            (forgetLabels {
              nodes = [ ];
              labeledEdges = _: "b";
            }).edges
              { f = _: 1; };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.forgetLabels: labeledEdges <a set> returned a string, not a list of \\{ label; target; \\}$";
          };
        };

        # ── THE ACCESSOR ITSELF (den-hoag-g8lo's table: a door or a falsifier per input) ──
        test-an-accessor-that-is-not-a-function-is-refused-by-name = {
          expr = walk {
            nodes = [ "a" ];
            labeledEdges = [ ];
          };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.query: the graph's labeledEdges is a list, not a function from a node id to a list of \\{ label; target; \\}$";
          };
        };
        test-an-absent-accessor-is-refused-by-name-where-no-formal-requires-it = {
          expr = walk { nodes = [ "a" ]; };
          expectedError = {
            type = "ThrownError";
            msg = "^gen-graph\\.query: the graph's labeledEdges is absent, not a function from a node id to a list of \\{ label; target; \\}$";
          };
        };
        # FALSIFIER, not a door: a pattern formal is a function, and what a function does with a
        # node id is not decidable before applying it. This pins the interpreter's abort — UNANCHORED,
        # because the text is Nix's — so the day a door covers this input, the cell reds and says so.
        test-a-pattern-formal-accessor-still-aborts-on-a-node-id = {
          expr = walk {
            nodes = [ "a" ];
            labeledEdges = { x }: [ x ];
          };
          expectedError = {
            type = "TypeError";
            msg = "expected a set but found a string";
          };
        };
        # ABSENCE IS A DECISION (`lib/query.nix`, THE LABELED CONTRACT IS TOTAL): at the two
        # surfaces taking the record by pattern, `labeledEdges` stays a required formal, so its
        # omission reports itself at the call rather than answering from `nodes` alone.
        test-forgetLabels-keeps-labeledEdges-a-required-formal = {
          expr = (forgetLabels { nodes = [ "a" ]; }).nodes;
          expectedError = {
            type = "TypeError";
            msg = "called without required argument 'labeledEdges'";
          };
        };
        test-labeledTranspose-keeps-labeledEdges-a-required-formal = {
          expr = (labeledTranspose { nodes = [ "a" ]; }).nodes;
          expectedError = {
            type = "TypeError";
            msg = "called without required argument 'labeledEdges'";
          };
        };
      };

    # den-hoag-pqp4z: every other caller function's RESULT is refused by name where it is read,
    # and a caller function that is not callable is refused at its surface's door. Catchability
    # across every mode is `ci/tests/caller-results.nix`; these pin WHICH refusal, anchored.
    flake.testsError.caller-results =
      let
        inherit (genGraph)
          boundedBy
          cyclicEdgesWhere
          query
          queryArrivals
          regex
          ;
        x = regex.star (regex.lit "x");
        graph = {
          nodes = [
            "a"
            "b"
          ];
          labeledEdges =
            id:
            if id == "a" then
              [
                {
                  label = "x";
                  target = "b";
                }
              ]
            else
              [ ];
        };
        q =
          extra:
          query (
            {
              inherit graph;
              from = "a";
              follow = x;
            }
            // extra
          );
        bounded = marks: (boundedBy graph (_: marks)).withheld "a";
        refusal = surface: tail: {
          type = "ThrownError";
          msg = "^gen-graph\\.${surface}: ${tail}$";
        };
      in
      {
        test-a-non-bool-where-is-refused-by-name = {
          expr = q { where = _: 1; };
          expectedError = refusal "query" "where \"a\" returned a int, not a bool";
        };
        test-a-non-function-where-is-refused-by-name = {
          expr = q { where = 1; };
          expectedError = refusal "query" "where is a int, not a function returning a bool";
        };
        # a set whose `__functor` is not a function is not callable (gen-view's `callable`)
        test-a-non-function-functor-where-is-refused-by-name = {
          expr = q {
            where = {
              __functor = 1;
            };
          };
          expectedError = refusal "query" "where is a set, not a function returning a bool";
        };
        test-a-non-function-functor-labeledEdges-is-refused-by-name = {
          expr = q {
            graph = graph // {
              labeledEdges = {
                __functor = 1;
              };
            };
          };
          expectedError = refusal "query" "the graph's labeledEdges is a set, not a function from a node id to a list of \\{ label; target; \\}";
        };
        test-a-non-int-advance-is-refused-by-name-where-the-distance-is-read = {
          expr = map (a: a.distance) (queryArrivals {
            inherit graph;
            from = "a";
            follow = x;
            advance = _: "far";
          });
          expectedError = refusal "queryArrivals" "advance on the step \"a\" -x-> \"b\" returned a string, not an int, the distance after the step";
        };
        test-a-non-string-groupBy-is-refused-by-name = {
          expr = q {
            mode = "visible";
            groupBy = _: 1;
          };
          expectedError = refusal "queryVisible" "groupBy on the answer at \"a\" returned a int, not a string, the answer's competition key";
        };
        test-a-non-list-marksOf-is-refused-by-name = {
          expr = (boundedBy graph (_: 1)).labeledEdges "a";
          expectedError = refusal "boundedBy" "marksOf \"a\" returned a int, not a list of marks \\{ name; admits; \\}";
        };
        test-a-non-mark-is-refused-by-name = {
          expr = bounded [ 1 ];
          expectedError = refusal "boundedBy" "marksOf \"a\" returned a int, not a mark \\{ name; admits; \\}";
        };
        test-a-mark-with-no-admits-is-refused-by-name = {
          expr = bounded [ { name = "m"; } ];
          expectedError = refusal "boundedBy" "marksOf \"a\" returned a mark with no admits, not a mark \\{ name; admits; \\}";
        };
        test-a-non-function-admits-is-refused-by-name = {
          expr = bounded [
            {
              name = "m";
              admits = 1;
            }
          ];
          expectedError = refusal "boundedBy" "a mark's admits is a int, not a function returning a bool";
        };
        test-a-non-bool-admits-is-refused-by-name = {
          expr = bounded [
            {
              name = "m";
              admits = _: 1;
            }
          ];
          expectedError = refusal "boundedBy" "a mark's admits on the label \"x\" returned a int, not a bool";
        };
        test-a-mark-with-no-name-is-refused-by-name = {
          expr = bounded [ { admits = _: false; } ];
          expectedError = refusal "boundedBy" "marksOf \"a\" returned a mark with no name; `withheld` reports a mark by its name";
        };
        test-a-non-bool-p-is-refused-by-name = {
          expr = cyclicEdgesWhere graph (_: 1);
          expectedError = refusal "cyclicEdgesWhere" "p on the label \"x\" returned a int, not a bool";
        };
        # FALSIFIER, not a door: a pattern formal is a function, and what it does with a node id is
        # not decidable before applying it. UNANCHORED, because the text is Nix's — the day a door
        # covers this input, the cell reds and says so.
        test-a-pattern-formal-where-still-aborts-on-a-node-id = {
          expr = q { where = { x }: true; };
          expectedError = {
            type = "TypeError";
            msg = "expected a set but found a string";
          };
        };
      };

    # THE IDENTIFIER DOORS (den-hoag-bkdkg, ADR-0025 item 1): a node VALUE where a door takes a node
    # id is refused under THAT door's name. A door whose body keys the id says "a string"; a door
    # whose body only hands it to the accessor and `genericClosure` keeps every scalar and says so.
    # What the refusal must not change, and its catchability, are `tests/identifier-doors.nix`.
    flake.testsError.identifier-refusal =
      let
        es = {
          a = [ "b" ];
          b = [ ];
        };
        g = {
          edges = id: es.${id} or [ ];
          nodes = [
            "a"
            "b"
          ];
          parent = id: if id == "b" then "a" else null;
        };
        X = {
          name = "a";
        };
        qa = from: {
          graph = genGraph.labeledFrom {
            inherit (g) nodes;
            perLabel.l = g.edges;
          };
          inherit from;
          follow = genGraph.regex.parse "l*";
        };
        str = who: "^gen-graph\\.${who}: got set, expected a node identifier \\(a string\\)$";
        scalar =
          who: "^gen-graph\\.${who}: got set, expected a node identifier \\(a string or another scalar\\)$";
        cell = msg: expr: {
          inherit expr;
          expectedError = {
            type = "ThrownError";
            inherit msg;
          };
        };
      in
      {
        test-reachableFrom = cell (scalar "reachableFrom") (genGraph.reachableFrom g X);
        test-reachableWhere = cell (scalar "reachableWhere") (genGraph.reachableWhere g X (_: true));
        test-canReach-from = cell (scalar "canReach") (genGraph.canReach g X "b");
        test-canReach-to = cell (scalar "canReach") (genGraph.canReach g "a" X);
        test-selfReachable = cell (scalar "selfReachable") (genGraph.selfReachable g X);
        test-ancestorsOf = cell (str "ancestorsOf") (genGraph.ancestorsOf g X);
        test-pathsBetween = cell (str "pathsBetween") (genGraph.pathsBetween g X "b");
        test-dependents = cell (str "dependents") (genGraph.dependents g X);
        test-dependentsOf = cell (str "dependentsOf") (genGraph.dependentsOf g X);
        test-dependentsFrontier = cell (str "dependentsFrontier") (
          genGraph.dependentsFrontier g X (_: false)
        );
        test-impactOf = cell (str "impactOf") (genGraph.impactOf g X);
        test-directDependentsOf = cell (str "directDependentsOf") (genGraph.directDependentsOf g X);
        test-coScc = cell (scalar "coScc") (genGraph.coScc g X "b");
        test-reachableVia = cell (scalar "reachableVia") (genGraph.reachableVia (genGraph.hoistEdges g) X);
        test-selfReachableVia = cell (scalar "selfReachableVia") (
          genGraph.selfReachableVia (genGraph.hoistEdges g) X
        );
        test-query = cell (scalar "query") (genGraph.query (qa X));
        test-queryArrivals = cell (scalar "queryArrivals") (
          genGraph.queryArrivals (qa X // { advance = _: 1; })
        );
      };

    # THE LOWLINK ARM'S DOMAIN IS A CLOSED ACCESSOR (ADR-0025 item 1). A target outside `nodes` is
    # refused by name, and so is a `nodes` entry that is not a string; each refusal is catchable.
    # `cyclicEdgesWhere` and `cyclePaths` bind the arm, so they refuse under its name. On `offNode`
    # both aborted uncatchably (`attribute 'x' missing`) before they bound it; on `offUnrelated`,
    # where the off-node target sits on no cycle, they ANSWERED before, and refusing is the
    # narrowed domain (README, *The partition routing contract*). `cycles` keeps the open
    # convention and still answers there.
    flake.testsError.lowlink-domain =
      let
        mk = m: {
          nodes = builtins.attrNames m;
          edges = id: m.${id} or [ ];
        };
        lab = g: {
          inherit (g) nodes;
          labeledEdges =
            id:
            map (x: {
              label = "${id}>${x}";
              target = x;
            }) (g.edges id);
        };
        # a -> x -> b -> a, x outside `nodes`: the off-node target is ON the cycle
        offNode = {
          nodes = [
            "a"
            "b"
          ];
          edges =
            id:
            {
              a = [ "x" ];
              x = [ "b" ];
              b = [ "a" ];
            }
            .${id};
        };
        # a <-> b, c -> x, x outside `nodes`: the off-node target is on no cycle and no p-edge
        offUnrelated = mk {
          a = [ "b" ];
          b = [ "a" ];
          c = [ "x" ];
        };
        outside = from: "^gen-graph\\.lowlink: edges \"${from}\" names a target outside `nodes`$";
        cell = msg: expr: {
          expr = builtins.deepSeq expr expr;
          expectedError = {
            type = "ThrownError";
            inherit msg;
          };
        };
        refused = v: !(builtins.tryEval (builtins.deepSeq v true)).success;
        ab = l: l == "a>b" || l == "b>a";
        nonString = genGraph.lowlink {
          nodes = [ 1 ];
          edges = _: [ ];
        };
      in
      {
        test-lowlink-offNode = cell (outside "a") (genGraph.lowlink offNode).sccOf;
        test-cyclicEdgesWhere-offNode = cell (outside "a") (
          genGraph.cyclicEdgesWhere (lab offNode) (_: true)
        );
        test-cyclePaths-offNode = cell (outside "a") (genGraph.cyclePaths offNode);
        test-lowlink-offUnrelated = cell (outside "c") (genGraph.lowlink offUnrelated).sccOf;
        test-cyclicEdgesWhere-offUnrelated = cell (outside "c") (
          genGraph.cyclicEdgesWhere (lab offUnrelated) ab
        );
        test-cyclePaths-offUnrelated = cell (outside "c") (genGraph.cyclePaths offUnrelated);
        test-lowlink-non-string-node = cell "^gen-graph\\.lowlink: got int, expected a node identifier \\(a string\\)$" nonString.sccOf;
        test-lowlink-refusals-are-catchable = {
          expr = {
            offNode = refused (genGraph.lowlink offNode).sccOf;
            cyclicEdgesWhere-offNode = refused (genGraph.cyclicEdgesWhere (lab offNode) (_: true));
            cyclePaths-offNode = refused (genGraph.cyclePaths offNode);
            offUnrelated = refused (genGraph.lowlink offUnrelated).sccOf;
            cyclicEdgesWhere-offUnrelated = refused (genGraph.cyclicEdgesWhere (lab offUnrelated) ab);
            cyclePaths-offUnrelated = refused (genGraph.cyclePaths offUnrelated);
            non-string-node = refused nonString.sccOf;
          };
          expected = {
            offNode = true;
            cyclicEdgesWhere-offNode = true;
            cyclePaths-offNode = true;
            offUnrelated = true;
            cyclicEdgesWhere-offUnrelated = true;
            cyclePaths-offUnrelated = true;
            non-string-node = true;
          };
        };
        # the open convention `cycles` keeps, on the same fixture the partition surfaces refuse
        test-cycles-answers-offUnrelated = {
          expr = genGraph.cycles offUnrelated;
          expected = [
            "a"
            "b"
          ];
        };
      };

    # den-hoag-0mqv1: a plain accessor's `edges` result is refused by name where it is read. The
    # surfaces pinned here are the ones whose text names themselves under any reading of which name
    # a shared primitive's refusal carries (den-hoag-7gp66); `ci/tests/edges-results.nix` asserts the
    # rest refuse catchably.
    flake.testsError.edges-results =
      let
        good =
          id:
          if id == "a" then
            [ "b" ]
          else if id == "b" then
            [ "c" ]
          else
            [ ];
        bad = id: if id == "b" then 1 else good id;
        nodes = [
          "a"
          "b"
          "c"
        ];
        acc = e: {
          edges = e;
          inherit nodes;
        };
        acyclic = e: if builtins.isFunction e then (id: if id == "a" then [ ] else e id) else e;
        res = who: "^gen-graph\\.${who}: edges \"b\" returned a int, not a list of node ids$";
        nf =
          who:
          "^gen-graph\\.${who}: the accessor's edges is a int, not a function from a node id to a list of node ids$";
        cell = msg: expr: {
          inherit expr;
          expectedError = {
            type = "ThrownError";
            inherit msg;
          };
        };
        # the walk surfaces are started at "b", so the refusal is read at the first application
        surfaces = e: {
          reachableFrom = genGraph.reachableFrom (acc e) "b";
          canReach = genGraph.canReach (acc e) "b" "c";
          selfReachable = genGraph.selfReachable (acc e) "b";
          pathsBetween = genGraph.pathsBetween (acc e) "a" "c";
          dependentsOf = genGraph.dependentsOf (acc e) "c";
          dependentsFrontier = genGraph.dependentsFrontier (acc e) "c" (_: true);
          directDependents = genGraph.directDependents (acc e);
          roots = genGraph.roots (acc e);
          leaves = genGraph.leaves (acc e);
          lowlink = (genGraph.lowlink (acc e)).sccOf;
          condensationOf = genGraph.condensationOf (acc e) {
            a = "a";
            b = "b";
            c = "c";
          };
          topoOrder = genGraph.topoOrder (acc (acyclic e));
          coneRank = genGraph.coneRank (acc (acyclic e)) nodes;
          expandPreorder = genGraph.expandPreorder {
            roots = [ "b" ];
            key = f: f;
            edges = e;
          };
        };
        cells = pin: e: builtins.mapAttrs (who: v: cell (pin who) (builtins.deepSeq v v)) (surfaces e);
      in
      builtins.listToAttrs (
        map (n: {
          name = "test-${n}-result";
          value = (cells res bad).${n};
        }) (builtins.attrNames (surfaces bad))
        ++ map (n: {
          name = "test-${n}-non-function";
          value = (cells nf 1).${n};
        }) (builtins.attrNames (surfaces 1))
      )
      // {
        test-fromRegistry-non-function =
          cell
            "^gen-graph\\.fromRegistry: edges is a int, not a function from a node id and its registry entry to a list of node ids$"
            (
              genGraph.reachableFrom (genGraph.fromRegistry {
                registry = {
                  a = { };
                };
                edges = 1;
              }) "a"
            );
        # FALSIFIERS, not doors: a missing `edges` is the arity class, a pattern-formal `edges` the
        # caller's own destructuring
        test-a-missing-edges-is-an-arity-abort = {
          expr = genGraph.reachableFrom { inherit nodes; } "a";
          expectedError = {
            type = "TypeError";
            msg = "called without required argument 'edges'";
          };
        };
        test-a-pattern-formal-edges-aborts-in-the-callers-destructuring = {
          expr = genGraph.reachableFrom (acc ({ x }: [ ])) "a";
          expectedError = {
            type = "TypeError";
            msg = "expected a set but found a string";
          };
        };
      };
  };
}
