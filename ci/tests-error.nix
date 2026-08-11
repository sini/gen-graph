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
      # LIVE CONTROL, same run: an acyclic cone through the same accessor does not refuse.
      # Without it, the two cells above are consistent with a surface that refuses everything.
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
