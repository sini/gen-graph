# THE DOORS (den-hoag-7gp66 P1, then P2 — `prelude.door`): every published step taking a record is
# a door, so a missing field, and an unknown one at a closed step, is a throw `tryEval` observes
# rather than Nix's uncatchable arity abort. The message cells live on `testsError` (`door-refusals`,
# `door-naming`); this file holds what an error cell cannot say — that the refusal is catchable,
# that it fires when the STEP is applied (each cell `seq`s the step applied to its argument and
# nothing else: no later argument, no field read), that a record step admits an extra field (R5)
# unless the field is one of its options step's own names (`optionsStep`, G10), that the published
# contract is the row (D3), and that the valid call is unchanged.
{ genGraph, genPrelude, ... }:
let
  F = import ./_fixtures/doors.nix { inherit genGraph; };
  applied = step: r: (builtins.tryEval (builtins.seq (step r) true)).success;
  extra = {
    ${F.unknown} = 1;
  };
  each = f: builtins.mapAttrs (_: f);
  guarded = builtins.filter (n: F.records.${n} ? misplaced) (builtins.attrNames F.records);
  guardedRows = builtins.listToAttrs (
    map (n: {
      name = n;
      value = F.records.${n};
    }) guarded
  );
  flag =
    v: names:
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = v;
      }) names
    );
in
{
  flake.tests.doors = {
    test-the-empty-options-are-admitted-at-every-options-step = {
      expr = each (d: applied d.door { }) F.options;
      expected = each (_: true) F.options;
    };
    # G1/G4: refused when the options are applied, before any operand or record.
    test-an-unknown-option-is-refused-catchably-at-every-options-step = {
      expr = each (d: applied d.door extra) F.options;
      expected = each (_: false) F.options;
    };
    # D3: the contract is published as data, and the functor-aware reader reads the same map.
    test-every-options-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.door.__contract) optional required open;
        functionArgs = genPrelude.functionArgs d.door;
      }) F.options;
      expected = each (d: {
        inherit (d) optional;
        required = [ ];
        open = false;
        functionArgs = flag true d.optional;
      }) F.options;
    };
    test-the-valid-record-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step d.good) F.records;
      expected = each (_: true) F.records;
    };
    # D2
    test-a-missing-field-is-refused-catchably = {
      expr = each (d: applied d.step (builtins.removeAttrs d.good [ d.drop ])) F.records;
      expected = each (_: false) F.records;
    };
    # G2 / R5, and G10-ctl on the guarded rows: a field no step names is admitted.
    test-an-extra-field-is-admitted-at-every-record-step = {
      expr = each (d: applied d.step (d.good // extra)) F.records;
      expected = each (_: true) F.records;
    };
    # G10: an option of the step's own options step, given on the record, is refused by name.
    test-a-misplaced-option-is-refused-at-every-guarded-record-step = {
      expr = each (d: applied d.step (d.good // { ${d.misplaced} = 1; })) guardedRows;
      expected = each (_: false) guardedRows;
    };
    test-every-record-step-publishes-the-row-as-its-contract = {
      expr = each (d: {
        inherit (d.step.__contract) required open;
        functionArgs = genPrelude.functionArgs d.step;
      }) F.records;
      expected = each (d: {
        inherit (d) required;
        open = true;
        functionArgs = flag false d.required;
      }) F.records;
    };
    test-a-door-reaching-a-primitive-refuses-catchably = {
      expr = [
        (each (r: (builtins.tryEval (builtins.deepSeq (r.run F.bad) true)).success) F.reached)
        (each (r: (builtins.tryEval (builtins.deepSeq (r.run F.badTarget) true)).success) F.reachedByTarget)
      ];
      expected = [
        (each (_: false) F.reached)
        (each (_: false) F.reachedByTarget)
      ];
    };
    # The valid call answers as it did before the check: one answer per door family.
    test-the-checked-doors-answer-unchanged = {
      expr = [
        (genGraph.topoOrder { } {
          nodes = [
            "a"
            "b"
          ];
          edges = id: { a = [ "b" ]; }.${id} or [ ];
        })
        (
          (genGraph.mkGraph {
            edges = [
              {
                from = "a";
                to = "b";
              }
            ];
          }).edges
            "a"
        )
        (genGraph.fixpoint { } (_: { a = [ "b" ]; }) { })
        ((genGraph.mkNodeRef (_: true)) "a").id
      ];
      expected = [
        {
          ok = true;
          order = [
            "b"
            "a"
          ];
        }
        [ "b" ]
        { a = [ "b" ]; }
        "a"
      ];
    };
  };
}
