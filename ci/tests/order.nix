{ genGraph, ... }:
let
  inherit (genGraph)
    entryAnywhere
    entryAfter
    entryBefore
    entryBetween
    phaseOrder
    ;
in
{
  flake.tests.order = {
    # ── entry* shapes (data-free: dispatch reads only the phase NAME) ──
    test-entry-anywhere-shape = {
      expr = entryAnywhere;
      expected = {
        before = [ ];
        after = [ ];
      };
    };
    test-entry-after-shape = {
      expr = entryAfter [ "a" ];
      expected = {
        before = [ ];
        after = [ "a" ];
      };
    };
    test-entry-before-shape = {
      expr = entryBefore [ "b" ];
      expected = {
        before = [ "b" ];
        after = [ ];
      };
    };
    test-entry-between-shape = {
      expr = entryBetween [ "c" ] [ "a" ];
      expected = {
        before = [ "c" ];
        after = [ "a" ];
      };
    };

    # ── phaseOrder: forward producers-first over the condensation ──
    test-order-linear = {
      expr = phaseOrder {
        a = entryAnywhere;
        b = entryAfter [ "a" ];
        c = entryAfter [ "b" ];
      };
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    test-order-before = {
      expr = phaseOrder {
        a = entryAnywhere;
        b = entryBefore [ "a" ];
      };
      expected = [
        "b"
        "a"
      ];
    };
    test-order-single-phase = {
      expr = phaseOrder { default = entryAnywhere; };
      expected = [ "default" ];
    };
    # diamond (matches the spike's ordering-delegation.nix fixture)
    test-order-diamond = {
      expr = phaseOrder {
        validate = entryAnywhere;
        resolve = entryAfter [ "validate" ];
        emit = entryAfter [ "resolve" ];
        report = entryAfter [
          "resolve"
          "emit"
        ];
      };
      expected = [
        "validate"
        "resolve"
        "emit"
        "report"
      ];
    };

    # ── independent phases: phaseOrder returns A valid topological order, not a
    # specific tie-break permutation. Assert both present (length-2 permutation);
    # any valid order is dispatch-output-equivalent because a phase's effect is
    # threaded into context only AFTER the phase. ──
    test-order-independent-permutation = {
      expr = builtins.sort builtins.lessThan (phaseOrder {
        p = entryAnywhere;
        q = entryAnywhere;
      });
      expected = [
        "p"
        "q"
      ];
    };

    # ── cycle => throw (preserves gen-dispatch dag.nix's throw-on-cycle contract) ──
    test-order-cycle-throws = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq (phaseOrder {
            a = entryAfter [ "b" ];
            b = entryAfter [ "a" ];
          }) true
        )).success;
      expected = false;
    };
    test-order-self-loop-throws = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq (phaseOrder {
            a = entryAfter [ "a" ];
          }) true
        )).success;
      expected = false;
    };
  };
}
